;;; omnivox-audio-channels.el --- Live notification channel routing -*- lexical-binding: t; -*-

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
;; Change all outputs of one worker together.  Main speech keeps running when
;; notification ownership changes.  Customize owns persistence, separately.
;;; Code:
(require 'cl-lib)
(defvar tts-program)
(defvar tts-speaker-process)
(defvar tts-notify-process)
(defvar tts-notification-device)
(defvar omnivox-library--timeout)
(declare-function tts--omnivox-program-p "tts-speak" (&optional program))
(declare-function tts--speech-process-usable-p "tts-speak" (process))
(declare-function tts--confirm-owned-retirement "tts-speak" (process))
(declare-function tts--retire-process "tts-lifecycle" (process))
(declare-function tts-notify-initialize "tts-speak" ())
(declare-function omnivox-remote-enabled-p "omnivox-remote" ())
(declare-function omnivox--process-supports-p "omnivox-voices" (process feature))
(declare-function omnivox--encode-control-request "omnivox-control-codec" (request))
(declare-function omnivox-library--control "omnivox-library-runtime" (process command))
(declare-function omnivox-library--wait-for-recovered-speech "omnivox-library-runtime" (process))
(declare-function omnivox-audio-devices--assert-resolved "omnivox-audio-devices" (role))

(defvar omnivox-audio-channels--busy nil)
(defvar omnivox-audio-channels--pending nil
  "Unconfirmed channel changes keyed by speech program.")

(defun omnivox-audio-channels--supported-p (process)
  "Whether PROCESS can change all of its output channels live."
  (and (processp process) (process-live-p process)
       (not (process-get process 'omnivox-library-retired))
       (not (process-get process 'omnivox-emergency-output))
       (not (process-get process 'omnivox-remote-managed))
       (fboundp 'omnivox--process-supports-p)
       (omnivox--process-supports-p process "audio_channel_selection_v1")))

(defun omnivox-audio-channels--live-p ()
  "Whether this session offers live local notification routing."
  (and (tts--omnivox-program-p) (not (omnivox-remote-enabled-p))
       (omnivox-audio-channels--supported-p tts-speaker-process)))

(defun omnivox-audio-channels--assert-resolved ()
  "Reject Save or assumed notification recovery after an uncertain change."
  (when (and (tts--omnivox-program-p) (not (omnivox-remote-enabled-p))
             (assoc tts-program omnivox-audio-channels--pending))
    (user-error "Notification channel change is unconfirmed; choose its route again")))

(defun omnivox-audio-channels--matches-p (response channel)
  "Whether RESPONSE confirms CHANNEL for speech, tones and sounds."
  (and (equal (plist-get response :type) "audio_channels_v1")
       (cl-every (lambda (key) (equal channel (plist-get response key)))
                 '(:speech :tone :sound))))

(defun omnivox-audio-channels--apply (process channel)
  "Set PROCESS to CHANNEL and confirm all three outputs before reporting success.
A lost reply is queried once.  Uncertainty blocks assumed recovery and Save;
choosing a route again is safe because the setter is idempotent."
  (unless (omnivox-audio-channels--supported-p process)
    (user-error "This notification worker does not support live channel routing"))
  (require 'omnivox-library-runtime)
  (let ((omnivox-library--timeout 1) response)
    (setf (alist-get tts-program omnivox-audio-channels--pending nil nil #'equal)
          (list :process process :channel channel))
    (setq response
          (condition-case nil
              (omnivox-library--control process (list :type "set_audio_channels_v1" :channel channel))
            (error nil)))
    (unless (omnivox-audio-channels--matches-p response channel)
      (setq response
            (condition-case nil
                (omnivox-library--control process '(:type "audio_channels_v1"))
              (error nil))))
    (unless (and (eq process tts-notify-process)
                 (omnivox-audio-channels--supported-p process)
                 (omnivox-audio-channels--matches-p response channel))
      (user-error "Notification channel change is unconfirmed; choose its route again"))
    (process-put process 'omnivox-audio-channel channel)
    (setq omnivox-audio-channels--pending
          (assoc-delete-all tts-program omnivox-audio-channels--pending))))

(defun omnivox-audio-channels--reset-command (process)
  "Reapply PROCESS's client channel override after an ordinary server reset."
  (when (omnivox-audio-channels--supported-p process)
    (let* ((pending (cdr (assoc tts-program omnivox-audio-channels--pending)))
           (channel (if (eq process (plist-get pending :process))
                        (plist-get pending :channel)
                      (process-get process 'omnivox-audio-channel))))
      (when channel
        (concat "omnivox_control "
                (omnivox--encode-control-request
                 (list :protocol_version 1 :request_id 0 :type "set_audio_channels_v1" :channel channel))
                "\n")))))

(defun omnivox-audio-channels--set-route (value)
  "Apply notification route VALUE without restarting main speech.
Existing workers change Left/Right/Both live.  Main output retires the notifier;
returning to a separate route starts only that worker using retained engines.
This does not save the option; the caller commits VALUE after success."
  (unless (omnivox-audio-channels--live-p)
    (user-error "Live notification routing requires a supporting local Omnivox worker"))
  (unless (member value '(nil "left" "right" "both" "default"))
    (user-error "Choose Automatic, Left, Right, Both or Main output"))
  (when omnivox-audio-channels--busy (user-error "A notification route change is already running"))
  (omnivox-audio-devices--assert-resolved 'notification)
  (let ((omnivox-audio-channels--busy t) (old tts-notify-process))
    (cond
     ((equal value "default")
      (tts--confirm-owned-retirement old)
      (when (processp old) (tts--retire-process old))
      (setq tts-notify-process nil
            omnivox-audio-channels--pending (assoc-delete-all tts-program omnivox-audio-channels--pending)))
     ((tts--speech-process-usable-p old)
      (omnivox-audio-channels--apply old (or value "both")))
     (t
      ;; Explicitly choosing a destination permits recovery, but only after the
      ;; old native owner has supplied its ordinary cleanup proof.
      (tts--confirm-owned-retirement old)
      (setq omnivox-audio-channels--pending (assoc-delete-all tts-program omnivox-audio-channels--pending))
      (let ((tts-notification-device value) (tts-notify-process old) new ready)
        (unwind-protect
            (progn
              (setq new (tts-notify-initialize))
              (omnivox-library--wait-for-recovered-speech new)
              (omnivox-audio-channels--apply new (or value "both"))
              (setq ready t))
          (unless ready
            (when (and (processp new) (not (eq new old)))
              (tts--confirm-owned-retirement new)
              (tts--retire-process new))))
        ;; Publish outside the temporary notification binding.
        (setq old new))
      (setq tts-notify-process old)))))

(provide 'omnivox-audio-channels)
;;; omnivox-audio-channels.el ends here
