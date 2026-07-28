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
(declare-function emacsvox-speak-mode-line "emacsvox-speak" ())
(declare-function tts-speak "tts-speak" (text))
(declare-function tts-voice-reset-code "tts-speak" ())
(declare-function tts--protocol-queue-code "tts-speak" (code))
(declare-function tts--protocol-queue-text "tts-speak" (text))
(declare-function tts--protocol-dispatch "tts-speak" ())

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

(defun emacsvox-aural-tools--fragment-rules (fragment)
  "Return the compiled presentation rules for feature FRAGMENT."
  (let ((entry
         (or
          (emacsvox-aural-feature-fragment-entry fragment)
          (user-error "Unknown presentation option: %S" fragment))))
    (emacsvox-aural-scheme-rules
     (emacsvox-aural-feature-fragment-entry-compiled entry))))

(defun emacsvox-aural-tools--automatic-fragment-example (fragment rule)
  "Return an automatically derived preview example for FRAGMENT RULE."
  (pcase-let* ((`(,facts ,context)
                 (emacsvox-aural-inspection-representative-input rule))
                (rule-id (emacsvox-aural-rule-id rule))
                (facts
                 (if (plist-member facts :content)
                     facts
                   (plist-put (copy-tree facts) :content "Example"))))
    (emacsvox-aural--make-feature-fragment-example
     :fragment fragment
     :id (intern (format "automatic-%s" rule-id))
     :rule rule-id
     :summary
     (format
      "Automatically derived %s"
      (emacsvox-aural-tools--humanize rule-id))
     :facts facts
     :context context
     :source 'automatic)))

(defun emacsvox-aural-tools--fragment-preview-examples (fragment)
  "Return curated and automatically completed examples for FRAGMENT."
  (let* ((curated
          (emacsvox-aural-feature-fragment-examples fragment))
         (covered
          (mapcar
           #'emacsvox-aural-feature-fragment-example-rule curated)))
    (append
     curated
     (cl-loop
      for rule in (emacsvox-aural-tools--fragment-rules fragment)
      when
      (and
       (emacsvox-aural-rule-enabled rule)
       (not (memq (emacsvox-aural-rule-id rule) covered)))
      collect
      (emacsvox-aural-tools--automatic-fragment-example fragment rule)))))

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

(defvar-local emacsvox-aural-feature-fragments-view 'grouped
  "Current presentation-option manager view.")

(defvar-local emacsvox-aural-feature-fragments-collapsed-collections nil
  "Collections hidden in the current presentation-option manager.")

(defvar emacsvox-aural-tools--fragment-preview-last-examples
  (make-hash-table :test #'eq)
  "Most recently selected preview example for each presentation option.")

(defvar-local emacsvox-aural-feature-fragment-previews-fragment nil
  "Presentation option shown in the current preview buffer.")

(defvar-local emacsvox-aural-feature-fragment-previews-examples nil
  "Preview examples shown in the current preview buffer.")

(defvar-local emacsvox-aural-feature-fragment-previews-isolated nil
  "Whether the current preview buffer auditions its option in isolation.")

(defun emacsvox-aural-tools--fragment-collection-row-p (id)
  "Return non-nil when manager row ID represents a collection."
  (and (consp id) (eq (car id) 'collection) (symbolp (cdr id))))

(defun emacsvox-aural-tools--fragment-collection-row-id (collection)
  "Return manager row identifier for COLLECTION."
  (cons 'collection collection))

(defun emacsvox-aural-tools--fragment-at-point-or-read (&optional prompt)
  "Return the presentation option at point, or read one using PROMPT."
  (let ((id
         (and
          (derived-mode-p 'emacsvox-aural-feature-fragments-mode)
          (tabulated-list-get-id))))
    (cond
     ((and (symbolp id) (emacsvox-aural-feature-fragment-entry id))
      id)
     ((emacsvox-aural-tools--fragment-collection-row-p id)
      (user-error
       "%s is a collection; press TAB or RET to expand or collapse it"
       (emacsvox-aural-tools--humanize (cdr id))))
     (t
      (let ((candidates (emacsvox-aural-feature-fragment-candidates)))
        (unless candidates
          (user-error "No presentation options are registered"))
        (intern
         (completing-read
          (or prompt "Aural presentation option: ")
          candidates nil 'must-match)))))))

(defun emacsvox-aural-tools--ordered-feature-fragment-ids ()
  "Return registered presentation options in stable order."
  (emacsvox-aural-normalized-feature-fragment-order))

(defun emacsvox-aural-tools--fragment-collections ()
  "Return presentation-option collections and their stably ordered entries."
  (let (collections)
    (dolist (id (emacsvox-aural-tools--ordered-feature-fragment-ids))
      (let* ((entry (emacsvox-aural-feature-fragment-entry id))
             (collection
              (emacsvox-aural-feature-fragment-collection entry))
             (cell (assq collection collections)))
        (if cell
            (setcdr cell (append (cdr cell) (list id)))
          (push (list collection id) collections))))
    (sort
     collections
     (lambda (left right)
       (string-lessp
        (symbol-name (car left))
        (symbol-name (car right)))))))

(defun emacsvox-aural-tools--fragment-kind (entry)
  "Return a user-facing kind name for feature fragment ENTRY."
  (if (emacsvox-aural-feature-fragment-entry-built-in entry)
      "built-in"
    "personal"))

(defun emacsvox-aural-tools--fragment-row (id)
  "Return a tabulated manager row for presentation option ID."
  (let* ((entry (emacsvox-aural-feature-fragment-entry id))
         (compiled
          (emacsvox-aural-feature-fragment-entry-compiled entry))
         (position
          (cl-position id emacsvox-aural-enabled-feature-fragments))
         (report (emacsvox-aural-validate-feature-fragment id)))
    (list
     id
     (vector
      (if (eq emacsvox-aural-feature-fragments-view 'grouped)
          (format "  %s" (emacsvox-aural-tools--humanize id))
        (emacsvox-aural-tools--humanize id))
      (if position (format "enabled %d" (1+ position)) "disabled")
      (emacsvox-aural-tools--fragment-kind entry)
      (format
       "%d"
       (length (emacsvox-aural-scheme-rules compiled)))
      (if (emacsvox-aural-validation-report-valid report)
          "valid"
        "invalid")
      (emacsvox-aural-scheme-summary compiled)))))

(defun emacsvox-aural-tools--fragment-collection-row (collection ids)
  "Return a tabulated manager row for COLLECTION containing IDS."
  (let* ((enabled
          (cl-count-if
           (lambda (id)
             (emacsvox-aural-feature-fragment-enabled-p id))
           ids))
         (rules
          (cl-loop
           for id in ids
           sum
           (length
            (emacsvox-aural-scheme-rules
             (emacsvox-aural-feature-fragment-entry-compiled
              (emacsvox-aural-feature-fragment-entry id))))))
         (collapsed
          (memq
           collection
           emacsvox-aural-feature-fragments-collapsed-collections)))
    (list
     (emacsvox-aural-tools--fragment-collection-row-id collection)
     (vector
      (capitalize (emacsvox-aural-tools--humanize collection))
      (format "%d of %d enabled" enabled (length ids))
      "collection"
      (number-to-string rules)
      ""
      (format
       "%s; %s to %s"
       (if collapsed "collapsed" "expanded")
       "TAB or RET"
       (if collapsed "expand" "collapse"))))))

(defun emacsvox-aural-feature-fragments--set-entries ()
  "Populate the current presentation-option manager."
  (setq
   tabulated-list-entries
   (if (eq emacsvox-aural-feature-fragments-view 'active)
       (mapcar
        #'emacsvox-aural-tools--fragment-row
        emacsvox-aural-enabled-feature-fragments)
     (cl-mapcan
      (lambda (collection)
        (let ((id (car collection))
              (fragments (cdr collection)))
          (cons
           (emacsvox-aural-tools--fragment-collection-row id fragments)
           (unless
               (memq
                id
                emacsvox-aural-feature-fragments-collapsed-collections)
             (mapcar
              #'emacsvox-aural-tools--fragment-row fragments)))))
      (emacsvox-aural-tools--fragment-collections)))))

(defun emacsvox-aural-feature-fragments--goto (fragment)
  "Move to feature FRAGMENT in the current manager."
  (emacsvox-aural-ui-goto-row fragment))

(defun emacsvox-aural-feature-fragments-refresh (&optional fragment)
  "Refresh the feature-fragment manager, preserving FRAGMENT and column."
  (interactive)
  (emacsvox-aural-ui-refresh-tabulated
   #'emacsvox-aural-feature-fragments--set-entries fragment))

(defun emacsvox-aural-tools--refresh-fragment-manager (&optional fragment)
  "Refresh an existing feature-fragment manager and select FRAGMENT."
  (when-let* ((buffer (get-buffer "*Aural Feature Fragments*")))
    (with-current-buffer buffer
      (when (derived-mode-p 'emacsvox-aural-feature-fragments-mode)
        (emacsvox-aural-feature-fragments-refresh fragment)))))

(defun emacsvox-aural-tools--fragment-spoken-summary (fragment)
  "Return a concise spoken summary of presentation option FRAGMENT."
  (let* ((entry (emacsvox-aural-feature-fragment-entry fragment))
         (compiled
          (emacsvox-aural-feature-fragment-entry-compiled entry))
         (position
          (cl-position fragment emacsvox-aural-enabled-feature-fragments))
         (count (length (emacsvox-aural-scheme-rules compiled)))
         (report (emacsvox-aural-validate-feature-fragment fragment)))
    (format
     "%s. %s %s presentation option. %s. %s. %d %s. %s."
     (emacsvox-aural-tools--humanize fragment)
     (emacsvox-aural-tools--fragment-kind entry)
     (emacsvox-aural-tools--humanize
      (emacsvox-aural-feature-fragment-collection entry))
     (if position
         (format "Enabled at position %d" (1+ position))
       "Disabled")
     (emacsvox-aural-scheme-summary compiled)
     count
     (if (= count 1) "presentation" "presentations")
     (if (emacsvox-aural-validation-report-valid report)
         "Valid"
       "Invalid; press v for diagnostics"))))

(defun emacsvox-aural-tools--fragment-collection-spoken-summary
    (collection)
  "Return a concise spoken summary for manager COLLECTION."
  (let* ((ids (cdr (assq collection
                          (emacsvox-aural-tools--fragment-collections))))
         (enabled
          (cl-count-if
           #'emacsvox-aural-feature-fragment-enabled-p ids))
         (collapsed
          (memq
           collection
           emacsvox-aural-feature-fragments-collapsed-collections)))
    (format
     "%s collection. %d of %d options enabled. %s."
     (emacsvox-aural-tools--humanize collection)
     enabled
     (length ids)
     (if collapsed "Collapsed" "Expanded"))))

(defun emacsvox-aural-feature-fragments-speak-current ()
  "Speak the presentation option or collection at point."
  (interactive)
  (let* ((id (tabulated-list-get-id))
         (summary
          (if (emacsvox-aural-tools--fragment-collection-row-p id)
              (emacsvox-aural-tools--fragment-collection-spoken-summary
               (cdr id))
            (emacsvox-aural-tools--fragment-spoken-summary
             (emacsvox-aural-tools--fragment-at-point-or-read)))))
    (if (fboundp 'tts-speak)
        (tts-speak summary)
      (message "%s" summary))
    summary))

(defun emacsvox-aural-feature-fragments-speak-current-cell ()
  "Speak the current feature-fragment column title and value."
  (interactive)
  (emacsvox-aural-tools--speak-tabulated-cell))

(defun emacsvox-aural-feature-fragments-next ()
  "Move to and speak the next presentation-option row."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-row
   1 "presentation option list"))

(defun emacsvox-aural-feature-fragments-previous ()
  "Move to and speak the previous presentation-option row."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-row
   -1 "presentation option list"))

(defun emacsvox-aural-feature-fragments-next-column ()
  "Move right and speak the next feature-fragment column."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-column 1))

(defun emacsvox-aural-feature-fragments-previous-column ()
  "Move left and speak the previous feature-fragment column."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-column -1))

(defun emacsvox-aural-feature-fragments-toggle-collection ()
  "Expand or collapse the presentation-option collection at point."
  (interactive)
  (let ((id (tabulated-list-get-id)))
    (unless (emacsvox-aural-tools--fragment-collection-row-p id)
      (user-error "Move to a collection row before expanding or collapsing"))
    (let ((collection (cdr id)))
      (if
          (memq
           collection
           emacsvox-aural-feature-fragments-collapsed-collections)
          (setq
           emacsvox-aural-feature-fragments-collapsed-collections
           (delq
            collection
            emacsvox-aural-feature-fragments-collapsed-collections))
        (push
         collection
         emacsvox-aural-feature-fragments-collapsed-collections))
      (emacsvox-aural-feature-fragments-refresh id)
      (emacsvox-aural-feature-fragments-speak-current))))

(defun emacsvox-aural-feature-fragments-activate ()
  "Open the option at point, or toggle its collection."
  (interactive)
  (if
      (emacsvox-aural-tools--fragment-collection-row-p
       (tabulated-list-get-id))
      (emacsvox-aural-feature-fragments-toggle-collection)
    (emacsvox-aural-describe-feature-fragment)))

(defun emacsvox-aural-feature-fragments-toggle-view ()
  "Switch between grouped discovery and active precedence views."
  (interactive)
  (let ((selected
         (and
          (symbolp (tabulated-list-get-id))
          (tabulated-list-get-id))))
    (setq
     emacsvox-aural-feature-fragments-view
     (if (eq emacsvox-aural-feature-fragments-view 'grouped)
         'active
       'grouped))
    (emacsvox-aural-feature-fragments-refresh selected)
    (let ((message
           (if (eq emacsvox-aural-feature-fragments-view 'grouped)
               "Grouped presentation options view"
             "Active presentation order, weakest to strongest")))
      (if (fboundp 'tts-speak)
          (tts-speak message)
        (message "%s" message)))))

(defun emacsvox-aural-describe-feature-fragment (&optional fragment)
  "Describe registered presentation option FRAGMENT."
  (interactive)
  (let* ((fragment
          (or
           fragment
           (emacsvox-aural-tools--fragment-at-point-or-read
            "View presentation option: ")))
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
      (princ (format "Aural presentation option: %s\n\n" fragment))
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
       (format
         "Collection: %s\n"
         (emacsvox-aural-tools--humanize
          (emacsvox-aural-feature-fragment-collection entry))))
      (princ
       (format "Summary: %s\n"
               (emacsvox-aural-scheme-summary compiled)))
      (let ((examples
             (emacsvox-aural-feature-fragment-examples fragment)))
        (princ
         (format
          "Curated preview examples: %d%s\n"
          (length examples)
          (if examples
              (format
               " (%s)"
               (mapconcat
                #'emacsvox-aural-feature-fragment-example-summary
                examples ", "))
            ""))))
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

(defun emacsvox-aural-tools--fragment-matching-rules
    (fragment facts context)
  "Return FRAGMENT rules matching FACTS and CONTEXT."
  (condition-case nil
      (let ((input (emacsvox-aural-normalize-input facts context)))
        (cl-remove-if-not
         (lambda (rule)
           (emacsvox-aural-rule-matches-p rule input))
         (emacsvox-aural-tools--fragment-rules fragment)))
    (emacsvox-aural-rule-error nil)))

(defun emacsvox-aural-tools--fragment-live-preview-input (fragment)
  "Return a live source preview input for FRAGMENT, or nil.

The source facts and mode remain real.  When necessary, choose the occasion
that lets the greatest number of fragment rules match those facts."
  (let ((source
         (if (emacsvox-aural-tools--interface-buffer-p)
             (emacsvox-aural-inspection-source-buffer)
           (emacsvox-aural-inspection-last-source-buffer))))
    (when source
      (with-current-buffer source
        (when-let* ((facts (emacsvox-aural-facts-at-point)))
          (let* ((rules (emacsvox-aural-tools--fragment-rules fragment))
                 (base-context (emacsvox-aural-context-at-point))
                 (current
                  (or (plist-get base-context :occasion) 'continuous))
                 (occasions
                  (delete-dups
                   (cons
                    current
                    (delq
                     nil
                     (mapcar
                      (lambda (rule)
                        (emacsvox-aural-selector-occasion
                         (emacsvox-aural-rule-selector rule)))
                      rules)))))
                 best-context
                 best-count)
            (dolist (occasion occasions)
              (let* ((context
                      (emacsvox-aural-inspection-context-for-occasion
                       base-context occasion))
                     (count
                      (length
                       (emacsvox-aural-tools--fragment-matching-rules
                        fragment facts context))))
                (when (> count (or best-count 0))
                  (setq best-context context
                        best-count count))))
            (when best-context
              (unless (plist-member facts :content)
                (let ((content
                       (string-trim
                        (buffer-substring-no-properties
                         (line-beginning-position)
                         (line-end-position)))))
                  (setq
                   facts
                   (plist-put
                    (copy-tree facts)
                    :content
                    (if (string-empty-p content) "Example" content)))))
              (list
               :kind 'live
               :summary
               (format "%s at point" (buffer-name))
               :facts facts
               :context best-context))))))))

(defun emacsvox-aural-tools--fragment-preview-example
    (fragment &optional example-id prompt)
  "Return one simulated example for FRAGMENT.

EXAMPLE-ID selects a particular example.  When PROMPT is non-nil, ask when
more than one example is available."
  (let ((examples
         (emacsvox-aural-tools--fragment-preview-examples fragment)))
    (unless examples
      (user-error "Presentation option %s has no rules to preview" fragment))
    (cond
     (example-id
      (or
       (cl-find
        example-id examples
        :key #'emacsvox-aural-feature-fragment-example-id
        :test #'eq)
       (user-error
        "Presentation option %s has no preview example %s"
        fragment example-id)))
     ((or (= (length examples) 1) (not prompt))
      (car examples))
     (t
      (let* ((choices
              (mapcar
               (lambda (example)
                 (cons
                  (format
                   "%s [%s]"
                   (emacsvox-aural-feature-fragment-example-summary example)
                   (emacsvox-aural-feature-fragment-example-id example))
                  example))
               examples))
             (answer
              (completing-read
               "Preview example: " choices nil 'must-match)))
        (cdr (assoc answer choices)))))))

(defun emacsvox-aural-tools--fragment-preview-enabled-order (fragment)
  "Return enabled option order with FRAGMENT included at stable precedence."
  (let ((members
         (cons
          fragment
          (copy-sequence emacsvox-aural-enabled-feature-fragments))))
    (cl-remove-if-not
     (lambda (id) (memq id members))
     (emacsvox-aural-normalized-feature-fragment-order))))

(defun emacsvox-aural-tools--resolve-fragment-preview
    (fragment facts context isolated)
  "Resolve FRAGMENT for FACTS and CONTEXT.

When ISOLATED is non-nil, resolve only the option's rules.  Otherwise combine
it with the active configuration without changing persistent state."
  (if isolated
      (emacsvox-aural-resolve
       facts context
       (emacsvox-aural-tools--fragment-rules fragment))
    (let
        ((emacsvox-aural-enabled-feature-fragments
          (emacsvox-aural-tools--fragment-preview-enabled-order fragment))
         (emacsvox-aural--current-rules-cache
          (make-hash-table :test #'equal)))
      (emacsvox-aural-resolve-active facts context))))

(defun emacsvox-aural-tools--compile-fragment-preview
    (fragment facts context isolated)
  "Compile a concrete preview of FRAGMENT for FACTS and CONTEXT.

ISOLATED has the meaning documented by
`emacsvox-aural-tools--resolve-fragment-preview'."
  (let* ((facts
          (if (plist-member facts :content)
              (copy-tree facts)
            (plist-put (copy-tree facts) :content "Example")))
         (render
          (emacsvox-aural-tools--resolve-fragment-preview
           fragment facts context isolated)))
    (emacsvox-aural-compile-plan render facts context)))

(defun emacsvox-aural-tools--play-fragment-preview
    (fragment facts context isolated)
  "Compile and play FRAGMENT for FACTS and CONTEXT.

When ISOLATED is non-nil, play only the option's rules.  Otherwise combine
it with the active configuration without changing persistent state."
  (let ((concrete
         (emacsvox-aural-tools--compile-fragment-preview
          fragment facts context isolated)))
    (emacsvox-aural-preview-play-plan concrete)))

(defun emacsvox-aural-tools--fragment-preview-example-input (example)
  "Return copied facts and context from preview EXAMPLE."
  (list
   (copy-tree
    (emacsvox-aural-feature-fragment-example-facts example))
   (copy-tree
    (emacsvox-aural-feature-fragment-example-context example))))

(defun emacsvox-aural-tools--audition-fragment-preview-cues
    (fragment example isolated)
  "Audition only the concrete cues for FRAGMENT EXAMPLE.

ISOLATED controls whether compilation includes the active configuration.
No speech actions, content, presentation history, or training explanations
are submitted, so speech cannot mask the auditioned cues."
  (pcase-let*
      ((`(,facts ,context)
        (emacsvox-aural-tools--fragment-preview-example-input example))
       (concrete
        (emacsvox-aural-tools--compile-fragment-preview
         fragment facts context isolated))
       (cues
        (cl-remove-if-not
         (lambda (action)
           (eq
            (emacsvox-aural-concrete-action-kind action)
            'cue))
         (append
          (emacsvox-aural-concrete-plan-before concrete)
          (emacsvox-aural-concrete-plan-after concrete)))))
    (unless cues
      (user-error
       "Preview example %s has no earcon"
       (emacsvox-aural-feature-fragment-example-id example)))
    (emacsvox-aural-preview-play-cues cues)
    (puthash
     fragment
     (emacsvox-aural-feature-fragment-example-id example)
     emacsvox-aural-tools--fragment-preview-last-examples)
    (emacsvox-aural-preview-message
     "Auditioning %s"
     (mapconcat
      (lambda (cue)
        (emacsvox-aural-tools--humanize
         (emacsvox-aural-concrete-action-cue cue)))
      cues ", "))
    (list :fragment fragment :example example :cues cues :concrete concrete)))

(defun emacsvox-aural-feature-fragments-preview
    (&optional isolated fragment example-id)
  "Preview a presentation option without changing its enabled state.

Use live facts from the remembered source buffer when they match FRAGMENT.
Otherwise use a curated or automatically derived simulated example.  When
several simulations are available interactively, open a persistent preview
buffer instead of repeatedly prompting in the minibuffer.
With prefix argument ISOLATED, play only the option rather than composing it
with the active configuration.  EXAMPLE-ID selects a simulation directly."
  (interactive "P")
  (let* ((interactivep (called-interactively-p 'interactive))
         (fragment
          (or
           fragment
           (emacsvox-aural-tools--fragment-at-point-or-read
            "Preview presentation option: ")))
         (live
          (unless example-id
            (emacsvox-aural-tools--fragment-live-preview-input fragment)))
         (examples
          (unless live
            (emacsvox-aural-tools--fragment-preview-examples fragment)))
         (example
          (unless (or live
                      (and
                       interactivep
                       (null example-id)
                       (> (length examples) 1)))
            (emacsvox-aural-tools--fragment-preview-example
             fragment example-id nil))))
    (if
        (and
         interactivep
         (null live)
         (null example-id)
         (> (length examples) 1))
        (emacsvox-aural-list-feature-fragment-previews
         fragment isolated examples t)
      (let* ((kind (if live 'live 'simulated))
             (summary
              (if live
                  (plist-get live :summary)
                (emacsvox-aural-feature-fragment-example-summary example)))
             (facts
              (copy-tree
               (if live
                   (plist-get live :facts)
                 (emacsvox-aural-feature-fragment-example-facts example))))
             (context
              (copy-tree
               (if live
                   (plist-get live :context)
                 (emacsvox-aural-feature-fragment-example-context example))))
             (announcement
              (format
               "%s preview. %s. %s occasion."
               (if live "Live source context" "Simulated example")
               summary
               (emacsvox-aural-tools--humanize
                (or (plist-get context :occasion) 'continuous)))))
        (emacsvox-aural-preview-message "%s" announcement)
        (when example
          (puthash
           fragment
           (emacsvox-aural-feature-fragment-example-id example)
           emacsvox-aural-tools--fragment-preview-last-examples))
        (list
         :kind kind
         :fragment fragment
         :example
         (and example
              (emacsvox-aural-feature-fragment-example-id example))
         :announcement announcement
         :concrete
         (emacsvox-aural-tools--play-fragment-preview
          fragment facts context isolated))))))

(defun emacsvox-aural-tools--fragment-preview-action-description (action)
  "Return a short user-facing description of render ACTION."
  (pcase (emacsvox-aural-action-kind action)
    ('cue
     (format
      "%s earcon"
      (emacsvox-aural-tools--humanize
       (emacsvox-aural-action-cue action))))
    ('speech
     (if-let* ((text (emacsvox-aural-action-text action)))
         (format "says %s" text)
       "speech"))
    ('pause
     (format
      "%s second pause"
      (emacsvox-aural-action-duration action)))
    (_
     (emacsvox-aural-tools--humanize
      (emacsvox-aural-action-kind action)))))

(defun emacsvox-aural-tools--fragment-preview-output-summary
    (fragment example isolated)
  "Describe the output of FRAGMENT EXAMPLE under ISOLATED resolution."
  (pcase-let*
      ((`(,facts ,context)
        (emacsvox-aural-tools--fragment-preview-example-input example))
       (facts
        (if (plist-member facts :content)
            facts
          (plist-put facts :content "Example")))
       (render
        (emacsvox-aural-tools--resolve-fragment-preview
         fragment facts context isolated))
       (actions
        (append
         (emacsvox-aural-render-plan-before render)
         (emacsvox-aural-render-plan-after render)))
       (content (emacsvox-aural-render-plan-content render))
       (voice (emacsvox-aural-content-style-voice content))
       (parts
        (mapcar
         #'emacsvox-aural-tools--fragment-preview-action-description
         actions)))
    (when voice
      (setq
       parts
       (append
        parts
        (list
         (format
          "content voice %s"
          (if (symbolp voice)
              (emacsvox-aural-tools--humanize voice)
            voice))))))
    (when (not (emacsvox-aural-content-style-speak content))
      (setq parts (append parts (list "content muted"))))
    (if parts
        (string-join parts ", ")
      "content only")))

(defun emacsvox-aural-tools--fragment-preview-context-summary (example)
  "Return a short context summary for preview EXAMPLE."
  (let* ((context
          (emacsvox-aural-feature-fragment-example-context example))
         (scope
          (or
           (plist-get context :module)
           (plist-get context :mode)
           'general))
         (occasion
          (or (plist-get context :occasion) 'continuous)))
    (format
     "%s, %s"
     (emacsvox-aural-tools--humanize scope)
     (emacsvox-aural-tools--humanize occasion))))

(defun emacsvox-aural-tools--fragment-preview-example-kind (example)
  "Return the user-facing provenance kind of preview EXAMPLE."
  (if
      (eq
       (emacsvox-aural-feature-fragment-example-source example)
       'automatic)
      "automatic"
    "curated"))

(defun emacsvox-aural-tools--fragment-preview-row (example)
  "Return one tabulated preview row for EXAMPLE."
  (list
   (emacsvox-aural-feature-fragment-example-id example)
   (vector
    (emacsvox-aural-feature-fragment-example-summary example)
    (emacsvox-aural-tools--fragment-preview-example-kind example)
    (emacsvox-aural-tools--humanize
     (emacsvox-aural-feature-fragment-example-rule example))
    (emacsvox-aural-tools--fragment-preview-context-summary example)
    (emacsvox-aural-tools--fragment-preview-output-summary
     emacsvox-aural-feature-fragment-previews-fragment
     example
     emacsvox-aural-feature-fragment-previews-isolated))))

(defun emacsvox-aural-feature-fragment-previews--set-entries ()
  "Populate the current presentation-option preview buffer."
  (setq
   tabulated-list-entries
   (mapcar
    #'emacsvox-aural-tools--fragment-preview-row
    emacsvox-aural-feature-fragment-previews-examples)))

(defun emacsvox-aural-feature-fragment-previews--goto (example-id)
  "Move to preview EXAMPLE-ID and its first column."
  (emacsvox-aural-ui-goto-row example-id))

(defun emacsvox-aural-feature-fragment-previews-refresh
    (&optional example-id)
  "Refresh preview examples, preserving EXAMPLE-ID and the current column."
  (interactive)
  (emacsvox-aural-ui-refresh-tabulated
   #'emacsvox-aural-feature-fragment-previews--set-entries
   example-id
   (or
    (gethash
     emacsvox-aural-feature-fragment-previews-fragment
     emacsvox-aural-tools--fragment-preview-last-examples)
    (and
     emacsvox-aural-feature-fragment-previews-examples
     (emacsvox-aural-feature-fragment-example-id
      (car emacsvox-aural-feature-fragment-previews-examples))))))

(defun emacsvox-aural-feature-fragment-previews--current-example ()
  "Return the preview example represented by the current row."
  (let ((id
         (or
          (tabulated-list-get-id)
          (user-error "Move to a preview example first"))))
    (or
     (cl-find
      id emacsvox-aural-feature-fragment-previews-examples
      :key #'emacsvox-aural-feature-fragment-example-id
      :test #'eq)
     (user-error "Unknown preview example: %S" id))))

(defun emacsvox-aural-feature-fragment-previews--remember-current ()
  "Remember the preview example selected by the current row."
  (when-let* ((id (tabulated-list-get-id)))
    (puthash
     emacsvox-aural-feature-fragment-previews-fragment
     id
     emacsvox-aural-tools--fragment-preview-last-examples))
  (tabulated-list-get-id))

(defun emacsvox-aural-feature-fragment-previews-speak-current ()
  "Speak a concise description of the preview example at point."
  (interactive)
  (let* ((example
          (emacsvox-aural-feature-fragment-previews--current-example))
         (summary
          (format
           "%s. %s example. Rule %s. Context %s. %s. %s preview."
           (emacsvox-aural-feature-fragment-example-summary example)
           (emacsvox-aural-tools--fragment-preview-example-kind example)
           (emacsvox-aural-tools--humanize
            (emacsvox-aural-feature-fragment-example-rule example))
           (emacsvox-aural-tools--fragment-preview-context-summary example)
           (emacsvox-aural-tools--fragment-preview-output-summary
            emacsvox-aural-feature-fragment-previews-fragment
            example
            emacsvox-aural-feature-fragment-previews-isolated)
           (if emacsvox-aural-feature-fragment-previews-isolated
               "Isolated"
             "Composed"))))
    (emacsvox-aural-feature-fragment-previews--remember-current)
    (if (fboundp 'tts-speak)
        (tts-speak summary)
      (message "%s" summary))
    summary))

(defun emacsvox-aural-feature-fragment-previews-speak-current-cell ()
  "Speak the current preview column title and value."
  (interactive)
  (emacsvox-aural-tools--speak-tabulated-cell))

(defun emacsvox-aural-feature-fragment-previews-next ()
  "Move to and speak the next preview example."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-row 1 "preview example list")
  (emacsvox-aural-feature-fragment-previews--remember-current))

(defun emacsvox-aural-feature-fragment-previews-previous ()
  "Move to and speak the previous preview example."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-row -1 "preview example list")
  (emacsvox-aural-feature-fragment-previews--remember-current))

(defun emacsvox-aural-feature-fragment-previews-next-column ()
  "Move right and speak the next preview column."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-column 1))

(defun emacsvox-aural-feature-fragment-previews-previous-column ()
  "Move left and speak the previous preview column."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-column -1))

(defun emacsvox-aural-feature-fragment-previews-play ()
  "Play the complete preview example at point."
  (interactive)
  (let* ((example
          (emacsvox-aural-feature-fragment-previews--current-example))
         (id
          (emacsvox-aural-feature-fragment-example-id example)))
    (emacsvox-aural-feature-fragment-previews--remember-current)
    (emacsvox-aural-feature-fragments-preview
     emacsvox-aural-feature-fragment-previews-isolated
     emacsvox-aural-feature-fragment-previews-fragment
     id)))

(defun emacsvox-aural-feature-fragment-previews-audition-cues ()
  "Audition only the earcons in the preview example at point."
  (interactive)
  (emacsvox-aural-tools--audition-fragment-preview-cues
   emacsvox-aural-feature-fragment-previews-fragment
   (emacsvox-aural-feature-fragment-previews--current-example)
   emacsvox-aural-feature-fragment-previews-isolated))

(defun emacsvox-aural-feature-fragment-previews-toggle-isolated ()
  "Toggle composed versus isolated resolution in this preview buffer."
  (interactive)
  (setq
   emacsvox-aural-feature-fragment-previews-isolated
   (not emacsvox-aural-feature-fragment-previews-isolated))
  (emacsvox-aural-feature-fragment-previews-refresh)
  (let ((summary
         (if emacsvox-aural-feature-fragment-previews-isolated
             "Isolated option preview"
           "Preview composed with the active configuration")))
    (if (fboundp 'tts-speak)
        (tts-speak summary)
      (message "%s" summary))
    summary))

(defun emacsvox-aural-feature-fragment-previews-help ()
  "Display and speak presentation-option preview help."
  (interactive)
  (with-help-window (help-buffer)
    (princ
     (concat
      "Aural Presentation Option Preview\n\n"
      "Each row is a curated or automatically derived representative example.\n"
      "Full preview reproduces normal presentation.  Cue-only audition stops\n"
      "manager speech and plays no labels, content, or training explanation.\n\n"
      "n or down next       p or up previous\n"
      "left/right column    . speak titled cell\n"
      "RET or P full preview\n"
      "c cue-only audition  i composed/isolated\n"
      "SPC speak example    g refresh\n"
      "o option manager     h aural home\n"
      "q quit\n")))
  (when (fboundp 'emacsvox-speak-help)
    (emacsvox-speak-help)))

(define-derived-mode
    emacsvox-aural-feature-fragment-previews-mode
    emacsvox-aural-tabulated-mode
  "Aural-Option-Preview"
  "Spoken browser for representative presentation-option examples."
  (emacsvox-aural-ui-configure-tabulated
   "preview example list"
   #'emacsvox-aural-feature-fragment-previews-speak-current
   #'emacsvox-aural-feature-fragment-previews-refresh
   nil
   #'emacsvox-aural-feature-fragment-previews--remember-current)
  (setq
   tabulated-list-format
   [("Example" 38 nil)
    ("Source" 12 nil)
    ("Rule" 38 nil)
    ("Context" 28 nil)
    ("Output" 0 nil)])
  (setq tabulated-list-padding 2)
  (add-hook
   'tabulated-list-revert-hook
   #'emacsvox-aural-feature-fragment-previews--set-entries nil t)
  (tabulated-list-init-header))

(dolist
    (binding
     '(("RET" . emacsvox-aural-feature-fragment-previews-play)
       ("P" . emacsvox-aural-feature-fragment-previews-play)
       ("c" . emacsvox-aural-feature-fragment-previews-audition-cues)
       ("i" . emacsvox-aural-feature-fragment-previews-toggle-isolated)
       ("o" . emacsvox-aural-list-feature-fragments)
       ("h" . emacsvox-aural)
       ("?" . emacsvox-aural-feature-fragment-previews-help)))
  (define-key
   emacsvox-aural-feature-fragment-previews-mode-map
   (kbd (car binding))
   (cdr binding)))

(defun emacsvox-aural-list-feature-fragment-previews
    (fragment &optional isolated examples speak)
  "Open the spoken preview browser for presentation option FRAGMENT.

When ISOLATED is non-nil, initially resolve the option by itself.  EXAMPLES
may supply an already completed preview-example list.  When SPEAK is non-nil,
announce the selected example after displaying the buffer."
  (let* ((source
          (emacsvox-aural-inspection-remember-source-buffer))
         (examples
          (or
           examples
           (emacsvox-aural-tools--fragment-preview-examples fragment)))
         (_
          (unless examples
            (user-error
             "Presentation option %s has no rules to preview"
             fragment)))
         (buffer (get-buffer-create "*Aural Option Preview*")))
    (with-current-buffer buffer
      (emacsvox-aural-feature-fragment-previews-mode)
      (emacsvox-aural-inspection-attach-source source)
      (setq
       emacsvox-aural-feature-fragment-previews-fragment fragment
       emacsvox-aural-feature-fragment-previews-examples examples
       emacsvox-aural-feature-fragment-previews-isolated
       (not (null isolated)))
      (emacsvox-aural-feature-fragment-previews-refresh))
    (emacsvox-aural-ui-pop-to-buffer buffer)
    (when (and speak (tabulated-list-get-id))
      (emacsvox-aural-feature-fragment-previews-speak-current))
    buffer))

(defun emacsvox-aural-tools--install-feature-fragment-state
    (registry enabled &optional order)
  "Validate and persist fragment REGISTRY, ENABLED state, and stable ORDER."
  (emacsvox-aural--validate-enabled-feature-fragments enabled registry)
  (let* ((previous (emacsvox-aural--capture-coordinated-state))
         (old-registry emacsvox-aural-feature-fragment-registry)
         (old-enabled emacsvox-aural-enabled-feature-fragments)
         (old-order emacsvox-aural-feature-fragment-order)
         (candidate-order
          (cl-remove-if-not
           (lambda (id) (gethash id registry))
           (copy-sequence
            (or order emacsvox-aural-feature-fragment-order))))
         (candidate-order
          (emacsvox-aural--merge-enabled-feature-fragment-order
           enabled candidate-order registry)))
    (setq
     emacsvox-aural-feature-fragment-registry registry
     emacsvox-aural-feature-fragment-order candidate-order
     emacsvox-aural-enabled-feature-fragments (copy-sequence enabled))
    (condition-case error
        (progn
          (emacsvox-aural-current-rules
           (emacsvox-aural-context-at-point))
          (emacsvox-aural-save-user-data))
      (error
       (setq
        emacsvox-aural-feature-fragment-registry old-registry
        emacsvox-aural-feature-fragment-order old-order
        emacsvox-aural-enabled-feature-fragments old-enabled)
       (signal (car error) (cdr error))))
    (emacsvox-aural--notify-coordinated-state-change
     previous 'feature-fragments '(feature-fragments))
    enabled))

(defun emacsvox-aural-create-feature-fragment (id &optional summary)
  "Create disabled personal feature fragment ID with SUMMARY."
  (interactive
   (let* ((answer (read-string "New presentation option identifier: "))
          (_
           (when (string-empty-p answer)
             (user-error "Presentation option identifier cannot be empty"))))
     (list (intern answer) nil)))
  (when (emacsvox-aural-feature-fragment-entry id)
    (user-error "Presentation option already exists: %S" id))
  (let ((registry
         (copy-hash-table emacsvox-aural-feature-fragment-registry))
        (data
         (list
          :schema-version emacsvox-aural-scheme-schema-version
          :id id
          :summary
          (or summary (format "Personal presentation option %s" id))
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
            "Copy presentation option: "))
          (answer
           (read-string
            "New personal presentation option identifier: "
            (format "%s-copy" source))))
     (when (string-empty-p answer)
       (user-error "Presentation option identifier cannot be empty"))
     (list source (intern answer))))
  (when (emacsvox-aural-feature-fragment-entry new-id)
    (user-error "Presentation option already exists: %S" new-id))
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
    (message "Created personal presentation option %s" new-id)
    new-id))

(defun emacsvox-aural-delete-feature-fragment (&optional fragment)
  "Delete personal feature FRAGMENT, disabling it when necessary."
  (interactive)
  (let* ((fragment
          (or
           fragment
           (emacsvox-aural-tools--fragment-at-point-or-read
            "Delete personal presentation option: ")))
         (entry
          (or
           (emacsvox-aural-feature-fragment-entry fragment)
           (user-error "Unknown feature fragment: %S" fragment))))
    (when (emacsvox-aural-feature-fragment-entry-built-in entry)
      (user-error "Built-in presentation option %s cannot be deleted" fragment))
    (when
        (or
         (not (called-interactively-p 'interactive))
         (yes-or-no-p
          (format
           "Delete personal presentation option %s%s? "
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
      (message "Deleted personal presentation option %s" fragment)
      fragment)))

(defun emacsvox-aural-feature-fragments-toggle (&optional fragment)
  "Enable or disable feature FRAGMENT without changing its stable order."
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
            (let ((members
                   (cons
                    fragment
                    (copy-sequence
                     emacsvox-aural-enabled-feature-fragments))))
              (cl-remove-if-not
               (lambda (id) (memq id members))
               (emacsvox-aural-normalized-feature-fragment-order))))))
    (emacsvox-aural-tools--install-feature-fragment-state
     (copy-hash-table emacsvox-aural-feature-fragment-registry)
     enabled)
    (emacsvox-aural-tools--refresh-fragment-manager fragment)
    (message
     "%s presentation option %s"
     (if enabled-p "Disabled" "Enabled")
     fragment)
    (not enabled-p)))

(defun emacsvox-aural-feature-fragments-move (offset)
  "Move the enabled feature fragment at point by OFFSET."
  (when
      (and
       (derived-mode-p 'emacsvox-aural-feature-fragments-mode)
       (eq emacsvox-aural-feature-fragments-view 'grouped))
    (user-error "Press a to switch to active order before reordering options"))
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
               "First enabled presentation option."
             "Last enabled presentation option."))
        (let ((enabled
               (copy-sequence
                emacsvox-aural-enabled-feature-fragments))
              (order
               (emacsvox-aural-normalized-feature-fragment-order)))
          (cl-rotatef
           (nth index enabled)
           (nth destination enabled))
          (let ((left
                 (cl-position
                  fragment order))
                (right
                 (cl-position
                  (nth index enabled) order)))
            (cl-rotatef (nth left order) (nth right order)))
          (emacsvox-aural-tools--install-feature-fragment-state
           (copy-hash-table
            emacsvox-aural-feature-fragment-registry)
           enabled order)
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
       "Built-in presentation option %s is read-only; press c to copy it"
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
       report "presentation option"))
    report))

(defun emacsvox-aural-feature-fragments-help ()
  "Display and speak presentation-option manager help."
  (interactive)
  (with-help-window (help-buffer)
    (princ
     (concat
      "Aural Presentation Options\n\n"
      "The grouped view organizes options by the integration that supplies them.\n"
      "TAB or RET on a collection expands or collapses it.  The active-order view\n"
      "shows enabled options from weakest to strongest.  Toggling an option never\n"
      "changes its stable precedence.  Personal overrides remain stronger.\n"
      "Rows speak value then title; columns speak title then value.\n"
      "Moving past either boundary announces it.\n\n"
      "C-n or down next     C-p or up previous\n"
      "n next titled row    p previous titled row\n"
      "left/right column    . speak titled cell\n"
      "RET open/toggle      TAB expand/collapse collection\n"
      "SPC speak row        a grouped/active-order view\n"
      "P preview option     C-u P preview option alone\n"
      "Multiple examples open a reusable preview browser\n"
      "t enable/disable     M-up/M-down reorder enabled options\n"
      "N create personal    c copy as personal\n"
      "e edit personal      d delete personal\n"
      "v validate           g refresh\n"
      "s scheme manager     h aural home\n"
      "q quit\n")))
  (when (fboundp 'emacsvox-speak-help)
    (emacsvox-speak-help)))

(define-derived-mode
    emacsvox-aural-feature-fragments-mode
    emacsvox-aural-tabulated-mode
  "Aural-Options"
  "Major mode for viewing and managing aural presentation options."
  (emacsvox-aural-ui-configure-tabulated
   "presentation option list"
   #'emacsvox-aural-feature-fragments-speak-current
   #'emacsvox-aural-feature-fragments-refresh)
  (setq
   tabulated-list-format
   [("Option" 32 nil)
    ("Status" 16 nil)
    ("Kind" 12 nil)
    ("Rules" 8 nil)
    ("Validation" 12 nil)
    ("Summary" 0 nil)])
  (setq tabulated-list-padding 2)
  (add-hook
   'tabulated-list-revert-hook
   #'emacsvox-aural-feature-fragments--set-entries nil t)
  (tabulated-list-init-header))

(dolist
    (binding
     '(("RET" . emacsvox-aural-feature-fragments-activate)
       ("TAB" . emacsvox-aural-feature-fragments-toggle-collection)
       ("a" . emacsvox-aural-feature-fragments-toggle-view)
       ("P" . emacsvox-aural-feature-fragments-preview)
       ("t" . emacsvox-aural-feature-fragments-toggle)
       ("<M-up>" . emacsvox-aural-feature-fragments-move-up)
       ("<M-down>" . emacsvox-aural-feature-fragments-move-down)
       ("N" . emacsvox-aural-create-feature-fragment)
       ("c" . emacsvox-aural-copy-feature-fragment)
       ("e" . emacsvox-aural-feature-fragments-edit)
       ("d" . emacsvox-aural-delete-feature-fragment)
       ("v" . emacsvox-aural-show-feature-fragment-validation)
       ("s" . emacsvox-aural-list-schemes)
       ("h" . emacsvox-aural)
       ("?" . emacsvox-aural-feature-fragments-help)))
  (define-key
   emacsvox-aural-feature-fragments-mode-map
   (kbd (car binding))
   (cdr binding)))

(defun emacsvox-aural-list-feature-fragments ()
  "Open the accessible manager for aural presentation options."
  (interactive)
  (let ((source
         (emacsvox-aural-inspection-remember-source-buffer))
        (buffer (get-buffer-create "*Aural Feature Fragments*")))
    (with-current-buffer buffer
      (emacsvox-aural-feature-fragments-mode)
      (emacsvox-aural-inspection-attach-source source)
      (emacsvox-aural-feature-fragments-refresh
       (car emacsvox-aural-enabled-feature-fragments)))
    (emacsvox-aural-ui-pop-to-buffer buffer)
    (if (tabulated-list-get-id)
        (when (called-interactively-p 'interactive)
          (emacsvox-aural-feature-fragments-speak-current))
      (when (called-interactively-p 'interactive)
        (if (fboundp 'tts-speak)
            (tts-speak
             "No presentation options are registered.  Press N to create one.")
          (message
           "No presentation options are registered.  Press N to create one."))))
    buffer))

(defun emacsvox-aural-home--source-buffer ()
  "Return the live inspection source for the current aural home buffer."
  (emacsvox-aural-inspection-source-buffer))

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
       "Presentation options"
       (emacsvox-aural-home--enabled-fragment-status)
       "Browse grouped optional presentation additions and their active order"))
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
  (emacsvox-aural-ui-goto-row id))

(defun emacsvox-aural-home-refresh (&optional id)
  "Refresh aural home status, preserving row ID and the current column."
  (interactive)
  (emacsvox-aural-ui-refresh-tabulated
   (lambda ()
     (setq tabulated-list-entries (emacsvox-aural-home--entries)))
   id 'explain))

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

(define-derived-mode emacsvox-aural-home-mode
    emacsvox-aural-tabulated-mode
  "Emacsvox-Aural"
  "Spoken home mode for aural presentation discovery and interaction."
  (emacsvox-aural-ui-configure-tabulated
   "aural home"
   #'emacsvox-aural-home-speak-current
   #'emacsvox-aural-home-refresh)
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
       ("x" . emacsvox-aural-home-explain)
       ("P" . emacsvox-aural-home-profiles)
       ("V" . emacsvox-aural-home-voice-palettes)
       ("v" . emacsvox-aural-home-toggle-face-presentation)
       ("D" . emacsvox-aural-doctor)
       ("?" . emacsvox-aural-home-help)))
  (define-key
   emacsvox-aural-home-mode-map
   (kbd (car binding))
   (cdr binding)))

(defun emacsvox-aural (&optional source-buffer)
  "Open the spoken aural home using SOURCE-BUFFER for contextual operations."
  (interactive)
  (let* ((source
          (emacsvox-aural-inspection-remember-source-buffer
           (or source-buffer (current-buffer))))
         (buffer (get-buffer-create "*Emacsvox Aural*")))
    (with-current-buffer buffer
      (emacsvox-aural-home-mode)
      (emacsvox-aural-inspection-attach-source source)
      (emacsvox-aural-home-refresh 'explain))
    (emacsvox-aural-ui-pop-to-buffer buffer)
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
