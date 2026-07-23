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

(defun emacsvox--advice-tab-bar-switch-to-tab-after (&rest _)
  "Speak the tab selected by an interactive name-based switch."
  (when (ems-interactive-p 'tab-bar-switch-to-tab)
    (emacsvox-tab-bar-speak-tab-name)))

(advice-add
 'tab-bar-switch-to-tab :after
 #'emacsvox--advice-tab-bar-switch-to-tab-after
 '((name . emacsvox)))

(cl-loop
 for target in
 '(
   tab-next tab-previous tab-select
   tab-bar-select-tab tab-bar-select-tab-by-name
   tab-bar-switch-to-next-tab tab-bar-switch-to-prev-tab
   tab-bar-switch-to-recent-tab)
 for function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after interactively selecting a tab."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'select-object)
         (emacsvox-tab-bar-speak-tab-name)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(cl-loop
 for target in
 '(
   tab-bar-close-other-tabs tab-bar-close-tab
   tab-close tab-close-other)
 for function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after interactively closing tabs."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'close-object)
         (emacsvox-tab-bar-speak-tab-name)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(cl-loop
 for target in
 '(tab-new tab-bar-new-tab)
 for function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after interactively creating a tab."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'open-object)
         (emacsvox-tab-bar-speak-tab-name)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-tab-bar-close-tab-by-name-after (name)
  "Report interactively closing the tab called NAME."
  (when (ems-interactive-p 'tab-bar-close-tab-by-name)
    (dtk-speak (message "Closed tab %s" name))
    (emacsvox-icon 'close-object)))

(advice-add
 'tab-bar-close-tab-by-name :after
 #'emacsvox--advice-tab-bar-close-tab-by-name-after
 '((name . emacsvox)))

;;; Tab Switcher commands:

(cl-loop
 for target in '(tab-list tab-switcher)
 for function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue after interactively opening the Tab Switcher."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'open-object)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-tab-switcher-execute-after (&rest _)
  "Cue after interactively deleting marked tabs."
  (when (ems-interactive-p 'tab-switcher-execute)
    (emacsvox-icon 'task-done)))

(advice-add
 'tab-switcher-execute :after
 #'emacsvox--advice-tab-switcher-execute-after
 '((name . emacsvox)))

(cl-loop
 for target in '(tab-switcher-prev-line tab-switcher-next-line)
 for function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after interactive Tab Switcher movement."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'large-movement)
         (emacsvox-speak-line)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(cl-loop
 for target in '(tab-switcher-unmark tab-switcher-backup-unmark)
 for function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after interactively unmarking a tab."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'unmark-object)
         (emacsvox-speak-line)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(cl-loop
 for target in '(tab-switcher-delete tab-switcher-delete-backwards)
 for function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after interactively marking a tab for deletion."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'delete-object)
         (emacsvox-speak-line)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-tab-switcher-select-after (&rest _)
  "Cue and speak after interactively selecting a tab."
  (when (ems-interactive-p 'tab-switcher-select)
    (emacsvox-icon 'select-object)
    (emacsvox-speak-line)))

(advice-add
 'tab-switcher-select :after
 #'emacsvox--advice-tab-switcher-select-after
 '((name . emacsvox)))

(provide 'emacsvox-tab-bar)
;;;  end of file
