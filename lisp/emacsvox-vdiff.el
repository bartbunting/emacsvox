;;; emacsvox-vdiff.el --- Speech-enable VDIFF  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable VDIFF An Emacs Interface to vdiff
;; Keywords: Emacsvox,  Audio Desktop vdiff
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
;; MERCHANTABILITY or FITNVDIFF FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; VDIFF ==  vimdiff
;; Installable from melpa, vdiff enables synchronized movement
;; through diff buffers without resorting to an extra control-panel
;; as is the case with ediff.
;;  In addition to speech-enabling interactive commands and setting
;;  up face->voice mappings, this module provides commands that speak
;;  the current hunk. These are bound in @code{vdiff-mode-prefix-map}.
;; @itemize  @bullet
;; @item  @code{emacsvox-vdiff-speak-this-hunk} bound to @kbd{SPC}.
;; @item @code{emacsvox-vdiff-speak-other-hunk} bound to @kbd{C-SPC}.
;; @item @code{emacsvox-vdiff-speak-other-line} bound to @kbd{l}.
;; @end itemize
;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'vdiff "vdiff" 'no-error)

;;;  Map Faces:

(voice-setup-add-map
 '(
   (vdiff-addition-face voice-brighten)
   (vdiff-change-face voice-overlay-1)
   (vdiff-closed-fold-face voice-smoothen)
   (vdiff-open-fold-face voice-lighten)
   (vdiff-refine-added voice-overlay-0)
   (vdiff-refine-changed voice-lighten)
   (vdiff-subtraction-face voice-smoothen)
   (vdiff-subtraction-fringe-face voice-smoothen-extra)
   (vdiff-target-face voice-monotone-extra)))

;;;  Emacsvox VDiff Commands:

(defun emacsvox-vdiff-get-overlay-at-point ()
  "Return vdiff overlay  at point."
  (let ((ovr (vdiff--overlay-at-pos)))
    (and (overlayp ovr)
         (overlay-get ovr 'vdiff-type)
         (not (eq (overlay-get ovr 'vdiff-type) 'fold))
         ovr)))

(defun  emacsvox-vdiff-speak-this-hunk ()
  "Speak VDiff hunk under point."
  (interactive)
  (let ((o(emacsvox-vdiff-get-overlay-at-point)))
    (when o
      (tts-speak (buffer-substring (overlay-start o) (overlay-end o))))))

(defun emacsvox-vdiff-speak-other-hunk ()
  "Speak corresponding hunk from other buffer."
  (interactive)
  (save-window-excursion
    (save-excursion
      (vdiff-switch-buffer (line-number-at-pos))
      (emacsvox-vdiff-speak-this-hunk))))

(defun emacsvox-vdiff-speak-other-line ()
  "Speak corresponding line from other buffer."
  (interactive)
  (save-window-excursion
    (save-excursion
      (vdiff-switch-buffer (line-number-at-pos))
      (emacsvox-speak-line))))

;;;  Interactive Commands:

(defvar emacsvox-vdiff--advice nil
  "Current VDiff targets and their native advice functions.")
(setq emacsvox-vdiff--advice nil)

(defun emacsvox-vdiff--register-after-group (targets feedback)
  "Define and register after advice for TARGETS using FEEDBACK."
  (dolist (target targets)
    (let ((advice-function
           (intern (format "emacsvox--advice-%s-after" target))))
      (eval
       `(defun ,advice-function (&rest _)
          ,(format "Provide speech feedback after `%s'." target)
          (when (ems-interactive-p ',target)
            (,feedback))))
      (push (list target :after advice-function) emacsvox-vdiff--advice))))

(defun emacsvox-vdiff--change-feedback ()
  "Speak a VDiff hunk after transferring changes."
  (emacsvox-icon 'task-done)
  (emacsvox-vdiff-speak-this-hunk))

(emacsvox-vdiff--register-after-group
 '(vdiff-receive-changes vdiff-receive-changes-and-step
   vdiff-send-changes vdiff-send-changes-and-step)
 #'emacsvox-vdiff--change-feedback)

(defun emacsvox--advice-vdiff-switch-buffer-after (&rest _)
  "speak."
  (when (ems-interactive-p 'vdiff-switch-buffer)
    (emacsvox-icon 'select-object) (emacsvox-speak-mode-line)))

(push '(vdiff-switch-buffer :after
        emacsvox--advice-vdiff-switch-buffer-after)
      emacsvox-vdiff--advice)

(defun emacsvox--advice-vdiff-refine-all-hunks-after (&rest _)
  "speak."
  (when (ems-interactive-p 'vdiff-refine-all-hunks)
    (emacsvox-icon 'task-done)))

(push '(vdiff-refine-all-hunks :after
        emacsvox--advice-vdiff-refine-all-hunks-after)
      emacsvox-vdiff--advice)

(defun emacsvox-vdiff--open-feedback ()
  "Speak a newly opened VDiff session."
  (emacsvox-icon 'task-done)
  (emacsvox-speak-mode-line))

(emacsvox-vdiff--register-after-group
 '(vdiff-buffers vdiff-buffers3 vdiff-current-file
   vdiff-files vdiff-files3)
 #'emacsvox-vdiff--open-feedback)

;;;  open/close Folds:
(defun emacsvox-vdiff--open-fold-feedback ()
  "Speak an opened VDiff fold."
  (emacsvox-icon 'open-object)
  (emacsvox-speak-line))

(emacsvox-vdiff--register-after-group
 '(vdiff-open-all-folds vdiff-open-fold)
 #'emacsvox-vdiff--open-fold-feedback)

(defun emacsvox-vdiff--close-fold-feedback ()
  "Speak a closed VDiff fold."
  (emacsvox-icon 'close-object)
  (emacsvox-speak-line))

(emacsvox-vdiff--register-after-group
 '(vdiff-close-all-folds vdiff-close-fold vdiff-close-other-folds)
 #'emacsvox-vdiff--close-fold-feedback)

;;;  Navigation:

(defun emacsvox-vdiff--movement-feedback ()
  "Speak the selected VDiff hunk."
  (emacsvox-vdiff-speak-this-hunk)
  (emacsvox-icon 'large-movement))

(emacsvox-vdiff--register-after-group
 '(vdiff-next-fold vdiff-next-hunk vdiff-previous-fold vdiff-previous-hunk)
 #'emacsvox-vdiff--movement-feedback)

(defun emacsvox-vdiff--install-advice ()
  "Install native advice after VDiff loads."
  (dolist (entry emacsvox-vdiff--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

(with-eval-after-load 'vdiff
  (emacsvox-vdiff--install-advice))

;;;  Setup:

(eval-after-load
    "vdiff"
  `(progn
     
     (define-key vdiff-mode-prefix-map "h" 'vdiff-hydra/body)
     (define-key vdiff-mode-map (kbd "C-c") vdiff-mode-prefix-map)
     (define-key vdiff-mode-prefix-map   " " 'emacsvox-vdiff-speak-this-hunk)
     (define-key vdiff-mode-prefix-map
                 (kbd "C-SPC") 'emacsvox-vdiff-speak-other-hunk)
     (define-key vdiff-mode-prefix-map
                 (kbd "l") 'emacsvox-vdiff-speak-other-line)))

(provide 'emacsvox-vdiff)
;;;  end of file
