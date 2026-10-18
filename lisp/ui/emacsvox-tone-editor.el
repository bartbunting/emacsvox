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

(defcustom emacsvox-tone-presets nil
  "Named personal tone drafts, saved independently of any cue's defaults.
Each entry contains a name and a tone-editor draft. Loading changes only the
private draft; Apply or Save and apply changes the destination cue."
  :type '(alist :key-type string :value-type plist)
  :group 'emacsvox-aural)

(defconst emacsvox-tone-editor--presets
  '(("Soft tick" "A brief sine tone with short fades, at 35 percent volume."
     :pitch 880 :duration 25 :volume 35 :waveform sine :envelope adsr
     :attack 2 :decay 5 :sustain 40 :release 10)
    ("Rounded beep" "A lower sine tone with a gradual onset and release, at 35 percent volume."
     :pitch 660 :duration 80 :volume 35 :waveform sine :envelope adsr
     :attack 15 :decay 10 :sustain 60 :release 30)
    ("Short pluck" "A triangle tone with a quick onset and falling level, at 35 percent volume."
     :pitch 1100 :duration 100 :volume 35 :waveform triangle :envelope adsr
     :attack 2 :decay 70 :sustain 15 :release 20))
  "Bundled starting points: name, explanation, then a complete draft.")

(defconst emacsvox-tone-editor--numbers
  '((:pitch "Pitch" "Hz" 50 10000 25)
    (:duration "Duration" "milliseconds" 5 1000 5)
    (:volume "Volume" "percent" 0 100 5)
    (:width "Pulse width" "percent" 5 95 5)
    (:end-pitch "End pitch" "Hz" 50 10000 25)
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

(defun emacsvox-tone-editor--label (key fallback)
  "Return the cue provider's label KEY, or FALLBACK."
  (or (plist-get (plist-get (emacsvox-tone-editor--state) :provider) key) fallback))

(defun emacsvox-tone-editor--data (pitch duration volume shape)
  "Represent PITCH, DURATION, VOLUME percent and SHAPE as an editor draft."
  (let ((envelope (plist-get shape :envelope)))
    (list :pitch pitch :duration duration :volume (round volume)
          :waveform (or (plist-get shape :waveform) 'sine)
          :width (* 100 (or (plist-get shape :pulse-width) 0.5))
          :sweep (and (plist-get shape :end-frequency-hz) t)
          :end-pitch (or (plist-get shape :end-frequency-hz) pitch)
          :curve (or (plist-get shape :envelope-curve) 'linear)
          :envelope (if envelope 'adsr 'classic)
          :attack (or (plist-get envelope :attack-ms) 5)
          :decay (or (plist-get envelope :decay-ms) 10)
          :sustain (* 100 (or (plist-get envelope :sustain-level) 0.6))
          :release (or (plist-get envelope :release-ms) 10))))

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
           (when (eq (plist-get data :waveform) 'pulse)
             (list :pulse-width (/ (or (plist-get data :width) 50) 100.0)))
           (when (plist-get data :sweep) (list :end-frequency-hz (plist-get data :end-pitch)))
           (when (and (eq (plist-get data :envelope) 'adsr) (eq (plist-get data :curve) 'exponential))
             (list :envelope-curve 'exponential))
           (when (eq (plist-get data :envelope) 'adsr)
             (list :envelope
                   (list :attack-ms (plist-get data :attack)
                         :decay-ms (plist-get data :decay)
                         :sustain-level (/ (plist-get data :sustain) 100.0)
                         :release-ms (plist-get data :release)))))))

(defun emacsvox-tone-editor--validate (data)
  "Validate the complete draft DATA before previewing or applying it."
  ;; Presets saved before extended tones retain their original sound.
  (dolist (entry `((:width . 50) (:end-pitch . ,(plist-get data :pitch)) (:curve . linear)))
    (unless (plist-member data (car entry)) (setq data (plist-put data (car entry) (cdr entry)))))
  (unless (and (memq (plist-get data :sweep) '(nil t)) (memq (plist-get data :curve) '(linear exponential)))
    (user-error "Invalid sweep or envelope curve"))
  (dolist (spec emacsvox-tone-editor--numbers)
    (let ((value (plist-get data (car spec))))
      (unless (and (numberp value) (<= (nth 3 spec) value (nth 4 spec))
                   (or (memq (car spec) '(:pitch :end-pitch :width :sustain)) (integerp value)))
        (user-error "Invalid %s: %s" (nth 1 spec) value))))
  (unless (memq (plist-get data :envelope) '(classic adsr))
    (user-error "Invalid tone envelope"))
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
                                     (cond ((and (memq key '(:attack :decay :sustain :release))
                                                 (eq (emacsvox-tone-editor--get :envelope) 'classic)) "; used with ADSR")
                                           ((and (eq key :width) (not (eq (emacsvox-tone-editor--get :waveform) 'pulse))) "; used with Pulse")
                                           ((and (eq key :end-pitch) (not (emacsvox-tone-editor--get :sweep))) "; sweep is off")
                                           (t ""))))))

(defun emacsvox-tone-editor--number-label (key)
  "Describe numeric draft KEY and its units."
  (let ((spec (assq key emacsvox-tone-editor--numbers)))
    (format "%s: %s %s" (nth 1 spec) (emacsvox-tone-editor--get key) (nth 2 spec))))

(defun emacsvox-tone-editor--name (value)
  "Return a concise label for choice VALUE."
  (pcase value ('adsr "ADSR") (_ (capitalize (symbol-name value)))))

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
     (emacsvox-transient--menu-suffix (cdr (assq (emacsvox-tone-editor--get key) choices)))))
  (emacsvox-transient--speak-button))

(defun emacsvox-tone-editor--preview (sample)
  "Preview the current draft; SAMPLE includes the cue provider's context."
  (let* ((state (emacsvox-tone-editor--state))
         (data (emacsvox-tone-editor--validate (copy-tree (plist-get state :draft)))))
    (funcall (plist-get (plist-get state :provider) :preview) data sample)))

(defun emacsvox-tone-editor--tone ()
  "Play the draft tone alone, including when the live cue is disabled.
Space and b interrupt previous main speech; S stops this preview immediately.
Preview does not apply or save adjustments.  Older workers report unsupported
shapes or volume instead of playing an inaccurate substitute."
  (interactive) (emacsvox-tone-editor--preview nil))

(defun emacsvox-tone-editor--sample ()
  "Read a sample using the draft tone to compare timing and speech masking.
The preview enables this tone privately without changing live settings.
Timing and other feedback follow the source's current settings."
  (interactive) (emacsvox-tone-editor--preview t))

(defun emacsvox-tone-editor--current ()
  "Play the currently applied tone alone for comparison with Space's draft.
Reread live settings, including earlier Apply. Capitalization also recognises
old menu rules awaiting migration. This leaves drafts and saved defaults
unchanged and interrupts the previous preview."
  (interactive)
  (let* ((provider (plist-get (emacsvox-tone-editor--state) :provider))
         (data (emacsvox-tone-editor--validate
                (funcall (or (plist-get provider :current) (plist-get provider :read))))))
    (funcall (plist-get provider :preview) data nil)))

(defun emacsvox-tone-editor--load-preset (name data)
  "Copy preset DATA named NAME into the draft and return to its control."
  (let ((draft (emacsvox-tone-editor--validate (copy-tree data)))
        (state (emacsvox-tone-editor--state)))
    (setf (plist-get state :draft) draft))
  (transient--stack-pop)
  (transient--show)
  (emacsvox-tone-editor--say (concat name "; draft only")))

(defun emacsvox-tone-editor--preset-children (_children)
  "Build browsable preset choices with individual explanations."
  (let* ((entries (append emacsvox-tone-editor--presets
                          (mapcar (lambda (entry)
                                    (append (list (car entry) "Your saved tone; loading changes only the draft.")
                                            (cdr entry)))
                                  emacsvox-tone-presets)))
         (width (length (number-to-string (length entries))))
         (index 0))
    (transient-parse-suffixes
     'emacsvox-tone-editor-presets
     (mapcar
      (lambda (entry)
        (let ((name (car entry)) (data (copy-tree (cddr entry)))
              (help (concat (cadr entry) "\nEnter copies this preset into the draft; Apply and Save remain separate.")))
          (list (format (concat "%0" (number-to-string width) "d") (cl-incf index))
                name (lambda () (:documentation help) (interactive)
                       (emacsvox-tone-editor--load-preset name data))
                :transient 'transient--do-replace)))
      entries))))

(transient-define-prefix emacsvox-tone-editor-presets ()
  "Choose a starting point for the private tone draft.
Arrows browse without changing anything. Enter loads a copy and returns;
q cancels. Space in the editor plays the resulting draft."
  ["Tone presets" :class transient-column
   :setup-children emacsvox-tone-editor--preset-children]
  ["Finish" ("q" "Cancel" transient-quit-one) ("C-q" "Close menus" transient-quit-all)]
  (interactive)
  (transient-setup 'emacsvox-tone-editor-presets nil nil :scope (emacsvox-aural-menu--context))
  (transient--show)
  (with-selected-window transient--window
    (transient--goto-button
     (seq-find (lambda (suffix) (equal (oref suffix description) "Soft tick")) transient--suffixes)))
  (emacsvox-transient--speak-button))

(defun emacsvox-tone-editor--save-preset ()
  "Save this draft under a name through Customize, without applying it.
The preset collection is shared by tone editors. Saving a preset leaves the
cue's live and saved defaults unchanged. Reusing a personal name asks before
replacement; bundled names cannot be replaced."
  (interactive)
  (let* ((data (emacsvox-tone-editor--validate
                (copy-tree (plist-get (emacsvox-tone-editor--state) :draft))))
         (name (string-trim (emacsvox-transient--read #'read-string "Save tone preset as: ")))
         (presets (copy-tree emacsvox-tone-presets)))
    (when (string-empty-p name) (user-error "Give the preset a name"))
    (when (assoc-string name emacsvox-tone-editor--presets t)
      (user-error "Choose a name other than a bundled preset"))
    (let ((existing (assoc-string name presets t)))
      (when (and existing (not (emacsvox-transient--read #'y-or-n-p (format "Replace tone preset %s? " (car existing)))))
        (user-error "Preset unchanged"))
      (if existing (setcdr existing data) (setq presets (append presets (list (cons name data))))))
    (customize-save-variable 'emacsvox-tone-presets presets)
    (emacsvox-tone-editor--say (concat "Saved preset " name "; cue unchanged"))))

(defun emacsvox-tone-editor--stop ()
  "Stop current main speech and tone preview immediately."
  (interactive) (tts-stop))

(defun emacsvox-tone-editor--apply (&optional save)
  "Apply this draft using the destination's scope; SAVE also persists it.
Spelling and capitalization change global defaults; indentation changes the
captured buffer or global defaults. Line cues apply session presentation rules.
Save uses Customize for ordinary defaults and personal rules for line cues.
Enablement, timing and shared volume stay intact."
  (interactive)
  (let* ((state (emacsvox-tone-editor--state))
         (data (emacsvox-tone-editor--validate (copy-tree (plist-get state :draft)))))
    (funcall (plist-get (plist-get state :provider) :apply) data save)
    (emacsvox-tone-editor--say
     (if save (emacsvox-tone-editor--label :save-message "Saved and applied tone defaults")
       (emacsvox-tone-editor--label :apply-message "Tone applied for this session")))))

(defun emacsvox-tone-editor--save ()
  "Save and apply this cue through its destination's persistence mechanism.
Line cues save conditional personal rules. Spelling, capitalization and global
indentation use Customize. Buffer-local indentation cannot be saved here. Capitalization migrates unchanged old
menu-generated rules on Save; contextual presentation rules remain intact.
This saves pitch, duration, individual volume, waveform, Pulse width, sweep
and envelope controls.
Timing, cue enablement, voices, earcons and shared tone volume stay unchanged."
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
    (keymap-set map "b" #'emacsvox-tone-editor--tone)
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

(defun emacsvox-tone-editor--width ()
  "Set Pulse width from 5 to 95 percent; Shift arrows change it by 5 points.
Width is the high part of each cycle. 50 percent sounds like Square; other
widths change the harmonic character. Only Pulse uses this value. The draft
retains it while you try other waveforms. Preview and Apply remain separate."
  (interactive) (emacsvox-tone-editor--number :width))
(put 'emacsvox-tone-editor--width 'emacsvox-tone-field :width)

(defun emacsvox-tone-editor--sweep ()
  "Toggle a linear pitch sweep within the tone's existing duration.
When enabled, pitch moves from Pitch to End pitch. A higher end rises and a
lower end falls. Turning it off keeps End pitch in the draft for later use.
This changes only the draft; timing relative to speech is unchanged."
  (interactive)
  (emacsvox-tone-editor--put :sweep (not (emacsvox-tone-editor--get :sweep)))
  (emacsvox-tone-editor--say (if (emacsvox-tone-editor--get :sweep) "Pitch sweep on" "Pitch sweep off")))

(defun emacsvox-tone-editor--end-pitch ()
  "Set the sweep's final pitch from 50 to 10000 Hz; Shift arrows change 25 Hz.
Used only when Pitch sweep is on. Pitch remains the starting frequency. Equal
start and end values keep constant pitch. Preview and Apply remain separate."
  (interactive) (emacsvox-tone-editor--number :end-pitch))
(put 'emacsvox-tone-editor--end-pitch 'emacsvox-tone-field :end-pitch)

(defun emacsvox-tone-editor--duration ()
  "Set total tone duration; Shift arrows change it by 5 ms.
Total duration includes all envelope stages. Range: 5–1000 ms. Oversized attack, decay and
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
  "Set ADSR attack time; Shift arrows change it by 5 ms.
Attack rises from silence to peak level. Zero starts immediately.
Range: 0–60000 ms.
Classic ignores this value. Oversized stages shorten to fit total duration."
  (interactive) (emacsvox-tone-editor--number :attack))
(put 'emacsvox-tone-editor--attack 'emacsvox-tone-field :attack)

(defun emacsvox-tone-editor--decay ()
  "Set ADSR decay time; Shift arrows change it by 5 ms.
Decay falls from peak to the sustain level. Zero goes straight to sustain.
Range: 0–60000 ms.
Classic ignores this value. Oversized stages shorten to fit total duration."
  (interactive) (emacsvox-tone-editor--number :decay))
(put 'emacsvox-tone-editor--decay 'emacsvox-tone-field :decay)

(defun emacsvox-tone-editor--sustain ()
  "Set ADSR sustain level; Shift arrows change it by 5 percentage points.
Sustain is 0–100 percent of peak, not a duration. The hold uses time left
after attack, decay and release. Classic ignores this value."
  (interactive) (emacsvox-tone-editor--number :sustain))
(put 'emacsvox-tone-editor--sustain 'emacsvox-tone-field :sustain)

(defun emacsvox-tone-editor--release ()
  "Set ADSR release time; Shift arrows change it by 5 ms.
Release fades to silence. Zero removes that fade; endpoint smoothing still
limits clicks. Range: 0–60000 ms. Classic ignores this value. Oversized
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

(defun emacsvox-tone-editor--pulse ()
  "Use a pulse waveform with adjustable high-time percentage.
At 50 percent width it sounds like Square. Narrower or wider pulses change
its character. Adjust Pulse width in the editor; only the draft changes."
  (interactive) (emacsvox-tone-editor--choose :waveform 'pulse))

(defun emacsvox-tone-editor--sawtooth ()
  "Use a bright, buzzy waveform with both odd and even harmonics.
Compare at a comfortable individual volume, especially alongside speech.
Selecting changes only the draft; Apply and Save remain separate."
  (interactive) (emacsvox-tone-editor--choose :waveform 'sawtooth))

(transient-define-prefix emacsvox-tone-editor-waveform ()
  "Choose the draft waveform from a list.
Up and Down browse without changing the draft. Enter selects and returns;
q cancels. Preview with Space after returning to the editor.
Only Pulse uses the editor's separate Pulse width control."
  ["Waveform"
   ("s" (lambda () (emacsvox-tone-editor--choice-label :waveform 'sine))
    emacsvox-tone-editor--sine :transient transient--do-replace)
   ("t" (lambda () (emacsvox-tone-editor--choice-label :waveform 'triangle))
    emacsvox-tone-editor--triangle :transient transient--do-replace)
   ("r" (lambda () (emacsvox-tone-editor--choice-label :waveform 'square))
    emacsvox-tone-editor--square :transient transient--do-replace)
   ("p" (lambda () (emacsvox-tone-editor--choice-label :waveform 'pulse))
    emacsvox-tone-editor--pulse :transient transient--do-replace)
   ("w" (lambda () (emacsvox-tone-editor--choice-label :waveform 'sawtooth))
    emacsvox-tone-editor--sawtooth :transient transient--do-replace)
   ]
  ["Finish" ("q" "Cancel" transient-quit-one) ("C-q" "Close menus" transient-quit-all)]
  (interactive)
  (emacsvox-tone-editor--choice-setup
   'emacsvox-tone-editor-waveform :waveform
   '((sine . emacsvox-tone-editor--sine) (triangle . emacsvox-tone-editor--triangle) (square . emacsvox-tone-editor--square) (pulse . emacsvox-tone-editor--pulse)
     (sawtooth . emacsvox-tone-editor--sawtooth))))

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
  "Choose the draft envelope from a list.
The envelope controls loudness over the life of the tone. Up and Down browse;
Enter selects and returns, while q cancels. Classic uses short endpoint fades.
ADSR uses Attack, Decay, Sustain level and Release in the editor. Selecting
does not preview or apply the draft; use Space after returning to hear it."
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

(defun emacsvox-tone-editor--linear ()
  "Use straight volume ramps for each ADSR stage, preserving the original ADSR.
Only ADSR uses the curve. Selecting changes only the draft and returns."
  (interactive) (emacsvox-tone-editor--choose :curve 'linear))
(defun emacsvox-tone-editor--exponential ()
  "Use curved ADSR ramps: a slower initial rise and faster initial decay or release.
Stage durations, endpoint levels and total tone duration stay the same.
Only ADSR uses this curve; the draft retains it when you choose Classic."
  (interactive) (emacsvox-tone-editor--choose :curve 'exponential))
(transient-define-prefix emacsvox-tone-editor-curve ()
  "Choose the ADSR curve from a list.
Up and Down browse without changing the draft. Enter selects and returns;
q cancels. Only ADSR uses this curve. Preview with Space back in the editor."
  ["ADSR curve"
   ("l" (lambda () (emacsvox-tone-editor--choice-label :curve 'linear)) emacsvox-tone-editor--linear :transient transient--do-replace)
   ("e" (lambda () (emacsvox-tone-editor--choice-label :curve 'exponential)) emacsvox-tone-editor--exponential :transient transient--do-replace)]
  ["Finish" ("q" "Cancel" transient-quit-one) ("C-q" "Close menus" transient-quit-all)]
  (interactive)
  (emacsvox-tone-editor--choice-setup 'emacsvox-tone-editor-curve :curve
                                    '((linear . emacsvox-tone-editor--linear) (exponential . emacsvox-tone-editor--exponential))))

(transient-define-prefix emacsvox-tone-editor ()
  "Edit a private tone draft.
Up and Down select items; Left and Right change sections. Shift-Left and
Shift-Right adjust numbers. Enter sets an exact number, toggles Pitch sweep,
or opens a choice list. Browsing a choice list changes nothing until Enter.
Space or b interrupts main speech and plays the draft tone alone. C plays the
applied tone; P reads a sample with the draft. S stops, without saving.
Preview comes before Presets in the section order. L loads a preset into the
draft; N saves a named preset without changing the cue. A applies the draft
in the destination's scope. Line cues use session presentation rules. W saves through Customize or the destination's personal rules;
buffer-local indentation must use global scope before saving.
q or C-g returns and discards unapplied edits; C-q closes all menus. Applied
and saved changes remain. Timing, cue enablement, voice and earcon choices
belong to the parent menu; shared main-tone volume belongs in Output settings."
  :refresh-suffixes t
  [:description (lambda () (plist-get (plist-get (emacsvox-tone-editor--state) :provider) :label))
   ("p" (lambda () (emacsvox-tone-editor--number-label :pitch)) emacsvox-tone-editor--pitch :transient t)
   ("d" (lambda () (emacsvox-tone-editor--number-label :duration)) emacsvox-tone-editor--duration :transient t)
   ("v" (lambda () (emacsvox-tone-editor--number-label :volume)) emacsvox-tone-editor--volume :transient t)
   ("w" (lambda () (concat "Waveform: " (emacsvox-tone-editor--name (emacsvox-tone-editor--get :waveform)))) emacsvox-tone-editor-waveform :transient transient--do-stack)
   ("u" (lambda () (concat (emacsvox-tone-editor--number-label :width) (unless (eq (emacsvox-tone-editor--get :waveform) 'pulse) "; used with Pulse"))) emacsvox-tone-editor--width :transient t)]
  ["Pitch movement"
   ("t" (lambda () (concat "Pitch sweep: " (if (emacsvox-tone-editor--get :sweep) "on" "off"))) emacsvox-tone-editor--sweep :transient t)
   ("f" (lambda () (emacsvox-tone-editor--number-label :end-pitch)) emacsvox-tone-editor--end-pitch :transient t)]
  ["Envelope (stage controls apply to ADSR)"
   ("e" (lambda () (concat "Envelope: " (emacsvox-tone-editor--name (emacsvox-tone-editor--get :envelope)))) emacsvox-tone-editor-envelope :transient transient--do-stack)
   ("k" (lambda () (concat "Curve: " (emacsvox-tone-editor--name (emacsvox-tone-editor--get :curve)))) emacsvox-tone-editor-curve :transient transient--do-stack)
   ("a" (lambda () (emacsvox-tone-editor--number-label :attack)) emacsvox-tone-editor--attack :transient t)
   ("c" (lambda () (emacsvox-tone-editor--number-label :decay)) emacsvox-tone-editor--decay :transient t)
   ("s" (lambda () (emacsvox-tone-editor--number-label :sustain)) emacsvox-tone-editor--sustain :transient t)
   ("r" (lambda () (emacsvox-tone-editor--number-label :release)) emacsvox-tone-editor--release :transient t)]
  ["Preview"
   ("SPC" "Play tone alone" emacsvox-tone-editor--tone :transient t)
   ("C" (lambda () (emacsvox-tone-editor--label :current-label "Play current tone")) emacsvox-tone-editor--current :transient t)
   ("P" "Read sample" emacsvox-tone-editor--sample :transient t)
   ("S" "Stop preview" emacsvox-tone-editor--stop :transient t)]
  ["Presets"
   ("L" "Load preset into draft" emacsvox-tone-editor-presets :transient transient--do-stack)
   ("N" "Save draft as named preset" emacsvox-tone-editor--save-preset :transient t)]
  ["Apply and save"
   ("R" "Reset draft to factory defaults" emacsvox-tone-editor--reset :transient t)
   ("A" (lambda () (emacsvox-tone-editor--label :apply-label "Apply for session")) emacsvox-tone-editor--apply :transient t)
   ("W" (lambda () (emacsvox-tone-editor--label :save-label "Save and apply tone defaults")) emacsvox-tone-editor--save :transient t)]
  ["Finish"
   ("q" "Back (discard unapplied edits)" emacsvox-tone-editor--back :transient transient--do-quit-one)
   ("C-q" "Close menus" transient-quit-all)]
  (interactive)
  (emacsvox-tone-editor--state)
  (transient-setup 'emacsvox-tone-editor nil nil :scope (emacsvox-aural-menu--context)))

(defun emacsvox-tone-editor--open (context provider)
  "Open a draft editor for cue PROVIDER using source CONTEXT.
PROVIDER supplies :label, :read, :apply and :preview callbacks. Optional
:current reads comparison values; label/message overrides describe the
provider's scope and persistence. :read with non-nil requests factory values."
  (emacsvox-aural-menu--source context)
  (let ((scope (append (list :tone-editor
                            (list :provider provider :draft (funcall (plist-get provider :read))))
                       context)))
    (transient-setup 'emacsvox-tone-editor nil nil :scope scope)))

(provide 'emacsvox-tone-editor)
;;; emacsvox-tone-editor.el ends here
