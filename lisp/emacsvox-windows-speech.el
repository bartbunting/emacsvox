;;; emacsvox-windows-speech.el --- Native Windows speech integration -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Bart Bunting
;; SPDX-License-Identifier: GPL-2.0-or-later

;; This file is not part of GNU Emacs, but the same permissions apply.
;; See the file COPYING in this distribution.

;;; Commentary:
;;
;; Register the native Windows speech servers bundled with Emacsvox.  Friendly
;; names shown by `tts-select-server' are translated to paths below the
;; configured server directory.  This module also configures native auditory
;; icons, notification streams, stereo positioning, and dependency diagnosis.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'tts-speak)
(require 'emacsvox-sounds)

(defgroup emacsvox-windows-speech nil
  "Native Windows speech and auditory-icon support under WSL."
  :group 'emacsvox)

(defcustom emacsvox-windows-speech-servers-directory
  (file-name-as-directory
   (expand-file-name
    (or
     (getenv "EMACSVOX_WINDOWS_SPEECH_SERVERS")
     emacsvox-servers-directory)))
  "Directory containing native Windows speech server launchers.

Set this directly or set `EMACSVOX_WINDOWS_SPEECH_SERVERS' in the
environment.  The bundled Emacsvox server directory is the default."
  :type 'directory
  :group 'emacsvox-windows-speech)

