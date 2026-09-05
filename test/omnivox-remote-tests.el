;;; omnivox-remote-tests.el --- Remote transport checks -*- lexical-binding: t; -*-

;;; Commentary:
;; Transport policy, filter composition, and lifecycle regression checks.
;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'tts-speak)
(require 'omnivox-voices)

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
