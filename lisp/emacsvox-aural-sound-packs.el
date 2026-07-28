;;; emacsvox-aural-sound-packs.el --- Spoken sound-pack workbench -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Accessible sound-pack and cue browsers.  Users can inspect native,
;; inherited, fallback, and missing assets; audition concrete cues; activate
;; packs; validate coverage; open directories; and edit safe discovered-pack
;; manifests without editing raw Lisp.

;;; Code:

(require 'cl-lib)
(require 'pp)
(require 'subr-x)
(require 'tabulated-list)
(require 'emacsvox-aural-tools)
(require 'emacsvox-aural-preview)
(require 'emacsvox-sounds)

(declare-function dired "dired" (dirname &optional switches))
(declare-function emacsvox-speak-help "emacsvox-speak" ())
(declare-function tts-speak "tts-speak" (text))

(defvar-local emacsvox-aural-sound-pack-cues-pack nil
  "Sound pack whose cue provenance is shown in the current buffer.")

(cl-defstruct
    (emacsvox-aural-sound-cue-detail
     (:constructor emacsvox-aural-sound-packs--make-cue-detail))
  "Resolved provenance for one cue in one sound pack."
  cue availability provider resource resolved-cue spatialization intent)

(defun emacsvox-aural-sound-packs--symbol-less-p (left right)
  "Return non-nil when symbol LEFT sorts before symbol RIGHT."
  (string-lessp (symbol-name left) (symbol-name right)))

(defun emacsvox-aural-sound-packs--registered-packs ()
  "Return registered resource packs sorted by identifier."
  (emacsvox-aural-refresh-discovered-resource-packs)
  (let (packs)
    (maphash
     (lambda (id pack)
       (emacsvox-aural-refresh-resource-pack id)
       (push pack packs))
     emacsvox-aural-resource-pack-registry)
    (sort
     packs
     (lambda (left right)
       (emacsvox-aural-sound-packs--symbol-less-p
        (emacsvox-aural-resource-pack-id left)
        (emacsvox-aural-resource-pack-id right))))))

(defun emacsvox-aural-sound-packs--pack-at-point-or-read
    (&optional prompt)
  "Return the sound-pack identifier at point, or read one using PROMPT."
  (or
   (tabulated-list-get-id)
   (intern
    (completing-read
     (or prompt "Sound pack: ")
     (emacsvox-aural-resource-pack-candidates)
     nil 'must-match))))

(defun emacsvox-aural-sound-packs--profile-status (pack)
  "Return concise coverage status for PACK."
  (if-let* ((profiles (emacsvox-aural-resource-pack-profiles pack)))
      (mapconcat #'symbol-name profiles ", ")
    (if (eq (emacsvox-aural-resource-pack-kind pack) 'sound)
        "button required"
      "none declared")))

(defun emacsvox-aural-sound-packs--report-status (report)
  "Return concise validation status for resource REPORT."
  (if (emacsvox-aural-resource-report-valid report)
      "valid"
    (string-join
     (delq
      nil
      (list
       "invalid"
       (when (emacsvox-aural-resource-report-missing-directory report)
         "directory missing")
       (when-let* ((missing
                    (emacsvox-aural-resource-report-missing-required
                     report)))
         (format "%d required missing" (length missing)))
       (when-let* ((unknown
                    (emacsvox-aural-resource-report-unknown-assets
                     report)))
         (format "%d unknown" (length unknown)))))
     ", ")))

(defun emacsvox-aural-sound-packs--pack-row (pack)
  "Return a tabulated manager row for PACK."
  (let* ((id (emacsvox-aural-resource-pack-id pack))
         (direct
          (hash-table-count
           (emacsvox-aural-resource-pack-assets pack)))
         (effective
          (hash-table-count (emacsvox-aural-effective-assets id)))
         (report (emacsvox-aural-validate-resource-pack id)))
    (list
     id
     (vector
      (symbol-name id)
      (if (eq id emacsvox-sounds-current-pack) "active" "")
      (symbol-name (emacsvox-aural-resource-pack-kind pack))
      (if (eq (emacsvox-aural-resource-pack-origin pack) 'discovered)
          "discovered"
        "registered")
      (if-let* ((parent (emacsvox-aural-resource-pack-parent pack)))
          (symbol-name parent)
        "")
      (format "%d native, %d effective" direct effective)
      (emacsvox-aural-sound-packs--profile-status pack)
      (symbol-name
       (emacsvox-aural-resource-pack-default-spatialization pack))
      (emacsvox-aural-sound-packs--report-status report)
      (abbreviate-file-name
       (emacsvox-aural-resource-pack-directory pack))
      (emacsvox-aural-resource-pack-summary pack)))))

(defun emacsvox-aural-sound-packs--set-entries ()
  "Populate the sound-pack manager."
  (setq
   tabulated-list-entries
   (mapcar
    #'emacsvox-aural-sound-packs--pack-row
    (emacsvox-aural-sound-packs--registered-packs))))

(defun emacsvox-aural-sound-packs--goto-id (id)
  "Move to tabulated row ID and its first column."
  (emacsvox-aural-ui-goto-row id))

(defun emacsvox-aural-sound-packs-refresh (&optional pack)
  "Refresh the sound-pack manager, preserving PACK and the current column."
  (interactive)
  (emacsvox-aural-ui-refresh-tabulated
   #'emacsvox-aural-sound-packs--set-entries
   pack
   emacsvox-sounds-current-pack))

(defun emacsvox-aural-sound-packs--spoken-summary (id)
  "Return a natural spoken summary of sound pack ID."
  (let* ((pack
          (or
           (emacsvox-aural-resource-pack id)
           (user-error "Unknown sound pack: %S" id)))
         (direct
          (hash-table-count
           (emacsvox-aural-resource-pack-assets pack)))
         (effective
          (hash-table-count (emacsvox-aural-effective-assets id)))
         (report (emacsvox-aural-validate-resource-pack id)))
    (string-join
     (delq
      nil
      (list
       (format "%s." (emacsvox-aural-tools--humanize id))
       (format
        "%s %s %s pack."
        (if (eq id emacsvox-sounds-current-pack) "Active" "Inactive")
        (if (eq (emacsvox-aural-resource-pack-origin pack) 'discovered)
            "discovered"
          "registered")
        (emacsvox-aural-resource-pack-kind pack))
       (when-let* ((parent (emacsvox-aural-resource-pack-parent pack)))
         (format
          "Parent %s."
          (emacsvox-aural-tools--humanize parent)))
       (format "%d native and %d effective assets." direct effective)
       (format
        "Coverage %s."
        (emacsvox-aural-tools--humanize
         (emacsvox-aural-sound-packs--profile-status pack)))
       (format
        "Spatialization %s."
        (emacsvox-aural-tools--humanize
         (emacsvox-aural-resource-pack-default-spatialization pack)))
       (format "%s." (emacsvox-aural-sound-packs--report-status report))
       (format "%s." (emacsvox-aural-resource-pack-summary pack))))
     " ")))

(defun emacsvox-aural-sound-packs-speak-current ()
  "Speak a natural summary of the sound pack at point."
  (interactive)
  (let ((summary
         (emacsvox-aural-sound-packs--spoken-summary
          (emacsvox-aural-sound-packs--pack-at-point-or-read))))
    (if (fboundp 'tts-speak)
        (tts-speak summary)
      (message "%s" summary))
    summary))

(defun emacsvox-aural-sound-packs-speak-current-cell ()
  "Speak the current sound-pack column title and value."
  (interactive)
  (emacsvox-aural-tools--speak-tabulated-cell))

(defun emacsvox-aural-sound-packs-next ()
  "Move to and speak the next sound pack."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-row 1 "sound pack list"))

(defun emacsvox-aural-sound-packs-previous ()
  "Move to and speak the previous sound pack."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-row -1 "sound pack list"))

(defun emacsvox-aural-sound-packs-next-column ()
  "Move right and speak the next sound-pack column."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-column 1))

(defun emacsvox-aural-sound-packs-previous-column ()
  "Move left and speak the previous sound-pack column."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-column -1))

(defun emacsvox-aural-sound-packs-activate ()
  "Activate the sound pack at point."
  (interactive)
  (let* ((id (emacsvox-aural-sound-packs--pack-at-point-or-read))
         (pack (emacsvox-aural-resource-pack id)))
    (unless (eq (emacsvox-aural-resource-pack-kind pack) 'sound)
      (user-error "Only sound packs can be activated as an auditory theme"))
    (emacsvox-sounds-select-theme id)
    (emacsvox-aural-sound-packs-refresh id)
    (emacsvox-aural-home-refresh-if-live)
    (when (called-interactively-p 'interactive)
      (emacsvox-aural-sound-packs-speak-current))
    id))

(defun emacsvox-aural-sound-packs--exact-asset
    (cue pack-id &optional path selected-pack)
  "Return exact CUE asset provenance through PACK-ID.

PATH protects this inspection helper from invalid inheritance cycles.
SELECTED-PACK distinguishes direct from inherited resources."
  (when (memq pack-id path)
    (signal
     'emacsvox-aural-resource-error
     (list
      (format
       "Resource pack inheritance cycle: %S"
       (nreverse (cons pack-id path))))))
  (let ((pack (emacsvox-aural-resource-pack pack-id))
        (selected-pack (or selected-pack pack-id)))
    (unless pack
      (user-error "Unknown sound pack: %S" pack-id))
    (or
     (when-let* ((module
                  (emacsvox-aural--resource-pack-module-asset cue pack-id)))
       (list
        :provider pack-id
        :resource (cdr module)
        :availability
        (if (eq pack-id selected-pack)
            "module override"
          "inherited module override")))
     (when-let* ((file
                  (gethash
                   cue (emacsvox-aural-resource-pack-assets pack))))
       (list
        :provider pack-id
        :resource file
        :availability
        (if (eq pack-id selected-pack) "native" "inherited")))
     (when-let* ((parent (emacsvox-aural-resource-pack-parent pack)))
       (emacsvox-aural-sound-packs--exact-asset
        cue parent (cons pack-id path) selected-pack)))))

(defun emacsvox-aural-sound-packs--cue-detail
    (cue pack-id &optional fallback-path)
  "Return resolved detail for CUE through PACK-ID.

FALLBACK-PATH protects cue fallback inspection from cycles."
  (when (memq cue fallback-path)
    (signal
     'emacsvox-aural-resource-error
     (list
      (format
       "Cue fallback cycle: %S"
       (nreverse (cons cue fallback-path))))))
  (let* ((record (emacsvox-aural-cue cue))
         (exact
          (emacsvox-aural-sound-packs--exact-asset cue pack-id))
         (module-default
          (unless exact
            (emacsvox-aural--resource-overlay-default-asset cue))))
    (cond
     (exact
      (let ((provider (plist-get exact :provider))
            (resource (plist-get exact :resource)))
        (emacsvox-aural-sound-packs--make-cue-detail
         :cue cue
         :availability (plist-get exact :availability)
         :provider provider
         :resource resource
         :resolved-cue cue
         :spatialization
         (emacsvox-aural-resource-spatialization resource pack-id)
         :intent
         (if record
             (emacsvox-aural-cue-summary record)
           "Unregistered cue identifier; validation error"))))
     (module-default
      (let ((provider (car module-default))
            (resource (cdr module-default)))
        (emacsvox-aural-sound-packs--make-cue-detail
         :cue cue
         :availability "module default"
         :provider provider
         :resource resource
         :resolved-cue cue
         :spatialization
         (emacsvox-aural-resource-spatialization resource pack-id)
         :intent
         (if record
             (emacsvox-aural-cue-summary record)
           "Unregistered cue identifier; validation error"))))
     ((and record (emacsvox-aural-cue-fallback record))
      (let* ((fallback (emacsvox-aural-cue-fallback record))
             (resolved
              (emacsvox-aural-sound-packs--cue-detail
               fallback pack-id (cons cue fallback-path))))
        (if (emacsvox-aural-sound-cue-detail-resource resolved)
            (progn
              (setf
               (emacsvox-aural-sound-cue-detail-cue resolved) cue
               (emacsvox-aural-sound-cue-detail-availability resolved)
               (format
                "fallback to %s"
                (emacsvox-aural-sound-cue-detail-resolved-cue resolved))
               (emacsvox-aural-sound-cue-detail-intent resolved)
               (emacsvox-aural-cue-summary record))
              resolved)
          (emacsvox-aural-sound-packs--make-cue-detail
           :cue cue
           :availability "missing"
           :intent (emacsvox-aural-cue-summary record)))))
     (t
      (emacsvox-aural-sound-packs--make-cue-detail
       :cue cue
       :availability "missing"
       :intent
       (if record
           (emacsvox-aural-cue-summary record)
         "Unregistered cue identifier; validation error"))))))

(defun emacsvox-aural-sound-packs--cue-ids (pack-id)
  "Return relevant registered and supplied cue identifiers for PACK-ID."
  (let* ((pack (emacsvox-aural-resource-pack pack-id))
         (kind (emacsvox-aural-resource-pack-kind pack))
         ids)
    (maphash
     (lambda (id cue)
       (when
           (if (eq kind 'prompt)
               (eq (emacsvox-aural-cue-kind cue) 'prompt)
             (not (eq (emacsvox-aural-cue-kind cue) 'prompt)))
         (push id ids)))
     emacsvox-aural-cue-registry)
    (maphash
     (lambda (id _file) (push id ids))
     (emacsvox-aural-effective-assets pack-id))
    (sort
     (delete-dups ids)
     #'emacsvox-aural-sound-packs--symbol-less-p)))

(defun emacsvox-aural-sound-pack-cues--row (cue)
  "Return a cue-browser row for CUE in the current pack."
  (let* ((detail
          (emacsvox-aural-sound-packs--cue-detail
           cue emacsvox-aural-sound-pack-cues-pack))
         (provider
          (emacsvox-aural-sound-cue-detail-provider detail))
         (resource
          (emacsvox-aural-sound-cue-detail-resource detail))
         (spatial
          (emacsvox-aural-sound-cue-detail-spatialization detail)))
    (list
     cue
     (vector
      (symbol-name cue)
      (emacsvox-aural-sound-cue-detail-availability detail)
      (if provider (symbol-name provider) "")
      (if resource (abbreviate-file-name resource) "")
      (if spatial (symbol-name spatial) "")
      (emacsvox-aural-sound-cue-detail-intent detail)))))

(defun emacsvox-aural-sound-pack-cues--set-entries ()
  "Populate the current sound-pack cue browser."
  (setq
   tabulated-list-entries
   (mapcar
    #'emacsvox-aural-sound-pack-cues--row
    (emacsvox-aural-sound-packs--cue-ids
     emacsvox-aural-sound-pack-cues-pack))))

(defun emacsvox-aural-sound-pack-cues-refresh (&optional cue)
  "Refresh the cue browser, preserving CUE and the current column."
  (interactive)
  (emacsvox-aural-ui-refresh-tabulated
   (lambda ()
     (emacsvox-aural-sound-packs--registered-packs)
     (emacsvox-aural-sound-pack-cues--set-entries))
   cue))

(defun emacsvox-aural-sound-pack-cues-speak-current ()
  "Speak the cue, provenance, and intent at point."
  (interactive)
  (let* ((cue
          (or
           (tabulated-list-get-id)
           (user-error "Move to a sound cue first")))
         (detail
          (emacsvox-aural-sound-packs--cue-detail
           cue emacsvox-aural-sound-pack-cues-pack))
         (summary
          (string-join
           (delq
            nil
            (list
             (format
              "%s."
              (emacsvox-aural-tools--humanize cue))
             (format
              "%s."
              (emacsvox-aural-sound-cue-detail-availability detail))
             (when-let* ((provider
                          (emacsvox-aural-sound-cue-detail-provider
                           detail)))
               (format
                "Provided by %s."
                (emacsvox-aural-tools--humanize provider)))
             (when-let* ((spatial
                          (emacsvox-aural-sound-cue-detail-spatialization
                           detail)))
               (format
                "Spatialization %s."
                (emacsvox-aural-tools--humanize spatial)))
             (format
              "%s."
              (emacsvox-aural-sound-cue-detail-intent detail))))
           " ")))
    (if (fboundp 'tts-speak)
        (tts-speak summary)
      (message "%s" summary))
    summary))

(defun emacsvox-aural-sound-pack-cues-speak-current-cell ()
  "Speak the current cue-browser column title and value."
  (interactive)
  (emacsvox-aural-tools--speak-tabulated-cell))

(defun emacsvox-aural-sound-pack-cues-next ()
  "Move to and speak the next cue."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-row 1 "sound cue list"))

(defun emacsvox-aural-sound-pack-cues-previous ()
  "Move to and speak the previous cue."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-row -1 "sound cue list"))

(defun emacsvox-aural-sound-pack-cues-next-column ()
  "Move right and speak the next cue column."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-column 1))

(defun emacsvox-aural-sound-pack-cues-previous-column ()
  "Move left and speak the previous cue column."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-column -1))

(defun emacsvox-aural-sound-packs--audition (pack-id cue)
  "Audition CUE as resolved through PACK-ID and return its detail."
  (let* ((detail
          (emacsvox-aural-sound-packs--cue-detail cue pack-id))
         (resource
          (emacsvox-aural-sound-cue-detail-resource detail))
         (resolved
          (emacsvox-aural-sound-cue-detail-resolved-cue detail))
         (provider
          (or
           (emacsvox-aural-sound-cue-detail-provider detail)
           pack-id)))
    (unless resource
      (user-error "Cue %s is missing from sound pack %s" cue pack-id))
    (emacsvox-aural-preview-play-cue
     resource
     (emacsvox-aural-sample-id provider resolved resource))
    (emacsvox-aural-preview-message
     "Auditioning %s from %s"
     cue provider)
    detail))

(defun emacsvox-aural-sound-packs-audition ()
  "Audition a representative cue from the sound pack at point."
  (interactive)
  (let* ((pack-id
          (emacsvox-aural-sound-packs--pack-at-point-or-read))
         (preferred
          (if
              (eq
               (emacsvox-aural-resource-pack-kind
                (emacsvox-aural-resource-pack pack-id))
               'prompt)
              '(startup waking-up success)
            '(button item open-object task-done)))
         (cue
          (or
           (cl-find-if
            (lambda (candidate)
              (emacsvox-aural-sound-cue-detail-resource
               (emacsvox-aural-sound-packs--cue-detail
                candidate pack-id)))
            preferred)
           (cl-find-if
            (lambda (candidate)
              (emacsvox-aural-sound-cue-detail-resource
               (emacsvox-aural-sound-packs--cue-detail
                candidate pack-id)))
            (emacsvox-aural-sound-packs--cue-ids pack-id)))))
    (unless cue
      (user-error "Sound pack %s has no audible registered cue" pack-id))
    (emacsvox-aural-sound-packs--audition pack-id cue)))

(defun emacsvox-aural-sound-pack-cues-audition ()
  "Audition the concrete cue at point."
  (interactive)
  (emacsvox-aural-sound-packs--audition
   emacsvox-aural-sound-pack-cues-pack
   (or
    (tabulated-list-get-id)
    (user-error "Move to a sound cue first"))))

(defun emacsvox-aural-sound-packs-show-validation (&optional pack-id)
  "Display and speak validation for PACK-ID or the pack at point."
  (interactive)
  (let* ((pack-id
          (or
           pack-id
           (emacsvox-aural-sound-packs--pack-at-point-or-read)))
         (pack (emacsvox-aural-resource-pack pack-id))
         (report (emacsvox-aural-validate-resource-pack pack-id))
         (status (emacsvox-aural-sound-packs--report-status report)))
    (with-help-window (help-buffer)
      (princ
       (format
        "Sound pack %s: %s\n\n"
        pack-id status))
      (princ
       (format
        "Directory: %s\nKind: %s\nOrigin: %s\nParent: %s\n"
        (emacsvox-aural-resource-pack-directory pack)
        (emacsvox-aural-resource-pack-kind pack)
        (emacsvox-aural-resource-pack-origin pack)
        (or (emacsvox-aural-resource-pack-parent pack) "none")))
      (princ
       (format
        "Coverage profiles: %s\nSpatialization: %s\n\n"
        (emacsvox-aural-sound-packs--profile-status pack)
        (emacsvox-aural-resource-pack-default-spatialization pack)))
      (princ
       (format
        "Missing directory: %s\nMissing required cues: %S\nUnknown assets: %S\n"
        (if (emacsvox-aural-resource-report-missing-directory report)
            "yes"
          "no")
        (emacsvox-aural-resource-report-missing-required report)
        (emacsvox-aural-resource-report-unknown-assets report))))
    (let ((spoken
           (format
            "Sound pack %s, %s."
            (emacsvox-aural-tools--humanize pack-id)
            status)))
      (if (fboundp 'tts-speak)
          (tts-speak spoken)
        (message "%s" spoken)))
    report))

(defun emacsvox-aural-sound-pack-cues-show-validation ()
  "Display and speak validation for the cue browser's sound pack."
  (interactive)
  (emacsvox-aural-sound-packs-show-validation
   emacsvox-aural-sound-pack-cues-pack))

(defun emacsvox-aural-sound-packs--current-pack ()
  "Return the resource pack represented by the current manager or cue buffer."
  (let ((id
         (if (derived-mode-p 'emacsvox-aural-sound-pack-cues-mode)
             emacsvox-aural-sound-pack-cues-pack
           (emacsvox-aural-sound-packs--pack-at-point-or-read))))
    (or
     (emacsvox-aural-resource-pack id)
     (user-error "Unknown sound pack: %S" id))))

(defun emacsvox-aural-sound-packs-open-directory ()
  "Open the current sound pack's directory in Dired."
  (interactive)
  (let* ((pack (emacsvox-aural-sound-packs--current-pack))
         (directory (emacsvox-aural-resource-pack-directory pack)))
    (unless (file-directory-p directory)
      (user-error "Sound pack directory does not exist: %s" directory))
    (dired directory)))

(defun emacsvox-aural-sound-packs--descends-from-p
    (id ancestor &optional path)
  "Return non-nil when resource pack ID descends from ANCESTOR.

PATH protects completion from invalid inheritance cycles."
  (cond
   ((eq id ancestor) t)
   ((memq id path) nil)
   (t
    (when-let* ((pack (emacsvox-aural-resource-pack id))
                (parent (emacsvox-aural-resource-pack-parent pack)))
      (emacsvox-aural-sound-packs--descends-from-p
       parent ancestor (cons id path))))))

(defun emacsvox-aural-sound-packs--parent-candidates (pack)
  "Return safe parent completion candidates for PACK."
  (let ((id (emacsvox-aural-resource-pack-id pack))
        (kind (emacsvox-aural-resource-pack-kind pack))
        candidates)
    (dolist (candidate (emacsvox-aural-sound-packs--registered-packs))
      (let ((candidate-id (emacsvox-aural-resource-pack-id candidate)))
        (when
            (and
             (eq kind (emacsvox-aural-resource-pack-kind candidate))
             (not
              (emacsvox-aural-sound-packs--descends-from-p
               candidate-id id)))
          (push (symbol-name candidate-id) candidates))))
    (cons "" (sort candidates #'string-lessp))))

(defun emacsvox-aural-sound-packs--profile-candidates ()
  "Return sorted resource requirement-profile completion candidates."
  (let (profiles)
    (maphash
     (lambda (id _profile) (push (symbol-name id) profiles))
     emacsvox-aural-requirement-profile-registry)
    (sort profiles #'string-lessp)))

(defun emacsvox-aural-sound-packs--write-manifest (pack data)
  "Atomically write validated manifest DATA for discovered PACK."
  (unless (eq (emacsvox-aural-resource-pack-origin pack) 'discovered)
    (user-error "Registered sound packs are read-only"))
  (let* ((directory (emacsvox-aural-resource-pack-directory pack))
         (file
          (expand-file-name
           emacsvox-aural-resource-pack-manifest directory))
         (backup (concat file "~"))
         (existed (file-exists-p file))
         (temporary
          (make-temp-file
           (expand-file-name ".sound-pack-" directory))))
    (unwind-protect
        (progn
          (with-temp-buffer
            (insert
             ";;; Emacsvox sound-pack metadata; read as data, not evaluated.\n\n")
            (let ((print-length nil)
                  (print-level nil))
              (pp data (current-buffer)))
            (write-region
             (point-min) (point-max) temporary nil 'silent))
          (set-file-modes temporary #o600)
          (when existed
            (copy-file file backup t t t))
          (rename-file temporary file t)
          (setq temporary nil)
          (condition-case error
              (let* ((_ (emacsvox-aural-refresh-discovered-resource-packs))
                     (updated
                      (emacsvox-aural-resource-pack
                       (emacsvox-aural-resource-pack-id pack))))
                (unless
                    (and
                     updated
                     (equal
                      (emacsvox-aural-resource-pack-summary updated)
                      (plist-get data :summary))
                     (eq
                      (emacsvox-aural-resource-pack-parent updated)
                      (plist-get data :parent))
                     (equal
                      (emacsvox-aural-resource-pack-profiles updated)
                      (plist-get data :profiles))
                     (eq
                      (emacsvox-aural-resource-pack-default-spatialization
                       updated)
                      (plist-get data :default-spatialization)))
                  (error
                   "Edited sound pack did not refresh from its manifest"))
                updated)
            (error
             (if existed
                 (copy-file backup file t t t)
               (when (file-exists-p file)
                 (delete-file file)))
             (ignore-errors
               (emacsvox-aural-refresh-discovered-resource-packs))
             (signal (car error) (cdr error)))))
      (when (and temporary (file-exists-p temporary))
        (delete-file temporary)))))

(defun emacsvox-aural-sound-packs-edit-manifest ()
  "Guidedly edit safe manifest metadata for the discovered pack at point."
  (interactive)
  (let* ((id (emacsvox-aural-sound-packs--pack-at-point-or-read))
         (pack (emacsvox-aural-resource-pack id)))
    (unless (eq (emacsvox-aural-resource-pack-origin pack) 'discovered)
      (user-error
       "Registered pack %s is read-only; edit a discovered personal pack"
       id))
    (let* ((summary
            (string-trim
             (read-string
              "Sound-pack summary: "
              (emacsvox-aural-resource-pack-summary pack))))
           (_
            (when (string-empty-p summary)
              (user-error "Sound-pack summary cannot be empty")))
           (parent-answer
            (completing-read
             "Parent pack, or none: "
             (emacsvox-aural-sound-packs--parent-candidates pack)
             nil 'must-match nil nil
             (when-let* ((parent
                          (emacsvox-aural-resource-pack-parent pack)))
               (symbol-name parent))))
           (profiles
            (mapcar
             #'intern
             (delete
              ""
              (completing-read-multiple
               "Coverage profiles, comma separated, or none: "
               (emacsvox-aural-sound-packs--profile-candidates)
               nil 'must-match
               (mapconcat
                #'symbol-name
                (emacsvox-aural-resource-pack-profiles pack)
                ",")))))
           (spatial
            (intern
             (completing-read
              "Default spatialization: "
              '("neutral" "stereo" "pre-spatialized")
              nil 'must-match nil nil
              (symbol-name
               (emacsvox-aural-resource-pack-default-spatialization
                pack)))))
           (data
            (list
             :schema-version
             emacsvox-aural-resource-pack-manifest-schema-version
             :summary summary
             :parent
             (unless (string-empty-p parent-answer)
               (intern parent-answer))
             :profiles profiles
             :default-spatialization spatial)))
      (emacsvox-aural-sound-packs--write-manifest pack data)
      (emacsvox-aural-sound-packs-refresh id)
      (emacsvox-aural-home-refresh-if-live)
      (message "Saved sound-pack manifest for %s" id)
      (when (called-interactively-p 'interactive)
        (emacsvox-aural-sound-packs-speak-current))
      data)))

(defun emacsvox-aural-sound-packs-help ()
  "Display and speak sound-pack manager help."
  (interactive)
  (with-help-window (help-buffer)
    (princ
     (concat
      "Aural Sound-Pack Manager\n\n"
      "Each row reports active state, ownership, inheritance, native and\n"
      "effective assets, coverage, spatialization, validation, directory,\n"
      "and intent.\n\n"
      "n or down next       p or up previous\n"
      "left/right column    . speak titled cell\n"
      "RET browse cues      SPC speak pack\n"
      "a activate           P audition representative cue\n"
      "v validate           e edit discovered manifest\n"
      "o open directory     g rescan and refresh\n"
      "h aural home         ? help\n"
      "q quit\n")))
  (when (fboundp 'emacsvox-speak-help)
    (emacsvox-speak-help)))

(define-derived-mode emacsvox-aural-sound-packs-mode
    emacsvox-aural-tabulated-mode
  "Aural-Sound-Packs"
  "Spoken manager for registered and dynamically discovered sound packs."
  (emacsvox-aural-ui-configure-tabulated
   "sound pack list"
   #'emacsvox-aural-sound-packs-speak-current
   #'emacsvox-aural-sound-packs-refresh)
  (setq
   tabulated-list-format
   [("Pack" 20 t)
    ("Status" 10 t)
    ("Kind" 9 t)
    ("Origin" 12 t)
    ("Parent" 16 t)
    ("Assets" 25 t)
    ("Coverage" 22 t)
    ("Spatial" 18 t)
    ("Validation" 26 t)
    ("Directory" 36 t)
    ("Intent" 0 t)])
  (setq tabulated-list-padding 2)
  (add-hook
   'tabulated-list-revert-hook
   #'emacsvox-aural-sound-packs-refresh nil t)
  (tabulated-list-init-header))

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
  (define-key
   emacsvox-aural-sound-packs-mode-map
   (kbd (car binding))
   (cdr binding)))

(defun emacsvox-aural-sound-pack-cues-help ()
  "Display and speak sound-pack cue-browser help."
  (interactive)
  (with-help-window (help-buffer)
    (princ
     (concat
      "Aural Sound Cue Browser\n\n"
      "Each row explains whether a cue is native, inherited, resolved through\n"
      "a registered fallback, or missing, together with its provider, file,\n"
      "spatialization, and semantic intent.\n\n"
      "n or down next       p or up previous\n"
      "left/right column    . speak titled cell\n"
      "RET or P audition    SPC speak cue\n"
      "v validate pack      o open pack directory\n"
      "g rescan pack        s sound-pack manager\n"
      "h aural home         ? help\n"
      "q quit\n")))
  (when (fboundp 'emacsvox-speak-help)
    (emacsvox-speak-help)))

(define-derived-mode
    emacsvox-aural-sound-pack-cues-mode
    emacsvox-aural-tabulated-mode
  "Aural-Sound-Cues"
  "Spoken browser for sound-pack cue intent and concrete provenance."
  (emacsvox-aural-ui-configure-tabulated
   "sound cue list"
   #'emacsvox-aural-sound-pack-cues-speak-current
   #'emacsvox-aural-sound-pack-cues-refresh)
  (setq
   tabulated-list-format
   [("Cue" 24 t)
    ("Availability" 24 t)
    ("Provider" 18 t)
    ("File" 40 t)
    ("Spatial" 18 t)
    ("Intent" 0 t)])
  (setq tabulated-list-padding 2)
  (add-hook
   'tabulated-list-revert-hook
   #'emacsvox-aural-sound-pack-cues-refresh nil t)
  (tabulated-list-init-header))

(dolist
    (binding
     '(("RET" . emacsvox-aural-sound-pack-cues-audition)
       ("P" . emacsvox-aural-sound-pack-cues-audition)
       ("v" . emacsvox-aural-sound-pack-cues-show-validation)
       ("o" . emacsvox-aural-sound-packs-open-directory)
       ("s" . emacsvox-aural-list-sound-packs)
       ("h" . emacsvox-aural)
       ("?" . emacsvox-aural-sound-pack-cues-help)))
  (define-key
   emacsvox-aural-sound-pack-cues-mode-map
   (kbd (car binding))
   (cdr binding)))

(defun emacsvox-aural-list-sound-packs (&optional pack)
  "Open the spoken sound-pack manager, selecting PACK when supplied."
  (interactive)
  (let ((source
         (emacsvox-aural-inspection-remember-source-buffer))
        (buffer (get-buffer-create "*Aural Sound Packs*")))
    (with-current-buffer buffer
      (emacsvox-aural-sound-packs-mode)
      (emacsvox-aural-inspection-attach-source source)
      (emacsvox-aural-sound-packs-refresh
       (or pack emacsvox-sounds-current-pack)))
    (emacsvox-aural-ui-pop-to-buffer buffer)
    (when
        (and
         (called-interactively-p 'interactive)
         (tabulated-list-get-id))
      (emacsvox-aural-sound-packs-speak-current))
    buffer))

(defun emacsvox-aural-list-sound-pack-cues (&optional pack)
  "Open the spoken cue browser for PACK or the sound pack at point."
  (interactive)
  (let* ((source
          (emacsvox-aural-inspection-remember-source-buffer))
         (pack
          (or
           pack
           (emacsvox-aural-sound-packs--pack-at-point-or-read)))
         (buffer
          (get-buffer-create
           (format "*Aural Sound Cues: %s*" pack))))
    (unless (emacsvox-aural-resource-pack pack)
      (user-error "Unknown sound pack: %S" pack))
    (with-current-buffer buffer
      (emacsvox-aural-sound-pack-cues-mode)
      (emacsvox-aural-inspection-attach-source source)
      (setq emacsvox-aural-sound-pack-cues-pack pack)
      (emacsvox-aural-sound-pack-cues-refresh))
    (emacsvox-aural-ui-pop-to-buffer buffer)
    (when
        (and
         (called-interactively-p 'interactive)
         (tabulated-list-get-id))
      (emacsvox-aural-sound-pack-cues-speak-current))
    buffer))

(provide 'emacsvox-aural-sound-packs)
;;; emacsvox-aural-sound-packs.el ends here
