;;; emacspeak-exwm.el --- Speech-enable EXWM  -*- lexical-binding: t; -*-
;;; $Author: tv.raman.tv $
;;; Description:  Speech-enable EXWM An Emacs Interface to exwm
;;; Keywords: Emacspeak,  Audio Desktop exwm
;;;   LCD Archive entry:

;;; LCD Archive Entry:
;;; emacspeak| T. V. Raman |raman@cs.cornell.edu
;;; A speech interface to Emacs |
;;;  $Revision: 4532 $ |
;;; Location https://github.com/tvraman/emacspeak
;;;

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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;;; EXWM ==  Emacs X Window Manager
;;; This module speech-enables and integrates EXWM on the Emacspeak
;;; Audio Desktop
;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacspeak-preamble)
(require 'exwm "exwm" 'no-error)

;;; Advise internal helpers:


(defun ems--exwm-workspace--prompt-for-workspace-before (&rest _)
  "speak prompt." (dtk-speak (ad-get-arg 0)))


(advice-add 'exwm-workspace--prompt-for-workspace :before
	    #'ems--exwm-workspace--prompt-for-workspace-before)




;;;   Advice Interactive Commands


(defun ems--exwm-floating-hide-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacspeak-icon 'close-object) (dtk-speak "Hid floating window")))


(advice-add 'exwm-floating-hide :after #'ems--exwm-floating-hide-after)





(defun ems--exwm-floating-toggle-floating-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (dtk-speak
     (format "Turned %s floating" (if exwm--floating-frame "on" "off")))
    (emacspeak-icon (if exwm--floating-frame 'on 'off))))


(advice-add 'exwm-floating-toggle-floating :after
	    #'ems--exwm-floating-toggle-floating-after)





(defun ems--exwm-input-grab-keyboard-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (dtk-speak "line mode") (emacspeak-icon 'off)))


(advice-add 'exwm-input-grab-keyboard :after
	    #'ems--exwm-input-grab-keyboard-after)





(defun ems--exwm-input-release-keyboard-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (dtk-speak "Char mode") (emacspeak-icon 'oon)))


(advice-add 'exwm-input-release-keyboard :after
	    #'ems--exwm-input-release-keyboard-after)





(defun ems--exwm-input-toggle-keyboard-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (cl-case exwm--input-mode
      (line-mode (dtk-speak "Line mode") (emacspeak-icon 'off))
      (char-mode (dtk-speak "Char mode") (emacspeak-icon 'on)))))


(advice-add 'exwm-input-toggle-keyboard :after
	    #'ems--exwm-input-toggle-keyboard-after)





(defun ems--exwm-layout-show-mode-line-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (dtk-speak "Showing mode line") (emacspeak-icon 'open-object)))


(advice-add 'exwm-layout-show-mode-line :after
	    #'ems--exwm-layout-show-mode-line-after)





(defun ems--exwm-layout-set-fullscreen-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (dtk-speak "Full screen") (emacspeak-icon 'window-resize)))


(advice-add 'exwm-layout-set-fullscreen :after
	    #'ems--exwm-layout-set-fullscreen-after)





(defun ems--exwm-layout-hide-mode-line-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (dtk-speak "hid mode line") (emacspeak-icon 'close-object)))


(advice-add 'exwm-layout-hide-mode-line :after
	    #'ems--exwm-layout-hide-mode-line-after)





(defun ems--exwm-layout-toggle-fullscreen-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (dtk-speak
     (format "Turned %s full screen"
	     (if (exwm-layout--fullscreen-p) "on" "off")))
    (emacspeak-icon (if (exwm-layout--fullscreen-p) 'on 'off))))


(advice-add 'exwm-layout-toggle-fullscreen :after
	    #'ems--exwm-layout-toggle-fullscreen-after)





(defun ems--exwm-layout-toggle-mode-line-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (dtk-speak
     (format "Turned %s mode line" (if mode-line-format 'on 'off)))
    (emacspeak-icon (if mode-line-format 'on 'off))))


(advice-add 'exwm-layout-toggle-mode-line :after
	    #'ems--exwm-layout-toggle-mode-line-after)




(defun ems--exwm-workspace-switch-after (&rest _)
  "speak frame title."
  (when (ems-interactive-p) (emacspeak-speak-frame-title)))


(advice-add 'exwm-workspace-switch :after
	    #'ems--exwm-workspace-switch-after)




;;; Additional Interactive Commands:
;; I bind this to s-/ via custom:

(defun emacspeak-exwm-workspace-cycle ()
  "Cycle to next workspace, with wrap-around"
  (interactive)
  (let ((count (length  exwm-workspace--list))
        (index (exwm-workspace--position exwm-workspace--current)))
    (cl-assert (not (zerop count)) """Workspaces not set up correctly." t)
    (exwm-workspace-switch (% (1+ index) count))
    (emacspeak-speak-frame-title)))

;;; Orca Toggle:

(global-set-key (kbd "s-o") 'emacspeak-orca-toggle)

;;; Configure Hooks:

(defun emacspeak-exwm-mode-hook ()
  "EXWM Setup For Emacspeak"
  (cl-declare (special emacspeak-prefix ))
  (define-key exwm-mode-map emacspeak-prefix 'emacspeak-keymap)
  (define-key exwm-mode-map  emacspeak-prefix 'emacspeak-keymap)
  (define-key exwm-mode-map
              (concat emacspeak-prefix "e")
              'exwm-input-send-simulation-key)
  (define-key exwm-mode-map
              (concat emacspeak-prefix emacspeak-prefix)
              'exwm-input-send-simulation-key)
  (emacspeak-speak-frame-title))

(cl-declaim (special exwm-mode-hook))
(add-hook
 'exwm-mode-hook
 #'emacspeak-exwm-mode-hook)

(provide 'emacspeak-exwm)
;;;  end of file

                                        ; 
                                        ; 
                                        ; 

