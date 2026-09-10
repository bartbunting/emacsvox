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
(declare-function emacsvox-aural-voice-editor-new "emacsvox-aural-voice-editor" (palette voice &optional source text))
(declare-function emacsvox-aural-voice-editor--copy "emacsvox-aural-voice-editor" (palette voice name source text))

(declare-function emacsvox-aural-profile-set-startup-palette "emacsvox-aural-profile-service" (palette &optional new-profile))
(declare-function emacsvox-aural-voice-workbench--selector-realization "emacsvox-aural-voice-workbench" (selector))
(declare-function emacsvox-aural-voice-workbench--selector-description "emacsvox-aural-voice-workbench" (selector))
(defvar emacsvox-aural-voice-workbench-inventory)

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

(defvar-local emacsvox-aural-voice-tuner-route-selector nil
  "Unsaved physical route selector used by this tuner.")

(defvar-local emacsvox-aural-voice-tuner-route-engine nil
  "Discovered engine descriptor used by the tuner route preview.")

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
     "%s active; %d palettes available"
     active count)))

(defun emacsvox-aural-voice-palettes--ids ()
  "Return registered palette identifiers in display order."
  (mapcar #'intern (emacsvox-aural-voice-palette-candidates)))

(defun emacsvox-aural-voice-palettes--kind (palette)
  "Return a display kind for PALETTE."
  (cond
   ((eq (emacsvox-aural-voice-palette-id palette)
        (or (emacsvox-aural-effective-scheme-provider 'voice-palette)
            'acss-default))
    "default")
   ((emacsvox-aural-voice-palette-built-in palette) "built-in")
   (t "personal")))

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
  "Return rooted parent candidates that cannot introduce a cycle with EXCLUDE."
  (cl-remove-if-not
   (lambda (candidate)
     (let ((id (intern candidate)) seen valid)
       (while (and id (not (eq id exclude)) (not (memq id seen)))
         (push id seen)
         (let ((record (emacsvox-aural-voice-palette id)))
           (if (eq id 'acss-default)
               (setq valid (and record (emacsvox-aural-voice-palette-built-in record)) id nil)
             (setq id (and record (emacsvox-aural-voice-palette-parent record))))))
       valid))
   (emacsvox-aural-voice-palette-candidates)))

(defun emacsvox-aural-voice-palettes--read-parent (&optional current exclude)
  "Read a parent palette, offering CURRENT and omitting EXCLUDE."
  (let ((answer
         (completing-read
          "Parent palette: "
          (emacsvox-aural-voice-palettes--parent-candidates exclude)
          nil 'must-match nil nil
          (if current (symbol-name current) "acss-default"))))
    (intern answer)))

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
    (unless (eq name (emacsvox-aural--canonical-voice-name name))
      (user-error "Reserved alias: %s; use %s" name
                  (emacsvox-aural--canonical-voice-name name)))
    (when (emacsvox-aural--generated-voice-name-p name)
      (user-error "Voice name is reserved for generated ACSS: %s" name))
    (when (assq name (emacsvox-aural-effective-voice-entries id))
      (user-error "Voice already exists in palette %s: %s" id name))
    name))



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
           :routing 'owned
           :id id
           :summary summary
           :parent (or parent 'acss-default)
           :entries nil)))
    (emacsvox-aural-voice-palettes--install-data data)
    (emacsvox-aural-voice-palettes-refresh id)
    (emacsvox-aural-voice-palettes-speak-current)
    id))

