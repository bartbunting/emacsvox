;;; emacsvox-remote-check.el --- Connected remote speech check -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; An explicit, audible acceptance check for bin/emacsvox --remote --check.
;; It owns only its connections, never the workstation service or SSH tunnel.

;;; Code:

(let ((root (file-name-as-directory (getenv "EMACSVOX_DIR"))))
  (load (expand-file-name "utils/emacsvox-remote-startup.el" root) nil t)
  (add-to-list 'load-path (expand-file-name "lisp" root))
  (load (expand-file-name "lisp/emacsvox-preamble.el" root) nil t))
(require 'tts-speak)
(require 'omnivox-voices)

(setq tts-notification-device nil
      omnivox-remote-auto-reconnect nil)

(defun emacsvox-remote-check--wait (predicate description)
  "Wait at most twenty seconds for PREDICATE, or fail with DESCRIPTION."
  (let ((deadline (+ (float-time) 20)))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.05))
    (unless (funcall predicate) (error "Timed out waiting for %s" description))))

(condition-case problem
    (unwind-protect
	(progn
	  (omnivox-remote-connect)
	  (emacsvox-remote-check--wait
	   (lambda ()
             (cl-every
              (lambda (process)
		(and (process-live-p process)
                     (process-get process omnivox--control-inventory-property)
                     (process-get process omnivox--control-registration-property)))
              (list tts-speaker-process tts-notify-process)))
	   "both workstation inventories and voice registrations")
	  (unless (omnivox-query-voices) (error "The workstation reports no voices"))
	  (dolist (lane `((,tts-speaker-process . "Remote foreground speech is ready.")
			  (,tts-notify-process . "Remote notification speech is ready.")))
            (let ((tts-speaker-process (car lane)) terminal)
              (tts--protocol-queue-text (cdr lane))
              (tts--protocol-dispatch-tracked (lambda (_ status) (setq terminal status)))
              (emacsvox-remote-check--wait (lambda () terminal) "speech completion")
              (unless (eq terminal 'completed) (error "Remote speech failed: %s" terminal))))
	  (princ "Both remote speech lanes completed. Confirm that you heard both announcements.\n"))
      (omnivox-remote-disconnect))
  (error
   (princ (format "Remote speech check failed: %s\n" (error-message-string problem))
          'external-debugging-output)
   (kill-emacs 1)))

;;; emacsvox-remote-check.el ends here
