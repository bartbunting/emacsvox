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
      (let ((value (list :palette palette-id :schema-version (plist-get data :schema-version)
                         :entry (copy-tree entry)))
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

(defun emacsvox-aural-voice-data--selectors (choices)
  "Return independent bare selectors from choice records CHOICES."
  (mapcar (lambda (choice) (copy-tree (plist-get choice :selector))) choices))

(defun emacsvox-aural-voice-data--wrap-selectors (selectors &optional portable)
  "Adapt untuned SELECTORS to temporary records, reusing PORTABLE identities.
Matching occurrences is only for old records without tuning.  No IDs are written
or allocated in a persistent store by this adapter."
  (let ((remaining (copy-tree portable))
        (used (mapcar (lambda (row) (plist-get row :id)) portable))
        (serial 0))
    (mapcar
     (lambda (selector)
       (let ((match (cl-find selector remaining :test #'equal
                             :key (lambda (row) (plist-get row :selector)))))
         (if match
             (progn (setq remaining (delq match remaining)) (copy-tree match))
           (let (id)
             (while (progn (setq id (format "choice-%d" (cl-incf serial)))
                           (member id used)))
             (push id used)
             (list :id id :selector (copy-tree selector) :adjustments nil)))))
     selectors)))

(defun emacsvox-aural-voice-data--portable-choices (choices)
  "Return independent portable records from CHOICES without reordering."
  (copy-tree (cl-remove-if-not
              (lambda (row) (eq (plist-get (plist-get row :selector) :scope) 'portable))
              choices)))

(defun emacsvox-aural-voice-data--choices (owner name properties local-sets &optional version)
  "Resolve choice PROPERTIES for OWNER and NAME against LOCAL-SETS.
VERSION is the defining palette schema, required for an empty schema-3 chain."
  (let* ((sets (emacsvox-aural-routing--validate-choice-sets local-sets))
         (id (plist-get properties :local-choices))
         (local (and id (cl-find id sets :test #'equal
                                :key (lambda (item) (plist-get item :id)))))
         (portable (plist-get properties :choices))
         (layered (if version (eq version 3)
                    (plist-member (car portable) :selector)))
         (versioned (eq (plist-get local :schema-version) 3))
         records)
    (when (and local
               (not (and (eq owner (plist-get local :palette))
                         (eq name (plist-get local :voice)))))
      (emacsvox-aural--resource-error "Wrong owner for local choices: %S" id))
    (when (and versioned (not layered))
      (emacsvox-aural--resource-error "Versioned local choices require palette schema 3"))
    (when layered
      (emacsvox-aural-routing--validate-choices portable t)
      (cond
       (versioned
        (setq records (plist-get local :choices))
        (unless (equal portable (emacsvox-aural-voice-data--portable-choices records))
          (emacsvox-aural--resource-error "Portable and local choices disagree: %S" id)))
       (local
        (when (cl-some (lambda (row) (plist-get row :adjustments)) portable)
          (emacsvox-aural--resource-error "Tuned choices require a versioned local snapshot"))
        (setq records (emacsvox-aural-voice-data--wrap-selectors
                       (plist-get local :selectors) portable)))
       (t (setq records portable))))
    (append
     (list :selectors (if layered (emacsvox-aural-voice-data--selectors records)
                        (copy-tree (if local (plist-get local :selectors) portable)))
           :language (plist-get properties :language)
           :choice-source (if local 'local 'portable)
           :diagnostics (and id (not local) (list 'missing-local-choices)))
     (when layered (list :choices (copy-tree records))))))

(cl-defun emacsvox-aural-voice-data--resolve
    (requested palette registry local-sets routing session policy
               &optional (aliases emacsvox-aural-default-voice-entries))
  "Resolve REQUESTED in PALETTE using explicit immutable inputs.
REGISTRY and LOCAL-SETS supply definitions and choices.  ROUTING supplies
legacy bindings; SESSION is the existing logical-name selector alist.  POLICY
is carried unchanged to the adapter.  ALIASES declares stable logical names."
  (let* ((logical-name (emacsvox-aural-routing--logical-name requested))
         (name (if (symbolp requested) requested (intern-soft logical-name)))
         (routing (and routing (emacsvox-aural-validate-routing-profile-data routing)))
         (entries (emacsvox-aural-voice-data--entries palette registry))
         (direct (cl-find name entries
                          :key (lambda (item) (car (plist-get item :entry)))))
         (canonical (or (and direct name)
                        (car (rassq name aliases))))
         (item (or direct (cl-find canonical entries
                                  :key (lambda (entry)
                                         (car (plist-get entry :entry))))))
         (owner (plist-get item :palette))
         (properties (cdr (plist-get item :entry)))
         (owned (and item
                     (eq (plist-get (emacsvox-aural-voice-palette-data-form
                                     (gethash owner registry)) :routing) 'owned)))
         (names (if owned
                    (emacsvox-aural-voice-data--names canonical entries aliases)
                  (and name (list name))))
         (saved (unless owned
                  (emacsvox-aural-routing--binding requested
                                                  (plist-get routing :bindings))))
         (choices (if owned
                      (emacsvox-aural-voice-data--choices owner canonical properties
                                                         local-sets (plist-get item :schema-version))
                    (list :selectors (copy-tree (plist-get saved :selectors))
                          :language (plist-get saved :language)
                          :choice-source 'legacy :diagnostics nil)))
         (temporary
          (if owned
              (emacsvox-aural-voice-data--binding
               names (mapcar (lambda (entry)
                               (list :logical-voice (car entry)
                                     :selectors (cdr entry))) session))
            (when-let* ((entry (cl-find (emacsvox-aural-routing--logical-name requested)
                                        session :test #'equal
                                        :key (lambda (entry)
                                               (emacsvox-aural-routing--logical-name
                                                (car entry))))))
              (list :logical-voice (car entry) :selectors (copy-tree (cdr entry)))))))
    (when temporary
      (unless (proper-list-p (plist-get temporary :selectors))
        (emacsvox-aural-routing--error "Session choices must be a proper list"))
      (dolist (selector (plist-get temporary :selectors))
        (emacsvox-aural-validate-routing-selector selector))
      (setq choices (plist-put choices :selectors (copy-tree (plist-get temporary :selectors))))
      (when (plist-member choices :choices)
        (setq choices (plist-put choices :choices
                                 (emacsvox-aural-voice-data--wrap-selectors
                                  (plist-get temporary :selectors)))))
      (setq choices (plist-put choices :choice-source 'session)))
    (append
     (list :requested requested :name (and item canonical) :palette owner
           :definition (copy-tree (if (plist-member properties :personality)
                                      (plist-get properties :personality)
                                    (plist-get properties :style)))
           :mode (if owned 'owned 'legacy)
           :automatic (and owned (null (plist-get choices :selectors))
                           (or (and temporary t) (null (plist-get choices :diagnostics))))
           :names names :entry (copy-tree (plist-get item :entry)) :session (copy-tree temporary) :policy (copy-tree policy))
     choices)))

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

(defun emacsvox-aural-voice-data--promote (data &optional row-ids)
  "Return owned palette DATA in schema 3, without changing local snapshots.
ROW-IDS optionally supplies frozen ID lists keyed by entry name for old chains."
  (emacsvox-aural-compile-voice-palette-data data)
  (unless (eq (plist-get data :routing) 'owned)
    (emacsvox-aural--resource-error "Only owned palettes can be promoted"))
  (let ((result (copy-tree data)))
    (unless (eq (plist-get result :schema-version) 3)
      (dolist (entry (plist-get result :entries))
        (let ((rows (emacsvox-aural-voice-data--wrap-selectors (plist-get (cdr entry) :choices)))
              (ids (assq (car entry) row-ids)))
          (when ids
            (unless (= (length rows) (length (cdr ids)))
              (emacsvox-aural--resource-error "Wrong number of allocated choice IDs"))
            (cl-mapc (lambda (row id) (setf (plist-get row :id) id)) rows (cdr ids)))
          (setcdr entry (plist-put (cdr entry) :choices rows))))
      (setq result (plist-put result :schema-version 3)))
    (emacsvox-aural-compile-voice-palette-data result)
    result))

(defun emacsvox-aural-voice-data--put-choices (data name choices snapshot-id &optional row-ids)
  "Propose CHOICES for direct NAME in DATA, promoting the palette if needed.
SNAPSHOT-ID identifies a fresh immutable local set when needed.  ROW-IDS freezes
other promoted entries' identities.  Publish through the save service."
  (let* ((data (emacsvox-aural-voice-data--promote data row-ids))
         (entry (assq name (plist-get data :entries)))
         (choices (emacsvox-aural-routing--validate-choices choices))
         (portable (emacsvox-aural-voice-data--portable-choices choices))
         sets)
    (unless entry (emacsvox-aural--resource-error "No direct owned entry: %S" name))
    (let ((properties (copy-tree (cdr entry))))
      (cl-remf properties :local-choices)
      (setq properties (plist-put properties :choices portable))
      (unless (equal choices portable)
        (emacsvox-aural-routing--require-id snapshot-id "New local snapshot ID")
        (setq properties (plist-put properties :local-choices snapshot-id))
        (setq sets (list (list :schema-version 3 :id snapshot-id
                              :palette (plist-get data :id) :voice name :choices choices))))
      (setcdr entry properties))
    (emacsvox-aural-compile-voice-palette-data data)
    (list :palette data :choice-sets (emacsvox-aural-routing--validate-choice-sets sets))))

(defun emacsvox-aural-voice-data--adjust-choice (choices id dimension operation &optional value)
  "Return CHOICES with ID's DIMENSION changed by OPERATION and VALUE.
OPERATION is inherit, default or set.  Every other field and row is preserved."
  (let* ((result (emacsvox-aural-routing--validate-choices choices))
         (row (cl-find id result :test #'equal :key (lambda (item) (plist-get item :id))))
         (patch (plist-get row :adjustments)))
    (unless row (emacsvox-aural--resource-error "Unknown choice: %S" id))
    (unless (memq dimension emacsvox-aural-routing--choice-dimensions)
      (emacsvox-aural--resource-error "Unknown choice dimension: %S" dimension))
    (pcase operation
      ('inherit (cl-remf patch dimension))
      ('default (setq patch (plist-put patch dimension nil)))
      ('set
       (unless (integerp value) (emacsvox-aural--resource-error "Custom value must be an integer"))
       (setq patch (plist-put patch dimension value)))
      (_ (emacsvox-aural--resource-error "Unknown choice adjustment operation")))
    (setf (plist-get row :adjustments) (emacsvox-aural-routing--validate-choice-adjustments patch))
    result))

(defun emacsvox-aural-voice-data--replace-choice (choices id selector adjustments)
  "Replace ID's SELECTOR in CHOICES, explicitly keeping or resetting ADJUSTMENTS.
ADJUSTMENTS must be keep or reset; no implicit tuning transfer is permitted."
  (let* ((result (emacsvox-aural-routing--validate-choices choices))
         (row (cl-find id result :test #'equal :key (lambda (item) (plist-get item :id)))))
    (unless row (emacsvox-aural--resource-error "Unknown choice: %S" id))
    (unless (memq adjustments '(keep reset))
      (emacsvox-aural--resource-error "Choose whether to keep or reset custom settings"))
    (emacsvox-aural-validate-routing-selector selector t)
    (setf (plist-get row :selector) (copy-tree selector))
    (when (eq adjustments 'reset) (setf (plist-get row :adjustments) nil))
    result))

(defun emacsvox-aural-voice-data--move-choice (choices id index)
  "Move choice ID in CHOICES to zero-based INDEX, preserving its whole record."
  (let* ((result (emacsvox-aural-routing--validate-choices choices))
         (row (cl-find id result :test #'equal :key (lambda (item) (plist-get item :id)))))
    (unless (and row (integerp index) (<= 0 index) (< index (length result)))
      (emacsvox-aural--resource-error "Invalid choice or destination"))
    (setq result (delq row result))
    (append (cl-subseq result 0 index) (list row) (nthcdr index result))))

(defun emacsvox-aural-voice-data--copy-owned
    (registry source destination summary local-sets local-ids)
  "Copy owned SOURCE to independent DESTINATION in REGISTRY with SUMMARY.
LOCAL-SETS supplies full chains; LOCAL-IDS supplies fresh IDs for the new owner.
Missing local data requires an explicit portable export instead of a local copy."
  (when (gethash destination registry)
    (emacsvox-aural--resource-error "Destination palette already exists: %S" destination))
  (let* ((record (gethash source registry))
         (data (and record (emacsvox-aural-voice-palette-data-form record)))
         (effective (emacsvox-aural-voice-data--entries source registry))
         (version (if (or (eq (plist-get data :schema-version) 3)
                          (cl-some (lambda (item) (eq (plist-get item :schema-version) 3)) effective)) 3 2))
         entries sets)
    (unless (eq (plist-get data :routing) 'owned)
      (emacsvox-aural--resource-error "Source does not own its choices: %S" source))
    (dolist (item effective)
      (let* ((entry (copy-tree (plist-get item :entry)))
             (name (car entry))
             (properties (cdr entry))
             (choices (emacsvox-aural-voice-data--choices
                       (plist-get item :palette) name properties local-sets
                       (plist-get item :schema-version)))
             (rows (and (= version 3)
                        (if (plist-member choices :choices) (plist-get choices :choices)
                          (emacsvox-aural-voice-data--wrap-selectors (plist-get choices :selectors))))))
        (when (plist-get choices :diagnostics)
          (emacsvox-aural--resource-error "Cannot copy missing local choices for %S" name))
        (when (= version 3)
          (setq properties (plist-put properties :choices
                                      (emacsvox-aural-voice-data--portable-choices rows))))
        (when (plist-get properties :local-choices)
          (let ((id (alist-get name local-ids)))
            (emacsvox-aural-routing--require-id id "New owner's local choice ID")
            (setq properties (plist-put properties :local-choices id))
            (push (if (= version 3)
                      (list :schema-version 3 :id id :palette destination :voice name :choices rows)
                    (list :id id :palette destination :voice name :selectors (plist-get choices :selectors))) sets)))
        (push (cons name properties) entries)))
    (let ((palette (list :schema-version version :id destination :summary summary
                         :parent nil :routing 'owned :entries (nreverse entries))))
      (emacsvox-aural-compile-voice-palette-data palette)
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