(defun emacsvox-aural-voice-palettes--copy (source)
  "Copy voice palette SOURCE to a prompted personal palette."
  (require 'emacsvox-aural-voice-editing)
  (let* ((id
          (emacsvox-aural-voice-palettes--read-new-id
           (format "%s-copy" source)))
         (summary (read-string "Copied palette purpose: " (format "Independent copy of %s" source)))
         (entries (emacsvox-aural-voice-data--entries source emacsvox-aural-voice-palette-registry))
         (sources (delete-dups (cons source (mapcar (lambda (item) (plist-get item :palette)) entries))))
         (draft (emacsvox-aural-voice-drafts--make
                 :key (list 'copy-palette source id)
                 :watches (emacsvox-aural-voice-drafts--watch sources)))
         (copy (emacsvox-aural-voice-data--copy-owned
                emacsvox-aural-voice-palette-registry source id summary
                emacsvox-aural-routing--choice-sets
                (mapcar (lambda (item) (cons (car (plist-get item :entry))
                                            (emacsvox-aural-voice-editing--new-id))) entries)))
         (proposal (emacsvox-aural-voice-drafts--prepare
                    draft (plist-get copy :palette) (plist-get copy :choice-sets) :sources sources)))
    (emacsvox-aural-voice-drafts--save proposal)
    (unless (memq 'published (emacsvox-aural-voice-save-completed proposal))
      (user-error "Palette copy did not complete: %s. Retry Copy"
                  (plist-get (emacsvox-aural-voice-save-result proposal) :message)))
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

(defun emacsvox-aural-voice-palettes--edit-entry (id name)
  "Open the complete editor for NAME in ID without saving or selecting it."
  (require 'emacsvox-aural-voice-editor)
  (if (assq name (emacsvox-aural-effective-voice-entries id))
      (emacsvox-aural-voice-editor-open id name (current-buffer))
    (emacsvox-aural-voice-editor-new id name (current-buffer))))

(defun emacsvox-aural-voice-palettes-edit-entry ()
  "Open the complete editor for a voice in the palette at point."
  (interactive)
  (let* ((id (emacsvox-aural-voice-palettes--at-point-or-read))
         (name (emacsvox-aural-voice-palettes--read-entry-name id)))
    (emacsvox-aural-voice-palettes--edit-entry id name)))

(defun emacsvox-aural-voice-palettes--parent-impact (id data)
  "Validate changing ID to DATA and return affected effective voice records."
  (let ((registry (copy-hash-table emacsvox-aural-voice-palette-registry))
        (pending (list id)) affected before impact)
    (while pending
      (let ((next (pop pending)))
        (unless (memq next affected)
          (push next affected)
          (setq pending (append (emacsvox-aural-voice-palettes--dependents next) pending)))))
    (dolist (palette affected)
      (push (cons palette (emacsvox-aural-voice-data--entries palette registry)) before))
    (puthash id (emacsvox-aural-compile-voice-palette-data data) registry)
    (let ((emacsvox-aural-voice-palette-registry registry))
      (dolist (palette affected)
        (let* ((old (alist-get palette before))
               (new (emacsvox-aural-voice-data--entries palette registry))
               (names (delete-dups (mapcar (lambda (item) (car (plist-get item :entry))) (append old new)))))
          (dolist (voice names)
            (let ((from (cl-find voice old :key (lambda (item) (car (plist-get item :entry)))))
                  (to (cl-find voice new :key (lambda (item) (car (plist-get item :entry))))))
              (unless (equal from to)
                (unless to (emacsvox-aural-voice-palettes--check-voice-references voice "changing parent"))
                (push (list :palette palette :voice voice
                            :from (plist-get from :palette) :to (plist-get to :palette)) impact))))))
      (when (memq (emacsvox-aural-effective-voice-palette) affected)
        (emacsvox-aural-voice-runtime--validate-selection)))
    (nreverse impact)))

(defun emacsvox-aural-voice-palettes--discard-clean-drafts (drafts)
  "Discard clean DRAFTS after their effective source entries change."
  (dolist (draft drafts)
    (let* ((key (emacsvox-aural-voice-draft-key draft))
           (context (gethash key emacsvox-aural-voice-editor--contexts)))
      (when context (emacsvox-aural-voice-editor--invalidate context))
      (remhash key emacsvox-aural-voice-drafts--registry)
      (remhash key emacsvox-aural-voice-editor--contexts)
      (when (and context (buffer-live-p (plist-get context :buffer)))
        (kill-buffer (plist-get context :buffer))))))

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
      (unless (member (symbol-name parent) (emacsvox-aural-voice-palettes--parent-candidates id))
        (user-error "Choose a parent whose ancestry ends at acss-default"))
      (if (eq parent (emacsvox-aural-voice-palette-parent palette))
          (emacsvox-aural-voice-palettes--install-data data id)
        (require 'emacsvox-aural-voice-editor)
        (let* ((drafts (emacsvox-aural-voice-palettes--rename-drafts id "changing parent"))
               (impact (emacsvox-aural-voice-palettes--parent-impact id data))
               (sources (delete-dups (append (list id parent) (mapcar (lambda (item) (plist-get item :palette)) impact))))
               (draft (emacsvox-aural-voice-drafts--make
                       :key (list 'parent id) :watches (emacsvox-aural-voice-drafts--watch sources)))
               (proposal (emacsvox-aural-voice-drafts--prepare draft data nil :sources sources)))
          (when impact
            (unless (yes-or-no-p
                     (format "Change parent to %s? Affected voices: %s. " parent
                             (mapconcat (lambda (item)
                                          (format "%s in %s (%s to %s)" (plist-get item :voice)
                                                  (plist-get item :palette) (or (plist-get item :from) "absent")
                                                  (or (plist-get item :to) "absent"))) impact "; ")))
              (user-error "Parent change cancelled")))
          (emacsvox-aural-voice-palettes--rename-drafts id "changing parent")
          (unless (equal impact (emacsvox-aural-voice-palettes--parent-impact id data))
            (user-error "Parent choices changed; review the change again"))
          (emacsvox-aural-voice-drafts--save proposal)
          (unless (memq 'published (emacsvox-aural-voice-save-completed proposal))
            (user-error "Parent change did not complete: %s. Retry Edit palette"
                        (plist-get (emacsvox-aural-voice-save-result proposal) :message)))
          (emacsvox-aural-voice-palettes--discard-clean-drafts drafts)))
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
           (_ (emacsvox-aural-voice-palettes--delete-voice id name)))
      (emacsvox-aural-voice-palettes-refresh id)
      (emacsvox-aural-ui-announce-result "Deleted direct voice %s from palette %s" name id)
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

(defun emacsvox-aural-voice-palettes--rename-drafts (id &optional action)
  "Return clean drafts affected by changing ID, rejecting unfinished saves.
ACTION describes the operation and defaults to renaming."
  (setq action (or action "renaming"))
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
             (user-error "Save or discard voice edits and finish pending saves before %s %s" action id)))
         (push draft drafts)))
     emacsvox-aural-voice-drafts--registry)
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
  (plist-get
   (cl-find name (emacsvox-aural--effective-voice-metadata
                  palette-id emacsvox-aural-voice-palette-registry)
            :key (lambda (item) (car (plist-get item :entry))))
   :palette))

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
        (let* ((opened (emacsvox-aural-voice-editing--snapshot palette name))
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
                              "Saved; palette-owned"))
                        (symbol-name (plist-get opened :owner)))))
      (error (list name (vector (symbol-name name) "Unavailable" "" "" (error-message-string err) "Unavailable"))))))

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

(defun emacsvox-aural-voice-palette-previews--row-summary ()
  "Return the complete spoken description of the voice row at point."
  (let* ((voice
          (emacsvox-aural-voice-palette-previews--current-voice))
         (row
          (or
           (cadr (assq voice tabulated-list-entries))
           (user-error "Unknown voice: %s" voice)))
         (summary
          (format
           "%s. Physical choice %s. Engine %s. Adjustments %s. State %s. Source %s."
           (aref row 0)
           (aref row 1)
           (aref row 2)
           (aref row 3)
           (aref row 4)
           (aref row 5))))
    summary))

