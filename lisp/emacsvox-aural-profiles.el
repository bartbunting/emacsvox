;;; emacsvox-aural-profiles.el --- Spoken presentation profiles -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: Emacsvox contributors
;; Maintainer: Emacsvox contributors
;; Keywords: accessibility, multimedia
;; URL: https://github.com/bartbunting/emacsvox

;; This file is part of Emacsvox.
;;
;; Emacsvox is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; Emacsvox is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with Emacsvox.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Accessible management for named configurations that select presentation
;; options while capturing sound, voice, and spatial choices.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'tabulated-list)
(require 'emacsvox-aural-schemes)
(require 'emacsvox-aural-profile-service)
(require 'emacsvox-aural-ui)
(require 'emacsvox-aural-inspection)
(require 'emacsvox-aural-description)

(defun emacsvox-aural-profiles--ids ()
  "Return registered profile identifiers in display order."
  (mapcar #'intern (emacsvox-aural-profile-candidates)))

(defalias
  'emacsvox-aural-profiles--current-id
  #'emacsvox-aural-current-profile-id)

(defun emacsvox-aural-profiles--status (id)
  "Return live global profile status for ID."
  (emacsvox-aural-profile-status id))

(defun emacsvox-aural-profiles--differences (id)
  "Return live global differences for profile ID."
  (emacsvox-aural-profile-differences id))

(defun emacsvox-aural-profiles--natural-list (items)
  "Join ITEMS as a concise spoken natural-language list."
  (pcase items
    ('nil "")
    (`(,only) only)
    (`(,first ,second) (format "%s and %s" first second))
    (_
     (format
      "%s, and %s"
      (mapconcat #'identity (butlast items) ", ")
      (car (last items))))))

(defun emacsvox-aural-profiles--difference-labels (differences &optional limit)
  "Summarize DIFFERENCES by label, optionally showing at most LIMIT labels."
  (let* ((labels
          (delete-dups
           (mapcar
            (lambda (difference) (plist-get difference :label))
            differences)))
         (shown (if limit (seq-take labels limit) labels))
         (remaining (- (length labels) (length shown)))
         (summary (emacsvox-aural-profiles--natural-list shown)))
    (if (> remaining 0)
        (format "%s plus %d more" summary remaining)
      summary)))

(defun emacsvox-aural-profiles--status-cell (id)
  "Return concise table status for profile ID."
  (let ((status (emacsvox-aural-profiles--status id)))
    (if (eq status 'diverged)
        (let ((differences (emacsvox-aural-profiles--differences id)))
          (if differences
              (format
               "diverged: %s; v details"
               (emacsvox-aural-profiles--difference-labels differences 2))
            "diverged; v details"))
      (symbol-name status))))

(defun emacsvox-aural-profiles--spoken-status (id)
  "Return accessible status detail for profile ID."
  (let ((status (emacsvox-aural-profiles--status id)))
    (if (eq status 'diverged)
        (let ((differences (emacsvox-aural-profiles--differences id)))
          (if differences
              (format
               "diverged in %s; press v for details"
               (emacsvox-aural-profiles--difference-labels differences))
            "diverged; press v for details"))
      (symbol-name status))))

(defun emacsvox-aural-profiles-status (&optional _source-buffer)
  "Return concise global presentation-profile status."
  (let ((count (hash-table-count emacsvox-aural-profile-registry))
        (current (emacsvox-aural-current-profile-id)))
    (cond
     (current
      (format
       "%s %s; %d saved"
       current
       (emacsvox-aural-profile-status current)
       count))
     ((zerop count) "none saved")
     (t (format "%d saved; no profile selected" count)))))

(defun emacsvox-aural-profiles--validation (id)
  "Return (VALID . DETAIL) for profile ID."
  (condition-case error
      (progn
        (emacsvox-aural--validate-profile-data
         (emacsvox-aural-profile-entry-data
          (emacsvox-aural-profile-entry id)))
        '(t . "valid"))
    (error (cons nil (error-message-string error)))))

(defun emacsvox-aural-profiles--spatial-summary (spatial)
  "Return concise display text for profile SPATIAL settings."
  (if (null spatial)
      "unchanged"
    (format
     "%s/%s"
     (if (plist-get spatial :enabled) "on" "off")
     (or (plist-get spatial :output) "current"))))

(defun emacsvox-aural-profiles--row (id)
  "Return a tabulated row for presentation profile ID."
  (let* ((entry (emacsvox-aural-profile-entry id))
         (data (emacsvox-aural-profile-entry-data entry))
         (validation (emacsvox-aural-profiles--validation id)))
    (list
     id
     (vector
      (symbol-name id)
      (emacsvox-aural-profiles--status-cell id)
      (if-let* ((fragments (plist-get data :feature-fragments)))
          (mapconcat #'symbol-name fragments ", ")
        "none")
      (format "%s" (or (plist-get data :sound-pack) "baseline"))
      (format "%s" (or (plist-get data :voice-palette) "baseline"))
      (emacsvox-aural-profiles--spatial-summary
       (plist-get data :spatial))
      (if (car validation) "valid" "invalid")
      (plist-get data :summary)))))

(defun emacsvox-aural-profiles--set-entries ()
  "Populate the current presentation-profile manager."
  (setq
   tabulated-list-entries
   (mapcar #'emacsvox-aural-profiles--row
           (emacsvox-aural-profiles--ids))))

(defun emacsvox-aural-profiles--goto (id)
  "Move to profile ID and its first column."
  (emacsvox-aural-ui-goto-row id))

(defun emacsvox-aural-profiles-refresh (&optional id)
  "Refresh profiles, preserving ID and the current column."
  (interactive)
  (emacsvox-aural-ui-refresh-tabulated
   #'emacsvox-aural-profiles--set-entries
   id
   (emacsvox-aural-current-profile-id)))

(defun emacsvox-aural-profiles--at-point-or-read ()
  "Return the profile at point or prompt for one."
  (or
   (tabulated-list-get-id)
   (when-let* ((candidates (emacsvox-aural-profile-candidates)))
     (intern
      (completing-read
       "Presentation profile: " candidates nil 'must-match)))
   (user-error
    "No presentation profiles; press N to save the current configuration")))

(defun emacsvox-aural-profiles--read-new-id (&optional prompt initial)
  "Read a new profile identifier with PROMPT and INITIAL input."
  (let* ((text
          (read-string
           (or prompt "New presentation profile name: ")
           initial))
         (id (intern (string-trim text))))
    (when (or (string-empty-p (symbol-name id))
              (keywordp id)
              (eq id nil)
              (eq id t))
      (user-error "Use a non-keyword profile name"))
    (when (emacsvox-aural-profile-entry id)
      (user-error "Presentation profile already exists: %s" id))
    id))

(defun emacsvox-aural-profiles-speak-current ()
  "Speak the complete presentation profile at point."
  (interactive)
  (let* ((id (emacsvox-aural-profiles--at-point-or-read))
         (data
          (emacsvox-aural-profile-entry-data
           (emacsvox-aural-profile-entry id)))
         (summary
          (format
           (concat
            "%s. %s. Options %s. Sound %s. Voice palette %s. "
            "Spatial %s. %s")
           (emacsvox-aural-humanize id)
           (emacsvox-aural-profiles--spoken-status id)
           (if-let* ((fragments (plist-get data :feature-fragments)))
               (mapconcat
                #'emacsvox-aural-humanize fragments ", ")
             "none")
           (or (plist-get data :sound-pack) "from baseline")
           (or (plist-get data :voice-palette) "from baseline")
           (emacsvox-aural-profiles--spatial-summary
            (plist-get data :spatial))
           (plist-get data :summary))))
    (if (fboundp 'tts-speak)
        (tts-speak summary)
      (message "%s" summary))
    summary))

(defun emacsvox-aural-profiles-speak-current-cell ()
  "Speak the current profile column title and value."
  (interactive)
  (emacsvox-aural-ui-speak-current-cell))

(defun emacsvox-aural-profiles-next ()
  "Move to and speak the next presentation profile."
  (interactive)
  (emacsvox-aural-ui-move-row 1 "presentation profiles"))

(defun emacsvox-aural-profiles-previous ()
  "Move to and speak the previous presentation profile."
  (interactive)
  (emacsvox-aural-ui-move-row -1 "presentation profiles"))

(defun emacsvox-aural-profiles-next-column ()
  "Move right and speak the next profile column."
  (interactive)
  (emacsvox-aural-ui-move-column 1))

(defun emacsvox-aural-profiles-previous-column ()
  "Move left and speak the previous profile column."
  (interactive)
  (emacsvox-aural-ui-move-column -1))

(defun emacsvox-aural-profiles--format-difference-value (field value)
  "Return an accessible rendering of difference VALUE for FIELD."
  (cond
   ((memq
     field
     '(spatial-enabled spatial-speech-enabled spatial-cue-enabled))
    (if value "enabled" "disabled"))
   ((eq field 'feature-fragments)
    (if value
        (mapconcat #'emacsvox-aural-humanize value ", then ")
      "none"))
   ((and
     (listp value)
     (eq (plist-get value :source) 'baseline))
    (format
     "from baseline, %s"
     (emacsvox-aural-humanize (plist-get value :value))))
   ((null value) "none")
   ((symbolp value) (emacsvox-aural-humanize value))
   (t (format "%s" value))))

(defun emacsvox-aural-profiles--spoken-differences (differences)
  "Return complete spoken detail for DIFFERENCES."
  (mapconcat
   (lambda (difference)
     (let ((field (plist-get difference :field)))
       (format
        "%s: saved %s; live %s"
        (capitalize (plist-get difference :label))
        (emacsvox-aural-profiles--format-difference-value
         field (plist-get difference :saved))
        (emacsvox-aural-profiles--format-difference-value
         field (plist-get difference :live)))))
   differences
   ". "))

(defun emacsvox-aural-profiles-describe (&optional id)
  "Display and speak complete details for profile ID."
  (interactive)
  (let* ((id (or id (emacsvox-aural-profiles--at-point-or-read)))
         (entry (emacsvox-aural-profile-entry id))
         (data (emacsvox-aural-profile-entry-data entry))
         (validation (emacsvox-aural-profiles--validation id))
         (status (emacsvox-aural-profiles--status id))
         (differences
          (and
           (eq status 'diverged)
           (emacsvox-aural-profiles--differences id))))
    (with-help-window (help-buffer)
      (princ (format "Presentation profile: %s\n\n" id))
      (princ (format "Summary: %s\n" (plist-get data :summary)))
      (princ
       (format
        "Status: %s\n"
        status))
      (princ
       (format
        "Presentation options: %S\n"
        (plist-get data :feature-fragments)))
      (princ (format "Sound pack: %s\n"
                     (or (plist-get data :sound-pack) "from baseline")))
      (princ (format "Voice palette: %s\n"
                     (or (plist-get data :voice-palette) "from baseline")))
      (princ (format "Spatial settings: %S\n"
                     (plist-get data :spatial)))
      (princ
       (format
        "Validation: %s%s\n"
        (if (car validation) "valid" "invalid")
        (if (car validation) "" (format "; %s" (cdr validation)))))
      (when differences
        (princ
         "\nDifferences from live configuration:\n")
        (dolist (difference differences)
          (let ((field (plist-get difference :field)))
            (princ
             (format
              "- %s: saved %s; live %s\n"
              (capitalize (plist-get difference :label))
              (emacsvox-aural-profiles--format-difference-value
               field (plist-get difference :saved))
              (emacsvox-aural-profiles--format-difference-value
               field (plist-get difference :live)))))))
      (princ
       "\nProfiles reference existing options. Edit rules in the option or override manager.\n"))
    (when (called-interactively-p 'interactive)
      (emacsvox-aural-profiles-speak-current)
      (when (and differences (fboundp 'tts-speak))
        (tts-speak
         (concat
          "Divergence details. "
          (emacsvox-aural-profiles--spoken-differences differences)))))
    data))

(defun emacsvox-aural-profiles-activate ()
  "Apply the saved presentation profile at point.

Confirm first when the currently selected profile has diverged, because
applying a saved profile replaces the differing live configuration."
  (interactive)
  (let ((id (emacsvox-aural-profiles--at-point-or-read)))
    (when-let* ((selected (emacsvox-aural-current-profile-id)))
      (when (eq (emacsvox-aural-profile-status selected) 'diverged)
        (unless
            (yes-or-no-p
             (if (eq selected id)
                 (format
                  (concat
                   "Profile %s has diverged. Restore its saved configuration "
                   "and discard the differing live settings? ")
                  id)
               (format
                (concat
                 "Selected profile %s has diverged. Applying saved profile %s "
                 "will discard the differing live settings. Continue? ")
                selected id)))
          (user-error "Apply cancelled; live settings are unchanged"))))
    (emacsvox-aural-apply-profile id)
    (emacsvox-aural-save-user-data)
    (emacsvox-aural-profiles-refresh id)
    (emacsvox-aural-ui-refresh-home-if-live)
    (when (called-interactively-p 'interactive)
      (emacsvox-aural-profiles-speak-current))
    id))

(defun emacsvox-aural-profiles--persist-mutation (mutation)
  "Persist MUTATION against staged profile state, then publish it.

MUTATION is called with copies of the profile registry and selected profile
dynamically installed.  If mutation, validation, or persistence fails, the
live registry and selected profile remain unchanged.  Return the value of
MUTATION."
  (let ((registry (copy-hash-table emacsvox-aural-profile-registry))
        (active-profile emacsvox-aural-active-profile)
        result)
    (let ((emacsvox-aural-profile-registry registry)
          (emacsvox-aural-active-profile active-profile))
      (setq result (funcall mutation)
            active-profile emacsvox-aural-active-profile)
      (emacsvox-aural-save-user-data))
    (setq
     emacsvox-aural-profile-registry registry
     emacsvox-aural-active-profile active-profile)
    result))

(defun emacsvox-aural-profiles-create ()
  "Save the complete current presentation configuration as a new profile."
  (interactive)
  (let* ((id (emacsvox-aural-profiles--read-new-id))
         (summary
          (read-string "Profile purpose: "
                       (format "Saved presentation profile %s" id)))
         (data
          (emacsvox-aural-capture-profile-data
           id summary)))
    (emacsvox-aural-profiles--persist-mutation
     (lambda ()
       (emacsvox-aural-register-profile
        data :source emacsvox-aural-schemes-file)
       (setq emacsvox-aural-active-profile id)))
    (emacsvox-aural-profiles-refresh id)
    (emacsvox-aural-profiles-speak-current)
    id))

(defun emacsvox-aural-profiles-copy ()
  "Copy the profile at point under a new identifier."
  (interactive)
  (let* ((source (emacsvox-aural-profiles--at-point-or-read))
         (source-data
          (emacsvox-aural-profile-entry-data
           (emacsvox-aural-profile-entry source)))
         (id
          (emacsvox-aural-profiles--read-new-id
           "Copy profile as: "
           (format "%s-copy" source)))
         (summary
          (read-string "Copied profile purpose: "
                       (plist-get source-data :summary)))
         (data (plist-put (copy-tree source-data) :id id)))
    (setq data (plist-put data :summary summary))
    (emacsvox-aural-profiles--persist-mutation
     (lambda ()
       (emacsvox-aural-register-profile
        data :source emacsvox-aural-schemes-file)))
    (emacsvox-aural-profiles-refresh id)
    (emacsvox-aural-profiles-speak-current)
    id))

(defun emacsvox-aural-profiles-update-from-current ()
  "Write the complete current configuration into the profile at point."
  (interactive)
  (let* ((id (emacsvox-aural-profiles--at-point-or-read))
         (summary
          (plist-get
           (emacsvox-aural-profile-entry-data
            (emacsvox-aural-profile-entry id))
           :summary))
         (data
          (emacsvox-aural-capture-profile-data
           id summary)))
    (unless
        (yes-or-no-p
         (format
          "Replace saved profile %s with the current live configuration? "
          id))
      (user-error "Write cancelled; saved profile is unchanged"))
    (emacsvox-aural-profiles--persist-mutation
     (lambda ()
       (emacsvox-aural-register-profile
        data :source emacsvox-aural-schemes-file :replace t)
       (setq emacsvox-aural-active-profile id)))
    (emacsvox-aural-profiles-refresh id)
    (emacsvox-aural-profiles-speak-current)
    id))

(defun emacsvox-aural-profiles-rename ()
  "Rename the presentation profile at point."
  (interactive)
  (let* ((old-id (emacsvox-aural-profiles--at-point-or-read))
         (new-id
          (emacsvox-aural-profiles--read-new-id
           "Rename profile to: " (symbol-name old-id)))
         (data
          (plist-put
           (copy-tree
            (emacsvox-aural-profile-entry-data
             (emacsvox-aural-profile-entry old-id)))
           :id new-id)))
    (emacsvox-aural-profiles--persist-mutation
     (lambda ()
       (remhash old-id emacsvox-aural-profile-registry)
       (when (eq old-id emacsvox-aural-active-profile)
         (setq emacsvox-aural-active-profile new-id))
       (emacsvox-aural-register-profile
        data :source emacsvox-aural-schemes-file)))
    (emacsvox-aural-profiles-refresh new-id)
    (emacsvox-aural-profiles-speak-current)
    new-id))

(defun emacsvox-aural-profiles-delete ()
  "Delete the personal presentation profile at point."
  (interactive)
  (let ((id (emacsvox-aural-profiles--at-point-or-read)))
    (unless (yes-or-no-p (format "Delete presentation profile %s? " id))
      (user-error "Deletion cancelled"))
    (emacsvox-aural-profiles--persist-mutation
     (lambda () (emacsvox-aural-delete-profile id)))
    (emacsvox-aural-profiles-refresh)
    (if (tabulated-list-get-id)
        (emacsvox-aural-profiles-speak-current)
      (when (fboundp 'tts-speak)
        (tts-speak "No presentation profiles are saved.")))
    id))

(defun emacsvox-aural-profiles-help ()
  "Display and speak presentation-profile manager help."
  (interactive)
  (with-help-window (help-buffer)
    (princ
     (concat
      "Aural Presentation Profiles\n\n"
      "A profile switches one complete named configuration over Emacsvox's\n"
      "fixed compatibility baseline. It selects ordered presentation options\n"
      "and captures sound-pack, voice-palette, and spatial choices. One profile\n"
      "identity can be selected. Buffer-local Voice Lock is independent.\n"
      "Active means the selected profile matches the live configuration.\n"
      "Diverged means it remains selected but its saved values and the live\n"
      "configuration differ; it does not mean that a write is pending.\n"
      "Press w to replace the saved profile with the current live values.\n"
      "Press a to restore the saved values; this confirms before discarding\n"
      "live differences. Edit rules in the option and override managers.\n\n"
      "n or down next       p or up previous\n"
      "left/right column    . speak titled cell\n"
      "RET or a apply saved SPC speak profile\n"
      "v view and validate  N save current as new\n"
      "c copy               w write current into profile\n"
      "r rename             d delete\n"
      "g refresh            h aural home\n"
      "q quit\n")))
  (when (fboundp 'emacsvox-speak-help)
    (emacsvox-speak-help)))

(define-derived-mode emacsvox-aural-profiles-mode
    emacsvox-aural-tabulated-mode
  "Aural-Profiles"
  "Spoken manager for complete aural presentation profiles."
  (emacsvox-aural-ui-configure-tabulated
   "presentation profiles"
   #'emacsvox-aural-profiles-speak-current
   #'emacsvox-aural-profiles-refresh)
  (setq
   tabulated-list-format
   [("Profile" 24 t)
    ("Status" 48 t)
    ("Options" 28 t)
    ("Sound" 16 t)
    ("Voice Palette" 18 t)
    ("Spatial" 14 t)
    ("Validation" 12 t)
    ("Purpose" 0 t)])
  (setq tabulated-list-padding 2)
  (add-hook
   'tabulated-list-revert-hook #'emacsvox-aural-profiles--set-entries nil t)
  (tabulated-list-init-header))

(defun emacsvox-aural-profiles-refresh-if-live (&rest _ignored)
  "Refresh the presentation-profile manager when it is open."
  (when-let* ((buffer (get-buffer "*Aural Presentation Profiles*")))
    (with-current-buffer buffer
      (when (derived-mode-p 'emacsvox-aural-profiles-mode)
        (emacsvox-aural-profiles-refresh)))))

(add-hook
 'emacsvox-aural-configuration-changed-hook
 #'emacsvox-aural-profiles-refresh-if-live)

(dolist
    (binding
     '(("RET" . emacsvox-aural-profiles-activate)
       ("a" . emacsvox-aural-profiles-activate)
       ("v" . emacsvox-aural-profiles-describe)
       ("N" . emacsvox-aural-profiles-create)
       ("c" . emacsvox-aural-profiles-copy)
       ("w" . emacsvox-aural-profiles-update-from-current)
       ("u" . nil)
       ("r" . emacsvox-aural-profiles-rename)
       ("d" . emacsvox-aural-profiles-delete)
       ("h" . emacsvox-aural)
       ("?" . emacsvox-aural-profiles-help)))
  (define-key
   emacsvox-aural-profiles-mode-map
   (kbd (car binding))
   (cdr binding)))

;;;###autoload
(defun emacsvox-aural-list-profiles (&optional profile)
  "Open the spoken manager for saved presentation PROFILE configurations."
  (interactive)
  (let ((source
         (emacsvox-aural-inspection-remember-source-buffer))
        (buffer (get-buffer-create "*Aural Presentation Profiles*")))
    (with-current-buffer buffer
      (emacsvox-aural-profiles-mode)
      (emacsvox-aural-inspection-attach-source source)
      (emacsvox-aural-profiles-refresh
       (or profile (emacsvox-aural-current-profile-id))))
    (emacsvox-aural-ui-pop-to-buffer buffer)
    (if (tabulated-list-get-id)
        (when (called-interactively-p 'interactive)
          (emacsvox-aural-profiles-speak-current))
      (when (called-interactively-p 'interactive)
        (if (fboundp 'tts-speak)
            (tts-speak
             "No presentation profiles are saved. Press capital N to save the current configuration.")
          (message
           "No presentation profiles are saved; press N to create one."))))
    buffer))

(provide 'emacsvox-aural-profiles)

;;; emacsvox-aural-profiles.el ends here
