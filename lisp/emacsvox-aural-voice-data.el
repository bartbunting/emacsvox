;;; emacsvox-aural-voice-data.el --- Owned voice data -*- lexical-binding: t; -*-

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

;; Private, data-only operations for palette-owned physical choices.
;; Inputs are explicit snapshots.  No function here writes files, discovers
;; engines, changes registries, or applies speech configuration.

;;; Code:

(require 'emacsvox-aural-resources)
(require 'emacsvox-aural-routing-profiles)

(define-error 'emacsvox-aural-voice-data-conflict
  "Conflicting voice choices" 'emacsvox-aural-resource-error)

(defun emacsvox-aural-voice-data--entries (palette-id registry &optional path)
  "Return effective owned metadata for PALETTE-ID in REGISTRY.
Each result contains :palette and :entry.  PATH detects inheritance cycles."
  (when (memq palette-id path)
    (emacsvox-aural--resource-error "Palette inheritance cycle: %S" path))
  (let* ((record (gethash palette-id registry))
         (data (and record (emacsvox-aural-voice-palette-data-form record)))
         (parent (plist-get data :parent))
         entries)
    (unless record
      (emacsvox-aural--resource-error "Unknown voice palette: %S" palette-id))
    (emacsvox-aural-compile-voice-palette-data data)
    (when parent
      (let ((parent-record (gethash parent registry)))
        (unless (and parent-record
                     (eq (plist-get data :routing)
                         (plist-get (emacsvox-aural-voice-palette-data-form
                                     parent-record) :routing)))
          (emacsvox-aural--resource-error
           "Missing parent or mixed palette ownership: %S" parent)))
      (setq entries (emacsvox-aural-voice-data--entries
                     parent registry (cons palette-id path))))
    (dolist (entry (plist-get data :entries))
      (let ((value (list :palette palette-id :entry (copy-tree entry)))
            (old (cl-position (car entry) entries
                              :key (lambda (item) (car (plist-get item :entry))))))
        (if old (setf (nth old entries) value)
          (setq entries (append entries (list value))))))
    entries))

(defun emacsvox-aural-voice-data--names (name entries aliases)
  "Return NAME and applicable ALIASES, respecting direct names in ENTRIES."
  (cons name
        (cl-loop for (canonical . alias) in aliases
                 when (and (eq name canonical) (symbolp alias) alias
                           (not (cl-find alias entries
                                         :key (lambda (item)
                                                (car (plist-get item :entry))))))
                 collect alias)))

(defun emacsvox-aural-voice-data--binding (names bindings)
  "Coalesce BINDINGS for NAMES, signalling conflicts with all candidates."
  (let* ((strings (mapcar #'symbol-name names))
         (matches (cl-remove-if-not
                   (lambda (binding)
                     (member (emacsvox-aural-routing--logical-name
                              (plist-get binding :logical-voice)) strings))
                   bindings))
         (first (car matches)))
    (when (cl-some
           (lambda (binding)
             (or (not (equal (plist-get binding :language)
                             (plist-get first :language)))
                 (not (equal (plist-get binding :selectors)
                             (plist-get first :selectors)))))
           (cdr matches))
      (signal 'emacsvox-aural-voice-data-conflict
              (list "Aliases have different choices" names (copy-tree matches))))
    (copy-tree first)))

(defun emacsvox-aural-voice-data--choices (owner name properties local-sets)
  "Resolve choice PROPERTIES for OWNER and NAME against LOCAL-SETS."
  (let* ((sets (emacsvox-aural-routing--validate-choice-sets local-sets))
         (id (plist-get properties :local-choices))
         (local (and id (cl-find id sets :test #'equal
                                :key (lambda (item) (plist-get item :id))))))
    (when (and local
               (not (and (eq owner (plist-get local :palette))
                         (eq name (plist-get local :voice)))))
      (emacsvox-aural--resource-error "Wrong owner for local choices: %S" id))
    (list :selectors (copy-tree (if local (plist-get local :selectors)
                                 (plist-get properties :choices)))
          :language (plist-get properties :language)
          :choice-source (if local 'local 'portable)
          :diagnostics (and id (not local) (list 'missing-local-choices)))))

(cl-defun emacsvox-aural-voice-data--convert
    (registry source destination summary routing local-ids
              &optional (aliases emacsvox-aural-default-voice-entries))
  "Propose an independent legacy SOURCE copy in explicit REGISTRY.
DESTINATION and SUMMARY identify the new palette.  ROUTING is an explicitly
selected profile, or nil for Automatic.  LOCAL-IDS maps names to allocated
snapshot IDs, reused on retry.  ALIASES declares stable logical names."
  (when (gethash destination registry)
    (emacsvox-aural--resource-error "Destination palette already exists: %S"
                                    destination))
  (let* ((source-record (gethash source registry))
         (source-data (and source-record
                           (emacsvox-aural-voice-palette-data-form source-record)))
         (effective (emacsvox-aural-voice-data--entries source registry))
         (profile (and routing
                       (emacsvox-aural-validate-routing-profile-data routing)))
         entries sets)
    (when (eq (plist-get source-data :routing) 'owned)
      (emacsvox-aural--resource-error "Source already owns its choices: %S" source))
    (dolist (item effective)
      (let* ((entry (copy-tree (plist-get item :entry)))
             (name (car entry))
             (binding (emacsvox-aural-voice-data--binding
                       (emacsvox-aural-voice-data--names name effective aliases)
                       (plist-get profile :bindings)))
             (selectors (plist-get binding :selectors))
             (portable (cl-remove-if-not
                        (lambda (selector) (eq (plist-get selector :scope) 'portable))
                        selectors))
             (language (plist-get binding :language))
             (properties (append (cdr entry) (list :choices (copy-tree portable)))))
        (when language
          (setq properties (append properties (list :language language))))
        (unless (equal selectors portable)
          (let ((id (alist-get name local-ids)))
            (emacsvox-aural-routing--require-id id "Allocated local choice ID")
            (push (list :id id :palette destination :voice name
                        :selectors (copy-tree selectors)) sets)
            (setq properties (append properties (list :local-choices id)))))
        (push (cons name properties) entries)))
    (let ((palette (list :schema-version 2 :id destination :summary summary
                         :parent nil :routing 'owned :entries (nreverse entries))))
      (emacsvox-aural-compile-voice-palette-data palette)
      (list :palette palette
            :choice-sets (emacsvox-aural-routing--validate-choice-sets (nreverse sets))
            :before-source (copy-tree source-data)
            :before-effective (copy-tree effective)
            :before-routing (copy-tree routing)))))

(defun emacsvox-aural-voice-data--copy-owned
    (registry source destination summary local-sets local-ids)
  "Copy owned SOURCE to independent DESTINATION in REGISTRY with SUMMARY.
LOCAL-SETS supplies full chains; LOCAL-IDS supplies fresh IDs for the new owner.
Missing local data requires an explicit portable export instead of a local copy."
  (when (gethash destination registry)
    (emacsvox-aural--resource-error "Destination palette already exists: %S"
                                    destination))
  (let* ((record (gethash source registry))
         (data (and record (emacsvox-aural-voice-palette-data-form record)))
         (effective (emacsvox-aural-voice-data--entries source registry))
         entries sets)
    (unless (eq (plist-get data :routing) 'owned)
      (emacsvox-aural--resource-error "Source does not own its choices: %S" source))
    (dolist (item effective)
      (let* ((entry (copy-tree (plist-get item :entry)))
             (name (car entry))
             (properties (cdr entry)))
        (when (plist-get properties :local-choices)
          (let* ((choices (emacsvox-aural-voice-data--choices
                           (plist-get item :palette) name properties local-sets))
                 (id (alist-get name local-ids)))
            (when (plist-get choices :diagnostics)
              (emacsvox-aural--resource-error
               "Cannot copy missing local choices for %S" name))
            (emacsvox-aural-routing--require-id id "New owner's local choice ID")
            (setq properties (plist-put properties :local-choices id))
            (push (list :id id :palette destination :voice name
                        :selectors (plist-get choices :selectors)) sets)))
        (push (cons name properties) entries)))
    (let ((palette (list :schema-version 2 :id destination :summary summary
                         :parent nil :routing 'owned :entries (nreverse entries))))
      (emacsvox-aural-compile-voice-palette-data palette)
      ;; This also rejects attempted reuse of another owner's identity.
      (emacsvox-aural-routing--merge-choice-sets local-sets sets)
      (list :palette palette :choice-sets (nreverse sets)))))

(defun emacsvox-aural-voice-data--portable-export (data)
  "Return portable palette DATA and diagnostics for omitted local choices."
  (emacsvox-aural-compile-voice-palette-data data)
  (let ((result (copy-tree data)) omitted)
    (dolist (entry (plist-get result :entries))
      (when (plist-get (cdr entry) :local-choices)
        (push (car entry) omitted))
      (let ((properties (cdr entry)))
        (cl-remf properties :local-choices)
        (setcdr entry properties)))
    (list :palette result :omitted-local-choices (nreverse omitted))))

(provide 'emacsvox-aural-voice-data)

;;; emacsvox-aural-voice-data.el ends here
