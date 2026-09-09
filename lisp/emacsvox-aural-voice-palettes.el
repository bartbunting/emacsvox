;;; emacsvox-aural-voice-palettes.el --- Spoken voice-palette manager -*- lexical-binding: t; -*-

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

;; Accessible management for inherited, data-safe ACSS voice palettes.

;;; Code:

(require 'emacsvox-aural-voice-editing)
(declare-function emacsvox-aural-voice-editor--status-for "emacsvox-aural-voice-editor" (palette voice))
(declare-function emacsvox-aural-voice-editor--invalidate "emacsvox-aural-voice-editor" (context))
(declare-function emacsvox-aural-voice-editor-refresh "emacsvox-aural-voice-editor" ())
(defvar emacsvox-aural-voice-editor--contexts)
(defvar voice-setup-defined-voices)
(defvar voice-setup-face-voice-table)
(defvar voice-setup-local-map)

(declare-function emacsvox-aural-voice-editor-open "emacsvox-aural-voice-editor" (palette voice &optional source text))

(require 'cl-lib)
(require 'subr-x)
(require 'tabulated-list)
(require 'emacsvox-aural-schemes)
(require 'emacsvox-aural-ui)
(require 'emacsvox-aural-inspection)
(require 'emacsvox-aural-description)
(require 'emacsvox-aural-preview)

(declare-function emacsvox-speak-help "emacsvox-speak" ())
(declare-function tts-speak "tts-speak" (text))
(declare-function tts-voice-reset-code "tts-speak" ())
(declare-function tts--protocol-queue-code "tts-speak" (code))
(declare-function tts--protocol-queue-text "tts-speak" (text))
(declare-function tts-preview-voice "tts-speak"
                  (text selector &rest arguments))
(declare-function tts-voice-family-capability
                  "tts-speak" (family &optional capabilities))
(declare-function tts-voice-family-id
                  "tts-speak" (family &optional capabilities))

(defcustom emacsvox-aural-voice-palettes-preview-text
  "The quick brown fox jumps over the lazy dog. Numbers one, two, three."
  "Comparison text used when auditioning voices from a palette."
  :type 'string
  :group 'emacsvox-aural)

(defvar emacsvox-aural-voice-palettes--last-preview-voices
  (make-hash-table :test #'eq)
  "Most recently selected preview voice for each palette.")

(defvar-local emacsvox-aural-voice-palette-previews-palette nil
  "Voice palette shown in the current preview buffer.")

(defvar-local emacsvox-aural-voice-palette-previews-entries nil
  "Effective voice entries shown in the current preview buffer.")

(defvar-local emacsvox-aural-voice-palette-previews-text nil
  "Comparison text used by the current preview buffer.")

(defconst emacsvox-aural-voice-tuner--dimension-descriptions
  '((family . "Portable or synth-specific ACSS family; a physical route takes precedence")
    (average-pitch . "Overall pitch from zero through nine")
    (pitch-range . "Pitch variation from zero through nine")
    (stress . "Word emphasis from zero through nine")
    (richness . "Spectral richness from zero through nine")
    (rate-offset . "Relative rate from twenty points slower through twenty points faster; zero is unchanged")
    (gain . "Post-synthesis gain; five is unchanged")
    (low-pass . "Low-pass amount; zero is neutral, nine removes the most high frequencies")
    (high-pass . "High-pass amount; zero is neutral, nine removes the most low frequencies")
    (pan . "Stereo position; zero is left, five centre, and nine right")
    (reverb . "Post-synthesis reverberation; zero is disabled")
    (echo . "Post-synthesis echo; zero is disabled")
    (chorus . "Post-synthesis chorus; zero is disabled"))
  "Spoken descriptions of tunable voice dimensions.")

(defvar-local emacsvox-aural-voice-tuner-palette nil
  "Personal palette containing the voice being tuned.")

(defvar-local emacsvox-aural-voice-tuner-voice nil
  "Voice name represented by the current tuner.")

(defvar-local emacsvox-aural-voice-tuner-original-definition nil
  "Persisted voice definition from which the tuner started.")

(defvar-local emacsvox-aural-voice-tuner-initial-style nil
  "Complete ACSS working style from which tuning started.")

(defvar-local emacsvox-aural-voice-tuner-working-style nil
  "Complete unsaved ACSS style currently being auditioned.")

(defvar-local emacsvox-aural-voice-tuner-history nil
  "Earlier tuner working styles, newest first.")

(defvar-local emacsvox-aural-voice-tuner-dirty nil
  "Whether the tuner working style differs from its initial style.")

(defvar-local emacsvox-aural-voice-tuner-preview-text nil
  "Comparison text spoken by the current tuner.")

(defvar-local emacsvox-aural-voice-tuner-source-buffer nil
  "Voice-palette preview buffer that opened the current tuner.")

(defvar-local emacsvox-aural-voice-tuner-route-selector nil
  "Unsaved physical route selector used by this tuner.")

(defvar-local emacsvox-aural-voice-tuner-route-language nil
  "Language constraint used by the tuner route preview.")

(defvar-local emacsvox-aural-voice-tuner-route-engine nil
  "Discovered engine descriptor used by the tuner route preview.")

(defvar-local emacsvox-aural-voice-tuner-route-realized nil
  "Most recently realized engine and voice reported by preview.")

(defvar-local emacsvox-aural-voice-tuner-preview-result nil
  "Most recent normalized route-preview completion result.")

(defvar-local emacsvox-aural-voice-tuner-preview-generation 0
  "Generation preventing obsolete callbacks from replacing current feedback.")

(defvar-local emacsvox-aural-voice-tuner-additional-dirty-function nil
  "Optional predicate for additional unsaved tuner state, such as a physical route.")

(defvar emacsvox-aural-voice-tuner--feedback-p nil
  "Non-nil while requesting operable tuner feedback rather than a voice sample.")

(defvar-local emacsvox-aural-voice-tuner-legacy-rate nil
  "Ignored nonzero legacy absolute rate found when this tuner opened.")

(defvar-local emacsvox-aural-voice-tuner-compare-reference-next-p t
  "Non-nil when the next tuner comparison should use the opening style.")

(defun emacsvox-aural-voice-palettes--active-id ()
  "Return the currently effective voice palette."
  (or
   emacsvox-aural-voice-palette-override
   (emacsvox-aural-effective-scheme-provider 'voice-palette)
   'acss-default))

(defun emacsvox-aural-voice-palettes-status ()
  "Return concise voice-palette status for Aural Home."
  (let ((active (emacsvox-aural-voice-palettes--active-id))
        (count (hash-table-count emacsvox-aural-voice-palette-registry)))
    (format
     "%s active; %d available%s"
     active count
     (if emacsvox-aural-voice-palette-override
         " (override)"
       " (from scheme)"))))

(defun emacsvox-aural-voice-palettes--ids ()
  "Return registered palette identifiers in display order."
  (mapcar #'intern (emacsvox-aural-voice-palette-candidates)))

(defun emacsvox-aural-voice-palettes--kind (palette)
  "Return a display kind for PALETTE."
  (if (emacsvox-aural-voice-palette-built-in palette)
      "built-in"
    "personal"))

(defun emacsvox-aural-voice-palettes--validation (id)
  "Return validation details for palette ID."
  (condition-case error
      (let ((missing (emacsvox-aural-validate-voice-palette id))
            (degradations
             (emacsvox-aural-voice-palette-capability-degradations id)))
        (list
         :valid (null missing)
         :missing missing
         :degradations degradations))
    (error
     (list :valid nil :errors (list (error-message-string error))))))

(defun emacsvox-aural-voice-palettes--validation-status (report)
  "Return concise status for palette validation REPORT."
  (cond
   ((plist-get report :errors) "invalid")
   ((plist-get report :missing)
    (format "%d unavailable" (length (plist-get report :missing))))
   ((plist-get report :degradations)
    (format "%d fallbacks" (length (plist-get report :degradations))))
   (t "valid")))

(defun emacsvox-aural-voice-palettes--row (id)
  "Return one tabulated manager row for palette ID."
  (let* ((palette (emacsvox-aural-voice-palette id))
         (direct (length (emacsvox-aural-voice-palette-entries palette)))
         (effective (length (emacsvox-aural-effective-voice-entries id)))
         (report (emacsvox-aural-voice-palettes--validation id)))
    (list
     id
     (vector
      (symbol-name id)
      (if (eq id (emacsvox-aural-voice-palettes--active-id))
          "active"
        "")
      (emacsvox-aural-voice-palettes--kind palette)
      (if-let* ((parent (emacsvox-aural-voice-palette-parent palette)))
          (symbol-name parent)
        "")
      (format "%d" direct)
      (format "%d" effective)
      (symbol-name
       (plist-get
        (emacsvox-aural-active-voice-capabilities) :adapter))
      (emacsvox-aural-voice-palettes--validation-status report)
      (emacsvox-aural-voice-palette-summary palette)))))

(defun emacsvox-aural-voice-palettes--set-entries ()
  "Populate the voice-palette manager."
  (setq
   tabulated-list-entries
   (mapcar
    #'emacsvox-aural-voice-palettes--row
    (emacsvox-aural-voice-palettes--ids))))

(defun emacsvox-aural-voice-palettes--goto (id)
  "Move to palette ID and its first column."
  (emacsvox-aural-ui-goto-row id))

(defun emacsvox-aural-voice-palettes-refresh (&optional id)
  "Refresh palettes while preserving ID and the current column."
  (interactive)
  (emacsvox-aural-ui-refresh-tabulated
   #'emacsvox-aural-voice-palettes--set-entries
   id
   (emacsvox-aural-voice-palettes--active-id)))

(defun emacsvox-aural-voice-palettes--at-point-or-read (&optional prompt)
  "Return the palette at point, or read one using PROMPT."
  (or
   (tabulated-list-get-id)
   (intern
    (completing-read
     (or prompt "Voice palette: ")
     (emacsvox-aural-voice-palette-candidates)
     nil 'must-match))))

(defun emacsvox-aural-voice-palettes--read-new-id (&optional initial)
  "Read a new personal palette identifier, offering INITIAL."
  (let* ((text
          (string-trim
           (read-string "New voice palette name: " initial)))
         (id (intern text)))
    (when
        (or
         (string-empty-p text)
         (keywordp id)
         (memq id '(nil t)))
      (user-error "Use a non-keyword voice palette name"))
    (when (emacsvox-aural-voice-palette id)
      (user-error "Voice palette already exists: %s" id))
    id))

(defun emacsvox-aural-voice-palettes--parent-candidates (&optional exclude)
  "Return palette candidates, omitting EXCLUDE."
  (cons
   "none"
   (cl-remove
    (and exclude (symbol-name exclude))
    (emacsvox-aural-voice-palette-candidates)
    :test #'equal)))

(defun emacsvox-aural-voice-palettes--read-parent (&optional current exclude)
  "Read a parent palette, offering CURRENT and omitting EXCLUDE."
  (let ((answer
         (completing-read
          "Parent palette: "
          (emacsvox-aural-voice-palettes--parent-candidates exclude)
          nil 'must-match nil nil
          (if current (symbol-name current) "acss-default"))))
    (unless (equal answer "none") (intern answer))))

(defun emacsvox-aural-voice-palettes--persist-mutation (mutation)
  "Persist MUTATION against a staged palette registry, then publish it.

MUTATION is called with a copy of the voice-palette registry dynamically
installed.  The complete candidate registry is validated and saved before it
replaces live state.  Return the value of MUTATION."
  (let ((registry
         (copy-hash-table emacsvox-aural-voice-palette-registry))
        result)
    (let ((emacsvox-aural-voice-palette-registry registry))
      (setq result (funcall mutation))
      (maphash
       (lambda (palette-id _)
         (emacsvox-aural-effective-voice-entries palette-id))
       registry)
      (emacsvox-aural-save-user-data))
    (setq emacsvox-aural-voice-palette-registry registry)
    result))

(defun emacsvox-aural-voice-palettes--install-data (data &optional old-id)
  "Atomically install personal palette DATA, replacing OLD-ID when non-nil."
  (let ((record
         (emacsvox-aural-voice-palettes--persist-mutation
          (lambda ()
            (when old-id
              (remhash old-id emacsvox-aural-voice-palette-registry))
            (let* ((record
                    (emacsvox-aural-compile-voice-palette-data
                     data nil emacsvox-aural-schemes-file))
                   (id (emacsvox-aural-voice-palette-id record)))
              (when
                  (gethash id emacsvox-aural-voice-palette-registry)
                (user-error "Voice palette already exists: %s" id))
              (puthash
               id record emacsvox-aural-voice-palette-registry)
              record)))))
    (emacsvox-aural-ui-refresh-home-if-live)
    record))

(defun emacsvox-aural-voice-palettes--replace-entries (data entries)
  "Return palette DATA with direct ENTRIES."
  (plist-put (copy-tree data) :entries (copy-tree entries)))

(defun emacsvox-aural-voice-palettes--entry-data
    (name definition)
  "Return safe entry data for NAME and DEFINITION."
  (if (symbolp definition)
      (list name :personality definition)
    (list name :style (copy-tree definition))))

(defun emacsvox-aural-voice-palettes--direct-entry (data name)
  "Return direct entry named NAME in palette DATA."
  (cl-find name (plist-get data :entries) :key #'car :test #'eq))

(defun emacsvox-aural-voice-palettes--put-entry (data entry)
  "Return palette DATA with direct ENTRY inserted or replaced."
  (let* ((name (car entry))
         (entries
          (cl-remove name (plist-get data :entries)
                     :key #'car :test #'eq)))
    (emacsvox-aural-voice-palettes--replace-entries
     data (append entries (list entry)))))

(defun emacsvox-aural-voice-palettes--read-entry-name (id)
  "Read a voice entry name for palette ID, permitting a new name."
  (let* ((entries (emacsvox-aural-effective-voice-entries id))
         (answer
          (string-trim
           (completing-read
            "Voice name to edit or create: "
            (mapcar (lambda (entry) (symbol-name (car entry))) entries))))
         (name (intern answer)))
    (when
        (or (string-empty-p answer) (keywordp name) (memq name '(nil t)))
      (user-error "Use a non-keyword voice name"))
    name))

(defun emacsvox-aural-voice-palettes--read-new-entry-name
    (id &optional initial)
  "Read a new voice entry name for palette ID, offering INITIAL."
  (let* ((text
          (string-trim
           (read-string "New voice name: " initial)))
         (name (intern text)))
    (when
        (or (string-empty-p text) (keywordp name) (memq name '(nil t)))
      (user-error "Use a non-keyword voice name"))
    (when (assq name (emacsvox-aural-effective-voice-entries id))
      (user-error "Voice already exists in palette %s: %s" id name))
    name))

(defun emacsvox-aural-voice-palettes--personality-candidates ()
  "Return known compatibility personality names."
  (let ((names
         (mapcar
          (lambda (entry) (symbol-name (cdr entry)))
          emacsvox-aural-default-voice-entries)))
    (dolist
        (symbol
         (apropos-internal "\\`voice-" #'boundp))
      (unless (string-suffix-p "-settings" (symbol-name symbol))
        (push (symbol-name symbol) names)))
    (sort (delete-dups names) #'string-lessp)))

(defun emacsvox-aural-voice-palettes--read-style-number
    (dimension current &optional label)
  "Read optional ACSS DIMENSION, offering CURRENT with optional LABEL."
  (let* ((field (emacsvox-aural--voice-style-field dimension))
         (minimum (plist-get field :minimum))
         (maximum (plist-get field :maximum))
         (prompt
          (format
           "%s, %d through %d; blank %s: "
           (or label (emacsvox-aural-humanize dimension))
           minimum maximum
           (if current (format "keeps %s" current) "uses the adapter default")))
         (answer (string-trim (read-string prompt))))
    (cond
     ((and (string-empty-p answer) current) current)
     ((string-empty-p answer) nil)
     ((or (not (string-match-p "\\`[0-9]\\'" answer))
          (not (<= minimum (string-to-number answer) maximum)))
      (user-error "%s must be %d through %d or blank" dimension minimum maximum))
     (t (string-to-number answer)))))

(defun emacsvox-aural-voice-palettes--read-style (&optional current)
  "Read a complete ACSS style, offering CURRENT values."
  (let* ((old-family (plist-get current :family))
         (family-text
          (string-trim
           (read-string
            (format
             "Voice family; blank %s: "
             (if old-family (format "keeps %s" old-family) "uses the adapter default"))
            nil nil
            (and old-family (format "%s" old-family)))))
         (style
          (list
           :family
           (unless (string-empty-p family-text)
             (intern family-text)))))
    (dolist (dimension (remq 'family emacsvox-aural-voice-dimensions))
      (setq
       style
       (plist-put
        style
        (emacsvox-aural--voice-dimension-key dimension)
        (emacsvox-aural-voice-palettes--read-style-number
         dimension
         (plist-get
          current
          (emacsvox-aural--voice-dimension-key dimension))))))
    style))

(defun emacsvox-aural-voice-palettes--read-definition (&optional current)
  "Read a complete voice definition, offering CURRENT."
  (let* ((default
          (if (and current (symbolp current))
              "personality"
            "custom ACSS"))
         (kind
          (completing-read
           "Voice definition kind: "
           '("personality" "custom ACSS")
           nil 'must-match nil nil default)))
    (if (equal kind "personality")
        (intern
         (completing-read
          "Existing personality: "
          (emacsvox-aural-voice-palettes--personality-candidates)
          nil 'must-match nil nil
          (and (symbolp current) (symbol-name current))))
      (emacsvox-aural-voice-palettes--read-style
       (and (listp current) current)))))

(defun emacsvox-aural-voice-palettes-speak-current ()
  "Speak the complete voice-palette row at point."
  (interactive)
  (let* ((id (emacsvox-aural-voice-palettes--at-point-or-read))
         (palette (emacsvox-aural-voice-palette id))
         (report (emacsvox-aural-voice-palettes--validation id))
         (summary
          (format
           "%s. %s. %s. Parent %s. %d direct voices, %d effective. %s. %s"
           (emacsvox-aural-humanize id)
           (if (eq id (emacsvox-aural-voice-palettes--active-id))
               "active"
             "inactive")
           (emacsvox-aural-voice-palettes--kind palette)
           (or (emacsvox-aural-voice-palette-parent palette) "none")
           (length (emacsvox-aural-voice-palette-entries palette))
           (length (emacsvox-aural-effective-voice-entries id))
           (emacsvox-aural-voice-palettes--validation-status report)
           (emacsvox-aural-voice-palette-summary palette))))
    (if (fboundp 'tts-speak)
        (tts-speak summary)
      (message "%s" summary))
    summary))

(defun emacsvox-aural-voice-palettes-speak-current-cell ()
  "Speak the current palette column title and value."
  (interactive)
  (emacsvox-aural-ui-speak-current-cell))

(defun emacsvox-aural-voice-palettes-next ()
  "Move to and speak the next voice palette."
  (interactive)
  (emacsvox-aural-ui-move-row 1 "voice palettes"))

(defun emacsvox-aural-voice-palettes-previous ()
  "Move to and speak the previous voice palette."
  (interactive)
  (emacsvox-aural-ui-move-row -1 "voice palettes"))

(defun emacsvox-aural-voice-palettes-next-column ()
  "Move right and speak the next palette column."
  (interactive)
  (emacsvox-aural-ui-move-column 1))

(defun emacsvox-aural-voice-palettes-previous-column ()
  "Move left and speak the previous palette column."
  (interactive)
  (emacsvox-aural-ui-move-column -1))

(defun emacsvox-aural-voice-palettes-describe (&optional id)
  "Display and speak the effective voices in palette ID."
  (interactive)
  (let* ((id (or id (emacsvox-aural-voice-palettes--at-point-or-read)))
         (palette (emacsvox-aural-voice-palette id))
         (direct (emacsvox-aural-voice-palette-entries palette))
         (report (emacsvox-aural-voice-palettes--validation id)))
    (emacsvox-aural-ui-with-help-window
      (princ (format "Voice palette: %s\n\n" id))
      (princ (format "Summary: %s\n"
                     (emacsvox-aural-voice-palette-summary palette)))
      (princ (format "Kind: %s\n"
                     (emacsvox-aural-voice-palettes--kind palette)))
      (princ (format "Parent: %s\n"
                     (or (emacsvox-aural-voice-palette-parent palette)
                         "none")))
      (princ
       (format
        "Active adapter: %s\n"
        (plist-get (emacsvox-aural-active-voice-capabilities) :adapter)))
      (princ
       (format
        "Validation: %s\n\n"
        (emacsvox-aural-voice-palettes--validation-status report)))
      (princ "Effective voices\n\n")
      (dolist (entry (emacsvox-aural-effective-voice-entries id))
        (princ
         (format
          "%s%s: %S\n"
          (car entry)
          (if (assq (car entry) direct) "" " (inherited)")
          (cdr entry))))
      (when-let* ((missing (plist-get report :missing)))
        (princ (format "\nUnavailable personalities: %S\n" missing)))
      (when-let* ((fallbacks (plist-get report :degradations)))
        (princ "\nAdapter fallbacks\n\n")
        (dolist (fallback fallbacks)
          (princ
           (format
            "%s: %s %S is unsupported by %s\n"
            (plist-get fallback :voice)
            (plist-get fallback :dimension)
            (plist-get fallback :requested)
            (plist-get fallback :adapter))))))
    (when (called-interactively-p 'interactive)
      (emacsvox-aural-voice-palettes-speak-current))
    report))

(defun emacsvox-aural-voice-palettes-create ()
  "Create an empty personal voice palette."
  (interactive)
  (let* ((id (emacsvox-aural-voice-palettes--read-new-id))
         (summary
          (read-string
           "Palette purpose: "
           (format "Personal voice palette %s" id)))
         (parent (emacsvox-aural-voice-palettes--read-parent))
         (data
          (list
           :schema-version emacsvox-aural-voice-palette-schema-version
           :id id
           :summary summary
           :parent parent
           :entries nil)))
    (emacsvox-aural-voice-palettes--install-data data)
    (emacsvox-aural-voice-palettes-refresh id)
    (emacsvox-aural-voice-palettes-speak-current)
    id))

(defun emacsvox-aural-voice-palettes--copy (source)
  "Copy voice palette SOURCE to a prompted personal palette."
  (when (eq (plist-get (emacsvox-aural-voice-palette-data-form
                        (emacsvox-aural-voice-palette source)) :schema-version) 3)
    (user-error "Copy this palette through the common voice editor to preserve individual settings"))
  (let* ((source-palette (emacsvox-aural-voice-palette source))
         (id
          (emacsvox-aural-voice-palettes--read-new-id
           (format "%s-copy" source)))
         (data
          (emacsvox-aural-voice-palette-data-form source-palette)))
    (setq data (plist-put data :id id))
    (setq
     data
     (plist-put
      data :summary
      (read-string
       "Copied palette purpose: "
       (format "Editable copy of %s" source))))
    (emacsvox-aural-voice-palettes--install-data data)
    id))

(defun emacsvox-aural-voice-palettes-copy ()
  "Copy the voice palette at point to a personal palette."
  (interactive)
  (let ((id
         (emacsvox-aural-voice-palettes--copy
          (emacsvox-aural-voice-palettes--at-point-or-read))))
    (emacsvox-aural-voice-palettes-refresh id)
    (emacsvox-aural-voice-palettes-speak-current)
    id))

(defun emacsvox-aural-voice-palettes--install-entry-definition
    (id name definition)
  "Install complete voice DEFINITION as NAME in personal palette ID."
  (when (emacsvox-aural-voice-runtime--owned-p id)
    (user-error "Use Tune in the common voice editor to preserve palette-owned choices"))
  (let* ((palette (emacsvox-aural-voice-palette id))
         (data (emacsvox-aural-voice-palette-data-form palette))
         (updated
          (emacsvox-aural-voice-palettes--put-entry
           data
           (emacsvox-aural-voice-palettes--entry-data name definition))))
    (when (emacsvox-aural-voice-palette-built-in palette)
      (user-error "Copy the built-in palette first, then edit the copy"))
    (emacsvox-aural-voice-palettes--install-data updated id)
    (message "Saved voice %s in palette %s" name id)
    name))

(defun emacsvox-aural-voice-palettes--edit-entry (id name)
  "Create or replace voice NAME in personal palette ID."
  (let* ((palette (emacsvox-aural-voice-palette id))
         (data (emacsvox-aural-voice-palette-data-form palette)))
    (when (emacsvox-aural-voice-palette-built-in palette)
      (user-error "Copy the built-in palette first, then edit the copy"))
    (let* ((direct (emacsvox-aural-voice-palettes--direct-entry data name))
           (current
            (if direct
                (or
                 (plist-get (cdr direct) :personality)
                 (plist-get (cdr direct) :style))
              (emacsvox-aural-voice name id)))
           (definition
            (emacsvox-aural-voice-palettes--read-definition current)))
      (emacsvox-aural-voice-palettes--install-entry-definition
       id name definition))))

(defun emacsvox-aural-voice-palettes-edit-entry ()
  "Create or replace one direct voice entry in the personal palette at point."
  (interactive)
  (let* ((id (emacsvox-aural-voice-palettes--at-point-or-read))
         (name (emacsvox-aural-voice-palettes--read-entry-name id)))
    (prog1
        (emacsvox-aural-voice-palettes--edit-entry id name)
      (emacsvox-aural-voice-palettes-refresh id))))

(defun emacsvox-aural-voice-palettes-edit-metadata ()
  "Edit summary and parent of the personal palette at point."
  (interactive)
  (let* ((id (emacsvox-aural-voice-palettes--at-point-or-read))
         (palette (emacsvox-aural-voice-palette id)))
    (when (emacsvox-aural-voice-palette-built-in palette)
      (user-error "Copy the built-in palette first, then edit the copy"))
    (let* ((data (emacsvox-aural-voice-palette-data-form palette))
           (summary
            (read-string
             "Palette purpose: "
             (emacsvox-aural-voice-palette-summary palette)))
           (parent
            (emacsvox-aural-voice-palettes--read-parent
             (emacsvox-aural-voice-palette-parent palette) id)))
      (setq data (plist-put data :summary summary))
      (setq data (plist-put data :parent parent))
      (emacsvox-aural-voice-palettes--install-data data id)
      (emacsvox-aural-voice-palettes-refresh id)
      (emacsvox-aural-voice-palettes-speak-current)
      id)))

(defun emacsvox-aural-voice-palettes-delete-entry ()
  "Delete one direct entry from the personal palette at point."
  (interactive)
  (let* ((id (emacsvox-aural-voice-palettes--at-point-or-read))
         (palette (emacsvox-aural-voice-palette id)))
    (when (emacsvox-aural-voice-palette-built-in palette)
      (user-error "Built-in voice entries cannot be deleted"))
    (let* ((data (emacsvox-aural-voice-palette-data-form palette))
           (entries (plist-get data :entries))
           (_ (unless entries (user-error "This palette has no direct voices")))
           (name
            (intern
             (completing-read
              "Delete direct voice: "
              (mapcar
               (lambda (entry) (symbol-name (car entry)))
               entries)
              nil 'must-match)))
           (updated
            (emacsvox-aural-voice-palettes--replace-entries
             data
             (cl-remove name entries :key #'car :test #'eq))))
      (unless (yes-or-no-p
               (format "Delete voice %s from palette %s? " name id))
        (user-error "Deletion cancelled"))
      (emacsvox-aural-voice-palettes--install-data updated id)
      (emacsvox-aural-voice-palettes-refresh id)
      name)))

(defun emacsvox-aural-voice-palettes--dependents (id)
  "Return direct palette children of ID."
  (let (children)
    (maphash
     (lambda (candidate palette)
       (when (eq id (emacsvox-aural-voice-palette-parent palette))
         (push candidate children)))
     emacsvox-aural-voice-palette-registry)
    children))

(defun emacsvox-aural-voice-palettes--references (id)
  "Return scheme and profile references to palette ID."
  (let (references)
    (maphash
     (lambda (scheme entry)
       (when
           (eq
            id
            (plist-get
             (emacsvox-aural-scheme-entry-data entry) :voice-palette))
         (push (format "scheme %s" scheme) references)))
     emacsvox-aural-scheme-registry)
    (maphash
     (lambda (profile entry)
       (when
           (eq
            id
            (plist-get
             (emacsvox-aural-profile-entry-data entry) :voice-palette))
         (push (format "profile %s" profile) references)))
     emacsvox-aural-profile-registry)
    references))

(defun emacsvox-aural-voice-palettes-delete ()
  "Delete the personal voice palette at point when it is unreferenced."
  (interactive)
  (let* ((id (emacsvox-aural-voice-palettes--at-point-or-read))
         (palette (emacsvox-aural-voice-palette id))
         (children (emacsvox-aural-voice-palettes--dependents id))
         (references (emacsvox-aural-voice-palettes--references id)))
    (when (emacsvox-aural-voice-palette-built-in palette)
      (user-error "Built-in voice palettes cannot be deleted"))
    (when children
      (user-error
       "Cannot delete %s; inherited by %s"
       id (mapconcat #'symbol-name children ", ")))
    (when references
      (user-error
       "Cannot delete %s; used by %s"
       id (string-join references ", ")))
    (unless (yes-or-no-p (format "Delete voice palette %s? " id))
      (user-error "Deletion cancelled"))
    (emacsvox-aural-voice-palettes--persist-mutation
     (lambda ()
       (remhash id emacsvox-aural-voice-palette-registry)
       id))
    (when (eq id emacsvox-aural-voice-palette-override)
      (emacsvox-aural-select-voice-palette nil))
    (emacsvox-aural-voice-palettes-refresh)
    (emacsvox-aural-ui-refresh-home-if-live)
    id))

(defun emacsvox-aural-voice-palettes--rename-drafts (id)
  "Return clean drafts affected by renaming ID, rejecting unfinished saves."
  (let ((affected (list id)) drafts)
    (let ((pending (list id)))
      (while pending
        (dolist (child (emacsvox-aural-voice-palettes--dependents (pop pending)))
          (unless (memq child affected)
            (push child affected)
            (push child pending)))))
    (maphash
     (lambda (_ draft)
       (when (cl-some (lambda (watch) (memq (car watch) affected))
                      (emacsvox-aural-voice-draft-watches draft))
         (let ((proposal (emacsvox-aural-voice-draft-proposal draft)))
           (when (or (emacsvox-aural-voice-drafts--dirty-fields draft)
                     (and proposal
                          (not (memq (emacsvox-aural-voice-save-state proposal)
                                     '(saved applied abandoned)))))
             (user-error "Save or discard voice edits and finish pending saves before renaming %s" id)))
         (push draft drafts)))
     emacsvox-aural-voice-drafts--registry)
    (dolist (buffer (buffer-list))
      (with-current-buffer buffer
        (when (and (memq emacsvox-aural-voice-tuner-palette affected)
                   emacsvox-aural-voice-tuner-dirty)
          (user-error "Save or discard voice tuning in %s before renaming" (buffer-name)))))
    drafts))

(defun emacsvox-aural-voice-palettes--rename-views (old new drafts)
  "Rebind clean DRAFTS and open palette views from OLD to NEW."
  (dolist (draft drafts)
    (let* ((key (emacsvox-aural-voice-draft-key draft))
           (renamed (if (and (eq (car key) 'base) (eq (cadr key) old))
                        (cons 'base (cons new (cddr key))) key)))
      (remhash key emacsvox-aural-voice-drafts--registry)
      (setf (emacsvox-aural-voice-draft-key draft) renamed
            (emacsvox-aural-voice-draft-proposal draft) nil
            (emacsvox-aural-voice-draft-watches draft)
            (emacsvox-aural-voice-drafts--watch
             (mapcar (lambda (watch) (if (eq (car watch) old) new (car watch)))
                     (emacsvox-aural-voice-draft-watches draft))))
      (puthash renamed draft emacsvox-aural-voice-drafts--registry)))
  (let (contexts)
    (maphash (lambda (key context)
               (when (memq (plist-get context :draft) drafts)
                 (push (cons key context) contexts)))
             emacsvox-aural-voice-editor--contexts)
    (dolist (entry contexts)
      (let ((context (cdr entry)))
        (emacsvox-aural-voice-editor--invalidate context)
        (dolist (field '(:palette :owner :destination))
          (when (eq (plist-get context field) old)
            (setf (plist-get context field) new)))
        (remhash (car entry) emacsvox-aural-voice-editor--contexts)
        (puthash (emacsvox-aural-voice-draft-key (plist-get context :draft))
                 context emacsvox-aural-voice-editor--contexts)
        (when (buffer-live-p (plist-get context :buffer))
          (with-current-buffer (plist-get context :buffer)
            (emacsvox-aural-voice-editor-refresh))))))
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (eq emacsvox-aural-voice-tuner-palette old)
        (setq emacsvox-aural-voice-tuner-palette new))
      (when (eq emacsvox-aural-voice-palette-previews-palette old)
        (setq emacsvox-aural-voice-palette-previews-palette new)
        (emacsvox-aural-voice-palette-previews-refresh)))))

(defun emacsvox-aural-voice-palettes-rename ()
  "Rename a personal palette, preserving tuning, inheritance and profile uses."
  (interactive)
  (require 'emacsvox-aural-voice-editor)
  (let* ((old (emacsvox-aural-voice-palettes--at-point-or-read))
         (palette (emacsvox-aural-voice-palette old)))
    (when (emacsvox-aural-voice-palette-built-in palette)
      (user-error "Built-in voice palettes cannot be renamed"))
    ;; Scheme definitions are maintained outside the personal data store.
    (maphash
     (lambda (id entry)
       (when (eq old (plist-get (emacsvox-aural-scheme-entry-data entry) :voice-palette))
         (user-error "Update scheme %s's palette reference before renaming %s" id old)))
     emacsvox-aural-scheme-registry)
    (let* ((drafts (emacsvox-aural-voice-palettes--rename-drafts old))
           (new (emacsvox-aural-voice-palettes--read-new-id (symbol-name old)))
           (registry (copy-hash-table emacsvox-aural-voice-palette-registry))
           (profiles (copy-hash-table emacsvox-aural-profile-registry))
           (data (emacsvox-aural-voice-palette-data-form palette))
           (aural-before (emacsvox-aural-voice-drafts--file-id emacsvox-aural-schemes-file))
           (routing-before (emacsvox-aural-voice-drafts--file-id emacsvox-aural-routing-profiles-file))
           (routing (or (emacsvox-aural-read-routing-profiles)
                        (emacsvox-aural-routing-user-data)))
           (sets (emacsvox-aural-routing--merge-choice-sets
                  (plist-get routing :choice-sets) emacsvox-aural-routing--choice-sets))
           (previous (emacsvox-aural--capture-coordinated-state))
           additions user-data)
      (unless (eq palette (gethash old registry))
        (user-error "Palette changed while choosing its new name; try again"))
      (setq drafts (emacsvox-aural-voice-palettes--rename-drafts old))
      (when (equal (expand-file-name emacsvox-aural-schemes-file)
                   (expand-file-name emacsvox-aural-routing-profiles-file))
        (user-error "Palette and routing stores must be distinct"))
      (setq data (plist-put data :id new))
      (dolist (entry (plist-get data :entries))
        (when-let* ((reference (plist-get (cdr entry) :local-choices)))
          (let ((snapshot (copy-tree
                           (cl-find reference sets :test #'equal
                                    :key (lambda (set) (plist-get set :id))))))
            (unless snapshot
              (user-error "Cannot rename %s: local choices for %s are missing" old (car entry)))
            (unless (and (eq (plist-get snapshot :palette) old)
                         (eq (plist-get snapshot :voice) (car entry)))
              (user-error "Local choices for %s have the wrong owner" (car entry)))
            (let ((id (emacsvox-aural-voice-editing--new-id)))
              (setcdr entry (plist-put (cdr entry) :local-choices id))
              (setq snapshot (plist-put snapshot :id id)
                    snapshot (plist-put snapshot :palette new))
              (push snapshot additions)))))
      (setq sets (emacsvox-aural-routing--merge-choice-sets sets additions))
      (remhash old registry)
      (puthash new (emacsvox-aural-compile-voice-palette-data
                    data nil emacsvox-aural-schemes-file) registry)
      (maphash
       (lambda (id record)
         (when (eq old (emacsvox-aural-voice-palette-parent record))
           (when (emacsvox-aural-voice-palette-built-in record)
             (user-error "Cannot rename %s: built-in palette %s inherits it" old id))
           (puthash id (emacsvox-aural-compile-voice-palette-data
                        (plist-put (emacsvox-aural-voice-palette-data-form record) :parent new)
                        nil (emacsvox-aural-voice-palette-source record)) registry)))
       registry)
      (maphash
       (lambda (id entry)
         (when (eq old (plist-get (emacsvox-aural-profile-entry-data entry) :voice-palette))
           (let ((copy (copy-emacsvox-aural-profile-entry entry)))
             (setf (emacsvox-aural-profile-entry-data copy)
                   (plist-put (copy-tree (emacsvox-aural-profile-entry-data entry)) :voice-palette new))
             (puthash id copy profiles)))) profiles)
      (let ((emacsvox-aural-voice-palette-registry registry)
            (emacsvox-aural-profile-registry profiles)
            (emacsvox-aural-routing--choice-sets sets))
        (maphash (lambda (id _) (emacsvox-aural-voice-runtime--validate id)) registry)
        (setq user-data (emacsvox-aural--validate-user-data (emacsvox-aural-user-data))))
      ;; Old immutable snapshots remain valid if the second write fails.
      (unless (and (equal aural-before (emacsvox-aural-voice-drafts--file-id emacsvox-aural-schemes-file))
                   (equal routing-before (emacsvox-aural-voice-drafts--file-id emacsvox-aural-routing-profiles-file)))
        (user-error "Saved voice data changed while preparing the rename; try again"))
      (when additions
        (emacsvox-aural-routing--write-user-data (plist-put routing :choice-sets sets)))
      (condition-case error-data
          (progn
            (unless (equal aural-before (emacsvox-aural-voice-drafts--file-id emacsvox-aural-schemes-file))
              (error "Saved palette data changed during rename"))
            (emacsvox-aural--write-user-data user-data))
        (error
         (if additions
             (error "Rename not completed; original palette unchanged. Extra local snapshots are retained; retry renaming. %s"
                    (error-message-string error-data))
           (signal (car error-data) (cdr error-data)))))
      (setq emacsvox-aural-voice-palette-registry registry
            emacsvox-aural-profile-registry profiles
            emacsvox-aural-routing--choice-sets sets)
      (when (eq emacsvox-aural-voice-palette-override old)
        (setq emacsvox-aural-voice-palette-override new))
      (emacsvox-aural-voice-palettes--rename-views old new drafts)
      (emacsvox-aural--notify-coordinated-state-change previous 'voice-palette-renamed '(voice-palette))
      (emacsvox-aural-voice-palettes-refresh new)
      (emacsvox-aural-ui-refresh-home-if-live)
      (emacsvox-aural-ui-announce-result "Renamed voice palette %s to %s" old new)
      new)))

(defun emacsvox-aural-voice-palettes-activate ()
  "Activate the voice palette at point as an override."
  (interactive)
  (let ((id (emacsvox-aural-voice-palettes--at-point-or-read)))
    (emacsvox-aural-select-voice-palette id)
    (emacsvox-aural-voice-palettes-refresh id)
    (emacsvox-aural-ui-refresh-home-if-live)
    (emacsvox-aural-voice-palettes-speak-current)
    id))

(defun emacsvox-aural-voice-palettes-follow-baseline ()
  "Clear the palette override and use the compatibility baseline."
  (interactive)
  (emacsvox-aural-select-voice-palette nil)
  (emacsvox-aural-voice-palettes-refresh
   (emacsvox-aural-voice-palettes--active-id))
  (emacsvox-aural-ui-refresh-home-if-live)
  (emacsvox-aural-voice-palettes-speak-current))

(defun emacsvox-aural-voice-palettes--read-voice (id &optional prompt)
  "Read an effective voice from palette ID using PROMPT."
  (intern
   (completing-read
    (or prompt "Voice to preview: ")
    (mapcar
     (lambda (entry) (symbol-name (car entry)))
     (emacsvox-aural-effective-voice-entries id))
    nil 'must-match)))

(defun emacsvox-aural-voice-palettes--entry-provider (name palette-id)
  "Return the palette that directly provides voice NAME to PALETTE-ID."
  (let ((current palette-id)
        provider)
    (while (and current (not provider))
      (let ((palette (emacsvox-aural-voice-palette current)))
        (when (assq name (emacsvox-aural-voice-palette-entries palette))
          (setq provider current))
        (setq current (emacsvox-aural-voice-palette-parent palette))))
    provider))

(defun emacsvox-aural-voice-palettes--preview-entries (palette)
  "Return effective entries for PALETTE in predictable voice-name order."
  (sort
   (copy-sequence (emacsvox-aural-effective-voice-entries palette))
   (lambda (left right)
     (string-lessp
      (symbol-name (car left))
      (symbol-name (car right))))))

(defun emacsvox-aural-voice-palettes--definition-summary (definition)
  "Return a concise display description of voice DEFINITION."
  (if (symbolp definition)
      (format "personality %s" definition)
    (string-trim
     (replace-regexp-in-string
      "[\n\t ]+" " " (prin1-to-string definition)))))

(defun emacsvox-aural-voice-palettes--effective-summary (compiled)
  "Return a concise effective-style description for COMPILED voice data."
  (string-trim
   (replace-regexp-in-string
    "[\n\t ]+" " "
    (prin1-to-string
     (emacsvox-aural-compiled-voice-style compiled)))))

(defun emacsvox-aural-voice-palettes--preview-status (compiled)
  "Return concise audition status for COMPILED voice data."
  (let ((command (emacsvox-aural-compiled-voice-command compiled))
        (degradations
         (emacsvox-aural-compiled-voice-degradations compiled)))
    (cond
     ((eq command 'inaudible) "inaudible")
     (degradations
      (format
       "%d fallback%s"
       (length degradations)
       (if (= (length degradations) 1) "" "s")))
     (t "ready"))))

(defun emacsvox-aural-voice-palette-previews--row (entry)
  "Describe saved physical choices, shared adjustments and draft state for ENTRY."
  (let ((name (car entry)) (palette emacsvox-aural-voice-palette-previews-palette))
    (condition-case err
        (let* ((opened (emacsvox-aural-voice-editing--snapshot palette name (emacsvox-aural-voice-runtime--profile)))
               (snapshot (plist-get opened :snapshot))
               (chain (plist-get snapshot :selectors)) (first (car chain))
               (style (emacsvox-aural-voice-editing--style snapshot palette))
               (changes (cl-loop for dimension in '(rate-offset average-pitch pitch-range stress richness gain low-pass high-pass pan reverb echo chorus)
                                 for key = (emacsvox-aural--voice-dimension-key dimension)
                                 when (numberp (plist-get style key))
                                 collect (format "%s %s" (emacsvox-aural-humanize dimension)
                                                 (emacsvox-aural-voice-tuner--value-description dimension (plist-get style key))))))
          (list name
                (vector (symbol-name name)
                        (concat (pcase (plist-get first :kind)
                                  ('exact (plist-get first :voice-id)) ('engine-default "Engine default")
                                  ('properties "Matching properties") (_ "Automatic"))
                                (if (cdr chain) (format " (+%d fallback)" (length (cdr chain))) ""))
                        (or (plist-get first :engine-id) "Automatic")
                        (if changes (string-join changes "; ") "Adapter defaults")
                        (or (and (fboundp 'emacsvox-aural-voice-editor--status-for)
                                 (emacsvox-aural-voice-editor--status-for palette name))
                            (if (plist-get opened :diagnostics) "Missing local choices"
                              (if (emacsvox-aural-voice-runtime--owned-p palette)
                                  "Saved; palette-owned" "Legacy shared routing"))))))
      (error (list name (vector (symbol-name name) "Unavailable" "" "" (error-message-string err)))))))

(defun emacsvox-aural-voice-palette-previews--set-entries ()
  "Populate the current voice-palette preview buffer."
  (setq
   tabulated-list-entries
   (mapcar
    #'emacsvox-aural-voice-palette-previews--row
    emacsvox-aural-voice-palette-previews-entries)))

(defun emacsvox-aural-voice-palette-previews--goto (voice)
  "Move to VOICE and its first preview column."
  (emacsvox-aural-ui-goto-row voice))

(defun emacsvox-aural-voice-palette-previews--update-header ()
  "Update the current preview buffer's palette and sample heading."
  (setq
   header-line-format
   (format
    " Palette: %s    Comparison text: %s"
    emacsvox-aural-voice-palette-previews-palette
    emacsvox-aural-voice-palette-previews-text)))

(defun emacsvox-aural-voice-palette-previews-refresh (&optional voice)
  "Refresh palette voices, preserving VOICE and the current column."
  (interactive)
  (let ((selected
         (or
          voice
          (tabulated-list-get-id)
          (gethash
           emacsvox-aural-voice-palette-previews-palette
           emacsvox-aural-voice-palettes--last-preview-voices)
          (caar emacsvox-aural-voice-palette-previews-entries))))
    (setq
     emacsvox-aural-voice-palette-previews-entries
     (emacsvox-aural-voice-palettes--preview-entries
      emacsvox-aural-voice-palette-previews-palette))
    (unless emacsvox-aural-voice-palette-previews-entries
      (user-error
       "Voice palette %s has no effective voices"
       emacsvox-aural-voice-palette-previews-palette))
    (unless (assq selected emacsvox-aural-voice-palette-previews-entries)
      (setq selected (caar emacsvox-aural-voice-palette-previews-entries)))
    (emacsvox-aural-ui-refresh-tabulated
     #'emacsvox-aural-voice-palette-previews--set-entries
     selected nil
     #'emacsvox-aural-voice-palette-previews--update-header)))

(defun emacsvox-aural-voice-palette-previews--current-voice ()
  "Return the effective voice represented by the current preview row."
  (or
   (tabulated-list-get-id)
   (user-error "Move to a voice first")))

(defun emacsvox-aural-voice-palette-previews--remember-current ()
  "Remember the voice selected by the current preview row."
  (when-let* ((voice (tabulated-list-get-id)))
    (puthash
     emacsvox-aural-voice-palette-previews-palette
     voice
     emacsvox-aural-voice-palettes--last-preview-voices))
  (tabulated-list-get-id))

(defun emacsvox-aural-voice-palette-previews-speak-current ()
  "Speak the complete palette voice row at point."
  (interactive)
  (let* ((voice
          (emacsvox-aural-voice-palette-previews--current-voice))
         (row
          (or
           (cadr (assq voice tabulated-list-entries))
           (user-error "Unknown voice: %s" voice)))
         (summary
          (format
           "%s. Physical choice %s. Engine %s. Adjustments %s. State %s."
           (aref row 0)
           (aref row 1)
           (aref row 2)
           (aref row 3)
           (aref row 4))))
    (emacsvox-aural-voice-palette-previews--remember-current)
    (if (fboundp 'tts-speak)
        (tts-speak summary)
      (message "%s" summary))
    summary))

(defun emacsvox-aural-voice-palette-previews-speak-current-cell ()
  "Speak the current preview column title and value."
  (interactive)
  (emacsvox-aural-ui-speak-current-cell))

(defun emacsvox-aural-voice-palette-previews-next ()
  "Move to and speak the next effective voice."
  (interactive)
  (emacsvox-aural-ui-move-row 1 "palette voices")
  (emacsvox-aural-voice-palette-previews--remember-current))

(defun emacsvox-aural-voice-palette-previews-previous ()
  "Move to and speak the previous effective voice."
  (interactive)
  (emacsvox-aural-ui-move-row -1 "palette voices")
  (emacsvox-aural-voice-palette-previews--remember-current))

(defun emacsvox-aural-voice-palette-previews-next-column ()
  "Move right and speak the next voice column."
  (interactive)
  (emacsvox-aural-ui-move-column 1))

(defun emacsvox-aural-voice-palette-previews-previous-column ()
  "Move left and speak the previous voice column."
  (interactive)
  (emacsvox-aural-ui-move-column -1))

(defun emacsvox-aural-voice-palettes--preview-sample (voice text)
  "Return comparison TEXT labelled with VOICE."
  (format
   "%s voice. %s"
   (capitalize (emacsvox-aural-humanize voice))
   text))

(defun emacsvox-aural-voice-palettes--compiled-preview-plan
    (compiled label text)
  "Return a preview plan for COMPILED voice and comparison TEXT under LABEL."
  (let ((command (emacsvox-aural-compiled-voice-command compiled)))
    (when (eq command 'inaudible)
      (user-error "Voice %s suppresses speech" label))
    (emacsvox-aural-preview-compiled-voice-plan
     compiled
     (emacsvox-aural-voice-palettes--preview-sample label text))))

(defun emacsvox-aural-voice-palettes--preview-plan
    (palette voice text)
  "Return a preview plan for VOICE from PALETTE speaking comparison TEXT."
  (emacsvox-aural-voice-palettes--compiled-preview-plan
   (emacsvox-aural-compile-voice-style voice palette)
   voice text))

(defun emacsvox-aural-voice-palette-previews-play ()
  "Audition the effective voice at point with the comparison text."
  (interactive)
  (let ((voice
         (emacsvox-aural-voice-palette-previews--current-voice)))
    (emacsvox-aural-voice-palette-previews--remember-current)
    (let ((plan
           (emacsvox-aural-voice-palettes--preview-plan
            emacsvox-aural-voice-palette-previews-palette
            voice
            emacsvox-aural-voice-palette-previews-text)))
      (emacsvox-aural-preview-play-plan plan))))

(defun emacsvox-aural-voice-palette-previews-play-all ()
  "Audition every effective voice using the same comparison text."
  (interactive)
  (let ((count 0)
        unavailable
        runs)
    (dolist (entry emacsvox-aural-voice-palette-previews-entries)
      (condition-case error
          (let* ((plan
                  (emacsvox-aural-voice-palettes--preview-plan
                   emacsvox-aural-voice-palette-previews-palette
                   (car entry)
                   emacsvox-aural-voice-palette-previews-text))
                 (text
                  (emacsvox-aural-concrete-content-text
                   (emacsvox-aural-concrete-plan-content plan))))
            (push (list plan text nil) runs)
            (cl-incf count))
        (error
         (push
          (format "%s: %s" (car entry) (error-message-string error))
          unavailable))))
    (unless (> count 0)
      (user-error "No voices in this palette can be previewed"))
    (emacsvox-aural-preview-play-runs (nreverse runs))
    (emacsvox-aural-preview-message
     "Previewing %d voice%s%s; press s to stop"
     count
     (if (= count 1) "" "s")
     (if unavailable
         (format ", skipped %d unavailable" (length unavailable))
       ""))
    (list :queued count :unavailable (nreverse unavailable))))

(defun emacsvox-aural-voice-palette-previews-stop ()
  "Stop the current voice audition."
  (interactive)
  (emacsvox-aural-preview-stop)
  (emacsvox-aural-preview-message "Voice preview stopped"))

(defun emacsvox-aural-voice-palette-previews-set-text ()
  "Set the comparison text used by this preview buffer."
  (interactive)
  (let ((text
         (string-trim
          (read-string
           "Voice comparison text: "
           emacsvox-aural-voice-palette-previews-text))))
    (when (string-empty-p text)
      (user-error "Comparison text cannot be empty"))
    (setq emacsvox-aural-voice-palette-previews-text text)
    (emacsvox-aural-voice-palette-previews--update-header)
    (if (fboundp 'tts-speak)
        (tts-speak "Voice comparison text updated")
      (message "Voice comparison text updated"))
    text))

(defun emacsvox-aural-voice-palette-previews-open-manager ()
  "Return to the palette manager for the current preview palette."
  (interactive)
  (emacsvox-aural-list-voice-palettes
   emacsvox-aural-voice-palette-previews-palette))

(defun emacsvox-aural-voice-palette-previews-explain ()
  "Explain the effective voice at point."
  (interactive)
  (emacsvox-aural-voice-palettes-explain
   emacsvox-aural-voice-palette-previews-palette
   (emacsvox-aural-voice-palette-previews--current-voice)))

(defun emacsvox-aural-voice-palette-previews--editable-palette ()
  "Return an editable palette for the current voice preview.

When the preview shows a built-in palette, offer to create and activate an
empty personal overlay that inherits from it.  Continue the current preview
in that overlay so subsequent edits do not create more palettes."
  (let* ((source emacsvox-aural-voice-palette-previews-palette)
         (palette (emacsvox-aural-voice-palette source)))
    (if (not (emacsvox-aural-voice-palette-built-in palette))
        source
      (unless
          (y-or-n-p
           (format
            "Palette %s is built in; create and activate a personal overlay? "
            source))
        (user-error "Voice editing cancelled"))
      (let* ((id
              (emacsvox-aural-voice-palettes--read-new-id
               (format "%s-personal" source)))
             (data
              (list
               :schema-version emacsvox-aural-voice-palette-schema-version
               :id id
               :summary (format "Personal additions to %s" source)
               :parent source
               :entries nil)))
        (emacsvox-aural-voice-palettes--install-data data)
        (emacsvox-aural-select-voice-palette id)
        (setq emacsvox-aural-voice-palette-previews-palette id)
        (message "Created and activated personal voice palette %s" id)
        id))))

(defun emacsvox-aural-voice-palette-previews-edit ()
  "Replace the effective voice at point using the guided definition editor."
  (interactive)
  (let* ((voice
          (emacsvox-aural-voice-palette-previews--current-voice)))
    (if (emacsvox-aural-voice-runtime--owned-p emacsvox-aural-voice-palette-previews-palette)
        (emacsvox-aural-voice-palette-previews-tune)
      (let ((palette-id
           (emacsvox-aural-voice-palette-previews--editable-palette)))
      (emacsvox-aural-voice-palettes--edit-entry palette-id voice)
      (emacsvox-aural-voice-palette-previews-refresh voice)
        voice))))

(defun emacsvox-aural-voice-tuner--complete-style
    (definition palette)
  "Return a complete ACSS style for DEFINITION resolved through PALETTE."
  (let* ((requested
          (and
           (emacsvox-aural-voice-style-p definition)
           (copy-tree definition)))
         (compiled
          (unless requested
            (emacsvox-aural-compile-voice-style definition palette)))
         (source
          (or
           requested
           (and
            compiled
            (copy-tree
             (emacsvox-aural-compiled-voice-style compiled)))))
         style)
    (dolist (dimension emacsvox-aural-rich-voice-dimensions)
      (let ((key (emacsvox-aural--voice-dimension-key dimension)))
        (setq
         style
         (plist-put
          style key
          (and source (plist-get source key))))))
    style))

(defun emacsvox-aural-voice-tuner--adapter ()
  "Return the active tuner adapter identifier."
  (or (plist-get emacsvox-aural-voice-tuner-route-engine :engine-id)
      (plist-get (emacsvox-aural-active-voice-capabilities) :adapter)))

(defun emacsvox-aural-voice-tuner--capability-dimensions ()
  "Return dimensions supported by the selected tuner route."
  (if emacsvox-aural-voice-tuner-route-engine
      (let ((dimensions
             (copy-sequence
              (plist-get emacsvox-aural-voice-tuner-route-engine
                         :acss-dimensions))))
        (when (and
               (memq 'rate dimensions)
               (memq
                'rate-offset
                (plist-get
                 (emacsvox-aural-active-voice-capabilities) :dimensions)))
          (push 'rate-offset dimensions))
        dimensions)
    (plist-get (emacsvox-aural-active-voice-capabilities) :dimensions)))

(defun emacsvox-aural-voice-tuner--effect-dimension-p (dimension)
  "Return non-nil when DIMENSION is a post-synthesis effect."
  (memq dimension emacsvox-aural-post-synthesis-dimensions))

(defun emacsvox-aural-voice-tuner--normalized-dimensions (values)
  "Normalize adapter dimension VALUES to Lisp symbols."
  (mapcar
   (lambda (value)
     (intern
      (replace-regexp-in-string
       "_" "-" (if (symbolp value) (symbol-name value) value))))
   values))

(defun emacsvox-aural-voice-tuner--supported-p (dimension)
  "Return non-nil when the selected route supports DIMENSION."
  (and
   (not (and emacsvox-aural-voice-tuner-route-selector
             (eq dimension 'family)))
   (if (emacsvox-aural-voice-tuner--effect-dimension-p dimension)
       (memq
        dimension
        (emacsvox-aural-voice-tuner--normalized-dimensions
         (if emacsvox-aural-voice-tuner-route-engine
             (plist-get emacsvox-aural-voice-tuner-route-engine
                        :post-synthesis-dimensions)
           (plist-get (emacsvox-aural-active-voice-capabilities)
                      :post-synthesis-dimensions))))
     (memq dimension
           (emacsvox-aural-voice-tuner--capability-dimensions)))))

(defun emacsvox-aural-voice-tuner--degraded-p (dimension)
  "Return non-nil when the latest routed preview omitted DIMENSION."
  (and
   emacsvox-aural-voice-tuner-route-selector
   (memq
    dimension
    (plist-get
     emacsvox-aural-voice-tuner-preview-result
     (if (emacsvox-aural-voice-tuner--effect-dimension-p dimension)
         :degraded-effects
       :degraded-acss)))))

(defun emacsvox-aural-voice-tuner--applied-p (dimension)
  "Return non-nil when the current preview applies DIMENSION."
  (and
   (emacsvox-aural-voice-tuner--supported-p dimension)
   (not (emacsvox-aural-voice-tuner--degraded-p dimension))
   (or
    emacsvox-aural-voice-tuner-route-selector
    (not (emacsvox-aural-voice-tuner--effect-dimension-p dimension))
    (emacsvox-aural-preview-structured-style-supported-p))))

(defun emacsvox-aural-voice-tuner--value (dimension)
  "Return the current requested value for DIMENSION."
  (plist-get
   emacsvox-aural-voice-tuner-working-style
   (emacsvox-aural--voice-dimension-key dimension)))

(defun emacsvox-aural-voice-tuner--display-value (value)
  "Return a user-facing description of voice VALUE."
  (if (null value) "adapter default" (format "%s" value)))

(defun emacsvox-aural-voice-tuner--control-value (dimension value)
  "Convert stored DIMENSION VALUE to its displayed control value.
Low-pass amounts run opposite to stored cutoffs.  All other values,
including nil for the adapter default, retain their representation."
  (if (and (eq dimension 'low-pass) (numberp value)) (- 9 value) value))

(defun emacsvox-aural-voice-tuner--stored-value (dimension value)
  "Convert displayed DIMENSION VALUE to its stored representation."
  (emacsvox-aural-voice-tuner--control-value dimension value))

(defun emacsvox-aural-voice-tuner--rate-offset-description (value)
  "Return a concise description of relative rate VALUE."
  (cond
   ((or (null value) (zerop value)) "unchanged")
   ((< value 0)
    (format "%d point%s slower" (- value) (if (= value -1) "" "s")))
   (t
    (format "%d point%s faster" value (if (= value 1) "" "s")))))

(defun emacsvox-aural-voice-tuner--value-description (dimension value)
  "Return the concise tuner description of DIMENSION VALUE."
  (cond
   ((null value) "adapter default")
   ((eq dimension 'rate-offset)
    (emacsvox-aural-voice-tuner--rate-offset-description value))
   ((and (eq dimension 'gain) (= value 5)) "unchanged")
   ((memq dimension '(low-pass high-pass))
    (let ((amount (emacsvox-aural-voice-tuner--control-value dimension value)))
      (if (zerop amount) "0 (neutral)" (number-to-string amount))))
   ((and (memq dimension '(reverb echo chorus)) (zerop value))
    "disabled")
   ((and (eq dimension 'pan) (= value 5)) "centre")
   (t (emacsvox-aural-voice-tuner--display-value value))))

(defun emacsvox-aural-voice-tuner--dimension-label (dimension)
  "Return the user-facing tuner label for DIMENSION."
  (pcase dimension
    ('family
     (if (eq (plist-get (emacsvox-aural-active-voice-capabilities)
                        :family-selection)
             'routed)
         "Portable Fallback Family"
       "Base Voice (ACSS Family)"))
    ('rate-offset "Relative Rate")
    ('low-pass "Low-pass Amount")
    ('high-pass "High-pass Amount")
    (_ (capitalize (emacsvox-aural-humanize dimension)))))

(defun emacsvox-aural-voice-tuner--family-description
    (family &optional effective)
  "Describe requested FAMILY, or its EFFECTIVE adapter realization."
  (if (null family)
      "adapter default"
    (let* ((capability (emacsvox-aural-active-voice-capabilities))
           (resolved
            (and
             effective
             (fboundp 'tts-voice-family-id)
             (tts-voice-family-id family capability)))
           (display-id (or resolved family))
           (entry
            (and
             (fboundp 'tts-voice-family-capability)
             (tts-voice-family-capability display-id capability)))
           (label (plist-get (cdr entry) :label)))
      (if label
          (format "%s — %s" display-id label)
        (format "%s" display-id)))))

(defun emacsvox-aural-voice-tuner--requested-value (dimension)
  "Describe the requested tuner value for DIMENSION."
  (let ((value (emacsvox-aural-voice-tuner--value dimension)))
    (pcase dimension
      ('family (emacsvox-aural-voice-tuner--family-description value))
      (_ (emacsvox-aural-voice-tuner--value-description dimension value)))))

(defun emacsvox-aural-voice-tuner--support-description (dimension)
  "Describe active adapter support for DIMENSION."
  (if (not emacsvox-aural-voice-tuner-route-selector)
      (cond
       ((not (emacsvox-aural-voice-tuner--supported-p dimension))
        (format
         "unsupported by %s"
         (emacsvox-aural-humanize
          (emacsvox-aural-voice-tuner--adapter))))
       ((not (emacsvox-aural-voice-tuner--applied-p dimension))
        "requested; preview transport cannot apply")
       (t
        (format
         "supported by %s"
         (emacsvox-aural-humanize
          (emacsvox-aural-voice-tuner--adapter)))))
    (cond
     ((and emacsvox-aural-voice-tuner-route-selector
           (eq dimension 'family))
      "portable fallback; physical route owns the base voice")
     ((emacsvox-aural-voice-tuner--degraded-p dimension)
      (format "omitted by %s" (emacsvox-aural-voice-tuner--adapter)))
     ((emacsvox-aural-voice-tuner--supported-p dimension)
      (format "%s by %s"
              (if (emacsvox-aural-voice-tuner--effect-dimension-p dimension)
                  "Omnivox-rendered"
                "engine-rendered")
              (emacsvox-aural-voice-tuner--adapter)))
     (t
      (format "omitted by %s" (emacsvox-aural-voice-tuner--adapter))))))

(defun emacsvox-aural-voice-tuner--effective-value (dimension)
  "Describe the auditioned value for DIMENSION."
  (if emacsvox-aural-voice-tuner-route-selector
      (cond
       ((eq dimension 'family) "physical route owns the base voice")
       ((emacsvox-aural-voice-tuner--degraded-p dimension) "reported omitted")
       ((not (emacsvox-aural-voice-tuner--supported-p dimension)) "unsupported")
       ((memq (plist-get emacsvox-aural-voice-tuner-preview-result :status) '(failed cancelled))
        "preview did not complete")
       ((eq (plist-get emacsvox-aural-voice-tuner-preview-result :status) 'completed)
        "playback accepted; exact value not reported")
       (t "advertised support; no playback report"))
    (if (emacsvox-aural-voice-tuner--applied-p dimension)
        (if (eq dimension 'family)
            (let* ((value (emacsvox-aural-voice-tuner--value dimension))
                   (capability (emacsvox-aural-active-voice-capabilities))
                   (selection (plist-get capability :family-selection))
                   (resolved
                    (and
                     value
                     (fboundp 'tts-voice-family-id)
                     (tts-voice-family-id value capability))))
              (cond
               ((null value) "adapter default")
               ((and (eq selection 'enumerated) (null resolved))
                "adapter default; requested family unavailable")
               (t
                (emacsvox-aural-voice-tuner--family-description value t))))
          (emacsvox-aural-voice-tuner--value-description
           dimension
           (emacsvox-aural-voice-tuner--value dimension)))
      "not applied")))

(defun emacsvox-aural-voice-tuner--route-description ()
  "Return the currently requested and realized tuner route."
  (if (not emacsvox-aural-voice-tuner-route-selector)
      (format "adapter %s" (emacsvox-aural-voice-tuner--adapter))
    (let ((realized emacsvox-aural-voice-tuner-route-realized))
      (format
       "route %S; realized %s"
       emacsvox-aural-voice-tuner-route-selector
       (if realized
           (format "%s/%s"
                   (plist-get realized :engine-id)
                   (plist-get realized :voice-id))
         "pending")))))

(defun emacsvox-aural-voice-tuner--row (dimension)
  "Return one tabulated tuner row for DIMENSION."
  (list
   dimension
   (vector
    (emacsvox-aural-voice-tuner--dimension-label dimension)
    (emacsvox-aural-voice-tuner--requested-value dimension)
    (emacsvox-aural-voice-tuner--effective-value dimension)
    (emacsvox-aural-voice-tuner--support-description dimension)
    (or
     (alist-get
      dimension
      emacsvox-aural-voice-tuner--dimension-descriptions)
     ""))))

(defun emacsvox-aural-voice-tuner--set-entries ()
  "Populate the current voice tuner."
  (setq
   tabulated-list-entries
   (mapcar
    #'emacsvox-aural-voice-tuner--row
    emacsvox-aural-rich-voice-dimensions)))

(defun emacsvox-aural-voice-tuner--goto (dimension)
  "Move to tuner DIMENSION and its first column."
  (emacsvox-aural-ui-goto-row dimension))

(defun emacsvox-aural-voice-tuner--update-header ()
  "Update tuner identity, adapter, and transaction state."
  (setq
   header-line-format
   (format
    " Voice: %s    Palette: %s    %s    %s"
    emacsvox-aural-voice-tuner-voice
    (or emacsvox-aural-voice-tuner-palette "temporary experiment")
    (emacsvox-aural-voice-tuner--route-description)
    (concat
     (if emacsvox-aural-voice-tuner-dirty "modified" "unchanged")
     (if emacsvox-aural-voice-tuner-legacy-rate
         (format "; legacy absolute rate %s ignored—retune Relative Rate"
                 emacsvox-aural-voice-tuner-legacy-rate)
       ""))))
  (force-mode-line-update))

(defun emacsvox-aural-voice-tuner-refresh (&optional dimension)
  "Refresh the tuner while preserving DIMENSION and the current column."
  (interactive)
  (emacsvox-aural-ui-refresh-tabulated
   #'emacsvox-aural-voice-tuner--set-entries
   dimension
   (car emacsvox-aural-rich-voice-dimensions)
   #'emacsvox-aural-voice-tuner--update-header))

(defun emacsvox-aural-voice-tuner--current-dimension ()
  "Return the voice dimension represented by the current tuner row."
  (or
   (tabulated-list-get-id)
   (user-error "Move to a voice setting first")))

(defun emacsvox-aural-voice-tuner-speak-current ()
  "Speak the complete tuner row at point."
  (interactive)
  (let* ((dimension (emacsvox-aural-voice-tuner--current-dimension))
         (row
          (or
           (cadr (assq dimension tabulated-list-entries))
           (user-error "Unknown voice setting: %s" dimension)))
         (summary
          (format
           "%s. Requested %s. Auditioned %s. %s. %s."
           (aref row 0)
           (aref row 1)
           (aref row 2)
           (aref row 3)
           (aref row 4))))
    (emacsvox-aural-ui-speak summary)
    summary))

(defun emacsvox-aural-voice-tuner-next ()
  "Move to and speak the next tunable dimension."
  (interactive)
  (emacsvox-aural-ui-move-row
   1 "voice settings"
   #'emacsvox-aural-voice-tuner--speak-setting))

(defun emacsvox-aural-voice-tuner-previous ()
  "Move to and speak the previous tunable dimension."
  (interactive)
  (emacsvox-aural-ui-move-row
   -1 "voice settings"
   #'emacsvox-aural-voice-tuner--speak-setting))

(defun emacsvox-aural-voice-tuner--setting-announcement (dimension)
  "Describe the current DIMENSION value and adapter support."
  (format
   "%s %s. %s%s"
   (emacsvox-aural-voice-tuner--dimension-label dimension)
   (emacsvox-aural-voice-tuner--requested-value dimension)
   (capitalize
    (emacsvox-aural-voice-tuner--support-description dimension))
   (if (emacsvox-aural-voice-tuner--applied-p dimension)
       "."
     "; this setting is requested but is not applied in this audition.")))

(defun emacsvox-aural-voice-tuner--speak-setting ()
  "Speak the current setting name, value, and adapter support."
  (let ((summary
         (emacsvox-aural-voice-tuner--setting-announcement
          (emacsvox-aural-voice-tuner--current-dimension))))
    (when (fboundp 'emacsvox-icon)
      (emacsvox-icon 'select-object))
    (emacsvox-aural-ui-speak summary)
    summary))

(defun emacsvox-aural-voice-tuner--normalized-acss (style)
  "Return normalized routed ACSS values from tuner STYLE."
  (let (acss)
    (dolist (dimension '(average-pitch pitch-range stress richness))
      (let* ((key (emacsvox-aural--voice-dimension-key dimension))
             (value (plist-get style key)))
        (when (numberp value)
          (setq
           acss
           (plist-put
            acss key (/ (float (max 0 (min 9 value))) 9.0))))))
    acss))

(defun emacsvox-aural-voice-tuner--normalized-effects (style)
  "Return normalized routed post-synthesis effects from tuner STYLE."
  (let (effects)
    (dolist (dimension emacsvox-aural-post-synthesis-dimensions)
      (let* ((key (emacsvox-aural--voice-dimension-key dimension))
             (value (plist-get style key)))
        (when (numberp value)
          (setq
           effects
           (plist-put
            effects key
            (emacsvox-aural-normalize-post-synthesis-value
             dimension value))))))
    effects))

(defun emacsvox-aural-voice-tuner--play-text
    (text style &optional record-result)
  "Speak TEXT through unsaved tuner STYLE.

When RECORD-RESULT is non-nil, retain routed realization and degradation
information for the working tuner display."
  (if emacsvox-aural-voice-tuner-route-selector
      (let ((buffer (current-buffer))
            (generation (cl-incf emacsvox-aural-voice-tuner-preview-generation))
            (feedback emacsvox-aural-voice-tuner--feedback-p))
        (when record-result
          (setq emacsvox-aural-voice-tuner-preview-result
                '(:status running)))
        (tts-preview-voice
         text emacsvox-aural-voice-tuner-route-selector
         :acss (emacsvox-aural-voice-tuner--normalized-acss style)
         :rate-offset (plist-get style :rate-offset)
         :effects (emacsvox-aural-voice-tuner--normalized-effects style)
         :language emacsvox-aural-voice-tuner-route-language
         :callback
         (when record-result
           (lambda (result)
             (when (and (buffer-live-p buffer)
                        (= generation (buffer-local-value
                                       'emacsvox-aural-voice-tuner-preview-generation buffer)))
               (with-current-buffer buffer
                 (setq emacsvox-aural-voice-tuner-preview-result result)
                 (when (eq (plist-get result :status) 'failed)
                   (tts-speak
                    (if feedback (concat "Tuned voice unavailable. " text)
                      (format "Voice preview failed: %s"
                              (or (plist-get result :message) "requested voice unavailable")))))
                 (when-let* ((realized (plist-get result :realized)))
                   (setq emacsvox-aural-voice-tuner-route-realized realized))
                 (when (derived-mode-p 'emacsvox-aural-voice-tuner-mode)
                   (emacsvox-aural-voice-tuner-refresh
                    (tabulated-list-get-id))))))))
        (and record-result emacsvox-aural-voice-tuner-preview-result))
    (let* ((compiled
            (emacsvox-aural-compile-voice-style
             style emacsvox-aural-voice-tuner-palette))
           (plan
            (emacsvox-aural-preview-compiled-voice-plan compiled text)))
      (emacsvox-aural-preview-play-plan plan)
      compiled)))

(defun emacsvox-aural-voice-tuner--speak-text (text)
  "Speak ordinary tuner feedback TEXT through the current working style.

If the staged route cannot be previewed, fall back to normal speech so that
the tuner remains operable."
  (condition-case error-data
      (let ((emacsvox-aural-voice-tuner--feedback-p t))
        (emacsvox-aural-voice-tuner--play-text
         text emacsvox-aural-voice-tuner-working-style t))
    (error
     (emacsvox-aural-preview-message
      "Tuned voice unavailable; using normal speech: %s"
      (error-message-string error-data))
     (if (fboundp 'tts-speak)
         (tts-speak text)
       (message "%s" text))))
  text)

(defun emacsvox-aural-voice-tuner-audition (&optional announcement)
  "Audition the unsaved working style after optional ANNOUNCEMENT."
  (interactive)
  (let ((text
         (concat
          (and announcement (concat announcement " "))
          (emacsvox-aural-voice-palettes--preview-sample
           emacsvox-aural-voice-tuner-voice
           emacsvox-aural-voice-tuner-preview-text))))
    (prog1
        (emacsvox-aural-voice-tuner--play-text
         text emacsvox-aural-voice-tuner-working-style t)
      (when announcement
        (emacsvox-aural-preview-message "%s" announcement)))))

(defun emacsvox-aural-voice-tuner-compare ()
  "Alternate an opening-style and working-style comparison sample."
  (interactive)
  (let* ((reference emacsvox-aural-voice-tuner-compare-reference-next-p)
         (label (if reference "Opening voice" "Working voice"))
         (style
          (if reference
              emacsvox-aural-voice-tuner-initial-style
            emacsvox-aural-voice-tuner-working-style))
         (text
          (concat
           label ". "
           (emacsvox-aural-voice-palettes--preview-sample
            emacsvox-aural-voice-tuner-voice
            emacsvox-aural-voice-tuner-preview-text))))
    (setq emacsvox-aural-voice-tuner-compare-reference-next-p
          (not reference))
    (prog1
        (emacsvox-aural-voice-tuner--play-text text style)
      (emacsvox-aural-preview-message "%s comparison" label))))

(defun emacsvox-aural-voice-tuner--update-dirty ()
  "Update and return the tuner dirty state."
  (setq
   emacsvox-aural-voice-tuner-dirty
   (or (not (equal emacsvox-aural-voice-tuner-working-style
                   emacsvox-aural-voice-tuner-initial-style))
       (and emacsvox-aural-voice-tuner-additional-dirty-function
            (funcall emacsvox-aural-voice-tuner-additional-dirty-function)))))

(defun emacsvox-aural-voice-tuner--set-value
    (dimension value &optional announcement)
  "Set DIMENSION to VALUE, refresh, and audition the working style.

ANNOUNCEMENT overrides the normal setting description."
  (let* ((key (emacsvox-aural--voice-dimension-key dimension))
         (current (plist-get emacsvox-aural-voice-tuner-working-style key)))
    (unless (equal current value)
      (push
       (copy-tree emacsvox-aural-voice-tuner-working-style)
       emacsvox-aural-voice-tuner-history)
      (setq
       emacsvox-aural-voice-tuner-working-style
       (plist-put
        (copy-tree emacsvox-aural-voice-tuner-working-style)
        key value)
       emacsvox-aural-voice-tuner-compare-reference-next-p t)
      (emacsvox-aural-voice-tuner--update-dirty)
      (emacsvox-aural-voice-tuner-refresh dimension)
      (emacsvox-aural-voice-tuner-audition
       (concat (or announcement
                   (emacsvox-aural-voice-tuner--setting-announcement dimension))
               (when (and emacsvox-aural-voice-tuner-route-engine
                          (not (emacsvox-aural-voice-tuner--supported-p dimension)))
                 (format ", unsupported by %s" (emacsvox-aural-voice-tuner--adapter))))))
    value))

(defun emacsvox-aural-voice-tuner--numeric-dimension ()
  "Return the current numeric dimension, or report a family-row error."
  (let ((dimension (emacsvox-aural-voice-tuner--current-dimension)))
    (when (eq dimension 'family)
      (user-error "Press RET to edit the voice family"))
    dimension))

(defun emacsvox-aural-voice-tuner--set-control-value (dimension value)
  "Set displayed DIMENSION VALUE and audition its stored equivalent."
  (let ((stored (emacsvox-aural-voice-tuner--stored-value dimension value)))
    (emacsvox-aural-voice-tuner--set-value
     dimension stored
     (emacsvox-aural-voice-tuner--value-description dimension stored))))

(defun emacsvox-aural-voice-tuner-increase ()
  "Increase the current numeric dimension and audition its new value."
  (interactive)
  (let* ((dimension (emacsvox-aural-voice-tuner--numeric-dimension))
         (current (emacsvox-aural-voice-tuner--control-value
                   dimension (emacsvox-aural-voice-tuner--value dimension)))
         (rate-offset-p (eq dimension 'rate-offset))
         (value (if (numberp current)
                    (1+ current)
                  (if (or rate-offset-p (memq dimension '(low-pass high-pass))) 1 5)))
         (maximum (plist-get (emacsvox-aural--voice-style-field dimension) :maximum)))
    (when (> value maximum)
      (user-error "%s is already at %s" dimension maximum))
    (emacsvox-aural-voice-tuner--set-control-value dimension value)))

(defun emacsvox-aural-voice-tuner-decrease ()
  "Decrease the current numeric dimension and audition its new value."
  (interactive)
  (let* ((dimension (emacsvox-aural-voice-tuner--numeric-dimension))
         (current (emacsvox-aural-voice-tuner--control-value
                   dimension (emacsvox-aural-voice-tuner--value dimension)))
         (rate-offset-p (eq dimension 'rate-offset))
         (value (if (numberp current)
                    (1- current)
                  (if (or rate-offset-p (memq dimension '(low-pass high-pass))) -1 5)))
         (minimum (plist-get (emacsvox-aural--voice-style-field dimension) :minimum)))
    (when (< value minimum)
      (user-error "%s is already at %s" dimension minimum))
    (emacsvox-aural-voice-tuner--set-control-value dimension value)))

(defun emacsvox-aural-voice-tuner-set-digit ()
  "Set the current numeric dimension from the typed digit and audition it."
  (interactive)
  (let ((dimension (emacsvox-aural-voice-tuner--numeric-dimension))
        (value (- last-command-event ?0)))
    (emacsvox-aural-voice-tuner--set-control-value dimension value)))

(defun emacsvox-aural-voice-tuner-use-default ()
  "Use the adapter default for the current dimension and audition it."
  (interactive)
  (emacsvox-aural-voice-tuner--set-value
   (emacsvox-aural-voice-tuner--current-dimension)
   nil))

(defun emacsvox-aural-voice-tuner--family-candidates (capability)
  "Return accessible completion choices from family CAPABILITY."
  (let (choices)
    (dolist (generic (plist-get capability :generic-families))
      (let* ((entry
              (and
               (fboundp 'tts-voice-family-capability)
               (tts-voice-family-capability generic capability)))
             (label (plist-get (cdr entry) :label)))
        (push
         (cons
          (format
           "%s — portable%s"
           generic
           (if label (format "; currently %s" label) ""))
          generic)
         choices)))
    (dolist (entry (plist-get capability :families))
      (let ((id (car entry))
            (label (plist-get (cdr entry) :label)))
        (push
         (cons
          (if label (format "%s — %s" id label) (format "%s" id))
          id)
         choices)))
    (nreverse choices)))

(defun emacsvox-aural-voice-tuner--read-family (current)
  "Read a base voice or ACSS family, initially CURRENT."
  (let* ((capability (emacsvox-aural-active-voice-capabilities))
         (selection
          (or
           (plist-get capability :family-selection)
           (cond
            ((plist-get capability :families) 'enumerated)
            ((emacsvox-aural-voice-tuner--supported-p 'family) 'free-form)
            (t 'unsupported)))))
    (pcase selection
      ('unsupported
       (user-error
        "The %s adapter does not support inline base-voice changes"
        (plist-get capability :adapter)))
      ('enumerated
       (let* ((choices
               (cons
                '("adapter default" . nil)
                (emacsvox-aural-voice-tuner--family-candidates capability)))
              (initial-entry
               (cl-find current choices :key #'cdr :test #'equal))
              (answer
               (completing-read
                "Base voice; choose a portable family or exact voice: "
                choices nil t nil nil (car-safe initial-entry))))
         (cdr (assoc-string answer choices))))
      ('routed
       (let* ((choices
               (cons
                '("adapter default" . nil)
                (emacsvox-aural-voice-tuner--family-candidates capability)))
              (initial-entry
               (cl-find current choices :key #'cdr :test #'equal))
              (answer
               (string-trim
                (completing-read
                 "Portable fallback family (not the Omnivox route): "
                 choices nil nil nil nil
                 (or (car-safe initial-entry)
                     (and current (format "%s" current))))))
              (entry (assoc-string answer choices)))
         (if entry
             (cdr entry)
           (unless (string-empty-p answer) answer))))
      (_
       (let ((answer
              (string-trim
               (read-string
                "Installed base voice; blank means adapter default: "
                (and current (format "%s" current))))))
         (unless (string-empty-p answer) answer))))))

(defun emacsvox-aural-voice-tuner-edit ()
  "Edit the current dimension and audition the new value."
  (interactive)
  (let* ((dimension (emacsvox-aural-voice-tuner--current-dimension))
         (current (emacsvox-aural-voice-tuner--control-value
                   dimension (emacsvox-aural-voice-tuner--value dimension)))
         (value
          (if (eq dimension 'family)
              (emacsvox-aural-voice-tuner--read-family current)
            (if (eq dimension 'rate-offset)
                (let* ((field (emacsvox-aural--voice-style-field dimension))
                       (minimum (plist-get field :minimum))
                       (maximum (plist-get field :maximum))
                       (answer
                        (string-trim
                         (read-string
                          (format
                           "Relative rate, %d through %d; blank means unchanged%s: "
                           minimum maximum
                           (if current (format " [%s]" current) "")))))
                       (value
                        (unless (string-empty-p answer)
                          (string-to-number answer))))
                  (when (and
                         value
                         (not (string-match-p "\\`[-+]?[0-9]+\\'" answer)))
                    (user-error "Relative rate must be %d through %d or blank"
                                minimum maximum))
                  (when (and value (not (<= minimum value maximum)))
                    (user-error "Relative rate must be %d through %d or blank"
                                minimum maximum))
                  value)
              (emacsvox-aural-voice-palettes--read-style-number
               dimension current
               (when (memq dimension '(low-pass high-pass))
                 (emacsvox-aural-voice-tuner--dimension-label dimension)))))))
    (emacsvox-aural-voice-tuner--set-value
     dimension (emacsvox-aural-voice-tuner--stored-value dimension value))))

(defun emacsvox-aural-voice-tuner-undo ()
  "Undo the most recent unsaved tuner change and audition it."
  (interactive)
  (unless emacsvox-aural-voice-tuner-history
    (user-error "No tuner change to undo"))
  (let ((dimension (emacsvox-aural-voice-tuner--current-dimension)))
    (setq
     emacsvox-aural-voice-tuner-working-style
     (pop emacsvox-aural-voice-tuner-history)
     emacsvox-aural-voice-tuner-compare-reference-next-p t)
    (emacsvox-aural-voice-tuner--update-dirty)
    (emacsvox-aural-voice-tuner-refresh dimension)
    (emacsvox-aural-voice-tuner-audition "Undid the last voice change.")))

(defun emacsvox-aural-voice-tuner-restore ()
  "Restore and audition the style present when the tuner opened."
  (interactive)
  (when
      (equal
       emacsvox-aural-voice-tuner-working-style
       emacsvox-aural-voice-tuner-initial-style)
    (user-error "The starting voice style is already restored"))
  (let ((dimension (emacsvox-aural-voice-tuner--current-dimension)))
    (push
     (copy-tree emacsvox-aural-voice-tuner-working-style)
     emacsvox-aural-voice-tuner-history)
    (setq
     emacsvox-aural-voice-tuner-working-style
     (copy-tree emacsvox-aural-voice-tuner-initial-style)
     emacsvox-aural-voice-tuner-compare-reference-next-p t)
    (emacsvox-aural-voice-tuner--update-dirty)
    (emacsvox-aural-voice-tuner-refresh dimension)
    (emacsvox-aural-voice-tuner-audition
     "Restored the voice style from when the tuner opened.")))

(defun emacsvox-aural-voice-tuner--refresh-source
    (source palette voice)
  "Refresh SOURCE after saving VOICE in PALETTE and keep VOICE selected."
  (when (buffer-live-p source)
    (with-current-buffer source
      (when
          (and
           (derived-mode-p
            'emacsvox-aural-voice-palette-previews-mode)
           (eq
            emacsvox-aural-voice-palette-previews-palette
            palette))
        (emacsvox-aural-voice-palette-previews-refresh voice)
        (let ((position (point)))
          (dolist (window (get-buffer-window-list source nil t))
            (set-window-point window position))))
      (when (derived-mode-p 'emacsvox-aural-voice-workbench-mode)
        (when (fboundp 'emacsvox-aural-voice-workbench-refresh)
          (funcall 'emacsvox-aural-voice-workbench-refresh
                   (format "%s" voice)))))))

(defun emacsvox-aural-voice-tuner--source-route-staged-p (source)
  "Return non-nil when SOURCE is a Workbench with unsaved routing edits."
  (and
   (buffer-live-p source)
   (with-current-buffer source
     (and
      (derived-mode-p 'emacsvox-aural-voice-workbench-mode)
      (boundp 'emacsvox-aural-voice-workbench-staged-profile)
      (boundp 'emacsvox-aural-voice-workbench-committed-profile)
      (not
       (equal emacsvox-aural-voice-workbench-staged-profile
              emacsvox-aural-voice-workbench-committed-profile))))))

(defun emacsvox-aural-voice-tuner--announce-save
    (source voice style-saved)
  "Announce what was saved for VOICE and whether SOURCE has a staged route."
  (let ((text
         (concat
          (if style-saved
              (format "Portable style for %s saved. " voice)
            (format "No portable style changes for %s. " voice))
          (if (emacsvox-aural-voice-tuner--source-route-staged-p source)
              (concat
               "Its physical route is still staged, not saved. "
               "In Voice Workbench press w to save and apply the route.")
            "No physical route was changed."))))
    (if (fboundp 'tts-speak)
        (tts-speak text)
      (message "%s" text))
    text))

(defun emacsvox-aural-voice-tuner-save ()
  "Atomically save the portable style and return to the voice preview."
  (interactive)
  (let ((source emacsvox-aural-voice-tuner-source-buffer)
        (palette emacsvox-aural-voice-tuner-palette)
        (voice emacsvox-aural-voice-tuner-voice)
        saved)
    (when emacsvox-aural-voice-tuner-dirty
      (emacsvox-aural-voice-palettes--install-entry-definition
       palette voice emacsvox-aural-voice-tuner-working-style)
      (setq
       emacsvox-aural-voice-tuner-original-definition
       (copy-tree emacsvox-aural-voice-tuner-working-style)
       emacsvox-aural-voice-tuner-initial-style
       (copy-tree emacsvox-aural-voice-tuner-working-style)
       emacsvox-aural-voice-tuner-history nil
       emacsvox-aural-voice-tuner-dirty nil
       saved t))
    (emacsvox-aural-quit t)
    (when saved
      (emacsvox-aural-voice-tuner--refresh-source
       source palette voice))
    (emacsvox-aural-voice-tuner--announce-save source voice saved)))

(defun emacsvox-aural-voice-tuner-quit ()
  "Cancel tuning, asking before discarding unsaved changes."
  (interactive)
  (when
      (or
       (not emacsvox-aural-voice-tuner-dirty)
       (yes-or-no-p "Discard unsaved voice tuning changes? "))
    (emacsvox-aural-quit t)))

(defun emacsvox-aural-voice-tuner-help ()
  "Display and speak voice tuner help."
  (interactive)
  (let* ((tuner (current-buffer))
         (help
          (concat
           "Aural Voice Tuner\n\n"
           "Changes are temporary until saved.  While this tuner is active,\n"
           "its navigation, cells, rows, boundaries, and help use the current\n"
           "unsaved working voice.  Adjustment announces only its new value,\n"
           "then auditions the same comparison text.\n"
           "Unsupported dimensions remain portable but do not affect this adapter.\n"
           "Relative Rate is a signed offset from the current global 0-to-100 rate.\n"
           "For example, global 75 plus minus 1 is 74; plus 4 is 79.  Zero or\n"
           "adapter default means unchanged.  Left and right adjust one point.\n"
           "Low-pass and high-pass amounts increase filtering from zero through nine.\n"
           "Zero is the neutral cutoff; d requests the adapter default.\n"
           "Gain five is unchanged; reverb, echo, and chorus zero are disabled;\n"
           "pan five is centre.\n"
           "Omnivox pitch contrast defaults to a gentle 0.5; customize\n"
           "omnivox-average-pitch-contrast to use zero through two.\n"
           "For a routed adapter, Portable Fallback Family is retained for other\n"
           "adapters but does not replace the physical voice chosen in Workbench.\n"
           "Saving a changed personality converts this palette entry to a complete\n"
           "custom ACSS style; cancelling preserves its original definition.\n\n"
           "Tuner w saves only this portable style.  If its physical route is\n"
           "staged in Voice Workbench, return there and press w to save and apply\n"
           "that separate machine-local route.\n\n"
           "n or down next       p or up previous\n"
           "left/right decrease/increase numeric value\n"
           "0 through 9 set a nonnegative numeric value directly\n"
           "RET or e edit        d use adapter default\n"
           "P audition           B alternate opening/working comparison\n"
           "u undo last change   R restore opening style\n"
           "w save style, return C-c C-c save style, return\n"
           "q or C-c C-k cancel and return\n"
           "h aural home         ? help; C-c C-i offline voice manual\n")))
    (emacsvox-aural-ui-with-help-window
      (princ help))
    (when (buffer-live-p tuner)
      (with-current-buffer tuner
        (emacsvox-aural-voice-tuner--speak-text help)))))

(defun emacsvox-aural-voice-tuner--action-applicable-p (command)
  "Return whether tuner COMMAND applies to the current parameter and state."
  (pcase command
    ('emacsvox-aural-voice-tuner-undo emacsvox-aural-voice-tuner-history)
    ('emacsvox-aural-voice-tuner-restore emacsvox-aural-voice-tuner-dirty)
    ((or 'emacsvox-aural-voice-tuner-edit 'emacsvox-aural-voice-tuner-use-default)
     (and (tabulated-list-get-id)
          (or (not (eq (tabulated-list-get-id) 'family))
              (emacsvox-aural-voice-tuner--supported-p 'family))))
    ((or 'emacsvox-aural-voice-tuner-increase 'emacsvox-aural-voice-tuner-decrease
         'emacsvox-aural-voice-tuner-set-digit)
     (and (tabulated-list-get-id) (not (eq (tabulated-list-get-id) 'family))))
    (_ t)))

(define-derived-mode
    emacsvox-aural-voice-tuner-mode
    emacsvox-aural-tabulated-mode
  "Aural-Voice-Tuner"
  "Transactional spoken tuner for one personal-palette voice."
  (setq-local emacsvox-aural-ui-action-filter #'emacsvox-aural-voice-tuner--action-applicable-p)
  (emacsvox-aural-ui-configure-tabulated
   "voice settings"
   #'emacsvox-aural-voice-tuner-speak-current
   #'emacsvox-aural-voice-tuner-refresh
   #'emacsvox-aural-voice-tuner--speak-setting)
  (setq
   tabulated-list-format
   [("Setting" 22 nil)
    ("Requested" 18 nil)
    ("Auditioned" 18 nil)
    ("Adapter" 28 nil)
    ("Meaning" 0 nil)])
  (setq tabulated-list-padding 2)
  (setq-local
   mode-line-process
   '(:eval (when emacsvox-aural-voice-tuner-dirty " [modified]")))
  (setq-local emacsvox-aural-ui-speech-function
              #'emacsvox-aural-voice-tuner--speak-text)
  (add-hook
   'tabulated-list-revert-hook
   #'emacsvox-aural-voice-tuner--set-entries nil t)
  (tabulated-list-init-header))

(define-key emacsvox-aural-voice-tuner-mode-map (kbd "s") nil)

(dolist
    (binding
     '(("RET" . emacsvox-aural-voice-tuner-edit)
       ("e" . emacsvox-aural-voice-tuner-edit)
       ("d" . emacsvox-aural-voice-tuner-use-default)
       ("P" . emacsvox-aural-voice-tuner-audition)
       ("B" . emacsvox-aural-voice-tuner-compare)
       ("u" . emacsvox-aural-voice-tuner-undo)
       ("R" . emacsvox-aural-voice-tuner-restore)
       ("w" . emacsvox-aural-voice-tuner-save)
       ("C-c C-c" . emacsvox-aural-voice-tuner-save)
       ("C-c C-k" . emacsvox-aural-voice-tuner-quit)
       ("<right>" . emacsvox-aural-voice-tuner-increase)
       ("<left>" . emacsvox-aural-voice-tuner-decrease)
       ("+" . emacsvox-aural-voice-tuner-increase)
       ("-" . emacsvox-aural-voice-tuner-decrease)
       ("h" . emacsvox-aural)
       ("q" . emacsvox-aural-voice-tuner-quit)
       ("?" . emacsvox-aural-voice-tuner-help)))
  (define-key
   emacsvox-aural-voice-tuner-mode-map
   (kbd (car binding))
   (cdr binding)))

(dotimes (digit 10)
  (define-key
   emacsvox-aural-voice-tuner-mode-map
   (char-to-string (+ ?0 digit))
   #'emacsvox-aural-voice-tuner-set-digit))

(cl-defun emacsvox-aural-voice-tuner-open
    (palette-id voice source text
                &key selector language engine realized)
  "Open a transactional tuner for VOICE in PALETTE-ID.

SOURCE is the manager to return to and TEXT is the comparison text.  When
SELECTOR is non-nil, audition the unsaved style against that staged physical
route using LANGUAGE, discovered ENGINE capabilities, and initial REALIZED
identity."
  (let ((palette (emacsvox-aural-voice-palette palette-id)))
    (when (emacsvox-aural-voice-palette-built-in palette)
      (user-error
       "Built-in palette; press o, then c to make an editable copy"))
    (let* ((inspection-source
            (emacsvox-aural-inspection-remember-source-buffer))
           (definition (emacsvox-aural-voice voice palette-id))
           (style
            (emacsvox-aural-voice-tuner--complete-style
             definition palette-id))
           (buffer (get-buffer-create "*Aural Voice Tuner*"))
           (resume
            (with-current-buffer buffer
              (and (derived-mode-p 'emacsvox-aural-voice-tuner-mode)
                   emacsvox-aural-voice-tuner-dirty
                   (eq palette-id emacsvox-aural-voice-tuner-palette)
                   (eq voice emacsvox-aural-voice-tuner-voice)
                   (equal selector emacsvox-aural-voice-tuner-route-selector)
                   (equal language emacsvox-aural-voice-tuner-route-language)))))
      (when
          (and (not resume) (with-current-buffer buffer
                              (and
                               (derived-mode-p 'emacsvox-aural-voice-tuner-mode)
                               emacsvox-aural-voice-tuner-dirty)))
        (unless
            (yes-or-no-p
             "Discard the unsaved voice tuner before opening another voice? ")
          (user-error "Kept the existing unsaved voice tuner")))
      (with-current-buffer buffer
        (unless resume
          (emacsvox-aural-voice-tuner-mode)
          (emacsvox-aural-inspection-attach-source inspection-source)
          (setq
           emacsvox-aural-voice-tuner-palette palette-id
           emacsvox-aural-voice-tuner-voice voice
           emacsvox-aural-voice-tuner-original-definition
           (copy-tree definition)
           emacsvox-aural-voice-tuner-initial-style (copy-tree style)
           emacsvox-aural-voice-tuner-working-style (copy-tree style)
           emacsvox-aural-voice-tuner-history nil
           emacsvox-aural-voice-tuner-dirty nil
           emacsvox-aural-voice-tuner-preview-text text
           emacsvox-aural-voice-tuner-source-buffer source
           emacsvox-aural-voice-tuner-route-selector (copy-tree selector)
           emacsvox-aural-voice-tuner-route-language language
           emacsvox-aural-voice-tuner-route-engine (copy-tree engine)
           emacsvox-aural-voice-tuner-route-realized (copy-tree realized)
           emacsvox-aural-voice-tuner-preview-result nil
           emacsvox-aural-voice-tuner-compare-reference-next-p t
           emacsvox-aural-voice-tuner-legacy-rate
           (and
            (emacsvox-aural-voice-style-p definition)
            (numberp (plist-get definition :rate))
            (not (zerop (plist-get definition :rate)))
            (plist-get definition :rate)))
          (emacsvox-aural-voice-tuner-refresh)))
      (emacsvox-aural-ui-pop-to-buffer buffer)
      (emacsvox-aural-voice-tuner-speak-current)
      buffer)))

(defun emacsvox-aural-voice-palette-previews-tune ()
  "Open the common voice editor without changing the palette or its selection."
  (interactive)
  (require 'emacsvox-aural-voice-editor)
  (emacsvox-aural-voice-editor-open
   emacsvox-aural-voice-palette-previews-palette
   (emacsvox-aural-voice-palette-previews--current-voice)
   (current-buffer) emacsvox-aural-voice-palette-previews-text))

(defun emacsvox-aural-voice-palette-previews-new ()
  "Create a new voice in the palette shown by the current preview."
  (interactive)
  (let* ((palette
          (emacsvox-aural-voice-palette-previews--editable-palette))
         (voice
          (emacsvox-aural-voice-palettes--read-new-entry-name palette))
         (definition
          (emacsvox-aural-voice-palettes--read-definition)))
    (emacsvox-aural-voice-palettes--install-entry-definition
     palette voice definition)
    (emacsvox-aural-voice-palette-previews-refresh voice)
    voice))

(defun emacsvox-aural-voice-palettes--copy-owned-voice (palette source name &optional rename)
  "Save an independent copy of PALETTE's effective SOURCE voice as NAME.
When RENAME is non-nil, remove the direct SOURCE entry in the same save."
  (let* ((record (emacsvox-aural-voice-palette palette))
         (data (emacsvox-aural-voice-palette-data-form record))
         (entries (emacsvox-aural-voice-data--entries
                   palette emacsvox-aural-voice-palette-registry))
         (item (cl-find source entries :key (lambda (entry) (car (plist-get entry :entry)))))
         (properties (copy-tree (cdr (plist-get item :entry))))
         (choices (and item (emacsvox-aural-voice-data--choices
                             (plist-get item :palette) source properties
                             emacsvox-aural-routing--choice-sets (plist-get item :schema-version))))
         (layered (or (eq (plist-get data :schema-version) 3)
                      (eq (plist-get item :schema-version) 3)))
         (rows (and layered (if (plist-member choices :choices) (plist-get choices :choices)
                              (emacsvox-aural-voice-data--wrap-selectors (plist-get choices :selectors)))))
         sets)
    (when (emacsvox-aural-voice-palette-built-in record)
      (user-error "Copy the built-in palette first"))
    (unless item (user-error "Unknown voice: %s" source))
    (when (cl-find name entries :key (lambda (entry) (car (plist-get entry :entry))))
      (user-error "Voice already exists in palette %s: %s" palette name))
    (when (plist-get choices :diagnostics)
      (user-error "Cannot copy %s: its saved local voice choices are missing" source))
    (when layered
      (setq data (emacsvox-aural-voice-data--promote data)
            properties (plist-put properties :choices (emacsvox-aural-voice-data--portable-choices rows))))
    (when (plist-get properties :local-choices)
      (let ((id (emacsvox-aural-voice-editing--new-id)))
        (setq properties (plist-put properties :local-choices id)
              sets (list (if layered
                             (list :schema-version 3 :id id :palette palette :voice name :choices rows)
                           (list :id id :palette palette :voice name :selectors (plist-get choices :selectors)))))))
    (when rename
      (setq data (emacsvox-aural-voice-palettes--replace-entries
                  data (cl-remove source (plist-get data :entries) :key #'car))))
    (setq data (emacsvox-aural-voice-palettes--put-entry data (cons name properties)))
    (let* ((draft (emacsvox-aural-voice-drafts--make
                   :key (list 'copy palette name)
                   :watches (emacsvox-aural-voice-drafts--watch (list palette))))
           (proposal (emacsvox-aural-voice-drafts--prepare draft data sets :sources (list palette))))
      (emacsvox-aural-voice-drafts--save proposal)
      (unless (memq 'published (emacsvox-aural-voice-save-completed proposal))
        (user-error "%s did not complete (%s): %s. Retry %s; the original voice is unchanged"
                    (if rename "Rename" "Copy")
                    (plist-get (emacsvox-aural-voice-drafts--status draft) :label)
                    (plist-get (emacsvox-aural-voice-save-result proposal) :message)
                    (if rename "r" "c"))))
    name))

(defun emacsvox-aural-voice-palettes--voice-reference-p (data voice)
  "Whether presentation DATA explicitly refers to VOICE."
  (and (consp data)
       (or (and (memq (car data) '(:voice :preset :personality))
                (eq (cadr data) voice))
           (emacsvox-aural-voice-palettes--voice-reference-p (car data) voice)
           (emacsvox-aural-voice-palettes--voice-reference-p (cdr data) voice))))

(defun emacsvox-aural-voice-palettes--check-voice-rename (palette voice)
  "Reject renaming an inherited, standard or referenced VOICE in PALETTE."
  (let* ((record (emacsvox-aural-voice-palette palette))
         (data (emacsvox-aural-voice-palette-data-form record)))
    (when (emacsvox-aural-voice-palette-built-in record)
      (user-error "Built-in voices cannot be renamed; copy the voice first"))
    (unless (assq voice (plist-get data :entries))
      (user-error "This voice is inherited; copy it first, or rename it in its owning palette"))
    (when (or (assq voice emacsvox-aural-default-voice-entries)
              (rassq voice emacsvox-aural-default-voice-entries)
              (memq voice (bound-and-true-p voice-setup-defined-voices)))
      (user-error "Standard voice %s is used by Emacsvox; copy it under a custom name first" voice))
    (when (and (emacsvox-aural-voice-palette-parent record)
               (assq voice (emacsvox-aural-effective-voice-entries
                            (emacsvox-aural-voice-palette-parent record))))
      (user-error "Renaming this override would reveal its inherited voice; copy it first")))
  (cl-labels ((check (data where)
                (when (emacsvox-aural-voice-palettes--voice-reference-p data voice)
                  (user-error "Voice %s is used by %s; remap that use before renaming" voice where)))
              (faces (table where)
                (when (hash-table-p table)
                  (maphash (lambda (face value)
                             (when (memq voice (if (listp value) value (list value)))
                               (user-error "Voice %s is mapped to face %s in %s; remap it before renaming"
                                           voice face where))) table))))
    (check emacsvox-aural-user-rules "personal rules")
    (check emacsvox-aural-session-rules "session rules")
    (dolist (pair `((,emacsvox-aural-scheme-registry . emacsvox-aural-scheme-entry-data)
                    (,emacsvox-aural-module-fragment-registry . emacsvox-aural-module-fragment-data)
                    (,emacsvox-aural-feature-fragment-registry . emacsvox-aural-feature-fragment-entry-data)
                    (,emacsvox-aural-voice-palette-registry . emacsvox-aural-voice-palette-data-form)))
      (maphash (lambda (id entry) (check (funcall (cdr pair) entry) id)) (car pair)))
    (faces (bound-and-true-p voice-setup-face-voice-table) "the global face map")
    (dolist (buffer (buffer-list))
      (with-current-buffer buffer
        (check emacsvox-aural-buffer-rules (buffer-name))
        (faces (bound-and-true-p voice-setup-local-map) (buffer-name))))
    (when (or (assq voice emacsvox-aural-session-routing-bindings)
              (cl-loop for entry being the hash-values of emacsvox-aural-routing-profile-registry
                       thereis (assq voice (plist-get (emacsvox-aural-routing-profile-entry-data entry) :bindings))))
      (user-error "Voice %s has a shared routing binding; update that binding before renaming" voice))))

(defun emacsvox-aural-voice-palette-previews-rename ()
  "Rename an unused custom voice defined directly in the personal palette."
  (interactive)
  (require 'emacsvox-aural-voice-editor)
  (let* ((palette emacsvox-aural-voice-palette-previews-palette)
         (old (emacsvox-aural-voice-palette-previews--current-voice))
         (_ (emacsvox-aural-voice-palettes--check-voice-rename palette old))
         (drafts (emacsvox-aural-voice-palettes--rename-drafts palette))
         (new (emacsvox-aural-voice-palettes--read-new-entry-name palette (symbol-name old))))
    (emacsvox-aural-voice-palettes--check-voice-rename palette old)
    (setq drafts (emacsvox-aural-voice-palettes--rename-drafts palette))
    (if (emacsvox-aural-voice-runtime--owned-p palette)
        (emacsvox-aural-voice-palettes--copy-owned-voice palette old new t)
      (let* ((data (emacsvox-aural-voice-palette-data-form (emacsvox-aural-voice-palette palette)))
             (entry (assq old (plist-get data :entries))))
        (setcar entry new)
        (emacsvox-aural-voice-palettes--install-data data palette)
        (emacsvox-aural-configuration-changed 'voice-renamed)))
    (dolist (draft drafts)
      (let* ((key (emacsvox-aural-voice-draft-key draft))
             (context (gethash key emacsvox-aural-voice-editor--contexts)))
        (when (and (eq (car key) 'base) (eq (caddr key) old)
                   (or (eq (cadr key) palette) (eq (plist-get context :owner) palette)))
          (let ((renamed (list 'base (cadr key) new)))
            (remhash key emacsvox-aural-voice-drafts--registry)
            (remhash key emacsvox-aural-voice-editor--contexts)
            (setf (emacsvox-aural-voice-draft-key draft) renamed)
            (puthash renamed draft emacsvox-aural-voice-drafts--registry)
            (when context
              (emacsvox-aural-voice-editor--invalidate context)
              (setf (plist-get context :voice) new)
              (puthash renamed context emacsvox-aural-voice-editor--contexts))))
        (setf (emacsvox-aural-voice-draft-proposal draft) nil
              (emacsvox-aural-voice-draft-watches draft)
              (emacsvox-aural-voice-drafts--watch (mapcar #'car (emacsvox-aural-voice-draft-watches draft))))
        (when (and context (buffer-live-p (plist-get context :buffer)))
          (with-current-buffer (plist-get context :buffer)
            (emacsvox-aural-voice-editor-refresh)))))
    (dolist (buffer (buffer-list))
      (with-current-buffer buffer
        (when (and (eq emacsvox-aural-voice-tuner-palette palette)
                   (eq emacsvox-aural-voice-tuner-voice old))
          (setq emacsvox-aural-voice-tuner-voice new)
          (emacsvox-aural-voice-tuner-refresh))))
    (emacsvox-aural-voice-palette-previews-refresh new)
    (emacsvox-aural-ui-announce-result "Renamed voice %s to %s in palette %s" old new palette)
    new))

(defun emacsvox-aural-voice-palette-previews-copy ()
  "Copy the current voice to a new, independently routable voice."
  (interactive)
  (let* ((source-palette
          emacsvox-aural-voice-palette-previews-palette)
         (source-voice
          (emacsvox-aural-voice-palette-previews--current-voice))
         (palette
          (emacsvox-aural-voice-palette-previews--editable-palette))
         (voice
          (emacsvox-aural-voice-palettes--read-new-entry-name
           palette (format "%s-copy" source-voice))))
    (if (emacsvox-aural-voice-runtime--owned-p palette)
        (emacsvox-aural-voice-palettes--copy-owned-voice palette source-voice voice)
      (emacsvox-aural-voice-palettes--install-entry-definition
       palette voice
       (emacsvox-aural-voice-tuner--complete-style
        (or (emacsvox-aural-voice source-voice source-palette)
            (user-error "Unknown voice: %s" source-voice))
        source-palette)))
    (emacsvox-aural-voice-palette-previews-refresh voice)
    voice))

(defun emacsvox-aural-voice-palette-previews-help ()
  "Display and speak voice-palette preview help."
  (interactive)
  (emacsvox-aural-ui-with-help-window
    (princ
     (concat
      "Aural Voice Palette Preview\n\n"
      "Each row is one effective voice, including inherited voices.  Every\n"
      "audition uses the same comparison text so differences are easier to\n"
      "hear.  The voice name is spoken in the voice being auditioned.\n\n"
      "n or down next       p or up previous\n"
      "left/right column    . speak titled cell\n"
      "RET voice details    P preview; A preview every voice\n"
      "T comparison text    S stop preview\n"
      "SPC speak voice      t tune voice\n"
      "e also tunes; s also stops for compatibility\n"
      "c copy voice         N new voice\n"
      "r rename an unused custom voice\n"
      "Copy saves a new voice, including owned choices and individual tuning.\n"
      "E replace definition\n"
      "Tune opens a draft; first save creates an independent personal palette\n"
      "x explain voice\n"
      "g refresh            o palette manager\n"
      "h aural home         q quit\n")))
  (when (fboundp 'emacsvox-speak-help)
    (emacsvox-speak-help)))

(define-derived-mode
    emacsvox-aural-voice-palette-previews-mode
    emacsvox-aural-tabulated-mode
  "Aural-Voice-Preview"
  "Spoken browser for effective voices in one palette."
  (emacsvox-aural-ui-configure-tabulated
   "palette voices"
   #'emacsvox-aural-voice-palette-previews-speak-current
   #'emacsvox-aural-voice-palette-previews-refresh
   nil
   #'emacsvox-aural-voice-palette-previews--remember-current)
  (setq
   tabulated-list-format
   [("Voice" 24 t)
    ("Physical voice" 28 t)
    ("Engine" 16 t)
    ("Adjustments" 48 t)
    ("State" 0 t)])
  (setq tabulated-list-padding 2)
  (add-hook
   'tabulated-list-revert-hook
   #'emacsvox-aural-voice-palette-previews--set-entries nil t)
  (tabulated-list-init-header))

(dolist
    (binding
     '(("RET" . emacsvox-aural-voice-palette-previews-explain)
       ("P" . emacsvox-aural-voice-palette-previews-play)
       ("A" . emacsvox-aural-voice-palette-previews-play-all)
       ("t" . emacsvox-aural-voice-palette-previews-tune)
       ("T" . emacsvox-aural-voice-palette-previews-set-text)
       ("s" . emacsvox-aural-voice-palette-previews-stop)
       ("S" . emacsvox-aural-voice-palette-previews-stop)
       ("e" . emacsvox-aural-voice-palette-previews-tune)
       ("E" . emacsvox-aural-voice-palette-previews-edit)
       ("c" . emacsvox-aural-voice-palette-previews-copy)
       ("r" . emacsvox-aural-voice-palette-previews-rename)
       ("N" . emacsvox-aural-voice-palette-previews-new)
       ("x" . emacsvox-aural-voice-palette-previews-explain)
       ("o" . emacsvox-aural-voice-palette-previews-open-manager)
       ("h" . emacsvox-aural)
       ("?" . emacsvox-aural-voice-palette-previews-help)))
  (define-key
   emacsvox-aural-voice-palette-previews-mode-map
   (kbd (car binding))
   (cdr binding)))

(defun emacsvox-aural-list-voice-palette-previews
    (palette &optional voice speak)
  "Open the spoken effective-voice browser for PALETTE.

VOICE selects the initial row.  When SPEAK is non-nil, announce that row
after displaying the preview buffer."
  (let ((source
         (emacsvox-aural-inspection-remember-source-buffer))
        (entries (emacsvox-aural-voice-palettes--preview-entries palette))
        (buffer (get-buffer-create "*Aural Voice Palette Preview*")))
    (unless entries
      (user-error "Voice palette %s has no effective voices" palette))
    (with-current-buffer buffer
      (unless (and (derived-mode-p 'emacsvox-aural-voice-palette-previews-mode)
                   (eq palette emacsvox-aural-voice-palette-previews-palette))
        (emacsvox-aural-voice-palette-previews-mode)
        (setq emacsvox-aural-voice-palette-previews-text
              emacsvox-aural-voice-palettes-preview-text))
      (emacsvox-aural-inspection-attach-source source)
      (setq
       emacsvox-aural-voice-palette-previews-palette palette
       emacsvox-aural-voice-palette-previews-entries entries)
      (emacsvox-aural-voice-palette-previews-refresh voice))
    (emacsvox-aural-ui-pop-to-buffer buffer)
    (when (and speak (tabulated-list-get-id))
      (emacsvox-aural-voice-palette-previews-speak-current))
    buffer))

(defun emacsvox-aural-voice-palettes-preview (&optional id)
  "Browse and audition all effective voices in palette ID or at point."
  (interactive)
  (let ((id (or id (emacsvox-aural-voice-palettes--at-point-or-read))))
    (emacsvox-aural-list-voice-palette-previews
     id nil (called-interactively-p 'interactive))))

(defun emacsvox-aural-voice-palettes-audition ()
  "Audition the selected palette's effective voices in order."
  (interactive)
  (emacsvox-aural-voice-palettes-preview)
  (emacsvox-aural-voice-palette-previews-play-all))

(defun emacsvox-aural-voice-palettes-explain (&optional id voice)
  "Explain one effective voice and its adapter fallback."
  (interactive)
  (let* ((id (or id (emacsvox-aural-voice-palettes--at-point-or-read)))
         (voice
          (or
           voice
           (emacsvox-aural-voice-palettes--read-voice
            id "Voice to explain: ")))
         (definition (emacsvox-aural-voice voice id))
         (compiled (emacsvox-aural-compile-voice-style voice id))
         (capability (emacsvox-aural-compiled-voice-capability compiled))
         (degradations
          (emacsvox-aural-compiled-voice-degradations compiled))
         (summary
          (format
           "%s in %s. Requested %S. Effective style %S. Adapter %s. %s"
           voice id definition
           (emacsvox-aural-compiled-voice-style compiled)
           (plist-get capability :adapter)
           (if degradations
               (format "%d fallback%s"
                       (length degradations)
                       (if (= (length degradations) 1) "" "s"))
             "No fallback"))))
    (emacsvox-aural-ui-with-help-window
      (princ (format "Voice: %s\nPalette: %s\n\n" voice id))
      (princ (format "Requested preset: %S\n" definition))
      (princ
       (format
        "Effective ACSS: %S\n"
        (emacsvox-aural-compiled-voice-style compiled)))
      (princ
       (format
        "Adapter capability: %S\n"
        capability))
      (princ
       (format
        "Dimension provenance: %S\n"
        (emacsvox-aural-compiled-voice-provenance compiled)))
      (if degradations
          (progn
            (princ "\nFallbacks\n\n")
            (dolist (degradation degradations)
              (princ (format "%S\n" degradation))))
        (princ "\nNo adapter fallback was required.\n")))
    (if (fboundp 'tts-speak)
        (tts-speak summary)
      (message "%s" summary))
    compiled))

(defun emacsvox-aural-voice-palettes-help ()
  "Display and speak voice-palette manager help."
  (interactive)
  (emacsvox-aural-ui-with-help-window
    (princ
     (concat
      "Aural Voice Palettes\n\n"
      "A named voice is a complete preset. A rule may layer explicit ACSS\n"
      "dimensions over that preset. Custom named presets therefore ask for\n"
      "all five dimensions; blank values mean the adapter default.\n\n"
      "n or down next       p or up previous\n"
      "left/right column    . speak titled cell\n"
      "RET browse voices    SPC speak palette\n"
      "a activate override  f use compatibility baseline\n"
      "N create palette     c copy palette\n"
      "r rename personal palette\n"
      "e edit voice         E edit summary and parent\n"
      "D delete voice       d delete palette\n"
      "B browse voices      P audition palette; S stop\n"
      "x explain voice\n"
      "In the voice list, N creates and c copies a voice\n"
      "v view and validate  g refresh\n"
      "h aural home         q quit\n")))
  (when (fboundp 'emacsvox-speak-help)
    (emacsvox-speak-help)))

(define-derived-mode
    emacsvox-aural-voice-palettes-mode
    emacsvox-aural-tabulated-mode
  "Aural-Voice-Palettes"
  "Spoken manager for inherited ACSS voice palettes."
  (emacsvox-aural-ui-configure-tabulated
   "voice palettes"
   #'emacsvox-aural-voice-palettes-speak-current
   #'emacsvox-aural-voice-palettes-refresh
   #'emacsvox-aural-ui-speak-name-and-state)
  (setq
   tabulated-list-format
   [("Palette" 24 t)
    ("Status" 10 t)
    ("Kind" 10 t)
    ("Parent" 20 t)
    ("Direct" 8 t)
    ("Effective" 10 t)
    ("Adapter" 12 t)
    ("Validation" 16 t)
    ("Purpose" 0 t)])
  (setq tabulated-list-padding 2)
  (add-hook
   'tabulated-list-revert-hook
   #'emacsvox-aural-voice-palettes--set-entries nil t)
  (tabulated-list-init-header))

(dolist
    (binding
     '(("RET" . emacsvox-aural-voice-palettes-preview)
       ("B" . emacsvox-aural-voice-palettes-preview)
       ("a" . emacsvox-aural-voice-palettes-activate)
       ("f" . emacsvox-aural-voice-palettes-follow-baseline)
       ("N" . emacsvox-aural-voice-palettes-create)
       ("c" . emacsvox-aural-voice-palettes-copy)
       ("r" . emacsvox-aural-voice-palettes-rename)
       ("e" . emacsvox-aural-voice-palettes-edit-entry)
       ("E" . emacsvox-aural-voice-palettes-edit-metadata)
       ("D" . emacsvox-aural-voice-palettes-delete-entry)
       ("d" . emacsvox-aural-voice-palettes-delete)
       ("P" . emacsvox-aural-voice-palettes-audition)
       ("x" . emacsvox-aural-voice-palettes-explain)
       ("v" . emacsvox-aural-voice-palettes-describe)
       ("h" . emacsvox-aural)
       ("?" . emacsvox-aural-voice-palettes-help)))
  (define-key
   emacsvox-aural-voice-palettes-mode-map
   (kbd (car binding))
   (cdr binding)))

;;;###autoload
(defun emacsvox-aural-list-voice-palettes (&optional palette)
  "Open the spoken manager for voice PALETTE providers."
  (interactive)
  (let ((source
         (emacsvox-aural-inspection-remember-source-buffer))
        (buffer (get-buffer-create "*Aural Voice Palettes*")))
    (with-current-buffer buffer
      (unless (derived-mode-p 'emacsvox-aural-voice-palettes-mode)
        (emacsvox-aural-voice-palettes-mode))
      (emacsvox-aural-inspection-attach-source source)
      (emacsvox-aural-voice-palettes-refresh
       (or palette (tabulated-list-get-id) (emacsvox-aural-voice-palettes--active-id))))
    (emacsvox-aural-ui-pop-to-buffer buffer)
    (when (called-interactively-p 'interactive)
      (emacsvox-aural-voice-palettes-speak-current))
    buffer))

(provide 'emacsvox-aural-voice-palettes)

;;; emacsvox-aural-voice-palettes.el ends here
