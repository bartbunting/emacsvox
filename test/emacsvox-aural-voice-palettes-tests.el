;;; emacsvox-aural-voice-palettes-tests.el --- Voice palette manager tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Test accessible voice-palette management, activation, and preview.

;;; Code:

(require 'ert)
(require 'emacsvox-aural-voice-palettes)
(require 'emacsvox-aural-voice-choice-tests)
(require 'emacsvox-aural-voice-editor)

(ert-deftest emacsvox-aural-voice-palettes-retired-screens-are-unavailable ()
  "The common editor is the only named and physical voice editing screen."
  (dolist (command '(emacsvox-aural-voice-tuner-open
                     emacsvox-aural-voice-experiment-open
                     emacsvox-aural-voice-palettes--read-definition
                     emacsvox-aural-voice-workbench--tune-logical))
    (should-not (fboundp command)))
  (should (fboundp 'emacsvox-aural-voice-editor-open))
  (should (fboundp 'emacsvox-aural-voice-editor-experiment)))

(defmacro emacsvox-test--with-voice-palettes (&rest body)
  "Run BODY with isolated voice-palette and presentation state."
  (declare (indent 0) (debug t))
  `(let ((emacsvox-aural-voice-palette-registry
          (copy-hash-table emacsvox-aural-voice-palette-registry))
         (emacsvox-aural-scheme-registry
          (make-hash-table :test #'eq))
         (emacsvox-aural-profile-registry
          (make-hash-table :test #'eq))
         (emacsvox-aural-voice-palette-override nil)
         (emacsvox-aural-voice-palette-changed-hook nil)
         (emacsvox-aural-voice-palettes--last-preview-voices
          (make-hash-table :test #'eq))
         (emacsvox-aural-voice-palettes-preview-text
          "The quick brown fox jumps over the lazy dog.")
         (emacsvox-aural-active-scheme 'default))
     (emacsvox-aural--register-default-scheme)
     (cl-letf (((symbol-function 'tts-speak) #'ignore))
       ,@body)))

(defconst emacsvox-test--voice-palette-data
  '(:routing owned :schema-version 3 :id reading :summary "Reading voices" :parent acss-default :entries ((heading :personality voice-bolden :choices nil) (aside :style (:family nil :average-pitch 4 :pitch-range 3 :stress nil :richness 6) :choices nil)))
  "Personal palette used by manager tests.")

(ert-deftest emacsvox-aural-voice-palettes-rows-and-bindings-are-complete ()
  "The manager reports provider state and exposes accessible operations."
  (emacsvox-test--with-voice-palettes
    (emacsvox-aural-register-voice-palette-data
     emacsvox-test--voice-palette-data)
    (with-temp-buffer
      (emacsvox-aural-voice-palettes-mode)
      (emacsvox-aural-voice-palettes-refresh 'reading)
      (let ((row (cadr (assq 'reading tabulated-list-entries))))
        (should (equal (aref row 0) "reading"))
        (should (equal (aref row 2) "personal"))
        (should (equal (aref row 3) "acss-default"))
        (should (equal (aref row 4) "2"))
        (should (= (string-to-number (aref row 5))
                   (length (emacsvox-aural-effective-voice-entries 'reading)))))
      (dolist
          (binding
           '(("RET" . emacsvox-aural-voice-palettes-preview)
             ("B" . emacsvox-aural-voice-palettes-preview)
             ("a" . emacsvox-aural-voice-palettes-activate)
             ("f" . emacsvox-aural-voice-palettes-follow-baseline)
             ("N" . emacsvox-aural-voice-palettes-create)
             ("c" . emacsvox-aural-voice-palettes-copy)
             ("r" . emacsvox-aural-voice-palettes-rename)
             ("e" . emacsvox-aural-voice-palettes-edit-entry)
             ("E" . emacsvox-aural-voice-palettes-edit-metadata)
             ("D" . emacsvox-aural-voice-palettes-delete-entry)
             ("d" . emacsvox-aural-voice-palettes-delete)
             ("P" . emacsvox-aural-voice-palettes-audition)
             ("x" . emacsvox-aural-voice-palettes-explain)
             ("v" . emacsvox-aural-voice-palettes-describe)
             ("h" . emacsvox-aural)
             ("?" . emacsvox-aural-voice-palettes-help)))
        (should
         (eq
          (lookup-key
           emacsvox-aural-voice-palettes-mode-map
           (kbd (car binding)))
          (cdr binding)))))))

(ert-deftest emacsvox-aural-voice-palettes-arrows-speak-selected-column ()
  "Vertical arrows preserve the selected column and speak its new value."
  (emacsvox-test--with-voice-palettes
    (emacsvox-aural-register-voice-palette-data
     emacsvox-test--voice-palette-data)
    (with-temp-buffer
      (emacsvox-aural-voice-palettes-mode)
      (setq tabulated-list-entries
            (mapcar #'emacsvox-aural-voice-palettes--row
                    '(acss-default reading)))
      (tabulated-list-print t)
      (emacsvox-aural-ui-goto-row 'acss-default)
      (emacsvox-aural-ui-goto-tabulated-column 2)
      (let (spoken)
        (cl-letf (((symbol-function 'tts-speak)
                   (lambda (text) (push text spoken)))
                  ((symbol-function 'emacsvox-icon) #'ignore))
          (call-interactively (key-binding (kbd "<down>")))
          (should (eq (tabulated-list-get-id) 'reading))
          (should (= (emacsvox-aural-ui-tabulated-column-index) 2))
          (call-interactively (key-binding (kbd "<up>")))
          (should (eq (tabulated-list-get-id) 'acss-default))
          (should (= (emacsvox-aural-ui-tabulated-column-index) 2)))
        (should (equal (nreverse spoken)
                       '("personal, Kind" "default, Kind")))))))

(defmacro emacsvox-test--with-palette-rename (&rest body)
  "Run BODY with personal tuned voices and isolated writable stores."
  (declare (indent 0) (debug t))
  `(emacsvox-test--with-voice-palettes
     (let* ((directory (make-temp-file "palette-rename-" t))
            (emacsvox-aural-schemes-file (expand-file-name "aural.el" directory))
            (emacsvox-aural-routing-profiles-file (expand-file-name "routing.el" directory))
            (emacsvox-aural-voice-drafts--registry (make-hash-table :test #'equal))
            (emacsvox-aural-voice-editor--contexts (make-hash-table :test #'equal))
            (emacsvox-aural-routing--choice-sets
             (plist-get (emacsvox-test--choice-fixture :expected-routing) :choice-sets))
            (emacsvox-aural-routing-profile-registry (make-hash-table :test #'eq))
            (emacsvox-aural-active-routing-profile nil)
            (emacsvox-aural-active-profile nil)
            (emacsvox-aural-configuration-changed-hook nil))
       (unwind-protect
           (progn
             (dolist (data (list (emacsvox-test--choice-fixture :unchanged-parent)
                                (emacsvox-test--choice-fixture :expected-palette)))
               (emacsvox-aural-register-voice-palette-data data))
             (emacsvox-aural-save-user-data)
             (emacsvox-aural-save-routing-profiles)
             (cl-letf (((symbol-function 'emacsvox-aural-voice-palettes--at-point-or-read)
                        (lambda () 'reading))
                       ((symbol-function 'read-string) (lambda (&rest _) "renamed"))
                       ((symbol-function 'emacsvox-aural-voice-palettes-refresh) #'ignore)
                       ((symbol-function 'emacsvox-aural-ui-refresh-home-if-live) #'ignore)
                       ((symbol-function 'emacsvox-aural-ui-announce-result) #'ignore))
               ,@body))
         (delete-directory directory t)))))

(ert-deftest emacsvox-aural-voice-palettes-copy-complete-effective-palette ()
  "Manager Copy preserves inherited tuning and saves independent local owners."
  (emacsvox-test--with-palette-rename
    (emacsvox-aural-register-voice-palette-data
     '(:schema-version 3 :id child :summary "Child" :parent reading :routing owned :entries nil))
    (emacsvox-aural-save-user-data)
    (let ((before (emacsvox-aural-voice-runtime--resolve 'bolden 'child))
          (selected (emacsvox-aural-effective-voice-palette)))
      (with-temp-buffer
        (emacsvox-aural-voice-palettes-mode)
        (cl-letf (((symbol-function 'emacsvox-aural-voice-palettes--at-point-or-read)
                   (lambda () 'child))
                  ((symbol-function 'emacsvox-aural-voice-palettes-speak-current) #'ignore))
          (should (eq (call-interactively (key-binding (kbd "c"))) 'renamed))))
      (let* ((data (emacsvox-aural-voice-palette-data-form (emacsvox-aural-voice-palette 'renamed)))
             (after (emacsvox-aural-voice-runtime--resolve 'bolden 'renamed))
             (ref (plist-get (cdr (assq 'bolden (plist-get data :entries))) :local-choices))
             (set (cl-find ref (plist-get (emacsvox-aural-read-routing-profiles) :choice-sets)
                           :test #'equal :key (lambda (set) (plist-get set :id)))))
        (should (eq (plist-get data :parent) 'acss-default))
        (should (= (length (plist-get data :entries))
                   (length (emacsvox-aural-effective-voice-entries 'child))))
        (dolist (key '(:definition :choices :selectors :language))
          (should (equal (plist-get before key) (plist-get after key))))
        (should (eq (plist-get set :palette) 'renamed))
        (should-not (equal ref (plist-get (cdr (assq 'bolden
                         (plist-get (emacsvox-aural-voice-drafts--palette-data 'reading) :entries))) :local-choices)))
        (should (equal data (cl-find 'renamed (plist-get (emacsvox-aural-read-user-data) :voice-palettes)
                                    :key (lambda (item) (plist-get item :id)))))
        (should (eq selected (emacsvox-aural-effective-voice-palette)))
        ;; Changing the source parent cannot change the independent copy.
        (puthash 'reading (emacsvox-aural-compile-voice-palette-data
                          '(:schema-version 3 :id reading :summary "Changed" :parent acss-default :routing owned :entries nil))
                 emacsvox-aural-voice-palette-registry)
        (should (equal (plist-get after :choices)
                       (plist-get (emacsvox-aural-voice-runtime--resolve 'bolden 'renamed) :choices)))))))

(ert-deftest emacsvox-aural-voice-palettes-copy-failure-preserves-source-and-retries ()
  (dolist (writer '(emacsvox-aural-routing--write-user-data emacsvox-aural--write-user-data))
    (emacsvox-test--with-palette-rename
      (let ((before (emacsvox-aural-voice-drafts--palette-data 'reading)))
        (cl-letf (((symbol-function writer) (lambda (&rest _) (error "Write failed"))))
          (should-error (emacsvox-aural-voice-palettes--copy 'reading)))
        (should-not (emacsvox-aural-voice-palette 'renamed))
        (should (equal before (emacsvox-aural-voice-drafts--palette-data 'reading)))
        (should (eq (emacsvox-aural-voice-palettes--copy 'reading) 'renamed))))))

(ert-deftest emacsvox-aural-voice-palettes-parent-candidates-are-rooted-and-acyclic ()
  (emacsvox-test--with-voice-palettes
    (dolist (pair '((a . acss-default) (b . a) (c . b) (other . acss-default)
                    (missing . absent) (loop-one . loop-two) (loop-two . loop-one)))
      (emacsvox-aural-register-voice-palette-data
       (list :schema-version 3 :id (car pair) :summary "Test" :parent (cdr pair) :routing 'owned :entries nil)))
    (should-error (emacsvox-aural-register-voice-palette-data
                   '(:schema-version 3 :id orphan :summary "Orphan" :parent nil :routing owned :entries nil)))
    (let ((candidates (emacsvox-aural-voice-palettes--parent-candidates 'a)))
      (dolist (valid '("acss-default" "other")) (should (member valid candidates)))
      (dolist (invalid '("none" "a" "b" "c" "orphan" "missing" "loop-one" "loop-two"))
        (should-not (member invalid candidates))))))

(ert-deftest emacsvox-aural-voice-palettes-parent-change-reports-descendants-and-saves ()
  (emacsvox-test--with-palette-rename
    (emacsvox-aural-register-voice-palette-data
     '(:schema-version 3 :id child :summary "Child" :parent reading :routing owned :entries nil))
    (emacsvox-aural-save-user-data)
    (let ((data (plist-put (emacsvox-aural-voice-drafts--palette-data 'reading) :parent 'acss-default)))
      (let ((impact (emacsvox-aural-voice-palettes--parent-impact 'reading data)))
        (should (cl-find 'reading impact :key (lambda (item) (plist-get item :palette))))
        (should (cl-find 'child impact :key (lambda (item) (plist-get item :palette))))
        ;; Direct entries retain their owner and settings.
        (should-not (cl-find 'bolden impact :key (lambda (item) (plist-get item :voice)))))
      (cl-letf (((symbol-function 'emacsvox-aural-voice-palettes--read-parent) (lambda (&rest _) 'acss-default))
                ((symbol-function 'emacsvox-aural-voice-palettes-speak-current) #'ignore)
                ((symbol-function 'yes-or-no-p)
                 (lambda (prompt) (should (string-match-p "in child" prompt)) t)))
        (emacsvox-aural-voice-palettes-edit-metadata))
      (should (eq (plist-get (emacsvox-aural-voice-drafts--palette-data 'reading) :parent) 'acss-default))
      (should (eq (plist-get (cl-find 'reading (plist-get (emacsvox-aural-read-user-data) :voice-palettes)
                                     :key (lambda (item) (plist-get item :id))) :parent) 'acss-default)))))

(ert-deftest emacsvox-aural-voice-palettes-parent-change-rejects-known-dangling-use ()
  (emacsvox-test--with-palette-rename
    (emacsvox-aural-voice-palettes--copy-owned-voice 'reading 'bolden 'custom-voice)
    (emacsvox-aural-register-voice-palette-data
     '(:schema-version 3 :id child :summary "Child" :parent reading :routing owned :entries nil))
    (let ((emacsvox-aural-user-rules '((:id use :render (:content (:voice (bolden custom-voice)))))))
      (should-error (emacsvox-aural-voice-palettes--parent-impact
                     'child (plist-put (emacsvox-aural-voice-drafts--palette-data 'child) :parent 'acss-default))
                    :type 'user-error))))

(ert-deftest emacsvox-aural-voice-palettes-references-distinguish-terminal-personalities ()
  (let* ((data '(:entries ((custom :personality implementation :choices nil))
                :render (:content (:voice (implementation (:preset implementation :echo 3))))))
         (renamed (emacsvox-aural-voice-palettes--rename-references data 'implementation 'new)))
    (should (eq (plist-get (cdr (assq 'custom (plist-get renamed :entries))) :personality) 'implementation))
    (should (equal (plist-get (plist-get (plist-get renamed :render) :content) :voice)
                   '(new (:preset new :echo 3))))
    (should-not (emacsvox-aural-voice-palettes--voice-reference-p
                 '(:entries ((custom :personality implementation :choices nil))) 'implementation))))

(ert-deftest emacsvox-aural-voice-palettes-rename-preserves-owned-tuning-and-references ()
  "Rename preserves complete choices, inheritance, profiles and selection on disk."
  (emacsvox-test--with-palette-rename
    (emacsvox-aural-register-voice-palette-data
     '(:schema-version 3 :id child :summary "Child" :parent reading :routing owned :entries nil))
    (emacsvox-aural-register-profile '(:id everyday :summary "Everyday" :voice-palette reading))
    (setq emacsvox-aural-active-profile 'everyday
          emacsvox-aural-voice-palette-override 'reading)
    (let* ((original (emacsvox-aural-voice-palette-data-form (emacsvox-aural-voice-palette 'reading)))
           (old-sets (copy-tree emacsvox-aural-routing--choice-sets))
           (before (emacsvox-aural-voice-runtime--resolve 'bolden 'reading)))
      (should (eq (emacsvox-aural-voice-palettes-rename) 'renamed))
      (should-not (gethash 'reading emacsvox-aural-voice-palette-registry))
      (should (eq emacsvox-aural-voice-palette-override 'renamed))
      (should (eq (emacsvox-aural-voice-palette-parent (emacsvox-aural-voice-palette 'child)) 'renamed))
      (let ((after (emacsvox-aural-voice-runtime--resolve 'bolden 'renamed)))
        (dolist (key '(:definition :choices :selectors :language))
          (should (equal (plist-get before key) (plist-get after key)))))
      (dolist (set old-sets)
        (should (member set emacsvox-aural-routing--choice-sets)))
      (let* ((saved (emacsvox-aural-read-user-data))
             (renamed (cl-find 'renamed (plist-get saved :voice-palettes)
                               :key (lambda (data) (plist-get data :id))))
             (sets (plist-get (emacsvox-aural-read-routing-profiles) :choice-sets)))
        (should-not (cl-find 'reading (plist-get saved :voice-palettes)
                             :key (lambda (data) (plist-get data :id))))
        (should (eq (plist-get (car (plist-get saved :profiles)) :voice-palette) 'renamed))
        (should (eq (plist-get renamed :parent) (plist-get original :parent)))
        (dolist (entry (plist-get renamed :entries))
          (when-let* ((id (plist-get (cdr entry) :local-choices)))
            (should (eq (plist-get (cl-find id sets :test #'equal
                                           :key (lambda (set) (plist-get set :id))) :palette)
                        'renamed))))))))

(ert-deftest emacsvox-aural-voice-palettes-rename-failure-leaves-original-usable ()
  "A failed palette write leaves live state and old local snapshots usable."
  (emacsvox-test--with-palette-rename
    (let ((before (emacsvox-aural-read-user-data))
          (registry emacsvox-aural-voice-palette-registry)
          (sets (copy-tree emacsvox-aural-routing--choice-sets)))
      (cl-letf (((symbol-function 'emacsvox-aural--write-user-data)
                 (lambda (&rest _) (error "Simulated palette write failure"))))
        (should-error (emacsvox-aural-voice-palettes-rename)))
      (should (eq registry emacsvox-aural-voice-palette-registry))
      (should (equal sets emacsvox-aural-routing--choice-sets))
      (should (equal before (emacsvox-aural-read-user-data)))
      (emacsvox-aural-voice-runtime--validate 'reading)
      (should (eq (emacsvox-aural-voice-palettes-rename) 'renamed)))))

(ert-deftest emacsvox-aural-voice-palettes-rename-legacy-preserves-schema ()
  "Renaming older palettes neither converts them nor changes their definitions."
  (dolist (data (list emacsvox-test--voice-palette-data
                     (emacsvox-test--choice-fixture :source-palette)))
    (emacsvox-test--with-palette-rename
      (puthash 'reading (emacsvox-aural-compile-voice-palette-data data)
               emacsvox-aural-voice-palette-registry)
      (emacsvox-aural-save-user-data)
      (emacsvox-aural-voice-palettes-rename)
      (let ((renamed (emacsvox-aural-voice-palette-data-form
                      (emacsvox-aural-voice-palette 'renamed))))
        (should (eq (plist-get renamed :schema-version) (plist-get data :schema-version)))
        (should (eq (plist-get renamed :parent) (plist-get data :parent)))
        (cl-loop for before in (plist-get data :entries)
                 for after in (plist-get renamed :entries)
                 do (dolist (key '(:style :personality :choices :language))
                      (should (equal (plist-get (cdr before) key)
                                     (plist-get (cdr after) key)))))))))

(ert-deftest emacsvox-aural-voice-palettes-rename-preserves-concurrent-file-change ()
  "A change between the two writes prevents replacing the changed palette file."
  (emacsvox-test--with-palette-rename
    (let ((write-routing (symbol-function 'emacsvox-aural-routing--write-user-data))
          (registry emacsvox-aural-voice-palette-registry)
          changed)
      (cl-letf (((symbol-function 'emacsvox-aural-routing--write-user-data)
                 (lambda (&rest arguments)
                   (apply write-routing arguments)
                   (with-temp-buffer
                     (insert-file-contents emacsvox-aural-schemes-file)
                     (goto-char (point-max))
                     (insert "\n;; Concurrent editor change\n")
                     (write-region (point-min) (point-max) emacsvox-aural-schemes-file nil 'silent))
                   (setq changed (emacsvox-aural-voice-drafts--file-id emacsvox-aural-schemes-file)))))
        (should-error (emacsvox-aural-voice-palettes-rename)))
      (should (eq registry emacsvox-aural-voice-palette-registry))
      (should (equal changed (emacsvox-aural-voice-drafts--file-id emacsvox-aural-schemes-file))))))

(ert-deftest emacsvox-aural-voice-palettes-rename-rejects-builtins-and-missing-local-data ()
  "Read-only or incomplete palettes fail without any persisted change."
  (emacsvox-test--with-palette-rename
    (let ((before (emacsvox-aural-read-user-data)))
      (cl-letf (((symbol-function 'emacsvox-aural-voice-palettes--at-point-or-read)
                 (lambda () 'acss-default)))
        (should-error (emacsvox-aural-voice-palettes-rename) :type 'user-error))
      (let ((emacsvox-aural-routing--choice-sets nil))
        (cl-letf (((symbol-function 'emacsvox-aural-read-routing-profiles) #'ignore))
          (should-error (emacsvox-aural-voice-palettes-rename) :type 'user-error)))
      (should (equal before (emacsvox-aural-read-user-data))))))

(ert-deftest emacsvox-aural-voice-palettes-rename-rejects-conflicts-and-preserves-drafts ()
  "Duplicate names and dirty drafts cannot overwrite saved voices or edits."
  (emacsvox-test--with-palette-rename
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "reading-parent")))
      (should-error (emacsvox-aural-voice-palettes-rename) :type 'user-error))
    (let* ((draft (emacsvox-aural-voice-drafts--open '(base reading bolden)
                   '(:definition (:average-pitch 4)) '(reading)))
           (context (list :draft draft :palette 'reading :owner 'reading :destination 'reading)))
      (puthash '(base reading bolden) context emacsvox-aural-voice-editor--contexts)
      (emacsvox-aural-voice-drafts--edit draft '(:definition (:average-pitch 7)))
      (should-error (emacsvox-aural-voice-palettes-rename) :type 'user-error)
      (should (equal (emacsvox-aural-voice-draft-working draft) '(:definition (:average-pitch 7))))
      (emacsvox-aural-voice-drafts--discard draft)
      (should (eq (emacsvox-aural-voice-palettes-rename) 'renamed))
      (should (eq (gethash '(base renamed bolden) emacsvox-aural-voice-drafts--registry) draft))
      (should-not (gethash '(base reading bolden) emacsvox-aural-voice-editor--contexts))
      (should (eq (plist-get context :palette) 'renamed))
      (should (equal (emacsvox-aural-voice-draft-watches draft)
                     (emacsvox-aural-voice-drafts--watch '(renamed)))))))

(ert-deftest emacsvox-aural-voice-preview-uses-workbench-preview-bindings ()
  "The palette browser shares tune, text, and stop keys with Workbench."
  (dolist
      (binding
       '(("t" . emacsvox-aural-voice-palette-previews-tune)
         ("T" . emacsvox-aural-voice-palette-previews-set-text)
         ("S" . emacsvox-aural-voice-palette-previews-stop)
         ("e" . emacsvox-aural-voice-palette-previews-tune)
         ("s" . emacsvox-aural-voice-palette-previews-stop)
         ("c" . emacsvox-aural-voice-palette-previews-copy)
         ("r" . emacsvox-aural-voice-palette-previews-rename)
         ("d" . emacsvox-aural-voice-palette-previews-delete)
         ("N" . emacsvox-aural-voice-palette-previews-new)))
    (should
     (eq
      (lookup-key emacsvox-aural-voice-palette-previews-mode-map
                  (kbd (car binding)))
      (cdr binding))))
  (with-temp-buffer
    (emacsvox-aural-voice-palette-previews-mode)
    (should
     (eq (key-binding (kbd "n")) #'emacsvox-aural-ui-next-row))))

(ert-deftest emacsvox-aural-voice-palettes-install-data-is-atomic ()
  "Palette replacement saves a complete temporary registry before publishing."
  (emacsvox-test--with-voice-palettes
    (let (saved)
      (cl-letf
          (((symbol-function 'emacsvox-aural-save-user-data)
            (lambda (&optional _)
              (setq
               saved
               (emacsvox-aural-voice-palette 'reading))
              "saved"))
           ((symbol-function 'emacsvox-aural-ui-refresh-home-if-live)
            #'ignore))
        (emacsvox-aural-voice-palettes--install-data
         emacsvox-test--voice-palette-data)
        (should saved)
        (should (emacsvox-aural-voice-palette 'reading))
        (let ((before emacsvox-aural-voice-palette-registry))
          (should-error
           (emacsvox-aural-voice-palettes--install-data
            (plist-put
             (copy-tree emacsvox-test--voice-palette-data)
             :parent 'missing)
            'reading)
           :type 'emacsvox-aural-resource-error)
          (should (eq emacsvox-aural-voice-palette-registry before))
          (should
           (eq
            (emacsvox-aural-voice-palette-parent
             (emacsvox-aural-voice-palette 'reading))
            'acss-default))
          (let (staged-registry staged-summary)
            (cl-letf
                (((symbol-function 'emacsvox-aural-save-user-data)
                  (lambda (&optional _)
                    (setq
                     staged-registry
                     emacsvox-aural-voice-palette-registry
                     staged-summary
                     (emacsvox-aural-voice-palette-summary
                      (emacsvox-aural-voice-palette 'reading)))
                    (error "Simulated persistence failure"))))
              (should-error
               (emacsvox-aural-voice-palettes--install-data
                (plist-put
                 (copy-tree emacsvox-test--voice-palette-data)
                 :summary "Unsaved replacement")
                'reading)))
            (should-not (eq staged-registry before))
            (should (equal staged-summary "Unsaved replacement"))
            (should (eq emacsvox-aural-voice-palette-registry before))
            (should
             (equal
              (emacsvox-aural-voice-palette-summary
               (emacsvox-aural-voice-palette 'reading))
              "Reading voices"))))))))

(ert-deftest emacsvox-aural-voice-palettes-delete-is-transactional ()
  "Failed deletion persistence leaves the palette and override live."
  (emacsvox-test--with-voice-palettes
    (emacsvox-aural-register-voice-palette-data
     emacsvox-test--voice-palette-data)
    (setq emacsvox-aural-voice-palette-override 'reading)
    (let ((before emacsvox-aural-voice-palette-registry)
          staged-registry
          staged-entry)
      (cl-letf
          (((symbol-function 'emacsvox-aural-voice-palettes--at-point-or-read)
            (lambda (&optional _) 'reading))
           ((symbol-function 'yes-or-no-p) (lambda (&rest _) t))
           ((symbol-function 'emacsvox-aural-save-user-data)
            (lambda (&optional _)
              (setq
               staged-registry emacsvox-aural-voice-palette-registry
               staged-entry (emacsvox-aural-voice-palette 'reading))
              (error "Simulated persistence failure"))))
        (should-error (emacsvox-aural-voice-palettes-delete)))
      (should-not (eq staged-registry before))
      (should-not staged-entry)
      (should (eq emacsvox-aural-voice-palette-registry before))
      (should (emacsvox-aural-voice-palette 'reading))
      (should (eq emacsvox-aural-voice-palette-override 'reading))
      (let ((selected 'not-called)
            saved-registry)
        (cl-letf
            (((symbol-function
               'emacsvox-aural-voice-palettes--at-point-or-read)
              (lambda (&optional _) 'reading))
             ((symbol-function 'yes-or-no-p) (lambda (&rest _) t))
             ((symbol-function 'emacsvox-aural-save-user-data)
              (lambda (&optional _)
                (setq
                 saved-registry
                 emacsvox-aural-voice-palette-registry)))
             ((symbol-function 'emacsvox-aural-select-voice-palette)
              (lambda (palette)
                (setq
                 selected palette
                 emacsvox-aural-voice-palette-override palette)))
             ((symbol-function 'emacsvox-aural-voice-palettes-refresh)
              #'ignore)
             ((symbol-function 'emacsvox-aural-ui-refresh-home-if-live)
              #'ignore))
          (should
           (eq (emacsvox-aural-voice-palettes-delete) 'reading)))
        (should (eq saved-registry emacsvox-aural-voice-palette-registry))
        (should-not (emacsvox-aural-voice-palette 'reading))
        (should-not selected)
        (should-not emacsvox-aural-voice-palette-override)))))

(ert-deftest emacsvox-aural-voice-palettes-activate-and-follow-baseline ()
  "The manager can select an override and return to the baseline."
  (emacsvox-test--with-voice-palettes
    (emacsvox-aural-register-voice-palette-data
     emacsvox-test--voice-palette-data)
    (with-temp-buffer
      (emacsvox-aural-voice-palettes-mode)
      (emacsvox-aural-voice-palettes-refresh 'reading)
      (cl-letf
          (((symbol-function 'tts-speak) #'ignore)
           ((symbol-function 'emacsvox-aural-ui-refresh-home-if-live)
            #'ignore))
        (emacsvox-aural-voice-palettes-activate)
        (should (eq emacsvox-aural-voice-palette-override 'reading))
        (emacsvox-aural-voice-palettes-follow-baseline)
        (should-not emacsvox-aural-voice-palette-override)
        (should
         (eq
          (emacsvox-aural-voice-palettes--active-id)
          'acss-default))))))

(ert-deftest emacsvox-aural-voice-palettes-preview-opens-effective-voice-browser ()
  "Palette preview lists direct and inherited voices without prompting."
  (emacsvox-test--with-voice-palettes
    (emacsvox-aural-register-voice-palette-data
     emacsvox-test--voice-palette-data)
    (unwind-protect
        (save-window-excursion
          (cl-letf
              (((symbol-function 'completing-read)
                (lambda (&rest _)
                  (ert-fail "Palette preview must not use completion")))
               ((symbol-function 'read-string)
                (lambda (&rest _)
                  (ert-fail "Palette preview must not prompt for text")))
               ((symbol-function 'tts-get-voice-command)
                (lambda (voice) (format "<%s>" voice))))
            (with-temp-buffer
              (emacsvox-aural-voice-palettes-mode)
              (emacsvox-aural-voice-palettes-refresh 'reading)
              (emacsvox-aural-voice-palettes-preview)))
          (with-current-buffer "*Aural Voice Palette Preview*"
            (should
             (derived-mode-p
              'emacsvox-aural-voice-palette-previews-mode))
            (should
             (derived-mode-p 'emacsvox-aural-tabulated-mode))
            (should (emacsvox-aural-ui-interface-buffer-p))
            (should
             (eq emacsvox-aural-voice-palette-previews-palette 'reading))
            (should (= (length tabulated-list-entries)
                       (length (emacsvox-aural-effective-voice-entries 'reading))))
            (should
             (equal
              (aref (cadr (assq 'heading tabulated-list-entries)) 1)
              "Automatic"))
            (should
             (equal
              (aref (cadr (assq 'annotate tabulated-list-entries)) 4)
              "Saved; palette-owned"))
            (should
             (eq
              (key-binding (kbd "<down>"))
              #'emacsvox-aural-ui-next-row))
            (should
             (eq
              (lookup-key
               emacsvox-aural-voice-palette-previews-mode-map
               (kbd "A"))
              #'emacsvox-aural-voice-palette-previews-play-all))
            (should
             (eq
              (lookup-key
               emacsvox-aural-voice-palette-previews-mode-map
               (kbd "e"))
              #'emacsvox-aural-voice-palette-previews-tune))
            (should
             (eq
              (lookup-key
               emacsvox-aural-voice-palette-previews-mode-map
               (kbd "E"))
              #'emacsvox-aural-voice-palette-previews-edit))))
      (when (get-buffer "*Aural Voice Palette Preview*")
        (kill-buffer "*Aural Voice Palette Preview*")))))

(ert-deftest emacsvox-aural-voice-palette-preview-edits-selected-voice ()
  "Both edit actions pass the selected voice to the complete editor."
  (emacsvox-test--with-voice-palettes
    (emacsvox-aural-register-voice-palette-data emacsvox-test--voice-palette-data)
    (with-temp-buffer
      (emacsvox-aural-voice-palette-previews-mode)
      (setq emacsvox-aural-voice-palette-previews-palette 'reading)
      (emacsvox-aural-voice-palette-previews-refresh 'heading)
      (cl-letf (((symbol-function 'emacsvox-aural-voice-editor-open)
                 (lambda (palette voice &rest _)
                   (should (eq palette 'reading)) (should (eq voice 'heading)))))
        (call-interactively (key-binding (kbd "E")))
        (call-interactively (key-binding (kbd "e")))))))

(defmacro emacsvox-test--with-voice-rename (&rest body)
  "Run BODY in a real voice list containing a saved custom voice."
  (declare (indent 0) (debug t))
  `(emacsvox-test--with-palette-rename
     (let ((emacsvox-aural-user-rules nil)
           (emacsvox-aural-session-rules nil))
       (emacsvox-aural-voice-palettes--copy-owned-voice 'reading 'bolden 'custom-voice)
       (with-temp-buffer
         (emacsvox-aural-voice-palette-previews-mode)
         (setq emacsvox-aural-voice-palette-previews-palette 'reading)
         (emacsvox-aural-voice-palette-previews-refresh 'custom-voice)
         ,@body))))

(ert-deftest emacsvox-aural-voice-palette-preview-delete-preserves-other-voices ()
  "Deletion removes the selected saved voice and its clean editor, not other tuning."
  (emacsvox-test--with-voice-rename
    (let* ((before (emacsvox-aural-voice-runtime--resolve 'bolden 'reading))
           (sets (copy-tree emacsvox-aural-routing--choice-sets))
           (draft (emacsvox-aural-voice-drafts--open '(base reading custom-voice)
                   '(:definition (:average-pitch 4)) '(reading)))
           (context (list :draft draft :palette 'reading :voice 'custom-voice :owner 'reading)))
      (puthash '(base reading custom-voice) context emacsvox-aural-voice-editor--contexts)
      (cl-letf (((symbol-function 'yes-or-no-p)
                 (lambda (prompt)
                   (should (string-match-p "custom-voice.*reading" prompt)) t)))
        (should (eq (emacsvox-aural-voice-palette-previews-delete) 'custom-voice)))
      (should-not (assq 'custom-voice emacsvox-aural-voice-palette-previews-entries))
      (should (tabulated-list-get-id))
      (should-not (gethash '(base reading custom-voice) emacsvox-aural-voice-drafts--registry))
      (should-not (gethash '(base reading custom-voice) emacsvox-aural-voice-editor--contexts))
      (should (equal sets emacsvox-aural-routing--choice-sets))
      (should (equal before (emacsvox-aural-voice-runtime--resolve 'bolden 'reading)))
      (should-not (assq 'custom-voice
                        (plist-get (cl-find 'reading (plist-get (emacsvox-aural-read-user-data) :voice-palettes)
                                             :key (lambda (data) (plist-get data :id))) :entries))))))

(ert-deftest emacsvox-aural-voice-palette-preview-delete-cancel-and-failure-keep-selection ()
  "Cancellation and persistence failure preserve the selected voice and saved data."
  (emacsvox-test--with-voice-rename
    (let ((before (emacsvox-aural-read-user-data)))
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) nil)))
        (should-error (emacsvox-aural-voice-palette-previews-delete) :type 'user-error))
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t))
                ((symbol-function 'emacsvox-aural-save-user-data)
                 (lambda (&rest _) (error "Simulated delete failure"))))
        (should-error (emacsvox-aural-voice-palette-previews-delete)))
      (should (eq (tabulated-list-get-id) 'custom-voice))
      (should (assq 'custom-voice (emacsvox-aural-effective-voice-entries 'reading)))
      (should (equal before (emacsvox-aural-read-user-data))))))

(ert-deftest emacsvox-aural-voice-palette-preview-delete-protects-references-and-restores-defaults ()
  "Custom mappings cannot dangle, while a standard override can be removed."
  (emacsvox-test--with-voice-rename
    (let ((emacsvox-aural-user-rules '((:id custom-use :render (:content (:voice custom-voice))))))
      (should-error (emacsvox-aural-voice-palette-previews-delete) :type 'user-error))
    (should-error (emacsvox-aural-voice-palettes--delete-voice 'reading 'annotate) :type 'user-error)
    (should-error (emacsvox-aural-voice-palettes--delete-voice 'acss-default 'bolden) :type 'user-error)
    ;; Reset uses actual ancestry, never a hidden standard fallback.
    (puthash 'reading-parent
             (emacsvox-aural-compile-voice-palette-data
              '(:schema-version 3 :id reading-parent :summary "Rooted parent"
                :parent acss-default :routing owned :entries nil))
             emacsvox-aural-voice-palette-registry)
    (cl-letf (((symbol-function 'yes-or-no-p)
               (lambda (prompt) (should (string-match-p "restore" prompt)) t)))
      (emacsvox-aural-voice-palettes--delete-voice 'reading 'bolden t))
    (should-not (assq 'bolden (plist-get (emacsvox-aural-voice-palette-data-form
                                        (emacsvox-aural-voice-palette 'reading)) :entries)))))

(ert-deftest emacsvox-aural-voice-palette-preview-delete-last-custom-voice-retains-inherited-list ()
  "Deleting the last custom voice leaves the inherited standard voices available."
  (emacsvox-test--with-palette-rename
    (emacsvox-aural-register-voice-palette-data
     '(:schema-version 3 :id solo :summary "Solo" :parent acss-default :routing owned
       :entries ((only-voice :personality voice-smoothen :choices nil))))
    (emacsvox-aural-save-user-data)
    (with-temp-buffer
      (emacsvox-aural-voice-palette-previews-mode)
      (setq emacsvox-aural-voice-palette-previews-palette 'solo)
      (emacsvox-aural-voice-palette-previews-refresh 'only-voice)
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
        (emacsvox-aural-voice-palette-previews-delete))
      (should tabulated-list-entries)
      (should-not (assq 'only-voice tabulated-list-entries))
      (should (tabulated-list-get-id)))
    (let (buffer spoken)
      (unwind-protect
          (save-window-excursion
            (cl-letf (((symbol-function 'tts-speak) (lambda (text) (push text spoken))))
              (setq buffer (emacsvox-aural-list-voice-palette-previews 'solo)))
            (should (= (length spoken) 1))
            (should (string-match-p "solo" (car spoken))))
        (when (buffer-live-p buffer) (kill-buffer buffer))))))

(ert-deftest emacsvox-aural-voice-palettes-opening-announces-location-once ()
  "Programmatic entry from Home announces the manager and palette without interruption."
  (emacsvox-test--with-voice-palettes
    (emacsvox-aural-register-voice-palette-data emacsvox-test--voice-palette-data)
    (let (manager preview spoken)
      (unwind-protect
          (save-window-excursion
            (cl-letf (((symbol-function 'tts-speak) (lambda (text) (push text spoken))))
              (setq manager (emacsvox-aural-list-voice-palettes 'reading))
              (should (= (length spoken) 1))
              (should (string-match-p "Voice palettes.*Selected reading" (car spoken)))
              (setq spoken nil)
              (setq preview (emacsvox-aural-list-voice-palette-previews 'reading 'heading t))
              (should (= (length spoken) 1))
              (dolist (text '("Voice palette reading" "voices" "heading" "Physical choice" "d deletes"))
                (should (string-match-p text (car spoken))))))
        (when (buffer-live-p preview) (kill-buffer preview))
        (when (buffer-live-p manager) (kill-buffer manager))))))

(ert-deftest emacsvox-aural-voice-palette-preview-rename-preserves-complete-voice ()
  "Rename removes the old row and preserves sound data under the selected new name."
  (emacsvox-test--with-voice-rename
    (let* ((before (emacsvox-aural-voice-runtime--resolve 'custom-voice 'reading))
           (sets (copy-tree emacsvox-aural-routing--choice-sets))
           (draft (emacsvox-aural-voice-drafts--open '(base reading custom-voice)
                   '(:definition (:average-pitch 4)) '(reading)))
           (context (list :draft draft :palette 'reading :voice 'custom-voice :owner 'reading)))
      (puthash '(base reading custom-voice) context emacsvox-aural-voice-editor--contexts)
      (should (eq (emacsvox-aural-voice-palette-previews-rename) 'renamed))
      (should (eq (tabulated-list-get-id) 'renamed))
      (should-not (assq 'custom-voice (emacsvox-aural-effective-voice-entries 'reading)))
      (let ((after (emacsvox-aural-voice-runtime--resolve 'renamed 'reading)))
        (dolist (field '(:definition :choices :selectors :language))
          (should (equal (plist-get before field) (plist-get after field)))))
      (dolist (set sets) (should (member set emacsvox-aural-routing--choice-sets)))
      (should (eq (gethash '(base reading renamed) emacsvox-aural-voice-drafts--registry) draft))
      (should (eq (plist-get context :voice) 'renamed))
      (let ((entries (plist-get (cl-find 'reading (plist-get (emacsvox-aural-read-user-data) :voice-palettes)
                                        :key (lambda (data) (plist-get data :id))) :entries)))
        (should (assq 'renamed entries))
        (should-not (assq 'custom-voice entries))))))

(ert-deftest emacsvox-aural-voice-palette-preview-rename-updates-mappings ()
  "Personal mappings survive restart; live maps and nested requests follow the rename."
  (dolist (request '(custom-voice (:preset custom-voice :echo 3)
                    (voice-smoothen custom-voice)))
    (emacsvox-test--with-voice-rename
      (let* ((rules `((:id custom-voice :match (:legacy-face bold)
                      :render (:content (:voice ,request)))))
             (emacsvox-aural-user-rules (copy-tree rules))
             (emacsvox-aural-session-rules (copy-tree rules))
             (voice-setup-face-voice-table (make-hash-table :test #'eq))
             (source (generate-new-buffer " *rename mapping*"))
             (before (emacsvox-aural-voice-runtime--resolve 'custom-voice 'reading)))
        (unwind-protect
            (progn
              (puthash 'bold '(custom-voice voice-smoothen) voice-setup-face-voice-table)
              (with-current-buffer source
                (setq-local emacsvox-aural-buffer-rules (copy-tree rules))
                (setq-local voice-setup-local-map (make-hash-table :test #'eq))
                (puthash 'italic 'custom-voice voice-setup-local-map))
              (emacsvox-aural-save-user-data)
              (emacsvox-aural-voice-palette-previews-rename)
              (let ((expected `((:id custom-voice :match (:legacy-face bold)
                                 :render (:content (:voice ,(cl-subst 'renamed 'custom-voice request)))))))
                (should (equal emacsvox-aural-user-rules expected))
                (should (equal emacsvox-aural-session-rules expected))
                (should (equal (plist-get (emacsvox-aural-read-user-data) :user-rules) expected))
                (with-current-buffer source
                  (should (equal emacsvox-aural-buffer-rules expected))
                  (should (eq (gethash 'italic voice-setup-local-map) 'renamed))))
              (should (equal (gethash 'bold voice-setup-face-voice-table) '(renamed voice-smoothen)))
              (let ((after (emacsvox-aural-voice-runtime--resolve 'renamed 'reading)))
                (dolist (field '(:definition :choices :selectors :language))
                  (should (equal (plist-get before field) (plist-get after field))))))
          (kill-buffer source))))))

(ert-deftest emacsvox-aural-voice-palette-preview-rename-protects-external-uses-and-standards ()
  "Separately maintained references, standard names and inherited voices stay protected."
  (emacsvox-test--with-voice-rename
    (let ((before (emacsvox-aural-read-user-data)))
      (dolist (voice '(bolden annotate))
        (should-error (emacsvox-aural-voice-palettes--check-voice-rename 'reading voice) :type 'user-error))
      (emacsvox-aural-register-voice-palette-data
       '(:routing owned :schema-version 3 :id other :summary "Other" :parent acss-default :entries ((custom-voice :personality voice-smoothen :choices nil))))
      (should-error (emacsvox-aural-voice-palette-previews-rename) :type 'user-error)
      (should (equal before (emacsvox-aural-read-user-data))))))

(ert-deftest emacsvox-aural-voice-palette-preview-rename-failure-keeps-old-name ()
  "Either store failing leaves the old name usable and permits retrying r."
  (dolist (writer '(emacsvox-aural-routing--write-user-data emacsvox-aural--write-user-data))
    (emacsvox-test--with-voice-rename
      (let* ((emacsvox-aural-user-rules '((:id mapped :render (:content (:voice custom-voice)))))
             (emacsvox-aural-session-rules (copy-tree emacsvox-aural-user-rules))
             (voice-setup-face-voice-table (make-hash-table :test #'eq))
             (_ (emacsvox-aural-save-user-data))
             (before (emacsvox-aural-read-user-data)))
        (puthash 'bold 'custom-voice voice-setup-face-voice-table)
        (cl-letf (((symbol-function writer) (lambda (&rest _) (error "Simulated rename failure"))))
          (should-error (emacsvox-aural-voice-palette-previews-rename) :type 'user-error))
        (should (equal before (emacsvox-aural-read-user-data)))
        (should (eq (gethash 'bold voice-setup-face-voice-table) 'custom-voice))
        (should (equal emacsvox-aural-user-rules (plist-get before :user-rules)))
        (should (equal emacsvox-aural-session-rules emacsvox-aural-user-rules))
        (should (eq (tabulated-list-get-id) 'custom-voice))
        (should (assq 'custom-voice (emacsvox-aural-effective-voice-entries 'reading)))
        (should (eq (emacsvox-aural-voice-palette-previews-rename) 'renamed))))))

(ert-deftest emacsvox-aural-voice-palette-preview-rename-custom-keeps-definition ()
  "Renaming a custom voice keeps its raw definition and complete palette schema."
  (emacsvox-test--with-palette-rename
    (puthash 'reading (emacsvox-aural-compile-voice-palette-data emacsvox-test--voice-palette-data)
             emacsvox-aural-voice-palette-registry)
    (emacsvox-aural-save-user-data)
    (with-temp-buffer
      (emacsvox-aural-voice-palette-previews-mode)
      (setq emacsvox-aural-voice-palette-previews-palette 'reading)
      (emacsvox-aural-voice-palette-previews-refresh 'aside)
      (let ((before (emacsvox-aural-voice 'aside 'reading))
            (emacsvox-aural-user-rules '((:id mapped :render (:content (:voice aside))))))
        (emacsvox-aural-save-user-data)
        (emacsvox-aural-voice-palette-previews-rename)
        (should (equal before (emacsvox-aural-voice 'renamed 'reading)))
        (should (equal (plist-get (emacsvox-aural-read-user-data) :user-rules)
                       '((:id mapped :render (:content (:voice renamed))))))
        (should (eq 3 (plist-get (emacsvox-aural-voice-palette-data-form
                                  (emacsvox-aural-voice-palette 'reading)) :schema-version)))))))

(ert-deftest emacsvox-aural-voice-palette-preview-copies-owned-voice-completely ()
  "The c command saves and selects a copy with independent local choices."
  (emacsvox-test--with-palette-rename
    (let* ((before (emacsvox-aural-voice-palette-data-form (emacsvox-aural-voice-palette 'reading)))
           (source (emacsvox-aural-voice-runtime--resolve 'bolden 'reading)))
      (with-temp-buffer
        (emacsvox-aural-voice-palette-previews-mode)
        (setq emacsvox-aural-voice-palette-previews-palette 'reading)
        (emacsvox-aural-voice-palette-previews-refresh 'bolden)
        (cl-letf (((symbol-function 'emacsvox-aural-voice-palettes--read-new-entry-name)
                   (lambda (palette initial)
                     (should (eq palette 'reading))
                     (should (equal initial "bolden-copy"))
                     'bolden-copy)))
          (should (eq (emacsvox-aural-voice-palette-previews-copy) 'bolden-copy)))
        (should (eq (tabulated-list-get-id) 'bolden-copy)))
      (let* ((after (emacsvox-aural-voice-palette-data-form (emacsvox-aural-voice-palette 'reading)))
             (copy (emacsvox-aural-voice-runtime--resolve 'bolden-copy 'reading))
             (reference (plist-get (cdr (assq 'bolden-copy (plist-get after :entries))) :local-choices))
             (sets (plist-get (emacsvox-aural-read-routing-profiles) :choice-sets)))
        (dolist (key '(:definition :choices :selectors :language))
          (should (equal (plist-get source key) (plist-get copy key))))
        (should (equal (plist-get before :entries)
                       (cl-remove 'bolden-copy (plist-get after :entries) :key #'car)))
        (should-not (equal reference (plist-get (cdr (assq 'bolden (plist-get before :entries))) :local-choices)))
        (should (eq (plist-get (cl-find reference sets :test #'equal :key (lambda (set) (plist-get set :id))) :voice)
                    'bolden-copy))
        (should (assq 'bolden-copy
                      (plist-get (cl-find 'reading (plist-get (emacsvox-aural-read-user-data) :voice-palettes)
                                           :key (lambda (data) (plist-get data :id))) :entries)))))))

(ert-deftest emacsvox-aural-voice-palette-preview-copies-inherited-and-untuned-owned-voices ()
  "Inherited Automatic voices and untuned local chains retain their settings."
  (emacsvox-test--with-palette-rename
    (emacsvox-aural-voice-palettes--copy-owned-voice 'reading 'annotate 'annotation-copy)
    (should (equal (plist-get (emacsvox-aural-voice-runtime--resolve 'annotate 'reading) :definition)
                   (plist-get (emacsvox-aural-voice-runtime--resolve 'annotation-copy 'reading) :definition)))
    (should-not (plist-get (emacsvox-aural-voice-runtime--resolve 'annotation-copy 'reading) :choices)))
  (emacsvox-test--with-palette-rename
    (puthash 'reading (emacsvox-aural-compile-voice-palette-data
                      (emacsvox-test--choice-fixture :source-palette)) emacsvox-aural-voice-palette-registry)
    (emacsvox-aural-save-user-data)
    (emacsvox-aural-voice-palettes--copy-owned-voice 'reading 'bolden 'bolden-copy)
    (should (eq 3 (plist-get (emacsvox-aural-voice-palette-data-form
                              (emacsvox-aural-voice-palette 'reading)) :schema-version)))
    (should (equal (plist-get (emacsvox-aural-voice-runtime--resolve 'bolden 'reading) :selectors)
                   (plist-get (emacsvox-aural-voice-runtime--resolve 'bolden-copy 'reading) :selectors)))))

(ert-deftest emacsvox-aural-voice-palette-preview-copy-owned-failure-is-retryable ()
  "Either store failing leaves the source intact and permits retrying c."
  (dolist (writer '(emacsvox-aural-routing--write-user-data emacsvox-aural--write-user-data))
    (emacsvox-test--with-palette-rename
      (let ((before (emacsvox-aural-read-user-data))
            (registry emacsvox-aural-voice-palette-registry))
        (cl-letf (((symbol-function writer) (lambda (&rest _) (error "Simulated write failure"))))
          (should-error (emacsvox-aural-voice-palettes--copy-owned-voice 'reading 'bolden 'bolden-copy)
                        :type 'user-error))
        (should (eq registry emacsvox-aural-voice-palette-registry))
        (should (equal before (emacsvox-aural-read-user-data)))
        (should-not (assq 'bolden-copy (emacsvox-aural-effective-voice-entries 'reading)))
        (should (eq (emacsvox-aural-voice-palettes--copy-owned-voice 'reading 'bolden 'bolden-copy)
                    'bolden-copy))))))

(ert-deftest emacsvox-aural-voice-palette-preview-new-opens-complete-draft ()
  "New Voice sends the current palette to the common editor without writing."
  (emacsvox-test--with-voice-palettes
    (with-temp-buffer
      (emacsvox-aural-voice-palette-previews-mode)
      (setq emacsvox-aural-voice-palette-previews-palette 'acss-default
            emacsvox-aural-voice-palette-previews-text "New sample")
      (let (opened)
        (cl-letf (((symbol-function 'emacsvox-aural-voice-palettes--read-new-entry-name)
                   (lambda (palette &optional _)
                     (should (eq palette 'acss-default)) 'new-voice))
                  ((symbol-function 'emacsvox-aural-voice-editor-new)
                   (lambda (&rest args) (setq opened args)))
                  ((symbol-function 'emacsvox-aural-save-user-data)
                   (lambda (&rest _) (ert-fail "Opening New Voice must not save"))))
          (call-interactively (lookup-key (current-local-map) (kbd "N")))
          (should (equal opened
                         (list 'acss-default 'new-voice (current-buffer) "New sample")))
          (should-not emacsvox-aural-voice-palette-override))))))

(ert-deftest emacsvox-aural-rich-voice-style-validates-and-persists-effects ()
  "Portable palette styles retain relative rate and post-synthesis dimensions."
  (emacsvox-test--with-voice-palettes
    (let ((data
           (copy-tree emacsvox-test--voice-palette-data)))
      (setcdr
       (assq 'aside (plist-get data :entries))
       '(:style
         (:family nil :average-pitch 4 :pitch-range 3
          :stress nil :richness 6 :rate-offset -7 :gain 5
          :low-pass 8 :high-pass nil :pan 2 :reverb 4 :echo 1 :chorus 6) :choices nil))
      (emacsvox-aural-register-voice-palette-data data)
      (let ((style (emacsvox-aural-voice 'aside 'reading)))
        (should (= (plist-get style :rate-offset) -7))
        (should (= (plist-get style :gain) 5))
        (should (= (plist-get style :reverb) 4))
        (should (= (plist-get style :echo) 1))
        (should (= (plist-get style :chorus) 6))))))

(ert-deftest emacsvox-aural-voice-palette-preview-inherits-shared-dismissal ()
  "A freshly loaded preview is registered and dismissible through shared UI."
  (with-temp-buffer
    (emacsvox-aural-voice-palette-previews-mode)
    (let (dismissed)
      (cl-letf
          (((symbol-function 'emacsvox-aural-capture-context) #'ignore)
           ((symbol-function 'quit-window)
            (lambda (&optional _kill _window) (setq dismissed t)))
           ((symbol-function 'emacsvox-icon) #'ignore)
           ((symbol-function 'emacsvox-speak-mode-line) #'ignore))
        (emacsvox-aural-quit))
      (should dismissed))))

(ert-deftest emacsvox-aural-voice-palette-preview-queues-labelled-comparison ()
  "One preview builds a concrete plan containing the labelled shared text."
  (emacsvox-test--with-voice-palettes
    (emacsvox-aural-register-voice-palette-data
     emacsvox-test--voice-palette-data)
    (let (preview-plan)
      (unwind-protect
          (save-window-excursion
            (cl-letf
                (((symbol-function 'emacsvox-aural-compile-voice-style)
                  (lambda (&rest _)
                    (emacsvox-aural--make-compiled-voice
                     :command "[[logical_voice heading]]"
                     :request 'heading
                     :style '(:average-pitch 6 :reverb 7)
                     :capability '(:adapter omnivox))))
                 ((symbol-function 'emacsvox-aural-preview-play-plan)
                  (lambda (plan) (setq preview-plan plan))))
              (emacsvox-aural-list-voice-palette-previews 'reading)
              (with-current-buffer "*Aural Voice Palette Preview*"
                (should
                 (emacsvox-aural-voice-palette-previews--goto 'heading))
                (emacsvox-aural-voice-palette-previews-play))))
        (when (get-buffer "*Aural Voice Palette Preview*")
          (kill-buffer "*Aural Voice Palette Preview*")))
      (let ((content (emacsvox-aural-concrete-plan-content preview-plan)))
        (should
         (equal
          (emacsvox-aural-concrete-content-text content)
          "Heading voice. The quick brown fox jumps over the lazy dog."))
        (should
         (equal
          (emacsvox-aural-concrete-content-voice-style content)
          '(:average-pitch 6 :reverb 7)))))))

(ert-deftest emacsvox-aural-voice-palette-preview-can-queue-all-voices ()
  "Play-all queues every voice against one comparison before dispatch."
  (emacsvox-test--with-voice-palettes
    (emacsvox-aural-register-voice-palette-data
     '(:routing owned :parent acss-default :schema-version 3 :id pair :summary "Two comparison voices" :entries ((first :personality voice-bolden :choices nil) (second :personality voice-animate :choices nil))))
    (let (preview-runs)
      (unwind-protect
          (save-window-excursion
            (cl-letf
                (((symbol-function 'emacsvox-aural-preview-message)
                  #'ignore)
                 ((symbol-function 'tts-get-voice-command)
                  (lambda (voice) (format "<%s>" voice)))
                 ((symbol-function 'emacsvox-aural-preview-play-runs)
                  (lambda (runs &optional _transaction-id)
                    (setq preview-runs runs))))
              (emacsvox-aural-list-voice-palette-previews 'pair)
              (with-current-buffer "*Aural Voice Palette Preview*"
                (should
                 (equal
                  (plist-get
                   (emacsvox-aural-voice-palette-previews-play-all)
                   :queued)
                  (length (emacsvox-aural-effective-voice-entries 'pair)))))))
        (when (get-buffer "*Aural Voice Palette Preview*")
          (kill-buffer "*Aural Voice Palette Preview*")))
      (should (= (length preview-runs) (length (emacsvox-aural-effective-voice-entries 'pair))))
      (should
       (equal
        (sort
         (mapcar
          (lambda (run)
            (emacsvox-aural-concrete-content-text
             (emacsvox-aural-concrete-plan-content (car run))))
          (cl-remove-if-not (lambda (run)
                              (member (emacsvox-aural-concrete-content-text
                                       (emacsvox-aural-concrete-plan-content (car run)))
                                      '("First voice. The quick brown fox jumps over the lazy dog."
                                        "Second voice. The quick brown fox jumps over the lazy dog."))) preview-runs))
         #'string-lessp)
        '("First voice. The quick brown fox jumps over the lazy dog."
          "Second voice. The quick brown fox jumps over the lazy dog."))))))

(provide 'emacsvox-aural-voice-palettes-tests)
;;; emacsvox-aural-voice-palettes-tests.el ends here
