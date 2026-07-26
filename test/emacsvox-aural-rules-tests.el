;;; emacsvox-aural-rules-tests.el --- Aural rule engine tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Test deterministic selector matching, composition, and render-plan
;; provenance without invoking speech or audio backends.

;;; Code:

(require 'ert)
(require 'emacsvox-aural-rules)

(defun emacsvox-test--compile-rule (id match render &optional origin order)
  "Compile a test rule with ID, MATCH, RENDER, ORIGIN, and ORDER."
  (emacsvox-aural-compile-rule
   (append
    (list :id id)
    (when order (list :order order))
    (list :match match :render render))
   (or origin 'scheme)))

(defun emacsvox-test--action-ids (actions)
  "Return stable identifiers from compiled ACTIONS."
  (mapcar #'emacsvox-aural-action-id actions))

(ert-deftest emacsvox-aural-rules-compile-versioned-scheme ()
  "Safe plist scheme data compiles to internal scheme and rule structures."
  (let* ((data
          '(:schema-version 1
            :id org-example
            :summary "Org example"
            :rules
            ((:id heading-level
              :match (:role heading :level 1)
              :render
              (:content (:voice voice-bolden))))))
         (scheme (emacsvox-aural-compile-scheme data 'module "org")))
    (should (emacsvox-aural-scheme-p scheme))
    (should (eq (emacsvox-aural-scheme-id scheme) 'org-example))
    (should (eq (emacsvox-aural-scheme-origin scheme) 'module))
    (should (= (length (emacsvox-aural-scheme-rules scheme)) 1))
    (should
     (emacsvox-aural-rule-p
      (car (emacsvox-aural-scheme-rules scheme))))))

(ert-deftest emacsvox-aural-rules-reject-unsafe-or-unknown-data ()
  "Unknown versions, keys, semantics, and action kinds fail validation."
  (should-error
   (emacsvox-aural-compile-scheme
    '(:schema-version 99 :id future :summary "Future" :rules ()))
   :type 'emacsvox-aural-rule-error)
  (should-error
   (emacsvox-test--compile-rule
    'unknown-role
    '(:role not-registered)
    '(:content (:speak t)))
   :type 'emacsvox-aural-rule-error)
  (should-error
   (emacsvox-test--compile-rule
    'unknown-action
    '(:role heading)
    '(:before ((:kind executable :text "(shell-command ...)"))))
   :type 'emacsvox-aural-rule-error)
  (should-error
   (emacsvox-test--compile-rule
    'unknown-key
    '(:role heading)
    '(:during ((:kind speech :text "invalid"))))
   :type 'emacsvox-aural-rule-error)
  (should-error
   (emacsvox-test--compile-rule
    'duplicate-actions
    '(:role heading)
    '(:before
      ((:id duplicate :kind cue :cue item)
       (:id duplicate :kind cue :cue open-object))))
   :type 'emacsvox-aural-rule-error))

(ert-deftest emacsvox-aural-rules-validate-portable-spatial-contract ()
  "Spatial styling accepts normalized balance or listener-relative azimuth."
  (let* ((rule
          (emacsvox-test--compile-rule
           'spatial
           '(:role heading)
           '(:before
             ((:id left-label :kind speech :text "Heading"
               :space (:balance -0.5)))
             :content (:space (:azimuth 90)))))
         (contribution (emacsvox-aural-rule-contribution rule)))
    (should
     (equal
      (emacsvox-aural-action-space
       (car
        (emacsvox-aural-phase-operations-append
         (emacsvox-aural-contribution-before contribution))))
      '(:balance -0.5)))
    (should
     (equal
      (emacsvox-aural-content-patch-space
       (emacsvox-aural-contribution-content contribution))
      '(:azimuth 90))))
  (dolist
      (space
       '((:balance -1.1)
         (:balance 1.1)
         (:azimuth 181)
         (:balance 0 :azimuth 0)
         (:elevation 20)
         (:unknown 0)))
    (should-error
     (emacsvox-test--compile-rule
      'invalid-space
      '(:role heading)
      `(:content (:space ,space)))
     :type 'emacsvox-aural-rule-error))
  (should-error
   (emacsvox-test--compile-rule
    'spatial-pause
    '(:role heading)
    '(:before
      ((:id pause :kind pause :duration 10 :space (:balance 0.5)))))
   :type 'emacsvox-aural-rule-error))

(ert-deftest emacsvox-aural-rules-compose-heading-level-and-folded-state ()
  "Independent level and folded-state rules compose into one ordered plan."
  (let* ((rules
          (list
           (emacsvox-test--compile-rule
            'heading-level-one
            '(:role heading :level 1)
            '(:before
              ((:id heading-label :kind speech :text "Heading 1"))
              :content (:voice voice-bolden)))
           (emacsvox-test--compile-rule
            'folded-heading
            '(:role heading :state folded)
            '(:after
              ((:id folded-label :kind speech :text "folded"))))))
         (plan
          (emacsvox-aural-resolve
           '(:role heading :level 1 :states (folded) :content "Title")
           '(:module org :mode org-mode :occasion navigation)
           rules))
         (content (emacsvox-aural-render-plan-content plan)))
    (should
     (equal
      (emacsvox-test--action-ids
       (emacsvox-aural-render-plan-before plan))
      '(heading-label)))
    (should
     (equal
      (emacsvox-test--action-ids
       (emacsvox-aural-render-plan-after plan))
      '(folded-label)))
    (should (eq (emacsvox-aural-content-style-voice content) 'voice-bolden))
    (should (emacsvox-aural-content-style-speak content))
    (should
     (equal
      (emacsvox-aural-render-plan-matched-rules plan)
      '(folded-heading heading-level-one)))))

(ert-deftest emacsvox-aural-rules-match-presentation-occasion ()
  "Occasion changes matching presentation without changing semantic facts."
  (let* ((rules
          (list
           (emacsvox-test--compile-rule
            'navigation-label
            '(:role heading :occasion navigation)
            '(:before
              ((:id navigation :kind speech :text "Heading"))))
           (emacsvox-test--compile-rule
            'continuous-voice
            '(:role heading :occasion continuous)
            '(:content (:voice voice-lighten)))))
         (facts '(:role heading :level 1))
         (navigation
          (emacsvox-aural-resolve
           facts '(:module org :mode org-mode :occasion navigation) rules))
         (continuous
          (emacsvox-aural-resolve
           facts '(:module org :mode org-mode :occasion continuous) rules)))
    (should
     (equal
      (emacsvox-test--action-ids
       (emacsvox-aural-render-plan-before navigation))
      '(navigation)))
    (should-not (emacsvox-aural-render-plan-before continuous))
    (should
     (eq
      (emacsvox-aural-content-style-voice
       (emacsvox-aural-render-plan-content continuous))
      'voice-lighten))))

(ert-deftest emacsvox-aural-rules-stronger-origin-wins-content-scalars ()
  "Fragments, personal, and session layers override weaker origins."
  (let* ((core
          (emacsvox-test--compile-rule
           'core-heading '(:role heading)
           '(:content (:voice voice-core)) 'core))
         (module
          (emacsvox-test--compile-rule
           'module-heading '(:role heading :module org)
           '(:content (:voice voice-module)) 'module))
         (scheme
          (emacsvox-test--compile-rule
           'scheme-heading '(:role heading)
           '(:content (:voice voice-scheme)) 'scheme))
         (fragment
          (emacsvox-test--compile-rule
           'fragment-heading '(:role heading)
           '(:content (:voice voice-fragment)) 'fragment))
         (user
          (emacsvox-test--compile-rule
           'user-heading '(:role heading)
           '(:content (:voice voice-user)) 'user))
         (session
          (emacsvox-test--compile-rule
           'session-heading '(:role heading)
           '(:content (:voice voice-session)) 'session))
         (plan
          (emacsvox-aural-resolve
           '(:role heading)
           '(:module org :mode org-mode :occasion navigation)
           (list session core user module fragment scheme)))
         (content (emacsvox-aural-render-plan-content plan)))
    (should
     (equal
      (emacsvox-aural-render-plan-matched-rules plan)
      '(core-heading module-heading scheme-heading
        fragment-heading user-heading session-heading)))
    (should (eq (emacsvox-aural-content-style-voice content) 'voice-session))
    (should
     (eq
      (alist-get 'voice (emacsvox-aural-content-style-provenance content))
      'session-heading))))

(ert-deftest emacsvox-aural-rules-prefer-nearest-derived-mode ()
  "The nearest selected derived-mode ancestor supplies scalar styling."
  (let* ((rules
          (list
           (emacsvox-test--compile-rule
            'outline-heading
            '(:role heading :mode outline-mode)
            '(:content (:voice voice-outline)))
           (emacsvox-test--compile-rule
            'org-heading
            '(:role heading :mode org-mode)
            '(:content (:voice voice-org)))))
         (plan
          (emacsvox-aural-resolve
           '(:role heading)
           '(:module org
             :mode org-src-mode
             :mode-lineage (org-src-mode org-mode outline-mode)
             :occasion navigation)
           rules)))
    (should
     (equal
      (emacsvox-aural-render-plan-matched-rules plan)
      '(outline-heading org-heading)))
    (should
     (eq
      (emacsvox-aural-content-style-voice
       (emacsvox-aural-render-plan-content plan))
      'voice-org))))

(ert-deftest emacsvox-aural-rules-combined-exact-context-is-specific ()
  "A combined module and exact-mode selector beats an exact-mode selector."
  (let* ((rules
          (list
           (emacsvox-test--compile-rule
            'mode-only
            '(:role heading :mode org-mode)
            '(:content (:voice voice-mode)))
           (emacsvox-test--compile-rule
            'module-and-mode
            '(:role heading :module org :mode org-mode)
            '(:content (:voice voice-combined)))))
         (plan
          (emacsvox-aural-resolve
           '(:role heading)
           '(:module org :mode org-mode :occasion navigation)
           rules)))
    (should
     (eq
      (emacsvox-aural-content-style-voice
       (emacsvox-aural-render-plan-content plan))
      'voice-combined))))

(ert-deftest emacsvox-aural-rules-break-true-ties-by-stable-id ()
  "Equivalent rules produce the same sequence independent of input order."
  (let* ((alpha
          (emacsvox-test--compile-rule
           'alpha '(:role heading)
           '(:before ((:id alpha-action :kind cue :cue item)))))
         (zebra
          (emacsvox-test--compile-rule
           'zebra '(:role heading)
           '(:before ((:id zebra-action :kind cue :cue open-object)))))
         (context '(:module org :mode org-mode :occasion navigation))
         (first
          (emacsvox-aural-resolve
           '(:role heading) context (list zebra alpha)))
         (second
          (emacsvox-aural-resolve
           '(:role heading) context (list alpha zebra))))
    (should
     (equal
      (emacsvox-test--action-ids
       (emacsvox-aural-render-plan-before first))
      '(alpha-action zebra-action)))
    (should
     (equal
      (emacsvox-test--action-ids
       (emacsvox-aural-render-plan-before first))
      (emacsvox-test--action-ids
       (emacsvox-aural-render-plan-before second))))))

(ert-deftest emacsvox-aural-rules-apply-explicit-sequence-operations ()
  "Prepend, append, remove, and replace operate on stable action IDs."
  (let* ((base
          (emacsvox-test--compile-rule
           'base '(:role heading)
           '(:before
             ((:id first :kind cue :cue item)
              (:id second :kind cue :cue open-object)))
           'scheme))
         (edit
          (emacsvox-test--compile-rule
           'edit '(:role heading)
           '(:before
             (:remove (first)
              :prepend ((:id prepended :kind speech :text "before"))
              :append ((:id appended :kind pause :duration 50))))
           'user))
         (plan
          (emacsvox-aural-resolve
           '(:role heading)
           '(:module org :mode org-mode :occasion navigation)
           (list edit base))))
    (should
     (equal
      (emacsvox-test--action-ids
       (emacsvox-aural-render-plan-before plan))
      '(prepended second appended)))
    (let* ((replace
            (emacsvox-test--compile-rule
             'replace '(:role heading)
             '(:before
               (:replace ((:id replacement :kind cue :cue task-done))))
             'session))
           (replaced
            (emacsvox-aural-resolve
             '(:role heading)
             '(:module org :mode org-mode :occasion navigation)
             (list base edit replace))))
      (should
       (equal
        (emacsvox-test--action-ids
         (emacsvox-aural-render-plan-before replaced))
        '(replacement))))))

(ert-deftest emacsvox-aural-rules-suppress-phase-and-content ()
  "A stronger rule can suppress a sequence phase and content speech."
  (let* ((base
          (emacsvox-test--compile-rule
           'base '(:role heading)
           '(:before ((:id cue :kind cue :cue item))
             :content (:voice voice-bolden))
           'scheme))
         (quiet
          (emacsvox-test--compile-rule
           'quiet '(:role heading)
           '(:before (:suppress t)
             :content (:suppress t))
           'user))
         (plan
          (emacsvox-aural-resolve
           '(:role heading)
           '(:module org :mode org-mode :occasion navigation)
           (list quiet base))))
    (should-not (emacsvox-aural-render-plan-before plan))
    (should-not
     (emacsvox-aural-content-style-speak
      (emacsvox-aural-render-plan-content plan)))))

(ert-deftest emacsvox-aural-rules-generate-stable-local-action-id ()
  "An omitted action ID is derived from rule, phase, and stable index."
  (let* ((rule
          (emacsvox-test--compile-rule
           'heading '(:role heading)
           '(:after
             ((:kind speech :text "one")
              (:kind speech :text "two")))))
         (plan
          (emacsvox-aural-resolve
           '(:role heading)
           '(:module org :mode org-mode :occasion navigation)
           (list rule))))
    (should
     (equal
      (emacsvox-test--action-ids
       (emacsvox-aural-render-plan-after plan))
      '(heading/after/0 heading/after/1)))))

(ert-deftest emacsvox-aural-rules-validate-facts-and-context ()
  "Unknown semantics, invalid attributes, and unknown context keys fail."
  (should-error
   (emacsvox-aural-normalize-input
    '(:role not-registered)
    '(:module org :mode org-mode :occasion navigation))
   :type 'emacsvox-aural-rule-error)
  (should-error
   (emacsvox-aural-normalize-input
    '(:role heading :level 0)
    '(:module org :mode org-mode :occasion navigation))
   :type 'emacsvox-aural-rule-error)
  (should-error
   (emacsvox-aural-normalize-input
    '(:role heading)
    '(:module org :command org-next-visible-heading))
   :type 'emacsvox-aural-rule-error))

(provide 'emacsvox-aural-rules-tests)
;;; emacsvox-aural-rules-tests.el ends here
