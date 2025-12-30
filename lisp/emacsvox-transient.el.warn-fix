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
;; @item  transient-show-popup:  1
;; @item transient-enable-popup-navigation:  t
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
(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacsvox-preamble)
(require 'derived)
(eval-when-compile (require 'transient))

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


(defun ems--transient-toggle-common-after (&rest _)
  "speak." (cl-declare (special transient-show-common-commands))
  (when (ems-interactive-p)
    (dtk-stop 'all)
    (emacsvox-icon (if transient-show-common-commands 'on 'off))))


(advice-add 'transient-toggle-common :after
	    #'ems--transient-toggle-common-after)





(defun ems--transient-resume-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (dtk-stop 'all) (emacsvox-icon 'open-object)))


(advice-add 'transient-resume :after #'ems--transient-resume-after)




(cl-loop
 for f in
 '(transient-quit-all transient-quit-one transient-quit-seq )
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (dtk-stop 'all)
       (emacsvox-icon 'close-object)
       (when (eq major-mode 'emacsvox-transient-mode) (bury-buffer))
       (emacsvox-speak-mode-line)))))

(cl-loop
 for f in
 '(transient-save transient-set)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'save-object)
       (dtk-stop 'all)))))

(cl-loop
 for f in
 '(transient-history-next transient-history-prev)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (dtk-speak-list (minibuffer-contents))
       (emacsvox-icon 'select-object)))))

(define-derived-mode emacsvox-transient-mode special-mode
  "Browse current transient choices"
  "emacsvox integration with Transient."
  (cl-declare (special transient-sticky-map))
  (use-local-map transient-sticky-map)
  (local-set-key (kbd "M-n") 'emacsvox-transient-next-section)
  (local-set-key (kbd "M-p") 'emacsvox-transient-previous-section)
  (local-set-key "q" 'bury-buffer)
  (local-set-key "r" 'transient-resume))

(defvar emacsvox-transient-cache nil
  "Cache of the last Transient buffer contents.")


(defun ems--transient--show-after (&rest _)
  "Speak and set up cache."
  (when (window-live-p transient--window)
    (with-current-buffer (window-buffer transient--window)
      (setq emacsvox-transient-cache
	    (buffer-substring (point-min) (point-max)))
      (emacsvox-speak-line) (emacsvox-icon 'open-object))))


(advice-add 'transient--show :after #'ems--transient--show-after)





(defun ems--transient-suspend-around (orig-fun &rest args)
  "Pop to *Transient-emacsvox* buffer where the message emitted by\nthe transient can be browsed.\nPress `r' to resume the suspended transient."
  (let ((result (apply orig-fun args)))
    (cl-declare (special emacsvox-transient-cache))
    (cond
     ((ems-interactive-p)
      (let
	  ((buff (get-buffer-create "*Transient-Emacsvox*"))
	   (inhibit-read-only t))
	(apply orig-fun args) (emacsvox-icon 'close-object)
	(with-current-buffer buff
	  (erase-buffer) (insert "r to resume, C-g to quit.\n\n")
	  (insert emacsvox-transient-cache) (goto-char (point-min))
	  (emacsvox-transient-mode))
	(switch-to-buffer buff) (emacsvox-speak-mode-line)))
     (t (apply orig-fun args)))
    result))


(advice-add 'transient-suspend :around #'ems--transient-suspend-around)




;;; section nav:

(defun emacsvox-transient-next-section ()
  "Next transient section."
  (interactive)
  (with-selected-window
      (if (window-live-p transient--window)
          transient--window (selected-window))
    (when-let
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
    (when-let
        ((match
          (text-property-search-backward
           'face 'transient-heading t t)))
      (goto-char (prop-match-beginning match))
      (emacsvox-speak-region (point) (prop-match-end match)))))

;;; Hooks:

(defun emacsvox-transient-post-hook ()
  "Actions to execute after transient is done."
  (cl-declare (special transient--stack))
  (unless transient--stack
    (dtk-stop 'all)
    (emacsvox-icon 'task-done)
    (emacsvox-speak-mode-line)))

(add-hook 'transient-exit-hook 'emacsvox-transient-post-hook)

;;; Advice transient navigation:
(cl-loop
 for f in
 '(transient-backward-button transient-forward-button)
 do
 (eval
  `(defadvice ,f (around emacsvox pre act comp)
     "speak selected button"
     (cond
      ((ems-interactive-p)
       ad-do-it
       (with-current-buffer (window-buffer transient--window)
         (when-let ((button (button-at (point)))
                    (start (button-start button))
                    (end (button-end button)))
           (dtk-speak (buffer-substring start end))
           (emacsvox-icon 'button))))
      (t ad-do-it))
     ad-return-value)))

;;; Enable And Customize Transient Navigation:
(declare-function transient-push-button "emacsvox-transient" t)

(defun emacsvox-transient-setup ()
  "Emacsvox Transient Customizations"
  (cl-declare (special transient-enable-popup-navigation
                       transient-popup-navigation-map
                       transient-predicate-map))
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

  (setq transient-enable-popup-navigation t
        transient-force-single-column t
        transient-semantic-coloring t
        transient-show-popup 1))
(emacsvox-transient-setup)

(provide 'emacsvox-transient)
;;;  end of file

