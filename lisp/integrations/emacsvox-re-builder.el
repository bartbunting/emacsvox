;;; emacsvox-re-builder.el --- re-builder  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman<tv.raman.tv@gmail.com>
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox, Audio Desktop
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

;; Speech-enable re-builder.
;; Will be used to advantage in efficiently setting up outline
;; regexp wizards


;;  required modules
;;; Code:

(require 'emacsvox-preamble)
(require 're-builder)

;;;  Map faces to personalities 
(voice-setup-add-map
 '(
   (reb-match-0 voice-overlay-0)
   (reb-match-1 voice-overlay-1)
   (reb-match-2 voice-overlay-2)
   (reb-match-3 voice-overlay-3)))

;;;  Speech-enable interactive commands.

(defun emacsvox--advice-re-builder-after (&rest _)
  "Speak status information."
  (when (ems-interactive-p 're-builder)
    (emacsvox-icon 'open-object) (emacsvox-speak-line)))

(advice-add 're-builder :after
            #'emacsvox--advice-re-builder-after)

(defun emacsvox--advice-reb-quit-after (&rest _)
  "speak."
  (when (ems-interactive-p 'reb-quit)
    (emacsvox-icon 'close-object)))

(advice-add 'reb-quit :after
            #'emacsvox--advice-reb-quit-after)

(defun emacsvox--advice-reb-next-match-after (&rest _)
  "Speak matched line."
  (when (ems-interactive-p 'reb-next-match)
    (let ((emacsvox-show-point t))
      (with-current-buffer reb-target-buffer
        (emacsvox-speak-line)
        (emacsvox-icon 'large-movement)))))

(advice-add 'reb-next-match :after
            #'emacsvox--advice-reb-next-match-after)

(defun emacsvox--advice-reb-prev-match-after (&rest _)
  "Speak matched line."
  (when (ems-interactive-p 'reb-prev-match)
    (let ((emacsvox-show-point t))
      (with-current-buffer reb-target-buffer
        (emacsvox-speak-line)
        (emacsvox-icon 'large-movement)))))

(advice-add 'reb-prev-match :after
            #'emacsvox--advice-reb-prev-match-after)

(defun emacsvox--advice-reb-toggle-case-after (&rest _)
  "Speak."
  (when (ems-interactive-p 'reb-toggle-case)
    (with-current-buffer reb-target-buffer
      (emacsvox-icon (if case-fold-search 'on 'off)))))

(advice-add 'reb-toggle-case :after
            #'emacsvox--advice-reb-toggle-case-after)

(defun emacsvox--advice-reb-copy-after (&rest _)
  "speak."
  (when (ems-interactive-p 'reb-copy)
    (emacsvox-icon 'yank-object)))

(advice-add 'reb-copy :after
            #'emacsvox--advice-reb-copy-after)

(defun emacsvox--advice-reb-enter-subexp-mode-after (&rest _)
  "speak."
  (when (ems-interactive-p 'reb-enter-subexp-mode)
    (emacsvox-icon 'open-object)))

(advice-add 'reb-enter-subexp-mode :after
            #'emacsvox--advice-reb-enter-subexp-mode-after)

(defun emacsvox--advice-reb-quit-subexp-mode-after (&rest _)
  "speak."
  (when (ems-interactive-p 'reb-quit-subexp-mode)
    (emacsvox-icon 'close-object)))

(advice-add 'reb-quit-subexp-mode :after
            #'emacsvox--advice-reb-quit-subexp-mode-after)

(defun emacsvox--advice-reb-auto-update-after (&rest _)
  "Speak after update is done."
  (when (buffer-live-p reb-target-buffer)
    (with-current-buffer reb-target-buffer
      (with-silent-modifications
        (mapc #'(lambda (o) (overlay-put o 'auditory-icon 'item))
              reb-overlays))))
  (emacsvox-speak-message-again))

(advice-add 'reb-auto-update :after
            #'emacsvox--advice-reb-auto-update-after)

(provide 'emacsvox-re-builder)

;;; emacsvox-re-builder.el ends here
