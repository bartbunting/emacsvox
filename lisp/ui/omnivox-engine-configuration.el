;;; omnivox-engine-configuration.el --- Local engine configuration -*- lexical-binding: t; -*-

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
;; Independent drafts of host engine settings.  Save never activates speech;
;; explicit Apply uses the established two-worker preflight/rollback service.

;;; Code:
(require 'cl-lib)
(require 'json)
(require 'subr-x)
(require 'emacsvox-aural-ui)
(require 'omnivox-library)

(declare-function emacsvox-aural-voice-workbench--open-engine
                  "emacsvox-aural-voice-workbench" (engine &optional parent))

(defvar-local omnivox-engine-configuration--review nil)
(defvar-local omnivox-engine-configuration--draft nil)
(defvar-local omnivox-engine-configuration--saved nil)
(defvar-local omnivox-engine-configuration--engine "espeak")
(defvar-local omnivox-engine-configuration--advanced nil)
(defvar-local omnivox-engine-configuration--status "Saved settings; running speech may differ")

(defun omnivox-engine-configuration--object (value)
  "Convert a JSON plist VALUE to editable hash tables, preserving arrays."
  (cond ((vectorp value) (vconcat (mapcar #'omnivox-engine-configuration--object value)))
        ((listp value)
         (let ((table (make-hash-table :test #'equal)))
           (while value
             (puthash (substring (symbol-name (pop value)) 1)
                      (omnivox-engine-configuration--object (pop value)) table))
           table))
        (t value)))

(defun omnivox-engine-configuration--json (value)
  "Encode editable VALUE for the native service."
  (decode-coding-string
   (json-serialize value :false-object :false :null-object :null) 'utf-8 t))

(defun omnivox-engine-configuration--request (command)
  "Send local settings COMMAND after negotiating editor support."
  (let ((service (omnivox-library--service)))
    (unwind-protect
        (progn
          (unless (eql 1 (plist-get (omnivox-library--request service '(:command "host"))
                                   :engine_settings_version))
            (user-error "Update the local Omnivox host to edit engine configuration"))
          (let ((reply (omnivox-library--request service command)))
            (unless (equal (plist-get reply :type) "engine_settings")
              (error "Unexpected engine settings response"))
            (plist-get reply :review)))
      (when (process-live-p service) (delete-process service)))))

(defun omnivox-engine-configuration--accept (review)
  "Accept saved REVIEW without confusing it with running worker settings."
  (unless (and (stringp (plist-get review :sha256))
               (stringp (plist-get review :path))
               (plist-member review :settings) (plist-member review :engines))
    (error "Incomplete engine configuration review"))
  (setq omnivox-engine-configuration--review review
        omnivox-engine-configuration--draft
        (omnivox-engine-configuration--object (plist-get review :settings))
        omnivox-engine-configuration--saved
        (omnivox-engine-configuration--json omnivox-engine-configuration--draft)))

(defun omnivox-engine-configuration--dirty-p ()
  "Whether this buffer retains an unsaved settings draft."
  (not (equal omnivox-engine-configuration--saved
              (omnivox-engine-configuration--json omnivox-engine-configuration--draft))))

(defun omnivox-engine-configuration--record ()
  "Return the selected engine's saved registration metadata."
  (or (seq-find (lambda (entry) (equal (plist-get entry :engine_id)
                                      omnivox-engine-configuration--engine))
                (plist-get omnivox-engine-configuration--review :engines))
      (user-error "Engine is no longer registered; choose another engine")))

(defun omnivox-engine-configuration--overrides ()
  "Return this engine's editable override object, creating it on demand."
  (let* ((engines (gethash "engine_overrides" omnivox-engine-configuration--draft))
         (id omnivox-engine-configuration--engine))
    (or (gethash id engines)
        (puthash id (make-hash-table :test #'equal) engines))))

(defun omnivox-engine-configuration--row (id label value)
  "Construct a settings row from ID, LABEL and displayed VALUE."
  (list id (vector label value)))

(defun omnivox-engine-configuration--live-state (process)
  "Describe PROCESS's retained engine inventory without inferring active settings."
  (let* ((inventory (and (processp process) (process-live-p process)
                         (process-get process 'omnivox--control-inventory)))
         (entry (seq-find (lambda (engine) (equal (plist-get engine :id)
                                                  omnivox-engine-configuration--engine))
                          (plist-get inventory :engines)))
         (runtime (seq-find (lambda (engine) (equal (plist-get engine :engine_id)
                                                    omnivox-engine-configuration--engine))
                            (plist-get inventory :engine_runtime))))
    (if entry
        (format "Last reported: %s%s"
                (or (plist-get (plist-get entry :availability) :status) "unknown")
                (if (plist-get runtime :disabled_by_policy) "; disabled by session policy" ""))
      "No current worker inventory")))

(defun omnivox-engine-configuration--render (&optional selected)
  "Render the draft, preserving SELECTED row and application actions."
  (let* ((record (omnivox-engine-configuration--record))
         (routing (gethash "routing" omnivox-engine-configuration--draft))
         (overrides (gethash omnivox-engine-configuration--engine
                             (gethash "engine_overrides" omnivox-engine-configuration--draft)))
         (setting (lambda (key default) (if overrides (gethash key overrides default) default)))
         (enabled (eq t (funcall setting "enabled" (plist-get record :enabled))))
         (disabled (member omnivox-engine-configuration--engine
                           (append (gethash "disabled_engine_ids" routing) nil)))
         (row #'omnivox-engine-configuration--row))
    (setq header-line-format
          (format "%s | %s | RET edit, s save, A Apply, l engine, q return"
                  omnivox-engine-configuration--engine
                  (if (omnivox-engine-configuration--dirty-p) "Unsaved draft"
                    omnivox-engine-configuration--status)))
    (emacsvox-aural-ui-refresh-tabulated
     (lambda ()
       (setq tabulated-list-entries
             (append
              (list
               (funcall row 'enabled "Enabled" (if (and enabled (not disabled)) "Yes" "No"))
               (funcall row 'preferred "Preferred engines"
                        (let ((value (gethash "preferred_engine_ids" routing)))
                          (if (and value (> (length value) 0))
                              (string-join (append value nil) ", ") "Host default")))
               (funcall row 'fallback "Backup engines"
                        (let ((value (gethash "fallback_engine_ids" routing :absent)))
                          (if (eq value :absent) "Host default"
                            (if (zerop (length value)) "None" (string-join (append value nil) ", ")))))
               (funcall row 'automatic "Automatic selection"
                        (if (or (not (stringp (plist-get record :program)))
                                (member omnivox-engine-configuration--engine
                                        (append (gethash "automatic_engine_ids" routing) nil)))
                            "Allowed" "Explicit selection only")))
              (unless (eq t (plist-get record :in_process))
                (list (funcall row 'program "Program on speech host"
                               (funcall setting "program" (if (stringp (plist-get record :program)) (plist-get record :program) "Installed helper")))))
              (when-let* ((override (plist-get record :environment_override))
                          ((stringp override)))
                (list (funcall row 'precedence "Higher-priority setting"
                               (concat override " overrides the saved program"))))
              (list (funcall row 'advanced "Advanced startup settings"
                             (if omnivox-engine-configuration--advanced "Expanded" "Collapsed")))
              (when (and omnivox-engine-configuration--advanced
                         (not (eq t (plist-get record :in_process))))
                (let ((timeouts (funcall setting "timeouts" nil)))
                  (append
                   (list (funcall row 'arguments "Startup arguments"
                                  (let ((value (funcall setting "arguments" nil)))
                                    (cond ((null value) "Registration default")
                                          ((zerop (length value)) "No arguments")
                                          (t (combine-and-quote-strings (append value nil)))))))
                   (mapcar (lambda (entry)
                             (funcall row (intern (car entry)) (concat (cdr entry) " (milliseconds)")
                                      (format "%s" (if timeouts (gethash (car entry) timeouts "Default") "Default"))))
                           '(("startup_ms" . "Startup wait") ("request_ms" . "Request wait")
                             ("synthesis_idle_ms" . "Synthesis idle wait"))))))
              (list (funcall row 'main-live "Running main speech"
                             (omnivox-engine-configuration--live-state tts-speaker-process))
                    (funcall row 'notify-live "Running notification speech"
                             (omnivox-engine-configuration--live-state tts-notify-process))
                    (funcall row 'validate "Check saved settings" "Validate host files; does not synthesize or restart")
                    (funcall row 'sample "Voices and spoken sample" "Uses voices in the running speech session")
                    (funcall row 'add "Add installed helper" "Register a compatible program, initially disabled")
                    (funcall row 'save "Save draft" "Keep speech running with its current settings")
                    (funcall row 'apply "Apply saved settings" "Review engine and voice settings for both workers; rollback on failure")))))
     selected)))

(defun omnivox-engine-configuration--changed (row)
  "Refresh and speak changed ROW without activating speech."
  (omnivox-engine-configuration--render row)
  (emacsvox-aural-ui-speak-current-row))

(defun omnivox-engine-configuration-speak-row ()
  "Speak this engine's selected setting and draft value."
  (interactive)
  (let ((row (or (tabulated-list-get-entry) (user-error "Choose a setting first"))))
    (emacsvox-aural-ui-speak
     (format "%s. %s. %s." omnivox-engine-configuration--engine (aref row 0) (aref row 1)))))

(defun omnivox-engine-configuration-edit ()
  "Edit the selected engine setting in the independent draft."
  (interactive)
  (let* ((id (tabulated-list-get-id))
         (routing (gethash "routing" omnivox-engine-configuration--draft))
         (engine omnivox-engine-configuration--engine))
    (pcase id
      ('advanced (setq omnivox-engine-configuration--advanced
                       (not omnivox-engine-configuration--advanced)))
      ('enabled
       (let* ((overrides (omnivox-engine-configuration--overrides))
              (disabled (append (gethash "disabled_engine_ids" routing) nil))
              (enabled (and (eq t (gethash "enabled" overrides
                                          (plist-get (omnivox-engine-configuration--record) :enabled)))
                            (not (member engine disabled)))))
         (puthash "enabled" (if enabled :false t) overrides)
         (puthash "disabled_engine_ids" (vconcat (delete engine disabled)) routing)))
      ((or 'preferred 'fallback)
       (let* ((key (if (eq id 'preferred) "preferred_engine_ids" "fallback_engine_ids"))
              (choices (mapcar (lambda (entry) (plist-get entry :engine_id))
                               (plist-get omnivox-engine-configuration--review :engines)))
              (answer (completing-read-multiple
                       "Engine IDs in priority order (comma separated; empty clears): "
                       choices nil t nil nil
                       (string-join (append (gethash key routing) nil) ","))))
         (unless (= (length answer) (length (delete-dups (copy-sequence answer))))
           (user-error "Choose each engine only once"))
         (puthash key (vconcat answer) routing)))
      ('automatic
       (unless (stringp (plist-get (omnivox-engine-configuration--record) :program))
         (user-error "Automatic permission applies to external helpers; disable a built-in engine instead"))
       (let ((ids (append (gethash "automatic_engine_ids" routing) nil)))
         (puthash "automatic_engine_ids"
                  (vconcat (if (member engine ids) (delete engine ids) (append ids (list engine)))) routing)))
      ('program
       (let* ((existing (gethash engine (gethash "engine_overrides" omnivox-engine-configuration--draft)))
              (program (read-string "Absolute program path on speech host (empty restores default): "
                                    (and existing (gethash "program" existing))))
              (overrides (omnivox-engine-configuration--overrides)))
         (if (string-empty-p program) (remhash "program" overrides)
           (puthash "program" program overrides))))
      ('arguments
       (puthash "arguments"
                (vconcat (split-string-and-unquote
                          (read-string "Literal startup arguments (quote spaces): ")))
                (omnivox-engine-configuration--overrides)))
      ((or 'startup_ms 'request_ms 'synthesis_idle_ms)
       (let* ((key (symbol-name id))
              (value (read-string "Milliseconds (empty restores default): ")))
         (unless (or (string-empty-p value) (string-match-p "\\`[0-9]+\\'" value))
           (user-error "Enter whole milliseconds"))
         (let* ((overrides (omnivox-engine-configuration--overrides))
                (timeouts (or (gethash "timeouts" overrides)
                              (puthash "timeouts" (make-hash-table :test #'equal) overrides))))
           (if (string-empty-p value) (remhash key timeouts)
             (puthash key (string-to-number value) timeouts)))))
      ('validate (omnivox-engine-configuration-check))
      ('sample (omnivox-engine-configuration-sample))
      ('add (omnivox-engine-configuration-add))
      ('save (omnivox-engine-configuration-save))
      ('apply (omnivox-engine-configuration-apply))
      (_ (user-error "This row is informational")))
    (when (memq id '(advanced enabled preferred fallback automatic program arguments startup_ms request_ms synthesis_idle_ms))
      (omnivox-engine-configuration--changed id))))

(defun omnivox-engine-configuration-save ()
  "Save the complete draft without restarting either speech worker."
  (interactive)
  (unless (omnivox-engine-configuration--dirty-p) (user-error "No changes to save"))
  (omnivox-engine-configuration--accept
   (omnivox-engine-configuration--request
    (list :command "engine-settings-save"
          :expected_sha256 (plist-get omnivox-engine-configuration--review :sha256)
          :settings_json (omnivox-engine-configuration--json omnivox-engine-configuration--draft))))
  (setq omnivox-engine-configuration--status "Saved; running speech is unchanged")
  (omnivox-engine-configuration--render 'save)
  (emacsvox-aural-ui-speak omnivox-engine-configuration--status))

(defun omnivox-engine-configuration-check ()
  "Validate the saved configuration, retaining any draft and active speech."
  (interactive)
  (let ((review (omnivox-engine-configuration--request '(:command "engine-settings-review"))))
    (unless (equal (plist-get review :sha256) (plist-get omnivox-engine-configuration--review :sha256))
      (user-error "Saved settings changed; refresh and review before Apply"))
    (when (seq-some #'identity (plist-get review :diagnostics))
      (user-error "Host registration problems: %s"
                  (string-join (append (plist-get review :diagnostics) nil) "; ")))
    (emacsvox-aural-ui-speak "Saved configuration is valid. Runtime voices require Apply and a spoken sample.")))

(defun omnivox-engine-configuration-apply ()
  "Review and apply saved settings through the existing two-worker rollback flow."
  (interactive)
  (when (omnivox-engine-configuration--dirty-p) (user-error "Save or discard the draft before Apply"))
  (omnivox-engine-configuration-check)
  (omnivox-library-apply "both")
  (setq omnivox-engine-configuration--status "Apply finished; inspect the Apply result and live voices")
  (omnivox-engine-configuration--render 'apply))

(defun omnivox-engine-configuration-sample ()
  "Open this engine's live voices for an exact spoken sample."
  (interactive)
  (require 'emacsvox-aural-voice-workbench)
  (emacsvox-aural-voice-workbench--open-engine
   omnivox-engine-configuration--engine (current-buffer)))

(defun omnivox-engine-configuration-add ()
  "Register an installed compatible helper on the speech host, initially disabled."
  (interactive)
  (when (omnivox-engine-configuration--dirty-p) (user-error "Save or discard edits before adding an engine"))
  (let* ((id (read-string "New engine ID: "))
         (program (read-string "Installed helper's absolute path on speech host: "))
         (arguments (vconcat (split-string-and-unquote (read-string "Literal startup arguments: ")))))
    (omnivox-engine-configuration--accept
     (omnivox-engine-configuration--request
      (list :command "engine-settings-add"
            :expected_sha256 (plist-get omnivox-engine-configuration--review :sha256)
            :manifest_json (omnivox-engine-configuration--json
                            (list :schema 1 :engine_id id :program program
                                  :arguments arguments :enabled :false)))))
    (setq omnivox-engine-configuration--engine id)
    (omnivox-engine-configuration--render 'enabled)
    (emacsvox-aural-ui-speak "Helper registered, disabled. Enable, Save and Apply to check it.")))

(defun omnivox-engine-configuration-refresh ()
  "Refresh saved settings after confirming any unsaved draft can be discarded."
  (interactive)
  (when (or (not (omnivox-engine-configuration--dirty-p))
            (yes-or-no-p "Discard this draft and read saved engine settings? "))
    (omnivox-engine-configuration--accept
     (omnivox-engine-configuration--request '(:command "engine-settings-review")))
    (omnivox-engine-configuration--render)))

(defun omnivox-engine-configuration-select ()
  "Choose an engine without discarding any settings drafts."
  (interactive)
  (setq omnivox-engine-configuration--engine
        (completing-read "Engine: "
                         (mapcar (lambda (entry) (plist-get entry :engine_id))
                                 (plist-get omnivox-engine-configuration--review :engines)) nil t))
  (omnivox-engine-configuration--changed 'enabled))

(defun omnivox-engine-configuration--kill-query ()
  "Confirm disposal of an unsaved draft."
  (or (not omnivox-engine-configuration--draft)
      (not (omnivox-engine-configuration--dirty-p))
      (yes-or-no-p "Discard unsaved engine settings? ")))

(define-derived-mode omnivox-engine-configuration-mode emacsvox-aural-tabulated-mode "Engine Settings"
  "Edit saved local engine settings separately from running speech."
  (emacsvox-aural-ui-configure-tabulated
   "Engine settings" #'omnivox-engine-configuration-speak-row #'omnivox-engine-configuration-refresh)
  (setq tabulated-list-format [("Setting" 30 t) ("Value" 60 nil)]
        tabulated-list-padding 2)
  (add-hook 'kill-buffer-query-functions #'omnivox-engine-configuration--kill-query nil t)
  (tabulated-list-init-header))

(dolist (entry '(("RET" . omnivox-engine-configuration-edit)
                 ("e" . omnivox-engine-configuration-edit)
                 ("s" . omnivox-engine-configuration-save)
                 ("A" . omnivox-engine-configuration-apply)
                 ("l" . omnivox-engine-configuration-select)
                 ("g" . omnivox-engine-configuration-refresh)
                 ("P" . omnivox-engine-configuration-sample)))
  (define-key omnivox-engine-configuration-mode-map (kbd (car entry)) (cdr entry)))

;;;###autoload
(defun omnivox-engine-configuration (&optional engine)
  "Edit local saved configuration for ENGINE, retaining any existing draft."
  (interactive)
  (let ((buffer (get-buffer-create "*Omnivox Engine Settings*")))
    (with-current-buffer buffer
      (unless omnivox-engine-configuration--review
        (let ((review (omnivox-engine-configuration--request '(:command "engine-settings-review"))))
          (omnivox-engine-configuration-mode)
          (omnivox-engine-configuration--accept review)))
      (when engine (setq omnivox-engine-configuration--engine engine))
      (omnivox-engine-configuration--render 'enabled))
    (emacsvox-aural-ui-pop-to-buffer buffer)))

(provide 'omnivox-engine-configuration)
;;; omnivox-engine-configuration.el ends here
