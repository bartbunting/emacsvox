;;; emacsvox-aural-routing-profiles-tests.el --- Voice routing tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Verify separate, data-only, machine-aware physical voice routing.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'omnivox-voices)
(require 'outloud-voices)
(require 'dectalk-voices)
(require 'emacsvox-aural-routing-profiles)

(defconst emacsvox-test--routing-profile
  '(:schema-version 2
    :id workstation
    :summary "Local workstation routing"
    :engine-order ("eloquence" "dectalk" "winrt" "espeak")
    :disabled-engines ("dectalk")
    :fallback
    (:allow-same-language t
     :global-default
     (:kind properties :scope portable :language "en-AU")
     :engines ("espeak"))
    :bindings
    ((:logical-voice voice-bolden :language "en-AU"
      :selectors
      ((:kind exact :scope local :engine-id "eloquence"
        :voice-id "eci:Reed")
       (:kind properties :scope portable :engine-id "dectalk"
        :gender male)))))
  "Representative machine routing profile data.")

(defmacro emacsvox-test--with-routing-profiles (&rest body)
  "Run BODY with isolated routing and Omnivox state."
  (declare (indent 0) (debug t))
  `(let ((emacsvox-aural-routing-profile-registry
          (make-hash-table :test #'eq))
         (emacsvox-aural-active-routing-profile nil)
         (emacsvox-aural-session-routing-bindings nil)
         (emacsvox-aural-session-engine-order nil)
         (emacsvox-aural-routing-profile-changed-hook nil)
         (omnivox-logical-voice-preferences nil)
         (omnivox-logical-voice-languages nil)
         (omnivox-engine-priority-ids nil)
         (omnivox-fallback-engine-ids '("espeak"))
         (omnivox-disabled-engine-ids nil)
         (omnivox-global-default-selector nil)
         (omnivox-allow-same-language-fallback t))
     ,@body))

(ert-deftest emacsvox-aural-routing-migrates-schema-one-disablement ()
  "Schema-one profiles gain an empty, independent disabled-engine list."
  (let ((profile
         (emacsvox-aural-validate-routing-profile-data
          '(:schema-version 1 :id old :summary "Old"
            :engine-order ("winrt")
            :fallback
            (:allow-same-language t :global-default nil :engines nil)
            :bindings nil))))
    (should (= (plist-get profile :schema-version) 2))
    (should-not (plist-get profile :disabled-engines))))

(ert-deftest emacsvox-aural-routing-requires-local-exact-identities ()
  "Exact native IDs cannot enter portable or temporary persisted data."
  (should-error
   (emacsvox-aural-validate-routing-selector
    '(:kind exact :scope portable :engine-id "winrt" :voice-id "David") t)
   :type 'emacsvox-aural-routing-profile-error)
  (should-error
   (emacsvox-aural-validate-routing-selector
    '(:kind engine-default :scope session :engine-id "winrt") t)
   :type 'emacsvox-aural-routing-profile-error)
  (should
   (equal
    (emacsvox-aural-validate-routing-selector
     '(:kind exact :scope local :engine-id "winrt" :voice-id "David") t)
    '(:kind exact :scope local :engine-id "winrt" :voice-id "David"))))

(ert-deftest emacsvox-aural-routing-composes-binding-and-engine-order ()
  "Logical selectors precede distinct global engine defaults."
  (emacsvox-test--with-routing-profiles
    (emacsvox-aural-register-routing-profile-data
     emacsvox-test--routing-profile "test")
    (setq emacsvox-aural-active-routing-profile 'workstation)
    (let ((selectors
           (emacsvox-aural-routing-selectors 'voice-bolden)))
      (should (eq (plist-get (nth 0 selectors) :kind) 'exact))
      (should (equal (plist-get (nth 1 selectors) :engine-id) "dectalk"))
      (should (equal (plist-get (nth 2 selectors) :engine-id) "winrt"))
      (should (equal (plist-get (nth 3 selectors) :engine-id) "espeak")))))

(ert-deftest emacsvox-aural-routing-promotes-engine-without-changing-routes ()
  "Engine preference preserves explicit selectors and fallback policy."
  (let* ((input (copy-tree emacsvox-test--routing-profile))
         (preferred
          (emacsvox-aural-routing-prefer-engine-in-data input "winrt")))
    (should
     (equal
      (plist-get preferred :engine-order)
      '("winrt" "eloquence" "dectalk" "espeak")))
    (should
     (equal
      (plist-get preferred :fallback)
      (plist-get input :fallback)))
    (should
     (equal
      (plist-get preferred :bindings)
      (plist-get input :bindings)))
    (should (equal input emacsvox-test--routing-profile))
    (should-error
     (emacsvox-aural-routing-prefer-engine-in-data input "dectalk")
     :type 'emacsvox-aural-routing-profile-error)))

(ert-deftest emacsvox-aural-routing-session-engine-order-is-unsaved-overlay ()
  "Session preference applies globally after explicit logical selectors."
  (emacsvox-test--with-routing-profiles
    (emacsvox-aural-register-routing-profile-data
     emacsvox-test--routing-profile "test")
    (setq emacsvox-aural-active-routing-profile 'workstation)
    (let (statuses)
      (cl-letf
          (((symbol-function 'tts-apply-voice-configuration)
            (lambda (callback)
              (let ((status '(:status applied :completion-guarantee local)))
                (push status statuses)
                (funcall callback status)
                status))))
        (emacsvox-aural-prefer-engine-for-session "winrt")
        (should
         (equal emacsvox-aural-session-engine-order
                '("winrt" "eloquence" "dectalk" "espeak")))
        (should
         (equal omnivox-engine-priority-ids
                emacsvox-aural-session-engine-order))
        (let ((selectors
               (emacsvox-aural-routing-selectors 'voice-bolden)))
          (should (eq (plist-get (nth 0 selectors) :kind) 'exact))
          (should (equal (plist-get (nth 0 selectors) :engine-id)
                         "eloquence"))
          (should (equal (plist-get (nth 1 selectors) :engine-id)
                         "dectalk"))
          (should (equal (plist-get (nth 2 selectors) :engine-id)
                         "winrt")))
        (let* ((user-data (emacsvox-aural-routing-user-data))
               (saved-profile (car (plist-get user-data :profiles))))
          (should
           (equal
            (plist-get saved-profile :engine-order)
            '("eloquence" "dectalk" "winrt" "espeak"))))
        (emacsvox-aural-clear-session-engine-order)
        (should-not emacsvox-aural-session-engine-order)
        (should
         (equal omnivox-engine-priority-ids
                '("eloquence" "dectalk" "winrt" "espeak")))
        (should (= (length statuses) 2))))))

(ert-deftest emacsvox-aural-routing-session-binding-replaces-saved-route ()
  "A temporary session route wins and is not added to saved user data."
  (emacsvox-test--with-routing-profiles
    (emacsvox-aural-register-routing-profile-data
     emacsvox-test--routing-profile "test")
    (setq emacsvox-aural-active-routing-profile 'workstation)
    (emacsvox-aural-set-session-routing-binding
     'voice-bolden
     '((:kind exact :engine-id "winrt" :voice-id "David")))
    (let ((selectors
           (emacsvox-aural-routing-selectors 'voice-bolden)))
      (should (= (length selectors) 1))
      (should (eq (plist-get (car selectors) :scope) 'session))
      (should (equal (plist-get (car selectors) :engine-id) "winrt")))
    (should-not
     (string-match-p
     "David" (prin1-to-string (emacsvox-aural-routing-user-data))))))

(ert-deftest emacsvox-aural-routing-resolves-static-engine-family-alias ()
  "An Omnivox Eloquence ID maps to the equivalent standalone family."
  (emacsvox-test--with-routing-profiles
    (let ((profile
           '(:schema-version 2 :id static :summary "Static"
             :engine-order nil :disabled-engines nil
             :fallback
             (:allow-same-language t :global-default nil :engines nil)
             :bindings
             ((:logical-voice voice-bolden
               :selectors
               ((:kind exact :scope local :engine-id "eloquence"
                 :voice-id "v2")))))))
      (emacsvox-aural-register-routing-profile-data profile "test")
      (setq emacsvox-aural-active-routing-profile 'static)
      (should
       (eq
        (emacsvox-aural-routing-static-family
         'voice-bolden 'paul
         (outloud-voice-capabilities)
         (let ((tts-voice-capabilities-function #'outloud-voice-capabilities))
           (tts-default-voice-inventory)))
        'outloud-v2)))))

(ert-deftest emacsvox-aural-routing-static-properties-degrade-safely ()
  "Static property routes resolve traits and missing routes retain ACSS."
  (emacsvox-test--with-routing-profiles
    (let ((profile
           '(:schema-version 2 :id static :summary "Static"
             :engine-order nil :disabled-engines nil
             :fallback
             (:allow-same-language t :global-default nil :engines nil)
             :bindings
             ((:logical-voice voice-bolden
               :selectors
               ((:kind properties :scope portable :engine-id "dectalk"
                 :gender female)))))))
      (emacsvox-aural-register-routing-profile-data profile "test")
      (setq emacsvox-aural-active-routing-profile 'static)
      (let* ((capabilities (dectalk-voice-capabilities))
             (tts-voice-capabilities-function
              (lambda () (copy-tree capabilities)))
             (inventory (tts-default-voice-inventory)))
        (should
         (eq
          (emacsvox-aural-routing-static-family
           'voice-bolden 'paul capabilities inventory)
          'betty))
        (should
         (eq
          (emacsvox-aural-routing-static-family
           'voice-animate 'harry capabilities inventory)
          'harry))))))

(ert-deftest emacsvox-aural-routing-diagnoses-exact-family-ownership ()
  "An exact route owns physical selection while ACSS family stays portable."
  (emacsvox-test--with-routing-profiles
    (emacsvox-aural-register-routing-profile-data
     emacsvox-test--routing-profile "test")
    (setq emacsvox-aural-active-routing-profile 'workstation)
    (cl-progv '(voice-bolden) (list (make-acss :family 'male))
      (let ((diagnostic
             (car
              (emacsvox-aural-routing-family-diagnostics 'voice-bolden))))
        (should (eq (plist-get diagnostic :kind)
                    'exact-route-overrides-family))
        (should (eq (plist-get diagnostic :requested-family) 'male))
        (should (equal (plist-get diagnostic :voice-id) "eci:Reed"))))))

(ert-deftest emacsvox-aural-routing-migrates-omnivox-order-faithfully ()
  "Import and apply preserve the existing effective Omnivox selector order."
  (emacsvox-test--with-routing-profiles
    (setq omnivox-logical-voice-preferences
          '((voice-bolden
             (exact "eloquence" "eci:Reed")
             (properties :engine "dectalk" :gender male)))
          omnivox-logical-voice-languages '((voice-bolden . "en-AU"))
          omnivox-engine-priority-ids '("eloquence" "winrt")
          omnivox-fallback-engine-ids '("espeak")
          omnivox-disabled-engine-ids '("dectalk")
          omnivox-global-default-selector
          '(properties :language "en-AU")
          omnivox-allow-same-language-fallback nil)
    (let ((before (omnivox--logical-registry-content "dectalk"))
          (profile
           (emacsvox-aural-routing-profile-from-omnivox 'imported)))
      (emacsvox-aural-register-routing-profile-data profile "migration")
      (cl-letf (((symbol-function 'omnivox-register-logical-voices)
                 #'ignore))
        (emacsvox-aural-apply-routing-profile 'imported))
      (should (equal (omnivox--logical-registry-content "dectalk") before))
      (should-not omnivox-allow-same-language-fallback)
      (should (equal omnivox-disabled-engine-ids '("dectalk")))
      (should
       (equal omnivox-global-default-selector
              '(properties :language "en-AU"))))))

(ert-deftest emacsvox-aural-routing-round-trips-separate-data-file ()
  "Machine routing saves and loads atomically outside palette data."
  (emacsvox-test--with-routing-profiles
    (let* ((directory (make-temp-file "emacsvox-routing-" t))
           (file (expand-file-name "routing.el" directory)))
      (unwind-protect
          (progn
            (emacsvox-aural-register-routing-profile-data
             emacsvox-test--routing-profile file)
            (setq emacsvox-aural-active-routing-profile 'workstation)
            (emacsvox-aural-save-routing-profiles file)
            (let ((saved (emacsvox-aural-read-routing-profiles file)))
              (should (eq (plist-get saved :active-profile) 'workstation))
              (should (= (length (plist-get saved :profiles)) 1)))
            (setq emacsvox-aural-routing-profile-registry
                  (make-hash-table :test #'eq)
                  emacsvox-aural-active-routing-profile nil)
            (emacsvox-aural-load-routing-profiles file)
            (should
             (emacsvox-aural-routing-profile 'workstation)))
        (delete-directory directory t)))))

(ert-deftest emacsvox-aural-routing-commit-rolls-back-on-save-failure ()
  "A failed atomic write restores the prior registry and active profile."
  (emacsvox-test--with-routing-profiles
    (emacsvox-aural-register-routing-profile-data
     emacsvox-test--routing-profile "old")
    (setq emacsvox-aural-active-routing-profile 'workstation)
    (let ((changed (copy-tree emacsvox-test--routing-profile)))
      (setf (plist-get changed :summary) "changed")
      (cl-letf (((symbol-function 'emacsvox-aural-save-routing-profiles)
                 (lambda (&rest _) (error "simulated save failure"))))
        (should-error
         (emacsvox-aural-commit-routing-profile-data changed "/tmp/unused")))
      (should (eq emacsvox-aural-active-routing-profile 'workstation))
      (should
       (equal
        (plist-get
         (emacsvox-aural-routing-profile-entry-data
          (emacsvox-aural-routing-profile 'workstation))
         :summary)
        "Local workstation routing")))))

(ert-deftest emacsvox-aural-routing-rejects-data-after-valid-form ()
  "The local routing reader accepts exactly one non-evaluated form."
  (let ((file (make-temp-file "emacsvox-routing-invalid-" nil ".el")))
    (unwind-protect
        (progn
          (write-region
           "(:schema-version 1 :active-profile nil :profiles nil) trailing"
           nil file nil 'silent)
          (should-error
           (emacsvox-aural-read-routing-profiles file)
           :type 'emacsvox-aural-routing-profile-error))
      (delete-file file))))

(ert-deftest emacsvox-aural-routing-portable-copy-removes-native-ids ()
  "Portable profile conversion uses voice traits and retains fallback order."
  (let* ((inventory
          '(:engines
            ((:engine-id "eloquence"
              :voices
              ((:voice-id "eci:Reed" :language "en-AU" :gender male))))))
         (portable
          (emacsvox-aural-routing-portable-profile-data
           emacsvox-test--routing-profile inventory))
         (selector
          (car (plist-get (car (plist-get portable :bindings)) :selectors))))
    (should (eq (plist-get selector :kind) 'properties))
    (should (eq (plist-get selector :scope) 'portable))
    (should (equal (plist-get selector :engine-id) "eloquence"))
    (should (equal (plist-get selector :language) "en-AU"))
    (should-not (string-match-p "eci:Reed" (prin1-to-string portable)))
    (should
     (equal (plist-get portable :engine-order)
            (plist-get emacsvox-test--routing-profile :engine-order)))))

(ert-deftest emacsvox-aural-routing-presets-are-staged-pure-transformations ()
  "Engine and language presets do not mutate their input profile."
  (let* ((input (copy-tree emacsvox-test--routing-profile))
         (ordered
          (emacsvox-aural-routing-apply-preset-to-data
           input 'dectalk-first))
         (language
          (emacsvox-aural-routing-apply-preset-to-data
           input 'native-language))
         (selector
          (car
           (plist-get (car (plist-get language :bindings)) :selectors))))
    (should (equal (plist-get ordered :engine-order)
                   '("dectalk" "eloquence" "winrt" "espeak")))
    (should (equal
             (plist-get (plist-get ordered :fallback) :engines)
             '("dectalk" "eloquence" "winrt" "espeak")))
    (should (eq (plist-get selector :kind) 'properties))
    (should (equal (plist-get selector :language) "en-AU"))
    (should (equal input emacsvox-test--routing-profile))))

(ert-deftest emacsvox-aural-routing-exports-one-non-evaluated-profile ()
  "Routing exchange round trips one profile and rejects trailing forms."
  (let* ((directory (make-temp-file "emacsvox-routing-export-" t))
         (file (expand-file-name "profile.el" directory)))
    (unwind-protect
        (progn
          (emacsvox-aural-export-routing-profile
           emacsvox-test--routing-profile file)
          (should
           (equal
            (emacsvox-aural-read-routing-profile file)
            (emacsvox-aural-validate-routing-profile-data
             emacsvox-test--routing-profile)))
          (write-region "\n(:another form)" nil file t 'silent)
          (should-error
           (emacsvox-aural-read-routing-profile file)
           :type 'emacsvox-aural-routing-profile-error))
      (delete-directory directory t))))

(provide 'emacsvox-aural-routing-profiles-tests)
;;; emacsvox-aural-routing-profiles-tests.el ends here
