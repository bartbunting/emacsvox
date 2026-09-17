;;; emacsvox-omnivox-components.el --- Inspect and manage speech engines -*- lexical-binding: t; -*-

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

;; Live engine discovery and required-runtime status.  The pinned WSL2 release
;; installer is an explicit separate view and keeps current speech running.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'tabulated-list)
(require 'emacsvox-aural-ui)
(require 'emacsvox-aural-inspection)
(require 'omnivox-engine-settings)

(declare-function emacsvox-aural "emacsvox-aural-home"
                  (&optional source-buffer))
(declare-function emacsvox-aural-inspection-remember-source-buffer
                  "emacsvox-aural-inspection" (&optional candidate))
(declare-function emacsvox-aural-inspection-attach-source
                  "emacsvox-aural-inspection" (source-buffer))
(declare-function emacsvox-speak-help "emacsvox-speak" ())
(declare-function tts--retire-process "tts-speak" (process))
(declare-function tts-restart "tts-speak" ())
(declare-function tts-speak "tts-speak" (text))

(defvar emacsvox-directory)
(defvar tts-notify-process)
(defvar tts-program)
(defvar tts-speaker-process)
(defvar omnivox-engine-inventory)
(defvar omnivox-engine-inventory-time)
(defvar omnivox--control-inventory-property)
(declare-function omnivox-voice-inventory "omnivox-voices" ())
(declare-function omnivox-refresh-voice-inventory "omnivox-voices" ())
(declare-function omnivox--process-supports-p "omnivox-voices" (process feature))
(declare-function tts-notify "tts-speak" (text &optional dont-log))
(declare-function emacsvox-aural-voice-workbench--open-engine
                  "emacsvox-aural-voice-workbench" (engine parent))
(declare-function emacsvox-aural-voice-workbench
                  "emacsvox-aural-voice-workbench" (&optional view))
(declare-function emacsvox-aural-voice-workbench-speak-current
                  "emacsvox-aural-voice-workbench" ())

(defgroup emacsvox-omnivox-components nil
  "Manage optional Omnivox engines."
  :group 'emacsvox)

(defcustom emacsvox-omnivox-component-installer
  (expand-file-name "bin/emacsvox-omnivox-components" emacsvox-directory)
  "Program that lists, installs, uninstalls, and tests Omnivox engines."
  :type 'file
  :group 'emacsvox-omnivox-components)

(defcustom emacsvox-omnivox-restart-after-component-install t
  "Legacy restart preference for direct component operations.
The installed-release view keeps current speech running.  Restart explicitly
when you intend to use changed engine files in this session."
  :type 'boolean
  :group 'emacsvox-omnivox-components)

(defvar-local emacsvox-omnivox-components--records nil
  "Component records displayed in the current manager buffer.")

(defvar-local emacsvox-omnivox-components--process nil
  "Active install, uninstall, or engine-test process for this manager.")

(defvar-local emacsvox-omnivox-components--snapshots nil
  "Per-lane inventory evidence, retained across reconnects.")
(defvar-local emacsvox-omnivox-components--results nil
  "Last completed managed check or operation for each engine.")
(defvar-local emacsvox-omnivox-components--listing-error nil
  "Reason managed installation information could not be refreshed.")
(defvar-local emacsvox-omnivox-components--listing-process nil
  "Asynchronous managed-installation listing owned by this buffer.")
(defvar-local emacsvox-omnivox-components--manager nil
  "Parent engine-list buffer for an engine details view.")
(defvar-local emacsvox-omnivox-components--engine-id nil
  "Engine shown in a details view.")
(defvar-local emacsvox-omnivox-components--details-parent nil
  "Engine browser to return to from details, independent of management state.")
(defvar-local emacsvox-omnivox-components--expanded-sections nil
  "Sections expanded in this engine's details buffer.")
(defvar-local emacsvox-omnivox-components--release-view nil
  "Non-nil while details explicitly show the installer's release.")
(defvar-local emacsvox-omnivox-components--release-target nil
  "Installation identity reported by the release installer.")
(defvar emacsvox-omnivox-components--release-operation nil
  "Non-nil while submitting an explicitly selected release operation.")

(defconst emacsvox-omnivox-components--fresh-seconds 300
  "Age after which opening details requests fresh engine discovery.")

(defun emacsvox-omnivox-components--lane-process (lane)
  "Return the speech process for LANE without starting it."
  (let ((symbol (if (eq lane 'main) 'tts-speaker-process 'tts-notify-process)))
    (and (boundp symbol) (symbol-value symbol))))

(defun emacsvox-omnivox-components--capture-inventory ()
  "Capture each worker's own inventory without probing or starting speech."
  (when (and (fboundp 'omnivox-voice-inventory)
             (boundp 'omnivox--control-inventory-property))
    (dolist (lane '(main notification))
      (let* ((process (emacsvox-omnivox-components--lane-process lane))
             (raw (and (processp process)
                       (process-get process omnivox--control-inventory-property))))
        (when raw
          (let* ((tts-speaker-process process)
                 (omnivox-engine-inventory raw)
                 (omnivox-engine-inventory-time
                  (process-get process 'omnivox-inventory-received-at)))
            (setf (alist-get lane emacsvox-omnivox-components--snapshots)
                  (list :process process
                        :inventory (omnivox-voice-inventory)))))))))

(defun emacsvox-omnivox-components--current-snapshot-p (lane)
  "Whether LANE's evidence belongs to its current live worker."
  (let* ((snapshot (alist-get lane emacsvox-omnivox-components--snapshots))
         (process (plist-get snapshot :process)))
    (and (process-live-p process)
         (eq process (emacsvox-omnivox-components--lane-process lane)))))

(defun emacsvox-omnivox-components--refresh-due-p (lane)
  "Whether LANE needs discovery from its current worker or a newer snapshot."
  (let ((received (plist-get
                   (plist-get (alist-get lane emacsvox-omnivox-components--snapshots)
                              :inventory) :received-at)))
    (or (not (emacsvox-omnivox-components--current-snapshot-p lane))
        (not received)
        (>= (float-time (time-subtract nil received))
            emacsvox-omnivox-components--fresh-seconds))))

(defun emacsvox-omnivox-components--refresh-old-inventory ()
  "Request older or replaced-worker evidence asynchronously when supported."
  (when (and (fboundp 'omnivox-refresh-voice-inventory)
             (fboundp 'omnivox--process-supports-p)
             (cl-some
              (lambda (lane)
                (let ((process (emacsvox-omnivox-components--lane-process lane)))
                  (and (process-live-p process)
                       (omnivox--process-supports-p process "engine_inventory")
                       (emacsvox-omnivox-components--refresh-due-p lane))))
              '(main notification)))
    (omnivox-refresh-voice-inventory)))

(defun emacsvox-omnivox-components--engine (id &optional lane)
  "Return engine ID from the retained inventory for LANE, normally main."
  (cl-find id
           (plist-get (plist-get
                       (alist-get (or lane 'main)
                                  emacsvox-omnivox-components--snapshots)
                       :inventory) :engines)
           :key (lambda (engine) (plist-get engine :engine-id)) :test #'equal))

(defun emacsvox-omnivox-components--lane-state (id lane)
  "Describe discovered engine ID in LANE without inferring runtime absence."
  (let ((engine (emacsvox-omnivox-components--engine id lane)))
    (cond
     ((and (null engine) (equal id "mbrola"))
      (plist-get (emacsvox-omnivox-components--mbrola-placeholder) :availability))
     ((null engine) "Not checked")
     ((not (emacsvox-omnivox-components--current-snapshot-p lane))
      (if (equal (plist-get engine :availability) "available")
          "Previously available" "Previous check; refresh needed"))
     ((plist-get engine :disabled-by-policy) "Disabled")
     ((equal (plist-get engine :availability) "available")
      (if (member (plist-get engine :health) '("healthy" "unknown" nil))
          "Available" "Available; needs attention"))
     ((equal (plist-get engine :availability) "unknown") "Not checked")
     (t "Needs attention"))))

(defun emacsvox-omnivox-components--all-records ()
  "Combine managed records with live engines, keeping their evidence separate."
  (let ((records (copy-sequence emacsvox-omnivox-components--records)))
    (dolist (lane '(main notification))
      (dolist (engine (plist-get
                      (plist-get (alist-get lane emacsvox-omnivox-components--snapshots)
                                 :inventory) :engines))
        (let ((id (plist-get engine :engine-id)))
          (unless (cl-find id records :key (lambda (r) (plist-get r :id)) :test #'equal)
            (setq records
                  (append records (list (list :id id :name (plist-get engine :display-name)
                                              :state "not-managed" :size 0))))))))
    (unless (cl-find "mbrola" records :key (lambda (r) (plist-get r :id)) :test #'equal)
      (setq records
            (append records '((:id "mbrola" :name "MBROLA" :state "not-managed"
                               :size 0 :detail "Prototype; supplied separately")))))
    records))

(defun emacsvox-omnivox-components--inventory-changed ()
  "Refresh open engine views from received evidence without changing focus."
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (derived-mode-p 'emacsvox-omnivox-components-mode)
        (emacsvox-omnivox-components--capture-inventory)
        (emacsvox-omnivox-components--render)
        (emacsvox-omnivox-components--refresh-details)))))

(add-hook 'tts-voice-inventory-changed-hook
          #'emacsvox-omnivox-components--inventory-changed)

(defconst emacsvox-omnivox-components--output-buffer
  "*Omnivox Component Output*")

(defconst emacsvox-omnivox-components--managed-ids
  '("flite" "rutts" "piper" "tgspeechbox")
  "Component identifiers that this manager may install and uninstall.")

(defun emacsvox-omnivox-components--mbrola-placeholder ()
  "Describe an unreported prototype without claiming runtime discovery."
  (let ((unconfigured
         (and (omnivox-engine-settings--supported-p)
              (string-empty-p (or (getenv "OMNIVOX_MBROLA_HELPER") "")))))
    (list :engine-id "mbrola" :display-name "MBROLA"
          :availability (if unconfigured "Prototype; not configured"
                          "Prototype; not reported")
          :availability-reason
          (if unconfigured "Open details for prototype setup"
            "Check configuration on the speech host, restart both streams, then refresh")
          :voices nil)))

(defun emacsvox-omnivox-components--browse-engines (engines)
  "Include optional engines missing from live ENGINES as unchecked rows."
  (let ((result (copy-sequence engines)))
    (dolist (id emacsvox-omnivox-components--managed-ids)
      (unless (cl-find id result :key (lambda (engine) (plist-get engine :engine-id)) :test #'equal)
        (setq result
              (append result
                      (list (list :engine-id id
                                  :display-name (pcase id ("rutts" "RuTTS") ("tgspeechbox" "TGSpeechBox")
                                                      (_ (capitalize id)))
                                  :availability "not reported" :voices nil))))))
    (unless (cl-find "mbrola" result :key (lambda (engine) (plist-get engine :engine-id))
                     :test #'equal)
      (setq result (append result (list (emacsvox-omnivox-components--mbrola-placeholder)))))
    result))

(defun emacsvox-omnivox-components--speak (text)
  "Speak TEXT when speech is available, otherwise display it."
  (if (fboundp 'tts-speak)
      (tts-speak text)
    (message "%s" text))
  text)

(defun emacsvox-omnivox-components--check-installer ()
  "Return the configured installer or signal a useful user error."
  (let ((program (expand-file-name emacsvox-omnivox-component-installer)))
    (unless (file-executable-p program)
      (user-error "Omnivox component installer is not executable: %s" program))
    program))

(defun emacsvox-omnivox-components--parse (output)
  "Parse machine-readable installer OUTPUT into component records."
  (mapcar
   (lambda (line)
     (let ((fields (split-string line "\t" nil)))
       (unless (= (length fields) 5)
         (error "Invalid Omnivox component record: %s" line))
       (pcase-let ((`(,id ,name ,state ,size ,detail) fields))
         (unless (string-match-p "\\`[[:alnum:]-]+\\'" id)
           (error "Invalid Omnivox component identifier: %s" id))
         (unless (string-match-p "\\`[0-9]+\\'" size)
           (error "Invalid Omnivox component size: %s" size))
         (list :id id :name name :state state
               :size (string-to-number size) :detail detail))))
   (split-string output "\n" t)))

(defun emacsvox-omnivox-components--accept-listing (text)
  "Retain engine records and the explicit release identity from TEXT."
  (let* ((records (emacsvox-omnivox-components--parse text))
         (target (cl-find "installation-target" records
                          :key (lambda (record) (plist-get record :id)) :test #'equal)))
    (unless (and target (file-name-absolute-p (plist-get target :detail))
                 (= 1 (cl-count "installation-target" records
                                :key (lambda (record) (plist-get record :id)) :test #'equal)))
      (error "Installer did not report one installation target; update the installer"))
    (setq emacsvox-omnivox-components--release-target target
          emacsvox-omnivox-components--records (delq target records)
          emacsvox-omnivox-components--listing-error nil)))

(defun emacsvox-omnivox-components--request-records ()
  "Start a bounded asynchronous managed-installation listing for this view."
  (unless (process-live-p emacsvox-omnivox-components--listing-process)
    (let ((manager (current-buffer))
          (output (generate-new-buffer " *Omnivox engine listing*")))
      (condition-case err
          (let* ((program (emacsvox-omnivox-components--check-installer))
                 (process
                  (make-process
                   :name "omnivox-module-list" :buffer output
                   :command (list program "--machine-target") :coding 'utf-8
                   :connection-type 'pipe :noquery t
                   :sentinel
                   (lambda (process _event)
                     (when (memq (process-status process) '(exit signal))
                       (when-let* ((timer (process-get process 'listing-timer)))
                         (cancel-timer timer))
                       (unwind-protect
                           (when (buffer-live-p manager)
                             (with-current-buffer manager
                               (when (eq process emacsvox-omnivox-components--listing-process)
                                 (setq emacsvox-omnivox-components--listing-process nil)
                                 (condition-case error-data
                                     (let ((text (with-current-buffer output (buffer-string))))
                                       (unless (and (eq (process-status process) 'exit)
                                                    (zerop (process-exit-status process)))
                                         (error "%s" (if (process-get process 'listing-timeout)
                                                          "Managed installation check timed out"
                                                        (string-trim text))))
                                       (emacsvox-omnivox-components--accept-listing text))
                                   (error
                                    (setq emacsvox-omnivox-components--listing-error
                                          (error-message-string error-data))))
                                 (emacsvox-omnivox-components--render)
                                 (emacsvox-omnivox-components--refresh-details))))
                         (when (buffer-live-p output) (kill-buffer output))))))))
            (setq emacsvox-omnivox-components--listing-process process)
            (process-put process 'listing-timer
                         (run-at-time 20 nil
                                      (lambda ()
                                        (when (process-live-p process)
                                          (process-put process 'listing-timeout t)
                                          (delete-process process))))))
        (error
         (kill-buffer output)
         (setq emacsvox-omnivox-components--listing-error (error-message-string err)))))))

(defun emacsvox-omnivox-components--human-size (bytes)
  "Return a compact human-readable description of BYTES."
  (cond
   ((zerop bytes) "included")
   ((>= bytes 1048576) (format "%.1f MiB" (/ bytes 1048576.0)))
   (t (format "%.0f KiB" (/ bytes 1024.0)))))

(defun emacsvox-omnivox-components--state (record)
  "Return the displayed state of RECORD, including a pending operation."
  (or
   (when (and (processp emacsvox-omnivox-components--process)
              (not (process-get emacsvox-omnivox-components--process 'emacsvox-release-operation))
              (equal (plist-get record :id)
                     (process-get emacsvox-omnivox-components--process
                                  'emacsvox-component-id)))
     (pcase (process-get emacsvox-omnivox-components--process
                         'emacsvox-operation)
       ('installation "installing")
       ('uninstallation "uninstalling")
       ('configuration-check "checking")
       ('test "testing")))
   (let* ((id (plist-get record :id))
          (main (emacsvox-omnivox-components--engine id))
          (notify (emacsvox-omnivox-components--engine id 'notification)))
     (if (and (emacsvox-omnivox-components--current-snapshot-p 'main)
              (emacsvox-omnivox-components--current-snapshot-p 'notification)
              (not (equal (emacsvox-omnivox-components--signature main)
                          (emacsvox-omnivox-components--signature notify))))
         "Streams differ"
       (emacsvox-omnivox-components--lane-state id 'main)))))

(defun emacsvox-omnivox-components--signature (engine)
  "Return comparable availability, policy and voice identity from ENGINE."
  (list (plist-get engine :availability) (plist-get engine :health)
        (plist-get engine :disabled-by-policy)
        (sort (mapcar (lambda (voice) (plist-get voice :voice-id))
                      (plist-get engine :voices)) #'string<)))

(defun emacsvox-omnivox-components--voice-count (id &optional lane)
  "Return discovered voice count for ID and LANE, or unknown."
  (if-let* ((engine (emacsvox-omnivox-components--engine id lane)))
      (number-to-string (length (plist-get engine :voices)))
    "Unknown"))

(defun emacsvox-omnivox-components--entries (records)
  "Return tabulated entries for component RECORDS."
  (mapcar
   (lambda (record)
     (list
      (plist-get record :id)
      (vector
       (plist-get record :name)
       (emacsvox-omnivox-components--state record)
       (emacsvox-omnivox-components--voice-count (plist-get record :id)))))
   records))

(defun emacsvox-omnivox-components--record (&optional id)
  "Return the current component record, or the record named by ID."
  (let ((id (or id emacsvox-omnivox-components--engine-id (tabulated-list-get-id))))
    (or (cl-find id (emacsvox-omnivox-components--all-records)
                 :test #'string= :key (lambda (record)
                                        (plist-get record :id)))
        (user-error "Move to an Omnivox component row first"))))

(defun emacsvox-omnivox-components--render (&optional id)
  "Redraw current engine records, preserving row ID and current column."
  (emacsvox-aural-ui-refresh-tabulated
   (lambda ()
     (setq tabulated-list-entries
           (emacsvox-omnivox-components--entries
            (emacsvox-omnivox-components--all-records))))
   id "windows"))

(defun emacsvox-omnivox-components-refresh (&optional id)
  "Refresh Omnivox engine status, preserving row ID and current column."
  (interactive)
  (emacsvox-omnivox-components--capture-inventory)
  (emacsvox-omnivox-components--render id)
  (emacsvox-omnivox-components--refresh-details)
  (when (fboundp 'omnivox-refresh-voice-inventory)
    (omnivox-refresh-voice-inventory)))

(defun emacsvox-omnivox-components-speak-current ()
  "Speak engine status and discovered voice count at point."
  (interactive)
  (let* ((record (emacsvox-omnivox-components--record))
         (text
          (format
           "%s. %s. %s voices."
           (plist-get record :name)
           (emacsvox-omnivox-components--state record)
           (emacsvox-omnivox-components--voice-count (plist-get record :id)))))
    (emacsvox-omnivox-components--speak text)))

(defun emacsvox-omnivox-components--running-omnivox-p ()
  "Return non-nil when the active speech server appears to be Omnivox."
  (and (boundp 'tts-speaker-process)
       (process-live-p tts-speaker-process)
       (boundp 'tts-program)
       (string-match-p "omnivox" (format "%s" tts-program))))

(defun emacsvox-omnivox-components--suspend-omnivox ()
  "Retire active Omnivox streams and return non-nil when any were stopped.

This releases persistent Windows helper executables before engine removal."
  (when (emacsvox-omnivox-components--running-omnivox-p)
    (unless (fboundp 'tts--retire-process)
      (error "Cannot safely stop Omnivox before engine removal"))
    (let ((speaker tts-speaker-process)
          (notifier (and (boundp 'tts-notify-process)
                         tts-notify-process)))
      (when (and (processp notifier) (not (eq notifier speaker)))
        (tts--retire-process notifier))
      (when (processp speaker)
        (tts--retire-process speaker))
      (setq tts-speaker-process nil)
      (when (boundp 'tts-notify-process)
        (setq tts-notify-process nil))
      t)))

(defun emacsvox-omnivox-components--last-output-line (output)
  "Return the last useful nonempty line in installer OUTPUT, or nil."
  (cl-find-if
   (lambda (line)
     (not
      (string-match-p
       (concat
        "\\`Process emacsvox-omnivox-component\\(?: stderr\\)? "
        "\\(?:finished\\|exited abnormally.*\\)\\'")
       line)))
   (reverse (split-string output "[\r\n]+" t "[[:space:]]+"))))

(defun emacsvox-omnivox-components--result-message
    (name operation success output event)
  "Describe the result for NAME and OPERATION.

SUCCESS is non-nil for a successful process.  Prefer useful details from
OUTPUT to the generic process sentinel EVENT."
  (let ((last-line
         (emacsvox-omnivox-components--last-output-line output)))
    (cond
     ((and success (eq operation 'test)
           (string-match "Found \\([0-9]+\\) voices:" output))
      (format "%s release check found %s voices. Read last result for details"
              name (match-string 1 output)))
     ((and success (eq operation 'test))
      (format "%s release voice check succeeded%s. Read last result for details"
              name (if last-line (format ": %s" last-line) "")))
     ((and success (eq operation 'installation))
      (format "%s installed" name))
     ((and success (eq operation 'uninstallation))
      (format "%s removed from the installed release" name))
     ((and (not success) (eq operation 'uninstallation)
           (string-search "helper is still in use" output))
      (format "%s removal failed: its helper is still in use. Stop sessions using it, then retry" name))
     (success
      (format "%s %s completed" name operation))
     (t
      (format "%s %s failed: %s. Results in engine details"
              name operation
              (or last-line (string-trim event) "unknown error"))))))

(defun emacsvox-omnivox-components--show-output (output)
  "Select installer OUTPUT as an accessible result buffer."
  (when (buffer-live-p output)
    (with-current-buffer output
      (emacsvox-aural-interface-mode)
      (local-set-key (kbd "h") #'emacsvox-aural)
      (goto-char (point-min)))
    (emacsvox-aural-ui-pop-to-buffer output)))

(defun emacsvox-omnivox-components--notice (text)
  "Report a short completion TEXT without interrupting foreground speech."
  (if (fboundp 'tts-notify) (tts-notify text) (message "%s" text)))

(defun emacsvox-omnivox-components--finish (process event)
  "Handle completion of component PROCESS described by EVENT."
  (when (memq (process-status process) '(exit signal))
    (when-let* ((timer (process-get process 'emacsvox-check-timer)))
      (cancel-timer timer))
    (let* ((manager (process-get process 'emacsvox-manager-buffer))
           (operation (process-get process 'emacsvox-operation))
           (name (process-get process 'emacsvox-component-name))
           (id (process-get process 'emacsvox-component-id))
           (restore-omnivox
            (process-get process 'emacsvox-restore-omnivox))
           (output (process-buffer process))
           (success (and (eq (process-status process) 'exit)
                         (zerop (process-exit-status process))))
           (output-text
            (if (buffer-live-p output)
                (with-current-buffer output (buffer-string))
              ""))
           (expected (process-get process 'emacsvox-expected-voice-count))
           (found (and (string-match "Found \\([0-9]+\\) voices:" output-text)
                       (string-to-number (match-string 1 output-text))))
           (_checked-files
            (when (and success expected (or (null found) (< found expected)))
              (setq success nil
                    output-text
                    (concat output-text
                            (format "\nExpected at least %d voices%s; found %s. Check selected files and duplicate voice names.\n"
                                    expected (if (equal id "flite") " including built-in SLT" "")
                                    (or found "no reported count"))))))
           (message-text
            (emacsvox-omnivox-components--result-message
             name operation success output-text event)))
      (when (buffer-live-p manager)
        (with-current-buffer manager
          (when (eq process emacsvox-omnivox-components--process)
            (setq emacsvox-omnivox-components--process nil)
            (setf (alist-get id emacsvox-omnivox-components--results nil nil #'equal)
                  (list :operation operation :success success :time (current-time)
                        :release (process-get process 'emacsvox-release-operation)
                        :installer (car (process-command process))
                        :summary message-text :output output-text))
            (condition-case err
                (if (process-get process 'emacsvox-release-operation)
                    (progn
                      (emacsvox-omnivox-components--request-records)
                      (emacsvox-omnivox-components--refresh-details))
                  (emacsvox-omnivox-components-refresh))
              (error
               (emacsvox-omnivox-components--render)
               (setq message-text
                     (format "%s; refresh failed: %s"
                             message-text (error-message-string err))))))))
      (when (and (not (process-get process 'emacsvox-release-operation))
                 (or restore-omnivox
                     (and success
                          (memq operation
                                '(installation uninstallation))
                          emacsvox-omnivox-restart-after-component-install
                          (emacsvox-omnivox-components--running-omnivox-p)))
                 (fboundp 'tts-restart))
        (condition-case err
            (tts-restart)
          (error
           (setq message-text
                 (format "%s; Omnivox restart failed: %s"
                         message-text (error-message-string err))))))
      (emacsvox-omnivox-components--notice
       (cond
        ((string-match-p "restart failed" message-text)
         (format "%s %s %s; speech restart failed. Read last result."
                 name operation (if success "completed" "failed")))
        ((and (eq operation 'uninstallation)
              (or success (string-search "helper is still in use" output-text)))
         message-text)
        (t (format "%s %s %s. Results in engine details."
                   name operation (if success "completed" "failed")))))
      (when (buffer-live-p manager)
        (with-current-buffer manager
          (let ((result (alist-get id emacsvox-omnivox-components--results nil nil #'equal)))
            (when result
              (setf (plist-get result :summary) message-text
                    (plist-get result :output)
                    (concat output-text "\n" message-text "\n"))))
          (emacsvox-omnivox-components--refresh-details))))))

(defun emacsvox-omnivox-components--start (record operation arguments)
  "Start OPERATION for component RECORD using installer ARGUMENTS."
  (when (process-live-p emacsvox-omnivox-components--process)
    (user-error "An Omnivox component operation is already running"))
  (let* ((program (emacsvox-omnivox-components--check-installer))
         (output (get-buffer-create
                  emacsvox-omnivox-components--output-buffer))
         (manager (current-buffer))
         (restore-omnivox nil)
         (process-environment (copy-sequence process-environment)))
    (when emacsvox-omnivox-components--release-operation
      (unless (and emacsvox-omnivox-components--release-target
                   (not emacsvox-omnivox-components--listing-error)
                   (not (process-live-p emacsvox-omnivox-components--listing-process)))
        (user-error "Wait for the installed release identity, or refresh its status"))
      (setenv "EMACSVOX_COMPONENT_EXPECTED_TARGET"
              (plist-get emacsvox-omnivox-components--release-target :detail)))
    (with-current-buffer output
      (let ((inhibit-read-only t))
        (erase-buffer)
        (fundamental-mode)))
    (emacsvox-omnivox-components--speak
     (format "%s %s started" (plist-get record :name) operation))
    (condition-case err
        (progn
          (when (and (eq operation 'uninstallation)
                     (not emacsvox-omnivox-components--release-operation))
            (setq restore-omnivox
                  (emacsvox-omnivox-components--running-omnivox-p))
            (when restore-omnivox
              (emacsvox-omnivox-components--suspend-omnivox)))
          (setq emacsvox-omnivox-components--process
                (make-process
                 :name "emacsvox-omnivox-component"
                 :buffer output
                 :stderr output
                 :command (cons program arguments)
                 :connection-type 'pipe
                 :coding 'utf-8
                 :noquery t
                 :sentinel #'emacsvox-omnivox-components--finish)))
      (error
       (when (and restore-omnivox (fboundp 'tts-restart))
         (tts-restart))
       (signal (car err) (cdr err))))
    (process-put emacsvox-omnivox-components--process
                 'emacsvox-manager-buffer manager)
    (process-put emacsvox-omnivox-components--process
                 'emacsvox-operation operation)
    (process-put emacsvox-omnivox-components--process
                 'emacsvox-component-id (plist-get record :id))
    (process-put emacsvox-omnivox-components--process
                 'emacsvox-component-name (plist-get record :name))
    (process-put emacsvox-omnivox-components--process
                 'emacsvox-restore-omnivox restore-omnivox)
    (process-put emacsvox-omnivox-components--process
                 'emacsvox-release-operation emacsvox-omnivox-components--release-operation)
    (when (derived-mode-p 'emacsvox-omnivox-components-mode)
      (emacsvox-omnivox-components--render)
      (emacsvox-omnivox-components--refresh-details))
    emacsvox-omnivox-components--process))

(defun emacsvox-omnivox-components-install ()
  "Select the installed release, then download and install an optional engine."
  (interactive)
  (if (not emacsvox-omnivox-components--release-operation)
      (emacsvox-omnivox-components--open-release)
    (let* ((record (emacsvox-omnivox-components--record))
           (state (plist-get record :state))
           (name (plist-get record :name))
           (id (plist-get record :id)))
      (unless (string= state "available")
        (user-error "%s is not currently downloadable: %s" name state))
      (when
          (yes-or-no-p
           (concat
            (format "Install %s (%s) in %s? " name
                    (emacsvox-omnivox-components--human-size
                     (plist-get record :size))
                    (or (plist-get emacsvox-omnivox-components--release-target :name) "the installed release"))
            (pcase id
              ("piper" "A separately reviewed voice model will still be required. ")
              ("tgspeechbox" "This engine is experimental. ")
              (_ ""))))
        (emacsvox-omnivox-components--start
         record 'installation (list "--install" id))))))

(defun emacsvox-omnivox-components-uninstall ()
  "Select the installed release, then confirm removal of an optional engine."
  (interactive)
  (if (not emacsvox-omnivox-components--release-operation)
      (emacsvox-omnivox-components--open-release)
    (let* ((record (emacsvox-omnivox-components--record))
           (state (plist-get record :state))
           (name (plist-get record :name))
           (id (plist-get record :id)))
      (unless (member id emacsvox-omnivox-components--managed-ids)
        (user-error
         "%s is part of the core or uses a user-supplied runtime" name))
      (unless (member state '("installed" "model-required"))
        (user-error "%s is not installed by this manager: %s" name state))
      (when
          (yes-or-no-p
           (concat
            (format "Uninstall %s from %s? " name
                    (or (plist-get emacsvox-omnivox-components--release-target :name) "the installed release"))
            "Its verified download remains cached. "
            "Files manually added inside its managed directory are also removed. "))
        (emacsvox-omnivox-components--start
         record 'uninstallation (list "--uninstall" id))))))

(defun emacsvox-omnivox-components-test ()
  "Select the installed release, then check its engine's runtime and voices."
  (interactive)
  (if (not emacsvox-omnivox-components--release-operation)
      (emacsvox-omnivox-components--open-release)
    (let ((record (emacsvox-omnivox-components--record)))
      (emacsvox-omnivox-components--start
       record 'test (list "--test" (plist-get record :id))))))

(defun emacsvox-omnivox-components-activate ()
  "Open details for the selected engine."
  (interactive)
  (emacsvox-omnivox-components--show-details
   (plist-get (emacsvox-omnivox-components--record) :id)
   (current-buffer) (current-buffer)))

(defun emacsvox-omnivox-components--show-details (id manager parent)
  "Show engine ID from MANAGER, returning to browser PARENT."
  (let ((buffer (get-buffer-create (format "*Omnivox Engine: %s*" id))))
    (with-current-buffer buffer
      (unless (derived-mode-p 'emacsvox-omnivox-engine-details-mode)
        (emacsvox-omnivox-engine-details-mode))
      (setq emacsvox-omnivox-components--manager manager
            emacsvox-omnivox-components--release-view nil
            emacsvox-omnivox-components--details-parent parent
            emacsvox-omnivox-components--engine-id id)
      (emacsvox-aural-inspection-attach-source
       (emacsvox-aural-inspection-source-buffer manager))
      (emacsvox-omnivox-components--render-details))
    (emacsvox-aural-ui--pop-to-buffer
     buffer #'emacsvox-omnivox-components--speak-details-opening)
    (with-current-buffer manager
      (emacsvox-omnivox-components--refresh-old-inventory))))

(defun emacsvox-omnivox-components--manager-buffer (&optional source)
  "Prepare retained management state from cached speech discovery and SOURCE."
  (let ((buffer (get-buffer-create "*Omnivox Engines*")))
    (with-current-buffer buffer
      (unless (derived-mode-p 'emacsvox-omnivox-components-mode)
        (emacsvox-omnivox-components-mode))
      (emacsvox-aural-inspection-attach-source source)
      (emacsvox-omnivox-components--capture-inventory)
      (emacsvox-omnivox-components--render))
    buffer))

(defun emacsvox-omnivox-components--open-engine (id parent)
  "Open ID's current speech details from PARENT without probing a release."
  (let ((manager (emacsvox-omnivox-components--manager-buffer
                  (emacsvox-aural-inspection-source-buffer parent))))
    (with-current-buffer manager
      (unless (cl-find id (emacsvox-omnivox-components--all-records)
                       :key (lambda (record) (plist-get record :id)) :test #'equal)
        (let ((engine (cl-find id (emacsvox-omnivox-components--browse-engines nil)
                               :key (lambda (entry) (plist-get entry :engine-id)) :test #'equal)))
          (push (list :id id :name (or (plist-get engine :display-name) id)
                      :state "not-checked" :size 0) emacsvox-omnivox-components--records)))
      (emacsvox-omnivox-components--render id))
    (emacsvox-omnivox-components--show-details id manager parent)))

(defun emacsvox-omnivox-components--process-description (process)
  "Describe PROCESS, including retained stopped workers, without credentials."
  (if (not (processp process)) "No recorded worker"
    (concat
     (unless (process-live-p process) "Stopped; ")
     (if (eq (process-type process) 'network)
         (format "Remote speech connection %s via %s:%s"
                 (process-name process)
                 (process-contact process :host) (process-contact process :service))
       (format "Process %s; %s" (process-id process)
               (or (car (process-command process)) (process-name process)))))))

(defun emacsvox-omnivox-components--runtime-state (id lane)
  "Describe ID's native runtime using only current LANE discovery."
  (let* ((engine (emacsvox-omnivox-components--engine id lane))
         (availability (plist-get engine :availability))
         (reason (or (plist-get engine :availability-reason)
                     (plist-get engine :health-reason)
                     (plist-get engine :last-failure))))
    (cond
     ((not (emacsvox-omnivox-components--current-snapshot-p lane))
      "Not checked for current worker")
     ((null engine) "Not checked")
     ((or (plist-get engine :disabled-by-policy)
          (and reason (string-match-p "[Dd]isabled\\|[Ee]xcluded" reason)))
      "Disabled; runtime status not established")
     ((and (equal availability "available")
           (member (plist-get engine :health) '(nil "unknown" "healthy")))
      (pcase id
        ("dectalk" "DLL and dictionary loaded successfully")
        ("eloquence" "ECI library loaded successfully")
        ("rhvoice" "RHVoice library loaded successfully")
        ("piper" "Piper library loaded successfully")
        ("mbrola" "MBROLA runtime initialized successfully")
        (_ "Runtime initialized successfully")))
     ((equal availability "unknown") "Not checked")
     (reason
      (let ((case-fold-search t))
        (concat
         (cond
          ((string-match-p "not found\\|no such file\\|cannot find\\|could not find\\|is missing\\|was missing" reason)
           "Missing: ")
          ((string-match-p "failed to load\\|could not load\\|could not be loaded\\|cannot load\\|load.*fail\\|initializ.*fail\\|wrong architecture\\|invalid.*library\\|bad exe" reason)
           "Load failed: ")
          (t "Unavailable: "))
         reason)))
     (t "Unavailable; no runtime reason reported"))))

(defun emacsvox-omnivox-components--runtime-rows (id)
  "Show required native runtime evidence for ID near the engine summary."
  (when (member id '("dectalk" "eloquence" "rhvoice" "piper" "mbrola"))
    (let ((main (emacsvox-omnivox-components--runtime-state id 'main))
          (notification (emacsvox-omnivox-components--runtime-state id 'notification)))
      (if (equal main notification)
          (list (list 'runtime (vector "Required runtime" (concat main " on both streams"))))
        (list (list 'main-runtime-status (vector "Main runtime" main))
              (list 'notification-runtime-status (vector "Notification runtime" notification)))))))

(defun emacsvox-omnivox-components--release-file-state (record)
  "Describe the release installer's file evidence for RECORD."
  (pcase (plist-get record :state)
    ("runtime-required" "Bridge found; Check release engine tests its required runtime")
    ("model-required" "Engine files found; Check release engine tests voice discovery")
    ("installed" "Engine files found")
    ("available" "Not installed; download available")
    ((or "core-missing" "core-update-required") "Required engine files missing")
    ("not-managed" "Not supplied by this release installer")
    (_ (or (plist-get record :detail) "Not checked"))))

(defun emacsvox-omnivox-components--release-rows (id)
  "Describe the explicitly selected installer release for engine ID."
  (let* ((record (emacsvox-omnivox-components--record id))
         (target emacsvox-omnivox-components--release-target)
         (result (alist-get id emacsvox-omnivox-components--results nil nil #'equal))
         (result (when (plist-get result :release) result))
         (ready (and target (not emacsvox-omnivox-components--listing-error)
                     (not (process-live-p emacsvox-omnivox-components--listing-process))))
         (operation emacsvox-omnivox-components--process))
    (append
     (list
      (list 'summary (vector (plist-get record :name) "Installed release management"))
      (list 'release-target (vector "Installation being managed"
                                    (or (plist-get target :name) "Waiting for release identity")))
      (list 'release-location (vector "Location" (or (plist-get target :detail) "Not checked")))
      (list 'release-purpose (vector "Scope" "Changes this release's files; speech selection is unchanged"))
      (list 'release-files
            (vector "Installed engine files"
                    (cond
                     ((process-live-p emacsvox-omnivox-components--listing-process) "Refreshing")
                     (emacsvox-omnivox-components--listing-error
                      (concat "Not checked: " emacsvox-omnivox-components--listing-error))
                     (t (emacsvox-omnivox-components--release-file-state record))))))
     (when (and (process-live-p operation)
                (equal id (process-get operation 'emacsvox-component-id))
                (process-get operation 'emacsvox-release-operation))
       (list (list 'release-progress
                   (vector "Operation" (format "%s in progress" (process-get operation 'emacsvox-operation))))))
     (when ready
       (append
        (when (equal (plist-get record :state) "available")
          (list (list 'install (vector "Install engine"
                                       (emacsvox-omnivox-components--human-size (plist-get record :size))))))
        (when (and (member id emacsvox-omnivox-components--managed-ids)
                   (member (plist-get record :state) '("installed" "model-required")))
          (list (list 'uninstall (vector "Uninstall engine" "Remove this release's engine files"))))
        (unless (member (plist-get record :state) '("not-managed" "not-checked"))
          (list (list 'test (vector "Check release engine" "Test runtime and voice discovery in this release"))))))
     (list (list 'check-live (vector "Refresh release files" "Update this installer's file information")))
     (when result
       (list (list 'result (vector "Last release operation" (plist-get result :summary)))
             (list 'output (vector "Read last result" "Complete output from the release operation"))))
     (list (list 'back (vector "Back to current engine" "Return to the running speech workers"))))))

(defun emacsvox-omnivox-components--release-supported-p ()
  "Whether this Emacs host supports the selected release installer."
  (or (not (equal (expand-file-name emacsvox-omnivox-component-installer)
                  (expand-file-name "bin/emacsvox-omnivox-components" emacsvox-directory)))
      (and (eq system-type 'gnu/linux)
           (or (getenv "WSL_DISTRO_NAME")
               (file-exists-p "/proc/sys/fs/binfmt_misc/WSLInterop")))))

(defun emacsvox-omnivox-components--open-release ()
  "Explicitly select the WSL installed release for engine management."
  (unless (emacsvox-omnivox-components--release-supported-p)
    (user-error "The configured release installer requires WSL"))
  (unless (derived-mode-p 'emacsvox-omnivox-engine-details-mode)
    (emacsvox-omnivox-components--show-details
     (plist-get (emacsvox-omnivox-components--record) :id)
     (current-buffer) (current-buffer)))
  (setq emacsvox-omnivox-components--release-view t)
  (with-current-buffer emacsvox-omnivox-components--manager
    (emacsvox-omnivox-components--request-records))
  (emacsvox-omnivox-components--render-details)
  (emacsvox-aural-ui-goto-row 'release-target)
  (emacsvox-omnivox-components--speak-detail))

(defun emacsvox-omnivox-components--detail-rows (id)
  "Return detail rows for ID using this manager's retained evidence."
  (let* ((record (or (cl-find id (emacsvox-omnivox-components--all-records)
                              :key (lambda (entry) (plist-get entry :id)) :test #'equal)
                     (list :id id :name id :state "not-managed" :size 0)))
         (result (alist-get id emacsvox-omnivox-components--results nil nil #'equal))
         (result (unless (plist-get result :release) result))
         (runtime-rows (emacsvox-omnivox-components--runtime-rows id))
         (rows (list (list 'summary (vector (plist-get record :name)
                                           (emacsvox-omnivox-components--summary record))))))
    (dolist (lane '(main notification))
      (when (and (not runtime-rows)
                 (emacsvox-omnivox-components--current-snapshot-p lane)
                 (string-search "attention" (emacsvox-omnivox-components--lane-state id lane)))
        (let* ((engine (emacsvox-omnivox-components--engine id lane))
               (reason (or (plist-get engine :availability-reason)
                           (plist-get engine :health-reason)
                           (plist-get engine :last-failure)
                           "Expand Diagnostics for the reported status")))
          (setq rows
                (append rows (list (list (if (eq lane 'main) 'main-problem 'notification-problem)
                                         (vector (if (eq lane 'main) "Main speech problem" "Notification problem")
                                                 reason))))))))
    (dolist (lane '(main notification))
      (let* ((engine (emacsvox-omnivox-components--engine id lane))
             (inventory (plist-get (alist-get lane emacsvox-omnivox-components--snapshots)
                                   :inventory))
             (time (plist-get inventory :received-at))
             (label (if (eq lane 'main) "Main speech" "Notification speech")))
        (setq rows
              (append rows
                      (list
                       (list lane (vector label
                                          (format "%s; %s voices"
                                                  (emacsvox-omnivox-components--lane-state id lane)
                                                  (emacsvox-omnivox-components--voice-count id lane))))
                       (list (intern (format "%s-target" lane))
                             (vector "Current worker"
                                     (emacsvox-omnivox-components--process-description
                                      (emacsvox-omnivox-components--lane-process lane))))
                       (list (intern (format "%s-source" lane))
                             (vector "Checked worker"
                                     (emacsvox-omnivox-components--process-description
                                      (plist-get (alist-get lane emacsvox-omnivox-components--snapshots)
                                                 :process))))
                       (list (intern (format "%s-time" lane))
                             (vector "Inventory received"
                                     (if time (format-time-string "%Y-%m-%d %H:%M:%S %Z" time)
                                       "Not timed; check again")))
                       (list (intern (format "%s-runtime" lane))
                             (vector "Runtime discovery"
                                     (cond
                                      ((null engine) "Not checked")
                                      ((equal (plist-get engine :availability) "available")
                                       "Found and loaded at the recorded check")
                                      (t (or (plist-get engine :availability-reason)
                                             "Not available; no reason reported")))))
                       (list (intern (format "%s-health" lane))
                             (vector "Health"
                                     (mapconcat
                                      (lambda (value) (format "%s" value))
                                      (delq nil (list (or (plist-get engine :health) "Not checked")
                                                      (plist-get engine :health-reason)
                                                      (plist-get engine :last-failure))) "; "))))))))
    (append
     rows
     runtime-rows
     (when (equal id "mbrola")
       (list
        (list 'prototype (vector "Prototype"
                                 "Engine supplied separately; US1, US2 and US3 voice downloads available with the updated companion; en1 included"))
        (list 'prototype-setup
              (vector "Prototype setup"
                      "Set OMNIVOX_MBROLA_HELPER in the speech host's launcher to the absolute native helper path, with its complete prototype bundle; restart both streams, then Refresh status"))))
     (list
      (list 'voices (vector "Browse voices" "Sample voices, enable or disable, and Apply"))
      (list 'check-live (vector "Refresh status" "Update runtime and voice discovery on both streams")))
     (when (emacsvox-omnivox-components--release-supported-p)
       (list (list 'release-manager (vector "Manage installed release"
                                            "Open the release installer and its target location"))))
     (when (member id '("piper" "flite" "mbrola"))
       (list
        (list 'download-voices (vector "Get more voices" "Download voices, then enable and Apply"))))
     (when (equal id "espeak")
       (list (list 'espeak-variants (vector "Voice variants" "Preview bundled variants and use them in a palette"))))
     (when-let* ((description (omnivox-engine-settings--description id)))
       (append
        (list (list 'settings-state (vector "Manual file settings" description)))
        (when (omnivox-engine-settings--supported-p)
          (list
           (list 'settings (vector "Edit file settings" "Manual files for this Emacs profile; used after restart"))
           (list 'check-settings (vector "Check configured engine" "Separate local discovery, 30 second limit; no sample or live restart"))
           (list 'restart-settings (vector "Restart local speech" "Restart this session's main and notification workers with current settings"))))))
     (when result
       (list
        (list 'result (vector "Last configured check"
                              (format "%s; %s; %s"
                                      (plist-get result :operation)
                                      (if (plist-get result :success) "succeeded" "failed")
                                      (format-time-string "%Y-%m-%d %H:%M:%S %Z" (plist-get result :time)))))
        (list 'output (vector "Read last result" "Retained output from that operation"))))
     (when (and result (not (plist-get result :success)))
       (list (list 'operation-error
                   (vector "Last operation failed"
                           (if (string-search "helper is still in use" (or (plist-get result :output) ""))
                               "Engine was not removed: helper still in use. Stop sessions using it, then retry"
                             "Read last result for the error and next steps")))))
     (list (list 'back (vector "Back to engines" "Return to the selected engine"))))))

(defun emacsvox-omnivox-components--summary (record)
  "Summarize RECORD, combining matching main and notification voice counts."
  (let* ((id (plist-get record :id))
         (state (emacsvox-omnivox-components--state record))
         (main (emacsvox-omnivox-components--voice-count id))
         (notification (emacsvox-omnivox-components--voice-count id 'notification))
         (main-state (emacsvox-omnivox-components--lane-state id 'main))
         (notification-state (emacsvox-omnivox-components--lane-state id 'notification)))
    (cond
     ((and (equal main "Unknown") (equal notification "Unknown")) state)
     ((not (equal main-state notification-state))
      (format "%s; main: %s, %s voices; notification: %s, %s voices"
              state main-state main notification-state notification))
     ((and (equal main notification)
           (not (equal state "Streams differ")))
      (format "%s; %s voice%s on both streams" state main (if (equal main "1") "" "s")))
     (t (format "%s; main %s voices; notification %s voices" state main notification)))))

(defconst emacsvox-omnivox-components--detail-sections
  '((startup-section "Startup settings" settings-state settings check-settings restart-settings)
    (result-section "Last configured check" result output)
    (diagnostics-section "Diagnostics"
                         main main-target main-source main-time main-runtime main-health
                         notification notification-target notification-source
                         notification-time notification-runtime notification-health))
  "Collapsible section identifiers, labels, and retained detail fields.")

(defun emacsvox-omnivox-components--layout-details (rows)
  "Present ROWS with common actions first and optional sections collapsed."
  (let* ((failed (assq 'operation-error rows))
         (visible (delq nil (mapcar (lambda (id) (assq id rows))
                                   (append '(summary runtime main-runtime-status notification-runtime-status main-problem notification-problem operation-error prototype)
                                           (when failed '(output))
                                           '(voices download-voices espeak-variants check-live prototype-setup release-manager))))))
    (dolist (section emacsvox-omnivox-components--detail-sections)
      (let* ((id (car section))
             (expanded (memq id emacsvox-omnivox-components--expanded-sections))
             (fields (delq nil (mapcar (lambda (field)
                                        (unless (and failed (eq field 'output)) (assq field rows)))
                                      (cddr section)))))
        (when fields
          (setq visible
                (append visible
                        (list (list id (vector (emacsvox-aural-ui--expansion-text (cadr section) expanded)
                                               (if expanded "Expanded" "Collapsed"))))
                        (when expanded fields))))))
    (append visible (list (assq 'back rows)))))

(defun emacsvox-omnivox-components--toggle-section ()
  "Expand or collapse the selected section and announce its new state."
  (let ((id (tabulated-list-get-id)))
    (if (memq id emacsvox-omnivox-components--expanded-sections)
        (setq emacsvox-omnivox-components--expanded-sections
              (delq id emacsvox-omnivox-components--expanded-sections))
      (push id emacsvox-omnivox-components--expanded-sections))
    (emacsvox-omnivox-components--render-details)
    (emacsvox-aural-ui--announce-expansion
     (memq id emacsvox-omnivox-components--expanded-sections))))

(defun emacsvox-omnivox-components--speak-details-opening ()
  "Announce the engine summary and the selected action together."
  (let ((summary (cadr (assq 'summary tabulated-list-entries)))
        (row (tabulated-list-get-entry)))
    (emacsvox-omnivox-components--speak
     (format "%s. %s%s" (aref summary 0) (aref summary 1)
             (if (eq (tabulated-list-get-id) 'summary) ""
               (format ". %s" (aref row 0)))))))

(defun emacsvox-omnivox-components--render-details ()
  "Redraw this details view, preserving its selected field and column."
  (setq header-line-format
        (if emacsvox-omnivox-components--release-view
            " Installed release; g refresh release files; q back to current engine"
          " Current speech workers; RET actions/sections; TAB actions; g refresh; q back"))
  (when (buffer-live-p emacsvox-omnivox-components--manager)
    (let* ((id emacsvox-omnivox-components--engine-id)
           (release emacsvox-omnivox-components--release-view)
           (rows (with-current-buffer emacsvox-omnivox-components--manager
                   (if release
                       (emacsvox-omnivox-components--release-rows id)
                     (emacsvox-omnivox-components--detail-rows id)))))
      (emacsvox-aural-ui-refresh-tabulated
       (lambda () (setq tabulated-list-entries
                        (if release rows (emacsvox-omnivox-components--layout-details rows)))) nil (if release 'release-target 'voices)))))

(defun emacsvox-omnivox-components--refresh-details ()
  "Redraw details belonging to this manager without selecting a window."
  (let ((manager (current-buffer)))
    (dolist (buffer (buffer-list))
      (with-current-buffer buffer
        (when (and (derived-mode-p 'emacsvox-omnivox-engine-details-mode)
                   (eq emacsvox-omnivox-components--manager manager))
          (emacsvox-omnivox-components--render-details))))))

(defun emacsvox-omnivox-components--check-live ()
  "Request fresh discovery from the connected speech workers."
  (interactive)
  (unless (and (fboundp 'omnivox-refresh-voice-inventory)
               (fboundp 'omnivox--process-supports-p)
               (cl-some (lambda (lane)
                          (let ((process (emacsvox-omnivox-components--lane-process lane)))
                            (and (process-live-p process)
                                 (omnivox--process-supports-p process "engine_inventory"))))
                        '(main notification)))
    (user-error "No connected Omnivox inventory service"))
  (omnivox-refresh-voice-inventory))

(defun emacsvox-omnivox-components--details-back ()
  "Return to the parent engine row."
  (interactive)
  (if emacsvox-omnivox-components--release-view
      (progn
        (setq emacsvox-omnivox-components--release-view nil)
        (emacsvox-omnivox-components--render-details)
        (emacsvox-aural-ui-goto-row 'release-manager)
        (emacsvox-omnivox-components--speak-detail))
    (let ((id emacsvox-omnivox-components--engine-id)
          (parent (or emacsvox-omnivox-components--details-parent
                      emacsvox-omnivox-components--manager)))
      (unless (buffer-live-p parent) (user-error "The engine list was closed"))
      (with-current-buffer parent
        (if (derived-mode-p 'emacsvox-omnivox-components-mode)
            (emacsvox-omnivox-components--render id)
          (let ((column (emacsvox-aural-ui-tabulated-column-index)))
            (emacsvox-aural-ui-goto-row id)
            (emacsvox-aural-ui-goto-tabulated-column column))))
      ;; Unwind the details window before returning, so quitting the engine
      ;; list cannot restore these details from its window history.
      (quit-window)
      (emacsvox-aural-ui--pop-to-buffer
       parent (if (with-current-buffer parent
                    (derived-mode-p 'emacsvox-omnivox-components-mode))
                  #'emacsvox-omnivox-components-speak-current
                #'emacsvox-aural-voice-workbench-speak-current)))))

(defun emacsvox-omnivox-components--details-activate ()
  "Perform the action on the selected detail row, or speak its value."
  (interactive)
  (let ((action (tabulated-list-get-id))
        (id emacsvox-omnivox-components--engine-id)
        (manager emacsvox-omnivox-components--manager))
    (unless (buffer-live-p manager) (user-error "The engine list was closed"))
    (cond
     ((assq action emacsvox-omnivox-components--detail-sections)
      (emacsvox-omnivox-components--toggle-section))
     ((eq action 'back) (emacsvox-omnivox-components--details-back))
     ((eq action 'check-live) (emacsvox-omnivox-components--details-refresh))
     ((eq action 'release-manager) (emacsvox-omnivox-components--open-release))
     ((eq action 'voice-library)
      (require 'omnivox-library)
      (omnivox-library id))
     ((eq action 'download-voices)
      (require 'omnivox-catalogue)
      (omnivox-catalogue id))
     ((eq action 'espeak-variants)
      (require 'omnivox-espeak-variants)
      (omnivox-espeak-variants))
     ((eq action 'voices)
      (require 'emacsvox-aural-voice-workbench)
      (emacsvox-aural-voice-workbench--open-engine id (current-buffer)))
     ((memq action '(settings check-settings restart-settings))
      (unless (omnivox-engine-settings--supported-p)
        (user-error "Engine file settings require the bundled local Omnivox launcher"))
      (pcase action
        ('settings
         (customize-option (nth 1 (assoc id omnivox-engine-settings--providers))))
        ('check-settings
         (with-current-buffer manager
           (let* ((emacsvox-omnivox-component-installer
                   (expand-file-name "omnivox" emacsvox-servers-directory))
                  (process-environment
                   (omnivox-engine-settings--environment emacsvox-omnivox-component-installer))
                  (record (emacsvox-omnivox-components--record id)))
             (setenv "EMACSVOX_OMNIVOX_DIAGNOSTIC" "1")
             (let ((process (emacsvox-omnivox-components--start
                             record 'configuration-check (list "--engine" id "--list-voices"))))
               (process-put process 'emacsvox-expected-voice-count
                            (if (and (equal id "flite")
                                     (not (omnivox-engine-settings--override
                                           (assoc id omnivox-engine-settings--providers))))
                                (1+ (cl-count-if #'car omnivox-flite-voice-files)) 1))
               (process-put process 'emacsvox-check-timer
                            (run-at-time 30 nil
                                         (lambda ()
                                           (when (process-live-p process)
                                             (unwind-protect
                                                 (when (buffer-live-p (process-buffer process))
                                                   (with-current-buffer (process-buffer process)
                                                     (let ((inhibit-read-only t))
                                                       (goto-char (point-max))
                                                       (insert "\nConfigured engine check timed out\n"))))
                                               (delete-process process))))))))))
        ('restart-settings
         (tts-restart)
         (emacsvox-omnivox-components--speak
          "Speech restart requested. Refresh live voices to check both workers."))))
     ((memq action '(install uninstall test))
      (unless emacsvox-omnivox-components--release-view
        (user-error "Choose Manage installed release first"))
      (with-current-buffer manager
        (let ((emacsvox-omnivox-components--engine-id id)
              (emacsvox-omnivox-components--release-operation t))
          (funcall (pcase action
                     ('install #'emacsvox-omnivox-components-install)
                     ('uninstall #'emacsvox-omnivox-components-uninstall)
                     ('test #'emacsvox-omnivox-components-test))))))
     ((eq action 'output)
      (let* ((result (with-current-buffer manager
                       (alist-get id emacsvox-omnivox-components--results nil nil #'equal)))
             (output (get-buffer-create (format "*Omnivox Result: %s*" id))))
        (with-current-buffer output
          (let ((inhibit-read-only t))
            (erase-buffer)
            (insert (or (plist-get result :output) "No retained output"))))
        (emacsvox-omnivox-components--show-output output)))
     (t (emacsvox-aural-ui-speak-current-row)))))

(defun emacsvox-omnivox-components--details-next-action ()
  "Move to the next actionable detail row."
  (interactive)
  (emacsvox-omnivox-components--details-move-action 1))

(defun emacsvox-omnivox-components--details-previous-action ()
  "Move to the previous actionable detail row."
  (interactive)
  (emacsvox-omnivox-components--details-move-action -1))

(defun emacsvox-omnivox-components--details-move-action (direction)
  "Move DIRECTION to a visible action or section, preserving boundary position."
  (let ((start (point)))
    (forward-line direction)
    (while (and (not (eobp))
                (not (or (assq (tabulated-list-get-id) emacsvox-omnivox-components--detail-sections)
                         (memq (tabulated-list-get-id)
                               '(voices voice-library download-voices espeak-variants check-live release-manager settings check-settings restart-settings install uninstall test output back))))
                (zerop (forward-line direction))))
    (unless (or (assq (tabulated-list-get-id) emacsvox-omnivox-components--detail-sections)
                (memq (tabulated-list-get-id)
                      '(voices voice-library download-voices espeak-variants check-live release-manager settings check-settings restart-settings install uninstall test output back)))
      (goto-char start))
    (emacsvox-aural-ui-speak-current-row)))

(defun emacsvox-omnivox-components--details-refresh ()
  "Request fresh evidence while retaining the selected detail field."
  (interactive)
  (unless (buffer-live-p emacsvox-omnivox-components--manager)
    (user-error "The engine list was closed"))
  (let ((release emacsvox-omnivox-components--release-view))
    (with-current-buffer emacsvox-omnivox-components--manager
      (if release
          (progn
            (emacsvox-omnivox-components--request-records)
            (emacsvox-omnivox-components--refresh-details))
        (emacsvox-omnivox-components-refresh)))))

(defun emacsvox-omnivox-components--speak-detail ()
  "Speak the selected engine detail's label and value."
  (let ((row (or (tabulated-list-get-entry) (user-error "Move to a detail first"))))
    (emacsvox-aural-ui--speak-control (format "%s. %s" (aref row 0) (aref row 1)))))

(define-derived-mode emacsvox-omnivox-engine-details-mode
    emacsvox-aural-tabulated-mode "Omnivox-Engine"
  "Spoken engine actions with collapsible settings and diagnostics."
  (emacsvox-aural-ui-configure-tabulated
   "Omnivox engine details" #'emacsvox-omnivox-components--speak-detail
   #'emacsvox-omnivox-components--details-refresh)
  (setq tabulated-list-format '[("Item" 25 nil) ("Details" 0 nil)]
        tabulated-list-padding 2)
  (tabulated-list-init-header))

(dolist (binding '(("RET" . emacsvox-omnivox-components--details-activate)
                   ("TAB" . emacsvox-omnivox-components--details-next-action)
                   ("<backtab>" . emacsvox-omnivox-components--details-previous-action)
                   ("?" . emacsvox-omnivox-components-help)
                   ("q" . emacsvox-omnivox-components--details-back)
                   ("h" . emacsvox-aural)))
  (define-key emacsvox-omnivox-engine-details-mode-map (kbd (car binding)) (cdr binding)))

(defun emacsvox-omnivox-components-help ()
  "Display and speak engine details and navigation help."
  (interactive)
  (emacsvox-aural-ui-with-help-window
    (princ
     (concat
      "Omnivox Engine Details\n\n"
      "The summary combines matching main and notification status.\n"
      "Browse voices opens samples and adjustments. Installed voices and\n"
      "Get more voices manage voices for engines that support them.\n\n"
      "Startup settings contains manual file overrides and speech restart.\n"
      "Required runtime describes native discovery by the current workers.\n"
      "Missing files, load failures, disabled engines and unchecked workers\n"
      "remain distinct. Diagnostics contains worker paths, check times,\n"
      "runtime discovery, and health. Sections remember their expanded state.\n\n"
      "Manage installed release explicitly opens the release installer.\n"
      "That view identifies its installation and location before offering\n"
      "Install engine, Uninstall engine, and Check release engine. It keeps\n"
      "current speech running. In that view, g refreshes release files and\n"
      "q returns to the current engine.\n\n"
      "Available describes discovery from the current running worker.\n"
      "Opening details refreshes older evidence in the background.\n"
      "Previously available refers to a stopped or replaced worker.\n"
      "Streams differ means availability, policy, health, or voices differ.\n\n"
      "n or down next       p or up previous\n"
      "left/right column    . speak titled cell\n"
      "RET activate action or expand/collapse section\n"
      "TAB next action or section; Shift-TAB previous\n"
      "g refresh            h aural home\n"
      "? help               q quit\n")))
  (when (fboundp 'emacsvox-speak-help)
    (emacsvox-speak-help)))

(define-derived-mode emacsvox-omnivox-components-mode
    emacsvox-aural-tabulated-mode
  "Omnivox-Engines"
  "Spoken engine status, details and verified engine installation."
  (emacsvox-aural-ui-configure-tabulated
   "Omnivox speech engine list"
   #'emacsvox-omnivox-components-speak-current
   #'emacsvox-omnivox-components-refresh)
  (setq tabulated-list-format
        [("Engine" 16 t)
         ("Status" 34 t)
         ("Voices" 8 t)]
        header-line-format " Current speech discovery; RET for runtime status and engine details"
        tabulated-list-padding 2)
  (add-hook 'tabulated-list-revert-hook
            #'emacsvox-omnivox-components-refresh nil t)
  (tabulated-list-init-header))

(dolist
    (binding
     '(("RET" . emacsvox-omnivox-components-activate)
       ("i" . emacsvox-omnivox-components-install)
       ("u" . emacsvox-omnivox-components-uninstall)
       ("t" . emacsvox-omnivox-components-test)
       ("h" . emacsvox-aural)
       ("?" . emacsvox-omnivox-components-help)))
  (define-key emacsvox-omnivox-components-mode-map
              (kbd (car binding)) (cdr binding)))

;;;###autoload
(defun emacsvox-omnivox-manage-components ()
  "Open Browse Voices for engine status, details and optional engines."
  (interactive)
  (require 'emacsvox-aural-voice-workbench)
  (emacsvox-aural-voice-workbench 'engines))

(provide 'emacsvox-omnivox-components)

;;; emacsvox-omnivox-components.el ends here
