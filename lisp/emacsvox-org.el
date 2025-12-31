;;; emacsvox-org.el --- Speech-enable org  -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:  Emacsvox front-end for ORG
;; Keywords: Emacsvox, org
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;;
;;  $Revision: 4347 $ |
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
;; Speech-enable org ---
;;  Org allows you to keep organized notes and todo lists.
;; Homepage: http://www.astro.uva.nl/~dominik/Tools/org/
;; or http://orgmode.org/
;;
;;; Code:

;;  required modules

(eval-when-compile (require 'cl-lib))
(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacsvox-preamble)
(require 'emacsvox-amark)
(require 'org)
(require 'org-element)
(require 'org-table "org-table" 'no-error)
(defvar org-ans2 nil)

;;;  voice locking:

(voice-setup-add-map
 '(
   (org-date voice-animate)
   (org-done voice-monotone-extra)
   (org-formula voice-animate-extra)
   (org-headline-done voice-monotone-medium)
   (org-level-1 voice-bolden)
   (org-level-2 voice-brighten)
   (org-level-3 voice-animate)
   (org-level-4 voice-lighten)
   (org-level-5 voice-smoothen)
   (org-level-6 voice-monotone)
   (org-level-7 voice-lighten-medium)
   (org-level-8 voice-lighten-extra)
   (org-link voice-bolden)
   (org-scheduled-previously voice-lighten-medium)
   (org-scheduled-today voice-bolden-extra)
   (org-special-keyword voice-lighten-extra)
   (org-table voice-bolden)
   (org-tag voice-smoothen)
   (org-time-grid voice-bolden)
   (org-todo voice-bolden-and-animate)
   (org-warning voice-bolden-and-animate)
   (org-agenda-calendar-event voice-animate-extra)
   (org-agenda-calendar-sexp voice-animate)
   (org-agenda-column-dateline voice-monotone-extra)
   (org-agenda-diary voice-animate)
   (org-agenda-dimmed-todo-face voice-smoothen-medium)
   (org-agenda-done voice-monotone-extra)
   (org-agenda-filter-category voice-lighten-extra)
   (org-agenda-filter-tags voice-lighten)
   (org-agenda-restriction-lock voice-monotone-extra)
   (org-agenda-structure voice-bolden)
   (org-archived voice-monotone-extra)
   (org-beamer-tag voice-bolden)
   (org-block voice-monotone-extra)
   (org-checkbox voice-animate)
   (org-coverlay voice-animate)
   (org-code voice-monotone-extra)
   (org-column voice-lighten)
   (org-column-title voice-lighten-extra)
   (org-date-selected voice-bolden)
   (org-default voice-smoothen)
   (org-document-info voice-monotone)
   (org-document-info-keyword voice-bolden-extra)
   (org-document-title voice-bolden)
   (org-drawer voice-smoothen-medium)
   (org-ellipsis voice-smoothen-extra)
   (org-footnote voice-smoothen)
   (org-habit-alert-face voice-monotone-extra)
   (org-habit-alert-future-face voice-monotone-extra)
   (org-habit-clear-face voice-monotone-extra)
   (org-habit-clear-future-face voice-monotone-extra)
   (org-habit-overdue-face voice-monotone-extra)
   (org-habit-overdue-future-face voice-monotone-extra)
   (org-habit-ready-future-face voice-monotone-extra)
   (org-hide voice-smoothen-extra)
   (org-indent voice-smoothen)
   (org-inlinetask voice-smoothen-extra)
   (org-meta-line voice-smoothen-medium)
   (org-property-value voice-animate)
   (org-scheduled voice-animate)
   (org-sexp-date voice-monotone-extra)
   (org-target voice-bolden)
   (org-upcoming-deadline voice-animate)
   (org-verbatim voice-monotone-extra)
   (org-habit-ready-face voice-monotone-extra)))

;;;  Structure Navigation:

(defun emacsvox-org-speak-item  ()
  "Speak item"
  (interactive )
  (unless (eq major-mode 'org-mode) (error "Not in an org buffer"))
  (unless (org-at-item-p) (error "Not at an item"))
  (save-excursion
    (let ((start (org-beginning-of-item))
          (end (org-end-of-item)))
      (emacsvox-speak-region start end))))

(cl-loop
 for f in
 '(org-next-item org-previous-item)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'item)
       (emacsvox-org-speak-item)))))

(cl-loop
 for f in
 '(
   org-mark-ring-goto org-mark-ring-push
   org-next-visible-heading org-previous-visible-heading
   org-forward-heading-same-level org-backward-heading-same-level
   org-backward-sentence org-forward-sentence
   org-backward-element org-forward-element
   org-next-link org-previous-link
   org-goto  org-goto-ret
   org-goto-left org-goto-right
   org-goto-quit
   org-metaleft org-metaright org-metaup org-metadown
   org-meta-return
   org-shiftmetaleft org-shiftmetaright org-shiftmetaup org-shiftmetadown
   org-mark-element org-mark-subtree
   )
 do
 (eval
  `(defadvice ,f(after emacsvox pre act comp)
     "Speak."
     (when (ems-interactive-p)
       (emacsvox-speak-line)
       (emacsvox-icon 'large-movement)))))

(cl-loop
 for f in 
 '(
   org-backward-paragraph org-forward-paragraph
   org-agenda-forward-block org-agenda-backward-block)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'paragraph)
       (emacsvox-speak-paragraph)))))

(defun ems--org-cycle-list-bullet-after (&rest _)
  "Speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'item) (emacsvox-speak-line)))

(advice-add 'org-cycle-list-bullet :after
            #'ems--org-cycle-list-bullet-after)

(defcustom emacsvox-org-table-after-movement-function
  #'emacsvox-org-table-speak-current-element
  "The function to call after moving in a table"
  :type
  '(choice
    (const :tag "speak cell contents only"
           emacsvox-org-table-speak-current-element)
    (const :tag "speak column header" emacsvox-org-table-speak-column-header)
    (const :tag "speak row header" emacsvox-org-table-speak-row-header)
    (const :tag "speak cell contents and column header"
           emacsvox-org-table-speak-column-header-and-element)
    (const :tag "speak cell contents and row header"
           emacsvox-org-table-speak-row-header-and-element)
    (const :tag "speak column contents and both headers"
           emacsvox-org-table-speak-both-headers-and-element))
  :group 'emacsvox-org)

;; orgalist-mode defines structured navigators that in turn call org-cycle.
;; Removing itneractive check in advice for org-cycle
;; to speech enable all such nav commands.
;; Note that org itself produces the folded state via org-unlogged-message
;; Which gets spoken by Emacsvox
(cl-loop
 for f in
 '(org-cycle org-shifttab)
 do
 (eval
  `(defadvice ,f(after emacsvox pre act comp)
     "speak."
     (cond
      ((org-at-table-p 'any)
       (funcall emacsvox-org-table-after-movement-function))
      (t
       (let ((dtk-stop-immediately nil))
         (when (ems-interactive-p)
           (emacsvox-speak-line))))))))

(defun ems--org-overview-after (&rest _)
  "speak."
  (when (ems-interactive-p) (message "Showing top-level overview.")))

(advice-add 'org-overview :after #'ems--org-overview-after)

(defun ems--org-content-after (&rest _)
  "speak."
  (when (ems-interactive-p) (message "Showing table of contents.")))

(advice-add 'org-content :after #'ems--org-content-after)

(defun ems--org-tree-to-indirect-buffer-after (&rest _)
  "Speak."
  (when (ems-interactive-p)
    (message "Cloned %s"
             (with-current-buffer org-last-indirect-buffer
               (goto-char (point-min))
               (buffer-substring (line-beginning-position)
                                 (line-end-position))))))

(advice-add 'org-tree-to-indirect-buffer :after
            #'ems--org-tree-to-indirect-buffer-after)

;;;  Header insertion and relocation

(cl-loop
 for f in
 '(
   org-delete-indentation
   org-insert-heading org-insert-todo-heading
   org-insert-structure-template
   org-promote-subtree org-demote-subtree
   org-do-promote org-do-demote
   org-move-subtree-up org-move-subtree-down
   org-convert-to-odd-levels org-convert-to-oddeven-levels
   )
 do
 (eval
  `(defadvice ,f(after emacsvox pre act comp)
     "Speak."
     (when (ems-interactive-p)
       (emacsvox-speak-line)
       (emacsvox-icon 'open-object)))))

(defun ems--org-delete-char-around (orig-fun &rest args)
  "Speak character you're deleting."
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p) (dtk-tone-deletion) (emacsvox-speak-char t)
      (apply orig-fun args))
     (t (apply orig-fun args)))
    result))

(advice-add 'org-delete-char :around #'ems--org-delete-char-around)

;;;  cut and paste:

(cl-loop
 for f in
 '(
   org-cut-subtree org-copy-subtree
   org-paste-subtree org-archive-subtree
   org-narrow-to-subtree)
 do
 (eval
  `(defadvice ,f(after emacsvox pre act comp)
     "Speak."
     (when (ems-interactive-p)
       (emacsvox-speak-line)
       (emacsvox-icon 'yank-object)))))

;;;  completion:

(defun ems--org-complete-around (orig-fun &rest args)
  "Say what you completed."
  (let ((result (apply orig-fun args)))
    (let
        ((prior (save-excursion (skip-syntax-backward "^ >") (point)))
         (dtk-stop-immediately t))
      (apply orig-fun args)
      (if (> (point) prior)
          (tts-with-punctuations 'all
                                 (if
                                     (>
                                      (length
                                       (emacsvox-get-minibuffer-contents))
                                      0)
                                     (dtk-speak
                                      (emacsvox-get-minibuffer-contents))
                                   (emacsvox-speak-line)))
        (emacsvox-speak-completions-if-available))
      result)
    result))

(advice-add 'org-complete :around #'ems--org-complete-around)

;;;  toggles:

(cl-loop
 for f in
 '(
   org-toggle-archive-tag org-toggle-comment)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "Speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'button)
       (emacsvox-speak-line)))))

;;;  ToDo:

;;;  timestamps and calendar:

(cl-loop
 for f in
 '(org-timestamp-down-day org-timestamp-up-day)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'select-object)
       (emacsvox-speak-line)))))

