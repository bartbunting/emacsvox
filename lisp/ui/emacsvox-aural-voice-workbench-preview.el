;;; emacsvox-aural-voice-workbench-preview.el --- Voice workbench preview and comparison -*- lexical-binding: t; -*-

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
;; Voice workbench preview and comparison.
;; Load through `emacsvox-aural-voice-workbench'.

;;; Code:

(require 'emacsvox-aural-voice-workbench-views)
(require 'emacsvox-aural-preview)

;; Workbench dependencies.
(declare-function emacsvox-aural-voice-workbench--active-palette
                  "emacsvox-aural-voice-workbench" ())
(declare-function emacsvox-aural-voice-workbench--browse-pairs
                  "emacsvox-aural-voice-workbench-library" ())
(declare-function emacsvox-aural-voice-workbench--library-active
                  "emacsvox-aural-voice-workbench-library" (id role))
(declare-function emacsvox-aural-voice-workbench--library-p
                  "emacsvox-aural-voice-workbench-library" ())
(defvar emacsvox-aural-voice-workbench-inventory)
(defvar emacsvox-aural-voice-workbench-rendered-view)
(defvar emacsvox-aural-voice-workbench-view)
;; End workbench dependencies.

(defcustom emacsvox-aural-voice-workbench-preview-text
  "The quick brown fox jumps over the lazy dog."
  "Common text used for Voice Workbench preview and A/B comparison."
  :group 'emacsvox-aural
  :type 'string)

(defvar-local emacsvox-aural-voice-workbench-preview-generation 0
  "Generation identifying the current preview and its callbacks.")

(defvar-local emacsvox-aural-voice-workbench-last-preview nil
  "Most recent normalized preview result in this workbench.")

(defun emacsvox-aural-voice-workbench--normalized-acss-value (value)
  "Normalize zero-to-nine ACSS VALUE for transactional preview."
  (and (numberp value) (/ (float (max 0 (min 9 value))) 9.0)))

(defun emacsvox-aural-voice-workbench--preview-acss (logical-voice)
  "Return portable normalized ACSS for LOGICAL-VOICE, when available."
  (when-let* ((entry
               (emacsvox-aural-voice-workbench--palette-entry logical-voice)))
    (let* ((definition (cdr entry))
           (style
            (emacsvox-aural-voice-tuner--complete-style
             definition (emacsvox-aural-voice-workbench--active-palette)))
           result)
      (dolist
          (dimension
           '(average-pitch pitch-range stress richness))
        (when-let* ((value
                     (plist-get
                      style
                      (emacsvox-aural--voice-dimension-key dimension)))
                    (normalized
                     (emacsvox-aural-voice-workbench--normalized-acss-value
                      value)))
          (setq
           result
           (plist-put
            result
            (emacsvox-aural--voice-dimension-key dimension)
            normalized))))
      result)))

(defun emacsvox-aural-voice-workbench--preview-rate-offset (logical-voice)
  "Return portable relative rate for LOGICAL-VOICE, when nonzero."
  (when-let* ((entry
               (emacsvox-aural-voice-workbench--palette-entry logical-voice))
              (style
               (emacsvox-aural-voice-tuner--complete-style
                (cdr entry) (emacsvox-aural-voice-workbench--active-palette)))
              (value (plist-get style :rate-offset)))
    (and (numberp value) (not (zerop value)) value)))

(defun emacsvox-aural-voice-workbench--preview-effects (logical-voice)
  "Return normalized post-synthesis effects for LOGICAL-VOICE."
  (when-let* ((entry
               (emacsvox-aural-voice-workbench--palette-entry logical-voice)))
    (let ((style
           (emacsvox-aural-voice-tuner--complete-style
            (cdr entry) (emacsvox-aural-voice-workbench--active-palette)))
          result)
      (dolist (dimension emacsvox-aural-post-synthesis-dimensions)
        (when-let* ((value
                     (plist-get
                      style
                      (emacsvox-aural--voice-dimension-key dimension)))
                    (normalized
                     (emacsvox-aural-normalize-post-synthesis-value
                      dimension value)))
          (setq
           result
           (plist-put
            result
            (emacsvox-aural--voice-dimension-key dimension)
            normalized))))
      result)))

(defun emacsvox-aural-voice-workbench--unavailable-reason (pair)
  "Return why physical PAIR cannot be auditioned, or nil when usable."
  (let ((engine (car pair)) (voice (cadr pair)))
    (cond
     ((null pair) "The selected voice is no longer installed")
     ((and (emacsvox-aural-voice-workbench--library-p)
           (eq 'no (emacsvox-aural-voice-workbench--library-active
                    (list (plist-get engine :engine-id) (plist-get voice :voice-id)) 'main)))
      "This voice is not active on main speech; review selection and Apply")
     ((not (tts--voice-preview-available-p (plist-get engine :availability)))
      (format "Engine %s is %s" (plist-get engine :engine-id)
              (plist-get engine :availability)))
     ((or (eq t (plist-get engine :disabled-by-policy))
          (member (plist-get engine :engine-id)
                  (plist-get emacsvox-aural-voice-workbench-inventory :disabled-engine-ids)))
      "The engine is disabled in the live routing policy")
     ((member (plist-get engine :circuit) '("open" "cooldown"))
      (format "The engine is in %s: %s" (plist-get engine :circuit)
              (or (plist-get engine :last-failure) "temporarily unavailable")))
     ((equal (plist-get engine :health) "failed") "The engine has failed")
     ((not (tts--voice-preview-available-p (plist-get voice :availability)))
      (format "Voice %s is %s" (plist-get voice :voice-id)
              (plist-get voice :availability))))))

(defun emacsvox-aural-voice-workbench--visible-physical-pairs ()
  "Return physical voices in displayed order, or filtered inventory order."
  (if (eq emacsvox-aural-voice-workbench-rendered-view 'physical)
      (save-excursion
        (goto-char (point-min))
        (let (pairs)
          (while (< (point) (point-max))
            (when-let* ((id (tabulated-list-get-id))
                        (_ (not (emacsvox-aural-voice-workbench--language-row-p id)))
                        (pair (emacsvox-aural-voice-workbench--physical-pair id)))
              (push pair pairs))
            (forward-line 1))
          (nreverse pairs)))
    (cl-remove-if-not
     (lambda (pair) (emacsvox-aural-voice-workbench--physical-visible-p
                     (car pair) (cadr pair)))
     (emacsvox-aural-voice-workbench--browse-pairs))))

(defun emacsvox-aural-voice-workbench--pair-name (pair)
  "Return the engine and physical voice name for PAIR."
  (format "%s, %s"
          (or (plist-get (car pair) :display-name) (plist-get (car pair) :engine-id))
          (or (plist-get (cadr pair) :display-name) (plist-get (cadr pair) :voice-id))))

(defun emacsvox-aural-voice-workbench--labelled-physical-entry (pair &optional identifier)
  "Build the exact sample and its optional label for PAIR and IDENTIFIER."
  (emacsvox-aural-preview-labelled-entry
   (emacsvox-aural-voice-workbench--physical-preview-entry pair)
   (emacsvox-aural-voice-workbench--pair-name pair) identifier))

(defun emacsvox-aural-voice-workbench--physical-preview-entry (pair)
  "Return one exact preview entry for physical engine/voice PAIR."
  (when-let* ((reason (emacsvox-aural-voice-workbench--unavailable-reason pair)))
    (user-error "%s" reason))
  (let ((engine (car pair)) (voice (cadr pair)))
    (list
     :text emacsvox-aural-voice-workbench-preview-text
     :selector
     (list :kind 'exact
           :engine-id (plist-get engine :engine-id)
           :voice-id (plist-get voice :voice-id)
           :scope 'session)
     :language (plist-get voice :language)
     :acss nil :effects nil)))

(defun emacsvox-aural-voice-workbench--logical-preview-entry (logical-voice)
  "Return the saved named voice preview with staged workstation policy."
  (let ((voice (emacsvox-aural-voice-workbench--resolved-voice logical-voice)))
    (list :text emacsvox-aural-voice-workbench-preview-text
          :language (plist-get voice :language)
          :acss (emacsvox-aural-voice-workbench--preview-acss logical-voice)
          :rate-offset (emacsvox-aural-voice-workbench--preview-rate-offset logical-voice)
          :effects (emacsvox-aural-voice-workbench--preview-effects logical-voice)
          :selectors (copy-tree (plist-get voice :selectors))
          :fallback-policy (emacsvox-aural-voice-runtime--preview-policy voice)
          :disabled-engine-ids (copy-sequence (plist-get (plist-get voice :policy) :disabled-engines)))))

(defun emacsvox-aural-voice-workbench--current-preview-entry ()
  "Return a preview entry for the current Workbench row."
  (let ((id (or (tabulated-list-get-id)
                (user-error "Move to a Voice Workbench row first"))))
    (pcase emacsvox-aural-voice-workbench-view
      ('physical
       (emacsvox-aural-voice-workbench--physical-preview-entry
        (or (emacsvox-aural-voice-workbench--physical-pair id)
            (user-error "The selected physical voice is no longer installed"))))
      ((or 'logical 'styles)
       (emacsvox-aural-voice-workbench--logical-preview-entry id))
      ('engines
       (list
        :text emacsvox-aural-voice-workbench-preview-text
        :selector (list :kind 'engine-default :engine-id id :scope 'session)
        :language nil :acss nil :effects nil)))))

(defun emacsvox-aural-voice-workbench--preview-description (result)
  "Return concise non-speaking status text for preview RESULT."
  (let* ((results (plist-get result :results))
         (last (car (last results)))
         (realized (plist-get last :realized))
         (degraded
          (append (plist-get last :degraded-acss)
                  (plist-get last :degraded-effects))))
    (format
     "Preview %s%s%s"
     (or (plist-get result :status) "unknown")
     (if realized
         (format ", realized %s/%s"
                 (plist-get realized :engine-id)
                 (plist-get realized :voice-id))
       "")
     (if degraded
         (format ", degraded %s"
                 (mapconcat (lambda (item) (format "%s" item))
                            degraded ", "))
       ""))))

(defun emacsvox-aural-voice-workbench--preview-complete (buffer result)
  "Record preview RESULT in live workbench BUFFER without speaking it."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (setq emacsvox-aural-voice-workbench-last-preview result)
      (force-mode-line-update)))
  (emacsvox-aural-preview-message
   "%s" (emacsvox-aural-voice-workbench--preview-description result)))

(defun emacsvox-aural-voice-workbench--preview-entries (entries)
  "Preview ENTRIES and record only the current sequence's terminal status."
  (let ((buffer (current-buffer))
        (generation (cl-incf emacsvox-aural-voice-workbench-preview-generation)))
    (setq emacsvox-aural-voice-workbench-last-preview
          (list :status (format "running %d" (length entries))))
    (force-mode-line-update)
    (condition-case error-data
        (tts-preview-voices
         entries
         (lambda (result)
           (when (and (buffer-live-p buffer)
                      (= generation (buffer-local-value
                                     'emacsvox-aural-voice-workbench-preview-generation buffer)))
             (emacsvox-aural-voice-workbench--preview-complete buffer result)
             (when (eq (plist-get result :status) 'failed)
               (with-current-buffer buffer
                 (emacsvox-aural-ui-announce-result
                  "Preview failed: %s"
                  (or (plist-get (car (last (plist-get result :results))) :message)
                      "The requested voice could not be played")))))))
      (error
       (setq emacsvox-aural-voice-workbench-last-preview
             (list :status 'failed :message (error-message-string error-data)))
       (signal (car error-data) (cdr error-data))))))

(defun emacsvox-aural-voice-workbench-preview ()
  "Preview the selected voice, identifying physical samples by name."
  (interactive)
  (emacsvox-aural-voice-workbench--preview-entries
   (if (eq emacsvox-aural-voice-workbench-view 'physical)
       (emacsvox-aural-voice-workbench--labelled-physical-entry
        (emacsvox-aural-voice-workbench--physical-pair (tabulated-list-get-id)) "1")
     (list (emacsvox-aural-voice-workbench--current-preview-entry)))))

(defun emacsvox-aural-voice-workbench-edit-preview-text ()
  "Edit the common Voice Workbench comparison text."
  (interactive)
  (let ((text
         (read-string "Voice preview text: "
                      emacsvox-aural-voice-workbench-preview-text)))
    (when (string-empty-p text)
      (user-error "Voice preview text must not be empty"))
    (setq emacsvox-aural-voice-workbench-preview-text text))
  (emacsvox-aural-preview-message "Voice preview text updated"))

(defun emacsvox-aural-voice-workbench-preview-all ()
  "Preview usable matching voices in displayed order, identifying each sample."
  (interactive)
  (let ((pairs (emacsvox-aural-voice-workbench--visible-physical-pairs))
        entries skipped (index 0))
    (when (and (not pairs) (eq emacsvox-aural-voice-workbench-view 'physical)
               tabulated-list-entries)
      (user-error "Expand a language to preview its voices"))
    (dolist (pair pairs)
      (if (emacsvox-aural-voice-workbench--unavailable-reason pair)
          (push (emacsvox-aural-voice-workbench--pair-name pair) skipped)
        (setq entries
              (nconc entries (emacsvox-aural-voice-workbench--labelled-physical-entry
                              pair (number-to-string (cl-incf index)))))))
    (unless entries (user-error "No available physical voices match the current filter"))
    (when skipped
      (emacsvox-aural-preview-message "Skipping unavailable voices: %s"
                                      (string-join (nreverse skipped) "; ")))
    (emacsvox-aural-voice-workbench--preview-entries entries)))

(defun emacsvox-aural-voice-workbench--physical-candidates (&optional filtered)
  "Return available physical voice candidates; FILTERED restricts the list."
  (mapcar
   (lambda (pair)
     (cons (format "%s [%s/%s]"
                   (emacsvox-aural-voice-workbench--pair-name pair)
                   (plist-get (car pair) :engine-id) (plist-get (cadr pair) :voice-id)) pair))
   (cl-remove-if #'emacsvox-aural-voice-workbench--unavailable-reason
                 (if filtered (emacsvox-aural-voice-workbench--visible-physical-pairs)
                   (emacsvox-aural-voice-workbench--all-engine-voices)))))

(defun emacsvox-aural-voice-workbench-compare ()
  "Compare the selected physical voice with another matching voice."
  (interactive)
  (unless (eq emacsvox-aural-voice-workbench-view 'physical)
    (user-error "Select a physical voice to begin comparison"))
  (let* ((first (emacsvox-aural-voice-workbench--physical-pair (tabulated-list-get-id)))
         (_ (when-let* ((reason (emacsvox-aural-voice-workbench--unavailable-reason first)))
              (user-error "%s" reason)))
         (candidates (cl-remove first (emacsvox-aural-voice-workbench--physical-candidates t)
                                :key #'cdr :test #'equal))
         (all-choice "Search all engines")
         (name (emacsvox-aural-ui--read-choice "Compare with B: "
                                              (append candidates (list (cons all-choice nil)))))
         (second
          (if (equal name all-choice)
              (let* ((all (cl-remove first (emacsvox-aural-voice-workbench--physical-candidates)
                                     :key #'cdr :test #'equal)))
                (unless all (user-error "No other available physical voices"))
                (cdr (assoc (emacsvox-aural-ui--read-choice "B voice, all engines: " all) all)))
            (cdr (assoc name candidates)))))
    (emacsvox-aural-voice-workbench--preview-entries
     (append (emacsvox-aural-voice-workbench--labelled-physical-entry first "A")
             (emacsvox-aural-voice-workbench--labelled-physical-entry second "B")))))

(defun emacsvox-aural-voice-workbench-stop-preview ()
  "Stop the active preview immediately."
  (interactive)
  (tts-stop)
  (setq emacsvox-aural-voice-workbench-last-preview '(:status cancelled))
  (force-mode-line-update)
  (emacsvox-aural-preview-message "Voice preview stopped"))

(provide 'emacsvox-aural-voice-workbench-preview)
;;; emacsvox-aural-voice-workbench-preview.el ends here
