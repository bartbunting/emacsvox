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
    org-agenda-next-line org-agenda-previous-line org-agenda-goto-today
    org-agenda-quit org-agenda-exit
    org-agenda-goto org-agenda-show org-agenda-switch-to org-agenda
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

(ert-deftest emacsvox-org-structure-advice-is-directly-registered ()
  "Org structure advice uses native advice directly."
  (dolist (target emacsvox-test--org-structure-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-org-item-feedback-is-target-aware ()
  "Only the matching Org item movement cues and speaks the item."
  (let ((ems--interactive-fn-name 'org-previous-item)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-org-speak-item)
               (lambda () (push 'speak-item events))))
      (emacsvox--advice-org-next-item-after)
      (emacsvox--advice-org-previous-item-after))
    (should
     (equal
      (nreverse events)
      '((icon item) speak-item)))))

(ert-deftest emacsvox-org-item-feedback-captures-semantic-boundary ()
  "Item movement exposes stable intent to both its cue and speech."
  (let ((ems--interactive-fn-name 'org-next-item)
        presentations)
    (cl-letf
        (((symbol-function 'emacsvox-icon)
          (lambda (_)
            (push
             (list
              (copy-tree emacsvox-aural-submission-facts)
              (copy-tree emacsvox-aural-submission-context))
             presentations)))
         ((symbol-function 'emacsvox-org-speak-item)
          (lambda ()
            (push
             (list
              (copy-tree emacsvox-aural-submission-facts)
              (copy-tree emacsvox-aural-submission-context))
             presentations))))
      (emacsvox--advice-org-next-item-after))
    (should (= (length presentations) 2))
    (dolist (presentation presentations)
      (should
       (equal
        (car presentation)
        '(:role org-item :events (focus-entered)
          :org-action item-navigation)))
      (should (eq (plist-get (cadr presentation) :module) 'org))
      (should
       (eq (plist-get (cadr presentation) :occasion) 'navigation)))))

(ert-deftest emacsvox-org-owned-semantics-are-registered ()
  "Org roles and operation intent are part of the inspectable contract."
  (dolist
      (semantic
       '(org-content org-item org-paragraph org-agenda-entry org-table
                     org-capture org-edit-buffer org-export org-action))
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

(ert-deftest emacsvox-org-structure-feedback-preserves-order ()
  "Org structure movement speaks before its large-movement cue."
  (let ((ems--interactive-fn-name 'org-next-visible-heading)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-org-next-visible-heading-after))
    (should
     (equal
      (nreverse events)
      '(speak-line (icon large-movement))))))

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
          facts context events)
      (cl-letf
          (((symbol-function 'emacsvox-speak-line)
            (lambda ()
              (setq
               facts (copy-tree emacsvox-aural-submission-facts)
               context (copy-tree emacsvox-aural-submission-context))
              (push 'speak-line events)))
           ((symbol-function 'emacsvox-icon)
            (lambda (icon) (push (list 'icon icon) events))))
        (emacsvox--advice-org-next-visible-heading-after))
      (should (equal events '(speak-line)))
      (should
       (equal
        facts
        '(:role heading :level 2 :visibility expanded
          :events (focus-entered))))
      (should (eq (plist-get context :module) 'org))
      (should (eq (plist-get context :mode) 'org-mode))
      (should (eq (plist-get context :occasion) 'navigation)))))

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
            (((symbol-function 'emacsvox-speak-line)
              (lambda ()
                (let* ((text
                        (buffer-substring
                         (line-beginning-position) (line-end-position)))
                       (prepared (emacsvox-aural-prepare-text text)))
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

(ert-deftest emacsvox-org-paragraph-feedback-preserves-order ()
  "Org paragraph movement cues before speaking the paragraph."
  (let ((ems--interactive-fn-name 'org-forward-paragraph)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-paragraph)
               (lambda () (push 'speak-paragraph events))))
      (emacsvox--advice-org-forward-paragraph-after))
    (should
     (equal
      (nreverse events)
      '((icon paragraph) speak-paragraph)))))

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
  "Only matching interactive non-table cycling speaks the line."
  (let ((ems--interactive-fn-name 'org-shifttab)
        events)
    (cl-letf (((symbol-function 'org-at-table-p)
               (lambda (&rest _) nil))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events))))
      (emacsvox--advice-org-cycle-after)
      (emacsvox--advice-org-shifttab-after))
    (should (equal events '(speak-line)))))

(ert-deftest emacsvox-org-cycle-submits-explicit-visibility-change ()
  "Org cycling submits heading level, new visibility, event, and occasion."
  (with-temp-buffer
    (emacsvox-test--activate-org-mode #'org-mode)
    (insert "* Parent\nBody\n** Child\n")
    (goto-char (point-min))
    (org-fold-hide-subtree)
    (let ((ems--interactive-fn-name 'org-cycle)
          facts context)
      (cl-letf
          (((symbol-function 'emacsvox-speak-line)
            (lambda ()
              (setq
               facts (copy-tree emacsvox-aural-submission-facts)
               context (copy-tree emacsvox-aural-submission-context)))))
        (emacsvox--advice-org-cycle-after))
      (should
       (equal
        facts
        '(:role heading :level 1 :visibility folded
          :states (folded) :events (state-changed))))
      (should (eq (plist-get context :module) 'org))
      (should (eq (plist-get context :occasion) 'state-change)))))

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
  "Calendar expression results speak even outside an interactive call."
  (let ((ems--interactive-fn-name nil)
        (org-ans2 "Thursday")
        spoken)
    (cl-letf (((symbol-function 'tts-speak)
               (lambda (text) (setq spoken text))))
      (emacsvox--advice-org-eval-in-calendar-after))
    (should (equal spoken "Thursday"))))

(ert-deftest emacsvox-org-agenda-navigation-preserves-feedback-order ()
  "Agenda navigation cues before speaking the destination line."
  (let ((ems--interactive-fn-name 'org-agenda-next-line)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events))))
      (emacsvox--advice-org-agenda-previous-line-after)
      (emacsvox--advice-org-agenda-next-line-after))
    (should
     (equal
      (nreverse events)
      '((icon select-object) speak-line)))))

(ert-deftest emacsvox-org-table-movement-feedback-remains-unconditional ()
  "Table movement always reports the current cell."
  (let* ((ems--interactive-fn-name nil)
         events
         (emacsvox-org-table-after-movement-function
          (lambda () (push 'table-cell events))))
    (emacsvox--advice-org-table-next-field-after)
    (should (equal events '(table-cell)))))

(ert-deftest emacsvox-org-return-selects-table-or-line-feedback ()
  "Interactive Org return reports a table cell or the destination line."
  (let* ((ems--interactive-fn-name 'org-return)
         events
         at-table
         (emacsvox-org-table-after-movement-function
          (lambda () (push 'table-cell events))))
    (cl-letf (((symbol-function 'org-at-table-p)
               (lambda (&rest _) at-table))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (setq at-table t)
      (emacsvox--advice-org-return-after)
      (setq at-table nil
            ems--interactive-fn-name 'org-return)
      (emacsvox--advice-org-return-after))
    (should
     (equal
      (nreverse events)
      '(table-cell speak-line (icon select-object))))))

(ert-deftest emacsvox-org-editing-advice-is-directly-registered ()
  "Org editing advice uses native advice directly."
  (dolist (target emacsvox-test--org-editing-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-org-heading-edit-feedback-preserves-order ()
  "Org heading edits speak the line before the open cue."
  (let ((ems--interactive-fn-name 'org-insert-heading)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-org-insert-todo-heading-after)
      (emacsvox--advice-org-insert-heading-after))
    (should
     (equal
      (nreverse events)
      '(speak-line (icon open-object))))))

(ert-deftest emacsvox-org-subtree-feedback-is-target-aware ()
  "Only the matching subtree command speaks and cues its result."
  (let ((ems--interactive-fn-name 'org-paste-subtree)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-org-copy-subtree-after)
      (emacsvox--advice-org-paste-subtree-after))
    (should
     (equal
      (nreverse events)
      '(speak-line (icon yank-object))))))

(ert-deftest emacsvox-org-generic-end-of-line-delegates-in-org-mode ()
  "Interactive generic line movement invokes Org's line endpoint logic."
  (let ((ems--interactive-fn-name 'end-of-line)
        (major-mode 'org-mode)
        delegated)
    (cl-letf (((symbol-function 'org-end-of-line)
               (lambda (&rest _) (setq delegated t))))
      (emacsvox--advice-end-of-line-after))
    (should delegated)))

(ert-deftest emacsvox-org-item-navigation-preserves-feedback-order ()
  "Org item navigation speaks the line before its selection cue."
  (let ((ems--interactive-fn-name 'org-end-of-item)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-org-end-of-item-after))
    (should
     (equal
      (nreverse events)
      '(speak-line (icon select-object))))))

(ert-deftest emacsvox-org-source-edit-feedback-is-target-aware ()
  "Only the matching source edit command reports its window transition."
  (let ((ems--interactive-fn-name 'org-edit-src-exit)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events))))
      (emacsvox--advice-org-edit-src-abort-after)
      (emacsvox--advice-org-edit-src-exit-after))
    (should
     (equal
      (nreverse events)
      '((icon close-object) speak-line)))))

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
  (let ((ems--interactive-fn-name 'org-capture-goto-last-stored)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events))))
      (emacsvox--advice-org-capture-goto-last-stored-after))
    (should
     (equal
      (nreverse events)
      '((icon large-movement) speak-line)))))

(ert-deftest emacsvox-org-capture-target-feedback-remains-unconditional ()
  "Internally selected capture targets still cue and speak."
  (let ((ems--interactive-fn-name nil)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events))))
      (emacsvox--advice-org-capture-goto-target-after))
    (should
     (equal
      (nreverse events)
      '((icon large-movement) speak-line)))))

(ert-deftest emacsvox-org-capture-lifecycle-cues-remain-unconditional ()
  "Finalizing and cancelling captures always emit their lifecycle cues."
  (let ((ems--interactive-fn-name nil)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events))))
      (emacsvox--advice-org-capture-finalize-after)
      (emacsvox--advice-org-capture-kill-after))
    (should (equal (nreverse events) '(save-object close-object)))))

(ert-deftest emacsvox-org-markdown-export-feedback-is-target-aware ()
  "Interactive Markdown export cues completion and speaks the mode line."
  (let ((ems--interactive-fn-name 'org-md-export-as-markdown)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'mode-line events))))
      (emacsvox--advice-org-md-export-as-markdown-after))
    (should
     (equal
      (nreverse events)
      '((icon task-done) mode-line)))))

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
  "Export menu feedback selects choices from native advice arguments."
  (let ((entries '((?a "Alpha") (?b "Beta")))
        notified
        waited)
    (cl-letf (((symbol-function 'tts-notify)
               (lambda (text) (setq notified text)))
              ((symbol-function 'sit-for)
               (lambda (seconds) (setq waited seconds))))
      (emacsvox--advice-org-export--dispatch-action-before
       "Export" '(?a ?b) entries nil nil nil))
    (should (equal notified "a: Alpha\n\nb: Beta\n"))
    (should (= waited 5))))

(ert-deftest emacsvox-org-export-to-file-uses-explicit-file ()
  "Export completion reports the FILE argument directly."
  (let (events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'tts-notify)
               (lambda (text) (push (list 'notify text) events))))
      (emacsvox--advice-org-export-to-file-after
       'html "/tmp/report.html" nil nil nil nil nil nil))
    (should
     (equal
      (nreverse events)
      '((icon save-object) (notify "Wrote /tmp/report.html"))))))

(provide 'emacsvox-org-tests)
;;; emacsvox-org-tests.el ends here
