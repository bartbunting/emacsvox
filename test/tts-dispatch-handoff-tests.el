;;; tts-dispatch-handoff-tests.el --- Submission ownership tests -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Exercise real dispatch and filter paths with substituted writes, without audio.
;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'tts-speak)
(require 'omnivox-voices)
(require 'emacsvox-speak)

(defmacro tts-handoff-test--with-process (&rest body)
  "Run BODY with an isolated capable speech process and callback state."
  (declare (indent 0) (debug t))
  `(let* ((process (make-pipe-process :name "tts-handoff-test" :noquery t))
          (tts-speaker-process process)
          (tts-notify-process nil)
          (tts-program "omnivox")
          (tts--tracked-dispatch-sequence 0)
          (tts--tracked-dispatches (make-hash-table :test #'eql))
          (tts--marker-dispatches (make-hash-table :test #'eql))
          (tts--dispatch-lifecycles (make-hash-table :test #'eql))
          (tts-stopped-hook nil)
          (emacsvox-speak-messages nil)
          (emacsvox-aural-delivery-failed-hook nil)
          (emacsvox-aural-submission-controls-interruption nil)
          (emacsvox-aural-submission-delivery-policy 'ordered)
          (emacsvox-aural--pending-deliveries (make-hash-table :test #'equal))
          (omnivox-last-realized-routes (make-hash-table :test #'equal))
          (omnivox--utterance-logical-voices (make-hash-table :test #'equal))
          (omnivox-realized-route-changed-hook nil)
          (tts-realized-voice-changed-hook nil))
     (unwind-protect
         (progn
           (process-put process tts--tracked-playback-completion-property t)
           (process-put process tts--marker-playback-events-property t)
           (process-put process emacsvox-aural--structured-timeline-process-property 3)
           ,@body)
       (let ((emacsvox-aural--delivery-transaction-active-p nil))
         (tts--cancel-process-tracked-dispatches process 'cancelled))
       (when-let* ((timer (process-get process 'tts--dispatch-notification-timer)))
         (cancel-timer timer))
       (delete-process process))))

(defun tts-handoff-test--event (id &optional sequence type)
  "Return a source marker for ID, SEQUENCE and TYPE."
  (list :protocol_version 2 :dispatch_id id :sequence (or sequence 1)
        :type (or type "utterance_started") :utterance_id 1
        :logical_voice_id "bolden" :engine_id "espeak"
        :actual_voice (list :engine_id "espeak" :voice_id "en")))

(defun tts-handoff-test--submit (marker completion &optional effect text)
  "Submit TEXT with MARKER and COMPLETION, optionally deferring EFFECT."
  (let* ((text (or text "The quick brown fox."))
         (tts--marker-event-function marker)
         (tts--tracked-completion-function completion)
         (plan (emacsvox-aural--make-concrete-plan
                :content (emacsvox-aural--make-concrete-content :text text :speak t)
                :context '(:icons-enabled nil))))
    (cl-letf (((symbol-function 'tts-voice-reset-code) (lambda () "")))
      (emacsvox-aural-call-with-delivery-transaction
       tts-speaker-process
       (lambda ()
         (when effect (emacsvox-aural--defer-delivery-effect effect))
         (emacsvox-aural-queue-concrete-plan plan text)
         (tts--protocol-dispatch))))))

(ert-deftest tts-handoff-early-events-wait-for-return-and-terminal-releases-owner ()
  (tts-handoff-test--with-process
   (let (returned callbacks)
     (cl-letf (((symbol-function 'process-send-string)
                (lambda (_process _command)
                  (should (tts--dispatch-playback-marker-event process (tts-handoff-test--event 1)))
                  (tts--complete-tracked-dispatch process "__EMACSVOX_TRACKED__ 1 completed")
                  (tts--dispatch-drain process)
                  (should-not callbacks))))
       (setq returned
             (tts-handoff-test--submit
              (lambda (id _event) (should (eql id returned)) (push 'marker callbacks))
              (lambda (id status) (should (eql id returned)) (push status callbacks)))))
     (should (= returned 1))
     (should-not callbacks)
     (should-not (gethash 1 tts--dispatch-lifecycles))
     (tts--dispatch-drain process)
     (should (equal (nreverse callbacks) '(marker completed)))
     (should (= 0 (process-get process 'tts--dispatch-owner-count)))
     (should-not (gethash 1 tts--marker-dispatches)))))

(ert-deftest tts-handoff-ordinary-speech-observes-source-without-marker-callback ()
  (tts-handoff-test--with-process
   (let (observed)
     (cl-letf (((symbol-function 'process-send-string)
                (lambda (&rest _)
                  (tts--dispatch-playback-marker-event process (tts-handoff-test--event 1))
                  (setq observed (tts--dispatch-lifecycle-source-observed-at
                                  (gethash 1 tts--dispatch-lifecycles))))))
       (should (= 1 (tts-handoff-test--submit nil nil))))
     (should (numberp observed))
     (should-not (process-get process 'tts--dispatch-notifications))
     (tts--complete-tracked-dispatch process "__EMACSVOX_TRACKED__ 1 completed")
     (tts--dispatch-drain process)
     (should (= 0 (process-get process 'tts--dispatch-owner-count))))))

(ert-deftest tts-handoff-partial-writes-and-retirement-never-publish-or-replay ()
  (dolist (failure '(stop exit error quit))
    (tts-handoff-test--with-process
     (let ((writes 0) injected callbacks result quit-seen)
       (cl-letf (((symbol-function 'message) #'ignore)
                 ((symbol-function 'process-send-string)
                  (lambda (&rest _)
                    (cl-incf writes)
                    (unless injected
                      (setq injected t)
                      (tts--dispatch-playback-marker-event process (tts-handoff-test--event 1))
                      (pcase failure
                        ('stop (tts--interrupt-process process))
                        ('exit (delete-process process)
                               (tts--cancel-process-tracked-dispatches process 'failed))
                        ('error (error "partial write"))
                        ('quit (signal 'quit nil)))))))
         (condition-case nil
             (setq result (tts-handoff-test--submit
                           (lambda (&rest _) (push 'marker callbacks))
                           (lambda (&rest _) (push 'terminal callbacks))))
           (quit (setq quit-seen t))))
       (should (eq quit-seen (eq failure 'quit)))
       (should-not result)
       (tts--dispatch-drain process)
       (should-not callbacks)
       (should (= writes (if (eq failure 'stop) 2 1)))
       (should (= 0 (process-get process 'tts--dispatch-owner-count)))
       (should-not (gethash 1 tts--dispatch-lifecycles))
       (should-not (gethash 1 tts--marker-dispatches))))))

(ert-deftest tts-handoff-effect-error-cleans-owner-after-complete-write ()
  (tts-handoff-test--with-process
   (let ((writes 0) callbacks)
     (cl-letf (((symbol-function 'process-send-string)
                (lambda (&rest _)
                  (cl-incf writes)
                  (tts--dispatch-playback-marker-event process (tts-handoff-test--event 1)))))
       (should-error
        (tts-handoff-test--submit (lambda (&rest _) (push t callbacks)) #'ignore
                                  (lambda () (error "post-write effect failure")))))
     (tts--dispatch-drain process)
     (should-not callbacks)
     (should (= writes 1))
     (should (= 0 (process-get process 'tts--dispatch-owner-count))))))

(ert-deftest tts-handoff-stop-after-early-terminal-cancels-once ()
  (tts-handoff-test--with-process
   (let (callbacks)
     (cl-letf (((symbol-function 'process-send-string) #'ignore))
       (tts-handoff-test--submit
        (lambda (&rest _) (push 'marker callbacks))
        (lambda (_id status) (push status callbacks)))
       (tts--dispatch-playback-marker-event process (tts-handoff-test--event 1))
       (tts--complete-tracked-dispatch process "__EMACSVOX_TRACKED__ 1 completed")
       (tts--interrupt-process process)
       (tts--interrupt-process process))
     (tts--dispatch-drain process)
     (should (equal callbacks '(cancelled)))
     (should (= 0 (process-get process 'tts--dispatch-owner-count))))))

(ert-deftest tts-handoff-callback-speech-owns-a-fresh-transaction ()
  (tts-handoff-test--with-process
   (let (writes)
     (cl-letf (((symbol-function 'process-send-string)
                (lambda (_process command) (push command writes))))
       (tts-handoff-test--submit
        (lambda (&rest _)
          (should-not emacsvox-aural--delivery-transaction-active-p)
          (should-not emacsvox-aural-submission-facts)
          (emacsvox-aural-call-with-delivery-transaction
           process (lambda () (emacsvox-aural-delivery-send process "q {next}\nd\n"))))
        nil)
       (tts--dispatch-playback-marker-event process (tts-handoff-test--event 1))
       (tts--dispatch-drain process))
     (should (= 2 (length writes)))
     (should (equal (car writes) "q {next}\nd\n")))))

(ert-deftest tts-handoff-legacy-dispatch-entry-points-retain-early-terminal ()
  (dolist (kind '(tracked marked))
    (dolist (captured '(nil t))
      (tts-handoff-test--with-process
       (let (result callbacks)
         (cl-letf (((symbol-function 'process-send-string)
                    (lambda (&rest _)
                      (tts--complete-tracked-dispatch process "__EMACSVOX_TRACKED__ 1 completed"))))
           (cl-labels ((submit ()
                         (let ((callback (lambda (id status)
                                           (should (eql id result)) (push status callbacks))))
                           (if (eq kind 'tracked) (tts--protocol-dispatch-tracked callback)
                             (tts--protocol-dispatch-marked #'ignore callback)))))
             (setq result (if captured
                              (emacsvox-aural-call-with-delivery-transaction process #'submit)
                            (submit)))))
         (should (= result 1))
         (should-not callbacks)
         (tts--dispatch-drain process)
         (should (equal callbacks '(completed))))))))

(ert-deftest tts-handoff-overflow-preserves-terminal-capacity ()
  (dolist (early '(nil t))
    (tts-handoff-test--with-process
     (let ((tts--dispatch-notification-limit 1) callbacks result)
       (cl-labels ((overflow ()
                     (tts--dispatch-playback-marker-event process (tts-handoff-test--event 1))
                     (tts--dispatch-playback-marker-event process (tts-handoff-test--event 1 2))))
         (cl-letf (((symbol-function 'process-send-string)
                    (lambda (&rest _) (when early (overflow)))))
           (setq result (tts-handoff-test--submit #'ignore
                                                  (lambda (_id status) (push status callbacks)))))
         (unless early (overflow)))
       (tts--dispatch-drain process)
       (if early (progn (should-not result) (should-not callbacks))
         (should (= result 1)) (should (equal callbacks '(failed))))
       (should (= 0 (process-get process 'tts--dispatch-owner-count)))))))

(ert-deftest tts-handoff-reentrant-filters-preserve-original-line-order ()
  (dolist (kind '(tts omnivox))
    (tts-handoff-test--with-process
     (let* ((filter (if (eq kind 'tts) #'tts--speaker-process-filter #'omnivox--control-process-filter))
            (forward (if (eq kind 'tts) tts--tracked-filter-property omnivox--control-original-filter-property))
            lines)
       (process-put process forward
                    (lambda (owner output)
                      (push output lines)
                      (when (equal output "first\n") (funcall filter owner "third\n"))))
       (funcall filter process "fir")
       (funcall filter process "st\nsecond\n")
       (should (equal (nreverse lines) '("first\n" "second\n" "third\n")))))))

(ert-deftest tts-handoff-route-hooks-wait-and-retired-events-cannot-relabel ()
  (tts-handoff-test--with-process
   (let (hooks)
     (let ((omnivox-realized-route-changed-hook (list (lambda (route) (push route hooks)))))
       (cl-letf (((symbol-function 'process-send-string) #'ignore))
         (tts-handoff-test--submit nil nil))
       (cl-labels ((emit (event)
                     (omnivox--handle-marker-line
                      process (concat omnivox-marker-event-prefix
                                      (base64-encode-string (json-serialize event) t)))))
         (emit (tts-handoff-test--event 1))
         (should-not hooks)
         (should (gethash "bolden" omnivox-last-realized-routes))
         (tts--dispatch-drain process)
         (should (= 1 (length hooks)))
         (tts-cancel-tracked-dispatch 1)
         (emit (plist-put (tts-handoff-test--event 1 2) :logical_voice_id "other"))
         (should-not (gethash "other" omnivox-last-realized-routes)))))))

(ert-deftest tts-handoff-multipart-failure-does-not-replay-or-leak ()
  (tts-handoff-test--with-process
   (let ((emacsvox-aural--timeline-frame-max-bytes 128)
         (emacsvox-aural--timeline-encoded-fragment-max-bytes 172)
         (writes 0) callbacks)
     (cl-letf (((symbol-function 'message) #'ignore)
               ((symbol-function 'process-send-string)
                (lambda (_process command)
                  (cl-incf writes)
                  (should (string-prefix-p "emacsvox_timeline_part 3 " command))
                  (should (> (length (split-string command "\n" t)) 1))
                  (error "connection lost after first multipart prefix"))))
       (should-not (tts-handoff-test--submit nil (lambda (&rest _) (push t callbacks))
                                             nil (make-string 1000 ?x))))
     (should (= 1 writes))
     (should-not callbacks)
     (should (= 0 (process-get process 'tts--dispatch-owner-count))))))

(ert-deftest tts-handoff-invalid-packet-reserves-no-owner-and-does-not-stop ()
  (tts-handoff-test--with-process
   (let ((emacsvox-aural--timeline-aggregate-max-bytes 10)
         (emacsvox-aural-submission-controls-interruption t)
         (emacsvox-aural-submission-interruption-policy 'lane)
         (emacsvox-aural-submission-delivery-policy 'urgent)
         writes)
     (cl-letf (((symbol-function 'process-send-string)
                (lambda (&rest _) (push t writes))))
       (should-error (tts-handoff-test--submit nil #'ignore)))
     (should-not writes)
     (should (= 0 (or (process-get process 'tts--dispatch-owner-count) 0))))))

(ert-deftest tts-handoff-reservation-limit-rejects-before-navigation-stop ()
  (tts-handoff-test--with-process
   (let ((tts--dispatch-owner-limit 1) writes)
     (cl-letf (((symbol-function 'process-send-string)
                (lambda (_process command) (push command writes))))
       (tts-handoff-test--submit nil nil)
       (let ((emacsvox-aural-submission-controls-interruption t)
             (emacsvox-aural-submission-interruption-policy 'lane)
             (emacsvox-aural-submission-delivery-policy 'urgent))
         (should-error (tts-handoff-test--submit nil nil))))
     (should (= 1 (length writes)))
     (should (= 1 (process-get process 'tts--dispatch-owner-count))))))

(ert-deftest tts-handoff-navigation-arms-after-its-own-interruption ()
  (tts-handoff-test--with-process
   (let ((emacsvox-aural-submission-controls-interruption t)
         (emacsvox-aural-submission-interruption-policy 'lane)
         (emacsvox-aural-submission-delivery-policy 'urgent)
         writes callbacks)
     (cl-letf (((symbol-function 'process-send-string)
                (lambda (_process command) (push command writes))))
       (should (= 1 (tts-handoff-test--submit nil (lambda (_id status) (push status callbacks))))))
     (should (equal (car (last writes)) "s\n"))
     (tts--complete-tracked-dispatch process "__EMACSVOX_TRACKED__ 1 completed")
     (tts--dispatch-drain process)
     (should (equal callbacks '(completed))))))

(ert-deftest tts-handoff-local-stop-hook-speech-has-independent-capture ()
  (tts-handoff-test--with-process
   (let ((emacsvox-aural-submission-controls-interruption t)
         (emacsvox-aural-submission-delivery-policy 'urgent)
         (tts-stopped-hook
          (list (lambda (owner)
                  (should-not emacsvox-aural--delivery-transaction-active-p)
                  (emacsvox-aural-call-with-delivery-transaction
                   owner (lambda () (emacsvox-aural-delivery-send owner "q {stopped}\nd\n"))))))
         writes)
     (cl-letf (((symbol-function 'process-send-string)
                (lambda (_process command) (push command writes))))
       (should (= 1 (tts-handoff-test--submit nil nil))))
     (should (= 3 (length writes)))
     (should (equal (nth 1 (reverse writes)) "q {stopped}\nd\n")))))

(ert-deftest tts-handoff-stop-hook-preserves-ambient-process-and-replacement ()
  (tts-handoff-test--with-process
   (let* ((notification (make-pipe-process :name "handoff-notify" :noquery t))
          (replacement (make-pipe-process :name "handoff-replacement" :noquery t))
          (tts-notify-process notification)
          (emacsvox-aural--delivery-transaction-active-p t)
          (emacsvox-aural-submission-lane 'notification)
          (tts-stopped-hook
           (list (lambda (owner)
                   (should (eq owner notification))
                   (should (eq tts-speaker-process process))
                   (should (eq emacsvox-aural-submission-lane 'main))
                   (should-not emacsvox-aural--delivery-transaction-active-p)
                   (setq tts-speaker-process replacement)))))
     (unwind-protect
         (progn
           (cl-letf (((symbol-function 'process-send-string) #'ignore))
             (tts--interrupt-process notification))
           (should (eq tts-speaker-process replacement))
           (should emacsvox-aural--delivery-transaction-active-p)
           (should (eq emacsvox-aural-submission-lane 'notification)))
       (delete-process notification)
       (delete-process replacement)))))

(ert-deftest tts-handoff-two-lanes-retire-independently ()
  (tts-handoff-test--with-process
   (let ((notification (make-pipe-process :name "handoff-notification" :noquery t))
         main-result notification-result)
     (unwind-protect
         (progn
           (dolist (property (list tts--tracked-playback-completion-property
                                   tts--marker-playback-events-property))
             (process-put notification property t))
           (process-put notification emacsvox-aural--structured-timeline-process-property 3)
           (cl-letf (((symbol-function 'process-send-string) #'ignore))
             (tts-handoff-test--submit nil (lambda (_id status) (push status main-result)))
             (let ((tts-speaker-process notification))
               (tts-handoff-test--submit nil (lambda (_id status) (push status notification-result))))
             (tts--interrupt-process process))
           (tts--complete-tracked-dispatch notification "__EMACSVOX_TRACKED__ 2 completed")
           (tts--dispatch-drain notification)
           (should (equal main-result '(cancelled)))
           (should (equal notification-result '(completed))))
       (tts--cancel-process-tracked-dispatches notification 'cancelled)
       (when-let* ((timer (process-get notification 'tts--dispatch-notification-timer)))
         (cancel-timer timer))
       (delete-process notification)))))

(ert-deftest tts-handoff-tracked-reader-advances-after-early-completion ()
  (tts-handoff-test--with-process
   (with-temp-buffer
     (insert "First sentence.  Second sentence.")
     (let* ((session (emacsvox--make-tracked-reading-session
                      :buffer (current-buffer) :window nil :generation 7 :process process
                      :limit (copy-marker (point-max)) :next (copy-marker 1)
                      :current-start (make-marker) :current-end (make-marker)))
            (emacsvox--tracked-reading-session session)
            (emacsvox--tracked-reading-generation 7)
            (emacsvox-tracked-reading-max-chars 18)
            (calls 0) first-end)
       (unwind-protect
           (cl-letf (((symbol-function 'tts-speak)
                      (lambda (text) (tts-handoff-test--submit nil tts--tracked-completion-function nil text)))
                     ((symbol-function 'process-send-string)
                      (lambda (&rest _)
                        (cl-incf calls)
                        (when (= calls 1)
                          (tts--complete-tracked-dispatch process "__EMACSVOX_TRACKED__ 1 completed")))))
             (emacsvox--tracked-reading-next 7)
             (setq first-end (marker-position (emacsvox--tracked-reading-session-current-end session)))
             (should (= 1 (emacsvox--tracked-reading-session-identifier session)))
             (tts--dispatch-drain process)
             (should (= calls 2))
             (should (= 2 (emacsvox--tracked-reading-session-identifier session)))
             (should (>= (point) first-end)))
         (emacsvox--tracked-reading-cancel))))))

(ert-deftest tts-handoff-reentrant-drain-and-callback-errors-preserve-order ()
  (tts-handoff-test--with-process
   (let (seen)
     (cl-letf (((symbol-function 'process-send-string) #'ignore)
               ((symbol-function 'message) #'ignore))
       (tts-handoff-test--submit
        (lambda (id event)
          (push (plist-get event :sequence) seen)
          (when (= 1 (plist-get event :sequence))
            (tts--dispatch-playback-marker-event process (tts-handoff-test--event id 2))
            (tts--dispatch-drain process)
            (should (equal seen '(1)))
            (error "observer failure"))) nil)
       (tts--dispatch-playback-marker-event process (tts-handoff-test--event 1))
       (tts--dispatch-drain process))
     (should (equal (reverse seen) '(1 2))))))

(ert-deftest tts-handoff-quit-consumes-current-notification-and-reschedules-rest ()
  (tts-handoff-test--with-process
   (let (seen quit-seen)
     (cl-letf (((symbol-function 'process-send-string) #'ignore))
       (tts-handoff-test--submit
        (lambda (_id event)
          (push (plist-get event :sequence) seen)
          (when (= 1 (plist-get event :sequence)) (signal 'quit nil))) nil))
     (tts--dispatch-playback-marker-event process (tts-handoff-test--event 1 1))
     (tts--dispatch-playback-marker-event process (tts-handoff-test--event 1 2))
     (condition-case nil (tts--dispatch-drain process) (quit (setq quit-seen t)))
     (should quit-seen)
     (should (equal seen '(1)))
     (should (timerp (process-get process 'tts--dispatch-notification-timer)))
     (tts--dispatch-drain process)
     (should (equal seen '(2 1))))))

(ert-deftest tts-handoff-sequence-gap-is-retained-and-changed-generation-suppresses-queue ()
  (tts-handoff-test--with-process
   (let (seen)
     (cl-letf (((symbol-function 'process-send-string) #'ignore))
       (tts-handoff-test--submit (lambda (&rest _) (setq seen t)) nil))
     (tts--dispatch-playback-marker-event process (tts-handoff-test--event 1 3))
     (should (equal (process-get process 'tts--marker-sequence-gap)
                    '(:dispatch-id 1 :previous 0 :received 3)))
     (process-put process 'tts--speech-process-generation 2)
     (tts--dispatch-drain process)
     (should-not seen)
     (should-not (process-get process 'tts--dispatch-notifications))
     (should (= 0 (process-get process 'tts--dispatch-owner-count))))))

(ert-deftest tts-handoff-semantic-snapshot-copies-mutable-strings-and-vectors ()
  (tts-handoff-test--with-process
   (tts--call-with-preparation process (lambda ()
    (let* ((name (copy-sequence "original")) (data (vector name))
          (owner (tts--dispatch-new-owner nil nil (list (cons "event" data)))))
     (unwind-protect
         (progn
           (aset name 0 ?X)
           (aset data 0 "replacement")
           (should (equal (cdr (car (tts--dispatch-owner-semantics owner))) ["original"])))
       (tts--dispatch-abandon owner)))))))

(ert-deftest tts-handoff-outer-submission-error-suppresses-published-callbacks ()
  (tts-handoff-test--with-process
   (let (callbacks)
     (cl-letf (((symbol-function 'process-send-string) #'ignore))
       (should-error
        (emacsvox-aural-call-with-submission
         (lambda ()
           (tts-handoff-test--submit nil (lambda (&rest _) (push t callbacks)))
           (tts--complete-tracked-dispatch process "__EMACSVOX_TRACKED__ 1 completed")
           (error "history finalization failed"))
         :context '(:module test))))
     (tts--dispatch-drain process)
     (should-not callbacks)
     (should (= 0 (process-get process 'tts--dispatch-owner-count))))))

(ert-deftest tts-handoff-captured-legacy-tracking-is-never-left-idle ()
  (tts-handoff-test--with-process
   (let ((emacsvox-aural-submission-delivery-policy 'replaceable)
         (emacsvox-aural-submission-replacement-key 'test)
         writes)
     (cl-letf (((symbol-function 'process-send-string)
                (lambda (&rest _) (push t writes))))
       (should (= 1 (emacsvox-aural-call-with-delivery-transaction
                     process (lambda () (tts--protocol-dispatch-tracked #'ignore))))))
     (should (= 1 (length writes)))
     (should (= 0 (hash-table-count emacsvox-aural--pending-deliveries))))))

(provide 'tts-dispatch-handoff-tests)
;;; tts-dispatch-handoff-tests.el ends here
