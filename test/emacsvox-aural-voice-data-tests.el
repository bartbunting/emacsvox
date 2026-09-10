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
    (puthash 'acss-default (emacsvox-aural-voice-palette 'acss-default) registry)
    (dolist (data palettes)
      (puthash (plist-get data :id)
               (emacsvox-aural-compile-voice-palette-data data (eq (plist-get data :id) 'acss-default)) registry))
    registry))

(defun emacsvox-test--voice-data-conversion ()
  "Return the first independently specified conversion."
  (copy-tree (car (plist-get emacsvox-test--voice-data-fixture :conversions))))

(defun emacsvox-test--voice-resolution-inputs ()
  "Return independent palette, local choice and workstation inputs."
  (let* ((fixture (copy-tree emacsvox-test--voice-data-fixture))
         (conversions (plist-get fixture :conversions)))
    (list :registry
          (emacsvox-test--voice-data-registry
           (append (plist-get fixture :source-palettes)
                   (mapcar (lambda (entry) (plist-get entry :expected-palette)) conversions)))
          :sets (apply #'append (mapcar (lambda (entry) (plist-get entry :expected-local-choice-sets)) conversions))
          :routing (cadr (plist-get fixture :source-routing-profiles))
          :policy '(:engine-order ("espeak" "dectalk") :disabled-engines ("dectalk")
                    :fallback (:allow-same-language t :global-default nil :engines ("eloquence"))))))

(defun emacsvox-test--resolve-owned (inputs voice palette)
  "Resolve VOICE in PALETTE from INPUTS and workstation policy."
  (emacsvox-aural-voice-data--resolve
   voice palette (plist-get inputs :registry) (plist-get inputs :sets)
     (plist-get inputs :policy)))

(ert-deftest emacsvox-aural-voice-data-resolve-switches-owned-chains ()
  "Palette A-B-A keeps ordered unavailable choices and shared stored values."
  (let* ((inputs (emacsvox-test--voice-resolution-inputs))
         (first (emacsvox-test--resolve-owned inputs 'voice-bolden 'reading-owned))
         (other (emacsvox-test--resolve-owned inputs "bolden" 'alternative-owned)))
    (should (eq (plist-get first :mode) 'owned))
    (should (eq (plist-get first :name) 'bolden))
    (should (eq (plist-get first :palette) 'reading-owned))
    (should (equal (plist-get first :names) '(bolden voice-bolden)))
    (should (equal (plist-get first :selectors) (emacsvox-aural-voice-data--selectors (plist-get (car (plist-get inputs :sets)) :choices))))
    (should (equal (plist-get other :selectors) (emacsvox-aural-voice-data--selectors (plist-get (cadr (plist-get inputs :sets)) :choices))))
    (should (equal (plist-get first :definition) (plist-get other :definition)))
    (should (= (plist-get (plist-get first :definition) :low-pass) 7))
    (should (equal (plist-get first :policy) (plist-get inputs :policy)))
    (should (equal first (emacsvox-test--resolve-owned inputs 'voice-bolden 'reading-owned)))))

(ert-deftest emacsvox-aural-voice-data-resolve-automatic-and-missing-differ ()
  "An automatic chain and a missing local snapshot have distinct diagnostics."
  (let* ((inputs (emacsvox-test--voice-resolution-inputs))
         (auto (emacsvox-test--resolve-owned inputs 'voice-annotate 'reading-owned)))
    (should (plist-get auto :automatic))
    (should (eq (plist-get auto :mode) 'owned))
    (should (eq (plist-get auto :definition) 'voice-annotate))
    (should-not (plist-get auto :selectors))
    (setf (plist-get inputs :sets) nil)
    (let ((missing (emacsvox-test--resolve-owned inputs 'bolden 'alternative-owned)))
      (should-not (plist-get missing :selectors))
      (should-not (plist-get missing :automatic))
      (should (equal (plist-get missing :diagnostics) '(missing-local-choices))))
    (let ((portable (emacsvox-test--resolve-owned inputs 'bolden 'reading-owned)))
      (should (eq (plist-get portable :choice-source) 'portable))
      (should (eq (plist-get (car (plist-get portable :selectors)) :kind) 'properties)))))

(ert-deftest emacsvox-aural-voice-data-resolve-isolates-results ()
  "Resolved styles, choices, policy and raw entries are fresh mutable copies."
  (let* ((inputs (emacsvox-test--voice-resolution-inputs))
         (expected (emacsvox-test--resolve-owned inputs 'bolden 'reading-owned))
         (result (emacsvox-test--resolve-owned inputs 'bolden 'reading-owned)))
    (setf (plist-get (plist-get result :definition) :average-pitch) 9
          (plist-get (car (plist-get result :selectors)) :voice-id) "changed"
          (plist-get (plist-get result :policy) :disabled-engines) nil
          (plist-get (cdr (plist-get result :entry)) :choices) nil)
    (should (equal expected (emacsvox-test--resolve-owned inputs 'bolden 'reading-owned)))))

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

(ert-deftest emacsvox-aural-voice-data-inheritance-owner-and-missing-local ()
  "Whole entries retain their defining owner; missing references use portable data."
  (let* ((conversion (emacsvox-test--voice-data-conversion))
         (parent (plist-get conversion :expected-palette))
         (sets (plist-get conversion :expected-local-choice-sets))
         (child '(:schema-version 3 :id child :summary "Child" :parent reading-owned :routing owned :entries nil))
         (registry (emacsvox-test--voice-data-registry (list parent child)))
         (item (cl-find 'bolden (emacsvox-aural-voice-data--entries 'child registry)
                        :key (lambda (entry) (car (plist-get entry :entry)))))
         (properties (cdr (plist-get item :entry))))
    (should (eq (plist-get item :palette) 'reading-owned))
    (should (equal (plist-get (emacsvox-aural-voice-data--choices
                              'reading-owned 'bolden properties sets) :selectors)
                   (emacsvox-aural-voice-data--selectors (plist-get (car sets) :choices))))
    (let ((missing (emacsvox-aural-voice-data--choices
                    'reading-owned 'bolden properties nil)))
      (should (equal (plist-get missing :diagnostics) '(missing-local-choices)))
      (should (equal (plist-get missing :choices) (plist-get properties :choices))))
    (should-error (emacsvox-aural-voice-data--choices 'child 'bolden properties sets))
    (setf (plist-get (car sets) :choices) nil)
    (should-error (emacsvox-aural-voice-data--choices 'reading-owned 'bolden properties sets))))

(ert-deftest emacsvox-aural-voice-data-shares-whole-entry-inheritance ()
  "Public definitions and owned resolution agree through four palette levels."
  (let* ((palettes
          '((:schema-version 3 :id acss-default :summary "Standard" :parent nil
             :routing owned
             :entries ((bolden :personality voice-bolden :choices nil)
                       (annotate :personality voice-annotate :choices nil)))
            (:schema-version 3 :id c :summary "C" :parent acss-default
             :routing owned
             :entries ((bolden :personality voice-monotone :choices nil
                        :language "en" :local-choices "parent-only")))
            (:schema-version 3 :id b :summary "B" :parent c :routing owned
             :entries ((bolden :style (:family nil :average-pitch 0
                                      :pitch-range nil :stress 4 :richness nil
                                      :rate-offset -2 :low-pass 0)
                        :choices nil)))
            (:schema-version 3 :id a :summary "A" :parent b :routing owned
             :entries nil)))
         (before (copy-tree palettes))
         (registry (emacsvox-test--voice-data-registry palettes))
         (emacsvox-aural-voice-palette-registry registry)
         (metadata (emacsvox-aural-voice-data--entries 'a registry))
         (resolved (emacsvox-aural-voice-data--resolve
                    'voice-bolden 'a registry nil   nil)))
    (should (equal (mapcar (lambda (item) (plist-get item :palette)) metadata)
                   '(b acss-default)))
    (should (equal (emacsvox-aural-voice 'bolden 'a)
                   (plist-get resolved :definition)))
    (should (eq (plist-get resolved :palette) 'b))
    (should (plist-get resolved :automatic))
    ;; A replacement inherits no fields, even from a parent with missing locals.
    (should-not (plist-get resolved :language))
    (should-not (plist-get resolved :diagnostics))
    (should (eq (emacsvox-aural-voice 'annotate 'a) 'voice-annotate))
    (setf (plist-get (cdr (plist-get (car metadata) :entry)) :style) nil)
    (setf (plist-get (emacsvox-aural-voice 'bolden 'a) :average-pitch) 9)
    (should (equal (emacsvox-aural-voice 'bolden 'a)
                   (plist-get resolved :definition)))
    (should (equal palettes before))))

(ert-deftest emacsvox-aural-voice-data-shares-inheritance-errors ()
  "Both readers reject missing parents and cycles without modifying records."
  (dolist (parent '(absent child))
    (let* ((data (list :schema-version 3 :id 'child :summary "Child"
                       :parent parent :routing 'owned :entries nil))
           (registry (emacsvox-test--voice-data-registry (list data)))
           (emacsvox-aural-voice-palette-registry registry))
      (should-error (emacsvox-aural-voice-data--entries 'child registry)
                    :type 'emacsvox-aural-resource-error)
      (should-error (emacsvox-aural-effective-voice-entries 'child)
                    :type 'emacsvox-aural-resource-error)
      (should (equal data (emacsvox-aural-voice-palette-data-form
                           (gethash 'child registry)))))))

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
    (should (equal (emacsvox-aural-voice-data--selectors (plist-get (cdr (car (plist-get export :entries))) :choices))
                   '((:kind properties :scope portable :engine-id "eloquence" :gender male))))
    (should (equal data before))))

(ert-deftest emacsvox-aural-voice-data-immutable-local-records ()
  "Retries preserve IDs; changed payloads, duplicates and session selectors fail."
  (let* ((sets (plist-get (emacsvox-test--voice-data-conversion)
                         :expected-local-choice-sets))
         (changed (copy-tree sets)))
    (should (equal sets (emacsvox-aural-routing--merge-choice-sets sets sets)))
    (should (equal sets (emacsvox-aural-routing--merge-choice-sets sets nil)))
    (setf (plist-get (car changed) :choices) nil)
    (should-error (emacsvox-aural-routing--merge-choice-sets sets changed))
    (should-error (emacsvox-aural-routing--validate-choice-sets (append sets sets)))
    (setf (plist-get (car changed) :selectors)
          '((:kind engine-default :scope session :engine-id "dectalk")))
    (should-error (emacsvox-aural-routing--validate-choice-sets changed))))

(ert-deftest emacsvox-aural-voice-data-old-envelopes-read-without-writing ()
  "Envelope upgrades are read-only and retain complete palette records."
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
              (should (= (plist-get read :schema-version) (if routing 3 9)))
              (unless routing
                (should (= (plist-get (car (plist-get read :voice-palettes))
                                      :schema-version) 3))))
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
         (aural (list :schema-version 9 :voice-palettes
                      (list (plist-get conversion :expected-palette))))
         (routing (list :schema-version 3 :active-profile nil :profiles nil
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
                             '(:schema-version 9 :voice-palettes nil) aural-file))
              (should-error (emacsvox-aural-routing--write-user-data routing routing-file)))
            (should (equal old-aural (emacsvox-aural-read-user-data aural-file)))
            (should (equal old-routing (emacsvox-aural-read-routing-profiles routing-file))))
          (should-not emacsvox-aural-routing--choice-sets)
          (should (= (hash-table-count emacsvox-aural-routing-profile-registry) 0))
          (should-not (directory-files directory nil "^\\.aural-")))
      (delete-directory directory t))))

(ert-deftest emacsvox-aural-voice-data-rejects-retired-palettes-and-alias-entries ()
  "Old palette formats and alias shadowing fail without registry mutation."
  (let* ((inputs (emacsvox-test--voice-resolution-inputs))
         (registry (plist-get inputs :registry))
         (before (hash-table-count registry)))
    (dolist (version '(1 2))
      (should-error (emacsvox-aural-compile-voice-palette-data
                     (list :schema-version version :id 'old :summary "Old"
                           :parent 'acss-default :routing 'owned :entries nil))))
    (should-error (emacsvox-aural-compile-voice-palette-data
                   '(:schema-version 3 :id shadow :summary "Shadow" :parent acss-default
                     :routing owned :entries ((voice-bolden :personality voice-smoothen :choices nil)))))
    (should (= before (hash-table-count registry)))
    (let ((canonical (emacsvox-test--resolve-owned inputs 'bolden 'reading-owned))
          (alias (emacsvox-test--resolve-owned inputs 'voice-bolden 'reading-owned)))
      (should (eq (plist-get alias :name) 'bolden))
      (should (equal (plist-get canonical :choices) (plist-get alias :choices))))
    (should-not (plist-get (emacsvox-test--resolve-owned inputs 'voice-custom 'reading-owned) :name))))

(ert-deftest emacsvox-aural-voice-data-rejects-retired-referenced-snapshot ()
  "Historical local records remain readable but cannot supply current choices."
  (let* ((old '(:id "historical" :palette reading-owned :voice bolden
                :selectors ((:kind exact :scope local :engine-id "dectalk" :voice-id "Paul"))))
         (sets (emacsvox-aural-routing--validate-choice-sets (list old)))
         (before (copy-tree sets)))
    (should (equal sets (list old)))
    (should-error (emacsvox-aural-voice-data--choices
                   'reading-owned 'bolden '(:choices nil :local-choices "historical") sets))
    (should (equal sets before))))

(ert-deftest emacsvox-aural-voice-data-has-no-shared-named-routing-api ()
  "Named choices are owned by palettes; workstation policy has no bindings."
  (dolist (function '(emacsvox-aural-set-session-routing-binding
                      emacsvox-aural-voice-data--convert emacsvox-aural-voice-data--promote
                      emacsvox-aural-routing-apply-preset-to-data))
    (should-not (fboundp function)))
  (should-error (emacsvox-aural-validate-routing-profile-data
                 '(:schema-version 2 :id old :summary "Old" :engine-order nil
                   :disabled-engines nil :fallback nil :bindings nil))))

(provide 'emacsvox-aural-voice-data-tests)
;;; emacsvox-aural-voice-data-tests.el ends here
