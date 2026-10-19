;;; emacsvox-speak-presentation.el --- Point and indentation presentation -*- lexical-binding: t; -*-

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

;; Point and indentation presentation.
;; The core speech facade retains activation in its established order.

;;; Code:

(require 'cl-lib)
(require 'tts-speak)
(require 'emacsvox-aural-submission)

(declare-function emacsvox-speak-line "emacsvox-speak" (&optional arg))

;;;  Showing the point:

(defcustom emacsvox-show-point-presentation 'voice
  "How `emacsvox-speak-line' presents buffer point.

`voice' applies the animated voice to the character at point.  `tone' and
`earcon' place a short marker at the exact text boundary.  `voice-tone' and
`voice-earcon' combine the corresponding presentations.  `spoken' says
\"point\" at the boundary.  `custom' publishes point facts for personal aural
rules without adding a built-in presentation, and `none' suppresses point
presentation while leaving `emacsvox-show-point' enabled."
  :type
  '(choice
    (const :tag "Animated voice" voice)
    (const :tag "Micro-tone" tone)
    (const :tag "Earcon" earcon)
    (const :tag "Animated voice and micro-tone" voice-tone)
    (const :tag "Animated voice and earcon" voice-earcon)
    (const :tag "Spoken word: point" spoken)
    (const :tag "Personal aural rules" custom)
    (const :tag "No point presentation" none))
  :group 'emacsvox-aural)

(defvar emacsvox-show-point nil
  "If T, command `emacsvox-speak-line' \\[emacsvox-speak-line]
indicates position of point by an aural highlight.
Command `emacsvox-toggle-show-point' bound to
\\[emacsvox-toggle-show-point] toggles this setting.  The presentation is
selected by `emacsvox-show-point-presentation'.")

(ems-generate-switcher 'emacsvox-toggle-show-point
                       'emacsvox-show-point
                       "Toggle state of  Emacsvox-show-point.
Interactive PREFIX arg means toggle  the global default value, and then set the
current local  value to the result.")

(defconst emacsvox-show-point-presentation-values
  '(voice tone earcon voice-tone voice-earcon spoken custom none)
  "Supported values of `emacsvox-show-point-presentation'.")

(defun emacsvox-set-show-point-presentation (presentation &optional global)
  "Select point PRESENTATION and preview the current line.

Set the option buffer-locally by default.  With interactive prefix GLOBAL,
also set the global default and use it in the current buffer."
  (interactive
   (list
    (intern
     (completing-read
      "Point presentation: "
      (mapcar #'symbol-name emacsvox-show-point-presentation-values)
      nil t nil nil
      (symbol-name emacsvox-show-point-presentation)))
    current-prefix-arg))
  (unless (memq presentation emacsvox-show-point-presentation-values)
    (user-error "Unknown point presentation: %S" presentation))
  (when global
    (set-default 'emacsvox-show-point-presentation presentation))
  (setq-local emacsvox-show-point-presentation presentation)
  (when (called-interactively-p 'interactive)
    (let ((emacsvox-show-point t))
      (emacsvox-speak-line)))
  presentation)

(defun emacsvox-speak--point-facts (position start end)
  "Return semantic point facts for POSITION between START and END.

Return nil when point presentation is disabled."
  (when
      (and
       emacsvox-show-point
       (not (eq emacsvox-show-point-presentation 'none)))
    (let* ((empty (= start end))
           (location
            (cond
             (empty 'empty)
             ((<= position start) 'beginning)
             ((>= position end) 'end)
             (t 'interior)))
           (boundary
            (if (and (not empty) (>= position end)) 'after 'before)))
      (list
       :events '(point-located)
       :point-position location
       :point-boundary boundary
       :point-presentation emacsvox-show-point-presentation))))

(defun emacsvox-speak--annotate-point (text position start end facts)
  "Attach point FACTS to the appropriate character in TEXT.

POSITION, START, and END are source-buffer positions.  At END, attach the
facts to the final character while `point-boundary' records that non-content
feedback belongs after it."
  (when (and facts (> (length text) 0))
    (let* ((offset
            (cond
             ((<= position start) 0)
             ((>= position end) (1- (length text)))
             (t (min (1- (length text)) (- position start)))))
           (existing
            (get-text-property offset emacsvox-aural-facts-property text)))
      (add-text-properties
       offset (1+ offset)
       (list
        emacsvox-aural-facts-property
        (emacsvox-aural-merge-facts existing facts))
       text)))
  text)

;;;   indentation:

(defcustom emacsvox-audio-indentation nil
  "Option indicating if line indentation is cued.
You can use command `emacsvox-toggle-audio-indentation' bound to
\\[emacsvox-toggle-audio-indentation] to toggle this setting."
  :type 'boolean
  :group 'emacsvox-aural)

(make-variable-buffer-local 'emacsvox-audio-indentation)

(defcustom emacsvox-indentation-presentation 'spoken
  "How enabled line indentation is presented.

`spoken' says the indentation column.  `duration-tone' uses a fixed pitch and
increases duration with indentation.  `pitch-tone' uses a fixed duration and
raises pitch with indentation.  The two `spoken-...-tone' values combine the
corresponding tone with speech.  `custom' publishes indentation facts for
personal aural rules, and `none' suppresses presentation while leaving
`emacsvox-audio-indentation' enabled."
  :type
  '(choice
    (const :tag "Spoken indentation column" spoken)
    (const :tag "Duration-coded tone" duration-tone)
    (const :tag "Rising-pitch tone" pitch-tone)
    (const :tag "Spoken column and duration-coded tone"
           spoken-duration-tone)
    (const :tag "Spoken column and rising-pitch tone"
           spoken-pitch-tone)
    (const :tag "Personal aural rules" custom)
    (const :tag "No indentation presentation" none))
  :group 'emacsvox-aural)

(defconst emacsvox-indentation-presentation-values
  '(spoken duration-tone pitch-tone
    spoken-duration-tone spoken-pitch-tone custom none)
  "Supported values of `emacsvox-indentation-presentation'.")

(defcustom emacsvox-indentation-tone-timing 'overlay
  "When indentation tones play relative to the line's speech.

`overlay' plays the tone alongside speech.  `insert' finishes the tone
before speaking the line.  This affects the built-in tonal indentation
presentations; spoken-only feedback is unchanged.  Backends without overlay
support play the tone before speech in either case."
  :type '(choice (const :tag "Alongside speech" overlay)
                 (const :tag "Before speech" insert))
  :group 'emacsvox-aural)

(defcustom emacsvox-indentation-pitch-tone-base 250.0
  "Pitch in hertz for the first nonzero indentation column."
  :type 'number
  :group 'emacsvox-aural)

(defcustom emacsvox-indentation-pitch-tone-semitones-per-column 1.0
  "Pitch rise in semitones for each additional indentation column."
  :type 'number
  :group 'emacsvox-aural)

(defcustom emacsvox-indentation-pitch-tone-maximum 2000.0
  "Maximum pitch in hertz for rising-pitch indentation tones."
  :type 'number
  :group 'emacsvox-aural)

(defcustom emacsvox-indentation-pitch-tone-duration 150
  "Requested duration in milliseconds for rising-pitch indentation tones.

The actual duration is never shorter than the registered blank-line tone."
  :type 'integer
  :group 'emacsvox-aural)

(defconst emacsvox-speak--indentation-duration-tone-pitch 250.0
  "Fixed pitch in hertz for duration-coded indentation tones.")

(defcustom emacsvox-indentation-pitch-tone-volume 100
  "Individual volume percentage for rising-pitch indentation tones.
This multiplies shared main-tone volume. Duration-coded tones are unchanged."
  :type '(integer :tag "Percent")
  :group 'emacsvox-aural)

(defcustom emacsvox-indentation-pitch-tone-shape '(:waveform sine)
  "Waveform, optional pitch sweep and envelope for rising-pitch indentation.
An optional sweep ends at its absolute configured frequency. The starting
pitch still rises with indentation; duration-coded tones remain unchanged."
  :type 'plist
  :group 'emacsvox-aural)

(defconst emacsvox-speak--indentation-duration-tone-base 50
  "Base duration in milliseconds for duration-coded indentation tones.")

(defconst emacsvox-speak--indentation-duration-tone-per-column 20
  "Milliseconds added per indentation column in duration-coded tones.")

(defun emacsvox-speak--blank-line-tone-duration ()
  "Return the registered blank-line tone duration in milliseconds."
  (if-let* ((tone (emacsvox-aural-tone 'line-empty)))
      (ceiling (emacsvox-aural-tone-duration tone))
    150))

(defun emacsvox-speak--indentation-pitch (columns)
  "Return rising indentation pitch in hertz for COLUMNS."
  (let* ((base (max 1.0 (float emacsvox-indentation-pitch-tone-base)))
         (step
          (max
           0.0
           (float emacsvox-indentation-pitch-tone-semitones-per-column)))
         (maximum
          (max base (float emacsvox-indentation-pitch-tone-maximum)))
         (semitones (* (max 0 (1- columns)) step)))
    (min maximum (* base (expt 2.0 (/ semitones 12.0))))))

(defun emacsvox-speak--indentation-tone-values (columns presentation)
  "Return the pitch and duration pair for COLUMNS and PRESENTATION."
  (pcase presentation
    ((or 'duration-tone 'spoken-duration-tone)
     (cons
      emacsvox-speak--indentation-duration-tone-pitch
      (+
       emacsvox-speak--indentation-duration-tone-base
       (* emacsvox-speak--indentation-duration-tone-per-column columns))))
    ((or 'pitch-tone 'spoken-pitch-tone)
     (cons
      (emacsvox-speak--indentation-pitch columns)
      (max
       (emacsvox-speak--blank-line-tone-duration)
       (ceiling (max 0 emacsvox-indentation-pitch-tone-duration)))))))

(defun emacsvox-speak--indentation-facts (columns)
  "Return semantic indentation facts for COLUMNS, or nil when disabled."
  (when
      (and
       emacsvox-audio-indentation
       (> columns 0)
       (memq
        emacsvox-indentation-presentation
        emacsvox-indentation-presentation-values)
       (not (eq emacsvox-indentation-presentation 'none)))
    (let ((facts
           (list
            :events '(indentation-located)
            :indentation-columns columns
            :indentation-presentation emacsvox-indentation-presentation)))
      (when-let*
          ((tone
            (emacsvox-speak--indentation-tone-values
             columns emacsvox-indentation-presentation)))
        (setq
         facts
         (append
          facts
          (list
           :indentation-tone-pitch (car tone)
           :indentation-tone-duration (cdr tone)
           :indentation-tone-timing emacsvox-indentation-tone-timing)))
        (when (memq emacsvox-indentation-presentation '(pitch-tone spoken-pitch-tone))
          (setq facts
                (append facts
                        (list :indentation-tone-volume (/ emacsvox-indentation-pitch-tone-volume 100.0)
                              :indentation-tone-shape (copy-tree emacsvox-indentation-pitch-tone-shape))))))
      facts)))

(defun emacsvox-speak--annotate-indentation (text facts)
  "Attach indentation FACTS across the first content token in TEXT.

Covering the token keeps its first character in the same synthesis span as
the rest of the word.  Existing range-local facts remain range-local."
  (when (and facts (> (length text) 0))
    (let* ((start (or (string-match "[^ \t]" text) 0))
           (end (or (string-match "[ \t]" text start) (length text)))
           (position start))
      (while (< position end)
        (let* ((next
                (next-single-property-change
                 position emacsvox-aural-facts-property text end))
               (existing
                (get-text-property
                 position emacsvox-aural-facts-property text)))
          (add-text-properties
           position next
           (list
            emacsvox-aural-facts-property
            (emacsvox-aural-merge-facts existing facts))
           text)
          (setq position next)))))
  text)

(defun emacsvox-speak--preview-indentation-presentation ()
  "Audition the selected indentation presentation at four columns."
  (let* ((columns 4)
         (text
          (concat
           (make-string columns ?\s)
           "indentation preview")))
    (tts-speak
     (emacsvox-speak--annotate-indentation
      text (emacsvox-speak--indentation-facts columns)))))

(defun emacsvox-set-indentation-presentation (presentation &optional global)
  "Select indentation PRESENTATION and preview four-column indentation.

Set the option buffer-locally by default.  With interactive prefix GLOBAL,
also set the global default and use it in the current buffer."
  (interactive
   (list
    (intern
     (completing-read
      "Indentation presentation: "
      (mapcar #'symbol-name emacsvox-indentation-presentation-values)
      nil t nil nil
      (symbol-name emacsvox-indentation-presentation)))
    current-prefix-arg))
  (unless (memq presentation emacsvox-indentation-presentation-values)
    (user-error "Unknown indentation presentation: %S" presentation))
  (when global
    (set-default 'emacsvox-indentation-presentation presentation))
  (setq-local emacsvox-indentation-presentation presentation)
  (when (called-interactively-p 'interactive)
    (let ((emacsvox-audio-indentation t))
      (emacsvox-speak--preview-indentation-presentation)))
  presentation)

(defun emacsvox-set-indentation-tone-timing (timing &optional global)
  "Select indentation tone TIMING and preview four-column indentation.

TIMING is `overlay' for alongside speech or `insert' for before speech.
Set the option buffer-locally.  With interactive prefix GLOBAL, also set
the global default.  Use Customize to save the default across sessions.
Preview the current tonal presentation, or a pitch tone if it has no tone,
without enabling indentation feedback or changing its presentation."
  (interactive
   (list
    (cdr
     (assoc
      (completing-read
       "Indentation tone timing: "
       '("Alongside speech" "Before speech") nil t nil nil
       (if (eq emacsvox-indentation-tone-timing 'insert)
           "Before speech" "Alongside speech"))
      '(("Alongside speech" . overlay) ("Before speech" . insert))))
    current-prefix-arg))
  (unless (memq timing '(overlay insert))
    (user-error "Unknown indentation tone timing: %S" timing))
  (when global
    (set-default 'emacsvox-indentation-tone-timing timing))
  (setq-local emacsvox-indentation-tone-timing timing)
  (when (called-interactively-p 'interactive)
    (let ((emacsvox-audio-indentation t)
          (emacsvox-indentation-presentation
           (if (memq emacsvox-indentation-presentation
                     '(duration-tone pitch-tone
                       spoken-duration-tone spoken-pitch-tone))
               emacsvox-indentation-presentation
             'pitch-tone)))
      (emacsvox-speak--preview-indentation-presentation)))
  timing)

;; Indicate indentation.
;; Argument indent   indicates number of columns to indent.

(ems-generate-switcher 'emacsvox-toggle-audio-indentation
                       'emacsvox-audio-indentation
                       "Toggle state of  Emacsvox  audio indentation.
Interactive PREFIX arg means toggle  the global default value, and then set the
current local  value to the result.
Specifying the method of indentation as `tones'
results in the Dectalk producing a tone whose length is a function of the
line's indentation.  Specifying `speak'
results in the number of initial spaces being spoken.")

(provide 'emacsvox-speak-presentation)

;;; emacsvox-speak-presentation.el ends here
