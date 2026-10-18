;;; emacsvox-enriched.el --- Audio FormatRichtext -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1995 by T. V. Raman
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: emacsvox, audio interface to emacs rich text
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
;; emacsvox extensions to voiceify rich  text.
;;; Code:

;;  required modules
(require 'emacsvox-preamble)
(require 'enriched)

;;;  voiceify-faces 
(defvar emacsvox-enriched-font-faces-to-voiceify
  (list 'bold 'italic   'bold-italic 'underlined)
  "List of font faces we voiceify")

(defun emacsvox-enriched-voiceify-faces (start end)
  "Map base fonts to voices.
Useful in voiceifying rich text."
  (interactive "r")
  
  (set (make-local-variable 'voice-lock-mode) t)
  (with-silent-modifications
    (save-excursion
      (goto-char start)
      (let ((face nil)
            (orig start)
            (pos nil)
            (justification-type nil))
        (unless (get-text-property (point) 'justification)
          (goto-char
           (or
            (next-single-property-change (point) 'justification
                                         (current-buffer) end)
            end)))
        (while (and  (not (eobp))
                     (< start end))
          (setq justification-type (get-text-property (point) 'justification))
          (save-excursion
            (beginning-of-line)
            (setq pos (point)))
          (goto-char
           (or
            (next-single-property-change (point) 'justification
                                         (current-buffer) end)
            end))
          (when justification-type
            (put-text-property pos (point)
                               'auditory-icon
                               justification-type))
          (setq start (point)))
        (goto-char orig)
        (while (and  (not (eobp))
                     (< start end))
          (setq face (get-text-property (point) 'face))
          (goto-char
           (or
            (next-single-property-change (point) 'face
                                         (current-buffer) end)
            end))
          (when (listp face)
            (setq face 
                  (cl-loop for f in emacsvox-enriched-font-faces-to-voiceify
                           thereis (cl-find f face))))
          (when face 
            (put-text-property start  (point)
                               'personality
                               (voice-setup-get-voice-for-face face))
            (setq face nil))
          (setq start (point))))))
  (message "voicified faces"))

;;;  advice enriched to automatically map faces to voices

(defun emacsvox--advice-enriched-decode-after (from to)
  "Map faces to voices between FROM and TO."
  (emacsvox-enriched-voiceify-faces from to))

(advice-add 'enriched-decode :after
            #'emacsvox--advice-enriched-decode-after)

(defun emacsvox--advice-enriched-mode-after (&rest _)
  "Map faces to voices in the current buffer."
  (emacsvox-enriched-voiceify-faces (point-min) (point-max)))

(advice-add 'enriched-mode :after
            #'emacsvox--advice-enriched-mode-after)

;;;  hooks
(add-hook 'enriched-mode-hook
          #'(lambda ()
              (or emacsvox-audio-indentation
                  (emacsvox-toggle-audio-indentation))))

(provide  'emacsvox-enriched)

;;; emacsvox-enriched.el ends here
