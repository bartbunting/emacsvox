;;; emacsvox-indentation.el --- Indentation feedback menu -*- lexical-binding: t; -*-

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

;; Choose indentation feedback, timing, and shared tone volume with Transient.

;;; Code:

(require 'cus-edit)
(require 'emacsvox-speak)
(require 'emacsvox-transient)

(defun emacsvox-indentation--state ()
  "Return the active menu's source buffer and global scope flag."
  (let ((prefix (or transient--prefix transient-current-prefix)))
    (unless (and prefix (eq (oref prefix command) 'emacsvox-indentation))
      (user-error "Open the indentation menu first"))
    (oref prefix scope)))

(defun emacsvox-indentation--source ()
  "Return the menu's live source buffer."
  (let ((source (car (emacsvox-indentation--state))))
    (unless (buffer-live-p source)
      (user-error "The indentation source buffer has been closed"))
    source))

(defun emacsvox-indentation--value (symbol)
  "Read SYMBOL in the selected scope."
  (if (cdr (emacsvox-indentation--state))
      (default-value symbol)
    (buffer-local-value symbol (emacsvox-indentation--source))))

(defun emacsvox-indentation--say (text)
  "Speak menu feedback TEXT, interrupting previous main speech."
  (with-current-buffer (emacsvox-indentation--source)
    (let ((toggle (get-text-property 0 'emacsvox-transient-toggle-state text)))
      (emacsvox-transient--submit-text
       text
       (emacsvox-transient--item-facts
        'value 'indentation 'command-menu-value-changed
        (unless (eq toggle 'off) '(selected)))
       'state-change (or toggle 'select-object)))))

(defun emacsvox-indentation--set (symbol value label)
  "Set SYMBOL to VALUE in the selected scope and announce LABEL."
  (with-current-buffer (emacsvox-indentation--source)
    (if (cdr (emacsvox-indentation--state))
        (set-default symbol value)
      (set (make-local-variable symbol) value)))
  (emacsvox-indentation--say label))

(defun emacsvox-indentation--choice (symbol value label)
  "Describe LABEL, marking it selected when SYMBOL equals VALUE."
  (if (eq (emacsvox-indentation--value symbol) value)
      (propertize (concat label " (selected)")
                  emacsvox-aural-facts-property '(:states (selected)))
    label))

(defun emacsvox-indentation--tonal-p ()
  "Return non-nil when the selected presentation includes a built-in tone."
  (memq (emacsvox-indentation--value 'emacsvox-indentation-presentation)
        '(pitch-tone duration-tone spoken-pitch-tone spoken-duration-tone)))

(defun emacsvox-indentation--scope ()
  "Switch between current-buffer settings and global defaults."
  (interactive)
  (let ((state (emacsvox-indentation--state)))
    (setcdr state (not (cdr state)))
    (emacsvox-indentation--say
     (if (cdr state) "Editing global defaults" "Editing current buffer"))))

(defun emacsvox-indentation--toggle ()
  "Toggle indentation feedback in the selected scope."
  (interactive)
  (let ((enabled (not (emacsvox-indentation--value 'emacsvox-audio-indentation))))
    (emacsvox-indentation--set 'emacsvox-audio-indentation enabled
                              (propertize
                               (if enabled "Indentation on" "Indentation off")
                               'emacsvox-transient-toggle-state
                               (if enabled 'on 'off)))))

(defun emacsvox-indentation--preview ()
  "Preview four-column indentation using the settings shown in the menu."
  (interactive)
  (let ((presentation (emacsvox-indentation--value 'emacsvox-indentation-presentation))
        (timing (emacsvox-indentation--value 'emacsvox-indentation-tone-timing)))
    (with-current-buffer (emacsvox-indentation--source)
      (let ((emacsvox-audio-indentation t)
            (emacsvox-indentation-presentation presentation)
            (emacsvox-indentation-tone-timing timing))
        (emacsvox-speak--preview-indentation-presentation)))))

(defun emacsvox-indentation--volume (&optional delta)
  "Set global tone volume, or adjust it by DELTA percentage points."
  (interactive)
  (emacsvox-indentation--source)
  (let ((value (if delta
                   (max 0 (min 100 (+ (default-value 'tts-main-tone-volume) delta)))
                 (read-number "Global tone volume (0 to 100): "
                              (default-value 'tts-main-tone-volume)))))
    (tts--validate-output-volume value)
    (customize-set-variable 'tts-main-tone-volume value)
    (emacsvox-indentation--say (format "%d percent" value))))

(defun emacsvox-indentation--save ()
  "Save global indentation defaults and main-stream tone volume."
  (interactive)
  (emacsvox-indentation--source)
  (unless (cdr (emacsvox-indentation--state))
    (user-error "Switch to Global defaults before saving"))
  (dolist (symbol '(emacsvox-audio-indentation emacsvox-indentation-presentation
                   emacsvox-indentation-tone-timing tts-main-tone-volume))
    (customize-save-variable symbol (default-value symbol)))
  (emacsvox-indentation--say "Saved global indentation defaults and tone volume"))

(defun emacsvox-indentation--setup (state)
  "Open Indentation with STATE containing a source buffer and global flag.
Linked menus may share STATE so changes of scope survive parent navigation."
  (unless (buffer-live-p (car state))
    (user-error "The indentation source buffer has been closed"))
  (transient-setup 'emacsvox-indentation nil nil :scope state))

;;;###autoload
(transient-define-prefix emacsvox-indentation (&optional global)
  "Choose indentation feedback for the current buffer or global defaults.
With prefix GLOBAL, start with global defaults.  Changes apply immediately;
closing the menu keeps them.  Global changes preserve buffer-local choices.
Save defaults explicitly to retain them across sessions.  Tone volume always
affects all main-stream Omnivox tones, independently of the selected scope."
  :refresh-suffixes t
  ["Scope and feedback"
   ("g" (lambda () (if (cdr (emacsvox-indentation--state))
                       "Scope: Global defaults" "Scope: Current buffer"))
    emacsvox-indentation--scope :transient t)
   ("e" (lambda ()
          (let ((enabled (emacsvox-indentation--value 'emacsvox-audio-indentation)))
            (propertize
             (if enabled "Indentation: on" "Indentation: off")
             'emacsvox-transient-toggle-state (if enabled 'on 'off)
             emacsvox-aural-facts-property (when enabled '(:states (selected))))))
    emacsvox-indentation--toggle :transient t)]
  ["Presentation"
   ("s" (lambda () (emacsvox-indentation--choice 'emacsvox-indentation-presentation 'spoken "Spoken column"))
    (lambda () (interactive) (emacsvox-indentation--set 'emacsvox-indentation-presentation 'spoken "Spoken column")) :transient t)
   ("p" (lambda () (emacsvox-indentation--choice 'emacsvox-indentation-presentation 'pitch-tone "Pitch tone"))
    (lambda () (interactive) (emacsvox-indentation--set 'emacsvox-indentation-presentation 'pitch-tone "Pitch tone")) :transient t)
   ("d" (lambda () (emacsvox-indentation--choice 'emacsvox-indentation-presentation 'duration-tone "Duration tone"))
    (lambda () (interactive) (emacsvox-indentation--set 'emacsvox-indentation-presentation 'duration-tone "Duration tone")) :transient t)
   ("P" (lambda () (emacsvox-indentation--choice 'emacsvox-indentation-presentation 'spoken-pitch-tone "Spoken column and pitch tone"))
    (lambda () (interactive) (emacsvox-indentation--set 'emacsvox-indentation-presentation 'spoken-pitch-tone "Spoken column and pitch tone")) :transient t)
   ("D" (lambda () (emacsvox-indentation--choice 'emacsvox-indentation-presentation 'spoken-duration-tone "Spoken column and duration tone"))
    (lambda () (interactive) (emacsvox-indentation--set 'emacsvox-indentation-presentation 'spoken-duration-tone "Spoken column and duration tone")) :transient t)
   ("c" (lambda () (emacsvox-indentation--choice 'emacsvox-indentation-presentation 'custom "Personal rules"))
    (lambda () (interactive) (emacsvox-indentation--set 'emacsvox-indentation-presentation 'custom "Personal rules")) :transient t)
   ("n" (lambda () (emacsvox-indentation--choice 'emacsvox-indentation-presentation 'none "No indication"))
    (lambda () (interactive) (emacsvox-indentation--set 'emacsvox-indentation-presentation 'none "No indication")) :transient t)]
  ["Tone timing"
   ("b" (lambda () (emacsvox-indentation--choice 'emacsvox-indentation-tone-timing 'insert "Before speech"))
    (lambda () (interactive) (emacsvox-indentation--set 'emacsvox-indentation-tone-timing 'insert "Tone before speech"))
    :inapt-if-not emacsvox-indentation--tonal-p :transient t)
   ("a" (lambda () (emacsvox-indentation--choice 'emacsvox-indentation-tone-timing 'overlay "Alongside speech"))
    (lambda () (interactive) (emacsvox-indentation--set 'emacsvox-indentation-tone-timing 'overlay "Tone alongside speech"))
    :inapt-if-not emacsvox-indentation--tonal-p :transient t)]
  ["All main-stream tones (global)"
   ("v" (lambda () (format "Volume: %d percent" (default-value 'tts-main-tone-volume)))
    emacsvox-indentation--volume :transient t)
   ("-" "Volume down 5 percent" (lambda () (interactive) (emacsvox-indentation--volume -5)) :transient t)
   ("+" "Volume up 5 percent" (lambda () (interactive) (emacsvox-indentation--volume 5)) :transient t)]
  ["Try and finish"
   ("SPC" "Preview four-column indentation" emacsvox-indentation--preview :transient t)
   ("S" "Save global defaults and volume" emacsvox-indentation--save
    :inapt-if-not (lambda () (cdr (emacsvox-indentation--state))) :transient t)
   ("q" "Close (keep changes)" transient-quit-one)]
  (interactive "P")
  (emacsvox-indentation--setup (cons (current-buffer) (and global t))))

(provide 'emacsvox-indentation)
;;; emacsvox-indentation.el ends here
