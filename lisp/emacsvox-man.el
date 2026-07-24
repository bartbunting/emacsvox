;;; emacsvox-man.el --- Speech enable Man -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $ 
;; DescriptionEmacsvox extensions for man-mode
;; Keywords:emacsvox, audio interface to emacs man 
;;;   LCD Archive entry: 

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com 
;; A speech interface to Emacs |
;; 
;;  $Revision: 4546 $ | 
;; Location https://github.com/robertmeta/emacsvox
;; 

;;;   Copyright:
;; Copyright (C) 1995 -- 2024, T. V. Raman 
;; Copyright (c) 1995 by T. V. Raman 
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



;;; Commentary:
;; Provide additional advice to man-mode 
;;; Code:
;;; Code:

;;  Required modules: 

;;; Code:
(require 'emacsvox-preamble)
(require 'voice-setup)
(require 'man)

;;;   Configure man

(cl-declaim (special Man-switches system-type))

(when (eq system-type 'gnu/linux)
  (setq Man-switches "-a"))

;;;  Map Faces:

(voice-setup-add-map
 '(
   (Man-overstrike  voice-bolden-medium)
   (Man-reverse voice-animate)
   (Man-underline voice-lighten)))

;;;   advice interactive commands 

(defun emacsvox--advice-Man-mode-after (&rest _)
  "Fixup variables paragraph-start and paragraph-separate.\nAlso provide an auditory icon"
  (setq paragraph-start "^[     \n\f]*$" paragraph-separate
        "^[     \n\f]*$")
  (modify-syntax-entry 10 " ")
  (setq imenu-generic-expression
        '((nil "\n\\([A-Z].*\\)" 1)
          ("*Subsections*" "^   \\([A-Z].*\\)" 1)))
  (dtk-set-punctuations 'all)
  (emacsvox-pronounce-refresh-pronunciations) (emacsvox-icon 'help))

(advice-add 'Man-mode :after #'emacsvox--advice-Man-mode-after)

(defun emacsvox--advice-Man-goto-section-after (&rest _)
  "Speak the line"
  (when (ems-interactive-p 'Man-goto-section)
    (emacsvox-icon 'section) (emacsvox-speak-line)))

(advice-add 'Man-goto-section :after
            #'emacsvox--advice-Man-goto-section-after)

(defun emacsvox--advice-Man-goto-page-after (&rest _)
  "Speak the line"
  (when (ems-interactive-p 'Man-goto-page)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'Man-goto-page :after
            #'emacsvox--advice-Man-goto-page-after)

(defun emacsvox--advice-Man-next-manpage-after (&rest _)
  "Speak the line"
  (when (ems-interactive-p 'Man-next-manpage)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'Man-next-manpage :after
            #'emacsvox--advice-Man-next-manpage-after)

(defun emacsvox--advice-Man-previous-manpage-after (&rest _)
  "Speak the line"
  (when (ems-interactive-p 'Man-previous-manpage)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'Man-previous-manpage :after
            #'emacsvox--advice-Man-previous-manpage-after)

(defun emacsvox--advice-Man-next-section-after (&rest _)
  "Speak the line"
  (when (ems-interactive-p 'Man-next-section)
    (emacsvox-icon 'section) (emacsvox-speak-line)))

(advice-add 'Man-next-section :after
            #'emacsvox--advice-Man-next-section-after)

(defun emacsvox--advice-Man-previous-section-after (&rest _)
  "Speak the line"
  (when (ems-interactive-p 'Man-previous-section)
    (emacsvox-icon 'section) (emacsvox-speak-line)))

(advice-add 'Man-previous-section :after
            #'emacsvox--advice-Man-previous-section-after)

(defun emacsvox--advice-Man-goto-see-also-section-after (&rest _)
  "Speak the line"
  (when (ems-interactive-p 'Man-goto-see-also-section)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'Man-goto-see-also-section :after
            #'emacsvox--advice-Man-goto-see-also-section-after)

(defun emacsvox--advice-Man-kill-after (&rest _)
  "Announce buffer that is current"
  (when (ems-interactive-p 'Man-kill)
    (emacsvox-icon 'close-object) (emacsvox-speak-mode-line)))

(advice-add 'Man-kill :after #'emacsvox--advice-Man-kill-after)

(defun emacsvox--advice-man-after (&rest _)
  "Speak the displayed manual page's mode line."
  (when (ems-interactive-p 'man)
    (emacsvox-speak-mode-line)))

(advice-add 'man :after #'emacsvox--advice-man-after)

;;;   Additional commands

(defun emacsvox-man-speak-this-section ()
  "Speak current section"
  (interactive)
  (save-excursion
    (let ((start (point))
          (end nil))
      (condition-case nil
          (progn
            (Man-next-section 1)
            (setq end (point)))
        (error (setq end (point-max))))
      (emacsvox-icon 'section)
      (emacsvox-speak-region start end))))

(defun emacsvox-man-browse-man-page ()
  "Browse the man page --read it a paragraph at a time"
  (interactive)
  (emacsvox-execute-repeatedly 'forward-paragraph))

(autoload 'emacsvox-view-line-to-top 
  "emacsvox-view" "Move current line to top of window"  t)

(cl-declaim (special  Man-mode-map))
(define-key Man-mode-map ";"
            'emacsvox-speak-current-window)
(define-key Man-mode-map "\M-j" 'imenu)
(define-key Man-mode-map "\M- " 'emacsvox-man-speak-this-section)
(define-key Man-mode-map "." 'emacsvox-man-browse-man-page)
(define-key Man-mode-map "t" 'emacsvox-view-line-to-top)
(define-key Man-mode-map "'" 'emacsvox-speak-rest-of-buffer)
(define-key Man-mode-map "N" 'emacsvox-speak-face-forward)
(define-key Man-mode-map "P" 'emacsvox-speak-face-backward)
(define-key Man-mode-map "[" 'backward-paragraph)
(define-key Man-mode-map "]" 'forward-paragraph)

(provide  'emacsvox-man)
