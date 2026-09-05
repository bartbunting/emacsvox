;;; emacsvox-aural-editor.el --- Accessible aural presentation editor -*- lexical-binding: t; -*-

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

;; A completion-driven special-mode editor for Presentation Options and
;; personal, session, or buffer-local rule layers.  The buffer remains plain
;; text and predictable for speech access.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'emacsvox-aural-semantics)
(require 'emacsvox-aural-explanation)
(require 'emacsvox-aural-feature-fragments)
(require 'emacsvox-aural-preview)
(require 'emacsvox-aural-providers)

(declare-function emacsvox-speak-help "emacsvox-speak" ())
(declare-function tts-speak "tts-speak" (text))

(defvar-local emacsvox-aural-editor-scope nil
  "Scope edited by the current aural editor buffer.")

(defvar-local emacsvox-aural-editor-target nil
  "Fragment identifier or source buffer edited by this editor.")

(defvar-local emacsvox-aural-editor-scheme-data nil
  "Working personal feature-fragment data.")

(defvar-local emacsvox-aural-editor-rules nil
  "Working declarative rules in display order.")

(defvar-local emacsvox-aural-editor-dirty nil
  "Non-nil when working editor data differs from its saved source.")

(defvar emacsvox-aural-editor-prepared-source-guard nil
  "Dynamically supplied source guard for a generated current-item rule.")

(defvar-local emacsvox-aural-editor-source-guard nil
  "Source guard checked before applying this generated working change.")

(defvaralias 'emacsvox-aural-editor--rule-index-property
  'emacsvox-aural-editor-rule-index-property)

(defconst emacsvox-aural-editor-rule-index-property
  'emacsvox-aural-editor-rule-index
  "Text property identifying the rule displayed at point.")

(defun emacsvox-aural-editor--scope-label ()
  "Return a concise label for the current editor scope."
  (pcase emacsvox-aural-editor-scope
    ('personal "persistent personal overrides")
    ('session "temporary session overrides")
    ('buffer
     (format
      "buffer-local overrides for %s"
      (if (buffer-live-p emacsvox-aural-editor-target)
          (buffer-name emacsvox-aural-editor-target)
        "a killed buffer")))
    ('fragment
     (format "personal feature fragment %s" emacsvox-aural-editor-target))))

(defun emacsvox-aural-editor-rule-enabled-p (rule)
  "Return non-nil when declarative RULE is enabled."
  (if (plist-member rule :enabled)
      (plist-get rule :enabled)
    t))

(defun emacsvox-aural-editor--phase-summary (phase)
  "Return a concise description of declarative PHASE."
  (let ((summary
         (cond
          ((null phase) "unchanged")
          ((and (listp phase) (listp (car phase)))
           (format "append %d action(s)" (length phase)))
          ((plist-get phase :suppress) "suppressed")
          ((plist-member phase :replace)
           (format "replace with %d action(s)"
                   (length (plist-get phase :replace))))
          ((plist-get phase :prepend)
           (format "prepend %d action(s)"
                   (length (plist-get phase :prepend))))
          ((plist-get phase :append)
           (format "append %d action(s)"
                   (length (plist-get phase :append))))
          ((plist-get phase :remove)
           (format "remove %S" (plist-get phase :remove)))
          (t "operations"))))
    (if-let* ((anchor (and (listp phase) (plist-get phase :anchor))))
        (format "%s at %s lifetime" summary anchor)
      summary)))

(defun emacsvox-aural-editor--content-summary (content)
  "Return a concise description of declarative CONTENT styling."
  (if (null content)
      "unchanged"
    (string-join
     (delq
      nil
      (list
       (when (plist-get content :suppress) "suppressed")
       (when (plist-member content :speak)
         (format "speak %s" (plist-get content :speak)))
       (when (plist-member content :voice)
         (format "voice %S" (plist-get content :voice)))
       (when (plist-member content :volume)
         (format "volume %S" (plist-get content :volume)))
       (when (plist-member content :space)
         (format "space %S" (plist-get content :space)))))
     ", ")))

(defun emacsvox-aural-editor-refresh ()
  "Render the current working Presentation Option or rule layer."
  (interactive)
  (let ((inhibit-read-only t)
        (position (point)))
    (erase-buffer)
    (insert (format "Aural Presentation Editor: %s\n\n"
                    (emacsvox-aural-editor--scope-label)))
    (pcase emacsvox-aural-editor-scope
      ('fragment
       (insert
        (format
         "Summary: %s\n\n"
         (plist-get emacsvox-aural-editor-scheme-data :summary)))))
    (insert
     "Keys: n add, RET/e edit, c copy, d delete, t enable/disable,\n"
     "M-up/M-down reorder, m metadata, p preview, x explain, v validate,\n"
     "w write, C-c C-c write, g refresh, q quit, ? help.\n\n")
    (if emacsvox-aural-editor-rules
        (cl-loop
         for rule in emacsvox-aural-editor-rules
         for index from 0
         do
         (let ((start (point))
               (render (plist-get rule :render)))
           (insert
            (format
             "%d. %s [%s]\n"
             (1+ index)
             (plist-get rule :id)
             (if (emacsvox-aural-editor-rule-enabled-p rule)
                 "enabled"
               "disabled")))
           (insert (format "   Match: %S\n" (plist-get rule :match)))
           (insert
            (format
             "   Before: %s\n"
             (emacsvox-aural-editor--phase-summary
              (plist-get render :before))))
           (insert
            (format
             "   Content: %s\n"
             (emacsvox-aural-editor--content-summary
              (plist-get render :content))))
           (insert
            (format
             "   After: %s\n\n"
             (emacsvox-aural-editor--phase-summary
              (plist-get render :after))))
           (put-text-property
            start (point)
            emacsvox-aural-editor-rule-index-property index)))
      (insert "No rules.  Press n to add one.\n"))
    (goto-char (min position (point-max)))))

(defun emacsvox-aural-editor--index-at-point ()
  "Return working rule index at point, or report that no rule is selected."
  (or
   (get-text-property
    (or
     (emacsvox-aural-inspection-point-position)
     (point-min))
    emacsvox-aural-editor-rule-index-property)
   (user-error "Move point to a displayed rule first")))

(defun emacsvox-aural-editor--rule-at-point ()
  "Return the working declarative rule displayed at point."
  (nth
   (emacsvox-aural-editor--index-at-point)
   emacsvox-aural-editor-rules))

(defun emacsvox-aural-editor-mark-dirty ()
  "Mark the current editor dirty and refresh its mode line."
  (setq emacsvox-aural-editor-dirty t)
  (force-mode-line-update))

(defun emacsvox-aural-editor--speak-edit-prompt (context)
  "Speak editing CONTEXT followed by the current minibuffer prompt."
  (when (fboundp 'tts-speak)
    (tts-speak
     (string-join
      (delq
       nil
       (list
        (and context (not (string-empty-p context)) context)
        (when-let* ((prompt (minibuffer-prompt)))
          (string-trim prompt))))
      ". "))))

(defmacro emacsvox-aural-editor--with-spoken-prompts (context &rest body)
  "Run BODY with every minibuffer prompt spoken after editing CONTEXT."
  (declare (indent 1) (debug t))
  `(let* ((prompt-context ,context)
          (minibuffer-setup-hook
           (append
            minibuffer-setup-hook
            (list
             (lambda ()
               (emacsvox-aural-editor--speak-edit-prompt
                prompt-context))))))
     ,@body))

(defun emacsvox-aural-editor--rule-prompt-context (rule action)
  "Describe RULE completely enough to orient an ACTION prompt sequence."
  (let ((render (plist-get rule :render)))
    (format
     "%s rule %s, %s. Match %S. Before %s. Content %s. After %s"
     action
     (plist-get rule :id)
     (if (emacsvox-aural-editor-rule-enabled-p rule) "enabled" "disabled")
     (plist-get rule :match)
     (emacsvox-aural-editor--phase-summary (plist-get render :before))
     (emacsvox-aural-editor--content-summary (plist-get render :content))
     (emacsvox-aural-editor--phase-summary (plist-get render :after)))))

(defun emacsvox-aural-editor--metadata-prompt-context ()
  "Describe the Presentation Option metadata being edited."
  (let ((data emacsvox-aural-editor-scheme-data))
    (string-join
     (delq
      nil
      (list
       (format "Editing metadata for %s"
               (emacsvox-aural-editor--scope-label))
       (format "Current summary %s"
               (or (plist-get data :summary) "empty"))))
     ". ")))

(defun emacsvox-aural-editor--read-boolean (prompt default)
  "Read a boolean using PROMPT and DEFAULT."
  (equal
   (completing-read
    prompt '("yes" "no") nil 'must-match nil nil
    (if default "yes" "no"))
   "yes"))

(defun emacsvox-aural-editor-mode-candidates ()
  "Return known major-mode command names for completion."
  (let (modes)
    (mapatoms
     (lambda (symbol)
       (when
           (and
            (commandp symbol)
            (string-suffix-p "-mode" (symbol-name symbol)))
         (push (symbol-name symbol) modes))))
    (sort (delete-dups modes) #'string-lessp)))

(defun emacsvox-aural-editor-face-candidates ()
  "Return currently defined visual face names for completion."
  (sort
   (delete-dups (mapcar #'symbol-name (face-list)))
   #'string-lessp))

(defun emacsvox-aural-editor-read-symbol-or-nil
    (prompt &optional default candidates require-match)
  "Read a symbol using PROMPT, DEFAULT, and CANDIDATES.

An empty answer returns nil.  REQUIRE-MATCH is passed to `completing-read'."
  (let* ((none "(none)")
         (answer
         (completing-read
          prompt
          (cons none candidates)
          nil require-match nil nil
          (if default (symbol-name default) none))))
    (unless (or (string-empty-p answer) (string= answer none))
      (intern answer))))

(defun emacsvox-aural-editor-read-attribute-value (record old)
  "Read a value for attribute RECORD, offering OLD as the default."
  (if-let* ((values (emacsvox-aural-semantic-allowed-values record)))
      (intern
       (completing-read
        (format "%s value: " (emacsvox-aural-semantic-id record))
        (mapcar #'symbol-name values)
        nil 'must-match nil nil
        (and old (format "%s" old))))
    (pcase (emacsvox-aural-semantic-value-type record)
      ('positive-integer
       (let ((value
              (read-number
               (format "%s value: "
                       (emacsvox-aural-semantic-id record))
               (and (integerp old) old))))
         (unless (> value 0)
           (user-error "Attribute value must be positive"))
         value))
      ('integer
       (read-number
        (format "%s value: " (emacsvox-aural-semantic-id record))
        (and (integerp old) old)))
      ('symbol
       (intern
        (read-string
         (format "%s value: " (emacsvox-aural-semantic-id record))
         (and old (format "%s" old)))))
      (_
       (read-string
        (format "%s value: " (emacsvox-aural-semantic-id record))
        (and old (format "%s" old)))))))

(defun emacsvox-aural-editor--add-semantic-selector (selector semantic)
  "Return SELECTOR extended to match registered SEMANTIC."
  (let ((record (emacsvox-aural-semantic semantic)))
    (pcase (emacsvox-aural-semantic-kind record)
      ('role
       (when (plist-get selector :role)
         (user-error "A selector can contain only one role"))
       (plist-put selector :role semantic))
      ('event
       (plist-put
        selector :events
        (append (plist-get selector :events) (list semantic))))
      ('state
       (plist-put
        selector :states
        (append (plist-get selector :states) (list semantic))))
      ('attribute
       (plist-put
        selector
        (intern (format ":%s" semantic))
        (emacsvox-aural-editor-read-attribute-value record nil))))))

(defun emacsvox-aural-editor--read-selector (&optional old)
  "Read a selector through completion, optionally preserving OLD."
  (if
      (and old
           (emacsvox-aural-editor--read-boolean
            "Keep existing selector? " t))
      (copy-tree old)
    (let (selector semantic)
      (while
          (setq
           semantic
           (emacsvox-aural-semantics-read
            "Add semantic selector (empty to finish): " t))
        (setq
         selector
         (emacsvox-aural-editor--add-semantic-selector
          selector semantic)))
      (let ((attributes
             (cl-loop
              for record in (emacsvox-aural-semantics)
              when (eq
                    (emacsvox-aural-semantic-kind record)
                    'attribute)
              collect
              (symbol-name (emacsvox-aural-semantic-id record))))
            required
            answer)
        (while
            (not
             (string-empty-p
              (setq
               answer
                (completing-read
                 "Require a detail without fixing its value (empty to finish): "
                attributes nil 'must-match))))
          (let ((attribute (intern answer)))
            (unless
                (plist-member
                 selector (intern (format ":%s" attribute)))
              (push attribute required))))
        (when required
          (setq
           selector
           (plist-put selector :requires (nreverse required)))))
      (when-let* ((module
                   (emacsvox-aural-editor-read-symbol-or-nil
                    "Module (empty for any): ")))
        (setq selector (plist-put selector :module module)))
      (when-let* ((mode
                   (emacsvox-aural-editor-read-symbol-or-nil
                    "Major mode (empty for any): "
                    nil
                    (emacsvox-aural-editor-mode-candidates))))
        (setq selector (plist-put selector :mode mode)))
      (when-let* ((occasion
                   (emacsvox-aural-editor-read-symbol-or-nil
                    "Occasion (empty for any): "
                    nil
                    (emacsvox-aural-occasion-candidates)
                    'must-match)))
        (setq selector (plist-put selector :occasion occasion)))
      (when-let* ((cue
                   (emacsvox-aural-editor-read-symbol-or-nil
                    "Legacy cue (empty for none): ")))
        (setq selector (plist-put selector :legacy-cue cue)))
      (when-let* ((face
                   (emacsvox-aural-editor-read-symbol-or-nil
                    "Visual face (empty for none): "
                    nil
                    (emacsvox-aural-editor-face-candidates))))
        (setq selector (plist-put selector :legacy-face face)))
      selector)))

(defun emacsvox-aural-editor-cue-candidates ()
  "Return registered cue identifiers for completion."
  (let (cues)
    (maphash
     (lambda (cue _) (push (symbol-name cue) cues))
     emacsvox-aural-cue-registry)
    (sort cues #'string-lessp)))

(defun emacsvox-aural-editor--voice-entry-names (entries)
  "Return the sorted voice names in palette ENTRIES."
  (sort
   (mapcar (lambda (entry) (symbol-name (car entry))) entries)
   #'string-lessp))

(defun emacsvox-aural-editor-voice-candidates (&optional current)
  "Return effective voice choices in a stable, meaningful order.

When CURRENT is non-nil, retain it as the first choice.  Special values come
next, followed by voices defined directly by the active palette and then
inherited voices.  Names within each palette group are alphabetical."
  (let* ((palette (emacsvox-aural-effective-voice-palette))
         (record (emacsvox-aural-voice-palette palette))
         (direct
          (emacsvox-aural-editor--voice-entry-names
           (emacsvox-aural-voice-palette-entries record)))
         (effective
          (emacsvox-aural-editor--voice-entry-names
           (emacsvox-aural-effective-voice-entries palette)))
         (inherited
          (cl-remove-if (lambda (name) (member name direct)) effective))
         (current-name
          (and current
               (if (symbolp current) (symbol-name current) current))))
    (delete-dups
     (append
      (and current-name (list current-name))
      '("default" "inaudible")
      direct inherited))))

(defun emacsvox-aural-editor--read-voice (&optional prompt)
  "Read a voice name using PROMPT, returning nil for default."
  (let ((answer
         (completing-read
          (or prompt "Voice: ")
          (emacsvox-aural-editor-voice-candidates)
          nil nil nil nil "default")))
    (unless (or (string-empty-p answer) (string= answer "default"))
      (intern answer))))

(defun emacsvox-aural-editor--read-space (&optional old label)
  "Read portable spatial styling, optionally preserving OLD.

LABEL identifies the speech or cue being edited."
  (let* ((choices
          (append
           (when old '("keep"))
           '("unchanged" "center" "balance" "azimuth")))
         (choice
          (intern
           (completing-read
            (format "%s spatial placement: " (or label "Content"))
            choices nil 'must-match nil nil
            (if old "keep" "unchanged")))))
    (pcase choice
      ('keep (copy-tree old))
      ('unchanged nil)
      ('center '(:balance 0.0))
      ('balance
       (let ((value (read-number "Balance (-1 left, +1 right): " 0.0)))
         (unless (<= -1.0 value 1.0)
           (user-error "Balance must be between -1.0 and 1.0"))
         (list :balance (float value))))
      ('azimuth
       (let ((value
              (read-number
               "Listener-relative azimuth in degrees (-180 to 180): "
               0.0)))
         (unless (<= -180.0 value 180.0)
           (user-error "Azimuth must be between -180 and 180 degrees"))
         (list :azimuth (float value)))))))

(defun emacsvox-aural-editor--read-action (rule-id phase index)
  "Read action INDEX for RULE-ID and PHASE."
  (let* ((kind
          (intern
           (completing-read
            "Action kind: " '("speech" "cue" "pause" "tone")
            nil 'must-match)))
         (id
          (intern
           (read-string
            "Stable action identifier: "
            (format "%s/%s/%d" rule-id phase index))))
         (action (list :id id :kind kind)))
    (pcase kind
      ('speech
       (let* ((form
               (completing-read
                "Speech wording: "
                '("literal text" "semantic template")
                nil 'must-match nil nil "literal text"))
              (text
               (read-string
                (if (string= form "semantic template")
                    "Template, for example Heading {level}: "
                  "Spoken text: "))))
         (setq
          action
          (plist-put
           action
           (if (string= form "semantic template")
               :text-template
             :text)
           text)))
       (when-let* ((voice
                    (emacsvox-aural-editor--read-voice
                     "Annotation voice (default for none): ")))
         (setq action (plist-put action :voice voice))))
      ('cue
       (setq
        action
        (plist-put
         action :cue
         (intern
          (completing-read
           "Semantic cue: "
           (emacsvox-aural-editor-cue-candidates)
           nil 'must-match)))))
      ('pause
       (setq
        action
        (plist-put
         action :duration
         (read-number "Pause duration in milliseconds: " 50))))
      ('tone
       (setq
        action
        (plist-put
         action :tone
         (intern
          (completing-read
           "Named tone: "
           (emacsvox-aural-tone-candidates)
           nil 'must-match))))
       (let ((audio-mode
              (intern
               (completing-read
                "Tone timing: " '("overlay" "insert")
                nil 'must-match nil nil "overlay"))))
         (unless (eq audio-mode 'overlay)
           (setq action (plist-put action :audio-mode audio-mode))))))
    (when (memq kind '(speech cue))
      (when-let* ((space
                   (emacsvox-aural-editor--read-space
                    nil (capitalize (symbol-name kind)))))
        (setq action (plist-put action :space space))))
    (let ((anchor
           (completing-read
            "Action lifetime: "
            '("inferred" "object" "run" "transition")
            nil 'must-match nil nil "inferred")))
      (unless (string= anchor "inferred")
        (setq action (plist-put action :anchor (intern anchor)))))
    action))

(defun emacsvox-aural-editor--read-actions (rule-id phase)
  "Read an ordered action list for RULE-ID and PHASE."
  (let (actions)
    (while
        (or
         (null actions)
         (y-or-n-p "Add another ordered action? "))
      (push
       (emacsvox-aural-editor--read-action
        rule-id phase (length actions))
       actions))
    (nreverse actions)))

(defun emacsvox-aural-editor--read-phase
    (rule-id phase &optional old)
  "Read PHASE contribution for RULE-ID, optionally preserving OLD."
  (let* ((choices
          (append
           (when old '("keep"))
           '("unchanged" "append" "prepend" "replace" "remove" "suppress")))
         (operation
          (intern
           (completing-read
            (format "%s phase operation: " (capitalize (symbol-name phase)))
            choices nil 'must-match nil nil
            (if old "keep" "unchanged")))))
    (pcase operation
      ('keep (copy-tree old))
      ('unchanged nil)
      ((or 'append 'prepend 'replace)
       (let ((result
              (list
               (intern (format ":%s" operation))
               (emacsvox-aural-editor--read-actions rule-id phase))))
         (when (eq operation 'replace)
           (let ((anchor
                  (completing-read
                   "Replacement lifetime: "
                   '("inferred" "object" "run" "transition")
                   nil 'must-match nil nil "inferred")))
             (unless (string= anchor "inferred")
               (setq result
                     (plist-put result :anchor (intern anchor))))))
         result))
      ('remove
       (let ((result
              (list
               :remove
               (mapcar
                #'intern
                (split-string
                 (read-string
                  "Action identifiers to remove, separated by spaces: ")
                 "[[:space:]]+" t))))
             (anchor
              (completing-read
               "Removal lifetime: "
               '("inferred" "object" "run" "transition")
               nil 'must-match nil nil "inferred")))
         (unless (string= anchor "inferred")
           (setq result (plist-put result :anchor (intern anchor))))
         result))
      ('suppress
       (let ((result (list :suppress t))
             (anchor
              (completing-read
               "Suppression lifetime: "
               '("inferred" "object" "run" "transition")
               nil 'must-match nil nil "inferred")))
         (unless (string= anchor "inferred")
           (setq result (plist-put result :anchor (intern anchor))))
         result)))))

(defun emacsvox-aural-editor--read-content (&optional old)
  "Read content styling, optionally preserving OLD."
  (if
      (and old
           (emacsvox-aural-editor--read-boolean
            "Keep existing content styling? " t))
      (copy-tree old)
    (let* ((speech
            (intern
             (completing-read
              "Content speech: "
              '("unchanged" "speak" "silence")
              nil 'must-match nil nil "unchanged")))
           (voice-answer
            (completing-read
             "Content voice: "
             (append '("unchanged") (emacsvox-aural-editor-voice-candidates))
             nil nil nil nil "unchanged"))
           (space
            (emacsvox-aural-editor--read-space
             (plist-get old :space) "Content"))
           content)
      (pcase speech
        ('speak (setq content (plist-put content :speak t)))
        ('silence (setq content (plist-put content :speak nil))))
      (unless (string= voice-answer "unchanged")
        (setq
         content
         (plist-put
          content :voice
          (unless (string= voice-answer "default")
            (intern voice-answer)))))
      (when space
        (setq content (plist-put content :space space)))
      content)))

(defun emacsvox-aural-editor--read-rule (&optional old copied-id)
  "Read one declarative rule, optionally editing OLD or using COPIED-ID."
  (let* ((old-id (plist-get old :id))
         (id
          (intern
           (read-string
            "Rule identifier: "
            (format "%s" (or copied-id old-id "new-rule")))))
         (enabled
          (emacsvox-aural-editor--read-boolean
           "Enable this rule? "
           (if old (emacsvox-aural-editor-rule-enabled-p old) t)))
         (old-render (plist-get old :render))
         (selector
          (emacsvox-aural-editor--read-selector
           (plist-get old :match)))
         (before
          (emacsvox-aural-editor--read-phase
           id 'before (plist-get old-render :before)))
         (content
          (emacsvox-aural-editor--read-content
           (plist-get old-render :content)))
         (after
          (emacsvox-aural-editor--read-phase
           id 'after (plist-get old-render :after)))
         render rule)
    (when before (setq render (plist-put render :before before)))
    (when content (setq render (plist-put render :content content)))
    (when after (setq render (plist-put render :after after)))
    (setq rule (list :id id :enabled enabled :match selector :render render))
    (emacsvox-aural-compile-rule rule 'user)
    rule))

(defun emacsvox-aural-editor-add-rule ()
  "Add a guided rule after the selected rule or at the end."
  (interactive)
  (let* ((rule
          (emacsvox-aural-editor--with-spoken-prompts
              "Adding a new aural rule"
            (emacsvox-aural-editor--read-rule)))
         (index
          (condition-case nil
              (1+ (emacsvox-aural-editor--index-at-point))
            (user-error (length emacsvox-aural-editor-rules)))))
    (setq
     emacsvox-aural-editor-rules
     (append
      (cl-subseq emacsvox-aural-editor-rules 0 index)
      (list rule)
      (nthcdr index emacsvox-aural-editor-rules)))
    (emacsvox-aural-editor-mark-dirty)
    (emacsvox-aural-editor-refresh)))

(defun emacsvox-aural-editor-edit-rule ()
  "Edit the selected rule through guided prompts."
  (interactive)
  (let* ((index (emacsvox-aural-editor--index-at-point))
         (old (nth index emacsvox-aural-editor-rules))
         (rule
          (emacsvox-aural-editor--with-spoken-prompts
              (emacsvox-aural-editor--rule-prompt-context old "Editing")
            (emacsvox-aural-editor--read-rule old))))
    (setf (nth index emacsvox-aural-editor-rules) rule)
    (emacsvox-aural-editor-mark-dirty)
    (emacsvox-aural-editor-refresh)))

(defun emacsvox-aural-editor-copy-rule ()
  "Copy the selected rule and request a new stable identifier."
  (interactive)
  (let* ((index (emacsvox-aural-editor--index-at-point))
         (old (nth index emacsvox-aural-editor-rules))
         (result
          (emacsvox-aural-editor--with-spoken-prompts
              (emacsvox-aural-editor--rule-prompt-context old "Copying")
            (let* ((copy-id
                    (intern
                     (read-string
                      "Copied rule identifier: "
                      (format "%s-copy" (plist-get old :id)))))
                   (rule
                    (emacsvox-aural-editor--read-rule old copy-id)))
              (cons copy-id rule))))
         (rule (cdr result)))
    (setq
     emacsvox-aural-editor-rules
     (append
      (cl-subseq emacsvox-aural-editor-rules 0 (1+ index))
      (list rule)
      (nthcdr (1+ index) emacsvox-aural-editor-rules)))
    (emacsvox-aural-editor-mark-dirty)
    (emacsvox-aural-editor-refresh)))

(defun emacsvox-aural-editor-delete-rule ()
  "Delete the selected working rule after confirmation."
  (interactive)
  (let* ((index (emacsvox-aural-editor--index-at-point))
         (rule (nth index emacsvox-aural-editor-rules)))
    (when (yes-or-no-p (format "Delete aural rule %s? " (plist-get rule :id)))
      (setq
       emacsvox-aural-editor-rules
       (append
        (cl-subseq emacsvox-aural-editor-rules 0 index)
        (nthcdr (1+ index) emacsvox-aural-editor-rules)))
      (emacsvox-aural-editor-mark-dirty)
      (emacsvox-aural-editor-refresh))))

(defun emacsvox-aural-editor-toggle-rule ()
  "Enable or disable the selected working rule without discarding it."
  (interactive)
  (let* ((index (emacsvox-aural-editor--index-at-point))
         (rule (copy-tree (nth index emacsvox-aural-editor-rules))))
    (setq
     rule
     (plist-put
      rule :enabled
      (not (emacsvox-aural-editor-rule-enabled-p rule))))
    (setf (nth index emacsvox-aural-editor-rules) rule)
    (emacsvox-aural-editor-mark-dirty)
    (emacsvox-aural-editor-refresh)))

(defun emacsvox-aural-editor-move-rule (offset)
  "Move the selected rule by OFFSET positions."
  (let* ((index (emacsvox-aural-editor--index-at-point))
         (destination (+ index offset)))
    (unless (< -1 destination (length emacsvox-aural-editor-rules))
      (user-error "Rule is already at that boundary"))
    (let ((rule (nth index emacsvox-aural-editor-rules)))
      (setf
       (nth index emacsvox-aural-editor-rules)
       (nth destination emacsvox-aural-editor-rules))
      (setf (nth destination emacsvox-aural-editor-rules) rule))
    (emacsvox-aural-editor-mark-dirty)
    (emacsvox-aural-editor-refresh)
    (goto-char (point-min))
    (let ((position
           (text-property-any
            (point-min) (point-max)
            emacsvox-aural-editor-rule-index-property destination)))
      (when position (goto-char position)))))

(defun emacsvox-aural-editor-move-rule-up ()
  "Move the selected rule earlier in its scope."
  (interactive)
  (emacsvox-aural-editor-move-rule -1))

(defun emacsvox-aural-editor-move-rule-down ()
  "Move the selected rule later in its scope."
  (interactive)
  (emacsvox-aural-editor-move-rule 1))

(defun emacsvox-aural-editor-edit-metadata ()
  "Edit metadata for the current personal Presentation Option."
  (interactive)
  (unless (eq emacsvox-aural-editor-scope 'fragment)
    (user-error "This rule-layer scope has no metadata"))
  (emacsvox-aural-editor--with-spoken-prompts
      (emacsvox-aural-editor--metadata-prompt-context)
    (let* ((data (copy-tree emacsvox-aural-editor-scheme-data))
           (summary
            (read-string
             "Presentation Option summary: "
             (plist-get data :summary))))
      (setq data (plist-put data :summary summary))
      (setq emacsvox-aural-editor-scheme-data data)
      (emacsvox-aural-editor-mark-dirty)
      (emacsvox-aural-editor-refresh))))

(defun emacsvox-aural-editor-normalized-rules ()
  "Return working rules with visible list order recorded explicitly."
  (cl-loop
   for rule in emacsvox-aural-editor-rules
   for order from 0
   collect (plist-put (copy-tree rule) :order order)))

(defun emacsvox-aural-editor--working-scheme-data ()
  "Return complete working personal Presentation Option data."
  (plist-put
   (copy-tree emacsvox-aural-editor-scheme-data)
   :rules
   (emacsvox-aural-editor-normalized-rules)))

(defun emacsvox-aural-editor-validation-report ()
  "Validate working data and return a report or simple success marker."
  (pcase emacsvox-aural-editor-scope
    ('fragment
     (let* ((data (emacsvox-aural-editor--working-scheme-data))
            (old
             (emacsvox-aural-feature-fragment-entry
              emacsvox-aural-editor-target))
            (compiled
             (emacsvox-aural--compile-feature-fragment data "editor"))
            (entry
             (emacsvox-aural--make-feature-fragment-entry
              :id emacsvox-aural-editor-target
              :collection
              (if old
                  (emacsvox-aural-feature-fragment-collection old)
                'personal)
              :data data
              :compiled compiled
              :source "editor"))
            (registry
             (copy-hash-table
              emacsvox-aural-feature-fragment-registry)))
       (puthash emacsvox-aural-editor-target entry registry)
       (let ((emacsvox-aural-feature-fragment-registry registry))
         (emacsvox-aural-validate-feature-fragment
          emacsvox-aural-editor-target))))
    (_
     (let ((origin
            (pcase emacsvox-aural-editor-scope
              ('personal 'user)
              ('session 'session)
              ('buffer 'buffer))))
       (emacsvox-aural--compile-rule-list
        (emacsvox-aural-editor-normalized-rules)
        origin "editor")
       t))))

(defun emacsvox-aural-editor-validate ()
  "Validate all working rules and display diagnostics."
  (interactive)
  (condition-case error
      (let ((report (emacsvox-aural-editor-validation-report)))
        (if (eq report t)
            (message "Working aural rules are valid")
          (emacsvox-aural-display-validation
           report
           (if (eq emacsvox-aural-editor-scope 'fragment)
               "Presentation Option"
             "rule layer"))))
    (error (user-error "%s" (error-message-string error)))))

(defun emacsvox-aural-editor--commit-fragment (rules)
  "Atomically commit personal feature fragment with normalized RULES."
  (let* ((id emacsvox-aural-editor-target)
         (old (emacsvox-aural-feature-fragment-entry id))
         (data
          (plist-put
           (copy-tree emacsvox-aural-editor-scheme-data)
           :rules rules))
         (compiled (emacsvox-aural--compile-feature-fragment data "editor"))
         (entry
          (emacsvox-aural--make-feature-fragment-entry
           :id id
           :collection
           (if old
               (emacsvox-aural-feature-fragment-collection old)
             'personal)
           :data data :compiled compiled
           :source emacsvox-aural-schemes-file))
         (registry
          (copy-hash-table
           emacsvox-aural-feature-fragment-registry)))
    (when
        (and old
             (emacsvox-aural-feature-fragment-entry-built-in old))
      (user-error
       "Built-in feature fragments cannot be edited; copy it first"))
    (puthash id entry registry)
    (emacsvox-aural-feature-fragments-install-state
     registry emacsvox-aural-enabled-feature-fragments)
    (setq emacsvox-aural-editor-scheme-data data)
    (emacsvox-aural-feature-fragments-refresh-if-live id)))

(defun emacsvox-aural-editor--commit-layer (rules)
  "Atomically commit normalized RULES to the selected override layer."
  (pcase emacsvox-aural-editor-scope
    ('personal
     (let ((old emacsvox-aural-user-rules))
       (setq emacsvox-aural-user-rules rules)
       (condition-case error
           (progn
             (emacsvox-aural-current-rules
              (emacsvox-aural-context-at-point))
             (emacsvox-aural-save-user-data)
             (emacsvox-aural-configuration-changed 'personal-rules))
         (error
          (setq emacsvox-aural-user-rules old)
          (signal (car error) (cdr error))))))
    ('session
     (let ((old emacsvox-aural-session-rules))
       (setq emacsvox-aural-session-rules rules)
       (condition-case error
           (progn
             (emacsvox-aural-current-rules
              (emacsvox-aural-context-at-point))
             (emacsvox-aural-configuration-changed 'session-rules))
         (error
          (setq emacsvox-aural-session-rules old)
          (signal (car error) (cdr error))))))
    ('buffer
     (unless (buffer-live-p emacsvox-aural-editor-target)
       (user-error "The edited source buffer has been killed"))
     (with-current-buffer emacsvox-aural-editor-target
       (let ((old emacsvox-aural-buffer-rules))
         (setq emacsvox-aural-buffer-rules rules)
         (condition-case error
             (progn
               (emacsvox-aural-current-rules
                (emacsvox-aural-current-context nil 'continuous))
               (emacsvox-aural-configuration-changed 'buffer-rules))
           (error
            (setq emacsvox-aural-buffer-rules old)
            (signal (car error) (cdr error)))))))))

(defun emacsvox-aural-editor-save ()
  "Validate and atomically save or apply current working rules."
  (interactive)
  (emacsvox-aural-inspection-check-source-guard
   emacsvox-aural-editor-source-guard)
  (let* ((rules (emacsvox-aural-editor-normalized-rules))
         (report (emacsvox-aural-editor-validation-report)))
    (when
        (and
         (not (eq report t))
         (not (emacsvox-aural-validation-report-valid report)))
      (user-error
       "Cannot save invalid aural presentation: %s"
       (string-join
        (emacsvox-aural-validation-report-errors report)
        "; ")))
    (pcase emacsvox-aural-editor-scope
      ('fragment (emacsvox-aural-editor--commit-fragment rules))
      (_ (emacsvox-aural-editor--commit-layer rules)))
    (setq
     emacsvox-aural-editor-rules (copy-tree rules)
     emacsvox-aural-editor-dirty nil
     emacsvox-aural-editor-source-guard nil)
    (force-mode-line-update)
    (emacsvox-aural-editor-refresh)
    (message "Saved %s" (emacsvox-aural-editor--scope-label))))

(defun emacsvox-aural-editor--compiled-rule-at-point ()
  "Compile and return the selected working rule."
  (emacsvox-aural-compile-rule
   (emacsvox-aural-editor--rule-at-point)
   (pcase emacsvox-aural-editor-scope
     ('personal 'user)
     ('session 'session)
     ('buffer 'buffer)
     ('fragment 'fragment)
     (_ (error "Unknown aural editor scope: %S"
               emacsvox-aural-editor-scope)))
   (emacsvox-aural-editor--index-at-point)
   "editor"))

(defun emacsvox-aural-editor--rule-example (rule)
  "Return representative facts and context for compiled RULE."
  (pcase-let
      ((`(,facts ,context)
        (emacsvox-aural-inspection-representative-input rule)))
    (unless (plist-get facts :content)
      (setq facts (plist-put facts :content "Example")))
    (list facts context)))

(defun emacsvox-aural-editor-preview-rule ()
  "Preview the selected unsaved working rule."
  (interactive)
  (let ((rule (emacsvox-aural-editor--compiled-rule-at-point)))
    (unless (emacsvox-aural-rule-enabled rule)
      (user-error "Enable the rule before previewing it"))
    (pcase-let*
        ((`(,facts ,context) (emacsvox-aural-editor--rule-example rule))
         (render (emacsvox-aural-resolve facts context (list rule)))
         (concrete (emacsvox-aural-compile-plan render facts context)))
      (emacsvox-aural-preview-play-plan concrete))))

(defun emacsvox-aural-editor-explain-rule ()
  "Explain the selected unsaved working rule against representative facts."
  (interactive)
  (let ((rule (emacsvox-aural-editor--compiled-rule-at-point)))
    (pcase-let*
        ((`(,facts ,context) (emacsvox-aural-editor--rule-example rule))
         (input (emacsvox-aural-normalize-input facts context))
         (matching
          (if (emacsvox-aural-rule-matches-p rule input)
              (list rule)
            nil))
         (render (emacsvox-aural-resolve facts context (list rule)))
         (concrete (emacsvox-aural-compile-plan render facts context))
         (explanation
          (emacsvox-aural--make-explanation
           :scheme emacsvox-aural-active-scheme
           :facts facts
           :context context
           :matching-rules
           (mapcar
            (lambda (match)
              (list
               :id (emacsvox-aural-rule-id match)
               :origin (emacsvox-aural-rule-origin match)
               :source "editor"
               :score (emacsvox-aural-rule-score match input)))
            matching)
           :render-plan render
           :concrete-plan concrete
           :suppressed-actions nil)))
      (emacsvox-aural-explanation-display
       explanation (called-interactively-p 'interactive)))))

(defun emacsvox-aural-editor-help ()
  "Display aural editor commands and workflow."
  (interactive)
  (with-help-window (help-buffer)
    (princ
     (concat
      "Aural Presentation Editor\n\n"
      "Each rule has guided semantic/context selectors and explicit before,\n"
      "content, and after phases.  Ordered actions are speech, cues, pauses,\n"
      "or named tones.\n"
      "Open a different editor buffer to choose another persistence scope.\n\n"
      "n add rule          RET or e edit rule\n"
      "c copy rule         d delete rule\n"
      "t enable/disable    M-up/M-down reorder\n"
      "m metadata          p preview\n"
      "x explain           v validate\n"
      "w or C-c C-c write changes\n"
      "h aural home\n"
      "q quit\n")))
  (when (fboundp 'emacsvox-speak-help)
    (emacsvox-speak-help)))

(defun emacsvox-aural-editor-quit ()
  "Quit the editor, asking before discarding working changes."
  (interactive)
  (when
      (or
       (not emacsvox-aural-editor-dirty)
       (yes-or-no-p "Discard unsaved aural editor changes? "))
    (emacsvox-aural-quit t)))

(defvar emacsvox-aural-scheme-editor-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map emacsvox-aural-interface-mode-map)
    (define-key map (kbd "n") #'emacsvox-aural-editor-add-rule)
    (define-key map (kbd "RET") #'emacsvox-aural-editor-edit-rule)
    (define-key map (kbd "e") #'emacsvox-aural-editor-edit-rule)
    (define-key map (kbd "c") #'emacsvox-aural-editor-copy-rule)
    (define-key map (kbd "d") #'emacsvox-aural-editor-delete-rule)
    (define-key map (kbd "t") #'emacsvox-aural-editor-toggle-rule)
    (define-key map (kbd "<M-up>") #'emacsvox-aural-editor-move-rule-up)
    (define-key map (kbd "<M-down>") #'emacsvox-aural-editor-move-rule-down)
    (define-key map (kbd "m") #'emacsvox-aural-editor-edit-metadata)
    (define-key map (kbd "p") #'emacsvox-aural-editor-preview-rule)
    (define-key map (kbd "x") #'emacsvox-aural-editor-explain-rule)
    (define-key map (kbd "v") #'emacsvox-aural-editor-validate)
    (define-key map (kbd "s") nil)
    (define-key map (kbd "w") #'emacsvox-aural-editor-save)
    (define-key map (kbd "C-c C-c") #'emacsvox-aural-editor-save)
    (define-key map (kbd "g") #'emacsvox-aural-editor-refresh)
    (define-key map (kbd "h") #'emacsvox-aural)
    (define-key map (kbd "?") #'emacsvox-aural-editor-help)
    (define-key map (kbd "q") #'emacsvox-aural-editor-quit)
    map)
  "Keymap for `emacsvox-aural-scheme-editor-mode'.")

(define-derived-mode emacsvox-aural-scheme-editor-mode
    emacsvox-aural-interface-mode
  "Aural-Presentation-Editor"
  "Accessible editor for declarative Presentation Options and rule layers."
  (setq-local
   mode-line-process
   '(:eval (when emacsvox-aural-editor-dirty " [modified]"))))

(defun emacsvox-aural-editor--personal-fragment-candidates ()
  "Return editable non-built-in feature fragment identifiers."
  (let (ids)
    (maphash
     (lambda (id entry)
       (unless (emacsvox-aural-feature-fragment-entry-built-in entry)
         (push (symbol-name id) ids)))
     emacsvox-aural-feature-fragment-registry)
    (sort ids #'string-lessp)))

(defun emacsvox-aural-editor--find-buffer (scope target)
  "Find an editor for SCOPE and TARGET, independently of its display name."
  (cl-find-if
   (lambda (buffer)
     (with-current-buffer buffer
       (and (derived-mode-p 'emacsvox-aural-scheme-editor-mode)
            (eq scope emacsvox-aural-editor-scope)
            (or (memq scope '(personal session))
                (eq target emacsvox-aural-editor-target)))))
   (buffer-list)))

(defun emacsvox-aural-editor--open-remap-target (scope source-buffer)
  "Open and return a clean remap editor for SCOPE and SOURCE-BUFFER."
  (unless (memq scope '(personal session buffer))
    (user-error "Point remapping cannot target a %S editor" scope))
  (let ((existing (emacsvox-aural-editor--find-buffer scope source-buffer)))
    (when
        (and
         existing
         (buffer-local-value 'emacsvox-aural-editor-dirty existing))
      (user-error
       "Save or quit the modified %s editor before preparing another remap"
       scope))
    (emacsvox-edit-aural-rules scope nil source-buffer)))

(defun emacsvox-aural-editor-open-prefilled-rule
    (scope rule source-buffer)
  "Open SCOPE with unsaved RULE for SOURCE-BUFFER selected.

SCOPE must be `personal', `session', or `buffer'.  Replace an existing
working rule with the same identifier, otherwise append RULE.  Refuse to
discard changes from an already open dirty editor."
  (let ((buffer
         (emacsvox-aural-editor--open-remap-target
          scope source-buffer))
        (id (plist-get rule :id)))
    (unless buffer
      (error "Aural %s editor did not open" scope))
    (with-current-buffer buffer
      (setq emacsvox-aural-editor-source-guard
            emacsvox-aural-editor-prepared-source-guard)
      (let ((index
             (cl-position
              id emacsvox-aural-editor-rules
              :key (lambda (entry) (plist-get entry :id))
              :test #'eq)))
        (if index
            (setf
             (nth index emacsvox-aural-editor-rules)
             (copy-tree rule))
          (setq
           index (length emacsvox-aural-editor-rules)
           emacsvox-aural-editor-rules
           (append
            emacsvox-aural-editor-rules
            (list (copy-tree rule)))))
        (emacsvox-aural-editor-mark-dirty)
        (emacsvox-aural-editor-refresh)
        (when-let* ((position
                     (text-property-any
                      (point-min) (point-max)
                      emacsvox-aural-editor-rule-index-property index)))
          (goto-char position))))
    buffer))

(defalias
  'emacsvox-aural-editor--open-prefilled-rule
  #'emacsvox-aural-editor-open-prefilled-rule)

(defun emacsvox-aural-editor-open-without-rule
    (scope rule-id source-buffer)
  "Open SCOPE with RULE-ID removed but unsaved for SOURCE-BUFFER.

This restores inherited behavior after the edited scope is saved."
  (let ((buffer
         (emacsvox-aural-editor--open-remap-target
          scope source-buffer)))
    (unless buffer
      (error "Aural %s editor did not open" scope))
    (with-current-buffer buffer
      (setq emacsvox-aural-editor-source-guard
            emacsvox-aural-editor-prepared-source-guard)
      (let ((index
             (cl-position
              rule-id emacsvox-aural-editor-rules
              :key (lambda (entry) (plist-get entry :id))
              :test #'eq)))
        (unless index
          (user-error
           "No generated earcon override exists in %s scope for this presentation"
           scope))
        (setq
         emacsvox-aural-editor-rules
         (append
          (cl-subseq emacsvox-aural-editor-rules 0 index)
          (nthcdr (1+ index) emacsvox-aural-editor-rules)))
        (emacsvox-aural-editor-mark-dirty)
        (emacsvox-aural-editor-refresh)
        (when emacsvox-aural-editor-rules
          (let* ((target
                  (min index
                       (1- (length emacsvox-aural-editor-rules))))
                 (position
                  (text-property-any
                   (point-min) (point-max)
                   emacsvox-aural-editor-rule-index-property target)))
            (when position
              (goto-char position))))))
    buffer))

(defalias
  'emacsvox-aural-editor--open-without-rule
  #'emacsvox-aural-editor-open-without-rule)

(defun emacsvox-edit-aural-rules (scope &optional fragment source-buffer)
  "Open an accessible rule editor for SCOPE.

SCOPE is `personal', `session', `buffer', or `fragment'.  FRAGMENT identifies
a personal Presentation Option.  SOURCE-BUFFER defaults to
the ordinary source associated with the current buffer for buffer scope.
Return the editor buffer.  Reopening a modified editor preserves its draft."
  (interactive
   (list
    (intern
     (completing-read
      "Edit aural scope: "
      '("personal" "session" "buffer" "fragment")
      nil 'must-match))))
  (let* ((origin-buffer (or source-buffer (current-buffer)))
         (source-buffer
          (emacsvox-aural-inspection-remember-source-buffer
           origin-buffer))
         (fragment
          (when (eq scope 'fragment)
            (or
             fragment
             (let ((candidates
                    (emacsvox-aural-editor--personal-fragment-candidates)))
               (unless candidates
                 (user-error "No personal Presentation Options; create or copy one first"))
               (intern
                (completing-read
                 "Edit personal Presentation Option: "
                 candidates nil 'must-match))))))
         (entry
          (and fragment
               (emacsvox-aural-feature-fragment-entry fragment)))
         (rules
          (pcase scope
            ('personal emacsvox-aural-user-rules)
            ('session emacsvox-aural-session-rules)
            ('buffer
             (unless source-buffer
               (user-error "No live source buffer is available"))
             (buffer-local-value
              'emacsvox-aural-buffer-rules source-buffer))
            ('fragment
             (unless entry
               (user-error
                "Unknown personal Presentation Option: %S" fragment))
             (when
                 (emacsvox-aural-feature-fragment-entry-built-in entry)
               (user-error
                "Built-in feature fragments cannot be edited; copy it first"))
             (plist-get
              (emacsvox-aural-feature-fragment-entry-data entry)
              :rules))
            (_ (user-error "Unknown aural editor scope: %S" scope))))
         (name
          (format
           "*Aural Editor: %s*"
           (pcase scope
             ('fragment fragment)
             ('buffer (format "buffer %s" (buffer-name source-buffer)))
             (_ scope))))
         (buffer
          (or (emacsvox-aural-editor--find-buffer
               scope (if (eq scope 'fragment) fragment source-buffer))
              (generate-new-buffer name))))
    (with-current-buffer buffer
      (unless emacsvox-aural-editor-dirty
        (emacsvox-aural-scheme-editor-mode)
        (emacsvox-aural-inspection-attach-source source-buffer)
        (setq
         emacsvox-aural-editor-scope scope
         emacsvox-aural-editor-target
         (if (eq scope 'fragment) fragment source-buffer)
         emacsvox-aural-editor-scheme-data
         (and entry
              (copy-tree (emacsvox-aural-feature-fragment-entry-data entry)))
         emacsvox-aural-editor-rules (copy-tree rules)
         emacsvox-aural-editor-dirty nil)
        (emacsvox-aural-editor-refresh)))
    (emacsvox-aural-ui-pop-to-buffer buffer)
    buffer))

(defun emacsvox-aural-editor-open-rule
    (scope rule-id &optional source-buffer)
  "Open RULE-ID in the advanced editor for override SCOPE.

SCOPE must be `personal', `session', or `buffer'.  SOURCE-BUFFER identifies
the ordinary source whose buffer-local rules should be edited."
  (unless (memq scope '(personal session buffer))
    (user-error "Not an override scope: %S" scope))
  (let ((buffer (emacsvox-edit-aural-rules scope nil source-buffer)))
    (with-current-buffer buffer
      (let ((index
             (cl-position
              rule-id emacsvox-aural-editor-rules
              :key (lambda (rule) (plist-get rule :id)))))
        (unless index
          (user-error
           "No %s override named %S is available"
           scope rule-id))
        (when-let* ((position
                     (text-property-any
                      (point-min) (point-max)
                      emacsvox-aural-editor-rule-index-property
                      index)))
          (goto-char position)
          (when-let* ((window (get-buffer-window buffer t)))
            (set-window-point window position)))))
    buffer))

(defun emacsvox-edit-aural-feature-fragment (&optional fragment)
  "Open the declarative editor for personal feature FRAGMENT."
  (interactive)
  (emacsvox-edit-aural-rules 'fragment fragment))

(defalias 'emacsvox-aural-edit-rules
  #'emacsvox-edit-aural-rules)
(defalias 'emacsvox-aural-edit-feature-fragment
  #'emacsvox-edit-aural-feature-fragment)

(defalias 'emacsvox-aural-editor--rule-enabled-p
  #'emacsvox-aural-editor-rule-enabled-p)
(defalias 'emacsvox-aural-editor--mark-dirty
  #'emacsvox-aural-editor-mark-dirty)
(defalias 'emacsvox-aural-editor--mode-candidates
  #'emacsvox-aural-editor-mode-candidates)
(defalias 'emacsvox-aural-editor--face-candidates
  #'emacsvox-aural-editor-face-candidates)
(defalias 'emacsvox-aural-editor--read-symbol-or-nil
  #'emacsvox-aural-editor-read-symbol-or-nil)
(defalias 'emacsvox-aural-editor--read-attribute-value
  #'emacsvox-aural-editor-read-attribute-value)
(defalias 'emacsvox-aural-editor--cue-candidates
  #'emacsvox-aural-editor-cue-candidates)
(defalias 'emacsvox-aural-editor--voice-candidates
  #'emacsvox-aural-editor-voice-candidates)
(defalias 'emacsvox-aural-editor--normalized-rules
  #'emacsvox-aural-editor-normalized-rules)
(defalias 'emacsvox-aural-editor--validation-report
  #'emacsvox-aural-editor-validation-report)
(provide 'emacsvox-aural-editor)

;;; emacsvox-aural-editor.el ends here
