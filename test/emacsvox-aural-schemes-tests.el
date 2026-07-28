;;; emacsvox-aural-schemes-tests.el --- Contextual scheme tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Test scheme inheritance, contextual override layers, legacy personality
;; compatibility, and safe persistent user data.

;;; Code:

(require 'ert)
(require 'emacsvox-aural-schemes)

(defmacro emacsvox-test--with-isolated-schemes (&rest body)
  "Run BODY with isolated scheme and contextual override state."
  (declare (indent 0) (debug t))
  `(let ((emacsvox-aural-scheme-registry
          (make-hash-table :test #'eq))
         (emacsvox-aural-module-fragment-registry
          (make-hash-table :test #'eq))
         (emacsvox-aural-feature-fragment-registry
          (make-hash-table :test #'eq))
         (emacsvox-aural-feature-fragment-example-registry
          (make-hash-table :test #'equal))
         (emacsvox-aural-profile-registry
          (make-hash-table :test #'eq))
         (emacsvox-aural-voice-palette-registry
          (copy-hash-table emacsvox-aural-voice-palette-registry))
         (emacsvox-aural-enabled-feature-fragments nil)
         (emacsvox-aural-feature-fragment-order nil)
         (emacsvox-aural-voice-palette-override nil)
         (emacsvox-aural-user-rules nil)
         (emacsvox-aural-session-rules nil)
         (emacsvox-aural-buffer-rules nil)
         (emacsvox-aural-configuration-generation 0)
         (emacsvox-aural-configuration-changed-hook nil)
         (emacsvox-aural--current-rules-cache
          (make-hash-table :test #'equal))
         (emacsvox-aural--provider-cache
          (make-hash-table :test #'equal))
         (emacsvox-aural--current-rules-cache-hits 0)
         (emacsvox-aural--current-rules-cache-misses 0)
         (emacsvox-aural-active-scheme 'default)
         (emacsvox-aural-active-scheme-changed-hook nil)
         (emacsvox-aural-effective-resource-pack-changed-hook nil)
         (emacsvox-aural-feature-fragments-changed-hook nil)
         (emacsvox-aural-user-data-migrations nil))
     (emacsvox-aural--register-default-scheme)
     ,@body))

(ert-deftest emacsvox-aural-schemes-cache-rules-and-providers-by-generation ()
  "Stable configuration reuses rule snapshots and inherited providers."
  (emacsvox-test--with-isolated-schemes
    (emacsvox-aural-register-scheme
     (emacsvox-test--scheme
      'cached "Cached"
      (list (emacsvox-test--voice-rule 'cached-heading 'voice-bolden))
      :parent 'default
      :resource-pack 'chimes))
    (emacsvox-aural-select-scheme 'cached)
    (clrhash emacsvox-aural--current-rules-cache)
    (clrhash emacsvox-aural--provider-cache)
    (setq
     emacsvox-aural--current-rules-cache-hits 0
     emacsvox-aural--current-rules-cache-misses 0)
    (let* ((context '(:module org))
           (first (emacsvox-aural-current-rules context))
           (second (emacsvox-aural-current-rules context))
           (original
            (symbol-function
             'emacsvox-aural--compute-effective-scheme-provider))
           (provider-computations 0))
      (should (eq first second))
      (should
       (equal
        (emacsvox-aural-rule-cache-statistics)
        (list
         :generation emacsvox-aural-configuration-generation
         :hits 1 :misses 1 :entries 1)))
      (cl-letf
          (((symbol-function
             'emacsvox-aural--compute-effective-scheme-provider)
            (lambda (property id)
              (cl-incf provider-computations)
              (funcall original property id))))
        (should
         (eq
          (emacsvox-aural-effective-scheme-provider 'resource-pack)
          'chimes))
        (should
         (eq
          (emacsvox-aural-effective-scheme-provider 'resource-pack)
          'chimes)))
      (should (= provider-computations 1)))))

(ert-deftest emacsvox-aural-schemes-invalidate-caches-on-state-change ()
  "Configuration APIs invalidate snapshots, while raw layers key by value."
  (emacsvox-test--with-isolated-schemes
    (let* ((context '(:module org))
           (first (emacsvox-aural-current-rules context))
           (generation emacsvox-aural-configuration-generation))
      (setq
       emacsvox-aural-session-rules
       '((:id session-heading
          :match (:role heading)
          :render (:content (:voice bolden)))))
      (let ((second (emacsvox-aural-current-rules context)))
        (should-not (eq first second))
        (should
         (memq
          'session-heading
          (mapcar #'emacsvox-aural-rule-id second))))
      (emacsvox-aural-configuration-changed 'test-change)
      (should (> emacsvox-aural-configuration-generation generation))
      (should (zerop (hash-table-count
                      emacsvox-aural--current-rules-cache)))
      (should (zerop (hash-table-count emacsvox-aural--provider-cache))))))

(defun emacsvox-test--scheme (id summary rules &rest properties)
  "Return scheme data for ID, SUMMARY, RULES, and PROPERTIES."
  (append
   (list :schema-version 1 :id id :summary summary)
   properties
   (list :rules rules)))

(defun emacsvox-test--voice-rule (id voice &optional match)
  "Return rule ID selecting VOICE for MATCH or every heading."
  (list
   :id id
   :match (or match '(:role heading))
   :render (list :content (list :voice voice))))

(defun emacsvox-test--write-lisp-data (file data)
  "Write printed Lisp DATA to FILE."
  (with-temp-buffer
    (prin1 data (current-buffer))
    (insert "\n")
    (write-region (point-min) (point-max) file nil 'silent)))

(ert-deftest emacsvox-aural-schemes-inherit-rules-and-providers ()
  "A child inherits providers and its equally specific rule wins."
  (emacsvox-test--with-isolated-schemes
    (emacsvox-aural-register-scheme
     (emacsvox-test--scheme
      'parent "Parent"
      (list (emacsvox-test--voice-rule 'parent-heading 'voice-lighten))
      :resource-pack 'chimes
      :voice-palette 'acss-default))
    (emacsvox-aural-register-scheme
     (emacsvox-test--scheme
      'child "Child"
      (list (emacsvox-test--voice-rule 'child-heading 'voice-bolden))
      :parent 'parent))
    (emacsvox-aural-select-scheme 'child)
    (should
     (eq
      (emacsvox-aural-effective-scheme-provider 'resource-pack)
      'chimes))
    (should
     (eq
      (emacsvox-aural-effective-scheme-provider 'voice-palette)
      'acss-default))
    (let* ((plan
            (emacsvox-aural-resolve-active
             '(:role heading)
             '(:mode org-mode :occasion navigation)))
           (content (emacsvox-aural-render-plan-content plan)))
      (should
       (equal
        (emacsvox-aural-render-plan-matched-rules plan)
        '(parent-heading child-heading)))
      (should
       (eq
        (emacsvox-aural-content-style-voice content)
        'voice-bolden)))))

(ert-deftest emacsvox-aural-schemes-reject-invalid-inheritance ()
  "Unknown parents, cycles, and inherited duplicate rule IDs fail."
  (emacsvox-test--with-isolated-schemes
    (emacsvox-aural-register-scheme
     (emacsvox-test--scheme 'orphan "Orphan" () :parent 'missing))
    (should-error
     (emacsvox-aural-effective-scheme-rules 'orphan)
     :type 'emacsvox-aural-scheme-error))
  (emacsvox-test--with-isolated-schemes
    (emacsvox-aural-register-scheme
     (emacsvox-test--scheme 'first "First" () :parent 'second))
    (emacsvox-aural-register-scheme
     (emacsvox-test--scheme 'second "Second" () :parent 'first))
    (should-error
     (emacsvox-aural-effective-scheme-rules 'first)
     :type 'emacsvox-aural-scheme-error))
  (emacsvox-test--with-isolated-schemes
    (emacsvox-aural-register-scheme
     (emacsvox-test--scheme
      'parent "Parent"
      (list (emacsvox-test--voice-rule 'same-id 'voice-lighten))))
    (emacsvox-aural-register-scheme
     (emacsvox-test--scheme
      'child "Child"
      (list (emacsvox-test--voice-rule 'same-id 'voice-bolden))
      :parent 'parent))
    (should-error
     (emacsvox-aural-effective-scheme-rules 'child)
     :type 'emacsvox-aural-scheme-error)))

(ert-deftest emacsvox-aural-schemes-validate-provider-references ()
  "Registry validation rejects a scheme naming an unavailable provider."
  (emacsvox-test--with-isolated-schemes
    (let ((emacsvox-aural-resource-pack-registry
           (make-hash-table :test #'eq)))
      (emacsvox-aural-register-resource-pack
       'chimes :summary "Test chimes" :directory temporary-file-directory)
      (emacsvox-aural-register-scheme
       (emacsvox-test--scheme
        'broken-provider "Broken provider" ()
        :resource-pack 'not-registered))
      (should-error
       (emacsvox-aural-validate-scheme-registry)
       :type 'emacsvox-aural-scheme-error))))

(ert-deftest emacsvox-aural-schemes-reject-invalid-provider-before-selection ()
  "A failed provider check leaves the current active scheme unchanged."
  (emacsvox-test--with-isolated-schemes
    (let ((emacsvox-aural-resource-pack-registry
           (make-hash-table :test #'eq)))
      (emacsvox-aural-register-resource-pack
       'chimes :summary "Test chimes" :directory temporary-file-directory)
      (emacsvox-aural-register-scheme
       (emacsvox-test--scheme
        'broken-provider "Broken provider" ()
        :resource-pack 'not-registered))
      (should-error
       (emacsvox-aural-select-scheme 'broken-provider)
       :type 'emacsvox-aural-scheme-error)
      (should (eq emacsvox-aural-active-scheme 'default)))))

(ert-deftest emacsvox-aural-schemes-layer-contextual-overrides ()
  "Buffer rules override session, personal, scheme, and module rules."
  (emacsvox-test--with-isolated-schemes
    (emacsvox-aural-register-module-fragment
     'org
     (emacsvox-test--scheme
      'org-default "Org defaults"
      (list
       (emacsvox-test--voice-rule
        'module-heading 'voice-monotone
        '(:role heading :mode outline-mode)))))
    (emacsvox-aural-register-scheme
     (emacsvox-test--scheme
      'contextual "Contextual"
      (list (emacsvox-test--voice-rule 'scheme-heading 'voice-lighten))
      :parent 'default))
    (emacsvox-aural-select-scheme 'contextual)
    (setq
     emacsvox-aural-user-rules
     (list (emacsvox-test--voice-rule 'user-heading 'voice-smoothen))
     emacsvox-aural-session-rules
     (list (emacsvox-test--voice-rule 'session-heading 'voice-animate)))
    (with-temp-buffer
      (setq-local
       emacsvox-aural-buffer-rules
       (list (emacsvox-test--voice-rule 'buffer-heading 'voice-bolden)))
      (let* ((context
              '(:module org
                :mode org-mode
                :mode-lineage (org-mode outline-mode)
                :occasion navigation))
             (plan
              (emacsvox-aural-resolve-active '(:role heading) context))
             (content (emacsvox-aural-render-plan-content plan)))
        (should
         (equal
          (emacsvox-aural-render-plan-matched-rules plan)
          '(module-heading scheme-heading user-heading
            session-heading buffer-heading)))
        (should
         (eq
          (emacsvox-aural-content-style-voice content)
          'voice-bolden))
        (should
         (eq
          (alist-get
           'voice
           (emacsvox-aural-content-style-provenance content))
          'buffer-heading))))))

(ert-deftest emacsvox-aural-schemes-compose-ordered-feature-fragments ()
  "Enabled fragments add to a scheme before stronger personal overrides."
  (emacsvox-test--with-isolated-schemes
    (emacsvox-aural-register-scheme
     (emacsvox-test--scheme
      'spoken "Spoken"
      '((:id scheme-heading
         :match (:role heading)
         :render
         (:before
          ((:id scheme-label :kind speech :text "Heading"))
          :content (:voice voice-lighten))))
      :parent 'default))
    (emacsvox-aural-register-feature-fragment
     (emacsvox-test--scheme
      'with-icon "Add a heading cue"
      '((:id fragment-heading-icon
         :match (:role heading)
         :render
         (:before
          (:append
           ((:id heading-icon :kind cue :cue section)))))))
     :built-in t
     :source "test")
    (emacsvox-aural-register-feature-fragment
     (emacsvox-test--scheme
      'with-prefix "Add another spoken prefix"
      '((:id fragment-heading-prefix
         :match (:role heading)
         :render
         (:before
          (:append
           ((:id extra-label :kind speech :text "Level")))))))
     :built-in t
     :source "test")
    (emacsvox-aural-select-scheme 'spoken)
    (emacsvox-aural-set-enabled-feature-fragments
     '(with-icon with-prefix))
    (setq
     emacsvox-aural-user-rules
     (list
      (emacsvox-test--voice-rule
       'personal-heading 'voice-bolden)))
    (let* ((plan
            (emacsvox-aural-resolve-active
             '(:role heading)
             '(:module org :mode org-mode :occasion navigation)))
           (content (emacsvox-aural-render-plan-content plan)))
      (should
       (equal
        (emacsvox-aural-render-plan-matched-rules plan)
        '(scheme-heading fragment-heading-icon
          fragment-heading-prefix personal-heading)))
      (should
       (equal
        (mapcar
         #'emacsvox-aural-action-id
         (emacsvox-aural-render-plan-before plan))
        '(scheme-label heading-icon extra-label)))
      (should
       (eq
        (emacsvox-aural-content-style-voice content)
        'voice-bolden)))))

(ert-deftest emacsvox-aural-schemes-order-feature-fragment-scalars ()
  "A later enabled fragment is stronger within the fragment origin."
  (emacsvox-test--with-isolated-schemes
    (dolist
        (entry
         '((first-fragment voice-lighten)
           (second-fragment voice-bolden)))
      (emacsvox-aural-register-feature-fragment
       (emacsvox-test--scheme
        (car entry)
        (symbol-name (car entry))
        (list
         (emacsvox-test--voice-rule
          (intern (format "%s-rule" (car entry)))
          (cadr entry))))
       :built-in t))
    (emacsvox-aural-set-enabled-feature-fragments
     '(first-fragment second-fragment))
    (let ((content
           (emacsvox-aural-render-plan-content
            (emacsvox-aural-resolve-active
             '(:role heading)
             '(:mode org-mode :occasion navigation)))))
      (should
       (eq
        (emacsvox-aural-content-style-voice content)
        'voice-bolden)))))

(ert-deftest emacsvox-aural-schemes-validate-feature-fragment-contract ()
  "Fragments reject providers, inheritance, unknown IDs, and duplicate enabling."
  (emacsvox-test--with-isolated-schemes
    (dolist
        (data
         (list
          (emacsvox-test--scheme
           'inheriting-fragment "Invalid parent" () :parent 'default)
          (emacsvox-test--scheme
           'provider-fragment "Invalid provider" ()
           :resource-pack 'chimes)))
      (should-error
       (emacsvox-aural-register-feature-fragment data)
       :type 'emacsvox-aural-scheme-error))
    (emacsvox-aural-register-feature-fragment
     (emacsvox-test--scheme 'valid-fragment "Valid" ())
     :built-in t)
    (should
     (eq
      (emacsvox-aural-feature-fragment-entry-collection
       (emacsvox-aural-feature-fragment-entry 'valid-fragment))
      'general))
    (let* ((entry
            (emacsvox-aural-feature-fragment-entry 'valid-fragment))
           (legacy-entry
            (record
             'emacsvox-aural-feature-fragment-entry
             (emacsvox-aural-feature-fragment-entry-id entry)
             (emacsvox-aural-feature-fragment-entry-data entry)
             (emacsvox-aural-feature-fragment-entry-compiled entry)
             (emacsvox-aural-feature-fragment-entry-built-in entry)
             (emacsvox-aural-feature-fragment-entry-source entry))))
      (should
       (eq
        (emacsvox-aural-feature-fragment-collection legacy-entry)
        'general)))
    (should-error
     (emacsvox-aural-register-feature-fragment
      (emacsvox-test--scheme 'bad-collection "Invalid collection" ())
      :collection "not-a-symbol")
     :type 'emacsvox-aural-rule-error)
    (emacsvox-aural-set-enabled-feature-fragments '(valid-fragment))
    (should-error
     (emacsvox-aural-set-enabled-feature-fragments '(missing-fragment))
     :type 'emacsvox-aural-scheme-error)
    (should-error
     (emacsvox-aural-set-enabled-feature-fragments
      '(valid-fragment valid-fragment))
     :type 'emacsvox-aural-scheme-error)
    (should
     (equal
      emacsvox-aural-enabled-feature-fragments
      '(valid-fragment)))))

(ert-deftest emacsvox-aural-schemes-validate-fragment-preview-examples ()
  "Provider examples are data-only, rule-specific, and idempotent."
  (emacsvox-test--with-isolated-schemes
    (emacsvox-aural-register-feature-fragment
     '(:schema-version 1
       :id heading-label
       :summary "Label headings"
       :rules
       ((:id heading-label-rule
         :match (:role heading :module org :occasion navigation)
         :render
         (:before
          ((:id heading-label-action :kind speech :text "Heading"))))
        (:id parked-heading-rule
         :enabled nil
         :match (:role heading :module org :occasion navigation)
         :render (:content (:voice bolden)))))
     :built-in t :collection 'org)
    (let* ((arguments
            '(:rule heading-label-rule
              :summary "An Org heading"
              :facts (:role heading :content "Roadmap")
              :context
              (:module org :mode org-mode :occasion navigation)
              :source "test"))
           (first
            (apply
             #'emacsvox-aural-register-feature-fragment-example
             'heading-label 'org-heading arguments))
           (second
            (apply
             #'emacsvox-aural-register-feature-fragment-example
             'heading-label 'org-heading arguments)))
      (should (eq first second))
      (should
       (eq
        (emacsvox-aural-feature-fragment-example
         'heading-label 'org-heading)
        first))
      (should
       (equal
        (emacsvox-aural-feature-fragment-examples 'heading-label)
        (list first))))
    (should-error
     (emacsvox-aural-register-feature-fragment-example
      'heading-label 'not-a-heading
      :rule 'heading-label-rule
      :summary "Wrong semantic context"
     :facts '(:role message :content "Mail")
     :context '(:module org :mode org-mode :occasion navigation))
     :type 'emacsvox-aural-rule-error)
    (should-error
     (emacsvox-aural-register-feature-fragment-example
      'heading-label 'parked-heading
      :rule 'parked-heading-rule
      :summary "Disabled example"
      :facts '(:role heading :content "Roadmap")
      :context '(:module org :mode org-mode :occasion navigation))
     :type 'emacsvox-aural-rule-error)))

(ert-deftest emacsvox-aural-schemes-preserve-legacy-personality-by-default ()
  "An unmatched explicit or face-derived legacy personality is retained."
  (emacsvox-test--with-isolated-schemes
    (let* ((plan
            (emacsvox-aural-resolve-active
             '(:content "legacy")
             '(:mode text-mode
               :occasion continuous
               :legacy-personality voice-comment
               :legacy-source face)))
           (content (emacsvox-aural-render-plan-content plan)))
      (should
       (eq
        (emacsvox-aural-content-style-voice content)
        'voice-comment))
      (should
       (eq
        (alist-get
         'voice
         (emacsvox-aural-content-style-provenance content))
        'face)))
    (let* ((style '(acss . generated))
           (plan
            (emacsvox-aural-resolve-active
             '(:content "legacy")
             (list
              :mode 'text-mode
              :occasion 'continuous
              :legacy-personality style)))
           (content (emacsvox-aural-render-plan-content plan)))
      (should
       (equal
        (emacsvox-aural-content-style-voice content)
        style)))))

(ert-deftest emacsvox-aural-schemes-reject-cross-layer-rule-id-reuse ()
  "Rule provenance stays unambiguous across contextual origin layers."
  (emacsvox-test--with-isolated-schemes
    (emacsvox-aural-register-scheme
     (emacsvox-test--scheme
      'named "Named"
      (list (emacsvox-test--voice-rule 'same 'voice-lighten))
      :parent 'default))
    (emacsvox-aural-select-scheme 'named)
    (setq
     emacsvox-aural-user-rules
     (list (emacsvox-test--voice-rule 'same 'voice-bolden)))
    (should-error
     (emacsvox-aural-current-rules
      '(:mode text-mode :occasion continuous))
     :type 'emacsvox-aural-scheme-error)))

(ert-deftest emacsvox-aural-schemes-remap-or-suppress-legacy-personality ()
  "Rules can replace or explicitly clear a legacy personality hint."
  (emacsvox-test--with-isolated-schemes
    (setq
     emacsvox-aural-user-rules
     (list
      (emacsvox-test--voice-rule
       'remap-comment
       'voice-annotate
       '(:legacy-personality voice-comment))))
    (let ((content
           (emacsvox-aural-render-plan-content
            (emacsvox-aural-resolve-active
             '(:content "legacy")
             '(:mode text-mode
               :occasion continuous
               :legacy-personality voice-comment)))))
      (should
       (eq
        (emacsvox-aural-content-style-voice content)
        'voice-annotate)))
    (setq
     emacsvox-aural-user-rules
     (list
      (emacsvox-test--voice-rule
       'suppress-comment nil
       '(:legacy-personality voice-comment))))
    (let ((content
           (emacsvox-aural-render-plan-content
            (emacsvox-aural-resolve-active
             '(:content "legacy")
             '(:mode text-mode
               :occasion continuous
               :legacy-personality voice-comment)))))
      (should-not (emacsvox-aural-content-style-voice content))
      (should
       (eq
        (alist-get
         'voice
         (emacsvox-aural-content-style-provenance content))
        'suppress-comment)))))

(ert-deftest emacsvox-aural-schemes-semantic-rule-beats-legacy-hint-rule ()
  "Registered semantic identity is more specific than presentation history."
  (emacsvox-test--with-isolated-schemes
    (setq
     emacsvox-aural-user-rules
     (list
      (emacsvox-test--voice-rule
       'legacy-heading 'voice-lighten
       '(:legacy-personality voice-comment))
      (emacsvox-test--voice-rule
       'semantic-heading 'voice-bolden
       '(:role heading))))
    (let ((content
           (emacsvox-aural-render-plan-content
            (emacsvox-aural-resolve-active
             '(:role heading)
             '(:mode org-mode
               :occasion navigation
               :legacy-personality voice-comment)))))
      (should
       (eq
        (emacsvox-aural-content-style-voice content)
        'voice-bolden)))))

(ert-deftest emacsvox-aural-schemes-customize-one-legacy-cue ()
  "One old icon can be remapped per mode or suppressed everywhere."
  (emacsvox-test--with-isolated-schemes
    (setq
     emacsvox-aural-user-rules
     (list
      (emacsvox-aural-make-legacy-cue-rule
       'org-item 'item 'open-object '(:mode org-mode))))
    (let ((org-plan
           (emacsvox-aural-resolve-legacy-icon
            'item
            '(:mode org-mode :occasion notification)))
          (text-plan
           (emacsvox-aural-resolve-legacy-icon
            'item
            '(:mode text-mode :occasion notification))))
      (should
       (equal
        (mapcar
         #'emacsvox-aural-action-cue
         (emacsvox-aural-render-plan-before org-plan))
        '(open-object)))
      (should
       (equal
        (mapcar
         #'emacsvox-aural-action-cue
         (emacsvox-aural-render-plan-before text-plan))
        '(item))))
    (setq
     emacsvox-aural-user-rules
     (list
      (emacsvox-aural-make-legacy-cue-rule
       'silence-item 'item nil)))
    (should-not
     (emacsvox-aural-render-plan-before
      (emacsvox-aural-resolve-legacy-icon
       'item
       '(:mode text-mode :occasion notification))))))

(ert-deftest emacsvox-aural-schemes-build-legacy-personality-rule ()
  "Compatibility helper creates scoped voice replacement and suppression."
  (emacsvox-test--with-isolated-schemes
    (setq
     emacsvox-aural-user-rules
     (list
      (emacsvox-aural-make-legacy-personality-rule
       'org-comment 'voice-comment 'voice-bolden '(:mode org-mode))))
    (let ((org-content
           (emacsvox-aural-render-plan-content
            (emacsvox-aural-resolve-active
             '(:content "comment")
             '(:mode org-mode
               :occasion continuous
               :legacy-personality voice-comment))))
          (text-content
           (emacsvox-aural-render-plan-content
            (emacsvox-aural-resolve-active
             '(:content "comment")
             '(:mode text-mode
               :occasion continuous
               :legacy-personality voice-comment)))))
      (should
       (eq
        (emacsvox-aural-content-style-voice org-content)
        'voice-bolden))
      (should
       (eq
        (emacsvox-aural-content-style-voice text-content)
        'voice-comment)))))

(ert-deftest emacsvox-aural-schemes-save-read-and-back-up-data ()
  "Personal data is mode 0600, round-trips, and preserves one backup."
  (emacsvox-test--with-isolated-schemes
    (let* ((directory (make-temp-file "emacsvox-schemes-" t))
           (file (expand-file-name "aural-schemes.el" directory)))
      (unwind-protect
          (progn
            (emacsvox-aural-register-scheme
             (emacsvox-test--scheme
              'personal "Personal"
              (list
               (emacsvox-test--voice-rule
                'personal-heading 'voice-lighten))
              :parent 'default))
            (setq
             emacsvox-aural-user-rules
             (list
              (emacsvox-test--voice-rule
               'user-heading 'voice-smoothen)))
            (emacsvox-aural-register-feature-fragment
             (emacsvox-test--scheme
              'personal-fragment "Personal fragment"
              (list
               (emacsvox-test--voice-rule
                'fragment-heading 'voice-annotate))))
            (emacsvox-aural-set-enabled-feature-fragments
             '(personal-fragment))
            (emacsvox-aural-save-user-data file)
            (let ((first (emacsvox-aural-read-user-data file)))
              (should (= (file-modes file) #o600))
              (setq
               emacsvox-aural-user-rules
               (list
                (emacsvox-test--voice-rule
                 'user-heading 'voice-bolden)))
              (emacsvox-aural-save-user-data file)
              (should (file-exists-p (concat file "~")))
              (should
               (equal
                (emacsvox-aural-read-user-data (concat file "~"))
                first)))
            (let ((emacsvox-aural-scheme-registry
                   (make-hash-table :test #'eq))
                  (emacsvox-aural-feature-fragment-registry
                   (make-hash-table :test #'eq))
                  (emacsvox-aural-enabled-feature-fragments nil)
                  (emacsvox-aural-user-rules nil))
              (emacsvox-aural--register-default-scheme)
              (emacsvox-aural-load-user-data file)
              (should (emacsvox-aural-scheme-entry 'personal))
              (should
               (emacsvox-aural-feature-fragment-entry
                'personal-fragment))
              (should
               (equal
                emacsvox-aural-enabled-feature-fragments
                '(personal-fragment)))
              (should
               (equal
                (plist-get
                 (plist-get
                  (car emacsvox-aural-user-rules)
                  :render)
                 :content)
                '(:voice voice-bolden)))))
        (delete-directory directory t)))))

(ert-deftest emacsvox-aural-schemes-reader-never-evaluates-data ()
  "Reader evaluation and trailing forms are rejected."
  (emacsvox-test--with-isolated-schemes
    (let* ((directory (make-temp-file "emacsvox-schemes-" t))
           (unsafe (expand-file-name "unsafe.el" directory))
           (trailing (expand-file-name "trailing.el" directory))
           (emacsvox-test--reader-sentinel nil))
      (unwind-protect
          (progn
            (with-temp-buffer
              (insert
               "#.(setq emacsvox-test--reader-sentinel 'executed)\n")
              (write-region
               (point-min) (point-max) unsafe nil 'silent))
            (should-error (emacsvox-aural-read-user-data unsafe))
            (should-not emacsvox-test--reader-sentinel)
            (with-temp-buffer
              (insert
               "(:schema-version 1 :schemes nil :user-rules nil)\n"
               "(:second-form t)\n")
              (write-region
               (point-min) (point-max) trailing nil 'silent))
            (should-error
             (emacsvox-aural-read-user-data trailing)
             :type 'emacsvox-aural-scheme-error))
        (delete-directory directory t)))))

(ert-deftest emacsvox-aural-schemes-reload-notifies-provider-change ()
  "Reloading an active definition reconciles its changed sound provider."
  (emacsvox-test--with-isolated-schemes
    (let* ((directory (make-temp-file "emacsvox-provider-reload-" t))
           (file (expand-file-name "aural.el" directory))
           changes)
      (unwind-protect
          (progn
            (emacsvox-aural-register-scheme
             (emacsvox-test--scheme
              'work "Old work scheme" nil :parent 'default))
            (emacsvox-aural-select-scheme 'work)
            (add-hook
             'emacsvox-aural-effective-resource-pack-changed-hook
             (lambda (old new) (push (list old new) changes)))
            (emacsvox-test--write-lisp-data
             file
             (list
              :schema-version emacsvox-aural-user-data-schema-version
              :schemes
              (list
               (emacsvox-test--scheme
                'work "New work scheme" nil
                :parent 'default :resource-pack '3d))
              :feature-fragments nil
              :enabled-feature-fragments nil
              :voice-palettes nil
              :profiles nil
              :user-rules nil))
            (emacsvox-aural-load-user-data file)
            (should
             (equal
              (emacsvox-aural-effective-scheme-provider 'resource-pack)
              '3d))
            (should (equal changes '((chimes 3d)))))
        (delete-directory directory t)))))

(ert-deftest emacsvox-aural-schemes-migrate-versioned-user-data ()
  "Registered migration hooks advance old data to the current schema."
  (emacsvox-test--with-isolated-schemes
    (let ((emacsvox-aural-user-data-migrations
           (list
            (cons
             0
             (lambda (data)
               (plist-put data :schema-version 1))))))
      (should
       (equal
        (emacsvox-aural-migrate-user-data
         '(:schema-version 0 :schemes nil :user-rules nil))
        '(:schema-version 5
          :schemes nil
          :user-rules nil
          :feature-fragments nil
          :enabled-feature-fragments nil
          :profiles nil
          :voice-palettes nil
          :feature-fragment-order nil))))
    (let ((migrated
           (emacsvox-aural-migrate-user-data
            '(:schema-version 4
              :schemes nil
              :feature-fragments
              ((:schema-version 1
                :id personal-a
                :summary "A"
                :rules nil)
               (:schema-version 1
                :id personal-b
                :summary "B"
                :rules nil))
              :enabled-feature-fragments (personal-b)
              :voice-palettes nil
              :profiles nil
              :user-rules nil))))
      (should (eq (plist-get migrated :schema-version) 5))
      (should
       (equal
        (plist-get migrated :feature-fragment-order)
        '(personal-b personal-a))))
    (should-error
     (emacsvox-aural-migrate-user-data
      '(:schema-version 0 :schemes nil :user-rules nil))
     :type 'emacsvox-aural-scheme-error)))

(ert-deftest emacsvox-aural-schemes-persist-personal-voice-palettes ()
  "Personal voice palettes round-trip as versioned non-evaluated data."
  (emacsvox-test--with-isolated-schemes
    (let* ((directory (make-temp-file "emacsvox-voice-palettes-" t))
           (file (expand-file-name "aural-schemes.el" directory))
           (palette
            '(:schema-version 1
              :id reading
              :summary "Reading voices"
              :parent acss-default
              :entries
              ((heading
                :style
                (:family paul :average-pitch 6 :pitch-range 4
                 :stress nil :richness 7))))))
      (unwind-protect
          (progn
            (emacsvox-aural-register-voice-palette-data palette)
            (emacsvox-aural-save-user-data file)
            (let ((saved (emacsvox-aural-read-user-data file)))
              (should (equal (plist-get saved :voice-palettes)
                             (list palette))))
            (let ((emacsvox-aural-voice-palette-registry
                   (emacsvox-aural--built-in-voice-palette-registry)))
              (emacsvox-aural-load-user-data file)
              (should
               (equal
                (emacsvox-aural-voice 'heading 'reading)
                '(:family paul :average-pitch 6 :pitch-range 4
                  :stress nil :richness 7)))))
        (delete-directory directory t)))))

(ert-deftest emacsvox-aural-schemes-palette-load-is-atomic ()
  "Invalid palette inheritance leaves the live palette registry unchanged."
  (emacsvox-test--with-isolated-schemes
    (emacsvox-aural-register-voice-palette-data
     '(:schema-version 1
       :id working-palette
       :summary "Working palette"
       :entries
       ((heading :personality voice-bolden))))
    (let* ((directory (make-temp-file "emacsvox-bad-palette-" t))
           (file (expand-file-name "invalid.el" directory))
           (before emacsvox-aural-voice-palette-registry))
      (unwind-protect
          (progn
            (emacsvox-test--write-lisp-data
             file
             '(:schema-version 4
               :schemes nil
               :feature-fragments nil
               :enabled-feature-fragments nil
               :voice-palettes
               ((:schema-version 1
                 :id broken
                 :summary "Broken"
                 :parent missing
                 :entries nil))
               :profiles nil
               :user-rules nil))
            (should-error
             (emacsvox-aural-load-user-data file)
             :type 'emacsvox-aural-resource-error)
            (should (eq emacsvox-aural-voice-palette-registry before))
            (should
             (emacsvox-aural-voice-palette 'working-palette))
            (should-not (emacsvox-aural-voice-palette 'broken)))
        (delete-directory directory t)))))

(ert-deftest emacsvox-aural-schemes-load-is-atomic ()
  "Invalid replacement data leaves live personal schemes and rules intact."
  (emacsvox-test--with-isolated-schemes
    (emacsvox-aural-register-scheme
     (emacsvox-test--scheme 'working "Working" () :parent 'default))
    (setq
     emacsvox-aural-user-rules
     (list (emacsvox-test--voice-rule 'working-rule 'voice-lighten)))
    (let* ((directory (make-temp-file "emacsvox-schemes-" t))
           (file (expand-file-name "invalid.el" directory))
           (before-registry emacsvox-aural-scheme-registry)
           (before-rules emacsvox-aural-user-rules))
      (unwind-protect
          (progn
            (emacsvox-test--write-lisp-data
             file
             (list
              :schema-version 1
              :schemes
              (list
               (emacsvox-test--scheme
                'broken "Broken" () :parent 'missing))
              :user-rules nil))
            (should-error
             (emacsvox-aural-load-user-data file)
             :type 'emacsvox-aural-scheme-error)
            (should
             (eq emacsvox-aural-scheme-registry before-registry))
            (should (eq emacsvox-aural-user-rules before-rules))
            (should (emacsvox-aural-scheme-entry 'working))
            (should-not (emacsvox-aural-scheme-entry 'broken)))
        (delete-directory directory t)))))

(ert-deftest emacsvox-aural-schemes-protect-built-ins ()
  "Personal data cannot replace a built-in scheme identifier."
  (emacsvox-test--with-isolated-schemes
    (let* ((directory (make-temp-file "emacsvox-schemes-" t))
           (file (expand-file-name "collision.el" directory)))
      (unwind-protect
          (progn
            (emacsvox-test--write-lisp-data
             file
             (list
              :schema-version 1
              :schemes
              (list
               (emacsvox-test--scheme 'default "Replacement" ()))
              :user-rules nil))
            (should-error
             (emacsvox-aural-load-user-data file)
             :type 'emacsvox-aural-scheme-error))
        (delete-directory directory t)))))

(ert-deftest emacsvox-aural-schemes-selection-runs-change-hook ()
  "Selecting a valid scheme notifies provider and editor integrations."
  (emacsvox-test--with-isolated-schemes
    (let (selected)
      (emacsvox-aural-register-scheme
       (emacsvox-test--scheme 'quiet "Quiet" () :parent 'default))
      (add-hook
       'emacsvox-aural-active-scheme-changed-hook
       (lambda () (setq selected emacsvox-aural-active-scheme)))
      (emacsvox-aural-select-scheme 'quiet)
      (should (eq selected 'quiet)))))

(provide 'emacsvox-aural-schemes-tests)
;;; emacsvox-aural-schemes-tests.el ends here
