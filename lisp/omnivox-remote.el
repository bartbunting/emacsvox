;;; omnivox-remote.el --- Workstation speech transport -*- lexical-binding: t; -*-

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

;; Authenticated loopback connections through a user-managed SSH reverse
;; forward.  Existing TTS filters own speech and control; this module owns
;; authentication, heartbeats, lane recovery, and bundled resource identifiers.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defgroup omnivox-remote nil
  "Speech on the workstation from a remote Emacs."
  :group 'emacsvox)

(defcustom omnivox-remote-host nil
  "Loopback endpoint of the SSH reverse forward, or nil for local speech.
Use the literal address 127.0.0.1 or ::1.  Select omnivox as `tts-program'."
  :type '(choice (const :tag "Local speech" nil)
                 (const "127.0.0.1") (const "::1"))
  :group 'omnivox-remote)

(defcustom omnivox-remote-port 6417
  "Port forwarded from this Emacs host to workstation Omnivox."
  :type 'integer :group 'omnivox-remote)

(defcustom omnivox-remote-token-file nil
  "Private file containing the workstation's 64-character service token.
The token is sent only through loopback; use SSH to encrypt the remote link."
  :type '(choice (const nil) file) :group 'omnivox-remote)

(defcustom omnivox-remote-auto-reconnect t
  "Whether a lost speech lane reconnects with fresh state and no replay."
  :type 'boolean :group 'omnivox-remote)

(defvar omnivox-remote--session nil)
(defvar omnivox-remote--retry-timer nil)
(defvar omnivox-remote--retry-delay 1)
(defvar omnivox-remote--connecting nil)
(defvar omnivox-remote--suspended nil)
(defvar omnivox-remote--last-error nil)
(defvar tts-program)
(defvar tts-speaker-process)
(defvar tts-notify-process)
(defvar emacsvox-sounds-dir)
(defvar omnivox-default-voice-id)
(defvar omnivox-engine-inventory)
(defvar omnivox-control-capabilities)
(defvar omnivox-available-voices)
(declare-function tts--omnivox-program-p "tts-speak" (&optional program))
(declare-function tts--retire-process "tts-speak" (process))
(declare-function tts--speech-process-sentinel "tts-speak" (process event))
(declare-function tts-restart "tts-speak" ())
(declare-function tts-make-process "tts-speak" (name))
(declare-function tts--protocol-sync "tts-speak" ())
(declare-function tts--notification-process-configured-p "tts-speak" ())
(declare-function tts-notify-initialize "tts-speak" ())
(declare-function voice-setup "voice-setup" ())
(declare-function omnivox--negotiate-process "omnivox-voices" (process))

(defun omnivox-remote-enabled-p ()
  "Return non-nil when Omnivox uses the remote workstation transport."
  (and omnivox-remote-host (tts--omnivox-program-p)))

(defun omnivox-remote--token ()
  "Read and validate the private token without including it in errors."
  (unless (and (stringp omnivox-remote-token-file)
               (not (file-remote-p omnivox-remote-token-file))
               (file-regular-p omnivox-remote-token-file))
    (error "Set omnivox-remote-token-file to a private local file"))
  (unless (or (eq system-type 'windows-nt)
              (zerop (logand #o077 (file-modes omnivox-remote-token-file))))
    (error "Omnivox remote token file needs private permissions (chmod 600)"))
  (unless (<= (file-attribute-size
               (file-attributes omnivox-remote-token-file)) 66)
    (error "Invalid Omnivox remote token file"))
  (with-temp-buffer
    (insert-file-contents-literally omnivox-remote-token-file)
    (let ((token (buffer-string)))
      (unless (string-match-p "\\`[0-9a-f]\\{64\\}\\(?:\r?\n\\)?\\'" token)
        (error "Invalid Omnivox remote token file"))
      (substring token 0 64))))

