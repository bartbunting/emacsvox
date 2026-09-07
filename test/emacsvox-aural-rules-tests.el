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

(ert-deftest emacsvox-aural-rules-match-required-attributes-for-templates ()
  "Presence selectors safely support dynamic semantic speech templates."
  (let* ((rule
          (emacsvox-test--compile-rule
           'dynamic-heading
           '(:role heading :requires (level))
           '(:before
             ((:id dynamic-label
               :kind speech
               :text-template "Heading {level}")))))
         (selector (emacsvox-aural-rule-selector rule))
         (action
          (car
           (emacsvox-aural-phase-operations-append
            (emacsvox-aural-contribution-before
             (emacsvox-aural-rule-contribution rule))))))
    (should
     (equal
      (emacsvox-aural-selector-required-attributes selector)
      '(level)))
    (should
     (equal
      (emacsvox-aural-action-template-fields action)
      '(level)))
    (should
     (emacsvox-aural-rule-matches-p
      rule
      (emacsvox-aural-normalize-input
       '(:role heading :level 3)
       '(:mode org-mode :occasion navigation))))
    (should-not
     (emacsvox-aural-rule-matches-p
      rule
      (emacsvox-aural-normalize-input
       '(:role heading)
       '(:mode org-mode :occasion navigation))))))

(ert-deftest emacsvox-aural-rules-compile-named-tone-actions ()
  "Tone actions retain a backend-independent resource name."
  (let* ((rule
          (emacsvox-test--compile-rule
           'blank-line
           '(:role heading :state folded)
           '(:before
             ((:id blank-tone :kind tone :tone line-empty)))))
         (action
          (car
           (emacsvox-aural-phase-operations-append
            (emacsvox-aural-contribution-before
             (emacsvox-aural-rule-contribution rule))))))
    (should (eq (emacsvox-aural-action-kind action) 'tone))
    (should (eq (emacsvox-aural-action-tone action) 'line-empty))
    (should (eq (emacsvox-aural-action-audio-mode action) 'overlay))
    (should-not (emacsvox-aural-action-duration action))))

(ert-deftest emacsvox-aural-rules-compile-fact-backed-tone-actions ()
  "Tone pitch and duration may be frozen from selector-guaranteed facts."
  (let* ((rule
          (emacsvox-test--compile-rule
           'indentation-tone
           '(:event indentation-located
             :requires
             (indentation-tone-pitch indentation-tone-duration))
           '(:before
             ((:id dynamic-indentation-tone
               :kind tone
               :pitch (:fact indentation-tone-pitch)
               :duration (:fact indentation-tone-duration)
               :audio-mode insert)))))
         (action
          (car
           (emacsvox-aural-phase-operations-append
            (emacsvox-aural-contribution-before
             (emacsvox-aural-rule-contribution rule))))))
    (should-not (emacsvox-aural-action-tone action))
    (should
     (equal
      (emacsvox-aural-action-pitch action)
      '(:fact indentation-tone-pitch)))
    (should
     (equal
      (emacsvox-aural-action-duration action)
      '(:fact indentation-tone-duration)))
    (should (eq (emacsvox-aural-action-audio-mode action) 'insert))
    (should
     (equal
      (emacsvox-aural-action-template-fields action)
      '(indentation-tone-pitch indentation-tone-duration)))))

(ert-deftest emacsvox-aural-rules-reject-unsafe-or-unguaranteed-templates ()
  "Templates accept only registered, selector-guaranteed semantic fields."
  (dolist
      (render
       '((:before
          ((:id missing-requirement :kind speech
            :text-template "Heading {level}")))
         (:before
          ((:id unknown-field :kind speech
            :text-template "Heading {arbitrary}")))
         (:before
          ((:id unmatched-brace :kind speech
            :text-template "Heading {level")))
         (:before
          ((:id conflicting-text :kind speech
            :text "Heading"
            :text-template "Heading {level}")))
         (:before
          ((:id unknown-property :kind speech
            :text "Heading" :execute arbitrary)))
         (:before
          ((:id cue-with-text :kind cue :cue item
            :text "ignored")))
         (:before
          ((:id pause-with-volume :kind pause :duration 10
            :volume 1)))
         (:before
          ((:id tone-with-duration :kind tone :tone line-empty
            :duration 10)))
         (:before
          ((:id incomplete-inline-tone :kind tone :pitch 440)))
         (:before
          ((:id invalid-tone-mode :kind tone :tone line-empty
            :audio-mode simultaneous)))
         (:before
          ((:id speech-with-tone-mode :kind speech :text "Heading"
            :audio-mode insert)))
         (:before
          ((:id unguaranteed-inline-tone :kind tone
            :pitch (:fact indentation-tone-pitch)
            :duration 150)))
         (:before
          ((:id unnamed-tone :kind tone)))
         (:before
          ((:id ambiguous-cue :kind cue
            :cue item :name button)))))
    (should-error
     (emacsvox-test--compile-rule
      'invalid-template
      '(:role heading)
      render)
     :type 'emacsvox-aural-rule-error))
  (should-error
   (emacsvox-test--compile-rule
    'invalid-required-kind
    '(:role heading :requires (folded))
    '(:content (:speak t)))
   :type 'emacsvox-aural-rule-error)
  (should-error
   (emacsvox-test--compile-rule
    'redundant-required
    '(:role heading :level 3 :requires (level))
    '(:content (:speak t)))
   :type 'emacsvox-aural-rule-error))

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

(ert-deftest emacsvox-aural-rules-match-semantic-fallbacks-with-provenance ()
  "General fallback rules compose before exact rules with an explicit path."
  (let ((emacsvox-aural-semantic-registry
         (copy-hash-table emacsvox-aural-semantic-registry))
        (emacsvox-aural-semantic-alias-registry
         (copy-hash-table emacsvox-aural-semantic-alias-registry)))
    (emacsvox-aural-register-semantic
     'contract-general-event
     :kind 'event
     :summary "General event")
    (emacsvox-aural-register-semantic
     'contract-specific-event
     :kind 'event
     :summary "Specific event"
     :fallback 'contract-general-event)
    (emacsvox-aural-validate-registry)
    (let* ((general
            (emacsvox-test--compile-rule
             'general
             '(:event contract-general-event)
             '(:before
               ((:id general-action :kind speech :text "general")))))
           (specific
            (emacsvox-test--compile-rule
             'specific
             '(:event contract-specific-event)
             '(:before
               ((:id specific-action :kind speech :text "specific")))))
           (plan
            (emacsvox-aural-resolve
             '(:event contract-specific-event)
             nil
             (list specific general)))
           (generic-match
            (cdr
             (assq
              'general
              (emacsvox-aural-render-plan-semantic-matches plan)))))
      (should
       (equal
        (emacsvox-aural-render-plan-matched-rules plan)
        '(general specific)))
      (should
       (equal
        (emacsvox-test--action-ids
         (emacsvox-aural-render-plan-before plan))
        '(general-action specific-action)))
      (should (= (plist-get (car generic-match) :distance) 1))
      (should
       (equal
        (plist-get (car generic-match) :path)
        '(contract-specific-event contract-general-event))))))

(ert-deftest emacsvox-aural-rules-enforce-operational-combinations ()
  "Declared role, occasion, and phase restrictions reject impossible rules."
  (let ((emacsvox-aural-semantic-registry
         (copy-hash-table emacsvox-aural-semantic-registry))
        (emacsvox-aural-semantic-alias-registry
         (copy-hash-table emacsvox-aural-semantic-alias-registry)))
    (emacsvox-aural-register-semantic
     'contract-importance
     :kind 'attribute
     :summary "Importance"
     :roles '(contract-object)
     :value-type 'symbol
     :allowed-values '(low high)
     :occasions '(navigation)
     :phases '(content))
    (emacsvox-aural-register-semantic
     'contract-object
     :kind 'role
     :summary "Contract object"
     :attributes '(contract-importance)
     :occasions '(navigation)
     :phases '(before content))
    (emacsvox-aural-validate-registry)
    (should
     (emacsvox-test--compile-rule
      'valid-contract
      '(:role contract-object :contract-importance high
        :occasion navigation)
      '(:content (:voice voice-bolden))))
    (dolist
        (definition
         '((wrong-role
            (:role heading :contract-importance high
             :occasion navigation)
            (:content (:speak t)))
           (wrong-occasion
            (:role contract-object :contract-importance high
             :occasion notification)
            (:content (:speak t)))
           (wrong-phase
            (:role contract-object :contract-importance high
             :occasion navigation)
            (:before
             ((:id invalid-phase :kind speech :text "important"))))))
      (should-error
       (emacsvox-test--compile-rule
        (car definition) (cadr definition) (caddr definition))
       :type 'emacsvox-aural-rule-error))
    (should-error
     (emacsvox-aural-normalize-input
      '(:role heading :contract-importance high)
      '(:occasion navigation))
     :type 'emacsvox-aural-rule-error)))

(ert-deftest emacsvox-aural-rules-canonicalize-and-merge-facts ()
  "Base and range facts produce one stable authoritative property per field."
  (should
   (equal
    (emacsvox-aural-merge-facts
     '(:role heading :event focus-entered :state folded
       :level 1 :content "base")
     '(:events (object-changed) :states (collapsed)
       :level 2 :content "local"))
    '(:role heading
      :events (object-changed focus-entered)
      :states (folded)
      :level 2
      :content "local")))
  (should
   (equal
    (emacsvox-aural-migrate-facts
     '(:role heading :state collapsed) 1)
    '(:role heading :states (folded)))))

(ert-deftest emacsvox-aural-rules-retain-semantic-alias-diagnostics ()
  "Deprecated identifiers compile canonically without losing diagnostics."
  (let* ((rule
          (emacsvox-test--compile-rule
           'old-folded-name
           '(:role heading :state collapsed)
           '(:content (:speak t))))
         (selector (emacsvox-aural-rule-selector rule))
         (input
          (emacsvox-aural-normalize-input
           '(:role heading :state collapsed))))
    (should
     (equal (emacsvox-aural-selector-states selector) '(folded)))
    (should (emacsvox-aural-selector-semantic-aliases selector))
    (should (equal (emacsvox-aural-input-states input) '(folded)))
    (should (emacsvox-aural-input-semantic-aliases input))))

(ert-deftest emacsvox-aural-rules-compose-explicit-voice-dimensions ()
  "Explicit ACSS data composes by dimension over a complete named preset."
  (let* ((rules
          (list
           (emacsvox-test--compile-rule
            'base '(:role heading)
            '(:content (:voice bolden))
            'core)
           (emacsvox-test--compile-rule
            'pitch '(:role heading)
            '(:content (:voice (:average-pitch 2)))
            'scheme)
           (emacsvox-test--compile-rule
            'richness '(:role heading)
            '(:content (:voice (:richness 8)))
            'user)))
         (content
          (emacsvox-aural-render-plan-content
           (emacsvox-aural-resolve
            '(:role heading)
            '(:mode org-mode :occasion navigation)
            rules))))
    (should
     (equal
      (emacsvox-aural-content-style-voice content)
      '(:preset bolden :average-pitch 2 :richness 8)))
    (should
     (eq
      (alist-get
       'preset
       (emacsvox-aural-content-style-voice-provenance content))
      'base))
    (should
     (eq
      (alist-get
       'average-pitch
       (emacsvox-aural-content-style-voice-provenance content))
      'pitch))
    (should
     (eq
      (alist-get
       'richness
       (emacsvox-aural-content-style-voice-provenance content))
      'richness))
    (should
     (eq
      (alist-get
       'stress
       (emacsvox-aural-content-style-voice-provenance content))
      'base))))

(ert-deftest emacsvox-aural-rules-compose-rich-dimensions-and-provenance ()
  "Every accepted style key composes and keeps its winning provenance."
  (dolist (key '(:rate-offset :gain :low-pass :high-pass :pan
                :reverb :echo :chorus :rate))
    (dolist (override '(nil 0 5))
      (let* ((rules
              (list (emacsvox-test--compile-rule
                     'base '(:role heading)
                     (list :content (list :voice (list key 3 :richness 8))) 'core)
                    (emacsvox-test--compile-rule
                     'override '(:role heading)
                     (list :content (list :voice (list key override))) 'user)))
             (content (emacsvox-aural-render-plan-content
                       (emacsvox-aural-resolve '(:role heading) nil rules)))
             (style (emacsvox-aural-content-style-voice content)))
        (should (plist-member style key))
        (should (equal (plist-get style key) override))
        (should (= (plist-get style :richness) 8))
        (should (eq (alist-get (intern (substring (symbol-name key) 1))
                              (emacsvox-aural-content-style-voice-provenance content))
                    'override))))))

(ert-deftest emacsvox-aural-rules-named-voice-resets-partial-style ()
  "A stronger named preset discards every inherited ACSS override."
  (let* ((rules
          (list
           (emacsvox-test--compile-rule
            'partial '(:role heading)
            '(:content (:voice (:average-pitch 2 :rate-offset 4 :reverb 8)))
            'core)
           (emacsvox-test--compile-rule
            'reset '(:role heading)
            '(:content (:voice lighten))
            'user)))
         (content
          (emacsvox-aural-render-plan-content
           (emacsvox-aural-resolve
            '(:role heading)
            '(:mode org-mode :occasion navigation)
            rules))))
    (should (eq (emacsvox-aural-content-style-voice content) 'lighten))
    (dolist (property (cons 'preset emacsvox-aural-rich-voice-dimensions))
      (should
       (eq
        (alist-get
         property
         (emacsvox-aural-content-style-voice-provenance content))
        'reset)))))

(ert-deftest emacsvox-aural-rules-validate-explicit-voice-style ()
  "Voice styles reject unknown, out-of-range, and malformed properties."
  (dolist
      (voice
       '((:average-pitch 10)
         (:stress -1)
         (:rate-offset -21)
         (:rate-offset 21)
         (:family 42)
         (:unknown 4)
         (:preset :keyword)))
    (should-error
     (emacsvox-test--compile-rule
      'invalid-voice
      '(:role heading)
      `(:content (:voice ,voice)))
     :type 'emacsvox-aural-rule-error)))

(ert-deftest emacsvox-aural-rules-accept-signed-relative-rate ()
  "Voice styles accept portable direct-point relative rates."
  (dolist (value '(-20 -1 0 4 20 nil))
    (should
     (emacsvox-aural-validate-voice-value
      (list :rate-offset value)
      "relative rate test"))))

(ert-deftest emacsvox-aural-rules-voice-field-inventories-are-compatible ()
  "Public dimension order and accepted legacy keys remain stable."
  (should (equal emacsvox-aural-voice-dimensions
                 '(family average-pitch pitch-range stress richness)))
  (should (equal emacsvox-aural-voice-rate-dimensions '(rate-offset)))
  (should (equal emacsvox-aural-post-synthesis-dimensions
                 '(gain low-pass high-pass pan reverb echo chorus)))
  (should (equal emacsvox-aural-rich-voice-dimensions
                 '(family average-pitch pitch-range stress richness rate-offset
                   gain low-pass high-pass pan reverb echo chorus)))
  (should (equal emacsvox-aural--voice-style-keys
                 '(:preset :family :average-pitch :pitch-range :stress :richness
                   :rate-offset :rate :gain :low-pass :high-pass :pan
                   :reverb :echo :chorus))))

(ert-deftest emacsvox-aural-rules-voice-field-values-and-diagnostics ()
  "Every numeric field retains its bounds, nil handling, and error text."
  ;; Expected fields and limits are deliberately independent of the schema.
  (dolist (fixture '((:average-pitch 0 9) (:pitch-range 0 9)
                     (:stress 0 9) (:richness 0 9) (:rate-offset -20 20)
                     (:rate 0 9) (:gain 0 9) (:low-pass 0 9) (:high-pass 0 9)
                     (:pan 0 9) (:reverb 0 9) (:echo 0 9) (:chorus 0 9)))
    (pcase-let ((`(,key ,minimum ,maximum) fixture))
      (dolist (value (list nil minimum 0 5 maximum))
        (let* ((style (list key value))
               (before (copy-tree style)))
          (should (eq style (emacsvox-aural-validate-voice-value style "voice")))
          (should (equal style before))))
      (dolist (value (list (1- minimum) (1+ maximum) 1.0 "5" t :default '(5)))
        (should
         (equal
          (should-error
           (emacsvox-aural-validate-voice-value (list key value) "voice")
           :type 'emacsvox-aural-rule-error)
          (list 'emacsvox-aural-rule-error
                (format "voice %s%S must be an integer from %s through %s, or nil: %S"
                        (if (eq key :rate) "legacy " "") key
                        minimum maximum value))))))))

(ert-deftest emacsvox-aural-rules-voice-preset-and-family-values ()
  "Preset and family retain their distinct symbol and nil contracts."
  (dolist (fixture '((:preset (nil t bolden))
                     (:family (nil t :keyword family "engine voice" ""))))
    (dolist (value (cadr fixture))
      (let ((style (list (car fixture) value)))
        (should (eq style (emacsvox-aural-validate-voice-value style "voice"))))))
  (dolist (fixture '((:preset (:keyword "bolden" 0 (bolden))
                     "a non-keyword symbol or nil")
                    (:family (0 1.0 (family) [family])
                     "a symbol, string, or nil")))
    (pcase-let ((`(,key ,values ,description) fixture))
      (dolist (value values)
        (should
         (equal
          (should-error
           (emacsvox-aural-validate-voice-value (list key value) "voice")
           :type 'emacsvox-aural-rule-error)
          (list 'emacsvox-aural-rule-error
                (format "voice %S must be %s: %S" key description value))))))))

(ert-deftest emacsvox-aural-rules-voice-validation-precedence ()
  "Report unknown fields first, then the historical field-validation order."
  (should
   (equal
    (should-error (emacsvox-aural-validate-voice-value
                   '(:rate 99 :unknown 1 :preset 42 :unknown 2) "voice"))
    '(emacsvox-aural-rule-error
      "Unknown properties in voice: (:unknown :unknown)")))
  ;; Reverse the input order: the validator's priority must win each time.
  (let* ((fixtures
          '((:preset 42 "voice :preset must be a non-keyword symbol or nil: 42")
            (:family 42 "voice :family must be a symbol, string, or nil: 42")
            (:average-pitch 10 "voice :average-pitch must be an integer from 0 through 9, or nil: 10")
            (:pitch-range 10 "voice :pitch-range must be an integer from 0 through 9, or nil: 10")
            (:stress 10 "voice :stress must be an integer from 0 through 9, or nil: 10")
            (:richness 10 "voice :richness must be an integer from 0 through 9, or nil: 10")
            (:gain 10 "voice :gain must be an integer from 0 through 9, or nil: 10")
            (:low-pass 10 "voice :low-pass must be an integer from 0 through 9, or nil: 10")
            (:high-pass 10 "voice :high-pass must be an integer from 0 through 9, or nil: 10")
            (:pan 10 "voice :pan must be an integer from 0 through 9, or nil: 10")
            (:reverb 10 "voice :reverb must be an integer from 0 through 9, or nil: 10")
            (:echo 10 "voice :echo must be an integer from 0 through 9, or nil: 10")
            (:chorus 10 "voice :chorus must be an integer from 0 through 9, or nil: 10")
            (:rate-offset 21 "voice :rate-offset must be an integer from -20 through 20, or nil: 21")
            (:rate 10 "voice legacy :rate must be an integer from 0 through 9, or nil: 10"))))
    (while fixtures
      (let ((style (apply #'append
                          (mapcar (lambda (fixture) (list (car fixture) (cadr fixture)))
                                  (reverse fixtures)))))
        (should (equal
                 (should-error (emacsvox-aural-validate-voice-value style "voice"))
                 (list 'emacsvox-aural-rule-error (caddar fixtures)))))
      (setq fixtures (cdr fixtures)))))

(ert-deftest emacsvox-aural-rules-voice-plist-shape-and-duplicates ()
  "Malformed styles fail, while duplicate fields keep first-value semantics."
  (dolist (style '((:gain) (:gain . 2) (:gain 2 :pan) (gain 2)
                   [:gain 2] (:unknown 2)))
    (should-not (emacsvox-aural-voice-style-p style))
    (should-error (emacsvox-aural--validate-voice-style style "voice")
                  :type 'emacsvox-aural-rule-error))
  (dolist (style '((:gain nil :gain 42) (:gain 0 :gain 42)
                   (:preset nil :preset 42) (:family "voice" :family 42)))
    (should (eq style (emacsvox-aural-validate-voice-value style "voice"))))
  (should-error
   (emacsvox-aural-validate-voice-value '(:gain 42 :gain 0) "voice")
   :type 'emacsvox-aural-rule-error))

(ert-deftest emacsvox-aural-rules-voice-presence-and-provenance ()
  "Composition distinguishes nil, zero, and omission for every style field."
  (dolist (fixture '((:family "test voice" nil)
                     (:average-pitch 7 0) (:pitch-range 7 0)
                     (:stress 7 0) (:richness 7 0) (:rate-offset -4 0)
                     (:rate 7 0) (:gain 7 0) (:low-pass 7 0) (:high-pass 7 0)
                     (:pan 7 0) (:reverb 7 0) (:echo 7 0) (:chorus 7 0)))
    (pcase-let ((`(,key ,initial ,zero) fixture))
      (dolist (value (list nil zero))
        (let* ((initial-style (list :preset 'bolden key initial))
               (content (emacsvox-aural--make-content-style :voice initial-style))
               (dimension (intern (substring (symbol-name key) 1))))
          (emacsvox-aural--apply-voice content (list key value) 'override)
          (should (equal (emacsvox-aural-content-style-voice content)
                         (list :preset 'bolden key value)))
          (should (eq (alist-get dimension
                                (emacsvox-aural-content-style-voice-provenance content))
                      'override))
          (should (equal initial-style (list :preset 'bolden key initial)))))
      (let ((content (emacsvox-aural--make-content-style :voice 'bolden)))
        (emacsvox-aural--apply-voice content (list key nil) 'override)
        (should (equal (emacsvox-aural-content-style-voice content)
                       (list :preset 'bolden key nil))))))
  (let ((content (emacsvox-aural--make-content-style
                  :voice '(:average-pitch 7 :pan 0))))
    (emacsvox-aural--apply-voice content '(:richness nil) 'override)
    (should (equal (emacsvox-aural-content-style-voice content)
                   '(:average-pitch 7 :pan 0 :richness nil)))
    (should-not (plist-member (emacsvox-aural-content-style-voice content) :gain))
    (emacsvox-aural--apply-voice content '(:preset nil) 'reset)
    (should (equal (emacsvox-aural-content-style-voice content) '(:preset nil)))
    (should (eq (alist-get 'gain
                          (emacsvox-aural-content-style-voice-provenance content))
                'reset))))

(ert-deftest emacsvox-aural-rules-compose-layered-face-presentations ()
  "Every named face may add actions while the strongest face wins voice ties."
  (let* ((warning
          (emacsvox-test--compile-rule
           'warning-face
           '(:legacy-face font-lock-warning-face)
           '(:before
             ((:id warning-cue :kind cue :cue warn-user))
             :content (:voice bolden))))
         (bold
          (emacsvox-test--compile-rule
           'bold-face
           '(:legacy-face bold)
           '(:before
             ((:id bold-cue :kind cue :cue item))
             :content (:voice lighten))))
         (rules (list warning bold))
         (context
          '(:mode text-mode :mode-lineage (text-mode)
            :occasion navigation
            :legacy-faces (font-lock-warning-face bold)))
         (plan (emacsvox-aural-resolve nil context rules)))
    (should
     (equal
      (emacsvox-aural-render-plan-matched-rules plan)
      '(bold-face warning-face)))
    (should
     (equal
      (mapcar
       #'emacsvox-aural-action-cue
       (emacsvox-aural-render-plan-before plan))
      '(item warn-user)))
    (should
     (eq
      (emacsvox-aural-content-style-voice
       (emacsvox-aural-render-plan-content plan))
      'bolden))
    (let ((reversed
           (emacsvox-aural-resolve
            nil
            '(:mode text-mode :mode-lineage (text-mode)
              :occasion navigation
              :legacy-faces (bold font-lock-warning-face))
            rules)))
      (should
       (eq
        (emacsvox-aural-content-style-voice
         (emacsvox-aural-render-plan-content reversed))
        'lighten)))
    (let* ((semantic
            (emacsvox-test--compile-rule
             'semantic-warning
             '(:role heading)
             '(:content (:voice annotate))))
           (semantic-plan
            (emacsvox-aural-resolve
             '(:role heading)
             context
             (list warning semantic))))
      (should
       (eq
        (emacsvox-aural-content-style-voice
         (emacsvox-aural-render-plan-content semantic-plan))
        'annotate)))))

(ert-deftest emacsvox-aural-rules-separate-face-and-voice-lock-controls ()
  "Face rules, legacy personality rules, and semantic rules have distinct gates."
  (let* ((face
          (emacsvox-test--compile-rule
           'face-warning
           '(:legacy-face font-lock-warning-face)
           '(:before
             ((:id face-cue :kind cue :cue warn-user)))))
         (legacy
          (emacsvox-test--compile-rule
           'legacy-voice
           '(:legacy-personality voice-bolden)
           '(:after
             ((:id legacy-label :kind speech :text "legacy voice")))))
         (semantic
          (emacsvox-test--compile-rule
           'semantic-heading
           '(:role heading)
           '(:content (:voice annotate))))
         (rules (list face legacy semantic))
         (base
          '(:mode text-mode :mode-lineage (text-mode)
            :occasion navigation
            :legacy-faces (font-lock-warning-face)
            :legacy-personality voice-bolden)))
    (dolist
        (case
         '((t t (face-warning legacy-voice semantic-heading))
           (nil t (legacy-voice semantic-heading))
           (t nil (face-warning semantic-heading))
           (nil nil (semantic-heading))))
      (pcase-let ((`(,faces ,voice-lock ,expected) case))
        (let* ((context
                (append
                 (list
                  :face-presentation-enabled faces
                  :voice-lock-enabled voice-lock)
                 base))
               (plan
                (emacsvox-aural-resolve
                 '(:role heading) context rules)))
          (should
           (equal
            (emacsvox-aural-render-plan-matched-rules plan)
            expected))
          (should
           (eq
            (emacsvox-aural-content-style-voice
             (emacsvox-aural-render-plan-content plan))
            'annotate)))))))

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
  (should
   (emacsvox-aural-input-p
    (emacsvox-aural-normalize-input
     '(:role heading)
     '(:module org :mode org-mode :occasion navigation
       :presentation-transaction-id 3))))
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
   :type 'emacsvox-aural-rule-error)
  (should-error
   (emacsvox-aural-normalize-input
    nil
    '(:mode text-mode :occasion navigation
      :legacy-faces (font-lock-warning-face "not-a-face")))
   :type 'emacsvox-aural-rule-error)
  (should-error
   (emacsvox-aural-normalize-input
    nil
    '(:mode text-mode :occasion navigation :icons-enabled yes))
   :type 'emacsvox-aural-rule-error)
  (should-error
   (emacsvox-aural-normalize-input
    nil
    '(:mode text-mode :occasion navigation
      :presentation-transaction-id invalid))
   :type 'emacsvox-aural-rule-error)
  (should-error
   (emacsvox-test--compile-rule
    'invalid-face
    '(:legacy-face "not-a-face")
    '(:content (:voice bolden)))
   :type 'emacsvox-aural-rule-error))

(ert-deftest emacsvox-aural-rules-infer-and-validate-action-anchors ()
  "Semantic actions default to objects and face actions default to runs."
  (let* ((semantic
          (emacsvox-test--compile-rule
           'semantic-anchor
           '(:role heading)
           '(:before
             ((:id semantic-default :kind cue :cue item)
              (:id semantic-transition :kind cue :cue select-object
               :anchor transition)))))
         (face
          (emacsvox-test--compile-rule
           'face-anchor
           '(:legacy-face font-lock-warning-face)
           '(:before
             ((:id face-default :kind speech :text "warning")))))
         (semantic-actions
          (emacsvox-aural-phase-operations-append
           (emacsvox-aural-contribution-before
            (emacsvox-aural-rule-contribution semantic))))
         (face-action
          (car
           (emacsvox-aural-phase-operations-append
            (emacsvox-aural-contribution-before
             (emacsvox-aural-rule-contribution face))))))
    (should
     (equal
      (mapcar #'emacsvox-aural-action-anchor semantic-actions)
      '(object transition)))
    (should (eq (emacsvox-aural-action-anchor face-action) 'run))
    (should-error
     (emacsvox-test--compile-rule
      'invalid-anchor
      '(:role heading)
      '(:before
        ((:id invalid :kind cue :cue item :anchor arbitrary))))
     :type 'emacsvox-aural-rule-error)))

(ert-deftest emacsvox-aural-rules-resolve-one-action-lifetime ()
  "Anchored resolution selects object, run, or transition actions."
  (let* ((rule
          (emacsvox-test--compile-rule
           'three-lifetimes
           '(:role heading)
           '(:before
             ((:id object-action :kind cue :cue item)
              (:id run-action :kind cue :cue select-object :anchor run)
              (:id transition-action :kind cue :cue open-object
               :anchor transition)))))
         (facts '(:role heading))
         (context '(:mode text-mode :occasion navigation)))
    (dolist
        (case
         '((object object-action)
           (run run-action)
           (transition transition-action)))
      (let ((plan
             (emacsvox-aural-resolve
              facts context (list rule) (car case))))
        (should
         (equal
          (emacsvox-test--action-ids
           (emacsvox-aural-render-plan-before plan))
          (cdr case)))))))

(ert-deftest emacsvox-aural-rules-share-matches-across-lifetimes ()
  "Several lifecycle plans reuse normalization and matching results."
  (let* ((rule
          (emacsvox-test--compile-rule
           'shared-lifetimes
           '(:role heading)
           '(:before
             ((:id run-action :kind cue :cue item :anchor run)
              (:id transition-action :kind cue :cue open-object
               :anchor transition)))))
         (input
          (cons
           '(:role heading)
           '(:mode text-mode :occasion navigation)))
         (normalize (symbol-function 'emacsvox-aural-normalize-input))
         (matching
          (symbol-function 'emacsvox-aural--matching-rules-for-inputs))
         (normalizations 0)
         (matches 0)
         plans)
    (cl-letf
        (((symbol-function 'emacsvox-aural-normalize-input)
          (lambda (&rest arguments)
            (cl-incf normalizations)
            (apply normalize arguments)))
         ((symbol-function 'emacsvox-aural--matching-rules-for-inputs)
          (lambda (&rest arguments)
            (cl-incf matches)
            (apply matching arguments))))
      (setq
       plans
       (emacsvox-aural--resolve-inputs-for-anchors
        (list input) (list rule) '(run transition))))
    (should (= normalizations 1))
    (should (= matches 1))
    (should
     (equal
      (emacsvox-test--action-ids
       (emacsvox-aural-render-plan-before (alist-get 'run plans)))
      '(run-action)))
    (should
     (equal
      (emacsvox-test--action-ids
       (emacsvox-aural-render-plan-before (alist-get 'transition plans)))
      '(transition-action)))
    (should-not
     (eq
      (emacsvox-aural-render-plan-content (alist-get 'run plans))
      (emacsvox-aural-render-plan-content (alist-get 'transition plans))))))

(ert-deftest emacsvox-aural-rules-object-face-actions-compose-once ()
  "An object action selected by several face runs contributes only once."
  (let* ((rule
          (emacsvox-test--compile-rule
           'face-object
           '(:legacy-face font-lock-warning-face)
           '(:before
             ((:id warning-object :kind speech :text "contains warning"
               :anchor object)))))
         (facts '(:role heading))
         (first
          '(:mode text-mode :occasion navigation
            :legacy-faces (font-lock-warning-face)))
         (second
          '(:mode text-mode :occasion navigation
            :legacy-faces (font-lock-warning-face bold)))
         (plan
          (emacsvox-aural-resolve-inputs
           (list (cons facts first) (cons facts second))
           (list rule) 'object)))
    (should
     (equal
      (emacsvox-test--action-ids
       (emacsvox-aural-render-plan-before plan))
      '(warning-object)))))

(provide 'emacsvox-aural-rules-tests)
;;; emacsvox-aural-rules-tests.el ends here
