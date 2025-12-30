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
;; Location https://github.com/tvraman/emacsvox
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
(cl-declaim  (optimize  (safety 0) (speed 3)))
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


(defun ems--syslog-whois-reverse-lookup-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-audit 'task-done)
    (message "Displayed WhoIs data in other window.")))


(advice-add 'syslog-whois-reverse-lookup :after
	    #'ems--syslog-whois-reverse-lookup-after)





(defun ems--syslog-filter-dates-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (forward-line -2) (what-line) (emacsvox-icon 'ellipses)))


(advice-add 'syslog-filter-dates :after
	    #'ems--syslog-filter-dates-after)





(defun ems--syslog-filter-lines-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-speak-line) (emacsvox-icon 'ellipses)))


(advice-add 'syslog-filter-lines :after
	    #'ems--syslog-filter-lines-after)





(defun ems--syslog-boot-start-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))


(advice-add 'syslog-boot-start :after #'ems--syslog-boot-start-after)




(cl-loop
 for f in 
 '(
   syslog-append-files syslog-prepend-files 
   syslog-next-file syslog-previous-file
   syslog-move-next-file syslog-move-previous-file syslog-open-files)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-speak-mode-line)
       (emacsvox-icon 'open-object)))))

;;; keymap setup:
(defun emacsvox-syslog-setup ()
  "Setup keybindings."
  
  (define-key syslog-mode-map ","  'emacsvox-speak-previous-field)
  (define-key syslog-mode-map "."  'emacsvox-speak-next-field))

(add-hook 'syslog-mode-load-hook #'emacsvox-syslog-setup)

(provide 'emacsvox-syslog)
;;;  end of file

