;;; emacsvox-dbus.el --- DBus On Emacsvox -*- lexical-binding: t; -*-
;; $Id: emacsvox-dbus.el 4797 2007-07-16 23:31:22Z tv.raman.tv $
;; $Author: tv.raman.tv $
;; Description:  DBus Tools For The Emacsvox Desktop
;; Keywords: Emacsvox,  Audio Desktop dbus
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ |
;; Location https://github.com/robertmeta/emacsvox
;; 

;;;   Copyright:
;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; All Rights Reserved.
;; 
;; This file is not part of GNU Emacs, but the same permissions apply.
;; 
;; GNU Emacs is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;; 
;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNDBUS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; Loading this module sets  up Emacsvox to respond to DBus notifications.
;; This module needs to be loaded explicitly from the user's init file
;; after emacsvox has been started.

;; @subsection Overview
;; 
;; This module provides integration via DBus  for the following:
;; @itemize @bullet
;; @item Respond to network coming up or going down
;; --- @code{(nm-enable)}.
;; @item Respond to screen getting locked/unlocked by gnome-screen-saver
;; --- @code{(emacsvox-dbus-watch-screen-lock)}.
;; @item Respond to laptop  going to sleep or waking up
;; ---  @code{(emacsvox-dbus-sleep-enable)}.
;; @item Respond to insertion/ejection of removable storage
;; --- @code{(emacsvox-dbus-udisks-enable)}.
;; @item Watch for power devices
;; --- @code{(emacsvox-dbus-upower-enable)}.
;; @item An interactive command  @command{emacsvox-dbus-lock-screen}
;; bound to @kbd{C-, C-d} to lock the screen using DBus.
;; Note: this key-binding is available only if this module is loaded.
;; @end itemize
;; Add calls to the desired functions from the above list
;; to the emacs startup file after  this module has been loaded.
;; To enable all of them, add (emacsvox-dbus-setup).
;; See relevant hooks for customizing behavior.
;; Note that each of the  sleep/wake-up, UDisks2   and network/up-down
;; can be separately enabled/disabled, and the actions customized
;; via appropriately named hook functions.
;; 
;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'amixer)
(require 'derived)
(require 'dbus)
(require 'emacsvox-nm "emacsvox-nm" 'no-error)

;;;  Forward Declarations:

(declare-function soundscape-restart "soundscape" (&optional device))

;;;  ScreenSaver Mode:

(define-derived-mode emacsvox-screen-saver-mode special-mode
  "Screen Saver Mode"
  "A light-weight mode for the `*Emacsvox Screen Saver *' buffer.
This is a hidden buffer that is made current so we automatically
switch to a screen-saver soundscape."
  (setq header-line-format "")
  t)

(defvar emacsvox-screen-saver-saved-conf  nil
  "Record window configuration when screen-saver was launched.")

(defun emacsvox-screen-saver ()
  "Launch Emacsvox screen-saver.
Initialize screen-saver buffer  if needed, and switch to  it."
  
  (setq emacsvox-screen-saver-saved-conf (current-window-configuration))
  (let ((buffer (get-buffer-create "*Emacsvox Screen Saver*")))
    (with-current-buffer buffer (emacsvox-screen-saver-mode))
    (funcall-interactively #'switch-to-buffer buffer)
    (delete-other-windows)))

;;;  NM Handlers
(declare-function ems--get-active-network-interfaces "emacsvox-wizards" nil)

(defun emacsvox-dbus-nm-connected ()
  "Announce  network manager connection.
Startup  apps that need the network."
  
  (setq emacsvox-speak-network-interfaces-list
        (ems--get-active-network-interfaces))
  (emacsvox-pip (format "%s. Network up. " (ems--get-essid)))
  (emacsvox-icon 'network-up))

(defun emacsvox-dbus-nm-disconnected ()
  "Announce  network manager disconnection.
Stop apps that use the network."
  
  (setq emacsvox-speak-network-interfaces-list
        (mapcar #'car (network-interface-list)))
  (emacsvox-icon 'network-down)
  (message (mapconcat #'identity emacsvox-speak-network-interfaces-list ""))
  (dtk-notify "Network down"))

(add-hook 'nm-connected-hook 'emacsvox-dbus-nm-connected)
(add-hook 'nm-disconnected-hook 'emacsvox-dbus-nm-disconnected)

;;;  Sleep/Resume:

(defun emacsvox-dbus-login1-sleep-p ()
  "Test if login1 service  sleep signal is available."
  (member
   "PrepareForSleep"
   (dbus-introspect-get-signal-names
    :system
    "org.freedesktop.login1" "/org/freedesktop/login1"
    "org.freedesktop.login1.Manager")))

(defvar emacsvox-dbus-sleep-hook nil
  "Functions called when machine is about to sleep (suspend or hibernate). ")

(defvar emacsvox-dbus-resume-hook nil
  "Functions called when machine is resumed (from suspend or hibernate).")

(defun emacsvox-dbus-sleep-signal-handler()
  (run-hooks 'emacsvox-dbus-sleep-hook))

(defun emacsvox-dbus-resume-signal-handler()
  "Resume handler"
  (run-hooks 'emacsvox-dbus-resume-hook))

(defun emacsvox-dbus-screensaver-check ()
  "Check  and fix Emacs DBus Binding to gnome-screensaver"
  (when (file-exists-p "/usr/bin/gnome-screensaver")
    (ems-with-messages-silenced
     (condition-case nil
         (dbus-call-method
          :session
          "org.gnome.ScreenSaver" "/org/gnome/ScreenSaver"
          "org.gnome.ScreenSaver" "GetActive")
       (error
        (start-process "screen-saver" nil "gnome-screensaver")))
     t)))

(defvar emacsvox-dbus-sleep-registration nil
  "List holding sleep registration.")

(defun emacsvox-dbus-sleep-register()
  "Register signal handlers for sleep/resume. Return list of
signal registration objects."
  (cond
   ((emacsvox-dbus-login1-sleep-p)
    (emacsvox-dbus-screensaver-check)
    (list
     (dbus-register-signal
      :system "org.freedesktop.login1" "/org/freedesktop/login1"
      "org.freedesktop.login1.Manager" "PrepareForSleep"
      #'(lambda(sleep)
          (if sleep
              (emacsvox-dbus-sleep-signal-handler)
            (emacsvox-dbus-resume-signal-handler))))))
   (t (error "org.freedesktop.login1 has no PrepareForSleep signal."))))

;; Enable integration
(defun emacsvox-dbus-sleep-enable()
  "Enable integration with Login1. Does nothing if already enabled."
  (interactive)
  
  (unless emacsvox-dbus-sleep-registration
    (setq emacsvox-dbus-sleep-registration (emacsvox-dbus-sleep-register))))

;; Disable integration
(defun emacsvox-dbus-sleep-disable()
  "Disable integration with login1 daemon. Does nothing if
already disabled."
  (interactive)
  
  (while emacsvox-dbus-sleep-registration
    (dbus-unregister-object (car emacsvox-dbus-sleep-registration))
    (setq emacsvox-dbus-sleep-registration
          (cdr emacsvox-dbus-sleep-registration))))

(defun emacsvox-dbus-sleep ()
  "Emacsvox  hook for -sleep signal from Login1."
  
  (let ((dtk-quiet t))
    (ems-with-messages-silenced
     (emacsvox-dbus-screensaver-check)
     (save-some-buffers t))))

(add-hook  'emacsvox-dbus-sleep-hook#'emacsvox-dbus-sleep)
;;; Orca For Lock Screen:

(defconst emacsvox-orca (executable-find "orca") "Orca executable")

;; Orca Toggle:
;; Easily start/stop orca for use with lock-screen, Chrome etc.

(defvar emacsvox-orca-handle nil
  "Orca process handle")

(defun emacsvox-orca-toggle ()
  "Toggle state of orca."
  (interactive)
  
  (cond
   (emacsvox-orca-handle
    (delete-process emacsvox-orca-handle)
    (setq emacsvox-orca-handle  nil))
   (t (setq emacsvox-orca-handle (start-process "Orca"nil "orca")))))

(defun emacsvox-dbus-resume ()
  "Emacsvox hook for Login1-resume."
  
  (ems-with-messages-silenced
   (tts-restart)
   (emacsvox-icon 'waking-up)
   (emacsvox-speak-brief-time)
   (amixer-restore amixer-alsactl-config-file)
   (when (featurep 'soundscape) (soundscape-restart))
   (cond
    ((dbus-call-method 
      :session "org.gnome.ScreenSaver" "/org/gnome/ScreenSaver"
      "org.gnome.ScreenSaver" "GetActive") ; screen locked, gdm login
     (and emacsvox-orca (not emacsvox-orca-handle) (emacsvox-orca-toggle))
     (emacsvox-icon 'pwd)
     (emacsvox-icon 'help))
    (t                                 ;screen unlocked
     (and emacsvox-orca emacsvox-orca-handle (emacsvox-orca-toggle)) 
     (when (featurep 'light) (light-black))))))

(add-hook 'emacsvox-dbus-resume-hook #'emacsvox-dbus-resume)

;;;  UDisks2:

(defvar emacsvox-dbus-udisks-registration nil
  "List holding storage (UDisks2) registration.")

(defun emacsvox-dbus-udisks-register()
  "Register signal handlers for UDisks2  InterfacesAdded signal."
  (list
   (dbus-register-signal
    :system
    "org.freedesktop.UDisks2" "/org/freedesktop/UDisks2"
    "org.freedesktop.DBus.ObjectManager" "InterfacesAdded"
    #'(lambda(path _props)
        (emacsvox-icon 'open-object)
        (message "Added storage %s" path)))
   (dbus-register-signal
    :system
    "org.freedesktop.UDisks2" "/org/freedesktop/UDisks2"
    "org.freedesktop.DBus.ObjectManager" "InterfacesRemoved"
    #'(lambda(path _props)
        (message "Removed storage %s" path)
        (emacsvox-icon 'close-object)))))

(defun emacsvox-dbus-udisks-enable()
  "Enable integration with UDisks2. Does nothing if already enabled."
  (interactive)
  
  (unless emacsvox-dbus-udisks-registration
    (setq emacsvox-dbus-udisks-registration
          (emacsvox-dbus-udisks-register))))

;; Disable integration
(defun emacsvox-dbus-udisks-disable()
  "Disable integration with UDisks2 daemon. Does nothing if
already disabled."
  (interactive)
  
  (while emacsvox-dbus-udisks-registration
    (dbus-unregister-object (car emacsvox-dbus-udisks-registration))
    (setq emacsvox-dbus-udisks-registration
          (cdr emacsvox-dbus-udisks-registration))))

;;;  UPower:

(defvar emacsvox-dbus-upower-registration nil
  "List holding storage (UPower) registration.")

(defun emacsvox-dbus-upower-register()
  "Register signal handlers for UPower  InterfacesAdded signal."
  (list
   (dbus-register-signal ; DeviceAdded
    :system
    "org.freedesktop.UPower" "/org/freedesktop/UPower"
    "org.freedesktop.UPower" "DeviceAdded"
    #'(lambda(device)
        (emacsvox-icon 'on)
        (message "Added device %s" device)))
   (dbus-register-signal
    :system
    "org.freedesktop.UPower" "/org/freedesktop/UPower"
    "org.freedesktop.UPower" "DeviceRemoved"
    #'(lambda(device)
        (message "Removed device  %s" device)
        (emacsvox-icon 'off)))
   (dbus-register-signal
    :system
    "org.freedesktop.UPower" "/org/freedesktop/UPower"
    "org.freedesktop.DBus.Properties.PropertiesChanged" "OnBattery"
    #'(lambda(state)
        (emacsvox-icon 'on)
        (message "Battery State:  %s" state)))))

(defun emacsvox-dbus-upower-enable()
  "Enable integration with UPower. Does nothing if already enabled."
  (interactive)
  
  (unless emacsvox-dbus-upower-registration
    (setq emacsvox-dbus-upower-registration
          (emacsvox-dbus-upower-register))))

;; Disable integration
(defun emacsvox-dbus-upower-disable()
  "Disable integration with UPower daemon. Does nothing if
already disabled."
  (interactive)
  
  (while emacsvox-dbus-upower-registration
    (dbus-unregister-object (car emacsvox-dbus-upower-registration))
    (setq emacsvox-dbus-upower-registration
          (cdr emacsvox-dbus-upower-registration))))

;;;  Interactive Command: Lock Screen
(defun emacsvox-dbus-lock-screen ()
  "Lock screen using DBus."
  (interactive)
  (emacsvox-dbus-screensaver-check)
  (emacsvox-icon 'close-object)
  (emacsvox-icon 'locking-up)
  (when (featurep 'light) (light-black))
  (dbus-call-method
   :session
   "org.gnome.ScreenSaver"
   "/"
   "org.gnome.ScreenSaver"
   "Lock"))

(global-set-key (kbd "C-, C-d") 'emacsvox-dbus-lock-screen)

;;;  Watch Screen Lock:

(defvar emacsvox-dbus-screen-lock-handle nil
  "Handle to DBus signal registration for watching screenlock.")

(defun emacsvox-dbus-watch-screen-lock ()
  "Register a handler to watch screen lock/unlock."
  (cl-declare (special emacsvox-dbus-screen-lock-handle
                       emacsvox-screen-saver-saved-conf))
  (setq
   emacsvox-dbus-screen-lock-handle
   (dbus-register-signal
    :session
    "org.gnome.ScreenSaver" "/org/gnome/ScreenSaver"
    "org.gnome.ScreenSaver" "ActiveChanged"
    #'(lambda (lock)
        (if lock
            (progn (emacsvox-screen-saver))
          (progn(emacsvox-icon 'desktop-login)
                (emacsvox-icon 'success)
                (emacsvox-orca-toggle)
                (light-black)
                (when (eq major-mode 'emacsvox-screen-saver-mode)(quit-window))
                (when
                    (window-configuration-p emacsvox-screen-saver-saved-conf)
                  (set-window-configuration
                   emacsvox-screen-saver-saved-conf))
                (emacsvox-speak-mode-line)))))))

(defun emacsvox-dbus-unwatch-screen-lock ()
  "De-Register a handler to watch screen lock/unlock."
  
  (dbus-unregister-object emacsvox-dbus-screen-lock-handle)
  (setq emacsvox-dbus-screen-lock-handle nil))

;;; Setup:
;;;###autoload
(defun emacsvox-dbus-setup ()
  "Turn on DBus handlers."
  (require 'dbus)
  (when (dbus-list-known-names :session)
    (nm-enable)
    (emacsvox-dbus-sleep-enable)
    (emacsvox-dbus-udisks-enable)
    (emacsvox-dbus-upower-enable)
    (emacsvox-dbus-watch-screen-lock)))

(provide 'emacsvox-dbus)
;;;  end of file

