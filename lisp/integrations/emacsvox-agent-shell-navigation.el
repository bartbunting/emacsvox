;;; emacsvox-agent-shell-navigation.el --- Semantic Agent Shell navigation  -*- lexical-binding: t; -*-

;; Copyright (C) 2025, T. V. Raman
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop agent-shell
;; URL: https://github.com/bartbunting/emacsvox

;; This file is part of Emacsvox.
;;
;; Emacsvox is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; Emacsvox is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with Emacsvox.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Transcript locations, response summaries, semantic movement, fragment
;; expansion and source-block interaction. Presentation supplies shared
;; feedback, events owns asynchronous response observation, and motion owns
;; visual movement and live-input policy. The facade retains activation.
;; Repeat-key installation is explicit so the facade controls activation order.
;; Load through `emacsvox-agent-shell'.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'emacsvox-preamble)
(require 'emacsvox-agent-shell-render)
(require 'emacsvox-agent-shell-tables)

(declare-function emacsvox-agent-shell--presentation-facts
                  "emacsvox-agent-shell-presentation" (role &optional event states attributes))
(declare-function emacsvox-agent-shell--session-buffer
                  "emacsvox-agent-shell-presentation" (&optional buffer))
(declare-function emacsvox-agent-shell--nonempty-text
                  "emacsvox-agent-shell-presentation" (value))
(declare-function emacsvox-agent-shell--submit-icon-feedback
                  "emacsvox-agent-shell-presentation" (facts occasion icon))
(declare-function emacsvox-agent-shell--submit-text-feedback
                  "emacsvox-agent-shell-presentation" (text facts occasion &optional icon delivery-policy replacement-key))
(declare-function emacsvox-agent-shell--semantic-item-feedback
                  "emacsvox-agent-shell" ())
(defvar emacsvox-agent-shell-block-navigation-max-characters)
(defvar emacsvox-agent-shell--response-turn-active-p)
(defvar emacsvox-agent-shell--last-completed-answer)
(defvar emacsvox-agent-shell--latest-turn-outcome)
(defvar agent-shell-ui--fold-toggle-state)
(declare-function agent-shell-copy-source-block-at-point
                  "agent-shell" (&optional pos))
(declare-function agent-shell-goto-last-interaction "agent-shell" ())
(declare-function agent-shell-interaction-at-point "agent-shell" ())
(declare-function agent-shell-markdown-source-block-at-point
                  "agent-shell-markdown" (&optional pos))
(declare-function agent-shell-status "agent-shell" t)
(declare-function agent-shell-ui-toggle-fragment "agent-shell-ui" ())
(declare-function agent-shell-ui-toggle-all-fragments "agent-shell-ui" ())
(declare-function agent-shell--point-in-live-input-p "agent-shell-prompt" ())

;;;  Navigation Commands

(defconst emacsvox-agent-shell--block-type-choices
  '(("Agent response" . agent-response)
    ("User prompt" . user-prompt)
    ("Thought or reasoning" . thought)
    ("Tool call" . tool-call)
    ("Activity group" . activity-group)
    ("Plan" . plan)
    ("Permission" . permission)
    ("Error" . error)
    ("Table" . table)
    ("Source block" . source-block)
    ("Heading" . heading)
    ("Link" . link)
    ("Other" . other))
  "Completion candidates for semantic agent-shell block navigation.")

(defun emacsvox-agent-shell--normalize-block-type (type)
  "Return current semantic navigation type for TYPE.
`tool-group' is the name used by older loaded support versions."
  (if (eq type 'tool-group) 'activity-group type))

(defvar emacsvox-agent-shell--block-navigation-type 'agent-response
  "Most recently selected semantic agent-shell block type.")

