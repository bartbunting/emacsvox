;;; emacsvox-aural-doctor.el --- Spoken aural diagnostics -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Diagnose the running aural installation and configuration without starting
;; a speech server or changing presentation state.  Safe, deterministic repairs
;; are explicit commands from the spoken report.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'tabulated-list)
(require 'emacsvox-aural-tools)

(defvar emacsvox-keymap)
(defvar emacsvox-prefix)
(defvar tts-speaker-process)

(declare-function
 emacsvox-aural-profiles--current-id "emacsvox-aural-profiles")

(cl-defstruct
    (emacsvox-aural-doctor-finding
     (:constructor emacsvox-aural-doctor--make-finding))
  "One installation or configuration diagnostic."
  id severity check status detail repair)

(defvar-local emacsvox-aural-doctor-findings nil
  "Findings displayed in the current Aural Doctor buffer.")

(defconst emacsvox-aural-doctor--loaded-entry-points
  '((aural-home emacsvox-aural)
    (point-explanation emacsvox-explain-aural-presentation)
    (protocol-boundary tts--protocol-queue-text)
    (aural-keymap emacsvox-keymap-update))
  "Functions whose loaded files identify the active aural installation.")

(defun emacsvox-aural-doctor--finding
    (id severity check status detail &optional repair)
  "Construct a finding with ID, SEVERITY, CHECK, STATUS, DETAIL, and REPAIR."
  (emacsvox-aural-doctor--make-finding
   :id id :severity severity :check check :status status
   :detail detail :repair repair))

