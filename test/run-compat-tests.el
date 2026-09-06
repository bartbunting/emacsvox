;;; run-compat-tests.el --- Supported Emacs compatibility gate -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Run core startup, reading, input, voice, Org and installer contracts without
;; third-party packages.  The complete integration suite remains make test.
;; CI supplies a private HOME and builds all byte-code before this source gate.

;;; Code:
(require 'ert)
(when (version< emacs-version "30.2")
  (error "Emacsvox compatibility tests require Emacs 30.2 or newer"))
(setq load-prefer-newer t)
(let* ((root (expand-file-name "../" (file-name-directory load-file-name)))
       (lisp (expand-file-name "lisp/" root)))
  (add-to-list 'load-path lisp)
  (add-to-list 'load-path (expand-file-name "test/" root))
  (add-to-list 'load-path (expand-file-name "utils/" root))
  (load (expand-file-name "emacsvox-preamble.el" lisp) nil nil)
  (dolist (module '(emacsvox-startup-tests
                    emacsvox-input-tests emacsvox-voice-tests
                    emacsvox-widget-tests emacsvox-org-tests
                    emacsvox-eww-tests emacsvox-reading-dom-tests emacsvox-epub-tests
                    emacsvox-autoload-tests emacsvox-native-bytecode-tests
                    emacsvox-launcher-tests emacsvox-wsl-install-tests
                    emacsvox-remote-install-tests))
    (require module)))
(ert-run-tests-batch-and-exit)
;;; run-compat-tests.el ends here
