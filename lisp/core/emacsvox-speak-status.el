;;; emacsvox-speak-status.el --- Buffer and system status speech -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Spoken Output
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

;; Buffer and system status speech.
;; The core speech facade retains activation in its established order.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'seq)
(require 'tts-speak)
(require 'emacsvox-speak-time)
(require 'emacsvox-speak-windows)

(defvar emacsvox-comint-autospeak)
(declare-function emacsvox-icon "emacsvox-sounds" (icon))
(declare-function which-function "which-func" ())

(defvar emacsvox-wpctl (executable-find "wpctl")
  "Location of wpctl.
Normally defined by `emacsvox-preamble'; this fallback also lets the
speech library load independently during native compilation.")
;;; Helper: Wifi ESSId:

(defsubst ems--get-essid ()
  "Return active Wifi ESSId"
  (string-trim (shell-command-to-string "iwgetid --raw")))

;;; Helper: Speak Frame Title

(defsubst emacsvox-speak-frame-title ()
  "Speak Frame Title"
  (tts-speak (cdr (assq 'name (frame-parameters))) ))

;;;  compute percentage into the buffer:

(defsubst emacsvox-get-current-percentage-into-buffer ()
  "Return percentage of position into current buffer."
  (let* ((pos (point))
         (total (buffer-size))
         (percent (if (> total 50000)
                      ;; Avoid overflow from multiplying by 100!
                      (/ (+ (/ total 200) (1- pos)) (max (/ total 100) 1))
                    (/ (+ (/ total 2) (* 100 (1- pos))) (max total 1)))))
    percent))

(defun emacsvox-get-current-percentage-verbosely ()
  "Return percentage of position into current buffer as a string."
  (let ((percent (emacsvox-get-current-percentage-into-buffer)))
    (propertize
     (cond
      ((= 0 percent) " top ")
      ((= 100 percent) " bottom ")
      (t (format " %d%% " percent)))
     'personality 'voice-monotone-extra)))

;;;  mail check

(defcustom emacsvox-mail-spool-file
  (expand-file-name
   (user-login-name)
   (if (boundp 'rmail-spool-directory)
       rmail-spool-directory
     "/usr/spool/mail/"))
  "Mail spool file examined  to alert you about newly
arrived mail."
  :type '(choice
          (const :tag "None" nil)
          (file :tag "Mail drop location"))
  :group 'emacsvox)

(defsubst emacsvox-get-file-size (filename)
  "Return file size for file FILENAME."
  (or (nth 7 (file-attributes filename)) 0))

(defvar emacsvox-mail-last-alerted-time (list 0 0)
  "Least  significant 16 digits of the time when mail alert was last issued. ")

(defun emacsvox-mail-get-last-mail-arrival-time (f)
  "Return time when mail  last arrived."
  (if (file-exists-p f)
      (nth 5 (file-attributes f))
    0))

(defcustom emacsvox-mail-alert-interval 300
  "Interval in seconds between mail alerts for the same pending
  message."
  :type 'integer
  :group 'emacsvox)

(defun emacsvox-mail-alert-user-p (f)
  "Predicate to check if we need to play an alert for the specified spool."
  (let* ((mod-time (emacsvox-mail-get-last-mail-arrival-time f))
         (size (emacsvox-get-file-size f))
         (result
          (and (> size 0)
               (or
                (null emacsvox-mail-last-alerted-time)
                (time-less-p emacsvox-mail-last-alerted-time mod-time)
                (time-less-p            ;unattended mail
                 (time-add emacsvox-mail-last-alerted-time
                           (list 0 emacsvox-mail-alert-interval))
                 (current-time))))))
    (when result
      (setq emacsvox-mail-last-alerted-time (current-time)))
    result))

(defun emacsvox-mail-alert-user ()
  "Alerts user about the arrival of new mail."

  (when (and emacsvox-mail-spool-file
             (emacsvox-mail-alert-user-p emacsvox-mail-spool-file))
    (emacsvox-icon 'new-mail)))

(defvar-local emacsvox-mail-alert t
  " If t, emacsvox will alert you about newly arrived mail
with an auditory icon when
displaying the mode line.
You can use command
`emacsvox-toggle-mail-alert' bound to
\\[emacsvox-toggle-mail-alert] to set this option. ")

(ems-generate-switcher 'emacsvox-toggle-mail-alert
                       'emacsvox-mail-alert
                       "Toggle state of  Emacsvox  mail alert.
Interactive PREFIX arg means toggle  the global default value, and then set the
current local  value to the result.
Turning on this option results in Emacsvox producing an auditory icon
indicating the arrival  of new mail when displaying the mode line.")

;;;  Mode line info collectors

(defsubst emacsvox-get-voicefied-recursion-info (level)
  "Return voicefied version of this recursive-depth level."
  (cond
   ((zerop level) nil)
   (t
    (propertize
     (format " Recursive Edit %d " level) 'personality 'voice-smoothen))))

(defsubst emacsvox-get-voicefied-frame-info (frame)
  "Return voicefied version of this frame name."
  (cond
   ((= (length (frame-list)) 1) nil)
   (t
    (propertize
     (format " %s " (frame-parameter frame 'name))
     'personality 'voice-lighten-extra ))))

;;;   Speak mode line information

;; compute current line number
(defsubst emacsvox-get-current-line-number ()
  (let ((start (point)))
    (save-excursion
      (save-restriction
        (widen)
        (goto-char (point-min))
        (+ 1 (count-lines start (point)))))))

(defun emacsvox-speak-which-function ()
  "Speak which function we are on.  Uses which-function from
which-func without turning that mode on.  "
  (interactive)
  (require 'which-func)
  (message (or (which-function) "Not inside a function.")))

(defun emacsvox-speak-buffer-info ()
  "Speak buffer information."
  (message "Buffer has %s lines and %s characters %s "
           (count-lines (point-min) (point-max))
           (- (point-max) (point-min))
           (if (= 1 (point-min))
               ""
             "with narrowing in effect. ")))

(defsubst ems--comint-autospeak nil
  "Predicate to test if comint autospeak applies."
  (and emacsvox-comint-autospeak
       (or (derived-mode-p 'comint-mode) (eq 'vterm-mode major-mode))))

(defun emacsvox-speak-mode-line (&optional buffer-info)
  "Speak the mode-line.
Speaks header-line if that is set when called non-interactively.
Interactive prefix arg speaks buffer info."
  (interactive "P")
  (with-current-buffer (window-buffer (selected-window))
    (tts-stop)
    (force-mode-line-update)
    (when
        (or
         (bound-and-true-p outline-minor-mode) (bound-and-true-p folding-mode))
      (emacsvox-icon 'ellipses))
    (when (and visual-line-mode (not global-visual-line-mode)) (sox-chime 2 2))
    (when emacsvox-mail-alert (emacsvox-mail-alert-user))
    (when (and mode-line-process
               (> (length (format-mode-line mode-line-process)) 0))
      (emacsvox-icon 'process-active))
    (cond
     ((and header-line-format (not (called-interactively-p 'interactive)))
      (emacsvox-speak-header-line))
     (buffer-info (emacsvox-speak-buffer-info))
     (t                                 ; main branch
      (let ((global-info (downcase (format-mode-line global-mode-string)))
            (window-count (length (window-list)))
            (autospeak
             (when (ems--comint-autospeak)
               (propertize "Autospeak" 'personality 'voice-lighten)))
            (vc-state
             (when (and vc-mode (buffer-file-name))
               (vc-state (buffer-file-name))))
            (frame-info (emacsvox-get-voicefied-frame-info (selected-frame)))
            (recursion-info
             (emacsvox-get-voicefied-recursion-info (recursion-depth)))
            (dir-info
             (when (or (eq major-mode 'shell-mode)
                       (eq major-mode 'comint-mode))
               (abbreviate-file-name default-directory))))
        (when (> window-count 1) (emacsvox--sox-multiwindow))
        (setq window-count ;;; int->string
              (if (> window-count 1) (format " %s " window-count) nil))
        (cond
         ((stringp mode-line-format) (tts-speak (downcase mode-line-format)))
         (t                             ;process modeline
          (unless (zerop (length global-info))
            (put-text-property
             0 (length global-info) 'personality 'voice-bolden-medium
             global-info))
;;; avoid pathological case
          (unless (and buffer-read-only (buffer-modified-p))
            (when (and buffer-file-name (buffer-modified-p))
              (emacsvox-icon 'modified-object))
            (when buffer-read-only
              (emacsvox-icon 'unmodified-object)))
          (tts-with-punctuations
           'all
           (tts-speak
            (concat
             autospeak
             dir-info
             (propertize (buffer-name) 'personality
                         'voice-lighten-medium)
             (emacsvox-get-current-percentage-verbosely)
             (when window-count
               (propertize window-count 'personality 'voice-smoothen))
             (when vc-mode
               (propertize (downcase vc-mode) 'personality 'voice-smoothen))
             (when vc-state (format " %s " vc-state))
             (when line-number-mode
               (format "line %d" (emacsvox-get-current-line-number)))
             (when column-number-mode
               (format "column %d" (current-column)))
             (propertize
              (downcase
               (format-mode-line mode-name)) 'personality 'voice-animate)
             global-info frame-info recursion-info))))))))))

(defun emacsvox-return-mode-line ()
  "Debug tool: return visually displayed mode-line as a string."
  (with-temp-buffer
    (insert (format-mode-line mode-line-format))
    (buffer-substring-no-properties (point-min) (point-max))))

(defun emacsvox-return-minor-mode-line ()
  "Debug tool: return visually displayed minor-mode-line as a string."
  (with-temp-buffer
    (insert (format-mode-line minor-mode-alist))
    (buffer-substring-no-properties (point-min) (point-max))))

(defun emacsvox-speak-current-buffer-name ()
  "Speak name of current buffer."
  (tts-with-punctuations 'all
                         (tts-speak
                          (buffer-name))))

(defconst ems--vol-cmd
  (when emacsvox-wpctl "wpctl get-volume @DEFAULT_AUDIO_SINK@")
  "Shell pipeline for getting volume.")

(defsubst ems--show-current-volume ()
  "volume display in minor-mode-line"

  (propertize
   (format " %s " (string-trim (shell-command-to-string ems--vol-cmd)))
   'personality 'voice-bolden))

(defvar emacsvox-speak-show-volume nil
  "Temporarily turned on when speaking minor-mode line.")

(defun emacsvox-speak-minor-mode-line (&optional log-msg)
  "Speak the minor mode-information.
Optional interactive prefix arg `log-msg' logs spoken info to
*Messages*."
  (interactive "P")

  (let* ((emacsvox-speak-show-volume ems--vol-cmd)
         (info (format-mode-line minor-mode-alist)))
    (when log-msg (ems--log-message info))
    (tts-with-punctuations 'some
                           (tts-speak  info))))

(defun emacsvox-speak-buffer-filename (&optional filename)
  "Speak name of file being visited in current buffer.
Speak default directory if invoked in a dired buffer, or when the
buffer is not visiting any file.  Interactive prefix arg
`filename' speaks only the final path component.  The result is
put in the kill ring for convenience."
  (interactive "P")
  (let ((tts-caps t)
        (location (or (buffer-file-name) default-directory)))
    (when filename
      (setq location (file-name-nondirectory location)))
    (kill-new location)
    (tts-speak location)))

;;;  Speak header-line

(defvar emacsvox-use-header-line t
  "Use default header line defined  by Emacsvox for buffers that
dont customize the header.")

(defvar emacsvox-header-line-format
  '((:eval (buffer-name)))
  "Default header-line-format defined by Emacsvox.
Displays name of current buffer.")

(defun emacsvox-speak-header-line ()
  "Speak header line if set."
  (interactive)
  (cond
   (header-line-format
    (let ((window-count (length (window-list))))
      (emacsvox-icon 'item)
      (when (> window-count 1) (emacsvox--sox-multiwindow))
      (tts-notify (format-mode-line header-line-format))))
   (t
    (tts-notify
     (concat
      (propertize (buffer-name) 'personality 'voice-smoothen)
      (format-time-string emacsvox-speak-time-brief-format))))))

(defun emacsvox-toggle-header-line ()
  "Toggle Emacsvox's default header line."
  (interactive)
  (if header-line-format
      (setq header-line-format nil)
    (setq header-line-format emacsvox-header-line-format))
  (emacsvox-icon (if header-line-format 'on 'off))
  (message "Turned %s default header line."
           (if header-line-format 'on 'off)))

(defvar emacsvox-battery-prev nil
  "Previous battery status.")

(defun emacsvox-battery-alarm (data)
  "Battery alarm when critical."
  (when
      (and emacsvox-battery-prev
           (string=  (alist-get ?L data) "off-line")
           (< (string-to-number (alist-get ?p data)) 10)
           (>= (string-to-number (alist-get ?p emacsvox-battery-prev)) 10))
    (emacsvox-icon 'battery-low)
    (setq emacsvox-battery-prev data)))
;;; Network Utils:

(defun ems--get-ip-address (dev)
  "get the IP-address for device DEV "
  (setq dev
        (or
         dev
         (completing-read "Dev: " (ems--get-active-network-interfaces) nil t)))
  (format-network-address (car (network-interface-info dev)) 'omit-port))

(defun ems--get-active-network-interfaces ()
  "Return  names of active network interfaces.
Filters out loopback for convenience."
  (when (fboundp 'network-interface-list)
    (seq-remove #'(lambda (d) ( string= d "lo") )
                (seq-uniq (mapcar #'car (network-interface-list))))))

(defun emacsvox-speak-net-id ()
  "Shows active network interfaces in the echo area.
 The address is also copied to the kill ring for convenient yanking."
  (interactive)
  (kill-new
   (message
    "%s: %s"
    (ems--get-essid)
    (ems--get-ip-address(cl-first  (ems--get-active-network-interfaces))))))

(provide 'emacsvox-speak-status)

;;; emacsvox-speak-status.el ends here
