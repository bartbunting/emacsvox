;;; emacsvox-calendar.el --- Speech enable Calendar -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:  Emacsvox extensions to speech enable the calendar.
;; Keywords: Emacsvox, Calendar, Spoken Output
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
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:
;; This module speech enables the Emacs Calendar.  Speech enabling is
;; not the same as speaking the screen: This is an excellent example
;; of the advantages of speech-enabled interaction.
;;; Code:

;;  required modules
;;; Code:
(require 'emacsvox-preamble)
(require 'calendar)
(require 'solar)
(require 'g-utils)
(require 'appt)

;;;   personalities
(voice-setup-add-map
 '(
   (calendar-today voice-bolden)
   (holiday voice-brighten-extra)
   (diary voice-bolden)
   ))

(defvar emacsvox-calendar-mark-personality voice-bolden
  "Personality to use when showing marked calendar entries.")

;;;   functions:
(defun emacsvox-calendar-sort-diary-entries ()
  "Sort entries in diary entries list."
  
  (when(and  (boundp 'diary-entries-list)
             diary-entries-list)
    (setq diary-entries-list
          (sort  diary-entries-list
                 #'(lambda (a b)
                     (string-lessp (cadr a) (cadr b)))))))

(defun emacsvox-calendar-entry-marked-p()
  "Check if diary entry is marked. "
  (memq 'diary
        (delq nil
              (mapcar
               #'(lambda (overlay)
                   (overlay-get overlay 'face))
               (overlays-at (point))))))

(defun emacsvox-calendar-speak-date()
  "Speak the date under point when called in Calendar Mode. "
  (interactive)
  (let ((date (calendar-date-string (calendar-cursor-to-date t))))
    (tts-with-punctuations
     'some
     (cond
      ((emacsvox-calendar-entry-marked-p)
       (dtk-speak-using-voice emacsvox-calendar-mark-personality date))
      (t (tts-speak date))))))

;;;   Advice:

(defun emacsvox--advice-calendar-exchange-point-and-mark-after (&rest _)
  "Speak the date after interactively exchanging point and mark."
  (when (ems-interactive-p 'calendar-exchange-point-and-mark)
    (emacsvox-icon 'large-movement) (emacsvox-calendar-speak-date)))

(advice-add
 'calendar-exchange-point-and-mark :after
 #'emacsvox--advice-calendar-exchange-point-and-mark-after
 '((name . emacsvox)))

(defun emacsvox--advice-calendar-set-mark-after (&rest _)
  "Speak the date after interactively setting the Calendar mark."
  (when (ems-interactive-p 'calendar-set-mark)
    (emacsvox-icon 'mark-object) (emacsvox-calendar-speak-date)))

(advice-add
 'calendar-set-mark :after #'emacsvox--advice-calendar-set-mark-after
 '((name . emacsvox)))

(add-hook 'calendar-mode-hook
          'emacsvox-calendar-setup)

(cl-loop
 for target in
 '(diary-fancy-display diary-simple-display diary-list-entries)
 for function = (intern (format "emacsvox--advice-%s-around" target))
 do
 (eval
  `(progn
     (defun ,function (orig-fun &rest args)
       "Control spoken messages while displaying diary entries."
       (let ((emacsvox-speak-messages
              (not (ems-interactive-p ',target))))
         (apply orig-fun args)))
     (advice-add
      ',target :around #',function '((name . emacsvox))))))

(defun emacsvox--advice-diary-view-entries-after (&rest _)
  "Speak the diary entries."
  (when (ems-interactive-p 'diary-view-entries)
    (ems-with-messages-silenced
     (cond
      ((buffer-live-p (get-buffer "*Fancy Diary Entries*"))
       (save-current-buffer
         (set-buffer "*Fancy Diary Entries*")
         (tts-with-punctuations "some" (emacsvox-speak-buffer))))
      (t (tts-speak "No diary entries."))))))

(advice-add
 'diary-view-entries :after #'emacsvox--advice-diary-view-entries-after
 '((name . emacsvox)))

(defun emacsvox--advice-calendar-mark-visible-date-after (date &rest _)
  "Apply the Calendar mark personality to DATE."
  (when (calendar-date-is-valid-p date)
    (save-current-buffer
      (set-buffer calendar-buffer)
      (calendar-cursor-to-visible-date date)
      (with-silent-modifications
        (put-text-property (1- (point)) (1+ (point)) 'personality
                           emacsvox-calendar-mark-personality)))))

(advice-add
 'calendar-mark-visible-date :after
 #'emacsvox--advice-calendar-mark-visible-date-after
 '((name . emacsvox)))

(defvar emacsvox-calendar-mode-line-format
  '((calendar-date-string (calendar-current-date))  "Calendar")
  "Mode line format for calendar  with Emacsvox.")

(defvar emacsvox-calendar-header-line-format
  '((:eval (calendar-date-string (calendar-cursor-to-date t))))
  "Header line used by Emacsvox in calendar.")

(cl-declaim (special calendar-mode-line-format))
(setq calendar-mode-line-format
      emacsvox-calendar-mode-line-format)

(defun emacsvox--advice-calendar-after (&rest _)
  "Announce yourself."
  (when (ems-interactive-p 'calendar)
    (emacsvox-icon 'open-object)
    (when emacsvox-use-header-line
      (setq header-line-format
            '((:eval
               (calendar-date-string (calendar-cursor-to-date t))))))
    (setq calendar-mode-line-format
          emacsvox-calendar-mode-line-format)
    (tts-with-punctuations 'some (emacsvox-speak-mode-line))))

(advice-add
 'calendar :after #'emacsvox--advice-calendar-after
 '((name . emacsvox)))

(defun emacsvox--advice-calendar-goto-date-after (&rest _)
  "Speak after interactively going to a date."
  (when (ems-interactive-p 'calendar-goto-date)
    (emacsvox-calendar-speak-date))
  (emacsvox-icon 'select-object))

(advice-add
 'calendar-goto-date :after #'emacsvox--advice-calendar-goto-date-after
 '((name . emacsvox)))

(defun emacsvox--advice-calendar-goto-today-after (&rest _)
  "Speak after interactively going to today."
  (when (ems-interactive-p 'calendar-goto-today)
    (emacsvox-calendar-speak-date))
  (emacsvox-icon 'select-object))

(advice-add
 'calendar-goto-today :after #'emacsvox--advice-calendar-goto-today-after
 '((name . emacsvox)))

(cl-loop
 for (target icon) in
 '((calendar-backward-day select-object)
   (calendar-forward-day select-object)
   (calendar-backward-week paragraph)
   (calendar-forward-week paragraph)
   (calendar-backward-month section)
   (calendar-forward-month section)
   (calendar-backward-year large-movement)
   (calendar-forward-year large-movement)
   (calendar-beginning-of-week paragraph)
   (calendar-beginning-of-month section)
   (calendar-beginning-of-year large-movement)
   (calendar-end-of-week paragraph)
   (calendar-end-of-month section)
   (calendar-end-of-year large-movement))
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Speak and cue an interactive Calendar movement."
       (when (ems-interactive-p ',target)
         (emacsvox-calendar-speak-date)
         (emacsvox-icon ',icon)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-calendar-exit-after (&rest _)
  "Cue an interactive Calendar exit and speak the resulting mode line."
  (when (ems-interactive-p 'calendar-exit)
    (emacsvox-icon 'close-object)
    (emacsvox-speak-mode-line)))

(advice-add
 'calendar-exit :after #'emacsvox--advice-calendar-exit-after
 '((name . emacsvox)))

(defun emacsvox--advice-diary-insert-block-entry-before (&rest _)
  "Describe the date range before interactively inserting a diary block."
  (when (ems-interactive-p 'diary-insert-block-entry)
    (let*
        ((cursor (calendar-cursor-to-date t))
         (mark
          (or (car calendar-mark-ring)
              (error "No mark set in this buffer")))
         (start) (end))
      (if
          (< (calendar-absolute-from-gregorian mark)
             (calendar-absolute-from-gregorian cursor))
          (setq start mark end cursor)
        (setq start cursor end mark))
      (emacsvox-icon 'open-object)
      (message "Block diary entry from  %s to %s"
               (calendar-date-string start nil t)
               (calendar-date-string end nil t)))))

(advice-add
 'diary-insert-block-entry :before
 #'emacsvox--advice-diary-insert-block-entry-before
 '((name . emacsvox)))

(defvar emacsvox-calendar-user-input nil
  "Records last user input to calendar")

(defun emacsvox--advice-calendar-read-around (orig-fun &rest args)
  "Record and return the value read by ORIG-FUN."
  (let ((result (apply orig-fun args)))
    (setq emacsvox-calendar-user-input result)
    result))

(advice-add
 'calendar-read :around #'emacsvox--advice-calendar-read-around
 '((name . emacsvox)))

(defun emacsvox--advice-diary-insert-anniversary-entry-before (&rest _)
  "Describe an interactively inserted anniversary diary entry."
  (when (ems-interactive-p 'diary-insert-anniversary-entry)
    (emacsvox-icon 'open-object)
    (message "Anniversary entry for %s"
             (calendar-date-string (calendar-cursor-to-date)))))

(advice-add
 'diary-insert-anniversary-entry :before
 #'emacsvox--advice-diary-insert-anniversary-entry-before
 '((name . emacsvox)))

(defun emacsvox--advice-diary-insert-cyclic-entry-after (&rest _)
  "Describe an interactively inserted cyclic diary entry."
  (when (ems-interactive-p 'diary-insert-cyclic-entry)
    (emacsvox-icon 'open-object)
    (message "Insert cyclic diary entry that repeats every\n%s days"
             emacsvox-calendar-user-input)))

(advice-add
 'diary-insert-cyclic-entry :after
 #'emacsvox--advice-diary-insert-cyclic-entry-after
 '((name . emacsvox)))

(defun emacsvox--advice-diary-insert-entry-after (&rest _)
  "Speak an interactively inserted diary entry."
  (when (ems-interactive-p 'diary-insert-entry)
    (emacsvox-icon 'open-object) (emacsvox-speak-line)))

(advice-add
 'diary-insert-entry :after #'emacsvox--advice-diary-insert-entry-after
 '((name . emacsvox)))

(defun emacsvox--advice-diary-insert-weekly-entry-before (&rest _)
  "Describe an interactively inserted weekly diary entry."
  (when (ems-interactive-p 'diary-insert-weekly-entry)
    (emacsvox-icon 'open-object)
    (message "Weekly diary entry for %s"
             (calendar-day-name (calendar-cursor-to-date t)))))

(advice-add
 'diary-insert-weekly-entry :before
 #'emacsvox--advice-diary-insert-weekly-entry-before
 '((name . emacsvox)))

(defun emacsvox--advice-diary-insert-yearly-entry-before (&rest _)
  "Describe an interactively inserted yearly diary entry."
  (when (ems-interactive-p 'diary-insert-yearly-entry)
    (emacsvox-icon 'open-object)
    (message "Yearly diary entry for %s %s"
             (calendar-month-name
              (cl-first (calendar-cursor-to-date t)))
             (cl-second (calendar-cursor-to-date t)))))

(advice-add
 'diary-insert-yearly-entry :before
 #'emacsvox--advice-diary-insert-yearly-entry-before
 '((name . emacsvox)))

(defun emacsvox--advice-diary-insert-monthly-entry-before (&rest _)
  "Describe an interactively inserted monthly diary entry."
  (when (ems-interactive-p 'diary-insert-monthly-entry)
    (emacsvox-icon 'open-object)
    (message "Monthly diary entry for %s"
             (cl-second (calendar-cursor-to-date t)))))

(advice-add
 'diary-insert-monthly-entry :before
 #'emacsvox--advice-diary-insert-monthly-entry-before
 '((name . emacsvox)))

(defun emacsvox--advice-calendar-cursor-holidays-after (&rest _)
  "Speak holidays displayed by an interactive Calendar command."
  (when (ems-interactive-p 'calendar-cursor-holidays)
    (emacsvox-speak-message-again)))

(advice-add
 'calendar-cursor-holidays :after
 #'emacsvox--advice-calendar-cursor-holidays-after
 '((name . emacsvox)))

(defun emacsvox--advice-diary-mark-entries-around (orig-fun &rest args)
  "Run ORIG-FUN once with spoken messages silenced."
  (ems-with-messages-silenced
   (apply orig-fun args)))

(advice-add
 'diary-mark-entries :around #'emacsvox--advice-diary-mark-entries-around
 '((name . emacsvox)))

;;;  Global sunrise/sunset wizard:

(defun emacsvox-calendar-sunrise-sunset (address &optional arg)
  "Display sunrise/sunset for specified address."
  (interactive
   (list
    (read-from-minibuffer "Address: ")
    current-prefix-arg))
  (cl-declare (special calendar-standard-time-zone-name
                       calendar-longitude calendar-latitude))
  (let* ((geo (gmaps-address-geocode address))
         (calendar-latitude (g-json-get 'lat geo))
         (calendar-longitude (g-json-get 'lng geo))
         (calendar-time-zone
          (solar-get-number
           "Enter difference from Coordinated Universal Time (in minutes): "))
         (calendar-standard-time-zone-name
          (cond ((zerop calendar-time-zone) "UTC")
                ((< calendar-time-zone 0)
                 (format "UTC%dmin" calendar-time-zone))
                (t (format "UTC+%dmin" calendar-time-zone))))
         (date (if arg (calendar-read-date) (calendar-current-date)))
         (date-string (calendar-date-string date t))
         (time-string (solar-sunrise-sunset-string date)))
    (message "%s: %s at %s" date-string time-string address)))

;;;   keymap

(defun emacsvox-calendar-setup()
  "Set up appropriate bindings for calendar"
  
  (save-current-buffer
    (set-buffer calendar-buffer)
    (local-unset-key emacsvox-prefix)
    (define-key calendar-mode-map (kbd "gG") 'emacsvox-google-search-before)
    (define-key calendar-mode-map (kbd "gg") 'emacsvox-google-search-after)
    (define-key calendar-mode-map "v" 'view-diary-entries)
    (define-key calendar-mode-map "\M-s" 'emacsvox-calendar-sunrise-sunset)
    (define-key calendar-mode-map  "\C-e." 'emacsvox-calendar-speak-date)
    (define-key calendar-mode-map  "\C-ee"
                'calendar-end-of-week)))

(define-key calendar-mode-map (kbd "gy") 'emacsvox-empv-yt-after)
(define-key calendar-mode-map (kbd "gY") 'emacsvox-empv-yt-before)
;;;   Appointments:

;;;  take over and speak the appointment

;; For the present, we just take over and speak the appointment.

(cl-declaim (special appt-display-duration))
(setq appt-display-duration 90)

(defun emacsvox-appt-speak-appointment (minutes-left new-time message)
  "Speak the appointment in addition to  displaying it visually."
  (emacsvox-icon 'alarm)
  (message "You have an appointment in %s minutes. %s"
           minutes-left message)
  (appt-disp-window minutes-left new-time  message))

(defun emacsvox-appt-delete-display ()
  "Function to delete appointment message"
  
  (and (get-buffer appt-buffer-name)
       (save-current-buffer
         (set-buffer appt-buffer-name)
         (erase-buffer))))

(cl-declaim (special appt-delete-window
                     appt-disp-window-function))

(setq appt-disp-window-function 'emacsvox-appt-speak-appointment)
(setq appt-delete-window 'emacsvox-appt-delete-display)

(defun emacsvox-appt-repeat-announcement ()
  "Speaks the most recently displayed appointment message if any."
  (interactive)
  
  (let  ((appt-buffer (get-buffer appt-buffer-name)))
    (cond
     (appt-buffer
      (save-current-buffer
        (set-buffer  appt-buffer)
        (if (= (point-min) (point-max))
            (message  "No appointments are currently displayed")
          (tts-speak (buffer-string)))))
     (t (message "You have no appointments ")))))

(defun emacsvox--advice-appt-add-after (time message &rest _)
  "Confirm that the alarm got set."
  (when (ems-interactive-p 'appt-add)
    (message "Set alarm %s at %s" message time)))

(advice-add
 'appt-add :after #'emacsvox--advice-appt-add-after
 '((name . emacsvox)))

;;;  Use GWeb if available for configuring sunrise/sunset coords

(defun emacsvox-calendar-setup-sunrise-sunset ()
  "Set up geo-coordinates using Google Maps reverse geocoding.
To use, configure variable gmaps-my-address via M-x customize-variable."
  (interactive)
  (cl-declare (special  gmaps-my-address gmaps-my-location
                        calendar-latitude calendar-longitude))
  (cond
   ((null gmaps-my-location)
    (message "First customize gmaps-my-address."))
   (t
    (setq
     calendar-latitude
     (g-json-get 'lat (gmaps-address-geocode gmaps-my-address))
     calendar-longitude
     (g-json-get 'lng (gmaps-address-geocode gmaps-my-address))))))

(defun emacsvox--advice-calendar-sunrise-sunset-around (orig-fun &rest args)
  "Like calendar's sunrise-sunset, but speaks location intelligently."
  (cond
   ((and (boundp 'gmaps-my-address) gmaps-my-address
         (ems-interactive-p 'calendar-sunrise-sunset))
    (let ((date (calendar-cursor-to-date t)))
      (message "%s at %s"
               (solar-sunrise-sunset-string date 'nolocation)
               gmaps-my-address)))
   (t (apply orig-fun args))))

(advice-add
 'calendar-sunrise-sunset :around
 #'emacsvox--advice-calendar-sunrise-sunset-around
 '((name . emacsvox)))

;;;  Lunar Phases

(cl-loop
 for target in '(calendar-lunar-phases lunar-phases)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Speak lunar phases displayed by an interactive Calendar command."
       (when (ems-interactive-p ',target)
         (with-current-buffer lunar-phases-buffer
           (emacsvox-icon 'open-object)
           (emacsvox-speak-buffer))))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(cl-loop
 for target in '(holidays calendar-list-holidays)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Speak holidays displayed by an interactive Calendar command."
       (when (ems-interactive-p ',target)
         (with-current-buffer holiday-buffer
           (emacsvox-icon 'open-object)
           (emacsvox-speak-buffer))))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(provide 'emacsvox-calendar)
;;;  emacs local variables
