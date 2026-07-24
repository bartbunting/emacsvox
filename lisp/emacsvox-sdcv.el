;;; emacsvox-sdcv.el --- Speech-enable SDCV  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable SDCV An Emacs Interface to sdcv
;; Keywords: Emacsvox,  Audio Desktop sdcv
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
;; MERCHANTABILITY or FITNSDCV FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; SDCV ==  Stardict  Dictionary Interface
;; This module sets up Emacsvox for use with sdcv.
;; You need to have  command-line sdcv installed.
;; You can install additional stardict dictionaries, see
;;  https://wiki.archlinux.org/index.php/sdcv
;; This module sets up Emacs module sdcv to use all the installed
;; dictionaries found on the system.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'let-alist)
(require 'emacsvox-preamble)

;;;  Interactive Commands:

(defvar emacsvox-sdcv--advice nil
  "Current SDCV targets and their native advice functions.")
(setq emacsvox-sdcv--advice nil)

(defun emacsvox-sdcv--register-after-group (targets feedback)
  "Define and register after advice for TARGETS using FEEDBACK."
  (dolist (target targets)
    (let ((advice-function
           (intern (format "emacsvox--advice-%s-after" target))))
      (eval
       `(defun ,advice-function (&rest _)
          ,(format "Provide speech feedback after `%s'." target)
          (when (ems-interactive-p ',target)
            (,feedback))))
      (push (list target :after advice-function) emacsvox-sdcv--advice))))

(defun emacsvox-sdcv--task-feedback ()
  "Announce completion of an SDCV search."
  (emacsvox-icon 'task-done))

(emacsvox-sdcv--register-after-group
 '(sdcv-search-input sdcv-search-input+ sdcv-search-pointer
   sdcv-search-pointer+)
 #'emacsvox-sdcv--task-feedback)

(defun emacsvox-sdcv--dictionary-feedback ()
  "Speak the selected SDCV dictionary."
  (emacsvox-speak-line)
  (emacsvox-icon 'large-movement))

(emacsvox-sdcv--register-after-group
 '(sdcv-previous-dictionary sdcv-next-dictionary)
 #'emacsvox-sdcv--dictionary-feedback)

(defun emacsvox-sdcv--line-feedback ()
  "Play the selection icon after SDCV line movement."
  (emacsvox-icon 'select-object))

(emacsvox-sdcv--register-after-group
 '(sdcv-next-line sdcv-prev-line)
 #'emacsvox-sdcv--line-feedback)

(defun emacsvox-sdcv--install-advice ()
  "Install native advice after SDCV loads."
  (dolist (entry emacsvox-sdcv--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

(with-eval-after-load 'sdcv
  (emacsvox-sdcv--install-advice))

(defun emacsvox-sdcv-update-dictionary-list ()
  "Update sdcv dictionary lists if necessary by examining
/usr/share/sdcv/dict"
  
  (let ((installed
         (json-parse-string
          (shell-command-to-string "sdcv -jnl ")
          :object-type 'alist)))
    (setq sdcv-dictionary-simple-list
          (cl-loop
           for d across installed collect 
           (let-alist d  .name)))))

(defun emacsvox-sdcv-setup ()
  "Setup Emacsvox for SDCV."
  
  (emacsvox-sdcv-update-dictionary-list)
  (cl-loop
   for binding in
   '(
     ("n" sdcv-next-dictionary)
     ("p" sdcv-previous-dictionary))
   do
   (emacsvox-keymap-update sdcv-mode-map binding)))

(defun emacsvox--advice-sdcv-quit-after (&rest _)
  "speak."
  (when (ems-interactive-p 'sdcv-quit)
    (emacsvox-icon 'close-object) (emacsvox-speak-mode-line)))

(advice-add 'sdcv-quit :after #'emacsvox--advice-sdcv-quit-after)

(when (bound-and-true-p sdcv-mode-map)
  (emacsvox-sdcv-setup))

(provide 'emacsvox-sdcv)
;;;  end of file
