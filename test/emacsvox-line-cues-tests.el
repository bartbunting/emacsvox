;;; emacsvox-line-cues-tests.el --- Line cue menu tests -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Commentary:
;; Test real navigation, draft persistence, and resolved cue output.
;;; Code:
(require 'emacsvox-capitalization-tests)
(require 'emacsvox-line-cues)

(defmacro emacsvox-test--with-line-cues (&rest body)
  "Open the line cue chooser with isolated personal rules for BODY."
  (declare (indent 0) (debug t))
  `(progn
     (skip-unless (display-graphic-p))
     (save-window-excursion
       (emacsvox-test--with-capitalization
         (let ((emacsvox-line-cues--drafts (make-hash-table :test #'eq))
               (transient--prefix nil) (transient--stack nil) (transient-show-menu t))
           (switch-to-buffer source)
           (local-set-key (kbd "<f8>") #'emacsvox-aural-menu)
           (unwind-protect
               (progn (execute-kbd-macro (kbd "<f8> o c")) ,@body)
             (when transient--prefix (execute-kbd-macro (kbd "C-q")))))))))

(ert-deftest emacsvox-line-cues-menu-tone-drafts-and-output ()
  "Every line tone saves, reloads, silences, and restores independently."
  (emacsvox-test--with-line-cues
    (dolist (choice '(("b" . empty) ("w" . whitespace-only) ("s" . separator)
                      ("d" . decorative) ("u" . unspeakable)))
      (execute-kbd-macro (kbd (concat (car choice) " <down> RET 6 0 0 RET S-<right> <down> RET 2 0 RET S-<right>")))
      (should (equal (emacsvox-line-cues--values) '(625 . 25)))
      (let (plan)
        (cl-letf (((symbol-function 'emacsvox-aural-preview-play-plan) (lambda (p) (setq plan p))))
          (execute-kbd-macro (kbd "SPC")))
        (should (= 625 (emacsvox-aural-concrete-action-pitch
                        (car (emacsvox-aural-concrete-plan-before plan))))))
      (should-not emacsvox-aural-user-rules)
      (execute-kbd-macro (kbd "q"))
      (execute-kbd-macro (kbd (car choice)))
      (should (equal (emacsvox-line-cues--values) '(625 . 25)))
      (execute-kbd-macro (kbd "S"))
      (setq emacsvox-aural-user-rules nil)
      (emacsvox-aural-load-user-data)
      (let* ((facts (list :line-condition (cdr choice)))
             (context (emacsvox-aural-context-at-point))
             (plan (emacsvox-aural-compile-plan
                    (emacsvox-aural-resolve-active facts context) facts context)))
        (should (= 1 (length (emacsvox-aural-concrete-plan-before plan))))
        (should (= 625 (emacsvox-aural-concrete-action-pitch
                        (car (emacsvox-aural-concrete-plan-before plan))))))
      (execute-kbd-macro (kbd "n S"))
      (should-not (emacsvox-aural-render-plan-before
                   (emacsvox-aural-resolve-active (list :line-condition (cdr choice)))))
      (execute-kbd-macro (kbd "r S q"))
      (should-not emacsvox-aural-user-rules))
    (execute-kbd-macro (kbd "q"))
    (should (eq (oref transient--prefix command) 'emacsvox-aural-menu-sounds))))

(ert-deftest emacsvox-line-cues-menu-boundary-rules-and-reset ()
  "Boundary changes use legacy cue selectors and preserve unrelated rules."
  (emacsvox-test--with-line-cues
    (setq emacsvox-aural-user-rules
          '((:id unrelated-line-test :match (:mode text-mode) :render (:content (:voice bolden)))))
    (let ((before (copy-tree emacsvox-aural-user-rules)))
      (execute-kbd-macro (kbd "e e s e l e c t - o b j e c t RET S"))
      (should (equal (car before) (car emacsvox-aural-user-rules)))
      (let ((actions (emacsvox-aural-render-plan-before
                      (emacsvox-aural-resolve-legacy-icon 'warn-user))))
        (should (= (length actions) 1))
        (should (eq (emacsvox-aural-action-cue (car actions)) 'select-object)))
      (execute-kbd-macro (kbd "n S"))
      (should-not (emacsvox-aural-render-plan-before
                   (emacsvox-aural-resolve-legacy-icon 'warn-user)))
      (execute-kbd-macro (kbd "r S"))
      (should (equal before emacsvox-aural-user-rules)))))

(ert-deftest emacsvox-line-cues-menu-validation-conflicts-and-discard ()
  "Bad entries and save conflicts retain the draft and existing rules."
  (emacsvox-test--with-line-cues
    (execute-kbd-macro (kbd "b <down> RET 5 0 0 RET"))
    (dolist (invalid '(0 -1 1.0e+INF 0.0e+NaN))
      (cl-letf (((symbol-function 'read-number) (lambda (&rest _) invalid)))
        (should-error (emacsvox-line-cues--pitch) :type 'user-error)))
    (should (= (car (emacsvox-line-cues--values)) 500))
    (cl-letf (((symbol-function 'emacsvox-aural-save-user-data)
               (lambda (&rest _) (error "Injected failure"))))
      (should-error (emacsvox-line-cues--save)))
    (should-not emacsvox-aural-user-rules)
    (with-temp-buffer
      (setq-local emacsvox-aural-editor-scope 'personal emacsvox-aural-editor-dirty t)
      (should-error (emacsvox-line-cues--save) :type 'user-error))
    (setq emacsvox-aural-user-rules (emacsvox-line-cues--rules 'empty '(700 . 30)))
    (should-error (emacsvox-line-cues--save) :type 'user-error)
    (execute-kbd-macro (kbd "D"))
    (should (equal (emacsvox-line-cues--values) '(700 . 30)))))

(provide 'emacsvox-line-cues-tests)
;;; emacsvox-line-cues-tests.el ends here