(cl-loop for f in
         '(org-timestamp-down org-timestamp-up)
         do
         (eval
          `(defadvice ,f (after emacsvox pre act comp)
             "speak."
             (when (ems-interactive-p)
               (emacsvox-icon 'select-object)
               (dtk-speak org-last-changed-timestamp)))))

(defun ems--org-eval-in-calendar-after (&rest _)
  "Speak what is returned." 
  (dtk-speak org-ans2))

(advice-add 'org-eval-in-calendar :after
            #'ems--org-eval-in-calendar-after)

;;;  Agenda:

;; AGENDA NAVIGATION

(cl-loop
 for f in
 '(
   org-agenda-next-date-line org-agenda-previous-date-line
   org-agenda-next-line org-agenda-previous-line
   org-agenda-goto-today
   )
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'select-object)
       (emacsvox-speak-line)))))

(cl-loop
 for f in
 '(org-agenda-quit org-agenda-exit)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'close-object)
       (emacsvox-speak-mode-line)))))

(cl-loop
 for f in
 '(org-agenda-goto org-agenda-show org-agenda-switch-to)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'open-object)
       (emacsvox-speak-line)))))

(defun ems--org-agenda-after (&rest _)
  "Speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'open-object) (emacsvox-speak-line)))

(advice-add 'org-agenda :after #'ems--org-agenda-after)

;;;  tables:

;;;  table minor mode:

(defun ems--orgtbl-mode-after (&rest _)
  "speak." 
  (when (ems-interactive-p)
    (emacsvox-icon (if orgtbl-mode 'on 'off))
    (message "Turned %s org table mode." (if orgtbl-mode 'on 'off))))

(advice-add 'orgtbl-mode :after #'ems--orgtbl-mode-after)

;;;  deleting chars:

(defun ems--org-return-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (cond
     ((org-at-table-p 'any)
      (funcall emacsvox-org-table-after-movement-function))
     (t (emacsvox-speak-line) (emacsvox-icon 'select-object)))))

(advice-add 'org-return :after #'ems--org-return-after)

;;;  Keymap update:

(defun emacsvox-org-update-keys ()
  "Update keys in org mode."
  
  (cl-loop
   for k in
   '(
     ("C-e" emacsvox-keymap)
     ("C-j" org-insert-heading)
     ("M-<down>" org-metadown)
     ("M-<left>"  org-metaleft)
     ("M-<right>" org-metaright)
     ("M-<up>" org-metaup)
     ("M-RET" org-meta-return)
     ("M-S-<down>" org-shiftmetadown)
     ("M-S-<left>" org-shiftmetaleft)
     ("M-S-<right>" org-shiftmetaright)
     ("M-S-<up>" org-shiftmetaup)
     ("M-S-RET" org-insert-todo-heading)
     ("S-RET" org-table-previous-row)
     ("S-<down>" org-shiftdown)
     ("S-<left>" org-shiftleft)
     ("S-<right>" org-shiftright)
     ("S-<up>" org-shiftup)
     ("S-TAB" org-shifttab))
   do
   (emacsvox-keymap-update  org-mode-map k)))

;;;  mode hook:

(defun emacsvox-org-mode-setup ()
  "Placed on org-mode-hook to do Emacsvox setup."
  
  (emacsvox-org-update-keys)
  (cl-loop
   for b in  
   '(("M-n" org-next-item)
     ("M-p" org-previous-item)
     ("C-o a" tvr-org-alphabetize)
     ("C-o e" tvr-org-enumerate)
     ("C-o i" tvr-org-itemize))
   do
   (emacsvox-keymap-update org-mode-map b))
  (define-prefix-command 'org-multi-keymap)
  (define-key org-mode-map (kbd "C-'") 'org-multi-keymap)
  (define-key org-multi-keymap "n" #'org-next-link)
  (define-key org-multi-keymap "'" #'org-open-at-point)
  (define-key org-multi-keymap ";" #'emacsvox-org-amarks-play)
  (define-key org-multi-keymap "p" #'org-previous-link)
  (define-key org-mode-map (kbd "C-,") 'emacsvox-alt-keymap)
  (define-key org-mode-map (kbd "C-c m") 'org-md-export-as-markdown)
  (define-key global-map (kbd "C-c i") 'org-insert-link)
  (define-key global-map (kbd "C-c l") 'org-store-link)
  (define-key global-map (kbd "C-c b") 'org-switchb)
  (define-key global-map  (kbd "C-c c") 'org-capture)
  (when (fboundp 'org-end-of-line)
    (define-key org-mode-map emacsvox-prefix  'emacsvox-keymap)
    (emacsvox-setup-programming-mode)
    (when dtk-caps (dtk-toggle-caps))
    (emacsvox-speak-load-directory-settings)))

(add-hook 'org-mode-hook #'emacsvox-org-mode-setup)

;; advice end-of-line here to call org specific action

(defun ems--end-of-line-after (&rest _)
  "Call org specific actions in org mode."
  (when
      (and (ems-interactive-p) (eq major-mode 'org-mode)
           (fboundp 'org-end-of-line))
    (org-end-of-line)))

(advice-add 'end-of-line :after #'ems--end-of-line-after)

(defun ems--org-toggle-checkbox-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'button) (emacsvox-speak-line)))

(advice-add 'org-toggle-checkbox :after
            #'ems--org-toggle-checkbox-after)

;;;  fix misc commands:

(cl-loop
 for f in
 '(
   org-occur
   org-beginning-of-item org-beginning-of-item-list
   org-end-of-item org-end-of-item-list)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p) (emacsvox-speak-line)
           (emacsvox-icon 'select-object)))))

(defun ems--org-beginning-of-line-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-speak-line) (emacsvox-icon 'left)))

(advice-add 'org-beginning-of-line :after
            #'ems--org-beginning-of-line-after)

(defun ems--org-end-of-line-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-speak-line) (emacsvox-icon 'right)))

(advice-add 'org-end-of-line :after #'ems--org-end-of-line-after)

;;;  global input wizard

(defun emacsvox-org-popup-input ()
  "Pops up an org input area."
  (interactive)
  (emacsvox-org-popup-input-buffer 'org-mode))

;;;  org capture

(defun ems--org-capture-goto-last-stored-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (emacsvox-speak-line)))

(advice-add 'org-capture-goto-last-stored :after
            #'ems--org-capture-goto-last-stored-after)

(defun ems--org-capture-goto-target-after (&rest _)
  "speak." (emacsvox-icon 'large-movement) (emacsvox-speak-line))

(advice-add 'org-capture-goto-target :after
            #'ems--org-capture-goto-target-after)

(defun ems--org-capture-finalize-after (&rest _)
  "speak." (emacsvox-icon 'save-object))

(advice-add 'org-capture-finalize :after
            #'ems--org-capture-finalize-after)

(defun ems--org-capture-kill-after (&rest _)
  "speak." (emacsvox-icon 'close-object))

(advice-add 'org-capture-kill :after #'ems--org-capture-kill-after)

(defun emacsvox-org-table-speak-current-element ()
  "echoes current table element"
  (interactive)
  (let ((field (org-table-get-field)))
    (cond
     ((string-match "^ *$" field) (dtk-speak "space"))
     (t (message field)))))

(defun emacsvox-org-table-speak-column-header ()
  "echoes column header"
  (interactive)
  (message
   (propertize (org-table-get 1 nil) 'face 'bold)))

(defun emacsvox-org-table-speak-row-header ()
  "echoes row header"
  (interactive)
  (message
   (propertize (org-table-get nil 1) 'face 'italic)))

(defun emacsvox-org-table-speak-coordinates ()
  "echoes coordinates"
  (interactive)
  (message
   (concat "row " (number-to-string (org-table-current-line))
           ", column " (number-to-string (org-table-current-column)))))

(defun emacsvox-org-table-speak-both-headers-and-element ()
  "echoes both row and col headers."
  (interactive)
  (message
   (concat
    (propertize (org-table-get nil 1) 'face 'italic)
    " "
    (propertize (org-table-get  1 nil) 'face 'bold) " "
    (org-table-get-field))))

(defun emacsvox-org-table-speak-row-header-and-element ()
  "echoes row header and element"
  (interactive)
  (message
   (concat
    (propertize (org-table-get nil 1) 'face 'italic)
    " "
    (org-table-get-field))))

(defun emacsvox-org-table-speak-column-header-and-element ()
  "echoes col header and element"
  (interactive)
  (if (eq (org-table-current-line) 1) ;; we're on the header line, 
      (message (org-table-get-field))
    (message
     (concat
      (propertize (org-table-get  1 nil) 'face 'bold)
      " "
      (org-table-get-field)))))

(cl-loop
 for f in
 '(org-table-next-field org-table-previous-field
                        org-table-next-row org-table-previous-row)
 do
 (eval
  `(defadvice ,f  (after emacsvox pre act comp)
     "speak."
     (funcall emacsvox-org-table-after-movement-function))))

