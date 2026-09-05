;;; verify-remote-omnivox.el --- Live workstation acceptance -*- lexical-binding: t; -*-

;;; Commentary:
;; Run against an isolated live service, using OMNIVOX_REMOTE_TEST_PORT and
;; OMNIVOX_REMOTE_TEST_TOKEN.  The caller owns the service and token lifecycle.
;;; Code:

(setq load-prefer-newer t)
(let* ((directory (file-name-directory (or load-file-name buffer-file-name)))
       (root (expand-file-name "../" directory)))
  (add-to-list 'load-path (expand-file-name "lisp" root))
  (load (expand-file-name "lisp/emacsvox-preamble.el" root) nil t))
(require 'cl-lib)
(require 'tts-speak)
(require 'omnivox-voices)

(setq tts-program "omnivox"
      tts-notification-device nil
      omnivox-remote-host "127.0.0.1"
      omnivox-remote-port (string-to-number (getenv "OMNIVOX_REMOTE_TEST_PORT"))
      omnivox-remote-token-file (getenv "OMNIVOX_REMOTE_TEST_TOKEN")
      omnivox-remote-auto-reconnect t)

(defun omnivox-remote-test-wait (predicate description)
  "Wait for PREDICATE, reporting DESCRIPTION on timeout."
  (let ((deadline (+ (float-time) 20)))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.05))
    (unless (funcall predicate) (error "Timed out: %s" description))))

(unwind-protect
    (cl-letf (((symbol-function 'tts--resolve-program)
               (lambda (&rest _) (error "Remote Emacs attempted a local launch"))))
      (omnivox-remote-connect)
      (omnivox-remote-test-wait
       (lambda ()
         (and (process-get tts-speaker-process omnivox--control-inventory-property)
              (process-get tts-notify-process omnivox--control-inventory-property)))
       "both workstation inventories")
      (unless (omnivox-query-voices) (error "Workstation has no voices"))
      (let (terminal)
        (tts--protocol-queue-text "Remote Emacs speech test.")
        (tts--protocol-dispatch-tracked (lambda (_ status) (setq terminal status)))
        (omnivox-remote-test-wait (lambda () terminal) "tracked speech completion")
        (unless (eq terminal 'completed) (error "Speech failed: %s" terminal)))
      (let ((old tts-notify-process)
            (speaker tts-speaker-process))
        (delete-process old)
        (omnivox-remote-test-wait
         (lambda () (and (process-live-p tts-notify-process)
                         (not (eq old tts-notify-process))
                         (process-get tts-notify-process omnivox--control-inventory-property)))
         "notification reconnect")
        (unless (eq speaker tts-speaker-process)
          (error "Notification recovery replaced the healthy speaker")))
      (let ((old tts-speaker-process)
            (notification tts-notify-process) terminal)
        (process-send-string old "sh 10000\n")
        (tts--protocol-dispatch-tracked (lambda (_ status) (setq terminal status)))
        (delete-process old)
        (omnivox-remote-test-wait (lambda () terminal) "lost dispatch failure")
        (unless (eq terminal 'failed) (error "Lost speech was not failed: %s" terminal))
        (omnivox-remote-test-wait
         (lambda () (and (process-live-p tts-speaker-process)
                         (not (eq old tts-speaker-process))
                         (process-get tts-speaker-process omnivox--control-inventory-property)))
         "speaker reconnect")
        (unless (eq notification tts-notify-process)
          (error "Speaker recovery replaced the healthy notification lane")))
      (princ "Remote Emacs inventories, tracked speech, and lane recovery passed.\n"))
  (omnivox-remote-disconnect))

;;; verify-remote-omnivox.el ends here
