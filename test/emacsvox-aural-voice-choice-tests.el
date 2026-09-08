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

(ert-deftest emacsvox-aural-voice-choice-promotion-matches-independent-fixture ()
  "Only the affected palette is promoted, with complete immutable local data."
  (let* ((source (emacsvox-test--choice-fixture :source-palette))
         (before (copy-tree source))
         (rows (emacsvox-test--tuned-choices))
         (proposal (emacsvox-aural-voice-data--put-choices
                    source 'bolden rows "reading-bolden-after"
                    '((smoothen "espeak-default"))))
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
                             '((smoothen "espeak-default")))))))

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
                   (list (plist-put (copy-tree (cadr sets)) :schema-version 4)))))
  (let ((data (emacsvox-test--choice-fixture :expected-palette)))
    (should-error (emacsvox-aural-compile-voice-palette-data (plist-put data :schema-version 2)))))

(ert-deftest emacsvox-aural-voice-choice-resolves-owned-records-and-session-replacement ()
  "Aliases and temporary routes retain their scope without physical-ID patch joins."
  (emacsvox-test--with-tuned-storage
   (let* ((rows (emacsvox-test--tuned-choices))
          (resolve (lambda (voice &optional session)
                     (emacsvox-aural-voice-data--resolve
                      voice 'reading emacsvox-aural-voice-palette-registry
                      emacsvox-aural-routing--choice-sets nil session nil)))
          (saved (funcall resolve 'bolden))
          (alias (funcall resolve 'voice-bolden))
          (temporary (funcall resolve 'bolden
                              (list (cons 'bolden (list (plist-get (car rows) :selector)))))))
     (should (equal (plist-get saved :choices) rows))
     (should (equal (plist-get alias :choices) rows))
     (should (equal (plist-get saved :selectors) (emacsvox-aural-voice-data--selectors rows)))
     (should (eq (plist-get temporary :choice-source) 'session))
     (should-not (plist-get (car (plist-get temporary :choices)) :adjustments))
     (should (equal (plist-get (funcall resolve 'bolden) :choices) rows))
     (setf (plist-get (car (plist-get saved :choices)) :adjustments) nil)
     (should (equal (plist-get (funcall resolve 'bolden) :choices) rows)))))

(ert-deftest emacsvox-aural-voice-choice-rejects-cross-store-disagreement ()
  "Wrong owners and inconsistent portable projections cannot silently load."
  (let* ((data (emacsvox-test--choice-fixture :expected-palette))
         (properties (cdr (assq 'bolden (plist-get data :entries))))
         (sets (plist-get (emacsvox-test--choice-fixture :expected-routing) :choice-sets)))
    (should-error (emacsvox-aural-voice-data--choices 'other 'bolden properties sets 3))
    (should-error (emacsvox-aural-voice-data--choices 'reading 'bolden properties sets 2))
    (setf (plist-get (car (plist-get properties :choices)) :adjustments) nil)
    (should-error (emacsvox-aural-voice-data--choices 'reading 'bolden properties sets 3)))
  (let* ((data (emacsvox-test--choice-fixture :expected-palette))
         (properties (cdr (assq 'bolden (plist-get data :entries))))
         (sets (plist-get (emacsvox-test--choice-fixture :source-routing) :choice-sets)))
    (setq properties (plist-put properties :local-choices "reading-bolden-before"))
    (should-error (emacsvox-aural-voice-data--choices 'reading 'bolden properties sets 3))))

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
   (let* ((snapshot (plist-get (emacsvox-aural-voice-editing--snapshot 'reading 'bolden nil) :snapshot))
          (rows (emacsvox-aural-voice-data--adjust-choice
                 (plist-get snapshot :choices) "eloquence-male" :richness 'set 8)))
     (setq snapshot (plist-put snapshot :choices rows))
     (let* ((proposal (emacsvox-aural-voice-editing--proposal 'reading 'bolden snapshot 'reading "" nil))
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
   (let* ((snapshot (plist-get (emacsvox-aural-voice-editing--snapshot 'reading 'bolden nil) :snapshot))
          (edited (emacsvox-aural-voice-editing--adjust snapshot 'reading 'richness 9))
          (proposal (emacsvox-aural-voice-editing--proposal 'reading 'bolden edited 'reading "Reading" nil))
          (entry (cdr (assq 'bolden (plist-get (plist-get proposal :palette) :entries)))))
     (should (equal (plist-get snapshot :choices) (emacsvox-test--tuned-choices)))
     (should (equal (plist-get entry :choices) (emacsvox-aural-voice-data--portable-choices
                                              (emacsvox-test--tuned-choices))))
     (should (= (plist-get (plist-get entry :style) :richness) 9))
     (should (equal (plist-get entry :local-choices) "reading-bolden-after"))
     (should-not (plist-get proposal :choice-sets))
     ;; A caller updating selectors alone cannot silently discard attached tuning.
     (setf (plist-get edited :selectors) nil)
     (should-error (emacsvox-aural-voice-editing--proposal 'reading 'bolden edited 'reading "" nil)
                   :type 'user-error))))

(ert-deftest emacsvox-aural-voice-choice-missing-local-preserved-until-explicit-reset ()
  "A shared edit retains an unresolved reference; choice edits require reset."
  (emacsvox-test--with-tuned-storage
   (let* ((emacsvox-aural-routing--choice-sets nil)
          (snapshot (plist-get (emacsvox-aural-voice-editing--snapshot 'reading 'bolden nil) :snapshot))
          (proposal (emacsvox-aural-voice-editing--proposal 'reading 'bolden snapshot 'reading "" nil)))
     (should (equal (plist-get (cdr (assq 'bolden (plist-get (plist-get proposal :palette) :entries))) :local-choices)
                    "reading-bolden-after"))
     (setq snapshot (plist-put snapshot :choices
                               (emacsvox-aural-voice-data--adjust-choice
                                (plist-get snapshot :choices) "eloquence-male" :richness 'set 8)))
     (should-error (emacsvox-aural-voice-editing--proposal 'reading 'bolden snapshot 'reading "" nil)
                   :type 'user-error)
     (setq snapshot (plist-put snapshot :reset-choices t))
     (setq proposal (emacsvox-aural-voice-editing--proposal 'reading 'bolden snapshot 'reading "" nil))
     (should-not (plist-get (cdr (assq 'bolden (plist-get (plist-get proposal :palette) :entries))) :local-choices)))))

(ert-deftest emacsvox-aural-voice-choice-promoted-old-reference-remains-untouched ()
  "Promotion leaves old local sets immutable and shared edits keep that reference."
  (let* ((data (emacsvox-aural-voice-data--promote (emacsvox-test--choice-fixture :source-palette)))
         (emacsvox-aural-voice-palette-registry
          (emacsvox-test--voice-data-registry (list data (emacsvox-test--choice-fixture :unchanged-parent))))
         (emacsvox-aural-routing--choice-sets
          (plist-get (emacsvox-test--choice-fixture :source-routing) :choice-sets))
         (snapshot (plist-get (emacsvox-aural-voice-editing--snapshot 'reading 'bolden nil) :snapshot))
         (proposal (emacsvox-aural-voice-editing--proposal 'reading 'bolden snapshot 'reading "" nil)))
    (should (equal (plist-get (cdr (assq 'bolden (plist-get (plist-get proposal :palette) :entries))) :choices)
                   (plist-get (cdr (assq 'bolden (plist-get data :entries))) :choices)))
    (should (equal (plist-get (cdr (assq 'bolden (plist-get (plist-get proposal :palette) :entries))) :local-choices)
                   "reading-bolden-before"))
    (should-not (cl-some (lambda (row) (plist-get row :adjustments)) (plist-get snapshot :choices)))
    (should-not (plist-get proposal :choice-sets))))

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
     (should-not (plist-get palette :parent))
     (should (eq (plist-get set :palette) 'copied))
     (should (equal (plist-get set :choices) (emacsvox-test--tuned-choices)))
     (should (equal (assq 'annotate (plist-get palette :entries))
                    (emacsvox-test--choice-fixture :expected-inherited-entry)))
     (should (equal (assq 'bolden (plist-get (plist-get export :palette) :entries))
                    (emacsvox-test--choice-fixture :expected-portable-bolden-entry)))
     (should (equal (plist-get export :omitted-local-choices) '(bolden))))
   (puthash 'child (emacsvox-aural-compile-voice-palette-data
                   '(:schema-version 2 :id child :summary "Child" :parent reading :routing owned :entries nil))
            emacsvox-aural-voice-palette-registry)
   (let* ((snapshot (plist-get (emacsvox-aural-voice-editing--snapshot 'child 'bolden nil) :snapshot))
          (proposal (emacsvox-aural-voice-editing--proposal 'child 'bolden snapshot 'child "" nil))
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

(ert-deftest emacsvox-aural-voice-choice-selector-only-palette-copy-cannot-reuse-owner ()
  "The older palette copier cannot publish another owner's local references."
  (require 'emacsvox-aural-voice-palettes)
  (emacsvox-test--with-tuned-storage
   (let ((before (hash-table-count emacsvox-aural-voice-palette-registry)))
     (cl-letf (((symbol-function 'emacsvox-aural-voice-palettes--read-new-id)
                (lambda (&rest _) (ert-fail "Unsupported copy prompted before validation")))
               ((symbol-function 'emacsvox-aural-save-user-data)
                (lambda (&rest _) (ert-fail "Unsupported copy wrote palette data"))))
       (should-error (emacsvox-aural-voice-palettes--copy 'reading) :type 'user-error))
     (should (= before (hash-table-count emacsvox-aural-voice-palette-registry))))))

(ert-deftest emacsvox-aural-voice-choice-partial-save-retry-keeps-settings-paired ()
  "The actual save coordinator freezes IDs and keeps old settings until publication."
  (emacsvox-test--with-voice-save
   (let* ((old (emacsvox-aural-voice-drafts--palette-data 'reading-owned))
          (rows (emacsvox-aural-voice-data--wrap-selectors
                 (plist-get (car emacsvox-aural-routing--choice-sets) :selectors)))
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

(provide 'emacsvox-aural-voice-choice-tests)
;;; emacsvox-aural-voice-choice-tests.el ends here
