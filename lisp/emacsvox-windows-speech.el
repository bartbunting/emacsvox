;;; emacsvox-windows-speech.el --- Native Windows speech integration -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Bart Bunting
;; SPDX-License-Identifier: GPL-2.0-or-later

;; This file is not part of GNU Emacs, but the same permissions apply.
;; See the file COPYING in this distribution.

;;; Commentary:
;;
;; Make native Windows speech servers stored outside Emacsvox available by
;; friendly names.  This is useful under WSL, where the server launchers and
;; their native bridges may live in a separate support checkout.

;;; Code:

(require 'subr-x)
(require 'tts-speak)

(defgroup emacsvox-windows-speech nil
  "Native Windows speech support under WSL."
  :group 'emacsvox)

(defcustom emacsvox-windows-speech-servers-directory
  (let* ((player (getenv "EMACSVOX_PLAY"))
         (directory
          (or
           (getenv "EMACSVOX_WINDOWS_SPEECH_SERVERS")
           (and player
                (> (length player) 0)
                (file-name-directory player)))))
    (and directory
         (file-name-as-directory (expand-file-name directory))))
  "Directory containing native Windows speech server launchers.

Set this directly or set `EMACSVOX_WINDOWS_SPEECH_SERVERS' in the
environment.  When neither is set, use the directory containing the
player named by `EMACSVOX_PLAY'."
  :type '(choice (const :tag "Not configured" nil)
                 directory)
  :group 'emacsvox-windows-speech)

(defconst emacsvox-windows-speech--server-files
  '(("windows-outloud" . "windows-outloud")
    ("windows-dtk" . "windows-dtk"))
  "Friendly speech server names and their launcher file names.")

(defvar emacsvox-windows-speech--enabled nil
  "Non-nil when friendly Windows server selection is enabled.")

(defvar emacsvox-windows-speech--added-server-names nil
  "Server names added to `tts-servers-alist' by this integration.")

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
  (setq emacsvox-windows-speech--enabled t)
  (when (called-interactively-p 'interactive)
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
  (dolist (name emacsvox-windows-speech--added-server-names)
    (setq tts-servers-alist (delete name tts-servers-alist)))
  (setq emacsvox-windows-speech--added-server-names nil
        emacsvox-windows-speech--enabled nil)
  (when (called-interactively-p 'interactive)
    (message "Disabled native Windows speech server selection")))

;; Loading this module is enough to expose any configured executable servers.
(emacsvox-windows-speech-enable)

(provide 'emacsvox-windows-speech)

;;; emacsvox-windows-speech.el ends here