;; Preserve a live session's selection when reloading across the rename.
(when (eq emacsvox-agent-shell--block-navigation-type 'tool-group)
  (setq emacsvox-agent-shell--block-navigation-type 'activity-group))

(defun emacsvox-agent-shell--block-type-label (type)
  "Return the display label for semantic block TYPE."
  (or (car (rassq
            (emacsvox-agent-shell--normalize-block-type type)
            emacsvox-agent-shell--block-type-choices))
      "Other"))

(defun emacsvox-agent-shell--block-role (type)
  "Return the registered semantic role for Agent Shell block TYPE."
  (pcase (emacsvox-agent-shell--normalize-block-type type)
    ('agent-response 'agent-response)
    ('user-prompt 'agent-user-prompt)
    ('thought 'agent-thought)
    ('tool-call 'agent-tool)
    ('permission 'permission-request)
    ('plan 'agent-plan)
    ('error 'agent-error)
    ('source-block 'agent-source-block)
    ('table 'agent-table)
    (_ 'agent-block)))

(defun emacsvox-agent-shell--block-facts
    (type &optional event attributes)
  "Return semantic facts for Agent Shell block TYPE.

EVENT describes the interaction and ATTRIBUTES augments the registered block
kind."
  (let ((kind (emacsvox-agent-shell--normalize-block-type type)))
    (emacsvox-agent-shell--presentation-facts
     (emacsvox-agent-shell--block-role kind)
     event nil
     (append (list :agent-block-kind kind) attributes))))

(defun emacsvox-agent-shell--block-location-facts (location &optional event)
  "Return semantic facts for block LOCATION and optional EVENT."
  (let ((type (or (plist-get location :type) 'other))
        attributes)
    (when-let* ((language (plist-get location :language)))
      (setq attributes
            (append attributes (list :agent-source-language language))))
    (when-let* ((visibility (plist-get location :visibility)))
      (setq attributes
            (append attributes (list :visibility visibility))))
    (emacsvox-agent-shell--block-facts
     type event attributes)))

(defun emacsvox-agent-shell--accept-block-type-default ()
  "Accept the default block type when the minibuffer is empty.
Otherwise insert the invoking character normally."
  (interactive)
  (if (string-empty-p (minibuffer-contents-no-properties))
      (exit-minibuffer)
    (self-insert-command 1)))

(defun emacsvox-agent-shell--block-type-minibuffer-setup (accept-key)
  "Bind ACCEPT-KEY to accept an empty block-type minibuffer."
  (when accept-key
    (use-local-map (copy-keymap (current-local-map)))
    (local-set-key (kbd accept-key)
                   #'emacsvox-agent-shell--accept-block-type-default)))

(defun emacsvox-agent-shell--read-block-type (&optional accept-key)
  "Read and remember a semantic agent-shell block type.
When ACCEPT-KEY is non-nil, let it accept the default on empty input."
  (let* ((default
          (emacsvox-agent-shell--block-type-label
           emacsvox-agent-shell--block-navigation-type))
         (selection
          (minibuffer-with-setup-hook
              (lambda ()
                (emacsvox-agent-shell--block-type-minibuffer-setup
                 accept-key))
            (let ((completion-ignore-case t))
              (completing-read
               (format-prompt "Block type" default)
               (mapcar #'car emacsvox-agent-shell--block-type-choices)
               nil t nil nil default)))))
    (setq emacsvox-agent-shell--block-navigation-type
          (cdr
           (assoc-string
            selection emacsvox-agent-shell--block-type-choices t)))))

(defun emacsvox-agent-shell--rendered-latest-agent-answer ()
  "Return the latest rendered answer from the current Agent Shell buffer."
  (save-excursion
    (condition-case nil
        (progn
          (agent-shell-goto-last-interaction)
          (when-let* ((interaction
                       (agent-shell-interaction-at-point))
                      (response (map-elt interaction :response)))
            (emacsvox-agent-shell--agent-answer-from-response response)))
      (error nil))))

(defun emacsvox-agent-shell--response-in-progress-p (shell-buffer)
  "Return non-nil when SHELL-BUFFER has an incomplete agent turn."
  (with-current-buffer shell-buffer
    (let ((status
           (condition-case nil
               (agent-shell-status :shell-buffer shell-buffer)
             (error nil))))
      (or emacsvox-agent-shell--response-turn-active-p
          (memq status '(busy blocked))))))

(defun emacsvox-agent-shell--latest-agent-answer-state ()
  "Return the completed answer and progress state for the current session."
  (let ((shell-buffer (emacsvox-agent-shell--session-buffer)))
    (with-current-buffer shell-buffer
      (let* ((in-progress
              (emacsvox-agent-shell--response-in-progress-p shell-buffer))
             (answer
              (cond
               ((or in-progress
                    (eq emacsvox-agent-shell--latest-turn-outcome 'failed))
                emacsvox-agent-shell--last-completed-answer)
               (emacsvox-agent-shell--last-completed-answer)
               (t
                (when-let* ((rendered
                             (emacsvox-agent-shell--rendered-latest-agent-answer)))
                  (setq emacsvox-agent-shell--last-completed-answer rendered
                        emacsvox-agent-shell--latest-turn-outcome 'completed)
                  rendered)))))
        (list :answer answer :in-progress in-progress)))))

(defun emacsvox-agent-shell--latest-agent-answer ()
  "Return the latest completed answer for the current Agent Shell session."
  (plist-get (emacsvox-agent-shell--latest-agent-answer-state) :answer))

(defconst emacsvox-agent-shell--response-overview-preview-limit 120
  "Maximum characters used for a response overview's opening phrase.")

(defconst emacsvox-agent-shell--markdown-heading-faces
  '(agent-shell-markdown-header-1
    agent-shell-markdown-header-2
    agent-shell-markdown-header-3
    agent-shell-markdown-header-4
    agent-shell-markdown-header-5
    agent-shell-markdown-header-6)
  "Rendered Markdown faces counted as headings in response overviews.")

(defun emacsvox-agent-shell--string-run-count (text predicate)
  "Count contiguous runs in TEXT for which PREDICATE returns non-nil.
PREDICATE receives TEXT and the start position of each property run."
  (let ((position 0)
        (end (length text))
        active-p
        (count 0))
    (while (< position end)
      (let ((match-p (funcall predicate text position)))
        (when (and match-p (not active-p))
          (setq count (1+ count)))
        (setq active-p match-p
              position
              (or (next-property-change position text end) end))))
    count))

(defun emacsvox-agent-shell--string-property-run-count (text property)
  "Count contiguous non-nil PROPERTY runs in TEXT."
  (emacsvox-agent-shell--string-run-count
   text
   (lambda (value position)
     (get-text-property position property value))))

(defun emacsvox-agent-shell--string-heading-run-count (text)
  "Count contiguous rendered Markdown heading runs in TEXT."
  (emacsvox-agent-shell--string-run-count
   text
   (lambda (value position)
     (let ((face (get-text-property position 'face value))
           (font-lock-face
            (get-text-property position 'font-lock-face value)))
       (seq-some
        (lambda (heading)
          (or (emacsvox-agent-shell--face-spec-includes-p face heading)
              (emacsvox-agent-shell--face-spec-includes-p
               font-lock-face heading)))
        emacsvox-agent-shell--markdown-heading-faces)))))

(defun emacsvox-agent-shell--response-overview-preview (answer)
  "Return a bounded opening sentence or phrase from ANSWER."
  (let* ((plain
          (string-trim
           (replace-regexp-in-string
            "[[:space:]]+" " " (substring-no-properties answer))))
         (limit emacsvox-agent-shell--response-overview-preview-limit)
         (sentence-start
          (string-match "[.!?]\\(?:[[:space:]]\\|\\'\\)" plain))
         (sentence-end (and sentence-start (1+ sentence-start))))
    (cond
     ((and sentence-end (<= sentence-end limit))
      (substring plain 0 sentence-end))
     ((<= (length plain) limit) plain)
     (t
      (let* ((prefix (substring plain 0 limit))
             (word-start
              (string-match "[[:space:]][^[:space:]]*\\'" prefix))
             (cut (or word-start limit)))
        (concat (string-trim-right (substring prefix 0 cut))
                ", continued"))))))

(defun emacsvox-agent-shell--response-overview (answer)
  "Return a concise structural overview of rendered ANSWER."
  (let* ((lines (1+ (cl-count ?\n answer)))
         (headings
          (emacsvox-agent-shell--string-heading-run-count answer))
         (source-blocks
          (emacsvox-agent-shell--string-property-run-count
           answer 'agent-shell-markdown-source-block-body))
         (tables
          (emacsvox-agent-shell--string-property-run-count
           answer 'agent-shell-markdown-table-source))
         (parts
          (list (format "%d %s" lines (if (= lines 1) "line" "lines")))))
    (dolist (entry `((,headings . "heading")
                     (,source-blocks . "code block")
                     (,tables . "table")))
      (when (> (car entry) 0)
        (setq parts
              (append
               parts
               (list
                (format "%d %s%s"
                        (car entry) (cdr entry)
                        (if (= (car entry) 1) "" "s")))))))
    (format "Last completed response: %s. Begins: %s"
            (string-join parts ", ")
            (emacsvox-agent-shell--response-overview-preview answer))))

(defun emacsvox-agent-shell-speak-last-response ()
  "Speak the latest completed agent answer in full without moving point."
  (interactive)
  (let* ((state (emacsvox-agent-shell--latest-agent-answer-state))
         (answer (plist-get state :answer))
         (in-progress (plist-get state :in-progress)))
    (if answer
      (progn
        (tts-stop)
        (emacsvox-agent-shell--submit-text-feedback
         (if in-progress
             (concat "Agent is still working. Last completed response: "
                     answer)
           answer)
         (emacsvox-agent-shell--presentation-facts
          'agent-response 'agent-content-inspected)
         'inspection 'item))
      (emacsvox-agent-shell--submit-text-feedback
       (if in-progress
           "Agent response in progress; no completed response available."
         "No agent response available.")
       (emacsvox-agent-shell--presentation-facts
        'agent-response 'operation-failed)
       'inspection 'warn-user))))

(defun emacsvox-agent-shell-speak-response-overview ()
  "Speak a concise overview of the latest completed agent answer."
  (interactive)
  (let* ((state (emacsvox-agent-shell--latest-agent-answer-state))
         (answer (plist-get state :answer))
         (in-progress (plist-get state :in-progress)))
    (if answer
      (progn
        (tts-stop)
        (emacsvox-agent-shell--submit-text-feedback
         (concat
          (when in-progress "Agent is still working. ")
          (emacsvox-agent-shell--response-overview answer))
         (emacsvox-agent-shell--presentation-facts
          'agent-response 'agent-content-inspected)
         'inspection 'item))
      (emacsvox-agent-shell--submit-text-feedback
       (if in-progress
           "Agent response in progress; no completed response available."
         "No agent response available.")
       (emacsvox-agent-shell--presentation-facts
        'agent-response 'operation-failed)
       'inspection 'warn-user))))

(defun emacsvox-agent-shell--concise-block-text (text)
  "Return a concise single-line version of block TEXT."
  (when text
    (let ((plain
           (string-trim
            (replace-regexp-in-string
             "[[:space:]]+" " " (substring-no-properties text)))))
      (unless (string-empty-p plain)
        (if (> (length plain) 80)
            (concat (substring plain 0 77) "...")
          plain)))))

(defun emacsvox-agent-shell--block-navigation-body-text (text)
  "Return normalized block body TEXT for semantic navigation speech."
  (when text
    (let ((plain
           (string-trim
            (replace-regexp-in-string
             "[[:space:]]+" " " (substring-no-properties text)))))
      (unless (string-empty-p plain)
        (let ((limit
               emacsvox-agent-shell-block-navigation-max-characters))
          (if (and (integerp limit)
                   (> limit 0)
                   (> (length plain) limit))
              (let* ((prefix (substring plain 0 limit))
                     (word-start
                      (unless (eq (aref plain limit) ?\s)
                        (string-match
                         "[[:space:]][^[:space:]]*\\'" prefix)))
                     (cut (or word-start limit))
                     (preview
                      (string-trim-right (substring prefix 0 cut))))
                (concat
                 preview
                 (format " [block truncated; %d characters omitted]"
                         (- (length plain) (length preview)))))
            plain))))))

(defun emacsvox-agent-shell--block-section-text (start end section)
  "Return semantic speech text for fragment SECTION between START and END."
  (let ((position start)
        result)
    (while (and (< position end) (not result))
      (let ((next
             (or (next-single-property-change
                  position 'agent-shell-ui-section nil end)
                 end)))
        (when (eq (get-text-property position 'agent-shell-ui-section)
                  section)
          (setq result
                (buffer-substring position next)))
        (setq position next)))
    (emacsvox-agent-shell--concise-block-text
     (and result
          (emacsvox-agent-shell--remove-visual-chrome-for-speech result)))))

(defun emacsvox-agent-shell--block-section-range (start end section)
  "Return the range of fragment SECTION between START and END."
  (let ((position start)
        result)
    (while (and (< position end) (not result))
      (let ((next
             (or (next-single-property-change
                  position 'agent-shell-ui-section nil end)
                 end)))
        (when (eq (get-text-property position 'agent-shell-ui-section)
                  section)
          (setq result (cons position next)))
        (setq position next)))
    result))

(defun emacsvox-agent-shell--visible-block-text (start end)
  "Return complete visible block text between START and END."
  (when (and start end (< start end))
    (let ((position start)
          parts)
      (while (< position end)
        (let ((next
               (or
                (next-single-char-property-change
                 position 'invisible nil end)
                end)))
          (unless (invisible-p position)
            ;; Keep renderer provenance until decorative table borders have
            ;; been removed; plain copies cannot distinguish them from data.
            (push (substring-no-properties
                   (emacsvox-agent-shell--without-table-borders-for-speech
                    (buffer-substring position next)))
                  parts))
          (setq position next)))
      (let ((text (string-trim (string-join (nreverse parts)))))
        (unless (string-empty-p text) text)))))

(defun emacsvox-agent-shell--fragment-visibility (start end state)
  "Return semantic visibility for foldable fragment STATE from START to END."
  (when (text-property-any
         start end 'agent-shell-ui-section 'indicator)
    (if (map-elt state :collapsed) 'folded 'expanded)))

(defun emacsvox-agent-shell--fragment-location (start end state)
  "Return a semantic location for fragment STATE from START to END."
  (let* ((qualified-id (map-elt state :qualified-id))
         (type
          (emacsvox-agent-shell--semantic-block-type
           qualified-id state start))
         (left
          (emacsvox-agent-shell--block-section-text
           start end 'label-left))
         (right
          (emacsvox-agent-shell--block-section-text
           start end 'label-right))
         (indicator
          (text-property-any
           start end 'agent-shell-ui-section 'indicator))
         (visibility
          (emacsvox-agent-shell--fragment-visibility start end state))
         (label
          (emacsvox-agent-shell--concise-block-text
           (string-join (delq nil (list left right)) " ")))
         (body-range
          (emacsvox-agent-shell--block-section-range start end 'body))
         (body
          (if body-range
              (emacsvox-agent-shell--visible-block-text
               (car body-range) (cdr body-range))
            (when (eq type 'user-prompt)
              (emacsvox-agent-shell--visible-block-text start end)))))
    (list :position start
          :end end
          :type type
          :state state
          :label label
          :body body
          :visibility visibility
          :fold-state
          (when indicator
            (if (eq visibility 'folded) "collapsed" "expanded")))))

(defun emacsvox-agent-shell--fragment-locations ()
  "Return semantic locations for all agent-shell UI fragments."
  (let ((position (point-min))
        locations)
    (while (< position (point-max))
      (let* ((state (get-text-property position 'agent-shell-ui-state))
             (next
              (or (next-single-property-change
                   position 'agent-shell-ui-state nil (point-max))
                  (point-max))))
        (when (and state (< position next))
          (push (emacsvox-agent-shell--fragment-location
                 position next state)
                locations))
        (setq position next)))
    (nreverse locations)))

(defun emacsvox-agent-shell--face-includes-p (value face)
  "Return non-nil when face specification VALUE includes FACE."
  (or (eq value face)
      (and (listp value) (memq face value))))

(defun emacsvox-agent-shell--prompt-face-p (value)
  "Return non-nil when face specification VALUE marks a shell prompt.
Live Shell Maker prompts use `comint-highlight-prompt'; restored Agent Shell
prompts use `agent-shell-prompt'.  Either face may occur more than once in a
face list."
  (or (emacsvox-agent-shell--face-includes-p
       value 'comint-highlight-prompt)
      (emacsvox-agent-shell--face-includes-p
       value 'agent-shell-prompt)))

(defun emacsvox-agent-shell--prompt-locations ()
  "Return semantic user-prompt locations in the current buffer."
  (let (locations)
    (dolist (property '(agent-shell-viewport-prompt font-lock-face face))
      (let ((position (point-min)))
        (while (< position (point-max))
          (let* ((value (get-text-property position property))
                 (next
                  (or (next-single-property-change
                       position property nil (point-max))
                      (point-max)))
                 (prompt-p
                  (if (eq property 'agent-shell-viewport-prompt)
                      value
                    (emacsvox-agent-shell--prompt-face-p value)))
                 (body-end
                  (when prompt-p
                    (if (eq property 'agent-shell-viewport-prompt)
                        next
                      (or (text-property-any
                           next (point-max) 'shell-maker--marker t)
                          (point-max))))))
            (when prompt-p
              (push
               (list :position position
                     :end body-end
                     :type 'user-prompt
                     :body
                     (emacsvox-agent-shell--visible-block-text
                      position body-end))
               locations))
            (setq position next)))))
    (nreverse locations)))

(defun emacsvox-agent-shell--table-locations ()
  "Return semantic locations for rendered Markdown tables."
  (let ((position (point-min))
        locations)
    (while (< position (point-max))
      (let* ((source
              (get-text-property
               position 'agent-shell-markdown-table-source))
             (next
              (or (next-single-property-change
                   position 'agent-shell-markdown-table-source
                   nil (point-max))
                  (point-max))))
        (when source
          (when-let* ((cell
                      (text-property-any
                       position next
                       'agent-shell-markdown-table-cell-start t)))
            (push (list :position cell
                        :start position
                        :end next
                        :type 'table
                        :state
                        (get-text-property cell 'agent-shell-ui-state))
                  locations)))
        (setq position next)))
    (nreverse locations)))

(defun emacsvox-agent-shell--property-range-at-position
    (property position)
  "Return PROPERTY's complete non-nil range containing POSITION."
  (when (and (< position (point-max))
             (get-text-property position property))
    (cons
     (or (previous-single-property-change
          (min (1+ position) (point-max))
          property nil (point-min))
         (point-min))
     (or (next-single-property-change
          position property nil (point-max))
         (point-max)))))

(defun emacsvox-agent-shell--fragment-location-at-position
    (position &optional metadata-only)
  "Return the agent-shell UI fragment containing POSITION.
When METADATA-ONLY is non-nil, do not copy its labels or body."
  (when-let* ((state
               (and (< position (point-max))
                    (get-text-property position 'agent-shell-ui-state)))
              (range
               (emacsvox-agent-shell--property-range-at-position
                'agent-shell-ui-state position)))
    (if metadata-only
        (list
         :position (car range)
         :end (cdr range)
         :type
         (emacsvox-agent-shell--semantic-block-type
          (map-elt state :qualified-id) state position)
         :state state
         :visibility
         (emacsvox-agent-shell--fragment-visibility
          (car range) (cdr range) state))
      (emacsvox-agent-shell--fragment-location
       (car range) (cdr range) state))))

(defun emacsvox-agent-shell--table-location-at-position (position)
  "Return the rendered Markdown table containing POSITION."
  (when-let* ((range
               (emacsvox-agent-shell--property-range-at-position
                'agent-shell-markdown-table-source position))
              (cell
               (text-property-any
                (car range) (cdr range)
                'agent-shell-markdown-table-cell-start t)))
    (list :position cell
          :start (car range)
          :end (cdr range)
          :type 'table
          :state (get-text-property cell 'agent-shell-ui-state))))

(defun emacsvox-agent-shell--source-block-language (source)
  "Return the fenced code language recorded in Markdown SOURCE."
  (when (and (stringp source)
             (string-match
              "\\`[ \t]*`\\{3,\\}[ \t]*\\([[:alnum:]+#-]*\\)"
              source))
    (emacsvox-agent-shell--nonempty-text (match-string 1 source))))

(defun emacsvox-agent-shell--source-block-panel-start (body-start)
  "Return the rendered panel start preceding BODY-START."
  (let ((start body-start))
    (while (and (> start (point-min))
                (stringp
                 (get-text-property
                  (1- start) 'agent-shell-markdown-source)))
      (setq start
            (or (previous-single-property-change
                 start 'agent-shell-markdown-source nil (point-min))
                (point-min))))
    start))

(defun emacsvox-agent-shell--source-block-panel-end (body-end)
  "Return the rendered panel end following BODY-END."
  (let ((end body-end))
    (while (and (< end (point-max))
                (stringp
                 (get-text-property end 'agent-shell-markdown-source)))
      (setq end
            (or (next-single-property-change
                 end 'agent-shell-markdown-source nil (point-max))
                (point-max))))
    end))

(defun emacsvox-agent-shell--source-block-line-count (body)
  "Return the number of logical lines in source block BODY."
  (if (or (not (stringp body)) (string-empty-p body))
      0
    (let ((lines 1)
          (position 0))
      (while (string-match "\n" body position)
        (setq lines (1+ lines)
              position (match-end 0)))
      lines)))

(defun emacsvox-agent-shell--source-block-locations ()
  "Return semantic locations for rendered Markdown source blocks."
  (let ((position (point-min))
        locations)
    (while (< position (point-max))
      (let* ((body-p
              (get-text-property
               position 'agent-shell-markdown-source-block-body))
             (next
              (or (next-single-property-change
                   position 'agent-shell-markdown-source-block-body
                   nil (point-max))
                  (point-max))))
        (when body-p
          (let* ((source
                  (get-text-property
                   position 'agent-shell-markdown-source))
                 (body
                  (agent-shell-markdown-source-block-at-point position)))
            (push
             (list
              :position position
              :start
              (emacsvox-agent-shell--source-block-panel-start position)
              :end (emacsvox-agent-shell--source-block-panel-end next)
              :type 'source-block
              :state (get-text-property position 'agent-shell-ui-state)
              :language
              (emacsvox-agent-shell--source-block-language source)
              :line-count
              (emacsvox-agent-shell--source-block-line-count body)
              :body body)
             locations)))
        (setq position next)))
    (nreverse locations)))

(defun emacsvox-agent-shell--source-block-location-at-body (position)
  "Return the rendered source-block location whose body contains POSITION."
  (when-let* ((range
               (emacsvox-agent-shell--property-range-at-position
                'agent-shell-markdown-source-block-body position))
              (body-start (car range))
              (body-end (cdr range))
              (source
               (get-text-property
                body-start 'agent-shell-markdown-source))
              (body
               (agent-shell-markdown-source-block-at-point body-start)))
    (list
     :position body-start
     :start (emacsvox-agent-shell--source-block-panel-start body-start)
     :end (emacsvox-agent-shell--source-block-panel-end body-end)
     :type 'source-block
     :state (get-text-property body-start 'agent-shell-ui-state)
     :language (emacsvox-agent-shell--source-block-language source)
     :line-count (emacsvox-agent-shell--source-block-line-count body)
     :body body)))

(defun emacsvox-agent-shell--markdown-panel-range-at-position (position)
  "Return the contiguous rendered Markdown panel containing POSITION."
  (when (and (< position (point-max))
             (stringp
              (get-text-property position 'agent-shell-markdown-source)))
    (let ((start position)
          (end position))
      (while (and (> start (point-min))
                  (stringp
                   (get-text-property
                    (1- start) 'agent-shell-markdown-source)))
        (setq start
              (or (previous-single-property-change
                   start 'agent-shell-markdown-source nil (point-min))
                  (point-min))))
      (while (and (< end (point-max))
                  (stringp
                   (get-text-property
                    end 'agent-shell-markdown-source)))
        (setq end
              (or (next-single-property-change
                   end 'agent-shell-markdown-source nil (point-max))
                  (point-max))))
      (cons start end))))

(defun emacsvox-agent-shell--source-block-location-at-position (position)
  "Return the rendered source block whose panel contains POSITION."
  (when-let* ((panel
               (emacsvox-agent-shell--markdown-panel-range-at-position
                position))
              (body
               (text-property-any
                (car panel) (cdr panel)
                'agent-shell-markdown-source-block-body t)))
    (emacsvox-agent-shell--source-block-location-at-body body)))

(defun emacsvox-agent-shell--deduplicate-block-locations (locations)
  "Return LOCATIONS without duplicate type/position pairs."
  (let (seen result)
    (dolist (location locations)
      (let ((key (cons (plist-get location :type)
                       (plist-get location :position))))
        (unless (member key seen)
          (push key seen)
          (push location result))))
    (nreverse result)))

(defun emacsvox-agent-shell--block-locations ()
  "Return all semantic transcript block locations in buffer order."
  (let* ((fragments (emacsvox-agent-shell--fragment-locations))
         (prompts (emacsvox-agent-shell--prompt-locations))
         (tables (emacsvox-agent-shell--table-locations))
         (source-blocks
          (emacsvox-agent-shell--source-block-locations))
         (locations (append fragments prompts tables source-blocks)))
    ;; A restored viewport normally retains response fragment state.  Keep a
    ;; whole-response fallback for older or plain viewport content.
    (when (and (derived-mode-p 'agent-shell-viewport-view-mode)
               (not (seq-find
                     (lambda (item)
                       (eq (plist-get item :type) 'agent-response))
                     fragments)))
      (when-let* ((prompt (car (last prompts)))
                  (start (plist-get prompt :end))
                  (response
                   (save-excursion
                     (goto-char start)
                     (skip-chars-forward " \\t\\n\\r")
                     (and (< (point) (point-max)) (point)))))
        (push (list :position response
                    :end (point-max)
                    :type 'agent-response
                    :body
                    (emacsvox-agent-shell--visible-block-text
                     response (point-max)))
              locations)))
    (sort (emacsvox-agent-shell--deduplicate-block-locations locations)
          (lambda (left right)
            (< (plist-get left :position)
               (plist-get right :position))))))

(defun emacsvox-agent-shell--fragment-location-in-direction
    (type direction origin)
  "Return the nearest UI fragment of TYPE from ORIGIN in DIRECTION."
  (save-excursion
    (goto-char origin)
    (let ((current
           (emacsvox-agent-shell--fragment-location-at-position
            origin t)))
      (if (and (eq direction 'backward)
               current
               (eq (plist-get current :type) type)
               (< (plist-get current :position) origin))
          (emacsvox-agent-shell--fragment-location-at-position
           (plist-get current :position))
        ;; Begin outside the current property run.  Starting a property
        ;; search inside a run can return only its remaining substring, and
        ;; `not-current' can skip an immediately adjacent matching run.
        (when current
          (goto-char
           (if (eq direction 'forward)
               (plist-get current :end)
             (plist-get current :position))))
        (let (match)
          (while
              (and
               (setq match
                     (funcall
                      (if (eq direction 'forward)
                          #'text-property-search-forward
                        #'text-property-search-backward)
                      'agent-shell-ui-state nil
                      (lambda (_value state) state)))
               (not
                (emacsvox-agent-shell--fragment-matches-type-p
                 type (prop-match-beginning match) (prop-match-end match)
                 (prop-match-value match)))))
          (when match
            (emacsvox-agent-shell--fragment-location
             (prop-match-beginning match)
             (prop-match-end match)
             (prop-match-value match))))))))

(defun emacsvox-agent-shell--fragment-matches-type-p (type start end state)
  "Return non-nil when fragment STATE from START to END matches TYPE.
Error navigation also includes tools with renderer-styled failure labels."
  (let ((kind (emacsvox-agent-shell--semantic-block-type
               (map-elt state :qualified-id) state start)))
    (or (eq kind type)
        (and (eq type 'error)
             (memq kind '(tool-call other))
             (when-let* ((range (emacsvox-agent-shell--block-section-range
                                start end 'label-left)))
               (let ((position (car range)) found)
                 (while (and (< position (cdr range)) (not found))
                   (setq found
                         (or (emacsvox-agent-shell--face-includes-p
                              (get-text-property position 'face)
                              'agent-shell-error)
                             (emacsvox-agent-shell--face-includes-p
                              (get-text-property position 'font-lock-face)
                              'agent-shell-error))
                         position
                         (next-property-change position nil (cdr range))))
                 found))))))

(defun emacsvox-agent-shell--heading-position-p (position)
  "Return non-nil when POSITION has a rendered Markdown heading face."
  (seq-some
   (lambda (face)
     (or (emacsvox-agent-shell--face-includes-p
          (get-text-property position 'face) face)
         (emacsvox-agent-shell--face-includes-p
          (get-text-property position 'font-lock-face) face)))
   emacsvox-agent-shell--markdown-heading-faces))

(defun emacsvox-agent-shell--heading-location-at-position (position)
  "Return the visible rendered heading containing POSITION, if any.
Inline emphasis or links within a heading do not split its destination."
  (when (and (< position (point-max))
             (not (invisible-p position))
             (emacsvox-agent-shell--heading-position-p position))
    (save-excursion
      (goto-char position)
      (let ((start position) (end (1+ position))
            (line-start (line-beginning-position))
            (line-end (line-end-position)))
        (while (and (> start line-start)
                    (emacsvox-agent-shell--heading-position-p (1- start)))
          (setq start (1- start)))
        (while (and (< end line-end)
                    (emacsvox-agent-shell--heading-position-p end))
          (setq end (1+ end)))
        (list :position start :end end :type 'heading
              :body (emacsvox-agent-shell--visible-block-text start end))))))

(defun emacsvox-agent-shell--link-location-at-position (position)
  "Return the visible rendered link containing POSITION, if any."
  (when (not (invisible-p position))
    (when-let* ((range (emacsvox-agent-shell--property-range-at-position
                       'agent-shell-markdown-url position)))
      (list :position (car range) :end (cdr range) :type 'link
            :body (emacsvox-agent-shell--visible-block-text
                   (car range) (cdr range))))))

(defun emacsvox-agent-shell--property-location-in-direction
    (property location-function direction origin &optional end-boundary)
  "Find PROPERTY from ORIGIN and convert it with LOCATION-FUNCTION.
Search in DIRECTION.  Forward locations must begin after ORIGIN.  Backward
locations must begin before ORIGIN, or end no later than ORIGIN when
END-BOUNDARY is non-nil."
  (save-excursion
    (goto-char origin)
    (let (location match)
      (while
          (and
           (not location)
           (setq match
                 (funcall
                  (if (eq direction 'forward)
                      #'text-property-search-forward
                    #'text-property-search-backward)
                  property nil (lambda (_value value) value))))
        (let ((candidate
               (funcall location-function
                        (prop-match-beginning match))))
          (when
              (and candidate
                   (if (eq direction 'forward)
                       (> (plist-get candidate :position) origin)
                     (if end-boundary
                         (<= (plist-get candidate :end) origin)
                       (< (plist-get candidate :position) origin))))
            (setq location candidate))))
      location)))

(defun emacsvox-agent-shell--prompt-location-from-range (property range)
  "Return a user-prompt location for PROPERTY spanning RANGE."
  (when-let* ((start (car range))
              (end
               (if (eq property 'agent-shell-viewport-prompt)
                   (cdr range)
                 (or (text-property-any
                      (cdr range) (point-max) 'shell-maker--marker t)
                     (point-max)))))
    (list :position start
          :end end
          :type 'user-prompt
          :body
          (emacsvox-agent-shell--visible-block-text start end))))

(defun emacsvox-agent-shell--prompt-location-from-match (property match)
  "Return a user-prompt location for PROPERTY search MATCH."
  (when-let* ((range
               (emacsvox-agent-shell--property-range-at-position
                property (prop-match-beginning match))))
    (emacsvox-agent-shell--prompt-location-from-range property range)))

(defun emacsvox-agent-shell--prompt-property-location-in-direction
    (property direction origin)
  "Return the nearest prompt marked by PROPERTY from ORIGIN in DIRECTION."
  (save-excursion
    (goto-char origin)
    (let (location match)
      (while
          (and
           (not location)
           (setq match
                 (funcall
                  (if (eq direction 'forward)
                      #'text-property-search-forward
                    #'text-property-search-backward)
                  property nil
                  (if (eq property 'agent-shell-viewport-prompt)
                      (lambda (_value value) value)
                    (lambda (_value value)
                      (emacsvox-agent-shell--prompt-face-p value))))))
        (let ((candidate
               (emacsvox-agent-shell--prompt-location-from-match
                property match)))
          (when
              (and candidate
                   ;; The last Comint prompt is an editor, not a submitted
                   ;; message.  Viewport prompts are transcript content.
                   (not (and (derived-mode-p 'agent-shell-mode)
                             (markerp (car-safe comint-last-prompt))
                             (marker-position (car comint-last-prompt))
                             (>= (plist-get candidate :position)
                                 (car comint-last-prompt))))
                   (if (eq direction 'forward)
                       (> (plist-get candidate :position) origin)
                     (< (plist-get candidate :position) origin)))
            (setq location candidate))))
      location)))

(defun emacsvox-agent-shell--nearest-location (locations direction)
  "Return the nearest of LOCATIONS in DIRECTION."
  (car
   (sort
    (delq nil locations)
    (if (eq direction 'forward)
        (lambda (left right)
          (< (plist-get left :position)
             (plist-get right :position)))
      (lambda (left right)
        (> (plist-get left :position)
           (plist-get right :position)))))))

(defun emacsvox-agent-shell--prompt-location-in-direction
    (direction origin)
  "Return the nearest rendered user prompt from ORIGIN in DIRECTION."
  (emacsvox-agent-shell--nearest-location
   (mapcar
    (lambda (property)
      (emacsvox-agent-shell--prompt-property-location-in-direction
       property direction origin))
    '(agent-shell-viewport-prompt font-lock-face face))
   direction))

(defun emacsvox-agent-shell--fragment-type-exists-p (type)
  "Return non-nil when the buffer contains a UI fragment of TYPE."
  (save-excursion
    (goto-char (point-min))
    (let (found match)
      (while
          (and
           (not found)
           (setq match
                 (text-property-search-forward
                  'agent-shell-ui-state nil
                  (lambda (_value state) state))))
        (setq found
              (eq
               (emacsvox-agent-shell--semantic-block-type
                (map-elt (prop-match-value match) :qualified-id)
                (prop-match-value match)
                (prop-match-beginning match))
               type)))
      found)))

(defun emacsvox-agent-shell--viewport-response-location ()
  "Return the plain restored-viewport response fallback, if present."
  (when (and (derived-mode-p 'agent-shell-viewport-view-mode)
             (not
              (emacsvox-agent-shell--fragment-type-exists-p
               'agent-response)))
    (when-let* ((prompt
                 (emacsvox-agent-shell--prompt-location-in-direction
                  'backward (point-max)))
                (start (plist-get prompt :end))
                (response
                 (save-excursion
                   (goto-char start)
                   (skip-chars-forward " \t\n\r")
                   (and (< (point) (point-max)) (point)))))
      (list :position response
            :end (point-max)
            :type 'agent-response
            :body
            (emacsvox-agent-shell--visible-block-text
             response (point-max))))))

(defun emacsvox-agent-shell--block-location-in-direction
    (type direction origin)
  "Return the nearest semantic TYPE from ORIGIN in DIRECTION."
  (setq type (emacsvox-agent-shell--normalize-block-type type))
  (pcase type
    ('heading
     (emacsvox-agent-shell--nearest-location
      (mapcar
       (lambda (property)
         (emacsvox-agent-shell--property-location-in-direction
          property #'emacsvox-agent-shell--heading-location-at-position
          direction origin t))
       '(face font-lock-face))
      direction))
    ('link
     (emacsvox-agent-shell--property-location-in-direction
      'agent-shell-markdown-url
      #'emacsvox-agent-shell--link-location-at-position direction origin t))
    ('table
     (emacsvox-agent-shell--property-location-in-direction
      'agent-shell-markdown-table-source
      #'emacsvox-agent-shell--table-location-at-position
      direction origin t))
    ('source-block
     (emacsvox-agent-shell--property-location-in-direction
      'agent-shell-markdown-source-block-body
      #'emacsvox-agent-shell--source-block-location-at-body
      direction origin t))
    ('user-prompt
     (emacsvox-agent-shell--nearest-location
      (list
       (emacsvox-agent-shell--fragment-location-in-direction
        type direction origin)
       (emacsvox-agent-shell--prompt-location-in-direction
        direction origin))
      direction))
    ('agent-response
     (or
      (emacsvox-agent-shell--fragment-location-in-direction
       type direction origin)
      (when-let* ((fallback
                   (emacsvox-agent-shell--viewport-response-location))
                  (position (plist-get fallback :position))
                  ((if (eq direction 'forward)
                       (> position origin)
                     (< position origin))))
        fallback)))
    (_
     (emacsvox-agent-shell--fragment-location-in-direction
      type direction origin))))

(defun emacsvox-agent-shell--prompt-location-at-position (position)
  "Return the rendered user prompt containing POSITION."
  (when (< position (point-max))
    (when-let* ((candidate
                 (emacsvox-agent-shell--prompt-location-in-direction
                  'backward (min (point-max) (1+ position))))
                (start (plist-get candidate :position))
                (end (plist-get candidate :end))
                ((<= start position))
                ((< position end)))
      candidate)))

(defun emacsvox-agent-shell--local-prompt-property-range
    (property position)
  "Return a prompt PROPERTY range containing POSITION, or nil.
For face properties, accept either the live Comint prompt face or Agent
Shell's restored-prompt face."
  (when (and (<= (point-min) position)
             (< position (point-max)))
    (let ((value (get-text-property position property)))
      (when (if (eq property 'agent-shell-viewport-prompt)
                value
              (emacsvox-agent-shell--prompt-face-p value))
        (emacsvox-agent-shell--property-range-at-position
         property position)))))

(defun emacsvox-agent-shell--prompt-input-face-position (position)
  "Return the prompt-face position starting POSITION's input field.
Shell Maker gives submitted input a nil `field' property immediately after
the output-field prompt prefix.  This property boundary permits constant-local
prompt discovery on every line of a multiline input."
  (let ((probe
         (cond
          ((and (< position (point-max))
                (null (get-text-property position 'field)))
           position)
          ((and (> position (point-min))
                (null (get-text-property (1- position) 'field)))
           (1- position)))))
    (when probe
      (let ((input-start
             (or (previous-single-property-change
                  (min (1+ probe) (point-max))
                  'field nil (point-min))
                 (point-min))))
        (when (> input-start (point-min))
          (1- input-start))))))

(defun emacsvox-agent-shell--local-prompt-location-at-position (position)
  "Return a prompt containing POSITION using only local buffer metadata."
  (let ((probes
         (delete-dups
          (delq
           nil
           (list
            (and (< position (point-max)) position)
            (and (> position (point-min)) (1- position))
            (emacsvox-agent-shell--prompt-input-face-position
             position))))))
    (catch 'location
      (dolist (property
               '(agent-shell-viewport-prompt font-lock-face face))
        (dolist (probe probes)
          (when-let* ((range
                      (emacsvox-agent-shell--local-prompt-property-range
                       property probe))
                     (location
                      (emacsvox-agent-shell--prompt-location-from-range
                       property range))
                     ((<= (plist-get location :position) position))
                     ((< position (plist-get location :end))))
            (throw 'location location))))
      nil)))

(defun emacsvox-agent-shell--output-field-position-p (position)
  "Return non-nil when POSITION is ordinary Shell Maker output.
Prompt prefixes are output fields too, but local prompt discovery runs before
this predicate.  User input has a nil field and therefore remains eligible for
the legacy fallback when its local boundary metadata is incomplete."
  (or (and (< position (point-max))
           (eq (get-text-property position 'field) 'output))
      (and (= position (point-max))
           (> position (point-min))
           (eq (get-text-property (1- position) 'field) 'output))))

(defun emacsvox-agent-shell--innermost-block-location (locations)
  "Return the innermost semantic block from LOCATIONS."
  (car
   (sort
    (delq nil locations)
    (lambda (left right)
      (let ((left-size
             (- (plist-get left :end)
                (or (plist-get left :start)
                    (plist-get left :position))))
            (right-size
             (- (plist-get right :end)
                (or (plist-get right :start)
                    (plist-get right :position)))))
        (or (< left-size right-size)
            (and (= left-size right-size)
                 (memq (plist-get left :type) '(table source-block))
                 (not
                  (memq (plist-get right :type)
                        '(table source-block))))))))))

(defun emacsvox-agent-shell--fragment-location-by-id
    (qualified-id origin)
  "Return fragment QUALIFIED-ID nearest ORIGIN, preferring earlier content."
  (save-excursion
    (goto-char origin)
    (let ((predicate
           (lambda (_value state)
             (equal (map-elt state :qualified-id) qualified-id))))
      (when-let* ((match
                   (or
                    (text-property-search-backward
                     'agent-shell-ui-state nil predicate)
                    (progn
                      (goto-char origin)
                      (text-property-search-forward
                       'agent-shell-ui-state nil predicate)))))
        (list :position (prop-match-beginning match)
              :end (prop-match-end match)
              :type
              (emacsvox-agent-shell--semantic-block-type
               (map-elt (prop-match-value match) :qualified-id)
               (prop-match-value match)
               (prop-match-beginning match))
              :state (prop-match-value match))))))

(defun emacsvox-agent-shell--expand-block-parent (location)
  "Expand LOCATION's collapsed parent group when necessary."
  (when-let* ((state (plist-get location :state))
              (group-id (map-elt state :group-id))
              ((invisible-p (plist-get location :position)))
              (parent
               (emacsvox-agent-shell--fragment-location-by-id
                group-id (plist-get location :position)))
              (parent-state (plist-get parent :state))
              ((map-elt parent-state :collapsed)))
    (goto-char (plist-get parent :position))
    (agent-shell-ui-toggle-fragment)))

(defun emacsvox-agent-shell--source-block-summary (location)
  "Return a concise spoken summary of source block LOCATION."
  (let ((language (plist-get location :language))
        (lines (plist-get location :line-count)))
    (if language
        (format "%s source block, %d %s."
                language lines (if (= lines 1) "line" "lines"))
      (format "Source block, %d %s."
              lines (if (= lines 1) "line" "lines")))))

(defun emacsvox-agent-shell--source-block-speech (location)
  "Return full voiced speech for source block LOCATION."
  (concat
   (propertize
    (emacsvox-agent-shell--source-block-summary location)
    'face 'agent-shell-markdown-source-block-language)
   " "
   (propertize
    (or (plist-get location :body) "")
    'face 'agent-shell-markdown-source-block)))

(defun emacsvox-agent-shell--activity-group-speech-label (label)
  "Return a semantic activity-group heading for rendered LABEL."
  (let ((case-fold-search t))
    (cond
     ((not label) "Activity group")
     ((string-match-p "\\_<activity\\_>" label) label)
     (t (concat "Activity group, " label)))))

(defun emacsvox-agent-shell--block-location-speech (location)
  "Return concise semantic navigation speech for block LOCATION."
  (let* ((type (plist-get location :type))
         (label (plist-get location :label))
         (body
          (emacsvox-agent-shell--block-navigation-body-text
           (plist-get location :body)))
         (fallback
          (or label
              (emacsvox-agent-shell--block-type-label
               type))))
    (cond
     ((eq type 'activity-group)
      (concat
       (string-join
        (delq nil
              (list
               (emacsvox-agent-shell--activity-group-speech-label label)
               (plist-get location :fold-state)))
        ", ")
       "."))
     (body
      (string-join (delq nil (list label body)) ". "))
     (t
      (concat
       (string-join
        (delq nil (list fallback (plist-get location :fold-state))) ", ")
       ".")))))

(defun emacsvox-agent-shell--jump-block-of-type
    (type direction &optional origin)
  "Move to semantic block TYPE in DIRECTION and announce it.
Use ORIGIN instead of point as the navigation boundary when non-nil."
  (unless (derived-mode-p 'agent-shell-mode
                          'agent-shell-viewport-view-mode)
    (user-error "Not in an agent-shell transcript"))
  (let* ((origin (or origin (point)))
         (target
          (emacsvox-agent-shell--block-location-in-direction
           type direction origin)))
    (if target
        (progn
          (emacsvox-agent-shell--expand-block-parent target)
          (goto-char (plist-get target :position))
          (tts-stop)
          (pcase type
            ('table
             (emacsvox-agent-shell--table-entry-feedback direction))
            ('link
             (emacsvox-agent-shell--semantic-item-feedback))
            ('source-block
             (emacsvox-agent-shell--submit-text-feedback
              (emacsvox-agent-shell--source-block-summary target)
              (emacsvox-agent-shell--block-location-facts
               target 'focus-entered)
              'navigation 'open-object))
            (_
             (emacsvox-agent-shell--submit-text-feedback
              (emacsvox-agent-shell--block-location-speech target)
              (emacsvox-agent-shell--block-location-facts
               target 'focus-entered)
              'navigation 'large-movement)))
          target)
      (emacsvox-agent-shell--submit-text-feedback
       (format "No %s %s%s."
               (if (eq direction 'forward) "later" "earlier")
               (downcase (emacsvox-agent-shell--block-type-label type))
               (if (memq type '(source-block heading link)) "" " block"))
       (emacsvox-agent-shell--block-facts type 'operation-failed)
       'navigation 'warn-user)
      nil)))

(defun emacsvox-agent-shell--block-location-at-point (&optional position)
  "Return the innermost semantic block containing POSITION or point.
Rendered tables and source blocks win ties with enclosing transcript blocks."
  (setq position (or position (point)))
  (let* ((table
          (emacsvox-agent-shell--table-location-at-position position))
         (source-block
          (emacsvox-agent-shell--source-block-location-at-position position))
         (fragment
          (emacsvox-agent-shell--fragment-location-at-position position t))
         (local-prompt
          (and (not fragment)
               (emacsvox-agent-shell--local-prompt-location-at-position
                position)))
         (location
          (emacsvox-agent-shell--innermost-block-location
           (if fragment
               ;; Current Agent Shell transcripts describe prompts and
               ;; responses with authoritative fragment metadata.  Avoid a
               ;; transcript-wide search through legacy prompt face runs once
               ;; that local metadata has identified the enclosing block.
               (list table source-block fragment)
             (list
              table source-block
              (or
               local-prompt
               (unless
                   (emacsvox-agent-shell--output-field-position-p position)
                 (emacsvox-agent-shell--prompt-location-at-position
                  position))))))))
    (or
     location
     (when-let* ((fallback
                  (emacsvox-agent-shell--viewport-response-location))
                 ((<= (plist-get fallback :position) position))
                 ((< position (plist-get fallback :end))))
       fallback))))

(defun emacsvox-agent-shell--fragment-toggle-target ()
  "Return the fragment targeted by the public toggle command at point."
  (or
   (emacsvox-agent-shell--fragment-location-at-position (point))
   (when-let* ((location
                (emacsvox-agent-shell--block-location-at-point))
               (state (plist-get location :state))
               (qualified-id (map-elt state :qualified-id))
               (fragment
                (emacsvox-agent-shell--fragment-location-by-id
                 qualified-id (point))))
     (emacsvox-agent-shell--fragment-location-at-position
      (plist-get fragment :position)))
   (save-excursion
     (when-let* ((match
                  (text-property-search-forward
                   'agent-shell-ui-state nil
                   (lambda (_value state) state))))
       (emacsvox-agent-shell--fragment-location-at-position
        (prop-match-beginning match))))))

(defun emacsvox-agent-shell--fragment-after-toggle (location)
  "Return the current fragment corresponding to pre-toggle LOCATION."
  (when-let* ((state (plist-get location :state))
              (qualified-id (map-elt state :qualified-id))
              (fragment
               (emacsvox-agent-shell--fragment-location-by-id
                qualified-id (plist-get location :position))))
    (emacsvox-agent-shell--fragment-location-at-position
     (plist-get fragment :position))))

(defun emacsvox-agent-shell--block-visibility-facts (location)
  "Return state-change facts for foldable block LOCATION."
  (emacsvox-agent-shell--presentation-facts
   'agent-block 'visibility-changed nil
   (list
    :agent-block-kind
    (emacsvox-agent-shell--normalize-block-type
     (plist-get location :type))
    :visibility (plist-get location :visibility))))

(defun emacsvox-agent-shell--expanded-block-speech (location)
  "Return concise visibility speech for expanded block LOCATION."
  (let* ((type (plist-get location :type))
         (label (plist-get location :label))
         (heading
          (if (eq type 'activity-group)
              (emacsvox-agent-shell--activity-group-speech-label label)
            (or label (emacsvox-agent-shell--block-type-label type)))))
    (format "%s, expanded." heading)))

(defun emacsvox-agent-shell--call-toggle-fragment
    (original-function arguments interactive-p)
  "Call fragment toggle ORIGINAL-FUNCTION with ARGUMENTS.

When INTERACTIVE-P is non-nil, announce a resulting visibility change."
  (let ((before
         (and
          interactive-p
          (emacsvox-agent-shell--fragment-toggle-target)))
        result)
    (setq result (apply original-function arguments))
    (when (and interactive-p before)
      (when-let* ((after
                   (emacsvox-agent-shell--fragment-after-toggle before))
                  (visibility (plist-get after :visibility))
                  ((not (eq visibility
                            (plist-get before :visibility)))))
        (let ((facts
               (emacsvox-agent-shell--block-visibility-facts after))
              (icon
               (if (eq visibility 'folded)
                   'close-object
                 'open-object))
              (content
               (and
                (eq visibility 'expanded)
                (emacsvox-agent-shell--expanded-block-speech after))))
          (if content
              (emacsvox-agent-shell--submit-text-feedback
               content facts 'state-change icon)
            (emacsvox-agent-shell--submit-icon-feedback
             facts 'state-change icon)))))
    result))

(defun emacsvox-agent-shell--toggle-fragment-around
    (original-function &rest arguments)
  "Announce a public interactive fragment visibility change."
  (emacsvox-agent-shell--call-toggle-fragment
   original-function arguments
   (ems-interactive-p 'agent-shell-ui-toggle-fragment)))

(defun emacsvox-agent-shell--toggle-fragment-action-around
    (original-function &rest arguments)
  "Announce a fragment toggle invoked by an inline RET or mouse action."
  (let ((target ems--interactive-fn-name))
    (emacsvox-agent-shell--call-toggle-fragment
     original-function arguments
     (and (functionp target) (ems-interactive-p target)))))

(defun emacsvox-agent-shell--toggle-all-fragments-around
    (original-function &rest arguments)
  "Announce the result of interactively toggling all fragments."
  (let ((interactive-p
         (ems-interactive-p 'agent-shell-ui-toggle-all-fragments))
        result)
    (setq result (apply original-function arguments))
    (when interactive-p
      (when-let* ((visibility
                   (pcase agent-shell-ui--fold-toggle-state
                     ('collapsed 'folded)
                     ('expanded 'expanded))))
        (emacsvox-agent-shell--submit-text-feedback
         (format "All Agent Shell blocks %s"
                 (if (eq visibility 'folded) "collapsed" "expanded"))
         (emacsvox-agent-shell--presentation-facts
          'agent-session 'visibility-changed nil
          (list :visibility visibility))
         'state-change
         (if (eq visibility 'folded) 'close-object 'open-object))))
    result))

(defun emacsvox-agent-shell--source-block-at-point ()
  "Return the semantic source block containing point, or signal an error."
  (let ((location (emacsvox-agent-shell--block-location-at-point)))
    (unless (eq (plist-get location :type) 'source-block)
      (user-error "Not in a rendered source block"))
    location))

(defun emacsvox-agent-shell-speak-source-block ()
  "Read the complete rendered Markdown source block at point."
  (interactive)
  (let ((location (emacsvox-agent-shell--source-block-at-point)))
    (tts-stop)
    (emacsvox-agent-shell--submit-text-feedback
     (emacsvox-agent-shell--source-block-speech location)
     (emacsvox-agent-shell--block-facts
      'source-block 'agent-content-inspected
      (when-let* ((language (plist-get location :language)))
        (list :agent-source-language language)))
     'inspection 'item)))

(defun emacsvox-agent-shell-copy-source-block ()
  "Copy the rendered Markdown source block at point using agent-shell."
  (interactive)
  (let ((location (emacsvox-agent-shell--source-block-at-point)))
    (prog1
        (let ((inhibit-message t))
          (agent-shell-copy-source-block-at-point
           (plist-get location :position)))
      (emacsvox-agent-shell--submit-text-feedback
       "Copied source block"
       (emacsvox-agent-shell--block-facts
        'source-block 'agent-content-copied
        (when-let* ((language (plist-get location :language)))
          (list :agent-source-language language)))
       'state-change 'yank-object))))

(defun emacsvox-agent-shell--yank-dwim-around (original &rest arguments)
  "Let an interactive Agent Shell text paste use normal yank feedback."
  (if (ems-interactive-p 'agent-shell-yank-dwim)
      (let ((ems--interactive-fn-name 'yank))
        (apply original arguments))
    (apply original arguments)))

(defun emacsvox-agent-shell--literal-character-input-p ()
  "Return non-nil when this command key should insert at an editable prompt."
  (and (integerp last-command-event)
       (> (length (this-command-keys-vector)) 0)
       (eq (key-binding (this-command-keys-vector)) this-command)
       (or (derived-mode-p 'agent-shell-viewport-edit-mode)
           (and (derived-mode-p 'agent-shell-mode)
                (agent-shell--point-in-live-input-p)))))

(defun emacsvox-agent-shell--navigate-block-at-point (direction &optional type)
  "Navigate in DIRECTION, preserving literal input at an editable prompt.
Use semantic TYPE when supplied, otherwise infer it from the block at point."
  (if (emacsvox-agent-shell--literal-character-input-p)
      (self-insert-command 1)
    (let* ((location
            (pcase type
              ('agent-response
               ;; Code and tables are nested destinations; response movement
               ;; must skip their enclosing answer as a whole.
               (let ((response
                      (or (emacsvox-agent-shell--fragment-location-at-position
                           (point) t)
                          (emacsvox-agent-shell--viewport-response-location))))
                 (when (and response
                            (<= (plist-get response :position) (point))
                            (< (point) (plist-get response :end)))
                   response)))
              ('table
               (emacsvox-agent-shell--table-location-at-position (point)))
              ('heading
               (emacsvox-agent-shell--heading-location-at-position (point)))
              ('link
               (emacsvox-agent-shell--link-location-at-position (point)))
              (_ (emacsvox-agent-shell--block-location-at-point))))
           (type (or type (plist-get location :type))))
      (if type
          (progn
            (setq emacsvox-agent-shell--block-navigation-type type)
            (when (emacsvox-agent-shell--jump-block-of-type
                   type direction (plist-get location :position))
              (emacsvox-agent-shell--activate-block-repeat-map)))
        (emacsvox-agent-shell--select-and-jump-block
         direction
         (pcase (cons direction last-command-event)
           (`(forward . ,?\]) "]")
           (`(backward . ,?\[) "[")))))))

(defvar emacsvox-agent-shell--block-repeat-map
  (make-sparse-keymap)
  "Temporary map for repeating semantic block navigation.")

(defun emacsvox-agent-shell--install-block-repeat-bindings ()
  "Install reload-safe semantic block repeat keys."
  (define-key emacsvox-agent-shell--block-repeat-map (kbd "]")
              #'emacsvox-agent-shell-repeat-next-block)
  (define-key emacsvox-agent-shell--block-repeat-map (kbd "[")
              #'emacsvox-agent-shell-repeat-previous-block))

(defun emacsvox-agent-shell--activate-block-repeat-map ()
  "Activate temporary bracket bindings for semantic block repetition."
  (set-transient-map emacsvox-agent-shell--block-repeat-map t))

(defun emacsvox-agent-shell--select-and-jump-block
    (direction &optional accept-key)
  "Select a block type and move in DIRECTION.
When ACCEPT-KEY is non-nil, let it accept the selector's default."
  (when (emacsvox-agent-shell--jump-block-of-type
         (emacsvox-agent-shell--read-block-type accept-key) direction)
    (emacsvox-agent-shell--activate-block-repeat-map)))

(defun emacsvox-agent-shell-next-block-of-type ()
  "Select a semantic block type and move to its next occurrence."
  (interactive)
  (emacsvox-agent-shell--select-and-jump-block 'forward))

(defun emacsvox-agent-shell-previous-block-of-type ()
  "Select a semantic block type and move to its previous occurrence."
  (interactive)
  (emacsvox-agent-shell--select-and-jump-block 'backward))

(defun emacsvox-agent-shell-next-block-at-point ()
  "Move to the next block matching the semantic block at point.
When invoked by `]' at an editable prompt, insert that character instead."
  (interactive)
  (emacsvox-agent-shell--navigate-block-at-point 'forward))

(defun emacsvox-agent-shell-previous-block-at-point ()
  "Move to the previous block matching the semantic block at point.
When invoked by `[' at an editable prompt, insert that character instead."
  (interactive)
  (emacsvox-agent-shell--navigate-block-at-point 'backward))

(defun emacsvox-agent-shell-next-table ()
  "Move to the next rendered Markdown table and announce it.
At an editable prompt, a directly bound character key inserts itself instead."
  (interactive)
  (emacsvox-agent-shell--navigate-block-at-point 'forward 'table))

(defun emacsvox-agent-shell-previous-table ()
  "Move to the previous rendered Markdown table and announce it.
At an editable prompt, a directly bound character key inserts itself instead."
  (interactive)
  (emacsvox-agent-shell--navigate-block-at-point 'backward 'table))

(defun emacsvox-agent-shell-next-response ()
  "Move to the next agent response and announce its body.
At an editable prompt, a directly bound character key inserts itself instead."
  (interactive)
  (emacsvox-agent-shell--navigate-block-at-point 'forward 'agent-response))

(defun emacsvox-agent-shell-previous-response ()
  "Move to the previous agent response and announce its body.
At an editable prompt, a directly bound character key inserts itself instead."
  (interactive)
  (emacsvox-agent-shell--navigate-block-at-point 'backward 'agent-response))

(defun emacsvox-agent-shell-next-heading ()
  "Move to the next visible Markdown heading.
At an editable prompt, a directly bound character key inserts itself instead."
  (interactive)
  (emacsvox-agent-shell--navigate-block-at-point 'forward 'heading))

(defun emacsvox-agent-shell-previous-heading ()
  "Move to the previous visible Markdown heading.
At an editable prompt, a directly bound character key inserts itself instead."
  (interactive)
  (emacsvox-agent-shell--navigate-block-at-point 'backward 'heading))

(defun emacsvox-agent-shell-next-source-block ()
  "Move to the next source block and announce its language and line count.
At an editable prompt, a directly bound character key inserts itself instead."
  (interactive)
  (emacsvox-agent-shell--navigate-block-at-point 'forward 'source-block))

(defun emacsvox-agent-shell-previous-source-block ()
  "Move to the previous source block and announce its language and line count.
At an editable prompt, a directly bound character key inserts itself instead."
  (interactive)
  (emacsvox-agent-shell--navigate-block-at-point 'backward 'source-block))

(defun emacsvox-agent-shell-next-user-prompt ()
  "Move to the next submitted user prompt.
At an editable prompt, a directly bound character key inserts itself instead."
  (interactive)
  (emacsvox-agent-shell--navigate-block-at-point 'forward 'user-prompt))

(defun emacsvox-agent-shell-previous-user-prompt ()
  "Move to the previous submitted user prompt.
At an editable prompt, a directly bound character key inserts itself instead."
  (interactive)
  (emacsvox-agent-shell--navigate-block-at-point 'backward 'user-prompt))

(defun emacsvox-agent-shell-next-link ()
  "Move to the next visible rendered link.
At an editable prompt, a directly bound character key inserts itself instead."
  (interactive)
  (emacsvox-agent-shell--navigate-block-at-point 'forward 'link))

(defun emacsvox-agent-shell-previous-link ()
  "Move to the previous visible rendered link.
At an editable prompt, a directly bound character key inserts itself instead."
  (interactive)
  (emacsvox-agent-shell--navigate-block-at-point 'backward 'link))

(defun emacsvox-agent-shell-next-error ()
  "Move to the next error or failed tool call.
At an editable prompt, a directly bound character key inserts itself instead."
  (interactive)
  (emacsvox-agent-shell--navigate-block-at-point 'forward 'error))

(defun emacsvox-agent-shell-previous-error ()
  "Move to the previous error or failed tool call.
At an editable prompt, a directly bound character key inserts itself instead."
  (interactive)
  (emacsvox-agent-shell--navigate-block-at-point 'backward 'error))

(defun emacsvox-agent-shell-repeat-next-block ()
  "Move to the next occurrence of the selected semantic block type."
  (interactive)
  (when (emacsvox-agent-shell--jump-block-of-type
         emacsvox-agent-shell--block-navigation-type 'forward)
    (emacsvox-agent-shell--activate-block-repeat-map)))

(defun emacsvox-agent-shell-repeat-previous-block ()
  "Move to the previous occurrence of the selected semantic block type."
  (interactive)
  (when (emacsvox-agent-shell--jump-block-of-type
         emacsvox-agent-shell--block-navigation-type 'backward)
    (emacsvox-agent-shell--activate-block-repeat-map)))

(provide 'emacsvox-agent-shell-navigation)

;;; emacsvox-agent-shell-navigation.el ends here
