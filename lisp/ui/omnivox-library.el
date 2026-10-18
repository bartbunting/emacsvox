;;; omnivox-library.el --- Local installed voices and Apply -*- lexical-binding: t; -*-

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

;; The bundled local launcher resolves a native owner for each speech lane.
;; Private stdio management holds the profile lease across paired Apply.
;; Startup records live on the native host; no remote management is provided.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'seq)
(require 'subr-x)
(require 'tabulated-list)
(require 'emacsvox-aural-ui)
(require 'omnivox-library-runtime)

(declare-function emacsvox-aural-voice-workbench "emacsvox-aural-voice-workbench" (&optional view))
(declare-function emacsvox-aural-voice-workbench--open-engine "emacsvox-aural-voice-workbench" (engine parent))
(declare-function emacsvox-aural-voice-workbench--library-action "emacsvox-aural-voice-workbench" (action &optional operation))
(declare-function emacsvox-aural-voice-workbench--library-start "emacsvox-aural-voice-workbench" ())
(declare-function emacsvox-aural-voice-runtime--resolve "emacsvox-aural-voice-runtime" (voice &optional palette profile))
(defvar emacsvox-aural-voice-workbench--library-source)
(defvar omnivox-library-last-removal nil "Most recent package removal result.")
(defvar-local omnivox-library--engine nil)
(defvar-local omnivox-library--index nil)
(defvar-local omnivox-library--index-sha nil)

(defun omnivox-library--confirm (prompt)
  "Ask PROMPT with yes/no completion, defaulting to no."
  (let ((completion-ignore-case t))
    (equal "yes" (downcase (completing-read prompt '("no" "yes") nil t nil nil "no")))))

;;;###autoload
(defun omnivox-library-apply (providers)
  "Review and apply installed enabled voices for PROVIDERS to both speech lanes."
  (interactive (list "both"))
  (when (or omnivox-library--busy (process-live-p omnivox-library--retained-service))
    (user-error "An Apply is active or needs inspection; see omnivox-library-last-result"))
  (unless (and (process-live-p tts-speaker-process) (process-live-p tts-notify-process)
               (not (eq tts-speaker-process tts-notify-process)))
    (user-error "Apply requires separate live main and notification speech processes"))
  (let ((service (omnivox-library--service))
        (old-pair (vector tts-speaker-process tts-notify-process)))
    (unwind-protect
        (let* ((library (omnivox-library--request service '(:command "inspect")))
               (index (plist-get library :index))
               (managed (omnivox-library--managed-providers providers index))
               (previous (vector (omnivox-library--snapshot (aref old-pair 0) 'speaker)
                                 (omnivox-library--snapshot (aref old-pair 1) 'notification)))
               (generation (omnivox-library--uuid))
               (staged (omnivox-library--request service
                                                (append (list :command "stage" :generation generation
                                                      :expected_sha256 (plist-get library :sha256)
                                                      :piper (if (member "piper" managed) t :false)
                                                      :flite (if (member "flite" managed) t :false))
                                                        (when (member "mbrola" managed) '(:mbrola t))
                                                        (when (member "rhvoice" managed) '(:rhvoice t)))))
               (candidate (plist-get staged :candidate))
               (main-startup (omnivox-library--candidate-startup generation 'speaker (aref old-pair 0)))
               (startups
                (vector main-startup
                        (omnivox-library--candidate-startup generation 'notification (aref old-pair 1)
                                                            (plist-get main-startup :startup))))
               (eligible (omnivox-library--eligible index (append (plist-get (aref previous 0) :eligible-voices) nil)
                                                    managed (plist-get (plist-get (aref startups 0) :startup) :policy)))
               (removed (seq-difference (plist-get (aref previous 0) :eligible-voices) eligible #'equal))
               (summary (omnivox-library--enabled-summary index managed))
               (plan (list :operation-id (omnivox-library--uuid) :candidate (plist-get candidate :configuration)
                           :previous-active (omnivox-library--configuration (plist-get library :active))
                           :index-sha256 (plist-get library :sha256)
                           :overridden-engines (vconcat (seq-remove (lambda (id) (member id managed))
                                                                   (plist-get (aref previous 0) :overridden-engines)))
                           :eligible-voices eligible :previous-lanes previous :candidate-startup startups
                           :impact (list :providers (vconcat managed) :removed (vconcat removed)))))
          (with-current-buffer (get-buffer-create "*Omnivox Apply review*")
            (let ((inhibit-read-only t))
              (erase-buffer)
              (insert (format "Apply enabled voices\n\n%s\n\nBoth speech streams will stop and restart.\nFiles and saved palette references are retained.\n\nVoices becoming unavailable: %d\n" summary (length removed)))
              (seq-doseq (voice removed) (insert (format "%s: %s\n" (plist-get voice :engine_id) (plist-get voice :voice_id))))
              (insert "\nIf either replacement fails, both previous configurations will be restored.\n")
              (special-mode)))
          (display-buffer "*Omnivox Apply review*")
          (when (omnivox-library--confirm (format "%s. Apply and restart both speech streams? " summary))
            (let ((result (omnivox-library--execute service plan old-pair)))
              (message "Voice library: %s%s" (plist-get result :status)
                       (if-let* ((failures (plist-get result :failures)))
                           (format "; %s" (plist-get (car failures) :reason))
                         (format "; %s" summary)))
              result)))
      (unless (eq service omnivox-library--retained-service)
        (when (process-live-p service) (delete-process service))))))

(defun omnivox-library--enabled-summary (index providers)
  "Describe desired enablement in INDEX for the selected PROVIDERS."
  (mapconcat
   (lambda (engine)
     (let ((count (seq-count (lambda (voice)
                              (and (equal engine (plist-get voice :engine_id))
                                   (eq t (plist-get voice :enabled))))
                            (plist-get index :voices))))
       (if (zerop count) (format "No %s voices enabled" (capitalize engine))
         (format "%d %s voice%s enabled" count (capitalize engine) (if (= count 1) "" "s")))))
   providers "; "))

(defconst omnivox-library--empty-help
  "No voices have been added to this library.

This screen lists managed voices, including disabled voices.
Press d to browse downloadable voices.
Press b to add the bundled Flite SLT voice, then a to review Apply.
Press q to return to engine details.
"
  "Explanation displayed when the managed voice library is empty.")

(defun omnivox-library-refresh ()
  "Refresh installed metadata without loading models or changing speech."
  (interactive)
  (if (derived-mode-p 'emacsvox-aural-voice-workbench-mode)
      (emacsvox-aural-voice-workbench--library-start)
    (let ((service (omnivox-library--service)))
      (unwind-protect
          (let ((reply (omnivox-library--request service '(:command "inspect"))))
            (setq omnivox-library--index (plist-get reply :index)
                  omnivox-library--index-sha (plist-get reply :sha256)
                  tabulated-list-entries
                  (mapcar (lambda (row)
                            (list (cons (plist-get row :engine_id) (plist-get row :physical_id))
                                  (vector (plist-get row :engine_id) (plist-get row :display_name)
                                          (if (eq (plist-get row :enabled) t) "Enabled" "Disabled")
                                          (plist-get row :physical_id))))
                          (seq-filter (lambda (row)
                                        (or (null omnivox-library--engine)
                                            (equal omnivox-library--engine (plist-get row :engine_id))))
                                      (plist-get omnivox-library--index :voices))))
            (tabulated-list-print t)
            (unless tabulated-list-entries
              (let ((inhibit-read-only t))
                (insert (if (equal omnivox-library--engine "piper")
                            "No Piper voices have been added.\n\nPress d to browse downloadable voices; q returns to engine details.\n"
                          omnivox-library--empty-help))
                (goto-char (point-min)))))
        (when (process-live-p service) (delete-process service))))))

(defun omnivox-library-toggle ()
  "Toggle desired enablement of the installed voice at point. Apply is separate."
  (interactive)
  (if (derived-mode-p 'emacsvox-aural-voice-workbench-mode)
      (emacsvox-aural-voice-workbench--library-action 'toggle)
    (let* ((id (or (tabulated-list-get-id) (user-error "No installed voice on this row")))
           (row (seq-find (lambda (row) (and (equal (car id) (plist-get row :engine_id))
                                             (equal (cdr id) (plist-get row :physical_id))))
                          (plist-get omnivox-library--index :voices)))
           (service (omnivox-library--service)))
      (unwind-protect
          (omnivox-library--request service (list :command "enable" :engine (car id) :voice (cdr id)
                                                  :enabled (if (eq (plist-get row :enabled) t) :false t)
                                                  :expected_sha256 omnivox-library--index-sha))
        (when (process-live-p service) (delete-process service)))
      (omnivox-library-refresh)
      (run-hooks 'omnivox-library--changed-hook)
      (message "%s %s; press a to review and Apply"
               (plist-get row :display_name)
               (if (eq (plist-get row :enabled) t) "disabled" "enabled")))))

(defun omnivox-library-import-validated (operation)
  "Install a successfully validated native OPERATION, initially disabled."
  (interactive "sNative validation operation UUID: ")
  (if (derived-mode-p 'emacsvox-aural-voice-workbench-mode)
      (emacsvox-aural-voice-workbench--library-action 'import operation)
    (omnivox-library-apply--uuid operation)
    (let ((service (omnivox-library--service)))
      (unwind-protect
          (omnivox-library--request service (list :command "import" :operation operation
                                                  :package (omnivox-library--uuid) :revision (omnivox-library--uuid)
                                                  :expected_sha256 omnivox-library--index-sha))
        (when (process-live-p service) (delete-process service))))
    (omnivox-library-refresh)
    (run-hooks 'omnivox-library--changed-hook)
    (message "Voices installed disabled; original files retained")))

(defun omnivox-library-include-flite-slt ()
  "Include built-in Flite SLT in desired state, enabled for the next Apply."
  (interactive)
  (if (derived-mode-p 'emacsvox-aural-voice-workbench-mode)
      (emacsvox-aural-voice-workbench--library-action 'slt)
    (when (equal omnivox-library--engine "piper")
      (user-error "Bundled SLT belongs to Flite; open the Flite library to add it"))
    (let ((service (omnivox-library--service)))
      (unwind-protect
          (omnivox-library--request service (list :command "include-flite-slt"
                                                  :expected_sha256 omnivox-library--index-sha))
        (when (process-live-p service) (delete-process service))))
    (omnivox-library-refresh)
    (run-hooks 'omnivox-library--changed-hook)
    (message "Built-in Flite SLT included and enabled for the next Apply")))

(defun omnivox-library--removal-references (voices)
  "List known palette choices referring to package VOICES, without editing them."
  (require 'emacsvox-aural-voice-runtime)
  (let (references)
    (dolist (name (emacsvox-aural-voice-palette-candidates))
      (let ((palette (intern name)))
        (dolist (entry (emacsvox-aural-effective-voice-entries palette))
          (let ((selectors (plist-get
                            (emacsvox-aural-voice-runtime--resolve (car entry) palette)
                            :selectors)))
            (when (seq-some
                   (lambda (selector)
                     (and (eq (plist-get selector :kind) 'exact)
                          (seq-some (lambda (voice)
                                      (and (equal (plist-get selector :engine-id) (plist-get voice :engine_id))
                                           (equal (plist-get selector :voice-id) (plist-get voice :physical_id))))
                                    voices)))
                   selectors)
              (push (format "%s / %s" name (car entry)) references))))))
    (sort (delete-dups references) #'string-lessp)))

(defun omnivox-library--removal-review (review references)
  "Display immutable package REVIEW and known palette REFERENCES."
  (with-current-buffer (get-buffer-create "*Omnivox uninstall review*")
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert (format "Uninstall %s\n\n%d bytes of managed package files.\n\nAffected voices sharing this package:\n"
                      (plist-get review :name) (plist-get review :package_bytes)))
      (seq-doseq (voice (plist-get review :voices))
        (insert (format "%s: %s\n" (plist-get voice :engine_id) (plist-get voice :display_name))))
      (insert "\nKnown palette references (kept for later reinstallation):\n")
      (insert (if references (mapconcat #'identity references "\n") "None found in loaded palettes"))
      (insert "\n\nBuilt-in voices, imported files and engine runtimes are retained.\n")
      (insert "Both speech streams keep running. Uninstall requires voices to be disabled and applied first.\n")
      (when (> (length (plist-get review :blockers)) 0)
        (insert "\nFiles retained because:\n")
        (seq-doseq (reason (plist-get review :blockers)) (insert (concat reason "\n"))))
      (special-mode)
      (goto-char (point-min))))
  (display-buffer "*Omnivox uninstall review*"))

(defun omnivox-library--removal-execute (service review source)
  "Review then submit removal on SERVICE, checking the captured SOURCE."
  (unless (and (stringp (plist-get review :operation_id))
               (stringp (plist-get review :plan_sha256))
               (integerp (plist-get review :package_bytes)))
    (error "Incomplete uninstall review from Omnivox"))
  (let ((references (omnivox-library--removal-references (plist-get review :voices))))
    (omnivox-library--removal-review review references)
    (when (> (length (plist-get review :blockers)) 0)
      (user-error "Uninstall blocked: %s; see the uninstall review"
                  (elt (plist-get review :blockers) 0)))
    (when (omnivox-library--confirm
           (format "Uninstall %s and all %d listed voices, retaining palette choices? "
                   (plist-get review :name) (length (plist-get review :voices))))
      (unless (and (equal source (omnivox-library--source-key))
                   (equal references (omnivox-library--removal-references (plist-get review :voices))))
        (user-error "Target or palette references changed; review uninstallation again"))
      ;; On a lost reply, preserve uncertainty and expose durable native recovery.
      (setq omnivox-library-last-removal
            (list :operation_id (plist-get review :operation_id) :status "unconfirmed"
                  :detail "Reply not confirmed; use Resume incomplete uninstallation"))
      (let* ((reply (omnivox-library--request
                     service (list :command "uninstall" :operation (plist-get review :operation_id)
                                   :expected_sha256 (plist-get review :plan_sha256))))
             (result (plist-get reply :result)))
        (unless (and (equal (plist-get reply :type) "removal")
                     (equal (plist-get result :operation_id) (plist-get review :operation_id)))
          (error "Uninstall result was not correlated with its reviewed operation"))
        (setq omnivox-library-last-removal result)
        (with-current-buffer (get-buffer-create "*Omnivox uninstall result*")
          (let ((inhibit-read-only t))
            (erase-buffer)
            (insert (format "%s: %s\n\n%d bytes confirmed removed.\n%d bytes remain.\n%d missing bytes have no confirmed deletion receipt.\n\nCounts describe package files; filesystem free-space changes can differ.\nSaved palette choices remain available for reinstallation.\n"
                            (plist-get review :name) (plist-get result :status)
                            (plist-get result :removed_bytes) (plist-get result :remaining_bytes)
                            (plist-get result :unconfirmed_bytes)))
            (insert (concat (plist-get result :detail) "\n"))
            (special-mode)))
        (display-buffer "*Omnivox uninstall result*")
        (run-hooks 'omnivox-library--changed-hook)
        (message "Uninstall %s: %d bytes removed; %d remain%s"
                 (plist-get result :status) (plist-get result :removed_bytes)
                 (plist-get result :remaining_bytes)
                 (if (> (plist-get result :unconfirmed_bytes) 0) "; some deletion amounts unconfirmed" ""))
        result))))

(defun omnivox-library--removal-supported (service)
  "Require explicit uninstall capability from SERVICE before sending mutations."
  (unless (eql (plist-get (omnivox-library--request service '(:command "host")) :removal_version) 1)
    (user-error "This Omnivox version does not support voice uninstallation")))

;;;###autoload
(defun omnivox-library-uninstall ()
  "Review and uninstall the selected managed Piper, Flite or MBROLA package.
All its speakers must be disabled and applied first.  Keep palette choices,
imported files, built-in voices and files still needed by speech sessions."
  (interactive)
  (when (or omnivox-library--busy (process-live-p omnivox-library--retained-service))
    (user-error "An Apply is active or needs inspection"))
  (let* ((combined (derived-mode-p 'emacsvox-aural-voice-workbench-mode))
         (id (or (tabulated-list-get-id) (user-error "Choose an installed voice first")))
         (engine (car-safe id))
         (voice (and (consp id) (if combined (cadr id) (cdr id))))
         (source (omnivox-library--source-key))
         service
         (omnivox-library--busy t)
         (omnivox-library--timeout 300))
    (unless (and (stringp engine) (stringp voice)) (user-error "Choose an installed physical voice"))
    (when (and combined (not (equal source emacsvox-aural-voice-workbench--library-source)))
      (user-error "Speech target changed; refresh the Voice Workbench before uninstalling"))
    (setq service (omnivox-library--service))
    (unwind-protect
        (progn
          (omnivox-library--removal-supported service)
          (let* ((library (omnivox-library--request service '(:command "inspect")))
                 (reply (omnivox-library--request
                         service (list :command "uninstall-preview" :engine engine :voice voice
                                       :expected_sha256 (plist-get library :sha256)))))
            (omnivox-library--removal-execute service (plist-get reply :review) source)))
      (when (process-live-p service) (delete-process service)))))

;;;###autoload
(defun omnivox-library-resume-uninstall ()
  "Review and resume an incomplete native package uninstallation."
  (interactive)
  (when (or omnivox-library--busy (process-live-p omnivox-library--retained-service))
    (user-error "An Apply is active or needs inspection"))
  (let ((source (omnivox-library--source-key))
        (service (omnivox-library--service))
        (omnivox-library--busy t)
        (omnivox-library--timeout 300))
    (unwind-protect
        (progn
          (omnivox-library--removal-supported service)
          (let* ((reply (omnivox-library--request service '(:command "uninstall-pending")))
                 (choices (seq-map (lambda (review)
                                     (cons (format "%s (%s)" (plist-get review :name) (plist-get review :operation_id)) review))
                                   (plist-get reply :reviews))))
            (unless choices (user-error "No incomplete package uninstallations"))
            (omnivox-library--removal-execute
             service (cdr (assoc (completing-read "Resume package cleanup: " choices nil t) choices)) source)))
      (when (process-live-p service) (delete-process service)))))

(defun omnivox-library-show-result ()
  "Show the last Apply outcome and any retained native process attempts."
  (interactive)
  (unless omnivox-library-last-result (user-error "No Apply result in this Emacs session"))
  (with-current-buffer (get-buffer-create "*Omnivox Apply result*")
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert (format "Voice library: %s\n\n" (plist-get omnivox-library-last-result :status)))
      (dolist (failure (plist-get omnivox-library-last-result :failures))
        (insert (format "%s: %s\n" (plist-get failure :phase) (plist-get failure :reason))))
      (dolist (process (delq nil (delete-dups (copy-sequence omnivox-library--retained-processes))))
        (insert (format "\n%s: connection %s; native cleanup %s; owner %s\n"
                        (process-name process) (process-status process)
                        (if (process-get process 'omnivox-library-retired) "confirmed" "not confirmed")
                        (plist-get (process-get process 'omnivox-library-owner) :worker))))
      (goto-char (point-min)) (special-mode)))
  (pop-to-buffer "*Omnivox Apply result*"))

(defun omnivox-library-download ()
  "Browse downloadable voices for this library engine."
  (interactive)
  (require 'omnivox-catalogue)
  (omnivox-catalogue omnivox-library--engine))

(defvar-keymap omnivox-library-mode-map
  :doc "Installed-voice actions."
  "d" #'omnivox-library-download "g" #'omnivox-library-refresh "e" #'omnivox-library-toggle
  "a" #'omnivox-library-apply "i" #'omnivox-library-import-validated
  "u" #'omnivox-library-uninstall "C-c u" #'omnivox-library-resume-uninstall
  "b" #'omnivox-library-include-flite-slt "r" #'omnivox-library-show-result)

(defun omnivox-library--speak-row (&optional actions)
  "Speak the selected voice and desired state, optionally with ACTIONS."
  (if (null tabulated-list-entries)
      (emacsvox-aural-ui-speak
       (if (equal omnivox-library--engine "piper")
           "No Piper voices added. Press d to download voices; q returns."
         "No voices added. Press d to download voices; b includes bundled Flite SLT; q returns."))
    (when-let* ((row (tabulated-list-get-entry)))
      (emacsvox-aural-ui-speak
       (concat (format "%s. %s. %s" (aref row 0) (aref row 1) (aref row 2))
               (when actions
                 (format ". Press e to %s; a reviews Apply"
                         (if (equal "Enabled" (aref row 2)) "disable" "enable"))))))))

(define-derived-mode omnivox-library-mode emacsvox-aural-tabulated-mode "Omnivox Voices"
  "Installed voices: e toggles enablement; a reviews Apply; i installs an import."
  (emacsvox-aural-ui-configure-tabulated
   "Installed Omnivox voices"
   #'omnivox-library--speak-row #'omnivox-library-refresh
   #'omnivox-library--speak-row)
  (setq tabulated-list-format [("Engine" 10 t) ("Voice" 28 t) ("Desired state" 14 t) ("Physical ID" 0 nil)])
  (setq header-line-format "d download; e enable/disable; a Apply; u uninstall; C-c u resume cleanup; b include SLT; i import; r result; g refresh; q back")
  (tabulated-list-init-header))

;;;###autoload
(defun omnivox-library (&optional engine)
  "Open installed voices on the local speech target, optionally for ENGINE."
  (interactive)
  (require 'emacsvox-aural-voice-workbench)
  (if engine
      (emacsvox-aural-voice-workbench--open-engine engine (current-buffer))
    (emacsvox-aural-voice-workbench 'physical)))

(provide 'omnivox-library)
;;; omnivox-library.el ends here
