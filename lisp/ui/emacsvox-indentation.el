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

(declare-function emacsvox-tone-editor--data "emacsvox-tone-editor" (pitch duration volume shape))
(declare-function emacsvox-tone-editor--shape "emacsvox-tone-editor" (data))
(declare-function emacsvox-tone-editor--open "emacsvox-tone-editor" (context provider))
(declare-function emacsvox-aural-menu--capture "emacsvox-aural-menu" (global))

(defun emacsvox-indentation--state ()
  "Return the active menu's source buffer and global scope flag."
  (let* ((prefix (or transient--prefix transient-current-prefix))
         (command (and prefix (oref prefix command))))
    (cond ((memq command '(emacsvox-indentation emacsvox-indentation-tone))
           (oref prefix scope))
          ((and (eq command 'emacsvox-tone-editor)
                (plist-get (oref prefix scope) :indentation-state)))
          (t (user-error "Open the indentation menu first")))))

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
  "Choose whether subsequent changes affect this buffer or global defaults."
  (interactive)
  (let ((state (emacsvox-indentation--state)))
    (setcdr state (not (cdr state)))
    (emacsvox-indentation--say
     (if (cdr state) "Editing global defaults" "Editing current buffer"))))

(defun emacsvox-indentation--toggle ()
  "Turn indentation feedback on or off for this buffer or global defaults."
  (interactive)
  (let ((enabled (not (emacsvox-indentation--value 'emacsvox-audio-indentation))))
    (emacsvox-indentation--set 'emacsvox-audio-indentation enabled
                              (propertize
                               (if enabled "Indentation on" "Indentation off")
                               'emacsvox-transient-toggle-state
                               (if enabled 'on 'off)))))

(defun emacsvox-indentation--preview (&optional pitch-tone)
  "Hear four columns with these settings, even when feedback is off.
With PITCH-TONE, preview rising pitch even if another presentation is selected."
  (interactive)
  (let ((presentation (emacsvox-indentation--value 'emacsvox-indentation-presentation))
        (timing (emacsvox-indentation--value 'emacsvox-indentation-tone-timing))
        (base (emacsvox-indentation--value 'emacsvox-indentation-pitch-tone-base))
        (rise (emacsvox-indentation--value 'emacsvox-indentation-pitch-tone-semitones-per-column))
        (maximum (emacsvox-indentation--value 'emacsvox-indentation-pitch-tone-maximum))
        (duration (emacsvox-indentation--value 'emacsvox-indentation-pitch-tone-duration))
        (volume (emacsvox-indentation--value 'emacsvox-indentation-pitch-tone-volume))
        (shape (emacsvox-indentation--value 'emacsvox-indentation-pitch-tone-shape)))
    (with-current-buffer (emacsvox-indentation--source)
      (let ((emacsvox-audio-indentation t)
            (emacsvox-indentation-presentation
             (if (and pitch-tone (not (memq presentation '(pitch-tone spoken-pitch-tone))))
                 'pitch-tone presentation))
            (emacsvox-indentation-tone-timing timing)
            (emacsvox-indentation-pitch-tone-base base)
            (emacsvox-indentation-pitch-tone-semitones-per-column rise)
            (emacsvox-indentation-pitch-tone-maximum maximum)
            (emacsvox-indentation-pitch-tone-duration duration)
            (emacsvox-indentation-pitch-tone-volume volume)
            (emacsvox-indentation-pitch-tone-shape shape))
        (emacsvox-speak--preview-indentation-presentation)))))

(defconst emacsvox-indentation--tone-controls
  '((emacsvox-indentation--base emacsvox-indentation-pitch-tone-base "Base pitch" "Hz" 25 1)
    (emacsvox-indentation--rise emacsvox-indentation-pitch-tone-semitones-per-column "Rise per column" "semitones" 0.25 0)
    (emacsvox-indentation--maximum emacsvox-indentation-pitch-tone-maximum "Maximum pitch" "Hz" 100 1)
    (emacsvox-indentation--duration emacsvox-indentation-pitch-tone-duration "Requested duration" "milliseconds" 10 0)
    (emacsvox-indentation--tone-volume emacsvox-indentation-pitch-tone-volume "Pitch-tone volume" "percent" 5 0))
  "Pitch-tone controls: command, option, label, units, step, and lower bound.")

(defun emacsvox-indentation--tone-label (command)
  "Describe pitch-tone COMMAND and any duration floor."
  (let* ((control (assq command emacsvox-indentation--tone-controls))
         (value (emacsvox-indentation--value (nth 1 control)))
         (floor (emacsvox-speak--blank-line-tone-duration)))
    (concat (format "%s: %s %s" (nth 2 control) value (nth 3 control))
            (when (and (eq command 'emacsvox-indentation--duration) (< value floor))
              (format "; effective %s milliseconds" floor)))))

(defun emacsvox-indentation--tone-edit (command &optional direction)
  "Edit pitch-tone COMMAND exactly, or step it in DIRECTION."
  (let* ((control (assq command emacsvox-indentation--tone-controls))
         (symbol (nth 1 control))
         (current (emacsvox-indentation--value symbol))
         (minimum (nth 5 control))
         (maximum (pcase command
                    ('emacsvox-indentation--base
                     (emacsvox-indentation--value 'emacsvox-indentation-pitch-tone-maximum))
                    ('emacsvox-indentation--tone-volume 100)))
         (minimum (if (eq command 'emacsvox-indentation--maximum)
                      (emacsvox-indentation--value 'emacsvox-indentation-pitch-tone-base)
                    minimum))
         (value
          (if direction
              (let ((next (max minimum (+ current (* direction (nth 4 control))))))
                (if maximum (min maximum next) next))
            ;; Select the edited control before prompting so arrows work on return.
            (let ((prefix transient--prefix)
                  (suffix (cl-find command transient--suffixes
                                   :key (lambda (item) (oref item command)))))
              (unwind-protect
                  (read-number (format "%s in %s: " (nth 2 control) (nth 3 control)) current)
                (when (and suffix prefix (eq transient--prefix prefix))
                  (transient--show)
                  (with-selected-window transient--window
                    (transient--goto-button suffix))))))))
    (unless (and (numberp value) (= (- value value) 0)
                 (>= value minimum) (or (null maximum) (<= value maximum))
                 (or (not (eq command 'emacsvox-indentation--duration)) (integerp value)))
      (user-error "%s must be finite, at least %s%s%s"
                  (nth 2 control) minimum
                  (if maximum (format ", at most %s" maximum) "")
                  (if (eq command 'emacsvox-indentation--duration) ", and an integer" "")))
    (emacsvox-indentation--set
     symbol value
     (concat (when (and direction (= current value))
               (if (> direction 0) "Maximum. " "Minimum. "))
             (format "%s %s" value (nth 3 control))
             (when (and (eq command 'emacsvox-indentation--duration)
                        (< value (emacsvox-speak--blank-line-tone-duration)))
               (format "; effective %s milliseconds" (emacsvox-speak--blank-line-tone-duration)))))))

(defun emacsvox-indentation--tone-volume ()
  "Set rising-pitch indentation volume; Shift arrows step by five percent.
Apply immediately in the selected buffer/global scope. This affects pitch-tone
and spoken-pitch-tone; duration-coded tones are unchanged. Shared main-tone
volume still scales this level. S saves global defaults through Customize."
  (interactive)
  (emacsvox-indentation--tone-edit 'emacsvox-indentation--tone-volume))

(defun emacsvox-indentation--base ()
  "Set the first column pitch; Shift arrows change it by 25 Hz." (interactive)
  (emacsvox-indentation--tone-edit 'emacsvox-indentation--base))
(defun emacsvox-indentation--rise ()
  "Set pitch rise per column; Shift arrows change it by 0.25 semitones." (interactive)
  (emacsvox-indentation--tone-edit 'emacsvox-indentation--rise))
(defun emacsvox-indentation--maximum ()
  "Set the pitch ceiling; Shift arrows change it by 100 Hz." (interactive)
  (emacsvox-indentation--tone-edit 'emacsvox-indentation--maximum))
(defun emacsvox-indentation--duration ()
  "Set requested tone duration; Shift arrows change it by 10 ms." (interactive)
  (emacsvox-indentation--tone-edit 'emacsvox-indentation--duration))

(defun emacsvox-indentation--tone-reset ()
  "Restore the four bundled pitch-tone values in the displayed scope."
  (interactive)
  (with-current-buffer (emacsvox-indentation--source)
    (dolist (control emacsvox-indentation--tone-controls)
      (let* ((symbol (nth 1 control))
             (value (eval (car (get symbol 'standard-value)) t)))
        (if (cdr (emacsvox-indentation--state)) (set-default symbol value)
          (set (make-local-variable symbol) value)))))
  (emacsvox-indentation--say "Restored bundled pitch-tone settings. Not saved."))

(defun emacsvox-indentation--tone-preview ()
  "Preview four columns as a pitch tone without changing the chosen presentation."
  (interactive)
  (emacsvox-indentation--preview t))

(defconst emacsvox-indentation--editor-fields
  '((:pitch . emacsvox-indentation-pitch-tone-base)
    (:duration . emacsvox-indentation-pitch-tone-duration)
    (:volume . emacsvox-indentation-pitch-tone-volume))
  "Rising-pitch options represented by the shared tone editor.")

(defun emacsvox-indentation--tone-data (&optional factory)
  "Read the selected scope's base tone, or FACTORY tone values."
  (let ((read (if factory (lambda (symbol) (eval (car (get symbol 'standard-value)) t))
                #'emacsvox-indentation--value)))
    (emacsvox-tone-editor--data
     (funcall read 'emacsvox-indentation-pitch-tone-base)
     (funcall read 'emacsvox-indentation-pitch-tone-duration)
     (funcall read 'emacsvox-indentation-pitch-tone-volume)
     (funcall read 'emacsvox-indentation-pitch-tone-shape))))

(defun emacsvox-indentation--apply-tone (data save)
  "Apply base tone DATA in the captured scope; SAVE requires global scope."
  (let* ((state (emacsvox-indentation--state))
         (shape (emacsvox-tone-editor--shape data))
         (values (append
                  (mapcar (lambda (field) (cons (cdr field) (plist-get data (car field))))
                          emacsvox-indentation--editor-fields)
                  (list (cons 'emacsvox-indentation-pitch-tone-shape shape)))))
    (when (and save (not (cdr state)))
      (user-error "Return to Indentation and select Global defaults before saving"))
    (when (> (plist-get data :pitch) (emacsvox-indentation--value 'emacsvox-indentation-pitch-tone-maximum))
      (user-error "Base pitch exceeds the maximum; adjust the parent menu's Maximum pitch first"))
    (with-current-buffer (emacsvox-indentation--source)
      (dolist (entry values)
        (cond (save (customize-save-variable (car entry) (cdr entry)))
              ((cdr state) (set-default (car entry) (cdr entry)))
              (t (set (make-local-variable (car entry)) (cdr entry))))))))

(defun emacsvox-indentation--preview-draft (data sample)
  "Preview base tone DATA alone, or SAMPLE at four indentation columns."
  (when (> (plist-get data :pitch) (emacsvox-indentation--value 'emacsvox-indentation-pitch-tone-maximum))
    (user-error "Base pitch exceeds the maximum; adjust Maximum pitch in the parent menu"))
  (let ((rise (emacsvox-indentation--value 'emacsvox-indentation-pitch-tone-semitones-per-column))
        (maximum (emacsvox-indentation--value 'emacsvox-indentation-pitch-tone-maximum))
        (timing (emacsvox-indentation--value 'emacsvox-indentation-tone-timing))
        (emacsvox-aural--exact-tone-preview t)
        (shape (emacsvox-tone-editor--shape data)))
    (with-current-buffer (emacsvox-indentation--source)
      (let ((emacsvox-audio-indentation t)
            (emacsvox-indentation-presentation 'pitch-tone)
            (emacsvox-indentation-tone-timing timing)
            (emacsvox-indentation-pitch-tone-base (plist-get data :pitch))
            (emacsvox-indentation-pitch-tone-duration (plist-get data :duration))
            (emacsvox-indentation-pitch-tone-volume (plist-get data :volume))
            (emacsvox-indentation-pitch-tone-shape shape)
            (emacsvox-indentation-pitch-tone-semitones-per-column rise)
            (emacsvox-indentation-pitch-tone-maximum maximum))
        (emacsvox-aural--tone-volume-deliverable-p (/ (plist-get data :volume) 100.0))
        (emacsvox-aural--tone-shape-deliverable-p shape)
        (if sample (emacsvox-speak--preview-indentation-presentation)
          (emacsvox-aural-submit-actions
           :facts (emacsvox-speak--indentation-facts 1) :module 'speak :occasion 'inspection
           :lane 'main :delivery-policy 'urgent :interruption-policy 'lane))))))

(defun emacsvox-indentation--edit-tone ()
  "Edit a private base-tone draft in the selected indentation scope.
Space previews the first column's tone; P reads a four-column sample. Actual
pitch rises by column and duration retains the blank-line minimum. A applies
only tone fields to this buffer or global defaults; W saves global tone fields
only. Rise, maximum, timing, enablement and shared volume remain in the parent.
Duration-coded tones are unchanged. Sweeps end at an absolute frequency."
  (interactive)
  ;; The shared editor loads the aural menu, which itself loads Indentation.
  (require 'emacsvox-tone-editor)
  (let* ((state (copy-tree (emacsvox-indentation--state)))
         (global (cdr state))
         (context (with-current-buffer (emacsvox-indentation--source)
                    (emacsvox-aural-menu--capture global))))
    (emacsvox-tone-editor--open
     (plist-put context :indentation-state state)
     (list :label (if global "Indentation base tone (global draft)" "Indentation base tone (buffer draft)")
           :read #'emacsvox-indentation--tone-data
           :apply #'emacsvox-indentation--apply-tone
           :apply-label (if global "Apply to global defaults for session" "Apply to source buffer")
           :apply-message (if global "Global base tone applied; buffer overrides remain" "Base tone applied to source buffer")
           :save-label (if global "Save global base-tone defaults" "Save requires global scope")
           :preview #'emacsvox-indentation--preview-draft))))

(defun emacsvox-indentation--stop ()
  "Stop the indentation preview." (interactive) (tts-stop))

(defun emacsvox-indentation--volume (&optional delta)
  "Set shared main-tone volume; Shift arrows change it by 5 percentage points.
Enter a volume from 0 to 100 for all main-stream tones.
When called from Lisp, adjust by DELTA percentage points if non-nil."
  (interactive)
  (emacsvox-indentation--source)
  (let ((value (if delta
                   (max 0 (min 100 (+ (default-value 'tts-main-tone-volume) delta)))
                 (emacsvox-transient--read #'read-number "Global tone volume (0 to 100): "
                              (default-value 'tts-main-tone-volume)))))
    (tts--validate-output-volume value)
    (customize-set-variable 'tts-main-tone-volume value)
    (emacsvox-indentation--say (format "%d percent" value))))

(defun emacsvox-indentation--adjust (delta)
  "Adjust Volume by DELTA, or a pitch-tone control by one step in its direction."
  (emacsvox-indentation--source)
  (let ((object
         (with-selected-window (emacsvox-transient--navigation-window)
           (when-let* ((button (button-at (point))))
             (button-get button 'button-data)))))
    (cond
     ((and (eieio-object-p object)
           (eq (oref object command) 'emacsvox-indentation--volume))
      (emacsvox-indentation--volume delta))
     ((and (eieio-object-p object)
           (assq (oref object command) emacsvox-indentation--tone-controls))
      (emacsvox-indentation--tone-edit (oref object command) (if (> delta 0) 1 -1)))
     (t (emacsvox-transient--submit-text
       "Not adjustable. Enter activates; left and right change sections."
       (emacsvox-transient--item-facts 'command 'adjust 'operation-failed)
       'state-change 'warn-user)))))

(defun emacsvox-indentation--decrease ()
  "Lower the selected numeric control by one step."
  (interactive)
  (emacsvox-indentation--adjust -5))

(defun emacsvox-indentation--increase ()
  "Raise the selected numeric control by one step."
  (interactive)
  (emacsvox-indentation--adjust 5))

(defun emacsvox-indentation--navigation-bindings (map)
  "Add shifted-arrow adjustment to MAP only for Indentation."
  (when (and transient-enable-menu-navigation transient--prefix
             (memq (oref transient--prefix command)
                   '(emacsvox-indentation emacsvox-indentation-tone)))
    (keymap-set map "S-<left>" #'emacsvox-indentation--decrease)
    (keymap-set map "S-<right>" #'emacsvox-indentation--increase))
  map)

(advice-add 'transient--make-transient-map :filter-return
            #'emacsvox-indentation--navigation-bindings)
(define-key transient-predicate-map [emacsvox-indentation--decrease]
            #'transient--do-stay)
(define-key transient-predicate-map [emacsvox-indentation--increase]
            #'transient--do-stay)

(defun emacsvox-indentation--save ()
  "Keep global indentation settings and tone volume across restarts.
Switch to Global defaults before saving; buffer-local choices are not saved."
  (interactive)
  (emacsvox-indentation--source)
  (unless (cdr (emacsvox-indentation--state))
    (user-error "Switch to Global defaults before saving"))
  (dolist (symbol '(emacsvox-audio-indentation emacsvox-indentation-presentation
                   emacsvox-indentation-tone-timing tts-main-tone-volume
                   emacsvox-indentation-pitch-tone-base
                   emacsvox-indentation-pitch-tone-semitones-per-column
                   emacsvox-indentation-pitch-tone-maximum
                   emacsvox-indentation-pitch-tone-duration
                   emacsvox-indentation-pitch-tone-volume
                   emacsvox-indentation-pitch-tone-shape))
    (customize-save-variable symbol (default-value symbol)))
  (emacsvox-indentation--say "Saved global indentation defaults and tone volume"))

(defun emacsvox-indentation--setup (state)
  "Open Indentation with STATE containing a source buffer and global flag.
Linked menus may share STATE so changes of scope survive parent navigation."
  (unless (buffer-live-p (car state))
    (user-error "The indentation source buffer has been closed"))
  (transient-setup 'emacsvox-indentation nil nil :scope state))

(transient-define-prefix emacsvox-indentation-tone ()
  "Tune rising-pitch indentation tones in the selected scope."
  :refresh-suffixes t
  ["Pitch-tone settings"
   ("g" (lambda () (if (cdr (emacsvox-indentation--state)) "Scope: Global defaults" "Scope: Current buffer")) emacsvox-indentation--scope :transient t)
   ("b" (lambda () (emacsvox-indentation--tone-label 'emacsvox-indentation--base)) emacsvox-indentation--base :transient t)
   ("r" (lambda () (emacsvox-indentation--tone-label 'emacsvox-indentation--rise)) emacsvox-indentation--rise :transient t)
   ("m" (lambda () (emacsvox-indentation--tone-label 'emacsvox-indentation--maximum)) emacsvox-indentation--maximum :transient t)
   ("d" (lambda () (emacsvox-indentation--tone-label 'emacsvox-indentation--duration)) emacsvox-indentation--duration :transient t)
   ("v" (lambda () (emacsvox-indentation--tone-label 'emacsvox-indentation--tone-volume)) emacsvox-indentation--tone-volume :transient t)
   ("E" "Base-tone editor: waveform, envelope and presets" emacsvox-indentation--edit-tone :transient transient--do-stack)]
  ["Try and finish"
   ("SPC" "Preview four-column pitch tone" emacsvox-indentation--tone-preview :transient t)
   ("s" "Stop preview" emacsvox-indentation--stop :transient t)
   ("R" "Restore bundled pitch-tone settings" emacsvox-indentation--tone-reset :transient t)
   ("S" "Save global indentation defaults and volume" emacsvox-indentation--save
    :inapt-if-not (lambda () (cdr (emacsvox-indentation--state))) :transient t)
   ("q" "Back (keep changes)" transient-quit-one)
   ("C-q" "Close all menus" transient-quit-all)]
  (interactive)
  (let ((state (emacsvox-indentation--state)))
    (emacsvox-indentation--source)
    (transient-setup 'emacsvox-indentation-tone nil nil :scope state)))

;;;###autoload
(transient-define-prefix emacsvox-indentation (&optional global)
  "Choose indentation feedback for the current buffer or global defaults.
With prefix GLOBAL, start with global defaults.  Changes apply immediately;
closing the menu keeps them.  Global changes preserve buffer-local choices.
Save defaults explicitly to retain them across sessions. Pitch-tone volume
uses the selected scope. Shared tone volume always affects all main-stream
Omnivox tones, independently of that scope.
Up/down selects a control; left/right changes sections.  Shift-left/right
adjusts Volume by five percentage points.  Space previews the indentation settings."
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
    (lambda () "Speak the indentation column number."
      (interactive) (emacsvox-indentation--set 'emacsvox-indentation-presentation 'spoken "Spoken column")) :transient t)
   ("p" (lambda () (emacsvox-indentation--choice 'emacsvox-indentation-presentation 'pitch-tone "Pitch tone"))
    (lambda () "Use a higher pitch for deeper indentation, with a fixed tone duration."
      (interactive) (emacsvox-indentation--set 'emacsvox-indentation-presentation 'pitch-tone "Pitch tone")) :transient t)
   ("d" (lambda () (emacsvox-indentation--choice 'emacsvox-indentation-presentation 'duration-tone "Duration tone"))
    (lambda () "Use a longer tone for deeper indentation, with a fixed pitch."
      (interactive) (emacsvox-indentation--set 'emacsvox-indentation-presentation 'duration-tone "Duration tone")) :transient t)
   ("P" (lambda () (emacsvox-indentation--choice 'emacsvox-indentation-presentation 'spoken-pitch-tone "Spoken column and pitch tone"))
    (lambda () "Speak the column number and use a higher pitch for deeper indentation."
      (interactive) (emacsvox-indentation--set 'emacsvox-indentation-presentation 'spoken-pitch-tone "Spoken column and pitch tone")) :transient t)
   ("D" (lambda () (emacsvox-indentation--choice 'emacsvox-indentation-presentation 'spoken-duration-tone "Spoken column and duration tone"))
    (lambda () "Speak the column number and use a longer tone for deeper indentation."
      (interactive) (emacsvox-indentation--set 'emacsvox-indentation-presentation 'spoken-duration-tone "Spoken column and duration tone")) :transient t)
   ("c" (lambda () (emacsvox-indentation--choice 'emacsvox-indentation-presentation 'custom "Personal rules"))
    (lambda () "Use your aural rules to present indentation instead of a built-in style."
      (interactive) (emacsvox-indentation--set 'emacsvox-indentation-presentation 'custom "Personal rules")) :transient t)
   ("n" (lambda () (emacsvox-indentation--choice 'emacsvox-indentation-presentation 'none "No indication"))
    (lambda () "Suppress the built-in spoken column and indentation tone."
      (interactive) (emacsvox-indentation--set 'emacsvox-indentation-presentation 'none "No indication")) :transient t)]
  ["Tone timing"
   ("b" (lambda () (emacsvox-indentation--choice 'emacsvox-indentation-tone-timing 'insert "Before speech"))
    (lambda () "Finish the indentation tone before speaking the line."
      (interactive) (emacsvox-indentation--set 'emacsvox-indentation-tone-timing 'insert "Tone before speech"))
    :inapt-if-not emacsvox-indentation--tonal-p :transient t)
   ("a" (lambda () (emacsvox-indentation--choice 'emacsvox-indentation-tone-timing 'overlay "Alongside speech"))
    (lambda () "Play the indentation tone at the same time as the line is spoken."
      (interactive) (emacsvox-indentation--set 'emacsvox-indentation-tone-timing 'overlay "Tone alongside speech"))
    :inapt-if-not emacsvox-indentation--tonal-p :transient t)
   ("t" "Pitch-tone settings" emacsvox-indentation-tone :transient transient--do-stack)]
  ["Tone levels"
   ("l" (lambda () (emacsvox-indentation--tone-label 'emacsvox-indentation--tone-volume)) emacsvox-indentation--tone-volume :transient t)
   ("v" (lambda () (format "Shared tone volume: %d percent" (default-value 'tts-main-tone-volume)))
    emacsvox-indentation--volume :transient t)
   ("-" "Volume down 5 percent" (lambda () "Lower all main-stream tones by five percentage points; speech volume stays unchanged."
      (interactive) (emacsvox-indentation--volume -5)) :transient t)
   ("+" "Volume up 5 percent" (lambda () "Raise all main-stream tones by five percentage points; speech volume stays unchanged."
      (interactive) (emacsvox-indentation--volume 5)) :transient t)]
  ["Try and finish"
   ("SPC" "Preview four-column indentation" emacsvox-indentation--preview :transient t)
   ("S" "Save global defaults and volume" emacsvox-indentation--save
    :inapt-if-not (lambda () (cdr (emacsvox-indentation--state))) :transient t)
   ("q" "Close (keep changes)" transient-quit-one)]
  (interactive "P")
  (emacsvox-indentation--setup (cons (current-buffer) (and global t))))

(provide 'emacsvox-indentation)
;;; emacsvox-indentation.el ends here
