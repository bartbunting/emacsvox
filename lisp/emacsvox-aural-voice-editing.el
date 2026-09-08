;;; emacsvox-aural-voice-editing.el --- Complete voice editing proposals -*- lexical-binding: t; -*-

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

;; Build complete named-voice proposals without writes or activation.  Physical
;; experiments explicitly choose shared adjustment scope and chain placement.

;;; Code:

(require 'emacsvox-aural-voice-drafts)
(require 'emacsvox-aural-compiler)

(defun emacsvox-aural-voice-editing--snapshot (palette voice routing)
  "Capture saved VOICE in PALETTE using explicit legacy ROUTING.
Temporary choices are deliberately excluded from the editable saved base."
  (let* ((entries (emacsvox-aural-voice-data--entries palette emacsvox-aural-voice-palette-registry))
         (resolved (emacsvox-aural-voice-data--resolve
                    voice palette emacsvox-aural-voice-palette-registry
                    emacsvox-aural-routing--choice-sets routing nil nil))
         (name (or (plist-get resolved :name) (user-error "Voice is not in this palette: %s" voice)))
         (binding (unless (eq (plist-get resolved :mode) 'owned)
                    (emacsvox-aural-voice-data--binding
                     (emacsvox-aural-voice-data--names name entries emacsvox-aural-default-voice-entries)
                     (plist-get routing :bindings)))))
    (list :name name :owner (plist-get resolved :palette)
          :diagnostics (copy-tree (plist-get resolved :diagnostics))
          :snapshot
          (append
           (list :definition (copy-tree (plist-get resolved :definition))
                :selectors (copy-tree (if (eq (plist-get resolved :mode) 'owned)
                                          (plist-get resolved :selectors) (plist-get binding :selectors)))
                :language (if (eq (plist-get resolved :mode) 'owned)
                              (plist-get resolved :language) (plist-get binding :language)))
           (when (plist-member resolved :choices)
             (list :choices (copy-tree (plist-get resolved :choices))))))))

(defun emacsvox-aural-voice-editing--definition-style (definition &optional seen)
  "Read raw DEFINITION as a style without compiling or registering a voice."
  (cond ((null definition) (emacsvox-aural--empty-voice-style))
        ((emacsvox-aural-voice-style-p definition) (copy-tree definition))
        ((emacsvox-aural--acss-p definition) (emacsvox-aural--acss-to-voice-style definition))
        ((and (symbolp definition) (not (memq definition seen)))
         (or (emacsvox-aural--personality-style definition)
             (and (boundp definition)
                  (emacsvox-aural-voice-editing--definition-style
                   (symbol-value definition) (cons definition seen)))
             (user-error "No inspectable settings for personality %s" definition)))
        (t (user-error "Cannot inspect this personality definition"))))

(defun emacsvox-aural-voice-editing--style (snapshot _palette)
  "Return SNAPSHOT's base style without compilation or contextual flattening."
  (let ((definition (plist-get snapshot :definition)))
    (copy-tree
     (if (and (symbolp definition) (plist-member snapshot :frozen-style))
         (plist-get snapshot :frozen-style)
       (emacsvox-aural-voice-editing--definition-style definition)))))

(defun emacsvox-aural-voice-editing--freeze (snapshot palette)
  "Freeze symbolic style values in SNAPSHOT for PALETTE.
Preserve the saved representation alongside the captured values."
  (let ((copy (copy-tree snapshot)))
    (if (symbolp (plist-get snapshot :definition))
        (plist-put copy :frozen-style (emacsvox-aural-voice-editing--style snapshot palette))
      copy)))

(defun emacsvox-aural-voice-editing--adjust (snapshot palette dimension value)
  "Set DIMENSION to stored VALUE in a new SNAPSHOT for PALETTE.
Preserve optional omissions until edited and retain zero and explicit nil."
  (let* ((result (copy-tree snapshot))
         (style (emacsvox-aural-voice-editing--style snapshot palette)))
    (dolist (required '(family average-pitch pitch-range stress richness))
      (let ((key (emacsvox-aural--voice-dimension-key required)))
        (unless (plist-member style key) (setq style (plist-put style key nil)))))
    (setq style (plist-put style (emacsvox-aural--voice-dimension-key dimension) value))
    (emacsvox-aural--validate-voice-style style "Voice editor")
    (plist-put result :definition style)))

(defun emacsvox-aural-voice-editing--keep (destination experiment part placement &optional index)
  "Combine DESTINATION and EXPERIMENT without flattening their other choices.
PART is physical, adjustments or both.  PLACEMENT is replace, preferred or
fallback; INDEX selects the replaced choice, defaulting to the first."
  (unless (memq part '(physical adjustments both)) (user-error "Choose what to keep"))
  (let ((result (copy-tree destination))
        (selector (copy-tree (car (plist-get experiment :selectors))))
        (chain (copy-tree (plist-get destination :selectors))))
    (when (memq part '(adjustments both))
      (setq result (plist-put result :definition (copy-tree (plist-get experiment :definition))))
      (setq result (map-delete result :frozen-style))
      (when (plist-member experiment :frozen-style)
        (setq result (plist-put result :frozen-style (copy-tree (plist-get experiment :frozen-style))))))
    (when (memq part '(physical both))
      (unless selector (user-error "Choose a physical voice for this experiment"))
      (emacsvox-aural-validate-routing-selector selector t)
      (setq chain
            (pcase placement
              ('preferred (cons selector chain))
              ('fallback (append chain (list selector)))
              ('replace
               (let ((index (or index 0)))
                 (cond ((and (null chain) (= index 0)) (list selector))
                       ((or (< index 0) (>= index (length chain))) (user-error "Choice no longer exists"))
                       (t (setf (nth index chain) selector) chain))))
              (_ (user-error "Choose where to place the physical voice"))))
      (setq result (plist-put result :selectors chain)))
    result))

(defun emacsvox-aural-voice-editing--new-id ()
  "Allocate a fresh local choice identity, frozen into its eventual proposal."
  (concat "voice-" (secure-hash 'sha256 (format "%S-%S-%S" (current-time) (emacs-pid) (random)))))

(defun emacsvox-aural-voice-editing--proposal (palette voice snapshot destination summary routing)
  "Propose SNAPSHOT for VOICE from PALETTE in DESTINATION with SUMMARY.
Legacy conversion uses explicitly captured ROUTING.  No registry is changed."
  (let* ((registry emacsvox-aural-voice-palette-registry)
         (source (gethash palette registry))
         (owned (eq (plist-get (emacsvox-aural-voice-palette-data-form source) :routing) 'owned))
         (entries (emacsvox-aural-voice-data--entries palette registry))
         (ids (mapcar (lambda (item) (cons (car (plist-get item :entry))
                                           (emacsvox-aural-voice-editing--new-id))) entries))
         (copy (cond ((not owned)
                      (emacsvox-aural-voice-data--convert registry palette destination summary routing ids))
                     ((not (eq palette destination))
                      (emacsvox-aural-voice-data--copy-owned
                       registry palette destination summary emacsvox-aural-routing--choice-sets ids))
                     ((emacsvox-aural-voice-palette-built-in source) (user-error "Copy this built-in palette first"))
                     (t (list :palette (emacsvox-aural-voice-palette-data-form source)))))
         (data (copy-tree (plist-get copy :palette)))
         (sets (copy-tree (plist-get copy :choice-sets)))
         (effective (copy-hash-table registry))
         item properties old-choices)
    (puthash destination (emacsvox-aural-compile-voice-palette-data data) effective)
    (setq item (cl-find voice (emacsvox-aural-voice-data--entries destination effective)
                        :key (lambda (item) (car (plist-get item :entry)))))
    (unless item (user-error "Unknown destination voice: %s" voice))
    (setq properties (copy-tree (cdr (plist-get item :entry))))
    (setq old-choices (emacsvox-aural-voice-data--choices
                       (plist-get item :palette) voice properties
                       (emacsvox-aural-routing--merge-choice-sets emacsvox-aural-routing--choice-sets sets)
                       (plist-get item :schema-version)))
    (let* ((selectors (copy-tree (plist-get snapshot :selectors)))
           (portable (cl-remove-if-not (lambda (s) (eq (plist-get s :scope) 'portable)) selectors))
           (reference (and (not (plist-get snapshot :reset-choices))
                           (eq (plist-get item :palette) destination)
                           (equal selectors (plist-get old-choices :selectors))
                           (plist-get properties :local-choices)))
           (definition (plist-get snapshot :definition))
           (layered (or (eq (plist-get data :schema-version) 3)
                        (plist-member snapshot :choices) (plist-member old-choices :choices)))
           (rows (when layered
                   (cond
                    ((and (plist-get snapshot :reset-choices)
                          (not (equal selectors (emacsvox-aural-voice-data--selectors
                                                 (plist-get snapshot :choices)))))
                     (emacsvox-aural-voice-data--wrap-selectors selectors))
                    ((plist-member snapshot :choices) (copy-tree (plist-get snapshot :choices)))
                    ((equal selectors (plist-get old-choices :selectors))
                     (if (plist-member old-choices :choices) (plist-get old-choices :choices)
                       (emacsvox-aural-voice-data--wrap-selectors selectors)))
                    (t (user-error "Edit complete choice records to preserve individual settings"))))))
      (when layered
        (emacsvox-aural-routing--validate-choices rows)
        (unless (equal selectors (emacsvox-aural-voice-data--selectors rows))
          (user-error "Physical choices and individual settings disagree"))
        (setq data (emacsvox-aural-voice-data--promote data)
              portable (emacsvox-aural-voice-data--portable-choices rows))
        (unless (equal rows (plist-get old-choices :choices)) (setq reference nil)))
      (dolist (selector selectors) (emacsvox-aural-validate-routing-selector selector t))
      (when (and (plist-get old-choices :diagnostics)
                 (not (plist-get snapshot :reset-choices))
                 (or (not (equal selectors (plist-get old-choices :selectors)))
                     (and layered (not (equal rows (plist-get old-choices :choices))))))
        (user-error "Reset missing local choices explicitly before changing the chain"))
      (when (and (not reference) (not (equal (if layered rows selectors) portable)))
        (setq reference (emacsvox-aural-voice-editing--new-id))
        (push (if layered
                  (list :schema-version 3 :id reference :palette destination :voice voice :choices rows)
                (list :id reference :palette destination :voice voice :selectors selectors)) sets))
      (setq properties (append (list (if (symbolp definition) :personality :style) (copy-tree definition)
                                     :choices portable)
                               (when reference (list :local-choices reference))
                               (when (plist-get snapshot :language) (list :language (plist-get snapshot :language)))))
      (setq data (plist-put data :entries
                            (cons (cons voice properties)
                                  (cl-remove voice (plist-get data :entries) :key #'car)))))
    (emacsvox-aural-compile-voice-palette-data data)
    (list :palette data :choice-sets sets)))

(defun emacsvox-aural-voice-editing--preview (snapshot palette policy text)
  "Create a full-chain base preview for SNAPSHOT, PALETTE, frozen POLICY and TEXT."
  (let ((style (emacsvox-aural-voice-editing--style snapshot palette)) acss effects)
    (dolist (dimension '(average-pitch pitch-range stress richness))
      (let* ((key (emacsvox-aural--voice-dimension-key dimension)) (value (plist-get style key)))
        (when (numberp value) (setq acss (plist-put acss key (/ (float (max 0 (min 9 value))) 9))))))
    (dolist (dimension emacsvox-aural-post-synthesis-dimensions)
      (let* ((key (emacsvox-aural--voice-dimension-key dimension)) (value (plist-get style key)))
        (when (numberp value)
          (setq effects (plist-put effects key (emacsvox-aural-normalize-post-synthesis-value dimension value))))))
    (list :text text :selectors (copy-tree (plist-get snapshot :selectors))
          :language (plist-get snapshot :language) :acss acss
          :rate-offset (plist-get style :rate-offset) :effects effects
          :fallback-policy (emacsvox-aural-voice-runtime--preview-policy (list :policy policy))
          :disabled-engine-ids (copy-sequence (plist-get policy :disabled-engines)))))

(provide 'emacsvox-aural-voice-editing)
;;; emacsvox-aural-voice-editing.el ends here
