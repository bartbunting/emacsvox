;;; emacsvox-agent-shell-render.el --- Interpret Agent Shell renderings  -*- lexical-binding: t; -*-

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
;;
;; Internal renderer compatibility boundary for `emacsvox-agent-shell'.
;; Interpret strings, text properties, and optional current-buffer fragment
;; metadata without loading Agent Shell or installing speech, advice, or hooks.
;; The main integration owns context capture, customization, delivery, and
;; activation/cleanup.  Private helper names remain available through it.

;;; Code:

(require 'cl-lib)
(cl-declaim (optimize (safety 0) (speed 3)))
(require 'map)
(require 'seq)
(require 'subr-x)

;;; Speech copies

(defun emacsvox-agent-shell--speech-copy-without-yank-handler (text)
  "Return TEXT prepared for speech without invoking a clipboard handler.
Current Agent Shell strips presentation properties through its buffer copy
filter.  Releases before 2026-08-31 instead attached `yank-handler' to rendered
Markdown.  Bypass that legacy handler so `tts-speak' retains faces and other
aural display properties while copying TEXT into its private scratch buffer."
  (if (and (stringp text)
           (> (length text) 0)
           (text-property-not-all 0 (length text) 'yank-handler nil text))
      (let ((copy (copy-sequence text)))
        (remove-text-properties 0 (length copy) '(yank-handler nil) copy)
        copy)
    text))


;;; Prompt and chat label properties

(defun emacsvox-agent-shell--face-spec-includes-p (spec face)
  "Return non-nil when face SPEC contains FACE."
  (cond
   ((eq spec face) t)
   ((consp spec)
    (or (emacsvox-agent-shell--face-spec-includes-p (car spec) face)
        (emacsvox-agent-shell--face-spec-includes-p (cdr spec) face)))
   (t nil)))

(defun emacsvox-agent-shell--prompt-face-spec-p (spec)
  "Return non-nil when face SPEC denotes an Agent Shell prompt."
  (or
   (emacsvox-agent-shell--face-spec-includes-p spec 'agent-shell-prompt)
   (emacsvox-agent-shell--face-spec-includes-p
    spec 'comint-highlight-prompt)))

(defun emacsvox-agent-shell--chat-label-rendering (rendered)
  "Return semantic label information from chat overlay RENDERED text.
The car is the first nonblank display line, preserving its properties.  The
cdr is non-nil when later nonblank content belongs to the same rendering, as
with Agent Shell's live input marker."
  (when (stringp rendered)
    ;; Agent Shell gives newline comment syntax, so POSIX `space' character
    ;; classes are not stable in its buffers.  Match display whitespace
    ;; explicitly to keep overlay parsing independent of the syntax table.
    (when-let* ((start (string-match "[^ \t\n\r]" rendered)))
      (let* ((length (length rendered))
             (line-end (or (string-match "[\n\r]" rendered start) length))
             (label (string-trim (substring rendered start line-end)))
             (trailing-p
              (and (< line-end length)
                   (string-match-p
                    "[^ \t\n\r]" rendered (1+ line-end)))))
        (unless (string-empty-p label)
          (cons label trailing-p))))))

