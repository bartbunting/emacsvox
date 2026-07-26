;;; emacsvox-aural-tools.el --- Aural scheme discovery and explanation -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Accessible home, list, describe, validation, explanation, preview,
;; selection, copy, reset, and training commands for semantic presentation.

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
  suppressed-actions basis presentation-id queued-at source-location)

(cl-defstruct
    (emacsvox-aural-validation-report
     (:constructor emacsvox-aural--make-validation-report))
  "Validation result for one registered aural scheme."
  scheme valid errors warnings missing-assets unavailable-voices
  unreachable-rules ambiguous-ties disabled-rules semantic-diagnostics)

(defvar emacsvox-aural-tools--last-explanation nil
  "Most recently displayed aural presentation explanation.")

(defvar emacsvox-aural-tools--last-source-buffer nil
  "Most recent non-aural buffer used as an aural inspection source.")

(defvar-local emacsvox-aural-home-source-buffer nil
  "Source buffer inspected and customized from the aural home buffer.")

(defvar emacsvox-sounds-current-pack)
(defvar emacsvox-aural-training-mode nil
  "Non-nil when semantic training explanations are enabled.")

(declare-function emacsvox-icon "emacsvox-sounds" (icon))
(declare-function emacsvox-edit-aural-scheme
                  "emacsvox-aural-editor" (&optional scheme))
(declare-function emacsvox-edit-aural-scheme-advanced
                  "emacsvox-aural-editor" (&optional scheme))
(declare-function emacsvox-edit-aural-rules
                  "emacsvox-aural-editor"
                  (scope &optional scheme source-buffer))
(declare-function emacsvox-edit-aural-feature-fragment
                  "emacsvox-aural-editor" (&optional fragment))
(declare-function emacsvox-aural-list-sound-packs
                  "emacsvox-aural-sound-packs" (&optional pack))
(declare-function emacsvox-aural-doctor
                  "emacsvox-aural-doctor" ())
(declare-function emacsvox-aural-doctor-summary
                  "emacsvox-aural-doctor" (&optional findings))
(declare-function emacsvox-aural-list-profiles
                  "emacsvox-aural-profiles" (&optional profile))
(declare-function emacsvox-aural-profiles-status
                  "emacsvox-aural-profiles" ())
(declare-function emacsvox-aural-list-voice-palettes
                  "emacsvox-aural-voice-palettes" (&optional palette))
(declare-function emacsvox-aural-voice-palettes-status
                  "emacsvox-aural-voice-palettes" ())
(declare-function emacsvox-speak-help "emacsvox-speak" ())
(declare-function tts-speak "tts-speak" (text))
(declare-function tts-voice-reset-code "tts-speak" ())
(declare-function tts--protocol-queue-code "tts-speak" (code))
(declare-function tts--protocol-queue-text "tts-speak" (text))
(declare-function tts--protocol-dispatch "tts-speak" ())

(defun emacsvox-aural-tools--interface-buffer-p (&optional buffer)
  "Return non-nil when BUFFER is an aural manager or editor buffer."
  (with-current-buffer (or buffer (current-buffer))
    (derived-mode-p
     'emacsvox-aural-home-mode
     'emacsvox-aural-semantics-mode
     'emacsvox-aural-schemes-mode
     'emacsvox-aural-feature-fragments-mode
     'emacsvox-aural-profiles-mode
     'emacsvox-aural-voice-palettes-mode
     'emacsvox-aural-doctor-mode
     'emacsvox-aural-sound-packs-mode
     'emacsvox-aural-sound-pack-cues-mode
     'emacsvox-aural-scheme-editor-mode
     'emacsvox-aural-simple-editor-mode)))

(defun emacsvox-aural-tools--remember-source-buffer (&optional buffer)
  "Remember BUFFER as the source for aural inspection when appropriate."
  (let ((buffer (or buffer (current-buffer))))
    (when
        (and
         (buffer-live-p buffer)
         (not (minibufferp buffer))
         (not (emacsvox-aural-tools--interface-buffer-p buffer)))
      (setq emacsvox-aural-tools--last-source-buffer buffer)))
  emacsvox-aural-tools--last-source-buffer)

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
   (let ((context (emacsvox-aural-capture-context))
         (position (emacsvox-aural-tools--point-position)))
     (when position
       (let* ((provenance
               (emacsvox-aural-capture-source-faces position))
              (faces
               (mapcar
                (lambda (entry) (plist-get entry :face))
                provenance)))
         (when faces
           (setq
            context
            (plist-put context :legacy-faces (copy-sequence faces)))
           (setq
            context
            (plist-put
             context :legacy-face-source
             (emacsvox-aural--source-face-summary provenance)))
           (setq
            context
            (plist-put
             context :legacy-face-provenance
             (copy-tree provenance))))))
     context)))

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

(defun emacsvox-aural-tools--interactive-explanation-input
    (choose-occasion)
  "Return exact queued input, or simulated input when CHOOSE-OCCASION."
  (let* ((source
          (if (emacsvox-aural-tools--interface-buffer-p)
              emacsvox-aural-tools--last-source-buffer
            (current-buffer)))
         (record
          (and
           (not choose-occasion)
           source
           (emacsvox-aural-last-presentation source))))
    (if record
        (list nil nil record)
      (append
       (emacsvox-aural-tools--read-explanation-input choose-occasion)
       (list nil)))))

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
   (assq semantic (emacsvox-aural-selector-attributes selector))
   (memq
    semantic
    (emacsvox-aural-selector-required-attributes selector))))

(defun emacsvox-aural-tools--rule-references-p (rule semantic)
  "Return non-nil when RULE selects or renders SEMANTIC."
  (or
   (emacsvox-aural-tools--selector-references-p
    (emacsvox-aural-rule-selector rule) semantic)
   (cl-some
    (lambda (action)
      (memq semantic (emacsvox-aural-action-template-fields action)))
    (emacsvox-aural-tools--rule-actions rule))))

(defun emacsvox-aural-tools--rules-for-semantic (semantic)
  "Return registered presentation and rule identifiers using SEMANTIC."
  (let (references)
    (cl-labels
        ((collect
          (owner compiled)
          (dolist
              (rule (emacsvox-aural-scheme-rules compiled))
            (when
                (emacsvox-aural-tools--rule-references-p
                 rule semantic)
              (push
               (cons owner (emacsvox-aural-rule-id rule))
               references)))))
      (maphash
       (lambda (scheme-id entry)
         (collect
          scheme-id
          (emacsvox-aural-scheme-entry-compiled entry)))
       emacsvox-aural-scheme-registry)
      (maphash
       (lambda (fragment-id entry)
         (collect
          fragment-id
          (emacsvox-aural-feature-fragment-entry-compiled entry)))
       emacsvox-aural-feature-fragment-registry)
      (maphash
       (lambda (fragment-id fragment)
         (collect
          fragment-id
          (emacsvox-aural-module-fragment-compiled fragment)))
       emacsvox-aural-module-fragment-registry))
    (sort
     references
     (lambda (left right)
       (string-lessp
        (format "%s/%s" (car left) (cdr left))
        (format "%s/%s" (car right) (cdr right)))))))

(defun emacsvox-aural-semantics--set-entries ()
  "Populate the current semantic-list buffer."
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
    (emacsvox-aural-semantics))))

(defun emacsvox-aural-semantics--goto (semantic)
  "Move to SEMANTIC in the current semantic-list buffer."
  (let ((start (point-min))
        found)
    (goto-char start)
    (while (and (not found) (< (point) (point-max)))
      (if (eq semantic (tabulated-list-get-id))
          (setq found t)
        (forward-line 1)))
    (unless found
      (goto-char start))
    (when found
      (emacsvox-aural-tools--goto-tabulated-column 0))
    found))

(defun emacsvox-aural-semantics-refresh (&optional semantic)
  "Refresh the semantic list, preserving SEMANTIC and the current column."
  (interactive)
  (let ((column
         (emacsvox-aural-tools--tabulated-column-index))
        (selected (or semantic (tabulated-list-get-id))))
    (emacsvox-aural-semantics--set-entries)
    (tabulated-list-print t)
    (if selected
        (progn
          (emacsvox-aural-semantics--goto selected)
          (emacsvox-aural-tools--goto-tabulated-column column))
      (goto-char (point-min))
      (emacsvox-aural-tools--goto-tabulated-column 0))))

(defun emacsvox-aural-semantics-speak-current ()
  "Speak a concise description of the semantic at point."
  (interactive)
  (let* ((semantic
          (or
           (tabulated-list-get-id)
           (user-error "Move to a semantic row first")))
         (record (emacsvox-aural-semantic semantic))
         (summary
          (format
           "%s. %s, owner %s. %s"
           (emacsvox-aural-tools--humanize semantic)
           (emacsvox-aural-semantic-kind record)
           (emacsvox-aural-tools--humanize
            (emacsvox-aural-semantic-owner record))
           (emacsvox-aural-semantic-summary record))))
    (if (fboundp 'tts-speak)
        (tts-speak summary)
      (message "%s" summary))
    summary))

(defun emacsvox-aural-semantics-speak-current-cell ()
  "Speak the current semantic column title and value."
  (interactive)
  (emacsvox-aural-tools--speak-tabulated-cell))

(defun emacsvox-aural-semantics-next ()
  "Move to and speak the next semantic."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-row 1 "semantic list"))

(defun emacsvox-aural-semantics-previous ()
  "Move to and speak the previous semantic."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-row -1 "semantic list"))

