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

(defun emacsvox-org-heading-facts (&optional event)
  "Return semantic facts for the Org heading at point.

Optional EVENT records the registered event that caused its presentation."
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
      facts)))

(defun emacsvox-org--feedback-facts (role event action)
  "Return Org facts for ROLE, EVENT, and user-visible ACTION."
  (append
   (list :role role)
   (when event (list :events (list event)))
   (when action (list :org-action action))))

(defun emacsvox-org--call-with-aural-presentation
    (facts occasion function &rest arguments)
  "Call FUNCTION with ARGUMENTS in one frozen Org presentation.

FACTS and OCCASION apply unless an enclosing submission already supplies more
specific values."
  (emacsvox-aural-call-with-submission
   function
   :facts (or facts '(:role org-content))
   :module 'org
   :occasion (or occasion 'navigation)
   :arguments arguments))

(defun emacsvox-org--present-feedback
    (facts occasion icon function &rest arguments)
  "Under FACTS and OCCASION, present ICON then call FUNCTION with ARGUMENTS."
  (emacsvox-org--call-with-aural-presentation
   facts occasion
   (lambda ()
     (when icon (emacsvox-icon icon))
     (apply function arguments))))

(defun emacsvox-org--present-feedback-after
    (facts occasion icon function &rest arguments)
  "Under FACTS and OCCASION, call FUNCTION then present ICON.
ARGUMENTS are passed to FUNCTION."
  (emacsvox-org--call-with-aural-presentation
   facts occasion
   (lambda ()
     (apply function arguments)
     (when icon (emacsvox-icon icon)))))

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
    (occasion event &optional fallback-action fallback-icon)
  "Speak the current line with Org facts for OCCASION and EVENT.

Return the heading facts when point is on a heading, or nil after using the
ordinary compatibility path for any other Org line.  FALLBACK-ACTION describes
that non-heading operation, and FALLBACK-ICON follows its spoken line."
  (let ((facts (emacsvox-org-heading-facts event)))
    (if (not facts)
        (progn
          (emacsvox-org--present-feedback-after
           (emacsvox-org--feedback-facts
            'org-content event fallback-action)
           occasion fallback-icon #'emacsvox-speak-line)
          nil)
      (emacsvox-org-refresh-aural-heading)
      (let* ((context
              (emacsvox-aural-capture-context 'org occasion))
             (emacsvox-aural-submission-facts facts)
             (emacsvox-aural-submission-context context)
             (emacsvox-aural-submission-module 'org)
             (emacsvox-aural-submission-occasion occasion))
        (emacsvox-speak-line))
      facts)))

(add-hook 'org-mode-hook #'emacsvox-org-enable-aural-annotations)

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
 for target in
 '(org-next-item org-previous-item)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after interactive Org item movement."
       (when (ems-interactive-p ',target)
         (emacsvox-org--present-feedback
          (emacsvox-org--feedback-facts
           'org-item 'focus-entered 'item-navigation)
          'navigation 'item #'emacsvox-org-speak-item)))
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
         (emacsvox-org--present-feedback
          (emacsvox-org--feedback-facts
           'org-paragraph 'focus-entered 'paragraph-navigation)
          'navigation 'paragraph #'emacsvox-speak-paragraph)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-org-cycle-list-bullet-after (&rest _)
  "Cue and speak after interactively cycling an Org list bullet."
  (when (ems-interactive-p 'org-cycle-list-bullet)
    (emacsvox-org--present-feedback
     (emacsvox-org--feedback-facts
      'org-item 'state-changed 'list-style-changed)
     'state-change 'item #'emacsvox-speak-line)))

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
         (funcall emacsvox-org-table-after-movement-function))
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
    (message "Showing top-level overview.")))

(advice-add
 'org-overview :after #'emacsvox--advice-org-overview-after
 '((name . emacsvox)))

(defun emacsvox--advice-org-content-after (&rest _)
  "Announce interactively requested Org contents."
  (when (ems-interactive-p 'org-content)
    (message "Showing table of contents.")))

(advice-add
 'org-content :after #'emacsvox--advice-org-content-after
 '((name . emacsvox)))

(defun emacsvox--advice-org-tree-to-indirect-buffer-after (&rest _)
  "Announce a subtree cloned interactively into an indirect buffer."
  (when (ems-interactive-p 'org-tree-to-indirect-buffer)
    (message "Cloned %s"
             (with-current-buffer org-last-indirect-buffer
               (goto-char (point-min))
               (buffer-substring (line-beginning-position)
                                 (line-end-position))))))

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
         (emacsvox-org--present-feedback-after
          (emacsvox-org--feedback-facts
           'org-content 'object-changed 'subtree-changed)
          'edit 'yank-object #'emacsvox-speak-line)))
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
         (emacsvox-org--present-feedback
          (emacsvox-org--feedback-facts
           'org-content 'state-changed 'option-toggled)
          'state-change 'button #'emacsvox-speak-line)))
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
         (emacsvox-org--present-feedback
          (emacsvox-org--feedback-facts
           'org-content 'object-changed 'timestamp-changed)
          'edit 'select-object #'emacsvox-speak-line)))
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
  "Speak the result of evaluating an Org calendar expression."
  (tts-speak org-ans2))

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
   org-agenda-goto-today
   )
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after interactive Org agenda navigation."
       (when (ems-interactive-p ',target)
         (emacsvox-org--present-feedback
          (emacsvox-org--feedback-facts
           'org-agenda-entry 'focus-entered 'agenda-navigation)
          'navigation 'select-object #'emacsvox-speak-line)))
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
         (emacsvox-org--present-feedback
          (emacsvox-org--feedback-facts
           'org-agenda-entry 'state-changed 'agenda-closed)
          'state-change 'close-object #'emacsvox-speak-mode-line)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(cl-loop
 for target in
 '(org-agenda-goto org-agenda-show org-agenda-switch-to)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after interactively opening an Org agenda item."
       (when (ems-interactive-p ',target)
         (emacsvox-org--present-feedback
          (emacsvox-org--feedback-facts
           'org-agenda-entry 'focus-entered 'agenda-opened)
          'navigation 'open-object #'emacsvox-speak-line)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-org-agenda-after (&rest _)
  "Cue and speak after interactively opening the Org agenda."
  (when (ems-interactive-p 'org-agenda)
    (emacsvox-org--present-feedback
     (emacsvox-org--feedback-facts
      'org-agenda-entry 'focus-entered 'agenda-opened)
     'navigation 'open-object #'emacsvox-speak-line)))

(advice-add
 'org-agenda :after #'emacsvox--advice-org-agenda-after
 '((name . emacsvox)))

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
      (funcall emacsvox-org-table-after-movement-function))
     (t
      (emacsvox-org--present-feedback-after
       (emacsvox-org--feedback-facts
        'org-content 'object-changed 'line-inserted)
       'edit 'select-object #'emacsvox-speak-line)))))

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
    (emacsvox-org--present-feedback
     (emacsvox-org--feedback-facts
      'org-item 'state-changed 'checkbox-toggled)
     'state-change 'button #'emacsvox-speak-line)))

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
         (emacsvox-org--present-feedback-after
          (emacsvox-org--feedback-facts
           'org-item 'focus-entered 'item-boundary)
          'navigation 'select-object #'emacsvox-speak-line)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-org-beginning-of-line-after (&rest _)
  "Speak after interactive movement to the beginning of an Org line."
  (when (ems-interactive-p 'org-beginning-of-line)
    (emacsvox-org--present-feedback-after
     (emacsvox-org--feedback-facts
      'org-content 'focus-entered 'line-start)
     'navigation 'left #'emacsvox-speak-line)))

(advice-add
 'org-beginning-of-line :after
 #'emacsvox--advice-org-beginning-of-line-after
 '((name . emacsvox)))

(defun emacsvox--advice-org-end-of-line-after (&rest _)
  "Speak after interactive movement to the end of an Org line."
  (when (ems-interactive-p 'org-end-of-line)
    (emacsvox-org--present-feedback-after
     (emacsvox-org--feedback-facts
      'org-content 'focus-entered 'line-end)
     'navigation 'right #'emacsvox-speak-line)))

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
    (emacsvox-org--present-feedback
     (emacsvox-org--feedback-facts
      'org-capture 'focus-entered 'capture-target)
     'navigation 'large-movement #'emacsvox-speak-line)))

(advice-add
 'org-capture-goto-last-stored :after
 #'emacsvox--advice-org-capture-goto-last-stored-after
 '((name . emacsvox)))

(defun emacsvox--advice-org-capture-goto-target-after (&rest _)
  "Cue and speak after visiting an Org capture target."
  (emacsvox-org--present-feedback
   (emacsvox-org--feedback-facts
    'org-capture 'focus-entered 'capture-target)
   'navigation 'large-movement #'emacsvox-speak-line))

(advice-add
 'org-capture-goto-target :after
 #'emacsvox--advice-org-capture-goto-target-after
 '((name . emacsvox)))

(defun emacsvox--advice-org-capture-finalize-after (&rest _)
  "Cue after finalizing an Org capture."
  (emacsvox-org--present-feedback
   (emacsvox-org--feedback-facts
    'org-capture 'object-changed 'capture-saved)
   'notification 'save-object #'ignore))

(advice-add
 'org-capture-finalize :after
 #'emacsvox--advice-org-capture-finalize-after
 '((name . emacsvox)))

(defun emacsvox--advice-org-capture-kill-after (&rest _)
  "Cue after cancelling an Org capture."
  (emacsvox-org--present-feedback
   (emacsvox-org--feedback-facts
    'org-capture 'state-changed 'capture-cancelled)
   'notification 'close-object #'ignore))

(advice-add
 'org-capture-kill :after
 #'emacsvox--advice-org-capture-kill-after
 '((name . emacsvox)))

(defun emacsvox-org-table-speak-current-element ()
  "echoes current table element"
  (interactive)
  (let ((field (org-table-get-field)))
    (cond
     ((string-match "^ *$" field) (tts-speak "space"))
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
 for target in
 '(org-table-next-field org-table-previous-field
                        org-table-next-row org-table-previous-row)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Speak the current Org table cell after movement."
       (funcall emacsvox-org-table-after-movement-function))
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
  "Speak prompt intelligently."
  (let (choices)
    (setq choices
          (cond ((null first-key) entries)
                (t (cl-caddr (assoc first-key entries)))))
    (tts-notify
     (mapconcat
      #'(lambda (e) (format "%c: %s\n" (cl-first e) (cl-second e)))
      choices "\n"))
    (sit-for 5)))

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
         (emacsvox-org--present-feedback
          (emacsvox-org--feedback-facts
           'org-edit-buffer 'state-changed 'edit-closed)
          'state-change 'close-object #'emacsvox-speak-line)))
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
         (emacsvox-org--present-feedback
          (emacsvox-org--feedback-facts
           'org-edit-buffer 'state-changed 'edit-opened)
          'state-change 'open-object #'emacsvox-speak-mode-line)))
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

;;; TVR: Conveniences

(defun tvr-org-itemize ()
  "Start a numbered  list."
  (interactive)
  (forward-line 0)
  (insert "  -  ")
  (emacsvox-org--present-feedback-after
   (emacsvox-org--feedback-facts
    'org-item 'object-changed 'list-item-created)
   'edit 'item #'emacsvox-speak-line))

(defun tvr-org-enumerate ()
  "Start a numbered  list."
  (interactive)
  (forward-line 0)
  (insert "  1.  ")
  (emacsvox-org--present-feedback-after
   (emacsvox-org--feedback-facts
    'org-item 'object-changed 'list-item-created)
   'edit 'item #'emacsvox-speak-line))

(defun tvr-org-alphabetize ()
  "Start an alphabetized   list."
  (interactive)
  (forward-line 0)
  (insert "  A.  ")
  (emacsvox-org--present-feedback-after
   (emacsvox-org--feedback-facts
    'org-item 'object-changed 'list-item-created)
   'edit 'item #'emacsvox-speak-line))

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
    (emacsvox-org--present-feedback
     (emacsvox-org--feedback-facts
      'org-export 'object-changed 'export-completed)
     'notification 'task-done #'emacsvox-speak-mode-line)))

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

(add-hook
 'org-publish-after-publishing-hook
 #'(lambda (_s _t)
     (emacsvox-org--present-feedback
      (emacsvox-org--feedback-facts
       'org-export 'object-changed 'publish-completed)
      'notification 'save-object #'emacsvox-speak-message-again)))

(defun emacsvox--advice-org-export-to-file-after (_backend file &rest _)
  "Cue and report the Org export output FILE."
  (emacsvox-org--present-feedback
   (emacsvox-org--feedback-facts
    'org-export 'object-changed 'export-completed)
   'notification 'save-object #'tts-notify (format "Wrote %s" file)))

(advice-add
 'org-export-to-file :after #'emacsvox--advice-org-export-to-file-after
 '((name . emacsvox)))

(provide 'emacsvox-org)
;;;  end of file
