;;; emacsvox-muggles-ui.el --- Browse managed Muggles -*- lexical-binding: t; -*-

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
;; Inspect converted Muggles without loading their optional libraries.
;; Session actions and explicit Customize saving retain the selected row.
;;; Code:
(require 'emacsvox-muggles-core)
(require 'emacsvox-aural-ui)
(require 'emacsvox-aural-inspection)

(defun emacsvox-muggles-ui--id ()
  "Return the selected managed Muggle, or explain the missing selection."
  (or (tabulated-list-get-id) (user-error "Move to a Muggle first")))

(defun emacsvox-muggles-ui--choice-label (id)
  "Describe ID's current request and whether it is a session choice."
  (let ((choice (emacsvox-muggles--choice id)))
    (format "%s; %s" (if (car choice) "Enabled" "Disabled")
            (pcase (cdr choice)
              ('session "session choice, not saved")
              ('configured "configured override")
              ('legacy "legacy collection request")
              (_ "default")))))

(defun emacsvox-muggles-ui--configured-label (id)
  "Describe ID's configured override without confusing absence with nil."
  (if-let* ((entry (assq id emacsvox-muggles-preferences)))
      (if (cdr entry) "Enabled" "Disabled")
    "No override; legacy request or disabled"))

(defun emacsvox-muggles-ui--context-label ()
  "Describe whether Run can use the captured Org source."
  (condition-case err
      (progn (emacsvox-muggles-ui--source) "Run available in captured Org buffer")
    (user-error (error-message-string err))))

(defun emacsvox-muggles-ui--populate ()
  "Render current choices, configured overrides and binding availability."
  (setq tabulated-list-entries
        (mapcar
         (lambda (record)
           (let ((id (car record)) (entry (cdr record)))
             (list id
                   (vector (plist-get entry :name)
                           (emacsvox-muggles-ui--choice-label id)
                           (emacsvox-muggles-ui--configured-label id)
                           (concat "Org " (plist-get entry :key))
                           (cdr (emacsvox-muggles--availability id))))))
         emacsvox-muggles--registry)
        header-line-format
        "Managed Muggles. RET details, e enable, d disable, r run in source, W save all session choices, ? help, q back."))

(defun emacsvox-muggles-ui-refresh ()
  "Refresh state without loading Muggles, changing choices or moving selection."
  (interactive)
  (emacsvox-aural-ui-refresh-tabulated #'emacsvox-muggles-ui--populate))

(defun emacsvox-muggles-ui--row-description ()
  "Describe the selected Muggle's purpose, choice and availability."
  (let* ((id (emacsvox-muggles-ui--id)) (entry (emacsvox-muggles--entry id)))
    (format "%s. %s %s. Configured: %s. %s."
             (plist-get entry :name) (plist-get entry :description)
             (emacsvox-muggles-ui--choice-label id)
             (emacsvox-muggles-ui--configured-label id)
             (cdr (emacsvox-muggles--availability id)))))

(defun emacsvox-muggles-ui-speak-current ()
  "Read the selected Muggle's purpose, choice and availability."
  (interactive)
  (emacsvox-aural-ui-speak (emacsvox-muggles-ui--row-description)))

(defun emacsvox-muggles-ui--change (enabled)
  "Set the selected request to ENABLED and retain row and column focus."
  (let ((inhibit-message t) (emacsvox-speak-messages nil))
    (emacsvox-muggles--set-session (emacsvox-muggles-ui--id) enabled))
  (emacsvox-muggles-ui-refresh)
  (let ((id (emacsvox-muggles-ui--id)))
    (emacsvox-aural-ui-speak
     (format "%s, not saved. %s."
             (if enabled "Enabled" "Disabled")
             (cdr (emacsvox-muggles--availability id))))))

(defun emacsvox-muggles-ui-enable ()
  "Enable the selected Muggle's managed keys for this session.
Preserve existing bindings.  This does not run the Muggle or save settings."
  (interactive)
  (emacsvox-muggles-ui--change t))

(defun emacsvox-muggles-ui-disable ()
  "Remove the selected Muggle's managed keys and close it if active.
Keep personal bindings, completed actions and direct M-x use; do not save."
  (interactive)
  (emacsvox-muggles-ui--change nil))

(defun emacsvox-muggles-ui-save ()
  "Save all explicit session Muggle choices through Customize.
Retain the selected row.  Failed saves leave session choices pending."
  (interactive)
  (let ((inhibit-message t) (emacsvox-speak-messages nil)) (emacsvox-muggles-save))
  (emacsvox-muggles-ui-refresh)
  (emacsvox-aural-ui-speak
   (concat "Saved all session Muggle choices through Customize. "
           (emacsvox-muggles-ui--row-description))))

(defun emacsvox-muggles-ui--source ()
  "Validate and return the captured Org source without moving point."
  (let ((source emacsvox-aural-ui-source-buffer)
        (position emacsvox-aural-ui-source-position))
    (unless (buffer-live-p source)
      (user-error "The source buffer has been closed; reopen Muggles from an Org buffer"))
    (unless (and (markerp position) (eq (marker-buffer position) source))
      (user-error "The source location is unavailable; reopen Muggles"))
    (emacsvox-aural-inspection-check-source-guard emacsvox-aural-ui-source-guard)
    (with-current-buffer source
      (unless (derived-mode-p 'org-mode)
        (user-error "Run requires an Org source buffer; reopen Muggles from Org"))
      (unless (<= (point-min) position (point-max))
        (user-error "The source location is outside the visible restriction; reopen Muggles")))
    source))

(defun emacsvox-muggles-ui-run ()
  "Enter the selected Muggle at the captured source location.
Run works even when managed keys are disabled or blocked.  It leaves the list
and starts navigation; this is an action, not a preview or an enable request."
  (interactive)
  (let* ((entry (emacsvox-muggles--entry (emacsvox-muggles-ui--id)))
         (source (emacsvox-muggles-ui--source))
         (position emacsvox-aural-ui-source-position))
    ;; Load before leaving the list so missing dependencies retain its focus.
    (require (intern (plist-get entry :library)))
    (pop-to-buffer source)
    (goto-char position)
    (call-interactively (plist-get entry :command))))

(defun emacsvox-muggles-ui-details ()
  "Explain the selected Muggle, its state, entry key and explicit actions.
Help changes no settings; q returns to the exact list row and column."
  (interactive)
  (let* ((id (emacsvox-muggles-ui--id)) (entry (emacsvox-muggles--entry id))
         (context (emacsvox-muggles-ui--context-label)))
    (emacsvox-aural-ui-with-help-window
      (princ (format "%s\n\n%s\n\nCurrent: %s.\nConfigured override: %s.\nEntry key: Org %s.\n%s.\n%s.\n\n"
                     (plist-get entry :name) (plist-get entry :description)
                     (emacsvox-muggles-ui--choice-label id)
                     (emacsvox-muggles-ui--configured-label id)
                     (plist-get entry :key)
                     (cdr (emacsvox-muggles--availability id)) context))
      (princ "Up and Down browse; Left and Right inspect columns. Space reads the row.\nRET or ? opens these details. g refreshes without loading a Muggle.\n\n")
      (princ "e enables managed keys for this session; d disables them and closes an active menu.\nThese are session-wide choices, not buffer-local settings. Existing keys are preserved.\nDirect M-x entry remains available when disabled or blocked. Dependencies are never installed.\n\n")
      (princ "W saves all session Muggle choices through Customize. Closing the list keeps unsaved session choices.\nConfigured overrides may come from Customize or your init; no override follows a legacy collection request, otherwise disabled.\n\n")
      (princ (format "r enters M-x %s in the captured Org source, even when disabled.\nRun leaves the list and starts navigation; it does not enable keys or save. q then exits that navigation menu.\n\n" (plist-get entry :command)))
      (princ "Only converted Muggles appear here. Other legacy collection members do not yet have individual switches.\n")))
  (when (fboundp 'emacsvox-speak-help) (emacsvox-speak-help)))

(define-derived-mode emacsvox-muggles-ui-mode emacsvox-aural-tabulated-mode
  "Muggles"
  "Browse managed Muggles with explicit session changes and Customize Save."
  (emacsvox-aural-ui-configure-tabulated
   "managed Muggles" #'emacsvox-muggles-ui-speak-current #'emacsvox-muggles-ui-refresh)
  (setq tabulated-list-format
        [("Muggle" 25 t) ("Current choice" 38 t) ("Configured override" 38 t)
         ("Entry key" 15 t) ("Availability" 0 t)]
        tabulated-list-padding 2
        tabulated-list-sort-key '("Muggle" . nil)
        emacsvox-aural-ui-extra-actions
        '(("Explain this Muggle and its state [RET]" . emacsvox-muggles-ui-details)
          ("Enable managed keys for this session [e]" . emacsvox-muggles-ui-enable)
          ("Disable managed keys for this session [d]" . emacsvox-muggles-ui-disable)
          ("Run in the captured source [r]" . emacsvox-muggles-ui-run)
          ("Save all session Muggle choices [W]" . emacsvox-muggles-ui-save)))
  (tabulated-list-init-header))

(dolist (binding '(("RET" . emacsvox-muggles-ui-details)
                   ("?" . emacsvox-muggles-ui-details)
                   ("e" . emacsvox-muggles-ui-enable)
                   ("d" . emacsvox-muggles-ui-disable)
                   ("r" . emacsvox-muggles-ui-run)
                   ("W" . emacsvox-muggles-ui-save)))
  (keymap-set emacsvox-muggles-ui-mode-map (car binding) (cdr binding)))

;;;###autoload
(defun emacsvox-muggles-browse ()
  "Browse managed Muggles without enabling, running or saving anything.
Only converted entries are listed.  RET explains the selected entry; e and d
change its session choice, r runs it in the captured source, and W saves all
session choices through Customize.  q keeps changes and returns."
  (interactive)
  (let* ((source (emacsvox-aural-inspection-remember-source-buffer))
         (buffer (get-buffer-create "*Emacsvox Muggles*")))
    (with-current-buffer buffer
      (unless (derived-mode-p 'emacsvox-muggles-ui-mode) (emacsvox-muggles-ui-mode))
      (setq emacsvox-aural-ui--return-function nil)
      (emacsvox-aural-inspection-attach-source source)
      (emacsvox-muggles-ui-refresh))
    (emacsvox-aural-ui--pop-to-buffer
     buffer (lambda ()
              (emacsvox-aural-ui-speak
               (concat "Managed Muggles. RET details, e enable, d disable, r run, W save all session choices. "
                       (emacsvox-muggles-ui--row-description)))))
    buffer))

(provide 'emacsvox-muggles-ui)
;;; emacsvox-muggles-ui.el ends here
