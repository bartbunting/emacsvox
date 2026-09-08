;;; emacsvox-aural-voice-drafts.el --- Voice draft save coordination -*- lexical-binding: t; -*-

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

;; Session drafts outlive their view buffers.  Frozen proposals coordinate the
;; existing nonactivating writers, then publish complete live data and request
;; acknowledged application.  No two-file atomic transaction is implied.

;;; Code:

(require 'emacsvox-aural-voice-runtime)
(require 'map)

(define-error 'emacsvox-aural-voice-draft-conflict "Voice draft destination changed")

(cl-defstruct (emacsvox-aural-voice-draft (:constructor emacsvox-aural-voice-drafts--make))
  key baseline working original history proposal watches)

(cl-defstruct (emacsvox-aural-voice-save (:constructor emacsvox-aural-voice-drafts--make-save))
  id draft snapshot palette choice-sets select watches before-palette
  aural-file routing-file before-files aural-data routing-data completed
  (state 'ready) result operation)

(defvar emacsvox-aural-voice-drafts--registry (make-hash-table :test #'equal)
  "Authoritative drafts by destination and editing scope for this session.")
(defvar emacsvox-aural-voice-drafts--serial 0
  "Allocator for immutable save proposal identities.")
(defvar emacsvox-aural-voice-drafts--changed-hook nil
  "Observers of complete draft state changes; never called between file writes.")

(defun emacsvox-aural-voice-drafts--open (key snapshot &optional sources)
  "Resume KEY or create its session draft from a copied SNAPSHOT.
SOURCES identifies palettes to watch for edits made after opening."
  (or (gethash key emacsvox-aural-voice-drafts--registry)
      (let ((draft (emacsvox-aural-voice-drafts--make
                    :key (copy-tree key) :baseline (copy-tree snapshot)
                    :working (copy-tree snapshot) :original (copy-tree snapshot)
                    :watches (emacsvox-aural-voice-drafts--watch sources))))
        (puthash (copy-tree key) draft emacsvox-aural-voice-drafts--registry)
        draft)))

(defun emacsvox-aural-voice-drafts--changed (draft)
  "Notify observers of DRAFT without requiring any view buffer to survive."
  (run-hook-with-args 'emacsvox-aural-voice-drafts--changed-hook draft))

(defun emacsvox-aural-voice-drafts--dirty-fields (draft)
  "Return fields differing between DRAFT's working values and saved baseline."
  (let ((before (emacsvox-aural-voice-draft-baseline draft))
        (after (emacsvox-aural-voice-draft-working draft)) fields)
    (dolist (key (delete-dups (append (map-keys before) (map-keys after))))
      (unless (and (eq (not (null (plist-member before key)))
                       (not (null (plist-member after key))))
                   (equal (plist-get before key) (plist-get after key)))
        (push key fields)))
    (nreverse fields)))

(defun emacsvox-aural-voice-drafts--edit (draft snapshot)
  "Replace DRAFT's working SNAPSHOT, retaining an undo step and pending save."
  (unless (equal snapshot (emacsvox-aural-voice-draft-working draft))
    (push (copy-tree (emacsvox-aural-voice-draft-working draft))
          (emacsvox-aural-voice-draft-history draft))
    (setf (emacsvox-aural-voice-draft-working draft) (copy-tree snapshot))
    (emacsvox-aural-voice-drafts--changed draft))
  draft)

(defun emacsvox-aural-voice-drafts--undo (draft)
  "Restore DRAFT's previous working values without changing completed saves."
  (when (emacsvox-aural-voice-draft-history draft)
    (setf (emacsvox-aural-voice-draft-working draft)
          (pop (emacsvox-aural-voice-draft-history draft)))
    (emacsvox-aural-voice-drafts--changed draft)))

(defun emacsvox-aural-voice-drafts--discard (draft)
  "Forget DRAFT's unsaved work, retaining any incomplete save or apply status."
  (when-let* ((proposal (emacsvox-aural-voice-draft-proposal draft)))
    (unless (or (emacsvox-aural-voice-save-completed proposal)
                (memq (emacsvox-aural-voice-save-state proposal) '(saving applying)))
      (setf (emacsvox-aural-voice-save-state proposal) 'abandoned
            (emacsvox-aural-voice-draft-proposal draft) nil)))
  (setf (emacsvox-aural-voice-draft-working draft)
        (copy-tree (emacsvox-aural-voice-draft-baseline draft))
        (emacsvox-aural-voice-draft-history draft) nil)
  (emacsvox-aural-voice-drafts--changed draft))

(defun emacsvox-aural-voice-drafts--file-id (file)
  "Return a content fingerprint for FILE, or nil when it does not exist."
  (when (file-exists-p file)
    (with-temp-buffer
      (insert-file-contents-literally file)
      (secure-hash 'sha256 (current-buffer)))))

(defun emacsvox-aural-voice-drafts--palette-data (id)
  "Return a fresh snapshot of the live palette named ID."
  (when-let* ((record (gethash id emacsvox-aural-voice-palette-registry)))
    (emacsvox-aural-voice-palette-data-form record)))

(defun emacsvox-aural-voice-drafts--watch (ids)
  "Capture effective definitions and their owners for palette IDS."
  (mapcar (lambda (id)
            (cons id (emacsvox-aural-voice-data--entries
                      id emacsvox-aural-voice-palette-registry))) ids))

(cl-defun emacsvox-aural-voice-drafts--prepare
    (draft palette choice-sets &key select sources
           (aural-file emacsvox-aural-schemes-file)
           (routing-file emacsvox-aural-routing-profiles-file))
  "Freeze DRAFT, destination PALETTE and new CHOICE-SETS for one save.
SELECT requests activation after complete persistence; nil saves to collection.
SOURCES lists palettes whose effective definitions must remain unchanged.
AURAL-FILE and ROUTING-FILE identify the two existing stores."
  (when-let* ((previous (emacsvox-aural-voice-draft-proposal draft)))
    (when (memq (emacsvox-aural-voice-save-state previous)
                '(saving partial failed applying))
      (user-error "Finish or retry the existing save before preparing another")))
  (unless (equal (emacsvox-aural-voice-draft-watches draft)
                 (emacsvox-aural-voice-drafts--watch
                  (mapcar #'car (emacsvox-aural-voice-draft-watches draft))))
    (signal 'emacsvox-aural-voice-draft-conflict '("Source changed since this draft opened")))
  (unless (eq (plist-get palette :routing) 'owned)
    (user-error "Voice saves require a palette with owned choices"))
  (when-let* ((record (gethash (plist-get palette :id) emacsvox-aural-voice-palette-registry)))
    (when (emacsvox-aural-voice-palette-built-in record)
      (user-error "Copy the built-in palette before saving")))
  (let* ((palette (copy-tree palette))
         (record (emacsvox-aural-compile-voice-palette-data palette))
         (id (plist-get palette :id))
         (before (emacsvox-aural-voice-drafts--palette-data id))
         (aural-file (expand-file-name aural-file))
         (routing-file (expand-file-name routing-file))
         (before-files (list (emacsvox-aural-voice-drafts--file-id aural-file)
                             (emacsvox-aural-voice-drafts--file-id routing-file)))
         (aural (or (emacsvox-aural-read-user-data aural-file) (emacsvox-aural-user-data)))
         (routing (or (emacsvox-aural-read-routing-profiles routing-file)
                      (emacsvox-aural-routing-user-data)))
         (registry (copy-hash-table emacsvox-aural-voice-palette-registry))
         (sets (emacsvox-aural-routing--merge-choice-sets
                (plist-get routing :choice-sets)
                (emacsvox-aural-routing--merge-choice-sets emacsvox-aural-routing--choice-sets choice-sets))))
    (when (equal aural-file routing-file) (user-error "Palette and routing stores must be distinct"))
    (when (and (file-exists-p aural-file)
               (not (equal before (cl-find id (plist-get aural :voice-palettes)
                                           :key (lambda (p) (plist-get p :id))))))
      (signal 'emacsvox-aural-voice-draft-conflict '("Saved destination differs from loaded data")))
    (puthash id record registry)
    (dolist (item (emacsvox-aural-voice-data--entries id registry))
      (emacsvox-aural-voice-data--choices
       (plist-get item :palette) (car (plist-get item :entry)) (cdr (plist-get item :entry)) sets
       (plist-get item :schema-version)))
    (let ((emacsvox-aural-voice-palette-registry registry)
          (emacsvox-aural-routing--choice-sets sets))
      (emacsvox-aural-voice-runtime--validate id))
    (unless (equal before-files (list (emacsvox-aural-voice-drafts--file-id aural-file)
                                      (emacsvox-aural-voice-drafts--file-id routing-file)))
      (signal 'emacsvox-aural-voice-draft-conflict '("Saved files changed while preparing")))
    (setq aural (plist-put aural :voice-palettes
                           (cons palette (cl-remove id (plist-get aural :voice-palettes)
                                                    :key (lambda (p) (plist-get p :id))))))
    (setq routing (plist-put routing :choice-sets sets))
    (let ((proposal
           (emacsvox-aural-voice-drafts--make-save
            :id (cl-incf emacsvox-aural-voice-drafts--serial) :draft draft
            :snapshot (copy-tree (emacsvox-aural-voice-draft-working draft))
            :palette palette :choice-sets (copy-tree sets) :select select
            :watches (emacsvox-aural-voice-drafts--watch
                      (delete-dups (append (mapcar #'car (emacsvox-aural-voice-draft-watches draft))
                                           sources (and before (list id)))))
            :before-palette before :aural-file aural-file :routing-file routing-file
            :before-files before-files
            :aural-data (emacsvox-aural--validate-user-data aural)
            :routing-data (emacsvox-aural-validate-routing-user-data routing))))
      (setf (emacsvox-aural-voice-draft-proposal draft) proposal)
      proposal)))

(defun emacsvox-aural-voice-drafts--check-live (proposal)
  "Reject changed destination or inherited source data for PROPOSAL."
  (let* ((data (emacsvox-aural-voice-save-palette proposal))
         (id (plist-get data :id))
         (emacsvox-aural-voice-palette-registry (copy-hash-table emacsvox-aural-voice-palette-registry))
         (emacsvox-aural-routing--choice-sets (emacsvox-aural-voice-save-choice-sets proposal)))
    (puthash id (emacsvox-aural-compile-voice-palette-data data) emacsvox-aural-voice-palette-registry)
    (emacsvox-aural-voice-runtime--validate id))
  (unless (and
           (equal (emacsvox-aural-voice-save-before-palette proposal)
                  (emacsvox-aural-voice-drafts--palette-data
                   (plist-get (emacsvox-aural-voice-save-palette proposal) :id)))
           (equal (emacsvox-aural-voice-save-watches proposal)
                  (emacsvox-aural-voice-drafts--watch
                   (mapcar #'car (emacsvox-aural-voice-save-watches proposal)))))
    (signal 'emacsvox-aural-voice-draft-conflict '("Palette or inherited definitions changed"))))

(defun emacsvox-aural-voice-drafts--check-file (proposal step)
  "Validate store STEP for PROPOSAL, recognizing a previously completed write."
  (let* ((aural (eq step 'palette))
         (file (if aural (emacsvox-aural-voice-save-aural-file proposal)
                 (emacsvox-aural-voice-save-routing-file proposal)))
         (reader (if aural #'emacsvox-aural-read-user-data #'emacsvox-aural-read-routing-profiles))
         (desired (if aural (emacsvox-aural-voice-save-aural-data proposal)
                    (emacsvox-aural-voice-save-routing-data proposal)))
         (completed (memq step (emacsvox-aural-voice-save-completed proposal)))
         (actual (funcall reader file)))
    (cond
     ((equal actual desired)
      (cl-pushnew step (emacsvox-aural-voice-save-completed proposal)))
     ((or completed
          (not (equal (emacsvox-aural-voice-drafts--file-id file)
                      (nth (if aural 0 1) (emacsvox-aural-voice-save-before-files proposal)))))
      (signal 'emacsvox-aural-voice-draft-conflict (list "Saved file changed" file))))))

(defun emacsvox-aural-voice-drafts--apply (proposal)
  "Apply the already published PROPOSAL with operation-owned acknowledgements."
  (let* ((draft (emacsvox-aural-voice-save-draft proposal))
         (palette (plist-get (emacsvox-aural-voice-save-palette proposal) :id))
         (operation nil))
    (unless (and (eq palette (emacsvox-aural-effective-voice-palette))
                 (equal (emacsvox-aural-voice-save-palette proposal)
                        (emacsvox-aural-voice-drafts--palette-data palette)))
      (signal 'emacsvox-aural-voice-draft-conflict '("Saved palette is no longer the active configuration")))
    (setq operation (cl-incf emacsvox-aural-routing--apply-operation))
    (setf (emacsvox-aural-voice-save-state proposal) 'applying
          (emacsvox-aural-voice-save-operation proposal) operation)
    (emacsvox-aural-routing--publish-apply-status (list :status 'applying :palette palette))
    (condition-case error-data
        (tts-apply-voice-configuration
         (lambda (result)
           (when (and (eq (emacsvox-aural-voice-save-state proposal) 'applying)
                      (= operation (emacsvox-aural-voice-save-operation proposal))
                      (eq proposal (emacsvox-aural-voice-draft-proposal draft)))
             (setf (emacsvox-aural-voice-save-result proposal) (copy-tree result)
                   (emacsvox-aural-voice-save-state proposal)
                   (if (/= operation emacsvox-aural-routing--apply-operation) 'superseded
                     (if (eq (plist-get result :status) 'applied) 'applied 'apply-failed)))
             (when (eq (emacsvox-aural-voice-save-state proposal) 'applied)
               (setf (emacsvox-aural-voice-draft-original draft)
                     (copy-tree (emacsvox-aural-voice-save-snapshot proposal))))
             (when (= operation emacsvox-aural-routing--apply-operation)
               (emacsvox-aural-routing--publish-apply-status (append (list :palette palette) result)))
             (emacsvox-aural-voice-drafts--changed draft))))
      (error
       (setf (emacsvox-aural-voice-save-state proposal) 'apply-failed
             (emacsvox-aural-voice-save-result proposal) (list :message (error-message-string error-data)))))))

(defun emacsvox-aural-voice-drafts--save (proposal)
  "Persist or retry frozen PROPOSAL, then publish and optionally apply it.
Errors remain attached to the proposal.  Repeating an in-flight save is a no-op."
  (unless (memq (emacsvox-aural-voice-save-state proposal) '(saving applying applied saved))
    (condition-case error-data
        (progn
          (unless (eq proposal (emacsvox-aural-voice-draft-proposal
                                (emacsvox-aural-voice-save-draft proposal)))
            (signal 'emacsvox-aural-voice-draft-conflict '("Save proposal has been replaced")))
          (if (memq 'published (emacsvox-aural-voice-save-completed proposal))
              (progn
                (emacsvox-aural-voice-drafts--check-file proposal 'local)
                (emacsvox-aural-voice-drafts--check-file proposal 'palette)
                (emacsvox-aural-voice-drafts--apply proposal))
            (emacsvox-aural-voice-drafts--check-live proposal)
            ;; Check both before either write; recheck the second before publishing.
            (emacsvox-aural-voice-drafts--check-file proposal 'local)
            (emacsvox-aural-voice-drafts--check-file proposal 'palette)
            (setf (emacsvox-aural-voice-save-state proposal) 'saving)
            (unless (memq 'local (emacsvox-aural-voice-save-completed proposal))
              (emacsvox-aural-routing--write-user-data
               (emacsvox-aural-voice-save-routing-data proposal)
               (emacsvox-aural-voice-save-routing-file proposal))
              (push 'local (emacsvox-aural-voice-save-completed proposal)))
            (emacsvox-aural-voice-drafts--check-live proposal)
            (emacsvox-aural-voice-drafts--check-file proposal 'palette)
            (unless (memq 'palette (emacsvox-aural-voice-save-completed proposal))
              (emacsvox-aural--write-user-data
               (emacsvox-aural-voice-save-aural-data proposal)
               (emacsvox-aural-voice-save-aural-file proposal))
              (push 'palette (emacsvox-aural-voice-save-completed proposal)))
            (emacsvox-aural-voice-drafts--check-live proposal)
            (let* ((data (emacsvox-aural-voice-save-palette proposal))
                   (id (plist-get data :id))
                   (draft (emacsvox-aural-voice-save-draft proposal))
                   (emacsvox-aural-voice-runtime--defer-apply t))
              (setq emacsvox-aural-routing--choice-sets
                    (emacsvox-aural-routing--merge-choice-sets
                     emacsvox-aural-routing--choice-sets (emacsvox-aural-voice-save-choice-sets proposal)))
              (puthash id (emacsvox-aural-compile-voice-palette-data
                           data nil (emacsvox-aural-voice-save-aural-file proposal))
                       emacsvox-aural-voice-palette-registry)
              (setf (emacsvox-aural-voice-draft-watches draft)
                    (emacsvox-aural-voice-drafts--watch
                     (mapcar #'car (emacsvox-aural-voice-draft-watches draft))))
              (push 'published (emacsvox-aural-voice-save-completed proposal))
              (setf (emacsvox-aural-voice-draft-baseline draft)
                    (copy-tree (emacsvox-aural-voice-save-snapshot proposal))
                    (emacsvox-aural-voice-save-state proposal) 'saved)
              (if (emacsvox-aural-voice-save-select proposal)
                  (emacsvox-aural-select-voice-palette id)
                (emacsvox-aural-configuration-changed 'voice-saved))
              (when (emacsvox-aural-voice-save-select proposal)
                (emacsvox-aural-voice-drafts--apply proposal)))))
      (error
       (setf (emacsvox-aural-voice-save-state proposal)
             (cond ((memq 'published (emacsvox-aural-voice-save-completed proposal)) 'apply-failed)
                   ((emacsvox-aural-voice-save-completed proposal) 'partial)
                   (t 'failed))
             (emacsvox-aural-voice-save-result proposal)
             (list :condition error-data :message (error-message-string error-data))))))
  (emacsvox-aural-voice-drafts--changed (emacsvox-aural-voice-save-draft proposal))
  proposal)

(defun emacsvox-aural-voice-drafts--status (draft)
  "Return presentation state shared by every view of DRAFT."
  (let* ((proposal (emacsvox-aural-voice-draft-proposal draft))
         (state (and proposal (emacsvox-aural-voice-save-state proposal)))
         (dirty (emacsvox-aural-voice-drafts--dirty-fields draft))
         (result (and proposal (emacsvox-aural-voice-save-result proposal)))
         (timeout (cl-some (lambda (lane) (eq (plist-get lane :phase) 'timeout))
                           (plist-get result :processes))))
    (list :dirty-fields dirty :save-state state :result (copy-tree result)
          :label
          (string-join
           (delq nil
                 (list (and dirty "Unsaved changes")
                       (pcase state
                         ('saving "Saving") ('applying "Saved; applying")
                         ('applied "Saved and applied") ('saved "Saved to collection")
                         ('apply-failed (if timeout "Saved; apply unconfirmed" "Saved; apply failed"))
                         ('partial "Partly saved; retry required")
                         ('failed "Save failed") ('superseded "Saved; a newer configuration is active")
                         (_ (unless dirty "No changes")))))
           "; "))))

(provide 'emacsvox-aural-voice-drafts)

;;; emacsvox-aural-voice-drafts.el ends here
