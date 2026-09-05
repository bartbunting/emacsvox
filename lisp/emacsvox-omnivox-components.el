;;; emacsvox-omnivox-components.el --- Install Omnivox engine modules -*- lexical-binding: t; -*-

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

;; Spoken front end to the pinned, verified WSL2 Omnivox component
;; manager.  Proprietary runtimes and voice models remain user supplied.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'tabulated-list)
(require 'emacsvox-aural-ui)
(require 'emacsvox-aural-inspection)

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

(defgroup emacsvox-omnivox-components nil
  "Manage optional Omnivox engine modules."
  :group 'emacsvox)

(defcustom emacsvox-omnivox-component-installer
  (expand-file-name "bin/emacsvox-omnivox-components" emacsvox-directory)
  "Program that lists, installs, uninstalls, and tests Omnivox modules."
  :type 'file
  :group 'emacsvox-omnivox-components)

(defcustom emacsvox-omnivox-restart-after-component-install t
  "Whether to restart running Omnivox after a managed module change."
  :type 'boolean
  :group 'emacsvox-omnivox-components)

(defvar-local emacsvox-omnivox-components--records nil
  "Component records displayed in the current manager buffer.")

(defvar-local emacsvox-omnivox-components--process nil
  "Active install, uninstall, or engine-test process for this manager.")

(defconst emacsvox-omnivox-components--output-buffer
  "*Omnivox Component Output*")

(defconst emacsvox-omnivox-components--managed-ids
  '("flite" "rutts" "piper" "tgspeechbox")
  "Component identifiers that this manager may install and uninstall.")

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

(defun emacsvox-omnivox-components--load-records ()
  "Return current component records from the verified installer manifest."
  (let ((program (emacsvox-omnivox-components--check-installer)))
    (with-temp-buffer
      (let ((status (process-file program nil '(t t) nil "--machine")))
        (unless (and (integerp status) (zerop status))
          (user-error
           "Could not list Omnivox components: %s"
           (string-trim (buffer-string))))
        (emacsvox-omnivox-components--parse (buffer-string))))))

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
              (equal (plist-get record :id)
                     (process-get emacsvox-omnivox-components--process
                                  'emacsvox-component-id)))
     (pcase (process-get emacsvox-omnivox-components--process
                         'emacsvox-operation)
       ('installation "installing")
       ('uninstallation "uninstalling")
       ('test "testing")))
   (if (equal (plist-get record :state) "available")
       "not installed"
     (replace-regexp-in-string "-" " " (plist-get record :state)))))

(defun emacsvox-omnivox-components--entries (records)
  "Return tabulated entries for component RECORDS."
  (mapcar
   (lambda (record)
     (list
      (plist-get record :id)
      (vector
       (plist-get record :name)
       (emacsvox-omnivox-components--state record)
       (emacsvox-omnivox-components--human-size
        (plist-get record :size))
       (plist-get record :detail))))
   records))

(defun emacsvox-omnivox-components--record (&optional id)
  "Return the current component record, or the record named by ID."
  (let ((id (or id (tabulated-list-get-id))))
    (or (cl-find id emacsvox-omnivox-components--records
                 :test #'string= :key (lambda (record)
                                        (plist-get record :id)))
        (user-error "Move to an Omnivox component row first"))))

(defun emacsvox-omnivox-components--render (&optional id)
  "Redraw current module records, preserving row ID and current column."
  (emacsvox-aural-ui-refresh-tabulated
   (lambda ()
     (setq tabulated-list-entries
           (emacsvox-omnivox-components--entries
            emacsvox-omnivox-components--records)))
   id "windows"))

(defun emacsvox-omnivox-components-refresh (&optional id)
  "Refresh Omnivox module status, preserving row ID and current column."
  (interactive)
  (setq emacsvox-omnivox-components--records
        (emacsvox-omnivox-components--load-records))
  (emacsvox-omnivox-components--render id))

(defun emacsvox-omnivox-components-speak-current ()
  "Speak the complete Omnivox component row at point."
  (interactive)
  (let* ((record (emacsvox-omnivox-components--record))
         (text
          (format
           "%s. %s. %s. %s."
           (plist-get record :name)
           (emacsvox-omnivox-components--state record)
           (emacsvox-omnivox-components--human-size
            (plist-get record :size))
           (plist-get record :detail))))
    (emacsvox-omnivox-components--speak text)))

(defun emacsvox-omnivox-components--running-omnivox-p ()
  "Return non-nil when the active speech server appears to be Omnivox."
  (and (boundp 'tts-speaker-process)
       (process-live-p tts-speaker-process)
       (boundp 'tts-program)
       (string-match-p "omnivox" (format "%s" tts-program))))

(defun emacsvox-omnivox-components--suspend-omnivox ()
  "Retire active Omnivox streams and return non-nil when any were stopped.

This releases persistent Windows helper executables before module removal."
  (when (emacsvox-omnivox-components--running-omnivox-p)
    (unless (fboundp 'tts--retire-process)
      (error "Cannot safely stop Omnivox before module removal"))
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
      (format "%s is available with %s voices. Voice list opened"
              name (match-string 1 output)))
     ((and success (eq operation 'test))
      (format "%s voice check succeeded%s. Results opened"
              name (if last-line (format ": %s" last-line) "")))
     ((and success (eq operation 'installation))
      (format "%s installed" name))
     ((and success (eq operation 'uninstallation))
      (format "%s uninstalled" name))
     (success
      (format "%s %s completed" name operation))
     (t
      (format "%s %s failed: %s. Details opened"
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

(defun emacsvox-omnivox-components--finish (process event)
  "Handle completion of component PROCESS described by EVENT."
  (when (memq (process-status process) '(exit signal))
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
           (message-text
            (emacsvox-omnivox-components--result-message
             name operation success output-text event)))
      (when (buffer-live-p manager)
        (with-current-buffer manager
          (when (eq process emacsvox-omnivox-components--process)
            (setq emacsvox-omnivox-components--process nil)
            (condition-case err
                (emacsvox-omnivox-components-refresh id)
              (error
               (emacsvox-omnivox-components--render id)
               (setq message-text
                     (format "%s; refresh failed: %s"
                             message-text (error-message-string err))))))))
      (when (and (or restore-omnivox
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
      (when (or (not success) (eq operation 'test))
        (emacsvox-omnivox-components--show-output output))
      (message "%s" message-text)
      (emacsvox-omnivox-components--speak message-text))))

(defun emacsvox-omnivox-components--start (record operation arguments)
  "Start OPERATION for component RECORD using installer ARGUMENTS."
  (when (process-live-p emacsvox-omnivox-components--process)
    (user-error "An Omnivox component operation is already running"))
  (let* ((program (emacsvox-omnivox-components--check-installer))
         (output (get-buffer-create
                  emacsvox-omnivox-components--output-buffer))
         (manager (current-buffer))
         (restore-omnivox nil))
    (with-current-buffer output
      (let ((inhibit-read-only t))
        (erase-buffer)
        (fundamental-mode)))
    (emacsvox-omnivox-components--speak
     (format "%s %s started" (plist-get record :name) operation))
    (condition-case err
        (progn
          (when (eq operation 'uninstallation)
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
    (when (derived-mode-p 'emacsvox-omnivox-components-mode)
      (emacsvox-omnivox-components--render))
    emacsvox-omnivox-components--process))

(defun emacsvox-omnivox-components-install ()
  "Download, verify, and install the selected optional engine module."
  (interactive)
  (let* ((record (emacsvox-omnivox-components--record))
         (state (plist-get record :state))
         (name (plist-get record :name))
         (id (plist-get record :id)))
    (unless (string= state "available")
      (user-error "%s is not currently downloadable: %s" name state))
    (when
        (yes-or-no-p
         (concat
          (format "Install %s (%s)? " name
                  (emacsvox-omnivox-components--human-size
                   (plist-get record :size)))
          (pcase id
            ("piper" "A separately reviewed voice model will still be required. ")
            ("tgspeechbox" "This engine is experimental. ")
            (_ ""))))
      (emacsvox-omnivox-components--start
       record 'installation (list "--install" id)))))

(defun emacsvox-omnivox-components-uninstall ()
  "Confirm and uninstall the selected manager-installed engine module."
  (interactive)
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
          (format "Uninstall %s? " name)
          "Its verified download remains cached. "
          "Files manually added inside its managed directory are also removed. "))
      (emacsvox-omnivox-components--start
       record 'uninstallation (list "--uninstall" id)))))

(defun emacsvox-omnivox-components-test ()
  "Ask Omnivox to list voices through the selected engine."
  (interactive)
  (let ((record (emacsvox-omnivox-components--record)))
    (emacsvox-omnivox-components--start
     record 'test (list "--test" (plist-get record :id)))))

(defun emacsvox-omnivox-components-activate ()
  "Install an available module, or test any other selected engine."
  (interactive)
  (if (string= (plist-get (emacsvox-omnivox-components--record) :state)
               "available")
      (emacsvox-omnivox-components-install)
    (emacsvox-omnivox-components-test)))

(defun emacsvox-omnivox-components-help ()
  "Display and speak Omnivox engine-module manager help."
  (interactive)
  (emacsvox-aural-ui-with-help-window
    (princ
     (concat
      "Omnivox Engine Modules\n\n"
      "This manager shows built-in engines, user-supplied runtime bridges,\n"
      "and optional modules pinned to the installed Omnivox release. Downloads\n"
      "are installed per user only after their SHA-256 checksum is verified.\n"
      "Release state describes that managed release installation. Browse and\n"
      "try voices reports the active server, which may use another installation.\n"
      "Emacsvox never downloads Eloquence, DECtalk, or RHVoice runtimes, or a\n"
      "Piper voice model.\n\n"
      "n or down next       p or up previous\n"
      "left/right column    . speak titled cell\n"
      "Not installed means downloadable; installing marks an active download.\n"
      "Uninstalling and testing mark other operations in progress.\n"
      "RET install missing module, otherwise test engine\n"
      "i install module     t check engine; open voices or error\n"
      "u uninstall a manager-installed module\n"
      "g refresh            h aural home\n"
      "? help               q quit\n")))
  (when (fboundp 'emacsvox-speak-help)
    (emacsvox-speak-help)))

(define-derived-mode emacsvox-omnivox-components-mode
    emacsvox-aural-tabulated-mode
  "Omnivox-Modules"
  "Spoken manager for verified Omnivox engine modules."
  (emacsvox-aural-ui-configure-tabulated
   "Omnivox engine module list"
   #'emacsvox-omnivox-components-speak-current
   #'emacsvox-omnivox-components-refresh)
  (setq tabulated-list-format
        [("Engine" 16 t)
         ("Release state" 21 t)
         ("Download" 11 t)
         ("Details" 0 t)]
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
  "Open the accessible Omnivox engine-module manager."
  (interactive)
  (let ((source (emacsvox-aural-inspection-remember-source-buffer))
        (buffer (get-buffer-create "*Omnivox Engine Modules*")))
    (with-current-buffer buffer
      (unless (derived-mode-p 'emacsvox-omnivox-components-mode)
        (emacsvox-omnivox-components-mode))
      (emacsvox-aural-inspection-attach-source source)
      (emacsvox-omnivox-components-refresh))
    (emacsvox-aural-ui-pop-to-buffer buffer)
    (when (called-interactively-p 'interactive)
      (emacsvox-omnivox-components-speak-current))
    buffer))

(provide 'emacsvox-omnivox-components)

;;; emacsvox-omnivox-components.el ends here
