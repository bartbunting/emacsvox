;;; emacsvox-aural-menu-tests.el --- Linked aural menu tests -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Cover source ownership and real linked-menu navigation.

;;; Code:
(require 'ert)
(require 'emacsvox-aural-menu)
(require 'emacsvox-indentation-tests)
(require 'emacsvox-aural-voice-workbench-tests)

(defmacro emacsvox-test--with-aural-menu (&rest body)
  "Run BODY with an isolated source and captured menu context."
  (declare (indent 0) (debug t))
  `(emacsvox-test--with-indentation-menu
     (insert "first item\nsecond item\n")
     (goto-char 3)
     (let* ((context (emacsvox-aural-menu--capture nil))
            (transient--prefix
             (transient-prefix :command 'emacsvox-aural-menu :scope context)))
       (cl-letf (((symbol-function 'tts-speak) #'ignore))
         ,@body))))

(ert-deftest emacsvox-aural-menu-captured-item-preserves-point-and-restriction ()
  "Item commands follow their marker without moving or widening the source."
  (emacsvox-test--with-aural-menu
    (goto-char 1)
    (insert "new\n")
    (goto-char (point-max))
    (narrow-to-region (line-beginning-position) (point-max))
    (let ((old-point (point)) (old-min (point-min)) observed)
      (with-temp-buffer
        (emacsvox-aural-menu--call-at-item
         (lambda () (interactive)
           (setq observed (list (current-buffer) (point)
                                (buffer-substring (line-beginning-position)
                                                  (line-end-position)))))))
      (should (equal observed (list source 7 "first item")))
      (should (= (point) old-point))
      (should (= (point-min) old-min)))))

(ert-deftest emacsvox-aural-menu-captures-interface-source-not-interface-point ()
  "Opening from an existing interface retains its source marker and guard."
  (emacsvox-test--with-aural-menu
    (goto-char (point-max))
    (with-temp-buffer
      (setq-local emacsvox-aural-ui-interface-buffer t
                  emacsvox-aural-ui-source-buffer source
                  emacsvox-aural-ui-source-position (plist-get context :position)
                  emacsvox-aural-ui-source-guard (plist-get context :guard))
      (let ((captured (emacsvox-aural-menu--capture t)))
        (should (eq (plist-get captured :source) source))
        (should (= (plist-get captured :position) 3))
        (should (cdr (plist-get captured :settings)))))))

(ert-deftest emacsvox-aural-menu-rejects-replaced-item-and-dead-source ()
  "Invalid targets cannot execute contextual actions or change settings."
  (emacsvox-test--with-aural-menu
    (let (called)
      (erase-buffer)
      (insert "first item\nsecond item\n")
      (should-error
       (emacsvox-aural-menu--call-at-item
        (lambda () (interactive) (setq called t))) :type 'user-error)
      (should-not called)
      (kill-buffer source)
      (should-error (emacsvox-aural-menu--feedback) :type 'user-error)
      (should-error (emacsvox-aural-menu--indentation) :type 'user-error)
      (should-error (emacsvox-aural-menu--toggle-scope) :type 'user-error)
      (should-not (cdr (plist-get context :settings))))))

(ert-deftest emacsvox-aural-menu-graphical-links-scope-and-refresh ()
  "Submenus share scope and retain local settings while global values change."
  (skip-unless (display-graphic-p))
  (save-window-excursion
    (emacsvox-test--with-aural-menu
      (switch-to-buffer source)
      (local-set-key (kbd "<f8>") #'emacsvox-aural-menu)
      (let ((transient--prefix nil) (transient-show-menu 0)
            (transient-history nil) (transient-values nil)
            (transient-save-history nil) (transient-history-file nil))
        (unwind-protect
            (progn
              (execute-kbd-macro (kbd "<f8> s i p b q"))
              (should (eq (oref transient--prefix command) 'emacsvox-aural-menu-speech))
              (transient--show)
              (with-current-buffer (window-buffer transient--window)
                (should (string-match-p "Indentation: off, pitch tone" (buffer-string))))
              (should (eq (buffer-local-value 'emacsvox-indentation-tone-timing source) 'insert))
              (execute-kbd-macro (kbd "g i d q"))
              (should (equal (emacsvox-aural-menu--scope-label) "Global defaults"))
              (should (eq (default-value 'emacsvox-indentation-presentation) 'duration-tone))
              (should (eq (buffer-local-value 'emacsvox-indentation-presentation source) 'pitch-tone))
              ;; A scope change in the leaf also updates its parents.
              (execute-kbd-macro (kbd "i g q q"))
              (should (eq (oref transient--prefix command) 'emacsvox-aural-menu))
              (should (equal (emacsvox-aural-menu--scope-label) "Current buffer"))
              (execute-kbd-macro (kbd "s i C-q"))
              (should-not transient--prefix)
              (should-not transient--stack)
              (should (eq (current-buffer) source))
              (should (= (point) 3))
              (execute-kbd-macro (kbd "C-u <f8> s i"))
              (should (cdr (emacsvox-indentation--state))))
          (when transient--prefix (execute-kbd-macro (kbd "C-q"))))))))

(ert-deftest emacsvox-aural-menu-graphical-direct-speech-and-button-entry ()
  "Speech settings opens directly; button activation links to Indentation."
  (skip-unless (display-graphic-p))
  (save-window-excursion
    (emacsvox-test--with-aural-menu
      (switch-to-buffer source)
      (local-set-key (kbd "<f8>") #'emacsvox-aural-menu-speech)
      (let ((transient--prefix nil) (transient-show-menu 0)
            (transient-save-history nil) (transient-history-file nil))
        (unwind-protect
            (progn
              (execute-kbd-macro (kbd "C-u <f8>"))
              (should-not transient--stack)
              (transient--show)
              (execute-kbd-macro (kbd "<down> <down> C-j"))
              (should (eq (oref transient--prefix command) 'emacsvox-indentation))
              (should (cdr (emacsvox-indentation--state)))
              (execute-kbd-macro (kbd "q q"))
              (should-not transient--prefix)
              (should (= (point) 3)))
          (when transient--prefix (execute-kbd-macro (kbd "C-q"))))))))

(ert-deftest emacsvox-aural-menu-graphical-enter-activates-focused-item ()
  "Enter follows submenus and activates settings without editing the source."
  (skip-unless (display-graphic-p))
  (save-window-excursion
    (emacsvox-test--with-aural-menu
      (switch-to-buffer source)
      (local-set-key (kbd "<f8>") #'emacsvox-aural-menu)
      (let ((transient--prefix nil) (transient-show-menu 0)
            (original (buffer-string))
            spoken)
        (cl-letf (((symbol-function 'emacsvox-aural-submit)
                   (lambda (text &rest _) (push text spoken))))
          (unwind-protect
              (progn
                (execute-kbd-macro (kbd "<f8>"))
                (transient--show)
                (should (seq-some (lambda (text) (string-match-p "Enter: activate" text)) spoken))
                (execute-kbd-macro (kbd "<down> RET"))
                (should (eq (oref transient--prefix command) 'emacsvox-aural-menu-speech))
                (transient--show)
                (execute-kbd-macro (kbd "<down> <down> <return>"))
                (should (eq (oref transient--prefix command) 'emacsvox-indentation))
                (transient--show)
                (execute-kbd-macro (kbd "<down> <down> RET"))
                (should (emacsvox-indentation--value 'emacsvox-audio-indentation))
                (execute-kbd-macro (kbd "M-RET"))
                (should-not (emacsvox-indentation--value 'emacsvox-audio-indentation))
                (execute-kbd-macro (kbd "C-j"))
                (should (emacsvox-indentation--value 'emacsvox-audio-indentation))
                (execute-kbd-macro (kbd "q q q"))
                (should-not transient--prefix)
                (should (eq (current-buffer) source))
                (should (equal (buffer-string) original))
                (should (= (point) 3)))
            (when transient--prefix (execute-kbd-macro (kbd "C-q")))))))))

(ert-deftest emacsvox-aural-menu-graphical-navigation-style-and-save ()
  "Navigation choices apply immediately and save independently of scope."
  (skip-unless (display-graphic-p))
  (let* ((original-style emacsvox-transient-navigation-style)
         (original-order emacsvox-transient-section-announcement-order)
         (original-verbose emacsvox-transient-verbose-descriptions)
         (properties (copy-tree (symbol-plist 'emacsvox-transient-navigation-style)))
         (order-properties (copy-tree (symbol-plist 'emacsvox-transient-section-announcement-order)))
         (verbose-properties (copy-tree (symbol-plist 'emacsvox-transient-verbose-descriptions)))
         (custom-file (make-temp-file "emacsvox-navigation-custom-"))
         (user-init-file custom-file))
    (unwind-protect
        (save-window-excursion
          (emacsvox-test--with-aural-menu
            (switch-to-buffer source)
            (setq emacsvox-transient-navigation-style 'continuous)
            (setq emacsvox-transient-section-announcement-order 'item-first)
            (setq emacsvox-transient-verbose-descriptions nil)
            (local-set-key (kbd "<f8>") #'emacsvox-aural-menu)
            (let ((transient--prefix nil) (transient-show-menu 0))
              (unwind-protect
                  (progn
                    (execute-kbd-macro (kbd "<f8> s n"))
                    (should (eq (oref transient--prefix command) 'emacsvox-aural-menu-navigation))
                    (transient--show)
                    (execute-kbd-macro (kbd "<down> <down> RET"))
                    (should (eq emacsvox-transient-navigation-style 'section-wrap))
                    (with-current-buffer (window-buffer transient--window)
                      (should (string-match-p "Wrap within section (selected)" (buffer-string))))
                    (execute-kbd-macro (kbd "n"))
                    (should (eq emacsvox-transient-section-announcement-order 'section-first))
                    (with-current-buffer (window-buffer transient--window)
                      (should (string-match-p "Section first (selected)" (buffer-string))))
                    (execute-kbd-macro (kbd "i"))
                    (should (eq emacsvox-transient-section-announcement-order 'item-first))
                    (execute-kbd-macro (kbd "m"))
                    (should (eq emacsvox-transient-section-announcement-order 'by-movement))
                    (with-current-buffer (window-buffer transient--window)
                      (should (string-match-p "By movement: sections or items (selected)" (buffer-string))))
                    ;; Section-only speech keeps Enter on the first choice.
                    (execute-kbd-macro (kbd "<right> RET"))
                    (should (eq emacsvox-transient-section-announcement-order 'item-first))
                    (execute-kbd-macro (kbd "m"))
                    (execute-kbd-macro (kbd "s v S q"))
                    (should emacsvox-transient-verbose-descriptions)
                    (should (eq emacsvox-transient-navigation-style 'section-stop))
                    (should (eq (oref transient--prefix command) 'emacsvox-aural-menu-speech))
                    (should (equal (emacsvox-aural-menu--scope-label) "Current buffer"))
                    (setq emacsvox-transient-navigation-style 'continuous)
                    (setq emacsvox-transient-section-announcement-order 'item-first)
                    (setq emacsvox-transient-verbose-descriptions nil)
                    (load custom-file nil t)
                    (should (eq emacsvox-transient-navigation-style 'section-stop))
                    (should (eq emacsvox-transient-section-announcement-order 'by-movement))
                    (should emacsvox-transient-verbose-descriptions)
                    (execute-kbd-macro (kbd "n v c q q q"))
                    (should-not emacsvox-transient-verbose-descriptions)
                    (should (eq emacsvox-transient-navigation-style 'continuous))
                    (should-not transient--prefix)
                    (should (eq (current-buffer) source))
                    (should (= (point) 3)))
                (when transient--prefix (execute-kbd-macro (kbd "C-q")))))))
      (setq emacsvox-transient-navigation-style original-style)
      (setq emacsvox-transient-section-announcement-order original-order)
      (setq emacsvox-transient-verbose-descriptions original-verbose)
      (setplist 'emacsvox-transient-navigation-style properties)
      (setplist 'emacsvox-transient-section-announcement-order order-properties)
      (setplist 'emacsvox-transient-verbose-descriptions verbose-properties)
      (delete-file custom-file))))

(ert-deftest emacsvox-aural-menu-graphical-detailed-descriptions ()
  "All settings items have readable help; detail preserves values and feedback."
  (skip-unless (display-graphic-p))
  (save-window-excursion
    (emacsvox-test--with-aural-menu
      (switch-to-buffer source)
      (local-set-key (kbd "<f8>") #'emacsvox-aural-menu)
      (let ((emacsvox-transient-verbose-descriptions nil)
            (transient-show-menu t)
            speech)
        (cl-letf (((symbol-function 'emacsvox-aural-submit)
                   (lambda (text &rest _) (push text speech))))
          (cl-labels
              ((check-items
                (keys)
                (let ((contents (with-current-buffer (window-buffer transient--window)
                                  (buffer-string))))
                  (dolist (key keys)
                    (let* ((object (seq-find (lambda (obj) (equal (oref obj key) key))
                                             transient--suffixes))
                           (documentation (and object (documentation (oref object command) t)))
                           (summary (and documentation (car (split-string documentation "\n")))))
                      (ert-info ((format "%s item %s" (oref transient--prefix command) key))
                        (should (and summary (not (string-empty-p summary))))
                        (should (string-match-p
                                 (regexp-quote (string-remove-suffix "." summary))
                                 contents))))))))
            (unwind-protect
                (progn
                  (execute-kbd-macro (kbd "<f8> s n v"))
                  (should emacsvox-transient-verbose-descriptions)
                  (should (equal (car speech) "Detailed descriptions on"))
                  (check-items '("c" "w" "s" "i" "n" "v" "S" "q" "C-q"))
                  (with-current-buffer (window-buffer transient--window)
                    (should (string-match-p "Wrap within section (selected)" (buffer-string)))
                    (should (string-match-p "Detailed descriptions: on" (buffer-string))))
                  (execute-kbd-macro (kbd "q"))
                  (check-items '("g" "i" "n" "q" "C-q"))
                  (execute-kbd-macro (kbd "i"))
                  (check-items '("g" "e" "s" "p" "d" "P" "D" "c" "n" "b" "a"
                                 "v" "-" "+" "SPC" "S" "q"))
                  (execute-kbd-macro (kbd "<down> <down>"))
                  (should (string-match-p "Turn indentation feedback" (car speech)))
                  (with-current-buffer (window-buffer transient--window)
                    (should (string-match-p "Volume: [0-9]+ percent" (buffer-string))))
                  (execute-kbd-macro (kbd "+"))
                  (should (string-match-p "\\`[0-9]+ percent\\'" (car speech)))
                  (execute-kbd-macro (kbd "? p"))
                  (should (string-match-p "Use a higher pitch" (buffer-string)))
                  (execute-kbd-macro (kbd "q q q"))
                  (check-items '("s" "x" "D" "q"))
                  (execute-kbd-macro (kbd "s n v"))
                  (should-not emacsvox-transient-verbose-descriptions)
                  (should (equal (car speech) "Detailed descriptions off"))
                  (with-current-buffer (window-buffer transient--window)
                    (should-not (string-match-p "Cycle up/down within" (buffer-string)))))
              (when transient--prefix (execute-kbd-macro (kbd "C-q"))))))))))

