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

(defun emacsvox-aural-voice-data--entries (palette-id registry &optional path)
  "Return effective owned metadata for PALETTE-ID in REGISTRY.
Each result contains :palette and :entry.  PATH detects inheritance cycles."
  (emacsvox-aural--effective-voice-metadata palette-id registry path))

(defun emacsvox-aural-voice-data--names (name entries aliases)
  "Return NAME and applicable ALIASES, respecting direct names in ENTRIES."
  (cons name
        (cl-loop for (canonical . alias) in aliases
                 when (and (eq name canonical) (symbolp alias) alias
                           (not (cl-find alias entries
                                         :key (lambda (item)
                                                (car (plist-get item :entry))))))
                 collect alias)))

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

(defun emacsvox-aural-voice-data--choices (owner name properties local-sets)
  "Resolve complete choices for OWNER and NAME from PROPERTIES and LOCAL-SETS."
  (let* ((sets (emacsvox-aural-routing--validate-choice-sets local-sets))
         (id (plist-get properties :local-choices))
         (local (and id (cl-find id sets :test #'equal :key (lambda (item) (plist-get item :id)))))
         (portable (plist-get properties :choices))
         (records (if local (plist-get local :choices) portable)))
    (emacsvox-aural-routing--validate-choices portable t)
    (when local
      (unless (and (eq owner (plist-get local :palette)) (eq name (plist-get local :voice)))
        (emacsvox-aural--resource-error "Wrong owner for local choices: %S" id))
      (unless (eq (plist-get local :schema-version) 3)
        (emacsvox-aural--resource-error "Local snapshot %S uses retired choice data" id))
      (unless (equal portable (emacsvox-aural-voice-data--portable-choices records))
        (emacsvox-aural--resource-error "Portable and local choices disagree: %S" id)))
    (list :selectors (emacsvox-aural-voice-data--selectors records)
          :choices (copy-tree records) :language (plist-get properties :language)
          :choice-source (if local 'local 'portable)
          :diagnostics (and id (not local) (list 'missing-local-choices)))))

(cl-defun emacsvox-aural-voice-data--resolve
    (requested palette registry local-sets policy &optional (aliases emacsvox-aural-default-voice-entries))
  "Resolve REQUESTED in PALETTE from immutable REGISTRY, LOCAL-SETS and POLICY.
ALIASES declares stable logical identities; physical choices belong to entries."
  (let* ((name (if (symbolp requested) requested
                 (intern-soft (emacsvox-aural-routing--logical-name requested))))
         (canonical (or (car (rassq name aliases)) name))
         (entries (emacsvox-aural-voice-data--entries palette registry))
         (item (cl-find canonical entries :key (lambda (entry) (car (plist-get entry :entry)))))
         (owner (plist-get item :palette))
         (properties (cdr (plist-get item :entry)))
         (choices (and item (emacsvox-aural-voice-data--choices owner canonical properties local-sets))))
    (append
     (list :requested requested :name (and item canonical) :palette owner
           :definition (copy-tree (if (plist-member properties :personality)
                                     (plist-get properties :personality) (plist-get properties :style)))
           :mode (and item 'owned)
           :automatic (and item (null (plist-get choices :selectors)) (null (plist-get choices :diagnostics)))
           :names (and item (emacsvox-aural-voice-data--names canonical entries aliases))
           :entry (copy-tree (plist-get item :entry)) :policy (copy-tree policy))
     choices)))

(defun emacsvox-aural-voice-data--put-choices (data name choices snapshot-id)
  "Propose complete CHOICES for direct NAME in DATA.
SNAPSHOT-ID identifies a fresh immutable local set. Publish through the save service."
  (let* ((data (copy-tree data))
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
  "Copy effective SOURCE to independent DESTINATION in REGISTRY with SUMMARY.
LOCAL-SETS supplies full chains; LOCAL-IDS supplies fresh IDs for the new owner.
Missing local data requires an explicit portable export instead of a local copy."
  (when (gethash destination registry)
    (emacsvox-aural--resource-error "Destination palette already exists: %S" destination))
  (emacsvox-aural-voice-data--materialize registry source destination summary local-sets local-ids))

(defun emacsvox-aural-voice-data--materialize
    (registry source destination summary local-sets local-ids)
  "Propose complete independent DESTINATION from SOURCE in REGISTRY.
SUMMARY and LOCAL-IDS belong to the new owner; LOCAL-SETS supplies full rows.
The caller validates destination conflicts in the publication registry."
  (let ((effective (emacsvox-aural-voice-data--entries source registry)) entries sets)
    (dolist (item effective)
      (let* ((entry (copy-tree (plist-get item :entry)))
             (name (car entry)) (properties (cdr entry))
             (choices (emacsvox-aural-voice-data--choices (plist-get item :palette) name properties local-sets))
             (rows (plist-get choices :choices)))
        (when (plist-get choices :diagnostics)
          (emacsvox-aural--resource-error "Cannot copy missing local choices for %S" name))
        (when (plist-get properties :local-choices)
          (let ((id (alist-get name local-ids)))
            (emacsvox-aural-routing--require-id id "New owner's local choice ID")
            (setq properties (plist-put properties :local-choices id))
            (push (list :schema-version 3 :id id :palette destination :voice name :choices rows) sets)))
        (push (cons name properties) entries)))
    (let ((palette (list :schema-version 3 :id destination :summary summary
                         :parent 'acss-default :routing 'owned :entries (nreverse entries))))
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

(defun emacsvox-aural-voice-data--export-effective (registry source)
  "Return a portable, independent export of SOURCE from REGISTRY.
Omission diagnostics name every voice whose local snapshot is excluded."
  (let ((data (list :schema-version 3
                    :id (if (eq source 'acss-default) 'acss-default-copy source)
                    :summary (emacsvox-aural-voice-palette-summary (gethash source registry))
                    :parent 'acss-default :routing 'owned
                    :entries (mapcar (lambda (item) (copy-tree (plist-get item :entry)))
                                     (emacsvox-aural-voice-data--entries source registry)))))
    (emacsvox-aural-voice-data--portable-export data)))

(defun emacsvox-aural-voice-data--backup (registry source local-sets)
  "Return SOURCE's complete ancestry and referenced LOCAL-SETS from REGISTRY."
  ;; Validate the complete chain before collecting it.
  (emacsvox-aural-voice-data--entries source registry)
  (let ((id source) palettes ids)
    (while id
      (let* ((record (gethash id registry))
             (data (emacsvox-aural-voice-palette-data-form record)))
        (push data palettes)
        (dolist (entry (plist-get data :entries))
          (let ((choices (emacsvox-aural-voice-data--choices id (car entry) (cdr entry) local-sets)))
            (when (plist-get choices :diagnostics)
              (emacsvox-aural--resource-error "Cannot back up missing local choices for %s in %s" (car entry) id)))
          (when-let* ((local (plist-get (cdr entry) :local-choices))) (push local ids)))
        (setq id (emacsvox-aural-voice-palette-parent record))))
    (list :schema-version 1 :kind 'voice-palette-backup :palette source
          :palettes (nreverse palettes)
          :choice-sets (copy-tree (cl-remove-if-not (lambda (set) (member (plist-get set :id) ids)) local-sets)))))

(defun emacsvox-aural-voice-data--read-exchange (data root)
  "Validate exchange DATA against standard ROOT and return isolated inputs.
Portable palettes are self-contained; backups carry their complete ancestry."
  (let ((registry (make-hash-table :test #'eq)) source sets kind)
    (if (eq (plist-get data :kind) 'voice-palette-backup)
        (progn
          (emacsvox-aural-routing--strict-properties
           data '(:schema-version :kind :palette :palettes :choice-sets)
           '(:schema-version :kind :palette :palettes :choice-sets))
          (unless (eq (plist-get data :schema-version) 1)
            (emacsvox-aural--resource-error "Unsupported palette backup version"))
          (setq source (plist-get data :palette) kind 'backup
                sets (emacsvox-aural-routing--validate-choice-sets (plist-get data :choice-sets)))
          (unless (proper-list-p (plist-get data :palettes))
            (emacsvox-aural--resource-error "Backup palettes must be a list"))
          (dolist (palette (plist-get data :palettes))
            (let ((id (plist-get palette :id)))
              (when (gethash id registry) (emacsvox-aural--resource-error "Duplicate backup palette: %s" id))
              (puthash id (emacsvox-aural-compile-voice-palette-data palette (eq id 'acss-default)) registry)))
          (unless (gethash 'acss-default registry)
            (emacsvox-aural--resource-error "Backup is missing its standard root"))
          (let ((validated (emacsvox-aural-voice-data--backup registry source sets)))
            (unless (= (length (plist-get validated :palettes)) (hash-table-count registry))
              (emacsvox-aural--resource-error "Backup contains unrelated palettes"))
            (unless (= (length sets) (length (plist-get validated :choice-sets)))
              (emacsvox-aural--resource-error "Backup contains unreferenced local snapshots"))))
      (setq source (plist-get data :id) kind 'portable)
      (unless (eq (plist-get data :parent) 'acss-default)
        (emacsvox-aural--resource-error "Portable imports must be independent children of acss-default"))
      (dolist (entry (plist-get data :entries))
        (when (plist-member (cdr entry) :local-choices)
          (emacsvox-aural--resource-error "Portable imports cannot contain local snapshot references")))
      (puthash 'acss-default root registry)
      (puthash source (emacsvox-aural-compile-voice-palette-data data) registry))
    (emacsvox-aural-voice-data--entries source registry)
    (list :kind kind :source source :registry registry :choice-sets sets)))

(provide 'emacsvox-aural-voice-data)

;;; emacsvox-aural-voice-data.el ends here
