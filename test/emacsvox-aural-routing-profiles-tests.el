;;; emacsvox-aural-routing-profiles-tests.el --- Voice routing tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Verify separate, data-only, machine-aware physical voice routing.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'omnivox-voices)
(require 'emacsvox-aural-routing-profiles)

(defconst emacsvox-test--routing-profile
  '(:schema-version 1
    :id workstation
    :summary "Local workstation routing"
    :engine-order ("eloquence" "dectalk" "winrt" "espeak")
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
         (emacsvox-aural-routing-profile-changed-hook nil)
         (omnivox-logical-voice-preferences nil)
         (omnivox-logical-voice-languages nil)
         (omnivox-engine-priority-ids nil)
         (omnivox-fallback-engine-ids '("espeak"))
         (omnivox-global-default-selector nil)
         (omnivox-allow-same-language-fallback t))
     ,@body))

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

(provide 'emacsvox-aural-routing-profiles-tests)
;;; emacsvox-aural-routing-profiles-tests.el ends here
