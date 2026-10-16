;;; emacsvox-interaction-tests.el --- Interaction menu tests -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Exercise scoped behavior, preview source ownership, phonetics, and persistence.
;;; Code:
(require 'ert)
(require 'emacsvox-aural-menu-tests)
(require 'emacsvox-interaction)

(defmacro emacsvox-test--with-interaction (&rest body)
  "Run BODY with isolated interaction settings and a graphical menu."
  (declare (indent 0) (debug t))
  `(progn
     (skip-unless (display-graphic-p))
     (save-window-excursion
       (emacsvox-test--with-aural-menu
         (let* ((directory (make-temp-file "interaction-menu-" t))
                (custom-file (expand-file-name "custom.el" directory))
                (user-init-file custom-file)
                (symbols (append emacsvox-interaction--scoped-options
                                 '(emacsvox-delayed-phonetic-mode emacsvox-delayed-phonetic-delay)))
                (defaults (mapcar (lambda (s) (cons s (default-value s))) symbols))
                (properties (mapcar (lambda (s) (cons s (copy-tree (symbol-plist s)))) symbols))
                (was-enabled emacsvox-delayed-phonetic-mode)
                (transient--prefix nil) (transient-show-menu t))
           (unwind-protect
               (cl-letf (((symbol-function 'emacsvox-icon) #'ignore))
                 (dolist (symbol emacsvox-interaction--scoped-options)
                   (set-default symbol nil)
                   (set (make-local-variable symbol) nil))
                 (set-default 'emacsvox-show-point-presentation 'voice)
                 (setq-local emacsvox-show-point-presentation 'voice)
                 (customize-set-variable 'emacsvox-delayed-phonetic-delay 1.0)
                 (emacsvox-delayed-phonetic-mode 1)
                 (switch-to-buffer source)
                 (local-set-key (kbd "<f8>") #'emacsvox-aural-menu)
                 (execute-kbd-macro (kbd "<f8> s t"))
                 ,@body)
             (when transient--prefix (execute-kbd-macro (kbd "C-q")))
             (dolist (entry defaults) (set-default (car entry) (cdr entry)))
             (dolist (entry properties) (setplist (car entry) (cdr entry)))
             (emacsvox-delayed-phonetic-mode (if was-enabled 1 -1))
             (when (get-file-buffer custom-file) (kill-buffer (get-file-buffer custom-file)))
             (delete-directory directory t)))))))

(ert-deftest emacsvox-interaction-menu-graphical-scope-and-echo ()
  "Echo and message controls retain independent scope and affect actual typing."
  (emacsvox-test--with-interaction
    (execute-kbd-macro (kbd "c w l i m"))
    (dolist (symbol '(emacsvox-character-echo emacsvox-word-echo emacsvox-line-echo
                     emacsvox-show-point emacsvox-speak-messages))
      (should (buffer-local-value symbol source))
      (should-not (default-value symbol)))
    (execute-kbd-macro (kbd "g"))
    (should-not (emacsvox-interaction--value 'emacsvox-character-echo))
    ;; Global toggle starts from the displayed default, even with a local override.
    (execute-kbd-macro (kbd "c"))
    (should (default-value 'emacsvox-character-echo))
    (should (buffer-local-value 'emacsvox-character-echo source))
    (with-temp-buffer (should emacsvox-character-echo) (should-not emacsvox-word-echo))
    (execute-kbd-macro (kbd "g m"))
    (should-not (buffer-local-value 'emacsvox-speak-messages source))
    (let (spoken)
      (cl-letf (((symbol-function 'emacsvox-aural-submit)
                 (lambda (text &rest _) (push text spoken))))
        (execute-kbd-macro (kbd "c c")))
      (should (member "Character echo: on" spoken)))
    (execute-kbd-macro (kbd "q q q"))
    (should-not transient--prefix)
    (should (eq (current-buffer) source))
    (should (= (point) 3))
    (let (letters words)
      (cl-letf (((symbol-function 'tts-letter) (lambda (text) (push text letters)))
                ((symbol-function 'emacsvox-speak-word)
                 (lambda (&rest _) (push (thing-at-point 'word t) words))))
        (goto-char (point-max))
        (insert "word")
        (let ((last-command-event ?d) (executing-kbd-macro nil) (noninteractive nil))
          (emacsvox-post-self-insert-hook))
        (insert " ")
        (let ((last-command-event ?\s) (executing-kbd-macro nil) (noninteractive nil))
          (emacsvox-post-self-insert-hook)))
      (should (equal letters '("d")))
      (should (equal words '("word"))))))

(ert-deftest emacsvox-interaction-menu-graphical-preview-and-source ()
  "Point previews use the displayed scope and captured item without moving point."
  (emacsvox-test--with-interaction
    (execute-kbd-macro (kbd "i p t"))
    (should (eq (buffer-local-value 'emacsvox-show-point-presentation source) 'tone))
    (let (seen)
      (cl-letf (((symbol-function 'emacsvox-aural-submit)
                 (lambda (text &rest _) (setq seen text))))
        (execute-kbd-macro (kbd "SPC")))
      (should (equal (substring-no-properties seen) "first item"))
      (should (eq (plist-get (get-text-property 2 emacsvox-aural-facts-property seen)
                            :point-presentation) 'tone)))
    (execute-kbd-macro (kbd "g"))
    (let (seen)
      (cl-letf (((symbol-function 'emacsvox-aural-submit)
                 (lambda (text &rest _) (setq seen text))))
        (execute-kbd-macro (kbd "SPC")))
      (should-not (plist-get (get-text-property 2 emacsvox-aural-facts-property seen)
                             :point-presentation)))
    (should (buffer-local-value 'emacsvox-show-point source))
    (with-current-buffer source (goto-char 15))
    (let (seen)
      (cl-letf (((symbol-function 'tts-speak) (lambda (text) (setq seen text))))
        (execute-kbd-macro (kbd "P")))
      (should (equal seen "romeo")))
    (should (= (with-current-buffer source (point)) 15))
    (execute-kbd-macro (kbd "q"))
    (should (cdr (plist-get (emacsvox-aural-menu--context) :settings)))))

(ert-deftest emacsvox-interaction-menu-graphical-phonetics-delay-and-focus ()
  "Global phonetics retain cancellation hooks; numeric entry retains focus."
  (emacsvox-test--with-interaction
    (should (memq #'emacsvox--delayed-phonetic-cancel pre-command-hook))
    (setq emacsvox--delayed-phonetic-request '(pending))
    (execute-kbd-macro (kbd "f"))
    (should-not emacsvox-delayed-phonetic-mode)
    (should-not emacsvox--delayed-phonetic-request)
    (should-not (memq #'emacsvox--delayed-phonetic-cancel pre-command-hook))
    (execute-kbd-macro (kbd "f d 0 . 5 RET S-<right>"))
    (should emacsvox-delayed-phonetic-mode)
    (should (= emacsvox-delayed-phonetic-delay 0.6))
    (setq emacsvox--delayed-phonetic-request '(pending))
    ;; Direct invocation checks the setter, independently of pre-command cancellation.
    (emacsvox-interaction--delay -0.1)
    (should-not emacsvox--delayed-phonetic-request)
    (should (= emacsvox-delayed-phonetic-delay 0.5))
    (execute-kbd-macro (kbd "g d 0 . 1 RET"))
    (let (spoken)
      (cl-letf (((symbol-function 'emacsvox-aural-submit)
                 (lambda (text &rest _) (setq spoken text))))
        (execute-kbd-macro (kbd "S-<left>")))
      (should (equal spoken "Minimum. 0.1 seconds")))
    (execute-kbd-macro (kbd "RET 0 . 7 RET S-<left>"))
    (should (= emacsvox-delayed-phonetic-delay 0.6))
    (dolist (invalid '(0 -1 1.0e+INF 0.0e+NaN))
      (cl-letf (((symbol-function 'read-number) (lambda (&rest _) invalid)))
        (should-error (emacsvox-interaction--delay) :type 'user-error)))
    (should (= emacsvox-delayed-phonetic-delay 0.6))
    (should-not (file-exists-p custom-file))
    (let (stopped)
      (cl-letf (((symbol-function 'tts-stop) (lambda () (setq stopped t))))
        (execute-kbd-macro (kbd "s")))
      (should stopped))))

(ert-deftest emacsvox-interaction-menu-graphical-defaults-survive-startup ()
  "Explicit Save persists scoped choices and global mode settings before loading Lisp."
  (emacsvox-test--with-interaction
    (execute-kbd-macro (kbd "c w l i m p t f d 0 . 5 RET"))
    (should-not (file-exists-p custom-file))
    (execute-kbd-macro (kbd "S"))
    (with-temp-buffer
      (let ((program (expand-file-name invocation-name invocation-directory)))
        (should (zerop
                 (call-process
                  program nil t nil "-Q" "--batch"
                  "--eval" (format "(load %S nil t)" custom-file)
                  "-L" emacsvox-lisp-directory "-l" "emacsvox-preamble" "-l" "emacsvox-speak"
                  "--eval"
                  "(prin1 (mapcar #'default-value '(emacsvox-character-echo emacsvox-word-echo emacsvox-line-echo emacsvox-show-point emacsvox-show-point-presentation emacsvox-speak-messages emacsvox-delayed-phonetic-mode emacsvox-delayed-phonetic-delay)))")))
        (should (string-match-p "(t t t t tone t nil 0.5)" (buffer-string)))))))

(provide 'emacsvox-interaction-tests)
;;; emacsvox-interaction-tests.el ends here
