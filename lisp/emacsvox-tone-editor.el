;;; emacsvox-tone-editor.el --- Draft tone adjustments -*- lexical-binding: t; -*-

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
;; Shared draft interaction; cue providers own their settings and preview facts.
;;; Code:
(require 'emacsvox-aural-menu)

(defconst emacsvox-tone-editor--numbers
  '((:pitch "Pitch" "Hz" 50 10000 25)
    (:duration "Duration" "milliseconds" 5 1000 5)
    (:volume "Volume" "percent" 0 100 5)
    (:attack "Attack" "milliseconds" 0 60000 5)
    (:decay "Decay" "milliseconds" 0 60000 5)
    (:sustain "Sustain" "percent" 0 100 5)
    (:release "Release" "milliseconds" 0 60000 5))
  "Numeric draft controls: key, label, units, minimum, maximum and step.")

(defun emacsvox-tone-editor--state ()
  "Return the current editor state after validating its captured source."
  (let ((context (emacsvox-aural-menu--context)))
    (emacsvox-aural-menu--source context)
    (or (plist-get context :tone-editor) (user-error "Open a tone editor first"))))

(defun emacsvox-tone-editor--get (key)
  "Read KEY from the private draft."
  (plist-get (plist-get (emacsvox-tone-editor--state) :draft) key))

(defun emacsvox-tone-editor--say (text)
  "Speak interruptible editor feedback TEXT."
  (emacsvox-transient--submit-text
   text (emacsvox-transient--menu-facts 'tone-editor 'command-menu-value-changed)
   'state-change 'select-object))

(defun emacsvox-tone-editor--put (key value)
  "Set draft KEY to VALUE without applying it."
  (let ((state (emacsvox-tone-editor--state)))
    (setf (plist-get state :draft)
          (plist-put (plist-get state :draft) key value))))

