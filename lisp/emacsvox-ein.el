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
(require 'emacsvox-aural-submission)
(require 'emacsvox-aural-provider-workflows)

;;;   Face->Voice mappings

(defconst emacsvox-ein--face-voice-map
  '((ein:basecell-input-area-face voice-lighten)
   (ein:basecell-input-prompt-face voice-animate)
   (ein:codecell-input-area-face voice-lighten)
   (ein:codecell-input-prompt-face voice-animate)
   (ein:htmlcell-input-area-face voice-smoothen)
   (ein:htmlcell-input-prompt-face voice-animate)
   (ein:markdowncell-input-area-face voice-smoothen)
   (ein:markdowncell-input-prompt-face voice-animate)
   (ein:rawcell-input-area-face voice-monotone)
   (ein:rawcell-input-prompt-face voice-animate)
   (ein:shared-output-cell-input-area-face voice-lighten)
   (ein:shared-output-cell-input-prompt-face voice-animate)
   (ein:textcell-input-area-face voice-smoothen)
   (ein:textcell-input-prompt-face voice-animate)
   (ein:cell-output-area voice-bolden)
   (ein:cell-output-area-error voice-monotone-extra)
   (ein:cell-output-prompt voice-monotone-extra)
   (ein:cell-output-stderr voice-monotone-extra)
   (ein:notification-tab-normal voice-smoothen-extra)
   (ein:pos-tip-face voice-annotate))
  "Voice personalities for faces defined by the current EIN package.")

(voice-setup-add-map emacsvox-ein--face-voice-map)

;;;  Additional Interactive Commands:

(defsubst emacsvox-ein-sox-gen (type)
  "Present the registered cell-type tone for TYPE.
This compatibility entry point now routes through aural policy rather than
starting an independent SoX process."
  (let ((kind
         (if (symbolp type)
             type
           (intern (downcase (format "%s" type))))))
    (emacsvox-aural-submit-actions
     :facts (list :role 'notebook-cell :notebook-cell-kind kind)
     :module 'ein
     :occasion 'inspection)))

(declare-function ein:cell-type "ein-classes" (arg &rest args))
(declare-function ein:cell-input-pos-min "ein-cell" (cell))
(declare-function ein:cell-input-pos-max "ein-cell" (cell))
(declare-function ein:worksheet-get-current-cell
                  "ein-worksheet" (&rest --cl-rest--))

(defun emacsvox-ein-enable-aural-context ()
  "Identify the current EIN buffer to aural presentation schemes."
  (setq-local emacsvox-aural-module 'ein))

(defun emacsvox-ein--update-notebook-aural-context ()
  "Track EIN notebook minor-mode ownership in the current buffer."
  (if (bound-and-true-p ein:notebook-mode)
      (emacsvox-ein-enable-aural-context)
    (if (derived-mode-p 'python-mode)
        (setq-local emacsvox-aural-module 'python)
      (kill-local-variable 'emacsvox-aural-module))))

(add-hook 'ein:notebook-mode-hook
          #'emacsvox-ein--update-notebook-aural-context)
(add-hook 'ein:notebooklist-mode-hook #'emacsvox-ein-enable-aural-context)

(defun emacsvox-ein--cell-kind (&optional cell)
  "Return the normalized content kind of CELL or the current cell."
  (when-let* ((cell
               (or
                cell
                (ein:worksheet-get-current-cell :noerror t))))
    (intern (downcase (format "%s" (ein:cell-type cell))))))

(defun emacsvox-ein--cell-facts (&optional cell action events)
  "Return semantic facts for CELL, optional ACTION, and EVENTS."
  (let ((facts (list :role 'notebook-cell))
        (kind (emacsvox-ein--cell-kind cell)))
    (when events
      (setq facts (plist-put facts :events events)))
    (when kind
      (setq facts (plist-put facts :notebook-cell-kind kind)))
    (when action
      (setq facts (plist-put facts :notebook-cell-action action)))
    facts))

(defun emacsvox-ein--submit-cell (&optional action occasion events)
  "Present the current cell with optional ACTION, OCCASION, and EVENTS."
  (when-let* ((cell
               (ein:worksheet-get-current-cell :noerror t)))
    (let* ((begin (ein:cell-input-pos-min cell))
           (end (ein:cell-input-pos-max cell))
           (kind (emacsvox-ein--cell-kind cell))
           (facts (emacsvox-ein--cell-facts cell action events))
           (content
            (and
             begin end (< begin end)
             (emacsvox-aural-source-substring begin end))))
      (emacsvox-aural-submit
       (or content (format "empty %s cell" (or kind 'notebook)))
       :facts facts
       :module 'ein
       :occasion (or occasion 'inspection)))))

(defun emacsvox-ein-speak-current-cell ()
  "Speak the complete current cell as one native presentation."
  (interactive)
  (emacsvox-ein--submit-cell nil 'inspection))

(defun emacsvox-ein--present-line (facts occasion)
  "Present the current line under FACTS and OCCASION."
  (let* ((begin (line-beginning-position))
         (end (line-end-position))
         (content
          (and
           (< begin end)
           (emacsvox-aural-source-substring begin end))))
    (if content
        (emacsvox-aural-submit
         content :facts facts :module 'ein :occasion occasion)
      (emacsvox-aural-submit-actions
       :facts (plist-put (copy-sequence facts) :line-condition 'empty)
       :module 'ein
       :occasion occasion))))

(defun emacsvox-ein--buffer-summary ()
  "Return a concise summary of the current EIN buffer."
  (format
   "%s, %s"
   (buffer-name)
   (downcase (format-mode-line mode-name))))

(defun emacsvox-ein--submit-message (text facts)
  "Display and natively present TEXT under FACTS."
  (let ((emacsvox-speak-messages nil))
    (message "%s" text))
  (emacsvox-aural-submit
   text :facts facts :module 'ein :occasion 'state-change))

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
       `(defun ,advice-function (&rest arguments)
          ,(format "Provide speech feedback after `%s'." target)
          (when (ems-interactive-p ',target)
            (apply #',feedback ',target arguments))))
      (push (list target :after advice-function) emacsvox-ein--advice))))

(defun emacsvox-ein--line-movement-feedback (target &rest _)
  "Speak the current line after EIN navigation."
  (emacsvox-ein--present-line
   (list
    :role 'notebook
    :events '(focus-entered)
    :notebook-action target)
   'navigation))

(emacsvox-ein--register-after-group
 '(ein:tb-jump-to-source-at-point-command ein:tb-next-item ein:tb-prev-item)
 #'emacsvox-ein--line-movement-feedback)

(defun emacsvox-ein--open-line-feedback (_target &rest _)
  "Speak the current line after opening an EIN view."
  (emacsvox-ein--present-line
   '(:role notebook :events (object-changed) :notebook-action opened)
   'state-change))

(emacsvox-ein--register-after-group
 '(ein:tb-show-km)
 #'emacsvox-ein--open-line-feedback)

(defun emacsvox-ein--source-movement-feedback (target &rest _)
  "Speak after moving between EIN source locations."
  (emacsvox-ein--line-movement-feedback target))

(emacsvox-ein--register-after-group
 '(ein:pytools-jump-back-command ein:pytools-jump-to-source-command)
 #'emacsvox-ein--source-movement-feedback)

(defun emacsvox-ein--delete-feedback (target &rest _)
  "Speak after deleting EIN cell content."
  (let ((description
         (pcase target
           ('ein:worksheet-clear-all-output-km "Cleared all cell output")
           ('ein:worksheet-clear-output-km "Cleared cell output")
           (_ nil))))
    (if description
        (emacsvox-ein--submit-message
         description
         '(:role notebook-cell
           :events (object-changed)
           :notebook-cell-action removed))
      (or
       (emacsvox-ein--submit-cell
        'removed 'state-change '(object-changed))
       (emacsvox-ein--submit-message
        "Cell removed"
        '(:role notebook-cell
          :events (object-changed)
          :notebook-cell-action removed))))))

(emacsvox-ein--register-after-group
 '(ein:worksheet-clear-all-output-km ein:worksheet-delete-cell
   ein:worksheet-clear-output-km ein:worksheet-kill-cell-km)
 #'emacsvox-ein--delete-feedback)

(defun emacsvox-ein--execute-feedback (target &rest _)
  "Report that the asynchronous EIN execution requested by TARGET started."
  (emacsvox-ein--submit-message
   (if (eq target 'ein:worksheet-execute-all-cells)
       "Notebook execution started. Press C-c . to hear results."
     "Cell execution started. Press C-c . to hear results.")
   (list
    :role 'code-operation
    :events '(operation-started)
    :code-operation-kind target)))

(emacsvox-ein--register-after-group
 '(ein:worksheet-execute-all-cells
   ein:worksheet-execute-cell-and-insert-below
   ein:worksheet-execute-cell-and-insert-below-km
   ein:worksheet-execute-cell-and-goto-next-km
   ein:worksheet-execute-cell-and-goto-next
   ein:worksheet-execute-cell ein:worksheet-execute-cell-km)
 #'emacsvox-ein--execute-feedback)

(defun emacsvox-ein--cell-movement-feedback (_target &rest _)
  "Speak the current EIN cell after navigation."
  (emacsvox-ein--submit-cell nil 'navigation '(focus-entered)))

(emacsvox-ein--register-after-group
 '(ein:worksheet-goto-next-input-km ein:worksheet-goto-prev-input-km
   ein:worksheet-goto-next-input ein:worksheet-goto-prev-input)
 #'emacsvox-ein--cell-movement-feedback)

(defun emacsvox-ein--insert-feedback (_target &rest _)
  "Speak after inserting an EIN cell."
  (emacsvox-ein--submit-cell 'inserted 'edit '(object-changed)))

(emacsvox-ein--register-after-group
 '(ein:worksheet-insert-cell-above ein:worksheet-insert-cell-below
   ein:worksheet-insert-cell-above-km ein:worksheet-insert-cell-below-km)
 #'emacsvox-ein--insert-feedback)

(emacsvox-ein--register-after-group
 '(ein:worksheet-split-cell-at-point)
 (lambda (_target &rest _)
   (emacsvox-ein--submit-cell 'split 'edit '(object-changed))))

(defun emacsvox-ein--yank-cell-feedback (_target &rest _)
  "Speak the cell inserted by an EIN yank command."
  (emacsvox-ein--submit-cell 'yanked 'edit '(object-changed)))

(emacsvox-ein--register-after-group
 '(ein:worksheet-yank-cell)
 #'emacsvox-ein--yank-cell-feedback)

(defun emacsvox-ein--cell-type-feedback (_target &rest _)
  "Report the current EIN cell type."
  (when-let* ((cell
               (ein:worksheet-get-current-cell :noerror t))
              (kind (emacsvox-ein--cell-kind cell)))
    (emacsvox-ein--submit-message
     (format "%s cell" kind)
     (list
      :role 'notebook-cell
      :events '(state-changed)
      :notebook-cell-kind kind
      :notebook-cell-action 'type-changed))))

(emacsvox-ein--register-after-group
 '(ein:worksheet-toggle-cell-type ein:worksheet-change-cell-type-km)
 #'emacsvox-ein--cell-type-feedback)

(defun emacsvox-ein--move-cell-feedback (target &rest _)
  "Report the direction of the cell movement requested by TARGET."
  (emacsvox-ein--submit-message
   (if (eq target 'ein:worksheet-move-cell-up-km)
       "Moved cell up"
     "Moved cell down")
   '(:role notebook-cell
     :events (object-changed)
     :notebook-cell-action moved)))

(emacsvox-ein--register-after-group
 '(ein:worksheet-move-cell-up-km ein:worksheet-move-cell-down-km)
 #'emacsvox-ein--move-cell-feedback)

(defun emacsvox-ein--toggle-output-feedback (target &rest _)
  "Report the visibility of the current EIN cell output."
  (let* ((all
          (eq target 'ein:worksheet-set-output-visibility-all-km))
         (collapsed
          (if all
              (and current-prefix-arg t)
            (when-let* ((cell
                         (ein:worksheet-get-current-cell :noerror t)))
              (slot-value cell 'collapsed)))))
    (emacsvox-ein--submit-message
     (format
      "%s%s output"
      (if collapsed "Hid" "Showing")
      (if all " all cell" " cell"))
     (list
      :role 'notebook-cell
      :events '(visibility-changed)
      :visibility (if collapsed 'folded 'expanded)))))

(emacsvox-ein--register-after-group
 '(ein:worksheet-toggle-output-km
   ein:worksheet-set-output-visibility-all-km)
 #'emacsvox-ein--toggle-output-feedback)

(defun emacsvox-ein--merge-cell-feedback (_target &rest _)
  "Speak after merging EIN cells."
  (emacsvox-ein--submit-cell 'merged 'edit '(object-changed)))

(emacsvox-ein--register-after-group
 '(ein:worksheet-merge-cell)
 #'emacsvox-ein--merge-cell-feedback)

(defun emacsvox-ein--save-feedback (target &rest _)
  "Report that the asynchronous notebook save requested by TARGET started."
  (emacsvox-ein--submit-message
   "Saving notebook"
   (list
    :role 'code-operation
    :events '(operation-started)
    :code-operation-kind target)))

(emacsvox-ein--register-after-group
 '(ein:notebook-save-to-command ein:notebook-save-notebook-command)
 #'emacsvox-ein--save-feedback)

(defun emacsvox-ein--open-notebook-feedback (_target &rest _)
  "Speak after opening an EIN notebook."
  (emacsvox-aural-submit
   (emacsvox-ein--buffer-summary)
   :facts '(:role notebook :events (object-changed) :notebook-action opened)
   :module 'ein
   :occasion 'state-change))

(emacsvox-ein--register-after-group
 '(ein:notebook-jump-to-opened-notebook)
 #'emacsvox-ein--open-notebook-feedback)

(defun emacsvox-ein--close-notebook-feedback (_target &rest _)
  "Speak after closing an EIN notebook."
  (emacsvox-aural-submit
   (format "Notebook closed. %s" (emacsvox-ein--buffer-summary))
   :facts '(:role notebook :events (object-changed) :notebook-action closed)
   :module 'ein
   :occasion 'state-change))

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
