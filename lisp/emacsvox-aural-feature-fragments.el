;;; emacsvox-aural-feature-fragments.el --- Spoken presentation options -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Accessible management, preview, validation, and persistence for optional
;; aural presentation fragments.

;;; Code:

(require 'cl-lib)
(require 'help-mode)
(require 'pp)
(require 'subr-x)
(require 'tabulated-list)
(require 'emacsvox-aural-schemes)
(require 'emacsvox-aural-ui)
(require 'emacsvox-aural-inspection)
(require 'emacsvox-aural-preview)
(require 'emacsvox-aural-validation)
(require 'emacsvox-aural-description)

(declare-function emacsvox-edit-aural-feature-fragment
                  "emacsvox-aural-editor" (&optional fragment))

(defun emacsvox-aural-feature-fragments--fragment-rules (fragment)
  "Return the compiled presentation rules for feature FRAGMENT."
  (let ((entry
         (or
          (emacsvox-aural-feature-fragment-entry fragment)
          (user-error "Unknown presentation option: %S" fragment))))
    (emacsvox-aural-scheme-rules
     (emacsvox-aural-feature-fragment-entry-compiled entry))))

(defun emacsvox-aural-feature-fragments--automatic-fragment-example (fragment rule)
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
      (emacsvox-aural-humanize rule-id))
     :facts facts
     :context context
     :source 'automatic)))

(defun emacsvox-aural-feature-fragments--fragment-preview-examples (fragment)
  "Return curated and automatically completed examples for FRAGMENT."
  (let* ((curated
          (emacsvox-aural-feature-fragment-examples fragment))
         (covered
          (mapcar
           #'emacsvox-aural-feature-fragment-example-rule curated)))
    (append
     curated
     (cl-loop
      for rule in (emacsvox-aural-feature-fragments--fragment-rules fragment)
      when
      (and
       (emacsvox-aural-rule-enabled rule)
       (not (memq (emacsvox-aural-rule-id rule) covered)))
      collect
      (emacsvox-aural-feature-fragments--automatic-fragment-example fragment rule)))))


(defvar-local emacsvox-aural-feature-fragments-view 'grouped
  "Current presentation-option manager view.")

(defvar-local emacsvox-aural-feature-fragments-collapsed-collections nil
  "Collections hidden in the current presentation-option manager.")

(defvar emacsvox-aural-feature-fragments--fragment-preview-last-examples
  (make-hash-table :test #'eq)
  "Most recently selected preview example for each presentation option.")

(defvar-local emacsvox-aural-feature-fragment-previews-fragment nil
  "Presentation option shown in the current preview buffer.")

(defvar-local emacsvox-aural-feature-fragment-previews-examples nil
  "Preview examples shown in the current preview buffer.")

(defvar-local emacsvox-aural-feature-fragment-previews-isolated nil
  "Whether the current preview buffer auditions its option in isolation.")

(defun emacsvox-aural-feature-fragments--fragment-collection-row-p (id)
  "Return non-nil when manager row ID represents a collection."
  (and (consp id) (eq (car id) 'collection) (symbolp (cdr id))))

(defun emacsvox-aural-feature-fragments--fragment-collection-row-id (collection)
  "Return manager row identifier for COLLECTION."
  (cons 'collection collection))

(defun emacsvox-aural-feature-fragments--fragment-at-point-or-read (&optional prompt)
  "Return the presentation option at point, or read one using PROMPT."
  (let ((id
         (and
          (derived-mode-p 'emacsvox-aural-feature-fragments-mode)
          (tabulated-list-get-id))))
    (cond
     ((and (symbolp id) (emacsvox-aural-feature-fragment-entry id))
      id)
     ((emacsvox-aural-feature-fragments--fragment-collection-row-p id)
      (user-error
       "%s is a collection; press TAB or RET to expand or collapse it"
       (emacsvox-aural-humanize (cdr id))))
     (t
      (let ((candidates (emacsvox-aural-feature-fragment-candidates)))
        (unless candidates
          (user-error "No presentation options are registered"))
        (intern
         (completing-read
          (or prompt "Aural presentation option: ")
          candidates nil 'must-match)))))))

(defun emacsvox-aural-feature-fragments--ordered-feature-fragment-ids ()
  "Return registered presentation options in stable order."
  (emacsvox-aural-normalized-feature-fragment-order))

(defun emacsvox-aural-feature-fragments--fragment-collections ()
  "Return presentation-option collections and their stably ordered entries."
  (let (collections)
    (dolist (id (emacsvox-aural-feature-fragments--ordered-feature-fragment-ids))
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

(defun emacsvox-aural-feature-fragments--fragment-kind (entry)
  "Return a user-facing kind name for feature fragment ENTRY."
  (if (emacsvox-aural-feature-fragment-entry-built-in entry)
      "built-in"
    "personal"))

(defun emacsvox-aural-feature-fragments--fragment-row (id)
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
          (format "  %s" (emacsvox-aural-humanize id))
        (emacsvox-aural-humanize id))
      (if position (format "enabled %d" (1+ position)) "disabled")
      (emacsvox-aural-feature-fragments--fragment-kind entry)
      (format
       "%d"
       (length (emacsvox-aural-scheme-rules compiled)))
      (if (emacsvox-aural-validation-report-valid report)
          "valid"
        "invalid")
      (emacsvox-aural-scheme-summary compiled)))))

(defun emacsvox-aural-feature-fragments--fragment-collection-row (collection ids)
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
     (emacsvox-aural-feature-fragments--fragment-collection-row-id collection)
     (vector
      (capitalize (emacsvox-aural-humanize collection))
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
        #'emacsvox-aural-feature-fragments--fragment-row
        emacsvox-aural-enabled-feature-fragments)
     (cl-mapcan
      (lambda (collection)
        (let ((id (car collection))
              (fragments (cdr collection)))
          (cons
           (emacsvox-aural-feature-fragments--fragment-collection-row id fragments)
           (unless
               (memq
                id
                emacsvox-aural-feature-fragments-collapsed-collections)
             (mapcar
              #'emacsvox-aural-feature-fragments--fragment-row fragments)))))
      (emacsvox-aural-feature-fragments--fragment-collections)))))

(defun emacsvox-aural-feature-fragments--goto (fragment)
  "Move to feature FRAGMENT in the current manager."
  (emacsvox-aural-ui-goto-row fragment))

(defun emacsvox-aural-feature-fragments-refresh (&optional fragment)
  "Refresh the feature-fragment manager, preserving FRAGMENT and column."
  (interactive)
  (emacsvox-aural-ui-refresh-tabulated
   #'emacsvox-aural-feature-fragments--set-entries fragment))

(defun emacsvox-aural-feature-fragments-refresh-if-live (&optional fragment)
  "Refresh an existing feature-fragment manager and select FRAGMENT."
  (when-let* ((buffer (get-buffer "*Aural Feature Fragments*")))
    (with-current-buffer buffer
      (when (derived-mode-p 'emacsvox-aural-feature-fragments-mode)
        (emacsvox-aural-feature-fragments-refresh fragment)))))

(defun emacsvox-aural-feature-fragments--fragment-spoken-summary (fragment)
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
     (emacsvox-aural-humanize fragment)
     (emacsvox-aural-feature-fragments--fragment-kind entry)
     (emacsvox-aural-humanize
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

(defun emacsvox-aural-feature-fragments--fragment-collection-spoken-summary
    (collection)
  "Return a concise spoken summary for manager COLLECTION."
  (let* ((ids (cdr (assq collection
                          (emacsvox-aural-feature-fragments--fragment-collections))))
         (enabled
          (cl-count-if
           #'emacsvox-aural-feature-fragment-enabled-p ids))
         (collapsed
          (memq
           collection
           emacsvox-aural-feature-fragments-collapsed-collections)))
    (format
     "%s collection. %d of %d options enabled. %s."
     (emacsvox-aural-humanize collection)
     enabled
     (length ids)
     (if collapsed "Collapsed" "Expanded"))))

(defun emacsvox-aural-feature-fragments-speak-current ()
  "Speak the presentation option or collection at point."
  (interactive)
  (let* ((id (tabulated-list-get-id))
         (summary
          (if (emacsvox-aural-feature-fragments--fragment-collection-row-p id)
              (emacsvox-aural-feature-fragments--fragment-collection-spoken-summary
               (cdr id))
            (emacsvox-aural-feature-fragments--fragment-spoken-summary
             (emacsvox-aural-feature-fragments--fragment-at-point-or-read)))))
    (if (fboundp 'tts-speak)
        (tts-speak summary)
      (message "%s" summary))
    summary))

(defun emacsvox-aural-feature-fragments-speak-current-cell ()
  "Speak the current feature-fragment column title and value."
  (interactive)
  (emacsvox-aural-ui-speak-current-cell))

(defun emacsvox-aural-feature-fragments-next ()
  "Move to and speak the next presentation-option row."
  (interactive)
  (emacsvox-aural-ui-move-row
   1 "presentation option list"))

(defun emacsvox-aural-feature-fragments-previous ()
  "Move to and speak the previous presentation-option row."
  (interactive)
  (emacsvox-aural-ui-move-row
   -1 "presentation option list"))

(defun emacsvox-aural-feature-fragments-next-column ()
  "Move right and speak the next feature-fragment column."
  (interactive)
  (emacsvox-aural-ui-move-column 1))

(defun emacsvox-aural-feature-fragments-previous-column ()
  "Move left and speak the previous feature-fragment column."
  (interactive)
  (emacsvox-aural-ui-move-column -1))

(defun emacsvox-aural-feature-fragments-toggle-collection ()
  "Expand or collapse the presentation-option collection at point."
  (interactive)
  (let ((id (tabulated-list-get-id)))
    (unless (emacsvox-aural-feature-fragments--fragment-collection-row-p id)
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
      (emacsvox-aural-feature-fragments--fragment-collection-row-p
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
           (emacsvox-aural-feature-fragments--fragment-at-point-or-read
            "View presentation option: ")))
         (entry
          (or
           (emacsvox-aural-feature-fragment-entry fragment)
           (user-error "Unknown feature fragment: %S" fragment)))
         (compiled
          (emacsvox-aural-feature-fragment-entry-compiled entry))
         (report (emacsvox-aural-validate-feature-fragment fragment))
         (summary
          (emacsvox-aural-feature-fragments--fragment-spoken-summary fragment)))
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
        (emacsvox-aural-feature-fragments--fragment-kind entry)))
      (princ
       (format
         "Collection: %s\n"
         (emacsvox-aural-humanize
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
      (emacsvox-aural-print-rules
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

(defun emacsvox-aural-feature-fragments--fragment-matching-rules
    (fragment facts context)
  "Return FRAGMENT rules matching FACTS and CONTEXT."
  (condition-case nil
      (let ((input (emacsvox-aural-normalize-input facts context)))
        (cl-remove-if-not
         (lambda (rule)
           (emacsvox-aural-rule-matches-p rule input))
         (emacsvox-aural-feature-fragments--fragment-rules fragment)))
    (emacsvox-aural-rule-error nil)))

(defun emacsvox-aural-feature-fragments--fragment-live-preview-input (fragment)
  "Return a live source preview input for FRAGMENT, or nil.

The source facts and mode remain real.  When necessary, choose the occasion
that lets the greatest number of fragment rules match those facts."
  (let ((source
         (if (emacsvox-aural-ui-interface-buffer-p)
             (emacsvox-aural-inspection-source-buffer)
           (emacsvox-aural-inspection-last-source-buffer))))
    (when source
      (with-current-buffer source
        (when-let* ((facts (emacsvox-aural-facts-at-point)))
          (let* ((rules (emacsvox-aural-feature-fragments--fragment-rules fragment))
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
                       (emacsvox-aural-feature-fragments--fragment-matching-rules
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

(defun emacsvox-aural-feature-fragments--fragment-preview-example
    (fragment &optional example-id prompt)
  "Return one simulated example for FRAGMENT.

EXAMPLE-ID selects a particular example.  When PROMPT is non-nil, ask when
more than one example is available."
  (let ((examples
         (emacsvox-aural-feature-fragments--fragment-preview-examples fragment)))
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

(defun emacsvox-aural-feature-fragments--fragment-preview-enabled-order (fragment)
  "Return enabled option order with FRAGMENT included at stable precedence."
  (let ((members
         (cons
          fragment
          (copy-sequence emacsvox-aural-enabled-feature-fragments))))
    (cl-remove-if-not
     (lambda (id) (memq id members))
     (emacsvox-aural-normalized-feature-fragment-order))))

(defun emacsvox-aural-feature-fragments--resolve-fragment-preview
    (fragment facts context isolated)
  "Resolve FRAGMENT for FACTS and CONTEXT.

When ISOLATED is non-nil, resolve only the option's rules.  Otherwise combine
it with the active configuration without changing persistent state."
  (if isolated
      (emacsvox-aural-resolve
       facts context
       (emacsvox-aural-feature-fragments--fragment-rules fragment))
    (let
        ((emacsvox-aural-enabled-feature-fragments
          (emacsvox-aural-feature-fragments--fragment-preview-enabled-order fragment))
         (emacsvox-aural--current-rules-cache
          (make-hash-table :test #'equal)))
      (emacsvox-aural-resolve-active facts context))))

(defun emacsvox-aural-feature-fragments--compile-fragment-preview
    (fragment facts context isolated)
  "Compile a concrete preview of FRAGMENT for FACTS and CONTEXT.

ISOLATED has the meaning documented by
`emacsvox-aural-feature-fragments--resolve-fragment-preview'."
  (let* ((facts
          (if (plist-member facts :content)
              (copy-tree facts)
            (plist-put (copy-tree facts) :content "Example")))
         (render
          (emacsvox-aural-feature-fragments--resolve-fragment-preview
           fragment facts context isolated)))
    (emacsvox-aural-compile-plan render facts context)))

(defun emacsvox-aural-feature-fragments--play-fragment-preview
    (fragment facts context isolated)
  "Compile and play FRAGMENT for FACTS and CONTEXT.

When ISOLATED is non-nil, play only the option's rules.  Otherwise combine
it with the active configuration without changing persistent state."
  (let ((concrete
         (emacsvox-aural-feature-fragments--compile-fragment-preview
          fragment facts context isolated)))
    (emacsvox-aural-preview-play-plan concrete)))

(defun emacsvox-aural-feature-fragments--fragment-preview-example-input (example)
  "Return copied facts and context from preview EXAMPLE."
  (list
   (copy-tree
    (emacsvox-aural-feature-fragment-example-facts example))
   (copy-tree
    (emacsvox-aural-feature-fragment-example-context example))))

(defun emacsvox-aural-feature-fragments--audition-fragment-preview-cues
    (fragment example isolated)
  "Audition only the concrete cues for FRAGMENT EXAMPLE.

ISOLATED controls whether compilation includes the active configuration.
No speech actions, content, presentation history, or training explanations
are submitted, so speech cannot mask the auditioned cues."
  (pcase-let*
      ((`(,facts ,context)
        (emacsvox-aural-feature-fragments--fragment-preview-example-input example))
       (concrete
        (emacsvox-aural-feature-fragments--compile-fragment-preview
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
     emacsvox-aural-feature-fragments--fragment-preview-last-examples)
    (emacsvox-aural-preview-message
     "Auditioning %s"
     (mapconcat
      (lambda (cue)
        (emacsvox-aural-humanize
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
           (emacsvox-aural-feature-fragments--fragment-at-point-or-read
            "Preview presentation option: ")))
         (live
          (unless example-id
            (emacsvox-aural-feature-fragments--fragment-live-preview-input fragment)))
         (examples
          (unless live
            (emacsvox-aural-feature-fragments--fragment-preview-examples fragment)))
         (example
          (unless (or live
                      (and
                       interactivep
                       (null example-id)
                       (> (length examples) 1)))
            (emacsvox-aural-feature-fragments--fragment-preview-example
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
               (emacsvox-aural-humanize
                (or (plist-get context :occasion) 'continuous)))))
        (emacsvox-aural-preview-message "%s" announcement)
        (when example
          (puthash
           fragment
           (emacsvox-aural-feature-fragment-example-id example)
           emacsvox-aural-feature-fragments--fragment-preview-last-examples))
        (list
         :kind kind
         :fragment fragment
         :example
         (and example
              (emacsvox-aural-feature-fragment-example-id example))
         :announcement announcement
         :concrete
         (emacsvox-aural-feature-fragments--play-fragment-preview
          fragment facts context isolated))))))

(defun emacsvox-aural-feature-fragments--fragment-preview-action-description (action)
  "Return a short user-facing description of render ACTION."
  (pcase (emacsvox-aural-action-kind action)
    ('cue
     (format
      "%s earcon"
      (emacsvox-aural-humanize
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
     (emacsvox-aural-humanize
      (emacsvox-aural-action-kind action)))))

(defun emacsvox-aural-feature-fragments--fragment-preview-output-summary
    (fragment example isolated)
  "Describe the output of FRAGMENT EXAMPLE under ISOLATED resolution."
  (pcase-let*
      ((`(,facts ,context)
        (emacsvox-aural-feature-fragments--fragment-preview-example-input example))
       (facts
        (if (plist-member facts :content)
            facts
          (plist-put facts :content "Example")))
       (render
        (emacsvox-aural-feature-fragments--resolve-fragment-preview
         fragment facts context isolated))
       (actions
        (append
         (emacsvox-aural-render-plan-before render)
         (emacsvox-aural-render-plan-after render)))
       (content (emacsvox-aural-render-plan-content render))
       (voice (emacsvox-aural-content-style-voice content))
       (parts
        (mapcar
         #'emacsvox-aural-feature-fragments--fragment-preview-action-description
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
              (emacsvox-aural-humanize voice)
            voice))))))
    (when (not (emacsvox-aural-content-style-speak content))
      (setq parts (append parts (list "content muted"))))
    (if parts
        (string-join parts ", ")
      "content only")))

(defun emacsvox-aural-feature-fragments--fragment-preview-context-summary (example)
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
     (emacsvox-aural-humanize scope)
     (emacsvox-aural-humanize occasion))))

(defun emacsvox-aural-feature-fragments--fragment-preview-example-kind (example)
  "Return the user-facing provenance kind of preview EXAMPLE."
  (if
      (eq
       (emacsvox-aural-feature-fragment-example-source example)
       'automatic)
      "automatic"
    "curated"))

(defun emacsvox-aural-feature-fragments--fragment-preview-row (example)
  "Return one tabulated preview row for EXAMPLE."
  (list
   (emacsvox-aural-feature-fragment-example-id example)
   (vector
    (emacsvox-aural-feature-fragment-example-summary example)
    (emacsvox-aural-feature-fragments--fragment-preview-example-kind example)
    (emacsvox-aural-humanize
     (emacsvox-aural-feature-fragment-example-rule example))
    (emacsvox-aural-feature-fragments--fragment-preview-context-summary example)
    (emacsvox-aural-feature-fragments--fragment-preview-output-summary
     emacsvox-aural-feature-fragment-previews-fragment
     example
     emacsvox-aural-feature-fragment-previews-isolated))))

(defun emacsvox-aural-feature-fragment-previews--set-entries ()
  "Populate the current presentation-option preview buffer."
  (setq
   tabulated-list-entries
   (mapcar
    #'emacsvox-aural-feature-fragments--fragment-preview-row
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
     emacsvox-aural-feature-fragments--fragment-preview-last-examples)
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
     emacsvox-aural-feature-fragments--fragment-preview-last-examples))
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
           (emacsvox-aural-feature-fragments--fragment-preview-example-kind example)
           (emacsvox-aural-humanize
            (emacsvox-aural-feature-fragment-example-rule example))
           (emacsvox-aural-feature-fragments--fragment-preview-context-summary example)
           (emacsvox-aural-feature-fragments--fragment-preview-output-summary
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
  (emacsvox-aural-ui-speak-current-cell))

(defun emacsvox-aural-feature-fragment-previews-next ()
  "Move to and speak the next preview example."
  (interactive)
  (emacsvox-aural-ui-move-row 1 "preview example list")
  (emacsvox-aural-feature-fragment-previews--remember-current))

(defun emacsvox-aural-feature-fragment-previews-previous ()
  "Move to and speak the previous preview example."
  (interactive)
  (emacsvox-aural-ui-move-row -1 "preview example list")
  (emacsvox-aural-feature-fragment-previews--remember-current))

(defun emacsvox-aural-feature-fragment-previews-next-column ()
  "Move right and speak the next preview column."
  (interactive)
  (emacsvox-aural-ui-move-column 1))

(defun emacsvox-aural-feature-fragment-previews-previous-column ()
  "Move left and speak the previous preview column."
  (interactive)
  (emacsvox-aural-ui-move-column -1))

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
  (emacsvox-aural-feature-fragments--audition-fragment-preview-cues
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
           (emacsvox-aural-feature-fragments--fragment-preview-examples fragment)))
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

(defun emacsvox-aural-feature-fragments-install-state
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
    (emacsvox-aural-feature-fragments-install-state
     registry emacsvox-aural-enabled-feature-fragments)
    (emacsvox-aural-feature-fragments-refresh-if-live id)
    (when (called-interactively-p 'interactive)
      (require 'emacsvox-aural-editor)
      (emacsvox-edit-aural-feature-fragment id))
    id))

(defun emacsvox-aural-copy-feature-fragment (source new-id)
  "Copy feature fragment SOURCE to disabled personal fragment NEW-ID."
  (interactive
   (let* ((source
          (emacsvox-aural-feature-fragments--fragment-at-point-or-read
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
    (emacsvox-aural-feature-fragments-install-state
     registry emacsvox-aural-enabled-feature-fragments)
    (emacsvox-aural-feature-fragments-refresh-if-live new-id)
    (message "Created personal presentation option %s" new-id)
    new-id))

(defun emacsvox-aural-delete-feature-fragment (&optional fragment)
  "Delete personal feature FRAGMENT, disabling it when necessary."
  (interactive)
  (let* ((fragment
          (or
           fragment
           (emacsvox-aural-feature-fragments--fragment-at-point-or-read
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
        (emacsvox-aural-feature-fragments-install-state
         registry enabled))
      (emacsvox-aural-feature-fragments-refresh-if-live)
      (message "Deleted personal presentation option %s" fragment)
      fragment)))

(defun emacsvox-aural-feature-fragments-toggle (&optional fragment)
  "Enable or disable feature FRAGMENT without changing its stable order."
  (interactive)
  (let* ((fragment
          (or
           fragment
           (emacsvox-aural-feature-fragments--fragment-at-point-or-read)))
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
    (emacsvox-aural-feature-fragments-install-state
     (copy-hash-table emacsvox-aural-feature-fragment-registry)
     enabled)
    (emacsvox-aural-feature-fragments-refresh-if-live fragment)
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
          (emacsvox-aural-feature-fragments--fragment-at-point-or-read))
         (index
          (cl-position fragment emacsvox-aural-enabled-feature-fragments)))
    (unless index
      (user-error "Enable %s before ordering it" fragment))
    (let ((destination (+ index offset)))
      (if (not
           (< -1 destination
              (length emacsvox-aural-enabled-feature-fragments)))
          (emacsvox-aural-ui-announce-boundary
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
          (emacsvox-aural-feature-fragments-install-state
           (copy-hash-table
            emacsvox-aural-feature-fragment-registry)
           enabled order)
          (emacsvox-aural-feature-fragments-refresh-if-live fragment)
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
          (emacsvox-aural-feature-fragments--fragment-at-point-or-read))
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
           (emacsvox-aural-feature-fragments--fragment-at-point-or-read)))
         (report
          (emacsvox-aural-validate-feature-fragment fragment)))
    (when (called-interactively-p 'interactive)
      (emacsvox-aural-display-validation
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

;;;###autoload
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

(defalias 'emacsvox-aural-tools--install-feature-fragment-state
  #'emacsvox-aural-feature-fragments-install-state)
(defalias 'emacsvox-aural-tools--refresh-fragment-manager
  #'emacsvox-aural-feature-fragments-refresh-if-live)

(provide 'emacsvox-aural-feature-fragments)
;;; emacsvox-aural-feature-fragments.el ends here
