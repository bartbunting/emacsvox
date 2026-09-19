;;; emacsvox-aural-voice-choice-tests.el --- Individual choice storage -*- lexical-binding: t; -*-

;;; Commentary:
;; Independent format examples and real persistence/recovery boundaries.
;;; Code:

(require 'ert)
(require 'emacsvox-aural-voice-data-tests)
(require 'emacsvox-aural-voice-drafts-tests)
(require 'emacsvox-aural-voice-editing)

(defconst emacsvox-test--voice-choice-fixture
  (emacsvox-aural-routing--read-one-form
   (expand-file-name "fixtures/voice-editor/fallback-tuning-storage.el"
                     (file-name-directory (or load-file-name buffer-file-name)))
   "individual voice fixture"))

(defun emacsvox-test--choice-fixture (key)
  "Return independent fixture data under KEY."
  (copy-tree (plist-get emacsvox-test--voice-choice-fixture key)))

(defun emacsvox-test--tuned-choices ()
  "Return the independent complete tuned chain."
  (plist-get (cadr (plist-get (emacsvox-test--choice-fixture :expected-routing) :choice-sets)) :choices))

(defmacro emacsvox-test--with-tuned-storage (&rest body)
  "Run BODY with the independent tuned palette and local records."
  (declare (indent 0) (debug t))
  `(let ((emacsvox-aural-voice-palette-registry
          (emacsvox-test--voice-data-registry
           (list (emacsvox-test--choice-fixture :unchanged-parent)
                 (emacsvox-test--choice-fixture :expected-palette))))
         (emacsvox-aural-routing--choice-sets
          (plist-get (emacsvox-test--choice-fixture :expected-routing) :choice-sets)))
     ,@body))

(ert-deftest emacsvox-aural-voice-choice-save-matches-independent-fixture ()
  "Saving changed choices preserves unrelated entries and immutable local data."
  (let* ((source (emacsvox-test--choice-fixture :source-palette))
         (before (copy-tree source))
         (rows (emacsvox-test--tuned-choices))
         (proposal (emacsvox-aural-voice-data--put-choices
                    source 'bolden rows "reading-bolden-after"
                    ))
         (routing (emacsvox-aural-validate-routing-user-data
                   (emacsvox-test--choice-fixture :source-routing))))
    (should (equal (plist-get proposal :palette) (emacsvox-test--choice-fixture :expected-palette)))
    (setq routing (plist-put routing :choice-sets
                             (emacsvox-aural-routing--merge-choice-sets
                              (plist-get routing :choice-sets) (plist-get proposal :choice-sets))))
    (should (equal routing (emacsvox-test--choice-fixture :expected-routing)))
    (should (equal source before))
    (should (equal rows (emacsvox-test--tuned-choices)))
    (should (equal proposal (emacsvox-aural-voice-data--put-choices
                             source 'bolden rows "reading-bolden-after"
                             )))))

(ert-deftest emacsvox-aural-voice-choice-rejects-malformed-patches-and-records ()
  "Choice patches have strict presence and range semantics without legacy spillover."
  (dolist (patch '((:richness 10) (:rate-offset -21) (:richness 0.5)
                   (:rate-offset 1.0) (:richness t) (:richness "3")
                   (:richness 1 :richness 2) (:richness) (:richness 1 . tail)
                   (:family nil) (:preset bolden) (:rate 3) (:volume 4)))
    (should-error (emacsvox-aural-routing--validate-choice-adjustments patch)))
  (dolist (patch '(nil (:richness nil) (:richness 0) (:rate-offset 0 :low-pass nil)))
    (should (equal patch (emacsvox-aural-routing--validate-choice-adjustments patch))))
  (let ((row (car (emacsvox-test--tuned-choices))))
    (dolist (id (list "" "two words" "é" (make-string 129 ?a) nil 4))
      (should-error (emacsvox-aural-routing--validate-choices
                     (list (plist-put (copy-tree row) :id id)))))
    (should-error (emacsvox-aural-routing--validate-choices (list row row)))
    (should-error (emacsvox-aural-routing--validate-choices
                   (cl-loop for i below 33 collect
                            (plist-put (copy-tree row) :id (format "choice-%d" i)))))
    (should-error (emacsvox-aural-routing--validate-choices (list row) t))
    (should-error (emacsvox-aural-routing--validate-choices
                   (list (append row '(:unexpected nil))))))
  (let ((sets (plist-get (emacsvox-test--choice-fixture :expected-routing) :choice-sets)))
    (should-error (emacsvox-aural-validate-routing-user-data
                   (list :schema-version 2 :active-profile nil :profiles nil :choice-sets sets)))
    (should-error (emacsvox-aural-routing--validate-choice-sets
                   (list (append (cadr sets) '(:selectors nil)))))
    (should-error (emacsvox-aural-routing--validate-choice-sets
                   (list (plist-put (copy-tree (cadr sets)) :schema-version 5)))))
  (let ((data (emacsvox-test--choice-fixture :expected-palette)))
    (should-error (emacsvox-aural-compile-voice-palette-data (plist-put data :schema-version 2)))))

(ert-deftest emacsvox-aural-voice-choice-resolves-owned-records-and-aliases ()
  "Aliases resolve the complete owned records and return independent copies."
  (emacsvox-test--with-tuned-storage
   (let* ((rows (emacsvox-test--tuned-choices))
          (resolve (lambda (voice)
                     (emacsvox-aural-voice-data--resolve
                      voice 'reading emacsvox-aural-voice-palette-registry
                      emacsvox-aural-routing--choice-sets   nil)))
          (saved (funcall resolve 'bolden))
          (alias (funcall resolve 'voice-bolden)))
     (should (equal (plist-get saved :choices) rows))
     (should (equal (plist-get alias :choices) rows))
     (should (equal (plist-get saved :selectors) (emacsvox-aural-voice-data--selectors rows)))
     (should (equal (plist-get (funcall resolve 'bolden) :choices) rows))
     (setf (plist-get (car (plist-get saved :choices)) :adjustments) nil)
     (should (equal (plist-get (funcall resolve 'bolden) :choices) rows)))))

(ert-deftest emacsvox-aural-voice-choice-rejects-cross-store-disagreement ()
  "Wrong owners and inconsistent portable projections cannot silently load."
  (let* ((data (emacsvox-test--choice-fixture :expected-palette))
         (properties (cdr (assq 'bolden (plist-get data :entries))))
         (sets (plist-get (emacsvox-test--choice-fixture :expected-routing) :choice-sets)))
    (should-error (emacsvox-aural-voice-data--choices 'other 'bolden properties sets))
    (should (emacsvox-aural-voice-data--choices 'reading 'bolden properties sets))
    (setf (plist-get (car (plist-get properties :choices)) :adjustments) nil)
    (should-error (emacsvox-aural-voice-data--choices 'reading 'bolden properties sets)))
  (let* ((data (emacsvox-test--choice-fixture :expected-palette))
         (properties (cdr (assq 'bolden (plist-get data :entries))))
         (sets (plist-get (emacsvox-test--choice-fixture :source-routing) :choice-sets)))
    (setq properties (plist-put properties :local-choices "reading-bolden-before"))
    (should-error (emacsvox-aural-voice-data--choices 'reading 'bolden properties sets))))

(ert-deftest emacsvox-aural-voice-choice-operations-preserve-identities-and-states ()
  "Reordering and replacement preserve the selected row; inheritance is removal."
  (let* ((rows (emacsvox-test--tuned-choices))
         (before (copy-tree rows))
         (id "eloquence-male")
         (zero (emacsvox-aural-voice-data--adjust-choice rows id :pan 'set 0))
         (default (emacsvox-aural-voice-data--adjust-choice zero id :pan 'default))
         (inherit (emacsvox-aural-voice-data--adjust-choice default id :pan 'inherit))
         (reordered (emacsvox-aural-voice-data--move-choice default id 0))
         (replacement '(:kind exact :scope local :engine-id "eloquence" :voice-id "Shelley")))
    (should (eq (plist-get (plist-get (cadr zero) :adjustments) :pan) 0))
    (should (plist-member (plist-get (cadr default) :adjustments) :pan))
    (should-not (plist-get (plist-get (cadr default) :adjustments) :pan))
    (should-not (plist-member (plist-get (cadr inherit) :adjustments) :pan))
    (should (equal (car reordered) (cadr default)))
    (let ((keep (emacsvox-aural-voice-data--replace-choice rows id replacement 'keep))
          (reset (emacsvox-aural-voice-data--replace-choice rows id replacement 'reset)))
      (should (equal (plist-get (cadr keep) :id) id))
      (should (equal (plist-get (cadr keep) :adjustments) (plist-get (cadr rows) :adjustments)))
      (should-not (plist-get (cadr reset) :adjustments))
      (should (equal (car reset) (car rows))))
    (should-error (emacsvox-aural-voice-data--replace-choice rows id replacement nil))
    (should-error (emacsvox-aural-voice-data--adjust-choice rows id :pan 'set nil))
    (should-error (emacsvox-aural-voice-data--adjust-choice rows id :pan 'set 10))
    (should-error (emacsvox-aural-voice-data--move-choice rows id 2))
    (let ((duplicates (copy-tree rows)))
      (setf (plist-get (cadr duplicates) :selector) (copy-tree (plist-get (car duplicates) :selector)))
      (should (equal (car (emacsvox-aural-voice-data--move-choice duplicates id 0))
                     (cadr duplicates))))
    (should (equal rows before))))

(ert-deftest emacsvox-aural-voice-choice-custom-edit-creates-new-local-snapshot ()
  "Changing a patch keeps row IDs and creates a new immutable full-chain snapshot."
  (emacsvox-test--with-tuned-storage
   (let* ((snapshot (plist-get (emacsvox-aural-voice-editing--snapshot 'reading 'bolden) :snapshot))
          (rows (emacsvox-aural-voice-data--adjust-choice
                 (plist-get snapshot :choices) "eloquence-male" :richness 'set 8)))
     (setq snapshot (plist-put snapshot :choices rows))
     (let* ((proposal (emacsvox-aural-voice-editing--proposal 'reading 'bolden snapshot 'reading ""))
            (set (car (plist-get proposal :choice-sets)))
            (properties (cdr (assq 'bolden (plist-get (plist-get proposal :palette) :entries)))))
       (should (equal (plist-get set :choices) rows))
       (should-not (equal (plist-get set :id) "reading-bolden-after"))
       (should (equal (plist-get properties :local-choices) (plist-get set :id)))
       (should (equal (plist-get properties :choices) (emacsvox-aural-voice-data--portable-choices rows)))
       (should (equal (plist-get (cadr emacsvox-aural-routing--choice-sets) :choices)
                      (emacsvox-test--tuned-choices)))))))

(ert-deftest emacsvox-aural-voice-choice-shared-edit-retains-tuning-and-reference ()
  "The existing shared editor can save without rewriting any choice patches."
  (emacsvox-test--with-tuned-storage
   (let* ((snapshot (plist-get (emacsvox-aural-voice-editing--snapshot 'reading 'bolden) :snapshot))
          (edited (emacsvox-aural-voice-editing--adjust snapshot 'reading 'richness 9))
          (proposal (emacsvox-aural-voice-editing--proposal 'reading 'bolden edited 'reading "Reading"))
          (entry (cdr (assq 'bolden (plist-get (plist-get proposal :palette) :entries)))))
     (should (equal (plist-get snapshot :choices) (emacsvox-test--tuned-choices)))
     (should (equal (plist-get entry :choices) (emacsvox-aural-voice-data--portable-choices
                                              (emacsvox-test--tuned-choices))))
     (should (= (plist-get (plist-get entry :style) :richness) 9))
     (should (equal (plist-get entry :local-choices) "reading-bolden-after"))
     (should-not (plist-get proposal :choice-sets))
     ;; A caller updating selectors alone cannot silently discard attached tuning.
     (setf (plist-get edited :selectors) nil)
     (should-error (emacsvox-aural-voice-editing--proposal 'reading 'bolden edited 'reading "")
                   :type 'user-error))))

(ert-deftest emacsvox-aural-voice-choice-missing-local-preserved-until-explicit-reset ()
  "A shared edit retains an unresolved reference; choice edits require reset."
  (emacsvox-test--with-tuned-storage
   (let* ((emacsvox-aural-routing--choice-sets nil)
          (snapshot (plist-get (emacsvox-aural-voice-editing--snapshot 'reading 'bolden) :snapshot))
          (proposal (emacsvox-aural-voice-editing--proposal 'reading 'bolden snapshot 'reading "")))
     (should (equal (plist-get (cdr (assq 'bolden (plist-get (plist-get proposal :palette) :entries))) :local-choices)
                    "reading-bolden-after"))
     (setq snapshot (plist-put snapshot :choices
                               (emacsvox-aural-voice-data--adjust-choice
                                (plist-get snapshot :choices) "eloquence-male" :richness 'set 8)))
     (should-error (emacsvox-aural-voice-editing--proposal 'reading 'bolden snapshot 'reading "")
                   :type 'user-error)
     (setq snapshot (plist-put snapshot :reset-choices t))
     (setq proposal (emacsvox-aural-voice-editing--proposal 'reading 'bolden snapshot 'reading ""))
     (should-not (plist-get (cdr (assq 'bolden (plist-get (plist-get proposal :palette) :entries))) :local-choices)))))

(ert-deftest emacsvox-aural-voice-choice-copy-inheritance-and-portable-export ()
  "Copy changes ownership while preserving row IDs, patches and inherited entries."
  (emacsvox-test--with-tuned-storage
   (let* ((copy (emacsvox-aural-voice-data--copy-owned
                 emacsvox-aural-voice-palette-registry 'reading 'copied "Copy"
                 emacsvox-aural-routing--choice-sets '((bolden . "copied-bolden"))))
          (palette (plist-get copy :palette))
          (set (car (plist-get copy :choice-sets)))
          (export (emacsvox-aural-voice-data--portable-export
                   (emacsvox-test--choice-fixture :expected-palette))))
     (should (= (plist-get palette :schema-version) 3))
     (should (eq (plist-get palette :parent) 'acss-default))
     (should (eq (plist-get set :palette) 'copied))
     (should (equal (plist-get set :choices) (emacsvox-test--tuned-choices)))
     (should (equal (assq 'annotate (plist-get palette :entries))
                    (emacsvox-test--choice-fixture :expected-inherited-entry)))
     (should (equal (assq 'bolden (plist-get (plist-get export :palette) :entries))
                    (emacsvox-test--choice-fixture :expected-portable-bolden-entry)))
     (should (equal (plist-get export :omitted-local-choices) '(bolden))))
   (puthash 'child (emacsvox-aural-compile-voice-palette-data
                   '(:schema-version 3 :id child :summary "Child" :parent reading :routing owned :entries nil))
            emacsvox-aural-voice-palette-registry)
   (let* ((snapshot (plist-get (emacsvox-aural-voice-editing--snapshot 'child 'bolden) :snapshot))
          (proposal (emacsvox-aural-voice-editing--proposal 'child 'bolden snapshot 'child ""))
          (set (car (plist-get proposal :choice-sets))))
     (should (= (plist-get (plist-get proposal :palette) :schema-version) 3))
     (should (eq (plist-get set :palette) 'child))
     (should (equal (plist-get set :choices) (emacsvox-test--tuned-choices)))
     (should-not (equal (plist-get set :id) "reading-bolden-after")))))

(ert-deftest emacsvox-aural-voice-choice-read-write-and-unloaded-routing-writer ()
  "Readers never write; another profile writer retains all immutable tuned records."
  (let* ((directory (make-temp-file "voice-choice-data-" t))
         (aural-file (expand-file-name "aural.el" directory))
         (routing-file (expand-file-name "routing.el" directory))
         (aural (list :schema-version 9 :voice-palettes
                       (list (emacsvox-test--choice-fixture :expected-palette)
                             (emacsvox-test--choice-fixture :unchanged-parent))))
         (routing (emacsvox-test--choice-fixture :expected-routing)))
    (unwind-protect
        (progn
          (with-temp-file aural-file (prin1 aural (current-buffer)))
          (with-temp-file routing-file (prin1 routing (current-buffer)))
          (let ((aural-before (emacsvox-aural-voice-drafts--file-id aural-file))
                (routing-before (emacsvox-aural-voice-drafts--file-id routing-file)))
            (should (equal aural (emacsvox-aural-read-user-data aural-file)))
            (should (equal routing (emacsvox-aural-read-routing-profiles routing-file)))
            (should (equal aural-before (emacsvox-aural-voice-drafts--file-id aural-file)))
            (should (equal routing-before (emacsvox-aural-voice-drafts--file-id routing-file)))
            (should-not (file-exists-p (concat aural-file "~"))))
          (emacsvox-aural--write-user-data aural aural-file)
          (let ((emacsvox-aural-routing--choice-sets nil)
                (emacsvox-aural-routing-profile-registry (make-hash-table :test #'eq))
                (emacsvox-aural-active-routing-profile nil))
            (emacsvox-aural-save-routing-profiles routing-file))
          (should (equal aural (emacsvox-aural-read-user-data aural-file)))
          (should (equal routing (emacsvox-aural-read-routing-profiles routing-file))))
      (delete-directory directory t))))

(ert-deftest emacsvox-aural-voice-choice-partial-save-retry-keeps-settings-paired ()
  "The actual save coordinator freezes IDs and keeps old settings until publication."
  (emacsvox-test--with-voice-save
   (let* ((old (emacsvox-aural-voice-drafts--palette-data 'reading-owned))
          (rows (copy-tree (plist-get (car emacsvox-aural-routing--choice-sets) :choices)))
          (rows (emacsvox-aural-voice-data--adjust-choice rows (plist-get (car rows) :id) :richness 'set 7))
          (change (emacsvox-aural-voice-data--put-choices old 'bolden rows "tuned-snapshot"))
          (proposed (plist-get change :palette))
          (proposal (emacsvox-aural-voice-drafts--prepare draft proposed (plist-get change :choice-sets)))
          (write (symbol-function 'emacsvox-aural--write-user-data)))
     (cl-letf (((symbol-function 'emacsvox-aural--write-user-data)
                (lambda (&rest _) (error "Injected second-store failure"))))
       (emacsvox-aural-voice-drafts--save proposal))
     (should (eq (emacsvox-aural-voice-save-state proposal) 'partial))
     (should (equal old (emacsvox-aural-voice-drafts--palette-data 'reading-owned)))
     (let* ((stored (plist-get (emacsvox-aural-read-routing-profiles) :choice-sets))
            (set (cl-find "tuned-snapshot" stored :test #'equal :key (lambda (s) (plist-get s :id)))))
       (should (equal (plist-get set :choices) rows))
       (cl-letf (((symbol-function 'emacsvox-aural--write-user-data) write))
         (emacsvox-aural-voice-drafts--save proposal))
       (should (eq (emacsvox-aural-voice-save-state proposal) 'saved))
       (should (equal proposed (emacsvox-aural-voice-drafts--palette-data 'reading-owned)))
       (should (equal stored (plist-get (emacsvox-aural-read-routing-profiles) :choice-sets)))))))

(defconst emacsvox-test--native-choice-fixture
  (emacsvox-aural-routing--read-one-form
   (expand-file-name "fixtures/voice-editor/engine-parameters-storage.el"
                     (file-name-directory (or load-file-name buffer-file-name)))
   "native voice fixture"))

(defun emacsvox-test--native-choices ()
  "Return the independent contract's complete native choice chain."
  (copy-tree
   (plist-get
    (cadr (plist-get (plist-get emacsvox-test--native-choice-fixture :expected-routing)
                     :choice-sets))
    :choices)))

(ert-deftest emacsvox-aural-native-choice-draft-matches-contract ()
  "Editing duplicate physical voices retains stable ownership and native units."
  (let* ((original (plist-get
                    (car (plist-get
                          (plist-get emacsvox-test--native-choice-fixture :source-routing)
                          :choice-sets)) :choices))
         (before (copy-tree original))
         (rows (emacsvox-aural-voice-data--adjust-native
                original "paul-main" "dectalk" "dectalk.design-voice.v1" "sm" 'set 55)))
    (setq rows (emacsvox-aural-voice-data--adjust-native
                rows "paul-main" "dectalk" "dectalk.design-voice.v1" "br" 'default))
    (setq rows (emacsvox-aural-voice-data--adjust-native
                rows "paul-soft" "dectalk" "dectalk.design-voice.v1" "sm" 'set 80))
    (setq rows (emacsvox-aural-voice-data--adjust-native
                rows "eci-default" "eloquence" "eloquence.eci-units.v1" "breathiness" 'set 42))
    (should (equal rows (emacsvox-test--native-choices)))
    (should (equal original before))
    (should (equal (emacsvox-aural-routing--validate-choices rows nil t) rows))))

(ert-deftest emacsvox-aural-native-choice-inherit-default-and-false ()
  "Set zero, set false, engine default and absence remain distinct."
  (dolist (case (plist-get emacsvox-test--native-choice-fixture :native-value-cases))
    (let* ((operation (plist-get case :operation))
           (rows (emacsvox-aural-voice-data--adjust-native
                  (emacsvox-test--native-choices) "paul-soft" "dectalk"
                  "dectalk.design-voice.v1" "sm" (plist-get operation :op)
                  (plist-get operation :value))))
      (should (equal (cdr (assoc "sm" (plist-get (plist-get (cadr rows) :native) :parameters)))
                     operation))))
  (let* ((before (emacsvox-test--native-choices))
         (rows (emacsvox-aural-voice-data--adjust-native
                before "paul-soft" "dectalk" "dectalk.design-voice.v1" "sm" 'inherit)))
    (should-not (plist-member (cadr rows) :native))
    (should (equal (car rows) (car before)))
    (should (equal (cddr rows) (cddr before)))
    (should (plist-member (cadr before) :native))
    (should (equal rows (emacsvox-aural-voice-data--adjust-native
                        rows "paul-soft" "dectalk" "dectalk.design-voice.v1" "sm" 'inherit)))))

(ert-deftest emacsvox-aural-native-choice-reorder-and-common-edits-preserve-native ()
  "Reordering and common tuning leave native records attached to their choices."
  (let* ((before (emacsvox-test--native-choices))
         (rows (emacsvox-aural-voice-data--move-choice before "paul-main" 2))
         (edited (emacsvox-aural-voice-data--adjust-choice rows "paul-main" :richness 'set 0)))
    (should (equal rows (list (cadr before) (caddr before) (car before))))
    (should (equal (plist-get (caddr edited) :native) (plist-get (car before) :native)))
    (should (equal (plist-get (caddr edited) :adjustments) '(:richness 0)))
    (should-not (plist-get (car before) :adjustments))
    (should (equal (emacsvox-aural-voice-data--portable-choices edited)
                   (list (caddr before))))))

(ert-deftest emacsvox-aural-native-choice-replacement-keeps-or-resets-explicitly ()
  "Engine changes cannot silently inherit another engine's native settings."
  (let* ((rows (emacsvox-test--native-choices))
         (same '(:kind exact :scope local :engine-id "dectalk" :voice-id "harry"))
         (other '(:kind engine-default :scope portable :engine-id "eloquence")))
    (should (equal (plist-get (car (emacsvox-aural-voice-data--replace-choice
                                    rows "paul-main" same 'keep)) :native)
                   (plist-get (car rows) :native)))
    (should-error (emacsvox-aural-voice-data--replace-choice rows "paul-main" other 'keep))
    (let ((reset (emacsvox-aural-voice-data--replace-choice rows "paul-main" other 'reset)))
      (should (equal (plist-get (car reset) :selector) other))
      (should-not (plist-member (car reset) :native))
      (should (equal (cdr reset) (cdr rows))))
    (should-error (emacsvox-aural-voice-data--adjust-native
                   rows "paul-main" "dectalk" "dectalk.other.v1" "sm" 'set 20))
    (should-error (emacsvox-aural-voice-data--adjust-native
                   rows "absent" "dectalk" "dectalk.design-voice.v1" "sm" 'set 20))))

(ert-deftest emacsvox-aural-native-choice-removal-is-independent-of-key-order ()
  "Native removal also works when the optional field is first in the plist."
  (let* ((row (copy-tree (cadr (emacsvox-test--native-choices))))
         (native (plist-get row :native)))
    (cl-remf row :native)
    (setq row (append (list :native native) row))
    (should-not (plist-member
                 (car (emacsvox-aural-voice-data--adjust-native
                       (list row) "paul-soft" "dectalk" "dectalk.design-voice.v1" "sm" 'inherit))
                 :native))
    (should-not (plist-member
                 (car (emacsvox-aural-voice-data--replace-choice
                       (list row) "paul-soft" (plist-get row :selector) 'reset)) :native))))

(ert-deftest emacsvox-aural-native-choice-preserves-unknown-inert-identities ()
  "Unknown semantic IDs survive validation without engine discovery or interning."
  (let* ((engine "uninstalled-test-engine-790d")
         (parameter "unadvertised-test-control-790d")
         (native (list :engine-id engine :schema-id "future.schema.v73"
                       :parameters (list (list parameter :op 'set :value "future-enum"))))
         (selector (list :kind 'properties :scope 'portable :engine-id engine :language "en")))
    (should-not (intern-soft parameter))
    (should (equal native (emacsvox-aural-routing--validate-native native selector)))
    (should-not (intern-soft parameter))
    (should-error (emacsvox-aural-routing--validate-native
                   native '(:kind properties :scope portable :language "en")))))

(ert-deftest emacsvox-aural-native-choice-validates-finite-typed-scalars ()
  "Accept bounded native scalars and reject executable or lossy representations."
  (let* ((row (car (emacsvox-test--native-choices)))
         (native (plist-get row :native))
         (selector (plist-get row :selector)))
    (dolist (value (list nil t 0 -1 (- (expt 2 63)) (1- (expt 2 63))
                         0.0 1.5 -4.3 "enum-value_1"))
      (setf (plist-get native :parameters) (list (list "sm" :op 'set :value value)))
      (should (equal native (emacsvox-aural-routing--validate-native native selector))))
    (dolist (value (list (expt 2 63) (1- (- (expt 2 63)))
                         1.0e+INF -1.0e+INF 0.0e+NaN
                         "" "two words" "é" (make-string 129 ?a)
                         :false 'false '(eval anything) [1 2] (current-buffer)))
      (setf (plist-get native :parameters) (list (list "sm" :op 'set :value value)))
      (should-error (emacsvox-aural-routing--validate-native native selector)))))

(ert-deftest emacsvox-aural-native-choice-rejects-malformed-records ()
  "Reject duplicate IDs, fields, operations and oversized or cyclic containers."
  (let* ((row (car (emacsvox-test--native-choices)))
         (native (plist-get row :native))
         (selector (plist-get row :selector)))
    (dolist (operation '((:op set) (:op default :value nil) (:op inherit)
                         (:op set :value 1 :value 2) (:op default :extra nil)
                         (:op default :op set) (:value 1) (:op . set)))
      (should-error (emacsvox-aural-routing--validate-native
                     (plist-put (copy-tree native) :parameters (list (cons "sm" operation))) selector)))
    (dolist (parameters (list '(("sm" :op default) ("sm" :op set :value 2))
                              '(("sm" :op default) . tail) '(bad) '((nil :op default))
                              (cl-loop for i below 65 collect (list (format "p%d" i) :op 'default))))
      (should-error (emacsvox-aural-routing--validate-native
                     (plist-put (copy-tree native) :parameters parameters) selector)))
    (let ((cycle (list '("sm" :op default))))
      (setcdr cycle cycle)
      (should-error (emacsvox-aural-routing--validate-native
                     (plist-put (copy-tree native) :parameters cycle) selector)))
    (dolist (key '(:engine-id :schema-id))
      (dolist (value (list "" "bad id" "é" (make-string 129 ?a) 'symbol nil))
        (should-error (emacsvox-aural-routing--validate-native
                       (plist-put (copy-tree native) key value) selector))))
    (should-error (emacsvox-aural-routing--validate-native
                   (append native '(:schema-id "duplicate")) selector))
    (should-error (emacsvox-aural-routing--validate-native
                   (append native '(:profile-id "runtime-only")) selector))
    (should-error (emacsvox-aural-routing--validate-native
                   native (append selector '(:engine-id "eloquence"))))
    (should-error (emacsvox-aural-routing--validate-native nil selector))))

(ert-deftest emacsvox-aural-native-choice-operation-limit-is-atomic ()
  "Replacing one of 64 controls is valid; adding another leaves input intact."
  (let* ((rows (emacsvox-test--native-choices))
         (native (plist-get (car rows) :native)))
    (setf (plist-get native :parameters)
          (cl-loop for i below 64 collect (list (format "p%d" i) :op 'default)))
    (let ((before (emacsvox-aural-routing--validate-choices rows nil t)))
      (should (emacsvox-aural-voice-data--adjust-native
               rows "paul-main" "dectalk" "dectalk.design-voice.v1" "p63" 'set 0))
      (should-error (emacsvox-aural-voice-data--adjust-native
                     rows "paul-main" "dectalk" "dectalk.design-voice.v1" "p64" 'set 0))
      (should (equal rows before)))))

(ert-deftest emacsvox-aural-native-choice-copies-native-strings-and-operations ()
  "A returned draft cannot mutate a saved native record, including its strings."
  (let* ((rows (emacsvox-aural-voice-data--adjust-native
                (emacsvox-test--native-choices) "paul-main" "dectalk"
                "dectalk.design-voice.v1" "enum" 'set (copy-sequence "choice")))
         (before (emacsvox-aural-routing--validate-choices rows nil t))
         (copy (emacsvox-aural-routing--validate-choices rows nil t))
         (native (plist-get (car copy) :native))
         (parameters (plist-get native :parameters)))
    (aset (plist-get native :engine-id) 0 ?x)
    (aset (plist-get native :schema-id) 0 ?x)
    (aset (caar parameters) 0 ?x)
    (aset (plist-get (cdr (assoc "enum" parameters)) :value) 0 ?x)
    (setf (plist-get (cdr (assoc "br" parameters)) :op) 'set)
    (should (equal rows before))))

(ert-deftest emacsvox-aural-native-choice-requires-versioned-storage ()
  "Old storage and wire readers cannot accept native data under their old schema."
  (let ((rows (emacsvox-test--native-choices)))
    (should-error (emacsvox-aural-routing--validate-choices rows))
    (should-error (emacsvox-aural-compile-voice-palette-data
                   (plist-put (copy-tree (plist-get emacsvox-test--native-choice-fixture :expected-palette))
                              :schema-version 3)))
    (should-error (emacsvox-aural-validate-routing-user-data
                   (plist-put (copy-tree (plist-get emacsvox-test--native-choice-fixture :expected-routing))
                              :schema-version 3)))))

(defun emacsvox-test--native-fixture (key)
  "Return an independent native storage fixture under KEY."
  (copy-tree (plist-get emacsvox-test--native-choice-fixture key)))

(defmacro emacsvox-test--with-native-storage (&rest body)
  "Run BODY with the native contract's palette and immutable snapshots."
  (declare (indent 0) (debug t))
  `(let ((emacsvox-aural-voice-palette-registry
          (emacsvox-test--voice-data-registry (list (emacsvox-test--native-fixture :expected-palette))))
         (emacsvox-aural-routing--choice-sets
          (plist-get (emacsvox-test--native-fixture :expected-routing) :choice-sets)))
     ,@body))

(ert-deftest emacsvox-aural-native-storage-promotion-matches-contract ()
  "First native save promotes the edited owner and publishes a new snapshot."
  (let* ((source (emacsvox-test--native-fixture :source-palette))
         (before (copy-tree source))
         (proposal (emacsvox-aural-voice-data--put-choices
                    source 'bolden (emacsvox-test--native-choices) "reading-bolden-after"))
         (routing (emacsvox-test--native-fixture :source-routing)))
    (should (equal (plist-get proposal :palette) (emacsvox-test--native-fixture :expected-palette)))
    (should (equal (emacsvox-aural-routing--with-choice-sets
                    routing (emacsvox-aural-routing--merge-choice-sets
                             (plist-get routing :choice-sets) (plist-get proposal :choice-sets)))
                   (emacsvox-test--native-fixture :expected-routing)))
    (should (equal source before))
    (should (equal (plist-get (emacsvox-aural-voice-data--portable-export
                              (plist-get proposal :palette)) :palette)
                   (emacsvox-test--native-fixture :expected-portable-palette)))))

(ert-deftest emacsvox-aural-native-storage-removal-preserves-existing-schema ()
  "Removing native edits never rewrites a retained snapshot or downgrades its owner."
  (let* ((palette (emacsvox-test--native-fixture :expected-palette))
         (routing (emacsvox-test--native-fixture :expected-routing))
         (rows (mapcar (lambda (row) (cl-remf row :native) row) (emacsvox-test--native-choices)))
         (proposal (emacsvox-aural-voice-data--put-choices palette 'bolden rows "common-again"))
         (sets (emacsvox-aural-routing--merge-choice-sets
                (plist-get routing :choice-sets) (plist-get proposal :choice-sets))))
    (should (= (plist-get (plist-get proposal :palette) :schema-version) 4))
    (should (= (plist-get (car (plist-get proposal :choice-sets)) :schema-version) 3))
    (should (= (plist-get (emacsvox-aural-routing--with-choice-sets routing sets) :schema-version) 4))
    (should (equal (cl-subseq sets 0 2) (plist-get routing :choice-sets)))
    (should-error (emacsvox-aural-voice-data--put-choices
                   (plist-put (copy-tree palette) :schema-version 99)
                   'bolden (emacsvox-test--native-choices) "invalid-version"))
    (should-error (emacsvox-aural-routing--with-choice-sets
                   (plist-put (copy-tree routing) :schema-version 99) sets))))

(ert-deftest emacsvox-aural-native-storage-local-only-still-promotes-owner ()
  "A local native choice requires schema four even with no portable controls."
  (let* ((proposal (emacsvox-aural-voice-data--put-choices
                    (emacsvox-test--native-fixture :source-palette) 'bolden
                    (list (car (emacsvox-test--native-choices))) "local-only"))
         (data (plist-get proposal :palette))
         (sets (plist-get proposal :choice-sets)))
    (should (= (plist-get data :schema-version) 4))
    (should-not (plist-get (cdr (assq 'bolden (plist-get data :entries))) :choices))
    (should-error (emacsvox-aural-voice-data--choices
                   'reading 'bolden (cdr (assq 'bolden (plist-get data :entries))) sets 3))
    (should-error (emacsvox-aural-routing--validate-choice-sets
                   (list (plist-put (copy-tree (car sets)) :schema-version 3))))))

(ert-deftest emacsvox-aural-native-storage-inheritance-copy-and-exchange ()
  "Copy and both exchange formats retain native settings under the right owner."
  (emacsvox-test--with-native-storage
    (puthash 'child (emacsvox-aural-compile-voice-palette-data
                    '(:schema-version 3 :id child :summary "Child" :parent reading
                      :routing owned :entries nil)) emacsvox-aural-voice-palette-registry)
    (let* ((resolved (emacsvox-aural-voice-data--resolve
                      'voice-bolden 'child emacsvox-aural-voice-palette-registry
                      emacsvox-aural-routing--choice-sets nil))
           (copy (emacsvox-aural-voice-data--copy-owned
                  emacsvox-aural-voice-palette-registry 'child 'copy "Copy"
                  emacsvox-aural-routing--choice-sets '((bolden . "copy-local"))))
           (backup (emacsvox-aural-voice-data--backup
                    emacsvox-aural-voice-palette-registry 'child emacsvox-aural-routing--choice-sets))
           (export (plist-get (emacsvox-aural-voice-data--export-effective
                              emacsvox-aural-voice-palette-registry 'child) :palette))
           (root (gethash 'acss-default emacsvox-aural-voice-palette-registry)))
      (should (eq (plist-get resolved :palette) 'reading))
      (should (equal (plist-get resolved :choices) (emacsvox-test--native-choices)))
      (should (= (plist-get (plist-get copy :palette) :schema-version) 4))
      (should (eq (plist-get (car (plist-get copy :choice-sets)) :palette) 'copy))
      (should (equal (plist-get (car (plist-get copy :choice-sets)) :choices) (plist-get resolved :choices)))
      (let* ((inputs (emacsvox-aural-voice-data--read-exchange backup root))
             (again (emacsvox-aural-voice-data--resolve
                     'bolden 'child (plist-get inputs :registry) (plist-get inputs :choice-sets) nil)))
        (should (equal again (emacsvox-aural-voice-data--resolve
                             'bolden 'child emacsvox-aural-voice-palette-registry
                             emacsvox-aural-routing--choice-sets nil))))
      (let* ((inputs (emacsvox-aural-voice-data--read-exchange export root))
             (again (emacsvox-aural-voice-data--resolve
                     'bolden 'child (plist-get inputs :registry) nil nil)))
        (should (equal (plist-get again :choices)
                       (emacsvox-aural-voice-data--portable-choices (emacsvox-test--native-choices)))))
      (should (= (plist-get (emacsvox-aural-voice-palette-data-form
                            (gethash 'child emacsvox-aural-voice-palette-registry)) :schema-version) 3)))))

(ert-deftest emacsvox-aural-native-storage-projection-and-owner-disagreement ()
  "Native operations participate in cross-store equality and owner checks."
  (let* ((palette (emacsvox-test--native-fixture :expected-palette))
         (properties (cdr (assq 'bolden (plist-get palette :entries))))
         (sets (plist-get (emacsvox-test--native-fixture :expected-routing) :choice-sets)))
    (let ((row (car (plist-get properties :choices))))
      (setf (plist-get row :native)
            '(:engine-id "eloquence" :schema-id "eloquence.eci-units.v1"
              :parameters (("breathiness" :op set :value 41)))))
    (should-error (emacsvox-aural-voice-data--choices 'reading 'bolden properties sets 4))
    (should-error (emacsvox-aural-voice-data--choices 'other 'bolden properties sets 4))
    (let ((missing (emacsvox-aural-voice-data--choices 'reading 'bolden properties nil 4)))
      (should (equal (plist-get missing :diagnostics) '(missing-local-choices)))
      (should (equal (plist-get missing :choices) (plist-get properties :choices))))))

(ert-deftest emacsvox-aural-native-storage-read-write-and-unloaded-writer ()
  "Data-only round trips retain native snapshots even in a client that has not loaded them."
  (let* ((directory (make-temp-file "native-storage-" t))
         (aural-file (expand-file-name "aural.el" directory))
         (routing-file (expand-file-name "routing.el" directory))
         (aural (list :schema-version 10 :voice-palettes (list (emacsvox-test--native-fixture :expected-palette))))
         (routing (emacsvox-test--native-fixture :expected-routing))
         (emacsvox-aural-routing--choice-sets nil)
         (emacsvox-aural-routing-profile-registry (make-hash-table :test #'eq))
         (emacsvox-aural-active-routing-profile nil))
    (unwind-protect
        (progn
          (should-error (emacsvox-aural--validate-user-data
                         (plist-put (copy-tree aural) :schema-version 9)))
          (should-error (emacsvox-aural--validate-user-data
                         (append aural '(:schema-version 10))))
          (emacsvox-aural--write-user-data aural aural-file)
          (emacsvox-aural-routing--write-user-data routing routing-file)
          (let ((before (emacsvox-aural-voice-drafts--file-id aural-file)))
            (should (equal aural (emacsvox-aural-read-user-data aural-file)))
            (should (equal before (emacsvox-aural-voice-drafts--file-id aural-file))))
          (emacsvox-aural-save-routing-profiles routing-file)
          (should (equal routing (emacsvox-aural-read-routing-profiles routing-file)))
          (should-not emacsvox-aural-routing--choice-sets)
          (should (= (plist-get (emacsvox-aural-routing-user-data) :schema-version) 3)))
      (delete-directory directory t))))

(ert-deftest emacsvox-aural-native-storage-shared-edit-and-inherited-edit ()
  "Shared edits retain local references; editing an inherited entry creates a new owner."
  (emacsvox-test--with-native-storage
    (let* ((snapshot (plist-get (emacsvox-aural-voice-editing--snapshot 'reading 'bolden) :snapshot))
           (changed (emacsvox-aural-voice-editing--adjust snapshot 'reading 'average-pitch 3))
           (proposal (emacsvox-aural-voice-editing--proposal 'reading 'bolden changed 'reading "Reading")))
      (should-not (plist-get proposal :choice-sets))
      (should (equal (plist-get (cdr (assq 'bolden (plist-get (plist-get proposal :palette) :entries)))
                               :local-choices) "reading-bolden-after"))
      (puthash 'child (emacsvox-aural-compile-voice-palette-data
                      '(:schema-version 3 :id child :summary "Child" :parent reading
                        :routing owned :entries nil)) emacsvox-aural-voice-palette-registry)
      (let* ((inherited (emacsvox-aural-voice-editing--proposal 'child 'bolden changed 'child "Child"))
             (set (car (plist-get inherited :choice-sets))))
        (should (= (plist-get (plist-get inherited :palette) :schema-version) 4))
        (should (eq (plist-get set :palette) 'child))
        (should (equal (plist-get set :choices) (emacsvox-test--native-choices)))))))

(ert-deftest emacsvox-aural-native-storage-partial-save-and-undo ()
  "A failed palette write keeps the old chain; retry reuses the frozen native snapshot."
  (emacsvox-test--with-voice-save
    (let* ((old (emacsvox-aural-voice-drafts--palette-data 'reading-owned))
           (changed (emacsvox-aural-voice-data--put-choices
                     old 'bolden (emacsvox-test--native-choices) "native-after"))
           (proposal (emacsvox-aural-voice-drafts--prepare
                      draft (plist-get changed :palette) (plist-get changed :choice-sets)))
           (original-write (symbol-function 'emacsvox-aural--write-user-data)))
      (cl-letf (((symbol-function 'emacsvox-aural--write-user-data)
                 (lambda (&rest _) (error "Injected native palette failure"))))
        (emacsvox-aural-voice-drafts--save proposal))
      (should (eq (emacsvox-aural-voice-save-state proposal) 'partial))
      (should (equal old (emacsvox-aural-voice-drafts--palette-data 'reading-owned)))
      (should (= (plist-get (emacsvox-aural-read-routing-profiles) :schema-version) 4))
      (should (= (plist-get (emacsvox-aural-read-user-data) :schema-version) 9))
      (let ((stored (emacsvox-aural-read-routing-profiles)))
        (cl-letf (((symbol-function 'emacsvox-aural--write-user-data) original-write))
          (emacsvox-aural-voice-drafts--save proposal))
        (should (eq (emacsvox-aural-voice-save-state proposal) 'saved))
        (should (= (plist-get (emacsvox-aural-read-user-data) :schema-version) 10))
        (should (equal stored (emacsvox-aural-read-routing-profiles))))
      (let* ((rows (emacsvox-test--native-choices))
             (draft (emacsvox-aural-voice-drafts--make :baseline (list :choices rows) :working (list :choices rows))))
        (emacsvox-aural-voice-drafts--edit
         draft (list :choices (emacsvox-aural-voice-data--adjust-native
                               rows "paul-main" "dectalk" "dectalk.design-voice.v1" "sm" 'set 66)))
        (should (equal (emacsvox-aural-voice-drafts--dirty-fields draft) '(:choices)))
        (emacsvox-aural-voice-drafts--undo draft)
        (should-not (emacsvox-aural-voice-drafts--dirty-fields draft))))))

(provide 'emacsvox-aural-voice-choice-tests)
;;; emacsvox-aural-voice-choice-tests.el ends here
