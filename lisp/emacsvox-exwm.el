;;; emacsvox-exwm.el --- Speech-enable EXWM  -*- lexical-binding: t; -*-
;;; $Author: tv.raman.tv $
;;; Description:  Speech-enable EXWM An Emacs Interface to exwm
;;; Keywords: Emacsvox,  Audio Desktop exwm
;;;   LCD Archive entry:

;;; LCD Archive Entry:
;;; emacsvox| T. V. Raman |raman@cs.cornell.edu
;;; A speech interface to Emacs |
;;;  $Revision: 4532 $ |
;;; Location https://github.com/robertmeta/emacsvox
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
;;; This module speech-enables and integrates EXWM on the Emacsvox
;;; Audio Desktop
;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'exwm "exwm" 'no-error)

;;; Advise internal helpers:

(defun emacsvox--advice-exwm-workspace--prompt-for-workspace-before
    (&optional prompt)
  "Speak PROMPT before reading an EXWM workspace."
  (when prompt (dtk-speak prompt)))

;;;   Advice Interactive Commands

(defun emacsvox--advice-exwm-floating-hide-after (&rest _)
  "speak."
  (when (ems-interactive-p 'exwm-floating-hide)
    (emacsvox-icon 'close-object) (dtk-speak "Hid floating window")))

(defun emacsvox--advice-exwm-floating-toggle-floating-after (&rest _)
  "speak."
  (when (ems-interactive-p 'exwm-floating-toggle-floating)
    (dtk-speak
     (format "Turned %s floating" (if exwm--floating-frame "on" "off")))
    (emacsvox-icon (if exwm--floating-frame 'on 'off))))

(defun emacsvox--advice-exwm-input-grab-keyboard-after (&rest _)
  "speak."
  (when (ems-interactive-p 'exwm-input-grab-keyboard)
    (dtk-speak "line mode") (emacsvox-icon 'off)))

(defun emacsvox--advice-exwm-input-release-keyboard-after (&rest _)
  "speak."
  (when (ems-interactive-p 'exwm-input-release-keyboard)
    (dtk-speak "Char mode") (emacsvox-icon 'on)))

(defun emacsvox--advice-exwm-input-toggle-keyboard-after (&rest _)
  "speak."
  (when (ems-interactive-p 'exwm-input-toggle-keyboard)
    (cl-case exwm--input-mode
      (line-mode (dtk-speak "Line mode") (emacsvox-icon 'off))
      (char-mode (dtk-speak "Char mode") (emacsvox-icon 'on)))))

(defun emacsvox--advice-exwm-layout-show-mode-line-after (&rest _)
  "speak."
  (when (ems-interactive-p 'exwm-layout-show-mode-line)
    (dtk-speak "Showing mode line") (emacsvox-icon 'open-object)))

(defun emacsvox--advice-exwm-layout-set-fullscreen-after (&rest _)
  "speak."
  (when (ems-interactive-p 'exwm-layout-set-fullscreen)
    (dtk-speak "Full screen") (emacsvox-icon 'window-resize)))

(defun emacsvox--advice-exwm-layout-hide-mode-line-after (&rest _)
  "speak."
  (when (ems-interactive-p 'exwm-layout-hide-mode-line)
    (dtk-speak "hid mode line") (emacsvox-icon 'close-object)))

(defun emacsvox--advice-exwm-layout-toggle-fullscreen-after (&rest _)
  "speak."
  (when (ems-interactive-p 'exwm-layout-toggle-fullscreen)
    (dtk-speak
     (format "Turned %s full screen"
             (if (exwm-layout--fullscreen-p) "on" "off")))
    (emacsvox-icon (if (exwm-layout--fullscreen-p) 'on 'off))))

(defun emacsvox--advice-exwm-layout-toggle-mode-line-after (&rest _)
  "speak."
  (when (ems-interactive-p 'exwm-layout-toggle-mode-line)
    (dtk-speak
     (format "Turned %s mode line" (if mode-line-format 'on 'off)))
    (emacsvox-icon (if mode-line-format 'on 'off))))

(defun emacsvox--advice-exwm-workspace-switch-after (&rest _)
  "speak frame title."
  (when (ems-interactive-p 'exwm-workspace-switch)
    (emacsvox-speak-frame-title)))

(defconst emacsvox-exwm--advice
  '((exwm-workspace--prompt-for-workspace :before
     emacsvox--advice-exwm-workspace--prompt-for-workspace-before)
    (exwm-floating-hide :after emacsvox--advice-exwm-floating-hide-after)
    (exwm-floating-toggle-floating :after
     emacsvox--advice-exwm-floating-toggle-floating-after)
    (exwm-input-grab-keyboard :after
     emacsvox--advice-exwm-input-grab-keyboard-after)
    (exwm-input-release-keyboard :after
     emacsvox--advice-exwm-input-release-keyboard-after)
    (exwm-input-toggle-keyboard :after
     emacsvox--advice-exwm-input-toggle-keyboard-after)
    (exwm-layout-show-mode-line :after
     emacsvox--advice-exwm-layout-show-mode-line-after)
    (exwm-layout-set-fullscreen :after
     emacsvox--advice-exwm-layout-set-fullscreen-after)
    (exwm-layout-hide-mode-line :after
     emacsvox--advice-exwm-layout-hide-mode-line-after)
    (exwm-layout-toggle-fullscreen :after
     emacsvox--advice-exwm-layout-toggle-fullscreen-after)
    (exwm-layout-toggle-mode-line :after
     emacsvox--advice-exwm-layout-toggle-mode-line-after)
    (exwm-workspace-switch :after
     emacsvox--advice-exwm-workspace-switch-after))
  "Current EXWM targets and their native advice functions.")

(defun emacsvox-exwm--install-advice ()
  "Install native advice for loaded EXWM commands."
  (dolist (entry emacsvox-exwm--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

(dolist (feature '(exwm exwm-floating exwm-input exwm-layout exwm-workspace))
  (eval `(with-eval-after-load ',feature
           (emacsvox-exwm--install-advice))))

;;; Additional Interactive Commands:
;; I bind this to s-/ via custom:

(defun emacsvox-exwm-workspace-cycle ()
  "Cycle to next workspace, with wrap-around"
  (interactive)
  (let ((count (length  exwm-workspace--list))
        (index (exwm-workspace--position exwm-workspace--current)))
    (cl-assert (not (zerop count)) """Workspaces not set up correctly." t)
    (exwm-workspace-switch (% (1+ index) count))
    (emacsvox-speak-frame-title)))

;;; Orca Toggle:

(global-set-key (kbd "s-o") 'emacsvox-orca-toggle)

;;; Configure Hooks:

(defun emacsvox-exwm-mode-hook ()
  "EXWM Setup For Emacsvox"
  
  (define-key exwm-mode-map emacsvox-prefix 'emacsvox-keymap)
  (define-key exwm-mode-map  emacsvox-prefix 'emacsvox-keymap)
  (define-key exwm-mode-map
              (concat emacsvox-prefix "e")
              'exwm-input-send-simulation-key)
  (define-key exwm-mode-map
              (concat emacsvox-prefix emacsvox-prefix)
              'exwm-input-send-simulation-key)
  (emacsvox-speak-frame-title))

(cl-declaim (special exwm-mode-hook))
(add-hook
 'exwm-mode-hook
 #'emacsvox-exwm-mode-hook)

(provide 'emacsvox-exwm)
;;;  end of file

                                        ; 
                                        ; 
                                        ; 
