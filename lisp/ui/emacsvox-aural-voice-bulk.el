;;; emacsvox-aural-voice-bulk.el --- Review a physical voice across a palette -*- lexical-binding: t; -*-

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
;; One unsaved review owns a complete palette proposal.  Private previews and
;; coordinated persistence reuse the common voice editor's existing services.

;;; Code:

(require 'emacsvox-aural-voice-editor)

(defvar emacsvox-aural-voice-bulk--contexts (make-hash-table :test #'equal)
  "Retained bulk reviews, including recoverable saves whose views were closed.")

(defun emacsvox-aural-voice-bulk--get (key)
  "Read KEY from this review."
  (plist-get emacsvox-aural-voice-editor--context key))

(defun emacsvox-aural-voice-bulk--inputs (source destination)
  "Capture effective SOURCE, complete local choices and DESTINATION identity."
  (let* ((registry emacsvox-aural-voice-palette-registry)
         (prepared (emacsvox-aural-voice-data--prepare-resolution
                    source registry emacsvox-aural-routing--choice-sets nil)))
    (list :source (emacsvox-aural-voice-drafts--palette-data source)
          :destination (emacsvox-aural-voice-drafts--palette-data destination)
          :entries (plist-get prepared :entries)
          :voices (mapcar (lambda (item)
                            (emacsvox-aural-voice-data--resolve-prepared
                             (car (plist-get item :entry)) prepared))
                          (plist-get prepared :entries)))))

(defun emacsvox-aural-voice-bulk--scopes (source destination)
  "Return source ancestors and palettes affected by SOURCE to DESTINATION."
  (let ((current source) scopes)
    (while (and current (not (memq current scopes)))
      (push current scopes)
      (setq current (plist-get (emacsvox-aural-voice-drafts--palette-data current) :parent)))
    (delete-dups
     (append (list destination) scopes
             (when (eq source destination)
               (emacsvox-aural-voice-palettes--descendants destination))))))

(defun emacsvox-aural-voice-bulk--conflicts (context)
  "Return other unfinished drafts overlapping CONTEXT."
  (let ((scopes (emacsvox-aural-voice-bulk--scopes
                 (plist-get context :source) (plist-get context :destination))) conflicts)
    (maphash
     (lambda (key draft)
       (let ((proposal (emacsvox-aural-voice-draft-proposal draft)))
         (when (and (not (eq draft (plist-get context :draft)))
                    (or (memq (cadr key) scopes)
                        (and (eq (car key) 'bulk) (memq (nth 2 key) scopes))
                        (cl-intersection scopes (mapcar #'car (emacsvox-aural-voice-draft-watches draft))))
                    (or (emacsvox-aural-voice-drafts--dirty-fields draft)
                        (and proposal (memq (emacsvox-aural-voice-save-state proposal)
                                            '(saving partial failed applying apply-failed)))))
           (push draft conflicts))))
     emacsvox-aural-voice-drafts--registry)
    conflicts))

(defun emacsvox-aural-voice-bulk--check (context)
  "Reject conflicting drafts or changed inputs to CONTEXT without writes."
  (when-let* ((conflicts (emacsvox-aural-voice-bulk--conflicts context)))
    (user-error "Unfinished voice edits: %s. Use Resolve drafts, then refresh this review"
                (mapconcat (lambda (draft) (format "%S" (emacsvox-aural-voice-draft-key draft)))
                           conflicts ", ")))
  (unless (equal (plist-get context :inputs)
                 (emacsvox-aural-voice-bulk--inputs
                  (plist-get context :source) (plist-get context :destination)))
    (signal 'emacsvox-aural-voice-draft-conflict '("Palette inputs changed; refresh and review again"))))

(defun emacsvox-aural-voice-bulk--files ()
  "Fingerprint both stores at the time a review opens."
  (mapcar #'emacsvox-aural-voice-drafts--file-id
          (list emacsvox-aural-schemes-file emacsvox-aural-routing-profiles-file)))

(defun emacsvox-aural-voice-bulk--build (context)
  "Capture a new unsaved review in CONTEXT after checking other drafts."
  (when (emacsvox-aural-voice-bulk--conflicts context)
    (user-error "Resolve unfinished voice drafts before refreshing this review"))
  (let* ((source (plist-get context :source))
         (destination (plist-get context :destination))
         (inputs (emacsvox-aural-voice-bulk--inputs source destination))
         (files (emacsvox-aural-voice-bulk--files))
         (data (emacsvox-aural-voice-editing--bulk-physical
                source destination (plist-get context :selector)
                (format "Personal voices based on %s" source)))
         (draft (plist-get context :draft)))
    (unless (and (equal inputs (emacsvox-aural-voice-bulk--inputs source destination))
                 (equal files (emacsvox-aural-voice-bulk--files)))
      (user-error "Palette inputs changed during preparation; refresh again"))
    (emacsvox-aural-voice-editor--invalidate context)
    (emacsvox-aural-voice-editor--context-put context :blocked nil)
    (dolist (pair (list (cons :inputs inputs) (cons :files files) (cons :data data)
                       (cons :rows (plist-get data :rows))
                       (cons :policy (emacsvox-aural-voice-editor--policy))))
      (emacsvox-aural-voice-editor--context-put context (car pair) (cdr pair)))
    (setf (emacsvox-aural-voice-draft-baseline draft) (plist-get inputs :destination)
          (emacsvox-aural-voice-draft-working draft) (copy-tree (plist-get data :palette))
          (emacsvox-aural-voice-draft-original draft) (copy-tree (plist-get inputs :destination))
          (emacsvox-aural-voice-draft-proposal draft) nil
          (emacsvox-aural-voice-draft-watches draft)
          (emacsvox-aural-voice-drafts--watch (list source)))
    (emacsvox-aural-voice-drafts--changed draft)))

(defun emacsvox-aural-voice-bulk--summary ()
  "Describe the scope and outcome of the complete review."
  (if (emacsvox-aural-voice-bulk--get :blocked)
      "Unfinished voice edits prevent preparation. r opens Resolve drafts; g refreshes after resolution"
    (let ((rows (emacsvox-aural-voice-bulk--get :rows)))
    (format "%s across %s: %d named voices; %d added, %d promoted, %d already preferred; %d inherited or copied. %s"
            (emacsvox-aural-voice-bulk--get :label)
            (emacsvox-aural-voice-bulk--get :destination) (length rows)
            (cl-count 'added rows :key (lambda (row) (plist-get row :action)))
            (cl-count 'promoted rows :key (lambda (row) (plist-get row :action)))
            (cl-count 'unchanged rows :key (lambda (row) (plist-get row :action)))
            (cl-count nil rows :key (lambda (row) (plist-get row :local)))
            (plist-get (emacsvox-aural-voice-drafts--status
                        (emacsvox-aural-voice-bulk--get :draft)) :label)))))

(defun emacsvox-aural-voice-bulk--render ()
  "Render the captured review while preserving its selected row and column."
  (let ((selected (tabulated-list-get-id)) (column (current-column)))
    (setq tabulated-list-entries
          (mapcar (lambda (row)
                    (let ((name (plist-get row :name)))
                      (list name
                            (vector (symbol-name name) (symbol-name (plist-get row :owner))
                                    (concat (pcase (plist-get row :action)
                                              ('added "Add preferred choice")
                                              ('promoted "Promote existing choice")
                                              (_ "Already preferred"))
                                            (unless (plist-get row :local) "; copy here"))))))
                  (emacsvox-aural-voice-bulk--get :rows)))
    (tabulated-list-print t)
    (emacsvox-aural-ui-goto-row (or selected 'default))
    (move-to-column column)
    (setq header-line-format (emacsvox-aural-voice-bulk--summary))))

(defun emacsvox-aural-voice-bulk-speak ()
  "Speak the selected named voice and proposed change."
  (interactive)
  (if-let* ((entry (tabulated-list-get-entry)))
      (emacsvox-aural-ui-speak (mapconcat #'identity entry ", "))
    (emacsvox-aural-ui-speak (emacsvox-aural-voice-bulk--summary))))

(defun emacsvox-aural-voice-bulk--opening ()
  "Speak the review scope and its main actions."
  (emacsvox-aural-ui-speak
   (concat (emacsvox-aural-voice-bulk--summary)
           ". B compares, P plays proposed, O plays original, A compares examples. "
           "w saves and applies; c saves to collection; x shows details; q goes back.")))

(defun emacsvox-aural-voice-bulk-stop ()
  "Cancel this review's private previews."
  (interactive)
  (emacsvox-aural-voice-editor--invalidate emacsvox-aural-voice-editor--context))

(defun emacsvox-aural-voice-bulk--preview (which &optional examples)
  "Preview WHICH snapshots, optionally comparing representative EXAMPLES."
  (let* ((context emacsvox-aural-voice-editor--context)
         (rows (emacsvox-aural-voice-bulk--get :rows))
         (names (if examples (cl-remove-if-not
                              (lambda (name) (cl-find name rows :key (lambda (row) (plist-get row :name))))
                              '(default indent animate bolden))
                  (list (or (tabulated-list-get-id) (user-error "Choose a named voice")))))
         (snapshots (pcase which ('compare '(:original :proposed))
                          ('original '(:original)) (_ '(:proposed)))) entries)
    (dolist (name names)
      (let ((row (cl-find name rows :key (lambda (item) (plist-get item :name)))))
        (dolist (key snapshots)
          (let* ((entry (emacsvox-aural-voice-editing--cascade
                         (plist-get row key) (plist-get context :source)
                         (plist-get context :policy) (plist-get context :text)))
                 (label (format "%s, %s." name (if (eq key :original) "original" "proposed"))))
            (setq entry (plist-put entry :variant (if (eq key :original) 'original 'edited)))
            (push (plist-put (plist-put (copy-tree entry) :text label) :role 'label) entries)
            (push entry entries)))))
    (unless entries (user-error "No representative voices; choose a row"))
    (emacsvox-aural-voice-editor--start-entries
     context (nreverse entries) (emacsvox-aural-voice-draft-revision (plist-get context :draft)))))

(defun emacsvox-aural-voice-bulk-play ()
  "Play the proposed named voice with its complete fallback chain."
  (interactive) (emacsvox-aural-voice-bulk--preview 'proposed))
(defun emacsvox-aural-voice-bulk-original ()
  "Play the original named voice."
  (interactive) (emacsvox-aural-voice-bulk--preview 'original))
(defun emacsvox-aural-voice-bulk-compare ()
  "Compare the original and proposed named voice without saving."
  (interactive) (emacsvox-aural-voice-bulk--preview 'compare))
(defun emacsvox-aural-voice-bulk-examples ()
  "Compare representative original and proposed named voices."
  (interactive) (emacsvox-aural-voice-bulk--preview 'compare t))

(defun emacsvox-aural-voice-bulk-details ()
  "Show scope, fallback tuning, playback evidence and save status."
  (interactive)
  (let* ((context emacsvox-aural-voice-editor--context)
         (name (tabulated-list-get-id))
         (row (cl-find name (plist-get context :rows) :key (lambda (item) (plist-get item :name))))
         (summary (emacsvox-aural-voice-bulk--summary))
         (impact (when (eq (plist-get context :source) (plist-get context :destination))
                   (delete-dups
                    (mapcan (lambda (item)
                              (emacsvox-aural-voice-palettes--edit-impact
                               (plist-get context :destination) (plist-get item :name)))
                            (plist-get context :rows))))))
    (emacsvox-aural-ui-with-help-window
      (princ summary)
      (princ "\n\nShared settings and all remaining fallbacks are preserved.\nInherited entries become local. Later named-voice edits are independent.\nNew standard names can still be inherited. Startup selection is separate.\n")
      (princ (format "\nSource: %s\nDestination: %s\nAffected descendants: %s\n"
                     (plist-get context :source) (plist-get context :destination) (or impact "none")))
      (when row
        (princ (format "\n%s — known uses: %s\nOriginal choices:\n%S\nProposed choices:\n%S\n"
                       name (or (emacsvox-aural-voice-palettes--known-uses name) "none")
                       (plist-get (plist-get row :original) :choices)
                       (plist-get (plist-get row :proposed) :choices))))
      (when-let* ((result (plist-get context :preview-result)))
        (princ (concat "\n" (emacsvox-aural-voice-editor--preview-status result) "\n")))
      (when-let* ((proposal (emacsvox-aural-voice-draft-proposal (plist-get context :draft))))
        (princ (format "\nSave/application details: %S\n" (emacsvox-aural-voice-save-result proposal)))))))

(defun emacsvox-aural-voice-bulk-resolve ()
  "Open an unfinished draft that conflicts with this review."
  (interactive)
  (let* ((drafts (emacsvox-aural-voice-bulk--conflicts emacsvox-aural-voice-editor--context))
         (choices (mapcar (lambda (draft) (cons (format "%S" (emacsvox-aural-voice-draft-key draft)) draft)) drafts)))
    (unless choices (user-error "No conflicting voice drafts"))
    (let* ((draft (cdr (assoc (completing-read "Resolve draft: " choices nil t) choices)))
           (key (emacsvox-aural-voice-draft-key draft))
           (context (gethash key emacsvox-aural-voice-editor--contexts)))
      (emacsvox-aural-voice-bulk-stop)
      (cond (context (emacsvox-aural-voice-editor--show context (current-buffer)))
            ((setq context (gethash key emacsvox-aural-voice-bulk--contexts))
             (emacsvox-aural-voice-bulk--show context))
            (t (user-error "Finish the existing %S operation in its original editor" key))))))

(defun emacsvox-aural-voice-bulk--refresh-editors (context)
  "Refresh clean base editors after CONTEXT has published its palette."
  (let ((scopes (cons (plist-get context :destination)
                      (emacsvox-aural-voice-palettes--descendants (plist-get context :destination)))))
    (maphash
     (lambda (key editor)
       (when (and (eq (car key) 'base) (memq (cadr key) scopes))
         (let ((draft (plist-get editor :draft)))
           (unless (emacsvox-aural-voice-drafts--dirty-fields draft)
             (let* ((opened (emacsvox-aural-voice-editing--snapshot (cadr key) (nth 2 key)))
                    (snapshot (emacsvox-aural-voice-editing--freeze (plist-get opened :snapshot) (cadr key))))
               (emacsvox-aural-voice-editor--invalidate editor)
               (setf (emacsvox-aural-voice-draft-baseline draft) (copy-tree snapshot)
                     (emacsvox-aural-voice-draft-working draft) (copy-tree snapshot)
                     (emacsvox-aural-voice-draft-original draft) (copy-tree snapshot)
                     (emacsvox-aural-voice-draft-history draft) nil
                     (emacsvox-aural-voice-draft-proposal draft) nil
                     (emacsvox-aural-voice-draft-watches draft) (emacsvox-aural-voice-drafts--watch (list (cadr key))))
               (emacsvox-aural-voice-editor--context-put editor :owner (plist-get opened :owner))
               (emacsvox-aural-voice-drafts--changed draft))))))
     emacsvox-aural-voice-editor--contexts)))

(defun emacsvox-aural-voice-bulk--save (select)
  "Save the entire reviewed palette, applying it when SELECT is non-nil."
  (let* ((context emacsvox-aural-voice-editor--context)
         (draft (plist-get context :draft))
         (proposal (emacsvox-aural-voice-draft-proposal draft)))
    (when (plist-get context :blocked)
      (user-error "Resolve unfinished drafts with r, then refresh with g"))
    (emacsvox-aural-voice-bulk-stop)
    (unless proposal
      (emacsvox-aural-voice-bulk--check context)
      (unless (equal (plist-get context :files) (emacsvox-aural-voice-bulk--files))
        (user-error "Saved files changed; refresh and review again"))
      (let ((data (plist-get context :data)))
        (setq proposal (emacsvox-aural-voice-drafts--prepare
                        draft (plist-get data :palette) (plist-get data :choice-sets)
                        :select select :sources (list (plist-get context :source))
                        :check (lambda () (emacsvox-aural-voice-bulk--check context))))))
    (unless (eq (not (null select)) (not (null (emacsvox-aural-voice-save-select proposal))))
      (user-error "Retry the original save action; use the palette manager for later selection"))
    (emacsvox-aural-voice-drafts--save proposal)
    (when (and (memq 'published (emacsvox-aural-voice-save-completed proposal))
               (not (plist-get context :published)))
      (emacsvox-aural-voice-editor--context-put context :published t)
      (emacsvox-aural-voice-bulk--refresh-editors context))
    (emacsvox-aural-voice-bulk--render)
    (emacsvox-aural-ui-speak (plist-get (emacsvox-aural-voice-drafts--status draft) :label))))

(defun emacsvox-aural-voice-bulk-save ()
  "Save all reviewed voices and apply the palette to both speech streams."
  (interactive) (emacsvox-aural-voice-bulk--save t))
(defun emacsvox-aural-voice-bulk-collect ()
  "Save all reviewed voices without selecting or applying the palette."
  (interactive) (emacsvox-aural-voice-bulk--save nil))

(defun emacsvox-aural-voice-bulk-refresh ()
  "Rebuild the unsaved review from current saved inputs."
  (interactive)
  (let* ((draft (emacsvox-aural-voice-bulk--get :draft))
         (proposal (emacsvox-aural-voice-draft-proposal draft)))
    (when (and proposal (or (emacsvox-aural-voice-save-completed proposal)
                            (memq (emacsvox-aural-voice-save-state proposal) '(saving applying))))
      (user-error "This review has begun saving; retry its save or start a new review"))
    (emacsvox-aural-voice-bulk--build emacsvox-aural-voice-editor--context)
    (emacsvox-aural-voice-bulk--render)
    (emacsvox-aural-voice-bulk--opening)))

(defun emacsvox-aural-voice-bulk-back ()
  "Return to the browser, retaining this review and any save recovery."
  (interactive)
  (emacsvox-aural-voice-bulk-stop)
  (let ((origin (emacsvox-aural-voice-bulk--get :origin)))
    (if (and (markerp origin) (marker-buffer origin))
        (progn (pop-to-buffer (marker-buffer origin)) (goto-char origin))
      (quit-window))))

(defun emacsvox-aural-voice-bulk-cancel ()
  "Discard an unsaved review without changing its source or destination."
  (interactive)
  (let* ((context emacsvox-aural-voice-editor--context)
         (draft (plist-get context :draft))
         (proposal (emacsvox-aural-voice-draft-proposal draft))
         (buffer (current-buffer)))
    (when (and proposal (or (emacsvox-aural-voice-save-completed proposal)
                            (memq (emacsvox-aural-voice-save-state proposal) '(saving applying))))
      (user-error "Saving has begun; q retains the result and recovery, without undoing saved changes"))
    (emacsvox-aural-voice-bulk-back)
    (remhash (emacsvox-aural-voice-draft-key draft) emacsvox-aural-voice-bulk--contexts)
    (remhash (emacsvox-aural-voice-draft-key draft) emacsvox-aural-voice-drafts--registry)
    (kill-buffer buffer)))

(defun emacsvox-aural-voice-bulk-close-result ()
  "Close a saved result without undoing its data or changing live selection."
  (interactive)
  (let* ((context emacsvox-aural-voice-editor--context)
         (draft (plist-get context :draft))
         (proposal (emacsvox-aural-voice-draft-proposal draft))
         (buffer (current-buffer)))
    (unless (and proposal (memq 'published (emacsvox-aural-voice-save-completed proposal))
                 (not (memq (emacsvox-aural-voice-save-state proposal) '(saving applying))))
      (user-error "Finish saving and wait for application before closing the result"))
    (emacsvox-aural-voice-bulk-back)
    (setf (emacsvox-aural-voice-draft-proposal draft) nil)
    (let ((key (emacsvox-aural-voice-draft-key draft)))
      (when (eq context (gethash key emacsvox-aural-voice-bulk--contexts))
        (remhash key emacsvox-aural-voice-bulk--contexts))
      (when (eq draft (gethash key emacsvox-aural-voice-drafts--registry))
        (remhash key emacsvox-aural-voice-drafts--registry)))
    (kill-buffer buffer)))

(defvar emacsvox-aural-voice-bulk-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map emacsvox-aural-tabulated-mode-map)
    (dolist (binding '(("P" . emacsvox-aural-voice-bulk-play)
                       ("O" . emacsvox-aural-voice-bulk-original)
                       ("B" . emacsvox-aural-voice-bulk-compare)
                       ("A" . emacsvox-aural-voice-bulk-examples)
                       ("S" . emacsvox-aural-voice-bulk-stop)
                       ("x" . emacsvox-aural-voice-bulk-details)
                       ("w" . emacsvox-aural-voice-bulk-save)
                       ("c" . emacsvox-aural-voice-bulk-collect)
                       ("g" . emacsvox-aural-voice-bulk-refresh)
                       ("r" . emacsvox-aural-voice-bulk-resolve)
                       ("q" . emacsvox-aural-voice-bulk-back)
                       ("C-c C-c" . emacsvox-aural-voice-bulk-save)
                       ("C-c C-k" . emacsvox-aural-voice-bulk-cancel)))
      (define-key map (kbd (car binding)) (cdr binding)))
    map))

(define-derived-mode emacsvox-aural-voice-bulk-mode emacsvox-aural-tabulated-mode "Palette-Voice-Review"
  "Review a physical voice across every named voice before saving."
  (emacsvox-aural-ui-configure-tabulated "palette voice review"
                                        #'emacsvox-aural-voice-bulk-speak
                                        #'emacsvox-aural-voice-bulk-refresh
                                        #'emacsvox-aural-voice-bulk-speak)
  (setq tabulated-list-format [("Named voice" 24 nil) ("Source" 20 nil) ("Proposed change" 40 nil)]
        tabulated-list-sort-key nil)
  (setq-local emacsvox-aural-ui-extra-actions
              '(("Play original" . emacsvox-aural-voice-bulk-original)
                ("Play proposed" . emacsvox-aural-voice-bulk-play)
                ("Compare" . emacsvox-aural-voice-bulk-compare)
                ("Compare examples" . emacsvox-aural-voice-bulk-examples)
                ("Stop preview" . emacsvox-aural-voice-bulk-stop)
                ("Review details" . emacsvox-aural-voice-bulk-details)
                ("Save and apply" . emacsvox-aural-voice-bulk-save)
                ("Save to collection" . emacsvox-aural-voice-bulk-collect)
                ("Resolve drafts" . emacsvox-aural-voice-bulk-resolve)
                ("Back; retain review" . emacsvox-aural-voice-bulk-back)
                ("Close saved result" . emacsvox-aural-voice-bulk-close-result)
                ("Cancel without saving" . emacsvox-aural-voice-bulk-cancel)))
  (add-hook 'kill-buffer-hook #'emacsvox-aural-voice-bulk-stop nil t)
  (add-hook 'change-major-mode-hook #'emacsvox-aural-voice-bulk-stop nil t)
  (tabulated-list-init-header))

(defun emacsvox-aural-voice-bulk--show (context)
  "Show or restore CONTEXT without rebuilding its immutable proposal."
  (let ((buffer (or (and (buffer-live-p (plist-get context :buffer)) (plist-get context :buffer))
                    (generate-new-buffer (format "*Palette voice review: %s*" (plist-get context :destination))))))
    (emacsvox-aural-voice-editor--context-put context :buffer buffer)
    (with-current-buffer buffer
      (unless (derived-mode-p 'emacsvox-aural-voice-bulk-mode) (emacsvox-aural-voice-bulk-mode))
      (setq emacsvox-aural-voice-editor--context context)
      (emacsvox-aural-voice-bulk--render))
    (emacsvox-aural-ui--pop-to-buffer buffer #'emacsvox-aural-voice-bulk--opening)
    buffer))

(defun emacsvox-aural-voice-bulk--open (source destination selector label origin)
  "Review SOURCE in DESTINATION using SELECTOR and LABEL, returning to ORIGIN."
  (let* ((key (list 'bulk source destination selector))
         (old (gethash key emacsvox-aural-voice-bulk--contexts))
         (previous (and old (emacsvox-aural-voice-draft-proposal (plist-get old :draft)))))
    (when (and previous (memq (emacsvox-aural-voice-save-state previous) '(saved applied superseded)))
      (setq old nil))
    (if old (emacsvox-aural-voice-bulk--show old)
      (let* ((draft (emacsvox-aural-voice-drafts--make :key key))
             (context (list :draft draft :source source :destination destination :selector (copy-tree selector)
                            :label label :origin (with-current-buffer origin (copy-marker (point)))
                            :buffer nil :preview-result nil :preview-generation 0
                            :refresh #'emacsvox-aural-voice-bulk--render
                            :text emacsvox-aural-voice-workbench-preview-text)))
        (if (emacsvox-aural-voice-bulk--conflicts context)
            (emacsvox-aural-voice-editor--context-put context :blocked t)
          (emacsvox-aural-voice-bulk--build context))
        (puthash key draft emacsvox-aural-voice-drafts--registry)
        (puthash key context emacsvox-aural-voice-bulk--contexts)
        (emacsvox-aural-voice-bulk--show context)))))

(defun emacsvox-aural-voice-bulk-open (pair &optional origin)
  "Choose a palette destination and review physical PAIR across all its voices.
ORIGIN is the browser to return to.  Opening or previewing writes nothing."
  (let* ((origin (or origin (current-buffer)))
         (selector (list :kind 'exact :scope 'local :engine-id (plist-get (car pair) :engine-id)
                         :voice-id (plist-get (cadr pair) :voice-id)))
         (action (completing-read "Use voice across: "
                                  '("Update an existing personal palette" "Create a new personal palette") nil t))
         (copy (equal action "Create a new personal palette"))
         (ids (cl-remove-if (lambda (id)
                              (and (not copy) (emacsvox-aural-voice-palette-built-in
                                               (gethash id emacsvox-aural-voice-palette-registry))))
                            (hash-table-keys emacsvox-aural-voice-palette-registry))))
    (unless ids (user-error "No personal palettes; choose Create a new personal palette"))
    (let* ((source (intern (completing-read (if copy "Copy voices and adjustments from: " "Update palette: ")
                                           (mapcar #'symbol-name ids) nil t nil nil
                                           (when (memq (emacsvox-aural-effective-voice-palette) ids)
                                             (symbol-name (emacsvox-aural-effective-voice-palette))))))
           (destination (if copy (emacsvox-aural-voice-palettes--read-new-id (format "%s-copy" source)) source)))
      (emacsvox-aural-voice-bulk--open source destination selector
                                     (emacsvox-aural-voice-workbench--pair-name pair) origin))))

;;;###autoload
(defun emacsvox-aural-voice-bulk-resume ()
  "Resume a retained palette voice review or incomplete save."
  (interactive)
  (let (choices)
    (maphash (lambda (_ context)
               (push (cons (format "%s to %s: %s" (plist-get context :source)
                                   (plist-get context :destination) (plist-get context :label)) context) choices))
             emacsvox-aural-voice-bulk--contexts)
    (unless choices (user-error "No retained palette voice reviews"))
    (emacsvox-aural-voice-bulk--show
     (cdr (assoc (completing-read "Resume review: " choices nil t) choices)))))

(defun emacsvox-aural-voice-bulk--changed (draft)
  "Refresh bulk views of DRAFT and announce completed application."
  (maphash
   (lambda (_ context)
     (when (eq draft (plist-get context :draft))
       (emacsvox-aural-voice-editor--invalidate context)
       (when (buffer-live-p (plist-get context :buffer))
         (with-current-buffer (plist-get context :buffer) (emacsvox-aural-voice-bulk--render)))
       (when-let* ((proposal (emacsvox-aural-voice-draft-proposal draft)))
         (let ((state (cons (emacsvox-aural-voice-save-operation proposal)
                            (emacsvox-aural-voice-save-state proposal))))
           (when (and (memq (cdr state) '(applied apply-failed superseded))
                      (not (equal state (plist-get context :announced))))
             (emacsvox-aural-voice-editor--context-put context :announced state)
             (tts-notify (plist-get (emacsvox-aural-voice-drafts--status draft) :label)))))))
   emacsvox-aural-voice-bulk--contexts))
(add-hook 'emacsvox-aural-voice-drafts--changed-hook #'emacsvox-aural-voice-bulk--changed)

(provide 'emacsvox-aural-voice-bulk)
;;; emacsvox-aural-voice-bulk.el ends here
