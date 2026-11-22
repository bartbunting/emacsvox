;;; profile.el --- Isolated phone listening session -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;; Author: Emacsvox contributors
;; Maintainer: Emacsvox maintainers
;; Keywords: accessibility, speech
;; URL: https://github.com/bartbunting/emacsvox

;; You can redistribute and modify this file under the GNU General Public
;; License version 2 or later. See COPYING in the repository root.

;;; Commentary:
;; This file is used by the isolated iPhone speech prototype.

;;; Code:

(setq user-emacs-directory (file-name-as-directory (getenv "EMACSVOX_PHONE_PROFILE"))
      server-name (file-name-nondirectory (directory-file-name user-emacs-directory))
      package-user-dir (expand-file-name "~/.emacs.d/elpa")
      emacsvox-use-icons nil
      emacsvox-play-program nil
      tts-notification-device "default"
      agent-shell-transcript-file-path-function nil
      agent-shell-inhibit-system-sleep nil
      acp-logging-enabled nil
      emacsvox-aural-diagnostic-log-file nil)
(require 'package)
(package-initialize)
(when-let* ((checkout (getenv "EMACSVOX_AGENT_SHELL_DIRECTORY")))
  (add-to-list 'load-path (expand-file-name checkout)))
(add-to-list 'load-path (expand-file-name "lisp" (getenv "EMACSVOX_DIR")))
(require 'emacsvox-preamble)
(setq emacsvox-user-directory (expand-file-name "speech/" user-emacs-directory))
(make-directory emacsvox-user-directory t)
(load (expand-file-name "emacsvox-setup.el" emacsvox-lisp-directory) nil nil t)
(let ((emacsvox-sounds--silent-theme-selection t))
  (emacsvox-sounds-select-theme (expand-file-name "packs/accent" emacsvox-sounds-dir)))
(setq-default emacsvox-use-icons t)
(require 'agent-shell)
(require 'emacsvox-agent-shell)
(setq agent-shell-openai-authentication (agent-shell-openai-make-authentication :login t)
      agent-shell-session-strategy 'new)

;;; profile.el ends here
