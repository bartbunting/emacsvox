;;; emacsvox-aural-voice-data-tests.el --- Owned voice storage tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Independently specified migration fixtures and persistence failure contracts.

;;; Code:

(require 'ert)
(require 'emacsvox-aural-voice-data)
(require 'emacsvox-aural-schemes)

(defconst emacsvox-test--voice-data-fixture
  (let ((file (expand-file-name
               "fixtures/voice-editor/conversion.el"
               (file-name-directory (or load-file-name buffer-file-name)))))
    (emacsvox-aural-routing--read-one-form file "voice fixture")))

(defun emacsvox-test--voice-data-registry (palettes)
  "Compile PALETTES into an isolated registry."
  (let ((registry (make-hash-table :test #'eq)))
    (dolist (data palettes)
      (puthash (plist-get data :id)
               (emacsvox-aural-compile-voice-palette-data data) registry))
    registry))

(defun emacsvox-test--voice-data-conversion ()
  "Return the first independently specified conversion."
  (copy-tree (car (plist-get emacsvox-test--voice-data-fixture :conversions))))

(ert-deftest emacsvox-aural-voice-data-conversion-fixtures ()
  "Two routing sources produce independent copies without touching inputs."
  (let* ((fixture (copy-tree emacsvox-test--voice-data-fixture))
         (before (copy-tree fixture))
         (registry (emacsvox-test--voice-data-registry
                    (plist-get fixture :source-palettes)))
         (live-registry emacsvox-aural-voice-palette-registry)
         (live-routing emacsvox-aural-routing-profile-registry)
         (live-active emacsvox-aural-active-routing-profile))
    (dolist (conversion (plist-get fixture :conversions))
      (let* ((expected (plist-get conversion :expected-palette))
             (sets (plist-get conversion :expected-local-choice-sets))
             (profile (cl-find (plist-get conversion :source-routing-profile)
                               (plist-get fixture :source-routing-profiles)
                               :key (lambda (data) (plist-get data :id))))
             (args (list registry (plist-get conversion :source-palette)
                         (plist-get expected :id) (plist-get expected :summary)
                         profile (mapcar (lambda (record)
                                           (cons (plist-get record :voice)
                                                 (plist-get record :id))) sets)))
             (result (apply #'emacsvox-aural-voice-data--convert args)))
        (should (equal (plist-get result :palette) expected))
        (should (equal (plist-get result :choice-sets) sets))
        (should (equal result (apply #'emacsvox-aural-voice-data--convert args)))
        (let ((emacsvox-aural-voice-palette-registry
               (emacsvox-test--voice-data-registry (list expected))))
          (should (equal (emacsvox-aural-voice 'bolden (plist-get expected :id))
                         (plist-get (cdr (car (plist-get expected :entries))) :style))))))
    (should (equal fixture before))
    (should (eq live-registry emacsvox-aural-voice-palette-registry))
    (should (eq live-routing emacsvox-aural-routing-profile-registry))
    (should (eq live-active emacsvox-aural-active-routing-profile))))

(ert-deftest emacsvox-aural-voice-data-validates-owned-metadata ()
  "Reject malformed, nonportable, ambiguous and unknown owned data."
  (let ((base (plist-get (emacsvox-test--voice-data-conversion) :expected-palette)))
    (dolist (edit (list (lambda (data) (plist-put data :schema-version 99))
                       (lambda (data) (plist-put data :routing 'legacy))
                       (lambda (data) (append data '(:id duplicate)))
                       (lambda (data) (plist-put data :entries '(bad . tail)))
                       (lambda (data) (plist-put data :entries
                                                '((bolden :personality voice-bolden))))
                       (lambda (data) (plist-put data :entries
                                                '((bolden :personality voice-bolden
                                                   :choices nil :choices nil))))
                       (lambda (data) (plist-put data :entries
                                                '((bolden :personality voice-bolden
                                                   :choices ((:kind exact :scope local
                                                              :engine-id "dtk" :voice-id "Paul"))))))
                       (lambda (data) (plist-put data :entries
                                                '((bolden :personality voice-bolden
                                                   :choices nil :local-choices ""))))))
      (should-error (emacsvox-aural-compile-voice-palette-data
                     (funcall edit (copy-tree base)))))))

(ert-deftest emacsvox-aural-voice-data-alias-conflict-and-direct-identity ()
  "Alias disagreements block migration; actual direct entries remain distinct."
  (let* ((fixture (copy-tree emacsvox-test--voice-data-fixture))
         (palettes (plist-get fixture :source-palettes))
         (profile (car (plist-get fixture :source-routing-profiles)))
         (registry (emacsvox-test--voice-data-registry palettes)))
    (setq profile (plist-put profile :bindings
                             (append (plist-get profile :bindings)
                                     '((:logical-voice bolden :selectors nil)))))
    (should-error (emacsvox-aural-voice-data--convert
                   registry 'source-child 'new "New" profile '((bolden . "one")))
                  :type 'emacsvox-aural-voice-data-conflict)
    (setf (plist-get (car palettes) :entries)
          (append (plist-get (car palettes) :entries)
                  '((voice-bolden :personality voice-bolden))))
    (let* ((result (emacsvox-aural-voice-data--convert
                    (emacsvox-test--voice-data-registry palettes)
                    'source-child 'new "New" profile '((voice-bolden . "two"))))
           (entries (plist-get (plist-get result :palette) :entries)))
      (should-not (plist-get (cdr (assq 'bolden entries)) :local-choices))
      (should (equal (plist-get (cdr (assq 'voice-bolden entries)) :local-choices)
                     "two")))))

(ert-deftest emacsvox-aural-voice-data-automatic-does-not-capture-session ()
  "An explicit Automatic conversion is independent of live session routing."
  (let* ((registry (emacsvox-test--voice-data-registry
                    (plist-get emacsvox-test--voice-data-fixture :source-palettes)))
         (emacsvox-aural-session-routing-bindings
          '((:logical-voice bolden :selectors
             ((:kind exact :scope session :engine-id "dectalk" :voice-id "Paul")))))
         (result (emacsvox-aural-voice-data--convert
                  registry 'source-child 'new "New" nil nil)))
    (should-not (plist-get result :choice-sets))
    (dolist (entry (plist-get (plist-get result :palette) :entries))
      (should (plist-member (cdr entry) :choices))
      (should-not (plist-get (cdr entry) :choices)))))

(ert-deftest emacsvox-aural-voice-data-inheritance-owner-and-missing-local ()
  "Whole entries retain their defining owner; missing references use portable data."
  (let* ((conversion (emacsvox-test--voice-data-conversion))
         (parent (plist-get conversion :expected-palette))
         (sets (plist-get conversion :expected-local-choice-sets))
         (child '(:schema-version 2 :id child :summary "Child" :parent reading-owned
                  :routing owned :entries nil))
         (registry (emacsvox-test--voice-data-registry (list parent child)))
         (item (car (emacsvox-aural-voice-data--entries 'child registry)))
         (properties (cdr (plist-get item :entry))))
    (should (eq (plist-get item :palette) 'reading-owned))
    (should (equal (plist-get (emacsvox-aural-voice-data--choices
                              'reading-owned 'bolden properties sets) :selectors)
                   (plist-get (car sets) :selectors)))
    (let ((missing (emacsvox-aural-voice-data--choices
                    'reading-owned 'bolden properties nil)))
      (should (equal (plist-get missing :diagnostics) '(missing-local-choices)))
      (should (equal (plist-get missing :selectors) (plist-get properties :choices))))
    (should-error (emacsvox-aural-voice-data--choices 'child 'bolden properties sets))
    (setf (plist-get (car sets) :selectors) nil)
    (should-not (plist-get (emacsvox-aural-voice-data--choices
                            'reading-owned 'bolden properties sets) :selectors))
    (puthash 'legacy (emacsvox-aural-compile-voice-palette-data
                      '(:schema-version 1 :id legacy :summary "Legacy" :parent child
                        :entries nil)) registry)
    (should-error (emacsvox-aural-voice-data--entries 'legacy registry))
    (let ((emacsvox-aural-voice-palette-registry registry))
      (should-error (emacsvox-aural-effective-voice-entries 'legacy)))))

(ert-deftest emacsvox-aural-voice-data-owned-copy-has-new-owner ()
  "Local copies preserve complete chains with new ownership and immutable IDs."
  (let* ((conversion (emacsvox-test--voice-data-conversion))
         (source (plist-get conversion :expected-palette))
         (sets (plist-get conversion :expected-local-choice-sets))
         (registry (emacsvox-test--voice-data-registry (list source)))
         (result (emacsvox-aural-voice-data--copy-owned
                  registry 'reading-owned 'new "New" sets '((bolden . "new-id")))))
    (should (equal (plist-get (car (plist-get result :choice-sets)) :selectors)
                   (plist-get (car sets) :selectors)))
    (should (eq (plist-get (car (plist-get result :choice-sets)) :palette) 'new))
    (should-error (emacsvox-aural-voice-data--copy-owned
                   registry 'reading-owned 'new "New" sets
                   '((bolden . "fixture-reading-bolden-1"))))
    (should-error (emacsvox-aural-voice-data--copy-owned
                   registry 'reading-owned 'new "New" nil '((bolden . "new-id"))))
    (should-error (emacsvox-aural-voice-data--copy-owned
                   registry 'reading-owned 'reading-owned "New" sets nil))))

(ert-deftest emacsvox-aural-voice-data-portable-export ()
  "Export strips local references without inventing portable selector matches."
  (let* ((data (plist-get (emacsvox-test--voice-data-conversion) :expected-palette))
         (before (copy-tree data))
         (result (emacsvox-aural-voice-data--portable-export data))
         (export (plist-get result :palette)))
    (should (equal (plist-get result :omitted-local-choices) '(bolden)))
    (should (eq (plist-get export :routing) 'owned))
    (should-not (plist-member (cdr (car (plist-get export :entries))) :local-choices))
    (should (equal (plist-get (cdr (car (plist-get export :entries))) :choices)
                   '((:kind properties :scope portable :engine-id "eloquence" :gender male))))
    (should (equal data before))))

(ert-deftest emacsvox-aural-voice-data-immutable-local-records ()
  "Retries preserve IDs; changed payloads, duplicates and session selectors fail."
  (let* ((sets (plist-get (emacsvox-test--voice-data-conversion)
                         :expected-local-choice-sets))
         (changed (copy-tree sets)))
    (should (equal sets (emacsvox-aural-routing--merge-choice-sets sets sets)))
    (should (equal sets (emacsvox-aural-routing--merge-choice-sets sets nil)))
    (setf (plist-get (car changed) :selectors) nil)
    (should-error (emacsvox-aural-routing--merge-choice-sets sets changed))
    (should-error (emacsvox-aural-routing--validate-choice-sets (append sets sets)))
    (setf (plist-get (car changed) :selectors)
          '((:kind engine-default :scope session :engine-id "dectalk")))
    (should-error (emacsvox-aural-routing--validate-choice-sets changed))))

(ert-deftest emacsvox-aural-voice-data-old-files-read-without-writing ()
  "Both envelope migrations are read-only and leave legacy palettes at version 1."
  (let ((directory (make-temp-file "voice-old-data-" t)))
    (unwind-protect
        (dolist (routing '(nil t))
          (let* ((file (expand-file-name (if routing "routing.el" "aural.el") directory))
                 (data (if routing '(:schema-version 1 :active-profile nil :profiles nil)
                         (list :schema-version 7 :voice-palettes
                               (copy-tree (plist-get emacsvox-test--voice-data-fixture
                                                     :source-palettes)))))
                 (text (prin1-to-string data)))
            (with-temp-file file (insert text))
            (let ((read (if routing (emacsvox-aural-read-routing-profiles file)
                          (emacsvox-aural-read-user-data file))))
              (should (= (plist-get read :schema-version) (if routing 2 8)))
              (unless routing
                (should (= (plist-get (car (plist-get read :voice-palettes))
                                      :schema-version) 1))))
            (should (equal text (with-temp-buffer
                                  (insert-file-contents file) (buffer-string))))
            (should-not (file-exists-p (concat file "~")))))
      (delete-directory directory t))))

(ert-deftest emacsvox-aural-voice-data-writers-retain-snapshots-and-survive-failure ()
  "Nonactivating writes round-trip, preserve snapshots and survive failed rename."
  (let* ((directory (make-temp-file "voice-data-write-" t))
         (aural-file (expand-file-name "aural.el" directory))
         (routing-file (expand-file-name "routing.el" directory))
         (conversion (emacsvox-test--voice-data-conversion))
         (sets (plist-get conversion :expected-local-choice-sets))
         (aural (list :schema-version 8 :voice-palettes
                      (list (plist-get conversion :expected-palette))))
         (routing (list :schema-version 2 :active-profile nil :profiles nil
                        :choice-sets sets))
         (emacsvox-aural-routing--choice-sets nil)
         (emacsvox-aural-routing-profile-registry (make-hash-table :test #'eq))
         (emacsvox-aural-active-routing-profile nil)
         (emacsvox-aural-routing-profile-changed-hook
          (list (lambda () (ert-fail "Writer invoked live hook")))))
    (unwind-protect
        (progn
          (emacsvox-aural-routing--write-user-data routing routing-file)
          (emacsvox-aural--write-user-data aural aural-file)
          (should (equal (emacsvox-aural-read-user-data aural-file) aural))
          (should (equal (emacsvox-aural-read-routing-profiles routing-file) routing))
          ;; An independent profile client has not loaded the new snapshots.
          (emacsvox-aural-save-routing-profiles routing-file)
          (should (equal (plist-get (emacsvox-aural-read-routing-profiles routing-file)
                                    :choice-sets) sets))
          (let ((old-aural (emacsvox-aural-read-user-data aural-file))
                (old-routing (emacsvox-aural-read-routing-profiles routing-file)))
            (cl-letf (((symbol-function 'rename-file)
                       (lambda (&rest _) (error "Injected rename failure"))))
              (should-error (emacsvox-aural--write-user-data
                             '(:schema-version 8 :voice-palettes nil) aural-file))
              (should-error (emacsvox-aural-routing--write-user-data routing routing-file)))
            (should (equal old-aural (emacsvox-aural-read-user-data aural-file)))
            (should (equal old-routing (emacsvox-aural-read-routing-profiles routing-file))))
          (should-not emacsvox-aural-routing--choice-sets)
          (should (= (hash-table-count emacsvox-aural-routing-profile-registry) 0))
          (should-not (directory-files directory nil "^\\.aural-")))
      (delete-directory directory t))))

(provide 'emacsvox-aural-voice-data-tests)
;;; emacsvox-aural-voice-data-tests.el ends here
