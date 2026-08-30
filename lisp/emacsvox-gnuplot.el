;;; emacsvox-gnuplot.el --- speech-enable gnuplot -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman<tv.raman.tv@gmail.com>
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox, WWW interaction
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

;; This module speech-enables gnuplot-mode
;; an Emacs add-on that enables fluent interaction with
;; gnuplot.
;; Use gnuplot to generate plots of mathematical functions
;; for inclusion in documents.

;;; Code:

;;; Dependencies and declarations:

(require 'emacsvox-preamble)

;;;  advice interactive commands

(defun emacsvox--advice-gnuplot-send-region-to-gnuplot-after (&rest _)
  "Speak status."
  (when (ems-interactive-p 'gnuplot-send-region-to-gnuplot)
    (emacsvox-icon 'select-object) (emacsvox-speak-other-window)))

(defun emacsvox--advice-gnuplot-send-line-to-gnuplot-after (&rest _)
  "Speak status."
  (when (ems-interactive-p 'gnuplot-send-line-to-gnuplot)
    (emacsvox-icon 'select-object) (emacsvox-speak-other-window)))

(defun emacsvox--advice-gnuplot-send-line-and-forward-after (&rest _)
  "Speak status."
  (when (ems-interactive-p 'gnuplot-send-line-and-forward)
    (emacsvox-icon 'select-object) (emacsvox-speak-other-window)))

(defun emacsvox--advice-gnuplot-send-buffer-to-gnuplot-after (&rest _)
  "Speak status."
  (when (ems-interactive-p 'gnuplot-send-buffer-to-gnuplot)
    (emacsvox-icon 'select-object) (emacsvox-speak-other-window)))

(defun emacsvox--advice-gnuplot-send-file-to-gnuplot-after (&rest _)
  "Speak status."
  (when (ems-interactive-p 'gnuplot-send-file-to-gnuplot)
    (emacsvox-icon 'select-object) (emacsvox-speak-other-window)))

(defun emacsvox--advice-gnuplot-delchar-or-maybe-eof-around
    (orig-fun &rest args)
  "Speak character you're deleting."
  (when (ems-interactive-p 'gnuplot-delchar-or-maybe-eof)
    (cond
     ((= (point) (point-max))
      (message "Sending EOF to comint process"))
     (t
      (emacsvox-speak-edit-operation 'deletion)
      (emacsvox-speak-char t))))
  (apply orig-fun args))

(defun emacsvox--advice-gnuplot-kill-comint-buffer-after (&rest _)
  "speak."
  (when (ems-interactive-p 'gnuplot-kill-comint-buffer)
    (emacsvox-icon 'close-object) (emacsvox-speak-mode-line)))

(defun emacsvox--advice-gnuplot-show-comint-buffer-after (&rest _)
  "Speak status."
  (when (ems-interactive-p 'gnuplot-show-comint-buffer)
    (emacsvox-icon 'select-object) (emacsvox-speak-mode-line)))

(defun emacsvox--advice-gnuplot-indent-line-after (&rest _)
  "Speak line we indented."
  (when (ems-interactive-p 'gnuplot-indent-line)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(defun emacsvox--advice-gnuplot-negate-option-after (&rest _)
  "Speak line we negated."
  (when (ems-interactive-p 'gnuplot-negate-option)
    (emacsvox-icon 'select-object) (emacsvox-speak-line)))

(defconst emacsvox-gnuplot--advice
  '((gnuplot-send-region-to-gnuplot :after
     emacsvox--advice-gnuplot-send-region-to-gnuplot-after)
    (gnuplot-send-line-to-gnuplot :after
     emacsvox--advice-gnuplot-send-line-to-gnuplot-after)
    (gnuplot-send-line-and-forward :after
     emacsvox--advice-gnuplot-send-line-and-forward-after)
    (gnuplot-send-buffer-to-gnuplot :after
     emacsvox--advice-gnuplot-send-buffer-to-gnuplot-after)
    (gnuplot-send-file-to-gnuplot :after
     emacsvox--advice-gnuplot-send-file-to-gnuplot-after)
    (gnuplot-delchar-or-maybe-eof :around
     emacsvox--advice-gnuplot-delchar-or-maybe-eof-around)
    (gnuplot-kill-comint-buffer :after
     emacsvox--advice-gnuplot-kill-comint-buffer-after)
    (gnuplot-show-comint-buffer :after
     emacsvox--advice-gnuplot-show-comint-buffer-after)
    (gnuplot-indent-line :after
     emacsvox--advice-gnuplot-indent-line-after)
    (gnuplot-negate-option :after
     emacsvox--advice-gnuplot-negate-option-after))
  "Current Gnuplot targets and their native advice functions.")

(defun emacsvox-gnuplot--install-advice ()
  "Install native advice for loaded Gnuplot commands."
  (dolist (entry emacsvox-gnuplot--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox-gnuplot)))))))

(with-eval-after-load 'gnuplot
  (emacsvox-gnuplot--install-advice))

(emacsvox-gnuplot--install-advice)

(add-hook 'gnuplot-mode-hook
          #'(lambda nil
              (tts-apply-punctuation-mode-policy)))

(provide 'emacsvox-gnuplot)

;;; emacsvox-gnuplot.el ends here
