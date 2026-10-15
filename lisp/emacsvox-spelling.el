;;; emacsvox-spelling.el --- Spelling feedback settings -*- lexical-binding: t; -*-

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
;; Independent spelling voice, tone and earcon controls with tone adjustment.
;; Changes apply to the current session; saving startup defaults is explicit.

;;; Code:
(require 'emacsvox-aural-menu)
(require 'emacsvox-flyspell)

(defconst emacsvox-spelling--options
  '(emacsvox-flyspell-use-voice emacsvox-flyspell-use-tone
    emacsvox-flyspell-use-earcon emacsvox-flyspell-tone-pitch
    emacsvox-flyspell-tone-duration)
  "Global spelling feedback options saved by this menu.")

(defun emacsvox-spelling--say (text)
  "Announce TEXT as interruptible menu feedback."
  (emacsvox-transient--submit-text
   text (emacsvox-transient--menu-facts 'spelling 'command-menu-value-changed)
   'state-change 'select-object))

(defun emacsvox-spelling--label (symbol label)
  "Describe boolean SYMBOL using LABEL."
  (format "%s: %s" label (if (default-value symbol) "on" "off")))

(defun emacsvox-spelling--toggle (symbol label)
  "Toggle global SYMBOL and announce LABEL with its new value."
  (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
  (set-default symbol (not (default-value symbol)))
  (emacsvox-spelling--say (emacsvox-spelling--label symbol label)))

(defun emacsvox-spelling--voice ()
  "Toggle mapped spelling voices during reading; other voice styling remains."
  (interactive)
  (emacsvox-spelling--toggle 'emacsvox-flyspell-use-voice "Voice"))
(defun emacsvox-spelling--tone ()
  "Toggle the spelling tone independently of voice and earcon feedback."
  (interactive)
  (emacsvox-spelling--toggle 'emacsvox-flyspell-use-tone "Tone"))
(defun emacsvox-spelling--earcon ()
  "Toggle the help earcon independently of voice and tone feedback."
  (interactive)
  (emacsvox-spelling--toggle 'emacsvox-flyspell-use-earcon "Earcon"))

(defun emacsvox-spelling--number (symbol label units minimum maximum step &optional direction)
  "Set SYMBOL exactly or by DIRECTION times STEP, within MINIMUM and MAXIMUM.
Announce LABEL and UNITS after validating the value."
  (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
  (let* ((old (default-value symbol))
         (value (if direction (min maximum (max minimum (+ old (* step direction))))
                  (emacsvox-aural-menu--read-number
                   (format "%s in %s (%s–%s): " label units minimum maximum) old))))
    (unless (and (numberp value) (<= minimum value maximum))
      (user-error "%s must be between %s and %s" label minimum maximum))
    (set-default symbol value)
    (emacsvox-spelling--say (format "%s %s" value units))))

(defun emacsvox-spelling--pitch (&optional direction)
  "Set spelling pitch, or adjust by DIRECTION times 25 Hz. Range: 50–10000 Hz."
  (interactive)
  (emacsvox-spelling--number 'emacsvox-flyspell-tone-pitch "Pitch" "Hz" 50 10000 25 direction))
(defun emacsvox-spelling--duration (&optional direction)
  "Set spelling duration, or adjust by DIRECTION times 5 ms. Range: 5–1000 ms."
  (interactive)
  (emacsvox-spelling--number 'emacsvox-flyspell-tone-duration "Duration" "milliseconds" 5 1000 5 direction))

(defun emacsvox-spelling--sample ()
  "Return sample text with one flagged word for private preview."
  (let ((text (copy-sequence "This mispeled word needs checking.")))
    (add-text-properties 5 13 '(emacsvox-flyspell-word (5 13) personality voice-bolden) text)
    text))

(defun emacsvox-spelling--preview ()
  "Read a sample with the selected feedback at its flagged word.
Preview does not change Flyspell, edit your text, or save settings."
  (interactive)
  (with-current-buffer (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
    (tts-speak (emacsvox-spelling--sample))))

(defun emacsvox-spelling--preview-tone ()
  "Play the adjusted tone alone, even when spelling tones are disabled."
  (interactive)
  (with-current-buffer (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
    (let ((emacsvox-flyspell-use-tone t) (emacsvox-flyspell-use-earcon nil))
      (emacsvox-aural-submit-actions
       :facts (emacsvox-flyspell--facts) :module 'flyspell :occasion 'inspection
       :lane 'main :interruption-policy 'lane))))

(defun emacsvox-spelling--save ()
  "Save global spelling controls and shared main-tone volume across restarts."
  (interactive)
  (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
  (dolist (symbol (append emacsvox-spelling--options '(tts-main-tone-volume)))
    (customize-save-variable symbol (default-value symbol)))
  (emacsvox-spelling--say "Saved spelling settings and shared tone volume"))

(defun emacsvox-spelling--adjust (direction)
  "Adjust the selected numeric control in DIRECTION."
  (let ((command (with-selected-window (emacsvox-transient--navigation-window)
                   (when-let* ((button (button-at (point))))
                     (oref (button-get button 'button-data) command)))))
    (pcase command
      ('emacsvox-spelling--pitch (emacsvox-spelling--pitch direction))
      ('emacsvox-spelling--duration (emacsvox-spelling--duration direction))
      ('emacsvox-aural-menu--main-tones
       (emacsvox-aural-menu--output-volume 'tts-main-tone-volume (* 5 direction)))
      (_ (user-error "Choose Pitch, Duration or Shared tone volume first")))))
(defun emacsvox-spelling--decrease ()
  "Decrease the selected numeric control." (interactive) (emacsvox-spelling--adjust -1))
(defun emacsvox-spelling--increase ()
  "Increase the selected numeric control." (interactive) (emacsvox-spelling--adjust 1))

(defun emacsvox-spelling--bindings (map)
  "Add shifted-arrow adjustments to spelling menu MAP."
  (when (and transient--prefix (eq (oref transient--prefix command) 'emacsvox-spelling))
    (keymap-set map "S-<left>" #'emacsvox-spelling--decrease)
    (keymap-set map "S-<right>" #'emacsvox-spelling--increase))
  map)
(advice-add 'transient--make-transient-map :filter-return #'emacsvox-spelling--bindings)
(define-key transient-predicate-map [emacsvox-spelling--decrease] #'transient--do-stay)
(define-key transient-predicate-map [emacsvox-spelling--increase] #'transient--do-stay)

;;;###autoload
(transient-define-prefix emacsvox-spelling ()
  "Choose global spelling feedback and adjust its tone.
Voice, tone and earcon combine independently. All off silences spelling
feedback without disabling Flyspell. Voice changes apply while reading;
tone and earcon also report errors detected while editing. Settings apply
immediately; S saves across restarts. Volume affects all main-stream tones."
  :refresh-suffixes t
  ["Spelling feedback (global; combine any)"
   ("v" (lambda () (emacsvox-spelling--label 'emacsvox-flyspell-use-voice "Voice")) emacsvox-spelling--voice :transient t)
   ("t" (lambda () (emacsvox-spelling--label 'emacsvox-flyspell-use-tone "Tone")) emacsvox-spelling--tone :transient t)
   ("e" (lambda () (emacsvox-spelling--label 'emacsvox-flyspell-use-earcon "Earcon")) emacsvox-spelling--earcon :transient t)]
  ["Tone adjustment (Shift arrows adjust selected control)"
   ("p" (lambda () (format "Pitch: %s Hz" emacsvox-flyspell-tone-pitch)) emacsvox-spelling--pitch :transient t)
   ("d" (lambda () (format "Duration: %s milliseconds" emacsvox-flyspell-tone-duration)) emacsvox-spelling--duration :transient t)
   ("V" (lambda () (format "Shared tone volume: %s percent" tts-main-tone-volume)) emacsvox-aural-menu--main-tones :transient t)
   ("b" "Preview tone alone" emacsvox-spelling--preview-tone :transient t)]
  ["Preview and save"
   ("SPC" "Read spelling sample" emacsvox-spelling--preview :transient t)
   ("S" "Save global settings" emacsvox-spelling--save :transient t)
   ("q" "Back (keep session changes)" transient-quit-one)
   ("C-q" "Close all menus" transient-quit-all)]
  (interactive)
  (let* ((prefix (or transient--prefix transient-current-prefix))
         (context (if (and prefix (eq (oref prefix command) 'emacsvox-aural-menu-speech))
                      (oref prefix scope) (emacsvox-aural-menu--capture nil))))
    (emacsvox-aural-menu--source context)
    (transient-setup 'emacsvox-spelling nil nil :scope context)))

(provide 'emacsvox-spelling)
;;; emacsvox-spelling.el ends here
