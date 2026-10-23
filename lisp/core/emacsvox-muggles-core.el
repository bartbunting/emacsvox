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

;;;###autoload (autoload 'emacsvox-muggles-org-table/body "emacsvox-muggles-core" "Edit and speak native Org table fields." t)
(unless (featurep 'emacsvox-muggle-org-table)
  (defun emacsvox-muggles-org-table/body ()
    "Edit and speak native Org table fields.  Hydra is required.
Native movement may realign or extend the table."
    (interactive)
    (require 'emacsvox-muggle-org-table)
    (call-interactively #'emacsvox-muggles-org-table/body)))

;;;###autoload (autoload 'emacsvox-muggles-navigate/body "emacsvox-muggles-core" "Enter repeatable text navigation, moving down one line." t)
(unless (featurep 'emacsvox-muggle-navigate)
  (defun emacsvox-muggles-navigate/body ()
    "Enter repeatable text navigation, moving down one line.
Hydra is required.  Managed entry keys are optional."
    (interactive)
    (require 'emacsvox-muggle-navigate)
    (call-interactively #'emacsvox-muggles-navigate/body)))

;;;###autoload (autoload 'emacsvox-muggles-outliner/body "emacsvox-muggles-core" "Navigate and fold outlines, enabling Outline minor mode." t)
(unless (featurep 'emacsvox-muggle-outliner)
  (defun emacsvox-muggles-outliner/body ()
    "Navigate and fold outlines, enabling Outline minor mode.
Hydra is required.  Exit preserves Outline mode and completed folds."
    (interactive)
    (require 'emacsvox-muggle-outliner)
    (call-interactively #'emacsvox-muggles-outliner/body)))

;;;###autoload (autoload 'emacsvox-muggles-view/body "emacsvox-muggles-core" "Use View navigation and reading without enabling View mode." t)
(unless (featurep 'emacsvox-muggle-view)
  (defun emacsvox-muggles-view/body ()
    "Use View navigation and reading without enabling View mode.
Hydra is required.  Managed entry keys are optional."
    (interactive)
    (require 'emacsvox-muggle-view)
    (call-interactively #'emacsvox-muggles-view/body)))

;;;###autoload (autoload 'emacsvox-muggles-yank-pop/body "emacsvox-muggles-core" "Browse repeatable yank commands without inserting text." t)
(unless (featurep 'emacsvox-muggle-yank)
  (defun emacsvox-muggles-yank-pop/body ()
    "Browse repeatable yank commands without inserting text."
    (interactive)
    (require 'emacsvox-muggle-yank)
    (call-interactively #'emacsvox-muggles-yank-pop/body)))

;;;###autoload (autoload 'emacsvox-muggles-yank-pop/yank "emacsvox-muggles-core" "Yank text and enter repeatable yank." t)
(unless (featurep 'emacsvox-muggle-yank)
  (defun emacsvox-muggles-yank-pop/yank ()
    "Yank text and enter repeatable yank."
    (interactive)
    (require 'emacsvox-muggle-yank)
    (call-interactively #'emacsvox-muggles-yank-pop/yank)))

;;;###autoload (autoload 'emacsvox-muggles-yank-pop/yank-pop "emacsvox-muggles-core" "Replace the last yank and enter repeatable yank." t)
(unless (featurep 'emacsvox-muggle-yank)
  (defun emacsvox-muggles-yank-pop/yank-pop ()
    "Replace the last yank and enter repeatable yank."
    (interactive)
    (require 'emacsvox-muggle-yank)
    (call-interactively #'emacsvox-muggles-yank-pop/yank-pop)))

;;;###autoload (autoload 'emacsvox-muggles-info-summary/body "emacsvox-muggles-core" "Open the Info navigation menu in an Info buffer." t)
(unless (featurep 'emacsvox-muggle-info)
  (defun emacsvox-muggles-info-summary/body ()
    "Open the Info navigation menu in an Info buffer."
    (interactive)
    (require 'emacsvox-muggle-info)
    (call-interactively #'emacsvox-muggles-info-summary/body)))

;;;###autoload (autoload 'emacsvox-muggles-smartparens/body "emacsvox-muggles-core" "Edit balanced expressions with Smartparens mode already enabled." t)
(unless (featurep 'emacsvox-muggle-smartparens)
  (defun emacsvox-muggles-smartparens/body ()
    "Edit balanced expressions with Smartparens mode already enabled."
    (interactive)
    (require 'emacsvox-muggle-smartparens)
    (call-interactively #'emacsvox-muggles-smartparens/body)))

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
     :scope "Org" :mode org-mode
     :command emacsvox-muggles-org-nav/body)
    (org-table
     :name "Org table editing"
     :description "Move and speak native Org table fields; movement may realign or extend the table. Run requires a table at point."
     :library "emacsvox-muggle-org-table"
     :dependencies (org hydra emacsvox-org)
     :feature org :map org-mode-map :key "C-c t"
     :scope "Org" :mode org-mode :table t
     :command emacsvox-muggles-org-table/body)
    (navigate
     :name "Text navigation"
     :description "Repeat line, character and scrolling commands. Run moves down one line immediately; Enable only installs the entry key."
     :library "emacsvox-muggle-navigate"
     :dependencies (hydra emacsvox-hydra)
     :map global-map :key "s-n" :scope "Global"
     :command emacsvox-muggles-navigate/body)
    (outliner
     :name "Outline navigation"
     :description "Move between outline headings and hide or show their text. Run enables Outline minor mode in the source buffer; exit and Disable preserve the mode and completed folds. Use z to leave; q hides sublevels."
     :library "emacsvox-muggle-outliner"
     :dependencies (outline hydra emacsvox-outline)
     :map global-map :key "C-. o" :scope "Global" :exit-key "z"
     :command emacsvox-muggles-outliner/body)
    (view
     :name "View navigation"
     :description "Move, search, read and copy text using View commands without enabling View mode or making the buffer read-only. Temporary hint changes are restored on exit; explicit hint choices and completed actions remain."
     :library "emacsvox-muggle-view"
     :dependencies (view hydra emacsvox-hydra)
     :map global-map :key "C-. v" :scope "Global"
     :command emacsvox-muggles-view/body)
    (yank
     :name "Repeatable yank"
     :description "Paste and cycle through the kill ring. Enable adopts standard C-y and M-y together; Disable restores them. Personal bindings stay protected. Run opens the menu without pasting; C-y pastes, M-y replaces the last yank. C-g exits."
     :library "emacsvox-muggle-yank"
     :dependencies (hydra emacsvox-hydra ido)
     :map global-map :key "C-y" :key-label "C-y, M-y" :scope "Global"
     :bindings (("C-y" emacsvox-muggles-yank-pop/yank yank)
                ("M-y" emacsvox-muggles-yank-pop/yank-pop yank-pop))
     :adoption "Explicit Enable may replace standard yank and yank-pop only. Both keys must be usable; a conflict blocks the pair. M-x yank and M-x yank-pop still invoke the ordinary commands. Legacy collection requests alone do not adopt these bindings. Inside the menu, i chooses with Ido; l opens the optional browse-kill-ring package. C-g cancels completion without changing text."
     :exit-key "C-g" :command emacsvox-muggles-yank-pop/body)
    (info
     :name "Info summary"
     :description "Choose Info navigation and help commands. Enable adopts the standard Info question-mark key; Disable restores Info-summary. Most actions leave the menu. C-g cancels; q leaves the Info window."
     :library "emacsvox-muggle-info"
     :dependencies (info hydra emacsvox-hydra)
     :feature info :map Info-mode-map :key "?" :scope "Info" :mode Info-mode
     :bindings (("?" emacsvox-muggles-info-summary/body Info-summary))
     :adoption "Explicit Enable may replace Info-summary on ? in Info only. Personal bindings stay protected. Press ? inside the menu, or use M-x Info-summary, for the ordinary summary. Legacy collection requests alone do not adopt this binding."
     :exit-key "C-g" :command emacsvox-muggles-info-summary/body)
    (smartparens
     :name "Smartparens"
     :description "Move, wrap, splice and edit balanced expressions. Run requires smartparens-mode already enabled in the source buffer; Enable only installs the entry key. Exit and Disable preserve completed edits and the mode. C-g exits."
     :library "emacsvox-muggle-smartparens"
     :dependencies (smartparens hydra emacsvox-hydra)
     :map global-map :key "C-c ," :scope "Global"
     :minor-mode smartparens-mode :exit-key "C-g"
     :command emacsvox-muggles-smartparens/body))
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
For yank and Info, explicit Enabled also adopts their documented standard
bindings; legacy requests alone do not.  Personal replacements stay protected.
Direct M-x entry stays callable.  Missing dependencies are never installed.
Use `emacsvox-muggles-enable' or `emacsvox-muggles-disable' for a session
choice, then `emacsvox-muggles-save' to persist those choices with Customize."
  :type '(alist :key-type (choice (const org-navigation) (const org-table)
                                 (const navigate) (const outliner)
                                 (const view) (const yank) (const info)
                                 (const smartparens)) :value-type boolean)
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

(defun emacsvox-muggles--map (entry)
  "Return ENTRY's current keymap, or nil while it is unavailable."
  (let ((name (plist-get entry :map)))
    (if (eq name 'global-map) (current-global-map)
      (and (boundp name) (keymapp (symbol-value name)) (symbol-value name)))))

(declare-function org-at-table-p "org" (&optional table-type))

(defun emacsvox-muggles--check-context (entry)
  "Check ENTRY's Run requirements at point without changing the buffer."
  (when-let* ((mode (plist-get entry :mode)))
    (unless (derived-mode-p mode)
      (user-error "%s requires an %s buffer" (plist-get entry :name)
                  (plist-get entry :scope))))
  (when-let* ((mode (plist-get entry :minor-mode)))
    (unless (and (boundp mode) (symbol-value mode))
      (user-error "%s requires %s in the source buffer" (plist-get entry :name) mode)))
  (when (and (plist-get entry :table)
             (not (and (fboundp 'org-at-table-p) (org-at-table-p))))
    (user-error "Org table editing requires a table at the captured position")))

(defun emacsvox-muggles--bindings (entry)
  "Return ENTRY's (KEY COMMAND STANDARD) binding specifications."
  (or (plist-get entry :bindings)
      (list (list (plist-get entry :key) (plist-get entry :command)))))

(defun emacsvox-muggles--key-label (entry)
  "Return the readable entry-key list for ENTRY."
  (or (plist-get entry :key-label) (plist-get entry :key)))

(defun emacsvox-muggles--withdraw (id)
  "Restore each of ID's bindings only while it is still owned."
  (dolist (owned (alist-get id emacsvox-muggles--owned))
    (pcase-let ((`(,map ,key ,command ,previous) owned))
      (when (eq (lookup-key map key) command)
        (define-key map key previous))))
  (setq emacsvox-muggles--owned (assq-delete-all id emacsvox-muggles--owned)))

(defun emacsvox-muggles--close (entry)
  "Close ENTRY's active Hydra, leaving other menus and completed actions alone."
  (when (and (bound-and-true-p hydra-curr-map)
             (boundp 'hydra-curr-body-fn)
             (eq hydra-curr-body-fn (plist-get entry :command))
             (fboundp 'hydra-keyboard-quit))
    (hydra-keyboard-quit)))

(defun emacsvox-muggles--binding-availability (id specification)
  "Inspect one SPECIFICATION for ID without changing keys or loading code."
  (let* ((entry (emacsvox-muggles--entry id))
         (map-name (plist-get entry :map))
         (map (emacsvox-muggles--map entry))
         (label (car specification)) (key (kbd label))
         (command (nth 1 specification)) (standard (nth 2 specification))
         (binding (lookup-key map key))
         (global (lookup-key (current-global-map) key))
         (choice (emacsvox-muggles--choice id))
         (adopt (and standard (eq binding standard) (car choice)
                     (memq (cdr choice) '(session configured)))))
    (cond
     ((integerp binding)
      (let* ((prefix (substring key 0 binding)) (value (lookup-key map prefix)))
        (cons 'conflict
              (format "%s is not a prefix in %s (%s); use M-x %s"
                      (key-description prefix) map-name
                      (if value (format "%S" value) "unbound")
                      (plist-get entry :command)))))
     ((and binding (not (eq binding command)) (not adopt))
      (cons 'conflict
            (if (and standard (eq binding standard))
                (format "%s retains %s; explicit Enable adopts this standard binding" label standard)
              (format "%s is blocked by %S in %s" label binding map-name))))
     ;; An existing local binding takes precedence over the global map.  Do
     ;; not mistake Info's inherited self-insert binding for a local conflict.
     ((and (null binding) global (not (eq global command)))
      (cons 'conflict (format "%s is blocked by global binding %S" label global)))
     ((eq binding command)
      (cons (if (cl-some (lambda (owned)
                           (and (eq (nth 0 owned) map) (equal (nth 1 owned) key)
                                (eq (nth 2 owned) command)))
                         (alist-get id emacsvox-muggles--owned))
                'active 'existing)
            (format "%s is bound to %s" label command)))
     (t (cons 'available (if adopt (format "%s may adopt %s" label standard)
                          (format "%s is available" label)))))))

(defun emacsvox-muggles--availability (id)
  "Return (STATE . DETAIL) for ID without loading or changing anything."
  (let* ((entry (emacsvox-muggles--entry id))
         (missing (cl-remove-if
                   (lambda (library) (locate-library (symbol-name library)))
                   (plist-get entry :dependencies))))
    (cond
     (missing (cons 'missing (format "Missing libraries: %s" missing)))
     ((and (plist-get entry :feature) (not (featurep (plist-get entry :feature))))
      (cons 'waiting (format "Waiting for %s to load" (plist-get entry :feature))))
     ((not (emacsvox-muggles--map entry))
      (cons 'waiting (format "Waiting for %s" (plist-get entry :map))))
     (t
      (let* ((states (mapcar (lambda (spec) (emacsvox-muggles--binding-availability id spec))
                             (emacsvox-muggles--bindings entry)))
             (conflict (assq 'conflict states)))
        (cond
         (conflict conflict)
         ((alist-get id emacsvox-muggles--errors)
          (cons 'failed (error-message-string (alist-get id emacsvox-muggles--errors))))
         ((assq 'available states) '(available . "Entry keys are available"))
         ((assq 'active states)
          (cons 'active (format "%s active" (emacsvox-muggles--key-label entry))))
         (t (cons 'existing (format "%s already bound independently"
                                   (emacsvox-muggles--key-label entry))))))))))

(defun emacsvox-muggles--sync (id)
  "Reconcile ID's desired state, activating its complete usable key set."
  (unless emacsvox-muggles--syncing
    (let* ((emacsvox-muggles--syncing t)
           (entry (emacsvox-muggles--entry id)))
      (emacsvox-muggles--withdraw id)
      (if (not (car (emacsvox-muggles--choice id)))
          (emacsvox-muggles--close entry)
        (when (eq (car (emacsvox-muggles--availability id)) 'available)
          (condition-case err
              (progn
                (require (intern (plist-get entry :library)))
                ;; Dependencies may install bindings; recheck the whole set.
                (when (eq (car (emacsvox-muggles--availability id)) 'available)
                  (dolist (spec (emacsvox-muggles--bindings entry))
                    (let* ((map (emacsvox-muggles--map entry))
                           (key (kbd (car spec))) (command (nth 1 spec))
                           (previous (lookup-key map key)))
                      (unless (eq previous command)
                        (push (list map key command previous)
                              (alist-get id emacsvox-muggles--owned))
                        (define-key map key command))))))
            (error
             (emacsvox-muggles--withdraw id)
             (setf (alist-get id emacsvox-muggles--errors) err))))))))

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
Only documented standard bindings may be adopted; personal bindings are
preserved.  Dependencies are never installed."
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
(with-eval-after-load 'info (emacsvox-muggles--sync-all))
(with-eval-after-load 'smartparens (emacsvox-muggles--sync-all))

(provide 'emacsvox-muggles-core)
(emacsvox-muggles--sync-all)
;;; emacsvox-muggles-core.el ends here
