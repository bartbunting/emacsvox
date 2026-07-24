;;; emacsvox-ein.el --- Speech-enable EIN -*- lexical-binding: t; -*-
;; $Id: emacsvox-ein.el 4797 2007-07-16 23:31:22Z tv.raman.tv $
;; $Author: tv.raman.tv $
;; Description:  Speech-enable EIN An Emacs Interface to IPython Notebooks
;; Keywords: Emacsvox,  Audio Desktop IPython, Jupyter, Notebooks
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ |
;; Location https://github.com/robertmeta/emacsvox
;; 

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
;; MERCHANTABILITY or FITNEIN FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; EIN ==  Emacs IPython Notebook
;; You can install package EIN via Melpa
;; This module speech-enables EIN
;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'sox-gen)

;;;   Face->Voice mappings

(voice-setup-add-map
 '(
   (ein:cell-input-area voice-lighten)
   (ein:cell-input-prompt voice-animate)
   (ein:cell-output-area voice-bolden)
   (ein:cell-output-area-error voice-monotone-extra)
   (ein:cell-output-prompt voice-monotone-extra )
   (ein:cell-output-stderr voice-monotone-extra)
   (ein:markdown-blockquote-face voice-monotone-extra)
   (ein:markdown-bold-face voice-bolden)
   (ein:markdown-code-face voice-monotone)
   (ein:markdown-comment-face voice-monotone-extra)
   (ein:markdown-footnote-marker-face voice-smoothen)
   (ein:markdown-footnote-text-face voice-annotate)
   (ein:markdown-header-delimiter-face voice-monotone-extra)
   (ein:markdown-header-face voice-bolden)
   (ein:markdown-header-face-1 voice-lighten)
   (ein:markdown-header-face-2 voice-smoothen)
   (ein:markdown-header-face-3 voice-annotate)
   (ein:markdown-header-face-4 voice-monotone-extra)
   (ein:markdown-header-face-5 voice-monotone-medium)
   (ein:markdown-header-face-6 voice-monotone-extra)
   (ein:markdown-header-rule-face voice-monotone-medium)
   (ein:markdown-highlight-face voice-animate)
   (ein:markdown-hr-face voice-monotone-medium)
   (ein:markdown-html-attr-name-face voice-lighten)
   (ein:markdown-html-attr-value-face voice-lighten-extra)
   (ein:markdown-html-entity-face voice-smoothen)
   (ein:markdown-html-tag-delimiter-face voice-monotone-extra)
   (ein:markdown-html-tag-name-face voice-smoothen-extra)
   (ein:markdown-inline-code-face voice-monotone-extra)
   (ein:markdown-italic-face voice-animate)
   (ein:markdown-language-info-face voice-monotone-extra)
   (ein:markdown-language-keyword-face voice-annotate)
   (ein:markdown-line-break-face voice-monotone-extra)
   (ein:markdown-link-face voice-animate)
   (ein:markdown-link-title-face voice-bolden)
   (ein:markdown-list-face voice-indent)
   (ein:markdown-markup-face voice-monotone-extra)
   (ein:markdown-math-face voice-annotate)
   (ein:markdown-metadata-key-face voice-smoothen)
   (ein:markdown-metadata-value-face voice-animate)
   (ein:markdown-missing-link-face voice-lighten)
   (ein:markdown-plain-url-face voice-annotate)
   (ein:markdown-pre-face voice-monotone-extra)
   (ein:markdown-reference-face voice-animate)
   (ein:markdown-strike-through-face voice-lighten)
   (ein:markdown-table-face voice-lighten)
   (ein:markdown-url-face voice-smoothen-extra)
   (ein:notification-tab-normal voice-smoothen-extra)
   (ein:notification-tab-selected voice-animate)
   (ein:pos-tip-face voice-annotate)))

;;;  Additional Interactive Commands:

(defsubst emacsvox-ein-sox-gen (type)
  "Generate a tone  that indicates markdown, code, or raw."
  (let ((fade "fade h .1 .5 .4 gain -8 "))
    (cond
     ((string= "raw" type) (sox-sin .5 "%-5:%3"fade))
     ((string= "code" type) (sox-sin .5 "%-1:%5" fade))
     ((string= "markdown" type) (sox-sin .5 "%4:%8"fade)))))

(declare-function ein:cell-type "ein-classes" (arg &rest args))
(declare-function ein:worksheet-get-current-cell
                  "ein-worksheet" (&rest --cl-rest--))

(defun emacsvox-ein-speak-current-cell ()
  "Speak current cell."
  (interactive)
  (emacsvox-speak-region (point) (next-overlay-change (point))))

