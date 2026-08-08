;;; emacsvox-aural-profile-service.el --- Aural profile service -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Stable non-UI operations over presentation-profile state.  Profile
;; managers and diagnostics depend on this service rather than each other's
;; private functions.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'emacsvox-aural-spatial)
(require 'emacsvox-aural-schemes)

(defvar emacsvox-sounds-current-pack)
(defvar emacsvox-sounds--silent-theme-selection)

(declare-function emacsvox-sounds-select-theme
                  "emacsvox-sounds" (&optional theme))

(defun emacsvox-aural-current-profile-id ()
  "Return the selected presentation-profile identifier, or nil."
  (and
   (emacsvox-aural-profile-entry emacsvox-aural-active-profile)
   emacsvox-aural-active-profile))

(defun emacsvox-aural-capture-profile-data (id summary &optional _source-buffer)
  "Return profile data ID with SUMMARY for the live global configuration.

The optional source-buffer argument is retained for older callers but is not
part of profile state."
  (emacsvox-aural--require-symbol id "Presentation profile identifier")
  (unless (and (stringp summary) (not (string-empty-p summary)))
    (emacsvox-aural--scheme-error
     "Presentation profile requires a summary"))
  (list
   :id id
   :summary summary
   :feature-fragments
   (copy-sequence emacsvox-aural-enabled-feature-fragments)
   :sound-pack
   (or
    (and
     (boundp 'emacsvox-sounds-current-pack)
     emacsvox-sounds-current-pack)
    (emacsvox-aural-effective-scheme-provider 'resource-pack))
   :voice-palette
   (or
    emacsvox-aural-voice-palette-override
    (emacsvox-aural-effective-scheme-provider 'voice-palette))
   :spatial
   (list
    :enabled emacsvox-aural-spatial-enabled
    :speech-enabled emacsvox-aural-spatial-speech-enabled
    :cue-enabled emacsvox-aural-spatial-cue-enabled
    :output emacsvox-aural-spatial-output
    :maximum-separation emacsvox-aural-spatial-maximum-separation
    :remapping
    (if (symbolp emacsvox-aural-spatial-remapping)
        emacsvox-aural-spatial-remapping
      'normal))))

(defun emacsvox-aural--apply-profile-spatial (spatial)
  "Apply validated profile SPATIAL settings."
  (when spatial
    (when (plist-member spatial :enabled)
      (setq emacsvox-aural-spatial-enabled
            (plist-get spatial :enabled)))
    (when (plist-member spatial :speech-enabled)
      (setq emacsvox-aural-spatial-speech-enabled
            (plist-get spatial :speech-enabled)))
    (when (plist-member spatial :cue-enabled)
      (setq emacsvox-aural-spatial-cue-enabled
            (plist-get spatial :cue-enabled)))
    (when (plist-member spatial :output)
      (setq emacsvox-aural-spatial-output
            (plist-get spatial :output)))
    (when (plist-member spatial :maximum-separation)
      (setq emacsvox-aural-spatial-maximum-separation
            (float (plist-get spatial :maximum-separation))))
    (when (plist-member spatial :remapping)
      (setq emacsvox-aural-spatial-remapping
            (plist-get spatial :remapping)))))

(defun emacsvox-aural-apply-profile (id &optional _source-buffer)
  "Validate and transactionally apply global profile ID.

The optional source-buffer argument is retained for older callers but is not
part of profile state."
  (let* ((entry
          (or
           (emacsvox-aural-profile-entry id)
           (emacsvox-aural--scheme-error
            "Unknown presentation profile: %S" id)))
         (data (copy-tree (emacsvox-aural-profile-entry-data entry)))
         (_ (emacsvox-aural--validate-profile-data data))
         (scheme 'default)
         (fragments (plist-get data :feature-fragments))
         (pack
          (or
           (plist-get data :sound-pack)
           (emacsvox-aural-effective-scheme-provider
            'resource-pack scheme)))
         (palette (plist-get data :voice-palette))
         (spatial (plist-get data :spatial))
         (old-scheme emacsvox-aural-active-scheme)
         (old-fragments
          (copy-sequence emacsvox-aural-enabled-feature-fragments))
         (old-fragment-order
          (copy-sequence emacsvox-aural-feature-fragment-order))
         (old-palette emacsvox-aural-voice-palette-override)
         (old-profile emacsvox-aural-active-profile)
         (old-pack
          (and
           (boundp 'emacsvox-sounds-current-pack)
           emacsvox-sounds-current-pack))
         (old-spatial
          (list
           :enabled emacsvox-aural-spatial-enabled
           :speech-enabled emacsvox-aural-spatial-speech-enabled
           :cue-enabled emacsvox-aural-spatial-cue-enabled
           :output emacsvox-aural-spatial-output
           :maximum-separation emacsvox-aural-spatial-maximum-separation
           :remapping emacsvox-aural-spatial-remapping))
         (previous (emacsvox-aural--capture-coordinated-state))
         state-committed)
    (when pack
      (unless (emacsvox-aural-resource-pack pack)
        (emacsvox-aural--scheme-error
         "Presentation profile %S sound pack is unavailable: %S"
         id pack))
      (require 'emacsvox-sounds))
    (unwind-protect
        (progn
          (when pack
            ;; Prepare the fallible concrete provider before publishing any
            ;; coordinated scheme state or running its observer hooks.
            (let ((emacsvox-sounds--silent-theme-selection t))
              (emacsvox-sounds-select-theme pack)))
          (setq
           emacsvox-aural-active-scheme scheme
           emacsvox-aural-feature-fragment-order
           (emacsvox-aural--merge-enabled-feature-fragment-order fragments)
           emacsvox-aural-enabled-feature-fragments
           (copy-sequence fragments)
           emacsvox-aural-voice-palette-override palette
           emacsvox-aural-active-profile id)
          (emacsvox-aural--apply-profile-spatial spatial)
          ;; From this point the complete profile is live.  Observer failures
          ;; must not roll it back to a state they were never told about.
          (setq state-committed t)
          (emacsvox-aural--notify-coordinated-state-change
           previous 'profile-applied
           '(active-scheme feature-fragments))
          (run-hook-with-args 'emacsvox-aural-profile-applied-hook id))
      (unless state-committed
        (setq
         emacsvox-aural-active-scheme old-scheme
         emacsvox-aural-feature-fragment-order old-fragment-order
         emacsvox-aural-enabled-feature-fragments old-fragments
         emacsvox-aural-voice-palette-override old-palette
         emacsvox-aural-active-profile old-profile)
        (emacsvox-aural--apply-profile-spatial old-spatial)
        (when old-pack
          (ignore-errors
            (let ((emacsvox-sounds--silent-theme-selection t))
              (emacsvox-sounds-select-theme old-pack))))))
    id))

(defun emacsvox-aural-profile-differences (id &optional _source-buffer)
  "Return structured differences between profile ID and live settings.

Each result is a plist containing `:field', `:label', `:saved', and `:live'.
Only global settings governed by the saved profile are compared.  The optional
source-buffer argument is retained for older callers but is ignored."
  (when-let* ((entry (emacsvox-aural-profile-entry id)))
    (let* ((data (emacsvox-aural-profile-entry-data entry))
           (spatial (plist-get data :spatial))
           (palette (plist-get data :voice-palette))
           (live-palette
            (or
             emacsvox-aural-voice-palette-override
             (emacsvox-aural-effective-scheme-provider 'voice-palette)))
           (pack
            (or
             (plist-get data :sound-pack)
             (emacsvox-aural-effective-scheme-provider
              'resource-pack 'default)))
           differences)
      (cl-labels
          ((record (field label saved live same-p)
             (unless same-p
               (push
                (list
                 :field field :label label :saved saved :live live)
                differences))))
        (record
         'feature-fragments "presentation options"
         (plist-get data :feature-fragments)
         emacsvox-aural-enabled-feature-fragments
         (equal
          (plist-get data :feature-fragments)
          emacsvox-aural-enabled-feature-fragments))
        (when (boundp 'emacsvox-sounds-current-pack)
          (record
           'sound-pack "sound pack" pack emacsvox-sounds-current-pack
           (eq pack emacsvox-sounds-current-pack)))
        (record
         'voice-palette "voice palette"
         (or
          palette
          (list
           :source 'baseline
           :value
           (emacsvox-aural-effective-scheme-provider
            'voice-palette 'default)))
         (or
          emacsvox-aural-voice-palette-override
          (list :source 'baseline :value live-palette))
         (if palette
             (eq palette live-palette)
           (null emacsvox-aural-voice-palette-override)))
        (when spatial
          (dolist
              (setting
               (list
                (list
                 :enabled 'spatial-enabled "spatial presentation"
                 emacsvox-aural-spatial-enabled #'eq)
                (list
                 :speech-enabled 'spatial-speech-enabled "spatial speech"
                 emacsvox-aural-spatial-speech-enabled #'eq)
                (list
                 :cue-enabled 'spatial-cue-enabled "spatial cues"
                 emacsvox-aural-spatial-cue-enabled #'eq)
                (list
                 :output 'spatial-output "spatial output"
                 emacsvox-aural-spatial-output #'eq)
                (list
                 :maximum-separation 'spatial-maximum-separation
                 "maximum spatial separation"
                 emacsvox-aural-spatial-maximum-separation #'=)
                (list
                 :remapping 'spatial-remapping "spatial remapping"
                 emacsvox-aural-spatial-remapping #'eq)))
            (pcase-let
                ((`(,key ,field ,label ,live ,predicate) setting))
              (when (plist-member spatial key)
                (let ((saved (plist-get spatial key)))
                  (record
                   field label saved live
                   (funcall predicate saved live)))))))
        (nreverse differences)))))

(defun emacsvox-aural-profile-matches-current-p (id &optional _source-buffer)
  "Return whether live global settings equal profile ID."
  (and
   (emacsvox-aural-profile-entry id)
   (null (emacsvox-aural-profile-differences id))))

(defun emacsvox-aural--profile-valid-p (id)
  "Return non-nil when profile ID still has valid component references."
  (condition-case nil
      (when-let* ((entry (emacsvox-aural-profile-entry id)))
        (emacsvox-aural--validate-profile-data
         (emacsvox-aural-profile-entry-data entry))
        t)
    (error nil)))

(defun emacsvox-aural-profile-status (id &optional _source-buffer)
  "Return live global status for profile ID."
  (cond
   ((not (emacsvox-aural--profile-valid-p id)) 'invalid)
   ((not (eq id emacsvox-aural-active-profile)) 'inactive)
   ((emacsvox-aural-profile-matches-current-p id) 'active)
   (t 'diverged)))

(defun emacsvox-aural-profile-current-p (id &optional _source-buffer)
  "Return whether profile ID is selected and matches live global settings."
  (eq (emacsvox-aural-profile-status id) 'active))

(provide 'emacsvox-aural-profile-service)
;;; emacsvox-aural-profile-service.el ends here
