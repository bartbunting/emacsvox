;;; tts-preparation-tests.el --- Cancellable preparation contracts -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Exercise cancellation and real pending quits with isolated process fixtures.
;;; Code:
(require 'tts-dispatch-handoff-tests)
(require 'omnivox-choice-playback-tests)

(defun tts-preparation-test--empty (process)
  "Check that PROCESS retains no preparation or dispatch reservations."
  (should (= 0 (or (process-get process 'tts--dispatch-owner-count) 0)))
  (should (= 0 (or (process-get process 'tts--dispatch-metadata-bytes) 0)))
  (maphash (lambda (scope _) (should-not (eq process (tts--preparation-process scope)))) tts--preparations)
  (maphash (lambda (_ owner) (should-not (eq process (tts--dispatch-owner-process owner)))) tts--prepared-owners)
  (maphash (lambda (_ entry) (should-not (eq process (tts--marker-dispatch-process entry)))) tts--marker-dispatches))

(ert-deftest tts-preparation-stop-at-projection-framing-and-admission ()
  (dolist (version '(3 4))
    (dolist (stage '(emacsvox-aural--build-structured-timeline
                     emacsvox-aural--frame-structured-timeline
                     tts--dispatch-check-admission))
      (omnivox-choice-playback-test--with-runtime
       (process-put speaker emacsvox-aural--structured-timeline-process-property version)
       (let ((original (symbol-function stage)) injected writes effects callbacks
             (emacsvox-aural-last-delivery-failure nil))
         (cl-letf (((symbol-function stage)
                    (lambda (&rest arguments)
                      (unless injected (setq injected t) (tts-stop t))
                      (apply original arguments)))
                   ((symbol-function 'process-send-string)
                    (lambda (_ command) (push command writes))))
           (should-not (omnivox-choice-playback-test--submit
                        #'ignore (lambda (&rest _) (push t callbacks))
                        (lambda () (push t effects)))))
         (should injected)
         (should (cl-every (lambda (command) (equal command "s\n")) writes))
         (should-not effects)
         (should-not callbacks)
         (should-not emacsvox-aural-last-delivery-failure)
         (tts-preparation-test--empty speaker))))))

(ert-deftest tts-preparation-own-stop-and-nested-stop-hook-contract ()
  (dolist (version '(3 4))
    (dolist (action '(none write-stop hook-stop ordered urgent))
      (omnivox-choice-playback-test--with-runtime
       (process-put speaker emacsvox-aural--structured-timeline-process-property version)
       (let* ((emacsvox-aural-submission-controls-interruption t)
              (emacsvox-aural-submission-delivery-policy 'urgent)
              entered nested result commands
              (tts-stopped-hook
               (list (lambda (_)
                       (when (and (memq action '(hook-stop ordered urgent)) (not entered))
                         (setq entered t)
                         (if (eq action 'hook-stop) (tts-stop t)
                           (let ((emacsvox-aural-submission-controls-interruption (eq action 'urgent))
                                 (emacsvox-aural-submission-delivery-policy action))
                             (setq nested (omnivox-choice-playback-test--submit)))))))))
         (cl-letf (((symbol-function 'process-send-string)
                    (lambda (_ command)
                      (push command commands)
                      (when (and (eq action 'write-stop) (equal command "s\n") (not entered))
                        (setq entered t) (tts-stop t)))))
           (setq result (omnivox-choice-playback-test--submit)))
         (should (equal result (and (memq action '(none ordered)) 1)))
         (should (equal nested (and (memq action '(ordered urgent)) 2)))
         (should (= (+ (if result 1 0) (if nested 1 0))
                    (cl-count-if (lambda (command) (string-prefix-p "emacsvox_timeline " command)) commands)))
         (tts--cancel-process-tracked-dispatches speaker 'cancelled)
         (tts-preparation-test--empty speaker))))))

(ert-deftest tts-preparation-legacy-direct-and-captured-cancel-before-command ()
  (dolist (kind '(tracked marked))
    (dolist (captured '(nil t))
      (tts-handoff-test--with-process
       (let ((original (symbol-function 'tts--dispatch-command)) commands callbacks)
         (cl-letf (((symbol-function 'process-send-string) (lambda (_ command) (push command commands)))
                   ((symbol-function 'tts--dispatch-command)
                    (lambda (owner command) (tts-stop) (funcall original owner command))))
           (cl-labels ((submit ()
                         (let ((callback (lambda (&rest _) (push t callbacks))))
                           (if (eq kind 'tracked) (tts--protocol-dispatch-tracked callback)
                             (tts--protocol-dispatch-marked #'ignore callback)))))
             (should-not (if captured
                             (emacsvox-aural-call-with-delivery-transaction process #'submit)
                           (submit)))))
         (should (equal commands '("s\n")))
         (should-not callbacks)
         (tts-preparation-test--empty process))))))

(ert-deftest tts-preparation-forgetting-one-owner-discards-unsent-atomic-packet ()
  (tts-handoff-test--with-process
   (let (commands)
     (cl-letf (((symbol-function 'process-send-string) (lambda (_ command) (push command commands))))
       (should (= 1 (tts--protocol-dispatch-tracked #'ignore)))
       (setq commands nil)
       (should-not
        (emacsvox-aural-call-with-delivery-transaction
         process (lambda ()
                   (let ((first (tts--protocol-dispatch-tracked #'ignore))
                         (second (tts--protocol-dispatch-tracked #'ignore)))
                     (tts-cancel-tracked-dispatch first)
                     second)))))
     (should-not commands)
     (should (tts--dispatch-owner-for process 1))
     (should (= 1 (process-get process 'tts--dispatch-owner-count)))
     (tts-cancel-tracked-dispatch 1)
     (tts-preparation-test--empty process))))

(ert-deftest tts-preparation-main-stop-preserves-prepared-notification ()
  (omnivox-choice-playback-test--with-runtime
   (let (commands result)
     (cl-letf (((symbol-function 'process-send-string) (lambda (process command) (push (cons process command) commands))))
       (let ((tts-speaker-process notification))
         (setq result
               (tts--call-with-preparation
                notification (lambda ()
                               (let ((owner (tts--dispatch-new-owner nil #'ignore nil)))
                                 (let ((tts-speaker-process speaker)) (tts-stop))
                                 (tts--dispatch-command owner "emacsvox_tracked_dispatch 1\n")))))))
     (should (= result 1))
     (should (equal commands (list (cons notification "emacsvox_tracked_dispatch 1\n") (cons speaker "s\n"))))
     (tts--cancel-process-tracked-dispatches notification 'cancelled)
     (tts-preparation-test--empty notification))))

(ert-deftest tts-preparation-stop-all-invalidates-both-lanes-before-first-write ()
  (omnivox-choice-playback-test--with-runtime
   (let (notification-scope main-scope writes)
     (cl-letf (((symbol-function 'process-send-string)
                (lambda (_ _command)
                  (should (tts--preparation-cancelled notification-scope))
                  (should (tts--preparation-cancelled main-scope))
                  (push t writes))))
       (should-not
        (tts--call-with-preparation
         notification
         (lambda ()
           (setq notification-scope tts--current-preparation)
           (let ((tts-speaker-process notification)) (tts--dispatch-new-owner nil nil nil))
           (tts--call-with-preparation
            speaker (lambda ()
                      (setq main-scope tts--current-preparation)
                      (tts--dispatch-new-owner nil nil nil)
                      (tts-stop t)))))))
     (should (= 2 (length writes)))
     (tts-preparation-test--empty speaker)
     (tts-preparation-test--empty notification))))

(ert-deftest tts-preparation-reservation-nonlocal-exits-leave-no-charge ()
  (dolist (exit '(quit error throw))
    (dolist (stage '(scope index count bytes))
      (tts-handoff-test--with-process
       (let ((native-comp-enable-subr-trampolines nil)
             (original-put (symbol-function 'process-put))
             (original-hash (symbol-function 'puthash)) injected caught commands)
         (cl-labels ((inject ()
                       (setq injected t)
                       (pcase exit ('quit (setq quit-flag t))
                         ('error (error "reservation fault"))
                         ('throw (throw 'reservation-fault 'thrown)))))
           (cl-letf (((symbol-function 'process-send-string) (lambda (&rest _) (push t commands)))
                     ((symbol-function 'process-put)
                      (lambda (owner property value)
                        (prog1 (funcall original-put owner property value)
                          (when (and (not injected) (eq owner process)
                                     (or (and (eq stage 'count) (eq property 'tts--dispatch-owner-count))
                                         (and (eq stage 'bytes) (eq property 'tts--dispatch-metadata-bytes))))
                            (inject)))))
                     ((symbol-function 'puthash)
                      (lambda (key value table)
                        (prog1 (funcall original-hash key value table)
                          (when (and (not injected)
                                     (or (and (eq stage 'scope) (eq table tts--preparations))
                                         (and (eq stage 'index) (eq table tts--prepared-owners))))
                            (inject))))))
             (setq caught
                   (catch 'reservation-fault
                     (condition-case nil (tts--protocol-dispatch-tracked #'ignore)
                       (quit 'quit) (error 'error))))))
         (should injected)
         (should (eq caught (if (eq exit 'throw) 'thrown exit)))
         (should-not commands)
         (tts-preparation-test--empty process))))))

(ert-deftest tts-preparation-release-failure-still-cleans-peer-owners ()
  (dolist (exit '(quit error throw))
    (tts-handoff-test--with-process
     (let ((native-comp-enable-subr-trampolines nil)
           (original (symbol-function 'process-put)) ready injected caught)
       (cl-letf (((symbol-function 'process-put)
                  (lambda (owner property value)
                    (prog1 (funcall original owner property value)
                      (when (and ready (not injected) (eq owner process)
                                 (eq property 'tts--dispatch-owner-count) (= value 1))
                        (setq injected t)
                        (pcase exit ('quit (setq quit-flag t))
                          ('error (error "release fault")) ('throw (throw 'release-fault 'thrown))))))))
         (setq caught
               (catch 'release-fault
                 (condition-case nil
                     (progn
                       (tts--call-with-preparation process
                         (lambda ()
                           (tts--dispatch-new-owner nil nil nil)
                           (tts--dispatch-new-owner nil nil nil)
                           (setq ready t)))
                       ;; Unwind cleanup itself defers pending quits. Give the
                       ;; caller a quit-checking evaluation point inside this handler.
                       (eval nil))
                   (quit 'quit) (error 'error)))))
       (should injected)
       (should (eq caught (if (eq exit 'throw) 'thrown exit)))
       (tts-preparation-test--empty process)))))

(ert-deftest tts-preparation-ownerless-capture-stop-discards-effects-and-queue ()
  (dolist (policy '(ordered urgent replaceable))
    (tts-handoff-test--with-process
     (let ((emacsvox-aural-submission-delivery-policy policy) commands effects)
       (cl-letf (((symbol-function 'process-send-string) (lambda (_ command) (push command commands))))
         (should-not
          (emacsvox-aural-call-with-delivery-transaction
           process (lambda ()
                     (emacsvox-aural-delivery-send process "q {stale}\nd\n")
                     (emacsvox-aural--defer-delivery-effect (lambda () (push t effects)))
                     (tts-stop)
                     'done))))
       (should (equal commands '("s\n")))
       (should-not effects)
       (should (= 0 (hash-table-count emacsvox-aural--pending-deliveries)))
       (tts-preparation-test--empty process)))))

(ert-deftest tts-preparation-capacity-rejects-before-policy-stop ()
  (tts-handoff-test--with-process
   (let ((tts--preparation-limit 1) writes)
     (cl-letf (((symbol-function 'process-send-string) (lambda (&rest _) (push t writes))))
       (should-error
        (tts--call-with-preparation process (lambda () (tts-handoff-test--submit nil nil)))))
     (should-not writes)
     (tts-preparation-test--empty process))))

(ert-deftest tts-preparation-full-owner-capacity-cleans-up-without-recursion-failure ()
  (tts-handoff-test--with-process
   (tts--call-with-preparation
    process (lambda ()
              (dotimes (_ tts--dispatch-owner-limit) (tts--dispatch-new-owner nil nil nil))
              (should-error (tts--dispatch-new-owner nil nil nil))))
   (tts-preparation-test--empty process)))

(ert-deftest tts-preparation-legacy-automatic-stop-does-not-cancel-own-speech ()
  (dolist (automatic '(nil t))
    (tts-handoff-test--with-process
     (let ((tts-stop-immediately automatic) (tts-quiet nil) commands)
       (cl-letf (((symbol-function 'process-send-string) (lambda (_ command) (push command commands)))
                 ((symbol-function 'tts-voice-reset-code) (lambda () "")))
         (should (integerp (tts--speak "The quick brown fox."))))
       (should (= (if automatic 1 0) (cl-count "s\n" commands :test #'equal)))
       (should (string-match-p "emacsvox_timeline " (car commands)))
       (tts--cancel-process-tracked-dispatches process 'cancelled)
       (tts-preparation-test--empty process)))))

(ert-deftest tts-preparation-pending-handoff-stop-preserves-newer-generation ()
  (dolist (newer '(nil t))
    (tts-handoff-test--with-process
     (let ((emacsvox-aural-submission-delivery-policy 'replaceable)
           (emacsvox-aural-submission-replacement-key 'test)
           (original (symbol-function 'run-with-idle-timer)) injected old-timer)
       (unwind-protect
           (cl-letf (((symbol-function 'process-send-string) #'ignore)
                     ((symbol-function 'run-with-idle-timer)
                      (lambda (&rest arguments)
                        (let ((timer (apply original arguments)))
                          (unless injected
                            (setq injected t old-timer timer)
                            (tts-stop)
                            (when newer
                              (emacsvox-aural--call-independent-callback
                               (lambda ()
                                 (let ((emacsvox-aural-submission-delivery-policy 'replaceable)
                                       (emacsvox-aural-submission-replacement-key 'test))
                                   (emacsvox-aural-call-with-delivery-transaction
                                    process (lambda () (emacsvox-aural-delivery-send process "q {new}\nd\n"))))))))
                          timer))))
             (should-not
              (emacsvox-aural-call-with-delivery-transaction
               process (lambda () (emacsvox-aural-delivery-send process "q {old}\nd\n") 'done)))
             (should-not (memq old-timer timer-idle-list))
             (should (= (if newer 1 0) (hash-table-count emacsvox-aural--pending-deliveries)))
             (when newer
               (let* ((pending (car (hash-table-values emacsvox-aural--pending-deliveries)))
                      (entry (car (emacsvox-aural--pending-delivery-entries pending))))
                 (should (equal (emacsvox-aural--delivery-entry-command entry) "q {new}\nd\n")))))
         (emacsvox-aural-cancel-pending-deliveries process))
       (tts-preparation-test--empty process)))))

(ert-deftest tts-preparation-process-replacement-and-sentinel-during-policy-stop ()
  (dolist (event '(generation sentinel retirement))
    (tts-handoff-test--with-process
     (let ((emacsvox-aural-submission-controls-interruption t)
           (emacsvox-aural-submission-delivery-policy 'urgent) injected writes)
       (cl-letf (((symbol-function 'message) #'ignore)
                 ((symbol-function 'process-send-string)
                  (lambda (_ command)
                    (push command writes)
                    (unless injected
                      (setq injected t)
                      (pcase event
                        ('generation (process-put process 'tts--speech-process-generation 'new))
                        ('sentinel (delete-process process) (tts--speech-process-sentinel process "finished\n"))
                        ('retirement (tts--retire-process process)))))))
         (should-not (tts-handoff-test--submit nil #'ignore)))
       (should (cl-every (lambda (command) (equal command "s\n")) writes))
       (tts-preparation-test--empty process)))))

(ert-deftest tts-preparation-final-admission-rechecks-cancellation-after-validator ()
  (omnivox-choice-playback-test--with-runtime
   (let ((original (symbol-function 'omnivox--choice-dispatch-admission)) (checks 0) commands)
     (cl-letf (((symbol-function 'process-send-string) (lambda (_ command) (push command commands)))
               ((symbol-function 'omnivox--choice-dispatch-admission)
                (lambda (owner)
                  (funcall original owner)
                  (when (= (cl-incf checks) 2) (tts-stop t)))))
       (should-not (omnivox-choice-playback-test--submit)))
     (should (= checks 2))
     (should (cl-every (lambda (command) (equal command "s\n")) commands))
     (tts-preparation-test--empty speaker))))

(ert-deftest tts-preparation-inactive-owner-cannot-observe-playback ()
  (tts-handoff-test--with-process
   (let (observed)
     (tts--call-with-preparation
      process (lambda ()
                (let ((owner (tts--dispatch-new-owner #'ignore #'ignore nil)))
                  (should-not (tts--dispatch-observing-p owner))
                  (should-not (tts--dispatch-playback-marker-event
                               process (tts-handoff-test--event (tts--dispatch-owner-id owner))
                               (lambda (_) (setq observed t)))))))
     (should-not observed)
     (tts-preparation-test--empty process))))

(provide 'tts-preparation-tests)
;;; tts-preparation-tests.el ends here
