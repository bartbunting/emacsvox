;;; emacsvox-aural-voice-palettes-tests.el --- Voice palette manager tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Test accessible voice-palette management, activation, and preview.

;;; Code:

(require 'ert)
(require 'emacsvox-aural-voice-palettes)
(require 'emacsvox-aural-voice-choice-tests)
(require 'emacsvox-aural-voice-editor)

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
  '(:schema-version 1
    :id reading
    :summary "Reading voices"
    :parent acss-default
    :entries
    ((heading :personality voice-bolden)
     (aside
      :style
      (:family nil :average-pitch 4 :pitch-range 3
       :stress nil :richness 6))))
  "Personal palette used by manager tests.")

(defun emacsvox-test--open-reading-voice-tuner (voice)
  "Open a tuner for VOICE in the test `reading' palette."
  (let ((source (get-buffer-create "*Test Voice Preview*")))
    (with-current-buffer source
      (emacsvox-aural-voice-palette-previews-mode)
      (setq
       emacsvox-aural-voice-palette-previews-palette 'reading
       emacsvox-aural-voice-palette-previews-entries
       (emacsvox-aural-voice-palettes--preview-entries 'reading)
       emacsvox-aural-voice-palette-previews-text
       emacsvox-aural-voice-palettes-preview-text
       tabulated-list-entries
       (list
        (list
         voice
         (vector (symbol-name voice) "" "" "" ""))))
      (tabulated-list-print t)
      (goto-char (point-min))
      (emacsvox-aural-ui-goto-tabulated-column 0)
      (cl-letf
          (((symbol-function 'emacsvox-aural-voice-tuner--play-text)
            #'ignore))
        (emacsvox-aural-voice-tuner-open
         emacsvox-aural-voice-palette-previews-palette
         (emacsvox-aural-voice-palette-previews--current-voice)
         (current-buffer) emacsvox-aural-voice-palette-previews-text)))
    (list source (get-buffer "*Aural Voice Tuner*"))))

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
            (emacsvox-aural-session-routing-bindings nil)
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

(ert-deftest emacsvox-aural-voice-tuner-uses-consistent-save-bindings ()
  "The tuner saves with Workbench-compatible acceptance keys."
  (should
   (eq
    (lookup-key emacsvox-aural-voice-tuner-mode-map (kbd "w"))
    #'emacsvox-aural-voice-tuner-save))
  (should
   (eq
    (lookup-key emacsvox-aural-voice-tuner-mode-map (kbd "C-c C-c"))
    #'emacsvox-aural-voice-tuner-save))
  (should-not
   (lookup-key emacsvox-aural-voice-tuner-mode-map (kbd "s"))))

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

(ert-deftest emacsvox-aural-voice-tuner-uses-consistent-cancel-binding ()
  "The tuner accepts the shared transaction-cancellation key."
  (should
   (eq
    (lookup-key emacsvox-aural-voice-tuner-mode-map (kbd "C-c C-k"))
    #'emacsvox-aural-voice-tuner-quit)))

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
              "Legacy shared routing"))
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
  "The preview browser edits and refreshes a selected personal voice."
  (emacsvox-test--with-voice-palettes
    (emacsvox-aural-register-voice-palette-data
     emacsvox-test--voice-palette-data)
    (unwind-protect
        (save-window-excursion
          (cl-letf
              (((symbol-function 'emacsvox-aural-save-user-data) #'ignore)
               ((symbol-function 'emacsvox-aural-ui-refresh-home-if-live)
                #'ignore)
               ((symbol-function 'emacsvox-aural-voice-palettes--read-definition)
                (lambda (current)
                  (should (eq current 'voice-bolden))
                  'voice-animate))
               ((symbol-function 'tts-get-voice-command)
                (lambda (voice) (format "<%s>" voice))))
            (emacsvox-aural-list-voice-palette-previews 'reading)
            (with-current-buffer "*Aural Voice Palette Preview*"
              (should
               (emacsvox-aural-voice-palette-previews--goto 'heading))
              (should
               (eq
                (emacsvox-aural-voice-palette-previews-edit)
                'heading))
              (should
               (eq (emacsvox-aural-voice 'heading 'reading) 'voice-animate))
              (should (eq (tabulated-list-get-id) 'heading)))))
      (when (get-buffer "*Aural Voice Palette Preview*")
        (kill-buffer "*Aural Voice Palette Preview*")))))

(ert-deftest emacsvox-aural-voice-palette-preview-creates-new-voice ()
  "The preview browser creates and selects a new personal voice."
  (emacsvox-test--with-voice-palettes
    (emacsvox-aural-register-voice-palette-data
     emacsvox-test--voice-palette-data)
    (let ((style
           '(:family paul :average-pitch 4 :pitch-range 3
             :stress 2 :richness 6)))
      (unwind-protect
          (save-window-excursion
            (cl-letf
                (((symbol-function 'emacsvox-aural-save-user-data) #'ignore)
                 ((symbol-function 'emacsvox-aural-ui-refresh-home-if-live)
                  #'ignore)
                 ((symbol-function
                   'emacsvox-aural-voice-palettes--read-new-entry-name)
                  (lambda (palette &optional _)
                    (should (eq palette 'reading))
                    'voice-dired-directory))
                 ((symbol-function
                   'emacsvox-aural-voice-palettes--read-definition)
                  (lambda (&optional current)
                    (should-not current)
                    style))
                 ((symbol-function 'tts-get-voice-command)
                  (lambda (voice) (format "<%s>" voice))))
              (emacsvox-aural-list-voice-palette-previews 'reading)
              (with-current-buffer "*Aural Voice Palette Preview*"
                (should
                 (eq
                  (emacsvox-aural-voice-palette-previews-new)
                  'voice-dired-directory))
                (should
                 (equal
                  (emacsvox-aural-voice 'voice-dired-directory 'reading)
                  style))
                (should
                 (eq (tabulated-list-get-id) 'voice-dired-directory)))))
        (when (get-buffer "*Aural Voice Palette Preview*")
          (kill-buffer "*Aural Voice Palette Preview*"))))))

(ert-deftest emacsvox-aural-voice-palette-preview-copies-independent-voice ()
  "Copying a personality-backed row creates an independent style entry."
  (emacsvox-test--with-voice-palettes
    (emacsvox-aural-register-voice-palette-data
     emacsvox-test--voice-palette-data)
    (unwind-protect
        (save-window-excursion
          (cl-letf
              (((symbol-function 'emacsvox-aural-save-user-data) #'ignore)
               ((symbol-function 'emacsvox-aural-ui-refresh-home-if-live)
                #'ignore)
               ((symbol-function
                 'emacsvox-aural-voice-palettes--read-new-entry-name)
                (lambda (palette initial)
                  (should (eq palette 'reading))
                  (should (equal initial "heading-copy"))
                  'voice-dired-directory))
               ((symbol-function 'tts-get-voice-command)
                (lambda (voice) (format "<%s>" voice))))
            (emacsvox-aural-list-voice-palette-previews 'reading)
            (with-current-buffer "*Aural Voice Palette Preview*"
              (should
               (emacsvox-aural-voice-palette-previews--goto 'heading))
              (should
               (eq
                (emacsvox-aural-voice-palette-previews-copy)
                'voice-dired-directory))
              (let ((definition
                     (emacsvox-aural-voice
                      'voice-dired-directory 'reading)))
                (should (emacsvox-aural-voice-style-p definition))
                (should-not (symbolp definition)))
              (should (eq (tabulated-list-get-id) 'voice-dired-directory)))))
      (when (get-buffer "*Aural Voice Palette Preview*")
        (kill-buffer "*Aural Voice Palette Preview*")))))

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

(ert-deftest emacsvox-aural-voice-palette-preview-copies-inherited-and-older-owned-voices ()
  "Inherited Automatic voices and schema-2 local chains retain their settings."
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
    (should (eq 2 (plist-get (emacsvox-aural-voice-palette-data-form
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

(ert-deftest emacsvox-aural-voice-palette-preview-uses-one-built-in-overlay ()
  "The first built-in edit creates one active overlay reused by later edits."
  (emacsvox-test--with-voice-palettes
    (let ((overlay-prompts 0)
          (id-prompts 0)
          (voice-count 0)
          (style
           '(:family nil :average-pitch 4 :pitch-range 3
             :stress 2 :richness 6)))
      (unwind-protect
          (save-window-excursion
            (cl-letf
                (((symbol-function 'emacsvox-aural-save-user-data) #'ignore)
                 ((symbol-function 'emacsvox-aural-ui-refresh-home-if-live)
                  #'ignore)
                 ((symbol-function 'y-or-n-p)
                  (lambda (&rest _)
                    (cl-incf overlay-prompts)
                    t))
                 ((symbol-function 'emacsvox-aural-voice-palettes--read-new-id)
                  (lambda (&optional initial)
                    (cl-incf id-prompts)
                    (should (equal initial "acss-default-personal"))
                    'personal-voices))
                 ((symbol-function
                   'emacsvox-aural-voice-palettes--read-new-entry-name)
                  (lambda (palette &optional _)
                    (should (eq palette 'personal-voices))
                    (intern (format "new-voice-%d" (cl-incf voice-count)))))
                 ((symbol-function
                   'emacsvox-aural-voice-palettes--read-definition)
                  (lambda (&optional _) style))
                 ((symbol-function 'tts-get-voice-command)
                  (lambda (voice) (format "<%s>" voice))))
              (emacsvox-aural-list-voice-palette-previews 'acss-default)
              (with-current-buffer "*Aural Voice Palette Preview*"
                (emacsvox-aural-voice-palette-previews-new)
                (emacsvox-aural-voice-palette-previews-new)
                (should
                 (eq emacsvox-aural-voice-palette-previews-palette
                     'personal-voices))
                (should (eq emacsvox-aural-voice-palette-override
                            'personal-voices))))
          (let ((palette
                 (emacsvox-aural-voice-palette 'personal-voices)))
            (should-not (emacsvox-aural-voice-palette-built-in palette))
            (should
             (eq (emacsvox-aural-voice-palette-parent palette)
                 'acss-default))
            (should
             (equal
              (mapcar #'car (emacsvox-aural-voice-palette-entries palette))
              '(new-voice-1 new-voice-2))))
          (should (= overlay-prompts 1))
          (should (= id-prompts 1)))
        (when (get-buffer "*Aural Voice Palette Preview*")
          (kill-buffer "*Aural Voice Palette Preview*"))))))

(ert-deftest emacsvox-aural-voice-tuner-reopens-its-working-draft ()
  "Reopening the same voice retains unsaved parameters without a discard prompt."
  (emacsvox-test--with-voice-palettes
    (emacsvox-aural-register-voice-palette-data emacsvox-test--voice-palette-data)
    (let (buffers)
      (unwind-protect
          (save-window-excursion
            (setq buffers (emacsvox-test--open-reading-voice-tuner 'aside))
            (with-current-buffer (cadr buffers)
              (setq emacsvox-aural-voice-tuner-working-style
                    (plist-put emacsvox-aural-voice-tuner-working-style :average-pitch 7)
                    emacsvox-aural-voice-tuner-dirty t))
            (with-current-buffer (car buffers)
              (cl-letf (((symbol-function 'yes-or-no-p)
                         (lambda (&rest _) (ert-fail "Unexpected discard prompt")))
                        ((symbol-function 'emacsvox-aural-voice-tuner--play-text) #'ignore))
                (emacsvox-aural-voice-tuner-open
         emacsvox-aural-voice-palette-previews-palette
         (emacsvox-aural-voice-palette-previews--current-voice)
         (current-buffer) emacsvox-aural-voice-palette-previews-text)))
            (with-current-buffer (cadr buffers)
              (should emacsvox-aural-voice-tuner-dirty)
              (should (= 7 (plist-get emacsvox-aural-voice-tuner-working-style
                                      :average-pitch)))))
        (dolist (buffer buffers)
          (when (buffer-live-p buffer) (kill-buffer buffer)))))))

(ert-deftest emacsvox-aural-voice-tuner-opens-complete-supported-form ()
  "The tuner exposes all dimensions and reports active adapter support."
  (emacsvox-test--with-voice-palettes
    (emacsvox-aural-register-voice-palette-data
     emacsvox-test--voice-palette-data)
    (let (buffers)
      (unwind-protect
          (save-window-excursion
            (cl-letf
                (((symbol-function 'emacsvox-aural-active-voice-capabilities)
                  (lambda ()
                    '(:adapter outloud
                      :dimensions
                      (average-pitch pitch-range stress richness)))))
              (setq buffers (emacsvox-test--open-reading-voice-tuner 'aside))
              (with-current-buffer (cadr buffers)
                (should (derived-mode-p 'emacsvox-aural-voice-tuner-mode))
                (should
                 (derived-mode-p 'emacsvox-aural-tabulated-mode))
                (should
                 (= (length tabulated-list-entries)
                    (length emacsvox-aural-rich-voice-dimensions)))
                (should-not emacsvox-aural-voice-tuner-dirty)
                (should
                 (equal
                  (plist-get
                   emacsvox-aural-voice-tuner-working-style
                   :average-pitch)
                  4))
                (should
                 (equal
                  (aref (cadr (assq 'family tabulated-list-entries)) 3)
                  "unsupported by outloud"))
                (should
                 (eq
                  (lookup-key
                   emacsvox-aural-voice-tuner-mode-map
                   (kbd "<right>"))
                  #'emacsvox-aural-voice-tuner-increase))
                (should
                 (eq
                  (lookup-key
                   emacsvox-aural-voice-tuner-mode-map
                   (kbd "7"))
                  #'emacsvox-aural-voice-tuner-set-digit))
                (should
                 (eq
                  (lookup-key
                   emacsvox-aural-voice-tuner-mode-map
                   (kbd "B"))
                  #'emacsvox-aural-voice-tuner-compare)))))
        (dolist (buffer buffers)
          (when (buffer-live-p buffer) (kill-buffer buffer)))))))

(ert-deftest emacsvox-aural-voice-tuner-navigation-announces-values ()
  "Up and Down announce each setting together with its current value."
  (emacsvox-test--with-voice-palettes
    (emacsvox-aural-register-voice-palette-data
     emacsvox-test--voice-palette-data)
    (let (buffers spoken style)
      (unwind-protect
          (save-window-excursion
            (cl-letf
                (((symbol-function 'emacsvox-aural-active-voice-capabilities)
                  (lambda ()
                    '(:adapter outloud
                      :dimensions
                      (family average-pitch pitch-range stress richness))))
                 ((symbol-function 'emacsvox-aural-voice-tuner--play-text)
                  (lambda (text working-style &optional _)
                    (setq spoken text
                          style (copy-tree working-style))))
                 ((symbol-function 'emacsvox-icon) #'ignore))
              (setq buffers (emacsvox-test--open-reading-voice-tuner 'aside))
              (with-current-buffer (cadr buffers)
                (setq
                 emacsvox-aural-voice-tuner-working-style
                 (plist-put
                  (copy-tree emacsvox-aural-voice-tuner-working-style)
                  :average-pitch 9))
                (emacsvox-aural-voice-tuner-refresh 'family)
                (setq spoken nil)
                (emacsvox-aural-voice-tuner-next)
                (should (eq (tabulated-list-get-id) 'average-pitch))
                (should
                 (equal
                  spoken
                  "Average Pitch 9. Supported By Outloud."))
                (should (= (plist-get style :average-pitch) 9))
                (emacsvox-aural-voice-tuner-next)
                (should (eq (tabulated-list-get-id) 'pitch-range))
                (emacsvox-aural-voice-tuner-previous)
                (should (eq (tabulated-list-get-id) 'average-pitch))
                (should
                 (equal
                  spoken
                  "Average Pitch 9. Supported By Outloud.")))))
        (dolist (buffer buffers)
          (when (buffer-live-p buffer) (kill-buffer buffer)))))))

(ert-deftest emacsvox-aural-voice-tuner-uses-working-voice-for-shared-ui ()
  "Cells and boundaries use the current unsaved style in the tuner buffer."
  (with-temp-buffer
    (emacsvox-aural-voice-tuner-mode)
    (setq
     emacsvox-aural-voice-tuner-working-style '(:average-pitch 8)
     tabulated-list-format [("Setting" 12 nil)]
     tabulated-list-entries '((pitch ["Pitch"])))
    (tabulated-list-init-header)
    (tabulated-list-print t)
    (goto-char (point-min))
    (let (requests)
      (cl-letf
          (((symbol-function 'emacsvox-aural-voice-tuner--play-text)
            (lambda (text style &optional _)
              (push (list text (copy-tree style)) requests)))
           ((symbol-function 'emacsvox-icon) #'ignore))
        (emacsvox-aural-ui-speak-current-cell)
        (emacsvox-aural-ui-announce-boundary "Top of voice settings."))
      (should
       (equal
        (nreverse requests)
        '(("Setting, Pitch" (:average-pitch 8))
          ("Top of voice settings." (:average-pitch 8))))))))

(ert-deftest emacsvox-aural-voice-tuner-compares-opening-and-working-styles ()
  "Repeated comparison alternates the opening and unsaved working voices."
  (with-temp-buffer
    (emacsvox-aural-voice-tuner-mode)
    (setq
     emacsvox-aural-voice-tuner-voice 'aside
     emacsvox-aural-voice-tuner-preview-text "Shared sample."
     emacsvox-aural-voice-tuner-initial-style '(:average-pitch 3)
     emacsvox-aural-voice-tuner-working-style '(:average-pitch 8)
     emacsvox-aural-voice-tuner-compare-reference-next-p t)
    (let (requests)
      (cl-letf
          (((symbol-function 'emacsvox-aural-voice-tuner--play-text)
            (lambda (text style &optional _)
              (push (list text (copy-tree style)) requests)))
           ((symbol-function 'emacsvox-aural-preview-message) #'ignore))
        (emacsvox-aural-voice-tuner-compare)
        (emacsvox-aural-voice-tuner-compare))
      (setq requests (nreverse requests))
      (should (string-prefix-p "Opening voice." (caar requests)))
      (should (equal (cadar requests) '(:average-pitch 3)))
      (should (string-prefix-p "Working voice." (caadr requests)))
      (should (equal (cadadr requests) '(:average-pitch 8)))
      (should emacsvox-aural-voice-tuner-compare-reference-next-p))))

(ert-deftest emacsvox-aural-voice-tuner-falls-back-to-operable-speech ()
  "Broken staged previews leave ordinary tuner navigation audible."
  (with-temp-buffer
    (emacsvox-aural-voice-tuner-mode)
    (setq emacsvox-aural-voice-tuner-working-style '(:average-pitch 9))
    (let (spoken)
      (cl-letf
          (((symbol-function 'emacsvox-aural-voice-tuner--play-text)
            (lambda (&rest _) (error "Preview failed")))
           ((symbol-function 'emacsvox-aural-preview-message) #'ignore)
           ((symbol-function 'tts-speak)
            (lambda (text) (setq spoken text))))
        (should
         (equal
          (emacsvox-aural-voice-tuner--speak-text "Recovery speech")
          "Recovery speech")))
      (should (equal spoken "Recovery speech")))))

(ert-deftest emacsvox-aural-voice-tuner-adjustments-announce-only-values ()
  "Horizontal and digit adjustments omit repeated setting descriptions."
  (with-temp-buffer
    (emacsvox-aural-voice-tuner-mode)
    (setq emacsvox-aural-voice-tuner-working-style '(:echo 7))
    (let (announcements)
      (cl-letf
          (((symbol-function 'emacsvox-aural-voice-tuner--current-dimension)
            (lambda () 'echo))
           ((symbol-function 'emacsvox-aural-voice-tuner-refresh) #'ignore)
           ((symbol-function 'emacsvox-aural-voice-tuner-audition)
            (lambda (&optional announcement)
              (push announcement announcements))))
        (emacsvox-aural-voice-tuner-increase)
        (emacsvox-aural-voice-tuner-decrease)
        (let ((last-command-event ?9))
          (emacsvox-aural-voice-tuner-set-digit)))
      (should (equal (nreverse announcements) '("8" "7" "9"))))))

(ert-deftest emacsvox-aural-voice-tuner-names-neutral-effect-values ()
  "Effect rows and adjustments describe their actual neutral states."
  (should
   (equal
    (mapcar
     (lambda (entry)
       (emacsvox-aural-voice-tuner--value-description
        (car entry) (cdr entry)))
     '((gain . 5) (low-pass . 9) (high-pass . 0)
       (pan . 5) (reverb . 0) (echo . 0) (chorus . 0)))
    '("unchanged" "0 (neutral)" "0 (neutral)"
      "centre" "disabled" "disabled" "disabled")))
  (with-temp-buffer
    (emacsvox-aural-voice-tuner-mode)
    (setq emacsvox-aural-voice-tuner-working-style '(:gain 4))
    (let (announcement)
      (cl-letf
          (((symbol-function 'emacsvox-aural-voice-tuner--current-dimension)
            (lambda () 'gain))
           ((symbol-function 'emacsvox-aural-voice-tuner-refresh) #'ignore)
           ((symbol-function 'emacsvox-aural-voice-tuner-audition)
            (lambda (&optional value) (setq announcement value))))
        (emacsvox-aural-voice-tuner-increase))
      (should (equal announcement "unchanged")))))

(ert-deftest emacsvox-aural-voice-tuner-adjusts-relative-rate-by-direct-points ()
  "Relative rate crosses zero in single points with concise announcements."
  (with-temp-buffer
    (emacsvox-aural-voice-tuner-mode)
    (setq emacsvox-aural-voice-tuner-working-style '(:rate-offset nil))
    (let (announcements)
      (cl-letf
          (((symbol-function 'emacsvox-aural-voice-tuner--current-dimension)
            (lambda () 'rate-offset))
           ((symbol-function 'emacsvox-aural-voice-tuner-refresh) #'ignore)
           ((symbol-function 'emacsvox-aural-voice-tuner-audition)
            (lambda (&optional announcement)
              (push announcement announcements))))
        (emacsvox-aural-voice-tuner-decrease)
        (emacsvox-aural-voice-tuner-increase)
        (emacsvox-aural-voice-tuner-increase))
      (should (= (plist-get emacsvox-aural-voice-tuner-working-style
                            :rate-offset)
                 1))
      (should
       (equal (nreverse announcements)
              '("1 point slower" "unchanged" "1 point faster"))))))

(ert-deftest emacsvox-aural-voice-tuner-auditions-selected-engine-route ()
  "Route-aware tuning uses normalized values and engine-specific support."
  (with-temp-buffer
    (emacsvox-aural-voice-tuner-mode)
    (setq
     emacsvox-aural-voice-tuner-palette 'reading
     emacsvox-aural-voice-tuner-voice 'aside
     emacsvox-aural-voice-tuner-working-style
     '(:family paul :average-pitch 4 :pitch-range 3
       :stress nil :richness 6 :rate-offset -7 :gain 5 :reverb 4 :chorus 6)
     emacsvox-aural-voice-tuner-preview-text "Shared sample."
     emacsvox-aural-voice-tuner-route-selector
     '(:kind exact :scope local :engine-id "eloquence"
       :voice-id "eci:Reed")
     emacsvox-aural-voice-tuner-route-language "en-AU"
     emacsvox-aural-voice-tuner-route-engine
     '(:engine-id "eloquence"
       :acss-dimensions (rate average-pitch pitch-range richness)
       :post-synthesis-dimensions ("gain" "reverb" "echo" "chorus")))
    (emacsvox-aural-voice-tuner-refresh 'average-pitch)
    (should
     (equal
      (aref (cadr (assq 'average-pitch tabulated-list-entries)) 3)
      "engine-rendered by eloquence"))
    (should
     (equal
      (aref (cadr (assq 'stress tabulated-list-entries)) 3)
      "omitted by eloquence"))
    (should
     (string-match-p
      "physical route owns"
      (aref (cadr (assq 'family tabulated-list-entries)) 3)))
    (let (request)
      (cl-letf
          (((symbol-function 'tts-preview-voice)
            (lambda (text selector &rest arguments)
              (setq request (list text selector arguments))
              (funcall
               (plist-get arguments :callback)
               '(:status completed
                 :realized
                 (:engine-id "eloquence" :voice-id "eci:Reed")
                 :degraded-acss (stress)
                 :degraded-effects (reverb))))))
        (emacsvox-aural-voice-tuner-audition "Average Pitch 4."))
      (should (string-match-p "Average Pitch 4" (car request)))
      (should
       (equal (cadr request)
              '(:kind exact :scope local :engine-id "eloquence"
                :voice-id "eci:Reed")))
      (let ((acss (plist-get (nth 2 request) :acss)))
        (should (= (plist-get acss :average-pitch) (/ 4.0 9.0)))
        (should (= (plist-get acss :pitch-range) (/ 3.0 9.0)))
        (should (= (plist-get acss :richness) (/ 6.0 9.0)))
        (should-not (plist-member acss :rate))
        (should-not (plist-member acss :family)))
      (should (= (plist-get (nth 2 request) :rate-offset) -7))
      (let ((effects (plist-get (nth 2 request) :effects)))
        (should (= (plist-get effects :gain) 0.5))
        (should (= (plist-get effects :reverb) (/ 4.0 9.0)))
        (should (= (plist-get effects :chorus) (/ 6.0 9.0))))
      (should
       (equal emacsvox-aural-voice-tuner-route-realized
              '(:engine-id "eloquence" :voice-id "eci:Reed")))
      (should
       (equal
        (emacsvox-aural-voice-tuner--support-description 'stress)
        "omitted by eloquence"))
      (should
       (equal
        (emacsvox-aural-voice-tuner--support-description 'gain)
        "Omnivox-rendered by eloquence"))
      (should
       (equal
        (emacsvox-aural-voice-tuner--support-description 'reverb)
        "omitted by eloquence")))))

(ert-deftest emacsvox-aural-voice-tuner-auditions-portable-effects-without-route ()
  "Palette tuning carries the complete unsaved style without a physical route."
  (with-temp-buffer
    (emacsvox-aural-voice-tuner-mode)
    (setq
     emacsvox-aural-voice-tuner-palette 'test
     emacsvox-aural-voice-tuner-voice 'lighten-extra
     emacsvox-aural-voice-tuner-working-style
     '(:average-pitch 6 :high-pass 5 :reverb 7 :echo 5 :chorus 4)
     emacsvox-aural-voice-tuner-preview-text "Shared sample."
     emacsvox-aural-voice-tuner-route-selector nil)
    (let (preview-plan)
      (cl-letf
          (((symbol-function 'emacsvox-aural-compile-voice-style)
            (lambda (definition _palette)
              (emacsvox-aural--make-compiled-voice
               :command "[[logical_voice acss-a6]]"
               :request (copy-tree definition)
               :style (copy-tree definition)
               :capability '(:adapter omnivox))))
           ((symbol-function 'emacsvox-aural-preview-play-plan)
            (lambda (plan) (setq preview-plan plan))))
        (emacsvox-aural-voice-tuner-audition))
      (let ((content (emacsvox-aural-concrete-plan-content preview-plan)))
        (should
         (equal
          (emacsvox-aural-concrete-content-voice-style content)
          '(:average-pitch 6 :high-pass 5 :reverb 7 :echo 5 :chorus 4)))
        (should
         (equal
          (emacsvox-aural-concrete-content-text content)
          "Lighten Extra voice. Shared sample."))))))

(ert-deftest emacsvox-aural-voice-tuner-reports-unavailable-effect-preview-path ()
  "Supported effects are not reported as applied on a legacy preview path."
  (with-temp-buffer
    (emacsvox-aural-voice-tuner-mode)
    (setq
     emacsvox-aural-voice-tuner-working-style '(:reverb 7)
     emacsvox-aural-voice-tuner-route-selector nil)
    (cl-letf
        (((symbol-function 'emacsvox-aural-active-voice-capabilities)
          (lambda ()
            '(:adapter omnivox :post-synthesis-dimensions (reverb))))
         ((symbol-function
           'emacsvox-aural-preview-structured-style-supported-p)
          (lambda () nil)))
      (should-not (emacsvox-aural-voice-tuner--applied-p 'reverb))
      (should
       (equal
        (emacsvox-aural-voice-tuner--effective-value 'reverb)
        "not applied"))
      (should
       (equal
        (emacsvox-aural-voice-tuner--support-description 'reverb)
        "requested; preview transport cannot apply"))
      (should
       (string-match-p
        "requested but is not applied in this audition"
        (emacsvox-aural-voice-tuner--setting-announcement 'reverb))))))

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
          :low-pass 8 :high-pass nil :pan 2 :reverb 4 :echo 1 :chorus 6)))
      (emacsvox-aural-register-voice-palette-data data)
      (let ((style (emacsvox-aural-voice 'aside 'reading)))
        (should (= (plist-get style :rate-offset) -7))
        (should (= (plist-get style :gain) 5))
        (should (= (plist-get style :reverb) 4))
        (should (= (plist-get style :echo) 1))
        (should (= (plist-get style :chorus) 6))))))

(ert-deftest emacsvox-aural-voice-tuner-adjusts-auditions-and-undoes ()
  "Adjustments remain temporary, audition immediately, and can be undone."
  (emacsvox-test--with-voice-palettes
    (emacsvox-aural-register-voice-palette-data
     emacsvox-test--voice-palette-data)
    (let (buffers preview-plans)
      (unwind-protect
          (save-window-excursion
            (cl-letf
                (((symbol-function 'emacsvox-aural-active-voice-capabilities)
                  (lambda ()
                    '(:adapter outloud
                      :dimensions
                      (average-pitch pitch-range stress richness))))
                 ((symbol-function 'voice-from-acss)
                  (lambda (_style &optional _logical-voice) 'voice-tuned))
                 ((symbol-function 'make-acss)
                  (lambda (&rest settings) settings))
                 ((symbol-function 'tts-get-voice-command)
                  (lambda (voice) (format "<%s>" voice)))
                 ((symbol-function 'emacsvox-aural-preview-play-plan)
                  (lambda (plan) (push plan preview-plans)))
                 ((symbol-function 'emacsvox-aural-preview-message)
                  #'ignore))
              (setq buffers (emacsvox-test--open-reading-voice-tuner 'aside))
              (with-current-buffer (cadr buffers)
                (should (emacsvox-aural-voice-tuner--goto 'average-pitch))
                (emacsvox-aural-voice-tuner-increase)
                (should
                 (=
                  (plist-get
                   emacsvox-aural-voice-tuner-working-style
                   :average-pitch)
                  5))
                (should emacsvox-aural-voice-tuner-dirty)
                (should (= (length emacsvox-aural-voice-tuner-history) 1))
                (should
                 (=
                  (plist-get
                   (emacsvox-aural-voice 'aside 'reading)
                   :average-pitch)
                  4))
                (let ((text
                       (emacsvox-aural-concrete-content-text
                        (emacsvox-aural-concrete-plan-content
                         (car preview-plans)))))
                  (should (string-prefix-p "5 " text))
                  (should-not (string-match-p "Average Pitch" text))
                  (should-not (string-match-p "Supported By" text))
                  (should
                   (string-match-p
                    "Aside voice. The quick brown fox jumps over the lazy dog."
                    text)))
                (emacsvox-aural-voice-tuner-undo)
                (should
                 (=
                  (plist-get
                   emacsvox-aural-voice-tuner-working-style
                   :average-pitch)
                  4))
                (should-not emacsvox-aural-voice-tuner-dirty)))
            (should (= (length preview-plans) 2)))
        (dolist (buffer buffers)
          (when (buffer-live-p buffer) (kill-buffer buffer)))))))

(ert-deftest emacsvox-aural-voice-tuner-saves-atomically ()
  "Saving publishes the complete working style and refreshes the preview."
  (emacsvox-test--with-voice-palettes
    (emacsvox-aural-register-voice-palette-data
     emacsvox-test--voice-palette-data)
    (let (buffers
          saved
          dismissed
          events
          (refresh-source
           (symbol-function 'emacsvox-aural-voice-tuner--refresh-source)))
      (unwind-protect
          (save-window-excursion
            (cl-letf
                (((symbol-function 'emacsvox-aural-active-voice-capabilities)
                  (lambda ()
                    '(:adapter outloud
                      :dimensions
                      (average-pitch pitch-range stress richness))))
                 ((symbol-function 'voice-from-acss)
                  (lambda (_style &optional _logical-voice) 'voice-tuned))
                 ((symbol-function 'make-acss)
                  (lambda (&rest settings) settings))
                 ((symbol-function 'tts-get-voice-command)
                  (lambda (voice) (format "<%s>" voice)))
                 ((symbol-function 'emacsvox-aural--ensure-speaker) #'ignore)
                 ((symbol-function 'emacsvox-aural-preview-stop)
                  #'ignore)
                 ((symbol-function 'emacsvox-aural-preview-message)
                  #'ignore)
                 ((symbol-function 'tts-voice-reset-code)
                  (lambda () "RESET"))
                 ((symbol-function 'tts--protocol-queue-code) #'ignore)
                 ((symbol-function 'tts--protocol-queue-text) #'ignore)
                 ((symbol-function 'tts--protocol-dispatch) #'ignore)
                 ((symbol-function 'emacsvox-aural-save-user-data)
                  (lambda (&optional _)
                    (setq
                     saved
                     (copy-tree
                      (emacsvox-aural-voice 'aside 'reading)))))
                 ((symbol-function 'emacsvox-aural-ui-refresh-home-if-live)
                  #'ignore)
                 ((symbol-function 'emacsvox-aural-capture-context) #'ignore)
                 ((symbol-function 'quit-window)
                  (lambda (&optional _kill _window)
                    (setq dismissed t)
                    (push 'quit events)))
                 ((symbol-function 'emacsvox-aural-voice-tuner--refresh-source)
                  (lambda (&rest arguments)
                    (push 'refresh events)
                    (apply refresh-source arguments)))
                 ((symbol-function 'emacsvox-icon) #'ignore)
                 ((symbol-function 'emacsvox-speak-mode-line) #'ignore))
              (setq buffers (emacsvox-test--open-reading-voice-tuner 'aside))
              (with-current-buffer (cadr buffers)
                (should (emacsvox-aural-voice-tuner--goto 'average-pitch))
                (emacsvox-aural-voice-tuner--set-value 'family 'paul)
                (emacsvox-aural-voice-tuner--set-value 'average-pitch 7)
                (should
                 (=
                  (plist-get
                   (emacsvox-aural-voice 'aside 'reading)
                   :average-pitch)
                  4))
                (emacsvox-aural-voice-tuner-save)))
            (should saved)
            (should (= (plist-get saved :average-pitch) 7))
            (should (eq (plist-get saved :family) 'paul))
            (should
             (=
              (plist-get
               (emacsvox-aural-voice 'aside 'reading)
               :average-pitch)
              7))
            (should dismissed)
            (should (equal (nreverse events) '(quit refresh)))
            (with-current-buffer (car buffers)
              (should (eq (tabulated-list-get-id) 'aside))))
        (dolist (buffer buffers)
          (when (buffer-live-p buffer) (kill-buffer buffer)))))))

(ert-deftest emacsvox-aural-voice-tuner-cancel-discards-working-style ()
  "Confirmed cancellation leaves the registered palette unchanged."
  (emacsvox-test--with-voice-palettes
    (emacsvox-aural-register-voice-palette-data
     emacsvox-test--voice-palette-data)
    (let (buffers dismissed)
      (unwind-protect
          (save-window-excursion
            (cl-letf
                (((symbol-function 'emacsvox-aural-active-voice-capabilities)
                  (lambda ()
                    '(:adapter outloud
                      :dimensions
                      (average-pitch pitch-range stress richness))))
                 ((symbol-function 'tts-speak) #'ignore)
                 ((symbol-function 'yes-or-no-p) (lambda (&rest _) t))
                 ((symbol-function 'emacsvox-aural-capture-context) #'ignore)
                 ((symbol-function 'quit-window)
                  (lambda (&optional _kill _window)
                    (setq dismissed t)))
                 ((symbol-function 'emacsvox-icon) #'ignore)
                 ((symbol-function 'emacsvox-speak-mode-line) #'ignore))
              (setq buffers (emacsvox-test--open-reading-voice-tuner 'aside))
              (with-current-buffer (cadr buffers)
                (setq
                 emacsvox-aural-voice-tuner-working-style
                 (plist-put
                  (copy-tree emacsvox-aural-voice-tuner-working-style)
                  :average-pitch 8)
                 emacsvox-aural-voice-tuner-dirty t)
                (emacsvox-aural-voice-tuner-quit)))
            (should dismissed)
            (should
             (=
              (plist-get
               (emacsvox-aural-voice 'aside 'reading)
               :average-pitch)
              4)))
        (dolist (buffer buffers)
          (when (buffer-live-p buffer) (kill-buffer buffer)))))))

(ert-deftest emacsvox-aural-voice-tuner-unchanged-personality-stays-named ()
  "Saving without adjustments does not convert a personality to ACSS data."
  (emacsvox-test--with-voice-palettes
    (emacsvox-aural-register-voice-palette-data
     emacsvox-test--voice-palette-data)
    (let (buffers dismissed)
      (unwind-protect
          (save-window-excursion
            (cl-letf
                (((symbol-function 'emacsvox-aural-compile-voice-style)
                  (lambda (&rest _)
                    (emacsvox-aural--make-compiled-voice
                     :style
                     '(:family nil :average-pitch 5 :pitch-range 5
                       :stress 5 :richness 5))))
                 ((symbol-function 'emacsvox-aural-active-voice-capabilities)
                  (lambda ()
                    '(:adapter outloud
                      :dimensions
                      (average-pitch pitch-range stress richness))))
                 ((symbol-function 'emacsvox-aural-save-user-data)
                  (lambda (&optional _)
                    (ert-fail "An unchanged tuner must not persist data")))
                 ((symbol-function 'emacsvox-aural-capture-context) #'ignore)
                 ((symbol-function 'quit-window)
                  (lambda (&optional _kill _window)
                    (setq dismissed t)))
                 ((symbol-function 'emacsvox-icon) #'ignore)
                 ((symbol-function 'emacsvox-speak-mode-line) #'ignore))
              (setq buffers (emacsvox-test--open-reading-voice-tuner 'heading))
              (with-current-buffer (cadr buffers)
                (should
                 (eq
                  emacsvox-aural-voice-tuner-original-definition
                  'voice-bolden))
                (should-not emacsvox-aural-voice-tuner-dirty)
                (emacsvox-aural-voice-tuner-save)))
            (should dismissed)
            (should
             (eq (emacsvox-aural-voice 'heading 'reading) 'voice-bolden)))
        (dolist (buffer buffers)
          (when (buffer-live-p buffer) (kill-buffer buffer)))))))

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

(ert-deftest emacsvox-aural-voice-tuner-offers-portable-and-exact-families ()
  "Enumerated adapters expose generic choices beside native base voices."
  (let (offered)
    (cl-letf
        (((symbol-function 'emacsvox-aural-active-voice-capabilities)
          (lambda ()
            '(:adapter outloud
              :family-selection enumerated
              :generic-families (male female)
              :families
              ((paul :label "Adult male 1" :generic (male))
               (outloud-v2
                :label "Adult female 1"
                :generic (female)))
              :dimensions (family))))
         ((symbol-function 'completing-read)
          (lambda (_prompt collection &rest _)
            (setq offered collection)
            (car
             (cl-find-if
              (lambda (entry)
                (eq (cdr entry) 'female))
              collection)))))
      (should
       (eq (emacsvox-aural-voice-tuner--read-family nil)
           'female)))
    (should
     (cl-find-if
      (lambda (entry) (eq (cdr entry) 'outloud-v2))
      offered))
    (should
     (string-match-p
      "portable.*currently Adult female 1"
      (car
       (cl-find-if
        (lambda (entry) (eq (cdr entry) 'female))
        offered))))))

(ert-deftest emacsvox-aural-voice-tuner-completes-routed-fallback-family ()
  "Routed adapters complete portable families without requiring a match."
  (let (offered require-match)
    (cl-letf
        (((symbol-function 'emacsvox-aural-active-voice-capabilities)
          (lambda ()
            '(:adapter omnivox
              :family-selection routed
              :generic-families (male female child)
              :families nil
              :dimensions (average-pitch))))
         ((symbol-function 'completing-read)
          (lambda (_prompt collection _predicate must-match &rest _)
            (setq offered collection
                  require-match must-match)
            "female — portable")))
      (should
       (eq (emacsvox-aural-voice-tuner--read-family nil)
           'female)))
    (should-not require-match)
    (should
     (cl-find-if
      (lambda (entry) (eq (cdr entry) 'child))
      offered))))

(ert-deftest emacsvox-aural-voice-tuner-rejects-unsupported-family-edit ()
  "Adapters without inline family selection explain that limitation."
  (cl-letf
      (((symbol-function 'emacsvox-aural-active-voice-capabilities)
        (lambda ()
          '(:adapter espeak
            :family-selection unsupported
            :dimensions (average-pitch pitch-range richness)))))
    (should-error
     (emacsvox-aural-voice-tuner--read-family nil)
     :type 'user-error)))

(ert-deftest emacsvox-aural-voice-palette-preview-can-queue-all-voices ()
  "Play-all queues every voice against one comparison before dispatch."
  (emacsvox-test--with-voice-palettes
    (emacsvox-aural-register-voice-palette-data
     '(:schema-version 1
       :id pair
       :summary "Two comparison voices"
       :entries
       ((first :personality voice-bolden)
        (second :personality voice-animate))))
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
                  2)))))
        (when (get-buffer "*Aural Voice Palette Preview*")
          (kill-buffer "*Aural Voice Palette Preview*")))
      (should (= (length preview-runs) 2))
      (should
       (equal
        (sort
         (mapcar
          (lambda (run)
            (emacsvox-aural-concrete-content-text
             (emacsvox-aural-concrete-plan-content (car run))))
          preview-runs)
         #'string-lessp)
        '("First voice. The quick brown fox jumps over the lazy dog."
          "Second voice. The quick brown fox jumps over the lazy dog."))))))

(ert-deftest emacsvox-aural-tuner-value-prompt-describes-retained-value ()
  "Blank numeric input retains an existing setting and describes that behavior."
  (let (prompt)
    (cl-letf (((symbol-function 'read-string) (lambda (text &rest _) (setq prompt text) "")))
      (should (= 6 (emacsvox-aural-voice-palettes--read-style-number 'average-pitch 6)))
      (should (string-match-p "blank keeps 6" prompt))
      (should-not (emacsvox-aural-voice-palettes--read-style-number 'average-pitch nil))
      (should (string-match-p "blank uses the adapter default" prompt)))))

(defmacro emacsvox-test--with-numeric-tuner (dimension value &rest body)
  "Run BODY in a tuner for DIMENSION and VALUE, recording refreshes and auditions."
  (declare (indent 2) (debug (form form body)))
  `(with-temp-buffer
     (emacsvox-aural-voice-tuner-mode)
     (let* ((tuner-test-dimension ,dimension)
            (tuner-test-key (intern (concat ":" (symbol-name tuner-test-dimension))))
            (tuner-test-initial (list :family 'paul tuner-test-key ,value))
            tuner-test-refreshes tuner-test-auditions)
       (setq emacsvox-aural-voice-tuner-initial-style (copy-tree tuner-test-initial)
             emacsvox-aural-voice-tuner-working-style (copy-tree tuner-test-initial))
       (cl-letf (((symbol-function 'emacsvox-aural-voice-tuner--current-dimension)
                  (lambda () tuner-test-dimension))
                 ((symbol-function 'emacsvox-aural-voice-tuner-refresh)
                  (lambda (&optional dimension) (push dimension tuner-test-refreshes)))
                 ((symbol-function 'emacsvox-aural-voice-tuner-audition)
                  (lambda (&optional announcement) (push announcement tuner-test-auditions))))
         ,@body))))

(ert-deftest emacsvox-aural-tuner-numeric-bounds-preserve-state-and-undo ()
  "Accepted boundary values audition once; rejected steps leave state intact."
  :tags '(voice-style-ui)
  ;; Independent expectations: do not obtain test limits from field metadata.
  (dolist (fixture '((average-pitch 0 9) (pitch-range 0 9) (stress 0 9)
                     (richness 0 9) (rate-offset -20 20) (gain 0 9)
                     (low-pass 0 9) (high-pass 0 9) (pan 0 9)
                     (reverb 0 9) (echo 0 9) (chorus 0 9)))
    (pcase-let ((`(,dimension ,minimum ,maximum) fixture))
      (dolist (step (if (eq dimension 'low-pass)
                       '((emacsvox-aural-voice-tuner-decrease 8 9)
                         (emacsvox-aural-voice-tuner-increase 1 0))
                     (list (list #'emacsvox-aural-voice-tuner-decrease (1+ minimum) minimum)
                           (list #'emacsvox-aural-voice-tuner-increase (1- maximum) maximum))))
        (pcase-let ((`(,command ,initial ,boundary) step))
          (emacsvox-test--with-numeric-tuner dimension initial
            (call-interactively command)
            (should (= (plist-get emacsvox-aural-voice-tuner-working-style tuner-test-key)
                       boundary))
            (should (equal emacsvox-aural-voice-tuner-history (list tuner-test-initial)))
            (should emacsvox-aural-voice-tuner-dirty)
            (should (equal tuner-test-refreshes (list dimension)))
            (should (= 1 (length tuner-test-auditions)))
            (let ((before (copy-tree emacsvox-aural-voice-tuner-working-style)))
              (should (equal (should-error (call-interactively command) :type 'user-error)
                             (list 'user-error
                                   (format "%s is already at %s" dimension
                                           (if (eq dimension 'low-pass) (- 9 boundary) boundary)))))
              (should (equal emacsvox-aural-voice-tuner-working-style before)))
            (should (equal emacsvox-aural-voice-tuner-history (list tuner-test-initial)))
            (should (= 1 (length tuner-test-refreshes)))
            (should (= 1 (length tuner-test-auditions)))
            (call-interactively #'emacsvox-aural-voice-tuner-undo)
            (should (equal emacsvox-aural-voice-tuner-working-style tuner-test-initial))
            (should-not emacsvox-aural-voice-tuner-history)
            (should-not emacsvox-aural-voice-tuner-dirty)
            (should (= 2 (length tuner-test-refreshes)))
            (should (= 2 (length tuner-test-auditions)))))))))

(ert-deftest emacsvox-aural-tuner-numeric-adjustments-from-nil ()
  "Nil starts at five for ordinary fields, and plus/minus one for rate."
  :tags '(voice-style-ui)
  (dolist (dimension '(average-pitch pitch-range stress richness rate-offset
                      gain pan reverb echo chorus))
    (dolist (command '(emacsvox-aural-voice-tuner-increase emacsvox-aural-voice-tuner-decrease))
      (emacsvox-test--with-numeric-tuner dimension nil
        (call-interactively command)
        (should (= (plist-get emacsvox-aural-voice-tuner-working-style tuner-test-key)
                   (if (eq dimension 'rate-offset)
                       (if (eq command 'emacsvox-aural-voice-tuner-increase) 1 -1)
                     5)))
        (should (equal emacsvox-aural-voice-tuner-history (list tuner-test-initial)))
        (should (= 1 (length tuner-test-refreshes)))
        (should (= 1 (length tuner-test-auditions)))))))

(ert-deftest emacsvox-aural-tuner-numeric-digit-and-default-shortcuts ()
  "Digits and reset preserve history, and repeating a value stays quiet."
  :tags '(voice-style-ui)
  (dolist (dimension '(average-pitch pitch-range stress richness rate-offset
                      gain low-pass high-pass pan reverb echo chorus))
    (emacsvox-test--with-numeric-tuner dimension nil
      (let ((last-command-event ?0))
        (call-interactively #'emacsvox-aural-voice-tuner-set-digit)
        (call-interactively #'emacsvox-aural-voice-tuner-set-digit))
      (should (= (plist-get emacsvox-aural-voice-tuner-working-style tuner-test-key)
                 (if (eq dimension 'low-pass) 9 0)))
      (should (= 1 (length emacsvox-aural-voice-tuner-history)))
      (should (= 1 (length tuner-test-auditions)))
      (let ((last-command-event ?9))
        (call-interactively #'emacsvox-aural-voice-tuner-set-digit))
      (should (= (plist-get emacsvox-aural-voice-tuner-working-style tuner-test-key)
                 (if (eq dimension 'low-pass) 0 9)))
      (call-interactively #'emacsvox-aural-voice-tuner-use-default)
      (call-interactively #'emacsvox-aural-voice-tuner-use-default)
      (should (equal emacsvox-aural-voice-tuner-working-style tuner-test-initial))
      (should (= 3 (length emacsvox-aural-voice-tuner-history)))
      (should (= 3 (length tuner-test-refreshes)))
      (should (= 3 (length tuner-test-auditions)))
      (should-not emacsvox-aural-voice-tuner-dirty))))

(ert-deftest emacsvox-aural-tuner-numeric-input-keeps-reader-contracts ()
  "Numeric edits preserve their distinct blank handling and accepted spellings."
  :tags '(voice-style-ui)
  (dolist (dimension '(average-pitch pitch-range stress richness rate-offset
                      gain low-pass high-pass pan reverb echo chorus))
    (dolist (current '(nil 0 5))
      (dolist (answer '("" " \t" "0" "9" " 3 " "00" "+1" "-0" "-20" "20"
                        "-21" "21" "10" "-1" "1.0" "+" "1x" "word"))
        (let* ((rate-p (eq dimension 'rate-offset))
               (trimmed (string-trim answer))
               (valid (if rate-p
                          (member trimmed '("" "0" "9" "3" "00" "+1" "-0" "-20" "20" "10" "-1"))
                        (member trimmed '("" "0" "9" "3"))))
               (expected (if (string-empty-p trimmed)
                             (unless rate-p current)
                           (if (eq dimension 'low-pass)
                               (- 9 (string-to-number trimmed))
                             (string-to-number trimmed))))
               prompt)
          (emacsvox-test--with-numeric-tuner dimension current
            (cl-letf (((symbol-function 'read-string)
                       (lambda (text &rest _) (setq prompt text) answer)))
              (if valid
                  (progn
                    (call-interactively #'emacsvox-aural-voice-tuner-edit)
                    (should (equal (plist-get emacsvox-aural-voice-tuner-working-style tuner-test-key)
                                   expected)))
                (should (equal
                         (should-error (call-interactively #'emacsvox-aural-voice-tuner-edit)
                                       :type 'user-error)
                         (list 'user-error
                               (if rate-p "Relative rate must be -20 through 20 or blank"
                                 (format "%s must be 0 through 9 or blank" dimension)))))))
            (when (eq dimension 'average-pitch)
              (should (equal prompt
                             (format "average pitch, 0 through 9; blank %s: "
                                     (if current (format "keeps %s" current)
                                       "uses the adapter default")))))
            (when rate-p
              (should (equal prompt
                             (format "Relative rate, -20 through 20; blank means unchanged%s: "
                                     (if current (format " [%s]" current) "")))))
            (if (and valid (not (equal current expected)))
                (progn
                  (should (equal emacsvox-aural-voice-tuner-history (list tuner-test-initial)))
                  (should emacsvox-aural-voice-tuner-dirty)
                  (should (= 1 (length tuner-test-refreshes)))
                  (should (= 1 (length tuner-test-auditions))))
              (should (equal emacsvox-aural-voice-tuner-working-style tuner-test-initial))
              (should-not emacsvox-aural-voice-tuner-history)
              (should-not emacsvox-aural-voice-tuner-dirty)
              (should-not tuner-test-refreshes)
              (should-not tuner-test-auditions))))))))

(ert-deftest emacsvox-aural-tuner-filter-amounts-preserve-cutoffs ()
  "Amount edits, display, previews and undo preserve stored cutoff semantics."
  ;; Existing saved cutoff 8 means amount 1; inspection and blank RET are inert.
  (emacsvox-test--with-numeric-tuner 'low-pass 8
    (should (equal (emacsvox-aural-voice-tuner--requested-value 'low-pass) "1"))
    (should (= (plist-get (emacsvox-aural-voice-tuner--normalized-effects
                          emacsvox-aural-voice-tuner-working-style) :low-pass)
               (/ 8.0 9.0)))
    (cl-letf (((symbol-function 'read-string)
               (lambda (prompt &rest _)
                 (should (string-prefix-p "Low-pass Amount, " prompt))
                 (should (string-match-p "blank keeps 1" prompt))
                 "")))
      (emacsvox-aural-voice-tuner-edit))
    (should-not emacsvox-aural-voice-tuner-dirty)
    (emacsvox-aural-voice-tuner-increase)
    (should (= (plist-get emacsvox-aural-voice-tuner-working-style :low-pass) 7))
    (should (equal (car tuner-test-auditions) "2"))
    (should (= (plist-get (emacsvox-aural-voice-tuner--normalized-effects
                          emacsvox-aural-voice-tuner-working-style) :low-pass)
               (/ 7.0 9.0)))
    (emacsvox-aural-voice-tuner-undo)
    (should (equal emacsvox-aural-voice-tuner-working-style tuner-test-initial))
    (should-not emacsvox-aural-voice-tuner-dirty))
  ;; From adapter defaults, right adds one unit; left cannot go below neutral.
  (dolist (fixture '((low-pass 8) (high-pass 1)))
    (emacsvox-test--with-numeric-tuner (car fixture) nil
      (should-error (emacsvox-aural-voice-tuner-decrease) :type 'user-error)
      (should-not emacsvox-aural-voice-tuner-dirty)
      (should-not tuner-test-auditions)
      (emacsvox-aural-voice-tuner-increase)
      (should (= (plist-get emacsvox-aural-voice-tuner-working-style tuner-test-key)
                 (cadr fixture)))
      (should (equal (car tuner-test-auditions) "1")))))

(ert-deftest emacsvox-aural-tuner-numeric-editor-keeps-five-field-acss-scope ()
  "The complete-style editor asks only for family and four ACSS dimensions."
  :tags '(voice-style-ui)
  (let ((answers '("paul" "0" "1" "2" "3")) prompts)
    (cl-letf (((symbol-function 'read-string)
               (lambda (prompt &rest _)
                 (push prompt prompts)
                 (or (pop answers) (ert-fail "Unexpected additional style prompt")))))
      (should (equal (emacsvox-aural-voice-palettes--read-style)
                     '(:family paul :average-pitch 0 :pitch-range 1 :stress 2 :richness 3))))
    (should-not answers)
    (should (equal (nreverse prompts)
                   '("Voice family; blank uses the adapter default: "
                     "average pitch, 0 through 9; blank uses the adapter default: "
                     "pitch range, 0 through 9; blank uses the adapter default: "
                     "stress, 0 through 9; blank uses the adapter default: "
                     "richness, 0 through 9; blank uses the adapter default: ")))))

(provide 'emacsvox-aural-voice-palettes-tests)
;;; emacsvox-aural-voice-palettes-tests.el ends here
