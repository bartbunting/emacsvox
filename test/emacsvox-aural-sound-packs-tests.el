;;; emacsvox-aural-sound-packs-tests.el --- Sound-pack workbench tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Contract coverage for accessible sound-pack and cue browsing, provenance,
;; audition, activation, validation, safe manifest editing, and home routing.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-aural-sound-packs)

(defun emacsvox-test--sound-workbench-file (directory cue)
  "Create an empty Ogg asset for CUE in DIRECTORY."
  (let ((file
         (expand-file-name
          (format "%s.ogg" cue) directory)))
    (write-region "" nil file nil 'silent)
    file))

(defun emacsvox-test--sound-workbench-manifest (directory data)
  "Write manifest DATA in DIRECTORY and return its path."
  (let ((file
         (expand-file-name
          emacsvox-aural-resource-pack-manifest directory)))
    (write-region data nil file nil 'silent)
    file))

(defmacro emacsvox-test--with-sound-workbench (&rest body)
  "Run BODY with isolated base and discovered overlay sound packs."
  (declare (indent 0) (debug t))
  `(let* ((root (make-temp-file "emacsvox-sound-workbench-" t))
          (base-directory (expand-file-name "base" root))
          (overlay-directory (expand-file-name "overlay" root))
          (emacsvox-aural-resource-pack-registry
           (make-hash-table :test #'eq))
          (emacsvox-aural-resource-overlay-registry
           (make-hash-table :test #'eq))
          (emacsvox-aural-disabled-resource-overlays nil)
          (emacsvox-aural-resource-overlays-changed-hook nil)
          (emacsvox-aural--resource-pack-discovery-registry
           emacsvox-aural-resource-pack-registry)
          (emacsvox-aural-resource-pack-discovery-roots (list root))
          (emacsvox-sounds-current-pack 'overlay)
          (emacsvox-aural-tools--last-source-buffer nil))
     (unwind-protect
         (progn
           (make-directory base-directory)
           (make-directory overlay-directory)
           (dolist (cue '(button item close-object))
             (emacsvox-test--sound-workbench-file
              base-directory cue))
           (emacsvox-test--sound-workbench-file
            overlay-directory 'button)
           (emacsvox-test--sound-workbench-manifest
            overlay-directory
            (concat
             "(:schema-version 1\n"
             " :summary \"Personal overlay\"\n"
             " :parent base\n"
             " :profiles nil\n"
             " :default-spatialization neutral)\n"))
           (emacsvox-aural-register-resource-pack
            'base
            :summary "Base test sounds"
            :directory base-directory)
           (emacsvox-aural-refresh-discovered-resource-packs)
           (setq emacsvox-sounds-current-pack 'overlay)
           ,@body)
       (dolist
           (buffer
            '("*Aural Sound Packs*" "*Aural Sound Cues: overlay*"
              "*Aural Sound Cues: base*"))
         (when (get-buffer buffer)
           (kill-buffer buffer)))
       (delete-directory root t))))

(ert-deftest emacsvox-aural-sound-pack-manager-reports-state-and-commands ()
  "The pack manager reports useful state and exposes every spoken operation."
  (emacsvox-test--with-sound-workbench
    (should (commandp 'emacsvox-aural-list-sound-packs))
    (should (commandp 'emacsvox-aural-list-sound-pack-cues))
    (save-window-excursion
      (emacsvox-aural-list-sound-packs 'overlay)
      (with-current-buffer "*Aural Sound Packs*"
        (should (derived-mode-p 'emacsvox-aural-sound-packs-mode))
        (let ((row (cadr (assq 'overlay tabulated-list-entries))))
          (should (equal (aref row 1) "active"))
          (should (equal (aref row 3) "discovered"))
          (should (equal (aref row 4) "base"))
          (should (equal (aref row 5) "1 native, 3 effective"))
          (should (equal (aref row 8) "valid")))
        (dolist
            (binding
             '(("RET" . emacsvox-aural-list-sound-pack-cues)
               ("a" . emacsvox-aural-sound-packs-activate)
               ("P" . emacsvox-aural-sound-packs-audition)
               ("v" . emacsvox-aural-sound-packs-show-validation)
               ("e" . emacsvox-aural-sound-packs-edit-manifest)
               ("o" . emacsvox-aural-sound-packs-open-directory)
               ("h" . emacsvox-aural)
               ("?" . emacsvox-aural-sound-packs-help)))
          (should
           (eq
            (lookup-key
             emacsvox-aural-sound-packs-mode-map
             (kbd (car binding)))
            (cdr binding))))))))

(ert-deftest emacsvox-aural-sound-pack-manager-speaks-navigation ()
  "Pack and cue navigation use direction-aware order and explicit boundaries."
  (emacsvox-test--with-sound-workbench
    (save-window-excursion
      (emacsvox-aural-list-sound-packs 'base)
      (with-current-buffer "*Aural Sound Packs*"
        (let (spoken)
          (cl-letf
              (((symbol-function 'tts-speak)
                (lambda (text) (setq spoken text)))
               ((symbol-function 'emacsvox-icon) #'ignore))
            (emacsvox-aural-sound-packs-previous)
            (should (equal spoken "Top of sound pack list."))
            (emacsvox-aural-sound-packs-next)
            (should (equal spoken "overlay, Pack"))
            (emacsvox-aural-sound-packs-next-column)
            (should (equal spoken "Status, active")))))
      (emacsvox-aural-list-sound-pack-cues 'overlay)
      (with-current-buffer "*Aural Sound Cues: overlay*"
        (let (spoken)
          (cl-letf
              (((symbol-function 'tts-speak)
                (lambda (text) (setq spoken text)))
               ((symbol-function 'emacsvox-icon) #'ignore))
            (emacsvox-aural-sound-packs--goto-id
             (caar tabulated-list-entries))
            (emacsvox-aural-sound-pack-cues-previous)
            (should (equal spoken "Top of sound cue list."))
            (emacsvox-aural-sound-packs--goto-id 'item)
            (emacsvox-aural-sound-pack-cues-next-column)
            (should (equal spoken "Availability, inherited"))))))))

(ert-deftest emacsvox-aural-sound-pack-cues-explain-provenance ()
  "Cue rows distinguish native, inherited, fallback, and missing assets."
  (emacsvox-test--with-sound-workbench
    (save-window-excursion
      (emacsvox-aural-list-sound-pack-cues 'overlay)
      (with-current-buffer "*Aural Sound Cues: overlay*"
        (let ((button (cadr (assq 'button tabulated-list-entries)))
              (item (cadr (assq 'item tabulated-list-entries)))
              (shutdown (cadr (assq 'shutdown tabulated-list-entries)))
              (emacsvox (cadr (assq 'emacsvox tabulated-list-entries)))
              (alarm (cadr (assq 'alarm tabulated-list-entries))))
          (should (equal (aref button 1) "native"))
          (should (equal (aref button 2) "overlay"))
          (should (equal (aref item 1) "inherited"))
          (should (equal (aref item 2) "base"))
          (should (equal
                   (aref shutdown 1)
                   "fallback to close-object"))
          (should (equal (aref shutdown 2) "base"))
          (should (equal (aref emacsvox 1) "missing"))
          (should (equal (aref alarm 1) "missing")))
        (dolist
            (binding
             '(("RET" . emacsvox-aural-sound-pack-cues-audition)
               ("P" . emacsvox-aural-sound-pack-cues-audition)
               ("v" . emacsvox-aural-sound-pack-cues-show-validation)
               ("o" . emacsvox-aural-sound-packs-open-directory)
               ("s" . emacsvox-aural-list-sound-packs)
               ("h" . emacsvox-aural)
               ("?" . emacsvox-aural-sound-pack-cues-help)))
          (should
           (eq
            (lookup-key
             emacsvox-aural-sound-pack-cues-mode-map
             (kbd (car binding)))
            (cdr binding))))))))

(ert-deftest emacsvox-aural-sound-pack-cues-explain-module-provenance ()
  "Cue rows distinguish themed module overrides from packaged defaults."
  (let ((emacsvox-aural-cue-registry
         (copy-hash-table emacsvox-aural-cue-registry)))
    (emacsvox-test--with-sound-workbench
      (let* ((module-directory (expand-file-name "modules/notmuch" root))
             (themed-directory
              (expand-file-name "notmuch" overlay-directory)))
        (make-directory module-directory t)
        (make-directory themed-directory)
        (emacsvox-aural-register-cue
         'notmuch-attachment
         :summary "A Notmuch attachment was reached"
         :fallback 'item
         :owner 'notmuch)
        (emacsvox-test--sound-workbench-file
         module-directory 'notmuch-attachment)
        (emacsvox-test--sound-workbench-file
         themed-directory 'notmuch-attachment)
        (emacsvox-aural-register-resource-overlay
         'notmuch-earcons
         :summary "Notmuch-specific earcons"
         :owner 'notmuch
         :directory module-directory)
        (let ((base
               (emacsvox-aural-sound-packs--cue-detail
                'notmuch-attachment 'base))
              (themed
               (emacsvox-aural-sound-packs--cue-detail
                'notmuch-attachment 'overlay)))
          (should
           (equal
            (emacsvox-aural-sound-cue-detail-availability base)
            "module default"))
          (should
           (eq
            (emacsvox-aural-sound-cue-detail-provider base)
            'notmuch-earcons))
          (should
           (equal
            (emacsvox-aural-sound-cue-detail-availability themed)
            "module override"))
          (should
           (eq
            (emacsvox-aural-sound-cue-detail-provider themed)
            'overlay)))))))

(ert-deftest emacsvox-aural-sound-pack-cues-audition-concrete-resource ()
  "Audition resolves the selected pack once and plays its concrete file."
  (emacsvox-test--with-sound-workbench
    (save-window-excursion
      (emacsvox-aural-list-sound-pack-cues 'overlay)
      (with-current-buffer "*Aural Sound Cues: overlay*"
        (emacsvox-aural-sound-packs--goto-id 'item)
        (let (played)
          (cl-letf
              (((symbol-function 'emacsvox-sounds-play-concrete-cue)
                (lambda (resource sample-id &optional balance)
                  (setq played (list resource sample-id balance)))))
            (emacsvox-aural-sound-pack-cues-audition))
          (should
           (equal
            (car played)
            (expand-file-name "item.ogg" base-directory)))
          (should
           (string-prefix-p "emacsvox-base-item-" (cadr played)))
          (should-not (caddr played)))))))

(ert-deftest emacsvox-aural-sound-pack-manager-activates-and-validates ()
  "Activation refreshes status while validation provides spoken diagnostics."
  (emacsvox-test--with-sound-workbench
    (save-window-excursion
      (emacsvox-aural-list-sound-packs 'base)
      (with-current-buffer "*Aural Sound Packs*"
        (let (selected spoken)
          (cl-letf
              (((symbol-function 'emacsvox-sounds-select-theme)
                (lambda (pack)
                  (setq
                   selected pack
                   emacsvox-sounds-current-pack pack)))
               ((symbol-function 'emacsvox-aural-home-refresh-if-live)
                #'ignore)
               ((symbol-function 'tts-speak)
                (lambda (text) (setq spoken text))))
            (emacsvox-aural-sound-packs-activate)
            (should (eq selected 'base))
            (should
             (equal
              (aref
               (cadr (assq 'base tabulated-list-entries))
               1)
              "active"))
            (let ((report
                   (emacsvox-aural-sound-packs-show-validation 'base)))
              (should
               (emacsvox-aural-resource-report-valid report))
              (should (equal spoken "Sound pack base, valid.")))))))))

(ert-deftest emacsvox-aural-sound-pack-manifest-editor-is-safe-and-atomic ()
  "Guided metadata persists as data and keeps a recoverable backup."
  (emacsvox-test--with-sound-workbench
    (let* ((manifest
            (expand-file-name
             emacsvox-aural-resource-pack-manifest overlay-directory))
           (original
            (with-temp-buffer
              (insert-file-contents manifest)
              (buffer-string))))
      (save-window-excursion
        (emacsvox-aural-list-sound-packs 'overlay)
        (with-current-buffer "*Aural Sound Packs*"
          (cl-letf
              (((symbol-function 'read-string)
                (lambda (&rest _) "Edited overlay"))
               ((symbol-function 'completing-read)
                (lambda (prompt &rest _)
                  (cond
                   ((string-prefix-p "Parent" prompt) "base")
                   ((string-prefix-p "Default spatialization" prompt)
                    "stereo")
                   (t (ert-fail (format "Unexpected prompt: %s" prompt))))))
               ((symbol-function 'completing-read-multiple)
                (lambda (&rest _) nil))
               ((symbol-function 'emacsvox-aural-home-refresh-if-live)
                #'ignore))
            (emacsvox-aural-sound-packs-edit-manifest))))
      (let ((pack (emacsvox-aural-resource-pack 'overlay))
            (data
             (emacsvox-aural--read-resource-pack-manifest
              overlay-directory)))
        (should
         (equal
          (emacsvox-aural-resource-pack-summary pack)
          "Edited overlay"))
        (should
         (eq
          (emacsvox-aural-resource-pack-default-spatialization pack)
          'stereo))
        (should (equal (plist-get data :summary) "Edited overlay"))
        (should (eq (plist-get data :parent) 'base))
        (should (file-exists-p (concat manifest "~")))
        (should
         (equal
          (with-temp-buffer
            (insert-file-contents (concat manifest "~"))
            (buffer-string))
          original))))))

(ert-deftest emacsvox-aural-sound-pack-manifest-write-rolls-back-errors ()
  "A failed registry refresh restores the previous manifest exactly."
  (emacsvox-test--with-sound-workbench
    (let* ((pack (emacsvox-aural-resource-pack 'overlay))
           (manifest
            (expand-file-name
             emacsvox-aural-resource-pack-manifest overlay-directory))
           (before
            (with-temp-buffer
              (insert-file-contents manifest)
              (buffer-string))))
      (cl-letf
          (((symbol-function
             'emacsvox-aural-refresh-discovered-resource-packs)
            (lambda () (error "simulated refresh failure"))))
        (should-error
         (emacsvox-aural-sound-packs--write-manifest
          pack
          '(:schema-version 1
            :summary "Must roll back"
            :parent base
            :profiles nil
            :default-spatialization neutral))))
      (should
       (equal
        (with-temp-buffer
          (insert-file-contents manifest)
          (buffer-string))
        before)))))

(ert-deftest emacsvox-aural-home-routes-sounds-to-workbench ()
  "The Sound packs home row opens the manager rather than a raw selector."
  (let ((source (generate-new-buffer " *sound-pack-home-source*"))
        opened)
    (unwind-protect
        (save-window-excursion
          (emacsvox-aural source)
          (with-current-buffer "*Emacsvox Aural*"
            (emacsvox-aural-home--goto 'sounds)
            (cl-letf
                (((symbol-function 'emacsvox-aural-list-sound-packs)
                  (lambda (&optional _pack)
                    (setq opened t))))
              (emacsvox-aural-home-activate)))
          (should opened))
      (when (get-buffer "*Emacsvox Aural*")
        (kill-buffer "*Emacsvox Aural*"))
      (kill-buffer source))))

(provide 'emacsvox-aural-sound-packs-tests)
;;; emacsvox-aural-sound-packs-tests.el ends here
