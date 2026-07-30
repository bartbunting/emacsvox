;;; emacsvox-org-tests.el --- Org advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Org advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-aural-explanation)
(require 'emacsvox-advice)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-org.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

;; Verify that direct advice survives definition of lazily loaded Org commands.
(require 'org-goto)
(require 'org-agenda)
(require 'org-archive)
(require 'org-capture)
(require 'org-src)
(require 'ox)
(require 'ox-md)

(define-derived-mode emacsvox-test-org-derived-mode org-mode
  "Emacsvox-Test-Org"
  "Derived Org mode used to verify aural mode ancestry.")

(defun emacsvox-test--org-context (&optional occasion)
  "Return captured Org context for OCCASION."
  (emacsvox-aural-capture-context
   'org (or occasion 'navigation)))

(defun emacsvox-test--activate-org-mode (mode)
  "Activate Org-derived MODE without unrelated full-startup setup."
  (let ((org-mode-hook
         (remove
          #'emacsvox-org-mode-setup
          (copy-sequence org-mode-hook))))
    (funcall mode)))

(defmacro emacsvox-test--capture-org-submissions (&rest body)
  "Evaluate BODY and return native Org text submissions in call order."
  (declare (indent 0) (debug t))
  `(let (captured)
     (cl-letf
         (((symbol-function 'emacsvox-aural-submit)
           (lambda (content &rest arguments)
             (push (cons content arguments) captured))))
       ,@body)
     (nreverse captured)))

(defun emacsvox-test--org-resolved-voice
    (mode user-rules &optional buffer-rules)
  "Resolve a heading voice in MODE with USER-RULES and BUFFER-RULES."
  (let ((emacsvox-aural-active-scheme 'default)
        (emacsvox-aural-user-rules user-rules)
        (emacsvox-aural-session-rules nil))
    (with-temp-buffer
      (emacsvox-test--activate-org-mode mode)
      (insert "* Heading\n")
      (goto-char (point-min))
      (setq emacsvox-aural-buffer-rules buffer-rules)
      (emacsvox-aural-content-style-voice
       (emacsvox-aural-render-plan-content
        (emacsvox-aural-resolve-active
         (emacsvox-org-heading-facts)
         (emacsvox-test--org-context)))))))

(defconst emacsvox-test--org-structure-after-targets
  '(org-next-item org-previous-item
    org-mark-ring-goto org-mark-ring-push
    org-next-visible-heading org-previous-visible-heading
    org-forward-heading-same-level org-backward-heading-same-level
    org-backward-sentence org-forward-sentence
    org-backward-element org-forward-element
    org-next-link org-previous-link
    org-goto org-goto-ret org-goto-left org-goto-right org-goto-quit
    org-metaleft org-metaright org-metaup org-metadown org-meta-return
    org-shiftmetaleft org-shiftmetaright org-shiftmetaup org-shiftmetadown
    org-mark-element org-mark-subtree
    org-backward-paragraph org-forward-paragraph
    org-agenda-forward-block org-agenda-backward-block
    org-cycle-list-bullet org-cycle org-shifttab
    org-overview org-content org-tree-to-indirect-buffer)
  "Native after-advice targets in the Org structure and folding slice.")

(defconst emacsvox-test--org-agenda-table-after-targets
  '(org-timestamp-down-day org-timestamp-up-day
    org-timestamp-down org-timestamp-up
    org-eval-in-calendar
    org-agenda-next-date-line org-agenda-previous-date-line
    org-agenda-next-line org-agenda-previous-line
    org-agenda-next-item org-agenda-previous-item org-agenda-goto-today
    org-agenda-quit org-agenda-exit
    org-agenda-goto org-agenda-show org-agenda-switch-to
    org-agenda-open-link org-agenda
    orgtbl-mode org-return
    org-table-next-field org-table-previous-field
    org-table-next-row org-table-previous-row)
  "Native after-advice targets in the Org agenda and table slice.")

(defconst emacsvox-test--org-editing-after-targets
  '(org-delete-indentation
    org-insert-heading org-insert-todo-heading org-insert-structure-template
    org-promote-subtree org-demote-subtree org-do-promote org-do-demote
    org-move-subtree-up org-move-subtree-down
    org-convert-to-odd-levels org-convert-to-oddeven-levels
    org-cut-subtree org-copy-subtree org-paste-subtree
    org-archive-subtree org-narrow-to-subtree
    org-toggle-archive-tag org-toggle-comment
    end-of-line org-toggle-checkbox
    org-occur org-beginning-of-item org-beginning-of-item-list
    org-end-of-item org-end-of-item-list
    org-beginning-of-line org-end-of-line
    org-edit-src-exit org-edit-src-abort
    org-edit-src-code org-edit-special org-switchb
    org-fill-paragraph org-todo)
  "Native after-advice targets in the Org editing slice.")

(defconst emacsvox-test--org-capture-after-targets
  '(org-capture-goto-last-stored org-capture-goto-target
    org-capture-finalize org-capture-kill org-md-export-as-markdown)
  "Native after-advice targets in the Org capture slice.")

(defconst emacsvox-test--org-document-state-around-targets
  '(org-priority org-set-tags-command org-schedule org-deadline
    org-set-effort org-inc-effort org-set-property
    org-set-property-and-value org-toggle-ordered-property
    org-update-statistics-cookies org-toggle-radio-button
    org-toggle-fixed-width org-toggle-pretty-entities
    org-toggle-timestamp-overlays org-ctrl-c-ctrl-c)
  "Quiet native around-advice targets for Org document state changes.")

(defconst emacsvox-test--org-agenda-line-around-targets
  '(org-agenda-todo org-agenda-todo-nextset org-agenda-todo-previousset
    org-agenda-priority org-agenda-priority-up org-agenda-priority-down
    org-agenda-do-date-earlier org-agenda-do-date-later
    org-agenda-schedule org-agenda-deadline
    org-agenda-set-tags org-agenda-set-effort org-agenda-set-property
    org-agenda-toggle-archive-tag
    org-agenda-drag-line-forward org-agenda-drag-line-backward
    org-agenda-clock-in org-agenda-clock-out org-agenda-clock-cancel
    org-agenda-bulk-mark org-agenda-bulk-mark-all
    org-agenda-bulk-mark-regexp org-agenda-bulk-unmark
    org-agenda-bulk-unmark-all org-agenda-bulk-toggle
    org-agenda-bulk-toggle-all org-agenda-bulk-action)
  "Agenda commands whose native result is the resulting entry line.")

(defconst emacsvox-test--org-agenda-message-around-targets
  '(org-agenda-archive org-agenda-archive-default-with-confirmation
    org-agenda-archive-default org-agenda-archive-to-archive-sibling
    org-agenda-kill org-agenda-refile
    org-agenda-filter org-agenda-filter-by-category
    org-agenda-filter-by-effort org-agenda-filter-by-regexp
    org-agenda-filter-by-tag org-agenda-filter-by-top-headline
    org-agenda-filter-remove-all org-agenda-limit-interactively
    org-agenda-manipulate-query-add org-agenda-manipulate-query-add-re
    org-agenda-manipulate-query-subtract
    org-agenda-manipulate-query-subtract-re
    org-agenda-earlier org-agenda-later org-agenda-goto-date
    org-agenda-date-prompt org-agenda-day-view org-agenda-week-view
    org-agenda-year-view org-agenda-view-mode-dispatch
    org-agenda-toggle-deadlines org-agenda-toggle-diary
    org-agenda-toggle-time-grid org-agenda-dim-blocked-tasks
    org-agenda-entry-text-mode org-agenda-follow-mode
    org-agenda-log-mode org-agenda-clockreport-mode
    org-agenda-append-agenda org-agenda-redo org-agenda-redo-all)
  "Agenda commands whose native result prefers Org's final message.")

(defconst emacsvox-test--org-table-change-around-targets
  '(org-table-delete-column org-table-move-column-left
    org-table-move-column-right org-table-insert-column
    org-table-kill-row org-table-insert-row
    org-table-move-row-up org-table-move-row-down
    org-table-paste-rectangle org-table-wrap-region
    org-table-insert-hline org-table-copy-down org-table-blank-field
    org-table-eval-formula org-table-recalculate org-table-sort-lines
    org-table-rotate-recalc-marks
    org-table-create-or-convert-from-region)
  "Org table commands whose native result is the resulting cell.")

(defconst emacsvox-test--org-table-message-around-targets
  '(org-table-sum org-table-field-info
    org-table-toggle-coordinate-overlays
    org-table-toggle-formula-debugger)
  "Org table commands whose native result prefers Org's message.")

(defconst emacsvox-test--org-table-editor-around-targets
  '(org-table-edit-formulas org-table-edit-field
    org-table-fedit-finish org-table-fedit-abort
    org-table-fedit-ref-up org-table-fedit-ref-down
    org-table-fedit-ref-left org-table-fedit-ref-right
    org-table-fedit-line-up org-table-fedit-line-down
    org-table-fedit-toggle-ref-type
    org-table-fedit-toggle-coordinates org-table-show-reference)
  "Org table editor commands with native lifecycle and editing feedback.")

(defconst emacsvox-test--org-babel-around-targets
  '(org-babel-execute-src-block org-babel-execute-maybe
    org-babel-execute-buffer org-babel-execute-subtree
    org-babel-next-src-block org-babel-previous-src-block
    org-babel-goto-named-src-block org-babel-goto-src-block-head
    org-babel-goto-named-result org-babel-open-src-block-result
    org-babel-load-in-session org-babel-switch-to-session
    org-babel-switch-to-session-with-code
    org-babel-do-key-sequence-in-edit-buffer
    org-babel-tangle org-babel-tangle-file
    org-babel-remove-result-one-or-many org-babel-demarcate-block
    org-babel-insert-header-arg org-babel-mark-block
    org-babel-view-src-block-info org-babel-expand-src-block
    org-babel-check-src-block org-babel-sha1-hash)
  "Org Babel commands with native result and lifecycle feedback.")

(ert-deftest emacsvox-org-structure-advice-is-directly-registered ()
  "Org structure advice uses native advice directly."
  (dolist (target emacsvox-test--org-structure-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-org-item-feedback-is-target-aware ()
  "Only the matching Org item movement submits the item."
  (let ((ems--interactive-fn-name 'org-previous-item)
        events)
    (cl-letf (((symbol-function 'emacsvox-org-speak-item)
               (lambda () (push 'speak-item events))))
      (emacsvox--advice-org-next-item-after)
      (emacsvox--advice-org-previous-item-after))
    (should (equal events '(speak-item)))))

(ert-deftest emacsvox-org-item-feedback-captures-semantic-boundary ()
  "Item movement submits source, stable intent, and its cue atomically."
  (with-temp-buffer
    (emacsvox-test--activate-org-mode #'org-mode)
    (insert "- first\n- second\n")
    (goto-char (point-min))
    (let ((ems--interactive-fn-name 'org-next-item)
          submission)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (setq submission (cons content arguments)))))
        (emacsvox--advice-org-next-item-after))
      (should (equal (substring-no-properties (car submission))
                     "- first\n"))
      (should
       (equal
        (plist-get (cdr submission) :facts)
        '(:role org-item :events (focus-entered)
          :org-action item-navigation)))
      (should (eq (plist-get (cdr submission) :module) 'org))
      (should
       (eq (plist-get (cdr submission) :occasion) 'navigation))
      (let ((action
             (car
              (plist-get
               (cdr submission) :compatibility-actions))))
        (should
         (eq
          (emacsvox-aural-compatibility-action-value action)
          'item))))))

(ert-deftest emacsvox-org-list-style-feedback-is-one-native-submission ()
  "Cycling a list bullet submits the changed line and cue together."
  (with-temp-buffer
    (emacsvox-test--activate-org-mode #'org-mode)
    (insert "- item\n")
    (goto-char (point-min))
    (let ((ems--interactive-fn-name 'org-cycle-list-bullet)
          submission)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (setq submission (cons content arguments)))))
        (emacsvox--advice-org-cycle-list-bullet-after))
      (should (equal (substring-no-properties (car submission)) "- item"))
      (should
       (equal
        (plist-get (cdr submission) :facts)
        '(:role org-item :events (state-changed)
          :org-action list-style-changed)))
      (should
       (eq
        (emacsvox-aural-compatibility-action-value
         (car
          (plist-get
           (cdr submission) :compatibility-actions)))
        'item)))))

(ert-deftest emacsvox-org-owned-semantics-are-registered ()
  "Org roles and operation intent are part of the inspectable contract."
  (dolist
      (semantic
       '(org-content org-item org-paragraph org-agenda-entry org-table
                     org-capture org-edit-buffer org-export
                     org-source-block org-babel-result org-action
                     org-table-row org-table-column
                     org-table-presentation))
    (should (emacsvox-aural-semantic semantic)))
  (should
   (eq
    (emacsvox-aural-semantic-kind
    (emacsvox-aural-semantic 'org-action))
    'attribute)))

(ert-deftest emacsvox-org-face-presentation-covers-current-org ()
  "Every face provided by the current Org interface has one voice mapping."
  (dolist
      (feature
       '(org-agenda org-clock org-colview org-habit org-indent
                    org-inlinetask org-src org-table ox-beamer))
    (require feature))
  (let* ((mapped (mapcar #'car emacsvox-org--face-voice-map))
         (current
          (seq-filter
           (lambda (face)
             (string-prefix-p "org-" (symbol-name face)))
           (face-list))))
    (should (= (length mapped) (length (delete-dups (copy-sequence mapped)))))
    (should-not (assq 'org-coverlay emacsvox-org--face-voice-map))
    (dolist (face current)
      (should (assq face emacsvox-org--face-voice-map)))))

(ert-deftest emacsvox-org-action-allows-specific-cue-overrides ()
  "A user rule can alter one Org operation without changing other modules."
  (let ((emacsvox-aural-active-scheme 'default)
        (emacsvox-aural-user-rules
         '((:id suppress-org-item-navigation
            :match
            (:role org-item :module org :org-action item-navigation)
            :render (:before (:remove (legacy-cue))))))
        (emacsvox-aural-session-rules nil)
        (emacsvox-aural-buffer-rules nil))
    (should-not
     (emacsvox-aural-render-plan-before
      (emacsvox-aural-resolve-legacy-icon
       'item
       (emacsvox-test--org-context)
       (emacsvox-org--feedback-facts
        'org-item 'focus-entered 'item-navigation))))))

(ert-deftest emacsvox-org-structure-feedback-uses-one-native-submission ()
  "Org structure movement submits its source line and semantic intent once."
  (with-temp-buffer
    (emacsvox-test--activate-org-mode #'org-mode)
    (insert "* Heading\n")
    (goto-char (point-min))
    (let ((ems--interactive-fn-name 'org-next-visible-heading)
          submissions)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (push (cons content arguments) submissions))))
        (emacsvox--advice-org-next-visible-heading-after))
      (should (= (length submissions) 1))
      (let ((submission (car submissions)))
        (should (equal (substring-no-properties (car submission))
                       "* Heading"))
        (should
         (equal
          (plist-get (cdr submission) :facts)
          '(:role heading :level 1 :visibility expanded
            :events (focus-entered)
            :org-action structure-navigation)))
        (should (eq (plist-get (cdr submission) :module) 'org))
        (should
         (eq (plist-get (cdr submission) :occasion) 'navigation))))))

(ert-deftest emacsvox-org-headings-carry-live-semantic-facts ()
  "Fontified Org headings expose level and refreshed folded-state facts."
  (with-temp-buffer
    (emacsvox-test--activate-org-mode #'org-mode)
    (insert "* Parent\nBody\n** Child\n")
    (goto-char (point-min))
    (font-lock-ensure)
    (should (eq emacsvox-aural-module 'org))
    (should
     (equal
      (get-text-property
       (point) emacsvox-aural-facts-property)
      '(:role heading :level 1 :visibility expanded)))
    (org-fold-hide-subtree)
    (emacsvox-org-refresh-aural-heading)
    (should
     (equal
      (get-text-property
       (point) emacsvox-aural-facts-property)
      '(:role heading :level 1 :visibility folded
        :states (folded))))))

(ert-deftest emacsvox-org-navigation-captures-event-and-context ()
  "Heading navigation submits one semantic speech operation."
  (with-temp-buffer
    (emacsvox-test--activate-org-mode #'org-mode)
    (insert "** Heading\n")
    (goto-char (point-min))
    (let ((ems--interactive-fn-name 'org-next-visible-heading)
          submission)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (setq submission (cons content arguments)))))
        (emacsvox--advice-org-next-visible-heading-after))
      (should
       (equal
        (plist-get (cdr submission) :facts)
        '(:role heading :level 2 :visibility expanded
          :events (focus-entered)
          :org-action structure-navigation)))
      (should (eq (plist-get (cdr submission) :module) 'org))
      (should
       (eq (plist-get (cdr submission) :occasion) 'navigation)))))

(ert-deftest emacsvox-org-default-plan-preserves-navigation-output-order ()
  "Default semantic heading output remains line then movement cue."
  (let ((emacsvox-aural-active-scheme 'default)
        (emacsvox-aural-user-rules nil)
        (emacsvox-aural-session-rules nil)
        (emacsvox-aural-buffer-rules nil))
    (with-temp-buffer
      (emacsvox-test--activate-org-mode #'org-mode)
      (insert "* Heading\n")
      (goto-char (point-min))
      (let* ((facts
              (emacsvox-org-heading-facts 'focus-entered))
             (plan
              (emacsvox-aural-resolve-active
               facts (emacsvox-test--org-context))))
        (should
         (emacsvox-aural-content-style-speak
          (emacsvox-aural-render-plan-content plan)))
        (should-not (emacsvox-aural-render-plan-before plan))
        (should
         (equal
          (mapcar
           (lambda (action)
             (list
              (emacsvox-aural-action-kind action)
              (emacsvox-aural-action-cue action)))
           (emacsvox-aural-render-plan-after plan))
          '((cue large-movement))))))))

(ert-deftest emacsvox-org-explanation-infers-navigation-and-speaks-plan ()
  "Org point help explains the scheme occasion and multimodal order."
  (let ((emacsvox-aural-active-scheme 'org-combined)
        (emacsvox-aural-user-rules nil)
        (emacsvox-aural-session-rules nil)
        (emacsvox-aural-buffer-rules nil))
    (with-temp-buffer
      (emacsvox-test--activate-org-mode #'org-mode)
      (insert "* Heading\n")
      (goto-char (point-min))
      (emacsvox-org-refresh-aural-heading)
      (pcase-let*
          ((`(,facts ,context)
            (emacsvox-aural-explanation--read-explanation-input nil))
           (explanation (emacsvox-aural-explain facts context))
           (matches
            (mapcar
             (lambda (entry) (plist-get entry :id))
             (emacsvox-aural-explanation-matching-rules explanation)))
           (summary
            (emacsvox-aural-explanation--spoken-explanation explanation)))
        (should (eq (plist-get context :occasion) 'navigation))
        (should
         (equal
          matches
          '(org-heading-navigation-compatibility org-combined-heading)))
        (should
         (string-match-p
          "Scheme org combined" summary))
        (should
         (string-match-p
          (concat
           "Before the content, say Heading once for the object, "
           "then play the section cue once for the object")
          summary))
        (should
         (string-match-p
          "content is spoken using the bolden voice"
          summary))))))

(ert-deftest emacsvox-org-example-schemes-cover-presentation-modalities ()
  "Selectable Org examples cover voice, labels, cues, phases, and state."
  (dolist
      (scheme
       '(org-voice-only org-spoken-label org-cue-only
         org-combined org-before-after org-folded-state))
    (let ((entry (emacsvox-aural-scheme-entry scheme)))
      (should entry)
      (should (emacsvox-aural-scheme-entry-built-in entry))))
  (let* ((facts
          '(:role heading :level 1 :states (folded)
            :events (focus-entered)))
         (context
          '(:module org :mode org-mode
            :mode-lineage (org-mode outline-mode)
            :occasion navigation))
         (emacsvox-aural-user-rules nil)
         (emacsvox-aural-session-rules nil)
         (emacsvox-aural-buffer-rules nil))
    (let* ((emacsvox-aural-active-scheme 'org-voice-only)
           (plan (emacsvox-aural-resolve-active facts context)))
      (should
       (eq
        (emacsvox-aural-content-style-voice
         (emacsvox-aural-render-plan-content plan))
        'bolden))
      (should-not (emacsvox-aural-render-plan-after plan)))
    (let* ((emacsvox-aural-active-scheme 'org-spoken-label)
           (plan (emacsvox-aural-resolve-active facts context)))
      (should
       (equal
        (mapcar #'emacsvox-aural-action-text
                (emacsvox-aural-render-plan-before plan))
        '("Heading 1"))))
    (let* ((emacsvox-aural-active-scheme 'org-cue-only)
           (plan (emacsvox-aural-resolve-active facts context)))
      (should
       (equal
        (mapcar #'emacsvox-aural-action-cue
                (emacsvox-aural-render-plan-before plan))
        '(section))))
    (let* ((emacsvox-aural-active-scheme 'org-combined)
           (plan (emacsvox-aural-resolve-active facts context)))
      (should
       (equal
        (mapcar #'emacsvox-aural-action-kind
                (emacsvox-aural-render-plan-before plan))
        '(speech cue)))
      (should
       (eq
        (emacsvox-aural-content-style-voice
         (emacsvox-aural-render-plan-content plan))
        'bolden)))
    (let* ((emacsvox-aural-active-scheme 'org-before-after)
           (plan (emacsvox-aural-resolve-active facts context)))
      (should
       (equal
        (mapcar #'emacsvox-aural-action-text
                (emacsvox-aural-render-plan-before plan))
        '("Heading")))
      (should
       (equal
        (mapcar #'emacsvox-aural-action-text
                (emacsvox-aural-render-plan-after plan))
        '("end heading"))))
    (let* ((emacsvox-aural-active-scheme 'org-folded-state)
           (plan (emacsvox-aural-resolve-active facts context)))
      (should
       (equal
        (mapcar #'emacsvox-aural-action-text
                (cl-remove-if-not
                 (lambda (action)
                   (eq (emacsvox-aural-action-kind action) 'speech))
                 (emacsvox-aural-render-plan-after plan)))
        '("folded"))))))

(ert-deftest emacsvox-org-feature-fragments-are-optional-built-ins ()
  "Org feature fragments are registered read-only and remain opt-in."
  (dolist
      (fragment
       '(org-heading-level-labels
         org-heading-section-cues
         org-heading-visibility-changes))
    (let ((entry (emacsvox-aural-feature-fragment-entry fragment)))
      (should entry)
      (should (emacsvox-aural-feature-fragment-entry-built-in entry))
      (should
       (eq
        (emacsvox-aural-feature-fragment-entry-collection entry)
        'org))
      (should
       (equal
        (emacsvox-aural-feature-fragment-entry-source entry)
        "emacsvox-aural-provider-org"))
      (should-not
       (emacsvox-aural-feature-fragment-enabled-p fragment))))
  (dolist
      (definition
       '((org-heading-level-labels org-level-three
          org-fragment-heading-level-label)
         (org-heading-visibility-changes org-level-two-folded
          org-fragment-heading-folded)))
    (let ((example
           (emacsvox-aural-feature-fragment-example
            (nth 0 definition) (nth 1 definition))))
      (should example)
      (should
       (eq
        (emacsvox-aural-feature-fragment-example-rule example)
        (nth 2 definition)))
      (should
       (equal
        (emacsvox-aural-feature-fragment-example-source example)
        "emacsvox-aural-provider-org")))))

(ert-deftest emacsvox-org-feature-fragments-compose-with-the-base-scheme ()
  "Optional Org features add to rather than replace inherited presentation."
  (let ((emacsvox-aural-active-scheme 'org-combined)
        (emacsvox-aural-enabled-feature-fragments
         '(org-heading-level-labels org-heading-section-cues))
        (emacsvox-aural-user-rules nil)
        (emacsvox-aural-session-rules nil)
        (emacsvox-aural-buffer-rules nil))
    (let* ((facts
            '(:role heading :level 3 :visibility expanded
              :events (focus-entered) :content "Title"))
           (context
            '(:module org :mode org-mode
              :mode-lineage (org-mode outline-mode)
              :occasion navigation))
           (plan (emacsvox-aural-resolve-active facts context))
           (explanation (emacsvox-aural-explain facts context))
           (level-rule
            (cl-find
             'org-fragment-heading-level-label
             (emacsvox-aural-explanation-matching-rules explanation)
             :key (lambda (entry) (plist-get entry :id))))
           (concrete (emacsvox-aural-compile-plan plan facts context)))
      (should
       (equal
        (mapcar
         #'emacsvox-aural-action-id
         (emacsvox-aural-render-plan-before plan))
        '(org-fragment-heading-level-label-action
          org-combined-label
          org-combined-cue
          org-fragment-heading-section-cue-action)))
      (should
       (eq
        (emacsvox-aural-content-style-voice
         (emacsvox-aural-render-plan-content plan))
        'bolden))
      (should
       (equal
        (emacsvox-aural-concrete-action-text
         (car (emacsvox-aural-concrete-plan-before concrete)))
        "Heading 3"))
      (should (eq (plist-get level-rule :origin) 'fragment))
      (should
       (equal
        (plist-get level-rule :source)
        "emacsvox-aural-provider-org")))))

(ert-deftest emacsvox-org-arrow-and-structural-navigation-present-alike ()
  "Down-arrow and Org structural navigation present one heading identically."
  (let ((emacsvox-aural-active-scheme 'default)
        (emacsvox-aural-enabled-feature-fragments
         '(org-heading-level-labels))
        (emacsvox-aural-user-rules nil)
        (emacsvox-aural-session-rules nil)
        (emacsvox-aural-buffer-rules nil))
    (with-temp-buffer
      (emacsvox-test--activate-org-mode #'org-mode)
      (insert "** Heading\n")
      (goto-char (point-min))
      (font-lock-ensure)
      (let ((ems--interactive-fn-name 'next-line)
            (line-move-visual nil)
            (visual-line-mode nil)
            plans)
        (cl-letf
            (((symbol-function 'tts-speak)
              (lambda (text)
                (let ((prepared
                       (if
                           (emacsvox-aural-concrete-plan-at 0 text)
                           text
                         (emacsvox-aural-prepare-text text))))
                  (push
                   (emacsvox-aural-concrete-plan-at 0 prepared)
                   plans)))))
          (emacsvox--advice-next-line-after)
          (emacsvox-org-speak-line-semantically
           'navigation 'focus-entered))
        (should (= (length plans) 2))
        (dolist (plan plans)
          (should
           (eq
            (plist-get
             (emacsvox-aural-concrete-plan-context plan)
             :occasion)
            'navigation))
          (should
           (equal
            (mapcar
             #'emacsvox-aural-concrete-action-text
             (emacsvox-aural-concrete-plan-before plan))
            '("Heading 2"))))
        (should
         (equal
          (mapcar
           #'emacsvox-aural-concrete-action-id
           (emacsvox-aural-concrete-plan-before (nth 0 plans)))
          (mapcar
           #'emacsvox-aural-concrete-action-id
           (emacsvox-aural-concrete-plan-before (nth 1 plans)))))
        (should
         (equal
          (mapcar
           #'emacsvox-aural-concrete-action-id
           (emacsvox-aural-concrete-plan-after (nth 0 plans)))
          (mapcar
           #'emacsvox-aural-concrete-action-id
          (emacsvox-aural-concrete-plan-after (nth 1 plans)))))))))

(ert-deftest emacsvox-org-mixed-face-heading-has-one-object-presentation ()
  "A fontified Org heading does not repeat semantic feedback per face run."
  (let ((emacsvox-aural-active-scheme 'default)
        (emacsvox-aural-enabled-feature-fragments
         '(org-heading-level-labels org-heading-section-cues))
        (emacsvox-aural-user-rules nil)
        (emacsvox-aural-session-rules nil)
        (emacsvox-aural-buffer-rules nil)
        (voice-lock-mode t))
    (with-temp-buffer
      (emacsvox-test--activate-org-mode #'org-mode)
      (insert "** TODO Mixed heading :tag:\n")
      (goto-char (point-min))
      (font-lock-ensure)
      (emacsvox-org-refresh-aural-heading)
      (let* ((text
              (buffer-substring
               (line-beginning-position) (line-end-position)))
             (prepared
              (let ((emacsvox-aural-submission-context
                     (emacsvox-test--org-context 'navigation)))
                (emacsvox-aural-prepare-text text)))
             (position 0)
             plans)
        (while (< position (length prepared))
          (push
           (emacsvox-aural-concrete-plan-at position prepared)
           plans)
          (setq
           position
           (next-single-property-change
            position emacsvox-aural-concrete-plan-property
            prepared (length prepared))))
        (setq plans (nreverse plans))
        (should (> (length plans) 1))
        (should
         (equal
          (mapcan
           (lambda (plan)
             (mapcar
              #'emacsvox-aural-concrete-action-text
              (cl-remove-if-not
               (lambda (action)
                 (eq
                  (emacsvox-aural-concrete-action-kind action)
                  'speech))
               (emacsvox-aural-concrete-plan-before plan))))
           plans)
          '("Heading 2")))
        (should
         (=
          (cl-count
           'org-fragment-heading-section-cue-action
           (mapcan
            (lambda (plan)
              (mapcar
               #'emacsvox-aural-concrete-action-id
               (emacsvox-aural-concrete-plan-before plan)))
            plans))
          1))))))

(ert-deftest emacsvox-org-visibility-fragment-speaks-level-and-new-state ()
  "The optional visibility fragment renders folded and opened wording."
  (let ((emacsvox-aural-active-scheme 'default)
        (emacsvox-aural-enabled-feature-fragments
         '(org-heading-visibility-changes))
        (emacsvox-aural-user-rules nil)
        (emacsvox-aural-session-rules nil)
        (emacsvox-aural-buffer-rules nil)
        (context
         '(:module org :mode org-mode
           :mode-lineage (org-mode outline-mode)
           :occasion state-change)))
    (dolist
        (case
         '((folded (folded) "Heading 3 is now folded")
           (expanded nil "Heading 3 is now opened")))
      (let* ((visibility (nth 0 case))
             (states (nth 1 case))
             (expected (nth 2 case))
             (facts
              (append
               (list
                :role 'heading
                :level 3
                :visibility visibility)
               (when states (list :states states))
               '(:events (state-changed) :content "Title")))
             (plan (emacsvox-aural-resolve-active facts context))
             (concrete
              (emacsvox-aural-compile-plan plan facts context)))
        (should
         (equal
          (mapcar
           #'emacsvox-aural-concrete-action-text
           (emacsvox-aural-concrete-plan-after concrete))
          (list expected)))))))

(ert-deftest emacsvox-org-combined-scheme-queues-one-concrete-plan ()
  "The motivating label, cue, voice, and heading text queue end to end."
  (let* ((emacsvox-aural-active-scheme 'org-combined)
         (emacsvox-aural-user-rules nil)
         (emacsvox-aural-session-rules nil)
         (emacsvox-aural-buffer-rules nil)
         (emacsvox-use-icons t)
         (facts
          '(:role heading :level 1 :events (focus-entered)
            :content "Title"))
         (context
          '(:module org :mode org-mode
            :mode-lineage (org-mode outline-mode)
            :occasion navigation))
         events)
    (cl-letf
        (((symbol-function 'tts-get-voice-command)
          (lambda (voice) (format "<%s>" voice)))
         ((symbol-function 'tts-voice-reset-code)
          (lambda () "RESET"))
         ((symbol-function 'tts--protocol-queue-code)
          (lambda (code) (push (list 'code code) events)))
         ((symbol-function 'tts--protocol-queue-text)
          (lambda (text) (push (list 'text text) events)))
         ((symbol-function 'emacsvox-queue-resource)
          (lambda (resource)
            (push (list 'cue (file-name-base resource)) events))))
      (emacsvox-aural-queue-concrete-plan
       (emacsvox-aural-compile-plan
        (emacsvox-aural-resolve-active facts context)
        facts context)))
    (should
     (equal
      (nreverse events)
      `((text "Heading")
        (cue "section")
        (code "RESET")
        (code ,(format "<%s>" (symbol-value 'voice-bolden)))
        (text "Title")
        (code "RESET"))))))

(ert-deftest emacsvox-org-user-overrides-cover-every-context-axis ()
  "Org headings honor global, mode, derived-mode, module, and buffer rules."
  (should
   (eq
    (emacsvox-test--org-resolved-voice
     #'org-mode
     '((:id org-test-global
        :match (:role heading)
        :render (:content (:voice animate)))))
    'animate))
  (should
   (eq
    (emacsvox-test--org-resolved-voice
     #'org-mode
     '((:id org-test-mode
        :match (:role heading :mode org-mode)
        :render (:content (:voice bolden)))))
    'bolden))
  (should
   (eq
    (emacsvox-test--org-resolved-voice
     #'emacsvox-test-org-derived-mode
     '((:id org-test-derived
        :match (:role heading :mode emacsvox-test-org-derived-mode)
        :render (:content (:voice lighten)))))
    'lighten))
  (should
   (eq
    (emacsvox-test--org-resolved-voice
     #'org-mode
     '((:id org-test-module
        :match (:role heading :module org)
        :render (:content (:voice smoothen)))))
    'smoothen))
  (should
   (eq
    (emacsvox-test--org-resolved-voice
     #'org-mode nil
     '((:id org-test-buffer
        :match (:role heading)
        :render (:content (:voice monotone)))))
    'monotone)))

(ert-deftest emacsvox-org-paragraph-feedback-is-one-native-submission ()
  "Org paragraph movement submits the paragraph with one leading cue."
  (with-temp-buffer
    (insert "First paragraph.\n\nSecond paragraph.\n")
    (goto-char (point-min))
    (let ((ems--interactive-fn-name 'org-forward-paragraph)
          submission)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (setq submission (cons content arguments)))))
        (emacsvox--advice-org-forward-paragraph-after))
      (should
       (equal
        (string-trim-right
         (substring-no-properties (car submission)))
        "First paragraph."))
      (should
       (equal
        (plist-get (cdr submission) :facts)
        '(:role org-paragraph :events (focus-entered)
          :org-action paragraph-navigation)))
      (let ((action
             (car
              (plist-get
               (cdr submission) :compatibility-actions))))
        (should
         (eq
          (emacsvox-aural-compatibility-action-value action)
          'paragraph))
        (should
         (eq
          (emacsvox-aural-compatibility-action-phase action)
          'before))))))

(ert-deftest emacsvox-org-cycle-keeps-table-feedback-unconditional ()
  "Org visibility cycling always reports the current table cell."
  (let* ((ems--interactive-fn-name nil)
         events
         (emacsvox-org-table-after-movement-function
          (lambda () (push 'table-cell events))))
    (cl-letf (((symbol-function 'org-at-table-p)
               (lambda (&rest _) t))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events))))
      (emacsvox--advice-org-cycle-after))
    (should (equal events '(table-cell)))))

(ert-deftest emacsvox-org-cycle-nontable-feedback-is-target-aware ()
  "Only matching interactive non-table cycling submits the line."
  (with-temp-buffer
    (insert "Body")
    (goto-char (point-min))
    (let ((ems--interactive-fn-name 'org-shifttab)
          submissions)
      (cl-letf (((symbol-function 'org-at-table-p)
                 (lambda (&rest _) nil))
                ((symbol-function 'emacsvox-aural-submit)
                 (lambda (content &rest arguments)
                   (push (cons content arguments) submissions))))
        (emacsvox--advice-org-cycle-after)
        (emacsvox--advice-org-shifttab-after))
      (should (= (length submissions) 1))
      (should
       (equal
        (plist-get (cdar submissions) :facts)
        '(:role org-content :events (state-changed)))))))

(ert-deftest emacsvox-org-cycle-submits-explicit-visibility-change ()
  "Org cycling submits heading level, new visibility, event, and occasion."
  (with-temp-buffer
    (emacsvox-test--activate-org-mode #'org-mode)
    (insert "* Parent\nBody\n** Child\n")
    (goto-char (point-min))
    (org-fold-hide-subtree)
    (let ((ems--interactive-fn-name 'org-cycle)
          submission)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (setq submission (cons content arguments)))))
        (emacsvox--advice-org-cycle-after))
      (should
       (equal
        (plist-get (cdr submission) :facts)
        '(:role heading :level 1 :visibility folded
          :states (folded) :events (state-changed))))
      (should (eq (plist-get (cdr submission) :module) 'org))
      (should
       (eq (plist-get (cdr submission) :occasion) 'state-change)))))

(ert-deftest emacsvox-org-agenda-table-advice-is-directly-registered ()
  "Org agenda and table advice uses native advice directly."
  (dolist (target emacsvox-test--org-agenda-table-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-org-timestamp-feedback-is-target-aware ()
  "Only the matching timestamp command submits one complete presentation."
  (let ((ems--interactive-fn-name 'org-timestamp-up)
        (org-last-changed-timestamp "<2026-07-23 Thu>")
        submissions)
    (cl-letf
        (((symbol-function 'emacsvox-aural-submit)
          (lambda (content &rest arguments)
            (push (cons content arguments) submissions))))
      (emacsvox--advice-org-timestamp-down-after)
      (emacsvox--advice-org-timestamp-up-after))
    (should (= (length submissions) 1))
    (let* ((submission (car submissions))
           (arguments (cdr submission))
           (action (car (plist-get arguments :compatibility-actions))))
      (should (equal (car submission) "<2026-07-23 Thu>"))
      (should
       (equal
        (plist-get arguments :facts)
        '(:role org-content :events (object-changed)
          :org-action timestamp-changed)))
      (should (eq (plist-get arguments :module) 'org))
      (should (eq (plist-get arguments :occasion) 'edit))
      (should
       (eq
        (emacsvox-aural-compatibility-action-value action)
        'select-object))
      (should
       (eq
        (emacsvox-aural-compatibility-action-phase action)
        'before)))))

(ert-deftest emacsvox-org-timestamp-native-plan-resolves-cue-once ()
  "Timestamp speech and its compatibility cue share one resolved object."
  (with-temp-buffer
    (emacsvox-test--activate-org-mode #'org-mode)
    (let ((ems--interactive-fn-name 'org-timestamp-up)
          (org-last-changed-timestamp "<2026-07-23 Thu>")
          prepared)
      (cl-letf
          (((symbol-function 'tts-speak)
            (lambda (text) (setq prepared text)))
           ((symbol-function 'emacsvox-icon)
            (lambda (&rest _)
              (ert-fail "Native timestamp feedback called legacy icon transport"))))
        (emacsvox--advice-org-timestamp-up-after))
      (let* ((plan (emacsvox-aural-concrete-plan-at 0 prepared))
             (before (emacsvox-aural-concrete-plan-before plan)))
        (should
         (equal
          (substring-no-properties prepared)
          "<2026-07-23 Thu>"))
        (should
         (= 1
            (cl-count
             'select-object before
             :key #'emacsvox-aural-concrete-action-cue)))
        (should
         (equal
          (plist-get
           (emacsvox-aural-concrete-plan-facts plan)
           :events)
          '(object-changed)))
        (should
         (natnump
          (plist-get
           (emacsvox-aural-concrete-plan-context plan)
           :presentation-transaction-id)))))))

(ert-deftest emacsvox-org-calendar-feedback-remains-unconditional ()
  "Calendar expression results submit even outside an interactive call."
  (let ((ems--interactive-fn-name nil)
        (org-ans2 "Thursday")
        submissions)
    (setq submissions
          (emacsvox-test--capture-org-submissions
            (emacsvox--advice-org-eval-in-calendar-after)))
    (should (= (length submissions) 1))
    (should (equal (caar submissions) "Thursday"))
    (should
     (equal
      (plist-get (cdar submissions) :facts)
      '(:role org-content :events (focus-entered)
        :org-action calendar-evaluated)))
    (should (eq (plist-get (cdar submissions) :occasion) 'inspection))))

(ert-deftest emacsvox-org-visibility-and-indirect-feedback-is-native ()
  "Overview, contents, and indirect-buffer results have semantic ownership."
  (let ((indirect-buffer (generate-new-buffer " *Org indirect test*"))
        submissions)
    (unwind-protect
        (progn
          (with-current-buffer indirect-buffer
            (insert "* Cloned heading\nBody"))
          (let ((org-last-indirect-buffer indirect-buffer))
            (cl-letf
                (((symbol-function 'emacsvox-org--submit-message-feedback)
                  (lambda (facts occasion icon text)
                    (push (list facts occasion icon text) submissions))))
              (let ((ems--interactive-fn-name 'org-overview))
                (emacsvox--advice-org-overview-after))
              (let ((ems--interactive-fn-name 'org-content))
                (emacsvox--advice-org-content-after))
              (let ((ems--interactive-fn-name
                     'org-tree-to-indirect-buffer))
                (emacsvox--advice-org-tree-to-indirect-buffer-after)))))
      (kill-buffer indirect-buffer))
    (should
     (equal
      (nreverse submissions)
      '(((:role org-content :events (state-changed)
          :org-action overview-shown)
         state-change nil "Showing top-level overview.")
        ((:role org-content :events (state-changed)
          :org-action contents-shown)
         state-change nil "Showing table of contents.")
        ((:role org-content :events (focus-entered)
          :org-action indirect-buffer-opened)
         navigation nil "Cloned * Cloned heading"))))))

(ert-deftest emacsvox-org-agenda-navigation-is-one-native-submission ()
  "Agenda navigation submits the destination and leading cue together."
  (with-temp-buffer
    (insert "Agenda entry")
    (goto-char (point-min))
    (let* ((ems--interactive-fn-name 'org-agenda-next-line)
           (submissions
            (emacsvox-test--capture-org-submissions
              (emacsvox--advice-org-agenda-previous-line-after)
              (emacsvox--advice-org-agenda-next-line-after)))
           (arguments (cdar submissions))
           (action
            (car (plist-get arguments :compatibility-actions))))
      (should (= (length submissions) 1))
      (should
       (equal
        (plist-get arguments :facts)
        '(:role org-agenda-entry :events (focus-entered)
          :org-action agenda-navigation)))
      (should
       (eq
        (emacsvox-aural-compatibility-action-value action)
        'select-object))
      (should
       (eq
        (emacsvox-aural-compatibility-action-phase action)
        'before)))))

(ert-deftest emacsvox-org-agenda-state-advice-is-directly-registered ()
  "Agenda state, filter, and view commands have named quiet adapters."
  (dolist
      (target
       (append emacsvox-test--org-agenda-line-around-targets
               emacsvox-test--org-agenda-message-around-targets))
    (let ((function
           (intern (format "emacsvox--advice-%s-around" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-org-agenda-line-change-owns-result ()
  "An agenda entry mutation speaks its resulting line, not Org's message."
  (with-temp-buffer
    (insert "  TODO Ship release")
    (goto-char (point-min))
    (let ((ems--interactive-fn-name 'org-agenda-priority)
          (emacsvox-speak-messages t)
          message-state
          submissions)
      (cl-letf
          (((symbol-function 'current-message)
            (lambda () "Priority changed"))
           ((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (push (cons content arguments) submissions))))
        (emacsvox--advice-org-agenda-priority-around
         (lambda (&rest _)
           (setq message-state emacsvox-speak-messages))))
      (should-not message-state)
      (should (= (length submissions) 1))
      (should
       (equal
        (substring-no-properties (caar submissions))
        "  TODO Ship release"))
      (should
       (equal
        (plist-get (cdar submissions) :facts)
        '(:role org-agenda-entry :events (state-changed)
          :org-action priority-changed))))))

(ert-deftest emacsvox-org-agenda-filter-preserves-informative-message ()
  "An agenda filter submits Org's final message once through native policy."
  (let ((ems--interactive-fn-name 'org-agenda-filter)
        (emacsvox-speak-messages t)
        (messages '("Before" "Filtered by tag work"))
        submissions)
    (cl-letf
        (((symbol-function 'current-message)
          (lambda () (pop messages)))
         ((symbol-function 'emacsvox-aural-submit)
          (lambda (content &rest arguments)
            (push (cons content arguments) submissions))))
      (emacsvox--advice-org-agenda-filter-around
       (lambda (&rest _)
         (should-not emacsvox-speak-messages))))
    (should (= (length submissions) 1))
    (should (equal (caar submissions) "Filtered by tag work"))
    (should
     (equal
      (plist-get (cdar submissions) :facts)
      '(:role org-agenda-entry :events (state-changed)
        :org-action agenda-filter-changed)))))

(ert-deftest emacsvox-org-table-movement-feedback-remains-unconditional ()
  "Table movement always reports the current cell."
  (let* ((ems--interactive-fn-name nil)
         events
         (emacsvox-org-table-after-movement-function
          (lambda () (push 'table-cell events))))
    (emacsvox--advice-org-table-next-field-after)
    (should (equal events '(table-cell)))))

(ert-deftest emacsvox-org-table-presentation-is-semantic-and-contextual ()
  "Table inspection and movement identify the cell, coordinates, and occasion."
  (with-temp-buffer
    (emacsvox-test--activate-org-mode #'org-mode)
    (insert "| Name | Value |\n| Row | Cell  |\n")
    (goto-char (point-min))
    (search-forward "Cell")
    (let (submissions)
      (cl-letf
          (((symbol-function 'emacsvox-org--submit-message-feedback)
            (lambda (facts occasion icon text)
              (push (list facts occasion icon text) submissions))))
        (emacsvox-org-table-speak-current-element)
        (let ((emacsvox-org-table-after-movement-function
               #'emacsvox-org-table-speak-column-header-and-element))
          (emacsvox-org--present-table-after-movement)))
      (setq submissions (nreverse submissions))
      (should (= (length submissions) 2))
      (pcase-let ((`(,facts ,occasion ,icon ,text) (nth 0 submissions)))
        (should (eq occasion 'inspection))
        (should-not icon)
        (should (equal text "Cell"))
        (should (eq (plist-get facts :org-action) 'table-inspection))
        (should (= (plist-get facts :org-table-row) 2))
        (should (= (plist-get facts :org-table-column) 2))
        (should (eq (plist-get facts :org-table-presentation) 'cell)))
      (pcase-let ((`(,facts ,occasion ,icon ,text) (nth 1 submissions)))
        (should (eq occasion 'navigation))
        (should-not icon)
        (should (equal (substring-no-properties text) "Value Cell"))
        (should (eq (plist-get facts :org-action) 'table-navigation))
        (should
         (eq
          (plist-get facts :org-table-presentation)
          'cell-with-column-header))))))

(ert-deftest emacsvox-org-table-command-advice-is-directly-registered ()
  "Org table mutation and inspection commands have named quiet adapters."
  (dolist
      (target
       (append emacsvox-test--org-table-change-around-targets
               emacsvox-test--org-table-message-around-targets))
    (let ((function
           (intern (format "emacsvox--advice-%s-around" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-org-table-editor-advice-is-directly-registered ()
  "Org field and formula editor commands have named quiet adapters."
  (dolist (target emacsvox-test--org-table-editor-around-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-around" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-org-table-formula-reports-resulting-cell ()
  "Formula evaluation submits the resulting cell and coordinates once."
  (with-temp-buffer
    (emacsvox-test--activate-org-mode #'org-mode)
    (insert "| Name | Value |\n| Row  | 1     |\n")
    (goto-char (point-min))
    (search-forward "1")
    (let ((ems--interactive-fn-name 'org-table-eval-formula)
          (emacsvox-speak-messages t)
          message-state
          submissions)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (push (cons content arguments) submissions))))
        (emacsvox--advice-org-table-eval-formula-around
         (lambda (&rest _)
           (setq message-state emacsvox-speak-messages)
           (org-table-put 2 2 "42"))))
      (should-not message-state)
      (should (= (length submissions) 1))
      (should (equal (caar submissions) "42"))
      (should
       (equal
        (plist-get (cdar submissions) :facts)
        '(:role org-table :events (state-changed)
          :org-action table-formula-evaluated
          :org-table-row 2 :org-table-column 2
          :org-table-presentation cell)))
      (should (eq (plist-get (cdar submissions) :occasion) 'state-change)))))

(ert-deftest emacsvox-org-table-inspection-preserves-message ()
  "Table inspection submits Org's informative message through native policy."
  (with-temp-buffer
    (emacsvox-test--activate-org-mode #'org-mode)
    (insert "| Value |\n| 12    |\n")
    (goto-char (point-min))
    (forward-line)
    (search-forward "12")
    (let ((ems--interactive-fn-name 'org-table-sum)
          (messages '("Before" "Sum: 12"))
          submissions)
      (cl-letf
          (((symbol-function 'current-message)
            (lambda () (pop messages)))
           ((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (push (cons content arguments) submissions))))
        (emacsvox--advice-org-table-sum-around
         (lambda (&rest _))))
      (should (= (length submissions) 1))
      (should (equal (caar submissions) "Sum: 12"))
      (should
       (eq
        (plist-get (plist-get (cdar submissions) :facts) :org-action)
        'table-inspected))
      (should (eq (plist-get (cdar submissions) :occasion) 'inspection)))))

(ert-deftest emacsvox-org-table-editor-lifecycle-is-semantic ()
  "Opening and closing a formula editor identifies both lifecycle states."
  (let ((source (generate-new-buffer " *Org table source*"))
        (editor (generate-new-buffer " *Org formula editor*"))
        submissions)
    (unwind-protect
        (progn
          (with-current-buffer source
            (emacsvox-test--activate-org-mode #'org-mode)
            (insert "| Name | Value |\n| Row  | 42    |\n")
            (goto-char (point-min))
            (forward-line)
            (search-forward "42"))
          (with-current-buffer editor
            (insert "$2 = $1 * 2")
            (goto-char (point-min)))
          (with-current-buffer source
            (let ((ems--interactive-fn-name 'org-table-edit-formulas))
              (cl-letf
                  (((symbol-function 'emacsvox-aural-submit)
                    (lambda (content &rest arguments)
                      (push (cons content arguments) submissions))))
                (emacsvox--advice-org-table-edit-formulas-around
                 (lambda (&rest _) (set-buffer editor))))))
          (with-current-buffer editor
            (let ((ems--interactive-fn-name 'org-table-fedit-finish))
              (cl-letf
                  (((symbol-function 'emacsvox-aural-submit)
                    (lambda (content &rest arguments)
                      (push (cons content arguments) submissions))))
                (emacsvox--advice-org-table-fedit-finish-around
                 (lambda (&rest _) (set-buffer source)))))))
      (kill-buffer editor)
      (kill-buffer source))
    (setq submissions (nreverse submissions))
    (should (= (length submissions) 2))
    (should
     (equal
      (plist-get (cdar submissions) :facts)
      '(:role org-edit-buffer :events (focus-entered)
        :org-action table-editor-opened)))
    (should
     (eq (plist-get (cdar submissions) :occasion) 'navigation))
    (should
     (eq
      (plist-get (plist-get (cdr (nth 1 submissions)) :facts) :org-action)
      'table-editor-closed))
    (should
     (equal (car (nth 1 submissions)) "42"))))

(ert-deftest emacsvox-org-field-editor-context-action-reports-close ()
  "C-c C-c reports a field-editor close instead of a generic context action."
  (let ((source (generate-new-buffer " *Org field source*"))
        (editor (generate-new-buffer " *Org field editor*"))
        submission)
    (unwind-protect
        (progn
          (with-current-buffer source
            (emacsvox-test--activate-org-mode #'org-mode)
            (insert "| Value |\n| Cell  |\n")
            (goto-char (point-min))
            (forward-line)
            (search-forward "Cell"))
          (with-current-buffer editor
            (setq-local org-finish-function 'org-table-finish-edit-field)
            (let ((ems--interactive-fn-name 'org-ctrl-c-ctrl-c))
              (cl-letf
                  (((symbol-function 'emacsvox-aural-submit)
                    (lambda (content &rest arguments)
                      (setq submission (cons content arguments)))))
                (emacsvox--advice-org-ctrl-c-ctrl-c-around
                 (lambda (&rest _) (set-buffer source)))))))
      (kill-buffer editor)
      (kill-buffer source))
    (should (equal (car submission) "Cell"))
    (should
     (eq
      (plist-get (plist-get (cdr submission) :facts) :org-action)
      'table-editor-closed))))

(ert-deftest emacsvox-org-return-selects-table-or-line-feedback ()
  "Org return defers table feedback and owns its non-table destination."
  (with-temp-buffer
    (insert "Destination")
    (goto-char (point-min))
    (let* ((ems--interactive-fn-name 'org-return)
           at-table
           (submissions
            (cl-letf (((symbol-function 'org-at-table-p)
                       (lambda (&rest _) at-table)))
              (emacsvox-test--capture-org-submissions
                (setq at-table t)
                (emacsvox--advice-org-return-after)
                (setq at-table nil
                      ems--interactive-fn-name 'org-return)
                (emacsvox--advice-org-return-after))))
           (action
            (car
             (plist-get
              (cdar submissions) :compatibility-actions))))
      (should (= (length submissions) 1))
      (should
       (eq
        (emacsvox-aural-compatibility-action-value action)
        'select-object))
      (should
       (eq
        (emacsvox-aural-compatibility-action-phase action)
        'after)))))

(ert-deftest emacsvox-org-return-reports-a-real-table-move-once ()
  "The table command called by `org-return' owns its one cell announcement."
  (with-temp-buffer
    (emacsvox-test--activate-org-mode #'org-mode)
    (insert "| A | B |\n| 1 | 2 |\n")
    (goto-char (point-min))
    (search-forward "A")
    (let* ((ems--interactive-fn-name 'org-return)
           events
           (emacsvox-org-table-after-movement-function
            (lambda () (push 'cell events))))
      (org-return)
      (should (equal events '(cell)))
      (should (= (line-number-at-pos) 2)))))

(ert-deftest emacsvox-org-editing-advice-is-directly-registered ()
  "Org editing advice uses native advice directly."
  (dolist (target emacsvox-test--org-editing-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-org-heading-edit-feedback-is-native-and-target-aware ()
  "Only the matching heading edit submits its resulting heading."
  (with-temp-buffer
    (emacsvox-test--activate-org-mode #'org-mode)
    (insert "* Heading\n")
    (goto-char (point-min))
    (let ((ems--interactive-fn-name 'org-insert-heading)
          submissions)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (push (cons content arguments) submissions))))
        (emacsvox--advice-org-insert-todo-heading-after)
        (emacsvox--advice-org-insert-heading-after))
      (should (= (length submissions) 1))
      (should
       (equal
        (plist-get (cdar submissions) :facts)
        '(:role heading :level 1 :visibility expanded
          :events (object-changed)
          :org-action heading-edited)))
      (should (eq (plist-get (cdar submissions) :occasion) 'edit)))))

(ert-deftest emacsvox-org-document-state-advice-is-directly-registered ()
  "Every covered Org document state command has its named quiet adapter."
  (dolist (target emacsvox-test--org-document-state-around-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-around" target))))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-org-document-state-owns-message-and-result ()
  "An interactive metadata command is quiet and submits its changed heading."
  (with-temp-buffer
    (emacsvox-test--activate-org-mode #'org-mode)
    (insert "* Task")
    (goto-char (point-min))
    (let ((ems--interactive-fn-name 'org-priority)
          (emacsvox-speak-messages t)
          message-state
          submissions)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (push (cons content arguments) submissions))))
        (should
         (eq
          'changed
          (emacsvox--advice-org-priority-around
           (lambda (&rest _)
             (setq message-state emacsvox-speak-messages)
             'changed)))))
      (should-not message-state)
      (should (= (length submissions) 1))
      (should
       (equal
        (plist-get (cdar submissions) :facts)
        '(:role heading :level 1 :visibility expanded
          :events (state-changed) :org-action priority-changed)))
      (should
       (eq (plist-get (cdar submissions) :occasion) 'state-change)))))

(ert-deftest emacsvox-org-subtree-feedback-is-target-aware ()
  "Only the matching subtree command submits its resulting line."
  (with-temp-buffer
    (insert "* Pasted subtree")
    (goto-char (point-min))
    (let* ((ems--interactive-fn-name 'org-paste-subtree)
           (submissions
            (emacsvox-test--capture-org-submissions
              (emacsvox--advice-org-copy-subtree-after)
              (emacsvox--advice-org-paste-subtree-after)))
           (arguments (cdar submissions))
           (action
            (car (plist-get arguments :compatibility-actions))))
      (should (= (length submissions) 1))
      (should
       (equal
        (plist-get arguments :facts)
        '(:role org-content :events (object-changed)
          :org-action subtree-changed)))
      (should
       (eq
        (emacsvox-aural-compatibility-action-value action)
        'yank-object))
      (should
       (eq
        (emacsvox-aural-compatibility-action-phase action)
        'after)))))

(ert-deftest emacsvox-org-generic-end-of-line-delegates-in-org-mode ()
  "Interactive generic line movement invokes Org's line endpoint logic."
  (let ((ems--interactive-fn-name 'end-of-line)
        (major-mode 'org-mode)
        delegated)
    (cl-letf (((symbol-function 'org-end-of-line)
               (lambda (&rest _) (setq delegated t))))
      (emacsvox--advice-end-of-line-after))
    (should delegated)))

(ert-deftest emacsvox-org-item-boundary-navigation-is-native ()
  "Org item-boundary navigation submits the line before its selection cue."
  (with-temp-buffer
    (insert "- Item")
    (goto-char (point-min))
    (let* ((ems--interactive-fn-name 'org-end-of-item)
           (submissions
            (emacsvox-test--capture-org-submissions
              (emacsvox--advice-org-end-of-item-after)))
           (arguments (cdar submissions))
           (action
            (car (plist-get arguments :compatibility-actions))))
      (should (= (length submissions) 1))
      (should
       (eq
        (emacsvox-aural-compatibility-action-value action)
        'select-object))
      (should
       (eq
        (emacsvox-aural-compatibility-action-phase action)
        'after)))))

(ert-deftest emacsvox-org-source-edit-feedback-is-target-aware ()
  "Only the matching source edit command reports its window transition."
  (with-temp-buffer
    (insert "Source block")
    (goto-char (point-min))
    (let* ((ems--interactive-fn-name 'org-edit-src-exit)
           (submissions
            (emacsvox-test--capture-org-submissions
              (emacsvox--advice-org-edit-src-abort-after)
              (emacsvox--advice-org-edit-src-exit-after)))
           (arguments (cdar submissions))
           (action
            (car (plist-get arguments :compatibility-actions))))
      (should (= (length submissions) 1))
      (should
       (eq
        (emacsvox-aural-compatibility-action-value action)
        'close-object))
      (should
       (eq
        (emacsvox-aural-compatibility-action-phase action)
        'before)))))

(ert-deftest emacsvox-org-babel-advice-is-directly-registered ()
  "Every covered Org Babel command has its named quiet adapter."
  (dolist (target emacsvox-test--org-babel-around-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-around" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-org-babel-execution-speaks-the-result ()
  "A real Babel execution submits its result instead of the source line."
  (with-temp-buffer
    (emacsvox-test--activate-org-mode #'org-mode)
    (insert
     "#+begin_src emacs-lisp\n"
     "(+ 20 22)\n"
     "#+end_src\n")
    (goto-char (point-min))
    (let ((ems--interactive-fn-name 'org-babel-execute-src-block)
          (org-confirm-babel-evaluate nil)
          submissions)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (push (cons content arguments) submissions))))
        (org-babel-execute-src-block))
      (should (= (length submissions) 1))
      (should (equal (caar submissions) "42"))
      (should
       (equal
        (plist-get (cdar submissions) :facts)
        '(:role org-babel-result :events (object-changed)
          :org-action source-block-executed)))
      (should (eq (plist-get (cdar submissions) :occasion) 'notification))
      (should (search-forward "#+RESULTS:" nil t))
      (should (search-forward ": 42" nil t)))))

(ert-deftest emacsvox-org-babel-navigation-identifies-source-block ()
  "Babel block navigation submits the destination as source-block semantics."
  (with-temp-buffer
    (emacsvox-test--activate-org-mode #'org-mode)
    (insert
     "#+begin_src emacs-lisp\n1\n#+end_src\n\n"
     "#+begin_src emacs-lisp\n2\n#+end_src\n")
    (goto-char (point-min))
    (let ((ems--interactive-fn-name 'org-babel-next-src-block)
          submissions)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (push (cons content arguments) submissions))))
        (org-babel-next-src-block))
      (should (= (length submissions) 1))
      (should
       (string-match-p
        "#\\+begin_src emacs-lisp"
        (substring-no-properties (caar submissions))))
      (should
       (equal
        (plist-get (cdar submissions) :facts)
        '(:role org-source-block :events (focus-entered)
          :org-action source-block-navigation)))
      (should (eq (plist-get (cdar submissions) :occasion) 'navigation)))))

(ert-deftest emacsvox-org-todo-feedback-reports-current-state ()
  "Interactive TODO changes submit the resulting state once."
  (let ((ems--interactive-fn-name 'org-todo)
        submitted)
    (cl-letf
        (((symbol-function 'org-get-todo-state)
          (lambda () "DONE"))
         ((symbol-function 'emacsvox-org--submit-message-feedback)
          (lambda (facts occasion icon text)
            (setq submitted (list facts occasion icon text)))))
      (emacsvox--advice-org-todo-after))
    (should
     (equal
      submitted
      '((:role org-content :events (state-changed)
         :org-action todo-changed)
        state-change button "DONE")))))

(ert-deftest emacsvox-org-state-messages-use-native-submission ()
  "Org state messages remain visible but have one native audible owner."
  (let ((emacsvox-speak-messages t)
        events)
    (cl-letf
        (((symbol-function 'message)
          (lambda (format-string &rest arguments)
            (push
             (list
              'message
              (apply #'format format-string arguments)
              emacsvox-speak-messages)
             events)))
         ((symbol-function 'emacsvox-aural-submit)
          (lambda (content &rest arguments)
            (push (list 'submit content arguments) events))))
      (emacsvox-org--submit-message-feedback
       '(:role org-content :events (state-changed)
         :org-action todo-changed)
       'state-change 'button "DONE"))
    (should (eq (caar events) 'submit))
    (should (equal (cadr (car events)) "DONE"))
    (let* ((arguments (nth 2 (car events)))
           (action
            (car (plist-get arguments :compatibility-actions))))
      (should
       (equal
        (plist-get arguments :facts)
        '(:role org-content :events (state-changed)
          :org-action todo-changed)))
      (should (eq (plist-get arguments :module) 'org))
      (should (eq (plist-get arguments :occasion) 'state-change))
      (should
       (eq
        (emacsvox-aural-compatibility-action-value action)
        'button)))
    (should
     (equal
      (cadr events)
      '(message "DONE" nil)))))

(ert-deftest emacsvox-org-table-and-fill-state-feedback-is-explicit ()
  "Table toggling and paragraph fill submit stable text and semantics."
  (let ((ems--interactive-fn-name 'orgtbl-mode)
        (orgtbl-mode t)
        submitted)
    (cl-letf
        (((symbol-function 'emacsvox-org--submit-message-feedback)
          (lambda (facts occasion icon text)
            (push (list facts occasion icon text) submitted))))
      (emacsvox--advice-orgtbl-mode-after)
      (setq ems--interactive-fn-name 'org-fill-paragraph)
      (emacsvox--advice-org-fill-paragraph-after))
    (should
     (equal
      (nreverse submitted)
      '(((:role org-table :events (state-changed)
          :org-action table-mode-toggled)
         state-change on "Turned on org table mode.")
        ((:role org-paragraph :events (object-changed)
          :org-action paragraph-filled)
         edit fill-object "Filled current paragraph"))))))

(ert-deftest emacsvox-org-capture-advice-is-directly-registered ()
  "Org capture advice uses native advice directly."
  (dolist (target emacsvox-test--org-capture-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-org-last-capture-feedback-is-target-aware ()
  "Visiting the last capture only reports an interactive invocation."
  (with-temp-buffer
    (insert "Captured item")
    (goto-char (point-min))
    (let* ((ems--interactive-fn-name 'org-capture-goto-last-stored)
           (submissions
            (emacsvox-test--capture-org-submissions
              (emacsvox--advice-org-capture-goto-last-stored-after)))
           (action
            (car
             (plist-get
              (cdar submissions) :compatibility-actions))))
      (should (= (length submissions) 1))
      (should
       (eq
        (emacsvox-aural-compatibility-action-value action)
        'large-movement)))))

(ert-deftest emacsvox-org-capture-target-feedback-remains-unconditional ()
  "Internally selected capture targets still cue and speak."
  (with-temp-buffer
    (insert "Capture target")
    (goto-char (point-min))
    (let* ((ems--interactive-fn-name nil)
           (submissions
            (emacsvox-test--capture-org-submissions
              (emacsvox--advice-org-capture-goto-target-after)))
           (arguments (cdar submissions)))
      (should (= (length submissions) 1))
      (should
       (equal
        (plist-get arguments :facts)
        '(:role org-capture :events (focus-entered)
          :org-action capture-target)))
      (should
       (eq
        (emacsvox-aural-compatibility-action-value
         (car
          (plist-get arguments :compatibility-actions)))
        'large-movement)))))

(ert-deftest emacsvox-org-capture-lifecycle-cues-remain-unconditional ()
  "Finalizing and cancelling captures submit their lifecycle cues natively."
  (let ((ems--interactive-fn-name nil)
        submissions)
    (cl-letf
        (((symbol-function 'emacsvox-aural-submit-actions)
          (lambda (&rest arguments)
            (push arguments submissions))))
      (emacsvox--advice-org-capture-finalize-after)
      (emacsvox--advice-org-capture-kill-after))
    (setq submissions (nreverse submissions))
    (should (= (length submissions) 2))
    (should
     (equal
      (mapcar
       (lambda (arguments)
         (emacsvox-aural-compatibility-action-value
          (car
           (plist-get arguments :compatibility-actions))))
       submissions)
      '(save-object close-object)))
    (should
     (equal
      (mapcar
       (lambda (arguments)
         (plist-get (plist-get arguments :facts) :org-action))
       submissions)
      '(capture-saved capture-cancelled)))))

(ert-deftest emacsvox-org-markdown-export-feedback-is-target-aware ()
  "Interactive Markdown export submits completion and buffer context once."
  (let* ((ems--interactive-fn-name 'org-md-export-as-markdown)
         (submissions
          (emacsvox-test--capture-org-submissions
            (emacsvox--advice-org-md-export-as-markdown-after)))
         (arguments (cdar submissions))
         (action
          (car (plist-get arguments :compatibility-actions))))
    (should (= (length submissions) 1))
    (should
     (equal
      (plist-get arguments :facts)
      '(:role org-export :events (object-changed)
        :org-action export-completed)))
    (should
     (eq
      (emacsvox-aural-compatibility-action-value action)
      'task-done))))

(ert-deftest emacsvox-org-risky-advice-is-directly-registered ()
  "Org deletion and export advice uses native advice directly."
  (dolist
      (entry
       '((org-delete-char :around emacsvox--advice-org-delete-char-around)
         (org-export--dispatch-action
          :before emacsvox--advice-org-export--dispatch-action-before)
         (org-export-to-file :after
                             emacsvox--advice-org-export-to-file-after)))
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-org-delete-char-calls-original-once ()
  "Interactive Org deletion gives feedback, then calls the command once."
  (let ((ems--interactive-fn-name 'org-delete-char)
        calls
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-edit-operation)
               (lambda (operation)
                 (push (list 'edit operation) events)))
              ((symbol-function 'emacsvox-speak-char)
               (lambda (delete-p) (push (list 'speak-char delete-p) events))))
      (should
       (eq
        'result
        (emacsvox--advice-org-delete-char-around
         (lambda (n)
           (push n calls)
           'result)
         3))))
    (should (equal calls '(3)))
    (should
     (equal
      (nreverse events)
      '((edit deletion) (speak-char t))))))

(ert-deftest emacsvox-org-delete-char-is-quiet-programmatically ()
  "Programmatic Org deletion calls the original once without feedback."
  (let ((ems--interactive-fn-name nil)
        calls
        feedback)
    (cl-letf (((symbol-function 'emacsvox-speak-edit-operation)
               (lambda (&rest _) (setq feedback t)))
              ((symbol-function 'emacsvox-speak-char)
               (lambda (&rest _) (setq feedback t))))
      (emacsvox--advice-org-delete-char-around
       (lambda (n) (push n calls))
       2))
    (should (equal calls '(2)))
    (should-not feedback)))

(ert-deftest emacsvox-org-legacy-completion-calls-original-once ()
  "The optional legacy Org completion wrapper preserves one-call semantics."
  (with-temp-buffer
    (let ((calls 0)
          events)
      (cl-letf (((symbol-function 'emacsvox-get-minibuffer-contents)
                 (lambda () ""))
                ((symbol-function 'emacsvox-speak-line)
                 (lambda () (push 'speak-line events)))
                ((symbol-function 'emacsvox-speak-completions-if-available)
                 (lambda () (push 'completions events))))
        (should
         (eq
          'result
          (emacsvox--advice-org-complete-around
           (lambda ()
             (cl-incf calls)
             (insert "completed")
             'result))))
      (should (= calls 1))
      (should (equal events '(speak-line)))))))

(ert-deftest emacsvox-org-legacy-completion-does-not-create-a-command ()
  "Absent legacy Org completion remains absent on current Org."
  (unless (symbol-file 'org-complete 'defun)
    (should-not (fboundp 'org-complete))))

(ert-deftest emacsvox-org-export-dispatch-uses-explicit-arguments ()
  "Export choices are one native submission without a forced delay."
  (let ((entries '((?a "Alpha") (?b "Beta")))
        submissions)
    (setq submissions
          (emacsvox-test--capture-org-submissions
            (emacsvox--advice-org-export--dispatch-action-before
             "Export" '(?a ?b) entries nil nil nil)))
    (should (= (length submissions) 1))
    (should (equal (caar submissions) "a: Alpha\nb: Beta"))
    (should
     (equal
      (plist-get (cdar submissions) :facts)
      '(:role org-export :events (focus-entered)
        :org-action export-menu-opened)))
    (should (eq (plist-get (cdar submissions) :occasion) 'inspection))))

(ert-deftest emacsvox-org-export-to-file-uses-explicit-file ()
  "Export completion reports the FILE argument directly."
  (let (submitted)
    (cl-letf
        (((symbol-function 'emacsvox-org--submit-message-feedback)
          (lambda (facts occasion icon text)
            (setq submitted (list facts occasion icon text)))))
      (emacsvox--advice-org-export-to-file-after
       'html "/tmp/report.html" nil nil nil nil nil nil))
    (should
     (equal
      submitted
      '((:role org-export :events (object-changed)
         :org-action export-completed)
        notification save-object "Wrote /tmp/report.html")))))

(ert-deftest emacsvox-org-publish-hook-is-reload-safe-and-explicit ()
  "Publishing uses one named hook and reports the produced file."
  (should
   (= 1
      (cl-count
       #'emacsvox-org--publish-finished
       org-publish-after-publishing-hook)))
  (let (submitted)
    (cl-letf
        (((symbol-function 'emacsvox-org--submit-message-feedback)
          (lambda (facts occasion icon text)
            (setq submitted (list facts occasion icon text)))))
      (emacsvox-org--publish-finished
       "/tmp/source.org" "/tmp/site/index.html"))
    (should
     (equal
      submitted
      '((:role org-export :events (object-changed)
         :org-action publish-completed)
        notification save-object "Published /tmp/site/index.html")))))

(provide 'emacsvox-org-tests)
;;; emacsvox-org-tests.el ends here
