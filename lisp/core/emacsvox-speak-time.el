;;; emacsvox-speak-time.el --- Time and date speech -*- lexical-binding: t; -*-

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

;; Time and date speech.
;; The core speech facade retains activation in its established order.

;;; Code:

(require 'cl-lib)
(require 'tts-speak)
(require 'emacsvox-speak-messages)
(require 'sox-gen)

(defvar ido-case-fold)
(defvar emacsvox-use-icons)
(defvar emacsvox-last-message)
(declare-function emacsvox-shell-command "emacsvox-speak" (command))
(declare-function emacsvox-speak-line "emacsvox-speak" (&optional arg))
(declare-function emacsvox-icon "emacsvox-sounds" (icon))
(declare-function calendar-cursor-to-nearest-date "cal-move" ())
(declare-function word-at-point "thingatpt" (&optional no-properties))

;;; Minibuffer Helpers:
;;;###autoload
(defun emacsvox-filter-after ()
  "Add after:today filter"
  (interactive)
  (insert (format " after:%s" (format-time-string "%Y/%m/%d")))
  (emacsvox-icon 'yank-object)
  (emacsvox-speak-line))

;;;###autoload
(defun emacsvox-filter-before ()
  "Add before:today filter"
  (interactive)
  (insert (format " before:%s" (format-time-string "%Y/%m/%d")))
  (emacsvox-icon 'yank-object)
  (emacsvox-speak-line))

;;;   Speak misc information e.g. time, version, current-kill  etc

(defcustom emacsvox-speak-time-format
  "%l %M%p on %A %B %_e"
  "Format string that specifies how the time should be spoken.
See the documentation for function
`format-time-string'"
  :group 'emacsvox
  :type 'string)

(defcustom emacsvox-speak-time-brief-format
  "%l %M"
  "Format for time in brief."
  :group 'emacsvox
  :type 'string)

(defvar emacsvox-speak-zoneinfo-directory
  "/usr/share/zoneinfo/"
  "Directory containing timezone data.")

(defun emacsvox-speak-world-clock (zone &optional set)
  "Display current date and time  for specified zone.
Optional second arg `set' sets the TZ environment variable as well."
  (interactive
   (list
    (let ((completion-ignore-case t)
          (ido-case-fold t)
          (read-file-name-completion-ignore-case t))
      (read-file-name "Timezone: " emacsvox-speak-zoneinfo-directory))
    current-prefix-arg))
  (when (and set
             (= 16 (car set)))
    ;; two interactive prefixes from caller
    (setenv "TZ" zone))
  (emacsvox-shell-command
   (format "export TZ=%s; date +\"%s\""
           zone
           (concat emacsvox-speak-time-format
                   (format
                    " in %s, %%Z, %%z "
                    (substring
                     zone
                     (length emacsvox-speak-zoneinfo-directory)))))))

(defun emacsvox-speak-brief-time ()
  "Time in brief"
  (interactive)

  (emacsvox-icon 'tick-tick)
  (emacsvox-pip (format-time-string emacsvox-speak-time-brief-format)))

(defun emacsvox-speak-time (&optional world)
  "Speak the time on the main speech stream.
The reading is also available via \\[emacsvox-view-notifications].
Optional interactive prefix arg `C-u'invokes world clock.
Timezone is specified using minibuffer completion.
Second interactive prefix sets clock to new timezone."
  (interactive "P")

  (emacsvox-icon 'time)
  (cond
   (world (call-interactively 'emacsvox-speak-world-clock))
   (t
    (let ((time-string
           (format-time-string emacsvox-speak-time-format
                               (current-time) (getenv "TZ"))))
      (emacsvox-log-notification time-string)
      (setq emacsvox-last-message time-string)
      (tts-speak time-string)))))

(defsubst ems--seconds-to-duration (sec)
  "Return seconds formatted as time if valid, otherwise return as is."
  (let ((v (car  (read-from-string sec))))
    (cond
     ((and (numberp v) (not (cl-minusp v)))
      (format-seconds "%.2h:%.2m:%.2s%z" v))
     (t sec))))

(defsubst ems--duration-to-seconds (d)
  "Convert hh:mm:ss to seconds."
  (let*
      ((sign (string-match "^-" d))
       (v
        (mapcar
         #'car
         (mapcar
          #'read-from-string
          (split-string (if sign (substring d 1) d) ":")))))
    (* (if sign -1 1)
       (+
        (* 3600 (or  (cl-first v) 0))
        (* 60 (or  (cl-second v) 0))
        (or  (cl-third v) 0)))))

(defsubst ems--format-clock (s)
  "Seconds -> mm:ss"
  (format "%02d:%02d" (floor (/ s 60)) (% (floor s) 60)))

(defun emacsvox-speak-seconds-since-epoch (seconds)
  "Speaks time value specified as seconds  since epoch."
  (interactive
   (list (read-minibuffer "Seconds: " (word-at-point))))

  (message
   (format-time-string
    emacsvox-speak-time-format (seconds-to-time seconds))))

(defun emacsvox-speak-microseconds-since-epoch (ms)
  "Speaks time value specified as microseconds  since epoch."
  (interactive
   (list (read-minibuffer "MicroSeconds: " (word-at-point))))
  (let ((seconds (/ ms 1000000)))
    (emacsvox-speak-seconds-since-epoch seconds)))

(defun emacsvox-speak-milliseconds-since-epoch (ms)
  "Speaks time value specified as milliseconds  since epoch.."
  (interactive
   (list (read-minibuffer "MilliSeconds: " (word-at-point))))
  (let ((seconds (/ ms 1000)))
    (emacsvox-speak-seconds-since-epoch seconds)))

(defun emacsvox-speak-date-as-seconds (time)
  "Read time value as a human-readable string, return seconds.
Seconds value is also placed in the kill-ring."
  (interactive "sTime: ")
  (let ((result (float-time (apply 'encode-time (parse-time-string time)))))
    (message "%s" result)
    (kill-new result)
    result))

;;;   speak message at time

(defun emacsvox-speak-message-at-time (time message)
  "Speak message at specified time.
Provides simple stop watch functionality.
See documentation for command run-at-time for details on time-spec."
  (interactive (list (read-from-minibuffer "Time specification:  ")
                     (read-from-minibuffer "Message: ")))
  (run-at-time
   time nil
   #'(lambda (m)
       (tts-notify m)
       (when emacsvox-use-icons (emacsvox-icon 'alarm))
       (sox-tones))
   message)
  (message "Set alarm for %s" time)
  (emacsvox-icon 'button))

;;;  Smart date prompe:

(defun emacsvox-speak-collect-date (prompt time-format-string)
  "Smart date collector.
Prompts with `prompt'.
`time-format-string' is format argument for format-time-string.
This function is sensitive to calendar mode when prompting."
  (let ((default (format-time-string time-format-string))) ; today is default
    (when (eq major-mode 'calendar-mode)
                                        ;get smart default from calendar
      (let ((date (calendar-cursor-to-nearest-date)))
        (setq default (format-time-string time-format-string
                                          (apply 'encode-time 0 0
                                                 0
                                                 (cl-second date)
                                                 (cl-first date)
                                                 (list (cl-third date)))))))
    (read-from-minibuffer prompt
                          default
                          nil nil nil
                          default)))

(defun emacsvox-speak-read-date-year/month/date ()
  "Return today as yyyy/mm/dd"
  (emacsvox-speak-collect-date "Date:"
                               "%Y/%m/%d"))

(defun emacsvox-speak-date-YearMonthDate ()
  "Return today as yyyymmdd"
  (emacsvox-speak-collect-date "Date:"
                               "%Y%m%d"))

(defun emacsvox-speak-date-month/date ()
  "Return today as mm/dd"
  (emacsvox-speak-collect-date "Date:"
                               "%m/%d"))

(defun emacsvox-speak-year-month-date ()
  "Return today as yyyy-mm-dd"
  (emacsvox-speak-collect-date "Date:"
                               "%Y-%m-%d"))

(provide 'emacsvox-speak-time)

;;; emacsvox-speak-time.el ends here
