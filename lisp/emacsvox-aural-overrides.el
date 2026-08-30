;;; emacsvox-aural-overrides.el --- Spoken presentation override manager -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: Emacsvox contributors
;; Maintainer: Emacsvox contributors
;; Keywords: accessibility, multimedia
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

;; Present personal, session, and source-buffer rules as one accessible view.
;; This manager does not introduce another presentation layer: it explains
;; and mutates the existing strongest three layers in the aural cascade.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'tabulated-list)
(require 'emacsvox-aural-schemes)
(require 'emacsvox-aural-ui)
(require 'emacsvox-aural-inspection)
(require 'emacsvox-aural-preview)
(require 'emacsvox-aural-validation)
(require 'emacsvox-aural-description)

(declare-function emacsvox-aural-editor-open-rule
                  "emacsvox-aural-editor"
                  (scope rule-id &optional source-buffer))
(declare-function emacsvox-speak-help "emacsvox-speak" ())

(cl-defstruct
    (emacsvox-aural-override-record
     (:constructor emacsvox-aural-overrides--make-record))
  "One declarative override and its manager provenance."
  key scope rule compiled source-buffer)

(defvar-local emacsvox-aural-overrides--records
  (make-hash-table :test #'equal)
  "Displayed override records keyed by tabulated row identifier.")

(defvar-local emacsvox-aural-overrides-filter-scope nil
  "Optional scope displayed by the current override manager.")

(defvar-local emacsvox-aural-overrides-filter-module nil
  "Optional module displayed by the current override manager.")

(defvar-local emacsvox-aural-overrides-filter-role nil
  "Optional semantic role displayed by the current override manager.")

(defun emacsvox-aural-overrides--source-buffer ()
  "Return the ordinary source attached to the current manager."
  (emacsvox-aural-inspection-source-buffer))

(defun emacsvox-aural-overrides--scope-rules (scope source)
  "Return raw override rules for SCOPE and ordinary SOURCE."
  (pcase scope
    ('personal emacsvox-aural-user-rules)
    ('session emacsvox-aural-session-rules)
    ('buffer
     (and
      (buffer-live-p source)
      (buffer-local-value 'emacsvox-aural-buffer-rules source)))
    (_ (error "Unknown aural override scope: %S" scope))))

(defun emacsvox-aural-overrides--origin (scope)
  "Return compiled rule origin for override SCOPE."
  (pcase scope
    ('personal 'user)
    ('session 'session)
    ('buffer 'buffer)
    (_ (error "Unknown aural override scope: %S" scope))))

(defun emacsvox-aural-overrides--source-label (scope source)
  "Return diagnostic source label for SCOPE and SOURCE."
  (pcase scope
    ('personal emacsvox-aural-schemes-file)
    ('session "session")
    ('buffer
     (format
     "buffer:%s"
      (if (buffer-live-p source)
          (buffer-name source)
        "unavailable")))))

(defun emacsvox-aural-overrides--collect (&optional source)
  "Return personal, session, and SOURCE-buffer override records."
  (let ((source (or source (emacsvox-aural-overrides--source-buffer)))
        records)
    (dolist (scope '(personal session buffer))
      (cl-loop
       for rule in (emacsvox-aural-overrides--scope-rules scope source)
       for index from 0
       for id = (plist-get rule :id)
       for compiled =
       (emacsvox-aural-compile-rule
        rule
        (emacsvox-aural-overrides--origin scope)
        index
        (emacsvox-aural-overrides--source-label scope source))
       do
       (push
        (emacsvox-aural-overrides--make-record
         :key (list scope id)
         :scope scope
         :rule (copy-tree rule)
         :compiled compiled
         :source-buffer source)
        records)))
    (nreverse records)))

(defun emacsvox-aural-overrides-status (&optional source)
  "Return concise counts for override layers relevant to SOURCE."
  (let* ((source
          (and
           source
           (emacsvox-aural-inspection-source-buffer source)))
         (personal (length emacsvox-aural-user-rules))
         (session (length emacsvox-aural-session-rules))
         (buffer
          (if source
              (length
               (buffer-local-value
                'emacsvox-aural-buffer-rules source))
            0)))
    (format
     "%d personal, %d session, %d this buffer"
     personal session buffer)))

(defun emacsvox-aural-overrides--enabled-p (record)
  "Return non-nil when override RECORD is enabled."
  (let ((rule (emacsvox-aural-override-record-rule record)))
    (if (plist-member rule :enabled)
        (plist-get rule :enabled)
      t)))

(defun emacsvox-aural-overrides--action-summary (action)
  "Return concise presentation text for declarative ACTION."
  (pcase (plist-get action :kind)
    ('cue
     (format
      "earcon %s"
      (emacsvox-aural-humanize
       (or (plist-get action :cue)
           (plist-get action :name)))))
    ('speech
     (format
      "speech %s"
      (or
       (plist-get action :text)
       (plist-get action :text-template)
       "template")))
    ('pause
     (format "pause %s" (plist-get action :duration)))
    ('tone
     (format
      "tone %s"
      (emacsvox-aural-humanize
       (plist-get action :tone))))
    (_ "action")))

(defun emacsvox-aural-overrides--actions-summary (actions)
  "Return concise presentation text for declarative ACTIONS."
  (if actions
      (mapconcat
       #'emacsvox-aural-overrides--action-summary
       actions ", ")
    "nothing"))

(defun emacsvox-aural-overrides--phase-summary (name phase)
  "Return concise change text for phase NAME and declarative PHASE."
  (cond
   ((null phase) nil)
   ((and (listp phase)
         (or (null phase) (listp (car phase))))
    (format
     "%s add %s"
     name
     (emacsvox-aural-overrides--actions-summary phase)))
   ((plist-get phase :suppress)
    (format "suppress %s phase" name))
   (t
    (let (parts)
      (when (plist-member phase :replace)
        (push
         (format
          "replace with %s"
          (emacsvox-aural-overrides--actions-summary
           (plist-get phase :replace)))
         parts))
      (when-let* ((ids (plist-get phase :remove)))
        (push
         (format
          "remove %s"
          (mapconcat
           #'emacsvox-aural-humanize ids ", "))
         parts))
      (when-let* ((actions (plist-get phase :prepend)))
        (push
         (format
          "add %s"
          (emacsvox-aural-overrides--actions-summary actions))
         parts))
      (when-let* ((actions (plist-get phase :append)))
        (push
         (format
          "add %s"
          (emacsvox-aural-overrides--actions-summary actions))
         parts))
      (format
       "%s %s"
       name
       (if parts
           (string-join (nreverse parts) "; ")
         "operations"))))))

(defun emacsvox-aural-overrides--content-summary (content)
  "Return concise change text for declarative CONTENT."
  (when content
    (let (parts)
      (when (plist-get content :suppress)
        (push "suppress content" parts))
      (when (plist-member content :speak)
        (push
         (format "speak %s" (plist-get content :speak))
         parts))
      (when (plist-member content :voice)
        (push
         (format
          "voice %s"
          (emacsvox-aural-humanize
           (or (plist-get content :voice) 'default)))
         parts))
      (when (plist-member content :volume)
        (push
         (format "volume %s" (plist-get content :volume))
         parts))
      (when (plist-member content :space)
        (push
         (format "space %S" (plist-get content :space))
         parts))
      (string-join (nreverse parts) ", "))))

(defun emacsvox-aural-overrides--change-summary (record)
  "Return concise presentation change made by override RECORD."
  (let* ((render
          (plist-get
           (emacsvox-aural-override-record-rule record)
           :render))
         (parts
          (delq
           nil
           (list
            (emacsvox-aural-overrides--phase-summary
             "before" (plist-get render :before))
            (emacsvox-aural-overrides--content-summary
             (plist-get render :content))
            (emacsvox-aural-overrides--phase-summary
             "after" (plist-get render :after))))))
    (if parts
        (string-join parts "; ")
      "no presentation change")))

(defun emacsvox-aural-overrides--target-summary (record)
  "Return concise selector text for override RECORD."
  (emacsvox-aural-describe-selector
   (emacsvox-aural-rule-selector
    (emacsvox-aural-override-record-compiled record))))

(defun emacsvox-aural-overrides--current-input (&optional source)
  "Return normalized source input for SOURCE, or nil."
  (let ((source (or source (emacsvox-aural-overrides--source-buffer))))
    (when (buffer-live-p source)
      (with-current-buffer source
        (emacsvox-aural-normalize-input
         (emacsvox-aural-facts-at-point)
         (emacsvox-aural-context-at-point))))))

(defun emacsvox-aural-overrides--here-status (record input)
  "Return current-point match status for RECORD against normalized INPUT."
  (if (null input)
      "no source"
    (let* ((enabled (emacsvox-aural-overrides--enabled-p record))
           (compiled
            (emacsvox-aural-override-record-compiled record))
           (candidate
            (if enabled
                compiled
              (let ((copy (copy-emacsvox-aural-rule compiled)))
                (setf (emacsvox-aural-rule-enabled copy) t)
                copy))))
      (cond
       ((emacsvox-aural-rule-matches-p candidate input)
        (if enabled "matches here" "would match"))
       (t "not here")))))

(defun emacsvox-aural-overrides--visible-p (record)
  "Return non-nil when RECORD passes the current manager filters."
  (let* ((rule (emacsvox-aural-override-record-rule record))
         (match (plist-get rule :match)))
    (and
     (or
      (null emacsvox-aural-overrides-filter-scope)
      (eq
       emacsvox-aural-overrides-filter-scope
       (emacsvox-aural-override-record-scope record)))
     (or
      (null emacsvox-aural-overrides-filter-module)
      (eq
       emacsvox-aural-overrides-filter-module
       (plist-get match :module)))
     (or
      (null emacsvox-aural-overrides-filter-role)
      (eq
       emacsvox-aural-overrides-filter-role
       (plist-get match :role))))))

(defun emacsvox-aural-overrides--row (record input)
  "Return tabulated row for override RECORD and current normalized INPUT."
  (let ((scope (emacsvox-aural-override-record-scope record))
        (rule (emacsvox-aural-override-record-rule record)))
    (list
     (emacsvox-aural-override-record-key record)
     (vector
      (symbol-name scope)
      (symbol-name (plist-get rule :id))
      (emacsvox-aural-overrides--target-summary record)
      (emacsvox-aural-overrides--change-summary record)
      (if (emacsvox-aural-overrides--enabled-p record)
          "enabled"
        "disabled")
      (emacsvox-aural-overrides--here-status record input)))))

(defun emacsvox-aural-overrides--set-entries ()
  "Populate the current Presentation Overrides manager."
  (let* ((source (emacsvox-aural-overrides--source-buffer))
         (input (emacsvox-aural-overrides--current-input source))
         (records
          (cl-remove-if-not
           #'emacsvox-aural-overrides--visible-p
           (emacsvox-aural-overrides--collect source))))
    (setq
     emacsvox-aural-overrides--records
     (make-hash-table :test #'equal))
    (dolist (record records)
      (puthash
       (emacsvox-aural-override-record-key record)
       record
       emacsvox-aural-overrides--records))
    (setq
     tabulated-list-entries
     (mapcar
      (lambda (record)
        (emacsvox-aural-overrides--row record input))
      records))))

(defun emacsvox-aural-overrides-refresh (&optional key)
  "Refresh overrides, preserving optional row KEY and current column."
  (interactive)
  (emacsvox-aural-ui-refresh-tabulated
   #'emacsvox-aural-overrides--set-entries key))

(defun emacsvox-aural-overrides--record ()
  "Return the override record at point."
  (let ((key
         (or
          (tabulated-list-get-id)
          (user-error "Move to a presentation override first"))))
    (or
     (gethash key emacsvox-aural-overrides--records)
     (user-error "That presentation override is no longer available"))))

(defun emacsvox-aural-overrides-speak-current ()
  "Speak the complete presentation override at point."
  (interactive)
  (let* ((record (emacsvox-aural-overrides--record))
         (rule (emacsvox-aural-override-record-rule record))
         (input
          (emacsvox-aural-overrides--current-input
           (emacsvox-aural-override-record-source-buffer record)))
         (summary
          (format
           "%s scope. %s. Target %s. Changes %s. %s. %s."
           (emacsvox-aural-override-record-scope record)
           (emacsvox-aural-humanize (plist-get rule :id))
           (emacsvox-aural-overrides--target-summary record)
           (emacsvox-aural-overrides--change-summary record)
           (if (emacsvox-aural-overrides--enabled-p record)
               "Enabled"
             "Disabled")
           (emacsvox-aural-overrides--here-status record input))))
    (if (fboundp 'tts-speak)
        (tts-speak summary)
      (message "%s" summary))
    summary))

(defun emacsvox-aural-overrides-speak-current-cell ()
  "Speak the current override column title and value."
  (interactive)
  (emacsvox-aural-ui-speak-current-cell))

(defun emacsvox-aural-overrides-next ()
  "Move to and speak the next presentation override."
  (interactive)
  (emacsvox-aural-ui-move-row
   1 "presentation overrides"))

(defun emacsvox-aural-overrides-previous ()
  "Move to and speak the previous presentation override."
  (interactive)
  (emacsvox-aural-ui-move-row
   -1 "presentation overrides"))

(defun emacsvox-aural-overrides-next-column ()
  "Move right and speak the next override column."
  (interactive)
  (emacsvox-aural-ui-move-column 1))

(defun emacsvox-aural-overrides-previous-column ()
  "Move left and speak the previous override column."
  (interactive)
  (emacsvox-aural-ui-move-column -1))

(defun emacsvox-aural-overrides-describe ()
  "Display and speak complete details for the override at point."
  (interactive)
  (let* ((record (emacsvox-aural-overrides--record))
         (rule (emacsvox-aural-override-record-rule record))
         (scope (emacsvox-aural-override-record-scope record))
         (input
          (emacsvox-aural-overrides--current-input
           (emacsvox-aural-override-record-source-buffer record))))
    (with-help-window (help-buffer)
      (princ
       (format
        "Presentation override: %s\n\n"
        (plist-get rule :id)))
      (princ (format "Scope: %s\n" scope))
      (princ
       (format
        "State: %s\n"
        (if (emacsvox-aural-overrides--enabled-p record)
            "enabled"
          "disabled")))
      (princ
       (format
        "At remembered source: %s\n"
        (emacsvox-aural-overrides--here-status record input)))
      (princ
       (format
        "Target: %s\n"
        (emacsvox-aural-overrides--target-summary record)))
      (princ
       (format
        "Change: %s\n"
        (emacsvox-aural-overrides--change-summary record)))
      (princ
       (format
        "Source: %s\n"
        (emacsvox-aural-overrides--source-label
         scope
         (emacsvox-aural-override-record-source-buffer record))))
      (princ
       (format
        "\nCompatibility baseline: %s\n"
        emacsvox-aural-active-scheme))
      (princ
       "The fixed baseline preserves compatibility. Automatic module presentation and enabled options compose above it; personal, session, and buffer overrides are the final and strongest layers.\n")
      (princ
       "\nPreview resolves the complete current cascade for a representative or matching live example. Removing this override restores the next weaker inherited behavior.\n")
      (princ (format "\nDeclarative data:\n\n%S\n" rule)))
    (when (called-interactively-p 'interactive)
      (emacsvox-aural-overrides-speak-current))
    rule))

(defun emacsvox-aural-overrides-preview ()
  "Preview the selected override in the complete current cascade."
  (interactive)
  (let* ((record (emacsvox-aural-overrides--record))
         (compiled (emacsvox-aural-override-record-compiled record))
         (source (emacsvox-aural-override-record-source-buffer record)))
    (unless (emacsvox-aural-overrides--enabled-p record)
      (user-error "Enable this override before previewing it"))
    (pcase-let*
        ((live-input
         (and
           (buffer-live-p source)
           (with-current-buffer source
             (let* ((facts (emacsvox-aural-facts-at-point))
                    (context (emacsvox-aural-context-at-point))
                    (input
                     (emacsvox-aural-normalize-input facts context)))
               (and
                (emacsvox-aural-rule-matches-p compiled input)
                (cons facts context))))))
         (`(,facts . ,context)
          (or
           live-input
           (pcase-let
               ((`(,representative-facts ,representative-context)
                 (emacsvox-aural-inspection-representative-input
                  compiled)))
             (cons representative-facts representative-context))))
         (facts
          (if (plist-member facts :content)
              facts
            (plist-put (copy-tree facts) :content "Example")))
         (buffer
          (if (buffer-live-p source)
              source
            (current-buffer)))
         (render
          (with-current-buffer buffer
            (emacsvox-aural-resolve
             facts context
             (emacsvox-aural-current-rules context))))
         (concrete
          (with-current-buffer buffer
            (emacsvox-aural-compile-plan render facts context))))
      (emacsvox-aural-preview-play-plan concrete)
      (emacsvox-aural-preview-message
       "Previewing %s in the complete current cascade"
       (emacsvox-aural-rule-id compiled))
      concrete)))

(defun emacsvox-aural-overrides-edit ()
  "Open the selected override in its scoped advanced editor."
  (interactive)
  (let* ((record (emacsvox-aural-overrides--record))
         (rule (emacsvox-aural-override-record-rule record)))
    (require 'emacsvox-aural-editor)
    (emacsvox-aural-editor-open-rule
     (emacsvox-aural-override-record-scope record)
     (plist-get rule :id)
     (emacsvox-aural-override-record-source-buffer record))))

(defun emacsvox-aural-overrides--validate-layer (scope rules)
  "Validate standalone RULES for override SCOPE."
  (emacsvox-aural--compile-rule-list
   rules
   (emacsvox-aural-overrides--origin scope)
   "override-manager"
   t)
  rules)

(defun emacsvox-aural-overrides--validate-active (source)
  "Validate the complete active presentation cascade at SOURCE."
  (let ((buffer
         (if (buffer-live-p source)
             source
           (current-buffer))))
    (with-current-buffer buffer
      (emacsvox-aural-current-rules
       (emacsvox-aural-context-at-point))))
  t)

(defun emacsvox-aural-overrides--commit
    (scope rules source reason)
  "Atomically install RULES in SCOPE for SOURCE, recording REASON."
  (emacsvox-aural-overrides--validate-layer scope rules)
  (pcase scope
    ('personal
     (let ((old emacsvox-aural-user-rules))
       (setq emacsvox-aural-user-rules rules)
       (condition-case error
           (progn
             (emacsvox-aural-overrides--validate-active source)
             (emacsvox-aural-save-user-data)
             (emacsvox-aural-configuration-changed reason))
         (error
          (setq emacsvox-aural-user-rules old)
          (signal (car error) (cdr error))))))
    ('session
     (let ((old emacsvox-aural-session-rules))
       (setq emacsvox-aural-session-rules rules)
       (condition-case error
           (progn
             (emacsvox-aural-overrides--validate-active source)
             (emacsvox-aural-configuration-changed reason))
         (error
          (setq emacsvox-aural-session-rules old)
          (signal (car error) (cdr error))))))
    ('buffer
     (unless (buffer-live-p source)
       (user-error "The override source buffer has been killed"))
     (with-current-buffer source
       (let ((old emacsvox-aural-buffer-rules))
         (setq emacsvox-aural-buffer-rules rules)
         (condition-case error
             (progn
               (emacsvox-aural-overrides--validate-active source)
               (emacsvox-aural-configuration-changed reason))
           (error
            (setq emacsvox-aural-buffer-rules old)
            (signal (car error) (cdr error))))))))
  rules)

(defun emacsvox-aural-overrides--replace-rule
    (rules id replacement)
  "Return RULES with ID replaced by REPLACEMENT."
  (mapcar
   (lambda (rule)
     (if (eq (plist-get rule :id) id)
         (copy-tree replacement)
       rule))
   rules))

(defun emacsvox-aural-overrides-toggle ()
  "Enable or disable the selected override immediately."
  (interactive)
  (let* ((record (emacsvox-aural-overrides--record))
         (scope (emacsvox-aural-override-record-scope record))
         (source (emacsvox-aural-override-record-source-buffer record))
         (rule (copy-tree (emacsvox-aural-override-record-rule record)))
         (id (plist-get rule :id))
         (enabled (not (emacsvox-aural-overrides--enabled-p record)))
         (rules
          (emacsvox-aural-overrides--scope-rules scope source)))
    (setq rule (plist-put rule :enabled enabled))
    (emacsvox-aural-overrides--commit
     scope
     (emacsvox-aural-overrides--replace-rule rules id rule)
     source
     'override-toggled)
    (emacsvox-aural-overrides-refresh (list scope id))
    (emacsvox-aural-ui-refresh-home-if-live)
    (emacsvox-aural-overrides-speak-current)
    enabled))

(defun emacsvox-aural-overrides-delete ()
  "Remove the selected override and restore weaker presentation."
  (interactive)
  (let* ((record (emacsvox-aural-overrides--record))
         (scope (emacsvox-aural-override-record-scope record))
         (source (emacsvox-aural-override-record-source-buffer record))
         (rule (emacsvox-aural-override-record-rule record))
         (id (plist-get rule :id))
         (rules
          (emacsvox-aural-overrides--scope-rules scope source)))
    (unless
        (yes-or-no-p
         (format
          "Remove %s override %s and restore weaker presentation? "
          scope id))
      (user-error "Override removal cancelled"))
    (emacsvox-aural-overrides--commit
     scope
     (cl-remove id rules :key (lambda (entry) (plist-get entry :id)))
     source
     'override-removed)
    (emacsvox-aural-overrides-refresh)
    (emacsvox-aural-ui-refresh-home-if-live)
    (if (tabulated-list-get-id)
        (emacsvox-aural-overrides-speak-current)
      (if (fboundp 'tts-speak)
          (tts-speak "No presentation overrides match the current filter.")
        (message "No presentation overrides match the current filter.")))
    id))

(defun emacsvox-aural-overrides--filter-candidates (records key)
  "Return sorted selector values at KEY across RECORDS."
  (sort
   (delete-dups
    (delq
     nil
     (mapcar
      (lambda (record)
        (plist-get
         (plist-get
          (emacsvox-aural-override-record-rule record)
          :match)
         key))
      records)))
   (lambda (left right)
     (string-lessp (symbol-name left) (symbol-name right)))))

(defun emacsvox-aural-overrides--read-filter
    (prompt candidates current)
  "Read a symbol filter using PROMPT, CANDIDATES, and CURRENT."
  (let* ((all "all")
         (names
          (cons all (mapcar #'symbol-name candidates)))
         (answer
          (completing-read
           prompt names nil 'must-match nil nil
           (if current (symbol-name current) all))))
    (unless (string= answer all)
      (intern answer))))

(defun emacsvox-aural-overrides-filter ()
  "Filter overrides by scope, module, and semantic role."
  (interactive)
  (let ((records (emacsvox-aural-overrides--collect)))
    (setq
     emacsvox-aural-overrides-filter-scope
     (emacsvox-aural-overrides--read-filter
      "Override scope: "
      '(personal session buffer)
      emacsvox-aural-overrides-filter-scope)
     emacsvox-aural-overrides-filter-module
     (emacsvox-aural-overrides--read-filter
      "Target module: "
      (emacsvox-aural-overrides--filter-candidates
       records :module)
      emacsvox-aural-overrides-filter-module)
     emacsvox-aural-overrides-filter-role
     (emacsvox-aural-overrides--read-filter
      "Target semantic role: "
      (emacsvox-aural-overrides--filter-candidates
       records :role)
      emacsvox-aural-overrides-filter-role))
    (emacsvox-aural-overrides-refresh)
    (let ((text
           (format
            "Override filter: scope %s, module %s, role %s. %d shown"
            (or emacsvox-aural-overrides-filter-scope "all")
            (or emacsvox-aural-overrides-filter-module "all")
            (or emacsvox-aural-overrides-filter-role "all")
            (length tabulated-list-entries))))
      (if (fboundp 'tts-speak)
          (tts-speak text)
        (message "%s" text)))
    tabulated-list-entries))

(defun emacsvox-aural-overrides-clear-filter ()
  "Clear every override-manager filter."
  (interactive)
  (setq
   emacsvox-aural-overrides-filter-scope nil
   emacsvox-aural-overrides-filter-module nil
   emacsvox-aural-overrides-filter-role nil)
  (emacsvox-aural-overrides-refresh)
  (let ((text
         (format
          "Override filter cleared. %d shown"
          (length tabulated-list-entries))))
    (if (fboundp 'tts-speak)
        (tts-speak text)
      (message "%s" text))))

(defun emacsvox-aural-overrides-help ()
  "Display and speak Presentation Overrides help."
  (interactive)
  (with-help-window (help-buffer)
    (princ
     (concat
      "Aural Presentation Overrides\n\n"
      "This is one view over the existing personal, session, and remembered\n"
      "source-buffer rule layers. The fixed compatibility baseline and module\n"
      "defaults are followed by enabled Presentation Options, then these\n"
      "stronger override layers.\n"
      "Personal overrides persist, session overrides last until Emacs exits,\n"
      "and buffer overrides last only for the remembered live buffer.\n\n"
      "The Here column says whether a selector matches the remembered source\n"
      "item. Preview uses that live item when possible and otherwise a\n"
      "representative example, resolving the complete current cascade.\n\n"
      "n or down next       p or up previous\n"
      "left/right column    . speak titled cell\n"
      "SPC speak row        RET or e edit in advanced editor\n"
      "x explain            P preview complete current result\n"
      "t enable/disable     d remove and restore weaker behavior\n"
      "f filter             a clear filters\n"
      "g refresh            h aural home\n"
      "q quit\n")))
  (when (fboundp 'emacsvox-speak-help)
    (emacsvox-speak-help)))

(define-derived-mode emacsvox-aural-overrides-mode
    emacsvox-aural-tabulated-mode
  "Aural-Overrides"
  "Spoken manager for personal, session, and buffer presentation overrides."
  (emacsvox-aural-ui-configure-tabulated
   "presentation overrides"
   #'emacsvox-aural-overrides-speak-current
   #'emacsvox-aural-overrides-refresh)
  (setq
   tabulated-list-format
   [("Scope" 12 t)
    ("Rule" 42 t)
    ("Target" 44 t)
    ("Change" 52 t)
    ("State" 10 t)
    ("Here" 14 t)])
  (setq tabulated-list-padding 2)
  (add-hook
   'tabulated-list-revert-hook
   #'emacsvox-aural-overrides--set-entries nil t)
  (tabulated-list-init-header))

(defun emacsvox-aural-overrides-refresh-if-live (&rest _ignored)
  "Refresh the Presentation Overrides manager when it is open."
  (when-let* ((buffer (get-buffer "*Aural Presentation Overrides*")))
    (with-current-buffer buffer
      (when (derived-mode-p 'emacsvox-aural-overrides-mode)
        (emacsvox-aural-overrides-refresh)))))

(add-hook
 'emacsvox-aural-configuration-changed-hook
 #'emacsvox-aural-overrides-refresh-if-live)

(dolist
    (binding
     '(("RET" . emacsvox-aural-overrides-edit)
       ("e" . emacsvox-aural-overrides-edit)
       ("x" . emacsvox-aural-overrides-describe)
       ("P" . emacsvox-aural-overrides-preview)
       ("t" . emacsvox-aural-overrides-toggle)
       ("d" . emacsvox-aural-overrides-delete)
       ("f" . emacsvox-aural-overrides-filter)
       ("a" . emacsvox-aural-overrides-clear-filter)
       ("h" . emacsvox-aural)
       ("?" . emacsvox-aural-overrides-help)))
  (define-key
   emacsvox-aural-overrides-mode-map
   (kbd (car binding))
   (cdr binding)))

;;;###autoload
(defun emacsvox-aural-list-overrides (&optional source)
  "Open the unified Presentation Overrides manager for optional SOURCE."
  (interactive)
  (let ((source
         (or
          (and source
               (emacsvox-aural-inspection-source-buffer source))
          (emacsvox-aural-inspection-remember-source-buffer)))
        (buffer
         (get-buffer-create "*Aural Presentation Overrides*")))
    (with-current-buffer buffer
      (emacsvox-aural-overrides-mode)
      (emacsvox-aural-inspection-attach-source source)
      (emacsvox-aural-overrides-refresh))
    (emacsvox-aural-ui-pop-to-buffer buffer)
    (if (tabulated-list-get-id)
        (when (called-interactively-p 'interactive)
          (emacsvox-aural-overrides-speak-current))
      (when (called-interactively-p 'interactive)
        (if (fboundp 'tts-speak)
            (tts-speak
             "No personal, session, or source-buffer presentation overrides.")
          (message
           "No personal, session, or source-buffer presentation overrides."))))
    buffer))

(provide 'emacsvox-aural-overrides)

;;; emacsvox-aural-overrides.el ends here
