;;; emacsvox-aural-profiles-tests.el --- Presentation profile tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Test data validation, transactional application, persistence, and the spoken
;; profile manager.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-sounds)
(require 'emacsvox-aural-profiles)

(defmacro emacsvox-test--with-aural-profiles (&rest body)
  "Run BODY with isolated presentation scheme and profile state."
  (declare (indent 0) (debug t))
  `(let ((emacsvox-aural-scheme-registry
          (make-hash-table :test #'eq))
         (emacsvox-aural-module-fragment-registry
          (make-hash-table :test #'eq))
         (emacsvox-aural-feature-fragment-registry
          (make-hash-table :test #'eq))
         (emacsvox-aural-profile-registry
          (make-hash-table :test #'eq))
         (emacsvox-aural-enabled-feature-fragments nil)
         (emacsvox-aural-active-scheme 'default)
         (emacsvox-aural-voice-palette-override nil)
         (emacsvox-aural-active-scheme-changed-hook nil)
         (emacsvox-aural-feature-fragments-changed-hook nil)
         (emacsvox-aural-profile-applied-hook nil)
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
   :spatial
   '(:enabled t :speech-enabled t :cue-enabled nil
     :output mono :maximum-separation 0.5 :remapping reverse)))

(ert-deftest emacsvox-aural-profiles-validate-component-references ()
  "Profiles reject unknown schemes, fragments, packs, and palettes."
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
      (should (eq emacsvox-aural-spatial-output 'mono))
      (should (= emacsvox-aural-spatial-maximum-separation 0.5))
      (should-not emacsvox-aural-spatial-cue-enabled)
      (should (emacsvox-aural-profile-current-p 'work)))))

(ert-deftest emacsvox-aural-profiles-application-rolls-back-on-error ()
  "A failed concrete sound switch restores every already changed setting."
  (emacsvox-test--with-aural-profiles
    (emacsvox-aural-register-profile (emacsvox-test--profile-data))
    (let ((old-spatial emacsvox-aural-spatial-output))
      (cl-letf
          (((symbol-function 'emacsvox-sounds-select-theme)
            (lambda (&rest _) (error "sound switch failed"))))
        (should-error (emacsvox-aural-apply-profile 'work)))
      (should (eq emacsvox-aural-active-scheme 'default))
      (should-not emacsvox-aural-enabled-feature-fragments)
      (should-not emacsvox-aural-voice-palette-override)
      (should (eq emacsvox-aural-spatial-output old-spatial))
      (should (eq emacsvox-sounds-current-pack 'chimes)))))

(ert-deftest emacsvox-aural-profiles-persist-and-load-references ()
  "Version 3 storage atomically preserves profiles referencing personal data."
  (emacsvox-test--with-aural-profiles
    (let* ((directory (make-temp-file "emacsvox-profiles-" t))
           (emacsvox-aural-schemes-file
            (expand-file-name "aural.el" directory)))
      (unwind-protect
          (progn
            (emacsvox-aural-register-profile
             (emacsvox-test--profile-data)
             :source emacsvox-aural-schemes-file)
            (emacsvox-aural-save-user-data)
            (should
             (eq
              (plist-get
               (emacsvox-aural-read-user-data) :schema-version)
              3))
            (setq emacsvox-aural-profile-registry
                  (make-hash-table :test #'eq))
            (emacsvox-aural-load-user-data)
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
       (eq
        (plist-get (plist-get data :spatial) :remapping)
        'center))
      (should (emacsvox-aural--validate-profile-data data)))))

(ert-deftest emacsvox-aural-profiles-manager-speaks-cells-and-boundaries ()
  "The profile manager follows the shared accessible table contract."
  (emacsvox-test--with-aural-profiles
    (emacsvox-aural-register-profile (emacsvox-test--profile-data))
    (let (spoken)
      (with-temp-buffer
        (emacsvox-aural-profiles-mode)
        (should
         (eq
          (lookup-key emacsvox-aural-profiles-mode-map (kbd "h"))
          #'emacsvox-aural))
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
            "top of presentation profiles" (car spoken))))))))

(provide 'emacsvox-aural-profiles-tests)
;;; emacsvox-aural-profiles-tests.el ends here
