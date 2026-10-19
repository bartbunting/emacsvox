;;; emacsvox-aural-voice-workbench-library.el --- Voice workbench library integration -*- lexical-binding: t; -*-

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
;; Voice workbench library integration.
;; Load through `emacsvox-aural-voice-workbench'.

;;; Code:

(require 'emacsvox-aural-voice-workbench-views)
(require 'omnivox-library)

;; Workbench dependencies.
(defvar emacsvox-aural-voice-workbench--filter-counts)
(defvar emacsvox-aural-voice-workbench--quick-filter)
(defvar emacsvox-aural-voice-workbench--quick-filters)
(defvar emacsvox-aural-voice-workbench--voice-list-parent)
(defvar emacsvox-aural-voice-workbench-filter)
(defvar emacsvox-aural-voice-workbench-inventory)
(declare-function emacsvox-aural-voice-workbench-refresh
                  "emacsvox-aural-voice-workbench" (&optional id))
(defvar emacsvox-aural-voice-workbench-view)
;; End workbench dependencies.

(declare-function omnivox-voice-inventory "omnivox-inventory" ())
(defvar omnivox-engine-inventory)
(defvar omnivox--control-inventory-property)
(declare-function omnivox--send-control-request "omnivox-voices" (process request callback))
(declare-function omnivox--pending-requests "omnivox-voices" (process))
(declare-function omnivox--process-supports-p "omnivox-voices" (process feature))

(defvar-local emacsvox-aural-voice-workbench--library-source nil)

(defvar-local emacsvox-aural-voice-workbench--library-reply nil)

(defvar-local emacsvox-aural-voice-workbench--library-error nil)

(defvar-local emacsvox-aural-voice-workbench--library-cancel nil)

(defvar-local emacsvox-aural-voice-workbench--library-ticket nil)

(defvar-local emacsvox-aural-voice-workbench--library-lanes nil)

(defun emacsvox-aural-voice-workbench--library-p ()
  "Whether this view can show Omnivox library information."
  (and (eq emacsvox-aural-voice-workbench-view 'physical)
       (equal "omnivox" (plist-get emacsvox-aural-voice-workbench-inventory :adapter))))

(defvar emacsvox-aural-voice-workbench--index-snapshot 'uncaptured
  "Library metadata captured for one synchronous redraw or filter operation.")

(defun emacsvox-aural-voice-workbench--library-index ()
  "Return installed metadata only while its native target is selected."
  (if (not (eq emacsvox-aural-voice-workbench--index-snapshot 'uncaptured))
      emacsvox-aural-voice-workbench--index-snapshot
    (when (and emacsvox-aural-voice-workbench--library-source
               (equal emacsvox-aural-voice-workbench--library-source
                      (omnivox-library--source-key)))
      (plist-get emacsvox-aural-voice-workbench--library-reply :index))))

(defun emacsvox-aural-voice-workbench--library-row (id)
  "Find installed metadata for physical ID, an engine and voice list."
  (seq-find (lambda (row)
              (equal id (list (plist-get row :engine_id) (plist-get row :physical_id))))
            (plist-get (emacsvox-aural-voice-workbench--library-index) :voices)))

(defun emacsvox-aural-voice-workbench--browse-pairs ()
  "Combine live and installed voices for browsing, leaving routing untouched."
  (let ((pairs (emacsvox-aural-voice-workbench--all-engine-voices)))
    (when (emacsvox-aural-voice-workbench--library-p)
      (dolist (row (append (plist-get (emacsvox-aural-voice-workbench--library-index) :voices) nil))
        (let ((engine (plist-get row :engine_id)) (voice (plist-get row :physical_id)))
          (unless (seq-some (lambda (pair)
                              (and (equal engine (plist-get (car pair) :engine-id))
                                   (equal voice (plist-get (cadr pair) :voice-id)))) pairs)
            (setq pairs
                  (append pairs
                          (list (list (list :engine-id engine :availability "unavailable")
                                      (list :voice-id voice :display-name (plist-get row :display_name)
                                            :language (let ((language (plist-get row :language)))
                                                        (unless (eq language :null) language))
                                            :availability "not active on main speech")))))))))
    pairs))

(defun emacsvox-aural-voice-workbench--library-stop ()
  "Cancel this buffer's private inspection and pending status requests."
  (when emacsvox-aural-voice-workbench--library-cancel
    (funcall emacsvox-aural-voice-workbench--library-cancel))
  (setq emacsvox-aural-voice-workbench--library-cancel nil
        emacsvox-aural-voice-workbench--library-ticket nil)
  (dolist (lane emacsvox-aural-voice-workbench--library-lanes)
    (when-let* ((cancel (plist-get (cdr lane) :cancel))) (funcall cancel)))
  (setq emacsvox-aural-voice-workbench--library-lanes nil))

(defun emacsvox-aural-voice-workbench--library-check-lanes ()
  "Request eligibility once for each current worker and inventory generation."
  (when (emacsvox-aural-voice-workbench--library-p)
    (require 'omnivox-voices)
    (dolist (role '(main notification))
      (let* ((process (if (eq role 'main) tts-speaker-process tts-notify-process))
             (raw (and process (process-get process omnivox--control-inventory-property)))
             (generation (plist-get raw :inventory_generation))
             (old (alist-get role emacsvox-aural-voice-workbench--library-lanes)))
        (unless (and (eq process (plist-get old :process))
                     (equal generation (plist-get old :generation)))
          (when-let* ((cancel (plist-get old :cancel))) (funcall cancel))
          (let ((record (list :process process :generation generation :status nil
                              :cancel nil :normalized nil :normalized-source nil))
                (buffer (current-buffer)) id timer done)
            (setf (alist-get role emacsvox-aural-voice-workbench--library-lanes) record)
            (when (and process (process-live-p process) generation
                       (omnivox--process-supports-p process "voice_library_v1"))
              (cl-labels
                  ((finish (&optional response)
                     (unless done
                       (setq done t)
                       (when timer (cancel-timer timer))
                       (when id (remhash id (omnivox--pending-requests process)))
                       (when (buffer-live-p buffer)
                         (with-current-buffer buffer
                           (when (eq record (alist-get role emacsvox-aural-voice-workbench--library-lanes))
                             (when (and (equal (plist-get response :type) "voice_library_status_v1")
                                        (equal generation (plist-get response :inventory_generation)))
                               (setf (plist-get record :status) response))
                             (emacsvox-aural-voice-workbench-refresh)))))))
                (setf (plist-get record :cancel) (lambda ()
                                                   (setq done t)
                                                   (when timer (cancel-timer timer))
                                                   (when id (remhash id (omnivox--pending-requests process)))))
                (setq timer (run-at-time 10 nil #'finish))
                (condition-case nil
                    (setq id (omnivox--send-control-request
                              process '(:type "voice_library_status_v1")
                              (lambda (worker response)
                                (when (eq worker process) (finish response)))))
                  (error (finish)))))))))))

(defun emacsvox-aural-voice-workbench--library-start ()
  "Refresh installed metadata in the background after presenting this view."
  (when (emacsvox-aural-voice-workbench--library-p)
    (emacsvox-aural-voice-workbench--library-stop)
    (let ((buffer (current-buffer)) (ticket (list t)))
      (unless (equal emacsvox-aural-voice-workbench--library-source (omnivox-library--source-key))
        (setq emacsvox-aural-voice-workbench--library-reply nil))
      (setq emacsvox-aural-voice-workbench--library-source (omnivox-library--source-key)
            emacsvox-aural-voice-workbench--library-ticket ticket
            emacsvox-aural-voice-workbench--library-error nil)
      (setq emacsvox-aural-voice-workbench--library-cancel
            (omnivox-library--inspect-async
             (lambda (reply failure)
               (when (buffer-live-p buffer)
                 (with-current-buffer buffer
                   (when (eq ticket emacsvox-aural-voice-workbench--library-ticket)
                     (unless (equal emacsvox-aural-voice-workbench--library-source
                                    (omnivox-library--source-key))
                       (setq reply nil failure "Voice library target changed; press R to refresh"))
                     (setq emacsvox-aural-voice-workbench--library-reply reply
                           emacsvox-aural-voice-workbench--library-error failure
                           emacsvox-aural-voice-workbench--library-ticket nil)
                     (emacsvox-aural-voice-workbench-refresh)))))))
      (emacsvox-aural-voice-workbench--library-check-lanes))))

(defun emacsvox-aural-voice-workbench--library-status (id role)
  "Return current worker status for ID on ROLE, or nil if unconfirmed."
  (let* ((record (alist-get role emacsvox-aural-voice-workbench--library-lanes))
         (process (if (eq role 'main) tts-speaker-process tts-notify-process))
         (status (plist-get record :status))
         (configuration (plist-get status :configuration))
         (index (emacsvox-aural-voice-workbench--library-index))
         (raw (and process (process-get process omnivox--control-inventory-property))))
    (when (and process (process-live-p process)
                  (eq process (plist-get record :process)) status
                  (plist-member status :eligible_voices)
                  (plist-member status :configuration)
                  (equal (plist-get raw :inventory_generation) (plist-get record :generation))
                  (or (not (emacsvox-aural-voice-workbench--library-row id))
                      (eq configuration :null)
                      (and (equal (plist-get index :target_id) (plist-get configuration :target_id))
                           (equal (plist-get index :profile_id) (plist-get configuration :profile_id)))))
      status)))

(defun emacsvox-aural-voice-workbench--library-active (id role)
  "Return yes, no or unknown eligibility for physical ID on ROLE."
  (let* ((status (emacsvox-aural-voice-workbench--library-status id role))
         (record (alist-get role emacsvox-aural-voice-workbench--library-lanes))
         (process (plist-get record :process))
         (raw (and process (process-get process omnivox--control-inventory-property))))
    (if (not status) 'unknown
      (if (not (seq-some (lambda (voice)
                           (equal id (list (plist-get voice :engine_id) (plist-get voice :voice_id))))
                         (plist-get status :eligible_voices)))
          'no
        (unless (eq raw (plist-get record :normalized-source))
          (let ((tts-speaker-process process)
                (omnivox-engine-inventory raw))
            (setf (plist-get record :normalized) (omnivox-voice-inventory)
                  (plist-get record :normalized-source) raw)
            (setf (alist-get role emacsvox-aural-voice-workbench--library-lanes) record)))
        (let* ((inventory (plist-get record :normalized))
               (engine (seq-find (lambda (engine) (equal (car id) (plist-get engine :engine-id)))
                                 (plist-get inventory :engines))))
          (cond
           ((null engine) 'unknown)
           ((or (not (tts--voice-preview-available-p (plist-get engine :availability)))
                (equal (plist-get engine :health) "failed")
                (member (plist-get engine :circuit) '("open" "cooldown"))) 'no)
           (t 'yes)))))))

(defun emacsvox-aural-voice-workbench--needs-apply (row)
  "Return yes, no or unknown for a managed ROW's desired selection.
Compare administrative eligibility, independently of runtime health.  A
known difference on either stream is sufficient; absent or superseded
worker evidence cannot establish a difference."
  (if (or (not (emacsvox-aural-voice-workbench--library-index))
          emacsvox-aural-voice-workbench--library-ticket
          emacsvox-aural-voice-workbench--library-error)
      'unknown
    (let* ((id (list (plist-get row :engine_id) (plist-get row :physical_id)))
           (excluded (seq-some
                      (lambda (entry) (equal id (list (plist-get entry :engine_id) (plist-get entry :voice_id))))
                      (plist-get (emacsvox-aural-voice-workbench--library-index) :disabled_physical_ids)))
           results)
      (dolist (role '(main notification))
        (let* ((status (emacsvox-aural-voice-workbench--library-status id role))
               (process (plist-get (alist-get role emacsvox-aural-voice-workbench--library-lanes) :process))
               (raw (and process (process-get process omnivox--control-inventory-property)))
               (policy (plist-get (plist-get raw :routing_policy) :policy))
               (desired (and (eq t (plist-get row :enabled)) (not excluded)
                             (not (seq-contains-p (plist-get policy :disabled_engine_ids) (car id)))))
               (eligible (seq-some
                          (lambda (entry) (equal id (list (plist-get entry :engine_id) (plist-get entry :voice_id))))
                          (plist-get status :eligible_voices))))
          (push (cond ((or (not status) (not (plist-member policy :disabled_engine_ids))
                           (seq-contains-p (plist-get status :overridden_engines) (car id))) 'unknown)
                      ((eq (not desired) (not eligible)) 'no)
                      (t 'yes)) results)))
      (cond ((memq 'yes results) 'yes) ((memq 'unknown results) 'unknown) (t 'no)))))

(defun emacsvox-aural-voice-workbench--quick-memberships (pair)
  "Return quick-filter memberships for PAIR from cached library evidence."
  (let* ((id (list (plist-get (car pair) :engine-id) (plist-get (cadr pair) :voice-id)))
         (row (emacsvox-aural-voice-workbench--library-row id))
         (package (and row (seq-find
                            (lambda (item)
                              (and (equal (plist-get item :package_id) (plist-get row :package_id))
                                   (equal (plist-get item :revision_id) (plist-get row :revision_id))))
                            (plist-get (emacsvox-aural-voice-workbench--library-index) :packages))))
         (members '(all)))
    (when (and (equal (plist-get package :ownership) "managed")
               (consp (plist-get package :catalogue)))
      (push 'downloaded members))
    (when (eq (plist-get row :enabled) t) (push 'enabled members))
    (when row
      (pcase (emacsvox-aural-voice-workbench--needs-apply row)
        ('yes (push 'needs-apply members))
        ('unknown (push 'unknown members))))
    members))

(defun emacsvox-aural-voice-workbench--filtered-pairs (&optional all)
  "Return physical pairs matching explicit filters and, unless ALL, quick filters.
Count voices before folding languages.  This uses cached evidence only."
  (setq emacsvox-aural-voice-workbench--filter-counts nil)
  (let ((emacsvox-aural-voice-workbench--index-snapshot
         (emacsvox-aural-voice-workbench--library-index)) visible)
    (dolist (pair (emacsvox-aural-voice-workbench--browse-pairs))
      (when (emacsvox-aural-voice-workbench--physical-visible-p (car pair) (cadr pair))
        (let ((members (if (emacsvox-aural-voice-workbench--library-p)
                           (emacsvox-aural-voice-workbench--quick-memberships pair) '(all))))
          (dolist (member members)
            (cl-incf (alist-get member emacsvox-aural-voice-workbench--filter-counts 0)))
          (when (or all (not (emacsvox-aural-voice-workbench--library-p))
                    (memq emacsvox-aural-voice-workbench--quick-filter members))
            (push pair visible)))))
    (nreverse visible)))

(defun emacsvox-aural-voice-workbench--quick-description (filter)
  "Describe FILTER's last count, including incomplete library or worker checks."
  (format "%s: %d%s" (alist-get filter emacsvox-aural-voice-workbench--quick-filters)
          (alist-get filter emacsvox-aural-voice-workbench--filter-counts 0)
          (cond
           ((and (not (eq filter 'all))
                 (or emacsvox-aural-voice-workbench--library-ticket
                     emacsvox-aural-voice-workbench--library-error
                     (not (emacsvox-aural-voice-workbench--library-index)))) "; library unconfirmed")
           ((and (eq filter 'needs-apply)
                 (> (alist-get 'unknown emacsvox-aural-voice-workbench--filter-counts 0) 0))
            (format "; %d unchecked" (alist-get 'unknown emacsvox-aural-voice-workbench--filter-counts)))
           (t ""))))

(defun emacsvox-aural-voice-workbench--library-states (id)
  "Return Installed, Enabled and Active descriptions for ID."
  (let* ((row (emacsvox-aural-voice-workbench--library-row id))
         (main (emacsvox-aural-voice-workbench--library-active id 'main))
         (notify (emacsvox-aural-voice-workbench--library-active id 'notification)))
    (list (cond (row "Library")
                ((or emacsvox-aural-voice-workbench--library-ticket
                     emacsvox-aural-voice-workbench--library-error) "Unknown")
                (t "Engine supplied"))
          (cond (row (if (eq (plist-get row :enabled) t) "Yes" "No"))
                ((or emacsvox-aural-voice-workbench--library-ticket
                     emacsvox-aural-voice-workbench--library-error) "Unknown")
                (t "Engine managed"))
          (pcase (list main notify)
            (`(yes yes) "Both") (`(yes no) "Main only") (`(no yes) "Notification only")
            (`(no no) "No") (`(yes unknown) "Main; notification unknown")
            (`(unknown yes) "Notification; main unknown") (_ "Unknown")))))

(defun emacsvox-aural-voice-workbench--library-action (action &optional operation)
  "Perform explicit library ACTION, optionally importing validated OPERATION."
  (unless (emacsvox-aural-voice-workbench--library-p)
    (user-error "Open Omnivox physical voices first"))
  (let* ((id (tabulated-list-get-id))
         (engine (or (and (not (emacsvox-aural-voice-workbench--language-row-p id)) (car-safe id))
                     emacsvox-aural-voice-workbench--voice-list-parent
                     (plist-get emacsvox-aural-voice-workbench-filter :engine)))
         (index (emacsvox-aural-voice-workbench--library-index))
         (source emacsvox-aural-voice-workbench--library-source)
         (sha (plist-get emacsvox-aural-voice-workbench--library-reply :sha256))
         (row (emacsvox-aural-voice-workbench--library-row id)))
    (when (and (eq action 'toggle) (emacsvox-aural-voice-workbench--language-row-p id))
      (user-error "Expand the language and choose a voice to enable or disable"))
    (pcase action
      ('download (require 'omnivox-catalogue) (omnivox-catalogue engine))
      ('apply (call-interactively #'omnivox-library-apply))
      ((or 'toggle 'slt 'import)
       (unless (and index (not emacsvox-aural-voice-workbench--library-ticket))
         (user-error "Wait for library information or press R to refresh"))
       (when (and (eq action 'toggle) (not row))
         (user-error "This voice is engine managed; b adds bundled Flite SLT to the library"))
       (when (and (eq action 'slt) (not (equal engine "flite")))
         (user-error "Open Flite voices to include bundled SLT"))
       (when (eq action 'import)
         (setq operation (or operation (read-string "Native validation operation UUID: "))))
       (omnivox-library--edit-selection source sha action row operation)
       (message "Desired voice selection saved; a reviews Apply")))
    (unless (eq action 'download)
      (run-hooks 'omnivox-library--changed-hook))))

(defun emacsvox-aural-voice-workbench--library-toggle ()
  "Enable or disable this installed voice for the next Apply."
  (interactive) (emacsvox-aural-voice-workbench--library-action 'toggle))

(defun emacsvox-aural-voice-workbench--library-apply ()
  "Review and Apply desired voices to both speech streams."
  (interactive) (emacsvox-aural-voice-workbench--library-action 'apply))

(defun emacsvox-aural-voice-workbench--library-download ()
  "Browse downloads for this engine."
  (interactive) (emacsvox-aural-voice-workbench--library-action 'download))

(defun emacsvox-aural-voice-workbench--library-import ()
  "Import a completed native validation operation, initially disabled."
  (interactive) (emacsvox-aural-voice-workbench--library-action 'import))

(defun emacsvox-aural-voice-workbench--library-slt ()
  "Include bundled Flite SLT in the managed selection."
  (interactive) (emacsvox-aural-voice-workbench--library-action 'slt))

(defun emacsvox-aural-voice-workbench--library-changed ()
  "Update open combined browsers after installation or desired-state changes."
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (derived-mode-p 'emacsvox-aural-voice-workbench-mode)
        (emacsvox-aural-voice-workbench--library-start)))))

(provide 'emacsvox-aural-voice-workbench-library)
;;; emacsvox-aural-voice-workbench-library.el ends here
