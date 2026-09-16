;;; omnivox-catalogue.el --- Available voices and downloads -*- lexical-binding: t; -*-

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

;; Reviewed catalogue data is shipped with Emacsvox.  Omnivox owns network
;; access, native validation and installation.  Progress never changes speech.

;;; Code:

(require 'omnivox-library)
(require 'emacsvox-preamble)

(defvar omnivox-catalogue--operations (make-hash-table :test #'equal))
(defvar-local omnivox-catalogue--engine nil)
(defvar-local omnivox-catalogue--json nil)
(defvar-local omnivox-catalogue--entries nil)
(defvar-local omnivox-catalogue--installed nil)
(defvar-local omnivox-catalogue--voices nil)
(defvar-local omnivox-catalogue--index-sha nil)
(defvar-local omnivox-catalogue--host nil)
(defvar-local omnivox-catalogue--entry nil)
(defvar-local omnivox-catalogue--parent nil)
(defvar-local omnivox-catalogue--query "")
(defvar-local omnivox-catalogue--documents nil)
(defvar-local omnivox-catalogue--metadata nil)
(defvar-local omnivox-catalogue--scope nil)
(defvar-local omnivox-catalogue--history nil)
(defvar-local omnivox-catalogue--show-speakers nil)

(defun omnivox-catalogue-speakers ()
  "Show or hide the speakers sharing this model download."
  (interactive)
  (unless omnivox-catalogue--entry (user-error "Open a model with RET first"))
  (setq omnivox-catalogue--show-speakers (not omnivox-catalogue--show-speakers))
  (omnivox-catalogue--render)
  (message "Speakers %s; each can be enabled separately after installation"
           (if omnivox-catalogue--show-speakers "shown" "hidden")))

(defun omnivox-catalogue--meta (entry field)
  "Return manifest FIELD for ENTRY, keeping native catalogue data separate."
  (plist-get (plist-get omnivox-catalogue--metadata
                        (intern (concat ":" (plist-get entry :id)))) field))

(defun omnivox-catalogue--name (entry)
  "Return the voice set name of ENTRY without its quality choice."
  (or (omnivox-catalogue--meta entry :voice_name) (plist-get entry :name)))

(defun omnivox-catalogue--rows ()
  "Build language, voice set or model rows from cached entries."
  (let* ((searching (not (string-empty-p omnivox-catalogue--query)))
         (entries
          (seq-filter
           (lambda (entry)
             (and (or (null omnivox-catalogue--engine)
                      (equal omnivox-catalogue--engine (plist-get entry :provider)))
                  (if searching
                      (string-match-p
                       (regexp-quote (downcase omnivox-catalogue--query))
                       (downcase (format "%s %s %s" (plist-get entry :name)
                                         (plist-get entry :language)
                                         (omnivox-catalogue--meta entry :language_name))))
                    (and (or (null omnivox-catalogue--scope)
                             (equal (car omnivox-catalogue--scope) (plist-get entry :language)))
                         (or (null (cdr omnivox-catalogue--scope))
                             (equal (cadr omnivox-catalogue--scope) (omnivox-catalogue--name entry)))))))
           omnivox-catalogue--entries))
         (grouping (and omnivox-catalogue--metadata (not searching)
                        (not (equal omnivox-catalogue--engine "flite"))
                        (< (length omnivox-catalogue--scope) 2))))
    (if grouping
        (let ((groups (make-hash-table :test #'equal)) rows)
          (seq-doseq (entry entries)
            (let ((key (if omnivox-catalogue--scope (omnivox-catalogue--name entry)
                         (plist-get entry :language))))
              (puthash key (cons entry (gethash key groups)) groups)))
          (maphash
           (lambda (key members)
             (push (if (and omnivox-catalogue--scope (= 1 (length members)))
                       (omnivox-catalogue--model-row (car members))
                     (list (list 'group key)
                         (vector (if omnivox-catalogue--scope key
                                   (format "%s (%s)" (or (omnivox-catalogue--meta (car members) :language_name) key) key))
                                 "" "" ""
                                 (format "%d %s; RET opens" (length members)
                                         (if omnivox-catalogue--scope "quality choices" "models"))))) rows)) groups)
          (sort rows (lambda (a b) (string-lessp (aref (cadr a) 0) (aref (cadr b) 0)))))
      (mapcar #'omnivox-catalogue--model-row (append entries nil)))))

(defun omnivox-catalogue--model-row (entry)
  "Return a selectable model row for ENTRY."
  (list (plist-get entry :id)
        (vector (plist-get entry :name) (plist-get entry :provider)
                (plist-get entry :language) (omnivox-catalogue--size entry)
                (omnivox-catalogue--status entry))))

(defun omnivox-catalogue--installed-speakers (entry)
  "Return installed library speakers belonging to ENTRY."
  (seq-filter
   (lambda (voice)
     (and (equal (plist-get voice :engine_id) (plist-get entry :provider))
          (seq-some (lambda (projection)
                      (equal (plist-get projection :physical_id) (plist-get voice :physical_id)))
                    (plist-get entry :voices))))
   omnivox-catalogue--voices))

(defun omnivox-catalogue-toggle ()
  "Enable or disable an installed speaker, leaving Apply explicit."
  (interactive)
  (let ((entry (omnivox-catalogue--selected)))
    (omnivox-catalogue-refresh)
    (let* ((voices (append (omnivox-catalogue--installed-speakers entry) nil))
           (choices (mapcar (lambda (voice)
                              (cons (format "%s [%s; speaker %s]" (plist-get voice :display_name)
                                            (if (eq t (plist-get voice :enabled)) "enabled" "disabled")
                                            (plist-get voice :speaker_index)) voice)) voices))
           (voice (cond ((null voices) (user-error "Install this model with i first"))
                        ((= 1 (length voices)) (car voices))
                        (t (cdr (assoc (completing-read "Speaker to enable or disable: " choices nil t) choices)))))
           (service (omnivox-library--service)))
      (unwind-protect
          (progn
            (unless voice (user-error "Choose a speaker first"))
            (unless (equal (omnivox-catalogue--key omnivox-catalogue--host nil)
                           (omnivox-catalogue--key (omnivox-library--request service '(:command "host")) nil))
              (user-error "Speech target changed; reopen the voice catalogue"))
            (omnivox-library--request
             service (list :command "enable" :engine (plist-get voice :engine_id)
                           :voice (plist-get voice :physical_id)
                           :enabled (if (eq t (plist-get voice :enabled)) :false t)
                           :expected_sha256 omnivox-catalogue--index-sha)))
        (when (process-live-p service) (delete-process service)))
      (omnivox-catalogue-refresh)
      (run-hooks 'omnivox-library--changed-hook)
      (message "%s %s; press a to review and Apply to both speech streams"
               (plist-get voice :display_name)
               (if (eq t (plist-get voice :enabled)) "disabled" "enabled")))))

(defun omnivox-catalogue-apply ()
  "Review and Apply enabled voices to both speech streams."
  (interactive)
  (omnivox-catalogue-refresh)
  (call-interactively #'omnivox-library-apply)
  (omnivox-catalogue-refresh))

(defun omnivox-catalogue-back ()
  "Return to the preceding catalogue group or screen."
  (interactive)
  (cond
   ((not (string-empty-p omnivox-catalogue--query))
    (setq omnivox-catalogue--query "")
    (omnivox-catalogue--render)
    (goto-char (point-min))
    (omnivox-catalogue--speak-row))
   (omnivox-catalogue--history
    (pcase-let ((`(,scope ,id ,column) (pop omnivox-catalogue--history)))
      (setq omnivox-catalogue--scope scope)
      (omnivox-catalogue--render)
      (goto-char (point-min))
      (while (and (not (eobp)) (not (equal id (tabulated-list-get-id)))) (forward-line 1))
      (move-to-column column)
      (omnivox-catalogue--speak-row)))
   (t (emacsvox-aural-quit))))

(defun omnivox-catalogue--key (host entry)
  "Identify ENTRY on the exact native HOST."
  (list (plist-get host :root) (plist-get host :target_id)
        (plist-get host :profile_id) (plist-get entry :id)))

(defun omnivox-catalogue--operation (entry)
  "Return the acquisition of ENTRY on this buffer's target."
  (gethash (omnivox-catalogue--key omnivox-catalogue--host entry)
           omnivox-catalogue--operations))

(defun omnivox-catalogue--size (entry)
  "Format the reviewed download size of ENTRY."
  (file-size-human-readable
   (cl-loop for file across (plist-get entry :files) sum (plist-get file :bytes))))

(defun omnivox-catalogue--status (entry)
  "Describe ENTRY without claiming an unfinished process succeeded."
  (let* ((operation (omnivox-catalogue--operation entry))
         (progress (plist-get operation :progress)))
    (cond
     ((seq-some (lambda (package)
                  (equal (plist-get (plist-get package :catalogue) :entry_id)
                         (plist-get entry :id))) omnivox-catalogue--installed)
      (let* ((voices (omnivox-catalogue--installed-speakers entry))
             (enabled (seq-count (lambda (voice) (eq t (plist-get voice :enabled))) voices)))
        (cond ((null voices) "Installed")
              ((zerop enabled) "Installed; disabled")
              (t (format "Installed; %d of %d enabled" enabled (length voices))))))
     ((plist-get operation :error) (plist-get operation :error))
     (progress
      (format "%s%s" (plist-get progress :state)
              (if (equal (plist-get progress :state) "downloading")
                  (format " %d%%" (/ (* 100 (plist-get progress :downloaded_bytes))
                                     (max 1 (plist-get progress :total_bytes)))) "")))
     (operation "Starting")
     (t "Available"))))

(defun omnivox-catalogue--render ()
  "Render cached catalogue and progress, preserving point and focus."
  (setq tabulated-list-entries
        (if omnivox-catalogue--entry
            (let* ((entry omnivox-catalogue--entry)
                   (operation (omnivox-catalogue--operation entry)))
              (mapcar (lambda (row) (list (car row) (vector (cadr row) (or (caddr row) ""))))
                      (list (list 'name "Voice" (plist-get entry :name))
                            (list 'status "Status" (omnivox-catalogue--status entry))
                            (list 'install "Install (i)" "Download and validate; add disabled")
                            (list 'enable "Enable or disable (e)" "Change desired state; choose a speaker for shared models")
                            (list 'apply "Apply (a)" "Review enabled voices and restart both speech streams")
                            (list 'library "Browse voices (l)" "Installed, enabled and active states; samples and palette editing")
                            (list 'engine "Engine" (plist-get entry :provider))
                            (list 'language "Language" (plist-get entry :language))
                            (list 'description "Description" (plist-get entry :description))
                            (list 'size "Download" (omnivox-catalogue--size entry))
                            (list 'speakers "Speakers" (format "%d; one shared model download" (length (plist-get entry :voices))))
                            (list 'licence "Licence" (plist-get entry :licence))
                            (list 'terms "Licence source" (plist-get entry :licence_url))
                            (list 'source "Voice source" (plist-get entry :source))
                            (list 'revision "Source revision" (plist-get entry :source_revision))
                            (list 'destination "Voice storage" (plist-get omnivox-catalogue--host :root))
                            (list 'detail "Progress detail" (or (plist-get operation :error)
                                                                (plist-get (plist-get operation :progress) :detail)))
                            (list 'operation "Operation" (plist-get (plist-get operation :progress) :operation_id))
                            (list 'cancel "Cancel installation" "Wait for native validation cleanup"))))
          (omnivox-catalogue--rows)))
  (when (and omnivox-catalogue--entry omnivox-catalogue--show-speakers)
    (setq tabulated-list-entries
          (append tabulated-list-entries
                  (mapcar (lambda (voice)
                            (list (list 'speaker (plist-get voice :speaker_index))
                                  (vector (format "Speaker %s" (plist-get voice :speaker_index))
                                          (plist-get voice :name))))
                          (append (plist-get omnivox-catalogue--entry :voices) nil)))))
  (setq header-line-format
        (if omnivox-catalogue--entry
            "i install; e enable/disable; a Apply; s speakers; l browse voices; q back"
          (concat (when omnivox-catalogue--scope
                    (concat (string-join omnivox-catalogue--scope " / ") " — "))
                  "RET opens; i install; e enable/disable; a Apply; / search; q back")))
  (tabulated-list-print t)
  (unless tabulated-list-entries
    (let ((inhibit-read-only t))
      (insert "No reviewed voices match this filter. Press / to change it; q to return.\n"))))

(defun omnivox-catalogue-refresh ()
  "Refresh native installed metadata without loading voices."
  (interactive)
  (let ((service (omnivox-library--service)))
    (unwind-protect
        (let ((host (omnivox-library--request service '(:command "host"))))
          (when (and omnivox-catalogue--host (not (equal host omnivox-catalogue--host)))
            ;; request_id changes on every response.
            (unless (equal (omnivox-catalogue--key host nil)
                           (omnivox-catalogue--key omnivox-catalogue--host nil))
              (user-error "Speech target changed; reopen the voice catalogue")))
          (let* ((reply (omnivox-library--request service '(:command "inspect")))
                 (index (plist-get reply :index)))
            (setq omnivox-catalogue--host host
                  omnivox-catalogue--index-sha (plist-get reply :sha256)
                  omnivox-catalogue--voices (plist-get index :voices)
                  omnivox-catalogue--installed (plist-get index :packages))))
      (when (process-live-p service) (delete-process service))))
  (let ((origin (current-buffer)) (host omnivox-catalogue--host)
        (installed omnivox-catalogue--installed) (voices omnivox-catalogue--voices)
        (sha omnivox-catalogue--index-sha))
    (dolist (buffer (buffer-list))
      (with-current-buffer buffer
        (when (and (not (eq buffer origin)) (derived-mode-p 'omnivox-catalogue-mode)
                   (equal (omnivox-catalogue--key host nil)
                          (omnivox-catalogue--key omnivox-catalogue--host nil)))
          (setq omnivox-catalogue--installed installed omnivox-catalogue--voices voices
                omnivox-catalogue--index-sha sha)
          (omnivox-catalogue--render)))))
  (omnivox-catalogue--render))

(defun omnivox-catalogue--selected ()
  "Return the voice being reviewed."
  (or omnivox-catalogue--entry
      (seq-find (lambda (entry) (equal (plist-get entry :id) (tabulated-list-get-id)))
                omnivox-catalogue--entries)
      (user-error "No available voice on this row")))

(defun omnivox-catalogue--redraw (key)
  "Update existing screens of KEY's target silently, without selecting them."
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (and (derived-mode-p 'omnivox-catalogue-mode)
                 (equal (butlast key) (butlast (omnivox-catalogue--key omnivox-catalogue--host nil))))
        (omnivox-catalogue--render)))))

(defun omnivox-catalogue--filter (process output)
  "Read bounded progress OUTPUT belonging to PROCESS only."
  (let* ((key (process-get process 'omnivox-catalogue-key))
         (operation (gethash key omnivox-catalogue--operations)))
    (when (eq process (plist-get operation :process))
      (condition-case err
          (let ((text (concat (or (process-get process 'omnivox-catalogue-fragment) "") output)))
            (when (> (string-bytes text) (* 2 1024 1024)) (error "Oversized installer response"))
            (while (string-match "\n" text)
              (let* ((end (match-beginning 0)) (line (substring text 0 end)))
                (setq text (substring text (1+ end)))
                (unless (string-prefix-p omnivox-library--prefix line) (error "Unexpected installer output"))
                (let ((reply (json-parse-string (substring line (length omnivox-library--prefix))
                                                :object-type 'plist :array-type 'array
                                                :null-object :null :false-object :false)))
                  (unless (= (plist-get reply :request_id) 1) (error "Uncorrelated installer response"))
                  (pcase (plist-get reply :type)
                    ("acquisition"
                     (let* ((progress (plist-get reply :progress))
                            (previous (plist-get operation :progress)))
                       (when (and previous (not (equal (plist-get previous :operation_id)
                                                       (plist-get progress :operation_id))))
                         (error "Installer operation changed"))
                       (setq operation (plist-put operation :progress progress))
                       (when (and (eq (plist-get progress :terminal) t)
                                  (not (plist-get operation :announced)))
                         (setq operation (plist-put operation :announced t))
                         (if (equal "installed-disabled" (plist-get progress :state))
                             (progn
                               (run-hooks 'omnivox-library--changed-hook)
                               (message "Voice installed disabled. Press e to enable, then a to review and Apply"))
                           (message "Voice installation: %s" (plist-get progress :state))))))
                    ("error" (setq operation (plist-put operation :error (plist-get reply :message))))
                    (_ (error "Unknown installer response"))))))
            (process-put process 'omnivox-catalogue-fragment text))
        (error
         (setq operation (plist-put operation :error (error-message-string err)))
         ;; EOF requests cleanup; killing the supervisor would abandon it.
         (when (process-live-p process) (process-send-eof process))))
      (puthash key operation omnivox-catalogue--operations)
      (omnivox-catalogue--redraw key))))

(defun omnivox-catalogue--sentinel (process _event)
  "Retain uncertain outcomes after PROCESS exits unexpectedly."
  (unless (process-live-p process)
    (let* ((key (process-get process 'omnivox-catalogue-key))
           (operation (gethash key omnivox-catalogue--operations)))
      (when (and (eq process (plist-get operation :process))
                 (not (eq (plist-get (plist-get operation :progress) :terminal) t))
                 (not (plist-get operation :error)))
        (puthash key (plist-put operation :error "Installer exited; inspect retained operation before retrying")
                 omnivox-catalogue--operations)
        (omnivox-catalogue--redraw key)))))

(defun omnivox-catalogue-install ()
  "Review and install the selected catalogue voice, initially disabled."
  (interactive)
  (let* ((entry (omnivox-catalogue--selected))
         (key (omnivox-catalogue--key omnivox-catalogue--host entry))
         (old (gethash key omnivox-catalogue--operations)))
    (when (process-live-p (plist-get old :process)) (user-error "This installation is still running"))
    (omnivox-catalogue-refresh)
    (when (seq-some (lambda (package) (equal (plist-get (plist-get package :catalogue) :entry_id)
                                             (plist-get entry :id))) omnivox-catalogue--installed)
      (user-error "Voice already installed; press e to enable it"))
    (unless omnivox-catalogue--entry (omnivox-catalogue-details))
    (when (yes-or-no-p (format "Download %s (%s), validate and install disabled? "
                               (plist-get entry :name) (omnivox-catalogue--size entry)))
      (let* ((program (tts--resolve-program tts-program))
             (process-environment (omnivox-engine-settings--environment program))
             (process (make-process :name "Omnivox voice download" :command (list program "--voice-library-acquire")
                                    :connection-type 'pipe :coding 'utf-8-unix :noquery t
                                    :filter #'omnivox-catalogue--filter :sentinel #'omnivox-catalogue--sentinel
                                    :stderr (get-buffer-create "*Omnivox voice download diagnostics*"))))
        (process-put process 'omnivox-catalogue-key key)
        (puthash key (list :process process) omnivox-catalogue--operations)
        (condition-case err
            (process-send-string process
                                 (concat (json-serialize (list :request_id 1 :command "acquire"
                                                               :voice (plist-get entry :id)
                                                               :plan_json omnivox-catalogue--json)) "\n"))
          (error (process-send-eof process) (signal (car err) (cdr err))))))))

(defun omnivox-catalogue-cancel ()
  "Request cancellation and retain the connection until native cleanup ends."
  (interactive)
  (let ((process (plist-get (omnivox-catalogue--operation (omnivox-catalogue--selected)) :process)))
    (unless (process-live-p process) (user-error "No running installation for this voice"))
    (process-send-eof process)
    (message "Cancellation requested; waiting for native cleanup")))

(defun omnivox-catalogue-library ()
  "Open installed voices for the selected engine."
  (interactive)
  (let ((engine (if omnivox-catalogue--entry (plist-get omnivox-catalogue--entry :provider)
                  omnivox-catalogue--engine)))
    (omnivox-library engine)))

(defun omnivox-catalogue-search (query)
  "Filter available voices by name or language QUERY."
  (interactive "sVoice name or language (empty for all): ")
  (setq omnivox-catalogue--query query)
  (omnivox-catalogue--render)
  (goto-char (point-min)))

(defun omnivox-catalogue--speak-row ()
  "Speak the current catalogue row."
  (emacsvox-aural-ui-speak
   (if-let* ((row (tabulated-list-get-entry)))
       (mapconcat #'identity row ". ")
     "No reviewed voices match. Press slash to change the filter; q returns.")))

(defun omnivox-catalogue-details ()
  "Show details or activate the selected detail action."
  (interactive)
  (if (eq (car-safe (tabulated-list-get-id)) 'group)
      (progn
        (push (list omnivox-catalogue--scope (tabulated-list-get-id) (current-column))
              omnivox-catalogue--history)
        (setq omnivox-catalogue--scope
              (append omnivox-catalogue--scope (list (cadr (tabulated-list-get-id)))))
        (omnivox-catalogue--render)
        (goto-char (point-min))
        (omnivox-catalogue--speak-row))
    (if omnivox-catalogue--entry
      (pcase (tabulated-list-get-id)
        ('install (omnivox-catalogue-install))
        ('enable (omnivox-catalogue-toggle))
        ('apply (omnivox-catalogue-apply))
        ('cancel (omnivox-catalogue-cancel))
        ('library (omnivox-catalogue-library))
        (_ (omnivox-catalogue--speak-row)))
    (let ((entry (omnivox-catalogue--selected)) (parent (current-buffer))
          (host omnivox-catalogue--host)
          (json (or (cdr (assoc (plist-get (omnivox-catalogue--selected) :id)
                               omnivox-catalogue--documents)) omnivox-catalogue--json))
          (entries omnivox-catalogue--entries) (installed omnivox-catalogue--installed)
          (voices omnivox-catalogue--voices) (sha omnivox-catalogue--index-sha)
          (buffer (get-buffer-create "*Omnivox Voice Download*")))
      (with-current-buffer buffer
        (omnivox-catalogue-mode)
        (setq omnivox-catalogue--entry entry omnivox-catalogue--host host
              omnivox-catalogue--json json omnivox-catalogue--entries entries
              omnivox-catalogue--installed installed omnivox-catalogue--parent parent
              omnivox-catalogue--voices voices omnivox-catalogue--index-sha sha
              tabulated-list-format [("Field" 22 nil) ("Value" 0 nil)])
        (tabulated-list-init-header)
        (omnivox-catalogue--render)
        (goto-char (point-min)))
      (emacsvox-aural-ui--pop-to-buffer buffer #'omnivox-catalogue--speak-row)))))

(defvar-keymap omnivox-catalogue-mode-map
  :doc "Available voice actions."
  "RET" #'omnivox-catalogue-details
  "q" #'omnivox-catalogue-back
  "s" #'omnivox-catalogue-speakers
  "e" #'omnivox-catalogue-toggle "a" #'omnivox-catalogue-apply
  "i" #'omnivox-catalogue-install "c" #'omnivox-catalogue-cancel
  "l" #'omnivox-catalogue-library "/" #'omnivox-catalogue-search)

(define-derived-mode omnivox-catalogue-mode emacsvox-aural-tabulated-mode "Available Voices"
  "Available voices: RET opens; i installs; e enables/disables; a reviews Apply."
  (emacsvox-aural-ui-configure-tabulated "Available Omnivox voices"
                                         #'omnivox-catalogue--speak-row #'omnivox-catalogue-refresh
                                         #'omnivox-catalogue--speak-row)
  (setq tabulated-list-format [("Voice" 24 t) ("Engine" 9 t) ("Language" 10 t) ("Download" 10 nil) ("Status" 0 nil)]
        header-line-format "RET details; i install; c cancel; l installed voices; / filter; g refresh; q back")
  (tabulated-list-init-header))

;;;###autoload
(defun omnivox-catalogue (&optional engine)
  "Browse reviewed downloadable voices, optionally restricted to ENGINE."
  (interactive)
  (let* ((directory (expand-file-name "omnivox-piper-catalogues" emacsvox-etc-directory))
         (manifest-file (expand-file-name "manifest.json" directory))
         (manifest (when (file-readable-p manifest-file)
                     (with-temp-buffer
                       (insert-file-contents manifest-file)
                       (json-parse-buffer :object-type 'plist :array-type 'array))))
         (files (cons (expand-file-name "omnivox-voice-catalogue.json" emacsvox-etc-directory)
                      (mapcar (lambda (name)
                                (unless (and (stringp name) (equal name (file-name-nondirectory name))
                                             (string-suffix-p ".json" name))
                                  (error "Invalid catalogue manifest filename"))
                                (expand-file-name name directory))
                              (append (plist-get manifest :catalogues) nil))))
         (service (omnivox-library--service)) entries documents)
    (unwind-protect
        (dolist (file files)
          (let* ((json (with-temp-buffer (insert-file-contents file) (buffer-string)))
                 (reply (omnivox-library--request service (list :command "catalogue" :plan_json json))))
            (seq-doseq (entry (plist-get (plist-get reply :catalogue) :entries))
              ;; The original catalogue wins for existing identities such as Kristin.
              (unless (assoc (plist-get entry :id) documents)
                (push (cons (plist-get entry :id) json) documents)
                (push entry entries)))))
      (when (process-live-p service) (delete-process service)))
    (let ((buffer (get-buffer-create "*Omnivox Available Voices*")))
      (with-current-buffer buffer
        (omnivox-catalogue-mode)
        (setq omnivox-catalogue--engine engine
              omnivox-catalogue--documents documents
              omnivox-catalogue--metadata (plist-get manifest :models)
              omnivox-catalogue--entries (vconcat (nreverse entries)))
        (omnivox-catalogue-refresh))
      (emacsvox-aural-ui--pop-to-buffer buffer #'omnivox-catalogue--speak-row))))

(provide 'omnivox-catalogue)
;;; omnivox-catalogue.el ends here
