;;; emacsvox-rst.el --- Speech-enable RST  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable RST An Emacs Interface to rst
;; Keywords: Emacsvox,  Audio Desktop rst
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
;; MERCHANTABILITY or FITNRST FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; RST ==  rst-mode for editing rst text files.
;; This module speech-enables rst-mode.
;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Map Faces

(voice-setup-add-map
 '(
   (rst-block   voice-annotate)
   (rst-external   voice-animate)
   (rst-definition   voice-bolden-medium)
   (rst-directive voice-smoothen)
   (rst-comment   voice-monotone-extra)
   (rst-emphasis1   voice-animate)
   (rst-emphasis2   voice-animate-extra)
   (rst-literal   voice-monotone-medium)
   (rst-reference   voice-bolden)
   (rst-transition   voice-lighten)
   (rst-adornment   voice-animate)
   (rst-level-1 voice-bolden)
   (rst-level-2  voice-bolden-medium)
   (rst-level-3  voice-lighten-medium)
   (rst-level-4 voice-lighten-extra)
   ))

;;;  Speech-enable interactive commands:
(cl-loop
 for f in
 '(rst-promote-region
   rst-shift-region)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'large-movement)
       (emacsvox-speak-line)))))

(cl-loop
 for f in
 '(rst-goto-section rst-forward-section rst-backward-section
                    rst-forward-indented-block)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'section)
       (emacsvox-speak-line)))))

(cl-loop
 for f in
 '(rst-compile rst-compile-alt-toolset
               rst-adjust rst-adjust-section-title
               rst-compile-find-conf rst-compile-pdf-preview
               rst-compile-pseudo-region rst-compile-slides-preview
               rst-display-adornments-hierarchy)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'task-done)
       (emacsvox-speak-line)))))

(defun ems--rst-toc-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'rst-toc :after #'ems--rst-toc-after)

(defun ems--rst-toc-mode-goto-section-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'rst-toc-mode-goto-section :after
            #'ems--rst-toc-mode-goto-section-after)

(defun ems--rst-toc-quit-window-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'close-object) (emacsvox-speak-mode-line)))

(advice-add 'rst-toc-quit-window :after
            #'ems--rst-toc-quit-window-after)

(defun ems--rst-force-fill-paragraph-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'fill-object) (emacsvox-speak-mode-line)))

(advice-add 'rst-force-fill-paragraph :after
            #'ems--rst-force-fill-paragraph-after)

(defun ems--rst-mark-section-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'mark-object) (emacsvox-speak-line)))

(advice-add 'rst-mark-section :after #'ems--rst-mark-section-after)

(cl-loop
 for f in
 '(
   rst-bullet-list-region rst-convert-bullets-to-enumeration
   rst-enumerate-region)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'item)
       (message "Bulletized. ")))))

(cl-loop
 for f in
 '(rst-insert-list rst-insert-list-new-item rst-toc-insert)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'open-object)
       (emacsvox-speak-line)))))
(cl-loop
 for f in
 '(rst-join-paragraph rst-line-block-region
                      rst-straighten-adornments rst-straighten-bullets-region)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'task-done)
       (emacsvox-speak-line)))))

(provide 'emacsvox-rst)
;;;  end of file