(defun emacsvox-tone-editor--shape (data)
  "Return the validated waveform and envelope represented by draft DATA."
  (emacsvox-aural--validate-tone-shape
   (append (list :waveform (plist-get data :waveform))
           (when (eq (plist-get data :envelope) 'adsr)
             (list :envelope
                   (list :attack-ms (plist-get data :attack)
                         :decay-ms (plist-get data :decay)
                         :sustain-level (/ (plist-get data :sustain) 100.0)
                         :release-ms (plist-get data :release)))))))

(defun emacsvox-tone-editor--validate (data)
  "Validate the complete draft DATA before previewing or applying it."
  (dolist (spec emacsvox-tone-editor--numbers)
    (let ((value (plist-get data (car spec))))
      (unless (and (numberp value) (<= (nth 3 spec) value (nth 4 spec))
                   (or (memq (car spec) '(:pitch :sustain)) (integerp value)))
        (user-error "Invalid %s: %s" (nth 1 spec) value))))
  (unless (and (memq (plist-get data :timing) '(insert overlay))
               (memq (plist-get data :envelope) '(classic adsr)))
    (user-error "Invalid tone timing or envelope"))
  (emacsvox-tone-editor--shape data)
  data)

(defun emacsvox-tone-editor--number (key &optional direction)
  "Set draft KEY exactly, or adjust it by DIRECTION steps."
  (let* ((spec (assq key emacsvox-tone-editor--numbers))
         (old (emacsvox-tone-editor--get key))
         (value (if direction
                    (min (nth 4 spec) (max (nth 3 spec) (+ old (* direction (nth 5 spec)))))
                  (emacsvox-aural-menu--read-number
                   (format "%s in %s (%s–%s): " (nth 1 spec) (nth 2 spec) (nth 3 spec) (nth 4 spec)) old)))
         (candidate (plist-put (copy-tree (plist-get (emacsvox-tone-editor--state) :draft)) key value)))
    (emacsvox-tone-editor--validate candidate)
    (emacsvox-tone-editor--put key value)
    (emacsvox-tone-editor--say (format "%s %s%s" value (nth 2 spec)
                                     (if (and (memq key '(:attack :decay :sustain :release))
                                              (eq (emacsvox-tone-editor--get :envelope) 'classic))
                                         "; used with ADSR" "")))))

(defun emacsvox-tone-editor--number-label (key)
  "Describe numeric draft KEY and its units."
  (let ((spec (assq key emacsvox-tone-editor--numbers)))
    (format "%s: %s %s" (nth 1 spec) (emacsvox-tone-editor--get key) (nth 2 spec))))

(defun emacsvox-tone-editor--name (value)
  "Return a concise label for choice VALUE."
  (pcase value ('insert "Before speech") ('overlay "Alongside speech")
         ('adsr "ADSR") (_ (capitalize (symbol-name value)))))

(defun emacsvox-tone-editor--choice-label (key value)
  "Describe choice VALUE for KEY with its selection state."
  (concat (emacsvox-tone-editor--name value)
          (when (eq value (emacsvox-tone-editor--get key)) ", selected")))

(defun emacsvox-tone-editor--choose (key value)
  "Set draft KEY to VALUE and return to its control."
  (emacsvox-tone-editor--put key value)
  (transient--stack-pop)
  (transient--show)
  (emacsvox-tone-editor--say (emacsvox-tone-editor--name value)))

(defun emacsvox-tone-editor--choice-setup (prefix key choices)
  "Open PREFIX for KEY, focusing its current command from CHOICES."
  (transient-setup prefix nil nil :scope (emacsvox-aural-menu--context))
  (transient--show)
  (with-selected-window transient--window
    (transient--goto-button
     (transient-suffix-object (cdr (assq (emacsvox-tone-editor--get key) choices)))))
  (emacsvox-transient--speak-button))

(defun emacsvox-tone-editor--preview (sample)
  "Preview the current draft; SAMPLE includes the cue provider's context."
  (let* ((state (emacsvox-tone-editor--state))
         (data (emacsvox-tone-editor--validate (copy-tree (plist-get state :draft)))))
    (funcall (plist-get (plist-get state :provider) :preview) data sample)))

(defun emacsvox-tone-editor--tone ()
  "Play the draft tone alone, including when the live cue is disabled.
Preview does not apply or save adjustments.  Older workers report unsupported
shapes or volume instead of playing an inaccurate substitute."
  (interactive) (emacsvox-tone-editor--preview nil))

(defun emacsvox-tone-editor--sample ()
  "Read a sample using the draft tone to compare timing and speech masking.
The preview enables this tone privately without changing live settings.
Other feedback follows the source's current settings."
  (interactive) (emacsvox-tone-editor--preview t))

(defun emacsvox-tone-editor--stop ()
  "Stop current main speech and tone preview immediately."
  (interactive) (tts-stop))

(defun emacsvox-tone-editor--apply (&optional save)
  "Apply this draft for the session; SAVE also persists its defaults."
  (interactive)
  (let* ((state (emacsvox-tone-editor--state))
         (data (emacsvox-tone-editor--validate (copy-tree (plist-get state :draft)))))
    (funcall (plist-get (plist-get state :provider) :apply) data save)
    (emacsvox-tone-editor--say (if save "Saved and applied tone defaults" "Tone applied for this session"))))

(defun emacsvox-tone-editor--save ()
  "Save and apply this cue's tone defaults through Customize.
This saves pitch, duration, individual volume, timing, waveform and envelope.
It leaves cue enablement, voices, earcons and shared tone volume unchanged."
  (interactive) (emacsvox-tone-editor--apply t))

(defun emacsvox-tone-editor--reset ()
  "Reset the private draft to factory defaults.
Live and saved settings stay intact.
Use Preview to hear it, then Apply or Save and apply if you want to keep it."
  (interactive)
  (let ((state (emacsvox-tone-editor--state)))
    (setf (plist-get state :draft)
          (funcall (plist-get (plist-get state :provider) :read) t)))
  (emacsvox-tone-editor--say "Draft reset to factory defaults"))

(defun emacsvox-tone-editor--back ()
  "Return and discard unapplied draft edits.  Applied and saved values remain."
  (interactive) (transient-quit-one))

(defun emacsvox-tone-editor--adjust (direction)
  "Adjust the selected numeric draft control in DIRECTION."
  (let* ((command (with-selected-window (emacsvox-transient--navigation-window)
                    (when-let* ((button (button-at (point))))
                      (oref (button-get button 'button-data) command))))
         (key (get command 'emacsvox-tone-field)))
    (unless key (user-error "Choose a numeric tone control first"))
    (emacsvox-tone-editor--number key direction)))

(defun emacsvox-tone-editor--decrease ()
  "Decrease the selected draft value." (interactive) (emacsvox-tone-editor--adjust -1))
(defun emacsvox-tone-editor--increase ()
  "Increase the selected draft value." (interactive) (emacsvox-tone-editor--adjust 1))
(defun emacsvox-tone-editor--bindings (map)
  "Add draft adjustment bindings to tone editor MAP."
  (when (and transient--prefix (eq (oref transient--prefix command) 'emacsvox-tone-editor))
    (keymap-set map "S-<left>" #'emacsvox-tone-editor--decrease)
    (keymap-set map "S-<right>" #'emacsvox-tone-editor--increase))
  map)
(advice-add 'transient--make-transient-map :filter-return #'emacsvox-tone-editor--bindings)
(define-key transient-predicate-map [emacsvox-tone-editor--decrease] #'transient--do-stay)
(define-key transient-predicate-map [emacsvox-tone-editor--increase] #'transient--do-stay)

(defun emacsvox-tone-editor--pitch ()
  "Set draft pitch in hertz; Shift arrows change it by 25 Hz. Range: 50–10000 Hz."
  (interactive) (emacsvox-tone-editor--number :pitch))
(put 'emacsvox-tone-editor--pitch 'emacsvox-tone-field :pitch)

(defun emacsvox-tone-editor--duration ()
  "Set total draft duration in milliseconds, including all envelope stages.
Shift arrows change it by 5 ms. Range: 5–1000 ms. Oversized attack, decay and
release stages are shortened proportionally; they never extend this duration."
  (interactive) (emacsvox-tone-editor--number :duration))
(put 'emacsvox-tone-editor--duration 'emacsvox-tone-field :duration)

(defun emacsvox-tone-editor--volume ()
  "Set this draft tone volume from 0 to 100 percent; Shift arrows change it by 5.
Zero silences it. Shared main-tone volume also scales playback. Other tones
are unchanged. Values below 100 require richer-tone support."
  (interactive) (emacsvox-tone-editor--number :volume))
(put 'emacsvox-tone-editor--volume 'emacsvox-tone-field :volume)

(defun emacsvox-tone-editor--attack ()
  "Set milliseconds for the ADSR rise from silence to peak level.
Zero starts immediately. Shift arrows change it by 5 ms, within 0–60000 ms.
Classic ignores this value. Oversized stages shorten to fit total duration."
  (interactive) (emacsvox-tone-editor--number :attack))
(put 'emacsvox-tone-editor--attack 'emacsvox-tone-field :attack)

(defun emacsvox-tone-editor--decay ()
  "Set milliseconds for the ADSR fall from peak to the sustain level.
Zero goes straight to sustain. Shift arrows change it by 5 ms.
Range: 0–60000 ms.
Classic ignores this value. Oversized stages shorten to fit total duration."
  (interactive) (emacsvox-tone-editor--number :decay))
(put 'emacsvox-tone-editor--decay 'emacsvox-tone-field :decay)

(defun emacsvox-tone-editor--sustain ()
  "Set the ADSR held level from 0 to 100 percent of peak, not a duration.
The hold uses time left after attack, decay and release. Shift arrows change
it by 5 percentage points. Classic ignores this value."
  (interactive) (emacsvox-tone-editor--number :sustain))
(put 'emacsvox-tone-editor--sustain 'emacsvox-tone-field :sustain)

(defun emacsvox-tone-editor--release ()
  "Set milliseconds for the ADSR final fade to silence.
Zero removes that fade; endpoint smoothing still limits clicks. Shift arrows
change it by 5 ms, within 0–60000 ms. Classic ignores this value. Oversized
stages shorten to fit total duration. Stop never waits for this fade."
  (interactive) (emacsvox-tone-editor--number :release))
(put 'emacsvox-tone-editor--release 'emacsvox-tone-field :release)

(defun emacsvox-tone-editor--sine ()
  "A smooth pure tone with no added harmonics; the original waveform.
Selecting changes only this draft; Apply and Save are separate actions."
  (interactive) (emacsvox-tone-editor--choose :waveform 'sine))

(defun emacsvox-tone-editor--triangle ()
  "A softer harmonic tone with a different timbre from sine.
Perceived loudness can differ; compare at a comfortable individual volume.
Selecting changes only this draft; Apply and Save are separate actions."
  (interactive) (emacsvox-tone-editor--choose :waveform 'triangle))

(defun emacsvox-tone-editor--square ()
  "A brighter harmonic tone, which may sound louder than sine or triangle.
The renderer limits high harmonics. Compare at a comfortable individual volume.
Selecting changes only this draft; Apply and Save are separate actions."
  (interactive) (emacsvox-tone-editor--choose :waveform 'square))

(transient-define-prefix emacsvox-tone-editor-waveform ()
  "Choose draft waveform; arrows browse without applying a choice.
Enter selects and returns. Cancel keeps the previous draft value."
  ["Waveform"
   ("s" (lambda () (emacsvox-tone-editor--choice-label :waveform 'sine))
    emacsvox-tone-editor--sine :transient transient--do-replace)
   ("t" (lambda () (emacsvox-tone-editor--choice-label :waveform 'triangle))
    emacsvox-tone-editor--triangle :transient transient--do-replace)
   ("r" (lambda () (emacsvox-tone-editor--choice-label :waveform 'square))
    emacsvox-tone-editor--square :transient transient--do-replace)
   ]
  ["Finish" ("q" "Cancel" transient-quit-one) ("C-q" "Close menus" transient-quit-all)]
  (interactive)
  (emacsvox-tone-editor--choice-setup
   'emacsvox-tone-editor-waveform :waveform
   '((sine . emacsvox-tone-editor--sine) (triangle . emacsvox-tone-editor--triangle) (square . emacsvox-tone-editor--square))))

(defun emacsvox-tone-editor--classic ()
  "Use the original short fades at each end of the tone.
ADSR controls are ignored but retained in this draft.
Selecting changes only this draft; Apply and Save are separate actions."
  (interactive) (emacsvox-tone-editor--choose :envelope 'classic))

(defun emacsvox-tone-editor--adsr ()
  "Shape the tone with attack, decay, sustain level and release.
Total duration stays fixed. Oversized timed stages shorten proportionally;
otherwise sustain holds for the remaining time. Stop remains immediate.
Selecting changes only this draft; Apply and Save are separate actions."
  (interactive) (emacsvox-tone-editor--choose :envelope 'adsr))

(transient-define-prefix emacsvox-tone-editor-envelope ()
  "Choose draft envelope; arrows browse without applying a choice.
Enter selects and returns. Cancel keeps the previous draft value."
  ["Envelope"
   ("c" (lambda () (emacsvox-tone-editor--choice-label :envelope 'classic))
    emacsvox-tone-editor--classic :transient transient--do-replace)
   ("a" (lambda () (emacsvox-tone-editor--choice-label :envelope 'adsr))
    emacsvox-tone-editor--adsr :transient transient--do-replace)
   ]
  ["Finish" ("q" "Cancel" transient-quit-one) ("C-q" "Close menus" transient-quit-all)]
  (interactive)
  (emacsvox-tone-editor--choice-setup
   'emacsvox-tone-editor-envelope :envelope
   '((classic . emacsvox-tone-editor--classic) (adsr . emacsvox-tone-editor--adsr))))

(defun emacsvox-tone-editor--insert ()
  "Finish the tone before its word, inserting a pause while reading.
This changes only the draft. A tone-only preview has no speech to delay.
Selecting changes only this draft; Apply and Save are separate actions."
  (interactive) (emacsvox-tone-editor--choose :timing 'insert))

(defun emacsvox-tone-editor--overlay ()
  "Play the tone alongside its word without adding a tone pause.
This is the default. Use the sample to judge whether the tone masks speech.
Selecting changes only this draft; Apply and Save are separate actions."
  (interactive) (emacsvox-tone-editor--choose :timing 'overlay))

(transient-define-prefix emacsvox-tone-editor-timing ()
  "Choose draft timing; arrows browse without applying a choice.
Enter selects and returns. Cancel keeps the previous draft value."
  ["Timing"
   ("b" (lambda () (emacsvox-tone-editor--choice-label :timing 'insert))
    emacsvox-tone-editor--insert :transient transient--do-replace)
   ("a" (lambda () (emacsvox-tone-editor--choice-label :timing 'overlay))
    emacsvox-tone-editor--overlay :transient transient--do-replace)
   ]
  ["Finish" ("q" "Cancel" transient-quit-one) ("C-q" "Close menus" transient-quit-all)]
  (interactive)
  (emacsvox-tone-editor--choice-setup
   'emacsvox-tone-editor-timing :timing
   '((insert . emacsvox-tone-editor--insert) (overlay . emacsvox-tone-editor--overlay))))

(transient-define-prefix emacsvox-tone-editor ()
  "Edit a private tone draft.  Arrows navigate; Shift arrows adjust numbers.
Enter sets an exact number or opens a choice list.  Preview leaves live settings
unchanged. Apply changes the session; Save and apply persists tone defaults.
Back discards unapplied edits. Shared main-tone volume belongs in Output settings."
  :refresh-suffixes t
  [:description (lambda () (plist-get (plist-get (emacsvox-tone-editor--state) :provider) :label))
   ("p" (lambda () (emacsvox-tone-editor--number-label :pitch)) emacsvox-tone-editor--pitch :transient t)
   ("d" (lambda () (emacsvox-tone-editor--number-label :duration)) emacsvox-tone-editor--duration :transient t)
   ("v" (lambda () (emacsvox-tone-editor--number-label :volume)) emacsvox-tone-editor--volume :transient t)
   ("w" (lambda () (concat "Waveform: " (emacsvox-tone-editor--name (emacsvox-tone-editor--get :waveform)))) emacsvox-tone-editor-waveform :transient transient--do-stack)
   ("m" (lambda () (concat "Timing: " (emacsvox-tone-editor--name (emacsvox-tone-editor--get :timing)))) emacsvox-tone-editor-timing :transient transient--do-stack)]
  ["Envelope (stage controls apply to ADSR)"
   ("e" (lambda () (concat "Envelope: " (emacsvox-tone-editor--name (emacsvox-tone-editor--get :envelope)))) emacsvox-tone-editor-envelope :transient transient--do-stack)
   ("a" (lambda () (emacsvox-tone-editor--number-label :attack)) emacsvox-tone-editor--attack :transient t)
   ("c" (lambda () (emacsvox-tone-editor--number-label :decay)) emacsvox-tone-editor--decay :transient t)
   ("s" (lambda () (emacsvox-tone-editor--number-label :sustain)) emacsvox-tone-editor--sustain :transient t)
   ("r" (lambda () (emacsvox-tone-editor--number-label :release)) emacsvox-tone-editor--release :transient t)]
  ["Preview"
   ("b" "Play tone alone" emacsvox-tone-editor--tone :transient t)
   ("SPC" "Read sample" emacsvox-tone-editor--sample :transient t)
   ("S" "Stop preview" emacsvox-tone-editor--stop :transient t)]
  ["Apply and save"
   ("R" "Reset draft to factory defaults" emacsvox-tone-editor--reset :transient t)
   ("A" "Apply for session" emacsvox-tone-editor--apply :transient t)
   ("W" "Save and apply tone defaults" emacsvox-tone-editor--save :transient t)]
  ["Finish"
   ("q" "Back (discard unapplied edits)" emacsvox-tone-editor--back :transient transient--do-quit-one)
   ("C-q" "Close menus" transient-quit-all)]
  (interactive)
  (emacsvox-tone-editor--state)
  (transient-setup 'emacsvox-tone-editor nil nil :scope (emacsvox-aural-menu--context)))

(defun emacsvox-tone-editor--open (context provider)
  "Open a draft editor for cue PROVIDER using source CONTEXT.
PROVIDER supplies :label, :read, :apply and :preview callbacks."
  (emacsvox-aural-menu--source context)
  (let ((scope (append (list :tone-editor
                            (list :provider provider :draft (funcall (plist-get provider :read))))
                       context)))
    (transient-setup 'emacsvox-tone-editor nil nil :scope scope)))

(provide 'emacsvox-tone-editor)
;;; emacsvox-tone-editor.el ends here
