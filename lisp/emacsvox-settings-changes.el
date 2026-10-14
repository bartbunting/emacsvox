;;; emacsvox-settings-changes.el --- Changed settings and draft status -*- lexical-binding: t; -*-

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
;; A read-only snapshot of loaded Custom options and their separate draft stores.
;;; Code:
(require 'cus-edit)
(require 'emacsvox-aural-menu)
(require 'emacsvox-aural-home)
(declare-function emacsvox-aural-voice-drafts--status "emacsvox-aural-voice-drafts" (draft))

(defvar-local emacsvox-settings-changes--source nil
  "Source buffer whose local values this snapshot describes.")
(defun emacsvox-settings-changes--print (value)
  "Print VALUE as bounded single-line data for display and speech."
  (let ((print-length 12) (print-level 4))
    (replace-regexp-in-string "[\n\r\t]+" " " (prin1-to-string value))))
(defun emacsvox-settings-changes--saved (symbol)
  "Describe SYMBOL's saved startup expression without evaluating it."
  (if-let* ((saved (get symbol 'saved-value)))
      (let ((form (car saved)))
        (cond ((eq (car-safe form) 'quote)
               (emacsvox-settings-changes--print (cadr form)))
              ((or (numberp form) (stringp form) (memq form '(nil t)) (keywordp form))
               (emacsvox-settings-changes--print form))
              (t (concat "Expression: " (emacsvox-settings-changes--print form)))))
    "No Customize save"))
(defun emacsvox-settings-changes--option (symbol source)
  "Return a changed-option row for SYMBOL in SOURCE, or nil.
Custom determines the default's state; local values remain a separate column."
  (when (and (boundp symbol) (default-boundp symbol)
             (get symbol 'custom-type) (not (get symbol 'byte-obsolete-variable)))
    (let* ((default (default-value symbol))
           (local (local-variable-p symbol source))
           (state (condition-case nil (custom-variable-state symbol default)
                    (error 'unknown))))
      (when (or local (get symbol 'saved-value) (not (eq state 'standard)))
        (list symbol
              (vector (symbol-name symbol)
                      (emacsvox-settings-changes--print (buffer-local-value symbol source))
                      (emacsvox-settings-changes--print default)
                      (emacsvox-settings-changes--saved symbol)
                      (format "%s; default %s%s" (if local "Buffer override" "Follows default") state
                              (if (eq symbol 'tts-notification-device) "; restart speech to apply routing" ""))))))))
(defun emacsvox-settings-changes--drafts ()
  "Describe retained drafts without reopening, applying, or saving them."
  (let (rows)
    (dolist (draft (emacsvox-aural-home--pending-drafts))
      (let ((name (if (bufferp draft) (buffer-name draft)
                    (format "Voice %s in %s" (or (plist-get draft :voice) "experiment")
                            (or (plist-get draft :palette) "no destination"))))
            (status (if (bufferp draft) "Unfinished editor draft"
                      (plist-get (emacsvox-aural-voice-drafts--status (plist-get draft :draft)) :label))))
        (push (list (list 'draft name) (vector name "Draft" "—" "Owning editor" status)) rows)))
    (dolist (entry '((emacsvox-capitalization--drafts :values "Capitalization cue")
                     (emacsvox-line-cues--drafts :value "Line/boundary cue")))
      (when (and (boundp (car entry)) (hash-table-p (symbol-value (car entry))))
        (maphash
         (lambda (kind draft)
           (unless (equal (plist-get draft (nth 1 entry)) (plist-get draft :initial))
             (push (list (list (car entry) kind)
                         (vector (format "%s: %s" (nth 2 entry) kind)
                                 (emacsvox-settings-changes--print (plist-get draft (nth 1 entry)))
                                 "—" (emacsvox-settings-changes--print (plist-get draft :initial))
                                 "Unsaved cue draft; personal-rule store")) rows)))
         (symbol-value (car entry)))))
    (when (bound-and-true-p emacsvox-aural-voice-palettes--import-pending)
      (push (list 'palette-import (vector "Palette import" "Pending" "—" "Palette store"
                                          "Resume import in the palette manager")) rows))
    (nreverse rows)))
(defun emacsvox-settings-changes--entries (source)
  "Collect a snapshot of loaded options, runtime values, and drafts for SOURCE."
  (unless (buffer-live-p source) (user-error "The settings source buffer has closed"))
  (let (options)
    (mapatoms
     (lambda (symbol)
       (when (string-match-p "\\`\\(?:emacsvox-\\|tts-\\|omnivox-\\)" (symbol-name symbol))
         (when-let* ((row (emacsvox-settings-changes--option symbol source)))
           (push row options)))))
    (append
     (sort options (lambda (a b) (string< (symbol-name (car a)) (symbol-name (car b)))))
     (cl-loop for symbol in '(tts-speech-rate emacsvox-agent-shell-speech-level)
              when (and (boundp symbol) (not (get symbol 'custom-type)))
              collect (list symbol (vector (symbol-name symbol)
                                           (emacsvox-settings-changes--print (buffer-local-value symbol source))
                                           (emacsvox-settings-changes--print (default-value symbol))
                                           "Runtime value" "Session/buffer state; use its settings command")))
     (list (list 'stores (vector "Voice, rule and pronunciation stores" "Separate stores" "—" "Use the owning editor"
                                "This view does not compare disk files or query the speech host")))
     (emacsvox-settings-changes--drafts))))
(defun emacsvox-settings-changes--speak ()
  "Speak the complete selected row, naming each value's scope."
  (interactive)
  (let ((row (or (tabulated-list-get-entry) (user-error "No changed setting at point"))))
    (emacsvox-aural-ui-speak
     (format "%s. Current: %s. Global default: %s. Saved startup or draft baseline: %s. %s"
             (aref row 0) (aref row 1) (aref row 2) (aref row 3) (aref row 4)))))
(defun emacsvox-settings-changes-refresh ()
  "Refresh the snapshot while keeping the selected setting and column."
  (interactive)
  (emacsvox-aural-ui-refresh-tabulated
   (lambda () (setq tabulated-list-entries
                    (emacsvox-settings-changes--entries emacsvox-settings-changes--source)))))
(define-derived-mode emacsvox-settings-changes-mode emacsvox-aural-tabulated-mode
  "Changed-Settings"
  "Read changed loaded options and retained drafts; g refreshes, q returns."
  (setq tabulated-list-format [("Setting or draft" 42 t) ("Current" 20 t)
                               ("Global default" 20 t) ("Saved/baseline" 28 t) ("State" 0 nil)])
  (setq header-line-format "Read-only snapshot: loaded options and retained drafts; g refreshes, q returns")
  (emacsvox-aural-ui-configure-tabulated "changed settings" #'emacsvox-settings-changes--speak
                                       #'emacsvox-settings-changes-refresh)
  (tabulated-list-init-header))
(define-key emacsvox-settings-changes-mode-map (kbd "RET") #'emacsvox-settings-changes--speak)

;;;###autoload
(defun emacsvox-settings-changes ()
  "Review current values, saved defaults and drafts without changing them."
  (interactive)
  (emacsvox-aural-menu--open-browser
   (lambda ()
     (let ((source (current-buffer)) (buffer (get-buffer-create "*Emacsvox Changed Settings*")))
       (with-current-buffer buffer
         (unless (derived-mode-p 'emacsvox-settings-changes-mode) (emacsvox-settings-changes-mode))
         (setq emacsvox-settings-changes--source source)
         (emacsvox-aural-inspection-attach-source source)
         (emacsvox-settings-changes-refresh))
       (emacsvox-aural-ui-pop-to-buffer buffer)
       buffer))
   'emacsvox-settings-changes))
(provide 'emacsvox-settings-changes)
;;; emacsvox-settings-changes.el ends here