;;;  Bind additional interactive commands
(when (boundp 'ein:notebook-mode-map)
  (cl-loop for k in
           '(
             ("\C-c." emacsvox-ein-speak-current-cell)
             )
           do
           (emacsvox-keymap-update ein:notebook-mode-map k)))

;;; Modules To Enable:

(defvar emacsvox-ein--advice nil
  "Current EIN targets and their native advice functions.")
(setq emacsvox-ein--advice nil)

(defun emacsvox-ein--register-after-group (targets feedback)
  "Define and register after advice for TARGETS using FEEDBACK."
  (dolist (target targets)
    (let ((advice-function
           (intern (format "emacsvox--advice-%s-after" target))))
      (eval
       `(defun ,advice-function (&rest _)
          ,(format "Provide speech feedback after `%s'." target)
          (when (ems-interactive-p ',target)
            (,feedback))))
      (push (list target :after advice-function) emacsvox-ein--advice))))

(defun emacsvox-ein--line-movement-feedback ()
  "Speak the current line after EIN navigation."
  (emacsvox-speak-line)
  (emacsvox-icon 'large-movement))

(emacsvox-ein--register-after-group
 '(ein:tb-jump-to-source-at-point-command ein:tb-next-item ein:tb-prev-item)
 #'emacsvox-ein--line-movement-feedback)

(defun emacsvox-ein--open-line-feedback ()
  "Speak the current line after opening an EIN view."
  (emacsvox-icon 'open-object)
  (emacsvox-speak-line))

(emacsvox-ein--register-after-group
 '(ein:tb-show-km ein:worksheet-split-cell-at-point)
 #'emacsvox-ein--open-line-feedback)

(defun emacsvox-ein--source-movement-feedback ()
  "Speak after moving between EIN source locations."
  (emacsvox-icon 'large-movement)
  (emacsvox-speak-line))

(emacsvox-ein--register-after-group
 '(ein:pytools-jump-back-command ein:pytools-jump-to-source-command)
 #'emacsvox-ein--source-movement-feedback)

(defun emacsvox-ein--delete-feedback ()
  "Speak after deleting EIN cell content."
  (emacsvox-speak-line)
  (emacsvox-icon 'delete-object))

(emacsvox-ein--register-after-group
 '(ein:worksheet-clear-all-output-km ein:worksheet-delete-cell
   ein:worksheet-clear-output-km ein:worksheet-kill-cell-km)
 #'emacsvox-ein--delete-feedback)

(defun emacsvox-ein--execute-feedback ()
  "Confirm execution of an EIN cell."
  (emacsvox-icon 'task-done)
  (forward-line 1)
  (message "Press C-c . to hear the results."))

(emacsvox-ein--register-after-group
 '(ein:worksheet-execute-all-cells
   ein:worksheet-execute-cell-and-insert-below
   ein:worksheet-execute-cell-and-insert-below-km
   ein:worksheet-execute-cell-and-goto-next-km
   ein:worksheet-execute-cell-and-goto-next
   ein:worksheet-execute-cell ein:worksheet-execute-cell-km)
 #'emacsvox-ein--execute-feedback)

(defun emacsvox-ein--cell-movement-feedback ()
  "Speak the current EIN cell after navigation."
  (emacsvox-icon 'large-movement)
  (emacsvox-ein-speak-current-cell))

(emacsvox-ein--register-after-group
 '(ein:worksheet-goto-next-input-km ein:worksheet-goto-prev-input-km
   ein:worksheet-goto-next-input ein:worksheet-goto-prev-input)
 #'emacsvox-ein--cell-movement-feedback)

(defun emacsvox-ein--insert-feedback ()
  "Speak after inserting an EIN cell."
  (emacsvox-icon 'yank-object)
  (emacsvox-speak-line))

(emacsvox-ein--register-after-group
 '(ein:worksheet-insert-cell-above ein:worksheet-insert-cell-below)
 #'emacsvox-ein--insert-feedback)

(defun emacsvox-ein--insert-command-feedback ()
  "Speak after an interactive EIN cell insertion command."
  (emacsvox-icon 'yank-object)
  (emacsvox-speak-line)
  (emacsvox-icon 'open-object))

(emacsvox-ein--register-after-group
 '(ein:worksheet-insert-cell-above-km ein:worksheet-insert-cell-below-km)
 #'emacsvox-ein--insert-command-feedback)

(defun emacsvox-ein--yank-cell-feedback ()
  "Speak the cell inserted by an EIN yank command."
  (emacsvox-ein-speak-current-cell)
  (emacsvox-icon 'yank-object))

(emacsvox-ein--register-after-group
 '(ein:worksheet-yank-cell)
 #'emacsvox-ein--yank-cell-feedback)

(defun emacsvox-ein--cell-type-feedback ()
  "Report the current EIN cell type."
  (let ((type (ein:cell-type (ein:worksheet-get-current-cell))))
    (emacsvox-ein-sox-gen type)
    (tts-speak type)))

(emacsvox-ein--register-after-group
 '(ein:worksheet-toggle-cell-type ein:worksheet-change-cell-type-km)
 #'emacsvox-ein--cell-type-feedback)

(defun emacsvox-ein--move-cell-up-feedback ()
  "Report moving an EIN cell up."
  (tts-speak "Moved cell up")
  (emacsvox-icon 'large-movement))

(emacsvox-ein--register-after-group
 '(ein:worksheet-move-cell-up-km)
 #'emacsvox-ein--move-cell-up-feedback)

(defun emacsvox-ein--move-cell-down-feedback ()
  "Report moving an EIN cell down."
  (tts-speak "Moved cell down")
  (emacsvox-icon 'large-movement))

(emacsvox-ein--register-after-group
 '(ein:worksheet-move-cell-down-km)
 #'emacsvox-ein--move-cell-down-feedback)

(defun emacsvox-ein--toggle-output-feedback ()
  "Report the visibility of the current EIN cell output."
  (let ((state (slot-value (ein:worksheet-get-current-cell) 'collapsed)))
    (emacsvox-icon (if state 'close-object 'open-object))
    (tts-speak (format "%s output" (if state "Hid" "Showing")))))

(emacsvox-ein--register-after-group
 '(ein:worksheet-toggle-output-km
   ein:worksheet-set-output-visibility-all-km)
 #'emacsvox-ein--toggle-output-feedback)

(defun emacsvox-ein--merge-cell-feedback ()
  "Speak after merging EIN cells."
  (emacsvox-icon 'close-object)
  (emacsvox-speak-line))

(emacsvox-ein--register-after-group
 '(ein:worksheet-merge-cell)
 #'emacsvox-ein--merge-cell-feedback)

(defun emacsvox-ein--save-feedback ()
  "Confirm saving an EIN notebook."
  (message "Saving notebook")
  (emacsvox-icon 'save-object))

(emacsvox-ein--register-after-group
 '(ein:notebook-save-to-command ein:notebook-save-notebook-command)
 #'emacsvox-ein--save-feedback)

(defun emacsvox-ein--open-notebook-feedback ()
  "Speak after opening an EIN notebook."
  (emacsvox-icon 'open-object)
  (emacsvox-speak-mode-line))

(emacsvox-ein--register-after-group
 '(ein:notebook-jump-to-opened-notebook)
 #'emacsvox-ein--open-notebook-feedback)

(defun emacsvox-ein--close-notebook-feedback ()
  "Speak after closing an EIN notebook."
  (emacsvox-icon 'close-object)
  (emacsvox-speak-mode-line))

(emacsvox-ein--register-after-group
 '(ein:notebook-close-km)
 #'emacsvox-ein--close-notebook-feedback)

(emacsvox-ein--register-after-group
 '(ein:notebooklist-prev-item ein:notebooklist-next-item)
 #'emacsvox-ein--line-movement-feedback)

(defconst emacsvox-ein--removed-targets
  '(ein
    ein:notebook-worksheet-insert-next ein:notebook-worksheet-insert-prev
    ein:notebook-worksheet-move-next ein:notebook-worksheet-move-prev
    ein:notebook-worksheet-open-1th ein:notebook-worksheet-open-2th
    ein:notebook-worksheet-open-3th ein:notebook-worksheet-open-4th
    ein:notebook-worksheet-open-5th ein:notebook-worksheet-open-6th
    ein:notebook-worksheet-open-7th ein:notebook-worksheet-open-8th
    ein:notebook-worksheet-open-last ein:notebook-worksheet-open-next
    ein:notebook-worksheet-open-next-or-first
    ein:notebook-worksheet-open-next-or-new
    ein:notebook-worksheet-open-prev ein:notebook-worksheet-open-prev-or-last)
  "Obsolete pre-nbformat-4 EIN worksheet-tab commands.")

(defun emacsvox-ein--install-advice ()
  "Install native advice for currently loaded EIN features."
  (dolist (entry emacsvox-ein--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

(dolist (feature
         '(ein ein-notebook ein-notebooklist ein-pytools
               ein-traceback ein-worksheet))
  (eval
   `(with-eval-after-load ',feature
      (emacsvox-ein--install-advice))))

(provide 'emacsvox-ein)
;;;  end of file
