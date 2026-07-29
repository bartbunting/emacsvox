;;; emacsvox-aural-resources.el --- Aural resource providers -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Register semantic cue and tone names, sound resource packs, module resource
;; overlays, requirement profiles, and device-independent voice palettes.
;; Resource resolution remains independent of local-player and speech-server
;; protocols.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'emacsvox-aural)
(require 'emacsvox-aural-rules)

(defvar read-eval)

(define-error
  'emacsvox-aural-resource-error
  "Invalid Emacsvox aural resource provider")

(defun emacsvox-aural--resource-error (format-string &rest arguments)
  "Signal a resource error described by FORMAT-STRING and ARGUMENTS."
  (signal
   'emacsvox-aural-resource-error
   (list (apply #'format format-string arguments))))

(cl-defstruct
    (emacsvox-aural-cue
     (:constructor emacsvox-aural--make-cue))
  "A named non-speech presentation cue."
  id summary kind fallback owner)

(cl-defstruct
    (emacsvox-aural-tone
     (:constructor emacsvox-aural--make-tone))
  "A named speech-server tone."
  id summary pitch duration force owner)

(cl-defstruct
    (emacsvox-aural-requirement-profile
     (:constructor emacsvox-aural--make-requirement-profile))
  "A named cue-coverage contract."
  id summary cues)

(cl-defstruct
    (emacsvox-aural-resource-pack
     (:constructor emacsvox-aural--make-resource-pack))
  "A concrete sound resource provider."
  id summary kind directory parent profiles default-spatialization assets
  origin)

(cl-defstruct
    (emacsvox-aural-resource-overlay
     (:constructor emacsvox-aural--make-resource-overlay))
  "Module-owned default assets and per-pack themed overrides."
  id summary owner directory default-spatialization assets
  pack-assets pack-unknown-assets)

(cl-defstruct
    (emacsvox-aural-resource-report
     (:constructor emacsvox-aural--make-resource-report))
  "Validation result for one resource pack."
  pack valid missing-required unknown-assets missing-directory)

(cl-defstruct
    (emacsvox-aural-voice-palette
     (:constructor emacsvox-aural--make-voice-palette))
  "A named collection of complete device-independent voice presets."
  id summary parent entries built-in source data)

(defvar emacsvox-aural-cue-registry (make-hash-table :test #'eq)
  "Map cue identifiers to `emacsvox-aural-cue' records.")

(defvar emacsvox-aural-tone-registry (make-hash-table :test #'eq)
  "Map tone identifiers to `emacsvox-aural-tone' records.")

(defvar emacsvox-aural-requirement-profile-registry
  (make-hash-table :test #'eq)
  "Map profile identifiers to cue requirement profiles.")

(defvar emacsvox-aural-resource-pack-registry
  (make-hash-table :test #'eq)
  "Map resource-pack identifiers to provider records.")

(defvar emacsvox-aural-resource-overlay-registry
  (make-hash-table :test #'eq)
  "Map module resource-overlay identifiers to provider records.")

(defvar emacsvox-aural-resource-packs-changed-hook nil
  "Abnormal hook run after resource-pack registration or refresh.

Each function receives the affected pack identifier, or nil for a discovery
refresh that may affect several packs.")

(defvar emacsvox-aural--defer-resource-pack-notifications nil
  "Non-nil while a resource-pack transaction is staging registry changes.")

(defvar emacsvox-aural--resource-pack-notification-pending nil
  "Non-nil when a deferred resource-pack transaction changed the registry.")

(defvar emacsvox-aural-resource-generation 0
  "Generation of the registered resource packs and enabled overlays.")

(defvar emacsvox-aural--effective-assets-cache
  (make-hash-table :test #'equal)
  "Effective asset tables keyed by resource generation and pack selection.")

(defvar emacsvox-aural--resource-spatialization-cache
  (make-hash-table :test #'equal)
  "Resolved resource ownership keyed by generation and lookup inputs.")

(defun emacsvox-aural--invalidate-resource-caches ()
  "Advance the resource generation and clear derived resource indexes."
  (cl-incf emacsvox-aural-resource-generation)
  (clrhash emacsvox-aural--effective-assets-cache)
  (clrhash emacsvox-aural--resource-spatialization-cache))

(defun emacsvox-aural--resource-packs-changed (&optional id)
  "Notify resource consumers that pack ID changed.

During discovery transactions, retain one pending notification until the
complete replacement registry has validated successfully."
  (emacsvox-aural--invalidate-resource-caches)
  (if emacsvox-aural--defer-resource-pack-notifications
      (setq emacsvox-aural--resource-pack-notification-pending t)
    (run-hook-with-args 'emacsvox-aural-resource-packs-changed-hook id)))

(defvar emacsvox-aural-resource-overlays-changed-hook nil
  "Abnormal hook run after module resource-overlay state changes.

Each function receives the affected overlay identifier, or nil when the
enabled overlay set changed.")

(defvar emacsvox-aural-resource-pack-discovery-roots nil
  "Sound-pack discovery roots in descending precedence order.")

(defvar emacsvox-aural--resource-pack-discovery-registry
  emacsvox-aural-resource-pack-registry
  "Registry associated with `emacsvox-aural-resource-pack-discovery-roots'.")

(defun emacsvox-aural--custom-set-personal-sound-packs-directory
    (symbol value)
  "Set personal sound-pack directory SYMBOL to VALUE."
  (unless (or (null value) (stringp value))
    (emacsvox-aural--resource-error
     "Personal sound-pack directory must be nil or a string: %S" value))
  (let ((old
         (and
          (boundp symbol)
          (stringp (default-value symbol))
          (file-name-as-directory
           (expand-file-name (default-value symbol)))))
        (normalized
         (and value (file-name-as-directory (expand-file-name value)))))
    (set-default symbol normalized)
    (unless (equal old normalized)
      (when old
        (when
            (fboundp
             'emacsvox-aural--remove-discovered-resource-packs-below-root)
          (emacsvox-aural--remove-discovered-resource-packs-below-root old))
        (setq
         emacsvox-aural-resource-pack-discovery-roots
         (delete old emacsvox-aural-resource-pack-discovery-roots)))
      (when normalized
        (push normalized emacsvox-aural-resource-pack-discovery-roots))
      (when
          (and
           (fboundp 'emacsvox-aural-refresh-discovered-resource-packs)
           (eq
            emacsvox-aural-resource-pack-registry
            emacsvox-aural--resource-pack-discovery-registry))
        (emacsvox-aural-refresh-discovered-resource-packs)))))

(defcustom emacsvox-aural-personal-sound-packs-directory
  (expand-file-name "~/.emacsvox/sounds/packs/")
  "Directory containing personal sound packs.

Each immediate child is a candidate pack.  Set this to nil to disable the
standard personal discovery root.  The directory need not exist."
  :type '(choice
          (const :tag "Disable standard personal sound packs" nil)
          directory)
  :set #'emacsvox-aural--custom-set-personal-sound-packs-directory
  :group 'emacsvox-aural)

(defvar emacsvox-aural-voice-palette-registry
  (make-hash-table :test #'eq)
  "Map voice-palette identifiers to palette records.")

(defconst emacsvox-aural-voice-palette-schema-version 1
  "Current safe data schema for personal voice palettes.")

(defconst emacsvox-aural-resource-pack-manifest
  "emacsvox-sound-pack.el"
  "Optional data-only manifest filename for a discovered sound pack.")

(defconst emacsvox-aural-resource-pack-manifest-schema-version 1
  "Current schema version for sound-pack manifests.")

(defvar emacsvox-aural-disabled-resource-overlays nil)

(defun emacsvox-aural--validate-disabled-resource-overlays (ids)
  "Validate disabled resource-overlay IDS and return a copy."
  (unless (and (listp ids) (cl-every #'symbolp ids))
    (emacsvox-aural--resource-error
     "Disabled resource overlays must be a list of symbols: %S" ids))
  (unless (= (length ids) (length (delete-dups (copy-sequence ids))))
    (emacsvox-aural--resource-error
     "A resource overlay is disabled more than once: %S" ids))
  (copy-sequence ids))

(defun emacsvox-aural--resource-overlays-changed (&optional id)
  "Notify resource consumers that overlay ID or enablement changed."
  (emacsvox-aural--invalidate-resource-caches)
  (run-hook-with-args 'emacsvox-aural-resource-overlays-changed-hook id)
  (when (fboundp 'emacsvox-aural-configuration-changed)
    (emacsvox-aural-configuration-changed 'resource-overlays)))

(defun emacsvox-aural-set-disabled-resource-overlays (ids)
  "Disable module resource overlays named by IDS.

An unavailable identifier may be named before its package is loaded."
  (setq
   emacsvox-aural-disabled-resource-overlays
   (emacsvox-aural--validate-disabled-resource-overlays ids))
  (emacsvox-aural--resource-overlays-changed)
  emacsvox-aural-disabled-resource-overlays)

(defun emacsvox-aural--custom-set-disabled-resource-overlays (symbol value)
  "Set disabled resource overlays in SYMBOL to VALUE."
  (let* ((validated
          (emacsvox-aural--validate-disabled-resource-overlays value))
         (changed
          (not (equal (default-value symbol) validated))))
    (set-default symbol validated)
    (when changed
      (emacsvox-aural--resource-overlays-changed))))

(defcustom emacsvox-aural-disabled-resource-overlays nil
  "Module resource overlays that should use their generic cue fallbacks.

Disabling an overlay suppresses both its packaged defaults and matching
themed overrides below an active sound pack."
  :type '(repeat symbol)
  :set #'emacsvox-aural--custom-set-disabled-resource-overlays
  :group 'emacsvox-aural)

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

(defconst emacsvox-aural-default-tone-definitions
  '((buffer-modified
     "A buffer has unsaved modifications"
     700 100 nil)
    (buffer-read-only
     "A buffer is read-only"
     250 100 nil)
    (edit-deletion
     "Text was deleted"
     500 75 t)
    (edit-line-created
     "A new line was created"
     225 75 t)
    (edit-lowercase
     "Text was changed to lowercase"
     600 100 t)
    (edit-uppercase
     "Text was changed to uppercase or capitalized"
     800 100 t)
    (field-empty
     "A structured field contains no text"
     261.6 150 t)
    (line-empty
     "An empty display line was reached"
     130.8 150 t)
    (line-whitespace
     "A display line containing only whitespace was reached"
     261.6 150 t)
    (line-separator
     "A horizontal separator line was reached"
     523.3 150 t)
    (line-decoration
     "A decorative punctuation line was reached"
     1047 150 t)
    (line-unspeakable
     "A nonempty line with no speakable content was reached"
     2093 150 t))
  "Built-in tones matching established nonverbal presentation signals.")

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

(cl-defun emacsvox-aural-register-tone
    (id &key summary pitch duration force (owner 'core))
  "Register tone ID with SUMMARY, PITCH, DURATION, FORCE, and OWNER.

PITCH is measured in hertz and DURATION in milliseconds.  Non-nil FORCE
requests immediate protocol dispatch after the tone."
  (emacsvox-aural--validate-id id "Tone identifier")
  (emacsvox-aural--validate-summary summary (format "Tone %S" id))
  (unless (and (numberp pitch) (> pitch 0))
    (emacsvox-aural--resource-error
     "Tone %S pitch must be a positive number: %S" id pitch))
  (unless (and (numberp duration) (>= duration 0))
    (emacsvox-aural--resource-error
     "Tone %S duration must be nonnegative: %S" id duration))
  (unless (booleanp force)
    (emacsvox-aural--resource-error
     "Tone %S force must be boolean: %S" id force))
  (emacsvox-aural--validate-id owner (format "Tone owner for %S" id))
  (when (gethash id emacsvox-aural-tone-registry)
    (emacsvox-aural--resource-error "Tone is already registered: %S" id))
  (let ((record
         (emacsvox-aural--make-tone
          :id id
          :summary summary
          :pitch pitch
          :duration duration
          :force force
          :owner owner)))
    (puthash id record emacsvox-aural-tone-registry)
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
        (default-spatialization 'neutral) (origin 'explicit))
  "Register resource pack ID with SUMMARY rooted at DIRECTORY.

KIND is `sound' or `prompt'.  PARENT supplies inherited assets, PROFILES name
coverage contracts, and DEFAULT-SPATIALIZATION describes the concrete assets.
ORIGIN is `explicit' for declared providers and `discovered' for synchronized
sound directories."
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
  (unless (memq origin '(explicit discovered))
    (emacsvox-aural--resource-error
     "Invalid registration origin for %S: %S" id origin))
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
          :assets (emacsvox-aural--scan-resource-directory directory)
          :origin origin)))
    (puthash id record emacsvox-aural-resource-pack-registry)
    (maphash
     (lambda (_ overlay)
       (emacsvox-aural--refresh-resource-overlay-pack overlay id))
     emacsvox-aural-resource-overlay-registry)
    (emacsvox-aural--resource-packs-changed id)
    record))

(defun emacsvox-aural-resource-overlay (id)
  "Return registered module resource overlay ID, or nil."
  (gethash id emacsvox-aural-resource-overlay-registry))

(defun emacsvox-aural-resource-overlay-enabled-p (id)
  "Return non-nil when registered resource overlay ID is enabled."
  (and
   (emacsvox-aural-resource-overlay id)
   (not (memq id emacsvox-aural-disabled-resource-overlays))))

(defun emacsvox-aural--scan-owned-cue-directory (directory owner)
  "Return (ASSETS . UNKNOWN) for Ogg files in DIRECTORY owned by OWNER."
  (let ((assets (make-hash-table :test #'eq))
        unknown)
    (when (file-directory-p directory)
      (dolist (file (directory-files directory 'full "\\.ogg\\'"))
        (when (file-regular-p file)
          (let* ((cue (intern (file-name-base file)))
                 (record (emacsvox-aural-cue cue)))
            (if (and record (eq owner (emacsvox-aural-cue-owner record)))
                (puthash cue file assets)
              (push cue unknown))))))
    (cons
     assets
     (sort
      (delete-dups unknown)
      (lambda (left right)
        (string-lessp (symbol-name left) (symbol-name right)))))))

(defun emacsvox-aural--refresh-resource-overlay-pack (overlay pack-id)
  "Refresh themed assets for resource OVERLAY below sound pack PACK-ID."
  (let ((pack (emacsvox-aural-resource-pack pack-id)))
    (if (and pack (eq (emacsvox-aural-resource-pack-kind pack) 'sound))
        (pcase-let*
            ((directory
              (expand-file-name
               (symbol-name (emacsvox-aural-resource-overlay-owner overlay))
               (emacsvox-aural-resource-pack-directory pack)))
             (`(,assets . ,unknown)
              (emacsvox-aural--scan-owned-cue-directory
               directory
               (emacsvox-aural-resource-overlay-owner overlay))))
          (puthash
           pack-id assets
           (emacsvox-aural-resource-overlay-pack-assets overlay))
          (puthash
           pack-id unknown
           (emacsvox-aural-resource-overlay-pack-unknown-assets overlay)))
      (remhash
       pack-id (emacsvox-aural-resource-overlay-pack-assets overlay))
      (remhash
       pack-id
       (emacsvox-aural-resource-overlay-pack-unknown-assets overlay))))
  overlay)

(defun emacsvox-aural--refresh-all-resource-overlay-packs ()
  "Refresh every registered overlay against the current sound-pack registry."
  (maphash
   (lambda (_id overlay)
     (clrhash (emacsvox-aural-resource-overlay-pack-assets overlay))
     (clrhash (emacsvox-aural-resource-overlay-pack-unknown-assets overlay))
     (maphash
      (lambda (pack-id _pack)
        (emacsvox-aural--refresh-resource-overlay-pack overlay pack-id))
      emacsvox-aural-resource-pack-registry))
   emacsvox-aural-resource-overlay-registry))

(cl-defun emacsvox-aural-register-resource-overlay
    (id &key summary owner directory (default-spatialization 'neutral))
  "Register module resource overlay ID rooted at DIRECTORY.

SUMMARY describes the overlay.  OWNER names the module that owns every cue
file in DIRECTORY.  An active sound pack may override these defaults below
its OWNER-named subdirectory.  DEFAULT-SPATIALIZATION describes the packaged
default assets."
  (emacsvox-aural--validate-id id "Resource overlay identifier")
  (emacsvox-aural--validate-summary summary (format "Resource overlay %S" id))
  (emacsvox-aural--validate-id owner (format "Owner for overlay %S" id))
  (unless (stringp directory)
    (emacsvox-aural--resource-error
     "Resource overlay %S directory must be a string" id))
  (unless (file-directory-p directory)
    (emacsvox-aural--resource-error
     "Resource overlay %S directory does not exist: %s" id directory))
  (unless (memq default-spatialization '(neutral stereo pre-spatialized))
    (emacsvox-aural--resource-error
     "Invalid default spatialization for overlay %S: %S"
     id default-spatialization))
  (when (emacsvox-aural-resource-overlay id)
    (emacsvox-aural--resource-error
     "Resource overlay is already registered: %S" id))
  (maphash
   (lambda (other-id overlay)
     (when (eq owner (emacsvox-aural-resource-overlay-owner overlay))
       (emacsvox-aural--resource-error
        "Resource overlay owner %S is already provided by %S"
        owner other-id)))
   emacsvox-aural-resource-overlay-registry)
  (pcase-let*
      ((expanded (expand-file-name directory))
       (`(,assets . ,unknown)
        (emacsvox-aural--scan-owned-cue-directory expanded owner)))
    (when unknown
      (emacsvox-aural--resource-error
       "Resource overlay %S contains unknown or foreign cues: %S"
       id unknown))
    (let ((overlay
           (emacsvox-aural--make-resource-overlay
            :id id
            :summary summary
            :owner owner
            :directory expanded
            :default-spatialization default-spatialization
            :assets assets
            :pack-assets (make-hash-table :test #'eq)
            :pack-unknown-assets (make-hash-table :test #'eq))))
      (maphash
       (lambda (pack-id _pack)
         (emacsvox-aural--refresh-resource-overlay-pack overlay pack-id))
       emacsvox-aural-resource-pack-registry)
      (puthash id overlay emacsvox-aural-resource-overlay-registry)
      (emacsvox-aural--resource-overlays-changed id)
      overlay)))

(defun emacsvox-aural-refresh-resource-overlay (id)
  "Rescan registered module resource overlay ID and themed overrides."
  (let ((overlay (emacsvox-aural-resource-overlay id)))
    (unless overlay
      (emacsvox-aural--resource-error "Unknown resource overlay: %S" id))
    (unless
        (file-directory-p
         (emacsvox-aural-resource-overlay-directory overlay))
      (emacsvox-aural--resource-error
       "Resource overlay %S directory does not exist: %s"
       id (emacsvox-aural-resource-overlay-directory overlay)))
    (pcase-let
        ((`(,assets . ,unknown)
          (emacsvox-aural--scan-owned-cue-directory
           (emacsvox-aural-resource-overlay-directory overlay)
           (emacsvox-aural-resource-overlay-owner overlay))))
      (when unknown
        (emacsvox-aural--resource-error
         "Resource overlay %S contains unknown or foreign cues: %S"
         id unknown))
      (setf (emacsvox-aural-resource-overlay-assets overlay) assets))
    (clrhash (emacsvox-aural-resource-overlay-pack-assets overlay))
    (clrhash (emacsvox-aural-resource-overlay-pack-unknown-assets overlay))
    (maphash
     (lambda (pack-id _pack)
       (emacsvox-aural--refresh-resource-overlay-pack overlay pack-id))
     emacsvox-aural-resource-pack-registry)
    (emacsvox-aural--resource-overlays-changed id)
    overlay))

(defun emacsvox-aural--complete-voice-style-p (value)
  "Return non-nil when VALUE is a complete explicit ACSS preset."
  (and
   (emacsvox-aural-voice-style-p value)
   (not (plist-member value :preset))
   (cl-every
    (lambda (dimension)
      (plist-member
       value (emacsvox-aural--voice-dimension-key dimension)))
    emacsvox-aural-voice-dimensions)))

(defun emacsvox-aural--validate-palette-entry (entry palette-id)
  "Validate voice palette ENTRY belonging to PALETTE-ID."
  (unless
      (and
       (consp entry)
       (symbolp (car entry))
       (car entry)
       (not (keywordp (car entry))))
    (emacsvox-aural--resource-error
     "Voice palette %S contains an invalid entry name: %S"
     palette-id entry))
  (let ((definition (cdr entry)))
    (cond
     ((and
       (symbolp definition)
       definition
       (not (keywordp definition))))
     ((emacsvox-aural--complete-voice-style-p definition)
      (condition-case error
          (emacsvox-aural-validate-voice-value
           definition
           (format "Voice %S in palette %S" (car entry) palette-id))
        (emacsvox-aural-rule-error
         (emacsvox-aural--resource-error
          "%s" (error-message-string error)))))
     (t
      (emacsvox-aural--resource-error
       (concat
        "Voice %S in palette %S must be a personality symbol or a complete "
        "ACSS style containing all five dimensions: %S")
       (car entry) palette-id definition))))
  entry)

(cl-defun emacsvox-aural-register-voice-palette
    (id &key summary parent entries built-in source data)
  "Register voice palette ID with complete named ENTRIES.

Each entry maps a name to either an existing personality symbol or a complete
explicit ACSS style.  BUILT-IN, SOURCE, and safe declarative DATA are retained
for management and persistence."
  (emacsvox-aural--validate-id id "Voice palette identifier")
  (emacsvox-aural--validate-summary summary (format "Voice palette %S" id))
  (when parent
    (emacsvox-aural--validate-id parent (format "Parent palette for %S" id)))
  (unless
      (and
       (listp entries)
       (cl-every #'consp entries))
    (emacsvox-aural--resource-error
     "Voice palette %S entries must be named pairs" id))
  (dolist (entry entries)
    (emacsvox-aural--validate-palette-entry entry id))
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
          :entries (copy-tree entries)
          :built-in built-in
          :source source
          :data (copy-tree data))))
    (puthash id record emacsvox-aural-voice-palette-registry)
    record))

(defun emacsvox-aural--compile-voice-palette-entry (data palette-id)
  "Compile safe voice entry DATA for PALETTE-ID."
  (unless (and (consp data) (symbolp (car data)))
    (emacsvox-aural--resource-error
     "Voice palette %S entry must start with a symbol: %S" palette-id data))
  (let* ((name (car data))
         (properties (cdr data))
         (allowed '(:personality :style))
         (unknown
          (and
           (emacsvox-aural--plist-p properties)
           (cl-loop
            for (key _) on properties by #'cddr
            unless (memq key allowed)
            collect key))))
    (unless (emacsvox-aural--plist-p properties)
      (emacsvox-aural--resource-error
       "Voice %S in palette %S must use keyword properties"
       name palette-id))
    (when unknown
      (emacsvox-aural--resource-error
       "Unknown properties for voice %S in palette %S: %S"
       name palette-id unknown))
    (when
        (eq
         (and (plist-member properties :personality) t)
         (and (plist-member properties :style) t))
      (emacsvox-aural--resource-error
       "Voice %S in palette %S must have exactly one of :personality or :style"
       name palette-id))
    (let ((definition
           (if (plist-member properties :personality)
               (plist-get properties :personality)
             (copy-tree (plist-get properties :style)))))
      (emacsvox-aural--validate-palette-entry
       (cons name definition) palette-id))))

(defun emacsvox-aural-compile-voice-palette-data
    (data &optional built-in source)
  "Compile safe voice palette DATA without registering it.

BUILT-IN and SOURCE become immutable management metadata on the result."
  (unless (emacsvox-aural--plist-p data)
    (emacsvox-aural--resource-error
     "Voice palette data must be a keyword plist: %S" data))
  (let* ((allowed
          '(:schema-version :id :summary :parent :entries))
         (unknown
          (cl-loop
           for (key _) on data by #'cddr
           unless (memq key allowed)
           collect key))
         (version (plist-get data :schema-version))
         (id (plist-get data :id))
         (summary (plist-get data :summary))
         (parent (plist-get data :parent))
         (raw-entries (plist-get data :entries)))
    (when unknown
      (emacsvox-aural--resource-error
       "Unknown voice palette properties: %S" unknown))
    (unless (eq version emacsvox-aural-voice-palette-schema-version)
      (emacsvox-aural--resource-error
       "Unsupported voice palette schema version: %S" version))
    (emacsvox-aural--validate-id id "Voice palette identifier")
    (emacsvox-aural--validate-summary summary (format "Voice palette %S" id))
    (when parent
      (emacsvox-aural--validate-id parent (format "Parent palette for %S" id)))
    (unless (listp raw-entries)
      (emacsvox-aural--resource-error
       "Voice palette %S entries must be a list" id))
    (let ((entries
           (mapcar
            (lambda (entry)
              (emacsvox-aural--compile-voice-palette-entry entry id))
            raw-entries)))
      (let ((names (mapcar #'car entries)))
        (unless
            (= (length names) (length (delete-dups (copy-sequence names))))
          (emacsvox-aural--resource-error
           "Voice palette %S contains duplicate names" id)))
      (emacsvox-aural--make-voice-palette
       :id id
       :summary summary
       :parent parent
       :entries entries
       :built-in built-in
       :source source
       :data (copy-tree data)))))

(defun emacsvox-aural-register-voice-palette-data
    (data &optional built-in source)
  "Compile and register safe voice palette DATA."
  (let* ((record
          (emacsvox-aural-compile-voice-palette-data
           data built-in source))
         (id (emacsvox-aural-voice-palette-id record)))
    (when (gethash id emacsvox-aural-voice-palette-registry)
      (emacsvox-aural--resource-error
       "Voice palette is already registered: %S" id))
    (puthash id record emacsvox-aural-voice-palette-registry)
    record))

(defun emacsvox-aural-voice-palette-data-form (palette)
  "Return safe persistent data for voice PALETTE."
  (or
   (copy-tree (emacsvox-aural-voice-palette-data palette))
   (list
    :schema-version emacsvox-aural-voice-palette-schema-version
    :id (emacsvox-aural-voice-palette-id palette)
    :summary (emacsvox-aural-voice-palette-summary palette)
    :parent (emacsvox-aural-voice-palette-parent palette)
    :entries
    (mapcar
     (lambda (entry)
       (if (symbolp (cdr entry))
           (list (car entry) :personality (cdr entry))
         (list (car entry) :style (copy-tree (cdr entry)))))
     (emacsvox-aural-voice-palette-entries palette)))))

(defun emacsvox-aural-cue (id)
  "Return registered cue ID, or nil."
  (gethash id emacsvox-aural-cue-registry))

(defun emacsvox-aural-tone (id)
  "Return registered tone ID, or nil."
  (gethash id emacsvox-aural-tone-registry))

(defun emacsvox-aural-tone-candidates ()
  "Return registered tone identifiers as sorted strings."
  (let (ids)
    (maphash
     (lambda (id _) (push (symbol-name id) ids))
     emacsvox-aural-tone-registry)
    (sort ids #'string-lessp)))

(defun emacsvox-aural-requirement-profile (id)
  "Return registered requirement profile ID, or nil."
  (gethash id emacsvox-aural-requirement-profile-registry))

(defun emacsvox-aural-resource-pack (id)
  "Return registered resource pack ID, or nil."
  (gethash id emacsvox-aural-resource-pack-registry))

(defun emacsvox-aural-voice-palette (id)
  "Return registered voice palette ID, or nil."
  (gethash id emacsvox-aural-voice-palette-registry))

(defun emacsvox-aural-voice-palette-candidates ()
  "Return registered voice-palette identifiers as sorted strings."
  (let (ids)
    (maphash
     (lambda (id _) (push (symbol-name id) ids))
     emacsvox-aural-voice-palette-registry)
    (sort ids #'string-lessp)))

(defun emacsvox-aural-resource-pack-candidates (&optional kind)
  "Return registered pack identifiers as strings, optionally limited to KIND."
  (emacsvox-aural-refresh-discovered-resource-packs)
  (let (ids)
    (maphash
     (lambda (id pack)
       (when (or (null kind) (eq kind (emacsvox-aural-resource-pack-kind pack)))
         (push (symbol-name id) ids)))
     emacsvox-aural-resource-pack-registry)
    (sort ids #'string-lessp)))

(defun emacsvox-aural--read-resource-pack-manifest (directory)
  "Read and validate the optional sound-pack manifest in DIRECTORY."
  (let ((file
         (expand-file-name
          emacsvox-aural-resource-pack-manifest directory)))
    (when (file-exists-p file)
      (unless (file-readable-p file)
        (emacsvox-aural--resource-error
         "Sound-pack manifest is not readable: %s" file))
      (with-temp-buffer
        (insert-file-contents file)
        (emacs-lisp-mode)
        (goto-char (point-min))
        (let* ((read-eval nil)
               (data
                (condition-case error
                    (read (current-buffer))
                  (error
                   (emacsvox-aural--resource-error
                    "Could not read sound-pack manifest %s: %s"
                    file (error-message-string error))))))
          (forward-comment (point-max))
          (unless (eobp)
            (emacsvox-aural--resource-error
             "Trailing data in sound-pack manifest: %s" file))
          (unless (emacsvox-aural--plist-p data)
            (emacsvox-aural--resource-error
             "Sound-pack manifest must be a keyword plist: %s" file))
          (cl-loop
           for (key _) on data by #'cddr
           unless
           (memq
            key
            '(:schema-version :summary :parent :profiles
              :default-spatialization))
           do
           (emacsvox-aural--resource-error
            "Unknown sound-pack manifest field %S in %s" key file))
          (unless
              (eq
               (plist-get data :schema-version)
               emacsvox-aural-resource-pack-manifest-schema-version)
            (emacsvox-aural--resource-error
             "Unsupported sound-pack manifest schema in %s: %S"
             file (plist-get data :schema-version)))
          (when (plist-member data :summary)
            (emacsvox-aural--validate-summary
             (plist-get data :summary)
             (format "Sound-pack manifest %s" file)))
          (when-let* ((parent (plist-get data :parent)))
            (emacsvox-aural--validate-id
             parent (format "Sound-pack manifest parent in %s" file)))
          (when (plist-member data :profiles)
            (let ((profiles (plist-get data :profiles)))
              (unless (and (listp profiles) (cl-every #'symbolp profiles))
                (emacsvox-aural--resource-error
                 "Sound-pack manifest profiles must be symbols in %s"
                 file))))
          (when (plist-member data :default-spatialization)
            (unless
                (memq
                 (plist-get data :default-spatialization)
                 '(neutral stereo pre-spatialized))
              (emacsvox-aural--resource-error
               "Invalid sound-pack spatialization in %s: %S"
               file (plist-get data :default-spatialization))))
          data)))))

(defun emacsvox-aural--resource-pack-default-summary (id)
  "Return a human-readable default summary for discovered pack ID."
  (format
   "Automatically discovered %s sound pack"
   (capitalize
    (replace-regexp-in-string "[-_]+" " " (symbol-name id)))))

(defun emacsvox-aural--resource-pack-inferred-profiles (directory)
  "Return requirement profiles directly satisfied by DIRECTORY."
  (let ((assets (emacsvox-aural--scan-resource-directory directory)))
    (when
        (cl-every
         (lambda (cue) (gethash cue assets))
         emacsvox-aural-legacy-complete-cues)
      '(legacy-complete))))

(defun emacsvox-aural--discovered-resource-pack-definition (directory)
  "Return registration arguments for sound pack DIRECTORY, or nil."
  (let* ((manifest-file
          (expand-file-name
           emacsvox-aural-resource-pack-manifest directory))
         (manifest-present (file-exists-p manifest-file))
         (button (expand-file-name "button.ogg" directory)))
    (when (or manifest-present (file-regular-p button))
      (let* ((id (intern (file-name-nondirectory
                          (directory-file-name directory))))
             (manifest
              (and
               manifest-present
               (emacsvox-aural--read-resource-pack-manifest directory)))
             (profiles
              (if (and manifest (plist-member manifest :profiles))
                  (plist-get manifest :profiles)
                (emacsvox-aural--resource-pack-inferred-profiles directory))))
        (list
         id
         :summary
         (or
          (plist-get manifest :summary)
          (emacsvox-aural--resource-pack-default-summary id))
         :directory directory
         :parent (plist-get manifest :parent)
         :profiles profiles
         :default-spatialization
         (or (plist-get manifest :default-spatialization) 'neutral)
         :origin 'discovered)))))

(defun emacsvox-aural--pack-immediately-below-root-p (pack root)
  "Return non-nil when discovered PACK is immediately below ROOT."
  (and
   (eq (emacsvox-aural-resource-pack-origin pack) 'discovered)
   (equal
    (file-name-as-directory
     (file-name-directory
      (directory-file-name
       (emacsvox-aural-resource-pack-directory pack))))
    (file-name-as-directory (expand-file-name root)))))

(defun emacsvox-aural--remove-discovered-resource-packs-below-root (root)
  "Remove dynamically discovered packs immediately below ROOT."
  (let (remove)
    (maphash
     (lambda (id pack)
       (when (emacsvox-aural--pack-immediately-below-root-p pack root)
         (push id remove)))
     emacsvox-aural-resource-pack-registry)
    (dolist (id remove)
      (remhash id emacsvox-aural-resource-pack-registry))
    (when remove
      (emacsvox-aural--refresh-all-resource-overlay-packs)
      (emacsvox-aural--resource-packs-changed))
    remove))

(defun emacsvox-aural--discovery-root-has-precedence-p (root pack)
  "Return non-nil when discovery ROOT has precedence over discovered PACK."
  (let ((candidate
         (cl-position
          (file-name-as-directory (expand-file-name root))
          emacsvox-aural-resource-pack-discovery-roots
          :test #'equal))
        (existing
         (cl-position-if
          (lambda (configured-root)
            (emacsvox-aural--pack-immediately-below-root-p
             pack configured-root))
          emacsvox-aural-resource-pack-discovery-roots)))
    (and candidate existing (< candidate existing))))

(defun emacsvox-aural-discover-resource-packs (sounds-directory)
  "Synchronize dynamically discovered packs below SOUNDS-DIRECTORY.

An immediate child directory is a sound pack when it contains `button.ogg'
or an `emacsvox-sound-pack.el' manifest.  The manifest is read as data with
reader evaluation disabled.  Explicit registrations take precedence over
discovered directories with the same identifier."
  (let* ((root (file-name-as-directory (expand-file-name sounds-directory)))
         (directories
          (when (file-directory-p root)
            (cl-remove-if-not
             #'file-directory-p
             (directory-files
              root 'full directory-files-no-dot-files-regexp))))
         definitions
         desired
         remove
         (emacsvox-aural--defer-resource-pack-notifications t)
         (emacsvox-aural--resource-pack-notification-pending nil))
    (dolist (directory directories)
      (when-let* ((definition
                   (emacsvox-aural--discovered-resource-pack-definition
                    directory)))
        (push definition definitions)
        (push (car definition) desired)))
    (let ((snapshot
           (copy-hash-table emacsvox-aural-resource-pack-registry)))
      (condition-case error
          (progn
            (maphash
             (lambda (id pack)
               (when
                   (and
                    (emacsvox-aural--pack-immediately-below-root-p pack root)
                    (not (memq id desired)))
                 (push id remove)))
             emacsvox-aural-resource-pack-registry)
            (dolist (id remove)
              (remhash id emacsvox-aural-resource-pack-registry))
            (when remove
              (emacsvox-aural--resource-packs-changed))
            (dolist (definition (nreverse definitions))
              (let* ((id (car definition))
                     (existing (emacsvox-aural-resource-pack id)))
                (when
                    (or
                     (null existing)
                     (emacsvox-aural--pack-immediately-below-root-p
                      existing root)
                     (and
                      (eq
                       (emacsvox-aural-resource-pack-origin existing)
                       'discovered)
                      (emacsvox-aural--discovery-root-has-precedence-p
                       root existing)))
                  (when existing
                    (remhash id emacsvox-aural-resource-pack-registry))
                  (apply
                   #'emacsvox-aural-register-resource-pack
                   definition))))
            (emacsvox-aural--refresh-all-resource-overlay-packs)
            (emacsvox-aural-validate-resource-registry))
        (error
         (clrhash emacsvox-aural-resource-pack-registry)
         (maphash
         (lambda (id pack)
            (puthash id pack emacsvox-aural-resource-pack-registry))
          snapshot)
         (emacsvox-aural--refresh-all-resource-overlay-packs)
         (emacsvox-aural--invalidate-resource-caches)
         (signal (car error) (cdr error)))))
    (setq
     desired
     (cl-remove-if-not
      (lambda (id)
        (let ((pack (emacsvox-aural-resource-pack id)))
          (and
           pack
           (emacsvox-aural--pack-immediately-below-root-p pack root))))
      (delete-dups desired)))
    (let ((result
           (sort
            desired
            (lambda (left right)
              (string-lessp (symbol-name left) (symbol-name right))))))
      (when emacsvox-aural--resource-pack-notification-pending
        (let ((emacsvox-aural--defer-resource-pack-notifications nil))
          (emacsvox-aural--resource-packs-changed)))
      result)))

(defun emacsvox-aural-refresh-discovered-resource-packs ()
  "Rescan configured discovery roots and return discovered pack identifiers."
  (interactive)
  (let (ids)
    (when
        (eq
         emacsvox-aural-resource-pack-registry
         emacsvox-aural--resource-pack-discovery-registry)
      (dolist (root emacsvox-aural-resource-pack-discovery-roots)
        (setq ids
              (append
               (emacsvox-aural-discover-resource-packs root)
               ids))))
    (setq ids
          (sort
           (delete-dups ids)
           (lambda (left right)
             (string-lessp (symbol-name left) (symbol-name right)))))
    (when (called-interactively-p 'interactive)
      (message
       "Discovered %d sound pack%s"
       (length ids) (if (= (length ids) 1) "" "s")))
    ids))

(defun emacsvox-aural-refresh-resource-pack (id)
  "Rescan registered resource pack ID and return it."
  (let ((pack (emacsvox-aural-resource-pack id)))
    (unless pack
      (emacsvox-aural--resource-error "Unknown resource pack: %S" id))
    (setf
     (emacsvox-aural-resource-pack-assets pack)
     (emacsvox-aural--scan-resource-directory
      (emacsvox-aural-resource-pack-directory pack)))
    (maphash
     (lambda (_ overlay)
       (emacsvox-aural--refresh-resource-overlay-pack overlay id))
     emacsvox-aural-resource-overlay-registry)
    (emacsvox-aural--resource-packs-changed id)
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

(defun emacsvox-aural--enabled-resource-overlays ()
  "Return enabled module resource overlays in stable identifier order."
  (let (overlays)
    (maphash
     (lambda (id overlay)
       (when (emacsvox-aural-resource-overlay-enabled-p id)
         (push overlay overlays)))
     emacsvox-aural-resource-overlay-registry)
    (sort
     overlays
     (lambda (left right)
       (string-lessp
        (symbol-name (emacsvox-aural-resource-overlay-id left))
        (symbol-name (emacsvox-aural-resource-overlay-id right)))))))

(defun emacsvox-aural--copy-resource-assets (source destination)
  "Copy cue mappings from SOURCE into DESTINATION."
  (maphash
   (lambda (cue file) (puthash cue file destination))
   source)
  destination)

(defun emacsvox-aural--resource-overlay-default-asset (cue)
  "Return (OVERLAY-ID . FILE) for enabled module-default CUE."
  (cl-loop
   for overlay in (emacsvox-aural--enabled-resource-overlays)
   for file = (gethash cue (emacsvox-aural-resource-overlay-assets overlay))
   when file
   return (cons (emacsvox-aural-resource-overlay-id overlay) file)))

(defun emacsvox-aural--resource-pack-module-asset (cue pack-id)
  "Return (OVERLAY-ID . FILE) for CUE below sound pack PACK-ID."
  (cl-loop
   for overlay in (emacsvox-aural--enabled-resource-overlays)
   for assets =
   (gethash pack-id (emacsvox-aural-resource-overlay-pack-assets overlay))
   for file = (and assets (gethash cue assets))
   when file
   return (cons (emacsvox-aural-resource-overlay-id overlay) file)))

(defun emacsvox-aural--apply-pack-assets-with-overlays
    (id assets &optional path)
  "Overlay inherited pack ID and its module subdirectories onto ASSETS.

PATH protects this helper from invalid inheritance cycles."
  (when (memq id path)
    (emacsvox-aural--resource-error
     "Resource pack inheritance cycle: %S" (nreverse (cons id path))))
  (let ((pack (emacsvox-aural-resource-pack id)))
    (unless pack
      (emacsvox-aural--resource-error "Unknown resource pack: %S" id))
    (when-let* ((parent (emacsvox-aural-resource-pack-parent pack)))
      (emacsvox-aural--apply-pack-assets-with-overlays
       parent assets (cons id path)))
    (emacsvox-aural--copy-resource-assets
     (emacsvox-aural-resource-pack-assets pack) assets)
    (when (eq (emacsvox-aural-resource-pack-kind pack) 'sound)
      (dolist (overlay (emacsvox-aural--enabled-resource-overlays))
        (when-let* ((module-assets
                     (gethash
                      id
                      (emacsvox-aural-resource-overlay-pack-assets overlay))))
          (emacsvox-aural--copy-resource-assets module-assets assets)))))
  assets)

(defun emacsvox-aural--build-effective-assets
    (pack-id &optional include-prompts)
  "Build effective assets for PACK-ID, including module resource overlays.

When INCLUDE-PROMPTS is non-nil, prompt resources form the weakest layer.
Enabled module defaults come next.  Each selected-pack inheritance layer then
adds its flat assets followed by OWNER-named module-subdirectory overrides."
  (let* ((pack (emacsvox-aural-resource-pack pack-id))
         (_
          (unless pack
            (emacsvox-aural--resource-error
             "Unknown resource pack: %S" pack-id)))
         (assets (make-hash-table :test #'eq)))
    (when
        (and include-prompts
             (not (eq pack-id 'prompts))
             (emacsvox-aural-resource-pack 'prompts))
      (emacsvox-aural--apply-pack-assets-with-overlays 'prompts assets))
    (when (eq (emacsvox-aural-resource-pack-kind pack) 'sound)
      (dolist (overlay (emacsvox-aural--enabled-resource-overlays))
        (emacsvox-aural--copy-resource-assets
         (emacsvox-aural-resource-overlay-assets overlay) assets)))
    (emacsvox-aural--apply-pack-assets-with-overlays pack-id assets)
    assets))

(defun emacsvox-aural--cached-effective-assets
    (pack-id &optional include-prompts)
  "Return the immutable cached effective assets for PACK-ID.

INCLUDE-PROMPTS has the same meaning as in
`emacsvox-aural-effective-assets'."
  (let* ((key
          (list
           emacsvox-aural-resource-generation
           pack-id
           (and include-prompts t)
           (copy-sequence emacsvox-aural-disabled-resource-overlays)))
         (cached
          (gethash key emacsvox-aural--effective-assets-cache)))
    (or
     cached
     (let ((assets
            (emacsvox-aural--build-effective-assets
             pack-id include-prompts)))
       (puthash key assets emacsvox-aural--effective-assets-cache)
       assets))))

(defun emacsvox-aural-effective-assets (pack-id &optional include-prompts)
  "Return effective assets for PACK-ID, including module resource overlays.

When INCLUDE-PROMPTS is non-nil, prompt resources form the weakest layer.
The returned table is a fresh copy and may be modified by the caller."
  (copy-hash-table
   (emacsvox-aural--cached-effective-assets pack-id include-prompts)))

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
  "Resolve CUE to a file from PACK-ID.

When INCLUDE-PROMPTS is non-nil, include prompt resources."
  (emacsvox-aural--resolve-cue-in-assets
   cue (emacsvox-aural--cached-effective-assets pack-id include-prompts)))

(defun emacsvox-aural--resource-spatialization-in-pack
    (resource pack-id &optional path)
  "Return spatialization for RESOURCE supplied through PACK-ID, or nil.

PATH protects this helper from invalid inheritance cycles."
  (when (memq pack-id path)
    (emacsvox-aural--resource-error
     "Resource pack inheritance cycle: %S"
     (nreverse (cons pack-id path))))
  (let ((pack (emacsvox-aural-resource-pack pack-id)))
    (unless pack
      (emacsvox-aural--resource-error "Unknown resource pack: %S" pack-id))
    (or
     (and
      (or
       (cl-loop
        for file being the hash-values of
        (emacsvox-aural-resource-pack-assets pack)
        thereis (equal file resource))
       (cl-some
        (lambda (overlay)
          (when-let* ((assets
                       (gethash
                        pack-id
                        (emacsvox-aural-resource-overlay-pack-assets overlay))))
            (cl-loop
             for file being the hash-values of assets
             thereis (equal file resource))))
        (emacsvox-aural--enabled-resource-overlays)))
      (emacsvox-aural-resource-pack-default-spatialization pack))
     (when-let* ((parent (emacsvox-aural-resource-pack-parent pack)))
       (emacsvox-aural--resource-spatialization-in-pack
        resource parent (cons pack-id path))))))

(defun emacsvox-aural--compute-resource-spatialization
    (resource pack-id &optional include-prompts path)
  "Compute spatialization metadata for RESOURCE selected through PACK-ID.

INCLUDE-PROMPTS includes the prompt pack in the lookup.  PATH detects pack
inheritance cycles.  The metadata comes from the pack that actually owns the
resolved file, rather than unconditionally from the selected child pack."
  (or
   (emacsvox-aural--resource-spatialization-in-pack
    resource pack-id path)
   (cl-loop
    for overlay in (emacsvox-aural--enabled-resource-overlays)
    when
    (cl-loop
     for file being the hash-values of
     (emacsvox-aural-resource-overlay-assets overlay)
     thereis (equal file resource))
    return
    (emacsvox-aural-resource-overlay-default-spatialization overlay))
   (when
       (and include-prompts
            (not (eq pack-id 'prompts))
            (emacsvox-aural-resource-pack 'prompts))
     (emacsvox-aural--resource-spatialization-in-pack resource 'prompts))
   'neutral))

(defun emacsvox-aural-resource-spatialization
    (resource pack-id &optional include-prompts path)
  "Return spatialization metadata for RESOURCE selected through PACK-ID.

INCLUDE-PROMPTS includes the prompt pack in the lookup.  PATH detects pack
inheritance cycles.  Results are cached for the current resource generation."
  (let* ((key
          (list
           emacsvox-aural-resource-generation
           resource
           pack-id
           (and include-prompts t)
           (copy-sequence emacsvox-aural-disabled-resource-overlays)
           path))
         (missing (make-symbol "missing"))
         (cached
          (gethash
           key emacsvox-aural--resource-spatialization-cache missing)))
    (if (eq cached missing)
        (let ((spatialization
               (emacsvox-aural--compute-resource-spatialization
                resource pack-id include-prompts path)))
          (puthash
           key spatialization
           emacsvox-aural--resource-spatialization-cache)
          spatialization)
      cached)))

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

(defun emacsvox-aural--resource-pack-module-unknown-assets
    (id &optional path)
  "Return themed module filenames with invalid cue ownership below pack ID.

PATH protects this helper from invalid inheritance cycles."
  (when (memq id path)
    (emacsvox-aural--resource-error
     "Resource pack inheritance cycle: %S" (nreverse (cons id path))))
  (let* ((pack (emacsvox-aural-resource-pack id))
         (_
          (unless pack
            (emacsvox-aural--resource-error "Unknown resource pack: %S" id)))
         (unknown
          (when-let* ((parent (emacsvox-aural-resource-pack-parent pack)))
            (emacsvox-aural--resource-pack-module-unknown-assets
             parent (cons id path)))))
    (dolist (overlay (emacsvox-aural--enabled-resource-overlays))
      (let ((owner (emacsvox-aural-resource-overlay-owner overlay)))
        (dolist
            (cue
             (gethash
              id
              (emacsvox-aural-resource-overlay-pack-unknown-assets overlay)))
          (push
           (intern (format "%s/%s" owner cue))
           unknown))))
    unknown))

(defun emacsvox-aural-validate-resource-pack (id &optional extra-required)
  "Return a validation report for pack ID and EXTRA-REQUIRED cues."
  (let* ((pack (emacsvox-aural-resource-pack id))
         (_
          (unless pack
            (emacsvox-aural--resource-error "Unknown resource pack: %S" id)))
         (directory (emacsvox-aural-resource-pack-directory pack))
         (missing-directory (not (file-directory-p directory)))
         (assets (emacsvox-aural-effective-assets id))
         (required
          (delete-dups
           (append
            (when (eq (emacsvox-aural-resource-pack-kind pack) 'sound)
              '(button))
            (emacsvox-aural--pack-profile-cues pack)
            (copy-sequence extra-required))))
         missing
         (unknown
          (emacsvox-aural--resource-pack-module-unknown-assets id)))
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
      (when (emacsvox-aural-rule-enabled rule)
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
                (push
                 (emacsvox-aural-action-cue action)
                 cues)))))))
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
  "Return the complete voice preset for NAME in PALETTE-ID."
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
      (when
          (and
           (symbolp (cdr entry))
           (not (boundp (cdr entry))))
        (push (cdr entry) missing)))
    (sort
     (delete-dups missing)
     (lambda (left right)
       (string-lessp (symbol-name left) (symbol-name right))))))

(defun emacsvox-aural-validate-resource-registry ()
  "Validate cue, tone, profile, pack, and voice-palette cross-references."
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
  (let ((owners (make-hash-table :test #'eq)))
    (maphash
     (lambda (id overlay)
       (let ((owner (emacsvox-aural-resource-overlay-owner overlay)))
         (when-let* ((other (gethash owner owners)))
           (emacsvox-aural--resource-error
            "Resource overlays %S and %S share owner %S"
            other id owner))
         (puthash owner id owners)
         (unless
             (file-directory-p
              (emacsvox-aural-resource-overlay-directory overlay))
           (emacsvox-aural--resource-error
            "Resource overlay %S directory does not exist: %s"
            id (emacsvox-aural-resource-overlay-directory overlay)))
         (maphash
          (lambda (cue _file)
            (let ((record (emacsvox-aural-cue cue)))
              (unless
                  (and
                   record
                   (eq owner (emacsvox-aural-cue-owner record)))
                (emacsvox-aural--resource-error
                 "Resource overlay %S supplies foreign cue %S"
                 id cue))))
          (emacsvox-aural-resource-overlay-assets overlay))
         (maphash
          (lambda (_pack-id assets)
            (maphash
             (lambda (cue _file)
               (let ((record (emacsvox-aural-cue cue)))
                 (unless
                     (and
                      record
                      (eq owner (emacsvox-aural-cue-owner record)))
                   (emacsvox-aural--resource-error
                    "Themed overlay %S supplies foreign cue %S"
                    id cue))))
             assets))
          (emacsvox-aural-resource-overlay-pack-assets overlay))))
     emacsvox-aural-resource-overlay-registry))
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
  "Register bundled cue and tone vocabularies, profiles, and voice palette."
  (dolist (definition emacsvox-aural--legacy-cue-definitions)
    (unless (emacsvox-aural-cue (car definition))
      (emacsvox-aural-register-cue
       (car definition) :summary (cadr definition))))
  (dolist (definition emacsvox-aural--prompt-cue-definitions)
    (unless (emacsvox-aural-cue (car definition))
      (emacsvox-aural-register-cue
       (car definition) :summary (cadr definition) :kind 'prompt)))
  (dolist (definition emacsvox-aural-default-tone-definitions)
    (unless (emacsvox-aural-tone (car definition))
      (emacsvox-aural-register-tone
       (car definition)
       :summary (nth 1 definition)
       :pitch (nth 2 definition)
       :duration (nth 3 definition)
       :force (nth 4 definition))))
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
     :entries emacsvox-aural-default-voice-entries
     :built-in t
     :source 'emacsvox-aural-resources)))

(defun emacsvox-aural--prioritize-resource-pack-discovery-roots (roots)
  "Put ROOTS first in configured discovery precedence order."
  (dolist (root (reverse roots))
    (setq root (file-name-as-directory (expand-file-name root)))
    (setq
     emacsvox-aural-resource-pack-discovery-roots
     (cons
      root
      (delete root emacsvox-aural-resource-pack-discovery-roots)))))

(defun emacsvox-aural-register-bundled-resources (sounds-directory)
  "Register bundled resources rooted at SOUNDS-DIRECTORY.

Bundled sound packs live below the `packs' child.  Personal packs are
discovered from `emacsvox-aural-personal-sound-packs-directory'.  Direct
sound-pack children of SOUNDS-DIRECTORY remain a lowest-precedence
compatibility source."
  (let* ((root
          (file-name-as-directory (expand-file-name sounds-directory)))
         (bundled-packs (expand-file-name "packs" root))
         (discovery-roots
          (delq
           nil
           (list
            emacsvox-aural-personal-sound-packs-directory
            bundled-packs
            root))))
    (when
        (eq
         emacsvox-aural-resource-pack-registry
         emacsvox-aural--resource-pack-discovery-registry)
      (emacsvox-aural--prioritize-resource-pack-discovery-roots
       discovery-roots))
    (dolist
        (definition
         `((prompts "Theme-independent prompts" prompt "prompts" nil neutral)
           (chimes "Short chime-based auditory cues" sound "packs/chimes"
                   (legacy-complete) neutral)
           (3d "HRTF-generated spatial auditory cues" sound "packs/3d"
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
    (dolist (discovery-root discovery-roots)
      (emacsvox-aural-discover-resource-packs discovery-root))
    (emacsvox-aural-validate-resource-registry)))

(emacsvox-aural--register-resource-vocabulary)

(provide 'emacsvox-aural-resources)
;;; emacsvox-aural-resources.el ends here
