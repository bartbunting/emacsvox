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



;;; Commentary:
;; Provide additional advice to perl-mode 
;;; Code:

;;;  requires
(require 'emacsvox-preamble)
(require 'perl-mode)

;;;   Advice electric insertion to talk:
(defun emacsvox--advice-perl-electric-terminator-after (&rest _)
  "Speak the character inserted by the legacy Perl electric command."
  (when (ems-interactive-p 'perl-electric-terminator)
    (emacsvox-speak-this-char last-input-event)))

(unless (and (boundp 'post-self-insert-hook)
             post-self-insert-hook
             (memq 'emacsvox-post-self-insert-hook post-self-insert-hook))
  (advice-add 'perl-electric-terminator :after
              #'emacsvox--advice-perl-electric-terminator-after))

;;;   Program structure:

(defun emacsvox--advice-mark-perl-function-after (&rest _)
  "speak"
  (when (ems-interactive-p 'mark-perl-function)
    (emacsvox-icon 'mark-object) (message "Marked procedure")))

(advice-add 'mark-perl-function :after
            #'emacsvox--advice-mark-perl-function-after)

(defun emacsvox--advice-perl-beginning-of-function-after (&rest _)
  "speak."
  (when (ems-interactive-p 'perl-beginning-of-function)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'perl-beginning-of-function :after
            #'emacsvox--advice-perl-beginning-of-function-after)

(defun emacsvox--advice-perl-end-of-function-after (&rest _)
  "speak."
  (when (ems-interactive-p 'perl-end-of-function)
    (emacsvox-icon 'large-movement)))

(advice-add 'perl-end-of-function :after
            #'emacsvox--advice-perl-end-of-function-after)

(provide  'emacsvox-perl)
