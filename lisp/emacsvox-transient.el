;;; emacsvox-transient.el --- TRANSIENT  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable TRANSIENT An Emacs Interface to transient
;; Keywords: Emacsvox,  Audio Desktop transient
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
;; MERCHANTABILITY or FITNTRANSIENT FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; TRANSIENT ==  Transient commands --- used by magit and friends.
;; This module speech-enables transient.

;; @subsection Introduction
;; 
;; Package Transient is similar to package Hydra in the sense that it
;; can be used to create a sequence of chained/hierarchical commands
;; that are invoked via a sequence of keys. It is used by Magit for
;; dispatching to the various Git commands.  Speech-enabling package
;; Transient results in the various interactive commands producing
;; auditory feedback. Transient shows an ephemeral window with the
;; currently available commands, Emacsvox speech-enables
;; transient--show to cache that content so it can be browsed if
;; desired.
;; 
;; Finally, this module defines a new minor mode called
;; transient-emacsvox  that  enables  interactive browsing of the
;; contents displayed temporarily. Note that without this
;; functionality, learning complex packages like Magit would be difficult
;; because  the list of available commands can be very long.
;; @subsection Recommended Customizations
;; I use the following customizations via .custom, adjust to taste,
;; but use these only after reading the transient info documentations.
;; @itemize
;; @item transient-force-single-column: t
;; @item  transient-show-menu:  1
;; @item transient-enable-menu-navigation:  t
;; @end itemize
;; 
;; this pops up the transient buffer after a short delay  and lets
;; you move through the buttons with the    up/down arrows. 
;; @subsection Browsing Contents Of transient--show
;; 
;; When executing a command defined via Transient --- e.g. command
;; Magit-dispatch and friends, 
;; @code{?} twice to suspend the transient   --- this calls
;; 2@code{transient-suspend}. Emacsvox now
;; displays a  *transient-emacsvox* buffer that displays the contents of the
;; most recently displayed transient choices. Pressing @kbd {r} resumes
;; the transient; Pressing @kbd{C-q} quits the transient.
;; 
;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'derived)
(require 'transient)

;;; Map Faces:

(voice-setup-add-map
 '(
   (transient-active-infix voice-animate)
   (transient-amaranth voice-animate)
   (transient-argument voice-animate)
   (transient-blue voice-lighten)
   (transient-disabled-suffix inaudible)
   (transient-enabled-suffix voice-brighten)
   (transient-heading voice-lighten)
   (transient-higher-level voice-brighten)
   (transient-inactive-argument inaudible)
   (transient-inactive-value inaudible)
   (transient-key voice-animate)
   (transient-mismatched-key voice-monotone-extra)
   (transient-nonstandard-key voice-monotone-extra)
   (transient-pink voice-bolden-medium)
   (transient-red voice-bolden)
   (transient-separator  'inaudible)
   (transient-teal voice-lighten-medium)
   (transient-unreachable voice-monotone-extra)
   (transient-unreachable-key voice-monotone-extra)
   (transient-value voice-brighten)
   ))

;;;  Advice Interactive Commands:

(defun emacsvox--advice-transient-toggle-common-after (&rest _)
  "speak." 
  (when (ems-interactive-p 'transient-toggle-common)
    (tts-stop 'all)
    (emacsvox-icon (if transient-show-common-commands 'on 'off))))

(advice-add 'transient-toggle-common :after
            #'emacsvox--advice-transient-toggle-common-after)

(defun emacsvox--advice-transient-resume-after (&rest _)
  "speak."
  (when (ems-interactive-p 'transient-resume)
    (tts-stop 'all) (emacsvox-icon 'open-object)))

(advice-add 'transient-resume :after
            #'emacsvox--advice-transient-resume-after)

(defun emacsvox-transient--quit-feedback (target)
  "Provide quit feedback when TARGET is the interactive command."
  (when (ems-interactive-p target)
    (tts-stop 'all)
    (emacsvox-icon 'close-object)
    (when (eq major-mode 'emacsvox-transient-mode)
      (bury-buffer))
    (emacsvox-speak-mode-line)))

(defun emacsvox--advice-transient-quit-all-after (&rest _)
  "Provide feedback after quitting all transients."
  (emacsvox-transient--quit-feedback 'transient-quit-all))

(advice-add 'transient-quit-all :after
            #'emacsvox--advice-transient-quit-all-after)

(defun emacsvox--advice-transient-quit-one-after (&rest _)
  "Provide feedback after quitting one transient."
  (emacsvox-transient--quit-feedback 'transient-quit-one))

(advice-add 'transient-quit-one :after
            #'emacsvox--advice-transient-quit-one-after)

(defun emacsvox--advice-transient-quit-seq-after (&rest _)
  "Provide feedback after quitting a transient key sequence."
  (emacsvox-transient--quit-feedback 'transient-quit-seq))

(advice-add 'transient-quit-seq :after
            #'emacsvox--advice-transient-quit-seq-after)

(defun emacsvox-transient--save-feedback (target)
  "Provide save feedback when TARGET is the interactive command."
  (when (ems-interactive-p target)
    (emacsvox-icon 'save-object)
    (tts-stop 'all)))

(defun emacsvox--advice-transient-save-after (&rest _)
  "Provide feedback after saving a transient value."
  (emacsvox-transient--save-feedback 'transient-save))

(advice-add 'transient-save :after
            #'emacsvox--advice-transient-save-after)

(defun emacsvox--advice-transient-set-after (&rest _)
  "Provide feedback after setting a transient value."
  (emacsvox-transient--save-feedback 'transient-set))

(advice-add 'transient-set :after
            #'emacsvox--advice-transient-set-after)

(defun emacsvox-transient--history-feedback (target)
  "Speak history when TARGET is the interactive command."
  (when (ems-interactive-p target)
    (dtk-speak-list (minibuffer-contents))
    (emacsvox-icon 'select-object)))

(defun emacsvox--advice-transient-history-next-after (&rest _)
  "Speak the next transient history value."
  (emacsvox-transient--history-feedback 'transient-history-next))

(advice-add 'transient-history-next :after
            #'emacsvox--advice-transient-history-next-after)

(defun emacsvox--advice-transient-history-prev-after (&rest _)
  "Speak the previous transient history value."
  (emacsvox-transient--history-feedback 'transient-history-prev))

(advice-add 'transient-history-prev :after
            #'emacsvox--advice-transient-history-prev-after)

(define-derived-mode emacsvox-transient-mode special-mode
  "Browse current transient choices"
  "emacsvox integration with Transient."
  
  (use-local-map transient-sticky-map)
  (local-set-key (kbd "M-n") 'emacsvox-transient-next-section)
  (local-set-key (kbd "M-p") 'emacsvox-transient-previous-section)
  (local-set-key "q" 'bury-buffer)
  (local-set-key "r" 'transient-resume))

(defvar emacsvox-transient-cache nil
  "Cache of the last Transient buffer contents.")

(defun emacsvox--advice-transient--show-after (&rest _)
  "Speak and set up cache."
  (when (window-live-p transient--window)
    (with-current-buffer (window-buffer transient--window)
      (setq emacsvox-transient-cache
            (buffer-substring (point-min) (point-max)))
      (emacsvox-speak-line) (emacsvox-icon 'open-object))))

(advice-add 'transient--show :after
            #'emacsvox--advice-transient--show-after)

(defun emacsvox--advice-transient-suspend-around (orig-fun)
  "Pop to *Transient-emacsvox* buffer where the message emitted by\nthe transient can be browsed.\nPress `r' to resume the suspended transient."
  (if (ems-interactive-p 'transient-suspend)
      (let
          ((buff (get-buffer-create "*Transient-Emacsvox*"))
           (inhibit-read-only t))
        (prog1 (funcall orig-fun)
          (emacsvox-icon 'close-object)
          (with-current-buffer buff
            (erase-buffer)
            (insert "r to resume, C-g to quit.\n\n")
            (insert emacsvox-transient-cache)
            (goto-char (point-min))
            (emacsvox-transient-mode))
          (switch-to-buffer buff)
          (emacsvox-speak-mode-line)))
    (funcall orig-fun)))

(advice-add 'transient-suspend :around
            #'emacsvox--advice-transient-suspend-around)

;;; section nav:

(defun emacsvox-transient-next-section ()
  "Next transient section."
  (interactive)
  (with-selected-window
      (if (window-live-p transient--window)
          transient--window (selected-window))
    (when-let*
        ((match
          (text-property-search-forward 'face 'transient-heading t t)))
      (goto-char (prop-match-beginning match))
      (emacsvox-speak-region (point) (prop-match-end match)))))

(defun emacsvox-transient-previous-section ()
  "Previous transient section."
  (interactive)
  (with-selected-window
      (if (window-live-p transient--window)
          transient--window (selected-window))
    (when-let*
        ((match
          (text-property-search-backward
           'face 'transient-heading t t)))
      (goto-char (prop-match-beginning match))
      (emacsvox-speak-region (point) (prop-match-end match)))))

;;; Hooks:

(defun emacsvox-transient-post-hook ()
  "Actions to execute after transient is done."
  
  (unless transient--stack
    (tts-stop 'all)
    (emacsvox-icon 'task-done)
    (emacsvox-speak-mode-line)))

(add-hook 'transient-exit-hook 'emacsvox-transient-post-hook)

;;; Advice transient navigation:

(defun emacsvox-transient--speak-button ()
  "Speak the current button in the Transient menu window."
  (with-current-buffer (window-buffer transient--window)
    (when-let* ((button (button-at (point)))
                (start (button-start button))
                (end (button-end button)))
      (tts-speak (buffer-substring start end))
      (emacsvox-icon 'button))))

(defun emacsvox--advice-transient-backward-button-around
    (orig-fun n)
  "Speak the button reached after moving backward by N."
  (prog1 (funcall orig-fun n)
    (when (ems-interactive-p 'transient-backward-button)
      (emacsvox-transient--speak-button))))

(advice-add 'transient-backward-button :around
            #'emacsvox--advice-transient-backward-button-around)

(defun emacsvox--advice-transient-forward-button-around
    (orig-fun n)
  "Speak the button reached after moving forward by N."
  (prog1 (funcall orig-fun n)
    (when (ems-interactive-p 'transient-forward-button)
      (emacsvox-transient--speak-button))))

(advice-add 'transient-forward-button :around
            #'emacsvox--advice-transient-forward-button-around)

;;; Enable And Customize Transient Navigation:

(defun emacsvox-transient-setup ()
  "Emacsvox Transient Customizations"
  (keymap-set  transient-popup-navigation-map "C-j" #'transient-push-button)
  (define-key transient-predicate-map
              [emacsvox-transient-previous-section] 'transient--do-move)
  (define-key transient-predicate-map
              [emacsvox-transient-next-section] 'transient--do-move)

  (define-key transient-popup-navigation-map "C-j" 'transient-push-button)
  (define-key transient-popup-navigation-map
              [left] 'emacsvox-transient-previous-section)
  (define-key transient-popup-navigation-map
              [right] 'emacsvox-transient-next-section)

  (setq transient-enable-menu-navigation t
        transient-force-single-column t
        transient-semantic-coloring t
        transient-show-menu 1))
(emacsvox-transient-setup)

(provide 'emacsvox-transient)
;;;  end of file