(defun emacsvox-agent-shell--prompt-face-at-p (text position)
  "Return non-nil when TEXT at POSITION carries an agent-shell prompt face."
  (or
   (emacsvox-agent-shell--prompt-face-spec-p
    (get-text-property position 'face text))
   (emacsvox-agent-shell--prompt-face-spec-p
    (get-text-property position 'font-lock-face text))))

(defun emacsvox-agent-shell--without-leading-chat-prompt (text)
  "Return TEXT without a leading prompt replaced by a visible chat label."
  (let ((position 0)
        (length (length text)))
    (while (and (< position length)
                (memq (aref text position) '(?\s ?\t ?\n ?\r)))
      (setq position (1+ position)))
    (let ((prompt-start position))
      (while (and (< position length)
                  (emacsvox-agent-shell--prompt-face-at-p text position))
        (setq position (next-property-change position text length)))
      (if (= position prompt-start)
          text
        (while (and (< position length)
                    (memq (aref text position) '(?\s ?\t ?\n ?\r)))
          (setq position (1+ position)))
        (substring text position)))))


;;; Status compatibility

;; Agent-shell exposes a customizable renderer but no semantic status text
;; property.  Keep this glyph/face compatibility adapter isolated here; the
;; rendered-plan fixture test detects upstream rendering drift.
(defconst emacsvox-agent-shell--status-icon-contexts
  '((?◔ agent-shell-pending pending)
    (?◔ agent-shell-warning in-progress)
    (?… agent-shell-pending pending)
    (?… agent-shell-warning in-progress)
    (?✓ agent-shell-success completed)
    (?✗ agent-shell-error failed))
  "Rendered icon, face, and semantic status triples used for speech.
Both current and legacy Agent Shell wait icons are recognized.")

(defun emacsvox-agent-shell--status-at (text position)
  "Return the semantic status represented at POSITION in TEXT."
  (let ((character (aref text position))
        (face (get-text-property position 'face text))
        (font-lock-face
         (get-text-property position 'font-lock-face text)))
    (cl-loop
     for (icon status-face status)
     in emacsvox-agent-shell--status-icon-contexts
     when (and (= character icon)
               (or
                (emacsvox-agent-shell--face-spec-includes-p
                 face status-face)
                (emacsvox-agent-shell--face-spec-includes-p
                 font-lock-face status-face)))
     return status)))


;;; Semantic fragment classification

(defun emacsvox-agent-shell--fragment-has-renderer-thought-face-p
    (qualified-id position &optional text)
  "Return non-nil when QUALIFIED-ID has renderer-owned thought styling.
POSITION identifies the fragment in the current buffer, or in TEXT when that
string is non-nil.  ACP content cannot manufacture these Emacs text properties."
  (let* ((object text)
         (minimum (if text 0 (point-min)))
         (maximum (if text (length text) (point-max))))
    (when (and (integer-or-marker-p position)
               (< position maximum)
               (equal
                qualified-id
                (map-elt
                 (get-text-property
                  position 'agent-shell-ui-state object)
                 :qualified-id)))
      (let* ((start
              (or
               (previous-single-property-change
                (min (1+ position) maximum)
                'agent-shell-ui-state object minimum)
               minimum))
             (end
              (or
               (next-single-property-change
                position 'agent-shell-ui-state object maximum)
               maximum))
             (cursor start)
             found)
        (while (and (< cursor end) (not found))
          (setq found
                (seq-some
                 (lambda (face)
                   (or
                    (emacsvox-agent-shell--face-spec-includes-p
                     (get-text-property cursor 'face object) face)
                    (emacsvox-agent-shell--face-spec-includes-p
                     (get-text-property cursor 'font-lock-face object) face)))
                 '(agent-shell-thought-body agent-shell-section-heading)))
          (setq cursor
                (min
                 (or (next-single-property-change
                      cursor 'face object end)
                     end)
                 (or (next-single-property-change
                      cursor 'font-lock-face object end)
                     end))))
        found))))

(defun emacsvox-agent-shell--semantic-block-type
    (qualified-id state &optional position text)
  "Classify QUALIFIED-ID and renderer STATE for navigation.
POSITION identifies the fragment in the current buffer, or in TEXT.  Agent
Shell currently exposes no public semantic type, so keep compatibility
inference isolated here and let renderer-owned group provenance beat IDs."
  (cond
   ;; Group headers and members are renderer-owned structure.  A provider can
   ;; choose a tool ID that resembles any reserved suffix, so grouped members
   ;; default to tools.  Thoughts are the one legitimate grouped content type;
   ;; accept those only when Agent Shell applied its own thought styling.
   ((eq (map-elt state :kind) 'group) 'activity-group)
   ((map-elt state :group-id)
    (if (and (stringp qualified-id)
             (string-match-p "agent_thought_chunk\\'" qualified-id)
             (emacsvox-agent-shell--fragment-has-renderer-thought-face-p
              qualified-id position text))
        'thought
      'tool-call))
   ((and (stringp qualified-id)
         (string-match-p "agent_message_chunk\\'" qualified-id))
    'agent-response)
   ((and (stringp qualified-id)
         (string-match-p "user_message_chunk\\'" qualified-id))
    'user-prompt)
   ((and (stringp qualified-id)
         (string-match-p "agent_thought_chunk\\'" qualified-id))
    'thought)
   ((and (stringp qualified-id)
         (string-match-p "permission-" qualified-id))
    'permission)
   ((and (stringp qualified-id)
         (string-match-p "-plan\\'" qualified-id))
    'plan)
   ((and (stringp qualified-id)
         (string-match-p
          "\\(?:failed-\\|Error\\|out-of-turn-acp-bug\\|[Uu]nhandled\\)"
          qualified-id))
    'error)
   (t 'other)))


;;; Decorative renderer controls

(defun emacsvox-agent-shell--thought-heading-start (text start end)
  "Return the semantic thought heading start in TEXT from START to END.
Agent Shell places its configurable thought-process icon before text carrying
the `agent-shell-section-heading' face.  Restrict this compatibility inference
to a semantic thought fragment so ordinary faced text is never suppressed."
  (let* ((state (get-text-property start 'agent-shell-ui-state text))
         (qualified-id (and state (map-elt state :qualified-id))))
    (when (eq (emacsvox-agent-shell--semantic-block-type
               qualified-id state start text)
              'thought)
      (let ((position start))
        (while
            (and
             (< position end)
             (not
              (or
               (emacsvox-agent-shell--face-spec-includes-p
                (get-text-property position 'face text)
                'agent-shell-section-heading)
               (emacsvox-agent-shell--face-spec-includes-p
                (get-text-property position 'font-lock-face text)
                'agent-shell-section-heading))))
          (setq
           position
           (min
            (or (next-single-property-change
                 position 'face text end)
                end)
            (or (next-single-property-change
                 position 'font-lock-face text end)
                end))))
        (and (< position end) position)))))

(defun emacsvox-agent-shell--remove-visual-chrome-for-speech (text)
  "Return TEXT without Agent Shell's decorative fragment prefixes.
Remove property-scoped fold indicators from every fragment.  For semantic
thought fragments, also remove the configurable icon before the faced heading.
Rendered source-block copy controls are likewise omitted from continuous
speech; item navigation announces their action semantically.
Only the returned speech copy changes; pointwise character review still names
the original characters in the buffer."
  (let ((position 0)
        (length (length text))
        removals)
    (while (< position length)
      (let* ((section
              (get-text-property position 'agent-shell-ui-section text))
             (source-copy
              (get-text-property
               position 'agent-shell-markdown-source-block-copy text))
             (next
              (min
               (or
                (next-single-property-change
                 position 'agent-shell-ui-section text length)
                length)
               (or
                (next-single-property-change
                 position 'agent-shell-markdown-source-block-copy text length)
                length))))
        (if source-copy
            (push (cons position next) removals)
          (pcase section
            ('indicator
             (push (cons position next) removals))
            ('label-left
             (when-let* ((heading
                          (emacsvox-agent-shell--thought-heading-start
                           text position next))
                         ((> heading position)))
               (push (cons position heading) removals)))))
        (setq position next)))
    (if (null removals)
        text
      (let ((source-position 0)
            parts)
        (dolist (range (nreverse removals))
          (when (< source-position (car range))
            (push (substring text source-position (car range)) parts))
          (setq source-position (max source-position (cdr range))))
        (when (< source-position length)
          (push (substring text source-position) parts))
        (apply #'concat (nreverse parts))))))


;;; Answer body extraction

(defun emacsvox-agent-shell--string-section-range
    (text start end section)
  "Return SECTION's text-property range in TEXT between START and END."
  (let ((position start)
        result)
    (while (and (< position end) (not result))
      (let ((next
             (or (next-single-property-change
                  position 'agent-shell-ui-section text end)
                 end)))
        (when (eq (get-text-property
                   position 'agent-shell-ui-section text)
                  section)
          (setq result (cons position next)))
        (setq position next)))
    result))

(defun emacsvox-agent-shell--agent-answer-from-response (response)
  "Return only rendered agent answer bodies from interaction RESPONSE.
Preserve their speech properties and order while excluding thoughts, plans,
tools, and other semantic fragments.  Use the complete text as a compatibility
fallback only when RESPONSE has no agent-shell semantic fragment properties."
  (when (stringp response)
    (let ((position 0)
          (end (length response))
          semantic-p
          bodies)
      (while (< position end)
        (let* ((state
                (get-text-property
                 position 'agent-shell-ui-state response))
               (next
                (or (next-single-property-change
                     position 'agent-shell-ui-state response end)
                    end)))
          (when state
            (setq semantic-p t)
            (when
                (eq
                 (emacsvox-agent-shell--semantic-block-type
                  (map-elt state :qualified-id) state position response)
                 'agent-response)
              (when-let* ((body-range
                           (emacsvox-agent-shell--string-section-range
                            response position next 'body))
                          (body
                           (string-trim
                            (substring
                             response
                             (car body-range) (cdr body-range))))
                          ((not (string-empty-p body))))
                (push body bodies))))
          (setq position next)))
      (cond
       (bodies (string-join (nreverse bodies) "\n"))
       ((not semantic-p)
        (let ((plain (string-trim response)))
          (unless (string-empty-p plain) plain)))))))

(provide 'emacsvox-agent-shell-render)
;;; emacsvox-agent-shell-render.el ends here