(defun emacsvox-aural-doctor--binding-finding
    (id keys expected description)
  "Diagnose binding KEYS against EXPECTED for DESCRIPTION under finding ID."
  (let ((actual (key-binding (kbd keys))))
    (if (eq actual expected)
        (emacsvox-aural-doctor--finding
         id 'ok description "correct"
         (format "%s runs %s" keys expected))
      (emacsvox-aural-doctor--finding
       id 'error description "incorrect"
       (format "%s runs %S; expected %S" keys actual expected)
       '(emacsvox-aural-doctor-restore-bindings)))))

(defun emacsvox-aural-doctor--source-for-loaded-file (file)
  "Return the likely source file corresponding to loaded FILE."
  (cond
   ((string-suffix-p ".elc" file)
    (concat (string-remove-suffix ".elc" file) ".el"))
   ((string-suffix-p ".el" file) file)))

(defun emacsvox-aural-doctor--loaded-file-finding (id function)
  "Diagnose the file providing FUNCTION under finding ID."
  (let ((loaded (symbol-file function 'defun)))
    (cond
     ((not loaded)
      (emacsvox-aural-doctor--finding
       id 'error (symbol-name function) "not loaded"
       "No function definition has a recorded source file"))
     (t
      (let* ((loaded (expand-file-name loaded))
             (source (emacsvox-aural-doctor--source-for-loaded-file loaded))
             (compiled (string-suffix-p ".elc" loaded))
             (stale
              (and compiled source (file-exists-p source)
                   (file-newer-than-file-p source loaded))))
        (if stale
            (emacsvox-aural-doctor--finding
             id 'warning (symbol-name function) "stale byte-code"
             (format "Loaded %s, but %s is newer" loaded source)
             (list 'emacsvox-aural-doctor-reload-source source))
          (emacsvox-aural-doctor--finding
           id 'info (symbol-name function)
           (if compiled "byte-compiled" "source")
           loaded)))))))

(defun emacsvox-aural-doctor--scheme-finding ()
  "Diagnose the active base scheme."
  (condition-case error
      (let ((report
             (emacsvox-aural-validate-scheme
              emacsvox-aural-active-scheme)))
        (if (emacsvox-aural-validation-report-valid report)
            (emacsvox-aural-doctor--finding
             'active-scheme 'ok "Active scheme" "valid"
             (format "%s" emacsvox-aural-active-scheme))
          (emacsvox-aural-doctor--finding
           'active-scheme 'error "Active scheme" "invalid"
           (format
            "%s: %s"
            emacsvox-aural-active-scheme
            (string-join
             (emacsvox-aural-validation-report-errors report) "; ")))))
    (error
     (emacsvox-aural-doctor--finding
      'active-scheme 'error "Active scheme" "unavailable"
      (error-message-string error)))))

(defun emacsvox-aural-doctor--fragment-finding ()
  "Diagnose the ordered enabled feature fragments."
  (condition-case error
      (progn
        (emacsvox-aural--validate-enabled-feature-fragments
         emacsvox-aural-enabled-feature-fragments)
        (emacsvox-aural-doctor--finding
         'feature-fragments 'ok "Feature fragments" "valid"
         (if emacsvox-aural-enabled-feature-fragments
             (mapconcat
              #'symbol-name emacsvox-aural-enabled-feature-fragments ", ")
           "None enabled")))
    (error
     (emacsvox-aural-doctor--finding
      'feature-fragments 'error "Feature fragments" "invalid"
      (error-message-string error)))))

(defun emacsvox-aural-doctor--profile-finding ()
  "Report saved profiles and selected-profile status."
  (require 'emacsvox-aural-profiles)
  (let ((count (hash-table-count emacsvox-aural-profile-registry))
        (current (emacsvox-aural-profiles--current-id)))
    (emacsvox-aural-doctor--finding
     'presentation-profile 'info "Presentation profile"
     (cond
      (current
       (format
        "%s %s"
        current (emacsvox-aural-profile-status current)))
      ((zerop count) "none saved")
      (t "none selected"))
     (format "%d saved profile%s"
             count (if (= count 1) "" "s")))))

(defun emacsvox-aural-doctor--sound-finding ()
  "Diagnose the selected concrete sound pack and its resources."
  (condition-case error
      (progn
        (emacsvox-aural-refresh-discovered-resource-packs)
        (let* ((scheme-pack
                (emacsvox-aural-effective-scheme-provider 'resource-pack))
               (selected
                (and
                 (boundp 'emacsvox-sounds-current-pack)
                 emacsvox-sounds-current-pack))
               (effective
                (or
                 (and selected (emacsvox-aural-resource-pack selected)
                      selected)
                 scheme-pack))
               (report
                (and effective
                     (emacsvox-aural-validate-resource-pack effective))))
          (cond
           ((not effective)
            (emacsvox-aural-doctor--finding
             'sound-pack 'error "Sound pack" "none"
             "Neither the selected theme nor active scheme provides a sound pack"
             '(emacsvox-aural-doctor-refresh-sound-packs)))
           ((emacsvox-aural-resource-report-valid report)
            (emacsvox-aural-doctor--finding
             'sound-pack 'ok "Sound pack" "valid"
             (format
              "Effective %s; selected %s; scheme %s"
              effective (or selected "none") (or scheme-pack "none"))
             '(emacsvox-aural-doctor-refresh-sound-packs)))
           (t
            (emacsvox-aural-doctor--finding
             'sound-pack 'error "Sound pack" "invalid"
             (format
              "%s; missing %S; unknown %S; missing directory %s"
              effective
              (emacsvox-aural-resource-report-missing-required report)
              (emacsvox-aural-resource-report-unknown-assets report)
              (emacsvox-aural-resource-report-missing-directory report))
             '(emacsvox-aural-doctor-refresh-sound-packs))))))
    (error
     (emacsvox-aural-doctor--finding
      'sound-pack 'error "Sound pack" "unavailable"
      (error-message-string error)
      '(emacsvox-aural-doctor-refresh-sound-packs)))))

(defun emacsvox-aural-doctor--personal-data-finding ()
  "Diagnose the data-only personal aural configuration."
  (cond
   ((not (file-exists-p emacsvox-aural-schemes-file))
    (emacsvox-aural-doctor--finding
     'personal-data 'info "Personal data" "not created"
     (abbreviate-file-name emacsvox-aural-schemes-file)))
   (t
    (condition-case error
        (progn
          (emacsvox-aural-read-user-data emacsvox-aural-schemes-file)
          (emacsvox-aural-doctor--finding
           'personal-data 'ok "Personal data" "valid"
           (abbreviate-file-name emacsvox-aural-schemes-file)
           '(emacsvox-aural-doctor-reload-personal-data)))
      (error
       (emacsvox-aural-doctor--finding
        'personal-data 'error "Personal data" "invalid"
        (error-message-string error)))))))

(defun emacsvox-aural-doctor--spatial-finding ()
  "Report spatial policy and available backend capabilities."
  (emacsvox-aural-doctor--finding
   'spatial 'info "Spatial presentation"
   (if emacsvox-aural-spatial-enabled "enabled" "disabled")
   (format
    "Output %s; speech %s; cues %s; capabilities %S"
    emacsvox-aural-spatial-output
    (if emacsvox-aural-spatial-speech-enabled "on" "off")
    (if emacsvox-aural-spatial-cue-enabled "on" "off")
    (emacsvox-aural-spatial-capabilities))))

(defun emacsvox-aural-doctor--speech-server-finding ()
  "Report live speech-server state without starting it."
  (let ((live (and tts-speaker-process
                   (process-live-p tts-speaker-process))))
    (emacsvox-aural-doctor--finding
     'speech-server 'info "Speech server"
     (if live "running" "not running")
     (if live
         (format "%s" (process-name tts-speaker-process))
       "Speech starts the configured server on demand"))))

(defun emacsvox-aural-doctor--training-finding ()
  "Report whether semantic training feedback is active."
  (emacsvox-aural-doctor--finding
   'training 'info "Training feedback"
   (if emacsvox-aural-training-mode "enabled" "disabled")
   "Training adds a concise semantic explanation after presentations"))

(defun emacsvox-aural-doctor--face-presentation-finding ()
  "Report independent explicit-face and legacy Voice Lock controls."
  (let ((source (emacsvox-aural-inspection-source-buffer)))
    (emacsvox-aural-doctor--finding
     'face-presentation 'info "Visual face presentation"
     (format
      "face %s; Voice Lock %s"
      (if emacsvox-aural-face-presentation-enabled "enabled" "disabled")
      (if (emacsvox-aural-voice-lock-enabled-p source) "enabled" "disabled"))
     (concat
      "Explicit :legacy-face scheme rules use the global face control. "
      "Voice Lock is per buffer and controls only legacy face/personality "
      "voice mapping. Semantic presentation remains active."))))

(defun emacsvox-aural-doctor-run ()
  "Return current aural installation and configuration findings."
  (append
   (list
    (emacsvox-aural-doctor--binding-finding
     'home-binding "C-e H" 'emacsvox-aural "Aural home binding")
    (emacsvox-aural-doctor--binding-finding
     'explain-binding "C-e E" 'emacsvox-aural-explain-presentation
     "Point explanation binding"))
   (mapcar
    (lambda (entry)
      (emacsvox-aural-doctor--loaded-file-finding
       (car entry) (cadr entry)))
    emacsvox-aural-doctor--loaded-entry-points)
   (list
    (emacsvox-aural-doctor--scheme-finding)
    (emacsvox-aural-doctor--fragment-finding)
    (emacsvox-aural-doctor--profile-finding)
    (emacsvox-aural-doctor--sound-finding)
    (emacsvox-aural-doctor--personal-data-finding)
    (emacsvox-aural-doctor--spatial-finding)
    (emacsvox-aural-doctor--face-presentation-finding)
    (emacsvox-aural-doctor--speech-server-finding)
    (emacsvox-aural-doctor--training-finding))))

(defun emacsvox-aural-doctor-summary (&optional findings)
  "Return a concise spoken summary of FINDINGS or a fresh diagnostic run."
  (let* ((findings (or findings (emacsvox-aural-doctor-run)))
         (errors
          (cl-count 'error findings
                    :key #'emacsvox-aural-doctor-finding-severity))
         (warnings
          (cl-count 'warning findings
                    :key #'emacsvox-aural-doctor-finding-severity)))
    (cond
     ((> errors 0)
      (format
       "%d %s and %d %s"
       errors (if (= errors 1) "problem" "problems")
       warnings (if (= warnings 1) "warning" "warnings")))
     ((> warnings 0)
      (format
       "No problems; %d %s"
       warnings (if (= warnings 1) "warning" "warnings")))
     (t "All checks passed"))))

(defun emacsvox-aural-doctor-restore-bindings ()
  "Restore the documented aural home and point-explanation bindings."
  (interactive)
  (define-key emacsvox-keymap (kbd "H") #'emacsvox-aural)
  (define-key
   emacsvox-keymap (kbd "E") #'emacsvox-aural-explain-presentation)
  (global-set-key emacsvox-prefix emacsvox-keymap)
  t)

(defun emacsvox-aural-doctor-reload-source (source)
  "Reload newer aural SOURCE exactly."
  (unless (and (stringp source) (file-readable-p source))
    (user-error "Aural source is not readable: %S" source))
  (load source nil nil t)
  source)

(defun emacsvox-aural-doctor-reload-personal-data ()
  "Reload the validated personal aural data file."
  (interactive)
  (emacsvox-aural-load-user-data)
  t)

(defun emacsvox-aural-doctor-refresh-sound-packs ()
  "Refresh dynamically discovered and registered sound packs."
  (interactive)
  (emacsvox-aural-refresh-discovered-resource-packs)
  t)

(defun emacsvox-aural-doctor--finding-at-point ()
  "Return the diagnostic finding at point."
  (let ((id (tabulated-list-get-id)))
    (or
     (cl-find id emacsvox-aural-doctor-findings
              :key #'emacsvox-aural-doctor-finding-id)
     (user-error "Move to a diagnostic row first"))))

(defun emacsvox-aural-doctor--set-entries ()
  "Populate the current doctor buffer."
  (setq emacsvox-aural-doctor-findings (emacsvox-aural-doctor-run))
  (setq
   tabulated-list-entries
   (mapcar
    (lambda (finding)
      (list
       (emacsvox-aural-doctor-finding-id finding)
       (vector
        (emacsvox-aural-doctor-finding-check finding)
        (symbol-name (emacsvox-aural-doctor-finding-severity finding))
        (emacsvox-aural-doctor-finding-status finding)
        (if (emacsvox-aural-doctor-finding-repair finding) "available" "")
        (emacsvox-aural-doctor-finding-detail finding))))
    emacsvox-aural-doctor-findings)))

(defun emacsvox-aural-doctor-refresh (&optional id)
  "Rerun diagnostics, preserving row ID and the current column."
  (interactive)
  (emacsvox-aural-ui-refresh-tabulated
   #'emacsvox-aural-doctor--set-entries id 'home-binding))

(defun emacsvox-aural-doctor-speak-current ()
  "Speak the complete diagnostic finding at point."
  (interactive)
  (let* ((finding (emacsvox-aural-doctor--finding-at-point))
         (summary
          (format
           "%s. %s. %s. %s"
           (emacsvox-aural-doctor-finding-check finding)
           (emacsvox-aural-doctor-finding-severity finding)
           (emacsvox-aural-doctor-finding-status finding)
           (emacsvox-aural-doctor-finding-detail finding))))
    (if (fboundp 'tts-speak)
        (tts-speak summary)
      (message "%s" summary))
    summary))

(defun emacsvox-aural-doctor-speak-current-cell ()
  "Speak the current diagnostic column title and value."
  (interactive)
  (emacsvox-aural-tools--speak-tabulated-cell))

(defun emacsvox-aural-doctor-next ()
  "Move to and speak the next diagnostic finding."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-row 1 "aural doctor"))

(defun emacsvox-aural-doctor-previous ()
  "Move to and speak the previous diagnostic finding."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-row -1 "aural doctor"))

(defun emacsvox-aural-doctor-next-column ()
  "Move right and speak the next diagnostic column."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-column 1))

(defun emacsvox-aural-doctor-previous-column ()
  "Move left and speak the previous diagnostic column."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-column -1))

(defun emacsvox-aural-doctor-repair-current ()
  "Run the deterministic repair offered by the finding at point."
  (interactive)
  (let* ((finding (emacsvox-aural-doctor--finding-at-point))
         (repair (emacsvox-aural-doctor-finding-repair finding)))
    (unless repair
      (user-error "This diagnostic does not have an automatic repair"))
    (apply (car repair) (cdr repair))
    (emacsvox-aural-doctor-refresh
     (emacsvox-aural-doctor-finding-id finding))
    (emacsvox-aural-doctor-speak-current)))

(defun emacsvox-aural-doctor-help ()
  "Display and speak Aural Doctor help."
  (interactive)
  (with-help-window (help-buffer)
    (princ
     (concat
      "Emacsvox Aural Doctor\n\n"
      "The doctor checks the running installation and presentation setup.\n"
      "It does not start the speech server or change settings automatically.\n\n"
      "n or down next       p or up previous\n"
      "left/right column    . speak titled cell\n"
      "SPC speak row        r run the offered safe repair\n"
      "g rerun all checks   h aural home\n"
      "q quit\n")))
  (when (fboundp 'emacsvox-speak-help)
    (emacsvox-speak-help)))

(define-derived-mode emacsvox-aural-doctor-mode
    emacsvox-aural-tabulated-mode
  "Aural-Doctor"
  "Spoken diagnostics for aural presentation."
  (emacsvox-aural-ui-configure-tabulated
   "aural doctor"
   #'emacsvox-aural-doctor-speak-current
   #'emacsvox-aural-doctor-refresh)
  (setq
   tabulated-list-format
   [("Check" 28 t)
    ("Severity" 10 t)
    ("Status" 18 t)
    ("Repair" 11 t)
    ("Detail" 0 t)])
  (setq tabulated-list-padding 2)
  (add-hook
   'tabulated-list-revert-hook #'emacsvox-aural-doctor--set-entries nil t)
  (tabulated-list-init-header))

(dolist
    (binding
     '(("r" . emacsvox-aural-doctor-repair-current)
       ("h" . emacsvox-aural)
       ("?" . emacsvox-aural-doctor-help)))
  (define-key
   emacsvox-aural-doctor-mode-map
   (kbd (car binding))
   (cdr binding)))

;;;###autoload
(defun emacsvox-aural-doctor ()
  "Open the spoken Aural Doctor and announce its overall result."
  (interactive)
  (let ((source
         (emacsvox-aural-inspection-remember-source-buffer))
        (buffer (get-buffer-create "*Aural Doctor*")))
    (with-current-buffer buffer
      (emacsvox-aural-doctor-mode)
      (emacsvox-aural-inspection-attach-source source)
      (emacsvox-aural-doctor-refresh))
    (emacsvox-aural-ui-pop-to-buffer buffer)
    (when (called-interactively-p 'interactive)
      (let ((summary
             (concat
              "Aural Doctor. "
              (emacsvox-aural-doctor-summary
               emacsvox-aural-doctor-findings)
              ".")))
        (if (fboundp 'tts-speak)
            (tts-speak summary)
          (message "%s" summary))))
    buffer))

(provide 'emacsvox-aural-doctor)
;;; emacsvox-aural-doctor.el ends here
