;;; emacsvox-settings-workflows-tests.el --- Linked workflow tests -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Commentary:
;; Check real editor return and captured source ownership.
;;; Code:
(require 'emacsvox-settings-tests)
(require 'emacsvox-settings-workflows)
(require 'emacsvox-aural-change-feedback-tests)

(ert-deftest emacsvox-settings-workflows-feedback-draft-return ()
  "A guided draft previews without saving and returns to its exact menu entry."
  (emacsvox-test--with-settings
    (let* ((facts '(:role heading :content "Example heading"))
           (context '(:mode org-mode :occasion navigation))
           (render (emacsvox-aural-resolve-active facts context))
           (concrete (emacsvox-aural-compile-plan render facts context))
           editor)
      (cl-letf (((symbol-function 'emacsvox-aural-tools--remap-source-input)
                 (lambda (&optional _)
                   (list :source source :facts facts :context context :render render :concrete concrete))))
        (execute-kbd-macro (kbd "f c")))
      (setq editor (current-buffer))
      (unwind-protect
          (progn
            (should (derived-mode-p 'emacsvox-aural-change-feedback-mode))
            (emacsvox-test--guided-choose "Change the content voice" "bolden")
            (should (emacsvox-test--guided-proposed))
            (should-not emacsvox-aural-user-rules)
            (execute-kbd-macro (kbd "q q q"))
            (should (eq (oref transient--prefix command) 'emacsvox-settings-feedback))
            (with-selected-window transient--window
              (should (eq (oref (button-get (button-at (point)) 'button-data) command)
                          'emacsvox-settings-workflows--change)))
            (should (buffer-local-value 'emacsvox-aural-change-feedback-render editor))
            (execute-kbd-macro (kbd "q q"))
            (should (eq (current-buffer) source))
            (should (= (point) 3)))
        (when (buffer-live-p editor) (kill-buffer editor))))))

(ert-deftest emacsvox-settings-workflows-reject-replaced-item ()
  "Captured-item editing rejects replaced source content before opening a draft."
  (emacsvox-test--with-settings
    (execute-kbd-macro (kbd "f"))
    (with-current-buffer source (erase-buffer) (insert "replacement"))
    (should-error (emacsvox-settings-workflows--change) :type 'user-error)))
(ert-deftest emacsvox-settings-workflows-rule-scopes-and-return ()
  "Each rule route owns its advertised scope and returns to its exact entry."
  (emacsvox-test--with-settings
    (execute-kbd-macro (kbd "r"))
    (dolist (entry '(("p" personal emacsvox-settings-workflows--personal)
                     ("s" session emacsvox-settings-workflows--session)
                     ("b" buffer emacsvox-settings-workflows--buffer)))
      (execute-kbd-macro (kbd (car entry)))
      (should (derived-mode-p 'emacsvox-aural-scheme-editor-mode))
      (should (eq emacsvox-aural-editor-scope (cadr entry)))
      (should (eq emacsvox-aural-editor-target source))
      (execute-kbd-macro (kbd "q"))
      (should (eq (oref transient--prefix command) 'emacsvox-settings-presentation))
      (with-selected-window transient--window
        (should (eq (oref (button-get (button-at (point)) 'button-data) command)
                    (nth 2 entry)))))
    (should-not (file-exists-p custom-file))))

(ert-deftest emacsvox-settings-workflows-face-save-is-explicit ()
  "Face feedback changes immediately; only the explicit save writes Customize."
  (emacsvox-test--with-settings
    (let ((emacsvox-aural-face-presentation-enabled t))
      (execute-kbd-macro (kbd "r v"))
      (should-not emacsvox-aural-face-presentation-enabled)
      (should-not (file-exists-p custom-file))
      (execute-kbd-macro (kbd "w"))
      (should (file-exists-p custom-file))
      (with-temp-buffer
        (insert-file-contents custom-file)
        (should (search-forward "emacsvox-aural-face-presentation-enabled nil" nil t))))))

(provide 'emacsvox-settings-workflows-tests)
;;; emacsvox-settings-workflows-tests.el ends here
