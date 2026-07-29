;;; emacsvox-yaml.el --- Speech-enable YAML  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable YAML An Emacs Interface to yaml
;; Keywords: Emacsvox,  Audio Desktop yaml
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ |
;; Location https://github.com/robertmeta/emacsvox
;; 

;;;   Copyright:
;; Copyright (C) 1995 -- 2007, 2011, T. V. Raman
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
;; MERCHANTABILITY or FITNYAML FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; YAML == Yet Another Markup Language
;; This module speech-enables yaml-mode.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Interactive Commands:

'(
  yaml-electric-backspace
  yaml-electric-bar-and-angle

  yaml-narrow-to-block-literal
  )

(defun emacsvox--advice-yaml-indent-line-after (&rest _)
  "speak."
  (when (ems-interactive-p 'yaml-indent-line)
    (emacsvox-speak-line)))

(defun emacsvox--advice-yaml-mode-after (&rest _)
  "speak."
  (unless emacsvox-audio-indentation
    (emacsvox-toggle-audio-indentation)))

(defun emacsvox--advice-yaml-fill-paragraph-after (&rest _)
  "speak."
  (when (ems-interactive-p 'yaml-fill-paragraph)
    (emacsvox-icon 'fill-object)))

(defun emacsvox--advice-yaml-electric-backspace-around (orig-fun &rest args)
  "speak."
  (let ((result (apply orig-fun args)))
    (when (ems-interactive-p 'yaml-electric-backspace)
      (emacsvox-speak-edit-operation 'deletion)
      (emacsvox-speak-this-char (preceding-char)))
    result))

(defun emacsvox--advice-yaml-electric-bar-and-angle-after (&rest _)
  "speak."
  (when (ems-interactive-p 'yaml-electric-bar-and-angle)
    (emacsvox-speak-line)))

(defun emacsvox--advice-yaml-electric-dash-and-dot-after (&rest _)
  "speak."
  (when (ems-interactive-p 'yaml-electric-dash-and-dot)
    (emacsvox-speak-line)))

(defconst emacsvox-yaml--advice
  '((yaml-indent-line :after emacsvox--advice-yaml-indent-line-after)
    (yaml-mode :after emacsvox--advice-yaml-mode-after)
    (yaml-fill-paragraph :after
     emacsvox--advice-yaml-fill-paragraph-after)
    (yaml-electric-backspace :around
     emacsvox--advice-yaml-electric-backspace-around)
    (yaml-electric-bar-and-angle :after
     emacsvox--advice-yaml-electric-bar-and-angle-after)
    (yaml-electric-dash-and-dot :after
     emacsvox--advice-yaml-electric-dash-and-dot-after))
  "Current YAML Mode targets and their native advice functions.")

(defun emacsvox-yaml--install-advice ()
  "Install advice after the optional YAML Mode package loads."
  (dolist (entry emacsvox-yaml--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

(with-eval-after-load 'yaml-mode
  (emacsvox-yaml--install-advice))

(provide 'emacsvox-yaml)
;;;  end of file
