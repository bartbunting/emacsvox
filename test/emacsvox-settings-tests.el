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

(ert-deftest emacsvox-settings-search-substrings-and-aliases ()
  "Search labels and aliases consistently without duplicate or arbitrary choices."
  (let ((completion-ignore-case nil)
        (completion-styles '(basic))
        (completion-category-defaults '((emacsvox-settings (styles basic))))
        (completion-category-overrides '((emacsvox-settings (styles basic))))
        opened)
    (cl-letf (((symbol-function 'completing-read)
               (lambda (_prompt table &rest _)
                 (dolist (case '(("cap" "Capitalization indication and camel case"
                                  "Capital-letter beep" "All-caps beep" "Spatial capabilities")
                                 ("CAPS BEEP" "Capital-letter beep" "All-caps beep")
                                 ("allcaps" "All-caps beep")
                                 ("allcaps beep" "All-caps beep")
                                 ("all caps" "All-caps beep")
                                 ("pitch and" "Indentation pitch and duration")
                                 ("[")))
                   (let ((matches (completion-all-completions
                                   (car case) table nil (length (car case)))))
                     ;; Completion styles append the replacement base position.
                     (when matches (setcdr (last matches) nil))
                     (should (equal (sort matches #'string-lessp)
                                    (sort (copy-sequence (cdr case)) #'string-lessp)))))
                 (should (equal (completion-try-completion "cap" table nil 3)
                                '("cap" . 3)))
                 (should (equal (completion-try-completion "allcaps" table nil 7)
                                '("All-caps beep" . 13)))
                 "All-caps beep"))
              ((symbol-function 'emacsvox-settings--open)
               (lambda (entry) (setq opened entry))))
      (emacsvox-settings-search))
    (should (equal (car opened) "All-caps beep"))
    (should (equal completion-styles '(basic)))
    (should (equal completion-category-defaults '((emacsvox-settings (styles basic)))))
    (should (equal completion-category-overrides '((emacsvox-settings (styles basic)))))
    (should-not completion-ignore-case)))

(ert-deftest emacsvox-settings-menu-search-partial-name-and-mixed-case ()
  "Complete a lowercase prefix or accept mixed case without activating a control."
  (emacsvox-test--with-settings
    (let ((completion-ignore-case nil)
          (completion-styles '(basic))
          (completion-category-overrides nil))
      (dolist (input (list (vconcat "capital-l" (kbd "TAB RET"))
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

(ert-deftest emacsvox-settings-menu-search-alias-and-substring-selection ()
  "Real completion accepts an alias or inner words and focuses without activation."
  (emacsvox-test--with-settings
    (let ((completion-styles '(basic)))
      ;; Both ambiguous searches must remain in the prompt until a choice is made.
      (execute-kbd-macro
       (vconcat (kbd "/") "cap" (kbd "TAB C-a C-k")
                "caps beep" (kbd "TAB C-a C-k") "ALLCAPS" (kbd "TAB RET")))
      (should (eq (oref transient--prefix command) 'emacsvox-capitalization))
      (with-selected-window transient--window
        (should (equal (oref (button-get (button-at (point)) 'button-data) key) "a")))
      (should (zerop (hash-table-count emacsvox-capitalization--drafts)))
      (execute-kbd-macro (kbd "q"))
      (execute-kbd-macro (vconcat (kbd "/") "pitch and" (kbd "TAB RET")))
      (should (eq (oref transient--prefix command) 'emacsvox-indentation-tone))
      (with-selected-window transient--window
        (should (equal (oref (button-get (button-at (point)) 'button-data) key) "b")))
      (should-not (file-exists-p custom-file))
      (execute-kbd-macro (kbd "q"))
      (should (eq (oref transient--prefix command) 'emacsvox-aural-menu))
      (should (equal completion-styles '(basic))))))

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

(ert-deftest emacsvox-settings-menu-action-search-and-return ()
  "Partial action search focuses a control, then opens it without visiting Home."
  (emacsvox-test--with-settings
    (cl-letf (((symbol-function 'emacsvox-aural)
               (lambda () (interactive) (error "Unexpected Home entry"))))
      (execute-kbd-macro (kbd "a p a c k s RET"))
      (should (eq (oref transient--prefix command) 'emacsvox-aural-menu-sounds))
      (with-selected-window transient--window
        (should (eq (oref (button-get (button-at (point)) 'button-data) command)
                    'emacsvox-aural-menu--sound-packs)))
      (execute-kbd-macro (kbd "RET"))
      (should (derived-mode-p 'emacsvox-aural-sound-packs-mode))
      (execute-kbd-macro (kbd "q"))
      (should (eq (oref transient--prefix command) 'emacsvox-aural-menu-sounds))
      (should (eq (emacsvox-aural-menu--source (emacsvox-aural-menu--context)) source))
      (execute-kbd-macro (kbd "q"))
      (should (eq (oref transient--prefix command) 'emacsvox-aural-menu)))))

(ert-deftest emacsvox-settings-actions-cover-home-without-activation ()
  "Every named Home action and alias has a passive focused-menu destination."
  (require 'emacsvox-aural-home)
  (emacsvox-test--with-settings
    (should-not (seq-find (lambda (suffix) (equal (oref suffix key) "h"))
                         transient--suffixes))
    (with-selected-window transient--window
      (should-not (string-match-p "Aural Home" (buffer-string))))
    (dolist (row (emacsvox-aural-home--all-entries))
      (should (emacsvox-settings--search-matches
               (aref (cadr row) 0) emacsvox-settings--actions nil)))
    (cl-letf (((symbol-function 'emacsvox-aural)
               (lambda () (interactive) (error "Unexpected Home entry"))))
      (dolist (entry emacsvox-settings--actions)
        (execute-kbd-macro (vconcat (kbd "a") (car entry) (kbd "RET")))
        (should (eq (oref transient--prefix command) (nth 2 entry)))
        (with-selected-window transient--window
          (should (equal (oref (button-get (button-at (point)) 'button-data) key)
                         (nth 3 entry))))
        (execute-kbd-macro (kbd "q"))
        (should (eq (oref transient--prefix command) 'emacsvox-aural-menu))))
    (should-not (file-exists-p custom-file))))

(ert-deftest emacsvox-settings-action-aliases-have-one-destination ()
  "Old names resolve to one displayed action, including mixed-case substrings."
  (let ((destinations (mapcar #'cdr emacsvox-settings--actions)))
    (should (= (length destinations) (length (delete-dups destinations)))))
  (dolist (case '(("Feedback for this item" "Explain this item")
                  ("recent AURAL" "Recent feedback")
                  ("MANUAL" "Read the Emacsvox manual")))
    (should (equal (emacsvox-settings--search-matches
                    (car case) emacsvox-settings--actions nil)
                   (cdr case))))
  (emacsvox-test--with-settings
    (dolist (case '(("Feedback for this item" emacsvox-settings-feedback "x")
                    ("Recent aural feedback" emacsvox-settings-feedback "h")
                    ("MANUAL" emacsvox-aural-menu "i")))
      (execute-kbd-macro (vconcat (kbd "a") (car case) (kbd "RET")))
      (should (eq (oref transient--prefix command) (nth 1 case)))
      (with-selected-window transient--window
        (should (equal (oref (button-get (button-at (point)) 'button-data) key)
                       (nth 2 case))))
      (should-not (derived-mode-p 'Info-mode))
      (execute-kbd-macro (kbd "q"))
      (should (eq (oref transient--prefix command) 'emacsvox-aural-menu)))
    ;; Search selects the manual first; the second Enter opens it.
    (execute-kbd-macro (kbd "a m a n u a l RET RET"))
    (should (derived-mode-p 'Info-mode))
    (execute-kbd-macro (kbd "q q"))
    (should (eq (oref transient--prefix command) 'emacsvox-aural-menu))
    (should (eq (emacsvox-aural-menu--source (emacsvox-aural-menu--context)) source))
    (should-not (file-exists-p custom-file))))

(ert-deftest emacsvox-settings-search-literal-spaces-and-prompt-isolation ()
  "Space preserves typed queries in both searches and leaves other prompts alone."
  (emacsvox-test--with-settings
    (let ((original-map minibuffer-local-must-match-map)
          (original-space (lookup-key minibuffer-local-must-match-map (kbd "SPC"))))
      (dolist (case '(("/" "all caps " "All-caps beep")
                      ("a" "Feedback for " "Explain this item")))
        (let (typed)
          (minibuffer-with-setup-hook
              (lambda ()
                (use-local-map (copy-keymap (current-local-map)))
                (local-set-key
                 (kbd "<f9>")
                 (lambda () (interactive)
                   (setq typed (minibuffer-contents-no-properties))
                   (delete-minibuffer-contents)
                   (insert (nth 2 case))
                   (exit-minibuffer))))
            (execute-kbd-macro (vconcat (kbd (car case)) (cadr case) (kbd "<f9>"))))
          (should (equal typed (cadr case)))
          (execute-kbd-macro (kbd "q"))
          (should (eq (oref transient--prefix command) 'emacsvox-aural-menu))))
      (should (eq original-map minibuffer-local-must-match-map))
      (should (equal original-space (lookup-key original-map (kbd "SPC"))))
      (let (ordinary-space)
        (minibuffer-with-setup-hook
            (lambda ()
              (setq ordinary-space (key-binding (kbd "SPC")))
              (signal 'quit nil))
          (condition-case nil
              (completing-read "Unrelated prompt: " '("one two") nil t)
            (quit nil)))
        (should (equal ordinary-space original-space)))
      (should-not (file-exists-p custom-file)))))

(ert-deftest emacsvox-settings-return-source-restores-captured-position ()
  "The explicit source action leaves all menus and restores the captured point."
  (emacsvox-test--with-settings
    (with-current-buffer source (goto-char (point-max)))
    (execute-kbd-macro (kbd "a R e t u r n SPC t o SPC s o u r c e RET"))
    (execute-kbd-macro (kbd "RET"))
    (should-not transient--prefix)
    (should-not transient--stack)
    (should (eq (current-buffer) source))
    (should (= (point) 3))))

(ert-deftest emacsvox-settings-menu-search-cancel-keeps-menu ()
  "Cancelling completion returns to the original menu without a mutation."
  (emacsvox-test--with-settings
    (dolist (key '("/ C-g" "a C-g"))
      (condition-case nil (execute-kbd-macro (kbd key)) (quit nil))
      (should (eq (oref transient--prefix command) 'emacsvox-aural-menu)))
    (should (eq (oref transient--prefix command) 'emacsvox-aural-menu))
    (should (= (with-current-buffer source (point)) 3))
    (should-not (file-exists-p custom-file))))
(provide 'emacsvox-settings-tests)
;;; emacsvox-settings-tests.el ends here
