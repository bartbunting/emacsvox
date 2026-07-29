;;; emacsvox-aural-tools.el --- Aural scheme discovery and explanation -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Semantic and scheme discovery, validation, explanation, remapping,
;; preview, mutation, and training commands for aural presentation.

;;; Code:

(require 'cl-lib)
(require 'help-mode)
(require 'pp)
(require 'subr-x)
(require 'tabulated-list)
(require 'emacsvox-aural-ui)
(require 'emacsvox-aural-transport)
(require 'emacsvox-aural-preview)
(require 'emacsvox-aural-validation)
(require 'emacsvox-aural-inspection)

(cl-defstruct
    (emacsvox-aural-explanation
     (:constructor emacsvox-aural--make-explanation))
  "Reproducible explanation of one resolved aural presentation."
  scheme facts context matching-rules render-plan concrete-plan
  suppressed-actions basis presentation-id queued-at source-location)

(defvar emacsvox-aural-tools--last-explanation nil
  "Most recently displayed aural presentation explanation.")

(defvar emacsvox-sounds-current-pack)
(defvar emacsvox-speak-messages)
(defvar emacsvox-aural-training-mode nil
  "Non-nil when semantic training explanations are enabled.")

(defcustom emacsvox-aural-training-voice 'annotate
  "Palette-aware voice used for semantic training explanations."
  :type 'symbol
  :group 'emacsvox-aural)

(defvar emacsvox-aural-tools--pending-training-explanations nil
  "Training explanations waiting for the current command to finish.")

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
(declare-function emacsvox-aural-list-feature-fragments
                  "emacsvox-aural-feature-fragments" ())
(declare-function emacsvox-aural-list-recent-feedback
                  "emacsvox-aural-recent-feedback"
                  (&optional source-buffer))
(declare-function emacsvox-aural-home-refresh
                  "emacsvox-aural-home" (&optional id))
(declare-function emacsvox-aural-editor--open-prefilled-rule
                  "emacsvox-aural-editor" (scope rule source-buffer))
(declare-function emacsvox-aural-editor--open-without-rule
                  "emacsvox-aural-editor" (scope rule-id source-buffer))
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
(declare-function emacsvox-aural-list-overrides
                  "emacsvox-aural-overrides" (&optional source))
(declare-function emacsvox-aural-overrides-status
                  "emacsvox-aural-overrides" (&optional source))
(declare-function emacsvox-aural-list-voice-palettes
                  "emacsvox-aural-voice-palettes" (&optional palette))
(declare-function emacsvox-aural-voice-palettes-status
                  "emacsvox-aural-voice-palettes" ())
(declare-function emacsvox-speak-help "emacsvox-speak" ())
(declare-function voice-setup-get-voice-for-face "voice-setup" (face))
(declare-function emacsvox-speak-mode-line "emacsvox-speak" ())
(declare-function tts-speak "tts-speak" (text))
(declare-function tts-voice-reset-code "tts-speak" ())
(declare-function tts--protocol-queue-code "tts-speak" (code))
(declare-function tts--protocol-queue-text "tts-speak" (text))
(declare-function tts--protocol-dispatch "tts-speak" ())

(autoload 'emacsvox-aural "emacsvox-aural-home"
  "Open the spoken aural presentation home." t)

(defalias 'emacsvox-aural-tools--tabulated-column-index
  #'emacsvox-aural-ui-tabulated-column-index)
(defalias 'emacsvox-aural-tools--goto-tabulated-column
  #'emacsvox-aural-ui-goto-tabulated-column)
(defalias 'emacsvox-aural-tools--tabulated-cell-description
  #'emacsvox-aural-ui-tabulated-cell-description)
(defalias 'emacsvox-aural-tools--speak-tabulated-cell
  #'emacsvox-aural-ui-speak-current-cell)
(defalias 'emacsvox-aural-tools--tabulated-boundary
  #'emacsvox-aural-ui--announce-boundary)
(defalias 'emacsvox-aural-tools--move-tabulated-row
  #'emacsvox-aural-ui-move-row)
(defalias 'emacsvox-aural-tools--move-tabulated-column
  #'emacsvox-aural-ui-move-column)
(defalias 'emacsvox-aural-tools--stop-preview-speech
  #'emacsvox-aural-preview-stop)
(defalias 'emacsvox-aural-tools--preview-message
  #'emacsvox-aural-preview-message)

(defun emacsvox-aural-tools--interface-buffer-p (&optional buffer)
  "Return non-nil when BUFFER is an aural manager or editor buffer."
  (emacsvox-aural-ui-interface-buffer-p buffer))

(defun emacsvox-aural-tools--matching-rules-for-occasion
    (facts context occasion)
  "Return rules matching FACTS in CONTEXT for OCCASION."
  (let* ((context
          (emacsvox-aural-inspection-context-for-occasion
           context occasion))
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
  (let* ((plan (emacsvox-aural-inspection-plan-at-point))
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
     (emacsvox-aural-inspection-context-for-occasion
      context occasion))))

(defun emacsvox-aural-tools--interactive-explanation-input
    (choose-occasion)
  "Return exact queued input, or simulated input when CHOOSE-OCCASION."
  (let* ((interface
          (emacsvox-aural-tools--interface-buffer-p))
         (source
          (emacsvox-aural-inspection-source-buffer))
         (record
          (and
           (not choose-occasion)
           source
           (emacsvox-aural-last-presentation source))))
    (if record
        (list nil nil record)
      (when (and interface (null source))
        (user-error "No live source buffer is available"))
      (let ((input
             (if (eq source (current-buffer))
                 (emacsvox-aural-tools--read-explanation-input
                  choose-occasion)
               (with-current-buffer source
                 (emacsvox-aural-tools--read-explanation-input
                  choose-occasion)))))
        (append input (list nil))))))

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
  (emacsvox-aural-ui-goto-row semantic))

(defun emacsvox-aural-semantics-refresh (&optional semantic)
  "Refresh the semantic list, preserving SEMANTIC and the current column."
  (interactive)
  (emacsvox-aural-ui-refresh-tabulated
   #'emacsvox-aural-semantics--set-entries semantic))

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

(define-derived-mode emacsvox-aural-semantics-mode
    emacsvox-aural-tabulated-mode
  "Aural-Semantics"
  "Major mode for browsing registered aural semantics."
  (emacsvox-aural-ui-configure-tabulated
   "semantic list"
   #'emacsvox-aural-semantics-speak-current
   #'emacsvox-aural-semantics-refresh)
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
       ("h" . emacsvox-aural)
       ("?" . emacsvox-aural-semantics-help)))
  (define-key
   emacsvox-aural-semantics-mode-map
   (kbd (car binding))
   (cdr binding)))

(defun emacsvox-list-aural-semantics ()
  "Open the accessible list of registered semantic vocabulary."
  (interactive)
  (let ((source
         (emacsvox-aural-inspection-remember-source-buffer))
        (buffer (get-buffer-create "*Aural Semantics*")))
    (with-current-buffer buffer
      (emacsvox-aural-semantics-mode)
      (emacsvox-aural-inspection-attach-source source)
      (emacsvox-aural-semantics-refresh))
    (emacsvox-aural-ui-pop-to-buffer buffer)
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

(defun emacsvox-aural-tools--scheme-provider (entry)
  "Return a user-facing provider name for scheme ENTRY."
  (let ((source
         (format "%s" (or (emacsvox-aural-scheme-entry-source entry) ""))))
    (cond
     ((not (emacsvox-aural-scheme-entry-built-in entry))
      "you (personal)")
     ((string= source "built-in") "Emacsvox core")
     ((string-match
       "\\`emacsvox-aural-provider-\\(.+\\)\\'" source)
      (format
       "%s integration"
       (capitalize
        (replace-regexp-in-string "-" " " (match-string 1 source)))))
     ((string-empty-p source) "Emacsvox")
     (t source))))

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
      (emacsvox-aural-tools--scheme-provider entry)
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
  (emacsvox-aural-ui-goto-row scheme))

(defun emacsvox-aural-schemes-refresh (&optional scheme)
  "Refresh the scheme manager, preserving SCHEME or the current row."
  (interactive)
  (emacsvox-aural-ui-refresh-tabulated
   #'emacsvox-aural-schemes--set-entries scheme))

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
         (provider (emacsvox-aural-tools--scheme-provider entry))
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
       (format "Provided by %s." provider)
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

(defun emacsvox-aural-schemes-speak-current-cell ()
  "Speak the current manager column title and value."
  (interactive)
  (emacsvox-aural-tools--speak-tabulated-cell))

(defun emacsvox-aural-schemes-next ()
  "Move to and speak the next scheme."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-row 1 "scheme list"))

(defun emacsvox-aural-schemes-previous ()
  "Move to and speak the previous scheme."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-row -1 "scheme list"))

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
      (princ
       (format
        "Provided by: %s\n"
        (emacsvox-aural-tools--scheme-provider entry)))
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
      "Exactly one scheme is active globally. It is the base presentation\n"
      "recipe: named rules plus optional default sound and voice providers.\n"
      "Emacsvox and mode integrations may provide read-only built-in schemes;\n"
      "you provide personal schemes by creating or copying one. Entering a\n"
      "mode does not select its scheme. Every presentation consults the active\n"
      "scheme, but only matching rules contribute. Activating a saved profile\n"
      "may explicitly select its scheme. Automatic module compatibility is a\n"
      "separate layer, followed by presentation options and then overrides.\n\n"
      "Each row identifies whether a scheme is active, who provided it, what\n"
      "it inherits, its effective sound pack and presentation count.\n"
      "Row movement speaks value then title; column movement title then value.\n"
      "past the first or last row announces the list boundary.\n\n"
      "n or down next       p or up previous\n"
      "left/right column    . speak titled cell\n"
      "RET view details     e simple editor\n"
      "A advanced editor    c copy\n"
      "C-u c flattened copy d delete personal scheme\n"
      "r rename personal    a activate\n"
      "P preview            v validate\n"
      "SPC speak row        g refresh\n"
      "f presentation options  h aural home\n"
      "q quit\n")))
  (when (fboundp 'emacsvox-speak-help)
    (emacsvox-speak-help)))

(define-derived-mode emacsvox-aural-schemes-mode
    emacsvox-aural-tabulated-mode
  "Aural-Schemes"
  "Major mode for viewing and managing registered aural schemes."
  (emacsvox-aural-ui-configure-tabulated
   "scheme list"
   #'emacsvox-aural-schemes-speak-current
   #'emacsvox-aural-schemes-refresh)
  (setq
   tabulated-list-format
   [("Scheme" 24 t)
    ("Status" 9 t)
    ("Kind" 10 t)
    ("Based on" 18 t)
    ("Sound pack" 18 t)
    ("Presentations" 22 t)
    ("Validation" 12 t)
    ("Provided by" 22 t)
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
 (kbd "v")
 #'emacsvox-validate-aural-scheme)
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
  (let ((source
         (emacsvox-aural-inspection-remember-source-buffer))
        (buffer (get-buffer-create "*Aural Schemes*")))
    (with-current-buffer buffer
      (emacsvox-aural-schemes-mode)
      (emacsvox-aural-inspection-attach-source source)
      (emacsvox-aural-schemes-refresh emacsvox-aural-active-scheme))
    (emacsvox-aural-ui-pop-to-buffer buffer)
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
         (voice-source
          (cdr
           (assq
            'voice
            (emacsvox-aural-content-style-provenance
             (emacsvox-aural-render-plan-content render)))))
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
       (when voice-source
         (format
          "The content voice comes from %s."
          (emacsvox-aural-tools--humanize voice-source)))
       (when after
         (format
          "After the content, %s."
          (mapconcat
           #'emacsvox-aural-tools--spoken-action after ", then ")))
       "To change this object's voice or one of its earcons, use the remap rows in Aural Home."))
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
      (when-let* ((voice-source
                   (cdr
                    (assq
                     'voice
                     (emacsvox-aural-content-style-provenance
                      (emacsvox-aural-render-plan-content render))))))
        (princ (format "Voice source: %S\n" voice-source)))
      (when-let* ((suppressed
                   (emacsvox-aural-explanation-suppressed-actions
                    explanation)))
        (princ (format "\nSuppressed or removed actions: %S\n" suppressed)))
      (when-let* ((degradations
                   (emacsvox-aural-concrete-plan-degradations concrete)))
        (princ (format "\nBackend degradation: %S\n" degradations)))
      (princ
       (concat
        "\nTo change this object's voice, choose Remap at point from "
        "Aural Home, or run M-x emacsvox-aural-remap-voice-at-point.\n")))
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
    (emacsvox-aural-inspection-remember-source-buffer))
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

(defun emacsvox-aural-tools--remap-source-input (&optional record)
  "Return presentation input for optional frozen RECORD or the current source.

For RECORD, use its exact frozen voice and semantic context.  Associate it
with the current inspection source only when the buffer name still matches;
history deliberately does not retain source buffers.  Without RECORD, prefer
the latest exact presentation from the current source and fall back to
inspectable facts at point."
  (if record
      (progn
        (unless (emacsvox-aural-presentation-record-p record)
          (user-error "Not an aural presentation record: %S" record))
        (let* ((concrete
                (emacsvox-aural-presentation-record-plan record))
               (source
                (emacsvox-aural-inspection-source-buffer))
               (source
                (and
                 source
                 (equal
                  (buffer-name source)
                  (emacsvox-aural-presentation-record-source-buffer-name
                   record))
                 source)))
          (list
           :source source
           :facts (copy-tree (emacsvox-aural-concrete-plan-facts concrete))
           :context
           (copy-tree (emacsvox-aural-concrete-plan-context concrete))
           :render (emacsvox-aural-concrete-plan-source-plan concrete)
           :concrete concrete)))
    (let ((source (emacsvox-aural-inspection-source-buffer)))
      (unless source
        (user-error "No live source buffer is available"))
      (with-current-buffer source
        (if-let* ((record (emacsvox-aural-last-presentation source)))
            (let* ((concrete
                    (emacsvox-aural-presentation-record-plan record))
                   (render
                    (emacsvox-aural-concrete-plan-source-plan concrete)))
              (list
               :source source
               :facts
               (copy-tree (emacsvox-aural-concrete-plan-facts concrete))
               :context
               (copy-tree (emacsvox-aural-concrete-plan-context concrete))
               :render render
               :concrete concrete))
          (let* ((facts (emacsvox-aural-facts-at-point))
                 (_
                  (unless facts
                    (user-error
                     "No presentation is recorded here; move away and back, then retry")))
                 (context (emacsvox-aural-context-at-point))
                 (explanation (emacsvox-aural-explain facts context)))
            (list
             :source source
             :facts (copy-tree facts)
             :context (copy-tree context)
             :render
             (emacsvox-aural-explanation-render-plan explanation)
             :concrete
             (emacsvox-aural-explanation-concrete-plan explanation))))))))

(defun emacsvox-aural-tools--voice-remap-selector (facts context)
  "Derive a stable object selector from FACTS and CONTEXT.

Transient events and the current occasion are deliberately omitted.  Object
states remain specific, while MODULE (or MODE when there is no module) keeps
the override local to its provider.  A visual face is used only when semantic
facts do not distinguish the object."
  (let ((role (plist-get facts :role))
        (states (copy-sequence (plist-get facts :states)))
        selector
        attributes)
    (when role
      (setq selector (plist-put selector :role role)))
    (dolist (semantic (emacsvox-aural-semantics))
      (when (eq (emacsvox-aural-semantic-kind semantic) 'attribute)
        (let* ((id (emacsvox-aural-semantic-id semantic))
               (key (intern (format ":%s" id))))
          (when (plist-member facts key)
            (push id attributes)
            (setq
             selector
             (plist-put selector key (copy-tree (plist-get facts key))))))))
    (when states
      (setq selector (plist-put selector :states states)))
    (if-let* ((module (plist-get context :module)))
        (setq selector (plist-put selector :module module))
      (when-let* ((mode (plist-get context :mode)))
        (setq selector (plist-put selector :mode mode))))
    (when
        (and
         (null role)
         (null attributes)
         (null states)
         (plist-get context :legacy-faces))
      (setq
       selector
       (plist-put
        selector :legacy-face (car (plist-get context :legacy-faces)))))
    (unless selector
      (user-error
       "This presentation has no stable semantic, mode, or face identity"))
    selector))

(defun emacsvox-aural-tools--voice-remap-current-voice (render context)
  "Return the requested voice represented by RENDER and CONTEXT."
  (or
   (emacsvox-aural-content-style-voice
    (emacsvox-aural-render-plan-content render))
   (cl-loop
    for face in (plist-get context :legacy-faces)
    thereis
    (and
     (fboundp 'voice-setup-get-voice-for-face)
     (voice-setup-get-voice-for-face face)))))

(defun emacsvox-aural-tools--voice-remap-default-name (voice)
  "Return the active palette name corresponding to VOICE."
  (let* ((palette
          (or
           (emacsvox-aural-effective-scheme-provider 'voice-palette)
           'acss-default))
         (entries (emacsvox-aural-effective-voice-entries palette)))
    (cond
     ((null voice) "default")
     ((assq voice entries) (symbol-name voice))
     ((cl-find voice entries :key #'cdr :test #'equal)
      (symbol-name
       (car (cl-find voice entries :key #'cdr :test #'equal))))
     ((and
       (symbolp voice)
       (string-prefix-p "voice-" (symbol-name voice))
       (assq
        (intern (string-remove-prefix "voice-" (symbol-name voice)))
        entries))
      (string-remove-prefix "voice-" (symbol-name voice)))
     (t "default"))))

(defun emacsvox-aural-tools--voice-remap-candidates ()
  "Return named voices available from the active palette."
  (let ((palette
         (or
          (emacsvox-aural-effective-scheme-provider 'voice-palette)
          'acss-default)))
    (sort
     (delete-dups
      (append
       '("default" "inaudible")
       (mapcar
        (lambda (entry) (symbol-name (car entry)))
        (emacsvox-aural-effective-voice-entries palette))))
     #'string-lessp)))

(defun emacsvox-aural-tools--voice-remap-scope
    (source-available &optional kind)
  "Read a remap scope for KIND.

KIND defaults to voice.  Offer buffer-local persistence only when
SOURCE-AVAILABLE is non-nil."
  (pcase
      (completing-read
       (format "Keep this %s change: " (or kind "voice"))
       (append
        '("always (personal)" "this Emacs session")
        (when source-available '("this buffer")))
       nil 'must-match nil nil "always (personal)")
    ("always (personal)" 'personal)
    ("this Emacs session" 'session)
    ("this buffer" 'buffer)))

(defun emacsvox-aural-tools--remap-rule-id (scope selector suffix)
  "Return a stable rule identifier for SCOPE, SELECTOR, and SUFFIX."
  (let ((parts
         (delq
          nil
          (list
           scope 'remap
           (plist-get selector :module)
           (plist-get selector :mode)
           (plist-get selector :role)))))
    (setq parts (append parts (plist-get selector :states)))
    (dolist (event (plist-get selector :events))
      (setq parts (append parts (list 'event event))))
    (when-let* ((occasion (plist-get selector :occasion)))
      (setq parts (append parts (list 'occasion occasion))))
    (dolist (semantic (emacsvox-aural-semantics))
      (when (eq (emacsvox-aural-semantic-kind semantic) 'attribute)
        (let* ((id (emacsvox-aural-semantic-id semantic))
               (key (intern (format ":%s" id))))
          (when (plist-member selector key)
            (setq parts
                  (append parts (list id (plist-get selector key))))))))
    (setq
     parts
     (append
      parts
      (list (plist-get selector :legacy-face))
      suffix))
    (intern
     (mapconcat
      (lambda (part)
        (string-trim
         (replace-regexp-in-string
          "[^[:alnum:]-]+" "-"
          (downcase (format "%s" part)))
         "-" "-"))
      (delq nil parts)
      "-"))))

(defun emacsvox-aural-tools--voice-remap-rule-id (scope selector)
  "Return a stable voice-remap identifier for SCOPE and SELECTOR."
  (emacsvox-aural-tools--remap-rule-id scope selector '(voice)))

(defun emacsvox-aural-remap-voice-at-point (&optional record)
  "Prepare a scoped named-voice override for RECORD or presentation at point.

When RECORD is non-nil, use that frozen presentation from recent feedback.
Otherwise the latest presentation heard in the source buffer supplies exact
facts and context.  The generated rule ignores transient events and
occasions, but retains object kind, state, and provider identity.  It opens
unsaved in the advanced rule editor so the selector can be reviewed or
  refined before `s' saves it."
  (interactive)
  (let* ((input
          (if record
              (emacsvox-aural-tools--remap-source-input record)
            (emacsvox-aural-tools--remap-source-input)))
         (facts (plist-get input :facts))
         (context (plist-get input :context))
         (render (plist-get input :render))
         (source (plist-get input :source))
         (selector
          (emacsvox-aural-tools--voice-remap-selector facts context))
         (compiled-selector
          (emacsvox-aural-rule-selector
           (emacsvox-aural-compile-rule
            (list
             :id 'point-voice-remap-preview
             :match selector
             :render '(:content (:voice default)))
            'user)))
         (description
          (emacsvox-aural-tools--selector-description compiled-selector))
         (current
          (emacsvox-aural-tools--voice-remap-current-voice render context))
         (default
          (emacsvox-aural-tools--voice-remap-default-name current))
         (answer
          (completing-read
           (format
            "Voice for %s (currently %s): "
            description
            (emacsvox-aural-tools--humanize default))
           (emacsvox-aural-tools--voice-remap-candidates)
           nil 'must-match nil nil default))
         (voice
          (unless (or (string-empty-p answer) (string= answer "default"))
            (intern answer)))
         (scope (emacsvox-aural-tools--voice-remap-scope source))
         (rule
          (list
           :id (emacsvox-aural-tools--voice-remap-rule-id scope selector)
           :match selector
           :render (list :content (list :voice voice)))))
    (require 'emacsvox-aural-editor)
    (emacsvox-aural-editor--open-prefilled-rule scope rule source)
    (message
     "Prepared %s voice override for %s; review it and press s to save"
     scope description)))

(defun emacsvox-aural-tools--earcon-remap-selector (facts context)
  "Derive a precise earcon selector from FACTS and CONTEXT.

Retain the stable semantic identity used by voice remapping, plus events and
occasion because earcons commonly announce a particular transition rather
than every presentation of an object."
  (let ((selector
         (emacsvox-aural-tools--voice-remap-selector facts context)))
    (when-let* ((events (copy-sequence (plist-get facts :events))))
      (setq selector (plist-put selector :events events)))
    (when-let* ((occasion (plist-get context :occasion)))
      (setq selector (plist-put selector :occasion occasion)))
    selector))

(defun emacsvox-aural-tools--earcon-remap-candidates ()
  "Return registered non-prompt cue identifiers for completion."
  (let (cues)
    (maphash
     (lambda (id cue)
       (unless (eq (emacsvox-aural-cue-kind cue) 'prompt)
         (push (symbol-name id) cues)))
     emacsvox-aural-cue-registry)
    (sort cues #'string-lessp)))

(defun emacsvox-aural-tools--earcon-remap-choices (concrete)
  "Return labeled concrete earcon choices from CONCRETE."
  (let (choices)
    (dolist
        (phase-actions
         (list
          (cons 'before
                (emacsvox-aural-concrete-plan-before concrete))
          (cons 'after
                (emacsvox-aural-concrete-plan-after concrete))))
      (let ((phase (car phase-actions))
            (actions (cdr phase-actions)))
        (cl-loop
         for action in actions
         for index from 0
         when
         (eq (emacsvox-aural-concrete-action-kind action) 'cue)
         do
         (let* ((cue (emacsvox-aural-concrete-action-cue action))
                (id (emacsvox-aural-concrete-action-id action))
                (source (emacsvox-aural-concrete-action-source action))
                (label
                 (format
                  "%s position %d: %s; action %s; source %s"
                  (capitalize (symbol-name phase))
                  (1+ index)
                  (emacsvox-aural-tools--humanize cue)
                  (emacsvox-aural-tools--humanize id)
                  (if source
                      (emacsvox-aural-tools--humanize source)
                    "unknown"))))
           (push
            (cons
             label
             (list
              :phase phase
              :action action
              :index index
              :count (length actions)))
            choices)))))
    (nreverse choices)))

(defun emacsvox-aural-tools--earcon-remap-choice (concrete)
  "Read and return one concrete earcon choice from CONCRETE."
  (let ((choices (emacsvox-aural-tools--earcon-remap-choices concrete)))
    (unless choices
      (user-error "This presentation contains no earcon to remap"))
    (if (= (length choices) 1)
        (cdar choices)
      (let ((answer
             (completing-read
              "Earcon to remap: "
              (mapcar #'car choices)
              nil 'must-match)))
        (cdr (assoc answer choices))))))

(defun emacsvox-aural-tools--validate-earcon-remap-choice
    (choice concrete)
  "Return CHOICE when it identifies one removable action in CONCRETE."
  (let* ((phase (plist-get choice :phase))
         (selected (plist-get choice :action))
         (id (emacsvox-aural-concrete-action-id selected))
         (anchor (emacsvox-aural-concrete-action-anchor selected))
         (actions
          (if (eq phase 'before)
              (emacsvox-aural-concrete-plan-before concrete)
            (emacsvox-aural-concrete-plan-after concrete)))
         (matches
          (cl-remove-if-not
           (lambda (action)
             (and
              (eq (emacsvox-aural-concrete-action-id action) id)
              (eq
               (emacsvox-aural-concrete-action-anchor action)
               anchor)))
           actions)))
    (when (> (length matches) 1)
      (user-error
       "Action ID %s is duplicated in this %s phase and anchor; use the advanced rule editor"
       id phase))
    choice))

(defun emacsvox-aural-tools--earcon-action-data (action cue)
  "Return declarative replacement data for concrete ACTION using CUE."
  (let ((anchor (emacsvox-aural-concrete-action-anchor action))
        (volume
         (emacsvox-aural-concrete-action-requested-volume action))
        (space
         (emacsvox-aural-concrete-action-requested-space action))
        (data
         (list
          :id (emacsvox-aural-concrete-action-id action)
          :kind 'cue
          :cue cue)))
    (unless (memq anchor emacsvox-aural-action-anchors)
      (user-error
       "The selected earcon has no precise lifecycle anchor: %S"
       anchor))
    (setq data (plist-put data :anchor anchor))
    (when (numberp volume)
      (setq data (plist-put data :volume volume)))
    (when space
      (setq data (plist-put data :space (copy-tree space))))
    data))

(defun emacsvox-aural-tools--preview-replacement-earcon
    (data facts context)
  "Audition replacement earcon DATA using FACTS and CONTEXT."
  (let* ((anchor (plist-get data :anchor))
         (action
          (emacsvox-aural--compile-action
           data 'earcon-remap-preview 'before 0 anchor))
         (render
          (emacsvox-aural--make-render-plan
           :before (list action)
           :content
           (emacsvox-aural--make-content-style :speak nil)))
         (concrete
          (emacsvox-aural-compile-plan
           render facts context 'local-cue))
         (cue (car (emacsvox-aural-concrete-plan-before concrete))))
    (emacsvox-aural-preview-play-cues (list cue))
    cue))

(defun emacsvox-aural-tools--earcon-remap-insertion (choice)
  "Return the least-disruptive insertion operation for earcon CHOICE."
  (let ((phase (plist-get choice :phase))
        (index (plist-get choice :index))
        (count (plist-get choice :count)))
    (cond
     ((zerop index) :prepend)
     ((= index (1- count)) :append)
     ((eq phase 'before) :prepend)
     (t :append))))

(defun emacsvox-aural-remap-earcon-at-point (&optional record)
  "Prepare a scoped override for one earcon in RECORD or at point.

Audition the exact selected earcon before asking whether to replace, suppress,
or restore it.  Replacement also auditions the newly resolved cue.  The
generated change opens unsaved in the advanced editor for review."
  (interactive)
  (let* ((input
          (if record
              (emacsvox-aural-tools--remap-source-input record)
            (emacsvox-aural-tools--remap-source-input)))
         (facts (plist-get input :facts))
         (context (plist-get input :context))
         (concrete (plist-get input :concrete))
         (source (plist-get input :source))
         (selector
          (emacsvox-aural-tools--earcon-remap-selector facts context))
         (compiled-selector
          (emacsvox-aural-rule-selector
           (emacsvox-aural-compile-rule
            (list
             :id 'point-earcon-remap-preview
             :match selector
             :render '(:content (:voice default)))
            'user)))
         (description
          (emacsvox-aural-tools--selector-description compiled-selector))
         (choice
          (emacsvox-aural-tools--validate-earcon-remap-choice
           (emacsvox-aural-tools--earcon-remap-choice concrete)
           concrete))
         (phase (plist-get choice :phase))
         (action (plist-get choice :action))
         (action-id (emacsvox-aural-concrete-action-id action))
         (current-cue (emacsvox-aural-concrete-action-cue action)))
    (emacsvox-aural-preview-play-cues (list action))
    (let* ((operation
            (pcase
                (completing-read
                 (format
                  "Change %s earcon for %s: "
                  (emacsvox-aural-tools--humanize current-cue)
                  description)
                 '("replace it" "suppress it" "restore inherited behavior")
                 nil 'must-match nil nil "replace it")
              ("replace it" 'replace)
              ("suppress it" 'suppress)
              ("restore inherited behavior" 'restore)))
           (scope
            (emacsvox-aural-tools--voice-remap-scope source "earcon"))
           (rule-id
            (emacsvox-aural-tools--remap-rule-id
             scope selector (list 'earcon phase action-id))))
      (require 'emacsvox-aural-editor)
      (if (eq operation 'restore)
          (progn
            (emacsvox-aural-editor--open-without-rule
             scope rule-id source)
            (message
             "Prepared removal of %s earcon override; press s to restore inherited behavior"
             scope))
        (let* ((phase-key (intern (format ":%s" phase)))
               (anchor
                (emacsvox-aural-concrete-action-anchor action))
               (phase-data
                (list :anchor anchor :remove (list action-id))))
          (when (eq operation 'replace)
            (let* ((answer
                    (completing-read
                     (format
                      "Replacement for %s: "
                      (emacsvox-aural-tools--humanize current-cue))
                     (emacsvox-aural-tools--earcon-remap-candidates)
                     nil 'must-match nil nil
                     (symbol-name current-cue)))
                   (replacement (intern answer))
                   (action-data
                    (emacsvox-aural-tools--earcon-action-data
                     action replacement)))
              (setq
               phase-data
               (plist-put
                phase-data
                (emacsvox-aural-tools--earcon-remap-insertion choice)
                (list action-data)))
              (emacsvox-aural-tools--preview-replacement-earcon
               action-data facts context)))
          (let ((rule
                 (list
                  :id rule-id
                  :match selector
                  :render (list phase-key phase-data))))
            (emacsvox-aural-editor--open-prefilled-rule
             scope rule source)
            (message
             "Prepared %s %s-earcon override for %s; review it and press s to save"
             scope phase description)))))))

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
          (emacsvox-aural-inspection-representative-input rule))
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
      (emacsvox-aural-preview-play-plan concrete))))

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
          (emacsvox-aural-inspection-representative-input rule))
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

(defun emacsvox-aural-tools--persist-scheme-mutation (reason mutation)
  "Persist staged scheme MUTATION, then publish it for REASON.

MUTATION is called with a copied scheme registry and isolated cache state.
The complete candidate registry is validated and saved before replacing live
state.  Registration notifications raised while staging remain private; one
configuration notification for REASON is published after commit.  Return the
value of MUTATION."
  (let ((registry (copy-hash-table emacsvox-aural-scheme-registry))
        result)
    (let ((emacsvox-aural-scheme-registry registry)
          (emacsvox-aural-configuration-generation
           emacsvox-aural-configuration-generation)
          (emacsvox-aural-configuration-changed-hook nil)
          (emacsvox-aural--current-rules-cache
           (make-hash-table :test #'equal))
          (emacsvox-aural--provider-cache
           (make-hash-table :test #'equal))
          (emacsvox-aural--current-rules-cache-hits
           emacsvox-aural--current-rules-cache-hits)
          (emacsvox-aural--current-rules-cache-misses
           emacsvox-aural--current-rules-cache-misses))
      (setq result (funcall mutation))
      (emacsvox-aural-validate-scheme-registry)
      (emacsvox-aural-save-user-data))
    (setq emacsvox-aural-scheme-registry registry)
    (emacsvox-aural-configuration-changed reason)
    result))

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
    (emacsvox-aural-tools--persist-scheme-mutation
     'scheme-copied
     (lambda ()
       (emacsvox-aural-register-scheme
        data :source emacsvox-aural-schemes-file)))
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
      (emacsvox-aural-tools--persist-scheme-mutation
       'scheme-deleted
       (lambda ()
         (remhash scheme emacsvox-aural-scheme-registry)
         scheme))
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
      (let ((active (eq scheme emacsvox-aural-active-scheme)))
        (emacsvox-aural-tools--persist-scheme-mutation
         'scheme-renamed
         (lambda ()
          (remhash scheme emacsvox-aural-scheme-registry)
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
              (remhash dependent emacsvox-aural-scheme-registry)
              (emacsvox-aural-register-scheme
               data
               :built-in
               (emacsvox-aural-scheme-entry-built-in child)
               :source
               (emacsvox-aural-scheme-entry-source child))))
          new-id))
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

(defun emacsvox-aural-home-refresh-if-live (&rest _ignored)
  "Refresh the aural home buffer when it is currently available."
  (when-let* ((buffer (get-buffer "*Emacsvox Aural*")))
    (with-current-buffer buffer
      (when (derived-mode-p 'emacsvox-aural-home-mode)
        (emacsvox-aural-home-refresh)))))

(defun emacsvox-aural-tools--concise-explanation
    (facts context concrete-cues concrete-p)
  "Return a concise explanation of FACTS and CONTEXT.

When CONCRETE-P is non-nil, describe CONCRETE-CUES that actually survived
resolution instead of the legacy cue that initiated resolution."
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
    (if concrete-p
        (dolist (cue concrete-cues)
          (push
           (format "earcon %s" (emacsvox-aural-tools--humanize cue))
           parts))
      (when-let* ((cue (plist-get context :legacy-cue)))
        (push
         (format "legacy cue %s" (emacsvox-aural-tools--humanize cue))
         parts)))
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

(defun emacsvox-aural-concise-explanation (facts context)
  "Return a concise spoken explanation of FACTS in CONTEXT."
  (emacsvox-aural-tools--concise-explanation facts context nil nil))

(defun emacsvox-aural-concise-plan-explanation (plan)
  "Return a concise explanation of the presentation actually in PLAN."
  (let ((cues
         (delete-dups
          (delq
           nil
           (mapcar
            #'emacsvox-aural-concrete-action-cue
            (append
             (emacsvox-aural-concrete-plan-before plan)
             (emacsvox-aural-concrete-plan-after plan)))))))
    (emacsvox-aural-tools--concise-explanation
     (emacsvox-aural-concrete-plan-facts plan)
     (emacsvox-aural-concrete-plan-context plan)
     cues t)))

(defun emacsvox-aural-tools--queue-training-explanation (text)
  "Queue training explanation TEXT in the configured training voice."
  (let ((voice-command
         (emacsvox-aural-compile-voice emacsvox-aural-training-voice)))
    (unless (eq voice-command 'inaudible)
      (tts--protocol-queue-code (tts-voice-reset-code))
      (when voice-command
        (tts--protocol-queue-code voice-command))
      (tts--protocol-queue-text text)
      (tts--protocol-queue-code (tts-voice-reset-code)))))

(defun emacsvox-aural-tools--training-command-active-p ()
  "Return non-nil while an interactive command is being presented."
  (or this-command
      (and (boundp 'real-this-command) real-this-command)))

(defun emacsvox-aural-tools--training-presented (plan)
  "Retain a concise semantic explanation after concrete PLAN."
  (let ((text (emacsvox-aural-concise-plan-explanation plan)))
    (if (emacsvox-aural-tools--training-command-active-p)
        (push text emacsvox-aural-tools--pending-training-explanations)
      (emacsvox-aural-tools--queue-training-explanation text))))

(defun emacsvox-aural-tools--flush-training-explanations ()
  "Queue deferred training explanations after normal command feedback."
  (when emacsvox-aural-tools--pending-training-explanations
    (let ((explanations
           (nreverse emacsvox-aural-tools--pending-training-explanations)))
      (setq emacsvox-aural-tools--pending-training-explanations nil)
      (dolist (text explanations)
        (emacsvox-aural-tools--queue-training-explanation text))
      (tts--protocol-dispatch))))

(define-minor-mode emacsvox-aural-training-mode
  "Speak concise semantics after each normal aural presentation."
  :global t
  :group 'emacsvox-aural
  (if emacsvox-aural-training-mode
      (progn
        (setq emacsvox-aural-tools--pending-training-explanations nil)
        (add-hook
         'emacsvox-aural-plan-presented-hook
         #'emacsvox-aural-tools--training-presented)
        (add-hook
         'post-command-hook
         #'emacsvox-aural-tools--flush-training-explanations t))
    (remove-hook
     'emacsvox-aural-plan-presented-hook
     #'emacsvox-aural-tools--training-presented)
    (remove-hook
     'post-command-hook
     #'emacsvox-aural-tools--flush-training-explanations)
    (setq emacsvox-aural-tools--pending-training-explanations nil)))

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
