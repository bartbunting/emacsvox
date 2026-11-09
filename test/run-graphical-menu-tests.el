;;; run-graphical-menu-tests.el --- Isolated graphical menu checks -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Use make graphical-menu-test. Optional packages come from the explicitly
;; selected package directory and prepared integration dependencies. Report
;; their loaded paths; this local check does not replace the pinned gates.

;;; Code:

(require 'ert)
(require 'package)
(let* ((root (expand-file-name "../" (file-name-directory load-file-name)))
       (profile (getenv "EMACSVOX_MENU_TEST_PROFILE"))
       (log (getenv "EMACSVOX_GRAPHICAL_TEST_LOG"))
       (kind (or (getenv "EMACSVOX_MENU_TEST_LOAD") "compiled"))
       (packages (getenv "EMACSVOX_MENU_TEST_PACKAGE_DIR"))
       (dependencies (getenv "EMACSVOX_TEST_DEPS_DIR"))
       (modules '(emacsvox-transient emacsvox-aural-menu emacsvox-settings-changes
                  emacsvox-settings emacsvox-settings-integrations emacsvox-settings-workflows
                  emacsvox-reading-settings emacsvox-output-settings emacsvox-table-settings
                  emacsvox-tree-settings emacsvox-tone-editor emacsvox-indentation
                  emacsvox-capitalization emacsvox-spelling emacsvox-interaction
                  emacsvox-line-cues emacsvox-aural-voice-menu))
       (suites '(emacsvox-transient-tests emacsvox-indentation-tests emacsvox-aural-menu-tests
                 emacsvox-capitalization-tests emacsvox-spelling-tests emacsvox-interaction-tests
                 emacsvox-line-cues-tests emacsvox-reading-settings-tests emacsvox-output-settings-tests
                 emacsvox-punctuation-menu-tests emacsvox-settings-tests emacsvox-table-settings-tests
                 emacsvox-tree-settings-tests emacsvox-settings-workflows-tests
                 emacsvox-aural-voice-menu-tests emacsvox-magit-tests))
       (status 2))
  (condition-case err
      (progn
        (unless (and profile log (display-graphic-p) (not noninteractive))
          (error "Use make graphical-menu-test with a graphical Emacs"))
        (unless (member kind '("source" "compiled"))
          (error "MENU_TEST_LOAD must be source or compiled"))
        (setq debug-on-error nil debug-on-quit nil
              load-prefer-newer t ring-bell-function #'ignore
              user-emacs-directory (file-name-as-directory profile)
              custom-file (expand-file-name "custom.el" profile)
              user-init-file custom-file
              emacsvox-user-directory (expand-file-name "data/" profile))
        (make-directory emacsvox-user-directory t)
        (advice-add 'message :after
                    (lambda (format-string &rest arguments)
                      (when format-string
                        (with-temp-buffer
                          (insert (apply #'format-message format-string arguments) "\n")
                          (write-region (point-min) (point-max) log t 'silent)))))
        (setq-default emacsvox-play-program nil)
        (setenv "TTS_PROGRAM" (expand-file-name "servers/log-null" root))
        ;; Activate only the chosen installation. No personal init is loaded.
        (setq package-user-dir (if (and packages (not (string-empty-p packages)))
                                   (expand-file-name packages)
                                 (expand-file-name "elpa/" profile))
              package-directory-list nil)
        (package-initialize)
        (when (and dependencies (file-directory-p dependencies))
          (dolist (path (directory-files dependencies t "^[^.]"))
            (when (file-directory-p path) (add-to-list 'load-path path t))))
        (dolist (directory '("lisp/" "test/" "utils/"))
          (add-to-list 'load-path (expand-file-name directory root)))
        (require 'emacsvox-preamble)
        (load (expand-file-name "lisp/emacsvox-loaddefs.el" root) nil t)
        (dolist (feature '(markdown-mode agent-shell eat notmuch magit))
          (unless (require feature nil t)
            (error "Missing %s: set MENU_TEST_PACKAGE_DIR or prepare TEST_DEPS_DIR" feature)))
        (setq-default emacsvox-speak-messages nil)
        (setq tts-speaker-process
              (make-process :name "menu-test-main" :noquery t
                            :command (list (expand-file-name "servers/log-null" root)))
              tts-notify-process
              (make-process :name "menu-test-notification" :noquery t
                            :command (list (expand-file-name "servers/log-null" root))))
        (fset 'ding #'ignore)
        (dolist (suite suites)
          (load (expand-file-name (concat (symbol-name suite) ".el")
                                  (expand-file-name "test/" root)) nil t))
        ;; Some test files deliberately load source. Select the requested
        ;; production modules after loading tests, and report those exact paths.
        (dolist (module modules)
          (let* ((library (locate-library (symbol-name module)))
                 (path (concat (file-name-sans-extension library)
                               (if (equal kind "compiled") ".elc" ".el"))))
            (load path nil t)
            (message "Menu module: %s" path)))
        (when (equal (getenv "EMACSVOX_MENU_TEST_MAGIT_SOURCE") "1")
          (load (concat (file-name-sans-extension (locate-library "magit-git")) ".el") nil t)
          (message "Magit Git module explicitly loaded from source"))
        (message "Emacs %s; Transient %s; Magit %s; Agent Shell %s"
                 emacs-version transient-version (magit-version) agent-shell--version)
        (dolist (function '(transient-setup magit-status-mode magit-config-get-from-cached-list
                           agent-shell-mode eat-mode notmuch-search-mode markdown-mode))
          (message "Dependency: %s %s" function (symbol-file function)))
        (let* ((selector
                '(or "^emacsvox-transient-" "^emacsvox-indentation-" "^emacsvox-aural-menu-"
                     "^emacsvox-capitalization-" "^emacsvox-spelling-" "^emacsvox-interaction-"
                     "^emacsvox-line-cues-" "^emacsvox-reading-settings-" "^emacsvox-output-settings-"
                     "^emacsvox-punctuation-menu-" "^emacsvox-settings-" "^emacsvox-table-settings-"
                     "^emacsvox-tree-settings-" "^emacsvox-tone-editor-" "^emacsvox-aural-voice-menu-"
                     "^emacsvox-speak-navigation-graphical-reading-" "^emacsvox-magit-transient-"))
               (stats (ert-run-tests-batch selector)))
          (message "Menu tests: %d completed, %d unexpected, %d skipped"
                   (ert-stats-completed stats) (ert-stats-completed-unexpected stats)
                   (ert-stats-skipped stats))
          (setq status (if (and (> (ert-stats-total stats) 0)
                                (= (ert-stats-completed stats) (ert-stats-total stats))
                                (zerop (ert-stats-completed-unexpected stats))
                                (zerop (ert-stats-skipped stats))) 0 1))))
    ((error quit)
     (when log
       (with-temp-buffer
         (insert (format "Graphical menu tests failed: %S\n" err))
         (write-region (point-min) (point-max) log t 'silent)))))
  (kill-emacs status))

;;; run-graphical-menu-tests.el ends here