(defun emacsvox-aural-voice-palette-previews-speak-current ()
  "Speak the complete palette voice row at point."
  (interactive)
  (let ((summary (emacsvox-aural-voice-palette-previews--row-summary)))
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

(defun emacsvox-aural-voice-palette-previews-edit ()
  "Open the complete voice editor for the effective voice at point."
  (interactive)
  (emacsvox-aural-voice-palette-previews-tune))

(defun emacsvox-aural-voice-tuner--complete-style (definition _palette)
  "Return complete raw DEFINITION fields for the shared voice controls.
Decode terminal personality implementations without re-entering named lookup."
  (let ((source (emacsvox-aural-voice-runtime--definition-style definition)) style)
    (dolist (dimension emacsvox-aural-rich-voice-dimensions)
      (let ((key (emacsvox-aural--voice-dimension-key dimension)))
        (setq style (plist-put style key (plist-get source key)))))
    style))

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

(defun emacsvox-aural-voice-palette-previews-tune ()
  "Open the common voice editor without changing the palette or its selection."
  (interactive)
  (require 'emacsvox-aural-voice-editor)
  (emacsvox-aural-voice-editor-open
   emacsvox-aural-voice-palette-previews-palette
   (emacsvox-aural-voice-palette-previews--current-voice)
   (current-buffer) emacsvox-aural-voice-palette-previews-text))

(defun emacsvox-aural-voice-palette-previews-new ()
  "Draft a new complete voice in the palette shown by the current preview."
  (interactive)
  (require 'emacsvox-aural-voice-editor)
  (let* ((palette emacsvox-aural-voice-palette-previews-palette)
         (voice (emacsvox-aural-voice-palettes--read-new-entry-name palette)))
    (emacsvox-aural-voice-editor-new
     palette voice (current-buffer) emacsvox-aural-voice-palette-previews-text)
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
                             emacsvox-aural-routing--choice-sets)))
         (rows (plist-get choices :choices))
         sets)
    (when (emacsvox-aural-voice-palette-built-in record)
      (user-error "Copy the built-in palette first"))
    (unless item (user-error "Unknown voice: %s" source))
    (when (cl-find name entries :key (lambda (entry) (car (plist-get entry :entry))))
      (user-error "Voice already exists in palette %s: %s" palette name))
    (when (plist-get choices :diagnostics)
      (user-error "Cannot copy %s: its saved local voice choices are missing" source))
    (setq properties (plist-put properties :choices (emacsvox-aural-voice-data--portable-choices rows)))
    (when (plist-get properties :local-choices)
      (let ((id (emacsvox-aural-voice-editing--new-id)))
        (setq properties (plist-put properties :local-choices id)
              sets (list (list :schema-version 3 :id id :palette palette :voice name :choices rows)))))
    (when rename
      (setq data (emacsvox-aural-voice-palettes--replace-entries
                  data (cl-remove source (plist-get data :entries) :key #'car))))
    (setq data (emacsvox-aural-voice-palettes--put-entry data (cons name properties)))
    (let* ((draft (emacsvox-aural-voice-drafts--make
                   :key (list 'copy palette name)
                   :watches (emacsvox-aural-voice-drafts--watch (list palette))))
           (proposal (emacsvox-aural-voice-drafts--prepare
                      draft data sets :sources (list palette)
                      :user-rules-transform
                      (when rename
                        ;; Validate the complete renamed state, before either write.
                        (lambda (rules)
                          (emacsvox-aural-voice-palettes--rename-references rules source name))))))
      (emacsvox-aural-voice-drafts--save proposal)
      (unless (memq 'published (emacsvox-aural-voice-save-completed proposal))
        (user-error "%s did not complete (%s): %s. Retry %s; the original voice is unchanged"
                    (if rename "Rename" "Copy")
                    (plist-get (emacsvox-aural-voice-drafts--status draft) :label)
                    (plist-get (emacsvox-aural-voice-save-result proposal) :message)
                    (if rename "r" "c"))))
    name))

(defun emacsvox-aural-voice-palettes--rename-voice-value (value old new)
  "Copy a logical voice VALUE, replacing OLD with NEW in composites and presets."
  (cond
   ((eq value old) new)
   ((and (consp value) (keywordp (car value)))
    (let ((result (copy-tree value)))
      (when (plist-member result :preset)
        (setq result (plist-put result :preset
                                (emacsvox-aural-voice-palettes--rename-voice-value
                                 (plist-get result :preset) old new))))
      result))
   ((and (consp value) (proper-list-p value))
    (mapcar (lambda (part) (emacsvox-aural-voice-palettes--rename-voice-value part old new)) value))
   (t value)))

(defun emacsvox-aural-voice-palettes--voice-reference-p (data voice)
  "Whether presentation DATA explicitly refers to VOICE."
  (and (consp data)
       (or (and (memq (car data) '(:voice :preset))
                (not (equal (cadr data) (emacsvox-aural-voice-palettes--rename-voice-value
                                        (cadr data) voice (make-symbol "replacement")))))
           (emacsvox-aural-voice-palettes--voice-reference-p (car data) voice)
           (emacsvox-aural-voice-palettes--voice-reference-p (cdr data) voice))))

(defun emacsvox-aural-voice-palettes--rename-references (data old new)
  "Copy presentation DATA, replacing explicit voice references from OLD to NEW."
  (if (not (consp data)) data
    (if (memq (car data) '(:voice :preset))
        (cons (car data)
              (cons (emacsvox-aural-voice-palettes--rename-voice-value (cadr data) old new)
                    (emacsvox-aural-voice-palettes--rename-references (cddr data) old new)))
      (cons (emacsvox-aural-voice-palettes--rename-references (car data) old new)
            (emacsvox-aural-voice-palettes--rename-references (cdr data) old new)))))

(defun emacsvox-aural-voice-palettes--rename-face-map (table old new)
  "Update live face TABLE values referring to OLD to use NEW."
  (when (hash-table-p table)
    (maphash (lambda (face value)
               (puthash face (emacsvox-aural-voice-palettes--rename-voice-value value old new) table))
             table)))

(defun emacsvox-aural-voice-palettes--check-voice-rename (palette voice)
  "Reject renaming an inherited, standard or externally referenced VOICE in PALETTE."
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
  (emacsvox-aural-voice-palettes--check-voice-references voice "renaming" t))

(defun emacsvox-aural-voice-palettes--check-voice-references (voice action &optional remap)
  "Reject ACTION when registered mappings or presets still use VOICE.
When REMAP is non-nil, allow personal rules and live face mappings to migrate."
  (cl-labels ((check (data where)
                (when (emacsvox-aural-voice-palettes--voice-reference-p data voice)
                  (user-error "Voice %s is used by %s; remap that use before %s" voice where action)))
              (faces (table where)
                (when (hash-table-p table)
                  (maphash (lambda (face value)
                             (when (emacsvox-aural-voice-palettes--voice-reference-p (list :voice value) voice)
                               (user-error "Voice %s is mapped to face %s in %s; remap it before %s"
                                           voice face where action))) table))))
    (unless remap
      (check emacsvox-aural-user-rules "personal rules")
      (check emacsvox-aural-session-rules "session rules"))
    (dolist (pair `((,emacsvox-aural-scheme-registry . emacsvox-aural-scheme-entry-data)
                    (,emacsvox-aural-module-fragment-registry . emacsvox-aural-module-fragment-data)
                    (,emacsvox-aural-feature-fragment-registry . emacsvox-aural-feature-fragment-entry-data)
                    (,emacsvox-aural-voice-palette-registry . emacsvox-aural-voice-palette-data-form)))
      (maphash (lambda (id entry) (check (funcall (cdr pair) entry) id)) (car pair)))
    (unless remap
      (faces (bound-and-true-p voice-setup-face-voice-table) "the global face map")
      (dolist (buffer (buffer-list))
        (with-current-buffer buffer
          (check emacsvox-aural-buffer-rules (buffer-name))
          (faces (bound-and-true-p voice-setup-local-map) (buffer-name)))))))

(defun emacsvox-aural-voice-palettes--delete-voice (palette voice &optional reset)
  "Remove direct VOICE from PALETTE after confirmation.
RESET requires an inherited replacement; deletion requires that there is none."
  (require 'emacsvox-aural-voice-editor)
  (let* ((record (emacsvox-aural-voice-palette palette))
         (data (emacsvox-aural-voice-palette-data-form record))
         (parent (emacsvox-aural-voice-palette-parent record))
         (fallback (and parent (assq voice (emacsvox-aural-effective-voice-entries parent))))
         drafts)
    (when (emacsvox-aural-voice-palette-built-in record)
      (user-error "Built-in voices cannot be deleted"))
    (unless (assq voice (plist-get data :entries))
      (user-error "This voice is already inherited; edit it here to make a personal entry"))
    (when (and fallback (not reset))
      (user-error "Use R to reset %s to its inherited voice" voice))
    (when (and reset (not fallback))
      (user-error "No parent supplies %s; use Delete to remove this custom voice" voice))
    (unless fallback (emacsvox-aural-voice-palettes--check-voice-references voice "deleting"))
    (setq drafts (emacsvox-aural-voice-palettes--rename-drafts palette "deleting"))
    (unless (yes-or-no-p
             (if reset
                 (format "Reset %s in %s and restore its inherited voice from %s? " voice palette parent)
               (format "Delete custom voice %s from palette %s? " voice palette)))
      (user-error "%s cancelled" (if reset "Reset" "Deletion")))
    (unless (eq record (emacsvox-aural-voice-palette palette))
      (user-error "Palette changed while confirming deletion; try again"))
    (unless fallback (emacsvox-aural-voice-palettes--check-voice-references voice "deleting"))
    (setq drafts (emacsvox-aural-voice-palettes--rename-drafts palette "deleting"))
    (emacsvox-aural-voice-palettes--install-data
     (emacsvox-aural-voice-palettes--replace-entries
      data (cl-remove voice (plist-get data :entries) :key #'car)) palette)
    ;; Discard only clean editor state, so saving an old view cannot recreate it.
    (dolist (draft drafts)
      (let* ((key (emacsvox-aural-voice-draft-key draft))
             (context (gethash key emacsvox-aural-voice-editor--contexts)))
        (if (and (eq (car key) 'base) (eq (caddr key) voice)
                 (or (eq (cadr key) palette) (eq (plist-get context :owner) palette)))
            (progn
              (when context (emacsvox-aural-voice-editor--invalidate context))
              (remhash key emacsvox-aural-voice-drafts--registry)
              (remhash key emacsvox-aural-voice-editor--contexts)
              (when (and context (buffer-live-p (plist-get context :buffer)))
                (kill-buffer (plist-get context :buffer))))
          (setf (emacsvox-aural-voice-draft-proposal draft) nil
                (emacsvox-aural-voice-draft-watches draft)
                (emacsvox-aural-voice-drafts--watch (mapcar #'car (emacsvox-aural-voice-draft-watches draft)))))))
    (dolist (buffer (buffer-list))
      (with-current-buffer buffer
        (when (eq emacsvox-aural-voice-palette-previews-palette palette)
          (emacsvox-aural-voice-palette-previews-refresh))))
    (emacsvox-aural-configuration-changed 'voice-deleted)
    voice))

(defun emacsvox-aural-voice-palette-previews-reset ()
  "Reset the direct voice at point to its parent's complete entry."
  (interactive)
  (let ((palette emacsvox-aural-voice-palette-previews-palette)
        (voice (emacsvox-aural-voice-palette-previews--current-voice)))
    (emacsvox-aural-voice-palettes--delete-voice palette voice t)
    (emacsvox-aural-voice-palette-previews-refresh voice)
    (emacsvox-aural-ui-announce-result "Reset %s in %s. The inherited voice remains selected" voice palette)
    voice))

(defun emacsvox-aural-voice-palettes-reset-entry ()
  "Choose a direct voice to reset to its parent's complete entry."
  (interactive)
  (let* ((palette (emacsvox-aural-voice-palettes--at-point-or-read))
         (record (emacsvox-aural-voice-palette palette))
         (parent (emacsvox-aural-voice-palette-parent record))
         (inherited (and parent (emacsvox-aural-effective-voice-entries parent)))
         (names (cl-loop for entry in (plist-get (emacsvox-aural-voice-palette-data-form record) :entries)
                         when (assq (car entry) inherited) collect (symbol-name (car entry)))))
    (unless names (user-error "This palette has no personal entries to reset"))
    (let ((voice (intern (completing-read "Reset voice to parent: " names nil t))))
      (emacsvox-aural-voice-palettes--delete-voice palette voice t)
      (emacsvox-aural-voice-palettes-refresh palette)
      (emacsvox-aural-ui-announce-result "Reset %s in %s to its inherited voice" voice palette))))

(defun emacsvox-aural-voice-palette-previews-delete ()
  "Confirm deletion of the current personal voice and select a remaining row."
  (interactive)
  (let* ((palette emacsvox-aural-voice-palette-previews-palette)
         (voice (emacsvox-aural-voice-palette-previews--current-voice))
         (names (mapcar #'car emacsvox-aural-voice-palette-previews-entries))
         (index (cl-position voice names))
         (neighbor (or (nth (1+ index) names) (and (> index 0) (nth (1- index) names)))))
    (emacsvox-aural-voice-palettes--delete-voice palette voice)
    (emacsvox-aural-voice-palette-previews-refresh
     (if (assq voice emacsvox-aural-voice-palette-previews-entries) voice neighbor))
    (emacsvox-aural-ui-announce-result
     "Deleted direct voice %s from palette %s. %s" voice palette
     (if (tabulated-list-get-id) (format "Selected %s" (tabulated-list-get-id))
       "No voices remain. o returns to the palette manager"))
    voice))

(defun emacsvox-aural-voice-palette-previews-rename ()
  "Rename a personal custom voice and update its personal and live face mappings."
  (interactive)
  (require 'emacsvox-aural-voice-editor)
  (let* ((palette emacsvox-aural-voice-palette-previews-palette)
         (old (emacsvox-aural-voice-palette-previews--current-voice))
         (_ (emacsvox-aural-voice-palettes--check-voice-rename palette old))
         (drafts (emacsvox-aural-voice-palettes--rename-drafts palette))
         (new (emacsvox-aural-voice-palettes--read-new-entry-name palette (symbol-name old))))
    (emacsvox-aural-voice-palettes--check-voice-rename palette old)
    (maphash
     (lambda (id record)
       (unless (eq id palette)
         (let ((entries (plist-get (emacsvox-aural-voice-palette-data-form record) :entries)))
           (when (or (assq old entries) (assq new entries))
             (user-error "Voice %s or %s is also defined in palette %s; shared mappings cannot be renamed safely"
                         old new id)))))
     emacsvox-aural-voice-palette-registry)
    (setq drafts (emacsvox-aural-voice-palettes--rename-drafts palette))
    (let* ((rules (emacsvox-aural-voice-palettes--rename-references
                   emacsvox-aural-user-rules old new))
           (emacsvox-aural-configuration-changed-hook nil))
      (let ((emacsvox-aural-user-rules rules))
        (if (emacsvox-aural-voice-runtime--owned-p palette)
            (emacsvox-aural-voice-palettes--copy-owned-voice palette old new t)
          (let* ((data (emacsvox-aural-voice-palette-data-form (emacsvox-aural-voice-palette palette)))
                 (entry (assq old (plist-get data :entries))))
            (setcar entry new)
            (emacsvox-aural-voice-palettes--install-data data palette))))
      ;; Publish mappings only after persistence succeeds.
      (setq emacsvox-aural-user-rules rules
            emacsvox-aural-session-rules
            (emacsvox-aural-voice-palettes--rename-references emacsvox-aural-session-rules old new))
      (emacsvox-aural-voice-palettes--rename-face-map
       (bound-and-true-p voice-setup-face-voice-table) old new)
      (dolist (buffer (buffer-list))
        (with-current-buffer buffer
          (when (local-variable-p 'emacsvox-aural-buffer-rules)
            (setq emacsvox-aural-buffer-rules
                  (emacsvox-aural-voice-palettes--rename-references emacsvox-aural-buffer-rules old new)))
          (emacsvox-aural-voice-palettes--rename-face-map
           (bound-and-true-p voice-setup-local-map) old new))))
    (emacsvox-aural-configuration-changed 'voice-renamed)
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
    (emacsvox-aural-voice-palette-previews-refresh new)
    (emacsvox-aural-ui-announce-result "Renamed voice %s to %s in palette %s" old new palette)
    new))

(defun emacsvox-aural-voice-palette-previews-copy ()
  "Copy the complete voice at point under a new name.
A built-in voice opens a personal draft; save it to create a personal child."
  (interactive)
  (require 'emacsvox-aural-voice-editor)
  (let* ((palette emacsvox-aural-voice-palette-previews-palette)
         (source (emacsvox-aural-voice-palette-previews--current-voice))
         (voice (emacsvox-aural-voice-palettes--read-new-entry-name
                 palette (format "%s-copy" source))))
    (if (emacsvox-aural-voice-palette-built-in (emacsvox-aural-voice-palette palette))
        (emacsvox-aural-voice-editor--copy
         palette source voice (current-buffer) emacsvox-aural-voice-palette-previews-text)
      (emacsvox-aural-voice-palettes--copy-owned-voice palette source voice)
      (emacsvox-aural-voice-palette-previews-refresh voice))
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
      "r rename a custom voice and its mappings\n"
      "R reset to parent    d delete custom voice, with confirmation\n"
      "Copy saves a new voice, including owned choices and individual tuning.\n"
      "E also opens the complete voice editor\n"
      "Editing a built-in voice opens a draft; saving creates a personal child\n"
      "x explain voice; u known uses and descendants\n"
      "O open source        g refresh; o palette manager\n"
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
    ("State" 24 t)
    ("Source" 0 t)])
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
       ("R" . emacsvox-aural-voice-palette-previews-reset)
       ("d" . emacsvox-aural-voice-palette-previews-delete)
       ("N" . emacsvox-aural-voice-palette-previews-new)
       ("x" . emacsvox-aural-voice-palette-previews-explain)
       ("o" . emacsvox-aural-voice-palette-previews-open-manager)
       ("O" . emacsvox-aural-voice-palette-previews-open-source)
       ("u" . emacsvox-aural-voice-palettes-where-used)
       ("h" . emacsvox-aural)
       ("?" . emacsvox-aural-voice-palette-previews-help)))
  (define-key
   emacsvox-aural-voice-palette-previews-mode-map
   (kbd (car binding))
   (cdr binding)))

(defun emacsvox-aural-list-voice-palette-previews
    (palette &optional voice speak)
  "Open the spoken effective-voice browser for PALETTE.

VOICE selects the initial row.  Announce the palette and navigation keys.
When SPEAK is non-nil, include the selected row's full description."
  (let ((source
         (emacsvox-aural-inspection-remember-source-buffer))
        (entries (emacsvox-aural-voice-palettes--preview-entries palette))
        (buffer (get-buffer-create "*Aural Voice Palette Preview*")))
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
    (emacsvox-aural-ui--pop-to-buffer
     buffer (lambda ()
              (emacsvox-aural-ui-speak
               (format "Voice palette %s. %d voices. %s" palette (length entries)
                       (if (tabulated-list-get-id)
                           (concat (if speak (emacsvox-aural-voice-palette-previews--row-summary)
                                     (format "Selected %s." (tabulated-list-get-id)))
                                   " t tunes, c copies, r renames, d deletes. Question mark for help.")
                         "No voices. o returns to the palette manager.")))))
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
      (princ (format "Source: %s\n" (emacsvox-aural-voice-palettes--entry-provider voice id)))
      (princ "Use u in the voice list for known uses and aliases; O opens the source; e edits here.\n\n")
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

(defvar emacsvox-aural-voice-palettes--import-pending nil
  "Frozen import awaiting an explicit retry or discard.")

(defun emacsvox-aural-voice-palettes--known-uses (voice)
  "Return known loaded references to VOICE and its declared aliases."
  (let ((names (cons voice (mapcar #'cdr (cl-remove-if-not
                                        (lambda (pair) (eq (car pair) voice))
                                        emacsvox-aural-default-voice-entries)))) uses)
    (cl-labels ((check (data where)
                  (when (cl-some (lambda (name) (emacsvox-aural-voice-palettes--voice-reference-p data name)) names)
                    (push where uses)))
                (faces (table where)
                  (when (hash-table-p table)
                    (maphash (lambda (face value) (check (list :voice value) (format "%s: face %s" where face))) table))))
      (check emacsvox-aural-user-rules "Personal rules")
      (check emacsvox-aural-session-rules "Session rules")
      (dolist (pair `((,emacsvox-aural-scheme-registry emacsvox-aural-scheme-entry-data "Scheme")
                      (,emacsvox-aural-module-fragment-registry emacsvox-aural-module-fragment-data "Module")
                      (,emacsvox-aural-feature-fragment-registry emacsvox-aural-feature-fragment-entry-data "Feature")
                      (,emacsvox-aural-voice-palette-registry emacsvox-aural-voice-palette-data-form "Palette")))
        (maphash (lambda (id entry) (check (funcall (cadr pair) entry) (format "%s %s" (nth 2 pair) id))) (car pair)))
      (faces (bound-and-true-p voice-setup-face-voice-table) "Global")
      (dolist (buffer (buffer-list))
        (with-current-buffer buffer
          (check emacsvox-aural-buffer-rules (format "Buffer %s: rules" (buffer-name)))
          (faces (bound-and-true-p voice-setup-local-map) (format "Buffer %s" (buffer-name))))))
    (sort (delete-dups uses) #'string-lessp)))

(defun emacsvox-aural-voice-palettes--descendants (palette)
  "Return all descendants of PALETTE without repeating cycles."
  (let ((pending (emacsvox-aural-voice-palettes--dependents palette)) (seen (list palette)) result)
    (while pending
      (let ((id (pop pending)))
        (unless (memq id seen)
          (push id seen) (push id result)
          (setq pending (append (emacsvox-aural-voice-palettes--dependents id) pending)))))
    (sort result (lambda (a b) (string-lessp (symbol-name a) (symbol-name b))))))

(defun emacsvox-aural-voice-palettes--edit-impact (palette voice)
  "Return descendants whose VOICE would change when edited in PALETTE."
  (when-let* ((owner (and (emacsvox-aural-voice-palette palette)
                         (emacsvox-aural-voice-palettes--entry-provider voice palette))))
    (cl-remove-if-not (lambda (id) (eq owner (emacsvox-aural-voice-palettes--entry-provider voice id)))
                      (emacsvox-aural-voice-palettes--descendants palette))))

(defun emacsvox-aural-voice-palettes--confirm-edit-impact (palette voice)
  "Review shared effects before saving VOICE in PALETTE."
  (when-let* ((affected (emacsvox-aural-voice-palettes--edit-impact palette voice)))
    (let ((uses (emacsvox-aural-voice-palettes--known-uses voice)))
      (unless (yes-or-no-p
               (format "Saving %s in %s also changes it in %s. Known loaded uses: %s. Save? "
                       voice palette (mapconcat #'symbol-name affected ", ")
                       (if uses (string-join uses "; ") "none")))
        (user-error "Save cancelled; the voice draft is retained")))))
(defun emacsvox-aural-voice-palettes-where-used (&optional palette voice)
  "Show known uses and descendants of PALETTE, or its selected VOICE."
  (interactive)
  (let* ((voices (derived-mode-p 'emacsvox-aural-voice-palette-previews-mode))
         (palette (or palette (if voices emacsvox-aural-voice-palette-previews-palette
                                (emacsvox-aural-voice-palettes--at-point-or-read))))
         (voice (or voice (and voices (emacsvox-aural-voice-palette-previews--current-voice))))
         (owner (and voice (emacsvox-aural-voice-palettes--entry-provider voice palette)))
         (uses (if voice (emacsvox-aural-voice-palettes--known-uses voice)
                 (emacsvox-aural-voice-palettes--references palette)))
         (descendants (emacsvox-aural-voice-palettes--descendants palette)))
    (emacsvox-aural-ui-with-help-window
      (princ (format "%s%s\n" palette (if voice (format ": %s; source %s" voice owner) "")))
      (when voice
        (princ (format "Declared aliases: %s\n"
                       (or (mapcar #'cdr (cl-remove-if-not (lambda (pair) (eq (car pair) voice))
                                                          emacsvox-aural-default-voice-entries)) "none")))
        (princ "Edit here creates or updates this palette's entry. Open Source visits its defining palette.\n"))
      (princ (format "\nDescendant palettes: %s\n" (or descendants "none")))
      (princ "\nKnown loaded references\n")
      (if uses (dolist (use uses) (princ (concat use "\n"))) (princ "None found.\n")))
    (emacsvox-aural-ui-speak (format "%s. %d known references; %d descendant palettes."
                                    (or voice palette) (length uses) (length descendants)))))

(defun emacsvox-aural-voice-palette-previews-open-source ()
  "Browse the defining palette of the selected voice."
  (interactive)
  (let* ((voice (emacsvox-aural-voice-palette-previews--current-voice))
         (owner (emacsvox-aural-voice-palettes--entry-provider voice emacsvox-aural-voice-palette-previews-palette)))
    (emacsvox-aural-list-voice-palette-previews owner)
    (emacsvox-aural-voice-palette-previews-refresh voice)
    (emacsvox-aural-voice-palette-previews-speak-current)))

(defun emacsvox-aural-voice-palettes-use-at-startup ()
  "Use the selected palette in the saved startup profile without applying it."
  (interactive)
  (require 'emacsvox-aural-profile-service)
  (let ((palette (emacsvox-aural-voice-palettes--at-point-or-read)) new-profile)
    (unless (emacsvox-aural-current-profile-id)
      (let* ((name (read-string "New startup profile name: "))
             (id (intern name)))
        (emacsvox-aural--validate-id id "Startup profile")
        (when (or (string-empty-p name) (emacsvox-aural-profile-entry id))
          (user-error "Choose an unused profile name"))
        (setq new-profile (emacsvox-aural-capture-profile-data id (format "Startup setup %s" id)))
        (unless (yes-or-no-p
                 (format "Create startup profile %s with palette %s, sound pack %s, features %S and spatial settings %S? "
                         id palette (plist-get new-profile :sound-pack)
                         (plist-get new-profile :feature-fragments) (plist-get new-profile :spatial)))
          (user-error "Startup choice cancelled"))))
    (let ((profile (emacsvox-aural-profile-set-startup-palette palette new-profile)))
      (emacsvox-aural-ui-refresh-home-if-live)
      (emacsvox-aural-ui-speak
       (format "Startup profile %s now uses %s. Current voices and other settings are unchanged." profile palette))
      profile)))

(defun emacsvox-aural-voice-palettes--write-exchange (data file)
  "Write inert exchange DATA atomically to FILE after explicit overwrite choice."
  (let* ((file (expand-file-name file))
         (before (emacsvox-aural-voice-drafts--file-id file)) temporary)
    (when (and before (not (yes-or-no-p (format "Replace export file %s? " file))))
      (user-error "Export cancelled"))
    (unless (equal before (emacsvox-aural-voice-drafts--file-id file))
      (user-error "Export destination changed; retry"))
    (setq temporary (make-temp-file (expand-file-name ".voice-palette-" (file-name-directory file))))
    (unwind-protect
        (progn
          (with-temp-buffer
            (insert ";;; Voice palette data; read without evaluation.\n")
            (let ((print-length nil) (print-level nil)) (pp data (current-buffer)))
            (write-region (point-min) (point-max) temporary nil 'silent))
          (set-file-modes temporary #o600)
          (unless (equal before (emacsvox-aural-voice-drafts--file-id file))
            (user-error "Export destination changed; retry"))
          (rename-file temporary file t)
          (setq temporary nil))
      (when temporary (delete-file temporary)))
    file))

(defun emacsvox-aural-voice-palettes-export ()
  "Export effective portable voices, explicitly omitting local physical choices."
  (interactive)
  (let* ((palette (emacsvox-aural-voice-palettes--at-point-or-read))
         (export (emacsvox-aural-voice-data--export-effective emacsvox-aural-voice-palette-registry palette))
         (omitted (plist-get export :omitted-local-choices))
         (file (read-file-name "Portable palette export: " nil nil nil (format "%s-portable.el" palette))))
    (when (and omitted (not (yes-or-no-p
                            (format "Export portable choices only? Local choices for %s will be omitted; use Full Backup to preserve them. "
                                    (mapconcat #'symbol-name omitted ", ")))))
      (user-error "Portable export cancelled"))
    (emacsvox-aural-voice-palettes--write-exchange (plist-get export :palette) file)
    (emacsvox-aural-ui-speak (format "Exported %s. Local choices omitted for %d voices." file (length omitted)))))

(defun emacsvox-aural-voice-palettes-backup ()
  "Back up complete palette ancestry and exact local choices for this machine."
  (interactive)
  (let* ((palette (emacsvox-aural-voice-palettes--at-point-or-read))
         (data (emacsvox-aural-voice-data--backup emacsvox-aural-voice-palette-registry palette emacsvox-aural-routing--choice-sets))
         (file (read-file-name "Full local palette backup: " nil nil nil (format "%s-backup.el" palette))))
    (emacsvox-aural-voice-palettes--write-exchange data file)
    (emacsvox-aural-ui-speak (format "Backed up %s with ancestry and local choices. Import restores an independent palette." palette))))

(defun emacsvox-aural-voice-palettes--import-gaps (data sets)
  "Describe DATA's choices absent from current inventory, resolving local SETS."
  (require 'emacsvox-aural-voice-workbench)
  (let ((emacsvox-aural-voice-workbench-inventory (tts-voice-inventory)) gaps)
    (dolist (entry (plist-get data :entries))
      (dolist (selector (plist-get (emacsvox-aural-voice-data--choices
                                   (plist-get data :id) (car entry) (cdr entry) sets) :selectors))
        (unless (emacsvox-aural-voice-workbench--selector-realization selector)
          (push (format "%s: %s" (car entry) (emacsvox-aural-voice-workbench--selector-description selector)) gaps))))
    (nreverse gaps)))

(defun emacsvox-aural-voice-palettes--finish-import ()
  "Save or retry the frozen pending import without activation."
  (let* ((proposal emacsvox-aural-voice-palettes--import-pending)
         (id (plist-get (emacsvox-aural-voice-save-palette proposal) :id)))
    (emacsvox-aural-voice-drafts--save proposal)
    (unless (memq 'published (emacsvox-aural-voice-save-completed proposal))
      (user-error "Import %s is %s. Press i to retry or discard the frozen import"
                  id (emacsvox-aural-voice-save-state proposal)))
    (setq emacsvox-aural-voice-palettes--import-pending nil)
    (emacsvox-aural-voice-palettes-refresh id)
    (emacsvox-aural-ui-speak (format "Imported %s as an independent palette. Current voices are unchanged." id))
    id))

(defun emacsvox-aural-voice-palettes-import ()
  "Import a portable palette or full backup as an independent saved palette."
  (interactive)
  (when emacsvox-aural-voice-palettes--import-pending
    (when (equal (completing-read "Pending import: " '("Retry" "Discard") nil t nil nil "Retry") "Discard")
      (emacsvox-aural-voice-drafts--discard (emacsvox-aural-voice-save-draft emacsvox-aural-voice-palettes--import-pending))
      (setq emacsvox-aural-voice-palettes--import-pending nil)
      (user-error "Pending import discarded; press i to choose another file")))
  (unless emacsvox-aural-voice-palettes--import-pending
    (let* ((file (read-file-name "Import portable palette or full backup: " nil nil t))
           (fingerprint (emacsvox-aural-voice-drafts--file-id file))
           (inputs (emacsvox-aural-voice-data--read-exchange
                    (emacsvox-aural-routing--read-one-form file "palette exchange")
                    (emacsvox-aural-voice-palette 'acss-default)))
           (source (plist-get inputs :source))
           (registry (plist-get inputs :registry))
           (id (emacsvox-aural-voice-palettes--read-new-id
                (if (gethash source emacsvox-aural-voice-palette-registry) (format "%s-imported" source) (symbol-name source))))
           (entries (emacsvox-aural-voice-data--entries source registry))
           (data (emacsvox-aural-voice-data--materialize
                  registry source id (emacsvox-aural-voice-palette-summary (gethash source registry))
                  (plist-get inputs :choice-sets)
                  (mapcar (lambda (item) (cons (car (plist-get item :entry)) (emacsvox-aural-voice-editing--new-id))) entries)))
           (palette (plist-get data :palette))
           (sets (plist-get data :choice-sets))
           (gaps (emacsvox-aural-voice-palettes--import-gaps palette sets))
           (draft (emacsvox-aural-voice-drafts--make :key (list 'import id)
                   :watches (emacsvox-aural-voice-drafts--watch '(acss-default)))))
      (let ((emacsvox-aural-voice-palette-registry (copy-hash-table emacsvox-aural-voice-palette-registry)))
        (puthash id (emacsvox-aural-compile-voice-palette-data palette) emacsvox-aural-voice-palette-registry)
        (when-let* ((missing (emacsvox-aural-validate-voice-palette id)))
          (user-error "Import has unavailable personality definitions: %s" missing)))
      (when gaps
        (emacsvox-aural-ui-with-help-window
          (princ "Choices absent from the current inventory; saved choices will be retained.\n\n")
          (dolist (gap gaps) (princ (concat gap "\n")))))
      (unless (yes-or-no-p (format "Import %s as independent palette %s with %d voices and %d choices absent from current inventory? "
                                   source id (length (plist-get palette :entries)) (length gaps)))
        (user-error "Import cancelled"))
      (unless (equal fingerprint (emacsvox-aural-voice-drafts--file-id file))
        (user-error "Import file changed during review; retry"))
      (when (emacsvox-aural-voice-palette id)
        (user-error "Palette %s was created during review; choose another name" id))
      (setq emacsvox-aural-voice-palettes--import-pending
            (emacsvox-aural-voice-drafts--prepare draft palette sets :sources '(acss-default)))))
  (emacsvox-aural-voice-palettes--finish-import))

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
      "a activate for this session; U use at startup\n"
      "f switch to default palette\n"
      "w portable export    W full local backup; i import independently\n"
      "After an incomplete import, i offers Retry or Discard\n"
      "N create palette     c copy palette\n"
      "r rename personal palette\n"
      "e edit voice         E edit summary and parent\n"
      "R reset voice to parent; D delete custom voice; d delete palette\n"
      "B browse voices      P audition palette; S stop\n"
      "x explain voice; u known uses and descendants\n"
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
   #'emacsvox-aural-voice-palettes-refresh)
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
       ("U" . emacsvox-aural-voice-palettes-use-at-startup)
       ("u" . emacsvox-aural-voice-palettes-where-used)
       ("w" . emacsvox-aural-voice-palettes-export)
       ("W" . emacsvox-aural-voice-palettes-backup)
       ("i" . emacsvox-aural-voice-palettes-import)
       ("f" . emacsvox-aural-voice-palettes-follow-baseline)
       ("N" . emacsvox-aural-voice-palettes-create)
       ("c" . emacsvox-aural-voice-palettes-copy)
       ("r" . emacsvox-aural-voice-palettes-rename)
       ("e" . emacsvox-aural-voice-palettes-edit-entry)
       ("E" . emacsvox-aural-voice-palettes-edit-metadata)
       ("D" . emacsvox-aural-voice-palettes-delete-entry)
       ("R" . emacsvox-aural-voice-palettes-reset-entry)
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
    (emacsvox-aural-ui--pop-to-buffer
     buffer (lambda ()
              (emacsvox-aural-ui-speak
               (format "Voice palettes. %d palettes. Selected %s. Return browses voices; a activates. Question mark for help."
                       (length tabulated-list-entries) (or (tabulated-list-get-id) "none")))))
    buffer))

(provide 'emacsvox-aural-voice-palettes)

;;; emacsvox-aural-voice-palettes.el ends here