(defun emacsvox-aural-semantics-next-column ()
  "Move right and speak the next semantic column title and value."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-column 1))

(defun emacsvox-aural-semantics-previous-column ()
  "Move left and speak the previous semantic column title and value."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-column -1))

(defun emacsvox-aural-semantics-help ()
  "Display and speak semantic-list help."
  (interactive)
  (with-help-window (help-buffer)
    (princ
     (concat
      "Aural Semantic List\n\n"
      "n or down next       p or up previous\n"
      "left/right column    . speak titled cell\n"
      "RET view details     SPC speak semantic\n"
      "g refresh            h aural home\n"
      "q quit\n")))
  (when (fboundp 'emacsvox-speak-help)
    (emacsvox-speak-help)))

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
  (add-hook
   'tabulated-list-revert-hook
   #'emacsvox-aural-semantics--set-entries nil t)
  (tabulated-list-init-header))

(dolist
    (binding
     '(("RET" . emacsvox-describe-aural-semantic)
       ("n" . emacsvox-aural-semantics-next)
       ("p" . emacsvox-aural-semantics-previous)
       ("<down>" . emacsvox-aural-semantics-next)
       ("<up>" . emacsvox-aural-semantics-previous)
       ("<right>" . emacsvox-aural-semantics-next-column)
       ("<left>" . emacsvox-aural-semantics-previous-column)
       ("." . emacsvox-aural-semantics-speak-current-cell)
       ("SPC" . emacsvox-aural-semantics-speak-current)
       ("g" . emacsvox-aural-semantics-refresh)
       ("h" . emacsvox-aural)
       ("?" . emacsvox-aural-semantics-help)))
  (define-key
   emacsvox-aural-semantics-mode-map
   (kbd (car binding))
   (cdr binding)))

(defun emacsvox-list-aural-semantics ()
  "Open the accessible list of registered semantic vocabulary."
  (interactive)
  (emacsvox-aural-tools--remember-source-buffer)
  (let ((buffer (get-buffer-create "*Aural Semantics*")))
    (with-current-buffer buffer
      (emacsvox-aural-semantics-mode)
      (emacsvox-aural-semantics-refresh))
    (pop-to-buffer buffer)
    (when (called-interactively-p 'interactive)
      (emacsvox-aural-semantics-speak-current))
    buffer))

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
      (when-let* ((roles (emacsvox-aural-semantic-roles record)))
        (princ (format "Valid roles: %S\n" roles)))
      (when-let* ((attributes (emacsvox-aural-semantic-attributes record)))
        (princ (format "Valid attributes: %S\n" attributes)))
      (when-let* ((states (emacsvox-aural-semantic-states record)))
        (princ (format "Valid states: %S\n" states)))
      (when-let* ((events (emacsvox-aural-semantic-events record)))
        (princ (format "Valid events: %S\n" events)))
      (when-let* ((occasions (emacsvox-aural-semantic-occasions record)))
        (princ (format "Occasions: %S\n" occasions)))
      (when-let* ((phases (emacsvox-aural-semantic-phases record)))
        (princ (format "Phases: %S\n" phases)))
      (when-let* ((usage (emacsvox-aural-semantic-usage record)))
        (princ (format "\nUsage\n\n%s\n" usage)))
      (when-let* ((aliases
                   (cl-remove-if-not
                    (lambda (alias)
                      (eq
                       (emacsvox-aural-canonical-semantic-id
                        (emacsvox-aural-semantic-alias-id alias))
                       (emacsvox-aural-semantic-id record)))
                    (emacsvox-aural-semantic-aliases))))
        (princ "\nDeprecated aliases\n\n")
        (dolist (alias aliases)
          (princ
           (format
            "%s, since contract version %d: %s\n"
            (emacsvox-aural-semantic-alias-id alias)
            (emacsvox-aural-semantic-alias-since-version alias)
            (or
             (emacsvox-aural-semantic-alias-summary alias)
             "Use the canonical identifier")))))
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

(defun emacsvox-aural-tools--semantic-diagnostics (rules)
  "Return alias and fallback-shadow diagnostics for compiled RULES."
  (let (diagnostics seen-aliases)
    (dolist (rule rules)
      (dolist
          (alias
           (emacsvox-aural-selector-semantic-aliases
            (emacsvox-aural-rule-selector rule)))
        (let ((id (emacsvox-aural-semantic-alias-id alias)))
          (unless (memq id seen-aliases)
            (push id seen-aliases)
            (push
             (list
              :kind 'deprecated-alias
              :rule (emacsvox-aural-rule-id rule)
              :alias id
              :canonical
              (emacsvox-aural-canonical-semantic-id id)
              :message
              (emacsvox-aural-semantic-alias-diagnostic id))
             diagnostics)))))
    (dolist (shadow (emacsvox-aural-fallback-shadow-diagnostics rules))
      (push
       (append
        (list
         :kind 'fallback-shadow
         :message
         (format
          "Rule %s selects a fallback of %s; both contribute, with %s stronger"
          (plist-get shadow :general)
          (plist-get shadow :specific)
          (plist-get shadow :specific)))
        shadow)
       diagnostics))
    (nreverse diagnostics)))

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
              unreachable ties disabled semantic-diagnostics)
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
            (setq ties (emacsvox-aural-tools--ambiguous-ties rules))
            (setq
             semantic-diagnostics
             (emacsvox-aural-tools--semantic-diagnostics rules))))
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
    (dolist (diagnostic semantic-diagnostics)
      (push (plist-get diagnostic :message) warnings))
    (emacsvox-aural--make-validation-report
     :scheme scheme
     :valid (null errors)
     :errors (nreverse errors)
     :warnings (nreverse warnings)
     :missing-assets (copy-sequence missing-assets)
     :unavailable-voices (delete-dups (nreverse unavailable))
     :unreachable-rules (nreverse unreachable)
     :ambiguous-ties ties
     :disabled-rules disabled
     :semantic-diagnostics semantic-diagnostics)))

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

