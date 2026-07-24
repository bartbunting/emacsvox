;;; emacsvox-nov.el --- Speech-enable NOV  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable NOV An Emacs Interface to nov
;; Keywords: Emacsvox,  Audio Desktop nov
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
;; MERCHANTABILITY or FITNNOV FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; NOV == Yet Another EPub Reader 
;; Package nov.el is an alternative to Emacsvox's built-in EPub
;; reader.
;; This module speech-enables nov.el
;; In addition, opening an epub using nov results in
;; directory-specific settings being loaded from file
;; @var{emacsvox-speak-directory-settings} ---
;;  That file can set book-specific settings such as speech-rate and
;; punctuation-mode among others.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Interactive Commands:

(defvar emacsvox-nov--advice nil
  "Current Nov targets and their native advice functions.")
(setq emacsvox-nov--advice nil)

(defun emacsvox-nov--register-after-group (targets feedback)
  "Define and register after advice for TARGETS using FEEDBACK."
  (dolist (target targets)
    (let ((advice-function
           (intern (format "emacsvox--advice-%s-after" target))))
      (eval
       `(defun ,advice-function (&rest _)
          ,(format "Provide speech feedback after `%s'." target)
          (when (ems-interactive-p ',target)
            (,feedback))))
      (push (list target :after advice-function) emacsvox-nov--advice))))

(defun emacsvox-nov--open-feedback ()
  "Speak the newly displayed Nov document."
  (emacsvox-icon 'open-object)
  (emacsvox-speak-buffer))

(emacsvox-nov--register-after-group
 '(nov-browse-url nov-display-metadata nov-goto-toc
   nov-next-document nov-previous-document)
 #'emacsvox-nov--open-feedback)

(defun emacsvox-nov--scroll-feedback ()
  "Speak the visible Nov window after scrolling."
  (emacsvox-icon 'scroll)
  (dtk-speak (emacsvox-get-window-contents)))

(emacsvox-nov--register-after-group
 '(nov-scroll-up nov-scroll-down)
 #'emacsvox-nov--scroll-feedback)

(defun emacsvox-nov--install-advice ()
  "Install native advice after Nov loads."
  (dolist (entry emacsvox-nov--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

(with-eval-after-load 'nov
  (emacsvox-nov--install-advice))

;;; Mode Hook:

(defun emacsvox-nov-mode-hook ()
  "Load directory-specific speech settings."
  
  (emacsvox-speak-load-directory-settings default-directory))

(add-hook 'nov-mode-hook #'emacsvox-nov-mode-hook)

(provide 'emacsvox-nov)
;;;  end of file
