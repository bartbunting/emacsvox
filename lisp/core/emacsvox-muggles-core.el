;;; emacsvox-muggles-core.el --- Independently managed Muggles -*- lexical-binding: t; -*-

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
;; Registration does not load a collection or install keys.  Session choices
;; override configured defaults and legacy collection requests.  Direct M-x
;; entry remains available when managed bindings are disabled.
;;; Code:

(require 'cl-lib)
(require 'cus-edit)

;; The optional Hydra replaces this lazy entry with its generated body.
;; Preserve that body if the optional library was loaded before this manager.
;;;###autoload (autoload 'emacsvox-muggles-org-nav/body "emacsvox-muggles-core" "Navigate and speak Org headings.  Managed entry keys are optional." t)
(unless (featurep 'emacsvox-muggle-org-navigation)
  (defun emacsvox-muggles-org-nav/body ()
    "Navigate and speak Org headings.  Managed entry keys are optional.
Load the optional Org navigation library on first use.  Hydra is required."
    (interactive)
    (require 'emacsvox-muggle-org-navigation)
    (call-interactively #'emacsvox-muggles-org-nav/body)))

(defgroup emacsvox-muggles nil
  "Independent convenience menus and their entry bindings."
  :group 'emacsvox)

(defconst emacsvox-muggles--registry
  '((org-navigation
     :name "Org heading navigation"
     :description "Move between Org headings and speak their sections."
     :library "emacsvox-muggle-org-navigation"
     :dependencies (org hydra emacsvox-outline)
     :feature org :map org-mode-map :key "C-c C-SPC"
     :command emacsvox-muggles-org-nav/body))
  "Converted Muggles and their loading and binding requirements.")

(defvar emacsvox-muggles--session nil "Explicit choices for this session.")
(defvar emacsvox-muggles--legacy nil "Entries requested by legacy collections.")
(defvar emacsvox-muggles--owned nil "Installed bindings, indexed by entry ID.")
(defvar emacsvox-muggles--errors nil "Last activation errors, indexed by ID.")
(defvar emacsvox-muggles--syncing nil "Non-nil while reconciling bindings.")
(defvar hydra-curr-body-fn)
(defvar hydra-curr-map)
(declare-function hydra-keyboard-quit "hydra")

(defun emacsvox-muggles--set-preferences (symbol value)
  "Set SYMBOL to VALUE and reconcile currently usable entries."
  (dolist (entry value)
    (unless (and (assq (car entry) emacsvox-muggles--registry)
                 (memq (cdr entry) '(nil t)))
      (error "Invalid managed Muggle preference: %S" entry)))
  (set-default symbol value)
  (when (fboundp 'emacsvox-muggles--sync-all)
    (emacsvox-muggles--sync-all)))

;;;###autoload
(defcustom emacsvox-muggles-preferences nil
  "Configured enable/disable overrides for managed Muggles.
Each entry is (ID . ENABLED).  An explicit nil disables managed entry keys,
even when a legacy collection requests the Muggle.  An absent entry follows
legacy collection requests, or remains disabled when none exists.
Direct M-x entry stays callable.  Missing dependencies are never installed.
Use `emacsvox-muggles-enable' or `emacsvox-muggles-disable' for a session
choice, then `emacsvox-muggles-save' to persist those choices with Customize."
  :type '(alist :key-type (choice (const org-navigation)) :value-type boolean)
  :initialize #'custom-initialize-default
  :set #'emacsvox-muggles--set-preferences
  :group 'emacsvox-muggles)

(defun emacsvox-muggles--entry (id)
  "Return the registered description for ID."
  (or (cdr (assq id emacsvox-muggles--registry))
      (user-error "Muggle is not managed yet: %s" id)))

(defun emacsvox-muggles--choice (id)
  "Return (ENABLED . ORIGIN) for ID, preserving explicit nil choices."
  (cond ((assq id emacsvox-muggles--session)
         (cons (cdr (assq id emacsvox-muggles--session)) 'session))
        ((assq id emacsvox-muggles-preferences)
         (cons (cdr (assq id emacsvox-muggles-preferences)) 'configured))
        ((memq id emacsvox-muggles--legacy) '(t . legacy))
        (t '(nil . default))))

(defun emacsvox-muggles--withdraw (id)
  "Withdraw ID's binding only while it is still owned by this manager."
  (when-let* ((owned (alist-get id emacsvox-muggles--owned)))
    (pcase-let ((`(,map ,key ,command ,previous) owned))
      (when (eq (lookup-key map key) command)
        (define-key map key previous)))
    (setq emacsvox-muggles--owned (assq-delete-all id emacsvox-muggles--owned))))

(defun emacsvox-muggles--close (entry)
  "Close ENTRY's active Hydra, leaving other menus and completed actions alone."
  (when (and (bound-and-true-p hydra-curr-map)
             (boundp 'hydra-curr-body-fn)
             (eq hydra-curr-body-fn (plist-get entry :command))
             (fboundp 'hydra-keyboard-quit))
    (hydra-keyboard-quit)))

(defun emacsvox-muggles--availability (id)
  "Return (STATE . DETAIL) for ID without loading or changing anything."
  (let* ((entry (emacsvox-muggles--entry id))
         (map-name (plist-get entry :map))
         (key (kbd (plist-get entry :key)))
         (command (plist-get entry :command))
         (missing (cl-remove-if
                   (lambda (library) (locate-library (symbol-name library)))
                   (plist-get entry :dependencies))))
    (cond
     (missing (cons 'missing (format "Missing libraries: %s" missing)))
     ((not (featurep (plist-get entry :feature)))
      (cons 'waiting (format "Waiting for %s to load" (plist-get entry :feature))))
     ((not (and (boundp map-name) (keymapp (symbol-value map-name))))
      (cons 'waiting (format "Waiting for %s" map-name)))
     (t
      (let ((binding (lookup-key (symbol-value map-name) key))
            (global (lookup-key (current-global-map) key)))
        (cond
         ((and binding (not (eq binding command)))
          (cons 'conflict (format "%s is blocked by %S in %s"
                                  (plist-get entry :key) binding map-name)))
         ((and global (not (eq global command)))
          (cons 'conflict (format "%s is blocked by global binding %S"
                                  (plist-get entry :key) global)))
         ((eq binding command)
          (cons (if (alist-get id emacsvox-muggles--owned) 'active 'existing)
                (format "%s is %s" (plist-get entry :key)
                        (if (alist-get id emacsvox-muggles--owned)
                            "active" "already bound independently"))))
         ((alist-get id emacsvox-muggles--errors)
          (cons 'failed (error-message-string (alist-get id emacsvox-muggles--errors))))
         (t '(available . "Entry key is available"))))))))

(defun emacsvox-muggles--sync (id)
  "Reconcile ID's desired state with its package and key availability."
  (unless emacsvox-muggles--syncing
    (let* ((emacsvox-muggles--syncing t)
           (entry (emacsvox-muggles--entry id)))
      ;; Recheck ownership first, including later personal or package bindings.
      (emacsvox-muggles--withdraw id)
      (if (not (car (emacsvox-muggles--choice id)))
          (emacsvox-muggles--close entry)
        (when (eq (car (emacsvox-muggles--availability id)) 'available)
          (condition-case err
              (progn
                (require (intern (plist-get entry :library)))
                ;; Loading dependencies can install their own bindings.
                (when (eq (car (emacsvox-muggles--availability id)) 'available)
                  (let* ((map (symbol-value (plist-get entry :map)))
                         (key (kbd (plist-get entry :key)))
                         (previous (lookup-key map key))
                         (command (plist-get entry :command)))
                    (define-key map key command)
                    (setf (alist-get id emacsvox-muggles--owned)
                          (list map key command previous)))))
            (error (setf (alist-get id emacsvox-muggles--errors) err))))))))

(defun emacsvox-muggles--sync-all ()
  "Reconcile all converted entries without loading a legacy collection."
  (dolist (entry emacsvox-muggles--registry)
    (emacsvox-muggles--sync (car entry))))

(defun emacsvox-muggles--legacy-enable (id)
  "Request ID for a legacy collection, respecting explicit overrides."
  (emacsvox-muggles--entry id)
  (cl-pushnew id emacsvox-muggles--legacy)
  (emacsvox-muggles--sync id))

(defun emacsvox-muggles--read ()
  "Read a converted Muggle by its descriptive name."
  (let ((choices (mapcar (lambda (entry) (cons (plist-get (cdr entry) :name) (car entry)))
                         emacsvox-muggles--registry)))
    (cdr (assoc (completing-read "Muggle: " choices nil t) choices))))

;;;###autoload
(defun emacsvox-muggles-status (id)
  "Report ID's requested state, origin and binding availability.
This command does not load a Muggle, change settings or install bindings."
  (interactive (list (emacsvox-muggles--read)))
  (let* ((entry (emacsvox-muggles--entry id))
         (choice (emacsvox-muggles--choice id))
         (availability (emacsvox-muggles--availability id))
         (status (list :id id :enabled (car choice) :origin (cdr choice)
                       :state (car availability) :detail (cdr availability))))
    (when (called-interactively-p 'interactive)
      (message "%s: %s (%s). %s. M-x %s remains available"
               (plist-get entry :name) (if (car choice) "enabled" "disabled")
               (cdr choice) (cdr availability) (plist-get entry :command)))
    status))

(defun emacsvox-muggles--set-session (id enabled)
  "Set ID to ENABLED for this session and report the resulting availability."
  (let ((entry (emacsvox-muggles--entry id)))
    (setf (alist-get id emacsvox-muggles--session) enabled)
    (setq emacsvox-muggles--errors (assq-delete-all id emacsvox-muggles--errors))
    (emacsvox-muggles--sync id)
    (message "%s %s for this session. %s. Use M-x emacsvox-muggles-save to save"
             (plist-get entry :name) (if enabled "enabled" "disabled")
             (cdr (emacsvox-muggles--availability id)))))

;;;###autoload
(defun emacsvox-muggles-enable (id)
  "Enable ID's managed entry keys for this session, without saving.
Conflicting bindings are preserved.  Dependencies are never installed."
  (interactive (list (emacsvox-muggles--read)))
  (emacsvox-muggles--set-session id t))

;;;###autoload
(defun emacsvox-muggles-disable (id)
  "Disable ID's managed keys and close its active menu, without saving.
Direct M-x entry remains callable; completed actions are not undone."
  (interactive (list (emacsvox-muggles--read)))
  (emacsvox-muggles--set-session id nil))

;;;###autoload
(defun emacsvox-muggles-save ()
  "Save explicit session choices through Customize, preserving other entries."
  (interactive)
  (unless emacsvox-muggles--session (user-error "No session Muggle choices to save"))
  ;; Customize otherwise silently keeps only a temporary value under -Q.
  (custom-file)
  (let ((preferences (copy-tree emacsvox-muggles-preferences))
        (old emacsvox-muggles-preferences)
        (properties (copy-tree (symbol-plist 'emacsvox-muggles-preferences))))
    (dolist (entry emacsvox-muggles--session)
      (setf (alist-get (car entry) preferences) (cdr entry)))
    (condition-case err
        (customize-save-variable 'emacsvox-muggles-preferences preferences)
      (error
       (setq emacsvox-muggles-preferences old)
       (setplist 'emacsvox-muggles-preferences properties)
       (signal (car err) (cdr err))))
    (setq emacsvox-muggles--session nil)
    (emacsvox-muggles--sync-all)
    (message "Saved Muggle choices through Customize")))

(with-eval-after-load 'org (emacsvox-muggles--sync-all))
(with-eval-after-load 'hydra (emacsvox-muggles--sync-all))

(provide 'emacsvox-muggles-core)
(emacsvox-muggles--sync-all)
;;; emacsvox-muggles-core.el ends here