(defun emacsvox-aural-tools--tabulated-column-index ()
  "Return the current tabulated column index, defaulting to the first."
  (let ((name
         (get-text-property
          (point) 'tabulated-list-column-name)))
    (or
     (and
      name
      (cl-position
       name tabulated-list-format
       :test #'string= :key #'car))
     0)))

(defun emacsvox-aural-tools--goto-tabulated-column (index)
  "Move to column INDEX on the current tabulated row."
  (let ((name (car (aref tabulated-list-format index)))
        (position (line-beginning-position))
        (limit (line-end-position))
        found)
    (while (and (< position limit) (not found))
      (if
          (equal
           name
           (get-text-property
            position 'tabulated-list-column-name))
          (setq found position)
        (setq
         position
         (next-single-property-change
          position 'tabulated-list-column-name nil limit))))
    (when found
      (goto-char found))
    found))

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
    (when found
      (emacsvox-aural-tools--goto-tabulated-column 0))
    found))

(defun emacsvox-aural-schemes-refresh (&optional scheme)
  "Refresh the scheme manager, preserving SCHEME or the current row."
  (interactive)
  (let ((column
         (and
          (null scheme)
          (derived-mode-p 'emacsvox-aural-schemes-mode)
          (emacsvox-aural-tools--tabulated-column-index)))
        (selected
         (or
          scheme
          (and
           (derived-mode-p 'emacsvox-aural-schemes-mode)
           (tabulated-list-get-id)))))
    (emacsvox-aural-schemes--set-entries)
    (tabulated-list-print t)
    (when selected
      (emacsvox-aural-schemes--goto-scheme selected)
      (when column
        (emacsvox-aural-tools--goto-tabulated-column column)))))

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
    (dolist
        (attribute
         (emacsvox-aural-selector-required-attributes selector))
      (push
       (format
        "%s present"
        (emacsvox-aural-tools--humanize attribute))
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
    (when-let* ((face (emacsvox-aural-selector-legacy-face selector)))
      (push
       (format "visual face %s" (emacsvox-aural-tools--humanize face))
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

(defun emacsvox-aural-tools--tabulated-cell-description ()
  "Return the current tabulated cell as titled spoken text."
  (let* ((entry
          (or
           (tabulated-list-get-entry)
           (user-error "Move to a tabulated row first")))
         (index (emacsvox-aural-tools--tabulated-column-index))
         (name (car (aref tabulated-list-format index)))
         (value (aref entry index))
         (value (if (listp value) (car value) value))
         (value (string-trim (format "%s" value))))
    (format
     "%s, %s"
     name
     (if (string-empty-p value) "blank" value))))

(defun emacsvox-aural-tools--speak-tabulated-cell ()
  "Speak the current tabulated column title and value."
  (let ((description
         (emacsvox-aural-tools--tabulated-cell-description)))
    (when (fboundp 'emacsvox-icon)
      (emacsvox-icon 'select-object))
    (if (fboundp 'tts-speak)
        (tts-speak description)
      (message "%s" description))
    description))

(defun emacsvox-aural-schemes-speak-current-cell ()
  "Speak the current manager column title and value."
  (interactive)
  (emacsvox-aural-tools--speak-tabulated-cell))

(defun emacsvox-aural-tools--tabulated-boundary (message)
  "Announce tabulated-list boundary MESSAGE."
  (when (fboundp 'emacsvox-icon)
    (emacsvox-icon 'warn-user))
  (if (fboundp 'tts-speak)
      (tts-speak message)
    (message "%s" message))
  message)

(defun emacsvox-aural-tools--move-tabulated-row (direction list-name)
  "Move a tabulated row in DIRECTION within LIST-NAME and speak the cell."
  (let ((origin (point))
        (column (emacsvox-aural-tools--tabulated-column-index)))
    (beginning-of-line)
    (let ((residue (forward-line direction)))
      (if (and (zerop residue) (tabulated-list-get-id))
          (progn
            (emacsvox-aural-tools--goto-tabulated-column column)
            (emacsvox-aural-tools--speak-tabulated-cell))
        (goto-char origin)
        (emacsvox-aural-tools--tabulated-boundary
         (format
          "%s of %s."
          (if (> direction 0) "Bottom" "Top")
          list-name))))))

(defun emacsvox-aural-schemes-next ()
  "Move to and speak the next scheme."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-row 1 "scheme list"))

(defun emacsvox-aural-schemes-previous ()
  "Move to and speak the previous scheme."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-row -1 "scheme list"))

(defun emacsvox-aural-tools--move-tabulated-column (direction)
  "Move a tabulated column in DIRECTION and speak its title and value."
  (let* ((index (emacsvox-aural-tools--tabulated-column-index))
         (last (1- (length tabulated-list-format)))
         (target (+ index direction)))
    (cond
     ((< target 0)
      (emacsvox-aural-tools--tabulated-boundary "First column."))
     ((> target last)
      (emacsvox-aural-tools--tabulated-boundary "Last column."))
     (t
      (emacsvox-aural-tools--goto-tabulated-column target)
      (emacsvox-aural-tools--speak-tabulated-cell)))))

(defun emacsvox-aural-schemes-next-column ()
  "Move right and speak the next manager column title and value."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-column 1))

(defun emacsvox-aural-schemes-previous-column ()
  "Move left and speak the previous manager column title and value."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-column -1))

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
      "Row and column movement speaks the column title and value.  Moving\n"
      "past the first or last row announces the list boundary.\n\n"
      "n or down next       p or up previous\n"
      "left/right column    . speak titled cell\n"
      "RET view details     e simple editor\n"
      "A advanced editor    c copy\n"
      "C-u c flattened copy d delete personal scheme\n"
      "r rename personal    a activate\n"
      "P preview            v validate\n"
      "SPC speak row        g refresh\n"
      "f feature fragments  h aural home\n"
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
 (kbd "P")
 #'emacsvox-preview-aural-scheme)
(define-key
 emacsvox-aural-schemes-mode-map
 (kbd "n")
 #'emacsvox-aural-schemes-next)
(define-key
 emacsvox-aural-schemes-mode-map
 (kbd "p")
 #'emacsvox-aural-schemes-previous)
(define-key
 emacsvox-aural-schemes-mode-map
 (kbd "<down>")
 #'emacsvox-aural-schemes-next)
(define-key
 emacsvox-aural-schemes-mode-map
 (kbd "<up>")
 #'emacsvox-aural-schemes-previous)
(define-key
 emacsvox-aural-schemes-mode-map
 (kbd "<right>")
 #'emacsvox-aural-schemes-next-column)
(define-key
 emacsvox-aural-schemes-mode-map
 (kbd "<left>")
 #'emacsvox-aural-schemes-previous-column)
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
 (kbd ".")
 #'emacsvox-aural-schemes-speak-current-cell)
(define-key
 emacsvox-aural-schemes-mode-map
 (kbd "g")
 #'emacsvox-aural-schemes-refresh)
(define-key
 emacsvox-aural-schemes-mode-map
 (kbd "?")
 #'emacsvox-aural-schemes-help)
(define-key
 emacsvox-aural-schemes-mode-map
 (kbd "f")
 #'emacsvox-aural-list-feature-fragments)
(define-key
 emacsvox-aural-schemes-mode-map
 (kbd "h")
 #'emacsvox-aural)

(defun emacsvox-list-aural-schemes ()
  "Open the accessible manager for registered aural schemes."
  (interactive)
  (emacsvox-aural-tools--remember-source-buffer)
  (let ((buffer (get-buffer-create "*Aural Schemes*")))
    (with-current-buffer buffer
      (emacsvox-aural-schemes-mode)
      (emacsvox-aural-schemes-refresh emacsvox-aural-active-scheme))
    (pop-to-buffer buffer)
    (when (called-interactively-p 'interactive)
      (emacsvox-aural-schemes-speak-current))
    buffer))

(defun emacsvox-aural-tools--display-validation (report &optional kind)
  "Display validation REPORT for object KIND in a help buffer."
  (with-help-window (help-buffer)
    (princ
     (format
      "Aural %s %s: %s\n\n"
      (or kind "scheme")
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
         (facts (emacsvox-aural-input-facts input))
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
        (let ((aliases
               (append
                (emacsvox-aural-input-semantic-aliases input)
                (emacsvox-aural-selector-semantic-aliases
                 (emacsvox-aural-rule-selector rule)))))
          (list
           :id (emacsvox-aural-rule-id rule)
           :origin (emacsvox-aural-rule-origin rule)
           :source (emacsvox-aural-rule-source rule)
           :score (emacsvox-aural-rule-score rule input)
           :semantic-matches
           (emacsvox-aural-rule-semantic-matches rule input)
           :semantic-aliases
           (mapcar
            (lambda (alias)
              (emacsvox-aural-semantic-alias-diagnostic
               (emacsvox-aural-semantic-alias-id alias)))
            aliases))))
      matching)
     :render-plan render
     :concrete-plan concrete
     :suppressed-actions
     (emacsvox-aural-tools--suppressed-action-ids matching render)
     :basis 'simulation)))

(defun emacsvox-aural-explain-record (record)
  "Return an exact explanation of frozen presentation RECORD."
  (unless (emacsvox-aural-presentation-record-p record)
    (user-error "Not an aural presentation record: %S" record))
  (let* ((concrete (emacsvox-aural-presentation-record-plan record))
         (render (emacsvox-aural-concrete-plan-source-plan concrete)))
    (emacsvox-aural--make-explanation
     :scheme (emacsvox-aural-concrete-plan-scheme concrete)
     :facts (copy-tree (emacsvox-aural-concrete-plan-facts concrete))
     :context (copy-tree (emacsvox-aural-concrete-plan-context concrete))
     :matching-rules
     (copy-tree (emacsvox-aural-concrete-plan-rule-provenance concrete))
     :render-plan render
     :concrete-plan concrete
     :suppressed-actions nil
     :basis 'exact-queued
     :presentation-id (emacsvox-aural-presentation-record-id record)
     :queued-at (copy-tree
                 (emacsvox-aural-presentation-record-queued-at record))
     :source-location
     (list
      :buffer
      (emacsvox-aural-presentation-record-source-buffer-name record)
      :position
      (emacsvox-aural-presentation-record-source-position record)))))

(defun emacsvox-aural-tools--format-action (action)
  "Return a concise description of concrete ACTION."
  (let* ((balance (emacsvox-aural-concrete-action-balance action))
         (anchor
          (or (emacsvox-aural-concrete-action-anchor action) 'undivided))
         (spatial
         (if (numberp balance)
              (format
               ", balance %.3f (%s)"
               balance
               (emacsvox-aural-concrete-action-spatial-capability action))
            ""))
         (volume
          (when-let* ((requested
                       (emacsvox-aural-concrete-action-requested-volume
                        action)))
            (format
             ", volume %S (%s)"
             requested
             (emacsvox-aural-concrete-action-volume-capability action)))))
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
     spatial
     volume
     (format ", %s anchored" anchor))))

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
    (dolist (face (emacsvox-aural-input-legacy-faces input))
      (setq
       parts
       (append
        parts
        (list
         (format
          "visual face %s"
          (emacsvox-aural-tools--humanize face))))))
    (if parts
        (string-join parts ", ")
      "unclassified content")))

(defun emacsvox-aural-tools--spoken-action (action)
  "Return a concise spoken description of concrete ACTION."
  (concat
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
       (emacsvox-aural-concrete-action-duration action))))
   (pcase (emacsvox-aural-concrete-action-anchor action)
     ('object " once for the object")
     ('run " for this formatting run")
     ('transition " at the presentation transition")
     (_ ""))))

(defun emacsvox-aural-tools--spoken-content (render concrete)
  "Describe resolved content from RENDER and CONCRETE for speech."
  (let* ((style (emacsvox-aural-render-plan-content render))
         (content (emacsvox-aural-concrete-plan-content concrete))
         (voice (emacsvox-aural-content-style-voice style))
         (voice-description
          (cond
           ((emacsvox-aural-voice-style-p voice)
            (let ((preset (plist-get voice :preset))
                  dimensions)
              (dolist (dimension emacsvox-aural-voice-dimensions)
                (let ((key
                       (emacsvox-aural--voice-dimension-key dimension)))
                  (when (plist-member voice key)
                    (push
                     (format
                      "%s %s"
                      (emacsvox-aural-tools--humanize dimension)
                      (or (plist-get voice key) "default"))
                     dimensions))))
              (string-join
               (append
                (when preset
                  (list
                   (format
                    "the %s preset"
                    (emacsvox-aural-tools--humanize preset))))
                (nreverse dimensions))
               ", with ")))
           (voice
            (format
             "the %s voice"
             (emacsvox-aural-tools--humanize voice)))
           (t "its existing voice")))
         (balance (emacsvox-aural-concrete-content-balance content)))
    (if (not (emacsvox-aural-concrete-content-speak content))
        "The content is suppressed"
      (concat
       "The content is spoken"
       (format " using %s" voice-description)
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

(defun emacsvox-aural-tools--context-control
    (context key fallback)
  "Return boolean control KEY from CONTEXT, or FALLBACK when absent."
  (if (plist-member context key)
      (plist-get context key)
    fallback))

(defun emacsvox-aural-tools--face-policy-description (context)
  "Describe frozen face and Voice Lock controls in CONTEXT."
  (format
   "Visual face scheme presentation is %s. Voice Lock is %s and controls only legacy face and personality voice mapping"
   (if
       (emacsvox-aural-tools--context-control
        context :face-presentation-enabled
        emacsvox-aural-face-presentation-enabled)
       "enabled"
     "disabled")
   (if
       (emacsvox-aural-tools--context-control
        context :voice-lock-enabled
        (emacsvox-aural-voice-lock-enabled-p))
       "enabled"
     "disabled")))

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
         (faces (plist-get context :legacy-faces))
         (face-source (plist-get context :legacy-face-source))
         (occasion (plist-get context :occasion))
         (fallback-count
          (cl-loop
           for rule in rules
           sum
           (cl-count-if
            (lambda (detail)
              (> (plist-get detail :distance) 0))
            (plist-get rule :semantic-matches))))
         (alias-diagnostics
          (delete-dups
           (cl-mapcan
            (lambda (rule)
              (copy-sequence (plist-get rule :semantic-aliases)))
            rules)))
         (matching-occasions
          (emacsvox-aural-tools--matching-occasion-description
           occasion-counts)))
    (string-join
     (delq
      nil
      (list
       "Aural explanation."
       (if
           (eq
            (emacsvox-aural-explanation-basis explanation)
            'exact-queued)
           (format
            "Exact queued presentation %s."
            (emacsvox-aural-explanation-presentation-id explanation))
         "Simulation using the current configuration.")
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
       (concat
        (emacsvox-aural-tools--face-policy-description context)
        ".")
       (when faces
         (format
          "Captured visual %s %s, strongest first, from %s."
          (if (= (length faces) 1) "face" "faces")
          (mapconcat
           #'emacsvox-aural-tools--humanize faces ", ")
          (emacsvox-aural-tools--humanize
           (or face-source 'unspecified-source))))
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
       (when (> fallback-count 0)
         (format
          "%d semantic fallback %s used; technical details give each path."
          fallback-count
          (if (= fallback-count 1) "match was" "matches were")))
       (when alias-diagnostics
         (format
          "%d deprecated semantic %s used."
          (length alias-diagnostics)
          (if (= (length alias-diagnostics) 1) "alias was" "aliases were")))
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
      (if
          (eq
           (emacsvox-aural-explanation-basis explanation)
           'exact-queued)
          (let ((location
                 (emacsvox-aural-explanation-source-location explanation)))
            (princ
             (format
              "Basis: exact queued presentation %s, heard at %s\n"
              (emacsvox-aural-explanation-presentation-id explanation)
              (format-time-string
               "%Y-%m-%d %H:%M:%S"
               (emacsvox-aural-explanation-queued-at explanation))))
            (princ
             (format
              "Source: %s at position %s\n"
              (or (plist-get location :buffer) "unknown")
              (or (plist-get location :position) "unknown"))))
        (princ
         "Basis: simulation using the current configuration; this may differ from previously heard output\n"))
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
      (when-let* ((object-id
                   (emacsvox-aural-concrete-plan-object-id concrete)))
        (princ
         (format
          "Frozen object: %S; formatting run: %S; object start: %s; object end: %s\n"
          object-id
          (emacsvox-aural-concrete-plan-run-id concrete)
          (if
              (emacsvox-aural-concrete-plan-object-start-p concrete)
              "yes"
            "no")
          (if
              (emacsvox-aural-concrete-plan-object-end-p concrete)
              "yes"
            "no"))))
      (princ
       (format
        "Module: %s; mode: %s\n"
        (or (plist-get context :module) "none")
        (or (plist-get context :mode) "none")))
      (princ
       (concat
        (emacsvox-aural-tools--face-policy-description context)
        ".\n"))
      (when-let* ((faces (plist-get context :legacy-faces)))
        (princ
         (format
          "Visual faces, strongest first: %s\n"
          (mapconcat #'symbol-name faces ", "))))
      (when-let*
          ((provenance (plist-get context :legacy-face-provenance)))
        (princ "Visual face source provenance:\n")
        (dolist (entry provenance)
          (princ
           (format
            "  %s: %s %s%s%s\n"
            (plist-get entry :face)
            (plist-get entry :source)
            (plist-get entry :property)
            (if (plist-member entry :priority)
                (format ", priority %S" (plist-get entry :priority))
              "")
            (if (plist-member entry :overlay-start)
                (format
                 ", source range %s to %s"
                 (plist-get entry :overlay-start)
                 (plist-get entry :overlay-end))
              "")))))
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
              (plist-get rule :source)))
            (dolist (detail (plist-get rule :semantic-matches))
              (princ
               (format
                "  %s: selected %s, actual %s, fallback path %S, distance %d\n"
                (plist-get detail :kind)
                (plist-get detail :selected)
                (plist-get detail :actual)
                (plist-get detail :path)
                (plist-get detail :distance))))
            (dolist
                (diagnostic
                 (delete-dups
                  (copy-sequence
                   (plist-get rule :semantic-aliases))))
              (when diagnostic
                (princ (format "  Deprecation: %s\n" diagnostic)))))
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
        (concat
         "Content: speak %s, voice command %S, balance %S (%s), "
         "volume %S (%s), "
         "provenance %S\n")
        (emacsvox-aural-concrete-content-speak content)
        (emacsvox-aural-concrete-content-voice-command content)
        (emacsvox-aural-concrete-content-balance content)
        (emacsvox-aural-concrete-content-spatial-capability content)
        (emacsvox-aural-concrete-content-requested-volume content)
        (or
         (emacsvox-aural-concrete-content-volume-capability content)
         'not-requested)
        (emacsvox-aural-content-style-provenance
         (emacsvox-aural-render-plan-content render))))
      (princ
       (format
        "Voice: requested %S, effective ACSS %S, capability %S, dimension provenance %S\n"
        (emacsvox-aural-concrete-content-voice-request content)
        (emacsvox-aural-concrete-content-voice-style content)
        (emacsvox-aural-concrete-content-voice-capability content)
        (emacsvox-aural-concrete-content-voice-provenance content)))
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

(defun emacsvox-explain-aural-presentation
    (&optional facts context record)
  "Explain exact queued RECORD or simulate FACTS in CONTEXT.

Interactively, use the last queued presentation for the source buffer when
available.  With a prefix argument, deliberately simulate an occasion chosen
by the user.  When no queued record is available, infer the occasion that
produces the most useful simulation.  The visual and spoken explanations
always identify whether they describe heard output or a simulation."
  (interactive
   (emacsvox-aural-tools--interactive-explanation-input
    current-prefix-arg))
  (when (called-interactively-p 'interactive)
    (emacsvox-aural-tools--remember-source-buffer))
  (let* ((facts
          (and
           (null record)
           (or facts (emacsvox-aural-tools--facts-or-read))))
         (context
          (and
           (null record)
           (or context (emacsvox-aural-context-at-point))))
         (explanation
          (if record
              (emacsvox-aural-explain-record record)
            (emacsvox-aural-explain facts context)))
         (occasion-counts
          (and
           (null record)
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
    (dolist
        (attribute
         (emacsvox-aural-selector-required-attributes selector))
      (unless
          (assq attribute (emacsvox-aural-selector-attributes selector))
        (let* ((record (emacsvox-aural-semantic attribute))
               (value
                (or
                 (car (emacsvox-aural-semantic-allowed-values record))
                 (pcase (emacsvox-aural-semantic-value-type record)
                   ('positive-integer 1)
                   ('integer 0)
                   ('number 0)
                   ('string "example")
                   ('symbol 'example)
                   ('boolean t)
                   (_ 'example)))))
          (setq
           facts
           (plist-put
            facts
            (intern (format ":%s" attribute))
            value)))))
    (when-let* ((mode (emacsvox-aural-selector-mode selector)))
      (setq context (plist-put context :mode mode))
      (setq
       context
       (plist-put context :mode-lineage
                  (emacsvox-aural-mode-lineage mode))))
    (when-let* ((face (emacsvox-aural-selector-legacy-face selector)))
      (setq context (plist-put context :legacy-faces (list face)))
      (setq context (plist-put context :legacy-face-source 'preview)))
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
        (setq emacsvox-aural-scheme-registry registry)
        (emacsvox-aural-configuration-changed 'scheme-deleted))
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
        (emacsvox-aural-configuration-changed 'scheme-renamed)
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
    (emacsvox-aural-configuration-changed 'override-reset)
    (when (called-interactively-p 'interactive)
      (message "Reset %s aural overrides" scope))
    t))

(defun emacsvox-aural-validate-feature-fragment (fragment)
  "Return a validation report for registered feature FRAGMENT."
  (let
      (errors warnings rules all-rules missing-assets unavailable
              unreachable ties disabled semantic-diagnostics)
    (condition-case error
        (let* ((entry
                (or
                 (emacsvox-aural-feature-fragment-entry fragment)
                 (emacsvox-aural--scheme-error
                  "Unknown feature fragment: %S" fragment)))
               (compiled
                (emacsvox-aural-feature-fragment-entry-compiled entry))
               (pack
                (emacsvox-aural-effective-scheme-provider 'resource-pack))
               (palette
                (or
                 (emacsvox-aural-effective-scheme-provider 'voice-palette)
                 'acss-default)))
          (setq
           all-rules
           (copy-sequence (emacsvox-aural-scheme-rules compiled))
           rules
           (cl-remove-if-not #'emacsvox-aural-rule-enabled all-rules)
           disabled
           (mapcar
            #'emacsvox-aural-rule-id
            (cl-remove-if #'emacsvox-aural-rule-enabled all-rules)))
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
                 errors))))
          (when (featurep 'voice-defs)
            (setq
             unavailable
             (emacsvox-aural-validate-voice-palette palette)))
          (dolist (rule rules)
            (when (emacsvox-aural-tools--rule-ineffective-p rule)
              (push (emacsvox-aural-rule-id rule) unreachable))
            (dolist (voice (emacsvox-aural-tools--rule-voices rule))
              (unless
                  (emacsvox-aural-tools--voice-available-p voice palette)
                (push voice unavailable))))
          (setq ties (emacsvox-aural-tools--ambiguous-ties rules))
          (setq
           semantic-diagnostics
           (emacsvox-aural-tools--semantic-diagnostics rules)))
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
    (dolist (diagnostic semantic-diagnostics)
      (push (plist-get diagnostic :message) warnings))
    (emacsvox-aural--make-validation-report
     :scheme fragment
     :valid (null errors)
     :errors (nreverse errors)
     :warnings (nreverse warnings)
     :missing-assets (copy-sequence missing-assets)
     :unavailable-voices (delete-dups (nreverse unavailable))
     :unreachable-rules (nreverse unreachable)
     :ambiguous-ties ties
     :disabled-rules disabled
     :semantic-diagnostics semantic-diagnostics)))

(defun emacsvox-aural-tools--fragment-at-point-or-read (&optional prompt)
  "Return the feature fragment at point, or read one using PROMPT."
  (or
   (and
    (derived-mode-p 'emacsvox-aural-feature-fragments-mode)
    (tabulated-list-get-id))
   (let ((candidates (emacsvox-aural-feature-fragment-candidates)))
     (unless candidates
       (user-error "No feature fragments are registered"))
     (intern
      (completing-read
       (or prompt "Aural feature fragment: ")
       candidates nil 'must-match)))))

(defun emacsvox-aural-tools--ordered-feature-fragment-ids ()
  "Return enabled feature fragment IDs first, then disabled IDs."
  (append
   (copy-sequence emacsvox-aural-enabled-feature-fragments)
   (cl-loop
    for candidate in (emacsvox-aural-feature-fragment-candidates)
    for id = (intern candidate)
    unless (memq id emacsvox-aural-enabled-feature-fragments)
    collect id)))

(defun emacsvox-aural-tools--fragment-kind (entry)
  "Return a user-facing kind name for feature fragment ENTRY."
  (if (emacsvox-aural-feature-fragment-entry-built-in entry)
      "built-in"
    "personal"))

(defun emacsvox-aural-tools--fragment-row (id)
  "Return a tabulated manager row for feature fragment ID."
  (let* ((entry (emacsvox-aural-feature-fragment-entry id))
         (compiled
          (emacsvox-aural-feature-fragment-entry-compiled entry))
         (position
          (cl-position id emacsvox-aural-enabled-feature-fragments))
         (report (emacsvox-aural-validate-feature-fragment id)))
    (list
     id
     (vector
      (symbol-name id)
      (if position (format "enabled %d" (1+ position)) "disabled")
      (emacsvox-aural-tools--fragment-kind entry)
      (format
       "%d"
       (length (emacsvox-aural-scheme-rules compiled)))
      (if (emacsvox-aural-validation-report-valid report)
          "valid"
        "invalid")
      (emacsvox-aural-scheme-summary compiled)))))

(defun emacsvox-aural-feature-fragments--set-entries ()
  "Populate the current feature-fragment manager."
  (setq
   tabulated-list-entries
   (mapcar
    #'emacsvox-aural-tools--fragment-row
    (emacsvox-aural-tools--ordered-feature-fragment-ids))))

(defun emacsvox-aural-feature-fragments--goto (fragment)
  "Move to feature FRAGMENT in the current manager."
  (let ((start (point-min))
        found)
    (goto-char start)
    (while (and (not found) (< (point) (point-max)))
      (if (eq fragment (tabulated-list-get-id))
          (setq found t)
        (forward-line 1)))
    (unless found
      (goto-char start))
    (when found
      (emacsvox-aural-tools--goto-tabulated-column 0))
    found))

(defun emacsvox-aural-feature-fragments-refresh (&optional fragment)
  "Refresh the feature-fragment manager, preserving FRAGMENT and column."
  (interactive)
  (let ((column
         (and
          (null fragment)
          (derived-mode-p 'emacsvox-aural-feature-fragments-mode)
          (emacsvox-aural-tools--tabulated-column-index)))
        (selected
         (or
          fragment
          (and
           (derived-mode-p 'emacsvox-aural-feature-fragments-mode)
           (tabulated-list-get-id)))))
    (emacsvox-aural-feature-fragments--set-entries)
    (tabulated-list-print t)
    (when selected
      (emacsvox-aural-feature-fragments--goto selected)
      (when column
        (emacsvox-aural-tools--goto-tabulated-column column)))))

(defun emacsvox-aural-tools--refresh-fragment-manager (&optional fragment)
  "Refresh an existing feature-fragment manager and select FRAGMENT."
  (when-let* ((buffer (get-buffer "*Aural Feature Fragments*")))
    (with-current-buffer buffer
      (when (derived-mode-p 'emacsvox-aural-feature-fragments-mode)
        (emacsvox-aural-feature-fragments-refresh fragment)))))

(defun emacsvox-aural-tools--fragment-spoken-summary (fragment)
  "Return a concise spoken summary of feature FRAGMENT."
  (let* ((entry (emacsvox-aural-feature-fragment-entry fragment))
         (compiled
          (emacsvox-aural-feature-fragment-entry-compiled entry))
         (position
          (cl-position fragment emacsvox-aural-enabled-feature-fragments))
         (count (length (emacsvox-aural-scheme-rules compiled)))
         (report (emacsvox-aural-validate-feature-fragment fragment)))
    (format
     "%s. %s feature fragment. %s. %s. %d %s. %s."
     (emacsvox-aural-tools--humanize fragment)
     (emacsvox-aural-tools--fragment-kind entry)
     (if position
         (format "Enabled at position %d" (1+ position))
       "Disabled")
     (emacsvox-aural-scheme-summary compiled)
     count
     (if (= count 1) "presentation" "presentations")
     (if (emacsvox-aural-validation-report-valid report)
         "Valid"
       "Invalid; press v for diagnostics"))))

(defun emacsvox-aural-feature-fragments-speak-current ()
  "Speak a concise description of the feature fragment at point."
  (interactive)
  (let* ((fragment
          (emacsvox-aural-tools--fragment-at-point-or-read))
         (summary
          (emacsvox-aural-tools--fragment-spoken-summary fragment)))
    (if (fboundp 'tts-speak)
        (tts-speak summary)
      (message "%s" summary))
    summary))

(defun emacsvox-aural-feature-fragments-speak-current-cell ()
  "Speak the current feature-fragment column title and value."
  (interactive)
  (emacsvox-aural-tools--speak-tabulated-cell))

(defun emacsvox-aural-feature-fragments-next ()
  "Move to and speak the next feature fragment."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-row
   1 "feature fragment list"))

(defun emacsvox-aural-feature-fragments-previous ()
  "Move to and speak the previous feature fragment."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-row
   -1 "feature fragment list"))

(defun emacsvox-aural-feature-fragments-next-column ()
  "Move right and speak the next feature-fragment column."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-column 1))

(defun emacsvox-aural-feature-fragments-previous-column ()
  "Move left and speak the previous feature-fragment column."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-column -1))

(defun emacsvox-aural-describe-feature-fragment (&optional fragment)
  "Describe registered feature FRAGMENT and its presentations."
  (interactive)
  (let* ((fragment
          (or
           fragment
           (emacsvox-aural-tools--fragment-at-point-or-read
            "View feature fragment: ")))
         (entry
          (or
           (emacsvox-aural-feature-fragment-entry fragment)
           (user-error "Unknown feature fragment: %S" fragment)))
         (compiled
          (emacsvox-aural-feature-fragment-entry-compiled entry))
         (report (emacsvox-aural-validate-feature-fragment fragment))
         (summary
          (emacsvox-aural-tools--fragment-spoken-summary fragment)))
    (with-help-window (help-buffer)
      (princ (format "Aural feature fragment: %s\n\n" fragment))
      (princ
       (format
        "Status: %s\n"
        (if-let* ((position
                   (cl-position
                    fragment emacsvox-aural-enabled-feature-fragments)))
            (format "enabled at position %d" (1+ position))
          "disabled")))
      (princ
       (format
        "Kind: %s\n"
        (emacsvox-aural-tools--fragment-kind entry)))
      (princ
       (format "Summary: %s\n"
               (emacsvox-aural-scheme-summary compiled)))
      (princ
       (format
        "Source: %s\n\nPresentations\n\n"
        (emacsvox-aural-feature-fragment-entry-source entry)))
      (emacsvox-aural-tools--print-scheme-rules
       (emacsvox-aural-scheme-rules compiled))
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

(defun emacsvox-aural-tools--install-feature-fragment-state
    (registry enabled)
  "Validate and persist feature-fragment REGISTRY and ENABLED order."
  (emacsvox-aural--validate-enabled-feature-fragments enabled registry)
  (let ((old-registry emacsvox-aural-feature-fragment-registry)
        (old-enabled emacsvox-aural-enabled-feature-fragments))
    (setq
     emacsvox-aural-feature-fragment-registry registry
     emacsvox-aural-enabled-feature-fragments (copy-sequence enabled))
    (condition-case error
        (progn
          (emacsvox-aural-current-rules
           (emacsvox-aural-context-at-point))
          (emacsvox-aural-save-user-data))
      (error
       (setq
        emacsvox-aural-feature-fragment-registry old-registry
        emacsvox-aural-enabled-feature-fragments old-enabled)
       (signal (car error) (cdr error))))
    (emacsvox-aural-configuration-changed 'feature-fragments)
    (run-hooks 'emacsvox-aural-feature-fragments-changed-hook)
    enabled))

(defun emacsvox-aural-create-feature-fragment (id &optional summary)
  "Create disabled personal feature fragment ID with SUMMARY."
  (interactive
   (let* ((answer (read-string "New feature fragment identifier: "))
          (_
           (when (string-empty-p answer)
             (user-error "Feature fragment identifier cannot be empty"))))
     (list (intern answer) nil)))
  (when (emacsvox-aural-feature-fragment-entry id)
    (user-error "Feature fragment already exists: %S" id))
  (let ((registry
         (copy-hash-table emacsvox-aural-feature-fragment-registry))
        (data
         (list
          :schema-version emacsvox-aural-scheme-schema-version
          :id id
          :summary
          (or summary (format "Personal feature fragment %s" id))
          :rules nil)))
    (let ((emacsvox-aural-feature-fragment-registry registry))
      (emacsvox-aural-register-feature-fragment
       data :source emacsvox-aural-schemes-file))
    (emacsvox-aural-tools--install-feature-fragment-state
     registry emacsvox-aural-enabled-feature-fragments)
    (emacsvox-aural-tools--refresh-fragment-manager id)
    (when (called-interactively-p 'interactive)
      (require 'emacsvox-aural-editor)
      (emacsvox-edit-aural-feature-fragment id))
    id))

(defun emacsvox-aural-copy-feature-fragment (source new-id)
  "Copy feature fragment SOURCE to disabled personal fragment NEW-ID."
  (interactive
   (let* ((source
           (emacsvox-aural-tools--fragment-at-point-or-read
            "Copy feature fragment: "))
          (answer
           (read-string
            "New personal feature fragment identifier: "
            (format "%s-copy" source))))
     (when (string-empty-p answer)
       (user-error "Feature fragment identifier cannot be empty"))
     (list source (intern answer))))
  (when (emacsvox-aural-feature-fragment-entry new-id)
    (user-error "Feature fragment already exists: %S" new-id))
  (let* ((source-entry
          (or
           (emacsvox-aural-feature-fragment-entry source)
           (user-error "Unknown feature fragment: %S" source)))
         (data
          (plist-put
           (copy-tree
            (emacsvox-aural-feature-fragment-entry-data source-entry))
           :id new-id))
         (data
          (plist-put
           data :summary
           (format "Editable copy of %s: %s"
                   source
                   (plist-get data :summary))))
         (registry
          (copy-hash-table emacsvox-aural-feature-fragment-registry)))
    (let ((emacsvox-aural-feature-fragment-registry registry))
      (emacsvox-aural-register-feature-fragment
       data :source emacsvox-aural-schemes-file))
    (emacsvox-aural-tools--install-feature-fragment-state
     registry emacsvox-aural-enabled-feature-fragments)
    (emacsvox-aural-tools--refresh-fragment-manager new-id)
    (message "Created personal feature fragment %s" new-id)
    new-id))

(defun emacsvox-aural-delete-feature-fragment (&optional fragment)
  "Delete personal feature FRAGMENT, disabling it when necessary."
  (interactive)
  (let* ((fragment
          (or
           fragment
           (emacsvox-aural-tools--fragment-at-point-or-read
            "Delete personal feature fragment: ")))
         (entry
          (or
           (emacsvox-aural-feature-fragment-entry fragment)
           (user-error "Unknown feature fragment: %S" fragment))))
    (when (emacsvox-aural-feature-fragment-entry-built-in entry)
      (user-error "Built-in feature fragment %s cannot be deleted" fragment))
    (when
        (or
         (not (called-interactively-p 'interactive))
         (yes-or-no-p
          (format
           "Delete personal feature fragment %s%s? "
           fragment
           (if (emacsvox-aural-feature-fragment-enabled-p fragment)
               " and disable it"
             ""))))
      (let ((registry
             (copy-hash-table
              emacsvox-aural-feature-fragment-registry))
            (enabled
             (delq
              fragment
              (copy-sequence emacsvox-aural-enabled-feature-fragments))))
        (remhash fragment registry)
        (emacsvox-aural-tools--install-feature-fragment-state
         registry enabled))
      (emacsvox-aural-tools--refresh-fragment-manager)
      (message "Deleted personal feature fragment %s" fragment)
      fragment)))

(defun emacsvox-aural-feature-fragments-toggle (&optional fragment)
  "Enable or disable feature FRAGMENT and persist the new order."
  (interactive)
  (let* ((fragment
          (or
           fragment
           (emacsvox-aural-tools--fragment-at-point-or-read)))
         (enabled-p
          (emacsvox-aural-feature-fragment-enabled-p fragment))
         (enabled
          (if enabled-p
              (delq
               fragment
               (copy-sequence emacsvox-aural-enabled-feature-fragments))
            (append
             emacsvox-aural-enabled-feature-fragments
             (list fragment)))))
    (emacsvox-aural-tools--install-feature-fragment-state
     (copy-hash-table emacsvox-aural-feature-fragment-registry)
     enabled)
    (emacsvox-aural-tools--refresh-fragment-manager fragment)
    (message
     "%s feature fragment %s"
     (if enabled-p "Disabled" "Enabled")
     fragment)
    (not enabled-p)))

(defun emacsvox-aural-feature-fragments-move (offset)
  "Move the enabled feature fragment at point by OFFSET."
  (let* ((fragment
          (emacsvox-aural-tools--fragment-at-point-or-read))
         (index
          (cl-position fragment emacsvox-aural-enabled-feature-fragments)))
    (unless index
      (user-error "Enable %s before ordering it" fragment))
    (let ((destination (+ index offset)))
      (if (not
           (< -1 destination
              (length emacsvox-aural-enabled-feature-fragments)))
          (emacsvox-aural-tools--tabulated-boundary
           (if (< offset 0)
               "First enabled feature fragment."
             "Last enabled feature fragment."))
        (let ((enabled
               (copy-sequence
                emacsvox-aural-enabled-feature-fragments)))
          (cl-rotatef
           (nth index enabled)
           (nth destination enabled))
          (emacsvox-aural-tools--install-feature-fragment-state
           (copy-hash-table
            emacsvox-aural-feature-fragment-registry)
           enabled)
          (emacsvox-aural-tools--refresh-fragment-manager fragment)
          (emacsvox-aural-feature-fragments-speak-current))))))

(defun emacsvox-aural-feature-fragments-move-up ()
  "Move the enabled feature fragment at point earlier."
  (interactive)
  (emacsvox-aural-feature-fragments-move -1))

(defun emacsvox-aural-feature-fragments-move-down ()
  "Move the enabled feature fragment at point later."
  (interactive)
  (emacsvox-aural-feature-fragments-move 1))

(defun emacsvox-aural-feature-fragments-edit ()
  "Edit the personal feature fragment at point."
  (interactive)
  (let* ((fragment
          (emacsvox-aural-tools--fragment-at-point-or-read))
         (entry (emacsvox-aural-feature-fragment-entry fragment)))
    (when (emacsvox-aural-feature-fragment-entry-built-in entry)
      (user-error
       "Built-in feature fragment %s is read-only; press c to copy it"
       fragment))
    (require 'emacsvox-aural-editor)
    (emacsvox-edit-aural-feature-fragment fragment)))

(defun emacsvox-aural-show-feature-fragment-validation
    (&optional fragment)
  "Validate feature FRAGMENT and display actionable diagnostics."
  (interactive)
  (let* ((fragment
          (or
           fragment
           (emacsvox-aural-tools--fragment-at-point-or-read)))
         (report
          (emacsvox-aural-validate-feature-fragment fragment)))
    (when (called-interactively-p 'interactive)
      (emacsvox-aural-tools--display-validation
       report "feature fragment"))
    report))

(defun emacsvox-aural-feature-fragments-help ()
  "Display and speak feature-fragment manager help."
  (interactive)
  (with-help-window (help-buffer)
    (princ
     (concat
      "Aural Feature Fragment Manager\n\n"
      "One base scheme is active.  Enabled feature fragments add independent\n"
      "presentation in the displayed order.  Personal overrides remain stronger.\n"
      "Row and column movement speaks titles, values, and list boundaries.\n\n"
      "n or down next       p or up previous\n"
      "left/right column    . speak titled cell\n"
      "RET view details     SPC speak row\n"
      "t enable/disable     M-up/M-down reorder enabled fragments\n"
      "N create personal    c copy as personal\n"
      "e edit personal      d delete personal\n"
      "v validate           g refresh\n"
      "s scheme manager     h aural home\n"
      "q quit\n")))
  (when (fboundp 'emacsvox-speak-help)
    (emacsvox-speak-help)))

(define-derived-mode
    emacsvox-aural-feature-fragments-mode tabulated-list-mode
  "Aural-Fragments"
  "Major mode for viewing and managing aural feature fragments."
  (setq
   tabulated-list-format
   [("Fragment" 28 t)
    ("Status" 12 t)
    ("Kind" 10 t)
    ("Rules" 8 t)
    ("Validation" 12 t)
    ("Summary" 0 t)])
  (setq tabulated-list-padding 2)
  (add-hook
   'tabulated-list-revert-hook
   #'emacsvox-aural-feature-fragments--set-entries nil t)
  (tabulated-list-init-header))

(dolist
    (binding
     '(("RET" . emacsvox-aural-describe-feature-fragment)
       ("SPC" . emacsvox-aural-feature-fragments-speak-current)
       ("." . emacsvox-aural-feature-fragments-speak-current-cell)
       ("n" . emacsvox-aural-feature-fragments-next)
       ("p" . emacsvox-aural-feature-fragments-previous)
       ("<down>" . emacsvox-aural-feature-fragments-next)
       ("<up>" . emacsvox-aural-feature-fragments-previous)
       ("<right>" . emacsvox-aural-feature-fragments-next-column)
       ("<left>" . emacsvox-aural-feature-fragments-previous-column)
       ("t" . emacsvox-aural-feature-fragments-toggle)
       ("<M-up>" . emacsvox-aural-feature-fragments-move-up)
       ("<M-down>" . emacsvox-aural-feature-fragments-move-down)
       ("N" . emacsvox-aural-create-feature-fragment)
       ("c" . emacsvox-aural-copy-feature-fragment)
       ("e" . emacsvox-aural-feature-fragments-edit)
       ("d" . emacsvox-aural-delete-feature-fragment)
       ("v" . emacsvox-aural-show-feature-fragment-validation)
       ("g" . emacsvox-aural-feature-fragments-refresh)
       ("s" . emacsvox-aural-list-schemes)
       ("h" . emacsvox-aural)
       ("?" . emacsvox-aural-feature-fragments-help)))
  (define-key
   emacsvox-aural-feature-fragments-mode-map
   (kbd (car binding))
   (cdr binding)))

(defun emacsvox-aural-list-feature-fragments ()
  "Open the accessible manager for aural feature fragments."
  (interactive)
  (emacsvox-aural-tools--remember-source-buffer)
  (let ((buffer (get-buffer-create "*Aural Feature Fragments*")))
    (with-current-buffer buffer
      (emacsvox-aural-feature-fragments-mode)
      (emacsvox-aural-feature-fragments-refresh
       (car emacsvox-aural-enabled-feature-fragments)))
    (pop-to-buffer buffer)
    (if (tabulated-list-get-id)
        (when (called-interactively-p 'interactive)
          (emacsvox-aural-feature-fragments-speak-current))
      (when (called-interactively-p 'interactive)
        (if (fboundp 'tts-speak)
            (tts-speak
             "No feature fragments are registered.  Press N to create one.")
          (message
           "No feature fragments are registered.  Press N to create one."))))
    buffer))

(defun emacsvox-aural-home--source-buffer ()
  "Return the live inspection source for the current aural home buffer."
  (cond
   ((buffer-live-p emacsvox-aural-home-source-buffer)
    emacsvox-aural-home-source-buffer)
   ((buffer-live-p emacsvox-aural-tools--last-source-buffer)
    emacsvox-aural-tools--last-source-buffer)))

(defun emacsvox-aural-home--enabled-fragment-status ()
  "Return concise status for enabled aural feature fragments."
  (if emacsvox-aural-enabled-feature-fragments
      (format
       "%d enabled: %s"
       (length emacsvox-aural-enabled-feature-fragments)
       (mapconcat
        #'symbol-name emacsvox-aural-enabled-feature-fragments ", "))
    "none enabled"))

(defun emacsvox-aural-home--face-presentation-status ()
  "Return face-scheme and source-buffer Voice Lock status."
  (let ((source (emacsvox-aural-home--source-buffer)))
    (format
     "%s; Voice Lock %s%s"
     (if emacsvox-aural-face-presentation-enabled "on" "off")
     (if (emacsvox-aural-voice-lock-enabled-p source) "on" "off")
     (if source
         (format " in %s" (buffer-name source))
       ""))))

(defun emacsvox-aural-home--profile-status ()
  "Return concise status for complete saved presentation profiles."
  (require 'emacsvox-aural-profiles)
  (emacsvox-aural-profiles-status))

(defun emacsvox-aural-home--voice-palette-status ()
  "Return concise status for voice palettes."
  (require 'emacsvox-aural-voice-palettes)
  (emacsvox-aural-voice-palettes-status))

(defun emacsvox-aural-home--spatial-status ()
  "Return concise status for portable spatial presentation."
  (if emacsvox-aural-spatial-enabled
      (format
       "on; speech %s, cues %s, output %s"
       (if emacsvox-aural-spatial-speech-enabled "on" "off")
       (if emacsvox-aural-spatial-cue-enabled "on" "off")
       emacsvox-aural-spatial-output)
    "off"))

(defun emacsvox-aural-home--validation-status ()
  "Return concise installation and configuration health."
  (require 'emacsvox-aural-doctor)
  (emacsvox-aural-doctor-summary))

(defun emacsvox-aural-home--entries ()
  "Return current rows for the aural home buffer."
  (let* ((source (emacsvox-aural-home--source-buffer))
         (source-name (if source (buffer-name source) "no source buffer"))
         (buffer-rules
          (if source
              (length
               (buffer-local-value 'emacsvox-aural-buffer-rules source))
            0))
         (pack
          (or
           (and
            (boundp 'emacsvox-sounds-current-pack)
            emacsvox-sounds-current-pack)
           (emacsvox-aural-effective-scheme-provider 'resource-pack)
           "none")))
    (list
     (list
      'explain
      (vector
       "Explain at point" source-name
       "Show and speak why the current item sounds as it does"))
     (list
      'profiles
      (vector
       "Presentation profiles"
       (emacsvox-aural-home--profile-status)
       "Save and switch complete scheme, fragment, sound, voice, and spatial configurations"))
     (list
      'schemes
      (vector
       "Schemes" (symbol-name emacsvox-aural-active-scheme)
       "View, activate, copy, edit, preview, and validate base schemes"))
     (list
      'voices
      (vector
       "Voice palettes"
       (emacsvox-aural-home--voice-palette-status)
       "Browse, create, edit, preview, explain, validate, and activate named voices"))
     (list
      'features
      (vector
       "Feature fragments"
       (emacsvox-aural-home--enabled-fragment-status)
       "Layer and order independent presentation additions"))
     (list
      'face-presentation
      (vector
       "Visual face presentation"
       (emacsvox-aural-home--face-presentation-status)
       "Toggle explicit face scheme rules; Voice Lock independently controls legacy voices"))
     (list
      'buffer-rules
      (vector
       "Current buffer rules"
       (format "%d in %s" buffer-rules source-name)
       "Edit temporary presentation rules for the source buffer"))
     (list
      'semantics
      (vector
       "Semantic vocabulary"
       (format "%d registered" (length (emacsvox-aural-semantics)))
       "Browse roles, events, states, attributes, owners, and intent"))
     (list
      'sounds
      (vector
       "Sound packs" (format "%s" pack)
       "Browse, audition, validate, edit, and activate auditory cue packs"))
     (list
      'spatial
      (vector
       "Spatial capabilities"
       (emacsvox-aural-home--spatial-status)
       "Inspect backend capability and fallback"))
     (list
      'spatial-settings
      (vector
       "Spatial settings" "Customize"
       "Configure output, separation, direction, speech, and cues"))
     (list
      'training
      (vector
       "Training mode"
       (if emacsvox-aural-training-mode "on" "off")
       "Toggle concise semantic explanations after presentations"))
     (list
      'diagnostics
      (vector
       "Aural Doctor"
       (emacsvox-aural-home--validation-status)
       "Diagnose bindings, loaded files, configuration, resources, and backend")))))

(defun emacsvox-aural-home--goto (id)
  "Move to home row ID and its first column."
  (let ((start (point-min))
        found)
    (goto-char start)
    (while (and (not found) (< (point) (point-max)))
      (if (eq id (tabulated-list-get-id))
          (setq found t)
        (forward-line 1)))
    (unless found
      (goto-char start))
    (when found
      (emacsvox-aural-tools--goto-tabulated-column 0))
    found))

(defun emacsvox-aural-home-refresh (&optional id)
  "Refresh aural home status, preserving row ID and the current column."
  (interactive)
  (let ((column (emacsvox-aural-tools--tabulated-column-index))
        (selected (or id (tabulated-list-get-id) 'explain)))
    (setq tabulated-list-entries (emacsvox-aural-home--entries))
    (tabulated-list-print t)
    (emacsvox-aural-home--goto selected)
    (emacsvox-aural-tools--goto-tabulated-column column)))

(defun emacsvox-aural-home-speak-current ()
  "Speak the complete aural home row at point."
  (interactive)
  (let* ((entry
          (or
           (tabulated-list-get-entry)
           (user-error "Move to an aural home row first")))
         (summary
          (format
           "%s. %s. %s."
           (aref entry 0) (aref entry 1) (aref entry 2))))
    (if (fboundp 'tts-speak)
        (tts-speak summary)
      (message "%s" summary))
    summary))

(defun emacsvox-aural-home-speak-current-cell ()
  "Speak the current aural home column title and value."
  (interactive)
  (emacsvox-aural-tools--speak-tabulated-cell))

(defun emacsvox-aural-home-next ()
  "Move to and speak the next aural home row."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-row 1 "aural home"))

(defun emacsvox-aural-home-previous ()
  "Move to and speak the previous aural home row."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-row -1 "aural home"))

(defun emacsvox-aural-home-next-column ()
  "Move right and speak the next aural home column."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-column 1))

(defun emacsvox-aural-home-previous-column ()
  "Move left and speak the previous aural home column."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-column -1))

(defun emacsvox-aural-home--call-in-source (command)
  "Call interactive COMMAND in the remembered source buffer."
  (let ((source (emacsvox-aural-home--source-buffer)))
    (unless source
      (user-error "No live source buffer is available"))
    (with-current-buffer source
      (call-interactively command))))

(defun emacsvox-aural-home-explain ()
  "Explain presentation at point in the remembered source buffer."
  (interactive)
  (emacsvox-aural-home--call-in-source
   #'emacsvox-aural-explain-presentation))

(defun emacsvox-aural-home-profiles ()
  "Open the complete presentation-profile manager."
  (interactive)
  (require 'emacsvox-aural-profiles)
  (emacsvox-aural-list-profiles))

(defun emacsvox-aural-home-voice-palettes ()
  "Open the accessible voice-palette manager."
  (interactive)
  (require 'emacsvox-aural-voice-palettes)
  (emacsvox-aural-list-voice-palettes))

(defun emacsvox-aural-home-toggle-face-presentation ()
  "Toggle explicit face scheme rules and speak the refreshed home row."
  (interactive)
  (emacsvox-aural-toggle-face-presentation)
  (emacsvox-aural-home-refresh 'face-presentation)
  (emacsvox-aural-home-speak-current))

(defun emacsvox-aural-home-activate ()
  "Perform the primary operation for the aural home row at point."
  (interactive)
  (pcase (or (tabulated-list-get-id)
             (user-error "Move to an aural home row first"))
    ('explain
     (emacsvox-aural-home-explain))
    ('profiles (emacsvox-aural-home-profiles))
    ('schemes (emacsvox-aural-list-schemes))
    ('voices (emacsvox-aural-home-voice-palettes))
    ('features (emacsvox-aural-list-feature-fragments))
    ('face-presentation
     (emacsvox-aural-home-toggle-face-presentation))
    ('buffer-rules
     (let ((source (emacsvox-aural-home--source-buffer)))
       (unless source
         (user-error "No live source buffer is available"))
       (require 'emacsvox-aural-editor)
       (emacsvox-edit-aural-rules 'buffer nil source)))
    ('semantics (emacsvox-aural-list-semantics))
    ('sounds
     (require 'emacsvox-aural-sound-packs)
     (emacsvox-aural-list-sound-packs))
    ('spatial (emacsvox-aural-describe-spatial-capabilities))
    ('spatial-settings (customize-group 'emacsvox-aural-spatial))
    ('training
     (emacsvox-aural-training-mode
      (if emacsvox-aural-training-mode -1 1))
     (emacsvox-aural-home-refresh 'training)
     (emacsvox-aural-home-speak-current))
    ('diagnostics
     (require 'emacsvox-aural-doctor)
     (emacsvox-aural-doctor))))

(defun emacsvox-aural-home-help ()
  "Display and speak aural home commands and discovery guidance."
  (interactive)
  (with-help-window (help-buffer)
    (princ
     (concat
      "Emacsvox Aural Home\n\n"
      "This is the main entry point for presentation discovery, editing,\n"
      "inspection, sound packs, spatial settings, and diagnostics.\n\n"
      "n or down next       p or up previous\n"
      "left/right column    . speak titled cell\n"
      "RET open or perform  SPC speak complete row\n"
      "x explain at point   P presentation profiles\n"
      "V voice palettes     v face rules toggle\n"
      "D aural doctor\n"
      "g refresh\n"
      "? display and speak this help\n"
      "C-e H opens this home from any ordinary buffer\n"
      "C-e E explains presentation from any ordinary buffer\n"
      "h returns here from any aural manager or editor\n"
      "q quit\n")))
  (when (fboundp 'emacsvox-speak-help)
    (emacsvox-speak-help)))

(define-derived-mode emacsvox-aural-home-mode tabulated-list-mode
  "Emacsvox-Aural"
  "Spoken home mode for aural presentation discovery and interaction."
  (setq
   tabulated-list-format
   [("Area" 24 t)
    ("Current status" 38 t)
    ("Purpose" 0 t)])
  (setq tabulated-list-padding 2)
  (add-hook
   'tabulated-list-revert-hook
   #'emacsvox-aural-home-refresh nil t)
  (tabulated-list-init-header))

(dolist
    (binding
     '(("RET" . emacsvox-aural-home-activate)
       ("SPC" . emacsvox-aural-home-speak-current)
       ("." . emacsvox-aural-home-speak-current-cell)
       ("n" . emacsvox-aural-home-next)
       ("p" . emacsvox-aural-home-previous)
       ("<down>" . emacsvox-aural-home-next)
       ("<up>" . emacsvox-aural-home-previous)
       ("<right>" . emacsvox-aural-home-next-column)
       ("<left>" . emacsvox-aural-home-previous-column)
       ("x" . emacsvox-aural-home-explain)
       ("P" . emacsvox-aural-home-profiles)
       ("V" . emacsvox-aural-home-voice-palettes)
       ("v" . emacsvox-aural-home-toggle-face-presentation)
       ("D" . emacsvox-aural-doctor)
       ("g" . emacsvox-aural-home-refresh)
       ("?" . emacsvox-aural-home-help)))
  (define-key
   emacsvox-aural-home-mode-map
   (kbd (car binding))
   (cdr binding)))

(defun emacsvox-aural (&optional source-buffer)
  "Open the spoken aural home using SOURCE-BUFFER for contextual operations."
  (interactive)
  (emacsvox-aural-tools--remember-source-buffer
   (or source-buffer (current-buffer)))
  (let* ((buffer (get-buffer-create "*Emacsvox Aural*"))
         (source
          (or
           (and (buffer-live-p source-buffer) source-buffer)
           (and
            (buffer-live-p emacsvox-aural-tools--last-source-buffer)
            emacsvox-aural-tools--last-source-buffer))))
    (with-current-buffer buffer
      (emacsvox-aural-home-mode)
      (when source
        (setq emacsvox-aural-home-source-buffer source))
      (emacsvox-aural-home-refresh 'explain))
    (pop-to-buffer buffer)
    (when (called-interactively-p 'interactive)
      (emacsvox-aural-home-speak-current))
    buffer))

(defun emacsvox-aural-home-refresh-if-live (&rest _ignored)
  "Refresh the aural home buffer when it is currently available."
  (when-let* ((buffer (get-buffer "*Emacsvox Aural*")))
    (with-current-buffer buffer
      (when (derived-mode-p 'emacsvox-aural-home-mode)
        (emacsvox-aural-home-refresh)))))

(add-hook
 'emacsvox-aural-active-scheme-changed-hook
 #'emacsvox-aural-home-refresh-if-live)
(add-hook
 'emacsvox-aural-feature-fragments-changed-hook
 #'emacsvox-aural-home-refresh-if-live)
(add-hook
 'emacsvox-aural-face-presentation-changed-hook
 #'emacsvox-aural-home-refresh-if-live)
(add-hook
 'emacsvox-aural-voice-palette-changed-hook
 #'emacsvox-aural-home-refresh-if-live)

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
    (dolist (face (plist-get context :legacy-faces))
      (push
       (format "visual face %s" (emacsvox-aural-tools--humanize face))
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

;; Keep the established verb-first commands while exposing one discoverable
;; `emacsvox-aural-' command namespace.
(defalias 'emacsvox-aural-list-semantics
  #'emacsvox-list-aural-semantics)
(defalias 'emacsvox-aural-describe-semantic
  #'emacsvox-describe-aural-semantic)
(defalias 'emacsvox-aural-list-schemes
  #'emacsvox-list-aural-schemes)
(defalias 'emacsvox-aural-describe-scheme
  #'emacsvox-describe-aural-scheme)
(defalias 'emacsvox-aural-show-scheme-validation
  #'emacsvox-validate-aural-scheme)
(defalias 'emacsvox-aural-describe-spatial-capabilities
  #'emacsvox-describe-aural-spatial-capabilities)
(defalias 'emacsvox-aural-explain-presentation
  #'emacsvox-explain-aural-presentation)
(defalias 'emacsvox-aural-preview-rule
  #'emacsvox-preview-aural-rule)
(defalias 'emacsvox-aural-preview-scheme
  #'emacsvox-preview-aural-scheme)
(defalias 'emacsvox-aural-set-scheme
  #'emacsvox-set-aural-scheme)
(defalias 'emacsvox-aural-reset-scheme
  #'emacsvox-reset-aural-scheme)
(defalias 'emacsvox-aural-copy-scheme
  #'emacsvox-copy-aural-scheme)
(defalias 'emacsvox-aural-delete-scheme
  #'emacsvox-delete-aural-scheme)
(defalias 'emacsvox-aural-rename-scheme
  #'emacsvox-rename-aural-scheme)
(defalias 'emacsvox-aural-reset-overrides
  #'emacsvox-reset-aural-overrides)

(provide 'emacsvox-aural-tools)
;;; emacsvox-aural-tools.el ends here
