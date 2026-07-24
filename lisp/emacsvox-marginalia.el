;;; emacsvox-marginalia.el --- Speech-enable Marginalia  -*- lexical-binding: t; -*-
;; $Author: Robert Melton $
;; Description:  Speech-enable Marginalia completion annotations
;; Keywords: Emacsvox, Audio Desktop, Marginalia, completion
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
;; MARGINALIA == Rich annotations for completion candidates.
;; Marginalia adds informative annotations in the minibuffer margin,
;; e.g., docstrings next to M-x commands, file sizes next to filenames.
;; Works with completion UIs like Vertico and Consult.
;; This module maps marginalia faces to voice personalities.

;;; Code:

;;   Required modules:

(require 'emacsvox-preamble)
(require 'marginalia nil 'noerror)

;;;  Map Faces:

(voice-setup-add-map
 '(
   (marginalia-key voice-bolden)
   (marginalia-type voice-animate)
   (marginalia-char voice-lighten)
   (marginalia-lighter voice-smoothen)
   (marginalia-list voice-monotone)
   (marginalia-number voice-lighten)
   (marginalia-string voice-smoothen)
   (marginalia-symbol voice-animate)
   (marginalia-value voice-smoothen)
   (marginalia-null voice-monotone)
   (marginalia-true voice-brighten)
   (marginalia-false voice-monotone)
   (marginalia-date voice-lighten)
   (marginalia-size voice-lighten)
   (marginalia-file-name voice-bolden)
   (marginalia-file-priv-dir voice-bolden)
   (marginalia-file-priv-exec voice-animate)
   (marginalia-file-priv-link voice-lighten)
   (marginalia-file-priv-read voice-smoothen)
   (marginalia-file-priv-write voice-brighten)
   (marginalia-file-priv-other voice-monotone)
   (marginalia-documentation voice-annotate)
   (marginalia-file-modes voice-monotone)
   (marginalia-file-owner voice-smoothen)
   (marginalia-modified voice-bolden)
   (marginalia-installed voice-brighten)))

;;;  Advice Interactive Commands:

(defun emacsvox--advice-marginalia-mode-after (&rest _)
  "Announce marginalia-mode state."
  (when (ems-interactive-p 'marginalia-mode)
    (emacsvox-icon (if marginalia-mode 'on 'off))
    (message "Turned %s marginalia mode."
             (if marginalia-mode "on" "off"))))

(defun emacsvox--advice-marginalia-cycle-after (&rest _)
  "Announce the new annotator after cycling."
  (when (ems-interactive-p 'marginalia-cycle)
    (emacsvox-icon 'select-object)
    (tts-speak "Cycled marginalia annotator.")))

(defconst emacsvox-marginalia--advice
  '((marginalia-mode :after emacsvox--advice-marginalia-mode-after)
    (marginalia-cycle :after emacsvox--advice-marginalia-cycle-after))
  "Current Marginalia targets and their native advice functions.")

(defun emacsvox-marginalia--install-advice ()
  "Install native advice for loaded Marginalia commands."
  (dolist (entry emacsvox-marginalia--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function
                    '((name . emacsvox-marginalia)))))))

(with-eval-after-load 'marginalia
  (emacsvox-marginalia--install-advice))

(emacsvox-marginalia--install-advice)

(provide 'emacsvox-marginalia)
;;;  end of file
