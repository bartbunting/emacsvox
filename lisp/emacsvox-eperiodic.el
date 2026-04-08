;;; emacsvox-eperiodic.el --- Periodic Table -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:  Emacsvox speech-enabler for Periodic Table
;; Keywords: Emacsvox, periodic  Table
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4074 $ |
;; Location https://github.com/tvraman/emacsvox
;; 

;;;   Copyright:

;; Copyright (C) 1995 -- 2024, T. V. Raman
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

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; eperiodic produces an interactive periodic table of elements
;; and can be found at 
;; http://vegemite.chem.nottingham.ac.uk/~matt/emacs/eperiodic.el
;;; Code:

;;  required modules

;;; Code:

(require 'emacsvox-preamble)

;;;  Forward decls:
(declare-function eperiodic-get-element-property  "ext:eperiodic.el" (e prop))
(declare-function eperiodic-element-at "ext:eperiodic.el" (&optional pos))

;;;  faces and voices 
(voice-setup-add-map
 '(
   (eperiodic-discovered-after-face voice-smoothen)
   (eperiodic-discovered-before-face voice-brighten)
   (eperiodic-discovered-in-face voice-lighten)
   (eperiodic-f-block-face voice-lighten-medium)
   (eperiodic-gas-face voice-lighten-extra)
   (eperiodic-group-number-face voice-lighten)
   (eperiodic-header-face voice-bolden)
   (eperiodic-liquid-face voice-smoothen)
   (eperiodic-p-block-face voice-monotone-extra)
   (eperiodic-period-number-face voice-lighten)
   (eperiodic-s-block-face voice-smoothen-medium)
   (eperiodic-solid-face voice-bolden-extra)
   (eperiodic-unknown-face voice-bolden-and-animate)))

;;;  helpers 

(defun emacsvox-eperiodic-name-element-at-point ()
  "Returns name of current element."
  
  (let ((name 
         (cdr
          (assoc 'name
                 (cdr (assoc (eperiodic-element-at)
                             eperiodic-element-properties)))))
        (face (get-text-property (point) 'face))
        (personality (get-text-property (point) 'personality)))
    (add-text-properties  0 (length name)
                          (list 'face face 'personality
                                personality)
                          name)
    name))

;;;  additional  commands

(defun emacsvox-eperiodic-previous-line ()
  "Move to next row and speak element."
  (interactive)
  (forward-line -1)
  (call-interactively 'eperiodic-next-element))

(defun emacsvox-eperiodic-next-line ()
  "Move to next row and speak element."
  (interactive)
  (forward-line 1)
  (call-interactively 'eperiodic-next-element))

(defun emacsvox-eperiodic-speak-current-element ()
  "Speak element at point."
  (interactive)
  (dtk-speak (emacsvox-eperiodic-name-element-at-point)))

(defun emacsvox-eperiodic-goto-property-section ()
  "Mark position and jump to properties section."
  (interactive)
  (push-mark (point))
  (goto-char
   (text-property-any (point) (point-max)
                      'face 'eperiodic-header-face))
  (forward-line 2)
  (emacsvox-speak-line)
  (emacsvox-icon 'large-movement))
(cl-declaim (special eperiodic-mode-map))
(when (boundp 'eperiodic-mode-map)
  (define-key eperiodic-mode-map " " 'emacsvox-eperiodic-speak-current-element)
  (define-key  eperiodic-mode-map
               "x" 'emacsvox-eperiodic-goto-property-section)
  (define-key eperiodic-mode-map "n" 'emacsvox-eperiodic-next-line)
  (define-key eperiodic-mode-map "p" 'emacsvox-eperiodic-previous-line)
  (define-key eperiodic-mode-map "l"
              'emacsvox-eperiodic-play-description)
  )

;;;   listen off the web:
(defvar emacsvox-eperiodic-media-location 
  "http://www.webelements.com/webelements/elements/media/snds-description/%s.rm"
  "Location of streaming media describing elements.")

(defun emacsvox-eperiodic-play-description ()
  "Play audio description from WebElements."
  (interactive)
  
  (let ((e (eperiodic-element-at)))
    (unless e  (error "No element under point."))
    (emacsvox-m-player
     (format  emacsvox-eperiodic-media-location
              (eperiodic-get-element-property e 'symbol))
     nil)))

;;;  advice interactive commands

(defun ems--eperiodic-find-element-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-eperiodic-speak-current-element)
    (emacsvox-icon 'large-movement)))

(advice-add 'eperiodic-find-element :after
            #'ems--eperiodic-find-element-after)

(defun ems--eperiodic-previous-element-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (dtk-speak (emacsvox-eperiodic-name-element-at-point))
    (emacsvox-icon 'large-movement)))

(advice-add 'eperiodic-previous-element :after
            #'ems--eperiodic-previous-element-after)

(defun ems--eperiodic-next-element-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (dtk-speak (emacsvox-eperiodic-name-element-at-point))
    (emacsvox-icon 'large-movement)))

(advice-add 'eperiodic-next-element :after
            #'ems--eperiodic-next-element-after)

(defun ems--eperiodic-after (&rest _)
  "Speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'eperiodic :after #'ems--eperiodic-after)

(defun ems--eperiodic-move-after (&rest _)
  "speak." (when (ems-interactive-p) (emacsvox-icon 'select-object)))

(advice-add 'eperiodic-move :after #'ems--eperiodic-move-after)

(defun ems--eperiodic-show-element-info-after (&rest _)
  "Speak displayed info."
  (when (ems-interactive-p)
    (let ((b (get-buffer "*EPeriodic Element*")))
      (unless b (error "Cannot find displayed info."))
      (save-current-buffer (set-buffer b) (emacsvox-speak-buffer)))))

(advice-add 'eperiodic-show-element-info :after
            #'ems--eperiodic-show-element-info-after)

(defun ems--eperiodic-bury-buffer-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'close-object) (emacsvox-speak-mode-line)))

(advice-add 'eperiodic-bury-buffer :after
            #'ems--eperiodic-bury-buffer-after)

(defun ems--eperiodic-cycle-view-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object)
    (message "View %s" eperiodic-colour-element-function)))

(advice-add 'eperiodic-cycle-view :after
            #'ems--eperiodic-cycle-view-after)

(provide 'emacsvox-eperiodic)
;;;  end of file

