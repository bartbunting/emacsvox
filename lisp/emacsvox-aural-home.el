;;; emacsvox-aural-home.el --- Spoken aural control center -*- lexical-binding: t; -*-

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

;; Status and routing home for aural presentation discovery, management,
;; diagnosis, and contextual remapping.

;;; Code:

(require 'subr-x)
(require 'tabulated-list)
(require 'emacsvox-aural-history)
(require 'emacsvox-aural-tools)
(require 'emacsvox-aural-explanation)
(require 'emacsvox-aural-recent-feedback)
(require 'emacsvox-aural-feature-fragments)

(declare-function emacsvox-edit-aural-rules
                  "emacsvox-aural-editor"
                  (scope &optional fragment source-buffer))
(declare-function emacsvox-aural-doctor
                  "emacsvox-aural-doctor" ())
(declare-function emacsvox-aural-doctor-summary
                  "emacsvox-aural-doctor" (&optional findings))
(declare-function emacsvox-aural-list-overrides
                  "emacsvox-aural-overrides" (&optional source))
(declare-function emacsvox-aural-overrides-status
                  "emacsvox-aural-overrides" (&optional source))
(declare-function emacsvox-aural-list-profiles
                  "emacsvox-aural-profiles" (&optional profile))
(declare-function emacsvox-aural-profiles-status
                  "emacsvox-aural-profiles" (&optional source-buffer))
(declare-function emacsvox-aural-list-sound-packs
                  "emacsvox-aural-sound-packs" (&optional pack))
(declare-function emacsvox-aural-list-voice-palettes
                  "emacsvox-aural-voice-palettes" (&optional palette))
(declare-function emacsvox-aural-voice-palettes-status
                  "emacsvox-aural-voice-palettes" ())
(declare-function emacsvox-aural-voice-workbench
                  "emacsvox-aural-voice-workbench" (&optional view))
(declare-function emacsvox-aural-voice-workbench-status
                  "emacsvox-aural-voice-workbench" ())
(declare-function emacsvox-speak-help "emacsvox-speak" ())
(declare-function tts-speak "tts-speak" (text))

(defun emacsvox-aural-home--source-buffer ()
  "Return the live inspection source for the current aural home buffer."
  (emacsvox-aural-inspection-source-buffer))

(defun emacsvox-aural-home--enabled-fragment-status ()
  "Return concise status for enabled aural feature fragments."
  (if emacsvox-aural-enabled-feature-fragments
      (format
       "%d enabled: %s"
       (length emacsvox-aural-enabled-feature-fragments)
       (mapconcat
        #'symbol-name emacsvox-aural-enabled-feature-fragments ", "))
    "none enabled"))

(defun emacsvox-aural-home--recent-feedback-status ()
  "Return concise status for retained aural feedback."
  (format
   "%s; Aural UI %s"
   (cond
    ((and
      (natnump emacsvox-aural-presentation-history-limit)
      (zerop emacsvox-aural-presentation-history-limit))
     "disabled")
    (emacsvox-aural-presentation-history
     (format
      "%d of %s retained"
      (length emacsvox-aural-presentation-history)
      emacsvox-aural-presentation-history-limit))
    (t "none retained"))
   (if emacsvox-aural-history-record-interface-presentations
       "included"
     "excluded")))

(defun emacsvox-aural-home--profile-status ()
  "Return concise status for complete saved presentation profiles."
  (require 'emacsvox-aural-profiles)
  (emacsvox-aural-profiles-status
   (emacsvox-aural-home--source-buffer)))

(defun emacsvox-aural-home--overrides-status ()
  "Return concise status for the strongest presentation rule layers."
  (require 'emacsvox-aural-overrides)
  (emacsvox-aural-overrides-status
   (emacsvox-aural-home--source-buffer)))

(defun emacsvox-aural-home--voice-palette-status ()
  "Return concise status for voice palettes."
  (require 'emacsvox-aural-voice-palettes)
  (emacsvox-aural-voice-palettes-status))

(defun emacsvox-aural-home--voice-workbench-status ()
  "Return concise cross-synth Voice Workbench status."
  (require 'emacsvox-aural-voice-workbench)
  (emacsvox-aural-voice-workbench-status))

(defun emacsvox-aural-home--spatial-status ()
  "Return concise status for portable spatial presentation."
  (if emacsvox-aural-spatial-enabled
      (format
       "on; speech %s, cues %s, output %s"
       (if emacsvox-aural-spatial-speech-enabled "on" "off")
       (if emacsvox-aural-spatial-cue-enabled "on" "off")
       emacsvox-aural-spatial-output)
    "off"))

(defun emacsvox-aural-home--validation-status ()
  "Return concise installation and configuration health."
  (require 'emacsvox-aural-doctor)
  (emacsvox-aural-doctor-summary))

(defun emacsvox-aural-home--entries ()
  "Return current rows for the aural home buffer."
  (let* ((source (emacsvox-aural-home--source-buffer))
         (source-name (if source (buffer-name source) "no source buffer"))
         (buffer-rules
          (if source
              (length
               (buffer-local-value 'emacsvox-aural-buffer-rules source))
            0))
         (pack
          (or
           (and
            (boundp 'emacsvox-sounds-current-pack)
            emacsvox-sounds-current-pack)
           (emacsvox-aural-effective-scheme-provider 'resource-pack)
           "none")))
    (list
     (list
      'explain
      (vector
       "Explain at point" source-name
       "Show and speak why the current item sounds as it does"))
     (list
      'remap
      (vector
       "Remap voice at point" source-name
       "Prepare a persistent, session, or buffer voice override for the current item"))
     (list
      'remap-earcon
      (vector
       "Remap earcon at point" source-name
       "Audition and replace, suppress, or restore one exact before or after earcon"))
     (list
      'overrides
      (vector
       "Presentation overrides"
       (emacsvox-aural-home--overrides-status)
       "Browse and manage personal, session, and current-buffer rule layers together"))
     (list
      'recent-feedback
      (vector
       "Recent aural feedback"
       (emacsvox-aural-home--recent-feedback-status)
       "Browse, explain, replay, audition, and remap bounded presentations that were heard"))
     (list
      'profiles
      (vector
       "Presentation profiles"
       (emacsvox-aural-home--profile-status)
       "Save and switch complete global presentation configurations"))
     (list
      'voices
      (vector
       "Voice palettes"
       (emacsvox-aural-home--voice-palette-status)
       "Browse, create, edit, preview, explain, validate, and activate named voices"))
     (list
      'voice-workbench
      (vector
       "Voice Workbench"
       (emacsvox-aural-home--voice-workbench-status)
       "Browse logical voices, installed physical voices, engines, routes, styles, and effects"))
     (list
      'features
      (vector
       "Presentation options"
       (emacsvox-aural-home--enabled-fragment-status)
       "Browse grouped optional presentation additions and their active order"))
     (list
      'buffer-rules
      (vector
       "Current buffer rules"
       (format "%d in %s" buffer-rules source-name)
       "Edit temporary presentation rules for the source buffer"))
     (list
      'semantics
      (vector
       "Semantic vocabulary"
       (format "%d registered" (length (emacsvox-aural-semantics)))
       "Browse roles, events, states, attributes, owners, and intent"))
     (list
      'sounds
      (vector
       "Sound packs" (format "%s" pack)
       "Browse, audition, validate, edit, and activate auditory cue packs"))
     (list
      'spatial
      (vector
       "Spatial capabilities"
       (emacsvox-aural-home--spatial-status)
       "Inspect backend capability and fallback"))
     (list
      'spatial-settings
      (vector
       "Spatial settings" "Customize"
       "Configure output, separation, direction, speech, and cues"))
     (list
      'training
      (vector
       "Training mode"
       (if emacsvox-aural-training-mode "on" "off")
       "Toggle concise semantic explanations after presentations"))
     (list
      'diagnostics
      (vector
       "Aural Doctor"
       (emacsvox-aural-home--validation-status)
       "Diagnose bindings, loaded files, configuration, resources, and backend")))))

(defun emacsvox-aural-home--goto (id)
  "Move to home row ID and its first column."
  (emacsvox-aural-ui-goto-row id))

(defun emacsvox-aural-home-refresh (&optional id)
  "Refresh aural home status, preserving row ID and the current column."
  (interactive)
  (emacsvox-aural-ui-refresh-tabulated
   (lambda ()
     (setq tabulated-list-entries (emacsvox-aural-home--entries)))
   id 'explain))

(defun emacsvox-aural-home-speak-current ()
  "Speak the complete aural home row at point."
  (interactive)
  (let* ((entry
          (or
           (tabulated-list-get-entry)
           (user-error "Move to an aural home row first")))
         (summary
          (format
           "%s. %s. %s."
           (aref entry 0) (aref entry 1) (aref entry 2))))
    (if (fboundp 'tts-speak)
        (tts-speak summary)
      (message "%s" summary))
    summary))

(defun emacsvox-aural-home-speak-current-cell ()
  "Speak the current aural home column title and value."
  (interactive)
  (emacsvox-aural-ui-speak-current-cell))

(defun emacsvox-aural-home-next ()
  "Move to and speak the next aural home row."
  (interactive)
  (emacsvox-aural-ui-move-row 1 "aural home"))

(defun emacsvox-aural-home-previous ()
  "Move to and speak the previous aural home row."
  (interactive)
  (emacsvox-aural-ui-move-row -1 "aural home"))

(defun emacsvox-aural-home-next-column ()
  "Move right and speak the next aural home column."
  (interactive)
  (emacsvox-aural-ui-move-column 1))

(defun emacsvox-aural-home-previous-column ()
  "Move left and speak the previous aural home column."
  (interactive)
  (emacsvox-aural-ui-move-column -1))

(defun emacsvox-aural-home--call-in-source (command)
  "Call interactive COMMAND in the remembered source buffer."
  (let ((source (emacsvox-aural-home--source-buffer)))
    (unless source
      (user-error "No live source buffer is available"))
    (with-current-buffer source
      (call-interactively command))))

(defun emacsvox-aural-home-explain ()
  "Explain presentation at point in the remembered source buffer."
  (interactive)
  (emacsvox-aural-home--call-in-source
   #'emacsvox-aural-explain-presentation))

(defun emacsvox-aural-home-remap-voice ()
  "Prepare a voice override for the remembered source item."
  (interactive)
  (emacsvox-aural-home--call-in-source
   #'emacsvox-aural-remap-voice-at-point))

(defun emacsvox-aural-home-remap-earcon ()
  "Prepare an earcon override for the remembered source item."
  (interactive)
  (emacsvox-aural-home--call-in-source
   #'emacsvox-aural-remap-earcon-at-point))

(defun emacsvox-aural-home-recent-feedback ()
  "Open bounded retained presentations from Aural Home."
  (interactive)
  (emacsvox-aural-list-recent-feedback
   (emacsvox-aural-home--source-buffer)))

(defun emacsvox-aural-home-overrides ()
  "Open unified presentation overrides from Aural Home."
  (interactive)
  (require 'emacsvox-aural-overrides)
  (emacsvox-aural-list-overrides
   (emacsvox-aural-home--source-buffer)))

(defun emacsvox-aural-home-profiles ()
  "Open the complete presentation-profile manager."
  (interactive)
  (require 'emacsvox-aural-profiles)
  (emacsvox-aural-list-profiles))

(defun emacsvox-aural-home-voice-palettes ()
  "Open the accessible voice-palette manager."
  (interactive)
  (require 'emacsvox-aural-voice-palettes)
  (emacsvox-aural-list-voice-palettes))

(defun emacsvox-aural-home-voice-workbench ()
  "Open cross-synth voice routing and style management."
  (interactive)
  (require 'emacsvox-aural-voice-workbench)
  (emacsvox-aural-voice-workbench))

(defun emacsvox-aural-home-activate ()
  "Perform the primary operation for the aural home row at point."
  (interactive)
  (pcase (or (tabulated-list-get-id)
             (user-error "Move to an aural home row first"))
    ('explain
     (emacsvox-aural-home-explain))
    ('remap
     (emacsvox-aural-home-remap-voice))
    ('remap-earcon
     (emacsvox-aural-home-remap-earcon))
    ('overrides
     (emacsvox-aural-home-overrides))
    ('recent-feedback
     (emacsvox-aural-home-recent-feedback))
    ('profiles (emacsvox-aural-home-profiles))
    ('voices (emacsvox-aural-home-voice-palettes))
    ('voice-workbench (emacsvox-aural-home-voice-workbench))
    ('features (emacsvox-aural-list-feature-fragments))
    ('buffer-rules
     (let ((source (emacsvox-aural-home--source-buffer)))
       (unless source
         (user-error "No live source buffer is available"))
       (require 'emacsvox-aural-editor)
       (emacsvox-edit-aural-rules 'buffer nil source)))
    ('semantics (emacsvox-aural-list-semantics))
    ('sounds
     (require 'emacsvox-aural-sound-packs)
     (emacsvox-aural-list-sound-packs))
    ('spatial (emacsvox-aural-describe-spatial-capabilities))
    ('spatial-settings (customize-group 'emacsvox-aural-spatial))
    ('training
     (emacsvox-aural-training-mode
      (if emacsvox-aural-training-mode -1 1))
     (emacsvox-aural-home-refresh 'training)
     (emacsvox-aural-home-speak-current))
    ('diagnostics
     (require 'emacsvox-aural-doctor)
     (emacsvox-aural-doctor))))

(defun emacsvox-aural-home-help ()
  "Display and speak aural home commands and discovery guidance."
  (interactive)
  (with-help-window (help-buffer)
    (princ
     (concat
      "Emacsvox Aural Home\n\n"
      "This is the main entry point for presentation discovery, editing,\n"
      "inspection, sound packs, spatial settings, and diagnostics.\n\n"
      "A fixed internal baseline preserves compatible presentation. Automatic\n"
      "mode presentation, enabled options, and finally personal, session, and\n"
      "buffer overrides compose on top. Open Presentation options to choose\n"
      "additions; open Presentation overrides for the strongest rule layers.\n\n"
      "n or down next       p or up previous\n"
      "left/right column    . speak titled cell\n"
      "RET open or perform  SPC speak complete row\n"
      "x explain at point   r remap voice at point\n"
      "R remap one exact earcon at point\n"
      "O presentation overrides\n"
      "H recent feedback\n"
      "P presentation profiles\n"
      "V voice palettes\n"
      "W voice workbench\n"
      "D aural doctor\n"
      "g refresh\n"
      "? display and speak this help\n"
      "C-e H opens this home from any ordinary buffer\n"
      "C-e E explains presentation from any ordinary buffer\n"
      "To remap an item, move to it, open C-e H, then press r or R.\n"
      "The generated override opens unwritten; review it and press w to write.\n"
      "h returns here from any aural manager or editor\n"
      "q quit\n")))
  (when (fboundp 'emacsvox-speak-help)
    (emacsvox-speak-help)))

(define-derived-mode emacsvox-aural-home-mode
    emacsvox-aural-tabulated-mode
  "Emacsvox-Aural"
  "Spoken home mode for aural presentation discovery and interaction."
  (emacsvox-aural-ui-configure-tabulated
   "aural home"
   #'emacsvox-aural-home-speak-current
   #'emacsvox-aural-home-refresh)
  (setq
   tabulated-list-format
   [("Area" 24 t)
    ("Current status" 38 t)
    ("Purpose" 0 t)])
  (setq tabulated-list-padding 2)
  (add-hook
   'tabulated-list-revert-hook
   #'emacsvox-aural-home-refresh nil t)
  (tabulated-list-init-header))

(dolist
    (binding
     '(("RET" . emacsvox-aural-home-activate)
       ("x" . emacsvox-aural-home-explain)
       ("r" . emacsvox-aural-home-remap-voice)
       ("R" . emacsvox-aural-home-remap-earcon)
       ("O" . emacsvox-aural-home-overrides)
       ("H" . emacsvox-aural-home-recent-feedback)
       ("P" . emacsvox-aural-home-profiles)
       ("V" . emacsvox-aural-home-voice-palettes)
       ("W" . emacsvox-aural-home-voice-workbench)
       ("D" . emacsvox-aural-doctor)
       ("?" . emacsvox-aural-home-help)))
  (define-key
   emacsvox-aural-home-mode-map
   (kbd (car binding))
   (cdr binding)))

;;;###autoload
(defun emacsvox-aural (&optional source-buffer)
  "Open the spoken aural home using SOURCE-BUFFER for contextual operations."
  (interactive)
  (let* ((source
          (emacsvox-aural-inspection-remember-source-buffer
           (or source-buffer (current-buffer))))
         (buffer (get-buffer-create "*Emacsvox Aural*")))
    (with-current-buffer buffer
      (emacsvox-aural-home-mode)
      (emacsvox-aural-inspection-attach-source source)
      (emacsvox-aural-home-refresh 'explain))
    (emacsvox-aural-ui-pop-to-buffer buffer)
    (when (called-interactively-p 'interactive)
      (emacsvox-aural-home-speak-current))
    buffer))

(add-hook
 'emacsvox-aural-feature-fragments-changed-hook
 #'emacsvox-aural-ui-refresh-home-if-live)
(add-hook
 'emacsvox-aural-voice-palette-changed-hook
 #'emacsvox-aural-ui-refresh-home-if-live)

(provide 'emacsvox-aural-home)

;;; emacsvox-aural-home.el ends here
