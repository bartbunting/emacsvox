;;; emacsvox-aural-profiles.el --- Spoken presentation profiles -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Accessible management for named configurations that reference existing
;; schemes and fragments while capturing sound, voice, and spatial choices.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'tabulated-list)
(require 'emacsvox-aural-tools)

(defun emacsvox-aural-profiles--ids ()
  "Return registered profile identifiers in display order."
  (mapcar #'intern (emacsvox-aural-profile-candidates)))

(defun emacsvox-aural-profiles--current-id ()
  "Return the selected presentation-profile identifier, or nil."
  (and
   (emacsvox-aural-profile-entry emacsvox-aural-active-profile)
   emacsvox-aural-active-profile))

(defun emacsvox-aural-profiles-status ()
  "Return concise status for presentation profiles."
  (let ((count (hash-table-count emacsvox-aural-profile-registry))
        (current (emacsvox-aural-profiles--current-id)))
    (cond
     (current
      (format
       "%s %s; %d saved"
       current (emacsvox-aural-profile-status current) count))
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
      (symbol-name (emacsvox-aural-profile-status id))
      (symbol-name (plist-get data :scheme))
      (if-let* ((fragments (plist-get data :feature-fragments)))
          (mapconcat #'symbol-name fragments ", ")
        "none")
      (format "%s" (or (plist-get data :sound-pack) "scheme"))
      (format "%s" (or (plist-get data :voice-palette) "scheme"))
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
   (emacsvox-aural-profiles--current-id)))

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
           "%s. %s. Scheme %s. Options %s. Sound %s. Voice %s. Spatial %s. %s"
           (emacsvox-aural-tools--humanize id)
           (emacsvox-aural-profile-status id)
           (plist-get data :scheme)
           (if-let* ((fragments (plist-get data :feature-fragments)))
               (mapconcat
                #'emacsvox-aural-tools--humanize fragments ", ")
             "none")
           (or (plist-get data :sound-pack) "from scheme")
           (or (plist-get data :voice-palette) "from scheme")
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
  (emacsvox-aural-tools--speak-tabulated-cell))

(defun emacsvox-aural-profiles-next ()
  "Move to and speak the next presentation profile."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-row 1 "presentation profiles"))

(defun emacsvox-aural-profiles-previous ()
  "Move to and speak the previous presentation profile."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-row -1 "presentation profiles"))

(defun emacsvox-aural-profiles-next-column ()
  "Move right and speak the next profile column."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-column 1))

(defun emacsvox-aural-profiles-previous-column ()
  "Move left and speak the previous profile column."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-column -1))

(defun emacsvox-aural-profiles-describe (&optional id)
  "Display and speak complete details for profile ID."
  (interactive)
  (let* ((id (or id (emacsvox-aural-profiles--at-point-or-read)))
         (entry (emacsvox-aural-profile-entry id))
         (data (emacsvox-aural-profile-entry-data entry))
         (validation (emacsvox-aural-profiles--validation id)))
    (with-help-window (help-buffer)
      (princ (format "Presentation profile: %s\n\n" id))
      (princ (format "Summary: %s\n" (plist-get data :summary)))
      (princ
       (format
        "Status: %s\n"
        (emacsvox-aural-profile-status id)))
      (princ (format "Scheme: %s\n" (plist-get data :scheme)))
      (princ
       (format
        "Presentation options: %S\n"
        (plist-get data :feature-fragments)))
      (princ (format "Sound pack: %s\n"
                     (or (plist-get data :sound-pack) "from scheme")))
      (princ (format "Voice palette: %s\n"
                     (or (plist-get data :voice-palette) "from scheme")))
      (princ (format "Spatial settings: %S\n"
                     (plist-get data :spatial)))
      (princ
       (format
        "Validation: %s%s\n"
        (if (car validation) "valid" "invalid")
        (if (car validation) "" (format "; %s" (cdr validation)))))
      (princ
       "\nProfiles reference existing components. Edit their rules in the scheme or fragment manager.\n"))
    (when (called-interactively-p 'interactive)
      (emacsvox-aural-profiles-speak-current))
    data))

(defun emacsvox-aural-profiles-activate ()
  "Apply the presentation profile at point."
  (interactive)
  (let ((id (emacsvox-aural-profiles--at-point-or-read)))
    (emacsvox-aural-apply-profile id)
    (emacsvox-aural-save-user-data)
    (emacsvox-aural-profiles-refresh id)
    (emacsvox-aural-home-refresh-if-live)
    (when (called-interactively-p 'interactive)
      (emacsvox-aural-profiles-speak-current))
    id))

(defun emacsvox-aural-profiles-create ()
  "Save the complete current presentation configuration as a new profile."
  (interactive)
  (let* ((id (emacsvox-aural-profiles--read-new-id))
         (old-active emacsvox-aural-active-profile)
         (summary
          (read-string "Profile purpose: "
                       (format "Saved presentation profile %s" id)))
         (data (emacsvox-aural-capture-profile-data id summary)))
    (emacsvox-aural-register-profile
     data :source emacsvox-aural-schemes-file)
    (setq emacsvox-aural-active-profile id)
    (condition-case error
        (emacsvox-aural-save-user-data)
      (error
       (remhash id emacsvox-aural-profile-registry)
       (setq emacsvox-aural-active-profile old-active)
       (signal (car error) (cdr error))))
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
    (emacsvox-aural-register-profile
     data :source emacsvox-aural-schemes-file)
    (condition-case error
        (emacsvox-aural-save-user-data)
      (error
       (remhash id emacsvox-aural-profile-registry)
       (signal (car error) (cdr error))))
    (emacsvox-aural-profiles-refresh id)
    (emacsvox-aural-profiles-speak-current)
    id))

(defun emacsvox-aural-profiles-update-from-current ()
  "Replace the profile at point with the complete current configuration."
  (interactive)
  (let* ((id (emacsvox-aural-profiles--at-point-or-read))
         (old (emacsvox-aural-profile-entry id))
         (old-active emacsvox-aural-active-profile)
         (summary
          (plist-get
           (emacsvox-aural-profile-entry-data old) :summary))
         (data (emacsvox-aural-capture-profile-data id summary)))
    (emacsvox-aural-register-profile
     data :source emacsvox-aural-schemes-file :replace t)
    (setq emacsvox-aural-active-profile id)
    (condition-case error
        (emacsvox-aural-save-user-data)
      (error
       (puthash id old emacsvox-aural-profile-registry)
       (setq emacsvox-aural-active-profile old-active)
       (signal (car error) (cdr error))))
    (emacsvox-aural-profiles-refresh id)
    (emacsvox-aural-profiles-speak-current)
    id))

(defun emacsvox-aural-profiles-rename ()
  "Rename the presentation profile at point."
  (interactive)
  (let* ((old-id (emacsvox-aural-profiles--at-point-or-read))
         (old-entry (emacsvox-aural-profile-entry old-id))
         (old-active emacsvox-aural-active-profile)
         (new-id
          (emacsvox-aural-profiles--read-new-id
           "Rename profile to: " (symbol-name old-id)))
         (data
          (plist-put
           (copy-tree (emacsvox-aural-profile-entry-data old-entry))
           :id new-id)))
    (remhash old-id emacsvox-aural-profile-registry)
    (when (eq old-id emacsvox-aural-active-profile)
      (setq emacsvox-aural-active-profile new-id))
    (condition-case error
        (progn
          (emacsvox-aural-register-profile
           data :source emacsvox-aural-schemes-file)
          (emacsvox-aural-save-user-data))
      (error
       (remhash new-id emacsvox-aural-profile-registry)
       (puthash old-id old-entry emacsvox-aural-profile-registry)
       (setq emacsvox-aural-active-profile old-active)
       (signal (car error) (cdr error))))
    (emacsvox-aural-profiles-refresh new-id)
    (emacsvox-aural-profiles-speak-current)
    new-id))

(defun emacsvox-aural-profiles-delete ()
  "Delete the personal presentation profile at point."
  (interactive)
  (let* ((id (emacsvox-aural-profiles--at-point-or-read))
         (entry (emacsvox-aural-profile-entry id))
         (old-active emacsvox-aural-active-profile))
    (unless (yes-or-no-p (format "Delete presentation profile %s? " id))
      (user-error "Deletion cancelled"))
    (remhash id emacsvox-aural-profile-registry)
    (when (eq id emacsvox-aural-active-profile)
      (setq emacsvox-aural-active-profile nil))
    (condition-case error
        (emacsvox-aural-save-user-data)
      (error
       (puthash id entry emacsvox-aural-profile-registry)
       (setq emacsvox-aural-active-profile old-active)
       (signal (car error) (cdr error))))
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
      "A profile switches one complete named configuration. It references a\n"
      "base scheme and ordered presentation options and captures sound, voice,\n"
      "and spatial choices. Exactly one profile identity can be selected.\n"
      "Active means its saved values match; modified means live settings have\n"
      "changed since selection. Edit rules in the scheme and option managers.\n\n"
      "n or down next       p or up previous\n"
      "left/right column    . speak titled cell\n"
      "RET or a activate    SPC speak profile\n"
      "v view and validate  N save current as new\n"
      "c copy               u update from current\n"
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
    ("Status" 10 t)
    ("Scheme" 20 t)
    ("Options" 28 t)
    ("Sound" 16 t)
    ("Voice" 18 t)
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
       ("u" . emacsvox-aural-profiles-update-from-current)
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
       (or profile (emacsvox-aural-profiles--current-id))))
    (pop-to-buffer buffer)
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
