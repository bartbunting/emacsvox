;;; emacsvox-aural-resources-tests.el --- Aural resource tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Test cue intent, requirement profiles, sound-pack inheritance and fallback,
;; scheme-derived requirements, and existing ACSS voice-palette exposure.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-aural-resources)

(defvar emacsvox-test--sound-pack-read-evaluated nil)

(defconst emacsvox-test--sounds-directory
  (expand-file-name
   "../sounds"
   (file-name-directory (or load-file-name buffer-file-name)))
  "Bundled sounds directory used by resource-provider tests.")

(defun emacsvox-test--resource-file (directory name)
  "Create empty Ogg NAME in DIRECTORY and return its path."
  (let ((file (expand-file-name (concat name ".ogg") directory)))
    (write-region "" nil file nil 'silent)
    file))

(defun emacsvox-test--sound-pack-manifest (directory data)
  "Write sound-pack manifest DATA in DIRECTORY and return its path."
  (let ((file
         (expand-file-name
          emacsvox-aural-resource-pack-manifest directory)))
    (write-region data nil file nil 'silent)
    file))

(defmacro emacsvox-test--with-resource-directory (&rest body)
  "Run BODY with temporary parent and child resource directories."
  (declare (indent 0) (debug t))
  `(let* ((root (make-temp-file "emacsvox-resources-" t))
          (parent-directory (expand-file-name "parent" root))
          (child-directory (expand-file-name "child" root)))
     (make-directory parent-directory)
     (make-directory child-directory)
     (unwind-protect
         (progn ,@body)
       (delete-directory root t))))

(defmacro emacsvox-test--with-empty-resource-packs (&rest body)
  "Run BODY with an isolated resource-pack registry."
  (declare (indent 0) (debug t))
  `(let ((emacsvox-aural-resource-pack-registry
          (make-hash-table :test #'eq))
         (emacsvox-aural-resource-overlay-registry
          (make-hash-table :test #'eq))
         (emacsvox-aural-personal-sound-packs-directory nil)
         (emacsvox-aural-disabled-resource-overlays nil)
         (emacsvox-aural-resource-packs-changed-hook nil)
         (emacsvox-aural-resource-overlays-changed-hook nil)
         (emacsvox-aural-resource-generation 0)
         (emacsvox-aural--effective-assets-cache
          (make-hash-table :test #'equal))
         (emacsvox-aural--resource-spatialization-cache
          (make-hash-table :test #'equal)))
     ,@body))

(ert-deftest emacsvox-aural-resources-cache-effective-assets-by-generation ()
  "Cue resolution reuses cached assets without exposing the cached table."
  (emacsvox-test--with-resource-directory
    (emacsvox-test--with-empty-resource-packs
      (emacsvox-test--resource-file parent-directory "button")
      (emacsvox-aural-register-resource-pack
       'test
       :summary "Test"
       :directory parent-directory)
      (let ((builds 0)
            (original
             (symbol-function
              'emacsvox-aural--build-effective-assets)))
        (cl-letf
            (((symbol-function 'emacsvox-aural--build-effective-assets)
              (lambda (&rest arguments)
                (cl-incf builds)
                (apply original arguments))))
          (let ((first (emacsvox-aural-effective-assets 'test))
                (second (emacsvox-aural-effective-assets 'test)))
            (should (= builds 1))
            (should-not (eq first second))
            (puthash 'private "/tmp/private.ogg" first)
            (should-not (gethash 'private second))
            (should-not
             (gethash
              'private
              (emacsvox-aural-effective-assets 'test))))
          (emacsvox-aural-resolve-cue 'button 'test)
          (should (= builds 1))
          (emacsvox-test--resource-file parent-directory "item")
          (let ((generation emacsvox-aural-resource-generation))
            (emacsvox-aural-refresh-resource-pack 'test)
            (should
             (> emacsvox-aural-resource-generation generation)))
          (should
           (gethash
            'item
            (emacsvox-aural-effective-assets 'test)))
          (should (= builds 2)))))))

(ert-deftest emacsvox-aural-resources-cache-ownership-by-generation ()
  "Spatial ownership is recomputed only after a resource change."
  (emacsvox-test--with-resource-directory
    (emacsvox-test--with-empty-resource-packs
      (let ((resource
             (emacsvox-test--resource-file
              parent-directory "button")))
        (emacsvox-aural-register-resource-pack
         'test
         :summary "Test"
         :directory parent-directory
         :default-spatialization 'stereo)
        (let ((computations 0)
              (original
               (symbol-function
                'emacsvox-aural--compute-resource-spatialization)))
          (cl-letf
              (((symbol-function
                 'emacsvox-aural--compute-resource-spatialization)
                (lambda (&rest arguments)
                  (cl-incf computations)
                  (apply original arguments))))
            (should
             (eq
              (emacsvox-aural-resource-spatialization resource 'test)
              'stereo))
            (should
             (eq
              (emacsvox-aural-resource-spatialization resource 'test)
              'stereo))
            (should (= computations 1))
            (emacsvox-aural--resource-packs-changed 'test)
            (should
             (eq
              (emacsvox-aural-resource-spatialization resource 'test)
              'stereo))
            (should (= computations 2))))))))

(ert-deftest emacsvox-aural-resources-register-intent-for-every-bundled-cue ()
  "Shared and prompt assets have registered intent descriptions."
  (should (= (length emacsvox-aural-legacy-complete-cues) 55))
  (dolist
      (definition
       (append
        emacsvox-aural--legacy-cue-definitions
        emacsvox-aural--prompt-cue-definitions))
    (let ((cue (emacsvox-aural-cue (car definition))))
      (should cue)
      (should
       (equal
        (emacsvox-aural-cue-summary cue)
        (cadr definition)))))
  (should-not (memq 'shutdown emacsvox-aural-legacy-complete-cues)))

(ert-deftest emacsvox-aural-resources-register-default-line-tones ()
  "Built-in line tones retain the existing pitches and durations by name."
  (should
   (equal
    (emacsvox-aural-tone-candidates)
    '("line-decoration" "line-empty" "line-separator"
      "line-unspeakable" "line-whitespace")))
  (dolist
      (expected
       '((line-empty 130.8 150 t)
         (line-whitespace 261.6 150 t)
         (line-separator 523.3 150 t)
         (line-decoration 1047 150 t)
         (line-unspeakable 2093 150 t)))
    (let ((tone (emacsvox-aural-tone (car expected))))
      (should tone)
      (should (= (emacsvox-aural-tone-pitch tone) (nth 1 expected)))
      (should (= (emacsvox-aural-tone-duration tone) (nth 2 expected)))
      (should (eq (emacsvox-aural-tone-force tone) (nth 3 expected))))))

(ert-deftest emacsvox-aural-resources-reject-invalid-tone-definitions ()
  "The tone registry accepts only safe, complete concrete definitions."
  (let ((emacsvox-aural-tone-registry (make-hash-table :test #'eq)))
    (emacsvox-aural-register-tone
     'valid :summary "Valid" :pitch 440 :duration 100 :force nil)
    (should-error
     (emacsvox-aural-register-tone
      'valid :summary "Duplicate" :pitch 220 :duration 50)
     :type 'emacsvox-aural-resource-error)
    (dolist
        (definition
         '((bad-pitch :summary "Bad" :pitch 0 :duration 50)
           (bad-duration :summary "Bad" :pitch 220 :duration -1)
           (bad-force :summary "Bad" :pitch 220 :duration 50 :force force)))
      (should-error
       (apply #'emacsvox-aural-register-tone definition)
       :type 'emacsvox-aural-resource-error))))

(ert-deftest emacsvox-aural-resources-bundled-packs-satisfy-profile ()
  "Chimes and 3d satisfy the shared legacy-complete requirements."
  (emacsvox-test--with-empty-resource-packs
    (emacsvox-aural-register-bundled-resources
     emacsvox-test--sounds-directory)
    (should (emacsvox-aural-validate-resource-registry))
    (dolist (id '(chimes 3d))
      (let ((report (emacsvox-aural-validate-resource-pack id)))
        (should (emacsvox-aural-resource-report-valid report))
        (should-not
         (emacsvox-aural-resource-report-missing-required report))
        (should-not
         (emacsvox-aural-resource-report-unknown-assets report))))
    (should
     (eq
      (emacsvox-aural-resource-pack-default-spatialization
       (emacsvox-aural-resource-pack '3d))
      'pre-spatialized))
    (should
      (eq
       (emacsvox-aural-resource-pack-default-spatialization
        (emacsvox-aural-resource-pack 'chimes))
       'neutral))))

(ert-deftest emacsvox-aural-resources-discover-and-remove-local-packs ()
  "Pack candidates dynamically track qualifying immediate directories."
  (let* ((root (make-temp-file "emacsvox-pack-discovery-" t))
         (clock (expand-file-name "clock" root))
         (bart (expand-file-name "bart" root))
         (emacsvox-aural-resource-pack-registry
          (make-hash-table :test #'eq))
         (emacsvox-aural--resource-pack-discovery-registry
          emacsvox-aural-resource-pack-registry)
         (emacsvox-aural-personal-sound-packs-directory nil)
         (emacsvox-aural-resource-pack-discovery-roots nil))
    (unwind-protect
        (progn
          (make-directory clock)
          (emacsvox-test--resource-file clock "chime-15")
          (emacsvox-aural-register-bundled-resources root)
          (should-not (emacsvox-aural-resource-pack 'clock))
          (make-directory bart)
          (dolist (cue emacsvox-aural-legacy-complete-cues)
            (emacsvox-test--resource-file bart (symbol-name cue)))
          (should
           (member
            "bart"
            (emacsvox-aural-resource-pack-candidates 'sound)))
          (let ((pack (emacsvox-aural-resource-pack 'bart)))
            (should (eq (emacsvox-aural-resource-pack-origin pack)
                        'discovered))
            (should
             (equal
              (emacsvox-aural-resource-pack-summary pack)
              "Automatically discovered Bart sound pack"))
            (should
             (equal
              (emacsvox-aural-resource-pack-profiles pack)
              '(legacy-complete))))
          (delete-directory bart t)
          (should-not
           (member
            "bart"
            (emacsvox-aural-resource-pack-candidates 'sound)))
          (should-not (emacsvox-aural-resource-pack 'bart)))
      (delete-directory root t))))

(ert-deftest emacsvox-aural-resources-notify-after-discovery-removal ()
  "A completed discovery transaction reports removal exactly once."
  (let* ((root (make-temp-file "emacsvox-pack-removal-notify-" t))
         (bart (expand-file-name "bart" root))
         (emacsvox-aural-resource-pack-registry
          (make-hash-table :test #'eq))
         (emacsvox-aural-resource-overlay-registry
          (make-hash-table :test #'eq))
         (emacsvox-aural-resource-packs-changed-hook nil)
         notifications)
    (unwind-protect
        (progn
          (make-directory bart)
          (emacsvox-test--resource-file bart "button")
          (add-hook
           'emacsvox-aural-resource-packs-changed-hook
           (lambda (id) (push id notifications)))
          (emacsvox-aural-discover-resource-packs root)
          (setq notifications nil)
          (delete-directory bart t)
          (emacsvox-aural-discover-resource-packs root)
          (should-not (emacsvox-aural-resource-pack 'bart))
          (should (equal notifications '(nil))))
      (delete-directory root t))))

(ert-deftest emacsvox-aural-resources-prefer-personal-packs-to-legacy-root ()
  "The personal pack root wins over, then falls back to, legacy `sounds/'."
  (let* ((root (make-temp-file "emacsvox-pack-roots-" t))
         (personal-root (make-temp-file "emacsvox-personal-packs-" t))
         (legacy-bart (expand-file-name "bart" root))
         (personal-bart (expand-file-name "bart" personal-root))
         (emacsvox-aural-resource-pack-registry
          (make-hash-table :test #'eq))
         (emacsvox-aural--resource-pack-discovery-registry
          emacsvox-aural-resource-pack-registry)
         (emacsvox-aural-resource-pack-discovery-roots nil)
         (emacsvox-aural-personal-sound-packs-directory personal-root))
    (unwind-protect
        (progn
          (make-directory legacy-bart)
          (emacsvox-test--resource-file legacy-bart "button")
          (emacsvox-aural-register-bundled-resources root)
          (should
           (equal
            (emacsvox-aural-resource-pack-directory
             (emacsvox-aural-resource-pack 'bart))
            legacy-bart))
          (make-directory personal-bart)
          (emacsvox-test--resource-file personal-bart "button")
          (emacsvox-aural-refresh-discovered-resource-packs)
          (should
           (equal
            (emacsvox-aural-resource-pack-directory
             (emacsvox-aural-resource-pack 'bart))
            personal-bart))
          (should
           (equal
            (car emacsvox-aural-resource-pack-discovery-roots)
            (file-name-as-directory personal-root)))
          (delete-directory personal-bart t)
          (emacsvox-aural-refresh-discovered-resource-packs)
          (should
           (equal
            (emacsvox-aural-resource-pack-directory
             (emacsvox-aural-resource-pack 'bart))
            legacy-bart)))
      (delete-directory root t)
      (delete-directory personal-root t))))

(ert-deftest emacsvox-aural-resources-discover-manifested-partial-pack ()
  "A data manifest can define inheritance and spatialization for a partial pack."
  (let* ((root (make-temp-file "emacsvox-pack-manifest-" t))
         (chimes (expand-file-name "packs/chimes" root))
         (partial (expand-file-name "personal-overlay" root))
         (emacsvox-aural-resource-pack-registry
          (make-hash-table :test #'eq))
         (emacsvox-aural-personal-sound-packs-directory nil))
    (unwind-protect
        (progn
          (make-directory chimes t)
          (make-directory partial)
          (emacsvox-test--resource-file chimes "button")
          (let ((item (emacsvox-test--resource-file partial "item")))
            (emacsvox-test--sound-pack-manifest
             partial
             (concat
              "(:schema-version 1\n"
              " :summary \"Personal overlay\"\n"
              " :parent chimes\n"
              " :profiles nil\n"
              " :default-spatialization stereo)\n"))
            (emacsvox-aural-register-bundled-resources root)
            (should
             (eq
              (emacsvox-aural-resource-pack-origin
               (emacsvox-aural-resource-pack 'chimes))
              'explicit))
            (let ((pack
                   (emacsvox-aural-resource-pack 'personal-overlay)))
              (should pack)
              (should (eq (emacsvox-aural-resource-pack-parent pack)
                          'chimes))
              (should
               (eq
                (emacsvox-aural-resource-pack-default-spatialization pack)
                'stereo))
              (should
               (equal
                (emacsvox-aural-resolve-cue
                 'button 'personal-overlay)
                (expand-file-name "button.ogg" chimes)))
              (should
               (equal
                (emacsvox-aural-resolve-cue 'item 'personal-overlay)
                item))
              (should
               (emacsvox-aural-resource-report-valid
                (emacsvox-aural-validate-resource-pack
                 'personal-overlay))))
            (emacsvox-test--sound-pack-manifest
             partial
             (concat
              "(:schema-version 1\n"
              " :summary \"Renamed overlay\"\n"
              " :parent chimes\n"
              " :profiles nil\n"
              " :default-spatialization neutral)\n"))
            (emacsvox-aural-discover-resource-packs root)
            (let ((pack
                   (emacsvox-aural-resource-pack 'personal-overlay)))
              (should
               (equal
                (emacsvox-aural-resource-pack-summary pack)
                "Renamed overlay"))
              (should
               (eq
                (emacsvox-aural-resource-pack-default-spatialization pack)
                'neutral)))
            (emacsvox-test--sound-pack-manifest
             partial
             (concat
              "(:schema-version 1\n"
              " :summary \"Invalid overlay\"\n"
              " :parent missing-pack)\n"))
            (should-error
             (emacsvox-aural-discover-resource-packs root)
             :type 'emacsvox-aural-resource-error)
            (should
             (equal
              (emacsvox-aural-resource-pack-summary
               (emacsvox-aural-resource-pack 'personal-overlay))
              "Renamed overlay"))))
      (delete-directory root t))))

(ert-deftest emacsvox-aural-resources-never-evaluate-pack-manifests ()
  "Dynamic discovery disables reader evaluation in sound-pack manifests."
  (let* ((root (make-temp-file "emacsvox-pack-safe-read-" t))
         (pack (expand-file-name "unsafe" root))
         (emacsvox-aural-resource-pack-registry
          (make-hash-table :test #'eq)))
    (unwind-protect
        (progn
          (make-directory pack)
          (emacsvox-test--sound-pack-manifest
           pack
           (concat
            "#.(progn\n"
            "    (setq emacsvox-test--sound-pack-read-evaluated t)\n"
            "    '(:schema-version 1))\n"))
          (setq emacsvox-test--sound-pack-read-evaluated nil)
          (let ((read-eval t))
            (should-error
             (emacsvox-aural-discover-resource-packs root)
             :type 'emacsvox-aural-resource-error))
          (should-not emacsvox-test--sound-pack-read-evaluated))
      (delete-directory root t))))

(ert-deftest emacsvox-aural-resources-resolve-optional-and-legacy-fallbacks ()
  "Optional shutdown and compatibility names resolve to available assets."
  (emacsvox-test--with-empty-resource-packs
    (emacsvox-aural-register-bundled-resources
     emacsvox-test--sounds-directory)
    (should
     (string-suffix-p
      "/packs/chimes/shutdown.ogg"
      (emacsvox-aural-resolve-cue 'shutdown 'chimes t)))
    (should
     (string-suffix-p
      "/packs/3d/close-object.ogg"
      (emacsvox-aural-resolve-cue 'shutdown '3d t)))
    (should
     (string-suffix-p
      "/prompts/startup.ogg"
      (emacsvox-aural-resolve-cue 'emacsvox '3d t)))
    (should
     (string-suffix-p
      "/packs/3d/repeat-end.ogg"
      (emacsvox-aural-resolve-cue 'repeat-stop '3d t)))
    (should
     (string-suffix-p
      "/packs/3d/deselect-object.ogg"
      (emacsvox-aural-resolve-cue 'unmark-object '3d t)))))

(ert-deftest emacsvox-aural-resources-require-button-for-standalone-pack ()
  "A sound pack without inherited button fallback is not standalone-valid."
  (emacsvox-test--with-resource-directory
    (emacsvox-test--with-empty-resource-packs
      (emacsvox-test--resource-file parent-directory "item")
      (emacsvox-aural-register-resource-pack
       'partial
       :summary "Partial"
       :directory parent-directory)
      (let ((report (emacsvox-aural-validate-resource-pack 'partial)))
        (should-not (emacsvox-aural-resource-report-valid report))
        (should
         (equal
          (emacsvox-aural-resource-report-missing-required report)
          '(button)))))))

(ert-deftest emacsvox-aural-resources-inherit-and-overlay-assets ()
  "A child pack inherits fallback assets and overlays matching names."
  (emacsvox-test--with-resource-directory
    (emacsvox-test--with-empty-resource-packs
      (let ((button
             (emacsvox-test--resource-file parent-directory "button"))
            (parent-item
             (emacsvox-test--resource-file parent-directory "item"))
            (child-item
             (emacsvox-test--resource-file child-directory "item")))
        (emacsvox-aural-register-resource-pack
         'parent :summary "Parent" :directory parent-directory)
        (emacsvox-aural-register-resource-pack
         'child
         :summary "Child"
         :directory child-directory
         :parent 'parent)
        (should
         (equal
          (emacsvox-aural-resolve-cue 'button 'child)
          button))
        (should-not (equal parent-item child-item))
        (should
         (equal
          (emacsvox-aural-resolve-cue 'item 'child)
          child-item))
        (should
         (emacsvox-aural-resource-report-valid
         (emacsvox-aural-validate-resource-pack 'child)))))))

(ert-deftest emacsvox-aural-resources-spatialization-follows-asset-owner ()
  "An inherited asset retains its provider's spatialization metadata."
  (emacsvox-test--with-resource-directory
    (emacsvox-test--with-empty-resource-packs
      (let ((parent-item
             (emacsvox-test--resource-file parent-directory "item"))
            (child-button
             (emacsvox-test--resource-file child-directory "button")))
        (emacsvox-aural-register-resource-pack
         'parent
         :summary "Pre-spatialized parent"
         :directory parent-directory
         :default-spatialization 'pre-spatialized)
        (emacsvox-aural-register-resource-pack
         'child
         :summary "Neutral child"
         :directory child-directory
         :parent 'parent)
        (should
         (eq
          (emacsvox-aural-resource-spatialization
           (emacsvox-aural-resolve-cue 'item 'child)
           'child)
          'pre-spatialized))
        (should
         (eq
          (emacsvox-aural-resource-spatialization child-button 'child)
          'neutral))
        (should
         (equal
          (emacsvox-aural-resolve-cue 'item 'child)
          parent-item))))))

(ert-deftest emacsvox-aural-resources-compose-module-earcon-overlays ()
  "The active pack overrides a module default before its generic fallback."
  (let ((emacsvox-aural-cue-registry
         (copy-hash-table emacsvox-aural-cue-registry)))
    (emacsvox-test--with-resource-directory
      (emacsvox-test--with-empty-resource-packs
        (let* ((plain-directory (expand-file-name "plain" root))
               (notmuch-directory
                (expand-file-name "notmuch" parent-directory))
               (plain-fallback
                (progn
                  (make-directory plain-directory)
                  (emacsvox-test--resource-file
                   plain-directory "button")
                  (emacsvox-test--resource-file
                   plain-directory "item")))
               (bart-fallback
                (progn
                  (emacsvox-test--resource-file
                   parent-directory "button")
                  (emacsvox-test--resource-file
                   parent-directory "item")))
               (module-default
                (emacsvox-test--resource-file
                 child-directory "notmuch-attachment"))
               (module-override
                (progn
                  (make-directory notmuch-directory)
                  (emacsvox-test--resource-file
                   notmuch-directory "notmuch-attachment"))))
          (emacsvox-aural-register-cue
           'notmuch-attachment
           :summary "A Notmuch attachment was reached"
           :fallback 'item
           :owner 'notmuch)
          (emacsvox-aural-register-resource-pack
           'plain
           :summary "Plain sounds"
           :directory plain-directory
           :default-spatialization 'neutral)
          (emacsvox-aural-register-resource-pack
           'bart
           :summary "Bart sounds"
           :directory parent-directory
           :default-spatialization 'pre-spatialized)
          (emacsvox-aural-register-resource-overlay
           'notmuch-earcons
           :summary "Notmuch-specific earcons"
           :owner 'notmuch
           :directory child-directory
           :default-spatialization 'stereo)
          (should
           (equal
            (emacsvox-aural-resolve-cue 'notmuch-attachment 'plain)
            module-default))
          (should
           (eq
            (emacsvox-aural-resource-spatialization
             module-default 'plain)
            'stereo))
          (should
           (equal
            (emacsvox-aural-resolve-cue 'notmuch-attachment 'bart)
            module-override))
          (should
           (eq
            (emacsvox-aural-resource-spatialization
             module-override 'bart)
            'pre-spatialized))
          (let ((emacsvox-aural-disabled-resource-overlays
                 '(notmuch-earcons)))
            (should
             (equal
              (emacsvox-aural-resolve-cue 'notmuch-attachment 'plain)
              plain-fallback))
            (should
             (equal
              (emacsvox-aural-resolve-cue 'notmuch-attachment 'bart)
              bart-fallback)))
          (should
           (emacsvox-aural-resource-report-valid
            (emacsvox-aural-validate-resource-pack 'bart))))))))

(ert-deftest emacsvox-aural-resources-enforce-module-overlay-ownership ()
  "A module overlay cannot supply core or another module's cue."
  (let ((emacsvox-aural-cue-registry
         (copy-hash-table emacsvox-aural-cue-registry)))
    (emacsvox-test--with-resource-directory
      (emacsvox-test--with-empty-resource-packs
        (emacsvox-test--resource-file child-directory "button")
        (should-error
         (emacsvox-aural-register-resource-overlay
          'notmuch-earcons
          :summary "Invalid Notmuch earcons"
          :owner 'notmuch
          :directory child-directory)
         :type 'emacsvox-aural-resource-error)))))

(ert-deftest emacsvox-aural-resources-report-invalid-themed-module-assets ()
  "A pack reports foreign files found below an enabled module directory."
  (let ((emacsvox-aural-cue-registry
         (copy-hash-table emacsvox-aural-cue-registry)))
    (emacsvox-test--with-resource-directory
      (emacsvox-test--with-empty-resource-packs
        (let ((notmuch-directory
               (expand-file-name "notmuch" parent-directory)))
          (make-directory notmuch-directory)
          (emacsvox-test--resource-file parent-directory "button")
          (emacsvox-test--resource-file child-directory "notmuch-attachment")
          (emacsvox-test--resource-file notmuch-directory "foreign")
          (emacsvox-aural-register-cue
           'notmuch-attachment
           :summary "A Notmuch attachment was reached"
           :fallback 'item
           :owner 'notmuch)
          (emacsvox-aural-register-resource-pack
           'bart :summary "Bart sounds" :directory parent-directory)
          (emacsvox-aural-register-resource-overlay
           'notmuch-earcons
           :summary "Notmuch-specific earcons"
           :owner 'notmuch
           :directory child-directory)
          (let ((report (emacsvox-aural-validate-resource-pack 'bart)))
            (should-not (emacsvox-aural-resource-report-valid report))
            (should
             (equal
              (emacsvox-aural-resource-report-unknown-assets report)
              '(notmuch/foreign)))))))))

(ert-deftest emacsvox-aural-resources-report-unknown-assets ()
  "Files without registered cue intent are reported."
  (emacsvox-test--with-resource-directory
    (emacsvox-test--with-empty-resource-packs
      (emacsvox-test--resource-file parent-directory "button")
      (emacsvox-test--resource-file parent-directory "mystery")
      (emacsvox-aural-register-resource-pack
       'unknown :summary "Unknown" :directory parent-directory)
      (let ((report (emacsvox-aural-validate-resource-pack 'unknown)))
        (should-not (emacsvox-aural-resource-report-valid report))
        (should
         (equal
          (emacsvox-aural-resource-report-unknown-assets report)
          '(mystery)))))))

(ert-deftest emacsvox-aural-resources-derive-requirements-from-scheme ()
  "Scheme cue actions become resource requirements."
  (emacsvox-test--with-resource-directory
    (emacsvox-test--with-empty-resource-packs
      (emacsvox-test--resource-file parent-directory "button")
      (emacsvox-test--resource-file parent-directory "item")
      (emacsvox-aural-register-resource-pack
       'focused :summary "Focused" :directory parent-directory)
      (let* ((scheme
              (emacsvox-aural-compile-scheme
               '(:schema-version 1
                 :id cue-example
                 :summary "Cue example"
                 :rules
                 ((:id before
                   :match (:role heading)
                   :render
                   (:before
                    ((:id item :kind cue :cue item))
                    :after
                    ((:id done :kind cue :cue task-done))))))))
             (required (emacsvox-aural-scheme-required-cues scheme))
             (report
              (emacsvox-aural-validate-scheme-resources scheme 'focused)))
        (should (equal required '(item task-done)))
        (should-not (emacsvox-aural-resource-report-valid report))
        (should
         (equal
          (emacsvox-aural-resource-report-missing-required report)
          '(task-done)))))))

(ert-deftest emacsvox-aural-resources-detect-pack-inheritance-cycle ()
  "Resource-pack inheritance cannot recurse through a cycle."
  (emacsvox-test--with-resource-directory
    (emacsvox-test--with-empty-resource-packs
      (emacsvox-aural-register-resource-pack
       'first
       :summary "First"
       :directory parent-directory
       :parent 'second)
      (emacsvox-aural-register-resource-pack
       'second
       :summary "Second"
       :directory child-directory
       :parent 'first)
      (should-error
       (emacsvox-aural-effective-assets 'first)
       :type 'emacsvox-aural-resource-error))))

(ert-deftest emacsvox-aural-resources-validate-cue-fallback-references ()
  "Resource registry validation rejects unknown and cyclic cue fallbacks."
  (let ((emacsvox-aural-cue-registry (make-hash-table :test #'eq))
        (emacsvox-aural-requirement-profile-registry
         (make-hash-table :test #'eq))
        (emacsvox-aural-resource-pack-registry
         (make-hash-table :test #'eq))
        (emacsvox-aural-voice-palette-registry
         (make-hash-table :test #'eq)))
    (emacsvox-aural-register-cue
     'first :summary "First" :fallback 'missing)
    (should-error
     (emacsvox-aural-validate-resource-registry)
     :type 'emacsvox-aural-resource-error)
    (clrhash emacsvox-aural-cue-registry)
    (emacsvox-aural-register-cue
     'first :summary "First" :fallback 'second)
    (emacsvox-aural-register-cue
     'second :summary "Second" :fallback 'first)
    (should-error
     (emacsvox-aural-validate-resource-registry)
     :type 'emacsvox-aural-resource-error)))

(ert-deftest emacsvox-aural-resources-expose-existing-acss-palette ()
  "The default palette names all 25 existing ACSS personalities."
  (let ((entries
         (emacsvox-aural-effective-voice-entries 'acss-default)))
    (should (= (length entries) 25))
    (should (eq (alist-get 'bolden entries) 'voice-bolden))
    (should (eq (emacsvox-aural-voice 'smoothen) 'voice-smoothen))))

(ert-deftest emacsvox-aural-resources-compile-safe-personal-voice-palette ()
  "Personal palette data supports inherited personalities and complete styles."
  (let ((emacsvox-aural-voice-palette-registry
         (copy-hash-table emacsvox-aural-voice-palette-registry))
        (style
         '(:family paul :average-pitch 6 :pitch-range 4
           :stress nil :richness 7)))
    (emacsvox-aural-register-voice-palette-data
     `(:schema-version 1
       :id personal
       :summary "Personal voices"
       :parent acss-default
       :entries
       ((strong :personality voice-bolden)
        (clear :style ,style)))
     nil
     'personal-data)
    (should (eq (emacsvox-aural-voice 'strong 'personal) 'voice-bolden))
    (should (equal (emacsvox-aural-voice 'clear 'personal) style))
    (should
     (equal
      (emacsvox-aural-voice-palette-data
       (emacsvox-aural-voice-palette 'personal))
      `(:schema-version 1
        :id personal
        :summary "Personal voices"
        :parent acss-default
        :entries
        ((strong :personality voice-bolden)
         (clear :style ,style)))))))

(ert-deftest emacsvox-aural-resources-require-complete-personal-style ()
  "A named custom preset must state all five ACSS dimensions."
  (should-error
   (emacsvox-aural-compile-voice-palette-data
    '(:schema-version 1
      :id incomplete
      :summary "Incomplete"
      :entries
      ((partial :style (:average-pitch 5)))))
   :type 'emacsvox-aural-resource-error))

(provide 'emacsvox-aural-resources-tests)
;;; emacsvox-aural-resources-tests.el ends here
