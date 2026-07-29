;;; emacsvox-aural-profiles-tests.el --- Presentation profile tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Test data validation, transactional application, persistence, and the spoken
;; profile manager.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-sounds)
(require 'emacsvox-aural-profiles)
(require 'emacsvox-aural-compatibility-voice)

(defmacro emacsvox-test--with-aural-profiles (&rest body)
  "Run BODY with isolated presentation scheme and profile state."
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
         (emacsvox-aural-active-profile nil)
         (emacsvox-aural-enabled-feature-fragments nil)
         (emacsvox-aural-feature-fragment-order nil)
         (emacsvox-aural-active-scheme 'default)
         (emacsvox-aural-voice-palette-override nil)
         (emacsvox-aural-active-scheme-changed-hook nil)
         (emacsvox-aural-effective-resource-pack-changed-hook nil)
         (emacsvox-aural-feature-fragments-changed-hook nil)
         (emacsvox-aural-profile-applied-hook nil)
         (emacsvox-aural-compatibility-voice-changed-hook nil)
         (voice-lock-mode t)
         (voice-lock-mode--set-explicitly nil)
         (emacsvox-aural-spatial-enabled t)
         (emacsvox-aural-spatial-speech-enabled t)
         (emacsvox-aural-spatial-cue-enabled t)
         (emacsvox-aural-spatial-output 'auto)
         (emacsvox-aural-spatial-maximum-separation 1.0)
         (emacsvox-aural-spatial-remapping 'normal)
         (emacsvox-sounds-current-pack 'chimes))
     (emacsvox-aural--register-default-scheme)
     (emacsvox-aural-register-feature-fragment
      '(:schema-version 1
        :id profile-feature
        :summary "Profile feature"
        :rules ())
      :built-in t
      :source "test")
     ,@body))

(defun emacsvox-test--profile-data (&optional id)
  "Return representative saved profile data named ID."
  (list
   :id (or id 'work)
   :summary "Focused work"
   :scheme 'default
   :feature-fragments '(profile-feature)
   :sound-pack 'chimes
   :voice-palette 'acss-default
   :compatibility-voice-enabled nil
   :spatial
   '(:enabled t :speech-enabled t :cue-enabled nil
     :output mono :maximum-separation 0.5 :remapping reverse)))

(ert-deftest emacsvox-aural-profiles-validate-component-references ()
  "Profiles reject unknown components and invalid compatibility state."
  (emacsvox-test--with-aural-profiles
    (should
     (emacsvox-aural-register-profile
      (emacsvox-test--profile-data)))
    (let ((bad
           (plist-put
            (emacsvox-test--profile-data 'bad)
            :feature-fragments '(missing))))
      (should-error
       (emacsvox-aural-register-profile bad)
       :type 'emacsvox-aural-scheme-error))
    (let ((bad
           (plist-put
            (emacsvox-test--profile-data 'bad)
            :voice-palette 'missing)))
      (should-error
       (emacsvox-aural-register-profile bad)
       :type 'emacsvox-aural-scheme-error))
    (let ((bad
           (plist-put
            (emacsvox-test--profile-data 'bad)
            :compatibility-voice-enabled 'sometimes)))
      (should-error
       (emacsvox-aural-register-profile bad)
       :type 'emacsvox-aural-scheme-error))))

(ert-deftest emacsvox-aural-profiles-apply-complete-configuration ()
  "Applying a profile switches all referenced settings and reports its ID."
  (emacsvox-test--with-aural-profiles
    (emacsvox-aural-register-profile (emacsvox-test--profile-data))
    (let (selected applied)
      (add-hook
       'emacsvox-aural-profile-applied-hook
       (lambda (id) (setq applied id)))
      (cl-letf
          (((symbol-function 'emacsvox-sounds-select-theme)
            (lambda (pack)
              (setq selected pack
                    emacsvox-sounds-current-pack pack))))
        (should (eq (emacsvox-aural-apply-profile 'work) 'work)))
      (should (eq applied 'work))
      (should (eq selected 'chimes))
      (should
       (equal
        emacsvox-aural-enabled-feature-fragments
        '(profile-feature)))
      (should (eq emacsvox-aural-voice-palette-override 'acss-default))
      (should (eq emacsvox-aural-active-profile 'work))
      (should (eq emacsvox-aural-spatial-output 'mono))
      (should (= emacsvox-aural-spatial-maximum-separation 0.5))
      (should-not emacsvox-aural-spatial-cue-enabled)
      (should-not
       (emacsvox-aural-compatibility-voice-enabled-p))
      (should
       (equal
        (aref (cadr (emacsvox-aural-profiles--row 'work)) 6)
        "off"))
      (should (emacsvox-aural-profile-current-p 'work)))))

(ert-deftest emacsvox-aural-profiles-target-source-compatibility-voice ()
  "Applying a profile changes only its selected source buffer's policy."
  (emacsvox-test--with-aural-profiles
    (emacsvox-aural-register-profile (emacsvox-test--profile-data))
    (let ((source (generate-new-buffer " *profile-source*"))
          (other (generate-new-buffer " *profile-other*")))
      (unwind-protect
          (progn
            (emacsvox-aural-set-compatibility-voice-enabled t source)
            (emacsvox-aural-set-compatibility-voice-enabled t other)
            (cl-letf
                (((symbol-function 'emacsvox-sounds-select-theme)
                  (lambda (pack)
                    (setq emacsvox-sounds-current-pack pack))))
              (emacsvox-aural-apply-profile 'work source))
            (should-not
             (emacsvox-aural-compatibility-voice-enabled-p source))
            (should
             (emacsvox-aural-compatibility-voice-enabled-p other))
            (should
             (eq (emacsvox-aural-profile-status 'work source) 'active))
            (should
             (eq (emacsvox-aural-profile-status 'work other) 'modified)))
        (kill-buffer source)
        (kill-buffer other)))))

(ert-deftest emacsvox-aural-profiles-old-data-leaves-compatibility-unchanged ()
  "Profiles without compatibility policy retain their historical behavior."
  (emacsvox-test--with-aural-profiles
    (let ((data
           (cl-loop
            for (key value) on (emacsvox-test--profile-data) by #'cddr
            unless (eq key :compatibility-voice-enabled)
            append (list key value))))
      (emacsvox-aural-register-profile data)
      (cl-letf
          (((symbol-function 'emacsvox-sounds-select-theme)
            (lambda (pack)
              (setq emacsvox-sounds-current-pack pack))))
        (emacsvox-aural-apply-profile 'work))
      (should (emacsvox-aural-compatibility-voice-enabled-p))
      (should (emacsvox-aural-profile-current-p 'work)))))

(ert-deftest emacsvox-aural-profiles-select-one-identical-profile ()
  "Identical saved configurations do not both appear active."
  (emacsvox-test--with-aural-profiles
    (emacsvox-aural-register-profile (emacsvox-test--profile-data 'first))
    (emacsvox-aural-register-profile (emacsvox-test--profile-data 'second))
    (cl-letf
        (((symbol-function 'emacsvox-sounds-select-theme)
          (lambda (pack)
            (setq emacsvox-sounds-current-pack pack))))
      (emacsvox-aural-apply-profile 'first)
      (should (eq (emacsvox-aural-profile-status 'first) 'active))
      (should (eq (emacsvox-aural-profile-status 'second) 'inactive))
      (emacsvox-aural-apply-profile 'second)
      (should (eq (emacsvox-aural-profile-status 'first) 'inactive))
      (should (eq (emacsvox-aural-profile-status 'second) 'active)))))

(ert-deftest emacsvox-aural-profiles-selected-profile-becomes-modified ()
  "Changing live configuration retains selected identity as modified."
  (emacsvox-test--with-aural-profiles
    (emacsvox-aural-register-profile (emacsvox-test--profile-data))
    (cl-letf
        (((symbol-function 'emacsvox-sounds-select-theme)
          (lambda (pack)
            (setq emacsvox-sounds-current-pack pack))))
      (emacsvox-aural-apply-profile 'work))
    (emacsvox-aural-set-enabled-feature-fragments nil)
    (should (eq emacsvox-aural-active-profile 'work))
    (should (eq (emacsvox-aural-profile-status 'work) 'modified))
    (should-not (emacsvox-aural-profile-current-p 'work))
    (should (eq (emacsvox-aural-current-profile-id) 'work))
    (should
     (equal
      (aref (cadr (emacsvox-aural-profiles--row 'work)) 1)
      "modified"))))

(ert-deftest emacsvox-aural-profiles-report-invalid-selected-profile ()
  "A selected profile with a missing component is invalid, not modified."
  (emacsvox-test--with-aural-profiles
    (emacsvox-aural-register-profile (emacsvox-test--profile-data))
    (setq emacsvox-aural-active-profile 'work)
    (remhash 'default emacsvox-aural-scheme-registry)
    (should (eq (emacsvox-aural-profile-status 'work) 'invalid))))

(ert-deftest emacsvox-aural-profiles-manager-maintains-selected-identity ()
  "Profile lifecycle commands update only the intended selected identity."
  (emacsvox-test--with-aural-profiles
    (let ((new-ids '(first copied renamed))
          (source (generate-new-buffer " *profile-manager-source*")))
      (unwind-protect
          (with-temp-buffer
            (emacsvox-aural-profiles-mode)
            (emacsvox-aural-inspection-attach-source source)
            (cl-letf
                (((symbol-function 'emacsvox-aural-profiles--read-new-id)
                  (lambda (&rest _) (pop new-ids)))
                 ((symbol-function 'read-string)
                  (lambda (&rest _) "Profile purpose"))
                 ((symbol-function 'emacsvox-aural-save-user-data) #'ignore)
                 ((symbol-function 'tts-speak) #'ignore)
                 ((symbol-function 'emacsvox-icon) #'ignore)
                 ((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
              (emacsvox-aural-profiles-create)
              (should (eq emacsvox-aural-active-profile 'first))
              (emacsvox-aural-profiles-copy)
              (should (eq emacsvox-aural-active-profile 'first))
              (emacsvox-aural-profiles-update-from-current)
              (should (eq emacsvox-aural-active-profile 'copied))
              (emacsvox-aural-profiles-rename)
              (should (eq emacsvox-aural-active-profile 'renamed))
              (emacsvox-aural-profiles-delete)
              (should-not emacsvox-aural-active-profile)
              (should (emacsvox-aural-profile-entry 'first))
              (should-not (emacsvox-aural-profile-entry 'renamed))))
        (kill-buffer source)))))

(ert-deftest emacsvox-aural-profiles-manager-mutations-are-transactional ()
  "Failed persistence publishes none of the five profile mutations."
  (dolist
      (case
       '((emacsvox-aural-profiles-create
          created ("created" "work") created)
         (emacsvox-aural-profiles-copy
          copied ("copied" "work") work)
         (emacsvox-aural-profiles-update-from-current
          unused ("work") work)
         (emacsvox-aural-profiles-rename
          renamed ("renamed") renamed)
         (emacsvox-aural-profiles-delete
          unused nil nil)))
    (emacsvox-test--with-aural-profiles
      (emacsvox-aural-register-profile
       (emacsvox-test--profile-data)
       :source emacsvox-aural-schemes-file)
      (setq
       emacsvox-aural-active-profile 'work
       emacsvox-aural-enabled-feature-fragments '(profile-feature)
       emacsvox-aural-spatial-output 'mono)
      (let* ((command (nth 0 case))
             (new-id (nth 1 case))
             (expected-ids (nth 2 case))
             (expected-active (nth 3 case))
             (original-registry emacsvox-aural-profile-registry)
             (original-entry (emacsvox-aural-profile-entry 'work))
             (original-live-state
              (list
               (emacsvox-aural--capture-coordinated-state)
               emacsvox-aural-spatial-output))
             staged-registry
             staged-ids
             staged-active)
        (cl-letf
            (((symbol-function 'emacsvox-aural-profiles--at-point-or-read)
              (lambda () 'work))
             ((symbol-function 'emacsvox-aural-profiles--read-new-id)
              (lambda (&rest _) new-id))
             ((symbol-function 'read-string)
              (lambda (&rest _) "Transactional profile"))
             ((symbol-function 'yes-or-no-p) (lambda (&rest _) t))
             ((symbol-function 'emacsvox-aural-save-user-data)
              (lambda (&rest _)
                (setq
                 staged-registry emacsvox-aural-profile-registry
                 staged-ids (emacsvox-aural-profile-candidates)
                 staged-active emacsvox-aural-active-profile)
                (error "Simulated persistence failure"))))
          (should-error (funcall command)))
        (should-not (eq staged-registry original-registry))
        (should (equal staged-ids expected-ids))
        (should (eq staged-active expected-active))
        (should (eq emacsvox-aural-profile-registry original-registry))
        (should (eq (emacsvox-aural-profile-entry 'work) original-entry))
        (should (eq emacsvox-aural-active-profile 'work))
        (should
         (equal
          (list
           (emacsvox-aural--capture-coordinated-state)
           emacsvox-aural-spatial-output)
          original-live-state))))))

(ert-deftest emacsvox-aural-profiles-application-rolls-back-on-error ()
  "A failed concrete sound switch restores every already changed setting."
  (emacsvox-test--with-aural-profiles
    (emacsvox-aural-register-profile (emacsvox-test--profile-data))
    (let ((old-spatial emacsvox-aural-spatial-output)
          fragment-notifications
          scheme-notifications)
      (add-hook
       'emacsvox-aural-feature-fragments-changed-hook
       (lambda ()
         (push
          (copy-sequence emacsvox-aural-enabled-feature-fragments)
          fragment-notifications)))
      (add-hook
       'emacsvox-aural-active-scheme-changed-hook
       (lambda ()
         (push emacsvox-aural-active-scheme scheme-notifications)))
      (cl-letf
          (((symbol-function 'emacsvox-sounds-select-theme)
            (lambda (&rest _) (error "sound switch failed"))))
        (should-error (emacsvox-aural-apply-profile 'work)))
      (should (eq emacsvox-aural-active-scheme 'default))
      (should-not emacsvox-aural-enabled-feature-fragments)
      (should-not emacsvox-aural-voice-palette-override)
      (should-not emacsvox-aural-active-profile)
      (should (eq emacsvox-aural-spatial-output old-spatial))
      (should (eq emacsvox-sounds-current-pack 'chimes))
      (should-not fragment-notifications)
      (should-not scheme-notifications))))

(ert-deftest emacsvox-aural-profiles-roll-back-compatibility-voice ()
  "A compatibility hook failure restores profile and source-buffer state."
  (emacsvox-test--with-aural-profiles
    (emacsvox-aural-register-profile (emacsvox-test--profile-data))
    (let ((source (generate-new-buffer " *profile-rollback-source*")))
      (unwind-protect
          (progn
            (emacsvox-aural-set-compatibility-voice-enabled t source)
            (add-hook
             'emacsvox-aural-compatibility-voice-changed-hook
             (lambda (_buffer enabled)
               (unless enabled
                 (error "Compatibility observer failed"))))
            (cl-letf
                (((symbol-function 'emacsvox-sounds-select-theme)
                  (lambda (pack)
                    (setq emacsvox-sounds-current-pack pack))))
              (should-error
               (emacsvox-aural-apply-profile 'work source)))
            (should
             (emacsvox-aural-compatibility-voice-enabled-p source))
            (should-not emacsvox-aural-active-profile)
            (should-not emacsvox-aural-enabled-feature-fragments)
            (should-not emacsvox-aural-voice-palette-override))
        (kill-buffer source)))))

(ert-deftest emacsvox-aural-profiles-persist-and-load-references ()
  "Current storage atomically preserves profiles referencing personal data."
  (emacsvox-test--with-aural-profiles
    (let* ((directory (make-temp-file "emacsvox-profiles-" t))
           (emacsvox-aural-schemes-file
            (expand-file-name "aural.el" directory)))
      (unwind-protect
          (progn
            (emacsvox-aural-register-profile
             (emacsvox-test--profile-data)
             :source emacsvox-aural-schemes-file)
            (setq emacsvox-aural-active-profile 'work)
            (emacsvox-aural-save-user-data)
            (should
             (eq
              (plist-get
               (emacsvox-aural-read-user-data) :schema-version)
              6))
            (should
             (eq
              (plist-get
               (emacsvox-aural-read-user-data) :active-profile)
              'work))
            (setq emacsvox-aural-profile-registry
                  (make-hash-table :test #'eq)
                  emacsvox-aural-active-profile nil)
            (emacsvox-aural-load-user-data)
            (should (eq emacsvox-aural-active-profile 'work))
            (should
             (equal
              (emacsvox-aural-profile-entry-data
               (emacsvox-aural-profile-entry 'work))
              (emacsvox-test--profile-data))))
        (delete-directory directory t)))))

(ert-deftest emacsvox-aural-profiles-capture-current-configuration ()
  "Saving current settings produces a complete data-only profile."
  (emacsvox-test--with-aural-profiles
    (setq
     emacsvox-aural-enabled-feature-fragments '(profile-feature)
     emacsvox-aural-spatial-remapping 'center)
    (let ((data
           (emacsvox-aural-capture-profile-data
            'captured "Captured configuration")))
      (should (eq (plist-get data :scheme) 'default))
      (should
       (equal
        (plist-get data :feature-fragments)
        '(profile-feature)))
      (should (eq (plist-get data :sound-pack) 'chimes))
      (should
       (plist-get data :compatibility-voice-enabled))
      (should
       (eq
        (plist-get (plist-get data :spatial) :remapping)
        'center))
      (should (emacsvox-aural--validate-profile-data data))
      (emacsvox-aural-register-profile data)
      (setq emacsvox-aural-active-profile 'captured)
      (should
       (equal
        (aref (cadr (emacsvox-aural-profiles--row 'captured)) 6)
        "on"))
      (should (eq (emacsvox-aural-profile-status 'captured) 'active)))))

(ert-deftest emacsvox-aural-profiles-manager-speaks-cells-and-boundaries ()
  "The profile manager follows the shared accessible table contract."
  (emacsvox-test--with-aural-profiles
    (emacsvox-aural-register-profile (emacsvox-test--profile-data))
    (let ((source (generate-new-buffer " *profile-cells-source*"))
          spoken)
      (unwind-protect
          (with-temp-buffer
            (emacsvox-aural-profiles-mode)
            (emacsvox-aural-inspection-attach-source source)
            (should
             (eq
              (lookup-key emacsvox-aural-profiles-mode-map (kbd "h"))
              #'emacsvox-aural))
            (should
             (eq
              (key-binding (kbd "q"))
              #'emacsvox-aural-quit))
            (cl-letf (((symbol-function 'tts-speak)
                       (lambda (text) (push text spoken)))
                      ((symbol-function 'emacsvox-icon) #'ignore))
              (emacsvox-aural-profiles-refresh)
              (emacsvox-aural-profiles-speak-current-cell)
              (should (string-match-p "Profile" (car spoken)))
              (goto-char (point-min))
              (emacsvox-aural-profiles-previous)
              (should
               (string-match-p
                "top of presentation profiles" (car spoken)))))
        (kill-buffer source)))))

(provide 'emacsvox-aural-profiles-tests)
;;; emacsvox-aural-profiles-tests.el ends here