(ert-deftest emacsvox-aural-menu-graphical-feedback-opens-real-details ()
  "Feedback returns to its menu with the original item and selected scope."
  (skip-unless (display-graphic-p))
  (require 'emacsvox-aural-explanation)
  (save-window-excursion
    (emacsvox-test--with-aural-menu
      (switch-to-buffer source)
      (local-set-key (kbd "<f8>") #'emacsvox-aural-menu)
      (let ((transient--prefix nil) (transient-show-menu 0)
            (transient-save-history nil) (transient-history-file nil)
            (feedback-command (symbol-function 'emacsvox-aural-menu--feedback))
            details observed menu-context announcements)
        (unwind-protect
            (cl-letf (((symbol-function 'emacsvox-aural-menu--feedback)
                       (lambda ()
                         (interactive)
                         ;; Feedback Details intentionally suppresses its UI in
                         ;; keyboard macros. Model a physical keypress here.
                         (let ((executing-kbd-macro nil))
                           (call-interactively feedback-command))))
                      ((symbol-function 'emacsvox-aural-explanation--read-explanation-input)
                       (lambda (_)
                         (setq observed (list (current-buffer) (point)))
                         '((:role heading) (:mode text-mode :occasion inspection)))))
              (execute-kbd-macro (kbd "C-u <f8> s q"))
              (setq menu-context (emacsvox-aural-menu--context))
              (with-current-buffer source (goto-char 15))
              (execute-kbd-macro (kbd "x"))
              (setq details (current-buffer))
              (should (derived-mode-p 'emacsvox-aural-feedback-details-mode))
              (should emacsvox-aural-feedback-outline-mode)
              (should outline-minor-mode)
              (should-not transient--prefix)
              (should-not transient--stack)
              (should (equal observed (list source 3)))
              (should (eq emacsvox-aural-ui-help-origin-buffer source))
              (should (= emacsvox-aural-ui-source-position 3))
              (should (= (with-current-buffer source (point)) 15))
              (should emacsvox-aural-ui--help-return-function)
              ;; Another menu can be used while the report remains open.
              (local-set-key (kbd "<f9>") #'emacsvox-indentation)
              (execute-kbd-macro (kbd "<f9> C-q"))
              (should (eq (current-buffer) details))
              (cl-letf (((symbol-function 'emacsvox-aural-submit)
                         (lambda (_text &rest args)
                           (push (plist-get (plist-get args :facts) :events)
                                 announcements))))
                (execute-kbd-macro (kbd "q")))
              (should (eq (current-buffer) source))
              (should (= (point) 3))
              (should (eq (emacsvox-aural-menu--context) menu-context))
              (should (cdr (plist-get menu-context :settings)))
              (should (equal announcements '((command-menu-opened))))
              (should (buffer-live-p details))
              (should-not (buffer-local-value 'emacsvox-aural-ui--help-return-function details))
              (execute-kbd-macro (kbd "q"))
              (should-not transient--prefix)
              ;; Reusing the report through a direct command clears its return.
              (execute-kbd-macro (kbd "<f8> x"))
              (when (and (buffer-live-p details) (not (eq details (current-buffer))))
                (kill-buffer details))
              (setq details (current-buffer))
              (let ((record emacsvox-aural-feedback-details--record))
                (should emacsvox-aural-ui--help-return-function)
                (with-current-buffer source
                  (emacsvox-aural-feedback-details--open record t)))
              (should-not emacsvox-aural-ui--help-return-function)
              (execute-kbd-macro (kbd "q"))
              (should (eq (current-buffer) source))
              (should-not transient--prefix)
              ;; Closing the source while reading must not revive a dead menu.
              (execute-kbd-macro (kbd "<f8> x"))
              (when (and (buffer-live-p details) (not (eq details (current-buffer))))
                (kill-buffer details))
              (setq details (current-buffer))
              (kill-buffer source)
              (execute-kbd-macro (kbd "q"))
              (should-not transient--prefix)
              (should-not (eq (current-buffer) details)))
          (when transient--prefix (execute-kbd-macro (kbd "C-q")))
          (when (and details (buffer-live-p details) (not (eq details source)))
            (kill-buffer details)))))))

(ert-deftest emacsvox-aural-menu-graphical-quit-announces-return-buffer ()
  "Closing announces the source once; returning to a parent speaks its menu."
  (skip-unless (display-graphic-p))
  (save-window-excursion
    (emacsvox-test--with-aural-menu
      (switch-to-buffer source)
      (local-set-key (kbd "<f8>") #'emacsvox-aural-menu)
      (let ((transient--prefix nil) (transient-show-menu 0)
            (transient-save-history nil) (transient-history-file nil)
            closures)
        (cl-letf (((symbol-function 'emacsvox-aural-submit)
                   (lambda (text &rest args)
                     (when (memq 'command-menu-closed
                                 (plist-get (plist-get args :facts) :events))
                       (push (list text (current-buffer)) closures)))))
          (unwind-protect
              (progn
                (dolist (keys '("q" "C-g" "s i C-q"
                                "<right> <right> <right> <right> <down> C-j"))
                  (execute-kbd-macro (kbd "<f8>"))
                  (transient--show)
                  (setq closures nil)
                  (execute-kbd-macro (kbd keys))
                  (should-not transient--prefix)
                  (should (= (length closures) 1))
                  (should (eq (cadar closures) source))
                  (should (string-prefix-p (buffer-name source) (caar closures))))
                (execute-kbd-macro (kbd "<f8> s i"))
                (setq closures nil)
                (execute-kbd-macro (kbd "q"))
                (should (eq (oref transient--prefix command) 'emacsvox-aural-menu-speech))
                (should-not closures)
                (execute-kbd-macro (kbd "q"))
                (should (eq (oref transient--prefix command) 'emacsvox-aural-menu))
                (should-not closures)
                (execute-kbd-macro (kbd "q"))
                (should-not transient--prefix)
                (should (= (length closures) 1)))
            (when transient--prefix (execute-kbd-macro (kbd "C-q")))))))))

(ert-deftest emacsvox-aural-menu-graphical-task-sections ()
  "Section arrows announce task groups and Enter opens the selected control."
  (skip-unless (display-graphic-p))
  (save-window-excursion
    (emacsvox-test--with-aural-menu
      (switch-to-buffer source)
      (local-set-key (kbd "<f8>") #'emacsvox-aural-menu)
      (dolist (style '(continuous section-wrap section-stop))
        (let ((transient--prefix nil) (transient-show-menu t)
              (emacsvox-transient-navigation-style style)
              (emacsvox-transient-section-announcement-order 'by-movement)
              (emacsvox-transient-verbose-descriptions nil)
              speech)
          (cl-letf (((symbol-function 'emacsvox-aural-submit)
                     (lambda (text &rest _) (push text speech))))
            (unwind-protect
                (progn
                  (execute-kbd-macro (kbd "C-u <f8>"))
                  (transient--show)
                  (dolist (section '(("This buffer and item" "." 2)
                                     ("Rules and saved work" "r" 3)
                                     ("Find and get help" "/" 4)
                                     ("Finish" "b" 5)))
                    (setq speech nil)
                    (execute-kbd-macro (kbd "<right>"))
                    (should (equal speech
                                   (list (format "%s. %s of 5 sections."
                                                 (car section) (nth 2 section)))))
                    (with-selected-window transient--window
                      (should (equal (oref (button-get (button-at (point)) 'button-data) key)
                                     (cadr section)))))
                  (execute-kbd-macro (kbd "<left> <left> <left> <left>"))
                  (should (equal (car speech) "Everyday settings. 1 of 5 sections."))
                  ;; Read the first item without moving, then activate it.
                  (execute-kbd-macro (kbd "<right> C-u 0 <down>"))
                  (should (equal (car speech) "Settings for this buffer. .."))
                  (execute-kbd-macro (kbd "RET"))
                  (should (eq (oref transient--prefix command) 'emacsvox-settings-buffer))
                  (execute-kbd-macro (kbd "q"))
                  (should (eq (oref transient--prefix command) 'emacsvox-aural-menu))
                  (should (cdr (plist-get (emacsvox-aural-menu--context) :settings)))
                  (with-selected-window transient--window
                    (should (equal (oref (button-get (button-at (point)) 'button-data) key) ".")))
                  (should (string-match-p "Settings for this buffer" (car speech)))
                  (execute-kbd-macro (kbd "RET"))
                  (should (eq (oref transient--prefix command) 'emacsvox-settings-buffer))
                  (execute-kbd-macro (kbd "q"))
                  (execute-kbd-macro (kbd "q"))
                  (should (eq (current-buffer) source))
                  (should (= (point) 3)))
              (when transient--prefix (execute-kbd-macro (kbd "C-q"))))))))))

(ert-deftest emacsvox-aural-menu-graphical-submenu-return-targets ()
  "Nested shortcuts restore their own entries, including delayed parent display."
  (skip-unless (display-graphic-p))
  (save-window-excursion
    (emacsvox-test--with-aural-menu
      (switch-to-buffer source)
      (local-set-key (kbd "<f8>") #'emacsvox-aural-menu)
      (let ((transient--prefix nil) (transient-show-menu t))
        (cl-labels ((check-key (key)
                     (transient--show)
                     (with-selected-window transient--window
                       (should (equal (oref (button-get (button-at (point)) 'button-data) key)
                                      key)))))
          (unwind-protect
              (progn
                (execute-kbd-macro (kbd "<f8>"))
                (transient--show)
                (execute-kbd-macro (kbd "<right>"))
                (check-key ".")
                ;; The shortcut, rather than the previously focused item, owns return.
                (execute-kbd-macro (kbd "s p C-g"))
                (check-key "p")
                (execute-kbd-macro (kbd "RET"))
                (should (eq (oref transient--prefix command) 'emacsvox-aural-menu-punctuation))
                (let ((transient-show-menu nil))
                  (setq transient--showp nil)
                  (execute-kbd-macro (kbd "q")))
                (check-key "p")
                ;; A later redraw must retain subsequent navigation.
                (execute-kbd-macro (kbd "<up>"))
                (check-key "r")
                (execute-kbd-macro (kbd "q"))
                (check-key "s")
                (execute-kbd-macro (kbd "v C-q <f8>"))
                (transient--show)
                (with-selected-window transient--window
                  (should-not (button-at (point)))))
            (when transient--prefix (execute-kbd-macro (kbd "C-q")))))))))

(ert-deftest emacsvox-aural-menu-graphical-help-returns-to-menu ()
  "Menu overview and command help return with scope and parent menus intact."
  (skip-unless (display-graphic-p))
  (save-window-excursion
    (emacsvox-test--with-aural-menu
      (switch-to-buffer source)
      (local-set-key (kbd "<f8>") #'emacsvox-aural-menu)
      (let ((transient--prefix nil) (transient-show-menu 0)
            (transient-save-history nil) (transient-history-file nil))
        (unwind-protect
            (progn
              (execute-kbd-macro (kbd "C-u <f8>"))
              (let ((context (emacsvox-aural-menu--context)))
                (dolist (keys '("? ?" "? s"))
                  (execute-kbd-macro (kbd keys))
                  (if (equal keys "? ?")
                      (progn
                        (should (derived-mode-p 'emacsvox-transient-mode))
                        (should buffer-read-only)
                        (should (string-match-p "Speech settings: Global defaults" (buffer-string)))
                        (should (string-match-p "Feedback for this item" (buffer-string)))
                        (should (string-match-p "Diagnostics and recovery" (buffer-string)))
                        (should-not (string-match-p "Aural Home" (buffer-string))))
                    (should (derived-mode-p 'help-mode)))
                  (should transient-resume-mode)
                  (execute-kbd-macro (kbd "q"))
                  (should (eq (emacsvox-aural-menu--context) context))
                  (should (eq (current-buffer) source))))
              (execute-kbd-macro (kbd "s i p - ? ?"))
              (should (derived-mode-p 'emacsvox-transient-mode))
              (should buffer-read-only)
              (should (string-match-p "Choose indentation feedback" (buffer-string)))
              (should (string-match-p "Pitch tone (selected)" (buffer-string)))
              (should (string-match-p "Volume: 45 percent" (buffer-string)))
              (execute-kbd-macro (kbd "q"))
              (should (eq (oref transient--prefix command) 'emacsvox-indentation))
              (should (cdr (emacsvox-indentation--state)))
              (execute-kbd-macro (kbd "s ? ?"))
              (should (string-match-p "Spoken column (selected)" (buffer-string)))
              (should-not (string-match-p "Pitch tone (selected)" (buffer-string)))
              (execute-kbd-macro (kbd "q"))
              (execute-kbd-macro (kbd "q q q"))
              (should-not transient--prefix)
              (should (eq (current-buffer) source))
              ;; Help before delayed display must not reuse the previous menu.
              (let ((transient-show-menu 60)
                    (emacsvox-transient-cache "Stale menu snapshot"))
                (execute-kbd-macro (kbd "<f8> ? ?"))
                (should (string-match-p "Feedback for this item" (buffer-string)))
                (should-not (string-match-p "Stale menu snapshot" (buffer-string)))
                (execute-kbd-macro (kbd "q q"))
                (should-not transient--prefix)))
          (when transient--prefix (execute-kbd-macro (kbd "C-q"))))))))

(ert-deftest emacsvox-aural-menu-graphical-help-selection-is-spoken ()
  "Entering help selection speaks once without opening or activating an item."
  (skip-unless (display-graphic-p))
  (save-window-excursion
    (emacsvox-test--with-aural-menu
      (switch-to-buffer source)
      (local-set-key (kbd "<f8>") #'emacsvox-aural-menu)
      (let ((transient--prefix nil) (transient-show-menu 0)
            submissions)
        (cl-letf (((symbol-function 'emacsvox-aural-submit)
                   (lambda (content &rest arguments)
                     (push (cons content arguments) submissions))))
          (unwind-protect
              (progn
                (execute-kbd-macro (kbd "<f8>"))
                (transient--show)
                (dolist (keys '(("?" . "?") ("C-h" . "s")))
                  (setq submissions nil)
                  (execute-kbd-macro (kbd (car keys)))
                  (should transient--helpp)
                  (should (eq (current-buffer) source))
                  (should (= (length submissions) 1))
                  (should (equal (caar submissions)
                                 "Help: press an item's key, or question mark for the menu overview."))
                  (should (eq (plist-get (cdar submissions) :lane) 'main))
                  (should (eq (plist-get (cdar submissions) :interruption-policy) 'lane))
                  (should (eq (plist-get (cdar submissions) :delivery-policy) 'replaceable))
                  (setq submissions nil)
                  (execute-kbd-macro (kbd (cdr keys)))
                  (should (derived-mode-p
                           (if (equal (cdr keys) "?")
                               'emacsvox-transient-mode 'help-mode)))
                  (should-not
                   (seq-some (lambda (entry)
                               (string-prefix-p "Help: press" (car entry)))
                             submissions))
                  (execute-kbd-macro (kbd "q"))
                  (should (eq (oref transient--prefix command) 'emacsvox-aural-menu))))
            (when transient--prefix (execute-kbd-macro (kbd "C-q")))))))))

(ert-deftest emacsvox-aural-menu-graphical-first-toggle-does-not-repeat-introduction ()
  "A submenu's first refresh speaks its changed scope, not its introduction."
  (skip-unless (display-graphic-p))
  (save-window-excursion
    (emacsvox-test--with-aural-menu
      (switch-to-buffer source)
      (local-set-key (kbd "<f8>") #'emacsvox-aural-menu)
      (let ((transient--prefix nil) (transient-show-menu 0)
            (transient-save-history nil) (transient-history-file nil)
            spoken)
        (cl-letf (((symbol-function 'emacsvox-aural-submit)
                   (lambda (text &rest _) (push text spoken))))
          (unwind-protect
              (progn
                (execute-kbd-macro (kbd "<f8>"))
                (transient--show)
                (execute-kbd-macro (kbd "s"))
                (should (string-prefix-p "Choose speech settings" (car spoken)))
                (setq spoken nil)
                (execute-kbd-macro (kbd "g"))
                (should (equal spoken '("Editing global defaults")))
                (setq spoken nil)
                (execute-kbd-macro (kbd "g"))
                (should (equal spoken '("Editing current buffer")))
                ;; Re-entering the submenu still introduces it once.
                (execute-kbd-macro (kbd "q"))
                (setq spoken nil)
                (execute-kbd-macro (kbd "s"))
                (should (= (length spoken) 1))
                (should (string-prefix-p "Choose speech settings" (car spoken))))
            (when transient--prefix (execute-kbd-macro (kbd "C-q")))))))))

(defun emacsvox-test--call-with-output-volumes (function)
  "Call FUNCTION with isolated output volumes set to 50 percent."
  (let ((saved (mapcar (lambda (entry)
                        (let ((symbol (car entry)))
                          (list symbol (default-value symbol)
                                (copy-tree (symbol-plist symbol)))))
                      tts--output-volume-settings)))
    (unwind-protect
        (progn
          (dolist (entry saved) (set-default (car entry) 50))
          (funcall function))
      (dolist (entry saved)
        (set-default (car entry) (nth 1 entry))
        (setplist (car entry) (nth 2 entry))))))

(ert-deftest emacsvox-aural-menu-output-bounds-validation-and-explicit-save ()
  "Volume edits are global, bounded, and persist only on explicit Save."
  (emacsvox-test--with-aural-menu
    (emacsvox-test--call-with-output-volumes
     (lambda ()
       (let (saved spoken)
         (cl-letf (((symbol-function 'customize-save-variable)
                    (lambda (symbol value &rest _) (push (cons symbol value) saved)))
                   ((symbol-function 'emacsvox-aural-submit)
                    (lambda (text &rest _) (push text spoken))))
           ;; Global controls remain usable after the captured text changes.
           (erase-buffer)
           (dolist (entry tts--output-volume-settings)
             (let ((symbol (car entry)))
               (emacsvox-aural-menu--output-volume symbol -55)
               (should (= (default-value symbol) 0))
               (emacsvox-aural-menu--output-volume symbol 105)
               (should (= (default-value symbol) 100))
               (cl-letf (((symbol-function 'read-number) (lambda (&rest _) 37)))
                 (emacsvox-aural-menu--output-volume symbol))
               (should (= (default-value symbol) 37))
               (should (equal (car spoken) "37 percent"))
               (cl-letf (((symbol-function 'read-number) (lambda (&rest _) 101)))
                 (should-error (emacsvox-aural-menu--output-volume symbol) :type 'user-error))
               (should (= (default-value symbol) 37))))
           (should-not saved)
           (emacsvox-aural-menu--save-output)
           (should (equal (nreverse saved)
                          (mapcar (lambda (entry) (cons (car entry) 37))
                                  tts--output-volume-settings)))
           (kill-buffer source)
           (should-error (emacsvox-aural-menu--output-volume 'tts-main-tone-volume -5)
                         :type 'user-error)))))))

(ert-deftest emacsvox-aural-menu-output-graphical-adjust-and-return ()
  "Shift adjusts the focused volume; plain arrows move sections; q returns."
  (skip-unless (display-graphic-p))
  (save-window-excursion
    (emacsvox-test--with-aural-menu
      (emacsvox-test--call-with-output-volumes
       (lambda ()
         (switch-to-buffer source)
         (local-set-key (kbd "<f8>") #'emacsvox-aural-menu)
         (let ((transient--prefix nil) (transient-show-menu 0) spoken)
           (cl-letf (((symbol-function 'emacsvox-aural-submit)
                      (lambda (text &rest _) (push text spoken))))
             (unwind-protect
                 (progn
                   (execute-kbd-macro (kbd "C-u <f8> o"))
                   (transient--show)
                   (should (eq (oref transient--prefix command) 'emacsvox-aural-menu-sounds))
                   (should (eq (plist-get (emacsvox-aural-menu--context) :source) source))
                   (should (cdr (plist-get (emacsvox-aural-menu--context) :settings)))
                   (should (string-match-p "Shift left and right: adjust volume"
                                           (emacsvox-transient--opening-text)))
                   (execute-kbd-macro (kbd "<down>"))
                   (setq spoken nil)
                   (execute-kbd-macro (kbd "S-<left> S-<left> S-<right>"))
                   (should (= tts-main-tone-volume 45))
                   (should (equal (reverse spoken) '("45 percent" "40 percent" "45 percent")))
                   (with-current-buffer (window-buffer transient--window)
                     (should (string-match-p "Tones: 45 percent" (buffer-string))))
                   (execute-kbd-macro (kbd "RET RET"))
                   (execute-kbd-macro (kbd "<down> S-<left>"))
                   (should (= tts-main-earcon-volume 45))
                   (execute-kbd-macro (kbd "<right> S-<left> <down> S-<left> <down> S-<left>"))
                   (should (= tts-notification-speech-volume 45))
                   (should (= tts-notification-tone-volume 45))
                   (should (= tts-notification-earcon-volume 45))
                   (execute-kbd-macro (kbd "<right> S-<left>"))
                   (should (string-prefix-p "Not adjustable" (car spoken)))
                   (execute-kbd-macro (kbd "q"))
                   (should (eq (oref transient--prefix command) 'emacsvox-aural-menu))
                   (should (equal (emacsvox-aural-menu--scope-label) "Global defaults"))
                   (should-not (lookup-key transient--transient-map (kbd "S-<left>")))
                   (execute-kbd-macro (kbd "q"))
                   (should (eq (current-buffer) source))
                   (should (= (point) 3)))
               (when transient--prefix (execute-kbd-macro (kbd "C-q")))))))))))

(ert-deftest emacsvox-aural-menu-output-graphical-browser-keeps-source ()
  "Browser quit restores Sounds and output, its parent, and the source."
  (skip-unless (display-graphic-p))
  (require 'emacsvox-aural-sound-packs)
  (save-window-excursion
    (emacsvox-test--with-aural-menu
      (switch-to-buffer source)
      (local-set-key (kbd "<f8>") #'emacsvox-aural-menu)
      (let ((transient--prefix nil) (transient-show-menu 0))
        (unwind-protect
            (progn
              (execute-kbd-macro (kbd "C-u <f8> o p"))
              (should-not transient--prefix)
              (should (derived-mode-p 'emacsvox-aural-sound-packs-mode))
              (should (eq (emacsvox-aural-inspection-source-buffer) source))
              (execute-kbd-macro (kbd "q"))
              (should (eq (oref transient--prefix command) 'emacsvox-aural-menu-sounds))
              (should (cdr (plist-get (emacsvox-aural-menu--context) :settings)))
              (with-selected-window transient--window
                (should (eq (oref (button-get (button-at (point)) 'button-data) command)
                            'emacsvox-aural-menu--sound-packs)))
              (should-not (buffer-local-value 'emacsvox-aural-ui--return-function
                                             (get-buffer "*Aural Sound Packs*")))
              (execute-kbd-macro (kbd "q"))
              (should (eq (oref transient--prefix command) 'emacsvox-aural-menu))
              (should (equal (emacsvox-aural-menu--scope-label) "Global defaults"))
              (execute-kbd-macro (kbd "q"))
              (should-not transient--prefix)
              (should (eq (current-buffer) source))
              (should (= (point) 3))
              ;; Reusing the browser outside a menu must not reopen a menu.
              (call-interactively #'emacsvox-aural-list-sound-packs)
              (execute-kbd-macro (kbd "q"))
              (should-not transient--prefix)
              (should (eq (current-buffer) source)))
          (when transient--prefix (execute-kbd-macro (kbd "C-q")))
          (when (get-buffer "*Aural Sound Packs*")
            (kill-buffer "*Aural Sound Packs*")))))))

(ert-deftest emacsvox-aural-menu-graphical-manual-returns-to-menu ()
  "Info navigation preserves menu return, scope, source, and selection."
  (skip-unless (display-graphic-p))
  (require 'info)
  (save-window-excursion
    (emacsvox-test--with-aural-menu
      (switch-to-buffer source)
      (local-set-key (kbd "<f8>") #'emacsvox-aural-menu)
      (let ((transient--prefix nil) (transient-show-menu 0)
            (info-quit (lookup-key Info-mode-map (kbd "q"))))
        (cl-letf (((symbol-function 'emacsvox-icon) #'ignore)
                  ((symbol-function 'emacsvox-speak-region) #'ignore)
                  ((symbol-function 'emacsvox-speak-buffer) #'ignore))
          (unwind-protect
              (progn
                (execute-kbd-macro (kbd "C-u <f8> i"))
                (should-not transient--prefix)
                (should (derived-mode-p 'Info-mode))
                (should (equal Info-current-node "Top"))
                (should (equal (file-truename Info-current-file)
                               (file-truename
                                (expand-file-name "emacsvox.info" emacsvox-info-directory))))
                (should (eq (key-binding (kbd "i")) #'Info-index))
                (should (eq (emacsvox-aural-inspection-source-buffer) source))
                (execute-kbd-macro (kbd "m Aural SPC Presentation RET"))
                (should (equal Info-current-node "Aural Presentation"))
                (execute-kbd-macro (kbd "q"))
                (should (eq (oref transient--prefix command) 'emacsvox-aural-menu))
                (should (cdr (plist-get (emacsvox-aural-menu--context) :settings)))
                (with-selected-window transient--window
                  (should (eq (oref (button-get (button-at (point)) 'button-data) command)
                              'emacsvox-aural-menu--manual)))
                (should-not (buffer-local-value 'emacsvox-aural-ui--return-function
                                                (get-buffer "*Emacsvox Settings Manual*")))
                ;; Enter follows the restored selection, including on repeat visits.
                (execute-kbd-macro (kbd "RET"))
                (should (derived-mode-p 'Info-mode))
                (should (equal Info-current-node "Top"))
                (execute-kbd-macro (kbd "q"))
                (execute-kbd-macro (kbd "q"))
                (should (eq (current-buffer) source))
                (should (= (point) 3))
                (should (eq (lookup-key Info-mode-map (kbd "q")) info-quit)))
            (when transient--prefix (execute-kbd-macro (kbd "C-q")))
            (when (get-buffer "*Emacsvox Settings Manual*")
              (kill-buffer "*Emacsvox Settings Manual*"))))))))

(ert-deftest emacsvox-aural-menu-graphical-manual-announces-entry ()
  "Opening and reopening the manual announce its text and opening cue once."
  (skip-unless (display-graphic-p))
  (require 'emacsvox-info)
  (save-window-excursion
    (emacsvox-test--with-aural-menu
      (switch-to-buffer source)
      (local-set-key (kbd "<f8>") #'emacsvox-aural-menu)
      (let ((transient--prefix nil) (transient-show-menu 0)
            speech cues)
        (cl-letf (((symbol-function 'emacsvox-icon)
                   (lambda (cue &rest _) (push cue cues)))
                  ((symbol-function 'emacsvox-speak-region)
                   (lambda (start end &rest _)
                     (push (list 'screenfull (current-buffer)
                                 (buffer-substring-no-properties start end)) speech)))
                  ((symbol-function 'emacsvox-speak-buffer)
                   (lambda (&rest _)
                     (push (list 'node (current-buffer)
                                 (buffer-substring-no-properties (point-min) (point-max))) speech))))
          (unwind-protect
              (progn
                (execute-kbd-macro (kbd "<f8>"))
                (dolist (policy '(screenfull node))
                  (let ((emacsvox-info-select-node-speak-chunk policy))
                    (setq speech nil cues nil)
                    (execute-kbd-macro (kbd (if (eq policy 'screenfull) "i" "RET")))
                    (should (derived-mode-p 'Info-mode))
                    (should (= (length speech) 1))
                    (should (eq (caar speech) policy))
                    (should (eq (cadar speech) (current-buffer)))
                    (should (string-match-p "Emacsvox" (nth 2 (car speech))))
                    (should (= (cl-count 'open-object cues) 1))
                    (execute-kbd-macro (kbd "q")))))
            (when transient--prefix (execute-kbd-macro (kbd "C-q")))
            (when (get-buffer "*Emacsvox Settings Manual*")
              (kill-buffer "*Emacsvox Settings Manual*"))))))))

(defun emacsvox-test--call-with-speech-settings (function)
  "Call FUNCTION with isolated speech settings and silent live test processes."
  (let* ((tts-speaker-process (make-pipe-process :name "menu-test-main" :noquery t))
         (tts-notify-process (make-pipe-process :name "menu-test-notify" :noquery t))
         (tts-speech-rate-step 8)
         (defaults (mapcar (lambda (symbol) (cons symbol (default-value symbol)))
                           '(tts-speech-rate tts-punctuation-mode))))
    (unwind-protect
        (cl-letf (((symbol-function 'tts-notify-process) (lambda () tts-notify-process))
                  ((symbol-function 'tts--protocol-set-rate) #'ignore)
                  ((symbol-function 'tts--protocol-set-punctuations) #'ignore)
                  ((symbol-function 'tts--omnivox-program-p) (lambda () t)))
          (set-default 'tts-speech-rate 60)
          (set-default 'tts-punctuation-mode 'some)
          (funcall function))
      (dolist (entry defaults) (set-default (car entry) (cdr entry)))
      (delete-process tts-speaker-process)
      (delete-process tts-notify-process))))

(ert-deftest emacsvox-aural-menu-speech-rate-scope-protocol-and-bounds ()
  "Rate edits use the source scope, notify on global changes, and respect bounds."
  (emacsvox-test--with-aural-menu
    (emacsvox-test--call-with-speech-settings
     (lambda ()
       (let (sent)
         (cl-letf (((symbol-function 'tts--protocol-set-rate)
                    (lambda (rate) (push (list tts-speaker-process rate) sent)))
                   ((symbol-function 'read-number) (lambda (&rest _) 72)))
           (emacsvox-aural-menu--rate)
           (should (= tts-speech-rate 72))
           (should (= (default-value 'tts-speech-rate) 60))
           (should (equal sent (list (list tts-speaker-process 72))))
           (setq sent nil)
           (setcdr (plist-get context :settings) t)
           (emacsvox-aural-menu--rate 1)
           (should (= tts-speech-rate 68))
           (should (= (default-value 'tts-speech-rate) 68))
           (should (equal (reverse sent)
                          (list (list tts-notify-process 68) (list tts-speaker-process 68))))
           (setcdr (plist-get context :settings) nil)
           (setq-local tts-speech-rate "70")
           (emacsvox-aural-menu--rate 1)
           (should (= tts-speech-rate 78))
           (setq-local tts-speech-rate 99)
           (emacsvox-aural-menu--rate 1)
           (should (= tts-speech-rate 100))
           (setq-local tts-speech-rate 1)
           (emacsvox-aural-menu--rate -1)
           (should (= tts-speech-rate 0))
           (cl-letf (((symbol-function 'read-number) (lambda (&rest _) 101)))
             (should-error (emacsvox-aural-menu--rate) :type 'user-error))
           (should (= tts-speech-rate 0))
           (cl-letf (((symbol-function 'tts--omnivox-program-p) (lambda () nil)))
             (setq-local tts-speech-rate 250)
             (emacsvox-aural-menu--rate 1)
             (should (= tts-speech-rate 258)))
           (delete-process tts-speaker-process)
           (should-error (emacsvox-aural-menu--rate 1) :type 'user-error)
           (should (= tts-speech-rate 258))))))))

(ert-deftest emacsvox-aural-menu-speech-punctuation-policy-profile-and-scope ()
  "Punctuation preserves policy reset, profile fallbacks, and existing scope semantics."
  (emacsvox-test--with-aural-menu
    (emacsvox-test--call-with-speech-settings
     (lambda ()
       (let ((tts-punctuation-mode-policy-alist '((fundamental-mode . all))))
         (should (eq (emacsvox-aural-menu--punctuation-value) 'all))
         (should (string-match-p "fundamental-mode policy" (emacsvox-aural-menu--punctuation-label)))
         (emacsvox-aural-menu--set-punctuation 'none)
         (should (eq tts-punctuation-mode-override 'none))
         (should (eq (default-value 'tts-punctuation-mode) 'some))
         (emacsvox-aural-menu--reset-punctuation)
         (should-not tts-punctuation-mode-override)
         (should (eq (emacsvox-aural-menu--punctuation-value) 'all))
         (cl-letf (((symbol-function 'omnivox-punctuation-profiles--read)
                    (lambda () '(profile "coding" all))))
           (emacsvox-aural-menu--choose-punctuation))
         (should (equal tts-punctuation-mode-override '(profile "coding" all)))
         (should (string-match-p "coding.*fallback" (emacsvox-aural-menu--punctuation-label)))
         (setcdr (plist-get context :settings) t)
         (should (eq (emacsvox-aural-menu--punctuation-value) 'some))
         (emacsvox-aural-menu--set-punctuation 'none)
         (should (eq (default-value 'tts-punctuation-mode) 'none))
         (should (eq tts-punctuation-mode-override 'none))
         (should-error (emacsvox-aural-menu--reset-punctuation) :type 'user-error)
         (kill-buffer source)
         (should-error (emacsvox-aural-menu--set-punctuation 'all) :type 'user-error))))))

(ert-deftest emacsvox-aural-menu-speech-graphical-rate-and-punctuation ()
  "Real keys adjust rate, retain prompt focus, and link punctuation with shared scope."
  (skip-unless (display-graphic-p))
  (save-window-excursion
    (emacsvox-test--with-aural-menu
      (emacsvox-test--call-with-speech-settings
       (lambda ()
         (switch-to-buffer source)
         (local-set-key (kbd "<f8>") #'emacsvox-aural-menu)
         (let ((transient--prefix nil) (transient-show-menu t) spoken)
           (cl-letf (((symbol-function 'emacsvox-aural-submit)
                      (lambda (text &rest _) (push text spoken))))
             (unwind-protect
                 (progn
                   (execute-kbd-macro (kbd "<f8> s <down> S-<right>"))
                   (should (string-prefix-p "Not adjustable" (car spoken)))
                   (should (= tts-speech-rate 60))
                   (execute-kbd-macro (kbd "<down> <down>"))
                   (setq spoken nil)
                   (execute-kbd-macro (kbd "S-<right> S-<right> S-<left>"))
                   (should (equal (reverse spoken) '("68" "76" "68")))
                   (should (= tts-speech-rate 68))
                   (should (= (default-value 'tts-speech-rate) 60))
                   (execute-kbd-macro (kbd "RET 7 2 RET S-<left>"))
                   (should (= tts-speech-rate 64))
                   (with-selected-window transient--window
                     (should (string-match-p "Rate: 64" (button-label (button-at (point))))))
                   (execute-kbd-macro (kbd "<down> RET"))
                   (should (eq (oref transient--prefix command) 'emacsvox-aural-menu-punctuation))
                   (should-not (lookup-key transient--transient-map (kbd "S-<right>")))
                   (execute-kbd-macro (kbd "n"))
                   (should (eq tts-punctuation-mode-override 'none))
                   (with-current-buffer (window-buffer transient--window)
                     (should (string-match-p "None (selected)" (buffer-string))))
                   (execute-kbd-macro (kbd "r"))
                   (should-not tts-punctuation-mode-override)
                   (execute-kbd-macro (kbd "g a q"))
                   (should (eq (oref transient--prefix command) 'emacsvox-aural-menu-speech))
                   (should (equal (emacsvox-aural-menu--scope-label) "Global defaults"))
                   (should (eq (default-value 'tts-punctuation-mode) 'all))
                   (with-current-buffer (window-buffer transient--window)
                     (should (string-match-p "Punctuation: all, global default" (buffer-string))))
                   (execute-kbd-macro (kbd "q q"))
                   (should-not transient--prefix)
                   (should (eq (current-buffer) source))
                   (should (= (point) 3)))
               (when transient--prefix (execute-kbd-macro (kbd "C-q")))))))))))

(ert-deftest emacsvox-aural-menu-speech-save-uses-displayed-global-values ()
  "Saving global scope must not promote different buffer overrides."
  (emacsvox-test--with-aural-menu
    (emacsvox-test--call-with-speech-settings
     (lambda ()
       (let (saved)
         (setq-local tts-speech-rate 72 tts-punctuation-mode-override 'none)
         (setcdr (plist-get context :settings) t)
         (cl-letf (((symbol-function 'customize-save-variable)
                    (lambda (symbol value &rest _) (push (cons symbol value) saved))))
           (emacsvox-aural-menu--save-speech))
         (should (equal (reverse saved)
                        '((omnivox-default-speech-rate . 60) (tts-punctuation-mode . some))))
         (should (= tts-speech-rate 72))
         (should (eq tts-punctuation-mode-override 'none)))))))

(ert-deftest emacsvox-aural-menu-speech-graphical-save-survives-startup ()
  "Explicit Save persists the startup rate and named punctuation across Emacs runs."
  (skip-unless (display-graphic-p))
  (require 'omnivox-voices)
  (let* ((custom-file (make-temp-file "emacsvox-speech-custom-" nil ".el"))
         (user-init-file custom-file)
         (symbols '(omnivox-default-speech-rate tts-punctuation-mode))
         (defaults (mapcar (lambda (symbol) (cons symbol (default-value symbol))) symbols))
         (properties (mapcar (lambda (symbol) (cons symbol (copy-tree (symbol-plist symbol)))) symbols)))
    (unwind-protect
        (save-window-excursion
          (emacsvox-test--with-aural-menu
            (emacsvox-test--call-with-speech-settings
             (lambda ()
               (switch-to-buffer source)
               (local-set-key (kbd "<f8>") #'emacsvox-aural-menu)
               (let ((transient--prefix nil) (transient-show-menu t))
                 (unwind-protect
                     (progn
                       (execute-kbd-macro (kbd "<f8> s r 7 2 RET p n q"))
                       (should (zerop (file-attribute-size (file-attributes custom-file))))
                       (execute-kbd-macro (kbd "S"))
                       (should (= (default-value 'tts-speech-rate) 72))
                       (should (= omnivox-default-speech-rate 72))
                       (should (eq (default-value 'tts-punctuation-mode) 'none))
                       (should (eq (oref transient--prefix command) 'emacsvox-aural-menu-speech))
                       (execute-kbd-macro (kbd "p"))
                       (cl-letf (((symbol-function 'omnivox-punctuation-profiles--read)
                                  (lambda () '(profile "coding" all))))
                         (execute-kbd-macro (kbd "p")))
                       (execute-kbd-macro (kbd "S q q q"))
                       (should (= omnivox-default-speech-rate 72))
                       (should (equal (default-value 'tts-punctuation-mode) '(profile "coding" all)))
                       (should-not transient--prefix)
                       ;; Load Custom before the libraries, as an init file can.
                       ;; Adapter setup must not overwrite the saved rate.
                       (with-temp-buffer
                         (let ((status
                                (call-process
                                 (expand-file-name invocation-name invocation-directory)
                                 nil (current-buffer) nil "-Q" "--batch"
                                 "--eval" (prin1-to-string `(load ,custom-file nil t))
                                 "-L" emacsvox-lisp-directory
                                 "-l" "emacsvox-preamble.el"
                                 "--eval"
                                 (prin1-to-string
                                  '(progn
                                     (require 'omnivox-voices)
                                     (cl-letf (((symbol-function 'omnivox--negotiate-processes) #'ignore)
                                               ((symbol-function 'omnivox--send-state-command) #'ignore))
                                       (omnivox-configure-tts))
                                     (unless (= (default-value 'tts-speech-rate) 72)
                                       (error "Saved rate did not survive startup"))
                                     (with-temp-buffer
                                       (let ((tts-punctuation-mode-policy-alist nil))
                                         (unless (equal (plist-get (tts-punctuation-mode-state) :mode)
                                                        '(profile "coding" all))
                                           (error "Saved punctuation did not survive startup")))
                                       (let ((tts-punctuation-mode-policy-alist '((fundamental-mode . some))))
                                         (unless (eq (plist-get (tts-punctuation-mode-state) :mode) 'some)
                                           (error "Saving replaced automatic punctuation policy")))))))))
                           (ert-info ((buffer-string)) (should (equal status 0))))))
                   (when transient--prefix (execute-kbd-macro (kbd "C-q")))))))))
      (dolist (entry defaults) (set-default (car entry) (cdr entry)))
      (dolist (entry properties) (setplist (car entry) (cdr entry)))
      (when (get-file-buffer custom-file) (kill-buffer (get-file-buffer custom-file)))
      (delete-file custom-file))))

(ert-deftest emacsvox-aural-menu-voices-graphical-workbench-return-and-drafts ()
  "Nested voice browsing returns to its menu and keeps drafts and filters."
  (skip-unless (display-graphic-p))
  (save-window-excursion
    (emacsvox-test--with-voice-workbench
      (emacsvox-test--with-aural-menu
        (switch-to-buffer source)
        (local-set-key (kbd "<f8>") #'emacsvox-aural-menu)
        (let ((transient--prefix nil) (transient-show-menu 0) spoken)
          (unwind-protect
              (cl-letf (((symbol-function 'emacsvox-aural-voice-workbench--library-start) #'ignore)
                        ((symbol-function 'emacsvox-aural-ui--speak-feedback)
                         (lambda (text &rest _) (push text spoken))))
                (execute-kbd-macro (kbd "C-u <f8> v b"))
                (should-not transient--prefix)
                (should (eq emacsvox-aural-voice-workbench-view 'engines))
                (should (eq (emacsvox-aural-inspection-source-buffer) source))
                (emacsvox-aural-ui-goto-row "winrt")
                (setq emacsvox-aural-voice-workbench-filter '(:language "en-US"))
                (emacsvox-aural-voice-workbench--stage
                 "Change a route"
                 (lambda ()
                   (setf (plist-get emacsvox-aural-voice-workbench-staged-profile :summary)
                         "menu draft")))
                (execute-kbd-macro (kbd "v q"))
                (should (eq emacsvox-aural-voice-workbench-view 'engines))
                (should (equal (tabulated-list-get-id) "winrt"))
                (execute-kbd-macro (kbd "q"))
                (should (eq (oref transient--prefix command) 'emacsvox-aural-menu-voices))
                (should (cl-some (lambda (text) (string-match-p "Engine policy changes remain staged" text)) spoken))
                (with-selected-window transient--window
                  (should (eq (oref (button-get (button-at (point)) 'button-data) command)
                              'emacsvox-aural-menu--browse-voices)))
                ;; Resume retains view, selection, filter, and unfinished policy.
                (execute-kbd-macro (kbd "w"))
                (should (equal (tabulated-list-get-id) "winrt"))
                (should (equal emacsvox-aural-voice-workbench-filter '(:language "en-US")))
                (should (equal (plist-get emacsvox-aural-voice-workbench-staged-profile :summary) "menu draft"))
                (execute-kbd-macro (kbd "q q"))
                (should (eq (oref transient--prefix command) 'emacsvox-aural-menu))
                (should (cdr (plist-get (emacsvox-aural-menu--context) :settings)))
                (execute-kbd-macro (kbd "q"))
                (should (eq (current-buffer) source))
                (should (= (point) 3))
                (should (equal (buffer-string) "first item\nsecond item\n"))
                ;; Direct entry must discard a still-pending menu return.
                (execute-kbd-macro (kbd "<f8> v b"))
                (switch-to-buffer source)
                (emacsvox-aural-voice-workbench)
                (should-not emacsvox-aural-ui--return-function)
                (execute-kbd-macro (kbd "q"))
                (should-not transient--prefix))
            (when transient--prefix (execute-kbd-macro (kbd "C-q")))
            (when (get-buffer "*Aural Voice Workbench*")
              (kill-buffer "*Aural Voice Workbench*"))))))))

(ert-deftest emacsvox-aural-menu-voices-graphical-palettes-return-and-direct-entry ()
  "Palette browsing returns to its focused menu item; direct entry clears it."
  (skip-unless (display-graphic-p))
  (require 'emacsvox-aural-voice-palettes)
  (save-window-excursion
    (emacsvox-test--with-voice-workbench
      (emacsvox-test--with-aural-menu
        (switch-to-buffer source)
        (local-set-key (kbd "<f8>") #'emacsvox-aural-menu-voices)
        (let ((transient--prefix nil) (transient-show-menu 0) selected)
          (unwind-protect
              (progn
                (execute-kbd-macro (kbd "<f8> p"))
                (should (derived-mode-p 'emacsvox-aural-voice-palettes-mode))
                (should (eq (emacsvox-aural-inspection-source-buffer) source))
                (setq selected (tabulated-list-get-id))
                (execute-kbd-macro (kbd "q"))
                (should (eq (oref transient--prefix command) 'emacsvox-aural-menu-voices))
                (with-selected-window transient--window
                  (should (eq (oref (button-get (button-at (point)) 'button-data) command)
                              'emacsvox-aural-menu--voice-palettes)))
                ;; Enter reopens the selected browser, preserving its selected row.
                (execute-kbd-macro (kbd "RET"))
                (should (derived-mode-p 'emacsvox-aural-voice-palettes-mode))
                (should (equal (tabulated-list-get-id) selected))
                (switch-to-buffer source)
                (emacsvox-aural-list-voice-palettes)
                (should-not emacsvox-aural-ui--return-function)
                (execute-kbd-macro (kbd "q"))
                (should-not transient--prefix)
                (should (eq (current-buffer) source))
                (should (= (point) 3)))
            (when transient--prefix (execute-kbd-macro (kbd "C-q")))
            (when (get-buffer "*Aural Voice Palettes*")
              (kill-buffer "*Aural Voice Palettes*"))))))))

(ert-deftest emacsvox-aural-menu-voices-graphical-engine-save-is-explicit ()
  "Global speech scope cannot silently turn a session preference into a save."
  (skip-unless (display-graphic-p))
  (save-window-excursion
    (emacsvox-test--with-voice-workbench
      (emacsvox-test--with-aural-menu
        (switch-to-buffer source)
        (local-set-key (kbd "<f8>") #'emacsvox-aural-menu)
        (let ((transient--prefix nil) (transient-show-menu t) session saved)
          (unwind-protect
              (cl-letf (((symbol-function 'emacsvox-aural-prefer-engine-for-session)
                         (lambda (engine &optional _) (setq session engine)))
                        ((symbol-function 'emacsvox-aural-commit-routing-profile-data)
                         (lambda (profile &rest _) (setq saved profile))))
                (execute-kbd-macro (kbd "C-u <f8> v e W TAB RET"))
                (should (window-live-p transient--window))
                (should (equal session "winrt"))
                (should-not saved)
                (should (eq (oref transient--prefix command) 'emacsvox-aural-menu-voices))
                (execute-kbd-macro (kbd "S W TAB RET"))
                (should (equal (plist-get saved :engine-order) '("winrt" "eloquence")))
                (should (eq (oref transient--prefix command) 'emacsvox-aural-menu-voices))
                (execute-kbd-macro (kbd "C-q"))
                (should-not transient--stack)
                (should (eq (current-buffer) source)))
            (when transient--prefix (execute-kbd-macro (kbd "C-q")))))))))

(provide 'emacsvox-aural-menu-tests)
;;; emacsvox-aural-menu-tests.el ends here
