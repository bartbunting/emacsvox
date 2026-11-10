;;; omnivox-discovery-refresh-tests.el --- Optional engine observations -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Code:
(require 'omnivox-recovery-tests)
(require 'omnivox-native-runtime-tests)

(defun omnivox-discovery-test--inventory (state)
  (list :type "inventory" :engines
        (vector (list :id "eloquence" :availability
                      (if (eq state 'pending)
                          '(:status "unavailable" :reason "Runtime rescan in progress")
                        (if (eq state 'failed)
                            '(:status "unavailable" :reason "Helper startup timed out")
                          '(:status "available")))))))

(defmacro omnivox-discovery-test--workers (&rest body)
  (declare (indent 0))
  `(omnivox-recovery-tests--workers
    (let ((process-environment (copy-sequence process-environment))
          (tts-voice-inventory-changed-hook nil)
          (omnivox-engine-inventory nil) (omnivox-engine-inventory-time nil)
          (omnivox-routing-policy-registration nil) (omnivox-control-last-error nil))
      (setenv "OMNIVOX_EXPERIMENTAL_EARLY_SPEECH" "1")
      (unwind-protect (progn ,@body)
        (dolist (p (list main notify replacement))
          (omnivox--cancel-discovery-refresh p)
          (delete-process p)
          (omnivox--retire-control-requests p))))))

(ert-deftest omnivox-discovery-refresh-is-opt-in-and-stops-on-final-failure ()
  (omnivox-discovery-test--workers
    (setenv "OMNIVOX_EXPERIMENTAL_EARLY_SPEECH" nil)
    (omnivox--handle-inventory-response main (omnivox-discovery-test--inventory 'pending))
    (should-not (process-get main 'omnivox--discovery-timer))
    (setenv "OMNIVOX_EXPERIMENTAL_EARLY_SPEECH" "1")
    (omnivox--schedule-discovery-refresh main)
    (should (timerp (process-get main 'omnivox--discovery-timer)))
    (omnivox--handle-discovery-response main (omnivox-discovery-test--inventory 'failed))
    (should-not (process-get main 'omnivox--discovery-timer))))

(ert-deftest omnivox-discovery-refresh-retries-lost-reply-within-fixed-budget ()
  (omnivox-discovery-test--workers
    (omnivox--handle-inventory-response main (omnivox-discovery-test--inventory 'pending))
    (let ((deadline (process-get main 'omnivox--discovery-deadline)))
      (omnivox--handle-discovery-response main '(:type "error" :code "timeout" :message "Lost reply"))
      (should (timerp (process-get main 'omnivox--discovery-timer)))
      (should (= deadline (process-get main 'omnivox--discovery-deadline)))
      (process-put main 'omnivox--discovery-deadline (- (float-time) 1))
      (omnivox--handle-discovery-response main '(:type "error" :code "timeout" :message "Lost reply"))
      (should-not (process-get main 'omnivox--discovery-timer)))))

(ert-deftest omnivox-discovery-refresh-deduplicates-requests-and-cleans-dead-owner ()
  (omnivox-discovery-test--workers
    (cl-letf (((symbol-function 'tts-queue--send-typed) #'ignore))
      (let ((id (omnivox--request-inventory main t)))
        (should (= id (omnivox--request-inventory main)))
        (should (= id (omnivox--request-inventory main t)))
        (should (= 1 (hash-table-count (omnivox--pending-requests main)))))))
  (omnivox-discovery-test--workers
    (omnivox--handle-inventory-response main (omnivox-discovery-test--inventory 'pending))
    (delete-process main)
    (omnivox--retire-control-requests main)
    (should-not (process-get main 'omnivox--discovery-timer))))

(ert-deftest omnivox-discovery-refresh-ignores-retired-and-replaced-lanes ()
  (dolist (retiring '(nil t))
    (omnivox-discovery-test--workers
      (omnivox--handle-inventory-response main (omnivox-discovery-test--inventory 'pending))
      (if retiring (process-put main 'tts--speech-process-retiring t)
        (setq tts-speaker-process replacement))
      (cl-letf (((symbol-function 'omnivox--request-inventory)
                 (lambda (&rest _) (ert-fail "Refreshed obsolete owner"))))
        (omnivox--refresh-discovery main))
      (omnivox--handle-discovery-response main (omnivox-discovery-test--inventory 'ready))
      (should (omnivox--discovery-pending-p
               (process-get main omnivox--control-inventory-property)))
      (should-not (process-get main 'omnivox--discovery-timer)))))

(ert-deftest omnivox-discovery-refresh-changes-only-own-lane-with-current-preferences ()
  (omnivox-discovery-test--workers
    (let ((omnivox-engine-priority-ids '("eloquence")) registrations)
      (dolist (p (list main notify))
        (process-put p omnivox--control-capabilities-property
                     '(:features ("logical_voice_registration"))))
      (cl-letf (((symbol-function 'omnivox--register-logical-voices)
                 (lambda (processes)
                   (push (list processes (copy-sequence omnivox-engine-priority-ids)) registrations))))
        (omnivox--handle-inventory-response main (omnivox-discovery-test--inventory 'pending))
        (omnivox--handle-inventory-response notify (omnivox-discovery-test--inventory 'pending))
        (setq registrations nil omnivox-engine-priority-ids '("flite"))
        (omnivox--handle-discovery-response main (omnivox-discovery-test--inventory 'pending))
        (should-not registrations)
        (omnivox--handle-discovery-response main (omnivox-discovery-test--inventory 'ready))
        (should (equal registrations (list (list (list main) '("flite")))))
        (should-not (process-get main 'omnivox--discovery-timer))
        (should (timerp (process-get notify 'omnivox--discovery-timer)))))))

(ert-deftest omnivox-discovery-refresh-starts-after-prepared-worker-is-published ()
  (omnivox-discovery-test--workers
    (omnivox--handle-inventory-response replacement (omnivox-discovery-test--inventory 'pending))
    (should-not (process-get replacement 'omnivox--discovery-timer))
    (setq tts-speaker-process replacement)
    (cl-letf (((symbol-function 'omnivox--finish-capability-negotiation) #'ignore)
              ((symbol-function 'omnivox--update-unicode-preprocessing) #'ignore))
      (omnivox--publish-prepared-main replacement))
    (should (timerp (process-get replacement 'omnivox--discovery-timer)))))

(ert-deftest omnivox-discovery-refresh-preserves-saved-native-choices ()
  (omnivox-native-runtime-test--with-speech
    (let* ((process-environment (copy-sequence process-environment))
           (tts-voice-inventory-changed-hook nil)
           (before (copy-tree emacsvox-aural-routing--choice-sets))
           (content (omnivox--process-logical-registry-content speaker)) writes)
      (setenv "OMNIVOX_EXPERIMENTAL_EARLY_SPEECH" "1")
      (unwind-protect
          (cl-letf (((symbol-function 'omnivox--set-process-routing-policy) (lambda (_) nil))
                    ((symbol-function 'process-send-string)
                     (lambda (process command)
                       (push (cons process (omnivox-test--choice-decode-command command)) writes))))
            (omnivox--handle-inventory-response speaker (omnivox-discovery-test--inventory 'pending))
            (omnivox--handle-discovery-response speaker (omnivox-discovery-test--inventory 'ready))
            (should (= 2 (length writes)))
            (dolist (write writes)
              (should (equal (plist-get (cdr write) :type) "register_logical_voices_v3"))
              (should (equal (plist-get (cdr write) :definitions)
                             (json-parse-string (json-serialize (plist-get content :definitions))
                                                :object-type 'plist :array-type 'list
                                                :null-object nil :false-object nil))))
            (should (equal before emacsvox-aural-routing--choice-sets)))
        (omnivox--cancel-discovery-refresh speaker)))))

(ert-deftest omnivox-discovery-refresh-survives-notification-process-binding ()
  (omnivox-discovery-test--workers
    (omnivox--handle-inventory-response main (omnivox-discovery-test--inventory 'pending))
    (let ((tts--notification-recovery-target (list main))
          (tts-speaker-process notify) requested)
      (cl-letf (((symbol-function 'omnivox--request-inventory)
                 (lambda (p discovery) (setq requested p) (should discovery))))
        (omnivox--refresh-discovery main))
      (should (eq requested main))
      (omnivox--handle-discovery-response main (omnivox-discovery-test--inventory 'ready))
      (should-not (omnivox--discovery-pending-p omnivox-engine-inventory))
      (should-not (process-get main 'omnivox--discovery-timer)))))

(provide 'omnivox-discovery-refresh-tests)
;;; omnivox-discovery-refresh-tests.el ends here
