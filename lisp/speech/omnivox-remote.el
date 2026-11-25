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
(require 'seq)
(require 'subr-x)
(require 'emacsvox-frame-speech)
(require 'tts-queue-state)

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
(cl-defstruct (omnivox-remote--frame (:copier nil))
  frame host port token-file endpoint timer (delay 1) error)
(defvar omnivox-remote--opening-frame nil)
(defvar tts-program)
(defvar tts-speaker-process)
(defvar tts-notify-process)
(defvar emacsvox-sounds-dir)
(defvar omnivox-default-voice-id)
(defvar omnivox-engine-inventory)
(defvar omnivox-control-capabilities)
(defvar omnivox-available-voices)
(defvar omnivox-library--timeout)
(defvar tts-handle-unicode)
(defvar tts-speech-rate)
(defvar omnivox-engine-inventory-time)
(defvar omnivox-routing-policy-registration)
(defvar omnivox-logical-voice-registration)
(defvar omnivox-control-last-error)
(declare-function omnivox-library--wait-for-recovered-speech "omnivox-library-runtime" (process))
(declare-function omnivox-library--control "omnivox-library-runtime" (process command))
(declare-function omnivox-library-apply--uuid "omnivox-library-apply" (value))
(declare-function omnivox--install-control-filter "omnivox-voices" (process))
(declare-function tts--omnivox-program-p "tts-speak" (&optional program))
(declare-function tts--retire-process "tts-lifecycle" (process))
(declare-function tts--speech-process-sentinel "tts-lifecycle" (process event))
(declare-function tts-restart "tts-speak" ())
(declare-function tts-make-process "tts-speak" (name))
(declare-function tts--protocol-sync "tts-speak" ())
(declare-function tts--notification-process-configured-p "tts-speak" ())
(declare-function tts-notify-initialize "tts-speak" ())
(declare-function voice-setup "voice-setup" ())
(declare-function omnivox--negotiate-process "omnivox-voices" (process))

(defun omnivox-remote-enabled-p ()
  "Return non-nil when Omnivox uses the remote workstation transport."
  (and (if (and emacsvox-frame-speech--active (not omnivox-remote--opening-frame))
           (and (processp tts-speaker-process)
                (process-get tts-speaker-process 'omnivox-remote-managed))
         omnivox-remote-host)
       (tts--omnivox-program-p)))

(defun omnivox-remote--begin-activation ()
  "Retire both remote lanes before selecting a fresh workstation configuration."
  (let ((omnivox-remote--connecting t))
    (when (timerp omnivox-remote--retry-timer) (cancel-timer omnivox-remote--retry-timer))
    (setq omnivox-remote--retry-timer nil)
    (dolist (process (delete-dups (list tts-speaker-process tts-notify-process)))
      (when (and (processp process) (process-get process 'omnivox-remote-managed))
        (tts--retire-process process)))
    (setq omnivox-remote--session nil)))

(defun omnivox-remote--acknowledge-engines (process)
  "Verify PROCESS agrees with its live peer's workstation configuration.
Older hosts without the feature retain ordinary negotiation. A restarted
workstation can prepare a new activation when no old lane remains live."
  (require 'omnivox-library-runtime)
  (omnivox--install-control-filter process)
  (let* ((omnivox-library--timeout 180)
         (capabilities (omnivox-library--control process '(:type "capabilities"))))
    (unless (equal (plist-get capabilities :type) "capabilities")
      (error "Missing remote worker capabilities"))
    (when (seq-contains-p (plist-get capabilities :features) "engine_configuration_v1" #'equal)
      (let* ((status (omnivox-library--control process '(:type "engine_configuration_status_v1")))
             (identity (plist-get status :activation_id)))
        (unless (equal (plist-get status :type) "engine_configuration_status_v1")
          (error "Missing remote worker configuration acknowledgement"))
        (omnivox-library-apply--uuid identity)
        (dolist (peer (delete-dups (list tts-speaker-process tts-notify-process)))
          (when (and (processp peer) (not (eq peer process)) (process-live-p peer)
                     (process-get peer 'omnivox-remote-managed))
            (unless (equal identity (process-get peer 'omnivox-engine-activation))
              (error "Remote speech lanes acknowledged different engine configurations"))))
        (process-put process 'omnivox-engine-activation identity)))))

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
          (tts-queue--send-typed process "OMNIVOX-REMOTE ping\n" 'neutral)
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
    (tts-queue--retire process)
    (when-let* ((timer (process-get process 'omnivox-remote-heartbeat)))
      (cancel-timer timer)
      (process-put process 'omnivox-remote-heartbeat nil))
    (when (process-get process 'omnivox-remote-managed)
      (let ((retiring (process-get process 'tts--speech-process-retiring)))
        (tts--speech-process-sentinel process event)
        (unless retiring
          (if-let* ((owner (process-get process 'omnivox-remote-frame)))
              (omnivox-remote--frame-lost owner process)
            (omnivox-remote--schedule-retry)))))))

(defun omnivox-remote--open (name token)
  "Authenticate lane NAME with TOKEN and return its network process."
  (let* ((process
          (tts-queue--create
           (lambda ()
             (make-network-process
              :name name :host omnivox-remote-host :service omnivox-remote-port
              :family (if (equal omnivox-remote-host "::1") 'ipv6 'ipv4)
              :coding 'utf-8-unix :noquery t :nowait t
              :filter #'omnivox-remote--filter :sentinel #'omnivox-remote--sentinel)) t))
         (deadline (+ (float-time) 4))
         success auth-receipt)
    (unwind-protect
        (progn
          (while (and (eq (process-status process) 'connect)
                      (< (float-time) deadline))
            (accept-process-output process 0.05))
          (unless (eq (process-status process) 'open)
            (error "Cannot connect to Omnivox SSH endpoint"))
          (let ((command (format "OMNIVOX-REMOTE 1 %s %s %s\n" token omnivox-remote--session
                                 (if (equal name "Notify") "notification" "speaker"))))
            (setq auth-receipt
                  (tts-queue--send process command (tts-queue--describe command 'neutral) t)))
          (while (and (process-live-p process)
                      (not (process-get process 'omnivox-remote-ready))
                      (not (process-get process 'omnivox-remote-error))
                      (< (float-time) deadline))
            (accept-process-output process 0.05))
          (if (process-get process 'omnivox-remote-ready)
              (progn
                (tts-queue--authenticated process auth-receipt)
                (setq success process))
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
    (when omnivox-remote--opening-frame
      (process-put process 'omnivox-remote-frame omnivox-remote--opening-frame))
    (process-put process 'omnivox-remote-pong (float-time))
    (process-put process 'omnivox-remote-heartbeat
                 (run-at-time 5 5 #'omnivox-remote--heartbeat process))
    process))

(defun omnivox-remote--retry ()
  "Restore failed remote lanes without replaying prior speech."
  (when (timerp omnivox-remote--retry-timer) (cancel-timer omnivox-remote--retry-timer))
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
            (tts-notify-initialize))
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

(defun omnivox-remote--frame-workers (owner)
  (when-let* ((endpoint (omnivox-remote--frame-endpoint owner)))
    (list (emacsvox-frame-speech--endpoint-main endpoint)
          (emacsvox-frame-speech--endpoint-notification endpoint))))

(defun omnivox-remote--retire-frame-workers (owner)
  (dolist (process (omnivox-remote--frame-workers owner))
    (when (process-live-p process) (tts--retire-process process))))

(defun omnivox-remote--frame-release (frame)
  "Cancel recovery and retire the remote workers owned by FRAME."
  (when-let* ((owner (frame-parameter frame 'omnivox-remote-connection)))
    (set-frame-parameter frame 'omnivox-remote-connection nil)
    (when-let* ((timer (omnivox-remote--frame-timer owner))) (cancel-timer timer))
    (setf (omnivox-remote--frame-timer owner) nil)
    (omnivox-remote--retire-frame-workers owner)
    (unless (seq-some (lambda (f) (frame-parameter f 'omnivox-remote-connection)) (frame-list))
      (remove-hook 'emacsvox-frame-speech-detach-hook #'omnivox-remote--frame-release))))

(defun omnivox-remote--frame-current-p (owner)
  (let ((frame (omnivox-remote--frame-frame owner)))
    (and (frame-live-p frame) (eq owner (frame-parameter frame 'omnivox-remote-connection)))))

(defun omnivox-remote--frame-schedule (owner)
  (when (and omnivox-remote-auto-reconnect (omnivox-remote--frame-current-p owner)
             (not (omnivox-remote--frame-timer owner)))
    (let ((delay (omnivox-remote--frame-delay owner)))
      (setf (omnivox-remote--frame-timer owner)
            (run-at-time delay nil #'omnivox-remote--frame-retry owner)
            (omnivox-remote--frame-delay owner) (min 30 (* 2 delay))))))

(defun omnivox-remote--frame-lost (owner process)
  (when (and (omnivox-remote--frame-current-p owner)
             (memq process (omnivox-remote--frame-workers owner)))
    ;; Keep the expired handle attached. Commands continue to edit the frame
    ;; while its speech and pending callbacks stay off the default desktop.
    (omnivox-remote--retire-frame-workers owner)
    (omnivox-remote--frame-schedule owner)))

(defun omnivox-remote--frame-open (owner)
  "Prepare and negotiate a fresh pair before publishing it to OWNER's frame."
  (let* ((frame (omnivox-remote--frame-frame owner))
         (previous (omnivox-remote--frame-endpoint owner))
         (original (emacsvox-frame-speech-endpoint frame))
         (omnivox-remote--opening-frame owner)
         (omnivox-remote-host (omnivox-remote--frame-host owner))
         (omnivox-remote-port (omnivox-remote--frame-port owner))
         (omnivox-remote-token-file (omnivox-remote--frame-token-file owner))
         (omnivox-remote--session nil) (omnivox-remote--suspended nil)
         (emacsvox-frame-speech--active nil) (emacsvox-frame-speech--command-owner nil)
         (emacsvox-frame-speech--hook-owner nil)
         (tts-program "omnivox") (tts-speaker-process nil) (tts-notify-process nil)
         (tts-speech-rate (if previous (emacsvox-frame-speech--endpoint-rate previous) tts-speech-rate))
         (tts-handle-unicode tts-handle-unicode)
         omnivox-engine-inventory omnivox-engine-inventory-time omnivox-control-capabilities
         omnivox-available-voices omnivox-logical-voice-registration omnivox-routing-policy-registration
         omnivox-control-last-error main notify installed)
    (unwind-protect
        (progn
          (setq main (tts-make-process "Speaker") tts-speaker-process main
                notify (tts-make-process "Notify") tts-notify-process notify)
          (dolist (process (list main notify))
            (omnivox--negotiate-process process)
            (omnivox-library--wait-for-recovered-speech process)
            (let ((tts-speaker-process process)) (tts--protocol-sync)))
          (unless (and (frame-live-p frame) (eq original (emacsvox-frame-speech-endpoint frame))
                       (or (null previous) (omnivox-remote--frame-current-p owner)))
            (error "Frame speech changed while connecting"))
          (setf (omnivox-remote--frame-endpoint owner)
                (emacsvox-frame-speech-attach frame main notify tts-program tts-speech-rate previous))
          (set-frame-parameter frame 'omnivox-remote-connection owner)
          (add-hook 'emacsvox-frame-speech-detach-hook #'omnivox-remote--frame-release)
          (setf (omnivox-remote--frame-delay owner) 1 (omnivox-remote--frame-error owner) nil)
          (setq installed t))
      (unless installed
        (dolist (process (list notify main))
          (when (and process (process-live-p process)) (tts--retire-process process)))))))

(defun omnivox-remote--frame-retry (owner)
  (when-let* ((timer (omnivox-remote--frame-timer owner))) (cancel-timer timer))
  (setf (omnivox-remote--frame-timer owner) nil)
  (when (omnivox-remote--frame-current-p owner)
    (condition-case err
        (omnivox-remote--frame-open owner)
      (error (setf (omnivox-remote--frame-error owner) (error-message-string err))
             (omnivox-remote--frame-schedule owner)))))

;;;###autoload
(defun omnivox-remote-connect-frame (host port token-file &optional frame)
  "Connect FRAME to workstation Omnivox at loopback HOST and forwarded PORT.
TOKEN-FILE contains the private workstation token. Use an existing SSH
forward. Interactively connect the selected frame. A lost lane recovers
with fresh speech workers when `omnivox-remote-auto-reconnect' is enabled."
  (interactive (list (completing-read "Forwarded loopback address: " '("127.0.0.1" "::1")
                                      nil t nil nil (or omnivox-remote-host "127.0.0.1"))
                     (read-number "Forwarded port: " omnivox-remote-port)
                     (read-file-name "Private token file: " nil omnivox-remote-token-file t)))
  (require 'tts-speak)
  (require 'omnivox-voices)
  (require 'omnivox-library-runtime)
  (setq frame (or frame (selected-frame)) token-file (expand-file-name token-file))
  (unless (frame-live-p frame) (user-error "Choose a live Emacs frame"))
  (let* ((old (frame-parameter frame 'omnivox-remote-connection))
         (same (and old (equal host (omnivox-remote--frame-host old))
                    (equal port (omnivox-remote--frame-port old))
                    (equal token-file (omnivox-remote--frame-token-file old))))
         (owner (if same old (make-omnivox-remote--frame
                              :frame frame :host host :port port :token-file token-file))))
    (unless (and same (cl-every #'process-live-p (omnivox-remote--frame-workers owner)))
      (when-let* ((timer (omnivox-remote--frame-timer owner))) (cancel-timer timer))
      (setf (omnivox-remote--frame-timer owner) nil)
      (condition-case err
          (omnivox-remote--frame-open owner)
        (error (setf (omnivox-remote--frame-error owner) (error-message-string err))
               (omnivox-remote--frame-schedule owner)
               (signal (car err) (cdr err)))))
    (when (called-interactively-p 'interactive)
      (emacsvox-frame-speech-call (omnivox-remote--frame-endpoint owner)
                                  #'message "Frame connected to workstation speech"))
    (omnivox-remote--frame-endpoint owner)))

;;;###autoload
(defun omnivox-remote-disconnect-frame (&optional frame)
  "Close FRAME's remote workers and return this frame to ordinary speech."
  (interactive)
  (setq frame (or frame (selected-frame)))
  (when (frame-parameter frame 'omnivox-remote-connection)
    (emacsvox-frame-speech-detach frame))
  (when (called-interactively-p 'interactive)
    (emacsvox-frame-speech-call nil #'message "Frame uses ordinary speech")))

;;;###autoload
(defun omnivox-remote-frame-status (&optional frame)
  "Describe FRAME's workstation connection and pending recovery."
  (interactive)
  (if-let* ((owner (frame-parameter frame 'omnivox-remote-connection)))
      (message "Workstation %s port %d. %s%s"
               (omnivox-remote--frame-host owner) (omnivox-remote--frame-port owner)
               (cond ((omnivox-remote--frame-timer owner) "Reconnecting")
                     ((cl-every #'process-live-p (omnivox-remote--frame-workers owner)) "Connected")
                     (t "Disconnected"))
               (if-let* ((reason (omnivox-remote--frame-error owner))) (concat ". " reason) ""))
    (message "This frame has no workstation connection")))

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
