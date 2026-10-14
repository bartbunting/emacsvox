;;; emacsvox-output-settings-tests.el --- Output menu tests -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Commentary:
;; Exercise explicit restart/save, spatial compilation, and history return.
;;; Code:
(require 'emacsvox-capitalization-tests)
(require 'emacsvox-output-settings)
(defmacro emacsvox-test--with-output-settings (&rest body)
  "Run BODY in the output menu with isolated global defaults."
  (declare (indent 0) (debug t))
  `(progn
     (skip-unless (display-graphic-p))
     (save-window-excursion
       (emacsvox-test--with-capitalization
         (let* ((symbols emacsvox-output-settings--options)
                (defaults (mapcar (lambda (s) (cons s (default-value s))) symbols))
                (properties (mapcar (lambda (s) (cons s (copy-tree (symbol-plist s)))) symbols))
                (transient--prefix nil) (transient--stack nil) (transient-show-menu t)
                (restarts 0))
           (unwind-protect
               (cl-letf (((symbol-function 'tts-restart) (lambda () (cl-incf restarts))))
                 (dolist (s symbols) (set-default s (eval (car (get s 'standard-value)) t)))
                 (switch-to-buffer source)
                 (local-set-key (kbd "<f8>") #'emacsvox-aural-menu)
                 (execute-kbd-macro (kbd "<f8> o n"))
                 ,@body)
             (when transient--prefix (execute-kbd-macro (kbd "C-q")))
             (dolist (entry defaults) (set-default (car entry) (cdr entry)))
             (dolist (entry properties) (setplist (car entry) (cdr entry)))))))))

(ert-deftest emacsvox-output-settings-menu-route-save-restart ()
  "Routing changes and Save never restart; explicit restart honours cancellation."
  (emacsvox-test--with-output-settings
    (execute-kbd-macro (kbd "r M a i n SPC o u t p u t RET e s c o m o n o RET m r e v e r s e RET d 0 . 5 RET S-<right>"))
    (should (equal tts-notification-device "default"))
    (should (= emacsvox-aural-spatial-maximum-separation 0.6))
    (should-not (file-exists-p custom-file))
    (execute-kbd-macro (kbd "S"))
    (should (zerop restarts))
    (with-temp-buffer
      (should (zerop (call-process (expand-file-name invocation-name invocation-directory) nil t nil
                                   "-Q" "--batch" "--eval" (format "(load %S nil t)" custom-file)
                                   "-L" emacsvox-lisp-directory "-l" "emacsvox-preamble"
                                   "-l" "emacsvox-aural-spatial" "--eval"
                                   "(prin1 (mapcar #'default-value '(tts-notification-device emacsvox-aural-spatial-enabled emacsvox-aural-spatial-speech-enabled emacsvox-aural-spatial-cue-enabled emacsvox-aural-spatial-output emacsvox-aural-spatial-remapping emacsvox-aural-spatial-maximum-separation)))")))
      (should (string-match-p "(\"default\" nil nil nil mono reverse 0.6)" (buffer-string))))
    (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) nil)))
      (execute-kbd-macro (kbd "R")))
    (should (zerop restarts))
    (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
      (execute-kbd-macro (kbd "R")))
    (should (= restarts 1))
    (execute-kbd-macro (kbd "q"))
    (should (eq (oref transient--prefix command) 'emacsvox-aural-menu-sounds))))

(ert-deftest emacsvox-output-settings-menu-spatial-preview-and-bounds ()
  "Spatial preview compiles the displayed mapping and rejects invalid separation."
  (emacsvox-test--with-output-settings
    (execute-kbd-macro (kbd "d 0 . 5 RET m r e v e r s e RET"))
    (dolist (invalid '(-1 2 1.0e+INF 0.0e+NaN))
      (cl-letf (((symbol-function 'read-number) (lambda (&rest _) invalid)))
        (should-error (emacsvox-output-settings--separation) :type 'user-error)))
    (let (plan)
      (cl-letf (((symbol-function 'emacsvox-sounds-spatial-capability) (lambda () 'stereo))
                ((symbol-function 'emacsvox-aural-preview-play-plan) (lambda (p) (setq plan p))))
        (execute-kbd-macro (kbd "SPC")))
      (let ((actions (emacsvox-aural-concrete-plan-before plan)))
        (should (= (emacsvox-aural-concrete-action-balance (car actions)) 0.5))
        (should (= (emacsvox-aural-concrete-action-balance (nth 2 actions)) -0.5))))
    (execute-kbd-macro (kbd "d 0 RET S-<left>"))
    (should (= emacsvox-aural-spatial-maximum-separation 0.0))
    (execute-kbd-macro (kbd "RET 1 RET S-<right>"))
    (should (= emacsvox-aural-spatial-maximum-separation 1.0))
    (should (zerop restarts))))

(ert-deftest emacsvox-output-settings-menu-history-and-active-preview ()
  "Notification preview uses the active route; history q restores the menu."
  (emacsvox-test--with-output-settings
    (let ((emacsvox-notifications-buffer (generate-new-buffer " *test notifications*"))
          seen)
      (unwind-protect
          (progn
            (with-current-buffer emacsvox-notifications-buffer (insert "Recorded notification\n"))
            (cl-letf (((symbol-function 'tts-notify) (lambda (text &optional no-log) (setq seen (list text no-log)))))
              (execute-kbd-macro (kbd "N")))
            (should (equal seen '("Notification output sample" t)))
            (execute-kbd-macro (kbd "h"))
            (should (string-match-p "Recorded notification" (buffer-string)))
            (execute-kbd-macro (kbd "q"))
            (should (eq (oref transient--prefix command) 'emacsvox-output-settings))
            (with-selected-window transient--window
              (should (eq (oref (button-get (button-at (point)) 'button-data) command)
                          'emacsvox-output-settings--history))))
        (kill-buffer emacsvox-notifications-buffer)
        (when (get-buffer "*Emacsvox Notification History*")
          (kill-buffer "*Emacsvox Notification History*"))))))
(provide 'emacsvox-output-settings-tests)
;;; emacsvox-output-settings-tests.el ends here
