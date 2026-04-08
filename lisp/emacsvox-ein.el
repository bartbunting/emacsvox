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

;;; tb (traceback):

(cl-loop
 for f in 
 '(ein:tb-jump-to-source-at-point-command
   ein:tb-next-item ein:tb-prev-item)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-speak-line)
       (emacsvox-icon 'large-movement)))))

(defun ems--ein:tb-show-km-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-line)))

(advice-add 'ein:tb-show-km :after #'ems--ein:tb-show-km-after)

;;; pytools:

(cl-loop
 for f in 
 '(ein:pytools-jump-back-command ein:pytools-jump-to-source-command)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'large-movement)
       (emacsvox-speak-line)))))

;;;  Worksheets:

(cl-loop
 for f in
 '(
   ein:worksheet-clear-all-output-km ein:worksheet-delete-cell
   ein:worksheet-clear-output-km ein:worksheet-kill-cell-km) do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-speak-line)
       (emacsvox-icon 'delete-object)))))

(cl-loop
 for f in
 '(
   ein:worksheet-execute-all-cells 
   ein:worksheet-execute-cell-and-insert-below
   ein:worksheet-execute-cell-and-insert-below-km
   ein:worksheet-execute-cell-and-goto-next-km
   ein:worksheet-execute-cell-and-goto-next
   ein:worksheet-execute-cell ein:worksheet-execute-cell-km) do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'task-done)
       (forward-line 1)
       (message "Press C-c . to hear the results.")))))

(cl-loop
 for f in
 '(
   ein:worksheet-goto-next-input-km ein:worksheet-goto-prev-input-km
   ein:worksheet-goto-next-input ein:worksheet-goto-prev-input)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'large-movement)
       (emacsvox-ein-speak-current-cell)))))

(cl-loop
 for f in
 '(
   ein:worksheet-yank-cell
   ein:worksheet-insert-cell-above-km ein:worksheet-insert-cell-above
   ein:worksheet-insert-cell-below-km ein:worksheet-insert-cell-below)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'yank-object)
       (emacsvox-speak-line)))))

(cl-loop
 for f in 
 '(ein:worksheet-toggle-cell-type ein ein:worksheet-change-cell-type-km )
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-ein-sox-gen (ein:cell-type (ein:worksheet-get-current-cell)))
       (dtk-speak (ein:cell-type (ein:worksheet-get-current-cell)))))))

(cl-loop
 for f in 
 '(ein:worksheet-insert-cell-below-km ein:worksheet-insert-cell-above-km)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'open-object)
       (emacsvox-speak-line)))))

(defun ems--ein:worksheet-move-cell-up-km-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (dtk-speak "Moved cell up") (emacsvox-icon 'large-movement)))

(advice-add 'ein:worksheet-move-cell-up-km :after
            #'ems--ein:worksheet-move-cell-up-km-after)

(defun ems--ein:worksheet-move-cell-down-km-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (dtk-speak "Moved cell down") (emacsvox-icon 'large-movement)))

(advice-add 'ein:worksheet-move-cell-down-km :after
            #'ems--ein:worksheet-move-cell-down-km-after)

(defun ems--ein:worksheet-yank-cell-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-ein-speak-current-cell) (emacsvox-icon 'yank-object)))

(advice-add 'ein:worksheet-yank-cell :after
            #'ems--ein:worksheet-yank-cell-after)

(cl-loop
 for f in 
 '(ein:worksheet-toggle-output-km ein:worksheet-set-output-visibility-all-km)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (let  ((state (slot-value (ein:worksheet-get-current-cell)
                                 'collapsed )))
         (emacsvox-icon
          (if state 'close-object 'open-object))
         (dtk-speak
          (format "%s output"
                  (if state "Hid" "Showing"))))))))

(defun ems--ein:worksheet-split-cell-at-point-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-line)))

(advice-add 'ein:worksheet-split-cell-at-point :after
            #'ems--ein:worksheet-split-cell-at-point-after)

(defun ems--ein:worksheet-merge-cell-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'close-object) (emacsvox-speak-line)))

(advice-add 'ein:worksheet-merge-cell :after
            #'ems--ein:worksheet-merge-cell-after)

;;; Notebooks:

(cl-loop
 for f in 
 '(ein:notebook-save-to-command ein:notebook-save-notebook-command)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (message "Saving notebook")
       (emacsvox-icon 'save-object)))))

(cl-loop
 for f in 
 '(
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
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'open-object)
       (emacsvox-speak-mode-line)))))

(defun ems--ein:notebook-jump-to-opened-notebook-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(advice-add 'ein:notebook-jump-to-opened-notebook :after
            #'ems--ein:notebook-jump-to-opened-notebook-after)

(defun ems--ein:notebook-close-km-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'close-object) (emacsvox-speak-mode-line)))

(advice-add 'ein:notebook-close-km :after
            #'ems--ein:notebook-close-km-after)

;;; Notebooklists:

(cl-loop
 for f in 
 '(ein:notebooklist-prev-item ein:notebooklist-next-item)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'large-movement)
       (emacsvox-speak-line)))))

(provide 'emacsvox-ein)
;;;  end of file

