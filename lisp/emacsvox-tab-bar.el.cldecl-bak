;;; emacsvox-tab-bar.el --- Speech-enable tab-bar  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable tab-bar An Emacs Interface to tab-bar
;; Keywords: Emacsvox,  Audio Desktop tab-bar
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ |
;; Location https://github.com/tvraman/emacsvox
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
;; MERCHANTABILITY or FITNtab-bar FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:

;; tab-bar == tabs for window configuration.
;; Speech-enable tab-bar interaction.  If you have
;; @var{browse-url-new-window-flag} set to T to have EWW open Web
;; pages in a new buffer, then set
;; @var{eww-browse-url-new-window-is-tab} to nil to avoid leaking
;; tabs.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacsvox-preamble)

;;;  Map Faces:

(voice-setup-add-map 
 '(
   (tab-bar voice-bolden)
   (tab-bar-tab voice-animate)
   (tab-bar-tab-inactive voice-smoothen)
   (tab-line voice-lighten)))

;;; Helpers:

(defsubst emacsvox-tab-bar-speak-tab-name ()
  "Speak name of current tab."
  (emacsvox-icon 'tick-tick)
  (dtk-notify
   (format "%s"
           (alist-get 'name (alist-get 'current-tab (tab-bar-tabs))))))

;;;  Interactive Commands:


(defun ems--tab-bar-switch-to-tab-after (&rest _)
  "speak."
  (when (ems-interactive-p) (emacsvox-tab-bar-speak-tab-name)))


(advice-add 'tab-bar-switch-to-tab :after
	    #'ems--tab-bar-switch-to-tab-after)




(cl-loop
 for f in 
 '(
   tab-next tab-previous tab-select
   tab-bar-select-tab tab-bar-select-tab-by-name
   tab-bar-switch-to-next-tab tab-bar-switch-to-prev-tab
   tab-bar-switch-to-recent-tab)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'select-object)
       (emacsvox-tab-bar-speak-tab-name)))))

(cl-loop
 for f in 
 '(
   tab-bar-close-other-tabs tab-bar-close-tab
   tab-close tab-close-other)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'close-object)
       (emacsvox-tab-bar-speak-tab-name)))))

(cl-loop
 for f in 
 '(tab-new tab-bar-new-tab)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'open-object)
       (emacsvox-tab-bar-speak-tab-name)))))


(defun ems--tab-bar-close-tab-by-name-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (dtk-speak (message "Closed tab %s" (ad-get-arg 0)))
    (emacsvox-icon 'close-object)))


(advice-add 'tab-bar-close-tab-by-name :after
	    #'ems--tab-bar-close-tab-by-name-after)




;;; tab-list commands:

(cl-loop
 for f in 
 '(tab-list tab-bar-list)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'open-object)))))


(defun ems--tab-bar-list-execute-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'task-done)))


(advice-add 'tab-bar-list-execute :after
	    #'ems--tab-bar-list-execute-after)




(cl-loop
 for f in 
 '(tab-bar-list-prev-line tab-bar-list-next-line)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'large-movement)
       (emacsvox-speak-line)))))


(defun ems--tab-bar-list-unmark-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'unmark-object) (emacsvox-speak-line)))


(advice-add 'tab-bar-list-unmark :after
	    #'ems--tab-bar-list-unmark-after)




(cl-loop
 for f in 
 '(tab-bar-list-delete  tab-bar-list-delete-backwards)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'delete-object)
       (emacsvox-speak-line)))))


(defun ems--tab-bar-list-select-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object) (emacsvox-speak-line)))


(advice-add 'tab-bar-list-select :after
	    #'ems--tab-bar-list-select-after)




(provide 'emacsvox-tab-bar)
;;;  end of file

