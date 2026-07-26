;;; emacsvox-aural-tools.el --- Aural scheme discovery and explanation -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Accessible list, describe, validation, explanation, preview, selection,
;; copy, reset, and training commands for semantic aural presentation.

;;; Code:

(require 'cl-lib)
(require 'help-mode)
(require 'pp)
(require 'subr-x)
(require 'tabulated-list)
(require 'emacsvox-aural-transport)

(cl-defstruct
    (emacsvox-aural-explanation
     (:constructor emacsvox-aural--make-explanation))
  "Reproducible explanation of one resolved aural presentation."
  scheme facts context matching-rules render-plan concrete-plan
  suppressed-actions)

(cl-defstruct
    (emacsvox-aural-validation-report
     (:constructor emacsvox-aural--make-validation-report))
  "Validation result for one registered aural scheme."
  scheme valid errors warnings missing-assets unavailable-voices
  unreachable-rules ambiguous-ties disabled-rules)

(defvar emacsvox-aural-tools--last-explanation nil
  "Most recently displayed aural presentation explanation.")

(declare-function emacsvox-icon "emacsvox-sounds" (icon))
(declare-function emacsvox-edit-aural-scheme
                  "emacsvox-aural-editor" (&optional scheme))
(declare-function emacsvox-edit-aural-scheme-advanced
                  "emacsvox-aural-editor" (&optional scheme))
(declare-function emacsvox-speak-help "emacsvox-speak" ())
(declare-function tts-speak "tts-speak" (text))

(defun emacsvox-aural-tools--point-position ()
  "Return a position at or immediately before point that can hold properties."
  (cond
   ((= (point-min) (point-max)) nil)
   ((= (point) (point-max)) (1- (point)))
   (t (point))))

(defun emacsvox-aural-tools--plan-at-point ()
  "Return the frozen concrete aural plan at point, or nil."
  (when-let* ((position (emacsvox-aural-tools--point-position)))
    (get-text-property
     position emacsvox-aural-concrete-plan-property)))

(defun emacsvox-aural-facts-at-point ()
  "Return semantic facts attached to the object at point, or nil."
  (when-let* ((position (emacsvox-aural-tools--point-position)))
    (or
     (get-text-property
      position emacsvox-aural-facts-property)
     (when-let* ((plan (emacsvox-aural-tools--plan-at-point)))
       (copy-tree (emacsvox-aural-concrete-plan-facts plan))))))

(defun emacsvox-aural-context-at-point ()
  "Return frozen presentation context at point or capture current context."
  (or
   (when-let* ((plan (emacsvox-aural-tools--plan-at-point)))
     (copy-tree (emacsvox-aural-concrete-plan-context plan)))
   (emacsvox-aural-capture-context)))

(defun emacsvox-aural-tools--context-for-occasion (context occasion)
  "Return a copy of CONTEXT whose presentation OCCASION is frozen."
  (plist-put (copy-tree context) :occasion occasion))

(defun emacsvox-aural-tools--matching-rules-for-occasion
    (facts context occasion)
  "Return rules matching FACTS in CONTEXT for OCCASION."
  (let* ((context
          (emacsvox-aural-tools--context-for-occasion context occasion))
         (rules (emacsvox-aural-current-rules context))
         (input (emacsvox-aural-normalize-input facts context)))
    (emacsvox-aural-matching-rules rules input)))

(defun emacsvox-aural-tools--occasion-match-counts (facts context)
  "Return registered occasions and matching-rule counts for FACTS and CONTEXT."
  (mapcar
   (lambda (candidate)
     (let ((occasion (intern candidate)))
       (cons
        occasion
        (length
         (emacsvox-aural-tools--matching-rules-for-occasion
          facts context occasion)))))
   (emacsvox-aural-occasion-candidates)))

(defun emacsvox-aural-tools--best-explanation-occasion (facts context)
  "Choose the most informative presentation occasion for FACTS in CONTEXT.

Prefer the current occasion when it ties for the most matching rules."
  (let* ((current (or (plist-get context :occasion) 'continuous))
         (counts
          (emacsvox-aural-tools--occasion-match-counts facts context))
         (best current)
         (best-count (or (alist-get current counts) 0)))
    (dolist (entry counts)
      (when (> (cdr entry) best-count)
        (setq best (car entry)
              best-count (cdr entry))))
    best))

(defun emacsvox-aural-tools--read-explanation-input (choose-occasion)
  "Read interactive explanation input.

Infer an informative occasion unless CHOOSE-OCCASION is non-nil, in which
case prompt with the inferred occasion as the default.  A frozen concrete
plan at point always supplies its actual occasion as the initial default."
  (let* ((plan (emacsvox-aural-tools--plan-at-point))
         (facts
          (if plan
              (copy-tree (emacsvox-aural-concrete-plan-facts plan))
            (emacsvox-aural-tools--facts-or-read)))
         (context (emacsvox-aural-context-at-point))
         (inferred
          (if plan
              (or (plist-get context :occasion) 'continuous)
            (emacsvox-aural-tools--best-explanation-occasion
             facts context)))
         (occasion
          (if choose-occasion
              (intern
               (completing-read
                "Explain aural occasion: "
                (emacsvox-aural-occasion-candidates)
                nil 'must-match nil nil (symbol-name inferred)))
            inferred)))
    (list
     facts
     (emacsvox-aural-tools--context-for-occasion context occasion))))

(defun emacsvox-aural-tools--read-semantic (&optional prompt allow-empty)
  "Read a registered semantic using PROMPT.

When ALLOW-EMPTY is non-nil, return nil for an empty answer."
  (let* ((answer
          (completing-read
           (or prompt "Aural semantic: ")
           (if allow-empty
               (cons "" (emacsvox-aural-semantic-candidates))
             (emacsvox-aural-semantic-candidates))
           nil 'must-match))
         (id (and (not (string-empty-p answer)) (intern answer))))
    id))

(defun emacsvox-aural-tools--facts-for-semantic (id)
  "Return representative facts for registered semantic ID."
  (let ((record (emacsvox-aural-semantic id)))
    (unless record
      (user-error "Unknown aural semantic: %S" id))
    (pcase (emacsvox-aural-semantic-kind record)
      ('role (list :role id))
      ('event (list :event id))
      ('state (list :state id))
      ('attribute
       (let* ((allowed (emacsvox-aural-semantic-allowed-values record))
              (value
               (cond
                (allowed
                 (intern
                  (completing-read
                   (format "%s value: " id)
                   (mapcar #'symbol-name allowed)
                   nil 'must-match)))
                ((eq
                  (emacsvox-aural-semantic-value-type record)
                  'positive-integer)
                 (let ((number
                        (read-number (format "%s value: " id))))
                   (unless (> number 0)
                     (user-error "%s must be positive" id))
                   number))
                ((eq
                  (emacsvox-aural-semantic-value-type record)
                  'integer)
                 (read-number (format "%s value: " id)))
                ((eq
                  (emacsvox-aural-semantic-value-type record)
                  'symbol)
                 (intern (read-string (format "%s value: " id))))
                (t
                 (read-string (format "%s value: " id))))))
         (list (intern (format ":%s" id)) value))))))

(defun emacsvox-aural-tools--facts-or-read ()
  "Return facts at point or interactively construct representative facts."
  (or
   (emacsvox-aural-facts-at-point)
   (emacsvox-aural-tools--facts-for-semantic
    (emacsvox-aural-tools--read-semantic))))

(defun emacsvox-aural-tools--selector-references-p (selector semantic)
  "Return non-nil when SELECTOR references SEMANTIC."
  (or
   (eq semantic (emacsvox-aural-selector-role selector))
   (memq semantic (emacsvox-aural-selector-events selector))
   (memq semantic (emacsvox-aural-selector-states selector))
   (assq semantic (emacsvox-aural-selector-attributes selector))))

(defun emacsvox-aural-tools--rules-for-semantic (semantic)
  "Return registered scheme and rule identifiers that reference SEMANTIC."
  (let (references)
    (maphash
     (lambda (scheme-id entry)
       (dolist
           (rule
            (emacsvox-aural-scheme-rules
             (emacsvox-aural-scheme-entry-compiled entry)))
         (when
             (emacsvox-aural-tools--selector-references-p
              (emacsvox-aural-rule-selector rule) semantic)
           (push
            (cons scheme-id (emacsvox-aural-rule-id rule))
            references))))
     emacsvox-aural-scheme-registry)
    (sort
     references
     (lambda (left right)
       (string-lessp
        (format "%s/%s" (car left) (cdr left))
        (format "%s/%s" (car right) (cdr right)))))))

(define-derived-mode emacsvox-aural-semantics-mode tabulated-list-mode
  "Aural-Semantics"
  "Major mode for browsing registered aural semantics."
  (setq
   tabulated-list-format
   [("Identifier" 28 t)
    ("Kind" 12 t)
    ("Owner" 18 t)
    ("Intent" 0 t)])
  (setq tabulated-list-padding 2)
  (tabulated-list-init-header))

(define-key
 emacsvox-aural-semantics-mode-map
 (kbd "RET")
 #'emacsvox-describe-aural-semantic)

(defun emacsvox-list-aural-semantics ()
  "Display registered roles, events, states, attributes, owners, and intent."
  (interactive)
  (let ((buffer (get-buffer-create "*Aural Semantics*")))
    (with-current-buffer buffer
      (emacsvox-aural-semantics-mode)
      (setq
       tabulated-list-entries
       (mapcar
        (lambda (record)
          (let ((id (emacsvox-aural-semantic-id record)))
            (list
             id
             (vector
              (symbol-name id)
              (symbol-name (emacsvox-aural-semantic-kind record))
              (symbol-name (emacsvox-aural-semantic-owner record))
              (emacsvox-aural-semantic-summary record)))))
        (emacsvox-aural-semantics)))
      (tabulated-list-print t))
    (pop-to-buffer buffer)))

(defun emacsvox-describe-aural-semantic (&optional semantic)
  "Describe registered SEMANTIC and schemes that present it."
  (interactive)
  (let* ((semantic
          (or
           semantic
           (and
            (derived-mode-p 'emacsvox-aural-semantics-mode)
            (tabulated-list-get-id))
           (emacsvox-aural-tools--read-semantic)))
         (record (emacsvox-aural-semantic semantic)))
    (unless record
      (user-error "Unknown aural semantic: %S" semantic))
    (with-help-window (help-buffer)
      (princ (format "%s\n\n" semantic))
      (princ (format "Kind: %s\n" (emacsvox-aural-semantic-kind record)))
      (princ (format "Owner: %s\n" (emacsvox-aural-semantic-owner record)))
      (princ (format "Intent: %s\n" (emacsvox-aural-semantic-summary record)))
      (when-let* ((fallback (emacsvox-aural-semantic-fallback record)))
        (princ (format "Fallback: %s\n" fallback)))
      (when-let* ((values (emacsvox-aural-semantic-allowed-values record)))
        (princ (format "Allowed values: %S\n" values)))
      (when-let* ((occasions (emacsvox-aural-semantic-occasions record)))
        (princ (format "Occasions: %S\n" occasions)))
      (when-let* ((phases (emacsvox-aural-semantic-phases record)))
        (princ (format "Phases: %S\n" phases)))
      (when-let* ((usage (emacsvox-aural-semantic-usage record)))
        (princ (format "\nUsage\n\n%s\n" usage)))
      (princ "\nRegistered presentations\n\n")
      (if-let* ((references
                 (emacsvox-aural-tools--rules-for-semantic semantic)))
          (dolist (reference references)
            (princ (format "%s / %s\n" (car reference) (cdr reference))))
        (princ "No registered scheme rule references this semantic.\n")))))

(defun emacsvox-aural-tools--all-phase-actions (operations)
  "Return every action introduced by phase OPERATIONS."
  (append
   (emacsvox-aural-phase-operations-replace operations)
   (emacsvox-aural-phase-operations-prepend operations)
   (emacsvox-aural-phase-operations-append operations)))

(defun emacsvox-aural-tools--rule-actions (rule)
  "Return every ordered action introduced by RULE."
  (let ((contribution (emacsvox-aural-rule-contribution rule)))
    (append
     (emacsvox-aural-tools--all-phase-actions
      (emacsvox-aural-contribution-before contribution))
     (emacsvox-aural-tools--all-phase-actions
      (emacsvox-aural-contribution-after contribution)))))

(defun emacsvox-aural-tools--content-patch-empty-p (patch)
  "Return non-nil when content PATCH cannot change presentation."
  (not
   (or
    (emacsvox-aural-content-patch-suppress patch)
    (emacsvox-aural-content-patch-speak-set-p patch)
    (emacsvox-aural-content-patch-voice-set-p patch)
    (emacsvox-aural-content-patch-volume-set-p patch)
    (emacsvox-aural-content-patch-space-set-p patch))))

(defun emacsvox-aural-tools--phase-empty-p (operations)
  "Return non-nil when phase OPERATIONS cannot change presentation."
  (not
   (or
    (emacsvox-aural-phase-operations-suppress operations)
    (emacsvox-aural-phase-operations-replace-set-p operations)
    (emacsvox-aural-phase-operations-remove operations)
    (emacsvox-aural-phase-operations-prepend operations)
    (emacsvox-aural-phase-operations-append operations))))

(defun emacsvox-aural-tools--rule-ineffective-p (rule)
  "Return non-nil when RULE has no presentation operation."
  (let ((contribution (emacsvox-aural-rule-contribution rule)))
    (and
     (emacsvox-aural-tools--phase-empty-p
      (emacsvox-aural-contribution-before contribution))
     (emacsvox-aural-tools--content-patch-empty-p
      (emacsvox-aural-contribution-content contribution))
     (emacsvox-aural-tools--phase-empty-p
      (emacsvox-aural-contribution-after contribution)))))

(defun emacsvox-aural-tools--ambiguous-ties (rules)
  "Return pairs in RULES requiring stable identifier tie-breaking."
  (let (ties)
    (while rules
      (let ((left (pop rules)))
        (dolist (right rules)
          (when
              (and
               (eq
                (emacsvox-aural-rule-origin left)
                (emacsvox-aural-rule-origin right))
               (= (emacsvox-aural-rule-layer-order left)
                  (emacsvox-aural-rule-layer-order right))
               (= (emacsvox-aural-rule-order left)
                  (emacsvox-aural-rule-order right))
               (equal
                (emacsvox-aural-rule-selector left)
                (emacsvox-aural-rule-selector right)))
            (push
             (cons
              (emacsvox-aural-rule-id left)
              (emacsvox-aural-rule-id right))
             ties)))))
    (nreverse ties)))

(defun emacsvox-aural-tools--rule-voices (rule)
  "Return voice values referenced by RULE."
  (let* ((contribution (emacsvox-aural-rule-contribution rule))
         (content (emacsvox-aural-contribution-content contribution))
         voices)
    (when (emacsvox-aural-content-patch-voice-set-p content)
      (push (emacsvox-aural-content-patch-voice content) voices))
    (dolist (action (emacsvox-aural-tools--rule-actions rule))
      (when (emacsvox-aural-action-voice action)
        (push (emacsvox-aural-action-voice action) voices)))
    voices))

(defun emacsvox-aural-tools--voice-available-p (voice palette)
  "Return non-nil when VOICE can be supplied by PALETTE or existing ACSS."
  (cond
   ((or (null voice) (eq voice 'inaudible)) t)
   ((eq (type-of voice) 'acss) t)
   ((and (listp voice) (proper-list-p voice))
    (cl-every
     (lambda (entry)
       (emacsvox-aural-tools--voice-available-p entry palette))
     voice))
   ((symbolp voice)
    (or
     (emacsvox-aural-voice voice palette)
     (boundp voice)))
   (t nil)))

(defun emacsvox-aural-tools--scheme-cues (rules)
  "Return unique cue names referenced by RULES."
  (let (cues)
    (dolist (rule rules)
      (dolist (action (emacsvox-aural-tools--rule-actions rule))
        (when (eq (emacsvox-aural-action-kind action) 'cue)
          (push (emacsvox-aural-action-cue action) cues))))
    (delete-dups cues)))

(defun emacsvox-aural-validate-scheme (scheme)
  "Return a complete validation report for registered SCHEME."
  (let
      (errors warnings rules all-rules missing-assets unavailable
              unreachable ties disabled)
    (condition-case error
        (progn
          (emacsvox-aural--scheme-chain scheme)
          (setq rules (emacsvox-aural-effective-scheme-rules scheme))
          (setq
           all-rules
           (cl-mapcan
            (lambda (entry)
              (copy-sequence
               (emacsvox-aural-scheme-rules
                (emacsvox-aural-scheme-entry-compiled entry))))
            (emacsvox-aural--scheme-chain scheme)))
          (setq
           disabled
           (mapcar
            #'emacsvox-aural-rule-id
            (cl-remove-if
             #'emacsvox-aural-rule-enabled all-rules)))
          (emacsvox-aural--validate-scheme-providers scheme)
          (let* ((pack
                  (emacsvox-aural-effective-scheme-provider
                   'resource-pack scheme))
                 (palette
                  (or
                   (emacsvox-aural-effective-scheme-provider
                    'voice-palette scheme)
                   'acss-default)))
            (when pack
              (let ((resource-report
                     (emacsvox-aural-validate-resource-pack
                      pack
                      (emacsvox-aural-tools--scheme-cues rules))))
                (setq
                 missing-assets
                 (emacsvox-aural-resource-report-missing-required
                  resource-report))
                (when
                    (emacsvox-aural-resource-report-missing-directory
                     resource-report)
                  (push
                   (format "Resource directory for %s is missing" pack)
                   errors))
                (when-let* ((unknown
                             (emacsvox-aural-resource-report-unknown-assets
                              resource-report)))
                  (push
                   (format "Unknown assets in %s: %S" pack unknown)
                   errors))))
            (setq
             unavailable
             (append
              (when (featurep 'voice-defs)
                (emacsvox-aural-validate-voice-palette palette))
              unavailable))
            (dolist (rule rules)
              (when (emacsvox-aural-tools--rule-ineffective-p rule)
                (push (emacsvox-aural-rule-id rule) unreachable))
              (dolist (voice (emacsvox-aural-tools--rule-voices rule))
                (unless
                    (emacsvox-aural-tools--voice-available-p voice palette)
                  (push voice unavailable))))
            (setq ties (emacsvox-aural-tools--ambiguous-ties rules))))
      (error (push (error-message-string error) errors)))
    (when missing-assets
      (push
       (format "Missing required cues: %S" missing-assets)
       errors))
    (when unavailable
      (push
       (format "Unavailable voices: %S" (delete-dups unavailable))
       errors))
    (when unreachable
      (push
       "Rules listed as unreachable contain no presentation operation"
       warnings))
    (when ties
      (push
       "Ambiguous ties are resolved only by stable rule identifier"
       warnings))
    (emacsvox-aural--make-validation-report
     :scheme scheme
     :valid (null errors)
     :errors (nreverse errors)
     :warnings (nreverse warnings)
     :missing-assets (copy-sequence missing-assets)
     :unavailable-voices (delete-dups (nreverse unavailable))
     :unreachable-rules (nreverse unreachable)
     :ambiguous-ties ties
     :disabled-rules disabled)))

(defun emacsvox-aural-tools--scheme-at-point-or-read (&optional prompt)
  "Return the scheme at point, or read one using PROMPT."
  (or
   (and
    (derived-mode-p 'emacsvox-aural-schemes-mode)
    (tabulated-list-get-id))
   (intern
    (completing-read
     (or prompt "Aural scheme: ")
     (emacsvox-aural-scheme-candidates)
     nil 'must-match nil nil
     (symbol-name emacsvox-aural-active-scheme)))))

(defun emacsvox-aural-tools--scheme-kind (entry)
  "Return a user-facing kind name for scheme ENTRY."
  (if (emacsvox-aural-scheme-entry-built-in entry)
      "built-in"
    "personal"))

(defun emacsvox-aural-tools--scheme-row (candidate)
  "Return a tabulated manager row for scheme CANDIDATE."
  (let* ((id (intern candidate))
         (entry (emacsvox-aural-scheme-entry id))
         (compiled (emacsvox-aural-scheme-entry-compiled entry))
         (direct (length (emacsvox-aural-scheme-rules compiled)))
         (effective
          (length (emacsvox-aural-effective-scheme-rules id t)))
         (report (emacsvox-aural-validate-scheme id)))
    (list
     id
     (vector
      candidate
      (if (eq id emacsvox-aural-active-scheme) "active" "")
      (emacsvox-aural-tools--scheme-kind entry)
      (if-let* ((parent (emacsvox-aural-scheme-parent compiled)))
          (symbol-name parent)
        "")
      (format
       "%s"
       (or
        (emacsvox-aural-effective-scheme-provider 'resource-pack id)
        ""))
      (format "%d direct, %d total" direct effective)
      (if (emacsvox-aural-validation-report-valid report)
          "valid"
        "invalid")
      (emacsvox-aural-scheme-summary compiled)))))

(defun emacsvox-aural-schemes--set-entries ()
  "Populate the current scheme-manager buffer."
  (setq
   tabulated-list-entries
   (mapcar
    #'emacsvox-aural-tools--scheme-row
    (emacsvox-aural-scheme-candidates))))

(defun emacsvox-aural-schemes--goto-scheme (scheme)
  "Move to SCHEME in the current scheme-manager buffer."
  (let ((start (point-min))
        found)
    (goto-char start)
    (while (and (not found) (< (point) (point-max)))
      (if (eq scheme (tabulated-list-get-id))
          (setq found t)
        (forward-line 1)))
    (unless found
      (goto-char start))
    found))

(defun emacsvox-aural-schemes-refresh (&optional scheme)
  "Refresh the scheme manager, preserving SCHEME or the current row."
  (interactive)
  (let ((selected
         (or
          scheme
          (and
           (derived-mode-p 'emacsvox-aural-schemes-mode)
           (tabulated-list-get-id)))))
    (emacsvox-aural-schemes--set-entries)
    (tabulated-list-print t)
    (when selected
      (emacsvox-aural-schemes--goto-scheme selected))))

(defun emacsvox-aural-tools--refresh-scheme-manager (&optional scheme)
  "Refresh an existing scheme-manager buffer and select SCHEME."
  (when-let* ((buffer (get-buffer "*Aural Schemes*")))
    (with-current-buffer buffer
      (when (derived-mode-p 'emacsvox-aural-schemes-mode)
        (emacsvox-aural-schemes-refresh scheme)))))

(defun emacsvox-aural-tools--selector-description (selector)
  "Return a concise natural description of compiled SELECTOR."
  (let (parts)
    (when-let* ((role (emacsvox-aural-selector-role selector)))
      (push
       (format "role %s" (emacsvox-aural-tools--humanize role))
       parts))
    (dolist (event (emacsvox-aural-selector-events selector))
      (push
       (format "event %s" (emacsvox-aural-tools--humanize event))
       parts))
    (dolist (state (emacsvox-aural-selector-states selector))
      (push
       (format "state %s" (emacsvox-aural-tools--humanize state))
       parts))
    (dolist (attribute (emacsvox-aural-selector-attributes selector))
      (push
       (format
        "%s %s"
        (emacsvox-aural-tools--humanize (car attribute))
        (emacsvox-aural-tools--humanize (cdr attribute)))
       parts))
    (when-let* ((module (emacsvox-aural-selector-module selector)))
      (push
       (format "module %s" (emacsvox-aural-tools--humanize module))
       parts))
    (when-let* ((mode (emacsvox-aural-selector-mode selector)))
      (push
       (format "mode %s" (emacsvox-aural-tools--humanize mode))
       parts))
    (when-let* ((occasion (emacsvox-aural-selector-occasion selector)))
      (push
       (format
        "occasion %s"
        (emacsvox-aural-tools--humanize occasion))
       parts))
    (when-let* ((cue (emacsvox-aural-selector-legacy-cue selector)))
      (push
       (format "legacy cue %s" (emacsvox-aural-tools--humanize cue))
       parts))
    (when (emacsvox-aural-selector-legacy-personality selector)
      (push "legacy voice property" parts))
    (if parts
        (string-join (nreverse parts) ", ")
      "all content")))

(defun emacsvox-aural-tools--print-scheme-rules (rules)
  "Print natural descriptions of compiled presentation RULES."
  (if (null rules)
      (princ "None.\n")
    (dolist (rule rules)
      (princ
       (format
        "%s%s - applies to %s\n"
        (emacsvox-aural-rule-id rule)
        (if (emacsvox-aural-rule-enabled rule) "" " (disabled)")
        (emacsvox-aural-tools--selector-description
         (emacsvox-aural-rule-selector rule)))))))

(defun emacsvox-aural-tools--scheme-spoken-summary (scheme)
  "Return a concise spoken summary of SCHEME."
  (let* ((entry (emacsvox-aural-scheme-entry scheme))
         (compiled (emacsvox-aural-scheme-entry-compiled entry))
         (parent (emacsvox-aural-scheme-parent compiled))
         (pack
          (emacsvox-aural-effective-scheme-provider
           'resource-pack scheme))
         (count
          (length (emacsvox-aural-effective-scheme-rules scheme t)))
         (report (emacsvox-aural-validate-scheme scheme)))
    (string-join
     (delq
      nil
      (list
       (format "%s." (emacsvox-aural-tools--humanize scheme))
       (format
        "%s%s scheme."
        (if (eq scheme emacsvox-aural-active-scheme) "Active " "")
        (emacsvox-aural-tools--scheme-kind entry))
       (when parent
         (format
          "Based on %s."
          (emacsvox-aural-tools--humanize parent)))
       (when pack
         (format
          "Sound pack %s."
          (emacsvox-aural-tools--humanize pack)))
       (format
        "%d effective %s."
        count
        (if (= count 1) "presentation" "presentations"))
       (if (emacsvox-aural-validation-report-valid report)
           "Valid."
         "Invalid; press v for diagnostics.")))
     " ")))

(defun emacsvox-aural-schemes-speak-current ()
  "Speak a concise description of the scheme at point."
  (interactive)
  (let* ((scheme
          (emacsvox-aural-tools--scheme-at-point-or-read))
         (summary
          (emacsvox-aural-tools--scheme-spoken-summary scheme)))
    (if (fboundp 'tts-speak)
        (tts-speak summary)
      (message "%s" summary))
    summary))

(defun emacsvox-describe-aural-scheme (&optional scheme)
  "View direct, inherited, effective, and resource details for SCHEME."
  (interactive)
  (let* ((scheme
          (or
           scheme
           (emacsvox-aural-tools--scheme-at-point-or-read
            "View aural scheme: ")))
         (entry (emacsvox-aural-scheme-entry scheme))
         (_
          (unless entry
            (user-error "Unknown aural scheme: %S" scheme)))
         (compiled (emacsvox-aural-scheme-entry-compiled entry))
         (chain (emacsvox-aural--scheme-chain scheme))
         (direct (emacsvox-aural-scheme-rules compiled))
         (inherited
          (cl-mapcan
           (lambda (ancestor)
             (copy-sequence
              (emacsvox-aural-scheme-rules
               (emacsvox-aural-scheme-entry-compiled ancestor))))
           (butlast chain)))
         (effective (emacsvox-aural-effective-scheme-rules scheme t))
         (report (emacsvox-aural-validate-scheme scheme))
         (summary
          (emacsvox-aural-tools--scheme-spoken-summary scheme)))
    (with-help-window (help-buffer)
      (princ (format "Aural scheme: %s\n\n" scheme))
      (princ (format "Status: %s\n"
                     (if (eq scheme emacsvox-aural-active-scheme)
                         "active"
                       "inactive")))
      (princ
       (format
        "Kind: %s\n"
        (emacsvox-aural-tools--scheme-kind entry)))
      (princ (format "Summary: %s\n"
                     (emacsvox-aural-scheme-summary compiled)))
      (princ
       (format
        "Based on: %s\n"
        (or (emacsvox-aural-scheme-parent compiled) "nothing")))
      (princ
       (format
        "Inheritance chain: %s\n"
        (mapconcat
         (lambda (ancestor)
           (symbol-name (emacsvox-aural-scheme-entry-id ancestor)))
         chain " -> ")))
      (princ
       (format "Source: %s\n"
               (emacsvox-aural-scheme-entry-source entry)))
      (princ "\nResources\n\n")
      (princ
       (format
        "Direct sound pack: %s\n"
        (or (emacsvox-aural-scheme-resource-pack compiled) "inherited")))
      (princ
       (format
        "Effective sound pack: %s\n"
        (or
         (emacsvox-aural-effective-scheme-provider
          'resource-pack scheme)
         "none")))
      (princ
       (format
        "Direct voice palette: %s\n"
        (or (emacsvox-aural-scheme-voice-palette compiled) "inherited")))
      (princ
       (format
        "Effective voice palette: %s\n"
        (or
         (emacsvox-aural-effective-scheme-provider
          'voice-palette scheme)
         "none")))
      (princ "\nDirect presentations\n\n")
      (emacsvox-aural-tools--print-scheme-rules direct)
      (princ "\nInherited presentations\n\n")
      (emacsvox-aural-tools--print-scheme-rules inherited)
      (princ
       (format
        "\nEffective presentation order (%d total)\n\n"
        (length effective)))
      (emacsvox-aural-tools--print-scheme-rules effective)
      (princ
       (format
        "\nValidation: %s\n"
        (if (emacsvox-aural-validation-report-valid report)
            "valid"
          "invalid")))
      (dolist (error (emacsvox-aural-validation-report-errors report))
        (princ (format "Error: %s\n" error)))
      (dolist (warning (emacsvox-aural-validation-report-warnings report))
        (princ (format "Warning: %s\n" warning))))
    (when (called-interactively-p 'interactive)
      (when (fboundp 'emacsvox-icon)
        (emacsvox-icon 'help))
      (when (fboundp 'tts-speak)
        (tts-speak summary)))
    summary))

(defun emacsvox-aural-schemes-edit ()
  "Edit the personal scheme at point in the simple spoken editor."
  (interactive)
  (let* ((scheme
          (emacsvox-aural-tools--scheme-at-point-or-read
           "Edit personal aural scheme: "))
         (entry (emacsvox-aural-scheme-entry scheme)))
    (when (emacsvox-aural-scheme-entry-built-in entry)
      (user-error
       "Built-in scheme %s is read-only; press c to copy it"
       scheme))
    (require 'emacsvox-aural-editor)
    (emacsvox-edit-aural-scheme scheme)))

(defun emacsvox-aural-schemes-edit-advanced ()
  "Edit the personal scheme at point in the advanced editor."
  (interactive)
  (let* ((scheme
          (emacsvox-aural-tools--scheme-at-point-or-read
           "Edit personal aural scheme: "))
         (entry (emacsvox-aural-scheme-entry scheme)))
    (when (emacsvox-aural-scheme-entry-built-in entry)
      (user-error
       "Built-in scheme %s is read-only; press c to copy it"
       scheme))
    (require 'emacsvox-aural-editor)
    (emacsvox-edit-aural-scheme-advanced scheme)))

(defun emacsvox-aural-schemes-copy (flattened)
  "Copy the scheme at point.

With prefix argument FLATTENED, copy effective rules instead of inheriting."
  (interactive "P")
  (let* ((source
          (emacsvox-aural-tools--scheme-at-point-or-read
           "Copy aural scheme: "))
         (answer
          (read-string
           "New personal scheme identifier: "
           (format "%s-copy" source)))
         (_
          (when (string-empty-p answer)
            (user-error "Scheme identifier cannot be empty")))
         (new-id (intern answer)))
    (emacsvox-copy-aural-scheme source new-id flattened)
    (emacsvox-aural-tools--refresh-scheme-manager new-id)
    (message
     "Created %s personal scheme %s"
     (if flattened "flattened" "inheriting")
     new-id)))

(defun emacsvox-aural-schemes-activate ()
  "Activate the scheme at point and refresh the manager."
  (interactive)
  (let ((scheme
         (emacsvox-aural-tools--scheme-at-point-or-read
          "Activate aural scheme: ")))
    (emacsvox-set-aural-scheme scheme)
    (emacsvox-aural-tools--refresh-scheme-manager scheme)
    (message "Activated aural scheme %s" scheme)))

(defun emacsvox-aural-schemes-help ()
  "Display and speak scheme-manager help."
  (interactive)
  (with-help-window (help-buffer)
    (princ
     (concat
      "Aural Scheme Manager\n\n"
      "Each row identifies whether a scheme is active, built-in or personal,\n"
      "what it inherits, its effective sound pack and presentation count.\n"
      "Use the normal line-movement keys to move between schemes.\n\n"
      "RET view details     e simple editor\n"
      "A advanced editor    c copy\n"
      "C-u c flattened copy d delete personal scheme\n"
      "r rename personal    a activate\n"
      "p preview            v validate\n"
      "SPC speak row        g refresh\n"
      "q quit\n")))
  (when (fboundp 'emacsvox-speak-help)
    (emacsvox-speak-help)))

(define-derived-mode emacsvox-aural-schemes-mode tabulated-list-mode
  "Aural-Schemes"
  "Major mode for viewing and managing registered aural schemes."
  (setq
   tabulated-list-format
   [("Scheme" 24 t)
    ("Status" 9 t)
    ("Kind" 10 t)
    ("Based on" 18 t)
    ("Sound pack" 18 t)
    ("Presentations" 22 t)
    ("Validation" 12 t)
    ("Summary" 0 t)])
  (setq tabulated-list-padding 2)
  (add-hook
   'tabulated-list-revert-hook
   #'emacsvox-aural-schemes--set-entries nil t)
  (tabulated-list-init-header))

(define-key
 emacsvox-aural-schemes-mode-map
 (kbd "RET")
 #'emacsvox-describe-aural-scheme)
(define-key
 emacsvox-aural-schemes-mode-map
 (kbd "e")
 #'emacsvox-aural-schemes-edit)
(define-key
 emacsvox-aural-schemes-mode-map
 (kbd "A")
 #'emacsvox-aural-schemes-edit-advanced)
(define-key
 emacsvox-aural-schemes-mode-map
 (kbd "c")
 #'emacsvox-aural-schemes-copy)
(define-key
 emacsvox-aural-schemes-mode-map
 (kbd "d")
 #'emacsvox-delete-aural-scheme)
(define-key
 emacsvox-aural-schemes-mode-map
 (kbd "r")
 #'emacsvox-rename-aural-scheme)
(define-key
 emacsvox-aural-schemes-mode-map
 (kbd "a")
 #'emacsvox-aural-schemes-activate)
(define-key
 emacsvox-aural-schemes-mode-map
 (kbd "p")
 #'emacsvox-preview-aural-scheme)
(define-key
 emacsvox-aural-schemes-mode-map
 (kbd "v")
 #'emacsvox-validate-aural-scheme)
(define-key
 emacsvox-aural-schemes-mode-map
 (kbd "SPC")
 #'emacsvox-aural-schemes-speak-current)
(define-key
 emacsvox-aural-schemes-mode-map
 (kbd "g")
 #'emacsvox-aural-schemes-refresh)
(define-key
 emacsvox-aural-schemes-mode-map
 (kbd "?")
 #'emacsvox-aural-schemes-help)

(defun emacsvox-list-aural-schemes ()
  "Open the accessible manager for registered aural schemes."
  (interactive)
  (let ((buffer (get-buffer-create "*Aural Schemes*")))
    (with-current-buffer buffer
      (emacsvox-aural-schemes-mode)
      (emacsvox-aural-schemes-refresh emacsvox-aural-active-scheme))
    (pop-to-buffer buffer)
    (when (called-interactively-p 'interactive)
      (emacsvox-aural-schemes-speak-current))
    buffer))

(defun emacsvox-aural-tools--display-validation (report)
  "Display validation REPORT in a help buffer."
  (with-help-window (help-buffer)
    (princ
     (format
      "Aural scheme %s: %s\n\n"
      (emacsvox-aural-validation-report-scheme report)
      (if (emacsvox-aural-validation-report-valid report)
          "valid"
        "invalid")))
    (dolist (error (emacsvox-aural-validation-report-errors report))
      (princ (format "Error: %s\n" error)))
    (dolist (warning (emacsvox-aural-validation-report-warnings report))
      (princ (format "Warning: %s\n" warning)))
    (when-let* ((rules
                 (emacsvox-aural-validation-report-unreachable-rules
                  report)))
      (princ (format "Unreachable rules: %S\n" rules)))
    (when-let* ((ties
                 (emacsvox-aural-validation-report-ambiguous-ties
                  report)))
      (princ (format "Ambiguous ties: %S\n" ties)))
    (when-let* ((disabled
                 (emacsvox-aural-validation-report-disabled-rules
                  report)))
      (princ (format "Disabled rules: %S\n" disabled)))
    (when-let* ((assets
                 (emacsvox-aural-validation-report-missing-assets
                  report)))
      (princ (format "Missing assets: %S\n" assets)))
    (when-let* ((voices
                 (emacsvox-aural-validation-report-unavailable-voices
                  report)))
      (princ (format "Unavailable voices: %S\n" voices)))))

(defun emacsvox-validate-aural-scheme (&optional scheme)
  "Validate registered SCHEME and display actionable diagnostics."
  (interactive)
  (let* ((scheme
          (or
           scheme
           (and
            (derived-mode-p 'emacsvox-aural-schemes-mode)
            (tabulated-list-get-id))
           (intern
            (completing-read
             "Validate aural scheme: "
             (emacsvox-aural-scheme-candidates)
             nil 'must-match nil nil
             (symbol-name emacsvox-aural-active-scheme)))))
         (report (emacsvox-aural-validate-scheme scheme)))
    (when (called-interactively-p 'interactive)
      (emacsvox-aural-tools--display-validation report))
    report))

(defun emacsvox-aural-tools--suppressed-action-ids (rules plan)
  "Return action identifiers introduced by RULES but absent from PLAN."
  (let ((introduced
         (mapcar
          #'emacsvox-aural-action-id
          (cl-mapcan
           (lambda (rule)
             (copy-sequence (emacsvox-aural-tools--rule-actions rule)))
           rules)))
        (retained
         (mapcar
          #'emacsvox-aural-action-id
          (append
           (emacsvox-aural-render-plan-before plan)
           (emacsvox-aural-render-plan-after plan)))))
    (cl-set-difference introduced retained :test #'eq)))

(defun emacsvox-aural-explain (facts &optional context)
  "Return a reproducible explanation for FACTS in CONTEXT."
  (let* ((context
          (copy-tree
           (or context (emacsvox-aural-capture-context))))
         (rules (emacsvox-aural-current-rules context))
         (input (emacsvox-aural-normalize-input facts context))
         (matching (emacsvox-aural-matching-rules rules input))
         (render (emacsvox-aural-resolve-active facts context))
         (concrete (emacsvox-aural-compile-plan render facts context)))
    (emacsvox-aural--make-explanation
     :scheme emacsvox-aural-active-scheme
     :facts (copy-tree facts)
     :context context
     :matching-rules
     (mapcar
      (lambda (rule)
        (list
         :id (emacsvox-aural-rule-id rule)
         :origin (emacsvox-aural-rule-origin rule)
         :source (emacsvox-aural-rule-source rule)
         :score (emacsvox-aural-rule-score rule input)))
      matching)
     :render-plan render
     :concrete-plan concrete
     :suppressed-actions
     (emacsvox-aural-tools--suppressed-action-ids matching render))))

(defun emacsvox-aural-tools--format-action (action)
  "Return a concise description of concrete ACTION."
  (let* ((balance (emacsvox-aural-concrete-action-balance action))
         (spatial
          (if (numberp balance)
              (format
               ", balance %.3f (%s)"
               balance
               (emacsvox-aural-concrete-action-spatial-capability action))
            "")))
    (concat
     (pcase (emacsvox-aural-concrete-action-kind action)
       ('cue
        (format
         "%s: cue %s -> %s"
         (emacsvox-aural-concrete-action-id action)
         (emacsvox-aural-concrete-action-cue action)
         (emacsvox-aural-concrete-action-resource action)))
       ('speech
        (format
         "%s: speak %S%s"
         (emacsvox-aural-concrete-action-id action)
         (emacsvox-aural-concrete-action-text action)
         (if-let* ((voice
                    (emacsvox-aural-concrete-action-voice-command action)))
             (format " using %S" voice)
           "")))
       ('pause
        (format
         "%s: pause %s"
         (emacsvox-aural-concrete-action-id action)
         (emacsvox-aural-concrete-action-duration action))))
     spatial)))

(defun emacsvox-describe-aural-spatial-capabilities ()
  "Describe current spatial backends and user policy."
  (interactive)
  (with-help-window (help-buffer)
    (princ "Aural spatial capabilities\n\n")
    (princ
     (format "Backends: %S\n" (emacsvox-aural-spatial-capabilities)))
    (princ
     (format
      "Enabled: %s; speech: %s; cues: %s\n"
      emacsvox-aural-spatial-enabled
      emacsvox-aural-spatial-speech-enabled
      emacsvox-aural-spatial-cue-enabled))
    (princ (format "Final output: %s\n" emacsvox-aural-spatial-output))
    (princ
     (format
      "Maximum separation: %.3f; remapping: %S\n"
      emacsvox-aural-spatial-maximum-separation
      emacsvox-aural-spatial-remapping))
    (princ
     "\nUnsupported spatial requests remain audible at the center.\n")))

(defun emacsvox-aural-tools--humanize (value)
  "Return VALUE in a form suitable for visual and spoken help."
  (cond
   ((symbolp value)
    (replace-regexp-in-string "-" " " (symbol-name value)))
   ((stringp value) value)
   (t (format "%s" value))))

(defun emacsvox-aural-tools--facts-description (facts context)
  "Return a concise natural-language description of FACTS in CONTEXT."
  (let* ((input (emacsvox-aural-normalize-input facts context))
         (parts
          (when-let* ((role (emacsvox-aural-input-role input)))
            (list (emacsvox-aural-tools--humanize role)))))
    (dolist (attribute (emacsvox-aural-input-attributes input))
      (setq
       parts
       (append
        parts
        (list
         (format
          "%s %s"
          (emacsvox-aural-tools--humanize (car attribute))
          (emacsvox-aural-tools--humanize (cdr attribute)))))))
    (dolist (state (emacsvox-aural-input-states input))
      (setq
       parts
       (append
        parts
        (list (emacsvox-aural-tools--humanize state)))))
    (dolist (event (emacsvox-aural-input-events input))
      (setq
       parts
       (append
        parts
        (list
         (format
          "event %s"
          (emacsvox-aural-tools--humanize event))))))
    (if parts
        (string-join parts ", ")
      "unclassified content")))

(defun emacsvox-aural-tools--spoken-action (action)
  "Return a concise spoken description of concrete ACTION."
  (pcase (emacsvox-aural-concrete-action-kind action)
    ('speech
     (format "say %s" (emacsvox-aural-concrete-action-text action)))
    ('cue
     (format
      "play the %s cue"
      (emacsvox-aural-tools--humanize
       (emacsvox-aural-concrete-action-cue action))))
    ('pause
     (format
      "pause for %s seconds"
      (emacsvox-aural-concrete-action-duration action)))))

(defun emacsvox-aural-tools--spoken-content (render concrete)
  "Describe resolved content from RENDER and CONCRETE for speech."
  (let* ((style (emacsvox-aural-render-plan-content render))
         (content (emacsvox-aural-concrete-plan-content concrete))
         (voice (emacsvox-aural-content-style-voice style))
         (balance (emacsvox-aural-concrete-content-balance content)))
    (if (not (emacsvox-aural-concrete-content-speak content))
        "The content is suppressed"
      (concat
       "The content is spoken"
       (if voice
           (format
            " using the %s voice"
            (emacsvox-aural-tools--humanize voice))
         " using its existing voice")
       (cond
        ((and (numberp balance) (< balance 0)) " on the left")
        ((and (numberp balance) (> balance 0)) " on the right")
        (t " in the center"))))))

(defun emacsvox-aural-tools--matching-occasion-description (counts)
  "Describe nonzero occasion match COUNTS, or return nil."
  (when-let* ((matching
               (cl-remove-if-not
                (lambda (entry) (> (cdr entry) 0))
                counts)))
    (mapconcat
     (lambda (entry)
       (format
        "%s, %d %s"
        (emacsvox-aural-tools--humanize (car entry))
        (cdr entry)
        (if (= (cdr entry) 1) "rule" "rules")))
     matching
     "; ")))

(defun emacsvox-aural-tools--spoken-explanation
    (explanation &optional occasion-counts)
  "Return a concise spoken summary of EXPLANATION.

OCCASION-COUNTS, when supplied, identifies other useful contexts when the
selected occasion has no matching rule."
  (let* ((scheme
          (or
           (emacsvox-aural-explanation-scheme explanation)
           emacsvox-aural-active-scheme))
         (facts (emacsvox-aural-explanation-facts explanation))
         (context (emacsvox-aural-explanation-context explanation))
         (rules (emacsvox-aural-explanation-matching-rules explanation))
         (render (emacsvox-aural-explanation-render-plan explanation))
         (concrete (emacsvox-aural-explanation-concrete-plan explanation))
         (before (emacsvox-aural-concrete-plan-before concrete))
         (after (emacsvox-aural-concrete-plan-after concrete))
         (occasion (plist-get context :occasion))
         (matching-occasions
          (emacsvox-aural-tools--matching-occasion-description
           occasion-counts)))
    (string-join
     (delq
      nil
      (list
       "Aural explanation."
       (format
        "Scheme %s."
        (emacsvox-aural-tools--humanize scheme))
       (format
        "%s."
        (capitalize
         (emacsvox-aural-tools--facts-description facts context)))
       (format
        "Occasion %s."
        (emacsvox-aural-tools--humanize occasion))
       (if rules
           (format
            "%d %s matched. Strongest rule %s."
            (length rules)
            (if (= (length rules) 1) "rule" "rules")
            (emacsvox-aural-tools--humanize
             (plist-get (car (last rules)) :id)))
         (concat
          "No rule matched."
          (when matching-occasions
            (format
             " Matching rules are available for %s. Use a prefix argument to choose an occasion."
             matching-occasions))))
       (when before
         (format
          "Before the content, %s."
          (mapconcat
           #'emacsvox-aural-tools--spoken-action before ", then ")))
       (concat
        (emacsvox-aural-tools--spoken-content render concrete)
        ".")
       (when after
         (format
          "After the content, %s."
          (mapconcat
           #'emacsvox-aural-tools--spoken-action after ", then ")))))
      " ")))

(defun emacsvox-aural-tools--display-explanation
    (explanation &optional speak occasion-counts)
  "Display EXPLANATION in a help buffer.

When SPEAK is non-nil, speak a concise natural-language summary rather than
the raw diagnostic buffer.  OCCASION-COUNTS describes contexts with matches."
  (let* ((render (emacsvox-aural-explanation-render-plan explanation))
         (concrete (emacsvox-aural-explanation-concrete-plan explanation))
         (content (emacsvox-aural-concrete-plan-content concrete))
         (context (emacsvox-aural-explanation-context explanation))
         (rules (emacsvox-aural-explanation-matching-rules explanation))
         (before (emacsvox-aural-concrete-plan-before concrete))
         (after (emacsvox-aural-concrete-plan-after concrete))
         (summary
          (emacsvox-aural-tools--spoken-explanation
           explanation occasion-counts))
         (matching-occasions
          (emacsvox-aural-tools--matching-occasion-description
           occasion-counts)))
    (setq emacsvox-aural-tools--last-explanation explanation)
    (with-help-window (help-buffer)
      (princ "Aural presentation explanation\n\n")
      (princ
       (format
        "Scheme: %s\n"
        (or
         (emacsvox-aural-explanation-scheme explanation)
         emacsvox-aural-active-scheme)))
      (princ
       (format
        "Object: %s\n"
        (emacsvox-aural-tools--facts-description
         (emacsvox-aural-explanation-facts explanation)
         context)))
      (princ
       (format "Occasion: %s\n" (plist-get context :occasion)))
      (princ
       (format
        "Module: %s; mode: %s\n"
        (or (plist-get context :module) "none")
        (or (plist-get context :mode) "none")))
      (when matching-occasions
        (princ
         (format
          "Occasions with matching rules: %s\n"
          matching-occasions)))
      (princ
       "Use a prefix argument with this command to choose another occasion.\n")
      (princ "\nResolved presentation order\n\n")
      (princ "Before content:\n")
      (if before
          (dolist (action before)
            (princ
             (format
              "  %s\n"
              (emacsvox-aural-tools--format-action action))))
        (princ "  Nothing.\n"))
      (princ
       (format
        "\nContent: %s.\n"
        (emacsvox-aural-tools--spoken-content render concrete)))
      (princ "After content:\n")
      (if after
          (dolist (action after)
            (princ
             (format
              "  %s\n"
              (emacsvox-aural-tools--format-action action))))
        (princ "  Nothing.\n"))
      (princ "\nMatching rules, weakest to strongest\n\n")
      (if rules
          (dolist (rule rules)
            (princ
             (format
              "%s, origin %s, score %S, source %S\n"
              (plist-get rule :id)
              (plist-get rule :origin)
              (plist-get rule :score)
              (plist-get rule :source))))
        (princ "No scheme rule matched for this occasion.\n"))
      (princ "\nTechnical details\n\n")
      (princ
       (format "Facts: %S\n" (emacsvox-aural-explanation-facts explanation)))
      (princ
       (format
        "Context: %S\n\n"
        context))
      (princ
       (format
        "Content: speak %s, voice command %S, balance %S (%s), provenance %S\n"
        (emacsvox-aural-concrete-content-speak content)
        (emacsvox-aural-concrete-content-voice-command content)
        (emacsvox-aural-concrete-content-balance content)
        (emacsvox-aural-concrete-content-spatial-capability content)
        (emacsvox-aural-content-style-provenance
         (emacsvox-aural-render-plan-content render))))
      (when-let* ((suppressed
                   (emacsvox-aural-explanation-suppressed-actions
                    explanation)))
        (princ (format "\nSuppressed or removed actions: %S\n" suppressed)))
      (when-let* ((degradations
                   (emacsvox-aural-concrete-plan-degradations concrete)))
        (princ (format "\nBackend degradation: %S\n" degradations))))
    (when speak
      (when (fboundp 'emacsvox-icon)
        (emacsvox-icon 'help))
      (when (fboundp 'tts-speak)
        (tts-speak summary)))
    summary))

(defun emacsvox-explain-aural-presentation (&optional facts context)
  "Explain presentation of FACTS in CONTEXT or semantic facts at point.

Interactively, infer the occasion that produces the most useful explanation.
With a prefix argument, prompt for the occasion.  The command displays full
technical details and speaks a concise description of the scheme, semantic
object, matching rule, and resolved before/content/after order."
  (interactive
   (emacsvox-aural-tools--read-explanation-input current-prefix-arg))
  (let* ((facts
          (or facts (emacsvox-aural-tools--facts-or-read)))
         (context
          (or context (emacsvox-aural-context-at-point)))
         (explanation (emacsvox-aural-explain facts context))
         (occasion-counts
          (and
           (called-interactively-p 'interactive)
           (emacsvox-aural-tools--occasion-match-counts facts context))))
    (when (called-interactively-p 'interactive)
      (emacsvox-aural-tools--display-explanation
       explanation t occasion-counts))
    explanation))

(defun emacsvox-aural-tools--representative-input (rule)
  "Return representative facts and context that match RULE."
  (let* ((selector (emacsvox-aural-rule-selector rule))
         (facts nil)
         (context
          (emacsvox-aural-capture-context
           (emacsvox-aural-selector-module selector)
           (or
            (emacsvox-aural-selector-occasion selector)
            'inspection))))
    (when-let* ((role (emacsvox-aural-selector-role selector)))
      (setq facts (plist-put facts :role role)))
    (when-let* ((events (emacsvox-aural-selector-events selector)))
      (setq facts (plist-put facts :events (copy-sequence events))))
    (when-let* ((states (emacsvox-aural-selector-states selector)))
      (setq facts (plist-put facts :states (copy-sequence states))))
    (dolist
        (attribute (emacsvox-aural-selector-attributes selector))
      (setq
       facts
       (plist-put
        facts
        (intern (format ":%s" (car attribute)))
        (cdr attribute))))
    (when-let* ((mode (emacsvox-aural-selector-mode selector)))
      (setq context (plist-put context :mode mode))
      (setq
       context
       (plist-put context :mode-lineage
                  (emacsvox-aural-mode-lineage mode))))
    (list facts context)))

(defun emacsvox-aural-tools--rule-candidates (&optional context)
  "Return completion candidates for rules relevant to CONTEXT."
  (mapcar
   (lambda (rule)
     (symbol-name (emacsvox-aural-rule-id rule)))
   (emacsvox-aural-current-rules
    (or context (emacsvox-aural-context-at-point)))))

(cl-defun emacsvox-preview-aural-rule
    (rule-id &optional facts (context nil context-supplied-p))
  "Resolve, compile, and play RULE-ID against FACTS and CONTEXT."
  (interactive
   (list
    (intern
     (completing-read
      "Preview aural rule: "
      (emacsvox-aural-tools--rule-candidates)
      nil 'must-match))))
  (let* ((point-facts (and (null facts) (emacsvox-aural-facts-at-point)))
         (lookup-context
          (or context (emacsvox-aural-context-at-point)))
         (rule
          (cl-find
           rule-id
           (emacsvox-aural-current-rules lookup-context)
           :key #'emacsvox-aural-rule-id
           :test #'eq)))
    (unless rule
      (user-error "Rule is not available in the current context: %S" rule-id))
    (pcase-let*
        ((`(,representative-facts ,representative-context)
          (emacsvox-aural-tools--representative-input rule))
         (facts
          (copy-tree
           (or facts
               point-facts
               representative-facts)))
         (context
          (if (or context-supplied-p point-facts)
              lookup-context
            representative-context))
         (content
          (or
           (plist-get facts :content)
           (and
            (called-interactively-p 'interactive)
            (read-string "Preview content: " "Example"))))
         (facts
          (if content (plist-put facts :content content) facts))
         (render (emacsvox-aural-resolve facts context (list rule)))
         (concrete (emacsvox-aural-compile-plan render facts context)))
      (emacsvox-aural--ensure-speaker)
      (emacsvox-aural-queue-concrete-plan concrete)
      (tts--protocol-dispatch)
      concrete)))

(defun emacsvox-preview-aural-scheme (&optional scheme rule-id)
  "Preview a representative presentation from SCHEME.

RULE-ID identifies one effective presentation.  Interactively, use the
scheme at point and prompt when it has more than one presentation."
  (interactive)
  (let* ((scheme
          (or
           scheme
           (emacsvox-aural-tools--scheme-at-point-or-read
            "Preview aural scheme: ")))
         (rules (emacsvox-aural-effective-scheme-rules scheme))
         (_
          (unless rules
            (user-error
             "Scheme %s has no effective presentations to preview"
             scheme)))
         (rule-id
          (or
           rule-id
           (if (= (length rules) 1)
               (emacsvox-aural-rule-id (car rules))
             (intern
              (completing-read
               "Preview presentation: "
               (mapcar
                (lambda (rule)
                  (symbol-name (emacsvox-aural-rule-id rule)))
                rules)
               nil 'must-match)))))
         (rule
          (cl-find
           rule-id rules
           :key #'emacsvox-aural-rule-id
           :test #'eq))
         (_
          (unless rule
            (user-error
             "Scheme %s has no presentation %s"
             scheme rule-id))))
    (pcase-let*
        ((`(,facts ,context)
          (emacsvox-aural-tools--representative-input rule))
         (content
          (if (called-interactively-p 'interactive)
              (read-string "Preview content: " "Example")
            "Example"))
         (facts (plist-put (copy-tree facts) :content content))
         (emacsvox-aural-active-scheme scheme)
         (emacsvox-aural-user-rules nil)
         (emacsvox-aural-session-rules nil)
         (emacsvox-aural-buffer-rules nil))
      (emacsvox-preview-aural-rule rule-id facts context))))

(defun emacsvox-set-aural-scheme (scheme)
  "Select registered aural SCHEME."
  (interactive
   (list
    (intern
     (completing-read
      "Set aural scheme: "
      (emacsvox-aural-scheme-candidates)
      nil 'must-match nil nil
      (symbol-name emacsvox-aural-active-scheme)))))
  (prog1
      (emacsvox-aural-select-scheme scheme)
    (when (called-interactively-p 'interactive)
      (message "Selected aural scheme %s" scheme))))

(defun emacsvox-reset-aural-scheme ()
  "Reset active aural presentation to the built-in default scheme."
  (interactive)
  (emacsvox-set-aural-scheme 'default))

(defun emacsvox-aural-tools--flattened-rules (scheme)
  "Return copied declarative inherited rules for SCHEME."
  (cl-mapcan
   (lambda (entry)
     (copy-tree
      (plist-get
       (emacsvox-aural-scheme-entry-data entry)
       :rules)))
   (emacsvox-aural--scheme-chain scheme)))

(defun emacsvox-copy-aural-scheme (source new-id &optional flattened)
  "Copy SOURCE to personal scheme NEW-ID.

By default the new scheme inherits SOURCE.  When FLATTENED is non-nil, copy
the complete effective rules and providers without a parent."
  (interactive
   (let* ((source
           (intern
            (completing-read
             "Copy aural scheme: "
             (emacsvox-aural-scheme-candidates)
             nil 'must-match)))
          (new-id
           (intern
            (read-string
             "New personal scheme identifier: "
             (format "%s-copy" source)))))
     (list source new-id current-prefix-arg)))
  (when (emacsvox-aural-scheme-entry new-id)
    (user-error "Aural scheme already exists: %S" new-id))
  (let* ((source-entry (emacsvox-aural-scheme-entry source))
         (_
          (unless source-entry
            (user-error "Unknown source aural scheme: %S" source)))
         (source-scheme
          (emacsvox-aural-scheme-entry-compiled source-entry))
         (data
          (if flattened
              (list
               :schema-version emacsvox-aural-scheme-schema-version
               :id new-id
               :summary
               (format "Editable flattened copy of %s" source)
               :resource-pack
               (emacsvox-aural-effective-scheme-provider
                'resource-pack source)
               :voice-palette
               (emacsvox-aural-effective-scheme-provider
                'voice-palette source)
               :rules (emacsvox-aural-tools--flattened-rules source))
            (list
             :schema-version emacsvox-aural-scheme-schema-version
             :id new-id
             :summary
             (format
              "Editable scheme inheriting %s: %s"
              source
              (emacsvox-aural-scheme-summary source-scheme))
             :parent source
             :rules nil))))
    (emacsvox-aural-register-scheme
     data :source emacsvox-aural-schemes-file)
    (condition-case error
        (emacsvox-aural-save-user-data)
      (error
       (remhash new-id emacsvox-aural-scheme-registry)
       (signal (car error) (cdr error))))
    (when (called-interactively-p 'interactive)
      (message "Created personal aural scheme %s" new-id))
    new-id))

(defun emacsvox-aural-tools--scheme-dependents (scheme)
  "Return schemes that directly inherit SCHEME."
  (let (dependents)
    (maphash
     (lambda (id entry)
       (when
           (eq
            scheme
            (emacsvox-aural-scheme-parent
             (emacsvox-aural-scheme-entry-compiled entry)))
         (push id dependents)))
     emacsvox-aural-scheme-registry)
    (sort
     dependents
     (lambda (left right)
       (string-lessp (symbol-name left) (symbol-name right))))))

(defun emacsvox-delete-aural-scheme (&optional scheme)
  "Delete personal SCHEME after checking active and inherited use.

A scheme with children cannot be deleted.  Deleting the active scheme
selects its parent, or the built-in default when it has no parent."
  (interactive)
  (let* ((scheme
          (or
           scheme
           (emacsvox-aural-tools--scheme-at-point-or-read
            "Delete personal aural scheme: ")))
         (entry (emacsvox-aural-scheme-entry scheme))
         (_
          (unless entry
            (user-error "Unknown aural scheme: %S" scheme)))
         (_
          (when (emacsvox-aural-scheme-entry-built-in entry)
            (user-error "Built-in scheme %s cannot be deleted" scheme)))
         (dependents
          (emacsvox-aural-tools--scheme-dependents scheme))
         (_
          (when dependents
            (user-error
             "Cannot delete %s; inherited by %s"
             scheme
             (mapconcat #'symbol-name dependents ", "))))
         (compiled (emacsvox-aural-scheme-entry-compiled entry))
         (fallback
          (or (emacsvox-aural-scheme-parent compiled) 'default))
         (active (eq scheme emacsvox-aural-active-scheme))
         (prompt
          (concat
           (format "Delete personal scheme %s? " scheme)
           (when active
             (format
              "It is active; %s will become active. "
              fallback)))))
    (when
        (or
         (not (called-interactively-p 'interactive))
         (yes-or-no-p prompt))
      (let ((registry (copy-hash-table emacsvox-aural-scheme-registry)))
        (remhash scheme registry)
        (let ((emacsvox-aural-scheme-registry registry))
          (emacsvox-aural-save-user-data))
        (setq emacsvox-aural-scheme-registry registry))
      (when active
        (emacsvox-aural-select-scheme fallback))
      (emacsvox-aural-tools--refresh-scheme-manager
       (if active fallback nil))
      (message "Deleted personal aural scheme %s" scheme)
      scheme)))

(defun emacsvox-rename-aural-scheme (&optional scheme new-id)
  "Rename personal SCHEME to NEW-ID and update direct child schemes."
  (interactive)
  (let* ((scheme
          (or
           scheme
           (emacsvox-aural-tools--scheme-at-point-or-read
            "Rename personal aural scheme: ")))
         (entry (emacsvox-aural-scheme-entry scheme))
         (_
          (unless entry
            (user-error "Unknown aural scheme: %S" scheme)))
         (_
          (when (emacsvox-aural-scheme-entry-built-in entry)
            (user-error "Built-in scheme %s cannot be renamed" scheme)))
         (answer
          (and
           (null new-id)
           (read-string
            "New personal scheme identifier: "
            (symbol-name scheme))))
         (_
          (when (and answer (string-empty-p answer))
            (user-error "Scheme identifier cannot be empty")))
         (new-id (or new-id (intern answer)))
         (_
          (when (and
                 (not (eq scheme new-id))
                 (emacsvox-aural-scheme-entry new-id))
            (user-error "Aural scheme already exists: %S" new-id)))
         (dependents
          (emacsvox-aural-tools--scheme-dependents scheme))
         (prompt
          (format
           "Rename personal scheme %s to %s%s? "
           scheme new-id
           (if dependents
               (format
                "; update %d child %s"
                (length dependents)
                (if (= (length dependents) 1) "scheme" "schemes"))
             ""))))
    (cond
     ((eq scheme new-id) scheme)
     ((and
       (called-interactively-p 'interactive)
       (not (yes-or-no-p prompt)))
      nil)
     (t
      (let ((registry (copy-hash-table emacsvox-aural-scheme-registry))
            (active (eq scheme emacsvox-aural-active-scheme)))
        (let ((emacsvox-aural-scheme-registry registry))
          (remhash scheme registry)
          (let ((data
                 (plist-put
                  (copy-tree
                   (emacsvox-aural-scheme-entry-data entry))
                  :id new-id)))
            (emacsvox-aural-register-scheme
             data
             :source (emacsvox-aural-scheme-entry-source entry)))
          (dolist (dependent dependents)
            (let* ((child (emacsvox-aural-scheme-entry dependent))
                   (data
                    (plist-put
                     (copy-tree
                      (emacsvox-aural-scheme-entry-data child))
                     :parent new-id)))
              (remhash dependent registry)
              (emacsvox-aural-register-scheme
               data
               :built-in
               (emacsvox-aural-scheme-entry-built-in child)
               :source
               (emacsvox-aural-scheme-entry-source child))))
          (maphash
           (lambda (id _)
             (emacsvox-aural--scheme-chain id)
             (emacsvox-aural-effective-scheme-rules id))
           registry)
          (emacsvox-aural-save-user-data))
        (setq emacsvox-aural-scheme-registry registry)
        (when active
          (emacsvox-aural-select-scheme new-id))
        (emacsvox-aural-tools--refresh-scheme-manager new-id)
        (message "Renamed personal aural scheme %s to %s" scheme new-id)
        new-id)))))

(defun emacsvox-reset-aural-overrides (scope)
  "Remove aural override rules from SCOPE.

SCOPE is `personal', `session', or `buffer'."
  (interactive
   (list
    (intern
     (completing-read
      "Reset aural overrides in scope: "
      '("personal" "session" "buffer")
      nil 'must-match))))
  (unless (memq scope '(personal session buffer))
    (user-error "Unknown aural override scope: %S" scope))
  (when
      (or
       (not (called-interactively-p 'interactive))
       (yes-or-no-p (format "Remove all %s aural overrides? " scope)))
    (pcase scope
      ('personal
       (setq emacsvox-aural-user-rules nil)
       (emacsvox-aural-save-user-data))
      ('session (setq emacsvox-aural-session-rules nil))
      ('buffer (setq emacsvox-aural-buffer-rules nil)))
    (when (called-interactively-p 'interactive)
      (message "Reset %s aural overrides" scope))
    t))

(defun emacsvox-aural-tools--humanize (value)
  "Return VALUE as concise spoken words."
  (replace-regexp-in-string "-" " " (format "%s" value)))

(defun emacsvox-aural-concise-explanation (facts context)
  "Return a concise spoken explanation of FACTS in CONTEXT."
  (let (parts)
    (when-let* ((role (plist-get facts :role)))
      (push (emacsvox-aural-tools--humanize role) parts))
    (dolist
        (event
         (append
          (when-let* ((one (plist-get facts :event))) (list one))
          (copy-sequence (plist-get facts :events))))
      (push (emacsvox-aural-tools--humanize event) parts))
    (dolist
        (state
         (append
          (when-let* ((one (plist-get facts :state))) (list one))
          (copy-sequence (plist-get facts :states))))
      (push (emacsvox-aural-tools--humanize state) parts))
    (dolist (record (emacsvox-aural-semantics))
      (when (eq (emacsvox-aural-semantic-kind record) 'attribute)
        (let* ((id (emacsvox-aural-semantic-id record))
               (keyword (intern (format ":%s" id))))
          (when (plist-member facts keyword)
            (push
             (format
              "%s %s"
              (emacsvox-aural-tools--humanize id)
              (emacsvox-aural-tools--humanize
               (plist-get facts keyword)))
             parts)))))
    (when-let* ((cue (plist-get context :legacy-cue)))
      (push
       (format "legacy cue %s" (emacsvox-aural-tools--humanize cue))
       parts))
    (when-let* ((occasion (plist-get context :occasion)))
      (push
       (format "%s occasion"
               (emacsvox-aural-tools--humanize occasion))
       parts))
    (if parts
        (concat (string-join (nreverse (delete-dups parts)) ", ") ".")
      "Unannotated content.")))

(defun emacsvox-aural-tools--training-presented (plan)
  "Queue a concise semantic explanation after concrete PLAN."
  (let ((text
         (emacsvox-aural-concise-explanation
          (emacsvox-aural-concrete-plan-facts plan)
          (emacsvox-aural-concrete-plan-context plan))))
    (tts--protocol-queue-code (tts-voice-reset-code))
    (tts--protocol-queue-text text)))

(define-minor-mode emacsvox-aural-training-mode
  "Speak concise semantics after each normal aural presentation."
  :global t
  :group 'emacsvox-aural
  (if emacsvox-aural-training-mode
      (add-hook
       'emacsvox-aural-plan-presented-hook
       #'emacsvox-aural-tools--training-presented)
    (remove-hook
     'emacsvox-aural-plan-presented-hook
     #'emacsvox-aural-tools--training-presented)))

(provide 'emacsvox-aural-tools)
;;; emacsvox-aural-tools.el ends here
