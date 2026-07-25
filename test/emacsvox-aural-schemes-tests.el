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
         (emacsvox-aural-user-rules nil)
         (emacsvox-aural-session-rules nil)
         (emacsvox-aural-buffer-rules nil)
         (emacsvox-aural-active-scheme 'default)
         (emacsvox-aural-active-scheme-changed-hook nil)
         (emacsvox-aural-user-data-migrations nil))
     (emacsvox-aural--register-default-scheme)
     ,@body))

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
                  (emacsvox-aural-user-rules nil))
              (emacsvox-aural--register-default-scheme)
              (emacsvox-aural-load-user-data file)
              (should (emacsvox-aural-scheme-entry 'personal))
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
        '(:schema-version 1 :schemes nil :user-rules nil))))
    (should-error
     (emacsvox-aural-migrate-user-data
      '(:schema-version 0 :schemes nil :user-rules nil))
     :type 'emacsvox-aural-scheme-error)))

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
