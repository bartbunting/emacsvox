;;; emacsvox-muggles-ui-tests.el --- Muggles browser checks -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Code:
(require 'emacsvox-muggles-tests)
(require 'emacsvox-aural-menu-tests)
(require 'emacsvox-muggles-ui)
(require 'emacsvox-settings)

(defmacro emacsvox-muggles-ui-test--isolated (&rest body)
  "Run BODY with isolated settings, source and silent speech capture."
  (declare (indent 0))
  `(emacsvox-muggles-test--isolated
     (save-window-excursion
       (emacsvox-test--with-aural-menu
         (org-mode)
         (let ((transient--prefix nil) (transient-show-menu 0)
               (transient-save-history nil) (transient-history nil)
               (transient-values nil) (transient-history-file nil)
               (emacsvox-use-icons nil))
           (unwind-protect
               (cl-letf (((symbol-function 'emacsvox-aural-ui-speak) #'ignore)
                         ((symbol-function 'emacsvox-speak-help) #'ignore))
                 ,@body)
             (when transient--prefix
               (if (display-graphic-p) (execute-kbd-macro (kbd "C-q"))
                 (transient-quit-all)))
             (when (get-buffer "*Emacsvox Muggles*")
               (kill-buffer "*Emacsvox Muggles*"))))))))

(ert-deftest emacsvox-muggles-ui-opening-is-passive ()
  (emacsvox-optional-module-test-load
   "emacsvox-muggles-ui.el"
   '(progn (require 'ert) (require 'package) (package-initialize)
           (require 'emacsvox-preamble) (require 'emacsvox-loaddefs))
   '(cl-letf (((symbol-function 'emacsvox-aural-ui-speak) #'ignore))
      (emacsvox-muggles-browse)
      (should (eq (tabulated-list-get-id) 'org-navigation))
      (should-not emacsvox-muggles--session)
      (should-not emacsvox-muggles--owned)
      (dolist (feature '(org hydra extra-muggles emacsvox-muggles
                            emacsvox-muggle-org-navigation))
        (should-not (featurep feature))))))

(ert-deftest emacsvox-muggles-ui-changes-retain-row-column-and-explicit-nil ()
  (emacsvox-muggles-ui-test--isolated
    (switch-to-buffer source)
    (emacsvox-muggles-browse)
    (emacsvox-aural-ui-goto-tabulated-column 2)
    (let ((old-point (point)))
      (emacsvox-muggles-ui-enable)
      (should (eq (tabulated-list-get-id) 'org-navigation))
      (should (= 2 (emacsvox-aural-ui-tabulated-column-index)))
      (should (string-match-p "not saved" (aref (tabulated-list-get-entry) 1)))
      (emacsvox-muggles-ui-disable)
      (should (= old-point (point)))
      (should (equal emacsvox-muggles--session '((org-navigation))))
      (let* ((dir (make-temp-file "muggles-ui-custom" t))
             (custom-file (expand-file-name "custom.el" dir))
             (user-init-file custom-file))
        (unwind-protect
            (progn
              (emacsvox-muggles-ui-save)
              (should-not emacsvox-muggles--session)
              (should (equal (aref (tabulated-list-get-entry) 2) "Disabled"))
              (should (= 2 (emacsvox-aural-ui-tabulated-column-index)))
              (should (file-exists-p custom-file)))
          (when (get-file-buffer custom-file) (kill-buffer (get-file-buffer custom-file)))
          (delete-directory dir t))))))

(ert-deftest emacsvox-muggles-ui-failed-save-retains-visible-pending-choice ()
  (emacsvox-muggles-ui-test--isolated
    (emacsvox-muggles-browse)
    (emacsvox-muggles-ui-disable)
    (let ((old-point (point)) (user-init-file "/unused-test-init"))
      (cl-letf (((symbol-function 'customize-save-variable)
                 (lambda (&rest _) (error "Cannot save"))))
        (should-error (emacsvox-muggles-ui-save)))
      (should (= old-point (point)))
      (should (assq 'org-navigation emacsvox-muggles--session))
      (should (string-match-p "not saved" (aref (tabulated-list-get-entry) 1))))))

(ert-deftest emacsvox-muggles-ui-run-rejects-dead-changed-and-wrong-source ()
  (emacsvox-muggles-ui-test--isolated
    (switch-to-buffer source)
    (emacsvox-muggles-browse)
    (with-current-buffer source (fundamental-mode))
    (should-error (emacsvox-muggles-ui-run) :type 'user-error)
    (should (derived-mode-p 'emacsvox-muggles-ui-mode))
    (with-current-buffer source (org-mode) (erase-buffer) (insert "replacement\n"))
    (should-error (emacsvox-muggles-ui-run) :type 'user-error)
    (should-not hydra-curr-map)
    (kill-buffer source)
    (should-error (emacsvox-muggles-ui-run) :type 'user-error)
    (should (derived-mode-p 'emacsvox-muggles-ui-mode))))

(ert-deftest emacsvox-muggles-ui-graphical-menu-help-and-return-focus ()
  (skip-unless (display-graphic-p))
  (emacsvox-muggles-ui-test--isolated
    (switch-to-buffer source)
    (local-set-key (kbd "<f8>") #'emacsvox-aural-menu)
    (execute-kbd-macro (kbd "<f8> m"))
    (should (derived-mode-p 'emacsvox-muggles-ui-mode))
    (should (eq emacsvox-aural-ui-source-buffer source))
    (should (= emacsvox-aural-ui-source-position 3))
    (execute-kbd-macro (kbd "<right> e d"))
    (should (eq (tabulated-list-get-id) 'org-navigation))
    (should (= 1 (emacsvox-aural-ui-tabulated-column-index)))
    (let ((point-before (point)) (browser (current-buffer)))
      (execute-kbd-macro (kbd "RET"))
      (should (buffer-live-p (get-buffer "*Help*")))
      (select-window (get-buffer-window "*Help*"))
      (execute-kbd-macro (kbd "q"))
      (should (eq (current-buffer) browser))
      (should (= (point) point-before)))
    (execute-kbd-macro (kbd "q"))
    (should (eq (oref transient--prefix command) 'emacsvox-aural-menu))
    (with-selected-window transient--window
      (should (eq (oref (button-get (button-at (point)) 'button-data) command)
                  'emacsvox-aural-menu--muggles)))
    (execute-kbd-macro (kbd "q"))
    (should (eq (current-buffer) source))
    (should (= (point) 3))
    (should (assq 'org-navigation emacsvox-muggles--session))
    (emacsvox-muggles-browse)
    (execute-kbd-macro (kbd "q"))
    (should-not transient--prefix)))

(ert-deftest emacsvox-muggles-ui-graphical-run-disabled-at-captured-position ()
  (skip-unless (display-graphic-p))
  (emacsvox-muggles-ui-test--isolated
    (switch-to-buffer source)
    (erase-buffer)
    (insert "* First\nBody\n* Second\nBody\n")
    (goto-char (point-min))
    (emacsvox-muggles-browse)
    (emacsvox-muggles-ui-disable)
    (with-current-buffer source (goto-char (point-max)))
    (execute-kbd-macro (kbd "r"))
    (should (eq (current-buffer) source))
    (should (= (point) (point-min)))
    (should hydra-curr-map)
    (should-not (car (emacsvox-muggles--choice 'org-navigation)))
    (execute-kbd-macro (kbd "q"))
    (should-not hydra-curr-map)))

(ert-deftest emacsvox-muggles-ui-search-selects-control-without-opening ()
  (skip-unless (display-graphic-p))
  (emacsvox-muggles-ui-test--isolated
    (switch-to-buffer source)
    (call-interactively #'emacsvox-aural-menu)
    (emacsvox-settings--open (assoc "Browse Muggles" emacsvox-settings--actions))
    (should-not (get-buffer "*Emacsvox Muggles*"))
    (with-selected-window transient--window
      (should (eq (oref (button-get (button-at (point)) 'button-data) command)
                  'emacsvox-aural-menu--muggles)))
    (should (assoc "Muggles: enable, disable and save navigation menus"
                   emacsvox-settings--destinations))))

(provide 'emacsvox-muggles-ui-tests)
;;; emacsvox-muggles-ui-tests.el ends here
