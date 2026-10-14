;;; emacsvox-aural-menu-tests.el --- Linked aural menu tests -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Cover source ownership and real linked-menu navigation.

;;; Code:
(require 'ert)
(require 'emacsvox-aural-menu)
(require 'emacsvox-indentation-tests)

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
      (should-error (emacsvox-aural-menu--home) :type 'user-error)
      (should-error (emacsvox-aural-menu--indentation) :type 'user-error)
      (should-error (emacsvox-aural-menu--toggle-scope) :type 'user-error)
      (should-not (cdr (plist-get context :settings))))))

(ert-deftest emacsvox-aural-menu-home-retains-item-after-source-moves ()
  "The fallback Home retains the captured item and survives menu closure."
  (require 'emacsvox-aural-home)
  (save-window-excursion
    (emacsvox-test--with-aural-menu
      (goto-char 15)
      (unwind-protect
          (progn
            (emacsvox-aural-menu--home)
            (with-current-buffer "*Emacsvox Aural*"
              (should (eq (emacsvox-aural-inspection-source-buffer) source))
              (should (= (emacsvox-aural-inspection-call-in-source #'point) 3)))
            (should (= (with-current-buffer source (point)) 15)))
        (when (get-buffer "*Emacsvox Aural*")
          (kill-buffer "*Emacsvox Aural*"))))))

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
                    (execute-kbd-macro (kbd "s n v S q"))
                    (should emacsvox-transient-verbose-descriptions)
                    (should (eq emacsvox-transient-navigation-style 'section-stop))
                    (should (eq (oref transient--prefix command) 'emacsvox-aural-menu-speech))
                    (should (equal (emacsvox-aural-menu--scope-label) "Current buffer"))
                    (setq emacsvox-transient-navigation-style 'continuous)
                    (setq emacsvox-transient-section-announcement-order 'item-first)
                    (setq emacsvox-transient-verbose-descriptions nil)
                    (load custom-file nil t)
                    (should (eq emacsvox-transient-navigation-style 'section-stop))
                    (should (eq emacsvox-transient-section-announcement-order 'section-first))
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
                  (check-items '("s" "x" "h" "q"))
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
                                "<right> C-j"))
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
                        (should (string-match-p "Aural Home (all actions)" (buffer-string))))
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
  "The existing browser opens after menu exit and retains the source buffer."
  (skip-unless (display-graphic-p))
  (require 'emacsvox-aural-sound-packs)
  (save-window-excursion
    (emacsvox-test--with-aural-menu
      (switch-to-buffer source)
      (local-set-key (kbd "<f8>") #'emacsvox-aural-menu)
      (let ((transient--prefix nil) (transient-show-menu 0))
        (unwind-protect
            (progn
              (execute-kbd-macro (kbd "<f8> o p"))
              (should-not transient--prefix)
              (should-not transient--stack)
              (should (derived-mode-p 'emacsvox-aural-sound-packs-mode))
              (should (eq (emacsvox-aural-inspection-source-buffer) source))
              (execute-kbd-macro (kbd "q"))
              (should (eq (current-buffer) source))
              (should (= (point) 3)))
          (when transient--prefix (execute-kbd-macro (kbd "C-q")))
          (when (get-buffer "*Aural Sound Packs*")
            (kill-buffer "*Aural Sound Packs*")))))))

(provide 'emacsvox-aural-menu-tests)
;;; emacsvox-aural-menu-tests.el ends here
