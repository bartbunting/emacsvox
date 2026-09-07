;;; run-core-tests.el --- Core speech regression gate -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Run speech, voice, transport, and startup contracts without optional Emacs
;; packages.  CI uses a fresh source checkout and private HOME.  Tests capture
;; speech events; no speech server or audio device is needed.

;;; Code:

(require 'ert)

(when (version< emacs-version "30.2")
  (error "Emacsvox core tests require Emacs 30.2 or newer"))

;; Do not silently skip the Make inventory or Tcl server environment checks.
(dolist (program '("make" "git" "sh" "tclsh"))
  (unless (executable-find program)
    (error "Emacsvox core tests require %s on PATH" program)))

(setq load-prefer-newer t)
(let* ((root (expand-file-name "../" (file-name-directory load-file-name)))
       (lisp (expand-file-name "lisp/" root)))
  (add-to-list 'load-path lisp)
  (add-to-list 'load-path (expand-file-name "test/" root))
  (load (expand-file-name "emacsvox-preamble.el" lisp) nil nil)
  (dolist (module '(emacsvox-tts-tests
                    omnivox-remote-tests
                    emacsvox-voice-tests
                    emacsvox-speak-tests
                    emacsvox-aural-transport-tests
                    emacsvox-aural-voice-workbench-tests
                    emacsvox-startup-tests
                    emacsvox-agent-shell-render-tests))
    (require module)))

(ert-run-tests-batch-and-exit)

;;; run-core-tests.el ends here
