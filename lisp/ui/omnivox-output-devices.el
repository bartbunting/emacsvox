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
;; A menu visit owns its candidate and asynchronous refresh identity.  Browsing
;; never applies output; Apply and Save retain the independent lane contract.
;;; Code:
(require 'omnivox-audio-devices)
(require 'emacsvox-aural-menu)
(require 'tts-speak)

(defun omnivox-output-devices--state ()
  "Return this menu visit's state, rejecting a changed speech target."
  (let* ((context (emacsvox-aural-menu--context))
         (state (plist-get context :output-devices)))
    (emacsvox-aural-menu--source context)
    (unless (and state (equal tts-program (plist-get state :program)))
      (user-error "Speech target changed; reopen output devices"))
    state))

(defun omnivox-output-devices--process (state)
  "Return STATE's current lane worker."
  (if (eq (plist-get state :role) 'speaker) tts-speaker-process tts-notify-process))

(defun omnivox-output-devices--saved (state)
  "Return this host and lane's saved entry, including a missing device."
  (cl-find-if (lambda (entry)
                (and (equal (car entry) (plist-get (plist-get state :catalogue) :host_scope))
                     (eq (cadr entry) (plist-get state :role))))
              omnivox-audio-device-preferences))

(defun omnivox-output-devices--label (id state)
  "Describe ID in STATE without treating its friendly name as identity."
  (if (equal id "default") "Follow system default"
    (or (plist-get (cl-find id (plist-get (plist-get state :catalogue) :devices)
                           :key (lambda (device) (plist-get device :id)) :test #'equal) :name)
        (when (equal id (nth 2 (omnivox-output-devices--saved state)))
          (nth 3 (omnivox-output-devices--saved state)))
        "Unavailable saved or applied device")))

(defun omnivox-output-devices--applied (state)
  "Return STATE's last confirmed selection."
  (when-let* ((status (plist-get (omnivox-audio-devices--record (plist-get state :role)) :status)))
    (omnivox-audio-devices--value (plist-get (plist-get status :state) :selection))))

(defun omnivox-output-devices--ids (state)
  "Return distinct available, saved and applied identities for STATE."
  (delete-dups
   (delq nil (append '("default")
                     (mapcar (lambda (device) (plist-get device :id))
                             (plist-get (plist-get state :catalogue) :devices))
                     (list (nth 2 (omnivox-output-devices--saved state))
                           (omnivox-output-devices--applied state))))))

(defun omnivox-output-devices--description (id state)
  "Describe ID's candidate, applied, saved and connection state."
  (let* ((record (omnivox-audio-devices--record (plist-get state :role)))
         (route (plist-get (plist-get record :status) :state))
         (live (and (eq (plist-get record :process) (omnivox-output-devices--process state))
                    (omnivox-audio-devices--supported-p (omnivox-output-devices--process state))))
         (devices (plist-get (plist-get state :catalogue) :devices))
         (label (omnivox-output-devices--label id state))
         (duplicates (cl-remove-if-not (lambda (d) (equal label (plist-get d :name))) devices)))
    (string-join
     (delq nil
           (list (if (> (length duplicates) 1)
                     (format "%s (device %d)" label
                             (1+ (or (cl-position id duplicates :key (lambda (d) (plist-get d :id)) :test #'equal) 0)))
                   label)
                 (when (equal id (plist-get state :candidate)) "Selected")
                 (when (equal id (omnivox-output-devices--applied state)) (if live "Applied" "Last confirmed"))
                 (when (equal id (or (nth 2 (omnivox-output-devices--saved state)) "default")) "Saved")
                 (when (and live (equal id (plist-get route :connected))) "Connected")
                 (when (and (not (equal id "default"))
                            (not (cl-find id devices :key (lambda (d) (plist-get d :id)) :test #'equal)))
                   "Unavailable"))) ", ")))

(defun omnivox-output-devices--visible-p (state)
  "Whether STATE still owns the displayed menu and its speech target."
  (and transient--prefix (equal tts-program (plist-get state :program))
       (memq (oref transient--prefix command) '(omnivox-output-devices--menu omnivox-output-devices--choices))
       (eq state (plist-get (oref transient--prefix scope) :output-devices))
       (buffer-live-p (plist-get (oref transient--prefix scope) :source))))

(defun omnivox-output-devices--render (state)
  "Refresh STATE's visible labels without reopening a closed or different menu."
  (when (omnivox-output-devices--visible-p state) (transient--show)))

(defun omnivox-output-devices--say (text)
  "Announce replaceable menu feedback TEXT on main speech."
  (emacsvox-transient--submit-text text
   (emacsvox-transient--menu-facts 'output-devices 'command-menu-value-changed)
   'state-change 'select-object))

(defun omnivox-output-devices--refresh (state)
  "Refresh STATE's catalogue and reconcile live output without applying a choice."
  (let ((identity (list 'refresh)) (role (plist-get state :role))
        (program (plist-get state :program)) (process (omnivox-output-devices--process state)))
    (setf (plist-get state :refresh) identity (plist-get state :message) "Refreshing outputs")
    (omnivox-audio-devices--discover
     (if (or (tts--speech-process-usable-p process)
             (not (omnivox-audio-devices--supported-p tts-speaker-process))) process tts-speaker-process)
     (lambda (catalogue)
       (when (and (eq identity (plist-get state :refresh)) (equal program tts-program))
         (if (and (eq (plist-get catalogue :supported) t) (stringp (plist-get catalogue :host_scope)))
             (progn
               (setf (plist-get state :catalogue) catalogue)
               (unless (plist-get state :candidate)
                 (setf (plist-get state :candidate) (or (omnivox-output-devices--applied state)
                                                        (nth 2 (omnivox-output-devices--saved state)) "default")))
               (setf (plist-get state :message)
                     (cond ((not (tts--speech-process-usable-p process)) "Worker unavailable; Apply can recover it")
                           ((eq (plist-get catalogue :truncated) t) "Catalogue truncated; refine devices on the host")
                           (t "Availability refreshed"))))
           (setf (plist-get state :catalogue) nil
                 (plist-get state :message) (or (plist-get catalogue :message) "Device selection unsupported")))
         (omnivox-output-devices--render state))))
    (when (omnivox-audio-devices--supported-p process)
      (omnivox-audio-devices--refresh-status
       process role
       (lambda (status)
         (when (and (eq identity (plist-get state :refresh)) (equal program tts-program)
                    (eq process (omnivox-output-devices--process state)))
           (setf (plist-get state :message)
                 (cond ((plist-get (omnivox-audio-devices--record role) :pending) "Apply unresolved; refresh or cancel")
                       ((not (omnivox-audio-devices--status-p status)) "Live output status unavailable")
                       ((not (plist-get (plist-get status :state) :connected)) "Selected output unavailable; no fallback")
                       (t "Live output connected")))
           (omnivox-output-devices--render state))))))
  (omnivox-output-devices--render state))

(defun omnivox-output-devices-refresh ()
  "Refresh availability and live status without applying the selected candidate."
  (interactive) (omnivox-output-devices--refresh (omnivox-output-devices--state)))

(defun omnivox-output-devices--select (id)
  "Select ID as a candidate and return; Apply and Save remain separate."
  (let ((state (omnivox-output-devices--state)))
    (setf (plist-get state :candidate) id)
    (transient--stack-pop)
    (omnivox-output-devices--render state)
    (omnivox-output-devices--say (concat (omnivox-output-devices--label id state) "; selected. Apply to use it."))))

(defun omnivox-output-devices--children (_children)
  "Build explained choices from this visit's stable list of identities."
  (let* ((state (omnivox-output-devices--state)) (ids (plist-get state :choice-ids))
         (width (length (number-to-string (length ids)))) (index 0))
    (transient-parse-suffixes
     'omnivox-output-devices--choices
     (mapcar
      (lambda (id)
        (let ((help (format "Select without changing audio; Apply in the parent menu makes it active.\n%s. Speech, tones and sounds move together. Save is separate.\nDevice identity: %s"
                            (omnivox-output-devices--label id state) id)))
          (list (format (concat "%0" (number-to-string width) "d") (cl-incf index))
                (omnivox-output-devices--description id state)
                (lambda () (:documentation help) (interactive) (omnivox-output-devices--select id))
                :transient 'transient--do-replace))) ids))))

(defun omnivox-output-devices--choose ()
  "Browse physical devices with arrows; Enter selects a candidate without applying."
  (interactive)
  (let* ((state (omnivox-output-devices--state)) (context (emacsvox-aural-menu--context)))
    (unless (eq (plist-get (plist-get state :catalogue) :supported) t)
      (user-error "Refresh a supported local Windows output catalogue first"))
    ;; Keep identities in order while browsing, even if an earlier refresh replies.
    (setf (plist-get state :choice-ids) (omnivox-output-devices--ids state))
    (transient-setup 'omnivox-output-devices--choices nil nil :scope context)
    (transient--show)
    (when (window-live-p transient--window)
      (let* ((ids (plist-get state :choice-ids))
             (index (or (cl-position (plist-get state :candidate) ids :test #'equal) 0))
             (key (format (concat "%0" (number-to-string (length (number-to-string (length ids)))) "d")
                          (1+ index)))
             (suffix (cl-find key transient--suffixes :key (lambda (item) (oref item key)) :test #'equal)))
        (when suffix (with-selected-window transient--window (transient--goto-button suffix)))))))

(defun omnivox-output-devices-apply ()
  "Apply the selected candidate to this lane without restarting healthy engines.
An unavailable worker requires explicit recovery after confirmed native cleanup."
  (interactive)
  (let* ((state (omnivox-output-devices--state)) (role (plist-get state :role))
         (catalogue (plist-get state :catalogue)) (process (omnivox-output-devices--process state))
         (id (or (plist-get state :candidate) (user-error "Choose an output first")))
         (selection (omnivox-audio-devices--selection id)))
    (when (and (eq role 'notification) (not (tts--notification-process-configured-p)))
      (user-error "Choose Automatic, Left, Right or Both notification routing first"))
    (unless (eq (plist-get catalogue :supported) t)
      (user-error "Refresh a supported local Windows output catalogue first"))
    (if (tts--speech-process-usable-p process)
        (progn
          (setf (plist-get state :message) "Preparing selected output")
          (omnivox-audio-devices--apply
           process role selection
           (lambda (outcome _status)
             (setf (plist-get state :message) (format "Apply %s; Save is separate" outcome))
             (omnivox-output-devices--render state)
             (when (omnivox-output-devices--visible-p state)
               (omnivox-output-devices--say (plist-get state :message))))
           (plist-get catalogue :host_scope)))
      (unless (yes-or-no-p (format "Recover %s speech using %s? " role (omnivox-output-devices--label id state)))
        (user-error "Recovery cancelled"))
      (let ((record (copy-sequence (omnivox-audio-devices--record role))))
        (setq record (plist-put record :pending nil) record (plist-put record :override selection)
              record (plist-put record :override-host (plist-get catalogue :host_scope))
              record (plist-put record :process nil) record (plist-put record :query-operation nil))
        (omnivox-audio-devices--put role record))
      (tts--confirm-owned-retirement process)
      (if (eq role 'speaker) (tts--recover-speaker) (tts-notify-initialize))
      (omnivox-output-devices--refresh state))
    (omnivox-output-devices--render state)))

(defun omnivox-output-devices-save ()
  "Save this host and lane's confirmed applied output, without applying a candidate."
  (interactive)
  (let* ((state (omnivox-output-devices--state)) (role (plist-get state :role))
         (record (omnivox-audio-devices--record role))
         (status (plist-get record :status)) (host (plist-get status :host_scope)))
    (unless (and (omnivox-audio-devices--status-p status) (not (plist-get record :pending))
                 (not (plist-get record :query-operation)) (not (plist-get record :override))
                 (eq (plist-get record :process) (omnivox-output-devices--process state))
                 (omnivox-audio-devices--supported-p (omnivox-output-devices--process state))
                 (equal host (plist-get (plist-get state :catalogue) :host_scope)))
      (user-error "Refresh and confirm the applied output before saving"))
    (let* ((id (omnivox-output-devices--applied state))
           (preferences (cons (list host role id (omnivox-output-devices--label id state))
                              (cl-remove-if (lambda (entry) (and (equal host (car entry)) (eq role (cadr entry))))
                                            omnivox-audio-device-preferences))))
      (let ((omnivox-audio-device-preferences preferences)) (omnivox-audio-devices--projection role))
      (customize-save-variable 'omnivox-audio-device-preferences preferences)
      (setf (plist-get state :message) "Saved applied choice for future Emacs sessions")
      (omnivox-output-devices--render state)
      (omnivox-output-devices--say (plist-get state :message)))))

(defun omnivox-output-devices-cancel ()
  "Cancel pending output preparation; already applied changes stay applied."
  (interactive)
  (let ((state (omnivox-output-devices--state)))
    (omnivox-audio-devices--refresh-status
     (omnivox-output-devices--process state) (plist-get state :role)
     (lambda (_status)
       (when (omnivox-output-devices--visible-p state) (omnivox-output-devices--refresh state))) t)))

(transient-define-prefix omnivox-output-devices--choices ()
  "Browse outputs without changing audio. Enter selects; Apply is in the parent menu."
  ["Choose an output" :class transient-column :setup-children omnivox-output-devices--children]
  ["Return" ("q" "Back without selecting" transient-quit-one)
   ("C-q" "Close menus" transient-quit-all)])

(transient-define-prefix omnivox-output-devices--menu ()
  "Choose this lane's physical device, then Apply; Save keeps the applied choice.
Arrows only browse. Enter on Choose opens a list; Enter there stages a candidate.
Apply moves speech, tones and sounds together without restarting healthy engines.
Main and notification devices are independent. An unavailable explicit device
never falls back. Follow system default explicitly chooses default following.
Refresh reconciles unanswered Apply operations. Cancel stops pending preparation;
already applied changes remain active. A dead worker requires confirmed cleanup
and explicit recovery. Save records only a confirmed live choice in Customize.
Device-choice Help includes its unique identity, including duplicate names.
Leaving this menu never applies or saves a candidate."
  :refresh-suffixes t
  [:description (lambda () (if (eq (plist-get (omnivox-output-devices--state) :role) 'speaker)
                               "Main output" "Notification output"))
   ("d" (lambda () (let ((state (omnivox-output-devices--state)))
                     (format "Choose: %s" (if-let* ((id (plist-get state :candidate)))
                                               (omnivox-output-devices--label id state) "waiting for devices"))))
    omnivox-output-devices--choose :transient transient--do-stack)
   ("a" "Apply selected output" omnivox-output-devices-apply :transient t)
   ("s" "Save applied output" omnivox-output-devices-save :transient t)]
  [:description (lambda () (plist-get (omnivox-output-devices--state) :message))
   ("g" "Refresh devices and live status" omnivox-output-devices-refresh :transient t)
   ("c" "Cancel pending Apply" omnivox-output-devices-cancel :transient t)]
  ["Return" ("q" "Back; keep applied changes" transient-quit-one)
   ("C-q" "Close menus" transient-quit-all)])

;;;###autoload
(defun omnivox-output-devices (&optional role)
  "Choose physical outputs for ROLE, either speaker or notification.
Main is the default. With a prefix argument, choose notification outputs.
Browse and select in Transient; Apply and Save are separate explicit actions."
  (interactive (list (if current-prefix-arg 'notification 'speaker)))
  (unless (and (tts--omnivox-program-p) (not (omnivox-remote-enabled-p)))
    (user-error "Physical device selection requires local Omnivox"))
  (setq role (or role 'speaker))
  (unless (memq role '(speaker notification)) (user-error "Choose main or notification output"))
  (let* ((prefix (or transient--prefix transient-current-prefix))
         (context (if (and prefix (eq (oref prefix command) 'emacsvox-output-settings))
                      (copy-sequence (oref prefix scope)) (emacsvox-aural-menu--capture nil)))
         ;; Allocate every mutable slot before sharing this visit with callbacks
         ;; and child menus; adding a plist key can replace its head.
         (state (list :role role :program tts-program :message "Refreshing outputs"
                      :catalogue nil :candidate nil :refresh nil :choice-ids nil)))
    (emacsvox-aural-menu--source context)
    (transient-setup 'omnivox-output-devices--menu nil nil :scope (plist-put context :output-devices state))
    (omnivox-output-devices--refresh state)))

(provide 'omnivox-output-devices)
;;; omnivox-output-devices.el ends here
