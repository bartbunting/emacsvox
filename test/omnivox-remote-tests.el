;;; omnivox-remote-tests.el --- Remote transport checks -*- lexical-binding: t; -*-

;;; Commentary:
;; Transport policy, filter composition, and lifecycle regression checks.
;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'tts-speak)
(require 'omnivox-voices)
(require 'voice-setup)

(ert-deftest omnivox-remote-token-is-private-bounded-and-not-echoed ()
  (let ((omnivox-remote-token-file (make-temp-file "omnivox-token-"))
        (secret (make-string 64 ?a)))
    (unwind-protect
        (progn
          (with-temp-file omnivox-remote-token-file (insert secret "\n"))
          (should (equal (omnivox-remote--token) secret))
          (unless (eq system-type 'windows-nt)
            (set-file-modes omnivox-remote-token-file #o644)
            (should-error (omnivox-remote--token))
            (set-file-modes omnivox-remote-token-file #o600))
          (with-temp-file omnivox-remote-token-file (insert secret "\nextra"))
          (let ((error (should-error (omnivox-remote--token))))
            (should-not (string-match-p secret (error-message-string error)))))
      (delete-file omnivox-remote-token-file))))

(ert-deftest omnivox-remote-resources-require-bundled-safe-identifiers ()
  (let* ((tts-program "omnivox")
         (omnivox-remote-host "127.0.0.1")
         (emacsvox-sounds-dir (make-temp-file "omnivox-sounds-" t))
         (icon (expand-file-name "button.ogg" emacsvox-sounds-dir))
         (outside (make-temp-file "omnivox-outside-")))
    (unwind-protect
        (progn
          (with-temp-file icon (insert "fixture"))
          (should (equal (omnivox-remote-resource icon) "omnivox-icon:button.ogg"))
          (should-error (omnivox-remote-resource outside))
          (unless (eq system-type 'windows-nt)
            (make-symbolic-link outside (expand-file-name "escape.ogg" emacsvox-sounds-dir))
            (should-error
             (omnivox-remote-resource (expand-file-name "escape.ogg" emacsvox-sounds-dir))))
          (let ((omnivox-remote-host nil))
            (should (equal (omnivox-remote-resource outside) outside))))
      (delete-directory emacsvox-sounds-dir t)
      (delete-file outside))))

(ert-deftest omnivox-remote-pongs-survive-composed-control-and-tracked-filters ()
  (let ((process (make-pipe-process :name "remote-filter-test" :noquery t)))
    (unwind-protect
        (progn
          (set-process-filter process #'omnivox-remote--filter)
          (tts--ensure-tracked-process-filter process)
          (omnivox--install-control-filter process)
          (funcall (process-filter process) process "OMNIVOX-REMOTE po")
          (should-not (process-get process 'omnivox-remote-pong))
          (funcall (process-filter process) process "ng\n")
          (should (numberp (process-get process 'omnivox-remote-pong))))
      (delete-process process))))

(ert-deftest omnivox-remote-intentional-retirement-does-not-reconnect ()
  (let ((process (make-pipe-process :name "remote-retire-test" :noquery t))
        handled)
    (process-put process 'omnivox-remote-managed t)
    (process-put process tts--speech-process-retiring-property t)
    (delete-process process)
    (cl-letf (((symbol-function 'tts--speech-process-sentinel)
               (lambda (&rest _) (setq handled t)))
              ((symbol-function 'omnivox-remote--schedule-retry)
               (lambda () (ert-fail "intentional retirement scheduled a reconnect"))))
      (omnivox-remote--sentinel process "closed\n"))
    (should handled)))

(ert-deftest omnivox-remote-disconnect-cleans-both-lanes-after-hook-error ()
  "Disconnect retires both lanes and their heartbeats despite a bad observer."
  (let* ((speaker (make-pipe-process :name "remote-disconnect-main" :noquery t))
         (notifier (make-pipe-process :name "remote-disconnect-notify" :noquery t))
         (tts-speaker-process speaker)
         (tts-notify-process notifier)
         (omnivox-remote--session "test-session")
         (omnivox-remote--suspended nil)
         (omnivox-remote--retry-timer nil)
         stopped
         (tts-stopped-hook
          (list (lambda (_) (error "observer broke"))
                (lambda (owner) (push owner stopped)))))
    (unwind-protect
        (progn
          (dolist (process (list speaker notifier))
            (process-put process 'omnivox-remote-managed t)
            (process-put process 'omnivox-remote-heartbeat
                         (run-at-time 3600 nil #'ignore))
            (set-process-sentinel process #'omnivox-remote--sentinel))
          (cl-letf (((symbol-function 'emacsvox-aural-delivery-send) #'ignore)
                    ((symbol-function 'omnivox-remote--schedule-retry)
                     (lambda () (ert-fail "Disconnect scheduled reconnect"))))
            (omnivox-remote-disconnect))
          (should omnivox-remote--suspended)
          (should-not omnivox-remote--session)
          (should (equal (nreverse stopped) (list speaker notifier)))
          (dolist (process (list speaker notifier))
            (should-not (process-live-p process))
            (should-not (process-get process 'omnivox-remote-heartbeat))))
      (dolist (process (list speaker notifier))
        (when-let* ((timer (process-get process 'omnivox-remote-heartbeat)))
          (cancel-timer timer))
        (when (process-live-p process) (delete-process process))))))

(defmacro omnivox-remote-tests--with-partial-startup (&rest body)
  "Run BODY with a failed first notifier connection and controlled retry."
  (declare (indent 0) (debug t))
  `(let* ((speaker (make-pipe-process :name "remote-start-main" :noquery t))
          (notifier (make-pipe-process :name "remote-start-notify" :noquery t))
          (tts-speaker-process nil) (tts-notify-process nil)
          (tts-program "omnivox") (tts-notification-device nil)
          (tts-stopped-hook nil)
          (omnivox-default-voice-id "")
          (omnivox-remote-host "127.0.0.1")
          (omnivox-remote-auto-reconnect t)
          (omnivox-remote--suspended nil)
          (omnivox-remote--connecting nil)
          (omnivox-remote--session "test-session")
          (omnivox-remote--retry-timer nil)
          (omnivox-remote--retry-delay 1)
          (omnivox-remote--last-error nil)
          (notify-attempts 0)
          (run-at-time-function (symbol-function 'run-at-time))
          starts configured negotiated synchronized timers)
     (unwind-protect
         (cl-letf
             (((symbol-function 'tts-make-process)
               (lambda (name)
                 (push name starts)
                 (if (equal name "Speaker") speaker
                   (if (= 1 (cl-incf notify-attempts))
                       (error "notification handshake failed")
                     notifier))))
              ((symbol-function 'voice-setup)
               (lambda () (push tts-speaker-process configured)))
              ((symbol-function 'omnivox--negotiate-process)
               (lambda (process) (push process negotiated)))
              ((symbol-function 'tts--protocol-sync)
               (lambda () (push tts-speaker-process synchronized)))
              ((symbol-function 'emacsvox-aural-delivery-send) #'ignore)
              ((symbol-function 'run-at-time)
               (lambda (seconds repeat function &rest arguments)
                 (if (eq function #'omnivox-remote--retry)
                     (let ((timer (timer-create)))
                       (timer-set-function timer function arguments)
                       (push timer timers)
                       timer)
                   (apply run-at-time-function seconds repeat function arguments)))))
           (process-put speaker 'omnivox-remote-managed t)
           (process-put notifier 'omnivox-remote-managed t)
           ,@body)
       (dolist (timer timers) (cancel-timer timer))
       (delete-process speaker)
       (delete-process notifier))))

(ert-deftest omnivox-remote-partial-startup-retries-only-missing-lane ()
  "Ordinary startup recovers its notifier without replacing working main speech."
  (omnivox-remote-tests--with-partial-startup
    (tts-initialize)
    (should (eq tts-speaker-process speaker))
    (should-not tts-notify-process)
    (should (timerp omnivox-remote--retry-timer))
    (should (equal omnivox-remote--last-error "notification handshake failed"))
    (omnivox-remote--schedule-retry)
    (should (= 1 (length timers)))
    (funcall (timer--function omnivox-remote--retry-timer))
    (should (eq tts-speaker-process speaker))
    (should (eq tts-notify-process notifier))
    (should (equal (nreverse starts) '("Speaker" "Notify" "Notify")))
    (should (equal configured (list speaker)))
    (should (equal negotiated (list notifier)))
    (should (equal synchronized (list notifier)))
    (should-not omnivox-remote--retry-timer)
    (should-not omnivox-remote--last-error)
    (should (= 1 omnivox-remote--retry-delay))))

(ert-deftest omnivox-remote-partial-startup-respects-recovery-settings ()
  "Partial startup cannot schedule remote recovery when it is disabled."
  (dolist (setting '(local no-auto suspended no-notifier))
    (omnivox-remote-tests--with-partial-startup
      (pcase setting
        ('local (setq omnivox-remote-host nil))
        ('no-auto (setq omnivox-remote-auto-reconnect nil))
        ('suspended (setq omnivox-remote--suspended t))
        ('no-notifier (setq tts-notification-device "")))
      (tts-initialize)
      (should (eq tts-speaker-process speaker))
      (should-not omnivox-remote--retry-timer)
      (should-not timers)
      (should (= notify-attempts (if (eq setting 'no-notifier) 0 1))))))

(ert-deftest omnivox-remote-disconnect-cancels-partial-startup-retry ()
  "Explicit disconnect suspends even a retry callback already dispatched."
  (omnivox-remote-tests--with-partial-startup
    (tts-initialize)
    (let ((retry omnivox-remote--retry-timer))
      (should (timerp retry))
      (omnivox-remote-disconnect)
      (should omnivox-remote--suspended)
      (should-not omnivox-remote--retry-timer)
      (should-not (process-live-p speaker))
      (funcall (timer--function retry))
      (should (= 1 notify-attempts))
      (should (equal (mapcar #'timer--function timers) '(omnivox-remote--retry))))))

(ert-deftest omnivox-remote-voice-discovery-uses-workstation-inventory ()
  (let ((tts-program "omnivox")
        (omnivox-remote-host "127.0.0.1")
        (tts-speaker-process (make-pipe-process :name "remote-inventory-test" :noquery t)))
    (unwind-protect
        (progn
          (process-put tts-speaker-process omnivox--control-inventory-property
                       '(:engines [(:id "dectalk" :voices
                                   [(:id (:voice_id "paul") :display_name "Paul"
                                     :language "en-US" :quality "compact")])]))
          (cl-letf (((symbol-function 'omnivox--server-program)
                     (lambda () (ert-fail "remote discovery launched a local executable"))))
            (should (equal (omnivox-query-voices) '(("paul" "Paul" "en-US" "compact"))))))
      (delete-process tts-speaker-process))))

(provide 'omnivox-remote-tests)
;;; omnivox-remote-tests.el ends here
