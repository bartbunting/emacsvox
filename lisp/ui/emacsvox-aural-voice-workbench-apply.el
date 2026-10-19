;;; emacsvox-aural-voice-workbench-apply.el --- Voice workbench save and apply -*- lexical-binding: t; -*-

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
;; Voice workbench save and apply.
;; Load through `emacsvox-aural-voice-workbench'.

;;; Code:

(require 'emacsvox-aural-voice-workbench-views)
(require 'emacsvox-aural-voice-workbench-routing)

;; Workbench dependencies.
(declare-function emacsvox-aural-voice-workbench--announce
                  "emacsvox-aural-voice-workbench" (format-string &rest arguments))
(defvar emacsvox-aural-voice-workbench-inventory)
(declare-function emacsvox-aural-voice-workbench-refresh
                  "emacsvox-aural-voice-workbench" (&optional id))
;; End workbench dependencies.

(defvar-local emacsvox-aural-voice-workbench-applied-undo nil
  "Previous known-good profile available after one successful save.")

(defvar-local emacsvox-aural-voice-workbench-diagnostics nil
  "Current inventory and apply diagnostics for the staged profile.")

(defun emacsvox-aural-voice-workbench--apply-timed-out-p (status)
  "Return non-nil when any stream in apply STATUS timed out."
  (seq-some (lambda (process) (eq 'timeout (plist-get process :phase)))
            (plist-get status :processes)))

(defun emacsvox-aural-voice-workbench--apply-status-description ()
  "Return concise apply status for the staged profile."
  (let* ((status emacsvox-aural-routing-apply-status)
         (profile-id
          (plist-get emacsvox-aural-voice-workbench-staged-profile :id)))
    (if (not (eq profile-id (plist-get status :profile-id)))
        "not applied here"
      (let* ((state (or (plist-get status :status) 'unknown))
             (processes (plist-get status :processes))
             (applied
              (cl-count
               'applied processes
               :key (lambda (process) (plist-get process :status)))))
        (concat
         (if processes
             (format "%s %d/%d" state applied (length processes))
           (format "%s" state))
         (when (emacsvox-aural-voice-workbench--apply-timed-out-p status)
           "; timed out; server outcome unconfirmed"))))))

(defun emacsvox-aural-voice-workbench--inventory-engine (engine-id)
  "Return staged inventory engine ENGINE-ID, or nil."
  (cl-find
   engine-id
   (plist-get emacsvox-aural-voice-workbench-inventory :engines)
   :key (lambda (engine) (plist-get engine :engine-id))
   :test #'equal))

(defun emacsvox-aural-voice-workbench--profile-diagnostics (profile)
  "Return non-blocking current-inventory diagnostics for PROFILE."
  (let (diagnostics checked-engines)
    (when (plist-get emacsvox-aural-voice-workbench-inventory :stale)
      (push
       '(:kind stale-inventory
         :message "Inventory is stale; routes will re-resolve when refreshed")
       diagnostics))
    (cl-labels
        ((check-engine
          (engine-id context)
          (when (and engine-id (not (member engine-id checked-engines)))
            (push engine-id checked-engines)
            (if-let* ((engine
                       (emacsvox-aural-voice-workbench--inventory-engine
                        engine-id)))
                (when
                    (member (format "%s" (plist-get engine :health))
                            '("failed" "unavailable"))
                  (push
                   (list :kind 'engine-unhealthy :engine-id engine-id
                         :context context
                         :message
                         (format "Engine %s is currently %s"
                                 engine-id (plist-get engine :health)))
                   diagnostics))
              (push
               (list :kind 'engine-missing :engine-id engine-id
                     :context context
                     :message
                     (format "Engine %s is not in current inventory" engine-id))
               diagnostics))))
         (check-selector
          (selector logical)
          (let* ((engine-id (plist-get selector :engine-id))
                 (engine (and engine-id
                              (emacsvox-aural-voice-workbench--inventory-engine
                               engine-id))))
            (check-engine engine-id logical)
            (when (and engine
                       (eq (plist-get selector :kind) 'exact)
                       (not
                        (tts--inventory-exact-voice
                         engine (plist-get selector :voice-id))))
              (push
               (list
                :kind 'voice-missing :logical-voice logical
                :engine-id engine-id
                :voice-id (plist-get selector :voice-id)
                :message
                (format "Exact voice %s/%s for %s is not installed"
                        engine-id (plist-get selector :voice-id) logical))
               diagnostics)))))
      (dolist (engine-id (append (plist-get profile :engine-order)
                                 (plist-get profile :disabled-engines)
                                 (plist-get (plist-get profile :fallback)
                                            :engines)))
        (check-engine engine-id 'global-policy))
      (when-let* ((global
                   (plist-get (plist-get profile :fallback) :global-default)))
        (check-selector global 'global-default))
      (dolist (voice (emacsvox-aural-voice-workbench--logical-voices))
        (dolist (selector (emacsvox-aural-voice-workbench--selectors voice))
          (check-selector selector voice)))
      (nreverse diagnostics))))

(defun emacsvox-aural-voice-workbench--apply-complete (buffer status)
  "Update live workbench BUFFER with terminal apply STATUS."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when (derived-mode-p 'emacsvox-aural-voice-workbench-mode)
        (setq emacsvox-aural-voice-workbench-diagnostics
              (emacsvox-aural-voice-workbench--profile-diagnostics
               emacsvox-aural-voice-workbench-staged-profile))
        (emacsvox-aural-voice-workbench-refresh)
        (emacsvox-aural-voice-workbench--announce
         "Voice configuration apply %s%s"
         (plist-get status :status)
         (if (emacsvox-aural-voice-workbench--apply-timed-out-p status)
             "; timed out; server outcome unconfirmed. Press r to reapply"
           ""))))))

(defun emacsvox-aural-voice-workbench--apply-callback ()
  "Return a callback targeting the current workbench buffer."
  (let ((buffer (current-buffer)))
    (lambda (status)
      (emacsvox-aural-voice-workbench--apply-complete buffer status))))

(defun emacsvox-aural-voice-workbench-save-and-apply ()
  "Atomically save the staged profile and apply it to every speech stream."
  (interactive)
  (let* ((validated
          (emacsvox-aural-validate-routing-profile-data
           emacsvox-aural-voice-workbench-staged-profile))
         (previous
          (copy-tree emacsvox-aural-voice-workbench-committed-profile))
         (diagnostics
          (emacsvox-aural-voice-workbench--profile-diagnostics validated))
         (callback (emacsvox-aural-voice-workbench--apply-callback)))
    (setq emacsvox-aural-voice-workbench-diagnostics diagnostics)
    (if (not (emacsvox-aural-voice-workbench--dirty-p))
        (progn
          (emacsvox-aural-apply-routing-profile
           (plist-get validated :id) callback)
          (emacsvox-aural-voice-workbench--announce
           "Committed routing is being reapplied"))
      (emacsvox-aural-commit-routing-profile-data
       validated emacsvox-aural-routing-profiles-file callback)
      (setq emacsvox-aural-voice-workbench-applied-undo previous
            emacsvox-aural-voice-workbench-committed-profile
            (copy-tree validated)
            emacsvox-aural-voice-workbench-staged-profile
            (copy-tree validated)
            emacsvox-aural-voice-workbench-undo-stack nil
            emacsvox-aural-voice-workbench-last-edit
            "Saved and submitted complete routing profile")
      (emacsvox-aural-voice-workbench-refresh)
      (emacsvox-aural-voice-workbench--announce
       "Routing profile saved atomically; apply pending%s"
       (if diagnostics
           (format ", %d current inventory warning%s"
                   (length diagnostics)
                   (if (= (length diagnostics) 1) "" "s"))
         "")))))

(defun emacsvox-aural-voice-workbench-retry-apply ()
  "Idempotently retry the committed profile on all live speech streams."
  (interactive)
  (when (emacsvox-aural-voice-workbench--dirty-p)
    (user-error "Save or cancel staged edits before retrying live apply"))
  (emacsvox-aural-apply-routing-profile
   (plist-get emacsvox-aural-voice-workbench-committed-profile :id)
   (emacsvox-aural-voice-workbench--apply-callback))
  (emacsvox-aural-voice-workbench--announce
   "Committed voice configuration apply retried"))

(defun emacsvox-aural-voice-workbench-undo-applied ()
  "Restore and apply the previous known-good profile revision."
  (interactive)
  (unless emacsvox-aural-voice-workbench-applied-undo
    (user-error "No saved Voice Workbench revision is available to restore"))
  (when (y-or-n-p "Restore the previous saved routing revision? ")
    (let ((restored (copy-tree emacsvox-aural-voice-workbench-applied-undo)))
      (emacsvox-aural-commit-routing-profile-data
       restored emacsvox-aural-routing-profiles-file
       (emacsvox-aural-voice-workbench--apply-callback))
      (setq emacsvox-aural-voice-workbench-committed-profile
            (copy-tree restored)
            emacsvox-aural-voice-workbench-staged-profile
            (copy-tree restored)
            emacsvox-aural-voice-workbench-applied-undo nil
            emacsvox-aural-voice-workbench-undo-stack nil
            emacsvox-aural-voice-workbench-last-edit
            "Restored previous saved routing revision")
      (emacsvox-aural-voice-workbench-refresh)
      (emacsvox-aural-voice-workbench--announce
       "Previous routing revision restored and apply pending"))))

(provide 'emacsvox-aural-voice-workbench-apply)
;;; emacsvox-aural-voice-workbench-apply.el ends here