;;;  Additional table function:

(unless (fboundp 'org-table-previous-row)
  (defun org-table-previous-row ()
    "Go to the previous row (same column) in the current table.
Before doing so, re-align the table if necessary."
    (interactive)
    (org-table-maybe-eval-formula)
    (org-table-maybe-recalculate-line)
    (if (or (looking-at "[ \t]*$")
            (save-excursion (skip-chars-backward " \t") (bolp)))
        (newline)
      (if (and org-table-automatic-realign
               org-table-may-need-update)
          (org-table-align))
      (let ((col (org-table-current-column)))
        (beginning-of-line 0)
        (when (or (not (org-at-table-p)) (org-at-table-hline-p))
          (beginning-of-line 1))
        (org-table-goto-column col)
        (skip-chars-backward "^|\n\r")
        (if (looking-at " ") (forward-char 1))))))

;;;  Capture

(defcustom emacsvox-org-hotlist  (expand-file-name
                                  "~/.org/hotlist.org")
  "Emacsvox org hotlist location."
  :type 'file
  :group 'emacsvox-org)

;;;###autoload
(defun emacsvox-org-capture-link (&optional open)
  "Capture hyperlink to current context.
To use this command, first do `customize-variable'
`org-capture-template' and assign letter `h' to a template that
creates the hyperlink on capture.  Optional interactive prefix
arg just opens the file"
  (interactive "P")
  (require 'org)
  (require 'ol-eww)
  (cond
   (open (funcall-interactively #'find-file  emacsvox-org-hotlist))
   (t
    (org-store-link nil)
    (org-capture nil "h"))))

(declare-function emacsvox-eww-current-title "emacsvox-eww" nil)

;;;  Speech-enable export prompt:

(defun ems--org-export--dispatch-action-before (&rest _)
  "Speak prompt intelligently."
  (let
      ((prompt (ad-get-arg 0)) (entries (ad-get-arg 2))
       (first-key (ad-get-arg 4)) (choices nil))
    (setq choices
          (cond ((null first-key) entries)
                (t (cl-caddr (assoc first-key entries)))))
    (dtk-notify
     (mapconcat
      #'(lambda (e) (format "%c: %s\n" (cl-first e) (cl-second e)))
      choices "\n"))
    (sit-for 5)))

(advice-add 'org-export--dispatch-action :before
            #'ems--org-export--dispatch-action-before)

;;;  Preview HTML With EWW:

(defun emacsvox-org-eww-file (file _link)
  "Preview HTML files with EWW from exporter."
  (add-hook 'emacsvox-eww-post-hook  #'emacsvox-speak-buffer)
  (funcall-interactively #'eww-open-file file))

;;;  Edit Special Advice:

(cl-loop
 for f in
 '(org-edit-src-exit org-edit-src-abort)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'close-object)
       (emacsvox-speak-line)))))

(cl-loop
 for f in
 '(org-edit-src-code org-edit-special org-switchb) do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (emacsvox-icon 'open-object)
       (emacsvox-speak-mode-line)))))

;;;  Fillers:

(defun ems--org-fill-paragraph-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'fill-object) (message "Filled current paragraph")))

(advice-add 'org-fill-paragraph :after #'ems--org-fill-paragraph-after)

(defun ems--org-todo-after (&rest _)
  "speak when changing the state of a TODO item."
  (when (ems-interactive-p)
    (emacsvox-icon 'button)
    (let ((state (org-get-todo-state)))
      (if (null state) (message "State unset") (message state)))))

(advice-add 'org-todo :after #'ems--org-todo-after)

;;; TVR: Conveniences

(defun tvr-org-itemize ()
  "Start a numbered  list."
  (interactive)
  (forward-line 0)
  (insert "  -  ")
  (emacsvox-speak-line)
  (emacsvox-icon 'item))

(defun tvr-org-enumerate ()
  "Start a numbered  list."
  (interactive)
  (forward-line 0)
  (insert "  1.  ")
  (emacsvox-speak-line)
  (emacsvox-icon 'item))

(defun tvr-org-alphabetize ()
  "Start an alphabetized   list."
  (interactive)
  (forward-line 0)
  (insert "  A.  ")
  (emacsvox-speak-line)
  (emacsvox-icon 'item))

;;;  specialized input buffers:

;; Taken from a message on the org mailing list.

(defun emacsvox-org-popup-input-buffer (mode)
  "Provide an input buffer in a specified mode."
  (interactive
   (list
    (intern
     (completing-read
      "Mode: "
      (mapcar
       #'(lambda (e)
           (list (symbol-name e)))
       (apropos-internal "-mode$" 'commandp))
      nil t))))
  (let ((buffer-name (generate-new-buffer-name "*input*")))
    (pop-to-buffer (make-indirect-buffer (current-buffer) buffer-name))
    (narrow-to-region (point) (point))
    (funcall mode)
    (let ((map (copy-keymap (current-local-map))))
      (define-key map (kbd "C-c C-c")
                  #'(lambda ()
                      (interactive)
                      (kill-buffer nil)
                      (delete-window)))
      (use-local-map map))
    (shrink-window-if-larger-than-buffer)))

;;; md export:

(defun ems--org-md-export-as-markdown-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'task-done) (emacsvox-speak-mode-line)))

(advice-add 'org-md-export-as-markdown :after
            #'ems--org-md-export-as-markdown-after)

;;; Amark:

(org-link-set-parameters
 "amark"
 :follow #'org-amark-follow-link
 :store #'org-amark-store-link
 :display 'org-link)

(defun org-amark-store-link ()
  "Store a link to a AMark.
Is enabled in the AMark Browser and M-Player Interaction buffers."
  (when-let
      ((m (memq major-mode '(emacsvox-m-player-mode emacsvox-amark-mode)))
       (amark
        (if  (button-at (point))
            (button-get (button-at (point)) 'mark)
          (call-interactively #'emacsvox-amark-find)))
       (link
        (concat
         "amark:" (emacsvox-amark-path amark)
         "#" (emacsvox-amark-position amark))))
    (org-link-store-props
     :type "amark" :link link
     :description (emacsvox-amark-name amark) )
    link))

(defun org-amark-follow-link (name)
  "Follow an AMark link."
  (when-let
      ((match (string-match "\\(.*\\)#\\(.*\\)" name))
       (filename (match-string 1 name))
       (position  (match-string 2 name)))
    (emacsvox-amark-play
     (make-emacsvox-amark :path filename  :position position))))

;;; Play Amarks:

(defun emacsvox-org-amarks-play ()
  "Loop through and play list of Amarks from org buffer.
Hit C-g to break out of the loop.
Press `y' to play to next amark."
  (interactive)
  (org-element-map
   (org-element-parse-buffer)
   'link
   (lambda (link)
     (when (string= (org-element-property :type link) "amark")
       (org-amark-follow-link
        (org-element-property :path link))))))

;;; EWW Marks:

(org-link-set-parameters
 "ebook"
 :follow #'emacsvox-eww-open-mark
 :store #'org-ebook-store-link
 :display 'org-link)

(defun org-ebook-store-link ()
  "Store a link to an EWW mark from an EBook. "
  (when-let
      ((m (eq major-mode 'emacsvox-eww-marks-mode))
       (b (button-at (point)))
       (desc  (buffer-substring (button-start b) (button-end b)))
       (link
        (concat
         "ebook:" (button-label b))))
    (org-link-store-props
     :type "ebook" :link link :description desc )
    link))

;;; e-media:

(defsubst org--ems-yt-p (url)
  "Predicate to check for YT urls."
  (string-match
   (format
    "^%s"
    (regexp-opt
     '("https://www.youtube.com/"
       "https://youtube.com/"
       "https://youtu.be/"
       "https://yewtu.be/"
       "http://www.youtube.com/"
       "http://youtube.com/"
       "http://youtu.be/"
       "http://yewtu.be/")))
   url))

(org-link-set-parameters
 "e-media"        ; stored from m-player or mtp
 :follow #'emacsvox-org-e-media-follow-url)

(declare-function
 emacsvox-eww-play-media-at-point "emacsvox-eww" (&optional playlist-p))

(defun emacsvox-org-e-media-follow-url (url)
  "Handle e-media URL, either mtv or mplayer based on URL."
  (cond
   ((org--ems-yt-p url) (empv-play url))
   (t (emacsvox-eww-play-media-at-point url))))
;;; org publish

(add-hook
 'org-publish-after-publishing-hook
 #'(lambda (_s _t)
     (emacsvox-icon 'save-object)
     (emacsvox-speak-message-again)))

(defun ems--org-export-to-file-after (&rest _)
  "speak." (emacsvox-icon 'save-object)
  (dtk-notify (format "Wrote %s" (ad-get-arg 1))))

(advice-add 'org-export-to-file :after #'ems--org-export-to-file-after)

(provide 'emacsvox-org)
;;;  end of file

