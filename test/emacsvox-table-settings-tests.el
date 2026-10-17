;;; emacsvox-table-settings-tests.el --- Scoped table settings tests -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Code:
(require 'emacsvox-settings-tests)
(require 'emacsvox-table-reader-tests)
(require 'emacsvox-table-settings)

(defmacro emacsvox-table-settings-test--isolated (&rest body)
  "Run BODY with restorable table defaults and Customize properties."
  (declare (indent 0))
  `(let* ((symbols (cons 'emacsvox-table-reader-mode-preferences
                        (mapcar #'cdr emacsvox-table-reader--options)))
          (defaults (mapcar (lambda (s) (cons s (default-value s))) symbols))
          (properties (mapcar (lambda (s) (cons s (copy-tree (symbol-plist s)))) symbols)))
     (unwind-protect (progn ,@body)
       (dolist (entry defaults) (set-default (car entry) (cdr entry)))
       (dolist (entry properties) (setplist (car entry) (cdr entry))))))

(ert-deftest emacsvox-table-settings-graphical-choices-preview-and-scope ()
  "Real menu navigation stages choices, retains focus, and writes only on Save."
  (emacsvox-table-settings-test--isolated
    (emacsvox-test--with-settings
      (execute-kbd-macro (kbd "s T"))
      (should (eq (oref transient--prefix command) 'emacsvox-table-settings))
      (execute-kbd-macro (kbd "t <down>"))
      (should-not (plist-get (emacsvox-table-settings--draft) :changed))
      (execute-kbd-macro (kbd "q"))
      (should-not (plist-get (emacsvox-table-settings--draft) :changed))
      (execute-kbd-macro (kbd "t 4"))
      (should (eq (oref transient--prefix command) 'emacsvox-table-settings))
      (with-selected-window transient--window
        (should (equal (oref (button-get (button-at (point)) 'button-data) key) "t")))
      (should (equal (buffer-local-value 'emacsvox-table-reader-titles source) '(column)))
      (should (string-match-p "pending" (emacsvox-table-settings--label 'titles)))
      (let ((before (with-current-buffer source (list (point) (buffer-string)))) spoken stopped)
        (cl-letf (((symbol-function 'emacsvox-table-settings--say)
                   (lambda (text &rest _) (push text spoken)))
                  ((symbol-function 'emacsvox-aural-preview-stop) (lambda () (setq stopped t))))
          (let ((focus (with-selected-window transient--window
                         (oref (button-get (button-at (point)) 'button-data) command))))
            (execute-kbd-macro (kbd "SPC s"))
            (with-selected-window transient--window
              (should (eq focus (oref (button-get (button-at (point)) 'button-data) command))))))
        (should stopped)
        (should (string-match-p "Engineer\\." (car spoken)))
        (should-not (string-match-p "Role" (car spoken)))
        (should (equal before (with-current-buffer source (list (point) (buffer-string))))))
      (should-not (file-exists-p custom-file))
      (execute-kbd-macro (kbd "A"))
      (should-not (with-current-buffer source (emacsvox-table-reader--preference 'titles)))
      (should-not (file-exists-p custom-file))
      (should (memq 'titles (plist-get (emacsvox-table-settings--draft) :applied)))
      (should (string-match-p "applied here, not saved" (emacsvox-table-settings--label 'titles)))
      ;; Saving after a local trial needs no second selection.
      (execute-kbd-macro (kbd "M"))
      (should (assq 'titles (alist-get 'text-mode emacsvox-table-reader-mode-preferences)))
      (should-not (alist-get 'titles (alist-get 'text-mode emacsvox-table-reader-mode-preferences)))
      ;; Nil is distinct from inheritance; only the explicit mode Save persists.
      (execute-kbd-macro (kbd "t 2 M"))
      (should (equal (alist-get 'titles (alist-get 'text-mode emacsvox-table-reader-mode-preferences)) '(row)))
      (should-not (with-current-buffer source (emacsvox-table-reader--preference 'titles)))
      (execute-kbd-macro (kbd "t 5 A"))
      (should (equal (with-current-buffer source (emacsvox-table-reader--preference 'titles)) '(row)))
      ;; The buffer inheritance choice cannot be a common default.  Finish
      ;; that local trial before staging a different common preference.
      (execute-kbd-macro (kbd "D o 2 W"))
      (with-temp-buffer
        (should (zerop (call-process (expand-file-name invocation-name invocation-directory) nil t nil
                                    "-Q" "--batch" "--eval" "(setq load-prefer-newer t)" "-L" emacsvox-lisp-directory
                                    "-l" "emacsvox-table-reader.el" "-l" custom-file
                                    "--eval" "(prin1 (list emacsvox-table-reader-data-position emacsvox-table-reader-mode-preferences))")))
        (should (string-match-p "(last ((text-mode (titles row))))" (buffer-string))))
      ;; Reset this mode to common inheritance and persist that decision.
      (execute-kbd-macro (kbd "t 5 M"))
      (should (eq (alist-get 'titles (alist-get 'text-mode emacsvox-table-reader-mode-preferences)) 'inherit))
      (should (equal (with-current-buffer source (emacsvox-table-reader--preference 'titles)) '(column)))
      (execute-kbd-macro (kbd "q q q"))
      (should (eq (current-buffer) source)))))

(ert-deftest emacsvox-table-settings-graphical-help-and-reset ()
  "Choice Help preserves the browsed row; reset and cancellation have no writes."
  (emacsvox-table-settings-test--isolated
    (emacsvox-test--with-settings
      (execute-kbd-macro (kbd "s T t <down>"))
      (execute-kbd-macro (kbd "? 2"))
      (should (derived-mode-p 'help-mode))
      (execute-kbd-macro (kbd "q"))
      (should (eq (oref transient--prefix command) 'emacsvox-table-settings--choices))
      (with-selected-window transient--window
        (should (equal (oref (button-get (button-at (point)) 'button-data) key) "2")))
      (execute-kbd-macro (kbd "q I"))
      (should (= (length (plist-get (emacsvox-table-settings--draft) :changed)) 8))
      (should-error (emacsvox-table-settings--save-common) :type 'user-error)
      (execute-kbd-macro (kbd "D"))
      (should-not (plist-get (emacsvox-table-settings--draft) :changed))
      (should-not (file-exists-p custom-file))
      ;; A stale source must never direct changes to the menu or another buffer.
      (let ((context (emacsvox-table-settings--context)))
        (execute-kbd-macro (kbd "C-q"))
        (kill-buffer source)
        (let ((transient--prefix (transient-prefix :command 'emacsvox-table-settings :scope context)))
          (should-error (emacsvox-table-settings--apply) :type 'user-error))))))

(ert-deftest emacsvox-table-settings-graphical-search-discards-closed-choices ()
  "Reopening through search must not revive unapplied choices from a closed page."
  (emacsvox-table-settings-test--isolated
    (emacsvox-test--with-settings
      (dotimes (visit 2)
        (execute-kbd-macro
         (vconcat (kbd "/") "Table titles and data order" (kbd "RET")))
        (should-not (plist-get (emacsvox-table-settings--draft) :changed))
        (should (equal (alist-get 'titles (plist-get (emacsvox-table-settings--draft) :values))
                       '(column)))
        (when (zerop visit) (execute-kbd-macro (kbd "t 4")))
        (execute-kbd-macro (kbd "q")))
      (should-not (file-exists-p custom-file)))))

(provide 'emacsvox-table-settings-tests)
;;; emacsvox-table-settings-tests.el ends here
