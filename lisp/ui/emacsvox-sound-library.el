;;; emacsvox-sound-library.el --- Recordings and explicit cue assignments -*- lexical-binding: t; -*-

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
;; Audio files in the library are candidates, not semantic cues. Explicit
;; assignment copies immutable audio into a pack before publishing its manifest.
;; Browsing and preview do not assign, activate a pack, or persist settings.
;;; Code:
(require 'emacsvox-aural-sound-packs)

(autoload 'emacsvox-aural-menu-library-preview "emacsvox-aural-menu" nil t)

(defcustom emacsvox-sound-library-preview-timing 'alongside
  "Automatic recording previews when moving between library rows.
Off announces the row without playing its recording. Before finishes the
recording before the announcement; alongside overlaps them; after plays the
recording when the announcement finishes. Before and after require an Omnivox
structured timeline. The choice applies to all library buffers. Space and P
still replay a recording explicitly when automatic preview is off."
  :type '(choice (const :tag "Off" off)
                 (const :tag "Before announcement" before)
                 (const :tag "Alongside announcement" alongside)
                 (const :tag "After announcement" after))
  :group 'emacsvox-aural)

(defcustom emacsvox-sound-library-directory
  (expand-file-name "~/.emacsvox/sounds/library/")
  "Directory of candidate recordings, separate from sound-pack cue assignments.
Put Ogg, WAV, MP3 or FLAC files here or in collection subdirectories, then
Rescan the library. Playback support depends on the audio backend. Import
copies files here without changing any cue. Assigned packs own their audio."
  :type 'directory :group 'emacsvox-aural)

(defconst emacsvox-sound-library--extensions "\\.\\(ogg\\|wav\\|mp3\\|flac\\)\\'"
  "Recording formats offered by the library.")
(defvar emacsvox-sound-library--cache (make-hash-table :test #'equal)
  "File attributes and measured metadata, invalidated by file changes.")
(defvar-local emacsvox-sound-library--recordings nil)
(defvar-local emacsvox-sound-library--filter "")
(defvar-local emacsvox-sound-library--unassigned nil)
(defvar-local emacsvox-sound-library--target nil
  "Captured pack, current cue, manifest identity and pending cue assignments.")

(defun emacsvox-sound-library--duration (file)
  "Return FILE's duration in seconds when ffprobe is available, otherwise nil."
  (when (executable-find "ffprobe")
    (with-temp-buffer
      (when (zerop (call-process "ffprobe" nil (list t nil) nil
                                 "-v" "error" "-show_entries" "format=duration"
                                 "-of" "default=noprint_wrappers=1:nokey=1" "-i" file))
        (let ((text (string-trim (buffer-string))))
          (when (string-match-p "\\`[0-9]+\\(?:\\.[0-9]+\\)?\\'" text)
            (string-to-number text)))))))

(defun emacsvox-sound-library--scan ()
  "Read candidate recordings without creating cues or writing metadata."
  (let ((root (expand-file-name emacsvox-sound-library-directory))
        (seen (make-hash-table :test #'equal)) result)
    (when (file-directory-p root)
      (dolist (file (sort (directory-files-recursively
                           root emacsvox-sound-library--extensions nil
                           (lambda (dir) (not (string-prefix-p "." (file-name-nondirectory dir)))))
                          #'string-lessp))
        (when (and (file-regular-p file) (file-readable-p file)
                   (file-in-directory-p (file-truename file) (file-truename root)))
          (let* ((attrs (file-attributes file))
                 (stamp (list (file-attribute-size attrs) (file-attribute-modification-time attrs)
                              (file-attribute-status-change-time attrs)))
                 (old (gethash file emacsvox-sound-library--cache))
                 (metadata (if (equal stamp (car old)) (cdr old)
                             (list (emacsvox-aural--recording-digest file)
                                   (emacsvox-sound-library--duration file))))
                 (id (car metadata))
                 (relative (file-relative-name file root))
                 (collection (or (file-name-directory relative) "Unfiled/")))
            (puthash file (cons stamp metadata) emacsvox-sound-library--cache)
            (unless (gethash id seen)
              (puthash id t seen)
              (push (list :id id :file file :name (emacsvox-aural-humanize (file-name-base file))
                          :collection (directory-file-name collection) :duration (cadr metadata)) result))))))
    (nreverse result)))

(defun emacsvox-sound-library--uses (id)
  "Return known direct pack/cue assignments for recording ID."
  (let (uses)
    (maphash
     (lambda (pack-id pack)
       (dolist (entry (emacsvox-aural-resource-pack-assignments pack))
         (when (and (listp (cdr entry)) (equal id (plist-get (cdr entry) :recording)))
           (push (format "%s / %s" pack-id (car entry)) uses))))
     emacsvox-aural-resource-pack-registry)
    (sort uses #'string-lessp)))

(defun emacsvox-sound-library--recording ()
  "Return the recording at point, reporting an empty or stale selection."
  (or (cl-find (tabulated-list-get-id) emacsvox-sound-library--recordings
               :key (lambda (r) (plist-get r :id)) :test #'equal)
      (user-error "Move to a recording first")))

(defun emacsvox-sound-library--manifest-id (pack)
  "Return the current manifest byte identity of PACK, or nil if absent."
  (let ((file (expand-file-name emacsvox-aural-resource-pack-manifest
                                (emacsvox-aural-resource-pack-directory pack))))
    (when (file-exists-p file) (emacsvox-aural--recording-digest file))))

(defun emacsvox-sound-library--capture (pack-id cue)
  "Capture a writable PACK-ID and semantic CUE for private comparison."
  (emacsvox-aural-refresh-discovered-resource-packs)
  (let ((pack (emacsvox-aural-resource-pack pack-id)))
    (unless (and pack (eq (emacsvox-aural-resource-pack-origin pack) 'discovered)
                 (file-writable-p (emacsvox-aural-resource-pack-directory pack)))
      (user-error "Choose a writable personal sound pack"))
    (unless (emacsvox-aural-cue cue) (user-error "Choose a registered semantic cue"))
    (list :pack pack-id :cue cue :directory (emacsvox-aural-resource-pack-directory pack)
          :manifest (emacsvox-sound-library--manifest-id pack) :drafts nil)))

(defun emacsvox-sound-library--put-draft (target draft)
  "Queue DRAFT for TARGET's current cue, replacing only that cue's proposal."
  (setf (alist-get (plist-get target :cue) (plist-get target :drafts)) draft))

(defun emacsvox-sound-library--pending-uses (id)
  "Return pending pack/cue assignments for recording ID in this buffer."
  (let ((target emacsvox-sound-library--target))
    (sort (cl-loop for (cue . draft) in (plist-get target :drafts)
                   when (and (listp draft) (equal id (plist-get draft :id)))
                   collect (format "%s / %s" (plist-get target :pack) cue))
          #'string-lessp)))

(defun emacsvox-sound-library--status (id)
  "Describe saved and pending assignments for recording ID."
  (let ((saved (emacsvox-sound-library--uses id))
        (pending (emacsvox-sound-library--pending-uses id)))
    (if (or saved pending)
        (string-join
         (append (when pending (list (concat "Pending: " (string-join pending ", "))))
                 (when saved (list (concat "Saved: " (string-join saved ", ")))))
         "; ")
      "Unassigned")))

(defun emacsvox-sound-library--commit (target)
  "Save all TARGET's pending assignments without changing the active pack.
Copy immutable audio first, then publish one manifest for the whole batch.
Failure leaves previous assignments effective and all proposals pending;
unreferenced immutable copies are harmless and reusable."
  (let* ((pack-id (plist-get target :pack))
         (pack (emacsvox-aural-resource-pack pack-id))
         (drafts (plist-get target :drafts)))
    (unless drafts (user-error "Select a recording or Reset to parent first"))
    (unless (and pack (eq (emacsvox-aural-resource-pack-origin pack) 'discovered)
                 (equal (plist-get target :directory) (emacsvox-aural-resource-pack-directory pack))
                 (equal (plist-get target :manifest) (emacsvox-sound-library--manifest-id pack)))
      (user-error "Sound pack changed; reopen the assignment before saving"))
    (let* ((directory (emacsvox-aural-resource-pack-directory pack))
           (data (list :summary (emacsvox-aural-resource-pack-summary pack)
                       :parent (emacsvox-aural-resource-pack-parent pack)
                       :profiles (emacsvox-aural-resource-pack-profiles pack)
                       :default-spatialization (emacsvox-aural-resource-pack-default-spatialization pack)
                       :assignments (emacsvox-aural-resource-pack-assignments pack)))
           (assignments (copy-tree (plist-get data :assignments))))
      (dolist (entry drafts)
        (let ((draft (cdr entry)) (assignment 'inherit))
          (unless (eq draft 'inherit)
            (let* ((id (plist-get draft :id)) (file (plist-get draft :file))
                   (relative (format "recordings/assigned/%s.%s" id (downcase (file-name-extension file))))
                   (destination (expand-file-name relative directory)))
              (unless (and (file-regular-p file) (equal id (emacsvox-aural--recording-digest file)))
                (user-error "Candidate recording changed; rescan and select it again"))
              (unless (file-in-directory-p (file-truename (file-name-directory destination))
                                           (file-truename directory))
                (user-error "Assigned recordings directory is outside the sound pack"))
              (make-directory (file-name-directory destination) t)
              (if (file-exists-p destination)
                  (unless (equal id (emacsvox-aural--recording-digest destination))
                    (user-error "Pack recording was modified; original assignment retained"))
                (let ((temporary (make-temp-file (expand-file-name ".recording-" (file-name-directory destination)))))
                  (unwind-protect
                      (progn
                        (copy-file file temporary t t)
                        (unless (equal id (emacsvox-aural--recording-digest temporary))
                          (user-error "Recording changed during copy; assignment retained"))
                        (rename-file temporary destination nil))
                    (when (file-exists-p temporary) (delete-file temporary)))))
              (setq assignment (list :recording id :file relative :name (plist-get draft :name)))))
          (setf (alist-get (car entry) assignments) assignment)))
      (setq data (plist-put data :schema-version 2)
            data (plist-put data :assignments assignments))
      (emacsvox-aural--validate-pack-assignments assignments directory)
      ;; Recheck after copying: another editor may have saved during preparation.
      (unless (equal (plist-get target :manifest) (emacsvox-sound-library--manifest-id pack))
        (user-error "Sound pack changed while copying; reopen the assignment"))
      (emacsvox-aural-sound-packs--write-manifest pack data)
      (setf (plist-get target :manifest) (emacsvox-sound-library--manifest-id pack)
            (plist-get target :drafts) nil)
      (emacsvox-aural-resource-pack pack-id))))

(defun emacsvox-sound-library--set-entries ()
  "Populate recordings with known assignments and the current search filter."
  (emacsvox-aural-refresh-discovered-resource-packs)
  (setq emacsvox-sound-library--recordings (emacsvox-sound-library--scan)
        tabulated-list-entries
        (cl-loop for r in emacsvox-sound-library--recordings
                 for uses = (emacsvox-sound-library--uses (plist-get r :id))
                 when (and (or (not emacsvox-sound-library--unassigned) (null uses)
                               (emacsvox-sound-library--pending-uses (plist-get r :id)))
                           (string-match-p
                            (regexp-quote (downcase emacsvox-sound-library--filter))
                            (downcase (concat (plist-get r :name) " " (plist-get r :collection)))))
                 collect
                 (list (plist-get r :id)
                       (vector (plist-get r :name) (plist-get r :collection)
                               (if (numberp (plist-get r :duration))
                                   (format "%.3f s" (plist-get r :duration)) "unknown")
                               (emacsvox-sound-library--status (plist-get r :id))))))
  (setq header-line-format
        (concat (if emacsvox-sound-library--target
                    (format "Assign %s / %s. %d pending. Up/Down browse, RET select, a another cue, SPC replay, C current, W save all, q discard."
                            (plist-get emacsvox-sound-library--target :pack)
                            (plist-get emacsvox-sound-library--target :cue)
                            (length (plist-get emacsvox-sound-library--target :drafts)))
                  "Recording library. Up/Down browse, SPC replay, a assign, i import, / search, u unassigned, ? help.")
                (format " Preview: %s." emacsvox-sound-library-preview-timing)
                (unless (string-empty-p emacsvox-sound-library--filter)
                  (concat " Filter: " emacsvox-sound-library--filter)))))

(defun emacsvox-sound-library-refresh ()
  "Rescan candidates and assignments without applying or saving anything."
  (interactive)
  (emacsvox-aural-ui-refresh-tabulated #'emacsvox-sound-library--set-entries))

(defun emacsvox-sound-library-speak-current ()
  "Speak the recording's name, collection, duration and known assignments."
  (interactive)
  (if (not (tabulated-list-get-id)) (emacsvox-aural-ui-speak "No matching recordings")
    (let ((r (emacsvox-sound-library--recording)))
      (emacsvox-aural-ui-speak
       (format "%s. %s. %s. %s."
               (plist-get r :name) (plist-get r :collection)
               (if (numberp (plist-get r :duration)) (format "%.3f seconds" (plist-get r :duration)) "Duration unknown")
               (emacsvox-sound-library--status (plist-get r :id)))))))

(defun emacsvox-sound-library-preview ()
  "Preview the selected recording without changing any cue or pack."
  (interactive)
  (let ((r (emacsvox-sound-library--recording)))
    (emacsvox-aural-preview-play-cue (plist-get r :file) (concat "recording-" (plist-get r :id)))))

(defun emacsvox-sound-library--navigation-plan (text)
  "Build one cancellable recording and announcement sequence for TEXT."
  (let* ((r (emacsvox-sound-library--recording))
         (timing emacsvox-sound-library-preview-timing)
         (action (emacsvox-aural--make-concrete-action
                  :id 'library-preview :kind 'cue
                  :resource (plist-get r :file)
                  :sample-id (concat "recording-" (plist-get r :id))
                  :audio-mode (if (eq timing 'before) 'insert 'overlay))))
    (emacsvox-aural-preview--prepare-plan
     (emacsvox-aural--make-concrete-plan
      :before (unless (eq timing 'after) (list action))
      :content (emacsvox-aural--make-concrete-content :text text :speak t)
      :after (when (eq timing 'after) (list action))
      :context '(:icons-enabled t)))))

(defun emacsvox-sound-library--move-row (direction)
  "Move in DIRECTION and present the row with its configured recording preview."
  ;; Capture the shared navigator's feedback so it can join the recording in
  ;; one timeline. Boundaries retain their normal announcement without audio.
  (let (text row)
    (let ((emacsvox-aural-ui-speech-function (lambda (value) (setq text value))))
      (setq row (emacsvox-aural-ui-move-row direction)))
    (cond
     ((or (not row) (eq emacsvox-sound-library-preview-timing 'off))
      (emacsvox-aural-preview-stop)
      (emacsvox-aural-ui-speak text))
     ((emacsvox-aural-preview-structured-style-supported-p)
      (emacsvox-aural-preview-play-plan
       (emacsvox-sound-library--navigation-plan text)))
     ((eq emacsvox-sound-library-preview-timing 'alongside)
      (emacsvox-aural-preview-stop)
      (emacsvox-aural-ui-speak text)
      (let ((r (emacsvox-sound-library--recording)))
        (emacsvox-sounds-play-concrete-cue
         (plist-get r :file) (concat "recording-" (plist-get r :id)))))
     (t
      (emacsvox-aural-preview-stop)
      (emacsvox-aural-ui-speak text)
      (user-error "Before/after library previews require an Omnivox structured timeline; choose Alongside or Off")))))

(defun emacsvox-sound-library-next ()
  "Move to the next recording and use the Library preview setting."
  (interactive)
  (emacsvox-sound-library--move-row 1))

(defun emacsvox-sound-library-previous ()
  "Move to the previous recording and use the Library preview setting."
  (interactive)
  (emacsvox-sound-library--move-row -1))

(defun emacsvox-sound-library-current ()
  "Preview the currently assigned cue in the captured target pack."
  (interactive)
  (unless emacsvox-sound-library--target (user-error "Choose Assign to cue first"))
  (emacsvox-aural-sound-packs--audition
   (plist-get emacsvox-sound-library--target :pack) (plist-get emacsvox-sound-library--target :cue)))

(defun emacsvox-sound-library-select ()
  "Queue this recording for the current cue; W saves all pending assignments.
Browsing and selecting do not change saved cue assignments.
SPC replays the candidate; C compares the saved cue.
a chooses another cue; q discards all proposals."
  (interactive)
  (unless emacsvox-sound-library--target (user-error "Press a to choose a pack and cue first"))
  (let ((r (copy-tree (emacsvox-sound-library--recording))))
    (emacsvox-sound-library--put-draft emacsvox-sound-library--target r)
    (emacsvox-sound-library-refresh)
    (emacsvox-aural-ui-speak (format "%s pending for %s. %d pending. W saves all"
                                     (plist-get r :name)
                                     (plist-get emacsvox-sound-library--target :cue)
                                     (length (plist-get emacsvox-sound-library--target :drafts))))))

(defun emacsvox-sound-library-reset ()
  "Prepare removal of the local cue assignment, revealing its parent or fallback.
Original audio stays intact. W saves all pending changes; q discards them."
  (interactive)
  (unless emacsvox-sound-library--target (user-error "Choose Assign to cue first"))
  (emacsvox-sound-library--put-draft emacsvox-sound-library--target 'inherit)
  (emacsvox-sound-library-refresh)
  (emacsvox-aural-ui-speak "Reset to parent pending. W saves all; q discards all"))

(defun emacsvox-sound-library-save ()
  "Save and apply all pending assignments to their captured pack.
An inactive pack stays inactive. Assigned audio is copied into the pack;
removing or renaming the library source cannot break that saved sound."
  (interactive)
  (unless emacsvox-sound-library--target (user-error "Choose Assign to cue first"))
  (let ((count (length (plist-get emacsvox-sound-library--target :drafts))))
    (emacsvox-sound-library--commit emacsvox-sound-library--target)
    (emacsvox-sound-library-refresh)
    (emacsvox-aural-ui-speak
     (format "Saved %d assignments in %s. %s"
             count (plist-get emacsvox-sound-library--target :pack)
             (if (eq (plist-get emacsvox-sound-library--target :pack) emacsvox-sounds-current-pack)
                 "Active pack updated" "Pack remains inactive")))))

(defun emacsvox-sound-library-search (text)
  "Filter recording names and collections by case-insensitive substring TEXT."
  (interactive (list (read-string "Recording or collection (empty for all): " emacsvox-sound-library--filter)))
  (setq emacsvox-sound-library--filter text)
  (emacsvox-sound-library-refresh)
  (emacsvox-sound-library-speak-current))

(defun emacsvox-sound-library-unassigned ()
  "Toggle recordings without saved assignments, keeping pending rows visible."
  (interactive)
  (setq emacsvox-sound-library--unassigned (not emacsvox-sound-library--unassigned))
  (emacsvox-sound-library-refresh)
  (emacsvox-aural-ui-speak (if emacsvox-sound-library--unassigned "Unassigned recordings" "All recordings")))

(defun emacsvox-sound-library-import (file collection)
  "Copy audio FILE to COLLECTION without assigning a cue or removing its source."
  (interactive (list (read-file-name "Import recording: " nil nil t)
                     (read-string "Collection: " "Imported")))
  (unless (and (file-regular-p file) (string-match-p emacsvox-sound-library--extensions file))
    (user-error "Choose an Ogg, WAV, MP3 or FLAC recording"))
  (unless (and (not (string-empty-p (string-trim collection)))
               (not (string-prefix-p "." collection))
               (not (string-match-p "[/\\\\]" collection)))
    (user-error "Use a collection name without directory separators or a leading dot"))
  (let* ((directory (expand-file-name collection emacsvox-sound-library-directory))
         (destination (expand-file-name (file-name-nondirectory file) directory)))
    (make-directory emacsvox-sound-library-directory t)
    (unless (file-in-directory-p (file-truename directory) (file-truename emacsvox-sound-library-directory))
      (user-error "Collection directory is outside the sound library"))
    (make-directory directory t)
    (if (file-exists-p destination)
        (unless (equal (emacsvox-aural--recording-digest file) (emacsvox-aural--recording-digest destination))
          (user-error "A different recording already has that name; choose another collection"))
      (copy-file file destination nil t))
    (when (derived-mode-p 'emacsvox-sound-library-mode) (emacsvox-sound-library-refresh))
    (message "Imported recording; no cue assigned")
    destination))

(defun emacsvox-sound-library-open-directory ()
  "Open the candidate library directory for adding or organising recordings."
  (interactive)
  (make-directory emacsvox-sound-library-directory t)
  (dired emacsvox-sound-library-directory))

(defun emacsvox-sound-library-delete ()
  "Delete this library file after confirmation, refusing known assignments.
Imported originals elsewhere and immutable pack copies remain untouched."
  (interactive)
  (emacsvox-aural-refresh-discovered-resource-packs)
  (let* ((r (emacsvox-sound-library--recording))
         (uses (append (emacsvox-sound-library--uses (plist-get r :id))
                       (emacsvox-sound-library--pending-uses (plist-get r :id)))))
    (when uses (user-error "Reassign or reset these cues first: %s" (string-join uses ", ")))
    (when (yes-or-no-p (format "Delete library recording %s? " (plist-get r :name)))
      (unless (and (file-in-directory-p (file-truename (plist-get r :file))
                                        (file-truename emacsvox-sound-library-directory))
                   (equal (plist-get r :id) (emacsvox-aural--recording-digest (plist-get r :file))))
        (user-error "Recording changed; rescan before deleting"))
      (delete-file (plist-get r :file) t)
      (emacsvox-sound-library-refresh))))

(defun emacsvox-sound-library-help ()
  "Explain available recordings, assignments, preview and explicit saving."
  (interactive)
  (emacsvox-aural-ui-with-help-window
   (princ (concat "Recording library\n\n"
                  "Recordings are available sounds, not events. Importing creates no cue.\n"
                  "Up/Down browse recordings without assigning them. Library preview\n"
                  "chooses Off, Before, Alongside or After the row announcement.\n"
                  "Open Library preview through C-c C-a Actions or Sounds and output.\n"
                  "Before and After require an Omnivox structured timeline. Save the\n"
                  "preference explicitly in that menu to keep it across restarts.\n"
                  "Left/Right read columns; / searches names and collections; u toggles Unassigned.\n"
                  "SPC or P replays the row; S stops. i imports a copy; o opens the library.\n"
                  "g rescans files; d deletes an unassigned library file after confirmation.\n"
                  "a chooses a personal pack and cue, then further cues in that same pack.\n"
                  "RET queues the row for the current cue; C previews its saved sound.\n"
                  "Pending rows show unsaved choices, including in the Unassigned filter.\n"
                  "R queues Reset to parent, retaining original audio. W saves all pending cues.\n"
                  "q discards all pending choices and returns. Reopen to choose another pack.\n"
                  "Saving an inactive pack does not activate it.\n"
                  "Assigned packs contain their own audio. Remote speech requires matching\n"
                  "workstation sound resources; this browser does not upload recordings.\n")))
  (when (fboundp 'emacsvox-speak-help) (emacsvox-speak-help)))

(defun emacsvox-sound-library--discard-on-dismiss ()
  "Clear pending assignments and return a spoken dismissal notice."
  (let ((count (length (plist-get emacsvox-sound-library--target :drafts))))
    (setq emacsvox-sound-library--target nil)
    (when (> count 0) (format "Discarded %d pending assignments" count))))

(define-derived-mode emacsvox-sound-library-mode emacsvox-aural-tabulated-mode
  "Sound-Library"
  "Browse available recordings and explicitly assign sounds to pack cues."
  (emacsvox-aural-ui-configure-tabulated "recording library" #'emacsvox-sound-library-speak-current
                                         #'emacsvox-sound-library-refresh)
  (setq tabulated-list-format [("Recording" 30 t) ("Collection" 26 t) ("Duration" 12 t) ("Assignments" 0 t)]
        tabulated-list-padding 2
        emacsvox-aural-ui-dismiss-warning-function #'emacsvox-sound-library--discard-on-dismiss
        emacsvox-aural-ui-extra-actions
        '(("Library preview: automatic playback and timing" . emacsvox-aural-menu-library-preview)))
  (tabulated-list-init-header))

(dolist (binding '(("RET" . emacsvox-sound-library-select) ("SPC" . emacsvox-sound-library-preview)
                   ("P" . emacsvox-sound-library-preview)
                   ("C" . emacsvox-sound-library-current) ("R" . emacsvox-sound-library-reset)
                   ("W" . emacsvox-sound-library-save) ("/" . emacsvox-sound-library-search)
                   ("u" . emacsvox-sound-library-unassigned) ("i" . emacsvox-sound-library-import)
                   ("o" . emacsvox-sound-library-open-directory) ("d" . emacsvox-sound-library-delete)
                   ("a" . emacsvox-sound-library-assign) ("?" . emacsvox-sound-library-help)))
  (keymap-set emacsvox-sound-library-mode-map (car binding) (cdr binding)))

(define-key emacsvox-sound-library-mode-map [remap emacsvox-aural-ui-next-row]
            #'emacsvox-sound-library-next)
(define-key emacsvox-sound-library-mode-map [remap emacsvox-aural-ui-previous-row]
            #'emacsvox-sound-library-previous)

;;;###autoload
(defun emacsvox-sound-library (&optional pack cue)
  "Browse available recordings, optionally proposing an assignment for PACK/CUE."
  (interactive)
  (let* ((source (emacsvox-aural-inspection-remember-source-buffer))
         (parent (current-buffer)) (row (tabulated-list-get-id))
         (target (and pack cue (emacsvox-sound-library--capture pack cue)))
         (buffer (get-buffer-create (if target (format "*Sound Library: %s*" pack) "*Sound Library*"))))
    (with-current-buffer buffer
      (unless (derived-mode-p 'emacsvox-sound-library-mode) (emacsvox-sound-library-mode))
      (if (plist-get emacsvox-sound-library--target :drafts)
          (when target
            (unless (eq pack (plist-get emacsvox-sound-library--target :pack))
              (user-error "Save or discard pending assignments before changing packs"))
            (setf (plist-get emacsvox-sound-library--target :cue) cue))
        (setq emacsvox-sound-library--target target))
      (emacsvox-aural-inspection-attach-source source)
      (unless (eq parent buffer)
        (setq emacsvox-aural-ui--return-function
              (lambda ()
                (when (buffer-live-p buffer)
                  (with-current-buffer buffer (setq emacsvox-sound-library--target nil)))
                (when (buffer-live-p parent)
                  (pop-to-buffer parent)
                  (when (derived-mode-p 'emacsvox-aural-sound-pack-cues-mode)
                    (emacsvox-aural-sound-pack-cues-refresh cue))
                  (when row (emacsvox-aural-ui-goto-row row))
                  t))))
      (emacsvox-sound-library-refresh))
    (emacsvox-aural-ui--pop-to-buffer
     buffer (lambda ()
              (emacsvox-aural-ui-speak
               (if target (format "Assign %s in %s. Browse, compare, then W to save" cue pack)
                 "Recording library. Available sounds; a assigns a cue"))
              (emacsvox-sound-library-speak-current)))
    buffer))

(defun emacsvox-sound-library--sort-choices (choices)
  "Return CHOICES alphabetically without changing the completion source."
  (sort (copy-sequence choices) #'string-lessp))

(defun emacsvox-sound-library--read-choice (prompt choices)
  "Read one of CHOICES with PROMPT in alphabetical display and cycling order."
  (completing-read
   prompt
   (lambda (string predicate action)
     (if (eq action 'metadata)
         '(metadata
           (display-sort-function . emacsvox-sound-library--sort-choices)
           (cycle-sort-function . emacsvox-sound-library--sort-choices))
       (complete-with-action action choices string predicate)))
   nil t))

(defun emacsvox-sound-library-assign ()
  "Queue the recording for a cue, keeping other pending choices in this buffer.
Choose a pack on the first assignment; further assignments use that pack.
W saves all pending cues together. q discards them; reopen to change packs."
  (interactive)
  (emacsvox-aural-refresh-discovered-resource-packs)
  (let* ((recording (and (derived-mode-p 'emacsvox-sound-library-mode)
                         (tabulated-list-get-id)
                         (copy-tree (emacsvox-sound-library--recording))))
         (packs (cl-remove-if-not
                 (lambda (id) (eq (emacsvox-aural-resource-pack-origin (emacsvox-aural-resource-pack (intern id))) 'discovered))
                 (emacsvox-aural-resource-pack-candidates 'sound)))
         (pack (or (plist-get emacsvox-sound-library--target :pack)
                   (intern (emacsvox-sound-library--read-choice "Assign in personal pack: " packs))))
         (cues (mapcar #'symbol-name (cl-remove-if-not #'emacsvox-aural-cue
                                                       (emacsvox-aural-sound-packs--cue-ids pack))))
         (cue (intern (emacsvox-sound-library--read-choice (format "Cue in %s: " pack) cues))))
    (if (derived-mode-p 'emacsvox-sound-library-mode)
        (if emacsvox-sound-library--target
            (setf (plist-get emacsvox-sound-library--target :cue) cue)
          (setq emacsvox-sound-library--target (emacsvox-sound-library--capture pack cue)))
      (emacsvox-sound-library pack cue))
    (when recording
      (emacsvox-sound-library--put-draft emacsvox-sound-library--target recording))
    (emacsvox-sound-library-refresh)
    (when recording (emacsvox-aural-ui-goto-row (plist-get recording :id)))
    (emacsvox-aural-ui-speak (format "%d pending. a adds another cue; W saves all; q discards all"
                                     (length (plist-get emacsvox-sound-library--target :drafts))))
    (emacsvox-sound-library-speak-current)))

(provide 'emacsvox-sound-library)
;;; emacsvox-sound-library.el ends here
