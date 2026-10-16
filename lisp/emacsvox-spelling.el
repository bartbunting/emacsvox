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
(require 'emacsvox-tone-editor)

(defconst emacsvox-spelling--options
  '(emacsvox-flyspell-use-voice emacsvox-flyspell-use-tone
    emacsvox-flyspell-use-earcon emacsvox-flyspell-tone-pitch
    emacsvox-flyspell-tone-duration emacsvox-flyspell-tone-volume
    emacsvox-flyspell-tone-timing emacsvox-flyspell-tone-shape)
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

(defun emacsvox-spelling--number (symbol label units minimum maximum step &optional direction integer-only)
  "Set SYMBOL exactly or by DIRECTION times STEP, within MINIMUM and MAXIMUM.
Announce LABEL and UNITS after validating the value.
When INTEGER-ONLY is non-nil, reject fractional input."
  (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
  (let* ((old (default-value symbol))
         (value (if direction (min maximum (max minimum (+ old (* step direction))))
                  (emacsvox-aural-menu--read-number
                   (format "%s in %s (%s–%s): " label units minimum maximum) old))))
    (unless (and (numberp value) (<= minimum value maximum)
                 (or (not integer-only) (integerp value)))
      (user-error "%s must be %sbetween %s and %s"
                  label (if integer-only "an integer " "") minimum maximum))
    (set-default symbol value)
    (emacsvox-spelling--say (format "%s %s" value units))))

(defun emacsvox-spelling--pitch (&optional direction)
  "Set spelling pitch; Shift arrows change it by 25 Hz.
Range: 50–10000 Hz. From Lisp, DIRECTION counts 25 Hz steps."
  (interactive)
  (emacsvox-spelling--number 'emacsvox-flyspell-tone-pitch "Pitch" "Hz" 50 10000 25 direction))
(defun emacsvox-spelling--duration (&optional direction)
  "Set spelling duration; Shift arrows change it by 5 ms.
Range: 5–1000 ms. From Lisp, DIRECTION counts 5 ms steps."
  (interactive)
  (emacsvox-spelling--number 'emacsvox-flyspell-tone-duration "Duration" "milliseconds" 5 1000 5 direction))

(defun emacsvox-spelling--volume (&optional direction)
  "Set spelling tone volume; Shift arrows change it by 5 percentage points.
From Lisp, DIRECTION counts five-percentage-point steps.
Range: 0–100 percent. Zero silences this tone; 100 preserves its original
level. The shared main-tone volume still scales it. Older workers omit
tones below 100; Preview explains missing support without changing settings."
  (interactive)
  (emacsvox-spelling--number 'emacsvox-flyspell-tone-volume
                             "Spelling tone volume" "percent" 0 100 5 direction t))

(defun emacsvox-spelling--timing-name ()
  "Describe the selected global spelling tone timing."
  (if (eq emacsvox-flyspell-tone-timing 'overlay) "Alongside speech" "Before speech"))

(defun emacsvox-spelling--timing-choice (value label)
  "Describe timing VALUE with LABEL and its selection state."
  (concat label (when (eq value emacsvox-flyspell-tone-timing) ", selected")))

(defun emacsvox-spelling--apply-timing (value)
  "Apply global timing VALUE and return to the spelling timing control."
  (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
  (set-default 'emacsvox-flyspell-tone-timing value)
  (transient--stack-pop)
  (transient--show)
  (emacsvox-spelling--say (emacsvox-spelling--timing-name)))

(defun emacsvox-spelling--before ()
  "Finish each spelling tone before reading its flagged word, adding a pause.
This applies globally for the session. Save in the spelling menu to keep it."
  (interactive) (emacsvox-spelling--apply-timing 'insert))

(defun emacsvox-spelling--alongside ()
  "Play spelling tones alongside flagged words without inserting tone pauses.
This applies globally for the session and leaves voice and earcons unchanged.
Tone-only previews and editing cues have no accompanying speech to overlap.
Save in the spelling menu to keep this choice across restarts."
  (interactive) (emacsvox-spelling--apply-timing 'overlay))

(transient-define-prefix emacsvox-spelling-timing ()
  "Choose global spelling tone timing; browsing does not change the setting.
Enter applies and returns. Cancel keeps the original choice.
Read the spelling sample to compare timing; a tone alone cannot demonstrate it."
  ["Spelling tone timing (global)"
   ("b" (lambda () (emacsvox-spelling--timing-choice 'insert "Before speech"))
    emacsvox-spelling--before :transient transient--do-replace)
   ("a" (lambda () (emacsvox-spelling--timing-choice 'overlay "Alongside speech"))
    emacsvox-spelling--alongside :transient transient--do-replace)]
  ["Finish"
   ("q" "Cancel" transient-quit-one)
   ("C-q" "Close menus" transient-quit-all)]
  (interactive)
  (transient-setup 'emacsvox-spelling-timing nil nil :scope (emacsvox-aural-menu--context))
  (transient--show)
  (with-selected-window transient--window
    (transient--goto-button
     (transient-suffix-object
      (if (eq emacsvox-flyspell-tone-timing 'overlay)
          'emacsvox-spelling--alongside 'emacsvox-spelling--before))))
  (emacsvox-transient--speak-button))

(defun emacsvox-spelling--check-preview ()
  "Require exact tone-volume support before submitting a spelling preview."
  (when emacsvox-flyspell-use-tone
    (let ((emacsvox-aural--exact-tone-preview t))
      (emacsvox-aural--tone-volume-deliverable-p
       (/ emacsvox-flyspell-tone-volume 100.0))
      (emacsvox-aural--tone-shape-deliverable-p emacsvox-flyspell-tone-shape))))

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
    (emacsvox-spelling--check-preview)
    (let ((emacsvox-aural--exact-tone-preview t))
      (tts-speak (emacsvox-spelling--sample)))))

(defun emacsvox-spelling--preview-tone ()
  "Interrupt main speech and play the tone, even when spelling tones are off."
  (interactive)
  (with-current-buffer (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
    (let ((emacsvox-flyspell-use-tone t) (emacsvox-flyspell-use-earcon nil)
          (emacsvox-aural--exact-tone-preview t))
      (emacsvox-spelling--check-preview)
      (emacsvox-aural-submit-actions
       :facts (emacsvox-flyspell--facts) :module 'flyspell :occasion 'inspection
       :lane 'main :delivery-policy 'urgent :interruption-policy 'lane))))

(defconst emacsvox-spelling--tone-fields
  '((:pitch . emacsvox-flyspell-tone-pitch)
    (:duration . emacsvox-flyspell-tone-duration)
    (:volume . emacsvox-flyspell-tone-volume))
  "Spelling options represented by the common tone editor.")

(defun emacsvox-spelling--tone-data (&optional factory)
  "Read current spelling tone settings, or FACTORY defaults."
  (let ((read (if factory (lambda (symbol) (eval (car (get symbol 'standard-value)) t))
                #'default-value)) data)
    (dolist (field emacsvox-spelling--tone-fields)
      (setq data (plist-put data (car field) (funcall read (cdr field)))))
    (let* ((shape (funcall read 'emacsvox-flyspell-tone-shape))
           (envelope (plist-get shape :envelope)))
      (append data (list :width (* 100 (or (plist-get shape :pulse-width) 0.5))
                         :sweep (and (plist-get shape :end-frequency-hz) t)
                         :end-pitch (or (plist-get shape :end-frequency-hz) (plist-get data :pitch))
                         :curve (or (plist-get shape :envelope-curve) 'linear)
                         :waveform (plist-get shape :waveform)
                         :envelope (if envelope 'adsr 'classic)
                         :attack (or (plist-get envelope :attack-ms) 5)
                         :decay (or (plist-get envelope :decay-ms) 10)
                         :sustain (* 100 (or (plist-get envelope :sustain-level) 0.6))
                         :release (or (plist-get envelope :release-ms) 10))))))

(defun emacsvox-spelling--apply-tone (data save)
  "Apply tone DATA globally; SAVE also persists only these tone options."
  (dolist (field emacsvox-spelling--tone-fields)
    (if save (customize-save-variable (cdr field) (plist-get data (car field)))
      (set-default (cdr field) (plist-get data (car field)))))
  (let ((shape (emacsvox-tone-editor--shape data)))
    (if save (customize-save-variable 'emacsvox-flyspell-tone-shape shape)
      (set-default 'emacsvox-flyspell-tone-shape shape))))

(defun emacsvox-spelling--preview-draft (data sample)
  "Preview private tone DATA, with a spelling SAMPLE when non-nil."
  (cl-progv (append (mapcar #'cdr emacsvox-spelling--tone-fields)
                    '(emacsvox-flyspell-tone-shape emacsvox-flyspell-use-tone))
      (append (mapcar (lambda (field) (plist-get data (car field))) emacsvox-spelling--tone-fields)
              (list (emacsvox-tone-editor--shape data) t))
    (if sample (emacsvox-spelling--preview) (emacsvox-spelling--preview-tone))))

(defun emacsvox-spelling--edit-tone ()
  "Edit a private draft of the global spelling tone, including waveform and envelope.
Preview changes neither live feedback nor saved defaults.  Apply changes the
session; Save and apply also persists tone defaults.  Back discards unapplied
edits.  Timing stays in Spelling feedback.  Voice, earcons and the shared
tone volume are outside this editor."
  (interactive)
  (emacsvox-tone-editor--open
   (emacsvox-aural-menu--context)
   (list :label "Spelling tone (global draft)"
         :read #'emacsvox-spelling--tone-data
         :apply #'emacsvox-spelling--apply-tone
         :preview #'emacsvox-spelling--preview-draft)))

(defun emacsvox-spelling--save ()
  "Save spelling controls, individual tone volume and shared main-tone volume.
This includes voice, tone and earcon enablement, tone timing, pitch, duration
and shape. These global defaults apply across restarts. The tone editor's W
saves only tone defaults; its S stops playback instead of saving."
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
      ('emacsvox-spelling--volume (emacsvox-spelling--volume direction))
      ('emacsvox-aural-menu--main-tones
       (emacsvox-aural-menu--output-volume 'tts-main-tone-volume (* 5 direction)))
      (_ (user-error "Choose Pitch, Duration, Spelling tone volume or Shared tone volume first")))))
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
immediately; S saves across restarts. Spelling tone volume affects only
this tone; Shared tone volume scales all main-stream tones.
E opens a private tone draft with waveform, sweep and envelope controls.
In this parent menu, Space reads the selected feedback sample and b plays
the tone alone. In the tone editor, Space plays only the draft tone, P reads
its sample, S stops, and W saves only tone defaults. Return here and use S
to save voice, tone and earcon enablement as well."
  :refresh-suffixes t
  ["Spelling feedback (global; combine any)"
   ("v" (lambda () (emacsvox-spelling--label 'emacsvox-flyspell-use-voice "Voice")) emacsvox-spelling--voice :transient t)
   ("t" (lambda () (emacsvox-spelling--label 'emacsvox-flyspell-use-tone "Tone")) emacsvox-spelling--tone :transient t)
   ("e" (lambda () (emacsvox-spelling--label 'emacsvox-flyspell-use-earcon "Earcon")) emacsvox-spelling--earcon :transient t)]
  ["Tone adjustment"
   ("E" "Edit complete tone" emacsvox-spelling--edit-tone :transient transient--do-stack)
   ("m" (lambda () (concat "Timing: " (emacsvox-spelling--timing-name)))
    emacsvox-spelling-timing :transient transient--do-stack)
   ("p" (lambda () (format "Pitch: %s Hz" emacsvox-flyspell-tone-pitch)) emacsvox-spelling--pitch :transient t)
   ("d" (lambda () (format "Duration: %s milliseconds" emacsvox-flyspell-tone-duration)) emacsvox-spelling--duration :transient t)
   ("l" (lambda () (format "Spelling tone volume: %s percent" emacsvox-flyspell-tone-volume)) emacsvox-spelling--volume :transient t)
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
