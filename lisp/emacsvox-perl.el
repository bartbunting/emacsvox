;;; emacsvox-perl.el --- Speech enable Perl Mode  -*- lexical-binding: t; -*- 
;;
;; $Author: tv.raman.tv $ 
;; DescriptionEmacsvox extensions for perl-mode
;; Keywords:emacsvox, audio interface to emacs perl
;;;   LCD Archive entry: 

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com 
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ | 
;; Location https://github.com/tvraman/emacsvox
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



;;; Commentary:
;; Provide additional advice to perl-mode 
;;; Code:

;;;  requires
(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacsvox-preamble)

;;;   Advice electric insertion to talk:
(unless (and (boundp 'post-self-insert-hook)
             post-self-insert-hook
             (memq 'emacsvox-post-self-insert-hook post-self-insert-hook))
  (defadvice electric-perl-terminator  (after emacsvox pre act comp)
    "Speak what you inserted."
    (when (ems-interactive-p)
      (emacsvox-speak-this-char last-input-event))))

;;;   Program structure:

(defun ems--mark-perl-function-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'mark-object) (message "Marked procedure")))

(advice-add 'mark-perl-function :after #'ems--mark-perl-function-after)

(defun ems--perl-beginning-of-function-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'perl-beginning-of-function :after
            #'ems--perl-beginning-of-function-after)

(defun ems--perl-end-of-function-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'large-movement)))

(advice-add 'perl-end-of-function :after
            #'ems--perl-end-of-function-after)

(provide  'emacsvox-perl)

