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

(ert-deftest emacsvox-line-cues-shared-editor-session-save-and-roundtrip ()
  "All five conditions retain full tone data without changing other rules."
  (emacsvox-test--with-capitalization
    (let ((emacsvox-line-cues--drafts (make-hash-table :test #'eq)))
      (dolist (kind '(empty whitespace-only separator decorative unspeakable))
        (let* ((draft (emacsvox-line-cues--draft kind))
               (transient--prefix
                (transient-prefix :command 'emacsvox-line-cues-edit
                                  :scope (plist-put (copy-sequence context) :cue-draft draft))))
          (cl-letf (((symbol-function 'transient-setup)
                     (lambda (command &rest args)
                       (setq transient--prefix
                             (transient-prefix :command command :scope (plist-get (nthcdr 2 args) :scope))))))
            (emacsvox-line-cues--edit-tone))
          (emacsvox-tone-editor--put :waveform 'triangle)
          (emacsvox-tone-editor--put :volume 40)
          (emacsvox-tone-editor--put :pitch 600)
          (let ((before (copy-tree draft)) plan)
            (cl-letf (((symbol-function 'emacsvox-aural-preview-play-plan)
                       (lambda (p) (setq plan p))))
              (emacsvox-tone-editor--tone))
            (should (equal before draft))
            (should (= 0.4 (emacsvox-aural-concrete-action-requested-volume
                            (car (emacsvox-aural-concrete-plan-before plan))))))
          (emacsvox-tone-editor--apply)
          (should (emacsvox-line-cues--session kind))
          (should-not (emacsvox-line-cues--saved kind))
          (let* ((facts (list :line-condition kind))
                 (context (emacsvox-aural-context-at-point))
                 (plan (emacsvox-aural-compile-plan
                        (emacsvox-aural-resolve-active facts context) facts context))
                 (tone (car (emacsvox-aural-concrete-plan-before plan))))
            (should (= 600 (emacsvox-aural-concrete-action-pitch tone)))
            (should (= 0.4 (emacsvox-aural-concrete-action-requested-volume tone)))
            (should (equal '(:waveform triangle) (emacsvox-aural-concrete-action-shape tone))))
          (emacsvox-tone-editor--save)
          (should-not (emacsvox-line-cues--session kind))
          (should (emacsvox-line-cues--saved kind))
          (should (equal (plist-get draft :value)
                         (emacsvox-line-cues--rule-value kind (emacsvox-line-cues--saved kind))))))
      (let ((saved (copy-tree emacsvox-aural-user-rules)))
        (setq emacsvox-aural-user-rules nil)
        (emacsvox-aural-load-user-data)
        (should (equal saved emacsvox-aural-user-rules))))))

(ert-deftest emacsvox-line-cues-session-reset-overrides-saved-rule ()
  "Session edits can coexist with a saved rule; reset reveals the factory tone."
  (emacsvox-test--with-capitalization
    (let* ((emacsvox-line-cues--drafts (make-hash-table :test #'eq))
           (emacsvox-aural-user-rules (emacsvox-line-cues--rules 'empty '(800 . 80)))
           (draft (emacsvox-line-cues--draft 'empty))
           (transient--prefix
            (transient-prefix :command 'emacsvox-line-cues-edit
                              :scope (plist-put (copy-sequence context) :cue-draft draft))))
      (setf (plist-get draft :value) '(600 . 60))
      (emacsvox-line-cues--commit nil)
      (should (equal (emacsvox-line-cues--rule-value 'empty (emacsvox-line-cues--saved 'empty)) '(800 . 80)))
      (let* ((facts '(:line-condition empty))
             (context (emacsvox-aural-context-at-point))
             (pitch (lambda ()
                      (emacsvox-aural-concrete-action-pitch
                       (car (emacsvox-aural-concrete-plan-before
                             (emacsvox-aural-compile-plan
                              (emacsvox-aural-resolve-active facts context) facts context)))))))
        (should (= 600 (funcall pitch)))
        (setf (plist-get draft :value) 'bundled)
        (emacsvox-line-cues--commit nil)
        (should (= (emacsvox-aural-tone-pitch (emacsvox-aural-tone 'line-empty)) (funcall pitch)))
        (emacsvox-line-cues--commit t)
        (should-not (emacsvox-line-cues--saved 'empty))
        (should-not (emacsvox-line-cues--session 'empty))))))

(ert-deftest emacsvox-line-cues-menu-shared-editor-return-and-cancel ()
  "The shared editor returns to its entry and cancellation leaves rules alone."
  (emacsvox-test--with-line-cues
    (execute-kbd-macro (kbd "b E p 6 0 0 RET q"))
    (should (eq (oref transient--prefix command) 'emacsvox-line-cues-edit))
    (should (eq (emacsvox-test--menu-focused-command) 'emacsvox-line-cues--edit-tone))
    (should-not emacsvox-aural-session-rules)
    (should-not emacsvox-aural-user-rules)
    (execute-kbd-macro (kbd "E p 6 0 0 RET A q"))
    (should (equal (emacsvox-line-cues--values) '(600 . 150)))
    (should (emacsvox-line-cues--session 'empty))
    (should-not emacsvox-aural-user-rules)
    (execute-kbd-macro (kbd "S"))
    (should-not emacsvox-aural-session-rules)
    (should (emacsvox-line-cues--saved 'empty))))

(ert-deftest emacsvox-sound-library-menu-graphical-return-focus ()
  "The library opened from settings returns to its own menu control."
  (emacsvox-test--with-line-cues
    (require 'emacsvox-sound-library)
    (let ((emacsvox-sound-library-directory (make-temp-file "library-menu-" t)))
      (unwind-protect
          (progn
            (execute-kbd-macro (kbd "q l"))
            (should (derived-mode-p 'emacsvox-sound-library-mode))
            (execute-kbd-macro (kbd "q"))
            (should (eq (oref transient--prefix command) 'emacsvox-aural-menu-sounds))
            (should (eq (emacsvox-test--menu-focused-command) 'emacsvox-aural-menu--sound-library)))
        (when (get-buffer "*Sound Library*") (kill-buffer "*Sound Library*"))
        (delete-directory emacsvox-sound-library-directory t)))))

(provide 'emacsvox-line-cues-tests)
;;; emacsvox-line-cues-tests.el ends here
