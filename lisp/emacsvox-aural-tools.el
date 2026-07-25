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
  facts context matching-rules render-plan concrete-plan suppressed-actions)

(cl-defstruct
    (emacsvox-aural-validation-report
     (:constructor emacsvox-aural--make-validation-report))
  "Validation result for one registered aural scheme."
  scheme valid errors warnings missing-assets unavailable-voices
  unreachable-rules ambiguous-ties disabled-rules)

(defvar emacsvox-aural-tools--last-explanation nil
  "Most recently displayed aural presentation explanation.")

(defun emacsvox-aural-tools--point-position ()
  "Return a position at or immediately before point that can hold properties."
  (cond
   ((= (point-min) (point-max)) nil)
   ((= (point) (point-max)) (1- (point)))
   (t (point))))

(defun emacsvox-aural-facts-at-point ()
  "Return semantic facts attached to the object at point, or nil."
  (when-let* ((position (emacsvox-aural-tools--point-position)))
    (or
     (get-text-property
      position emacsvox-aural-facts-property)
     (when-let* ((plan
                  (get-text-property
                   position emacsvox-aural-concrete-plan-property)))
       (copy-tree (emacsvox-aural-concrete-plan-facts plan))))))

(defun emacsvox-aural-context-at-point ()
  "Return frozen presentation context at point or capture current context."
  (or
   (when-let* ((position (emacsvox-aural-tools--point-position))
               (plan
                (get-text-property
                 position emacsvox-aural-concrete-plan-property)))
     (copy-tree (emacsvox-aural-concrete-plan-context plan)))
   (emacsvox-aural-capture-context)))

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

(define-derived-mode emacsvox-aural-schemes-mode tabulated-list-mode
  "Aural-Schemes"
  "Major mode for browsing registered aural schemes."
  (setq
   tabulated-list-format
   [("Scheme" 24 t)
    ("Active" 8 t)
    ("Parent" 18 t)
    ("Sound pack" 18 t)
    ("Voice palette" 18 t)
    ("Validation" 12 t)
    ("Summary" 0 t)])
  (setq tabulated-list-padding 2)
  (tabulated-list-init-header))

(define-key
 emacsvox-aural-schemes-mode-map
 (kbd "RET")
 #'emacsvox-validate-aural-scheme)

(defun emacsvox-list-aural-schemes ()
  "Display scheme inheritance, providers, summary, and validation state."
  (interactive)
  (let ((buffer (get-buffer-create "*Aural Schemes*")))
    (with-current-buffer buffer
      (emacsvox-aural-schemes-mode)
      (setq
       tabulated-list-entries
       (mapcar
        (lambda (candidate)
          (let* ((id (intern candidate))
                 (entry (emacsvox-aural-scheme-entry id))
                 (compiled (emacsvox-aural-scheme-entry-compiled entry))
                 (report (emacsvox-aural-validate-scheme id)))
            (list
             id
             (vector
              candidate
              (if (eq id emacsvox-aural-active-scheme) "yes" "")
              (if-let* ((parent
                         (emacsvox-aural-scheme-parent compiled)))
                  (symbol-name parent)
                "")
              (format
               "%s"
               (or
                (emacsvox-aural-effective-scheme-provider
                 'resource-pack id)
                ""))
              (format
               "%s"
               (or
                (emacsvox-aural-effective-scheme-provider
                 'voice-palette id)
                ""))
              (if
                  (emacsvox-aural-validation-report-valid report)
                  "valid"
                "invalid")
              (emacsvox-aural-scheme-summary compiled)))))
        (emacsvox-aural-scheme-candidates)))
      (tabulated-list-print t))
    (pop-to-buffer buffer)))

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
      (emacsvox-aural-concrete-action-duration action)))))

(defun emacsvox-aural-tools--display-explanation (explanation)
  "Display EXPLANATION in a help buffer."
  (let* ((render (emacsvox-aural-explanation-render-plan explanation))
         (concrete (emacsvox-aural-explanation-concrete-plan explanation))
         (content (emacsvox-aural-concrete-plan-content concrete)))
    (setq emacsvox-aural-tools--last-explanation explanation)
    (with-help-window (help-buffer)
      (princ "Aural presentation explanation\n\n")
      (princ
       (format "Facts: %S\n" (emacsvox-aural-explanation-facts explanation)))
      (princ
       (format
        "Context: %S\n\n"
        (emacsvox-aural-explanation-context explanation)))
      (princ "Matching rules, weakest to strongest\n\n")
      (if-let* ((rules
                 (emacsvox-aural-explanation-matching-rules explanation)))
          (dolist (rule rules)
            (princ
             (format
              "%s, origin %s, score %S, source %S\n"
              (plist-get rule :id)
              (plist-get rule :origin)
              (plist-get rule :score)
              (plist-get rule :source))))
        (princ "No scheme rule matched.\n"))
      (princ "\nResolved order\n\n")
      (dolist (action (emacsvox-aural-concrete-plan-before concrete))
        (princ
         (format "Before: %s\n"
                 (emacsvox-aural-tools--format-action action))))
      (princ
       (format
        "Content: speak %s, voice command %S, provenance %S\n"
        (emacsvox-aural-concrete-content-speak content)
        (emacsvox-aural-concrete-content-voice-command content)
        (emacsvox-aural-content-style-provenance
         (emacsvox-aural-render-plan-content render))))
      (dolist (action (emacsvox-aural-concrete-plan-after concrete))
        (princ
         (format "After: %s\n"
                 (emacsvox-aural-tools--format-action action))))
      (when-let* ((suppressed
                   (emacsvox-aural-explanation-suppressed-actions
                    explanation)))
        (princ (format "\nSuppressed or removed actions: %S\n" suppressed)))
      (when-let* ((degradations
                   (emacsvox-aural-concrete-plan-degradations concrete)))
        (princ (format "\nBackend degradation: %S\n" degradations))))))

(defun emacsvox-explain-aural-presentation (&optional facts context)
  "Explain presentation of FACTS in CONTEXT or semantic facts at point."
  (interactive)
  (let* ((facts
          (or facts (emacsvox-aural-tools--facts-or-read)))
         (context
          (or context (emacsvox-aural-context-at-point)))
         (explanation (emacsvox-aural-explain facts context)))
    (when (called-interactively-p 'interactive)
      (emacsvox-aural-tools--display-explanation explanation))
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