(defcustom emacsvox-windows-speech-enable-notification-stream t
  "Whether Windows speech servers use a separate notification stream.
The notification stream uses a second server and native bridge process, so
notifications can speak independently of the main speech stream.  Changes
take effect the next time the speech server is selected or restarted."
  :type 'boolean
  :group 'emacsvox-windows-speech)

(defcustom emacsvox-windows-speech-main-pan 0.0
  "Stereo position of the main Windows speech stream.
-1.0 is fully left, 0.0 is centered, and 1.0 is fully right.  Values
outside that range are clamped when the speech process starts.  Changes
take effect the next time the speech server is selected or restarted."
  :type 'number
  :group 'emacsvox-windows-speech)

(defcustom emacsvox-windows-speech-notification-pan 0.65
  "Stereo position of the Windows notification speech stream.
-1.0 is fully left, 0.0 is centered, and 1.0 is fully right.  Values
outside that range are clamped when the notification process starts.
Changes take effect when the speech server is selected or restarted."
  :type 'number
  :group 'emacsvox-windows-speech)

(defconst emacsvox-windows-speech--server-files
  '(("windows-outloud" . "windows-outloud")
    ("windows-dtk" . "windows-dtk"))
  "Friendly speech server names and their launcher file names.")

(defvar emacsvox-windows-speech--enabled nil
  "Non-nil when friendly Windows server selection is enabled.")

(defvar emacsvox-windows-speech--added-server-names nil
  "Server names added to `tts-servers-alist' by this integration.")

(defvar emacsvox-windows-speech--saved-audio-state nil
  "Audio configuration saved before enabling native Windows playback.")

(defconst emacsvox-windows-speech--notification-device "windows-default"
  "Internal device name that enables Emacsvox's notification process.")

(defconst emacsvox-windows-speech--pan-environment-variable
  "EMACSVOX_WINDOWS_SPEECH_PAN"
  "Environment variable passed to a native Windows speech bridge.")

(defun emacsvox-windows-speech--server-path (name)
  "Return the configured native Windows server path for NAME."
  (when-let* ((directory emacsvox-windows-speech-servers-directory)
              (file (cdr (assoc-string
                          name emacsvox-windows-speech--server-files))))
    (expand-file-name file directory)))

(defun emacsvox-windows-speech--resolve-server-arguments (arguments)
  "Translate a friendly server name in ARGUMENTS to its absolute path."
  (let* ((name (car arguments))
         (path
          (and (stringp name)
               (emacsvox-windows-speech--server-path name))))
    (if path
        (progn
          (unless (file-executable-p path)
            (user-error "Windows speech server is not executable: %s" path))
          (cons path (cdr arguments)))
      arguments)))

(defun emacsvox-windows-speech--server-p (program)
  "Return non-nil when PROGRAM names one of the Windows speech servers."
  (and
   (stringp program)
   (member
    (file-name-nondirectory program)
    (mapcar #'cdr emacsvox-windows-speech--server-files))))

(defun emacsvox-windows-speech--with-notification-stream
    (original &rest arguments)
  "Call ORIGINAL with Windows notification-stream support enabled.
ARGUMENTS are the original arguments to `tts-initialize'."
  (if
      (not
       (and emacsvox-windows-speech-enable-notification-stream
            (emacsvox-windows-speech--server-p tts-program)))
      (apply original arguments)
    (let
        ((tts-multi-engines
          (append
           '("windows-outloud" "windows-dtk") tts-multi-engines))
         (tts-notification-device
          (if
              (and
               (stringp tts-notification-device)
               (> (length tts-notification-device) 0)
               (not (string= tts-notification-device "default")))
              tts-notification-device
            emacsvox-windows-speech--notification-device)))
      (apply original arguments))))

(defun emacsvox-windows-speech--clamp-pan (pan)
  "Return numeric PAN constrained to the inclusive range -1.0 to 1.0."
  (setq pan (if (numberp pan) (float pan) 0.0))
  (max -1.0 (min 1.0 pan)))

(defun emacsvox-windows-speech--with-stereo-position
    (original name &rest arguments)
  "Call ORIGINAL to start speech process NAME at its stereo position.
ARGUMENTS are any remaining arguments to `tts-make-process'."
  (if (not (emacsvox-windows-speech--server-p tts-program))
      (apply original name arguments)
    (let ((process-environment (copy-sequence process-environment))
          (pan
           (if (string= name "Notify")
               emacsvox-windows-speech-notification-pan
             emacsvox-windows-speech-main-pan)))
      (setenv
       emacsvox-windows-speech--pan-environment-variable
       (number-to-string
        (emacsvox-windows-speech--clamp-pan pan)))
      (apply original name arguments))))

(defun emacsvox-windows-speech--register-server-names ()
  "Add available friendly Windows server names to completion."
  (unless tts-servers-alist
    (tts-setup-servers-alist))
  (dolist (entry emacsvox-windows-speech--server-files)
    (let* ((name (car entry))
           (path (emacsvox-windows-speech--server-path name)))
      (when (and path
                 (file-executable-p path)
                 (not (member name tts-servers-alist)))
        (setq tts-servers-alist
              (append tts-servers-alist (list name)))
        (push name emacsvox-windows-speech--added-server-names)))))

(defun emacsvox-windows-speech-enable ()
  "Enable friendly selection of native Windows speech servers."
  (interactive)
  (unless emacsvox-windows-speech--enabled
    (setq emacsvox-windows-speech--added-server-names nil)
    (emacsvox-windows-speech--register-server-names))
  (unless
      (advice-member-p
       #'emacsvox-windows-speech--resolve-server-arguments
       'tts-select-server)
    (advice-add
     'tts-select-server :filter-args
     #'emacsvox-windows-speech--resolve-server-arguments))
  (unless
      (advice-member-p
       #'emacsvox-windows-speech--with-notification-stream
       'tts-initialize)
    (advice-add
     'tts-initialize :around
     #'emacsvox-windows-speech--with-notification-stream))
  (unless
      (advice-member-p
       #'emacsvox-windows-speech--with-stereo-position
       'tts-make-process)
    (advice-add
     'tts-make-process :around
     #'emacsvox-windows-speech--with-stereo-position))
  (setq emacsvox-windows-speech--enabled t)
  (when (called-interactively-p 'interactive)
    (emacsvox-icon 'on)
    (message "Enabled native Windows speech server selection")))

(defun emacsvox-windows-speech-disable ()
  "Disable friendly selection of native Windows speech servers."
  (interactive)
  (when
      (advice-member-p
       #'emacsvox-windows-speech--resolve-server-arguments
       'tts-select-server)
    (advice-remove
     'tts-select-server
     #'emacsvox-windows-speech--resolve-server-arguments))
  (when
      (advice-member-p
       #'emacsvox-windows-speech--with-notification-stream
       'tts-initialize)
    (advice-remove
     'tts-initialize
     #'emacsvox-windows-speech--with-notification-stream))
  (when
      (advice-member-p
       #'emacsvox-windows-speech--with-stereo-position
       'tts-make-process)
    (advice-remove
     'tts-make-process
     #'emacsvox-windows-speech--with-stereo-position))
  (dolist (name emacsvox-windows-speech--added-server-names)
    (setq tts-servers-alist (delete name tts-servers-alist)))
  (setq emacsvox-windows-speech--added-server-names nil
        emacsvox-windows-speech--enabled nil)
  (when (called-interactively-p 'interactive)
    (emacsvox-icon 'off)
    (message "Disabled native Windows speech server selection")))

(defun emacsvox-windows-speech-select-server (server)
  "Select friendly Windows speech SERVER and restart speech."
  (interactive
   (list
    (completing-read
     "Windows speech server:"
     (mapcar #'car emacsvox-windows-speech--server-files)
     nil t)))
  (emacsvox-windows-speech-enable)
  (tts-select-server server))

(defun emacsvox-windows-speech-select-eloquence ()
  "Select the native Windows Eloquence server."
  (interactive)
  (emacsvox-windows-speech-select-server "windows-outloud"))

(defun emacsvox-windows-speech-select-dectalk ()
  "Select the native Windows DECtalk server."
  (interactive)
  (emacsvox-windows-speech-select-server "windows-dtk"))

(defun emacsvox-windows-speech--audio-player ()
  "Return the configured native Windows auditory-icon player path."
  (expand-file-name
   "windows-play" emacsvox-windows-speech-servers-directory))

(defun emacsvox-windows-speech-configure-audio (&optional restart)
  "Route auditory icons and generated SoX cues through Windows.
With prefix argument RESTART, restart the active speech server afterward."
  (interactive "P")
  (let ((player (emacsvox-windows-speech--audio-player)))
    (unless (and player (file-executable-p player))
      (user-error "Windows auditory-icon player is not executable: %s"
                  (or player "not configured")))
    (unless emacsvox-windows-speech--saved-audio-state
      (setq emacsvox-windows-speech--saved-audio-state
            (list
             :emacsvox-play (getenv "EMACSVOX_PLAY")
             :emacsvox-play-program emacsvox-play-program
             :play-arguments ems--play-args
             :sox-play sox-play)))
    (setenv "EMACSVOX_PLAY" player)
    (set 'emacsvox-play-program nil)
    (set 'ems--play-args nil)
    (set 'sox-play player)
    (when restart
      (tts-restart))
    (when (called-interactively-p 'interactive)
      (emacsvox-icon 'on)
      (message
       "Configured native Windows audio%s"
       (if restart " and restarted speech" "")))
    player))

(defun emacsvox-windows-speech-restore-audio (&optional restart)
  "Restore audio settings saved before native Windows configuration.
With prefix argument RESTART, restart the active speech server afterward."
  (interactive "P")
  (unless emacsvox-windows-speech--saved-audio-state
    (user-error "No previous audio configuration has been saved"))
  (let ((state emacsvox-windows-speech--saved-audio-state))
    (setenv "EMACSVOX_PLAY" (plist-get state :emacsvox-play))
    (set 'emacsvox-play-program
         (plist-get state :emacsvox-play-program))
    (set 'ems--play-args (plist-get state :play-arguments))
    (set 'sox-play (plist-get state :sox-play))
    (setq emacsvox-windows-speech--saved-audio-state nil))
  (when restart
    (tts-restart))
  (when (called-interactively-p 'interactive)
    (emacsvox-icon 'off)
    (message
     "Restored previous audio configuration%s"
     (if restart " and restarted speech" ""))))

(defun emacsvox-windows-speech--tclx-available-p ()
  "Return non-nil when Tcl can load the Tclx package."
  (when-let* ((tclsh (executable-find "tclsh")))
    (with-temp-buffer
      (insert "if {[catch {package require Tclx}]} {exit 1}\n")
      (eq
       0
       (call-process-region
        (point-min) (point-max) tclsh nil nil nil)))))

(defun emacsvox-windows-speech--diagnostic-checks ()
  "Return native Windows speech diagnostic checks."
  (let* ((directory emacsvox-windows-speech-servers-directory)
         (tts-library (expand-file-name "tts-lib.tcl" directory)))
    (list
     (list
      "WSL"
      (or
       (getenv "WSL_DISTRO_NAME")
       (file-exists-p "/proc/sys/fs/binfmt_misc/WSLInterop")))
     (list "PowerShell" (executable-find "powershell.exe"))
     (list "wslpath" (executable-find "wslpath"))
     (list "SoX" (executable-find "sox"))
     (list "Tclx" (emacsvox-windows-speech--tclx-available-p))
     (list "Emacsvox tts-lib.tcl" (file-readable-p tts-library))
     (list
      "Windows audio bridge"
      (file-executable-p
       (expand-file-name
        "windows-audio/bin/WindowsPlay.exe" directory)))
     (list
      "Windows Eloquence bridge"
      (file-executable-p
       (expand-file-name
        "windows-eloquence/bin/EloquenceBridge.exe" directory)))
     (list
      "Windows DECtalk bridge"
      (file-executable-p
       (expand-file-name
        "windows-dectalk/bin/DectalkBridge.exe" directory)))
     (list
      "DECtalk runtime"
      (file-readable-p
       (expand-file-name
        "windows-dectalk/runtime/DECtalk.dll" directory))))))

(defun emacsvox-windows-speech-diagnose ()
  "Display native Windows speech dependency and build status."
  (interactive)
  (let* ((checks (emacsvox-windows-speech--diagnostic-checks))
         (failed (cl-count-if-not #'cadr checks))
         (buffer
          (get-buffer-create "*Emacsvox Windows Speech Diagnostics*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "Emacsvox Windows speech diagnostics\n\n")
        (dolist (check checks)
          (insert
           (format
            "[%s] %s\n"
            (if (cadr check) "OK" "MISSING")
            (car check))))
        (special-mode)))
    (display-buffer buffer)
    (emacsvox-icon (if (zerop failed) 'task-done 'warn-user))
    (message
     "Windows speech diagnostics: %d passed, %d missing"
     (- (length checks) failed) failed)
    checks))

;; Loading this module exposes the bundled executable server launchers without
;; changing the active speech server or audio player.
(emacsvox-windows-speech-enable)

(provide 'emacsvox-windows-speech)

;;; emacsvox-windows-speech.el ends here
