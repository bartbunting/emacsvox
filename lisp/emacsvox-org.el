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
;; Location https://github.com/robertmeta/emacsvox
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

(require 'cl-lib)
(require 'subr-x)
(require 'emacsvox-preamble)
(require 'emacsvox-aural-submission)
(require 'emacsvox-aural-transport)
(require 'emacsvox-aural-provider-org)
(require 'emacsvox-amark)
(require 'org)
(require 'org-element)
(require 'org-table "org-table" 'no-error)
(defvar org-ans2 nil)
(defvar org-multi-keymap)
(defvar emacsvox-speak-messages)

;;;  Semantic aural presentation:

(defvar-local emacsvox-org-aural-annotation-enabled nil
  "Non-nil when semantic heading annotation is installed in this buffer.")

(defun emacsvox-org-heading-folded-p ()
  "Return non-nil when point is on an Org heading with hidden descendants."
  (and
   (org-at-heading-p)
   (org-fold-folded-p (line-end-position) 'outline)))

(defun emacsvox-org-heading-facts (&optional event action)
  "Return semantic facts for the Org heading at point.

Optional EVENT records the registered event that caused its presentation.
Optional ACTION identifies the user-visible Org operation."
  (when (org-at-heading-p)
    (let* ((folded (emacsvox-org-heading-folded-p))
           (facts
            (list
             :role 'heading
             :level (org-reduced-level (org-outline-level))
             :visibility (if folded 'folded 'expanded))))
      (when folded
        (setq facts (plist-put facts :states '(folded))))
      (when event
        (setq facts (plist-put facts :events (list event))))
      (when action
        (setq facts (plist-put facts :org-action action)))
      facts)))

(defun emacsvox-org--feedback-facts (role event action)
  "Return Org facts for ROLE, EVENT, and user-visible ACTION."
  (append
   (list :role role)
   (when event (list :events (list event)))
   (when action (list :org-action action))))

(defun emacsvox-org--submit-message-feedback
    (facts occasion icon text)
  "Display TEXT and submit it with FACTS, OCCASION, and leading ICON.

Message speech is inhibited because the native submission owns the audible
presentation."
  (let ((emacsvox-speak-messages nil))
    (message "%s" text))
  (emacsvox-aural-submit
   text
   :facts facts
   :module 'org
   :occasion occasion
   :compatibility-actions
   (and icon (list (emacsvox-aural-compatibility-icon icon)))))

(defun emacsvox-org--submit-actions (facts occasion &rest icons)
  "Submit FACTS and compatibility ICONS as one action-only transaction."
  (emacsvox-aural-submit-actions
   :facts facts
   :module 'org
   :occasion occasion
   :compatibility-actions
   (mapcar #'emacsvox-aural-compatibility-icon icons)))

(defun emacsvox-org--submit-text
    (content facts occasion &optional icon icon-phase)
  "Submit CONTENT under FACTS and OCCASION with optional compatibility ICON.
ICON-PHASE defaults to `before'."
  (if (and (stringp content) (> (length content) 0))
      (emacsvox-aural-submit
       content
       :facts facts
       :module 'org
       :occasion occasion
       :compatibility-actions
       (when icon
         (list
          (emacsvox-aural-compatibility-icon icon icon-phase))))
    (when icon
      (emacsvox-org--submit-actions facts occasion icon))))

(defun emacsvox-org--line-content ()
  "Return the current Org line with speech-relevant properties intact."
  (concat
   (emacsvox-aural-source-substring
    (line-beginning-position) (line-end-position))
   (ems--display-props-get)))

(defun emacsvox-org--buffer-summary ()
  "Return a concise voice-preserving summary of the selected buffer."
  (concat
   (propertize (buffer-name) 'personality voice-lighten-medium)
   ", "
   (propertize
    (downcase
     (or
      (and (stringp mode-name) mode-name)
      (and (listp mode-name) (cl-find-if #'stringp mode-name))
      (replace-regexp-in-string
       "-mode\\'" "" (symbol-name major-mode))))
    'personality voice-animate)))

(defun emacsvox-org-refresh-aural-heading ()
  "Refresh semantic text properties on the Org heading at point."
  (when-let* ((facts (emacsvox-org-heading-facts)))
    (let ((start (line-beginning-position))
          (end (line-end-position)))
      (with-silent-modifications
        (remove-text-properties
         start end
         (list
          emacsvox-aural-facts-property nil
          emacsvox-aural-module-property nil))
        (add-text-properties
         start end
         (list
          emacsvox-aural-facts-property facts
          emacsvox-aural-module-property 'org))))
    facts))

(defun emacsvox-org--aural-heading-matcher (limit)
  "Annotate the next Org heading before LIMIT for font locking."
  (when (re-search-forward org-heading-regexp limit t)
    (save-excursion
      (goto-char (match-beginning 0))
      (emacsvox-org-refresh-aural-heading))
    t))

(defconst emacsvox-org--aural-font-lock-keywords
  '((emacsvox-org--aural-heading-matcher))
  "Font-lock matcher that attaches semantic facts to Org headings.")

(defun emacsvox-org-enable-aural-annotations ()
  "Enable semantic heading facts and Org module context in this buffer."
  (setq-local emacsvox-aural-module 'org)
  (unless emacsvox-org-aural-annotation-enabled
    (setq-local emacsvox-org-aural-annotation-enabled t)
    (add-to-list
     (make-local-variable 'font-lock-extra-managed-props)
     emacsvox-aural-facts-property)
    (add-to-list
     (make-local-variable 'font-lock-extra-managed-props)
     emacsvox-aural-module-property)
    (font-lock-add-keywords
     nil emacsvox-org--aural-font-lock-keywords 'append)
    (font-lock-flush)))

(defun emacsvox-org-speak-line-semantically
    (occasion event &optional action fallback-icon)
  "Speak the current line with Org facts for OCCASION and EVENT.

Return the heading facts when point is on a heading, or nil after using the
ordinary compatibility path for any other Org line.  ACTION describes the
operation, and FALLBACK-ICON follows a non-heading line."
  (let ((facts (emacsvox-org-heading-facts event action)))
    (when facts
      (emacsvox-org-refresh-aural-heading))
    (emacsvox-org--submit-text
     (emacsvox-org--line-content)
     (or
      facts
      (emacsvox-org--feedback-facts
       'org-content event action))
     occasion
     (unless facts fallback-icon)
     'after)
    facts))

(add-hook 'org-mode-hook #'emacsvox-org-enable-aural-annotations)

;;;  voice locking:

(defconst emacsvox-org--face-voice-map
  '((org-agenda-calendar-daterange voice-animate)
    (org-agenda-calendar-event voice-animate-extra)
    (org-agenda-calendar-sexp voice-animate)
    (org-agenda-clocking voice-animate-extra)
    (org-agenda-column-dateline voice-monotone-extra)
    (org-agenda-current-time voice-bolden)
    (org-agenda-date voice-bolden)
    (org-agenda-date-today voice-bolden-and-animate)
    (org-agenda-date-weekend voice-brighten)
    (org-agenda-date-weekend-today voice-brighten-extra)
    (org-agenda-diary voice-animate)
    (org-agenda-dimmed-todo-face voice-smoothen-medium)
    (org-agenda-done voice-monotone-extra)
    (org-agenda-filter-category voice-lighten-extra)
    (org-agenda-filter-effort voice-lighten-extra)
    (org-agenda-filter-regexp voice-lighten)
    (org-agenda-filter-tags voice-lighten)
    (org-agenda-restriction-lock voice-monotone-extra)
    (org-agenda-structure voice-bolden)
    (org-agenda-structure-filter voice-bolden-and-animate)
    (org-agenda-structure-secondary voice-brighten)
    (org-archived voice-monotone-extra)
    (org-beamer-tag voice-bolden)
    (org-block voice-monotone-extra)
    (org-block-begin-line voice-smoothen-medium)
    (org-block-end-line voice-smoothen-medium)
    (org-checkbox voice-animate)
    (org-checkbox-statistics-done voice-monotone-extra)
    (org-checkbox-statistics-todo voice-bolden-and-animate)
    (org-cite voice-bolden)
    (org-cite-key voice-bolden)
    (org-clock-overlay voice-animate)
    (org-code voice-monotone-extra)
    (org-column voice-lighten)
    (org-column-title voice-lighten-extra)
    (org-date voice-animate)
    (org-date-selected voice-bolden)
    (org-default voice-smoothen)
    (org-dispatcher-highlight voice-bolden-extra)
    (org-document-info voice-monotone)
    (org-document-info-keyword voice-bolden-extra)
    (org-document-title voice-bolden)
    (org-done voice-monotone-extra)
    (org-drawer voice-smoothen-medium)
    (org-ellipsis voice-smoothen-extra)
    (org-footnote voice-smoothen)
    (org-formula voice-animate-extra)
    (org-habit-alert-face voice-monotone-extra)
    (org-habit-alert-future-face voice-monotone-extra)
    (org-habit-clear-face voice-monotone-extra)
    (org-habit-clear-future-face voice-monotone-extra)
    (org-habit-overdue-face voice-monotone-extra)
    (org-habit-overdue-future-face voice-monotone-extra)
    (org-habit-ready-face voice-monotone-extra)
    (org-habit-ready-future-face voice-monotone-extra)
    (org-headline-done voice-monotone-medium)
    (org-headline-todo voice-bolden-and-animate)
    (org-hide voice-smoothen-extra)
    (org-imminent-deadline voice-bolden-and-animate)
    (org-indent voice-smoothen)
    (org-inline-src-block voice-monotone-extra)
    (org-inlinetask voice-smoothen-extra)
    (org-latex-and-related voice-smoothen)
    (org-level-1 voice-bolden)
    (org-level-2 voice-brighten)
    (org-level-3 voice-animate)
    (org-level-4 voice-lighten)
    (org-level-5 voice-smoothen)
    (org-level-6 voice-monotone)
    (org-level-7 voice-lighten-medium)
    (org-level-8 voice-lighten-extra)
    (org-link voice-bolden)
    (org-list-dt voice-bolden)
    (org-macro voice-smoothen)
    (org-meta-line voice-smoothen-medium)
    (org-mode-line-clock voice-animate)
    (org-mode-line-clock-overrun voice-bolden-and-animate)
    (org-priority voice-bolden-extra)
    (org-property-value voice-animate)
    (org-quote voice-smoothen)
    (org-scheduled voice-animate)
    (org-scheduled-previously voice-lighten-medium)
    (org-scheduled-today voice-bolden-extra)
    (org-sexp-date voice-monotone-extra)
    (org-special-keyword voice-lighten-extra)
    (org-table voice-bolden)
    (org-table-header voice-bolden)
    (org-table-row voice-bolden)
    (org-tag voice-smoothen)
    (org-tag-group voice-smoothen)
    (org-target voice-bolden)
    (org-time-grid voice-bolden)
    (org-todo voice-bolden-and-animate)
    (org-upcoming-deadline voice-animate)
    (org-upcoming-distant-deadline voice-lighten)
    (org-verbatim voice-monotone-extra)
    (org-verse voice-smoothen)
    (org-warning voice-bolden-and-animate))
  "Voice personalities for current Org interface faces.")

(voice-setup-add-map emacsvox-org--face-voice-map)

;;;  Structure Navigation:

(defun emacsvox-org-speak-item  ()
  "Speak the current Org item through one semantic presentation."
  (interactive)
  (unless (eq major-mode 'org-mode) (error "Not in an org buffer"))
  (unless (org-at-item-p) (error "Not at an item"))
  (save-excursion
    (let ((start (org-beginning-of-item))
          (end (org-end-of-item)))
      (emacsvox-org--submit-text
       (emacsvox-aural-source-substring start end)
       (emacsvox-org--feedback-facts
        'org-item 'focus-entered 'item-navigation)
       'navigation 'item))))

(cl-loop
 for target in
 '(org-next-item org-previous-item)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after interactive Org item movement."
       (when (ems-interactive-p ',target)
         (emacsvox-org-speak-item)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(cl-loop
 for target in
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
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Speak after an interactive Org structure movement."
       (when (ems-interactive-p ',target)
         (emacsvox-org-speak-line-semantically
          'navigation 'focus-entered
          'structure-navigation 'large-movement)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(cl-loop
 for target in
 '(
   org-backward-paragraph org-forward-paragraph
   org-agenda-forward-block org-agenda-backward-block)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after interactive Org paragraph movement."
       (when (ems-interactive-p ',target)
         (save-excursion
           (forward-paragraph 1)
           (let ((end (point)))
             (backward-paragraph 1)
             (emacsvox-org--submit-text
              (emacsvox-aural-source-substring (point) end)
              (emacsvox-org--feedback-facts
               'org-paragraph 'focus-entered 'paragraph-navigation)
              'navigation 'paragraph)))))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-org-cycle-list-bullet-after (&rest _)
  "Cue and speak after interactively cycling an Org list bullet."
  (when (ems-interactive-p 'org-cycle-list-bullet)
    (emacsvox-org--submit-text
     (emacsvox-org--line-content)
     (emacsvox-org--feedback-facts
      'org-item 'state-changed 'list-style-changed)
     'state-change 'item)))

(advice-add
 'org-cycle-list-bullet :after
 #'emacsvox--advice-org-cycle-list-bullet-after
 '((name . emacsvox)))

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

(defvar emacsvox-org--table-presentation-occasion 'inspection
  "Occasion captured by an Org table presentation command.")

(defun emacsvox-org--table-facts
    (presentation &optional action event)
  "Return semantic facts for Org table PRESENTATION at point.

ACTION defaults to navigation or inspection according to the captured
occasion.  EVENT defaults to `focus-entered'."
  (append
   (emacsvox-org--feedback-facts
    'org-table (or event 'focus-entered)
    (or
     action
     (if (eq emacsvox-org--table-presentation-occasion 'navigation)
         'table-navigation
       'table-inspection)))
   (when (org-at-table-p 'any)
     (list
      :org-table-row (org-table-current-line)
      :org-table-column (org-table-current-column)
      :org-table-presentation presentation))))

(defun emacsvox-org--submit-table-text (text presentation)
  "Display and submit Org table TEXT described by PRESENTATION."
  (emacsvox-org--submit-message-feedback
   (emacsvox-org--table-facts presentation)
   emacsvox-org--table-presentation-occasion nil text))

(defun emacsvox-org--present-table-after-movement ()
  "Present the configured Org table information after navigation."
  (let ((emacsvox-org--table-presentation-occasion 'navigation))
    (funcall emacsvox-org-table-after-movement-function)))

(defun emacsvox-org--table-cell-content ()
  "Return the trimmed current table cell, or nil outside a table."
  (when (org-at-table-p 'any)
    (let ((field (string-trim (org-table-get-field))))
      (if (string-empty-p field) "space" field))))

(defun emacsvox-org--present-table-change (action icon)
  "Present the current table cell after ACTION, with compatibility ICON."
  (emacsvox-org--submit-text
   (or (emacsvox-org--table-cell-content)
       (and (not (eobp)) (emacsvox-org--line-content))
       "Table changed")
   (emacsvox-org--table-facts 'cell action 'state-changed)
   'state-change icon))

(defun emacsvox-org--present-table-message
    (action prior-message fallback)
  "Present an Org table inspection ACTION.

Prefer a message different from PRIOR-MESSAGE and otherwise use FALLBACK."
  (let ((current (current-message)))
    (emacsvox-org--submit-text
     (if
         (and
          (stringp current)
          (not (string-empty-p current))
          (not (equal current prior-message)))
         current
       fallback)
     (emacsvox-org--table-facts 'cell action 'focus-entered)
     'inspection)))

;; orgalist-mode defines structured navigators that in turn call org-cycle.
;; Removing itneractive check in advice for org-cycle
;; to speech enable all such nav commands.
;; Note that org itself produces the folded state via org-unlogged-message
;; Which gets spoken by Emacsvox
(cl-loop
 for target in
 '(org-cycle org-shifttab)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Speak after Org visibility cycling or report the current table cell."
       (cond
        ((org-at-table-p 'any)
         (emacsvox-org--present-table-after-movement))
        (t
         (let ((tts-stop-immediately nil))
           (when (ems-interactive-p ',target)
             (emacsvox-org-refresh-aural-heading)
             (emacsvox-org-speak-line-semantically
              'state-change 'state-changed))))))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-org-overview-after (&rest _)
  "Announce an interactively requested Org overview."
  (when (ems-interactive-p 'org-overview)
    (emacsvox-org--submit-message-feedback
     (emacsvox-org--feedback-facts
      'org-content 'state-changed 'overview-shown)
     'state-change nil "Showing top-level overview.")))

(advice-add
 'org-overview :after #'emacsvox--advice-org-overview-after
 '((name . emacsvox)))

(defun emacsvox--advice-org-content-after (&rest _)
  "Announce interactively requested Org contents."
  (when (ems-interactive-p 'org-content)
    (emacsvox-org--submit-message-feedback
     (emacsvox-org--feedback-facts
      'org-content 'state-changed 'contents-shown)
     'state-change nil "Showing table of contents.")))

(advice-add
 'org-content :after #'emacsvox--advice-org-content-after
 '((name . emacsvox)))

(defun emacsvox--advice-org-tree-to-indirect-buffer-after (&rest _)
  "Announce a subtree cloned interactively into an indirect buffer."
  (when (ems-interactive-p 'org-tree-to-indirect-buffer)
    (emacsvox-org--submit-message-feedback
     (emacsvox-org--feedback-facts
      'org-content 'focus-entered 'indirect-buffer-opened)
     'navigation nil
     (format
      "Cloned %s"
      (with-current-buffer org-last-indirect-buffer
        (save-excursion
          (goto-char (point-min))
          (buffer-substring
           (line-beginning-position) (line-end-position))))))))

(advice-add
 'org-tree-to-indirect-buffer :after
 #'emacsvox--advice-org-tree-to-indirect-buffer-after
 '((name . emacsvox)))

;;;  Header insertion and relocation

(cl-loop
 for target in
 '(
   org-delete-indentation
   org-insert-heading org-insert-todo-heading
   org-insert-structure-template
   org-promote-subtree org-demote-subtree
   org-do-promote org-do-demote
   org-move-subtree-up org-move-subtree-down
   org-convert-to-odd-levels org-convert-to-oddeven-levels
   )
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Speak after an interactive Org heading edit."
       (when (ems-interactive-p ',target)
         (emacsvox-org-speak-line-semantically
          'edit 'object-changed 'heading-edited 'open-object)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-org-delete-char-around (original n)
  "Cue deletion and call ORIGINAL once with N."
  (when (ems-interactive-p 'org-delete-char)
    (emacsvox-speak-edit-operation 'deletion)
    (emacsvox-speak-char t))
  (funcall original n))

(advice-add
 'org-delete-char :around #'emacsvox--advice-org-delete-char-around
 '((name . emacsvox)))

;;;  cut and paste:

(cl-loop
 for target in
 '(
   org-cut-subtree org-copy-subtree
   org-paste-subtree org-archive-subtree
   org-narrow-to-subtree)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Speak after an interactive Org subtree operation."
       (when (ems-interactive-p ',target)
         (emacsvox-org--submit-text
          (emacsvox-org--line-content)
          (emacsvox-org--feedback-facts
           'org-content 'object-changed 'subtree-changed)
          'edit 'yank-object 'after)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

;;;  completion:

(defun emacsvox--advice-org-complete-around (original &rest arguments)
  "Call legacy Org completion once, then speak its result."
  (let ((prior (save-excursion (skip-syntax-backward "^ >") (point)))
        (tts-stop-immediately t))
    (let ((result (apply original arguments)))
      (if (> (point) prior)
          (tts-with-punctuations
           'all
           (if (> (length (emacsvox-get-minibuffer-contents)) 0)
               (tts-speak (emacsvox-get-minibuffer-contents))
             (emacsvox-speak-line)))
        (emacsvox-speak-completions-if-available))
      result)))

;; Current Org uses `completion-at-point', which Emacsvox advises centrally.
;; Avoid creating an advised placeholder when the legacy command is absent.
(when (fboundp 'org-complete)
  (advice-add
   'org-complete :around #'emacsvox--advice-org-complete-around
   '((name . emacsvox))))

;;;  toggles:

(cl-loop
 for target in
 '(
   org-toggle-archive-tag org-toggle-comment)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after an interactive Org toggle."
       (when (ems-interactive-p ',target)
         (emacsvox-org--submit-text
          (emacsvox-org--line-content)
          (emacsvox-org--feedback-facts
           'org-content 'state-changed 'option-toggled)
          'state-change 'button)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

;;;  ToDo:

;;;  timestamps and calendar:

(cl-loop
 for target in
 '(org-timestamp-down-day org-timestamp-up-day)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after an interactive Org day adjustment."
       (when (ems-interactive-p ',target)
         (emacsvox-org--submit-text
          (emacsvox-org--line-content)
          (emacsvox-org--feedback-facts
           'org-content 'object-changed 'timestamp-changed)
          'edit 'select-object)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(cl-loop
 for target in
 '(org-timestamp-down org-timestamp-up)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after an interactive Org timestamp adjustment."
       (when (ems-interactive-p ',target)
         (emacsvox-aural-submit
          org-last-changed-timestamp
          :facts
          (emacsvox-org--feedback-facts
           'org-content 'object-changed 'timestamp-changed)
          :module 'org
          :occasion 'edit
          :compatibility-actions
          (list
           (emacsvox-aural-compatibility-icon 'select-object)))))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-org-eval-in-calendar-after (&rest _)
  "Submit the result of evaluating an Org calendar expression."
  (emacsvox-org--submit-text
   (format "%s" org-ans2)
   (emacsvox-org--feedback-facts
    'org-content 'focus-entered 'calendar-evaluated)
   'inspection))

(advice-add
 'org-eval-in-calendar :after
 #'emacsvox--advice-org-eval-in-calendar-after
 '((name . emacsvox)))

;;;  Agenda:

;; AGENDA NAVIGATION

(cl-loop
 for target in
 '(
   org-agenda-next-date-line org-agenda-previous-date-line
   org-agenda-next-line org-agenda-previous-line
   org-agenda-next-item org-agenda-previous-item
   org-agenda-goto-today
   )
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after interactive Org agenda navigation."
       (when (ems-interactive-p ',target)
         (emacsvox-org--submit-text
          (emacsvox-org--line-content)
          (emacsvox-org--feedback-facts
           'org-agenda-entry 'focus-entered 'agenda-navigation)
          'navigation 'select-object)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(cl-loop
 for target in
 '(org-agenda-quit org-agenda-exit)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after interactively closing an Org agenda."
       (when (ems-interactive-p ',target)
         (emacsvox-org--submit-text
          (emacsvox-org--buffer-summary)
          (emacsvox-org--feedback-facts
           'org-agenda-entry 'state-changed 'agenda-closed)
          'state-change 'close-object)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(cl-loop
 for target in
 '(org-agenda-goto org-agenda-show org-agenda-switch-to
                   org-agenda-open-link)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after interactively opening an Org agenda item."
       (when (ems-interactive-p ',target)
         (emacsvox-org--submit-text
          (emacsvox-org--line-content)
          (emacsvox-org--feedback-facts
           'org-agenda-entry 'focus-entered 'agenda-opened)
          'navigation 'open-object)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-org-agenda-after (&rest _)
  "Cue and speak after interactively opening the Org agenda."
  (when (ems-interactive-p 'org-agenda)
    (emacsvox-org--submit-text
     (emacsvox-org--line-content)
     (emacsvox-org--feedback-facts
      'org-agenda-entry 'focus-entered 'agenda-opened)
     'navigation 'open-object)))

(advice-add
 'org-agenda :after #'emacsvox--advice-org-agenda-after
 '((name . emacsvox)))

(defun emacsvox-org--present-agenda-result
    (action icon prior-message prefer-message &optional fallback)
  "Present one agenda ACTION with ICON after an interactive command.

PRIOR-MESSAGE is the message visible before the command.  When PREFER-MESSAGE
is non-nil, a new message produced by Org is preferred over the current line.
FALLBACK is used when neither provides useful content."
  (let* ((current (current-message))
         (new-message
          (and
           prefer-message
           (stringp current)
           (not (string-empty-p current))
           (not (equal current prior-message))
           current))
         (line
          (and
           (not prefer-message)
           (not (eobp))
           (emacsvox-org--line-content)))
         (content (or new-message line fallback "Agenda changed")))
    (emacsvox-org--submit-text
     content
     (emacsvox-org--feedback-facts
      'org-agenda-entry 'state-changed action)
     'state-change icon)))

(cl-loop
 for (target action icon) in
 '((org-agenda-todo todo-changed button)
   (org-agenda-todo-nextset todo-changed button)
   (org-agenda-todo-previousset todo-changed button)
   (org-agenda-priority priority-changed button)
   (org-agenda-priority-up priority-changed button)
   (org-agenda-priority-down priority-changed button)
   (org-agenda-do-date-earlier planning-changed button)
   (org-agenda-do-date-later planning-changed button)
   (org-agenda-schedule planning-changed button)
   (org-agenda-deadline planning-changed button)
   (org-agenda-set-tags tags-changed button)
   (org-agenda-set-effort effort-changed button)
   (org-agenda-set-property property-changed button)
   (org-agenda-toggle-archive-tag option-toggled button)
   (org-agenda-drag-line-forward agenda-entry-reordered button)
   (org-agenda-drag-line-backward agenda-entry-reordered button)
   (org-agenda-clock-in agenda-clock-changed button)
   (org-agenda-clock-out agenda-clock-changed button)
   (org-agenda-clock-cancel agenda-clock-changed button)
   (org-agenda-bulk-mark agenda-mark-changed mark-object)
   (org-agenda-bulk-mark-all agenda-mark-changed mark-object)
   (org-agenda-bulk-mark-regexp agenda-mark-changed mark-object)
   (org-agenda-bulk-unmark agenda-mark-changed mark-object)
   (org-agenda-bulk-unmark-all agenda-mark-changed mark-object)
   (org-agenda-bulk-toggle agenda-mark-changed mark-object)
   (org-agenda-bulk-toggle-all agenda-mark-changed mark-object)
   (org-agenda-bulk-action agenda-bulk-action button))
 for function = (intern (format "emacsvox--advice-%s-around" target))
 do
 (eval
  `(progn
     (defun ,function (original &rest arguments)
       "Call an interactive agenda command quietly and present its entry."
       (if (not (eq ems--interactive-fn-name ',target))
           (apply original arguments)
         (let ((prior-message (current-message))
               (emacsvox-speak-messages nil))
           (prog1
               (apply original arguments)
             (emacsvox-org--present-agenda-result
              ',action ',icon prior-message nil)))))
     (advice-add
      ',target :around #',function '((name . emacsvox))))))

(cl-loop
 for (target action icon fallback) in
 '((org-agenda-archive agenda-entry-archived save-object
                       "Agenda entry archived")
   (org-agenda-archive-default-with-confirmation
    agenda-entry-archived save-object "Agenda entry archived")
   (org-agenda-archive-default agenda-entry-archived save-object
                               "Agenda entry archived")
   (org-agenda-archive-to-archive-sibling
    agenda-entry-archived save-object "Agenda entry archived")
   (org-agenda-kill agenda-entry-deleted delete-object
                    "Agenda entry deleted")
   (org-agenda-refile agenda-entry-refiled yank-object
                      "Agenda entry refiled")
   (org-agenda-filter agenda-filter-changed button
                      "Agenda filter changed")
   (org-agenda-filter-by-category agenda-filter-changed button
                                  "Agenda category filter changed")
   (org-agenda-filter-by-effort agenda-filter-changed button
                                "Agenda effort filter changed")
   (org-agenda-filter-by-regexp agenda-filter-changed button
                                "Agenda regular expression filter changed")
   (org-agenda-filter-by-tag agenda-filter-changed button
                             "Agenda tag filter changed")
   (org-agenda-filter-by-top-headline agenda-filter-changed button
                                      "Agenda headline filter changed")
   (org-agenda-filter-remove-all agenda-filter-changed button
                                 "Agenda filters removed")
   (org-agenda-limit-interactively agenda-filter-changed button
                                   "Agenda limit changed")
   (org-agenda-manipulate-query-add agenda-filter-changed button
                                    "Agenda query changed")
   (org-agenda-manipulate-query-add-re agenda-filter-changed button
                                       "Agenda query changed")
   (org-agenda-manipulate-query-subtract agenda-filter-changed button
                                         "Agenda query changed")
   (org-agenda-manipulate-query-subtract-re agenda-filter-changed button
                                            "Agenda query changed")
   (org-agenda-earlier agenda-view-changed large-movement
                       "Earlier agenda view")
   (org-agenda-later agenda-view-changed large-movement
                     "Later agenda view")
   (org-agenda-goto-date agenda-view-changed large-movement
                         "Agenda date changed")
   (org-agenda-date-prompt agenda-view-changed large-movement
                           "Agenda date changed")
   (org-agenda-day-view agenda-view-changed large-movement
                        "Agenda day view")
   (org-agenda-week-view agenda-view-changed large-movement
                         "Agenda week view")
   (org-agenda-year-view agenda-view-changed large-movement
                         "Agenda year view")
   (org-agenda-view-mode-dispatch agenda-view-changed large-movement
                                  "Agenda view changed")
   (org-agenda-toggle-deadlines agenda-display-changed button
                                "Agenda deadline display changed")
   (org-agenda-toggle-diary agenda-display-changed button
                            "Agenda diary display changed")
   (org-agenda-toggle-time-grid agenda-display-changed button
                                "Agenda time grid display changed")
   (org-agenda-dim-blocked-tasks agenda-display-changed button
                                 "Agenda blocked task display changed")
   (org-agenda-entry-text-mode agenda-display-changed button
                               "Agenda entry text display changed")
   (org-agenda-follow-mode agenda-display-changed button
                           "Agenda follow mode changed")
   (org-agenda-log-mode agenda-display-changed button
                        "Agenda log mode changed")
   (org-agenda-clockreport-mode agenda-display-changed button
                                "Agenda clock report changed")
   (org-agenda-append-agenda agenda-view-changed large-movement
                             "Agenda view appended")
   (org-agenda-redo agenda-refreshed select-object
                    "Agenda refreshed")
   (org-agenda-redo-all agenda-refreshed select-object
                        "All agenda views refreshed"))
 for function = (intern (format "emacsvox--advice-%s-around" target))
 do
 (eval
  `(progn
     (defun ,function (original &rest arguments)
       "Call an interactive agenda command quietly and present its result."
       (if (not (eq ems--interactive-fn-name ',target))
           (apply original arguments)
         (let ((prior-message (current-message))
               (emacsvox-speak-messages nil))
           (prog1
               (apply original arguments)
             (emacsvox-org--present-agenda-result
              ',action ',icon prior-message t ,fallback)))))
     (advice-add
      ',target :around #',function '((name . emacsvox))))))

;;;  tables:

;;;  table minor mode:

(defun emacsvox--advice-orgtbl-mode-after (&rest _)
  "Report the new state after interactively toggling Org table mode."
  (when (ems-interactive-p 'orgtbl-mode)
    (let* ((state (if orgtbl-mode 'on 'off))
           (text (format "Turned %s org table mode." state)))
      (emacsvox-org--submit-message-feedback
       (emacsvox-org--feedback-facts
        'org-table 'state-changed 'table-mode-toggled)
       'state-change state text))))

(advice-add
 'orgtbl-mode :after #'emacsvox--advice-orgtbl-mode-after
 '((name . emacsvox)))

;;;  deleting chars:

(defun emacsvox--advice-org-return-after (&rest _)
  "Speak the destination after interactive Org return."
  (when (ems-interactive-p 'org-return)
    (cond
     ((org-at-table-p 'any)
      ;; `org-return' delegates table movement to `org-table-next-row',
      ;; whose adapter owns the resulting cell announcement.
      nil)
     (t
      (emacsvox-org--submit-text
       (emacsvox-org--line-content)
       (emacsvox-org--feedback-facts
        'org-content 'object-changed 'line-inserted)
       'edit 'select-object 'after)))))

(advice-add
 'org-return :after #'emacsvox--advice-org-return-after
 '((name . emacsvox)))

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
    (when tts-caps (tts-toggle-caps))
    (emacsvox-speak-load-directory-settings)))

(add-hook 'org-mode-hook #'emacsvox-org-mode-setup)

;; advice end-of-line here to call org specific action

(defun emacsvox--advice-end-of-line-after (&rest _)
  "Call org specific actions in org mode."
  (when
      (and (ems-interactive-p 'end-of-line) (eq major-mode 'org-mode)
           (fboundp 'org-end-of-line))
    (org-end-of-line)))

(advice-add
 'end-of-line :after #'emacsvox--advice-end-of-line-after
 '((name . emacsvox)))

(defun emacsvox--advice-org-toggle-checkbox-after (&rest _)
  "Cue and speak after interactively toggling an Org checkbox."
  (when (ems-interactive-p 'org-toggle-checkbox)
    (emacsvox-org--submit-text
     (emacsvox-org--line-content)
     (emacsvox-org--feedback-facts
      'org-item 'state-changed 'checkbox-toggled)
     'state-change 'button)))

(advice-add
 'org-toggle-checkbox :after
 #'emacsvox--advice-org-toggle-checkbox-after
 '((name . emacsvox)))

;;;  fix misc commands:

(cl-loop
 for target in
 '(
   org-occur
   org-beginning-of-item org-beginning-of-item-list
   org-end-of-item org-end-of-item-list)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Speak after interactive Org item navigation."
       (when (ems-interactive-p ',target)
         (emacsvox-org--submit-text
          (emacsvox-org--line-content)
          (emacsvox-org--feedback-facts
           'org-item 'focus-entered 'item-boundary)
          'navigation 'select-object 'after)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-org-beginning-of-line-after (&rest _)
  "Speak after interactive movement to the beginning of an Org line."
  (when (ems-interactive-p 'org-beginning-of-line)
    (emacsvox-org--submit-text
     (emacsvox-org--line-content)
     (emacsvox-org--feedback-facts
      'org-content 'focus-entered 'line-start)
     'navigation 'left 'after)))

(advice-add
 'org-beginning-of-line :after
 #'emacsvox--advice-org-beginning-of-line-after
 '((name . emacsvox)))

(defun emacsvox--advice-org-end-of-line-after (&rest _)
  "Speak after interactive movement to the end of an Org line."
  (when (ems-interactive-p 'org-end-of-line)
    (emacsvox-org--submit-text
     (emacsvox-org--line-content)
     (emacsvox-org--feedback-facts
      'org-content 'focus-entered 'line-end)
     'navigation 'right 'after)))

(advice-add
 'org-end-of-line :after #'emacsvox--advice-org-end-of-line-after
 '((name . emacsvox)))

;;;  global input wizard

(defun emacsvox-org-popup-input ()
  "Pops up an org input area."
  (interactive)
  (emacsvox-org-popup-input-buffer 'org-mode))

;;;  org capture

(defun emacsvox--advice-org-capture-goto-last-stored-after (&rest _)
  "Cue and speak after interactively visiting the last capture."
  (when (ems-interactive-p 'org-capture-goto-last-stored)
    (emacsvox-org--submit-text
     (emacsvox-org--line-content)
     (emacsvox-org--feedback-facts
      'org-capture 'focus-entered 'capture-target)
     'navigation 'large-movement)))

(advice-add
 'org-capture-goto-last-stored :after
 #'emacsvox--advice-org-capture-goto-last-stored-after
 '((name . emacsvox)))

(defun emacsvox--advice-org-capture-goto-target-after (&rest _)
  "Cue and speak after visiting an Org capture target."
  (emacsvox-org--submit-text
   (emacsvox-org--line-content)
   (emacsvox-org--feedback-facts
    'org-capture 'focus-entered 'capture-target)
   'navigation 'large-movement))

(advice-add
 'org-capture-goto-target :after
 #'emacsvox--advice-org-capture-goto-target-after
 '((name . emacsvox)))

(defun emacsvox--advice-org-capture-finalize-after (&rest _)
  "Cue after finalizing an Org capture."
  (emacsvox-org--submit-actions
   (emacsvox-org--feedback-facts
    'org-capture 'object-changed 'capture-saved)
   'notification 'save-object))

(advice-add
 'org-capture-finalize :after
 #'emacsvox--advice-org-capture-finalize-after
 '((name . emacsvox)))

(defun emacsvox--advice-org-capture-kill-after (&rest _)
  "Cue after cancelling an Org capture."
  (emacsvox-org--submit-actions
   (emacsvox-org--feedback-facts
    'org-capture 'state-changed 'capture-cancelled)
   'notification 'close-object))

(advice-add
 'org-capture-kill :after
 #'emacsvox--advice-org-capture-kill-after
 '((name . emacsvox)))

(defun emacsvox-org-table-speak-current-element ()
  "Speak the current Org table cell."
  (interactive)
  (let ((field (string-trim (org-table-get-field))))
    (emacsvox-org--submit-table-text
     (if (string-empty-p field) "space" field)
     'cell)))

(defun emacsvox-org-table-speak-column-header ()
  "Speak the current Org table column header."
  (interactive)
  (emacsvox-org--submit-table-text
   (propertize (string-trim (org-table-get 1 nil)) 'face 'bold)
   'column-header))

(defun emacsvox-org-table-speak-row-header ()
  "Speak the current Org table row header."
  (interactive)
  (emacsvox-org--submit-table-text
   (propertize (string-trim (org-table-get nil 1)) 'face 'italic)
   'row-header))

(defun emacsvox-org-table-speak-coordinates ()
  "Speak the current Org table coordinates."
  (interactive)
  (emacsvox-org--submit-table-text
   (format "row %d, column %d"
           (org-table-current-line)
           (org-table-current-column))
   'coordinates))

(defun emacsvox-org-table-speak-both-headers-and-element ()
  "Speak both headers and the current Org table cell."
  (interactive)
  (emacsvox-org--submit-table-text
   (concat
    (propertize (string-trim (org-table-get nil 1)) 'face 'italic)
    " "
    (propertize (string-trim (org-table-get 1 nil)) 'face 'bold) " "
    (string-trim (org-table-get-field)))
   'cell-with-both-headers))

(defun emacsvox-org-table-speak-row-header-and-element ()
  "Speak the row header and current Org table cell."
  (interactive)
  (emacsvox-org--submit-table-text
   (concat
    (propertize (string-trim (org-table-get nil 1)) 'face 'italic)
    " "
    (string-trim (org-table-get-field)))
   'cell-with-row-header))

(defun emacsvox-org-table-speak-column-header-and-element ()
  "Speak the column header and current Org table cell."
  (interactive)
  (emacsvox-org--submit-table-text
   (if (= (org-table-current-line) 1)
       (string-trim (org-table-get-field))
     (concat
      (propertize (string-trim (org-table-get 1 nil)) 'face 'bold)
      " "
      (string-trim (org-table-get-field))))
   'cell-with-column-header))

(cl-loop
 for target in
 '(org-table-next-field org-table-previous-field
                        org-table-next-row org-table-previous-row)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Speak the current Org table cell after movement."
       (emacsvox-org--present-table-after-movement))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

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

(defun emacsvox--advice-org-export--dispatch-action-before
    (_prompt _allowed-keys entries _options first-key _expertp)
  "Present the export choices selected by FIRST-KEY from ENTRIES."
  (let ((choices
         (if first-key
             (cl-caddr (assoc first-key entries))
           entries)))
    (emacsvox-org--submit-text
     (mapconcat
      (lambda (entry)
        (format "%c: %s" (cl-first entry) (cl-second entry)))
      choices "\n")
     (emacsvox-org--feedback-facts
      'org-export 'focus-entered 'export-menu-opened)
     'inspection)))

(advice-add
 'org-export--dispatch-action :before
 #'emacsvox--advice-org-export--dispatch-action-before
 '((name . emacsvox)))

;;;  Preview HTML With EWW:

(defun emacsvox-org-eww-file (file _link)
  "Preview HTML files with EWW from exporter."
  (add-hook 'emacsvox-eww-post-hook  #'emacsvox-speak-buffer)
  (funcall-interactively #'eww-open-file file))

;;;  Edit Special Advice:

(cl-loop
 for target in
 '(org-edit-src-exit org-edit-src-abort)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after interactively closing an Org edit buffer."
       (when (ems-interactive-p ',target)
         (emacsvox-org--submit-text
          (emacsvox-org--line-content)
          (emacsvox-org--feedback-facts
           'org-edit-buffer 'state-changed 'edit-closed)
          'state-change 'close-object)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(cl-loop
 for target in
 '(org-edit-src-code org-edit-special org-switchb)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after interactively opening an Org edit buffer."
       (when (ems-interactive-p ',target)
         (emacsvox-org--submit-text
          (emacsvox-org--buffer-summary)
          (emacsvox-org--feedback-facts
           'org-edit-buffer 'state-changed 'edit-opened)
          'state-change 'open-object)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

;;;  Fillers:

(defun emacsvox--advice-org-fill-paragraph-after (&rest _)
  "Report an interactively filled Org paragraph."
  (when (ems-interactive-p 'org-fill-paragraph)
    (emacsvox-org--submit-message-feedback
     (emacsvox-org--feedback-facts
      'org-paragraph 'object-changed 'paragraph-filled)
     'edit 'fill-object "Filled current paragraph")))

(advice-add
 'org-fill-paragraph :after
 #'emacsvox--advice-org-fill-paragraph-after
 '((name . emacsvox)))

(defun emacsvox--advice-org-todo-after (&rest _)
  "Report the state after interactively changing an Org TODO item."
  (when (ems-interactive-p 'org-todo)
    (let ((state (org-get-todo-state)))
      (emacsvox-org--submit-message-feedback
       (emacsvox-org--feedback-facts
        'org-content 'state-changed 'todo-changed)
       'state-change 'button
       (or state "State unset")))))

(advice-add
 'org-todo :after #'emacsvox--advice-org-todo-after
 '((name . emacsvox)))

;;;  Metadata and context-sensitive state:

(defun emacsvox-org--present-document-state (action icon)
  "Present the current Org line after ACTION, with compatibility ICON."
  (if (org-at-table-p 'any)
      (emacsvox-org--present-table-change action icon)
    (emacsvox-org-speak-line-semantically
     'state-change 'state-changed action icon)))

(cl-loop
 for (target action icon) in
 '((org-priority priority-changed button)
   (org-set-tags-command tags-changed button)
   (org-schedule planning-changed button)
   (org-deadline planning-changed button)
   (org-set-effort effort-changed button)
   (org-inc-effort effort-changed button)
   (org-set-property property-changed button)
   (org-set-property-and-value property-changed button)
   (org-toggle-ordered-property property-changed button)
   (org-update-statistics-cookies statistics-updated button)
   (org-toggle-radio-button radio-button-toggled button)
   (org-toggle-fixed-width display-changed button)
   (org-toggle-pretty-entities display-changed button)
   (org-toggle-timestamp-overlays display-changed button)
   (org-ctrl-c-ctrl-c context-action button))
 for function = (intern (format "emacsvox--advice-%s-around" target))
 do
 (eval
  `(progn
     (defun ,function (original &rest arguments)
       "Call an interactive Org state command quietly and present its result."
       (if (not (eq ems--interactive-fn-name ',target))
           (apply original arguments)
         (let ((emacsvox-speak-messages nil))
           (prog1
               (apply original arguments)
             (emacsvox-org--present-document-state ',action ',icon)))))
     (advice-add
      ',target :around #',function '((name . emacsvox))))))

;;;  Table editing and inspection:

(cl-loop
 for (target action icon) in
 '((org-table-delete-column table-changed delete-object)
   (org-table-move-column-left table-changed button)
   (org-table-move-column-right table-changed button)
   (org-table-insert-column table-changed open-object)
   (org-table-kill-row table-changed delete-object)
   (org-table-insert-row table-changed open-object)
   (org-table-move-row-up table-changed button)
   (org-table-move-row-down table-changed button)
   (org-table-paste-rectangle table-changed yank-object)
   (org-table-wrap-region table-changed fill-object)
   (org-table-insert-hline table-changed open-object)
   (org-table-copy-down table-changed yank-object)
   (org-table-blank-field table-changed delete-object)
   (org-table-eval-formula table-formula-evaluated button)
   (org-table-recalculate table-recalculated button)
   (org-table-sort-lines table-sorted button)
   (org-table-rotate-recalc-marks table-changed button)
   (org-table-create-or-convert-from-region table-created open-object))
 for function = (intern (format "emacsvox--advice-%s-around" target))
 do
 (eval
  `(progn
     (defun ,function (original &rest arguments)
       "Call an interactive Org table command quietly and present its cell."
       (if (not (eq ems--interactive-fn-name ',target))
           (apply original arguments)
         (let ((emacsvox-speak-messages nil))
           (prog1
               (apply original arguments)
             (emacsvox-org--present-table-change ',action ',icon)))))
     (advice-add
      ',target :around #',function '((name . emacsvox))))))

(cl-loop
 for (target fallback) in
 '((org-table-sum "Table sum calculated")
   (org-table-field-info "Table field information")
   (org-table-toggle-coordinate-overlays
    "Table coordinate display changed")
   (org-table-toggle-formula-debugger
    "Table formula debugger changed"))
 for function = (intern (format "emacsvox--advice-%s-around" target))
 do
 (eval
  `(progn
     (defun ,function (original &rest arguments)
       "Call an interactive Org table inspector quietly and present its result."
       (if (not (eq ems--interactive-fn-name ',target))
           (apply original arguments)
         (let ((prior-message (current-message))
               (emacsvox-speak-messages nil))
           (prog1
               (apply original arguments)
             (emacsvox-org--present-table-message
              'table-inspected prior-message ,fallback)))))
     (advice-add
      ',target :around #',function '((name . emacsvox))))))

;;; TVR: Conveniences

(defun tvr-org-itemize ()
  "Start a numbered  list."
  (interactive)
  (forward-line 0)
  (insert "  -  ")
  (emacsvox-org--submit-text
   (emacsvox-org--line-content)
   (emacsvox-org--feedback-facts
    'org-item 'object-changed 'list-item-created)
   'edit 'item 'after))

(defun tvr-org-enumerate ()
  "Start a numbered  list."
  (interactive)
  (forward-line 0)
  (insert "  1.  ")
  (emacsvox-org--submit-text
   (emacsvox-org--line-content)
   (emacsvox-org--feedback-facts
    'org-item 'object-changed 'list-item-created)
   'edit 'item 'after))

(defun tvr-org-alphabetize ()
  "Start an alphabetized   list."
  (interactive)
  (forward-line 0)
  (insert "  A.  ")
  (emacsvox-org--submit-text
   (emacsvox-org--line-content)
   (emacsvox-org--feedback-facts
    'org-item 'object-changed 'list-item-created)
   'edit 'item 'after))

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

(defun emacsvox--advice-org-md-export-as-markdown-after (&rest _)
  "Cue and speak after an interactive Org Markdown export."
  (when (ems-interactive-p 'org-md-export-as-markdown)
    (emacsvox-org--submit-text
     (emacsvox-org--buffer-summary)
     (emacsvox-org--feedback-facts
      'org-export 'object-changed 'export-completed)
     'notification 'task-done)))

(advice-add
 'org-md-export-as-markdown :after
 #'emacsvox--advice-org-md-export-as-markdown-after
 '((name . emacsvox)))

;;; Amark:

(org-link-set-parameters
 "amark"
 :follow #'org-amark-follow-link
 :store #'org-amark-store-link
 :display 'org-link)

(defun org-amark-store-link ()
  "Store a link to a AMark.
Is enabled in the AMark Browser and M-Player Interaction buffers."
  (when-let*
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
  (when-let*
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
  (when-let*
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
(declare-function emacsvox-eww-open-mark "emacsvox-eww" (name &optional delete))
(declare-function empv-play "empv" (source))

(defun emacsvox-org-e-media-follow-url (url)
  "Handle e-media URL, either mtv or mplayer based on URL."
  (cond
   ((org--ems-yt-p url) (empv-play url))
   (t (emacsvox-eww-play-media-at-point url))))
;;; org publish

(defun emacsvox-org--publish-finished (_source output)
  "Report that Org produced published file OUTPUT."
  (emacsvox-org--submit-message-feedback
   (emacsvox-org--feedback-facts
    'org-export 'object-changed 'publish-completed)
   'notification 'save-object
   (format "Published %s" (abbreviate-file-name output))))

(add-hook
 'org-publish-after-publishing-hook
 #'emacsvox-org--publish-finished)

(defun emacsvox--advice-org-export-to-file-after (_backend file &rest _)
  "Cue and report the Org export output FILE."
  (emacsvox-org--submit-message-feedback
   (emacsvox-org--feedback-facts
    'org-export 'object-changed 'export-completed)
   'notification 'save-object
   (format "Wrote %s" (abbreviate-file-name file))))

(advice-add
 'org-export-to-file :after #'emacsvox--advice-org-export-to-file-after
 '((name . emacsvox)))

(provide 'emacsvox-org)
;;;  end of file
