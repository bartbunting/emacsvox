;;; emacsvox-windows-startup.el --- Native isolated startup -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Commentary:
;; Paths and check selection are environment data from the PowerShell launcher.
;;; Code:
(let ((settings (json-parse-string
                 (decode-coding-string
                  (base64-decode-string (getenv "EMACSVOX_NATIVE_SETTINGS")) 'utf-8))))
  (setenv "EMACSVOX_DIR" (gethash "Root" settings))
  (setq user-emacs-directory (file-name-as-directory (gethash "Profile" settings))
        tts-program (gethash "Omnivox" settings))
  (setenv "TTS_PROGRAM" tts-program)
  (setenv "ESPEAK_NG_DATA" (expand-file-name "espeak-ng-data" (file-name-directory tts-program)))
  (setenv "EMACSVOX_NATIVE_RESULT" (let ((result (gethash "Result" settings)))
                                     (and (stringp result) result))))

(defun emacsvox-windows-check ()
  "Check fresh graphical startup, both routing acknowledgements and speech."
  (let ((result (getenv "EMACSVOX_NATIVE_RESULT")))
    (condition-case problem
        (progn
          (unless (eq window-system 'w32) (error "A native Windows GUI is required"))
          (let ((deadline (+ (float-time) 45)))
            (while (and (< (float-time) deadline)
                        (not (and (process-live-p tts-speaker-process)
                                  (process-live-p tts-notify-process)
                                  (process-get tts-speaker-process omnivox--control-registration-property)
                                  (process-get tts-notify-process omnivox--control-registration-property))))
              (accept-process-output nil 0.05)))
          (dolist (lane `((,tts-speaker-process . "Native Windows foreground speech is ready.")
                          (,tts-notify-process . "Native Windows notification speech is ready.")))
            (unless (and (process-live-p (car lane))
                         (process-get (car lane) omnivox--control-inventory-property)
                         (process-get (car lane) omnivox--control-registration-property))
              (error "Native speech inventory or routing is not ready"))
            (let ((tts-speaker-process (car lane)) status
                  (deadline (+ (float-time) 30)))
              (tts--protocol-queue-text (cdr lane))
              (tts--protocol-dispatch-tracked (lambda (_ value) (setq status value)))
              (while (and (not status) (< (float-time) deadline))
                (accept-process-output nil 0.05))
              (unless (eq status 'completed) (error "Native speech failed: %s" status))))
          (with-temp-file result
            (insert "PASS: fresh Windows GUI startup, both inventories, routing and speech completion.\n"))
          (kill-emacs 0))
      (error
       (with-temp-file result (insert (error-message-string problem)))
       (kill-emacs 1)))))

(when (getenv "EMACSVOX_NATIVE_RESULT")
  (add-hook 'emacs-startup-hook (lambda () (run-at-time 2 nil #'emacsvox-windows-check))))
(condition-case problem
    (load (expand-file-name "lisp/emacsvox-setup.el" (getenv "EMACSVOX_DIR")) nil t)
  (error
   (when (getenv "EMACSVOX_NATIVE_RESULT")
     (with-temp-file (getenv "EMACSVOX_NATIVE_RESULT") (insert (error-message-string problem)))
     (kill-emacs 1))
   (signal (car problem) (cdr problem))))
;;; emacsvox-windows-startup.el ends here
