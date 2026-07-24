;;; emacsvox-syslog.el --- Speech-enable SYSLOG -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable SYSLOG-MODE An Emacs Interface to syslog-mode
;; Keywords: Emacsvox,  Audio Desktop syslog-mode
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ |
;; Location https://github.com/robertmeta/emacsvox
;; 

;;;   Copyright:

;; Copyright (C) 1995 -- 2007, 2019, T. V. Raman
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
;; MERCHANTABILITY or FITNSYSLOG-MODE FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; SYSLOG-MODE ==  Working with various log files.
;; Install package syslog-mode from melpa.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Map Faces:

(voice-setup-add-map 
 '(
   (syslog-debug voice-animate)
   (syslog-error voice-bolden)
   (syslog-file voice-smoothen-extra)
   (syslog-hide voice-annotate)
   (syslog-hour voice-monotone-extra)
   (syslog-info voice-animate)
   (syslog-ip voice-lighten)
   (syslog-su voice-bolden)
   (syslog-warn voice-bolden)))

;;;  Interactive Commands:

(defun emacsvox--advice-syslog-whois-reverse-lookup-after (&rest _)
  "speak."
  (when (ems-interactive-p 'syslog-whois-reverse-lookup)
    (emacsvox-audit 'task-done)
    (message "Displayed WhoIs data in other window.")))

(defun emacsvox--advice-syslog-filter-dates-after (&rest _)
  "speak."
  (when (ems-interactive-p 'syslog-filter-dates)
    (forward-line -2) (what-line) (emacsvox-icon 'ellipses)))

(defun emacsvox--advice-syslog-filter-lines-after (&rest _)
  "speak."
  (when (ems-interactive-p 'syslog-filter-lines)
    (emacsvox-speak-line) (emacsvox-icon 'ellipses)))

(defun emacsvox--advice-syslog-boot-start-after (&rest _)
  "speak."
  (when (ems-interactive-p 'syslog-boot-start)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(defconst emacsvox-syslog--file-targets
  '(syslog-append-files
    syslog-prepend-files
    syslog-next-file
    syslog-previous-file
    syslog-move-next-file
    syslog-move-previous-file
    syslog-open-files)
  "Syslog commands that open or move between log files.")

(cl-loop
 for target in emacsvox-syslog--file-targets
 for advice-function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "speak."
     (when (ems-interactive-p ',target)
       (emacsvox-speak-mode-line)
       (emacsvox-icon 'open-object)))))

(defconst emacsvox-syslog--advice-targets
  (append
   '(syslog-whois-reverse-lookup
     syslog-filter-dates
     syslog-filter-lines
     syslog-boot-start)
   emacsvox-syslog--file-targets)
  "Current Syslog targets that receive native after advice.")

(defun emacsvox-syslog--install-advice ()
  "Install advice after the optional Syslog Mode package loads."
  (dolist (target emacsvox-syslog--advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target :after function '((name . emacsvox)))))))

(with-eval-after-load 'syslog-mode
  (emacsvox-syslog--install-advice))

;;; keymap setup:
(defun emacsvox-syslog-setup ()
  "Setup keybindings."
  
  (define-key syslog-mode-map ","  'emacsvox-speak-previous-field)
  (define-key syslog-mode-map "."  'emacsvox-speak-next-field))

(add-hook 'syslog-mode-load-hook #'emacsvox-syslog-setup)

(provide 'emacsvox-syslog)
;;;  end of file
