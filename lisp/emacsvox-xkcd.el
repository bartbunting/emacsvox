;;; emacsvox-xkcd.el --- Speech-enable XKCD  -*- lexical-binding: t; -*-
;; $Id: emacsvox-xkcd.el 4797 2007-07-16 23:31:22Z tv.raman.tv $
;; $Author: tv.raman.tv $
;; Description:  Speech-enable XKCD An Emacs Interface to xkcd
;; Keywords: Emacsvox,  Audio Desktop xkcd
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
;; MERCHANTABILITY or FITNXKCD FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; XKCD ==  XKCD In Emacs
;; View XKCD comics in Emacs.
;; Speech enables package xkcd
;; Augments it by displaying the alt text and the transcript.

;;   Required modules:
;;; Code:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'json)
(require 'xkcd "xkcd" 'no-error)

;;;  Fix error when loading images on the console:

(defun ems--xkcd-insert-image-around (orig-fun &rest args)
  "no-Op on console"
  (cond ((not window-system) t) (t (apply orig-fun args))))

(advice-add 'xkcd-insert-image :around #'ems--xkcd-insert-image-around)

(defun ems--xkcd-kill-buffer-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'close-object) (emacsvox-speak-mode-line)))

(advice-add 'xkcd-kill-buffer :after #'ems--xkcd-kill-buffer-after)

(defvar xkcd-transcript nil
  "Cache current transcript.")
;; Cache transcript.
;; Content downloaded by the time this is called.
(defun emacsvox-xkcd-get-current-transcript ()
  "Cache current transcript."
  
  (setq 
   xkcd-transcript 
   (cdr 
    (assoc 'transcript (json-read-from-string (xkcd-get-json "" xkcd-cur))))))

(defun ems--xkcd-get-after (&rest _)
  "Insert cached transcript in xkcd-transcript."
  (let ((inhibit-read-only t))
    (emacsvox-xkcd-get-current-transcript) (goto-char (point-max))
    (insert xkcd-alt) (insert "\n")
    (insert
     (format "Transcript: %s"
             (if (zerop (length xkcd-transcript)) "Not available yet."
               xkcd-transcript)))
    (goto-char (point-min)) (emacsvox-icon 'open-object)
    (emacsvox-speak-buffer)))

(advice-add 'xkcd-get :after #'ems--xkcd-get-after)

;;;  Advice browse-url-default-browser:

(defun ems--browse-url-default-browser-around (orig-fun &rest args)
  "Use Emacs browser --- rather than an external browser."
  (when nil (apply orig-fun args)) (eww-browse-url (ad-get-arg 0)))

(advice-add 'browse-url-default-browser :around
            #'ems--browse-url-default-browser-around)

(defun emacsvox-xkcd-open-explanation-browser ()
  "Open explanation of current xkcd in default browser"
  (interactive)
  
  (browse-url (concat "http://www.explainxkcd.com/wiki/index.php/"
                      (number-to-string xkcd-cur))))
(when (boundp 'xkcd-mode-map)
  (define-key xkcd-mode-map "e" 'emacsvox-xkcd-open-explanation-browser))
(provide 'emacsvox-xkcd)
;;;  end of file

