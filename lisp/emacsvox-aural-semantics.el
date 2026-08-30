;;; emacsvox-aural-semantics.el --- Browse aural semantics -*- lexical-binding: t; -*-

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

;; Semantic selection, representative facts, reference discovery, and the
;; accessible browser for the registered aural vocabulary.

;;; Code:

(require 'cl-lib)
(require 'help-mode)
(require 'subr-x)
(require 'tabulated-list)
(require 'emacsvox-aural-schemes)
(require 'emacsvox-aural-ui)
(require 'emacsvox-aural-inspection)
(require 'emacsvox-aural-description)
(require 'emacsvox-aural-validation)

(declare-function emacsvox-speak-help "emacsvox-speak" ())
(declare-function tts-speak "tts-speak" (text))

(autoload 'emacsvox-aural "emacsvox-aural-home"
  "Open the spoken aural presentation home." t)

(defun emacsvox-aural-semantics-read (&optional prompt allow-empty)
  "Read a registered semantic using PROMPT.

When ALLOW-EMPTY is non-nil, return nil for an empty answer."
  (let* ((answer
          (completing-read
           (or prompt "Aural semantic: ")
           (if allow-empty
               (cons "" (emacsvox-aural-semantic-candidates))
             (emacsvox-aural-semantic-candidates))
           nil 'must-match))
         (id (and (not (string-empty-p answer)) (intern answer))))
    id))

(defun emacsvox-aural-semantics-representative-facts (id)
  "Return representative facts for registered semantic ID."
  (let ((record (emacsvox-aural-semantic id)))
    (unless record
      (user-error "Unknown aural semantic: %S" id))
    (pcase (emacsvox-aural-semantic-kind record)
      ('role (list :role id))
      ('event (list :event id))
      ('state (list :state id))
      ('attribute
       (let* ((allowed (emacsvox-aural-semantic-allowed-values record))
              (value
               (cond
                (allowed
                 (intern
                  (completing-read
                   (format "%s value: " id)
                   (mapcar #'symbol-name allowed)
                   nil 'must-match)))
                ((eq
                  (emacsvox-aural-semantic-value-type record)
                  'positive-integer)
                 (let ((number
                        (read-number (format "%s value: " id))))
                   (unless (> number 0)
                     (user-error "%s must be positive" id))
                   number))
                ((eq
                  (emacsvox-aural-semantic-value-type record)
                  'integer)
                 (read-number (format "%s value: " id)))
                ((eq
                  (emacsvox-aural-semantic-value-type record)
                  'symbol)
                 (intern (read-string (format "%s value: " id))))
                (t
                 (read-string (format "%s value: " id))))))
         (list (intern (format ":%s" id)) value))))))

(defun emacsvox-aural-semantics-facts-or-read ()
  "Return facts at point or interactively construct representative facts."
  (or
   (emacsvox-aural-facts-at-point)
   (emacsvox-aural-semantics-representative-facts
    (emacsvox-aural-semantics-read))))

(defun emacsvox-aural-semantics--selector-references-p
    (selector semantic)
  "Return non-nil when SELECTOR references SEMANTIC."
  (or
   (eq semantic (emacsvox-aural-selector-role selector))
   (memq semantic (emacsvox-aural-selector-events selector))
   (memq semantic (emacsvox-aural-selector-states selector))
   (assq semantic (emacsvox-aural-selector-attributes selector))
   (memq
    semantic
    (emacsvox-aural-selector-required-attributes selector))))

(defun emacsvox-aural-semantics--rule-references-p (rule semantic)
  "Return non-nil when RULE selects or renders SEMANTIC."
  (or
   (emacsvox-aural-semantics--selector-references-p
    (emacsvox-aural-rule-selector rule) semantic)
   (cl-some
    (lambda (action)
      (memq semantic (emacsvox-aural-action-template-fields action)))
    (emacsvox-aural-rule-actions rule))))

(defun emacsvox-aural-semantics--rules-for (semantic)
  "Return registered presentation and rule identifiers using SEMANTIC."
  (let (references)
    (cl-labels
        ((collect
          (owner compiled)
          (dolist
              (rule (emacsvox-aural-scheme-rules compiled))
            (when
                (emacsvox-aural-semantics--rule-references-p
                 rule semantic)
              (push
               (cons owner (emacsvox-aural-rule-id rule))
               references)))))
      (maphash
       (lambda (scheme-id entry)
         (collect
          scheme-id
          (emacsvox-aural-scheme-entry-compiled entry)))
       emacsvox-aural-scheme-registry)
      (maphash
       (lambda (fragment-id entry)
         (collect
          fragment-id
          (emacsvox-aural-feature-fragment-entry-compiled entry)))
       emacsvox-aural-feature-fragment-registry)
      (maphash
       (lambda (fragment-id fragment)
         (collect
          fragment-id
          (emacsvox-aural-module-fragment-compiled fragment)))
       emacsvox-aural-module-fragment-registry))
    (sort
     references
     (lambda (left right)
       (string-lessp
        (format "%s/%s" (car left) (cdr left))
        (format "%s/%s" (car right) (cdr right)))))))

(defun emacsvox-aural-semantics--set-entries ()
  "Populate the current semantic-list buffer."
  (setq
   tabulated-list-entries
   (mapcar
    (lambda (record)
      (let ((id (emacsvox-aural-semantic-id record)))
        (list
         id
         (vector
          (symbol-name id)
          (symbol-name (emacsvox-aural-semantic-kind record))
          (symbol-name (emacsvox-aural-semantic-owner record))
          (emacsvox-aural-semantic-summary record)))))
    (emacsvox-aural-semantics))))

(defun emacsvox-aural-semantics--goto (semantic)
  "Move to SEMANTIC in the current semantic-list buffer."
  (emacsvox-aural-ui-goto-row semantic))

(defun emacsvox-aural-semantics-refresh (&optional semantic)
  "Refresh the semantic list, preserving SEMANTIC and the current column."
  (interactive)
  (emacsvox-aural-ui-refresh-tabulated
   #'emacsvox-aural-semantics--set-entries semantic))

(defun emacsvox-aural-semantics-speak-current ()
  "Speak a concise description of the semantic at point."
  (interactive)
  (let* ((semantic
          (or
           (tabulated-list-get-id)
           (user-error "Move to a semantic row first")))
         (record (emacsvox-aural-semantic semantic))
         (summary
          (format
           "%s. %s, owner %s. %s"
           (emacsvox-aural-humanize semantic)
           (emacsvox-aural-semantic-kind record)
           (emacsvox-aural-humanize
            (emacsvox-aural-semantic-owner record))
           (emacsvox-aural-semantic-summary record))))
    (if (fboundp 'tts-speak)
        (tts-speak summary)
      (message "%s" summary))
    summary))

(defun emacsvox-aural-semantics-speak-current-cell ()
  "Speak the current semantic column title and value."
  (interactive)
  (emacsvox-aural-ui-speak-current-cell))

(defun emacsvox-aural-semantics-next ()
  "Move to and speak the next semantic."
  (interactive)
  (emacsvox-aural-ui-move-row 1 "semantic list"))

(defun emacsvox-aural-semantics-previous ()
  "Move to and speak the previous semantic."
  (interactive)
  (emacsvox-aural-ui-move-row -1 "semantic list"))

(defun emacsvox-aural-semantics-next-column ()
  "Move right and speak the next semantic column title and value."
  (interactive)
  (emacsvox-aural-ui-move-column 1))

(defun emacsvox-aural-semantics-previous-column ()
  "Move left and speak the previous semantic column title and value."
  (interactive)
  (emacsvox-aural-ui-move-column -1))

(defun emacsvox-aural-semantics-help ()
  "Display and speak semantic-list help."
  (interactive)
  (with-help-window (help-buffer)
    (princ
     (concat
      "Aural Semantic List\n\n"
      "n or down next       p or up previous\n"
      "left/right column    . speak titled cell\n"
      "RET view details     SPC speak semantic\n"
      "g refresh            h aural home\n"
      "q quit\n")))
  (when (fboundp 'emacsvox-speak-help)
    (emacsvox-speak-help)))

(define-derived-mode emacsvox-aural-semantics-mode
    emacsvox-aural-tabulated-mode
  "Aural-Semantics"
  "Major mode for browsing registered aural semantics."
  (emacsvox-aural-ui-configure-tabulated
   "semantic list"
   #'emacsvox-aural-semantics-speak-current
   #'emacsvox-aural-semantics-refresh)
  (setq
   tabulated-list-format
   [("Identifier" 28 t)
    ("Kind" 12 t)
    ("Owner" 18 t)
    ("Intent" 0 t)])
  (setq tabulated-list-padding 2)
  (add-hook
   'tabulated-list-revert-hook
   #'emacsvox-aural-semantics--set-entries nil t)
  (tabulated-list-init-header))

(dolist
    (binding
     '(("RET" . emacsvox-describe-aural-semantic)
       ("h" . emacsvox-aural)
       ("?" . emacsvox-aural-semantics-help)))
  (define-key
   emacsvox-aural-semantics-mode-map
   (kbd (car binding))
   (cdr binding)))

(defun emacsvox-list-aural-semantics ()
  "Open the accessible list of registered semantic vocabulary."
  (interactive)
  (let ((source
         (emacsvox-aural-inspection-remember-source-buffer))
        (buffer (get-buffer-create "*Aural Semantics*")))
    (with-current-buffer buffer
      (emacsvox-aural-semantics-mode)
      (emacsvox-aural-inspection-attach-source source)
      (emacsvox-aural-semantics-refresh))
    (emacsvox-aural-ui-pop-to-buffer buffer)
    (when (called-interactively-p 'interactive)
      (emacsvox-aural-semantics-speak-current))
    buffer))

(defun emacsvox-describe-aural-semantic (&optional semantic)
  "Describe registered SEMANTIC and presentation data that uses it."
  (interactive)
  (let* ((semantic
          (or
           semantic
           (and
            (derived-mode-p 'emacsvox-aural-semantics-mode)
            (tabulated-list-get-id))
           (emacsvox-aural-semantics-read)))
         (record (emacsvox-aural-semantic semantic)))
    (unless record
      (user-error "Unknown aural semantic: %S" semantic))
    (with-help-window (help-buffer)
      (princ (format "%s\n\n" semantic))
      (princ (format "Kind: %s\n" (emacsvox-aural-semantic-kind record)))
      (princ (format "Owner: %s\n" (emacsvox-aural-semantic-owner record)))
      (princ (format "Intent: %s\n" (emacsvox-aural-semantic-summary record)))
      (when-let* ((fallback (emacsvox-aural-semantic-fallback record)))
        (princ (format "Fallback: %s\n" fallback)))
      (when-let* ((values (emacsvox-aural-semantic-allowed-values record)))
        (princ (format "Allowed values: %S\n" values)))
      (when-let* ((roles (emacsvox-aural-semantic-roles record)))
        (princ (format "Valid roles: %S\n" roles)))
      (when-let* ((attributes (emacsvox-aural-semantic-attributes record)))
        (princ (format "Valid attributes: %S\n" attributes)))
      (when-let* ((states (emacsvox-aural-semantic-states record)))
        (princ (format "Valid states: %S\n" states)))
      (when-let* ((events (emacsvox-aural-semantic-events record)))
        (princ (format "Valid events: %S\n" events)))
      (when-let* ((occasions (emacsvox-aural-semantic-occasions record)))
        (princ (format "Occasions: %S\n" occasions)))
      (when-let* ((phases (emacsvox-aural-semantic-phases record)))
        (princ (format "Phases: %S\n" phases)))
      (when-let* ((usage (emacsvox-aural-semantic-usage record)))
        (princ (format "\nUsage\n\n%s\n" usage)))
      (when-let* ((aliases
                   (cl-remove-if-not
                    (lambda (alias)
                      (eq
                       (emacsvox-aural-canonical-semantic-id
                        (emacsvox-aural-semantic-alias-id alias))
                       (emacsvox-aural-semantic-id record)))
                    (emacsvox-aural-semantic-aliases))))
        (princ "\nDeprecated aliases\n\n")
        (dolist (alias aliases)
          (princ
           (format
            "%s, since contract version %d: %s\n"
            (emacsvox-aural-semantic-alias-id alias)
            (emacsvox-aural-semantic-alias-since-version alias)
            (or
             (emacsvox-aural-semantic-alias-summary alias)
             "Use the canonical identifier")))))
      (princ "\nRegistered presentations\n\n")
      (if-let* ((references
                 (emacsvox-aural-semantics--rules-for semantic)))
          (dolist (reference references)
            (princ (format "%s / %s\n" (car reference) (cdr reference))))
        (princ "No registered scheme rule references this semantic.\n")))))

(defalias 'emacsvox-aural-list-semantics
  #'emacsvox-list-aural-semantics)
(defalias 'emacsvox-aural-describe-semantic
  #'emacsvox-describe-aural-semantic)

(provide 'emacsvox-aural-semantics)

;;; emacsvox-aural-semantics.el ends here
