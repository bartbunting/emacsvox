;;; emacsvox-aural-resources.el --- Aural resource providers -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Register semantic cue names, sound resource packs, requirement profiles,
;; and device-independent voice palettes.  Resource resolution remains
;; independent of local-player and speech-server protocols.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'emacsvox-aural)
(require 'emacsvox-aural-rules)

(define-error
  'emacsvox-aural-resource-error
  "Invalid Emacsvox aural resource provider")

(cl-defstruct
    (emacsvox-aural-cue
     (:constructor emacsvox-aural--make-cue))
  "A named non-speech presentation cue."
  id summary kind fallback owner)

(cl-defstruct
    (emacsvox-aural-requirement-profile
     (:constructor emacsvox-aural--make-requirement-profile))
  "A named cue-coverage contract."
  id summary cues)

(cl-defstruct
    (emacsvox-aural-resource-pack
     (:constructor emacsvox-aural--make-resource-pack))
  "A concrete sound resource provider."
  id summary kind directory parent profiles default-spatialization assets)

(cl-defstruct
    (emacsvox-aural-resource-report
     (:constructor emacsvox-aural--make-resource-report))
  "Validation result for one resource pack."
  pack valid missing-required unknown-assets missing-directory)

(cl-defstruct
    (emacsvox-aural-voice-palette
     (:constructor emacsvox-aural--make-voice-palette))
  "A named collection of device-independent personality symbols."
  id summary parent entries)

(defvar emacsvox-aural-cue-registry (make-hash-table :test #'eq)
  "Map cue identifiers to `emacsvox-aural-cue' records.")

(defvar emacsvox-aural-requirement-profile-registry
  (make-hash-table :test #'eq)
  "Map profile identifiers to cue requirement profiles.")

(defvar emacsvox-aural-resource-pack-registry
  (make-hash-table :test #'eq)
  "Map resource-pack identifiers to provider records.")

(defvar emacsvox-aural-voice-palette-registry
  (make-hash-table :test #'eq)
  "Map voice-palette identifiers to palette records.")

(defconst emacsvox-aural--legacy-cue-definitions
  '((alarm "An urgent alarm")
    (alert-user "Immediate attention is required")
    (ask-question "A question is awaiting an answer")
    (ask-short-question "A short question is awaiting an answer")
    (button "Generic interaction feedback")
    (center "A spatial or directional value is centered")
    (char "A character-level operation occurred")
    (close-object "An object, view, or container was closed")
    (complete "A completion was accepted or completed")
    (delete-object "An object was deleted")
    (deselect-object "A mark or selection was removed")
    (doc "Documentation content was reached")
    (ellipses "Content is hidden, omitted, or abbreviated")
    (fill-object "An object was filled, formatted, or reflowed")
    (help "Help content became available")
    (item "An item or candidate was reached")
    (key "A key or key binding was presented")
    (large-movement "Navigation moved across a structural boundary")
    (left "Movement or placement is toward the left")
    (mark-object "An object was marked or selected")
    (modified-object "An object has unsaved modifications")
    (more "Additional content is available")
    (n-answer "The letter N answer was selected")
    (network-down "Network connectivity became unavailable")
    (network-up "Network connectivity became available")
    (new-mail "New mail arrived or an unread message was reached")
    (news "News or release information became available")
    (no-answer "A negative answer was selected")
    (off "A setting or state was turned off")
    (on "A setting or state was turned on")
    (open-object "An object, view, or container was opened")
    (paragraph "A paragraph boundary or operation was reached")
    (process-active "A process remains active")
    (progress "An operation is making progress")
    (repeat-active "Repeated activity remains active")
    (repeat-end "Repeated activity ended")
    (repeat-start "Repeated activity started")
    (right "Movement or placement is toward the right")
    (save-object "An object was saved")
    (scroll "A view was scrolled")
    (search-hit "A search found a match")
    (search-miss "A search did not find a match")
    (section "A document section was reached")
    (select-object "An object became current or selected")
    (shutdown "A game or activity ended")
    (task-done "A task completed successfully")
    (tick-tick "A short repeated clock tick")
    (time "Time information was presented")
    (tock-tock "A contrasting repeated clock tick")
    (unmodified-object "An object has no unsaved modifications")
    (voice-mail "A voice message arrived or was reached")
    (warn-user "A warning requires attention")
    (window-resize "A window or pane was resized")
    (y-answer "The letter Y answer was selected")
    (yank-object "Content was inserted from saved text")
    (yes-answer "An affirmative answer was selected"))
  "Intent descriptions for the shared legacy cue vocabulary.")

(defconst emacsvox-aural--prompt-cue-definitions
  '((battery-low "Battery charge is low")
    (chime-start "A chime service started")
    (desktop-login "A desktop session login completed")
    (desktop-logout "A desktop session logout completed")
    (dialog-question "A desktop dialog is asking a question")
    (emacspeak "The Emacspeak product identity")
    (launch-wm "A window manager is starting")
    (locking-up "The desktop session is being locked")
    (pwd "A password is requested")
    (resume "The system or session resumed")
    (service-login "A service login completed")
    (service-logout "A service logout completed")
    (startup "Emacsvox is ready or identified")
    (success "An external operation succeeded")
    (tvr-emacs "A personalized Emacs identity prompt")
    (unlocked "The desktop session was unlocked")
    (waking-up "Emacsvox speech is becoming ready"))
  "Intent descriptions for theme-independent prompt cues.")

(defconst emacsvox-aural-legacy-complete-cues
  '(alarm alert-user ask-question ask-short-question button center char
    close-object complete delete-object deselect-object doc ellipses
    fill-object help item key large-movement left mark-object modified-object
    more n-answer network-down network-up new-mail news no-answer off on
    open-object paragraph process-active progress repeat-active repeat-end
    repeat-start right save-object scroll search-hit search-miss section
    select-object task-done tick-tick time tock-tock unmodified-object
    voice-mail warn-user window-resize y-answer yank-object yes-answer)
  "The 55 cues shared by the bundled chimes and 3d resource packs.")

(defconst emacsvox-aural-default-voice-entries
  '((animate . voice-animate)
    (animate-extra . voice-animate-extra)
    (animate-medium . voice-animate-medium)
    (annotate . voice-annotate)
    (bolden . voice-bolden)
    (bolden-and-animate . voice-bolden-and-animate)
    (bolden-extra . voice-bolden-extra)
    (bolden-medium . voice-bolden-medium)
    (brighten . voice-brighten)
    (brighten-extra . voice-brighten-extra)
    (brighten-medium . voice-brighten-medium)
    (indent . voice-indent)
    (lighten . voice-lighten)
    (lighten-extra . voice-lighten-extra)
    (lighten-medium . voice-lighten-medium)
    (monotone . voice-monotone)
    (monotone-extra . voice-monotone-extra)
    (monotone-medium . voice-monotone-medium)
    (overlay-0 . voice-overlay-0)
    (overlay-1 . voice-overlay-1)
    (overlay-2 . voice-overlay-2)
    (overlay-3 . voice-overlay-3)
    (smoothen . voice-smoothen)
    (smoothen-extra . voice-smoothen-extra)
    (smoothen-medium . voice-smoothen-medium))
  "The existing ACSS personalities exposed as the default voice palette.")

(defun emacsvox-aural--resource-error (format-string &rest arguments)
  "Signal a resource error described by FORMAT-STRING and ARGUMENTS."
  (signal
   'emacsvox-aural-resource-error
   (list (apply #'format format-string arguments))))

(cl-defun emacsvox-aural-register-cue
    (id &key summary (kind 'cue) fallback (owner 'core))
  "Register cue ID with SUMMARY, KIND, FALLBACK, and OWNER."
  (emacsvox-aural--validate-id id "Cue identifier")
  (emacsvox-aural--validate-summary summary (format "Cue %S" id))
  (unless (memq kind '(cue prompt compatibility))
    (emacsvox-aural--resource-error "Invalid cue kind for %S: %S" id kind))
  (when fallback
    (emacsvox-aural--validate-id fallback (format "Cue fallback for %S" id)))
  (emacsvox-aural--validate-id owner (format "Cue owner for %S" id))
  (when (gethash id emacsvox-aural-cue-registry)
    (emacsvox-aural--resource-error "Cue is already registered: %S" id))
  (let ((record
         (emacsvox-aural--make-cue
          :id id :summary summary :kind kind :fallback fallback :owner owner)))
    (puthash id record emacsvox-aural-cue-registry)
    record))

(cl-defun emacsvox-aural-register-requirement-profile
    (id &key summary cues)
  "Register requirement profile ID containing CUES."
  (emacsvox-aural--validate-id id "Requirement profile identifier")
  (emacsvox-aural--validate-summary
   summary (format "Requirement profile %S" id))
  (unless (and (listp cues) (cl-every #'symbolp cues))
    (emacsvox-aural--resource-error
     "Requirement profile %S cues must be symbols" id))
  (when (gethash id emacsvox-aural-requirement-profile-registry)
    (emacsvox-aural--resource-error
     "Requirement profile is already registered: %S" id))
  (let ((record
         (emacsvox-aural--make-requirement-profile
          :id id :summary summary :cues (delete-dups (copy-sequence cues)))))
    (puthash id record emacsvox-aural-requirement-profile-registry)
    record))

(defun emacsvox-aural--scan-resource-directory (directory)
  "Return a cue-to-file hash table for Ogg files in DIRECTORY."
  (let ((assets (make-hash-table :test #'eq)))
    (when (file-directory-p directory)
      (dolist (file (directory-files directory 'full "\\.ogg\\'"))
        (puthash (intern (file-name-base file)) file assets)))
    assets))

(cl-defun emacsvox-aural-register-resource-pack
    (id &key summary (kind 'sound) directory parent profiles
        (default-spatialization 'neutral))
  "Register resource pack ID rooted at DIRECTORY."
  (emacsvox-aural--validate-id id "Resource pack identifier")
  (emacsvox-aural--validate-summary summary (format "Resource pack %S" id))
  (unless (memq kind '(sound prompt))
    (emacsvox-aural--resource-error
     "Invalid resource pack kind for %S: %S" id kind))
  (unless (stringp directory)
    (emacsvox-aural--resource-error
     "Resource pack %S directory must be a string" id))
  (when parent
    (emacsvox-aural--validate-id parent (format "Parent pack for %S" id)))
  (unless (and (listp profiles) (cl-every #'symbolp profiles))
    (emacsvox-aural--resource-error
     "Resource pack %S profiles must be symbols" id))
  (unless (memq default-spatialization '(neutral stereo pre-spatialized))
    (emacsvox-aural--resource-error
     "Invalid default spatialization for %S: %S"
     id default-spatialization))
  (when (gethash id emacsvox-aural-resource-pack-registry)
    (emacsvox-aural--resource-error
     "Resource pack is already registered: %S" id))
  (let ((record
         (emacsvox-aural--make-resource-pack
          :id id
          :summary summary
          :kind kind
          :directory (expand-file-name directory)
          :parent parent
          :profiles (delete-dups (copy-sequence profiles))
          :default-spatialization default-spatialization
          :assets (emacsvox-aural--scan-resource-directory directory))))
    (puthash id record emacsvox-aural-resource-pack-registry)
    record))

(cl-defun emacsvox-aural-register-voice-palette
    (id &key summary parent entries)
  "Register voice palette ID with named personality ENTRIES."
  (emacsvox-aural--validate-id id "Voice palette identifier")
  (emacsvox-aural--validate-summary summary (format "Voice palette %S" id))
  (when parent
    (emacsvox-aural--validate-id parent (format "Parent palette for %S" id)))
  (unless
      (and
       (listp entries)
       (cl-every
        (lambda (entry)
          (and
           (consp entry)
           (symbolp (car entry))
           (symbolp (cdr entry))))
        entries))
    (emacsvox-aural--resource-error
     "Voice palette %S entries must map symbols to personalities" id))
  (when (gethash id emacsvox-aural-voice-palette-registry)
    (emacsvox-aural--resource-error
     "Voice palette is already registered: %S" id))
  (let ((names (mapcar #'car entries)))
    (unless (= (length names) (length (delete-dups (copy-sequence names))))
      (emacsvox-aural--resource-error
       "Voice palette %S contains duplicate names" id)))
  (let ((record
         (emacsvox-aural--make-voice-palette
          :id id
          :summary summary
          :parent parent
          :entries (copy-tree entries))))
    (puthash id record emacsvox-aural-voice-palette-registry)
    record))

(defun emacsvox-aural-cue (id)
  "Return registered cue ID, or nil."
  (gethash id emacsvox-aural-cue-registry))

(defun emacsvox-aural-requirement-profile (id)
  "Return registered requirement profile ID, or nil."
  (gethash id emacsvox-aural-requirement-profile-registry))

(defun emacsvox-aural-resource-pack (id)
  "Return registered resource pack ID, or nil."
  (gethash id emacsvox-aural-resource-pack-registry))

(defun emacsvox-aural-voice-palette (id)
  "Return registered voice palette ID, or nil."
  (gethash id emacsvox-aural-voice-palette-registry))

(defun emacsvox-aural-resource-pack-candidates (&optional kind)
  "Return registered pack identifiers as strings, optionally limited to KIND."
  (let (ids)
    (maphash
     (lambda (id pack)
       (when (or (null kind) (eq kind (emacsvox-aural-resource-pack-kind pack)))
         (push (symbol-name id) ids)))
     emacsvox-aural-resource-pack-registry)
    (sort ids #'string-lessp)))

(defun emacsvox-aural-refresh-resource-pack (id)
  "Rescan registered resource pack ID and return it."
  (let ((pack (emacsvox-aural-resource-pack id)))
    (unless pack
      (emacsvox-aural--resource-error "Unknown resource pack: %S" id))
    (setf
     (emacsvox-aural-resource-pack-assets pack)
     (emacsvox-aural--scan-resource-directory
      (emacsvox-aural-resource-pack-directory pack)))
    pack))

(defun emacsvox-aural--effective-pack-assets (id &optional path)
  "Return inherited assets for pack ID while detecting cycles in PATH."
  (when (memq id path)
    (emacsvox-aural--resource-error
     "Resource pack inheritance cycle: %S" (nreverse (cons id path))))
  (let ((pack (emacsvox-aural-resource-pack id)))
    (unless pack
      (emacsvox-aural--resource-error "Unknown resource pack: %S" id))
    (let ((assets
           (if-let* ((parent (emacsvox-aural-resource-pack-parent pack)))
               (emacsvox-aural--effective-pack-assets parent (cons id path))
             (make-hash-table :test #'eq))))
      (maphash
       (lambda (cue file) (puthash cue file assets))
       (emacsvox-aural-resource-pack-assets pack))
      assets)))

(defun emacsvox-aural-effective-assets (pack-id &optional include-prompts)
  "Return effective assets for PACK-ID, optionally overlaying it on prompts."
  (let ((assets
         (if (and include-prompts
                  (not (eq pack-id 'prompts))
                  (emacsvox-aural-resource-pack 'prompts))
             (emacsvox-aural--effective-pack-assets 'prompts)
           (make-hash-table :test #'eq))))
    (maphash
     (lambda (cue file) (puthash cue file assets))
     (emacsvox-aural--effective-pack-assets pack-id))
    assets))

(defun emacsvox-aural--resolve-cue-in-assets (cue assets &optional path)
  "Resolve CUE through ASSETS and registered fallback, detecting PATH cycles."
  (when (memq cue path)
    (emacsvox-aural--resource-error
     "Cue fallback cycle: %S" (nreverse (cons cue path))))
  (or
   (gethash cue assets)
   (when-let* ((record (emacsvox-aural-cue cue))
               (fallback (emacsvox-aural-cue-fallback record)))
     (emacsvox-aural--resolve-cue-in-assets
      fallback assets (cons cue path)))))

(defun emacsvox-aural-resolve-cue (cue pack-id &optional include-prompts)
  "Resolve CUE to a file from PACK-ID and optional prompt resources."
  (emacsvox-aural--resolve-cue-in-assets
   cue (emacsvox-aural-effective-assets pack-id include-prompts)))

(defun emacsvox-aural--pack-profile-cues (pack)
  "Return declared requirement cues for PACK."
  (let (cues)
    (dolist (id (emacsvox-aural-resource-pack-profiles pack))
      (let ((profile (emacsvox-aural-requirement-profile id)))
        (unless profile
          (emacsvox-aural--resource-error
           "Pack %S names unknown requirement profile %S"
           (emacsvox-aural-resource-pack-id pack) id))
        (setq
         cues
         (append
          (emacsvox-aural-requirement-profile-cues profile)
          cues))))
    (delete-dups cues)))

(defun emacsvox-aural-validate-resource-pack (id &optional extra-required)
  "Return a validation report for pack ID and EXTRA-REQUIRED cues."
  (let* ((pack (emacsvox-aural-resource-pack id))
         (_
          (unless pack
            (emacsvox-aural--resource-error "Unknown resource pack: %S" id)))
         (directory (emacsvox-aural-resource-pack-directory pack))
         (missing-directory (not (file-directory-p directory)))
         (assets (emacsvox-aural--effective-pack-assets id))
         (required
          (delete-dups
           (append
            (when (eq (emacsvox-aural-resource-pack-kind pack) 'sound)
              '(button))
            (emacsvox-aural--pack-profile-cues pack)
            (copy-sequence extra-required))))
         missing
         unknown)
    (dolist (cue required)
      (unless (emacsvox-aural--resolve-cue-in-assets cue assets)
        (push cue missing)))
    (maphash
     (lambda (cue _)
       (unless (emacsvox-aural-cue cue)
         (push cue unknown)))
     assets)
    (setq missing
          (sort (delete-dups missing)
                (lambda (left right)
                  (string-lessp (symbol-name left) (symbol-name right)))))
    (setq unknown
          (sort (delete-dups unknown)
                (lambda (left right)
                  (string-lessp (symbol-name left) (symbol-name right)))))
    (emacsvox-aural--make-resource-report
     :pack id
     :valid (not (or missing-directory missing unknown))
     :missing-required missing
     :unknown-assets unknown
     :missing-directory missing-directory)))

(defun emacsvox-aural-scheme-required-cues (scheme)
  "Return unique cue identifiers referenced by compiled SCHEME."
  (let (cues)
    (dolist (rule (emacsvox-aural-scheme-rules scheme))
      (let ((contribution (emacsvox-aural-rule-contribution rule)))
        (dolist
            (operations
             (list
              (emacsvox-aural-contribution-before contribution)
              (emacsvox-aural-contribution-after contribution)))
          (dolist
              (action
               (append
                (emacsvox-aural-phase-operations-replace operations)
                (emacsvox-aural-phase-operations-prepend operations)
                (emacsvox-aural-phase-operations-append operations)))
            (when (eq (emacsvox-aural-action-kind action) 'cue)
              (push (emacsvox-aural-action-cue action) cues))))))
    (sort
     (delete-dups cues)
     (lambda (left right)
       (string-lessp (symbol-name left) (symbol-name right))))))

(defun emacsvox-aural-validate-scheme-resources (scheme pack-id)
  "Validate that PACK-ID can resolve every cue used by compiled SCHEME."
  (emacsvox-aural-validate-resource-pack
   pack-id (emacsvox-aural-scheme-required-cues scheme)))

(defun emacsvox-aural-effective-voice-entries (palette-id &optional path)
  "Return inherited voice entries for PALETTE-ID, detecting cycles in PATH."
  (when (memq palette-id path)
    (emacsvox-aural--resource-error
     "Voice palette inheritance cycle: %S"
     (nreverse (cons palette-id path))))
  (let ((palette (emacsvox-aural-voice-palette palette-id)))
    (unless palette
      (emacsvox-aural--resource-error
       "Unknown voice palette: %S" palette-id))
    (let ((entries
           (if-let* ((parent (emacsvox-aural-voice-palette-parent palette)))
               (emacsvox-aural-effective-voice-entries
                parent (cons palette-id path))
             nil)))
      (dolist (entry (emacsvox-aural-voice-palette-entries palette))
        (setf (alist-get (car entry) entries) (cdr entry)))
      entries)))

(defun emacsvox-aural-voice (name &optional palette-id)
  "Return the personality for NAME in PALETTE-ID or the default palette."
  (alist-get
   name
   (emacsvox-aural-effective-voice-entries
    (or palette-id 'acss-default))))

(defun emacsvox-aural-validate-voice-palette (&optional palette-id)
  "Return unbound personalities in PALETTE-ID or the default palette."
  (let (missing)
    (dolist
        (entry
         (emacsvox-aural-effective-voice-entries
          (or palette-id 'acss-default)))
      (unless (boundp (cdr entry))
        (push (cdr entry) missing)))
    (sort
     (delete-dups missing)
     (lambda (left right)
       (string-lessp (symbol-name left) (symbol-name right))))))

(defun emacsvox-aural-validate-resource-registry ()
  "Validate cue, profile, pack, and voice-palette cross-references."
  (maphash
   (lambda (id _cue)
     (let ((current id)
           path)
       (while current
         (when (memq current path)
           (emacsvox-aural--resource-error
            "Cue fallback cycle: %S" (nreverse (cons current path))))
         (push current path)
         (let ((record (emacsvox-aural-cue current)))
           (unless record
             (emacsvox-aural--resource-error
              "Unknown cue fallback in path: %S" (nreverse path)))
           (setq current (emacsvox-aural-cue-fallback record))))))
   emacsvox-aural-cue-registry)
  (maphash
   (lambda (id profile)
     (dolist (cue (emacsvox-aural-requirement-profile-cues profile))
       (unless (emacsvox-aural-cue cue)
         (emacsvox-aural--resource-error
          "Requirement profile %S names unknown cue %S" id cue))))
   emacsvox-aural-requirement-profile-registry)
  (maphash
   (lambda (id pack)
     (emacsvox-aural--pack-profile-cues pack)
     (when-let* ((parent (emacsvox-aural-resource-pack-parent pack)))
       (unless (emacsvox-aural-resource-pack parent)
         (emacsvox-aural--resource-error
          "Resource pack %S names unknown parent %S" id parent)))
     (emacsvox-aural--effective-pack-assets id))
   emacsvox-aural-resource-pack-registry)
  (maphash
   (lambda (id palette)
     (when-let* ((parent (emacsvox-aural-voice-palette-parent palette)))
       (unless (emacsvox-aural-voice-palette parent)
         (emacsvox-aural--resource-error
          "Voice palette %S names unknown parent %S" id parent)))
     (emacsvox-aural-effective-voice-entries id))
   emacsvox-aural-voice-palette-registry)
  t)

(defun emacsvox-aural--register-resource-vocabulary ()
  "Register bundled cue vocabulary, profiles, and default voice palette."
  (dolist (definition emacsvox-aural--legacy-cue-definitions)
    (unless (emacsvox-aural-cue (car definition))
      (emacsvox-aural-register-cue
       (car definition) :summary (cadr definition))))
  (dolist (definition emacsvox-aural--prompt-cue-definitions)
    (unless (emacsvox-aural-cue (car definition))
      (emacsvox-aural-register-cue
       (car definition) :summary (cadr definition) :kind 'prompt)))
  (dolist
      (definition
       '((emacsvox "Legacy Emacsvox identity cue" startup)
         (repeat-stop "Legacy repeated-activity completion cue" repeat-end)
         (unmark-object "Legacy cleared-selection cue" deselect-object)))
    (unless (emacsvox-aural-cue (car definition))
      (emacsvox-aural-register-cue
       (car definition)
       :summary (cadr definition)
       :kind 'compatibility
       :fallback (caddr definition))))
  (let ((shutdown (emacsvox-aural-cue 'shutdown)))
    (when shutdown
      (setf (emacsvox-aural-cue-fallback shutdown) 'close-object)))
  (unless (emacsvox-aural-requirement-profile 'legacy-complete)
    (emacsvox-aural-register-requirement-profile
     'legacy-complete
     :summary "The 55 cues shared by the bundled legacy sound themes"
     :cues emacsvox-aural-legacy-complete-cues))
  (unless (emacsvox-aural-voice-palette 'acss-default)
    (emacsvox-aural-register-voice-palette
     'acss-default
     :summary "Existing device-independent ACSS personalities"
     :entries emacsvox-aural-default-voice-entries)))

(defun emacsvox-aural-register-bundled-resources (sounds-directory)
  "Register bundled packs below SOUNDS-DIRECTORY."
  (dolist
      (definition
       `((prompts "Theme-independent prompts" prompt "prompts" nil neutral)
         (chimes "Short chime-based auditory cues" sound "chimes"
                 (legacy-complete) neutral)
         (3d "HRTF-generated spatial auditory cues" sound "3d"
             (legacy-complete) pre-spatialized)))
    (let ((id (nth 0 definition)))
      (unless (emacsvox-aural-resource-pack id)
        (emacsvox-aural-register-resource-pack
         id
         :summary (nth 1 definition)
         :kind (nth 2 definition)
         :directory (expand-file-name (nth 3 definition) sounds-directory)
         :profiles (nth 4 definition)
         :default-spatialization (nth 5 definition)))))
  (emacsvox-aural-validate-resource-registry))

(emacsvox-aural--register-resource-vocabulary)

(provide 'emacsvox-aural-resources)
;;; emacsvox-aural-resources.el ends here
