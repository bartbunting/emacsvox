;;; emacsvox-reading-lines.el --- Wrapped row reading preferences -*- lexical-binding: t; -*-

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
;; Resolve explicit reading preferences and add continuation feedback to the
;; existing cancellable presentation timeline.  Loading defines no hooks.
;;; Code:
(require 'cl-lib)
(require 'emacsvox-aural-submission)

(defgroup emacsvox-reading-lines nil
  "Source-line reading and wrapped-row feedback."
  :group 'emacsvox)

(defconst emacsvox-reading-lines--factory
  '(:mode inherit :speech off :frequency every
    :first-sound earcon :first-cue wrapped-line-first :first-placement alongside
    :first-volume 0.6 :first-tone (:pitch 880 :duration 45 :shape (:waveform sine))
    :middle-sound earcon :middle-cue wrapped-line-middle :middle-placement alongside
    :middle-volume 0.6 :middle-tone (:pitch 660 :duration 45 :shape (:waveform sine))
    :last-sound earcon :last-cue wrapped-line-last :last-placement alongside
    :last-volume 0.6 :last-tone (:pitch 440 :duration 45 :shape (:waveform sine)))
  "Factory feedback values; reading mode preserves existing mode defaults.")

(defcustom emacsvox-reading-lines-defaults nil
  "Global reading preferences, overriding factory values by plist key.
Use `emacsvox-reading-settings' for explained choices and explicit saving.
An absent key follows the factory value.  :mode is inherit, source or visual;
inherit preserves each major mode's existing navigation.  Sounds require a
worker supporting structured timelines; unavailable sounds are not retimed."
  :type 'plist :group 'emacsvox-reading-lines)

(defcustom emacsvox-reading-lines-modes nil
  "Reading preference plists keyed by exact major-mode symbol.
Each absent preference follows `emacsvox-reading-lines-defaults'.  Use the
reading settings menu to save choices without changing personal source files."
  :type '(alist :key-type symbol :value-type plist) :group 'emacsvox-reading-lines)

(defvar-local emacsvox-reading-lines-overrides nil
  "Temporary buffer preferences; missing keys follow mode and global values.")
(defvar-local emacsvox-reading-lines--original nil
  "Navigation state captured before applying an explicit reading preference.")
(defvar emacsvox-reading-lines--last-visit nil
  "Identity of the last presented source line, buffer and window.")
(defvar emacsvox-reading-lines--reading-place nil
  "Last command's buffer and selected window, for entry tracking.")

(defun emacsvox-reading-lines--merge (&rest layers)
  "Merge preference LAYERS, first layer taking precedence, over factory values."
  (let ((result (copy-tree emacsvox-reading-lines--factory)))
    (dolist (layer (reverse layers))
      (while layer
        (setq result (plist-put result (pop layer) (copy-tree (pop layer))))))
    result))

(defun emacsvox-reading-lines--values ()
  "Return effective preferences in the current source buffer."
  (emacsvox-reading-lines--merge
   emacsvox-reading-lines-overrides
   (alist-get major-mode emacsvox-reading-lines-modes)
   emacsvox-reading-lines-defaults))

(defun emacsvox-reading-lines--origin (key)
  "Describe the inheritance source of preference KEY in this buffer."
  (cond ((plist-member emacsvox-reading-lines-overrides key) "buffer")
        ((plist-member (alist-get major-mode emacsvox-reading-lines-modes) key) "major mode")
        ((plist-member emacsvox-reading-lines-defaults key) "global")
        (t "factory")))

(defun emacsvox-reading-lines--apply-mode ()
  "Apply the current buffer's explicit reading mode, preserving native defaults."
  (let ((mode (plist-get (emacsvox-reading-lines--values) :mode)))
    (if (eq mode 'inherit)
        (when emacsvox-reading-lines--original
          (let ((original emacsvox-reading-lines--original))
            (visual-line-mode (if (nth 0 original) 1 -1))
            (if (nth 1 original) (setq-local line-move-visual (nth 2 original))
              (kill-local-variable 'line-move-visual))
            (setq emacsvox-reading-lines--original nil)))
      (unless emacsvox-reading-lines--original
        (setq emacsvox-reading-lines--original
              (list visual-line-mode (local-variable-p 'line-move-visual) line-move-visual)))
      (visual-line-mode (if (eq mode 'visual) 1 -1))
      (setq-local line-move-visual (eq mode 'visual)))))

(defun emacsvox-reading-lines--track-place ()
  "Reset source-entry feedback when the reading buffer or window changes."
  (let ((place (cons (current-buffer) (selected-window))))
    (unless (equal place emacsvox-reading-lines--reading-place)
      (setq emacsvox-reading-lines--last-visit nil
            emacsvox-reading-lines--reading-place place))))

(defun emacsvox-reading-lines--refresh ()
  "Reconcile explicit preferences in existing buffers after Apply or startup."
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer (emacsvox-reading-lines--apply-mode)))
  (setq emacsvox-reading-lines--last-visit nil))

(defun emacsvox-reading-lines--key (type field)
  "Return the independent preference key for row TYPE and FIELD."
  (intern (format ":%s-%s" type field)))

(defun emacsvox-reading-lines--sound-unavailable (values type)
  "Return why TYPE's sound in VALUES cannot play, or nil when available."
  (unless (eq 'off (plist-get values (emacsvox-reading-lines--key type 'sound)))
    (condition-case err
        (cond
         ((not (and (process-live-p tts-speaker-process)
                    (emacsvox-aural-structured-timeline-available-p)))
          "Sound unavailable: start a worker with structured timeline support")
         ((and (eq 'tone (plist-get values (emacsvox-reading-lines--key type 'sound)))
               (let ((shape (plist-get (plist-get values (emacsvox-reading-lines--key type 'tone)) :shape)))
                 (and shape (not (equal shape '(:waveform sine)))))
               (not (and (fboundp 'omnivox--rich-tones-supported-p)
                         (omnivox--rich-tones-supported-p tts-speaker-process))))
          "Tone shaping unavailable on this worker"))
      (error (error-message-string err)))))

(defun emacsvox-reading-lines--description (type style)
  "Return TYPE's spoken prefix for STYLE, or nil."
  (pcase style
    ('brief (pcase type ('first "Start. ") ('middle "Continued. ") ('last "End. ")))
    ('explicit (pcase type ('first "Same line continues below. ")
                      ('middle "Same line continues above and below. ")
                      ('last "Same line continues above. ")))))

(defun emacsvox-reading-lines--rule (type values)
  "Build TYPE's presentation rule from VALUES, respecting worker capabilities."
  (let* ((sound (plist-get values (emacsvox-reading-lines--key type 'sound)))
         (placement (plist-get values (emacsvox-reading-lines--key type 'placement)))
         (description (emacsvox-reading-lines--description type (plist-get values :speech)))
         (action
          (unless (or (eq sound 'off) (emacsvox-reading-lines--sound-unavailable values type))
            (append (list :id 'wrapped-row-sound :kind (if (eq sound 'tone) 'tone 'cue)
                          :volume (plist-get values (emacsvox-reading-lines--key type 'volume))
                          :audio-mode (if (eq placement 'before) 'insert 'overlay))
                    (if (eq sound 'tone)
                        (copy-tree (plist-get values (emacsvox-reading-lines--key type 'tone)))
                      (list :cue (plist-get values (emacsvox-reading-lines--key type 'cue)))))))
         (prefix (when description
                   (list (list :id 'wrapped-row-description :kind 'speech :text description))))
         (before (append (unless (eq placement 'after) (and action (list action))) prefix))
         (after (and action (eq placement 'after) (list action))))
    (when (or before after)
      (list :id (intern (format "wrapped-row-feedback-%s" type)) :match (list :wrapped-row type)
            :render (append (when before (list :before (list :append before)))
                            (when after (list :after (list :append after))))))))

(defun emacsvox-reading-lines--presentation (row context facts &optional force)
  "Return context and facts for ROW's feedback in CONTEXT and FACTS.
FORCE repeats feedback even when the source line was already visited.  Keep
all cues in the same native submission as the row text."
  (emacsvox-reading-lines--track-place)
  (let* ((type (plist-get row :type))
         (values (emacsvox-reading-lines--values))
         (identity (list (current-buffer) (selected-window)
                         (plist-get row :source-start) (buffer-chars-modified-tick)))
         (announce (or force (eq (plist-get values :frequency) 'every)
                       (not (equal identity emacsvox-reading-lines--last-visit))))
         (rule (and announce (not (eq type 'complete))
                    (emacsvox-reading-lines--rule type values))))
    (setq emacsvox-reading-lines--last-visit identity)
    (if (not rule) (list context facts)
      (list (plist-put (copy-tree context) :buffer-rules
                       (append (plist-get context :buffer-rules) (list rule)))
            (plist-put (copy-tree facts) :wrapped-row type)))))

(provide 'emacsvox-reading-lines)
;;; emacsvox-reading-lines.el ends here
