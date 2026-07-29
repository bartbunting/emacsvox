;;; emacsvox-aural-scheme-manager.el --- Spoken scheme management -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Accessible discovery, preview, validation, activation, copying, renaming,
;; and deletion for registered aural presentation schemes.

;;; Code:

(require 'cl-lib)
(require 'help-mode)
(require 'subr-x)
(require 'tabulated-list)
(require 'emacsvox-aural-schemes)
(require 'emacsvox-aural-ui)
(require 'emacsvox-aural-description)
(require 'emacsvox-aural-preview)
(require 'emacsvox-aural-validation)
(require 'emacsvox-aural-inspection)

(declare-function emacsvox-icon "emacsvox-sounds" (icon))
(declare-function emacsvox-edit-aural-scheme
                  "emacsvox-aural-editor" (&optional scheme))
(declare-function emacsvox-edit-aural-scheme-advanced
                  "emacsvox-aural-editor" (&optional scheme))
(declare-function emacsvox-aural "emacsvox-aural-home"
                  (&optional source-buffer))
(declare-function emacsvox-aural-list-feature-fragments
                  "emacsvox-aural-feature-fragments" ())
(declare-function emacsvox-speak-help "emacsvox-speak" ())
(declare-function tts-speak "tts-speak" (text))

(defun emacsvox-aural-scheme-manager--scheme-at-point-or-read (&optional prompt)
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

(defun emacsvox-aural-scheme-manager--scheme-kind (entry)
  "Return a user-facing kind name for scheme ENTRY."
  (if (emacsvox-aural-scheme-entry-built-in entry)
      "built-in"
    "personal"))

(defun emacsvox-aural-scheme-manager--scheme-provider (entry)
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

(defun emacsvox-aural-scheme-manager--scheme-row (candidate)
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
      (emacsvox-aural-scheme-manager--scheme-kind entry)
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
      (emacsvox-aural-scheme-manager--scheme-provider entry)
      (emacsvox-aural-scheme-summary compiled)))))

(defun emacsvox-aural-schemes--set-entries ()
  "Populate the current scheme-manager buffer."
  (setq
   tabulated-list-entries
   (mapcar
    #'emacsvox-aural-scheme-manager--scheme-row
    (emacsvox-aural-scheme-candidates))))

(defun emacsvox-aural-schemes--goto-scheme (scheme)
  "Move to SCHEME in the current scheme-manager buffer."
  (emacsvox-aural-ui-goto-row scheme))

(defun emacsvox-aural-schemes-refresh (&optional scheme)
  "Refresh the scheme manager, preserving SCHEME or the current row."
  (interactive)
  (emacsvox-aural-ui-refresh-tabulated
   #'emacsvox-aural-schemes--set-entries scheme))

(defun emacsvox-aural-scheme-manager--refresh-if-live (&optional scheme)
  "Refresh an existing scheme-manager buffer and select SCHEME."
  (when-let* ((buffer (get-buffer "*Aural Schemes*")))
    (with-current-buffer buffer
      (when (derived-mode-p 'emacsvox-aural-schemes-mode)
        (emacsvox-aural-schemes-refresh scheme)))))

(defun emacsvox-aural-scheme-manager--spoken-summary (scheme)
  "Return a concise spoken summary of SCHEME."
  (let* ((entry (emacsvox-aural-scheme-entry scheme))
         (compiled (emacsvox-aural-scheme-entry-compiled entry))
         (parent (emacsvox-aural-scheme-parent compiled))
         (pack
          (emacsvox-aural-effective-scheme-provider
           'resource-pack scheme))
         (count
          (length (emacsvox-aural-effective-scheme-rules scheme t)))
         (provider (emacsvox-aural-scheme-manager--scheme-provider entry))
         (report (emacsvox-aural-validate-scheme scheme)))
    (string-join
     (delq
      nil
      (list
       (format "%s." (emacsvox-aural-humanize scheme))
       (format
        "%s%s scheme."
        (if (eq scheme emacsvox-aural-active-scheme) "Active " "")
        (emacsvox-aural-scheme-manager--scheme-kind entry))
       (format "Provided by %s." provider)
       (when parent
         (format
          "Based on %s."
          (emacsvox-aural-humanize parent)))
       (when pack
         (format
          "Sound pack %s."
          (emacsvox-aural-humanize pack)))
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
          (emacsvox-aural-scheme-manager--scheme-at-point-or-read))
         (summary
          (emacsvox-aural-scheme-manager--spoken-summary scheme)))
    (if (fboundp 'tts-speak)
        (tts-speak summary)
      (message "%s" summary))
    summary))

(defun emacsvox-aural-schemes-speak-current-cell ()
  "Speak the current manager column title and value."
  (interactive)
  (emacsvox-aural-ui-speak-current-cell))

(defun emacsvox-aural-schemes-next ()
  "Move to and speak the next scheme."
  (interactive)
  (emacsvox-aural-ui-move-row 1 "scheme list"))

(defun emacsvox-aural-schemes-previous ()
  "Move to and speak the previous scheme."
  (interactive)
  (emacsvox-aural-ui-move-row -1 "scheme list"))

(defun emacsvox-aural-schemes-next-column ()
  "Move right and speak the next manager column title and value."
  (interactive)
  (emacsvox-aural-ui-move-column 1))

(defun emacsvox-aural-schemes-previous-column ()
  "Move left and speak the previous manager column title and value."
  (interactive)
  (emacsvox-aural-ui-move-column -1))

(defun emacsvox-describe-aural-scheme (&optional scheme)
  "View direct, inherited, effective, and resource details for SCHEME."
  (interactive)
  (let* ((scheme
          (or
           scheme
           (emacsvox-aural-scheme-manager--scheme-at-point-or-read
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
          (emacsvox-aural-scheme-manager--spoken-summary scheme)))
    (with-help-window (help-buffer)
      (princ (format "Aural scheme: %s\n\n" scheme))
      (princ (format "Status: %s\n"
                     (if (eq scheme emacsvox-aural-active-scheme)
                         "active"
                       "inactive")))
      (princ
       (format
        "Kind: %s\n"
        (emacsvox-aural-scheme-manager--scheme-kind entry)))
      (princ
       (format
        "Provided by: %s\n"
        (emacsvox-aural-scheme-manager--scheme-provider entry)))
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
      (emacsvox-aural-print-rules direct)
      (princ "\nInherited presentations\n\n")
      (emacsvox-aural-print-rules inherited)
      (princ
       (format
        "\nEffective presentation order (%d total)\n\n"
        (length effective)))
      (emacsvox-aural-print-rules effective)
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
          (emacsvox-aural-scheme-manager--scheme-at-point-or-read
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
          (emacsvox-aural-scheme-manager--scheme-at-point-or-read
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
          (emacsvox-aural-scheme-manager--scheme-at-point-or-read
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
    (emacsvox-aural-scheme-manager--refresh-if-live new-id)
    (message
     "Created %s personal scheme %s"
     (if flattened "flattened" "inheriting")
     new-id)))

(defun emacsvox-aural-schemes-activate ()
  "Activate the scheme at point and refresh the manager."
  (interactive)
  (let ((scheme
         (emacsvox-aural-scheme-manager--scheme-at-point-or-read
          "Activate aural scheme: ")))
    (emacsvox-set-aural-scheme scheme)
    (emacsvox-aural-scheme-manager--refresh-if-live scheme)
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
      (emacsvox-aural-display-validation report))
    report))

(defun emacsvox-aural-scheme-manager--rule-candidates (&optional context)
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
      (emacsvox-aural-scheme-manager--rule-candidates)
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
           (emacsvox-aural-scheme-manager--scheme-at-point-or-read
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

(defun emacsvox-aural-scheme-manager--flattened-rules (scheme)
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
               :rules (emacsvox-aural-scheme-manager--flattened-rules source))
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
    (emacsvox-aural-persist-scheme-mutation
     'scheme-copied
     (lambda ()
       (emacsvox-aural-register-scheme
        data :source emacsvox-aural-schemes-file)))
    (when (called-interactively-p 'interactive)
      (message "Created personal aural scheme %s" new-id))
    new-id))

(defun emacsvox-aural-scheme-manager--dependents (scheme)
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
           (emacsvox-aural-scheme-manager--scheme-at-point-or-read
            "Delete personal aural scheme: ")))
         (entry (emacsvox-aural-scheme-entry scheme))
         (_
          (unless entry
            (user-error "Unknown aural scheme: %S" scheme)))
         (_
          (when (emacsvox-aural-scheme-entry-built-in entry)
            (user-error "Built-in scheme %s cannot be deleted" scheme)))
         (dependents
          (emacsvox-aural-scheme-manager--dependents scheme))
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
      (emacsvox-aural-persist-scheme-mutation
       'scheme-deleted
       (lambda ()
         (remhash scheme emacsvox-aural-scheme-registry)
         scheme))
      (when active
        (emacsvox-aural-select-scheme fallback))
      (emacsvox-aural-scheme-manager--refresh-if-live
       (if active fallback nil))
      (message "Deleted personal aural scheme %s" scheme)
      scheme)))

(defun emacsvox-rename-aural-scheme (&optional scheme new-id)
  "Rename personal SCHEME to NEW-ID and update direct child schemes."
  (interactive)
  (let* ((scheme
          (or
           scheme
           (emacsvox-aural-scheme-manager--scheme-at-point-or-read
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
          (emacsvox-aural-scheme-manager--dependents scheme))
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
        (emacsvox-aural-persist-scheme-mutation
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
        (emacsvox-aural-scheme-manager--refresh-if-live new-id)
        (message "Renamed personal aural scheme %s to %s" scheme new-id)
        new-id)))))

(defalias 'emacsvox-aural-list-schemes
  #'emacsvox-list-aural-schemes)
(defalias 'emacsvox-aural-describe-scheme
  #'emacsvox-describe-aural-scheme)
(defalias 'emacsvox-aural-show-scheme-validation
  #'emacsvox-validate-aural-scheme)
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

(provide 'emacsvox-aural-scheme-manager)
;;; emacsvox-aural-scheme-manager.el ends here