(defun omnivox-remote--filter (process output)
  "Consume transport records in PROCESS OUTPUT forwarded by TTS filters."
  (let ((pending (concat (process-get process 'omnivox-remote-fragment) output))
        end)
    (while (setq end (string-search "\n" pending))
      (let ((line (string-trim-right (substring pending 0 end) "\r")))
        (cond
         ((equal line "OMNIVOX-REMOTE 1 ready")
          (process-put process 'omnivox-remote-ready t))
         ((string-prefix-p "OMNIVOX-REMOTE 1 error " line)
          (process-put process 'omnivox-remote-error (substring line 23)))
         ((equal line "OMNIVOX-REMOTE pong")
          (process-put process 'omnivox-remote-pong (float-time)))))
      (setq pending (substring pending (1+ end))))
    (if (> (string-bytes pending) (* 512 1024))
        (delete-process process)
      (process-put process 'omnivox-remote-fragment pending))))

(defun omnivox-remote--heartbeat (process)
  "Check PROCESS liveness and send a transport heartbeat."
  (when (process-live-p process)
    (if (> (- (float-time) (process-get process 'omnivox-remote-pong)) 20)
        (delete-process process)
      (condition-case nil
          (process-send-string process "OMNIVOX-REMOTE ping\n")
        (error (delete-process process))))))

(defun omnivox-remote--schedule-retry ()
  "Schedule one bounded-backoff retry after a remote lane failure."
  (when (and (omnivox-remote-enabled-p) omnivox-remote-auto-reconnect
             (not omnivox-remote--suspended)
             (not omnivox-remote--connecting)
             (not (timerp omnivox-remote--retry-timer)))
    (setq omnivox-remote--retry-timer
          (run-at-time omnivox-remote--retry-delay nil #'omnivox-remote--retry)
          omnivox-remote--retry-delay (min 30 (* 2 omnivox-remote--retry-delay)))))

(defun omnivox-remote--sentinel (process event)
  "Retire PROCESS with EVENT through TTS and arrange remote recovery."
  (unless (process-live-p process)
    (when-let* ((timer (process-get process 'omnivox-remote-heartbeat)))
      (cancel-timer timer)
      (process-put process 'omnivox-remote-heartbeat nil))
    (when (process-get process 'omnivox-remote-managed)
      (let ((retiring (process-get process 'tts--speech-process-retiring)))
        (tts--speech-process-sentinel process event)
        (unless retiring (omnivox-remote--schedule-retry))))))

(defun omnivox-remote--open (name token)
  "Authenticate lane NAME with TOKEN and return its network process."
  (let* ((process
          (make-network-process
           :name name :host omnivox-remote-host :service omnivox-remote-port
           :family (if (equal omnivox-remote-host "::1") 'ipv6 'ipv4)
           :coding 'utf-8-unix :noquery t :nowait t
           :filter #'omnivox-remote--filter :sentinel #'omnivox-remote--sentinel))
         (deadline (+ (float-time) 4))
         success)
    (unwind-protect
        (progn
          (while (and (eq (process-status process) 'connect)
                      (< (float-time) deadline))
            (accept-process-output process 0.05))
          (unless (eq (process-status process) 'open)
            (error "Cannot connect to Omnivox SSH endpoint"))
          (process-send-string
           process
           (format "OMNIVOX-REMOTE 1 %s %s %s\n" token omnivox-remote--session
                   (if (equal name "Notify") "notification" "speaker")))
          (while (and (process-live-p process)
                      (not (process-get process 'omnivox-remote-ready))
                      (not (process-get process 'omnivox-remote-error))
                      (< (float-time) deadline))
            (accept-process-output process 0.05))
          (if (process-get process 'omnivox-remote-ready)
              (setq success process)
            (error "Omnivox remote connection: %s"
                   (or (process-get process 'omnivox-remote-error) "handshake timeout"))))
      (unless success (delete-process process)))
    success))

(defun omnivox-remote-make-process (name)
  "Create authenticated remote speech lane NAME without a local executable."
  (when omnivox-remote--suspended
    (error "Remote speech disconnected; use omnivox-remote-connect"))
  (unless (and (member omnivox-remote-host '("127.0.0.1" "::1"))
               (integerp omnivox-remote-port) (< 0 omnivox-remote-port 65536))
    (error "Remote Omnivox requires a loopback address and valid port"))
  (let ((token (omnivox-remote--token))
        (old (if (equal name "Notify") tts-notify-process tts-speaker-process))
        (omnivox-remote--connecting t)
        (deadline (+ (float-time) 5))
        process)
    (unless omnivox-remote--session
      ;; This is an identity, not the authentication secret.
      (setq omnivox-remote--session
            (substring (secure-hash 'sha256
                                    (format "%s:%s:%s" (emacs-pid) (current-time) (random)))
                       0 32)))
    (when (processp old) (tts--retire-process old))
    (unless (equal name "Notify")
      (setq omnivox-engine-inventory nil omnivox-control-capabilities nil
            omnivox-available-voices nil))
    (while (not process)
      (condition-case err
          (setq process (omnivox-remote--open name token))
        (error
         (if (and (< (float-time) deadline)
                  (equal (error-message-string err) "Omnivox remote connection: busy"))
             (accept-process-output nil 0.1)
           (signal (car err) (cdr err))))))
    (process-put process 'omnivox-remote-managed t)
    (process-put process 'omnivox-remote-pong (float-time))
    (process-put process 'omnivox-remote-heartbeat
                 (run-at-time 5 5 #'omnivox-remote--heartbeat process))
    process))

(defun omnivox-remote--retry ()
  "Restore failed remote lanes without replaying prior speech."
  (setq omnivox-remote--retry-timer nil)
  (when (and (omnivox-remote-enabled-p) (not omnivox-remote--suspended))
    (condition-case err
        (let ((omnivox-remote--connecting t))
          (unless (process-live-p tts-speaker-process)
            (setq tts-speaker-process (tts-make-process "Speaker"))
            (voice-setup)
            (tts--protocol-sync))
          (when (and (tts--notification-process-configured-p)
                     (not (process-live-p tts-notify-process)))
            (tts-notify-initialize)
            (when (process-live-p tts-notify-process)
              (omnivox--negotiate-process tts-notify-process)
              (let ((tts-speaker-process tts-notify-process))
                (tts--protocol-sync))
              (unless (string-empty-p omnivox-default-voice-id)
                (process-send-string
                 tts-notify-process (format "tts_set_voice %s\n" omnivox-default-voice-id)))))
          (setq omnivox-remote--retry-delay 1 omnivox-remote--last-error nil))
      (error
       (setq omnivox-remote--last-error (error-message-string err))
       (omnivox-remote--schedule-retry)))))

;;;###autoload
(defun omnivox-remote-connect ()
  "Connect or reconnect configured workstation speech with fresh lane state."
  (interactive)
  (require 'tts-speak)
  (unless omnivox-remote-host
    (user-error "Configure omnivox-remote-host and omnivox-remote-token-file first"))
  (setq omnivox-remote--suspended nil tts-program "omnivox")
  (when (timerp omnivox-remote--retry-timer)
    (cancel-timer omnivox-remote--retry-timer))
  (setq omnivox-remote--retry-timer nil omnivox-remote--retry-delay 1)
  (condition-case err
      (progn
        (tts-restart)
        (when (and (tts--notification-process-configured-p)
                   (not (process-live-p tts-notify-process)))
          (omnivox-remote--schedule-retry)))
    (error (omnivox-remote--schedule-retry) (signal (car err) (cdr err)))))

;;;###autoload
(defun omnivox-remote-disconnect ()
  "Stop workstation speech and disable automatic reconnect until connected."
  (interactive)
  (setq omnivox-remote--suspended t)
  (when (timerp omnivox-remote--retry-timer)
    (cancel-timer omnivox-remote--retry-timer))
  (setq omnivox-remote--retry-timer nil)
  (dolist (process (list tts-speaker-process tts-notify-process))
    (when (and (processp process) (process-get process 'omnivox-remote-managed))
      (tts--retire-process process)))
  (setq omnivox-remote--session nil))

;;;###autoload
(defun omnivox-remote-status ()
  "Display connection and recovery status without exposing the service token."
  (interactive)
  (message "Omnivox remote %s:%s; speaker %s; notification %s; retry %s%s"
           omnivox-remote-host omnivox-remote-port
           (and (processp tts-speaker-process) (process-status tts-speaker-process))
           (and (processp tts-notify-process) (process-status tts-notify-process))
           (if (timerp omnivox-remote--retry-timer) "pending" "none")
           (if omnivox-remote--last-error (concat "; " omnivox-remote--last-error) "")))

(defun omnivox-remote-resource (path)
  "Map local bundled sound PATH to a workstation icon ID when remote is active."
  (if (not (omnivox-remote-enabled-p)) path
    (let* ((root (file-name-as-directory (file-truename emacsvox-sounds-dir)))
           (file (file-truename path))
           (relative (file-relative-name file root)))
      (unless (and (file-in-directory-p file root)
                   (cl-every
                    (lambda (part)
                      (and (not (member part '("" "." "..")))
                           (string-match-p "\\`[A-Za-z0-9_.-]+\\'" part)))
                    (split-string relative "/")))
        (error "Remote speech needs a bundled sound below emacsvox-sounds-dir"))
      (concat "omnivox-icon:" relative))))

(provide 'omnivox-remote)
;;; omnivox-remote.el ends here
