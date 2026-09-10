;;; emacsvox-aural-voice-runtime.el --- Owned voice routing -*- lexical-binding: t; -*-

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

;; Connect immutable owned voice resolution to current configuration and the
;; existing adapter apply service.  Physical discovery stays in the adapters.

;;; Code:

(require 'emacsvox-aural-voice-data)
(require 'emacsvox-aural-schemes)

(declare-function tts-apply-voice-configuration "tts-speak" (&optional callback))
(declare-function tts-voice-inventory "tts-speak" ())
(declare-function voice-setup--generated-acss-p "voice-setup" (voice))
(declare-function voice-setup--generated-acss "voice-setup" (voice))

(defvar emacsvox-aural-voice-runtime--palette nil
  "Explicit palette bound while compiling or inspecting an inactive voice.")

(defvar emacsvox-aural-voice-runtime--defer-apply nil
  "Non-nil while a save coordinator owns acknowledged application.")

(defvar emacsvox-aural-voice-runtime--last-snapshot nil
  "Owned palette state last observed by the configuration bridge.")

(defun emacsvox-aural-voice-runtime--palette (&optional palette)
  "Return explicit PALETTE or the currently effective selection."
  (or palette emacsvox-aural-voice-runtime--palette
      (emacsvox-aural-effective-voice-palette)))

(defun emacsvox-aural-voice-runtime--owned-p (&optional palette)
  "Return non-nil when PALETTE owns physical choices."
  (when-let* ((record (gethash (emacsvox-aural-voice-runtime--palette palette)
                               emacsvox-aural-voice-palette-registry)))
    (eq (plist-get (emacsvox-aural-voice-palette-data-form record) :routing) 'owned)))

(defun emacsvox-aural-voice-runtime--profile (&optional profile)
  "Return explicit staged PROFILE or a snapshot of current workstation policy."
  (emacsvox-aural-routing-effective-profile-data
   (or profile (emacsvox-aural-routing-profile-from-omnivox
                'voice-runtime "Current workstation routing"))))

(defun emacsvox-aural-voice-runtime--resolve (voice &optional palette profile)
  "Resolve VOICE in PALETTE using explicit snapshots of local and session state.
PROFILE optionally supplies staged workstation policy for inspection."
  (let ((profile (emacsvox-aural-voice-runtime--profile profile)))
    (emacsvox-aural-voice-data--resolve
     voice (emacsvox-aural-voice-runtime--palette palette)
     emacsvox-aural-voice-palette-registry emacsvox-aural-routing--choice-sets
     profile emacsvox-aural-session-routing-bindings
     (list :engine-order (copy-sequence (plist-get profile :engine-order))
           :disabled-engines (copy-sequence (plist-get profile :disabled-engines))
           :fallback (copy-tree (plist-get profile :fallback))))))

(defun emacsvox-aural-voice-runtime--owned (voice &optional palette profile)
  "Return owned VOICE resolution, or nil to retain legacy behavior.
PALETTE and PROFILE optionally select inactive data for inspection."
  (when (emacsvox-aural-voice-runtime--owned-p palette)
    (let ((result (emacsvox-aural-voice-runtime--resolve voice palette profile)))
      (and (eq (plist-get result :mode) 'owned) result))))

(defun emacsvox-aural-voice-runtime--validate (&optional palette)
  "Validate owned metadata and temporary aliases in PALETTE before applying."
  (when (emacsvox-aural-voice-runtime--owned-p palette)
    (dolist (entry (emacsvox-aural-effective-voice-entries
                    (emacsvox-aural-voice-runtime--palette palette)))
      (emacsvox-aural-voice-runtime--owned (car entry) palette))))

(defun emacsvox-aural-voice-runtime--snapshot ()
  "Capture owned data that must be registered after a palette or session change."
  (when (emacsvox-aural-voice-runtime--owned-p)
    (let* ((entries (emacsvox-aural-voice-data--entries
                     (emacsvox-aural-voice-runtime--palette) emacsvox-aural-voice-palette-registry))
           (ids (mapcar (lambda (item) (plist-get (cdr (plist-get item :entry)) :local-choices)) entries)))
      (list (emacsvox-aural-voice-runtime--palette) entries
            (copy-tree (cl-remove-if-not (lambda (set) (member (plist-get set :id) ids))
                                        emacsvox-aural-routing--choice-sets))
            (copy-tree emacsvox-aural-session-routing-bindings)))))

(defun emacsvox-aural-voice-runtime--configuration-changed (&rest _)
  "Apply changed owned definitions and choices through the acknowledged service."
  (let ((snapshot (emacsvox-aural-voice-runtime--snapshot)))
    (unless (equal snapshot emacsvox-aural-voice-runtime--last-snapshot)
      (emacsvox-aural-voice-runtime--validate)
      (setq emacsvox-aural-voice-runtime--last-snapshot snapshot)
      (let ((operation (cl-incf emacsvox-aural-routing--apply-operation))
            (palette (emacsvox-aural-voice-runtime--palette)))
        (unless emacsvox-aural-voice-runtime--defer-apply
          (when (fboundp 'tts-apply-voice-configuration)
            (emacsvox-aural-routing--publish-apply-status
             (list :status 'applying :palette palette))
            (condition-case error-data
                (tts-apply-voice-configuration
                 (lambda (result)
                   (when (= operation emacsvox-aural-routing--apply-operation)
                     (emacsvox-aural-routing--publish-apply-status
                      (append (list :palette palette) result)))))
              (error
               (emacsvox-aural-routing--publish-apply-status
                (list :status 'failed :palette palette
                      :message (error-message-string error-data)))))))))))

(defun emacsvox-aural-voice-runtime--definition-style (definition &optional seen)
  "Read raw DEFINITION without compiling, routing or registering a voice.
SEEN prevents personality-variable cycles; opaque personalities are rejected."
  (cond
   ((null definition)
    (cl-loop for dimension in emacsvox-aural-voice-dimensions
             append (list (emacsvox-aural--voice-dimension-key dimension) nil)))
   ((emacsvox-aural-voice-style-p definition) (copy-tree definition))
   ((emacsvox-aural--acss-p definition)
    (emacsvox-aural--acss-to-voice-style definition))
   ((and (fboundp 'voice-setup--generated-acss-p)
         (voice-setup--generated-acss-p definition))
    (emacsvox-aural--acss-to-voice-style
     (voice-setup--generated-acss definition)))
   ((and (symbolp definition) (not (memq definition seen)))
    (let ((settings (intern-soft (format "%s-settings" definition))))
      (cond
       ((and settings (boundp settings) (proper-list-p (symbol-value settings)))
        (cl-loop for dimension in emacsvox-aural-voice-dimensions
                 for index from 0
                 append (list (emacsvox-aural--voice-dimension-key dimension)
                              (nth index (symbol-value settings)))))
       ((boundp definition)
        (emacsvox-aural-voice-runtime--definition-style
         (symbol-value definition) (cons definition seen)))
       (t (user-error "No inspectable settings for personality %s" definition)))))
   (t (user-error "Cannot inspect this personality definition"))))

(defun emacsvox-aural-voice-runtime--preview-policy (resolved)
  "Return the complete generic preview policy for RESOLVED workstation state."
  (let* ((policy (plist-get resolved :policy))
         (fallback (plist-get policy :fallback)))
    (list :preferred-engines
          (or (copy-sequence (plist-get policy :engine-order))
              (when (fboundp 'tts-voice-inventory)
                (when-let* ((preferred (plist-get (tts-voice-inventory) :preferred-engine-id)))
                  (list preferred))))
          :allow-same-language-on-requested-engine (plist-get fallback :allow-same-language)
          :global-default (copy-tree (plist-get fallback :global-default))
          :fallback-engines (copy-sequence (plist-get fallback :engines)))))

(add-hook 'emacsvox-aural-configuration-changed-hook
          #'emacsvox-aural-voice-runtime--configuration-changed)
(add-hook 'emacsvox-aural-routing-profile-changed-hook
          #'emacsvox-aural-voice-runtime--configuration-changed)

(provide 'emacsvox-aural-voice-runtime)

;;; emacsvox-aural-voice-runtime.el ends here
