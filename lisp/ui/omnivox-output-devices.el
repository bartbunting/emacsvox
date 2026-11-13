;;; omnivox-output-devices.el --- Choose physical speech outputs -*- lexical-binding: t; -*-

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
;; Row navigation only highlights a candidate.  Apply, Save and recovery are
;; explicit actions.  Device IDs remain distinct even when names are equal.
;;; Code:
(require 'omnivox-audio-devices)
(require 'emacsvox-aural-ui)
(require 'tts-speak)
(declare-function emacsvox-speak-help "emacsvox-speak" ())
(defvar-local omnivox-output-devices--role 'speaker)
(defvar-local omnivox-output-devices--catalogue nil)
(defvar-local omnivox-output-devices--message "Refreshing")
(defvar-local omnivox-output-devices--refresh nil)

(defun omnivox-output-devices--process ()
  "Return this editor's current lane worker."
  (if (eq omnivox-output-devices--role 'speaker) tts-speaker-process tts-notify-process))

(defun omnivox-output-devices--saved ()
  "Return this host and lane's saved entry, including a missing device."
  (cl-find-if (lambda (entry) (and (equal (car entry) (plist-get omnivox-output-devices--catalogue :host_scope))
                                  (eq (cadr entry) omnivox-output-devices--role)))
              omnivox-audio-device-preferences))

(defun omnivox-output-devices--label (id)
  "Describe ID without treating its friendly name as identity."
  (if (equal id "default") "Follow system default"
    (or (plist-get (cl-find id (plist-get omnivox-output-devices--catalogue :devices)
                           :key (lambda (device) (plist-get device :id)) :test #'equal) :name)
        (when (equal id (nth 2 (omnivox-output-devices--saved))) (nth 3 (omnivox-output-devices--saved)))
        "Unavailable saved or applied device")))

(defun omnivox-output-devices--render ()
  "Render available, saved and applied outputs without applying the candidate."
  (let* ((selected (tabulated-list-get-id))
         (record (omnivox-audio-devices--record omnivox-output-devices--role))
         (state (plist-get (plist-get record :status) :state))
         (live (and (eq (plist-get record :process) (omnivox-output-devices--process))
                    (omnivox-audio-devices--supported-p (omnivox-output-devices--process))))
         (applied (when state (omnivox-audio-devices--value (plist-get state :selection))))
         (saved (or (nth 2 (omnivox-output-devices--saved)) "default"))
         (devices (mapcar (lambda (device) (plist-get device :id))
                          (plist-get omnivox-output-devices--catalogue :devices)))
         (ids (delete-dups (delq nil (append (list "default") devices (list saved applied))))))
    (setq header-line-format
          (format " %s | %s | a Apply highlighted, s Save applied, g Refresh, c Cancel Apply, ? Help"
                  (if (eq omnivox-output-devices--role 'speaker) "Main output" "Notification output")
                  omnivox-output-devices--message))
    (emacsvox-aural-ui-refresh-tabulated
     (lambda ()
       (setq tabulated-list-entries
             (mapcar
              (lambda (id)
                (list id (vector (omnivox-output-devices--label id)
                                 (string-join
                                  (delq nil
                                        (list (when (equal id applied) (if live "Applied" "Last confirmed"))
                                              (when (equal id saved) "Saved")
                                              (when (and live (equal id (plist-get state :connected))) "Connected")
                                              (when (and (not (equal id "default")) (not (member id devices))) "Unavailable")))
                                  ", ") id))) ids)))
     (or selected applied saved "default"))))

(defun omnivox-output-devices-speak-row ()
  "Speak the highlighted output, its saved/applied state and unique identity."
  (interactive)
  (when-let* ((row (tabulated-list-get-entry)))
    (tts-speak (mapconcat #'identity row ". "))))

(defun omnivox-output-devices-refresh ()
  "Refresh device availability and reconcile any unresolved Apply; change nothing."
  (interactive)
  (let ((buffer (current-buffer)) (identity (list 'refresh))
        (role omnivox-output-devices--role) (process (omnivox-output-devices--process)))
    (setq omnivox-output-devices--refresh identity)
    (omnivox-audio-devices--discover
     (if (or (tts--speech-process-usable-p process) (not (omnivox-audio-devices--supported-p tts-speaker-process)))
         process tts-speaker-process)
     (lambda (catalogue)
       (when (buffer-live-p buffer)
         (with-current-buffer buffer
           (when (eq identity omnivox-output-devices--refresh)
             (if (and (eq (plist-get catalogue :supported) t) (stringp (plist-get catalogue :host_scope)))
                 (setq omnivox-output-devices--catalogue catalogue
                       omnivox-output-devices--message
                       (cond ((not (tts--speech-process-usable-p process)) "Speech worker unavailable; Apply can recover it")
                             ((eq (plist-get catalogue :truncated) t) "Catalogue truncated; refine output devices on the host")
                             (t "Availability refreshed")))
               (setq omnivox-output-devices--message (or (plist-get catalogue :message) "Selection is unsupported on this backend")))
             (omnivox-output-devices--render))))))
    (when (omnivox-audio-devices--supported-p process)
      (omnivox-audio-devices--refresh-status
       process role
       (lambda (status)
         (when (buffer-live-p buffer)
           (with-current-buffer buffer
             (when (eq identity omnivox-output-devices--refresh)
               (setq omnivox-output-devices--message
                     (cond ((plist-get (omnivox-audio-devices--record role) :pending) "Apply unresolved; refresh or cancel")
                           ((not (omnivox-audio-devices--status-p status)) "Live output status unavailable")
                           ((not (plist-get (plist-get status :state) :connected)) "Selected output unavailable; no fallback")
                           (t "Live output connected")))
               (omnivox-output-devices--render))))))))
  (omnivox-output-devices--render))

(defun omnivox-output-devices-apply ()
  "Apply the highlighted output to this live lane without restarting engines.
For a dead worker, explicitly establish its recovery destination first; native
cleanup must still be confirmed before a replacement can start."
  (interactive)
  (when (and (eq omnivox-output-devices--role 'notification)
             (not (tts--notification-process-configured-p)))
    (user-error
     (if (omnivox-audio-channels--live-p)
         "Choose Automatic, Left, Right or Both notification routing first"
       "Choose Automatic, Left, Right or Both notification routing and restart speech first")))
  (unless (eq (plist-get omnivox-output-devices--catalogue :supported) t)
    (user-error "Refresh a supported local Windows output catalogue first"))
  (let* ((id (or (tabulated-list-get-id) (user-error "Highlight an output first")))
         (selection (omnivox-audio-devices--selection id))
         (role omnivox-output-devices--role) (process (omnivox-output-devices--process))
         (buffer (current-buffer)))
    (if (tts--speech-process-usable-p process)
        (progn
          (setq omnivox-output-devices--message "Preparing selected output")
          (omnivox-audio-devices--apply
           process role selection
           (lambda (outcome _status)
             (when (buffer-live-p buffer)
               (with-current-buffer buffer
                 (setq omnivox-output-devices--message (format "Apply %s; Save is separate" outcome))
                 (omnivox-output-devices--render)
                 (message "%s output: %s" role omnivox-output-devices--message))))
           (plist-get omnivox-output-devices--catalogue :host_scope))
          (omnivox-output-devices--render))
      (unless (yes-or-no-p (format "Recover %s speech using %s? " role (omnivox-output-devices--label id)))
        (user-error "Recovery cancelled"))
      (let ((record (copy-sequence (omnivox-audio-devices--record role))))
        (setq record (plist-put record :pending nil) record (plist-put record :override selection)
              record (plist-put record :override-host (plist-get omnivox-output-devices--catalogue :host_scope))
              ;; Late replies from the retired owner cannot replace this explicit
              ;; recovery choice while native cleanup is being confirmed.
              record (plist-put record :process nil) record (plist-put record :query-operation nil))
        (omnivox-audio-devices--put role record))
      (tts--confirm-owned-retirement process)
      (if (eq role 'speaker) (tts--recover-speaker) (tts-notify-initialize))
      (omnivox-output-devices-refresh))))

(defun omnivox-output-devices-save ()
  "Save this lane's confirmed applied choice for this host; do not change audio."
  (interactive)
  (let* ((record (omnivox-audio-devices--record omnivox-output-devices--role))
         (status (plist-get record :status)) (host (plist-get status :host_scope)))
    (unless (and (omnivox-audio-devices--status-p status) (not (plist-get record :pending))
                 (not (plist-get record :override))
                 (equal host (plist-get omnivox-output-devices--catalogue :host_scope)))
      (user-error "Refresh and confirm the applied output before saving"))
    (let* ((id (omnivox-audio-devices--value (plist-get (plist-get status :state) :selection)))
           (preferences (cons (list host omnivox-output-devices--role id (omnivox-output-devices--label id))
                              (cl-remove-if (lambda (entry) (and (equal host (car entry))
                                                                 (eq omnivox-output-devices--role (cadr entry))))
                                            omnivox-audio-device-preferences))))
      (let ((omnivox-audio-device-preferences preferences))
        (omnivox-audio-devices--projection omnivox-output-devices--role))
      (customize-save-variable 'omnivox-audio-device-preferences preferences)
      (setq omnivox-output-devices--message "Saved applied choice for future Emacs sessions")
      (omnivox-output-devices--render)
      (message "%s" omnivox-output-devices--message))))

(defun omnivox-output-devices-cancel ()
  "Cancel this lane's pending preparation; already applied changes stay applied."
  (interactive)
  (let ((buffer (current-buffer)))
    (omnivox-audio-devices--refresh-status
     (omnivox-output-devices--process) omnivox-output-devices--role
     (lambda (_status) (when (buffer-live-p buffer)
                         (with-current-buffer buffer (omnivox-output-devices-refresh)))) t)))

(defun omnivox-output-devices-help ()
  "Explain physical output browsing, Apply, Save, availability and recovery."
  (interactive)
  (emacsvox-aural-ui-with-help-window
    (princ "Physical speech output devices\n\n")
    (princ "Arrows browse only. Space speaks the row, including its unique device ID.\n")
    (princ "a applies the highlighted device to this lane. Speech, tones and sounds move together.\n")
    (princ "Healthy engines stay loaded. Interrupted audio is cancelled and never replayed.\n")
    (princ "s saves the confirmed applied choice for this host and lane in Customize.\n")
    (princ "g refreshes devices and live status. c cancels a pending preparation.\n")
    (princ "An unavailable explicit device never falls back to speakers. Apply Follow system default to choose that behavior.\n")
    (princ "An unanswered Apply remains unknown; refresh it before recovery. For a dead worker, Apply asks to recover on the highlighted device.\n")
    (princ "Main and notification choices are independent. Channel routing and stereo placement remain separate.\n")
    (princ "A dedicated notification worker is required for a separate notification device.\n")
    (princ "q returns without applying or saving the highlighted row. Applied session choices remain active.\n\n")
    (princ (format "Speech host: %s\nStatus: %s\n"
                   (or (plist-get omnivox-output-devices--catalogue :host_scope) "unknown")
                   omnivox-output-devices--message)))
  (when (fboundp 'emacsvox-speak-help) (emacsvox-speak-help)))

(define-derived-mode omnivox-output-devices-mode emacsvox-aural-tabulated-mode "Output-Devices"
  "Browse physical outputs; explicitly Apply, Save or recover the selected lane."
  (emacsvox-aural-ui-configure-tabulated "Physical output devices"
                                        #'omnivox-output-devices-speak-row #'omnivox-output-devices-refresh)
  (setq tabulated-list-format [("Output" 42 t) ("State" 28 t) ("Device ID" 20 t)]
        tabulated-list-padding 2)
  (tabulated-list-init-header))

(dolist (binding '(("a" . omnivox-output-devices-apply) ("s" . omnivox-output-devices-save)
                   ("c" . omnivox-output-devices-cancel) ("g" . omnivox-output-devices-refresh)
                   ("RET" . omnivox-output-devices-speak-row) ("?" . omnivox-output-devices-help)))
  (define-key omnivox-output-devices-mode-map (kbd (car binding)) (cdr binding)))

;;;###autoload
(defun omnivox-output-devices (&optional role)
  "Browse physical outputs for ROLE, either speaker or notification.
Main is the default.  With a prefix argument, browse notification outputs."
  (interactive (list (if current-prefix-arg 'notification 'speaker)))
  (unless (and (tts--omnivox-program-p) (not (omnivox-remote-enabled-p)))
    (user-error "Physical device selection requires local Omnivox"))
  (setq role (or role 'speaker))
  (unless (memq role '(speaker notification)) (user-error "Choose main or notification output"))
  (let ((buffer (get-buffer-create (format "*Omnivox %s Output Devices*" role))))
    (with-current-buffer buffer
      (unless (derived-mode-p 'omnivox-output-devices-mode) (omnivox-output-devices-mode))
      (setq omnivox-output-devices--role role)
      (omnivox-output-devices-refresh))
    (emacsvox-aural-ui-pop-to-buffer buffer)
    buffer))

(provide 'omnivox-output-devices)
;;; omnivox-output-devices.el ends here
