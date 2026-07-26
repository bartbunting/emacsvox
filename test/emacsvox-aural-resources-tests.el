;;; emacsvox-aural-resources-tests.el --- Aural resource tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Test cue intent, requirement profiles, sound-pack inheritance and fallback,
;; scheme-derived requirements, and existing ACSS voice-palette exposure.

;;; Code:

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
          (make-hash-table :test #'eq)))
     ,@body))

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

(ert-deftest emacsvox-aural-resources-discover-manifested-partial-pack ()
  "A data manifest can define inheritance and spatialization for a partial pack."
  (let* ((root (make-temp-file "emacsvox-pack-manifest-" t))
         (chimes (expand-file-name "chimes" root))
         (partial (expand-file-name "personal-overlay" root))
         (emacsvox-aural-resource-pack-registry
          (make-hash-table :test #'eq)))
    (unwind-protect
        (progn
          (make-directory chimes)
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
      "/chimes/shutdown.ogg"
      (emacsvox-aural-resolve-cue 'shutdown 'chimes t)))
    (should
     (string-suffix-p
      "/3d/close-object.ogg"
      (emacsvox-aural-resolve-cue 'shutdown '3d t)))
    (should
     (string-suffix-p
      "/prompts/startup.ogg"
      (emacsvox-aural-resolve-cue 'emacsvox '3d t)))
    (should
     (string-suffix-p
      "/3d/repeat-end.ogg"
      (emacsvox-aural-resolve-cue 'repeat-stop '3d t)))
    (should
     (string-suffix-p
      "/3d/deselect-object.ogg"
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

(provide 'emacsvox-aural-resources-tests)
;;; emacsvox-aural-resources-tests.el ends here
