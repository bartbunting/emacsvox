;;; emacsvox-settings-tests.el --- Settings discovery tests -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Commentary:
;; Exercise real search destinations, captured context, and return paths.
;;; Code:
(require 'emacsvox-capitalization-tests)
(require 'emacsvox-settings)
(defmacro emacsvox-test--with-settings (&rest body)
  "Run BODY from the root menu with an isolated source."
  (declare (indent 0) (debug t))
  `(progn
     (skip-unless (display-graphic-p))
     (save-window-excursion
       (emacsvox-test--with-capitalization
         (let ((transient--prefix nil) (transient--stack nil) (transient-show-menu t))
           (switch-to-buffer source)
           (text-mode)
           (local-set-key (kbd "<f8>") #'emacsvox-aural-menu)
           (unwind-protect
               (progn (execute-kbd-macro (kbd "<f8>")) ,@body)
             (when transient--prefix (execute-kbd-macro (kbd "C-q")))))))))

(ert-deftest emacsvox-settings-menu-search-every-destination ()
  "Every searchable destination opens and selects its actual control."
  (emacsvox-test--with-settings
    (dolist (entry emacsvox-settings--destinations)
      (execute-kbd-macro (vconcat (kbd "/") (car entry) (kbd "RET")))
      (should (eq (oref transient--prefix command) (nth 2 entry)))
      (with-selected-window transient--window
        (should (equal (oref (button-get (button-at (point)) 'button-data) key)
                       (nth 3 entry))))
      (execute-kbd-macro (kbd "q"))
      (should (eq (oref transient--prefix command) 'emacsvox-aural-menu)))
    (should-not (file-exists-p custom-file))))

(ert-deftest emacsvox-settings-search-capitalization-insensitive ()
  "Lowercase prefixes match labels and typed casing preserves the destination."
  (let ((completion-ignore-case nil) opened)
    (cl-letf (((symbol-function 'completing-read)
               (lambda (_prompt collection &rest _)
                 (let ((matches (all-completions "cap" collection)))
                   (should (member "Capital-letter beep" matches))
                   (should (member "Capitalization indication and camel case" matches)))
                 "capital-letter beep"))
              ((symbol-function 'emacsvox-settings--open)
               (lambda (entry) (setq opened entry))))
      (emacsvox-settings-search))
    (should (equal (car opened) "Capital-letter beep"))
    (should-not completion-ignore-case)))

(ert-deftest emacsvox-settings-menu-search-partial-name-and-mixed-case ()
  "Complete a lowercase prefix or accept mixed case without activating a control."
  (emacsvox-test--with-settings
    (let ((completion-ignore-case nil)
          (completion-styles '(basic))
          (completion-category-overrides nil))
      (dolist (input (list (vconcat "cap" (kbd "TAB") "-letter beep" (kbd "RET"))
                           (vconcat "cApItAl-LeTtEr BeEp" (kbd "RET"))))
        (execute-kbd-macro (vconcat (kbd "/") input))
        (should (eq (oref transient--prefix command) 'emacsvox-capitalization))
        (with-selected-window transient--window
          (should (equal (oref (button-get (button-at (point)) 'button-data) key) "l")))
        (should (zerop (hash-table-count emacsvox-capitalization--drafts)))
        (should-not (file-exists-p custom-file))
        (execute-kbd-macro (kbd "q"))
        (should (eq (oref transient--prefix command) 'emacsvox-aural-menu)))
      (should-not completion-ignore-case))))

(ert-deftest emacsvox-settings-menu-search-preserves-source-and-scope ()
  "Search edits the captured source and returns without moving source point."
  (emacsvox-test--with-settings
    (execute-kbd-macro (vconcat (kbd "/") "Indentation pitch and duration" (kbd "RET")))
    (execute-kbd-macro (kbd "RET 5 0 0 RET"))
    (should (= (buffer-local-value 'emacsvox-indentation-pitch-tone-base source) 500))
    (should (= (default-value 'emacsvox-indentation-pitch-tone-base) 250.0))
    (execute-kbd-macro (kbd "q q"))
    (should (eq (current-buffer) source))
    (should (= (point) 3))))

(ert-deftest emacsvox-settings-menu-buffer-mode-and-custom-return ()
  "Buffer discovery starts locally and Customize q returns to its menu."
  (emacsvox-test--with-settings
    (setcdr (plist-get (emacsvox-aural-menu--context) :settings) t)
    (execute-kbd-macro (kbd "."))
    (should-not (cdr (plist-get (emacsvox-aural-menu--context) :settings)))
    (should (eq (emacsvox-settings--mode-group) 'text))
    (execute-kbd-macro (kbd "m"))
    (should (derived-mode-p 'Custom-mode))
    (execute-kbd-macro (kbd "q"))
    (should (eq (oref transient--prefix command) 'emacsvox-settings-buffer))
    (execute-kbd-macro (kbd "i q q"))
    (should (eq (oref transient--prefix command) 'emacsvox-aural-menu))
    (should (cdr (plist-get (emacsvox-aural-menu--context) :settings)))))

(ert-deftest emacsvox-settings-menu-home-action-search-and-return ()
  "Home action search retains its captured item and its return to the menu."
  (emacsvox-test--with-settings
    (execute-kbd-macro (kbd "a S o u n d SPC p a c k s RET"))
    (should (derived-mode-p 'emacsvox-aural-sound-packs-mode))
    (execute-kbd-macro (kbd "q"))
    (should (derived-mode-p 'emacsvox-aural-home-mode))
    (should (eq (emacsvox-aural-inspection-source-buffer) source))
    (should (= emacsvox-aural-ui-source-position 3))
    (execute-kbd-macro (kbd "q"))
    (should (eq (oref transient--prefix command) 'emacsvox-aural-menu))))

(ert-deftest emacsvox-settings-menu-search-cancel-keeps-menu ()
  "Cancelling completion returns to the original menu without a mutation."
  (emacsvox-test--with-settings
    (condition-case nil (execute-kbd-macro (kbd "/ C-g")) (quit nil))
    (should (eq (oref transient--prefix command) 'emacsvox-aural-menu))
    (should (= (with-current-buffer source (point)) 3))
    (should-not (file-exists-p custom-file))))
(provide 'emacsvox-settings-tests)
;;; emacsvox-settings-tests.el ends here
