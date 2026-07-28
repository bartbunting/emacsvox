;;; emacsvox-aural-tests.el --- Semantic aural registry tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Test the device-independent vocabulary before rule or playback integration.

;;; Code:

(require 'ert)
(require 'emacsvox-aural)
(require 'emacsvox-aural-provider-workflows)

(defmacro emacsvox-test--with-empty-aural-registries (&rest body)
  "Run BODY with isolated empty semantic and occasion registries."
  (declare (indent 0) (debug t))
  `(let ((emacsvox-aural-semantic-registry (make-hash-table :test #'eq))
         (emacsvox-aural-occasion-registry (make-hash-table :test #'eq))
         (emacsvox-aural-semantic-alias-registry
          (make-hash-table :test #'eq)))
     ,@body))

(ert-deftest emacsvox-aural-builtins-validate ()
  "The initial core semantics and occasions form a valid registry."
  (should (emacsvox-aural-validate-registry))
  (dolist
      (id
       '(heading level folded focus-entered state-changed object-changed
         product-identity activity-ended selection-cleared game-over))
    (should (emacsvox-aural-semantic id)))
  (dolist
      (id
       '(navigation continuous state-change edit inspection notification))
    (should (emacsvox-aural-occasion id))))

(ert-deftest emacsvox-aural-workflow-semantics-are-owned-and-valid ()
  "Cross-module semantics are available before integrations load."
  (should (emacsvox-aural-validate-registry))
  (dolist
      (id
       '(message field field-kind unread flagged has-attachments
         refresh-completed refresh-failed code-construct syntax-role
         boundary-entered candidate selected accepted completion-index
         agent-session agent-response agent-thought agent-tool
         permission-request processing processing-started
         processing-completed processing-failed))
    (should (emacsvox-aural-semantic id)))
  (should
   (eq
    (emacsvox-aural-semantic-owner
     (emacsvox-aural-semantic 'agent-response))
    'agent-shell))
  (should
   (eq
    (emacsvox-aural-semantic-owner
     (emacsvox-aural-semantic 'candidate))
    'core)))

(ert-deftest emacsvox-aural-mail-content-supports-state-change ()
  "Structured message content remains valid while its state changes."
  (dolist (id '(field unread flagged has-attachments))
    (should
     (memq
      'state-change
      (emacsvox-aural-semantic-occasions
       (emacsvox-aural-semantic id))))))

(ert-deftest emacsvox-aural-registers-complete-semantic-metadata ()
  "A valid semantic record retains its documented metadata."
  (emacsvox-test--with-empty-aural-registries
    (emacsvox-aural-register-occasion
     'navigation :summary "Focus moved")
    (let ((record
           (emacsvox-aural-register-semantic
            'heading
            :kind 'role
            :summary "A structural heading"
            :owner 'org
            :occasions '(navigation)
            :phases '(before content after)
            :usage "Attach to the heading text.")))
      (should (eq (emacsvox-aural-semantic 'heading) record))
      (should (eq (emacsvox-aural-semantic-kind record) 'role))
      (should (eq (emacsvox-aural-semantic-owner record) 'org))
      (should
       (equal
        (emacsvox-aural-semantic-phases record)
        '(before content after)))
      (should (emacsvox-aural-validate-registry)))))

(ert-deftest emacsvox-aural-rejects-duplicate-registration ()
  "Two owners cannot silently assign different meaning to one identifier."
  (emacsvox-test--with-empty-aural-registries
    (emacsvox-aural-register-semantic
     'heading :kind 'role :summary "A heading")
    (should-error
     (emacsvox-aural-register-semantic
      'heading :kind 'role :summary "Another heading")
     :type 'emacsvox-aural-registration-error)))

(ert-deftest emacsvox-aural-rejects-incomplete-or-invalid-metadata ()
  "Identifiers, kinds, summaries, owners, and attribute fields are checked."
  (emacsvox-test--with-empty-aural-registries
    (should-error
     (emacsvox-aural-register-semantic
      :heading :kind 'role :summary "Heading")
     :type 'emacsvox-aural-registration-error)
    (should-error
     (emacsvox-aural-register-semantic
      'heading :kind 'unknown :summary "Heading")
     :type 'emacsvox-aural-registration-error)
    (should-error
     (emacsvox-aural-register-semantic
      'heading :kind 'role :summary "")
     :type 'emacsvox-aural-registration-error)
    (should-error
     (emacsvox-aural-register-semantic
      'heading :kind 'role :summary "Heading" :value-type 'integer)
     :type 'emacsvox-aural-registration-error)))

(ert-deftest emacsvox-aural-validates-occasion-references ()
  "Semantic entries cannot name presentation occasions that do not exist."
  (emacsvox-test--with-empty-aural-registries
    (emacsvox-aural-register-semantic
     'heading
     :kind 'role
     :summary "A heading"
     :occasions '(navigation))
    (should-error
     (emacsvox-aural-validate-registry)
     :type 'emacsvox-aural-registration-error)
    (emacsvox-aural-register-occasion
     'navigation :summary "Focus moved")
    (should (emacsvox-aural-validate-registry))))

(ert-deftest emacsvox-aural-validates-fallback-existence ()
  "A semantic fallback must name another registered semantic."
  (emacsvox-test--with-empty-aural-registries
    (emacsvox-aural-register-semantic
     'specific
     :kind 'event
     :summary "Specific event"
     :fallback 'general)
    (should-error
     (emacsvox-aural-validate-registry)
     :type 'emacsvox-aural-registration-error)
    (emacsvox-aural-register-semantic
     'general :kind 'event :summary "General event")
    (should (emacsvox-aural-validate-registry))))

(ert-deftest emacsvox-aural-rejects-fallback-cycles ()
  "Semantic fallback chains cannot contain cycles."
  (emacsvox-test--with-empty-aural-registries
    (emacsvox-aural-register-semantic
     'first :kind 'event :summary "First" :fallback 'second)
    (emacsvox-aural-register-semantic
     'second :kind 'event :summary "Second" :fallback 'first)
    (should-error
     (emacsvox-aural-validate-registry)
     :type 'emacsvox-aural-registration-error)))

(ert-deftest emacsvox-aural-registers-operational-contracts ()
  "Roles and semantic restrictions retain and validate typed references."
  (emacsvox-test--with-empty-aural-registries
    (emacsvox-aural-register-occasion
     'navigation :summary "Focus moved")
    (emacsvox-aural-register-semantic
     'importance
     :kind 'attribute
     :summary "Importance"
     :value-type 'symbol
     :allowed-values '(low high)
     :roles '(article)
     :occasions '(navigation)
     :phases '(content))
    (emacsvox-aural-register-semantic
     'article
     :kind 'role
     :summary "Article"
     :attributes '(importance)
     :occasions '(navigation)
     :phases '(content))
    (should (emacsvox-aural-validate-registry))
    (should
     (equal
      (emacsvox-aural-semantic-roles
       (emacsvox-aural-semantic 'importance))
      '(article)))
    (setf
     (emacsvox-aural-semantic-attributes
      (emacsvox-aural-semantic 'article))
     '(missing))
    (should-error
     (emacsvox-aural-validate-registry)
     :type 'emacsvox-aural-registration-error)))

(ert-deftest emacsvox-aural-aliases-are-versioned-and-diagnostic ()
  "Stable aliases resolve canonically and explain their deprecation."
  (should
   (eq (emacsvox-aural-canonical-semantic-id 'collapsed) 'folded))
  (should
   (string-match-p
    "deprecated since contract version 1; use folded"
    (emacsvox-aural-semantic-alias-diagnostic 'collapsed))))

(ert-deftest emacsvox-aural-rejects-cross-kind-fallbacks ()
  "A fallback remains within one semantic kind."
  (emacsvox-test--with-empty-aural-registries
    (emacsvox-aural-register-semantic
     'object :kind 'role :summary "Object")
    (emacsvox-aural-register-semantic
     'specific :kind 'event :summary "Specific" :fallback 'object)
    (should-error
     (emacsvox-aural-validate-registry)
     :type 'emacsvox-aural-registration-error)))

(ert-deftest emacsvox-aural-completion-and-description-are-deterministic ()
  "Registry discovery is sorted and describes intent, owner, and kind."
  (emacsvox-test--with-empty-aural-registries
    (emacsvox-aural-register-semantic
     'zebra :kind 'event :summary "Last" :owner 'example)
    (emacsvox-aural-register-semantic
     'alpha :kind 'role :summary "First")
    (should
     (equal
      (emacsvox-aural-semantic-candidates)
      '("alpha" "zebra")))
    (should
     (equal
      (emacsvox-aural-semantic-description 'zebra)
      "zebra (event, owner example): Last"))))

(ert-deftest emacsvox-aural-audit-reports-unique-unknown-identifiers ()
  "Development audits return unknown identifiers in stable order."
  (emacsvox-test--with-empty-aural-registries
    (emacsvox-aural-register-semantic
     'known :kind 'event :summary "Known")
    (should
     (equal
      (emacsvox-aural-audit-semantic-ids
       '(unknown-z known unknown-a unknown-z))
      '(unknown-a unknown-z)))))

(ert-deftest emacsvox-aural-legacy-icon-mappings-record-intent ()
  "Ambiguous legacy icons map to the semantic decisions from Slice 0."
  (should
   (equal
    (emacsvox-aural-legacy-icon-input 'repeat-stop)
    '(:source legacy-icon
      :cue repeat-stop
      :semantic activity-ended)))
  (should
   (equal
    (emacsvox-aural-legacy-icon-input 'item)
    '(:source legacy-icon
      :cue item
      :semantic nil))))

(ert-deftest emacsvox-aural-legacy-personality-is-a-hint-not-identity ()
  "A legacy personality adapter records voice presentation separately."
  (should
   (equal
    (emacsvox-aural-legacy-personality-input
     'voice-bolden 'face-mapping)
    '(:source face-mapping :voice voice-bolden))))

(ert-deftest emacsvox-aural-face-presentation-toggle-is-independent ()
  "The global face-rule control supports toggle and explicit prefix states."
  (let ((emacsvox-aural-face-presentation-enabled t)
        (emacsvox-aural-face-presentation-changed-hook nil)
        (changes 0))
    (add-hook
     'emacsvox-aural-face-presentation-changed-hook
     (lambda () (setq changes (1+ changes))))
    (should-not (emacsvox-aural-toggle-face-presentation))
    (should (emacsvox-aural-toggle-face-presentation 1))
    (should-not (emacsvox-aural-toggle-face-presentation 0))
    (should (= changes 3))))

(provide 'emacsvox-aural-tests)
;;; emacsvox-aural-tests.el ends here
