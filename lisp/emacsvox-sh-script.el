;;; emacsvox-sh-script.el --- Speech enable script -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:   extension to speech enable sh-script 
;; Keywords: Emacsvox, Audio Desktop
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ |
;; Location https://github.com/robertmeta/emacsvox
;; 

;;;   Copyright:

;; Copyright (C) 1995 -- 2024, T. V. Raman<tv.raman.tv@gmail.com>
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

;;  required modules

(require 'emacsvox-preamble)

;;; Commentary:

;; This module speech-enables sh-script.el 

;;; Code:

;;;   advice interactive commands

(defun ems--sh-mode-after (&rest _)
  "Speech-enable sh-script editing." (dtk-set-punctuations 'all)
  (unless emacsvox-audio-indentation
    (emacsvox-toggle-audio-indentation))
  (emacsvox-speak-mode-line))

(advice-add 'sh-mode :after #'ems--sh-mode-after)

(defun ems--sh-indent-line-after (&rest _)
  "speak to indicate indentation."
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (emacsvox-speak-current-column)))

(advice-add 'sh-indent-line :after #'ems--sh-indent-line-after)

(unless (and (boundp 'post-self-insert-hook)
             post-self-insert-hook
             (memq 'emacsvox-post-self-insert-hook post-self-insert-hook))
  (defadvice sh-assignment (after emacsvox pre act comp)
    "Speak assignment as it is inserted."
    (when (ems-interactive-p)
      (emacsvox-speak-this-char (preceding-char)))))

(defun ems--sh-maybe-here-document-around (orig-fun &rest args)
  "Spoken feedback based on what we insert."
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p)
      (let ((start (point)))
        (apply orig-fun args)
        (if (= (point) (1+ start))
            (emacsvox-speak-this-char last-input-event)
          (message "Started a shell here  document."))))
     (t (apply orig-fun args)))
    result))

(advice-add 'sh-maybe-here-document :around
            #'ems--sh-maybe-here-document-around)

(defun ems--sh-newline-and-indent-after (&rest _)
  "speak to indicate indentation."
  (when (ems-interactive-p) (emacsvox-speak-line)))

(advice-add 'sh-newline-and-indent :after
            #'ems--sh-newline-and-indent-after)

(defun ems--sh-beginning-of-command-after (&rest _)
  "Speak point moved to."
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'sh-beginning-of-command :after
            #'ems--sh-beginning-of-command-after)

(defun ems--sh-end-of-command-after (&rest _)
  "Speak point moved to."
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'sh-end-of-command :after #'ems--sh-end-of-command-after)

;;;  advice skeleton insertion 
(unless (and (boundp 'post-self-insert-hook)
             post-self-insert-hook
             (memq 'emacsvox-post-self-insert-hook post-self-insert-hook))
  (defadvice skeleton-pair-insert-maybe(around emacsvox pre
                                               act comp)
    "Speak what you inserted."
    (cond
     ((ems-interactive-p)
      (let ((orig (point)))
        ad-do-it
        (emacsvox-speak-region orig (point))))
     (t ad-do-it))
    ad-return-value))

(provide 'emacsvox-sh-script)
;;;  end of file

