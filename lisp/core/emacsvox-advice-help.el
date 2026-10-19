;;; emacsvox-advice-help.el --- Core Help and key-description feedback -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1995, 1996, 1997 by T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox, Speech, Advice, Spoken output
;; URL: https://github.com/bartbunting/emacsvox

;; This file is part of Emacsvox.
;;
;; Emacsvox is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; Emacsvox is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with Emacsvox.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Core Help and key-description feedback.
;; Load through `emacsvox-advice'.  The facade owns activation.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'emacsvox-preamble)
(require 'emacsvox-aural-submission)

(defun emacsvox--advice-help-do-xref-after (&rest _)
  "Speak the Help reference just selected."
  (emacsvox-speak-line)
  (emacsvox-icon 'item))

(defun emacsvox--advice-help-xref-go-back-after (&rest _)
  "Speak the Help reference reached by moving backward."
  (emacsvox-speak-line))

(defun emacsvox--advice-help-xref-go-forward-after (&rest _)
  "Speak the Help reference reached by moving forward."
  (emacsvox-speak-line))

(defun emacsvox--advice-help-window-display-message-around
    (original &rest arguments)
  "Call ORIGINAL with Help window messages silenced."
  (ems-with-messages-silenced (apply original arguments)))

(defun emacsvox--describe-key-filter-return (target result)
  "Announce interactive key help and return RESULT unchanged.
TARGET identifies the key-description command."
  (when (ems-interactive-p target)
    (emacsvox-icon 'help)
    (unless result
      (emacsvox-speak-help)))
  result)

(defun emacsvox--advice-describe-key-filter-return (result)
  "Announce interactive `describe-key' help and return RESULT."
  (emacsvox--describe-key-filter-return 'describe-key result))

(defun emacsvox--advice-describe-keymap-filter-return (result)
  "Announce interactive `describe-keymap' help and return RESULT."
  (emacsvox--describe-key-filter-return 'describe-keymap result))

(defvar emacsvox--help-char-helpbuf " *Char Help*"
  "This is hard-coded in subr.el")

(defun emacsvox--advice-help-form-show-after (&rest _)
  "Speak displayed help form."
  (when (buffer-live-p (get-buffer emacsvox--help-char-helpbuf))
    (with-current-buffer emacsvox--help-char-helpbuf
      (goto-char (point-min))
      (emacsvox-speak-buffer))))

(defun ems-canonicalize-key-description (desc)
  "Change key description to a speech-friendly form."
  (let ((shift-regexp "S-\\(.\\)")
        (ctrl-regexp "C-\\(.\\)")
        (meta-regexp "M-\\(.\\)")
        (caps-regexp "\\b[A-Z]\\b")
        (hyper-regexp "C-x @ h")
        (alt-regexp "C-x @ a")
        (super-regexp "C-x @ s")
        (buffer-undo-list t))
    (with-temp-buffer

      (setq case-fold-search nil)
      (erase-buffer)
      (insert desc)
      (goto-char (point-min))
      (while (search-forward "SPC" nil t)
        (replace-match "space"))
      (goto-char (point-min))
      (while (search-forward "ESC" nil t)
        (replace-match "escape"))
      (goto-char (point-min))
      (while (search-forward "RET" nil t)
        (replace-match "return"))
      (goto-char (point-min))
      (while (re-search-forward hyper-regexp nil t)
        (replace-match "hyper "))
      (goto-char (point-min))
      (while (re-search-forward alt-regexp nil t)
        (replace-match "alt "))
      (goto-char (point-min))
      (while (re-search-forward super-regexp nil t)
        (replace-match "super "))
      (goto-char (point-min))
      (while (re-search-forward shift-regexp nil t)
        (replace-match "shift \\1"))
      (goto-char (point-min))
      (while (re-search-forward ctrl-regexp nil t)
        (replace-match "control \\1"))
      (goto-char (point-min))
      (while (re-search-forward meta-regexp nil t)
        (replace-match "meta \\1"))
      (goto-char (point-min))
      (goto-char (point-min))
      (while (re-search-forward caps-regexp nil t)
        (replace-match " cap \\& " t))
      (buffer-string))))

(defun emacsvox--advice-describe-key-briefly-around
    (original &rest arguments)
  "Call ORIGINAL once and speak an interactive key description."
  (if (ems-interactive-p 'describe-key-briefly)
      (let* ((emacsvox-speak-messages nil)
             (result (apply original arguments)))
        (tts-speak (ems-canonicalize-key-description result))
        result)
    (apply original arguments)))

(defun ems--get-where-is (cmd )
  "Return string describing keys that invoke `cmd'. "
  (let* ((keys (where-is-internal cmd overriding-local-map nil nil ))
         (desc
          (if (zerop (length keys))
              "is not on any key"
            (mapconcat 'key-description keys ", "))))
    (concat
     (format "%s  " cmd)
     (ems-canonicalize-key-description desc))))

(defun emacsvox--advice-where-is-after (definition &optional _insert)
  "Speak keys for interactive `where-is' DEFINITION."
  (when (ems-interactive-p 'where-is)
    (tts-speak (ems--get-where-is definition))))

(provide 'emacsvox-advice-help)
;;; emacsvox-advice-help.el ends here
