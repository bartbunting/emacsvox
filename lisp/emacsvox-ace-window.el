;;; emacsvox-ace-window.el --- Speech-enable ACE-WINDOW  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable ACE-WINDOW An Emacs Interface to ace-window
;; Keywords: Emacsvox,  Audio Desktop ace-window
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;;
;;  $Revision: 4532 $ |
;; Location https://github.com/robertmeta/emacsvox
;;

;;;   Copyright:

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; All Rights Reserved.
;;
;; This file is not part of GNU Emacs, but the same permissions apply.
;;
;; GNU Emacs is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; ACE-WINDOW == ace-window
;; Speech-enable ace-window for fast window switching.
;; Provides auditory feedback when selecting, swapping, deleting,
;; and maximizing windows.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'ace-window nil 'noerror)

;;;  Map Faces:

(voice-setup-add-map
 '(
   (aw-leading-char-face voice-animate)
   (aw-background-face voice-monotone-extra)
   (aw-mode-line-face voice-bolden)))

;;;  Advice Interactive Commands:

(defadvice ace-window (after emacsvox pre act comp)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object)
    (emacsvox-speak-mode-line)))

(defadvice ace-swap-window (after emacsvox pre act comp)
  "speak."
  (when (ems-interactive-p)
    (dtk-speak "Swapped windows")
    (emacsvox-icon 'task-done)))

(defadvice ace-delete-window (after emacsvox pre act comp)
  "speak."
  (when (ems-interactive-p)
    (dtk-speak "Deleted window")
    (emacsvox-icon 'close-object)
    (emacsvox-speak-mode-line)))

(defadvice ace-delete-other-windows (after emacsvox pre act comp)
  "speak."
  (when (ems-interactive-p)
    (dtk-speak "One window")
    (emacsvox-icon 'close-object)
    (emacsvox-speak-mode-line)))

(defadvice ace-maximize-window (after emacsvox pre act comp)
  "speak."
  (when (ems-interactive-p)
    (dtk-speak "Maximized window")
    (emacsvox-icon 'select-object)
    (emacsvox-speak-mode-line)))

(provide 'emacsvox-ace-window)
;;;  end of file
