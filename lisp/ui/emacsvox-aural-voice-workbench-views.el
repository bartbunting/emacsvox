;;; emacsvox-aural-voice-workbench-views.el --- Voice workbench views -*- lexical-binding: t; -*-

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
;; Row descriptions, columns, filtering and language trees for Voice Workbench.
;; These helpers use the current workbench's captured inventory and draft.
;; They own derived display rows and language expansion, while the main module
;; owns editing, asynchronous observations, preview and save/apply operations.
;; Load through `emacsvox-aural-voice-workbench'.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'tabulated-list)
(require 'tts-speak)
(require 'emacsvox-aural-resources)
(require 'emacsvox-aural-schemes)
(require 'emacsvox-aural-routing-profiles)
(require 'emacsvox-aural-ui)
(require 'emacsvox-aural-voice-palettes)

(declare-function emacsvox-aural-voice-editor--status-for
                  "emacsvox-aural-voice-editor" (palette voice))
(declare-function emacsvox-omnivox-components--browse-engines
                  "emacsvox-omnivox-components" (engines))

(declare-function emacsvox-aural-voice-workbench--active-palette
                  "emacsvox-aural-voice-workbench" ())
(declare-function emacsvox-aural-voice-workbench--dirty-p
                  "emacsvox-aural-voice-workbench" ())
(declare-function emacsvox-aural-voice-workbench--apply-status-description
                  "emacsvox-aural-voice-workbench" ())
(declare-function emacsvox-aural-voice-workbench--library-p
                  "emacsvox-aural-voice-workbench" ())
(declare-function emacsvox-aural-voice-workbench--library-index
                  "emacsvox-aural-voice-workbench" ())
(declare-function emacsvox-aural-voice-workbench--browse-pairs
                  "emacsvox-aural-voice-workbench" ())
(declare-function emacsvox-aural-voice-workbench--filtered-pairs
                  "emacsvox-aural-voice-workbench" (&optional all))
(declare-function emacsvox-aural-voice-workbench--quick-description
                  "emacsvox-aural-voice-workbench" (filter))
(declare-function emacsvox-aural-voice-workbench--library-states
                  "emacsvox-aural-voice-workbench" (id))
(declare-function emacsvox-aural-voice-workbench--unavailable-reason
                  "emacsvox-aural-voice-workbench-preview" (pair))
(defvar emacsvox-aural-voice-workbench--library-error)
(defvar emacsvox-aural-voice-workbench--library-ticket)
(defvar emacsvox-aural-voice-workbench--views)
(defvar emacsvox-aural-voice-workbench-view)
(defvar emacsvox-aural-voice-workbench-inventory)
(defvar emacsvox-aural-voice-workbench-staged-profile)
(defvar emacsvox-aural-voice-workbench--voice-list-parent)
(defvar emacsvox-aural-voice-workbench--details-parent)
(defvar emacsvox-aural-voice-workbench-filter)
(defvar emacsvox-aural-voice-workbench--quick-filter)
(defvar emacsvox-aural-voice-workbench--language-expansion)
(defvar emacsvox-aural-voice-workbench--voice-languages)
(defvar emacsvox-aural-voice-workbench--language-order)
(defvar emacsvox-aural-voice-workbench--language-names)
(defvar emacsvox-aural-voice-workbench--region-names)
(defvar emacsvox-aural-voice-workbench-last-preview)
(defvar emacsvox-aural-voice-workbench--index-snapshot)

(defun emacsvox-aural-voice-workbench--inventory-counts ()
  "Return the engine and physical voice counts in the current inventory."
  (let ((engines
         (plist-get emacsvox-aural-voice-workbench-inventory :engines))
        (voices 0))
    (dolist (engine engines)
      (cl-incf voices (length (plist-get engine :voices))))
    (cons (length engines) voices)))

(defun emacsvox-aural-voice-workbench--age-description ()
  "Return concise inventory age text."
  (if-let* ((age
             (plist-get
              emacsvox-aural-voice-workbench-inventory :age-seconds)))
      (cond
       ((< age 1) "now")
       ((< age 60) (format "%d seconds" (floor age)))
       ((< age 3600) (format "%d minutes" (floor (/ age 60))))
       (t (format "%d hours" (floor (/ age 3600)))))
    "not timed"))

(defun emacsvox-aural-voice-workbench--physical-filter ()
  "Return explicit filters with the current engine browser's temporary scope."
  (if emacsvox-aural-voice-workbench--voice-list-parent
      (plist-put (copy-tree emacsvox-aural-voice-workbench-filter)
                 :engine emacsvox-aural-voice-workbench--voice-list-parent)
    emacsvox-aural-voice-workbench-filter))

(defun emacsvox-aural-voice-workbench--filter-description ()
  "Return concise physical filter text."
  (let (parts)
    (cl-loop
     for (key value) on (emacsvox-aural-voice-workbench--physical-filter) by #'cddr
     when value
     do (push (format "%s=%s" (substring (symbol-name key) 1) value) parts))
    (if parts (mapconcat #'identity (nreverse parts) ",") "none")))

(defun emacsvox-aural-voice-workbench--engine-order-description ()
  "Return concise saved or temporary engine-order status."
  (if emacsvox-aural-session-engine-order
      (format "%s first for session"
              (car emacsvox-aural-session-engine-order))
    "saved engine order"))

(defun emacsvox-aural-voice-workbench--header ()
  "Return the non-speaking status header for the current workbench."
  (if (emacsvox-aural-voice-workbench--library-p)
      (format " RET expand/sample; P sample; x details; t tune; + enable/disable; a Apply; d download; Q filters (1–4); / find; R refresh; q back | %s | %s"
              (emacsvox-aural-voice-workbench--quick-description emacsvox-aural-voice-workbench--quick-filter)
              (cond (emacsvox-aural-voice-workbench--library-ticket "Loading library")
                    (emacsvox-aural-voice-workbench--library-error emacsvox-aural-voice-workbench--library-error)
                    (t "Enabled is desired; Active is usable on a stream, not memory residency")))
    (let* ((inventory emacsvox-aural-voice-workbench-inventory)
         (counts (emacsvox-aural-voice-workbench--inventory-counts))
         (generation (plist-get inventory :generation))
         (profile (or (plist-get
                       emacsvox-aural-voice-workbench-staged-profile :id)
                      "none")))
    (format
     (concat
      " %s | adapter %s | inventory %s%s, generation %s, age %s | "
      "%d engines, %d voices | processes %s | routing %s, %s, %s, "
      "apply %s | filter %s | "
      "preview %s%s ")
     (alist-get emacsvox-aural-voice-workbench-view
                emacsvox-aural-voice-workbench--views)
     (or (plist-get inventory :adapter) "unknown")
     (or (plist-get inventory :source) "unknown")
     (if (plist-get inventory :stale) " stale" "")
     (or generation "none")
     (emacsvox-aural-voice-workbench--age-description)
     (car counts) (cdr counts)
     (or (plist-get inventory :process-agreement) "unknown")
     profile
     (if (emacsvox-aural-voice-workbench--dirty-p) "staged" "committed")
     (emacsvox-aural-voice-workbench--engine-order-description)
     (emacsvox-aural-voice-workbench--apply-status-description)
     (emacsvox-aural-voice-workbench--filter-description)
     (or (plist-get emacsvox-aural-voice-workbench-last-preview :status)
         "not run")
     (if emacsvox-aural-voice-workbench--details-parent
         " | Main speech target; q returns to engine details" "")))))

(defun emacsvox-aural-voice-workbench--resolved-voice (logical-voice)
  "Resolve LOGICAL-VOICE with complete saved choices and staged engine policy."
  (emacsvox-aural-voice-runtime--resolve
   logical-voice (emacsvox-aural-voice-workbench--active-palette)
   emacsvox-aural-voice-workbench-staged-profile))

(defun emacsvox-aural-voice-workbench--selectors (logical-voice)
  "Return the complete ordered choices for LOGICAL-VOICE."
  (plist-get (emacsvox-aural-voice-workbench--resolved-voice logical-voice) :selectors))

(defun emacsvox-aural-voice-workbench--logical-voices ()
  "Return effective named voices from the active palette."
  (sort (mapcar (lambda (entry) (symbol-name (car entry)))
                (emacsvox-aural-effective-voice-entries
                 (emacsvox-aural-voice-workbench--active-palette))) #'string-lessp))

(defun emacsvox-aural-voice-workbench--selector-description (selector)
  "Return concise display text for routing SELECTOR."
  (pcase (plist-get selector :kind)
    ('exact
     (format "%s/%s [%s]"
             (plist-get selector :engine-id)
             (plist-get selector :voice-id)
             (plist-get selector :scope)))
    ('engine-default
     (format "%s default [%s]"
             (plist-get selector :engine-id)
             (plist-get selector :scope)))
    ('properties
     (let (traits)
       (dolist (property '(:engine-id :language :gender))
         (when-let* ((value (plist-get selector property)))
           (push (format "%s" value) traits)))
       (format "%s properties [%s]"
               (if traits (mapconcat #'identity (nreverse traits) "/") "any")
               (plist-get selector :scope))))
    (_ "invalid selector")))

(defun emacsvox-aural-voice-workbench--route-description (logical-voice)
  "Return concise staged route text for LOGICAL-VOICE."
  (if-let* ((selectors
             (emacsvox-aural-voice-workbench--selectors logical-voice)))
      (mapconcat
       #'emacsvox-aural-voice-workbench--selector-description selectors " then ")
    "adapter default"))

(defun emacsvox-aural-voice-workbench--scope-description (_logical-voice)
  "Describe named choices separately from shared workstation policy."
  "palette-owned; policy shared")

(defun emacsvox-aural-voice-workbench--provenance-description (logical-voice)
  "Describe the saved source of LOGICAL-VOICE."
  (let ((voice (emacsvox-aural-voice-workbench--resolved-voice logical-voice)))
    (format "%s in %s" (or (plist-get voice :choice-source) 'automatic)
            (plist-get voice :palette))))

(defun emacsvox-aural-voice-workbench--palette-entry (logical-voice)
  "Return the complete model's named definition for LOGICAL-VOICE."
  (let* ((palette (emacsvox-aural-voice-workbench--active-palette))
         (resolved (emacsvox-aural-voice-runtime--resolve logical-voice palette
                                                        emacsvox-aural-voice-workbench-staged-profile)))
    (when (plist-get resolved :name)
      (cons (plist-get resolved :name) (plist-get resolved :definition)))))

(defun emacsvox-aural-voice-workbench--palette-aliases (logical-voice)
  "Return the canonical palette name for LOGICAL-VOICE."
  (when-let* ((name (plist-get (emacsvox-aural-voice-workbench--resolved-voice logical-voice) :name)))
    (list (symbol-name name))))

(defun emacsvox-aural-voice-workbench--style-description (logical-voice)
  "Return concise portable style text for LOGICAL-VOICE."
  (if-let* ((entry
             (emacsvox-aural-voice-workbench--palette-entry logical-voice)))
      (let* ((definition (cdr entry))
             (realized
              (if (and (symbolp definition) (boundp definition))
                  (symbol-value definition)
                definition)))
        (string-trim
         (replace-regexp-in-string
          "[\n\t ]+" " " (format "%S" realized))))
    "not in active palette"))

(defun emacsvox-aural-voice-workbench--family-diagnostic (logical-voice)
  "Return concise exact-route/family status for LOGICAL-VOICE."
  (let* ((entry (emacsvox-aural-voice-workbench--palette-entry logical-voice))
         (definition
          (if entry
              (let ((value (cdr entry)))
                (if (and (symbolp value) (boundp value))
                    (symbol-value value)
                  value))
            logical-voice))
         (family
          (emacsvox-aural-routing--style-family definition))
         (exact
          (cl-find-if
           (lambda (selector) (eq (plist-get selector :kind) 'exact))
           (emacsvox-aural-voice-workbench--selectors logical-voice))))
    (if (and family exact)
        (format "exact voice; %s family retained for fallback" family)
      "none")))

(defun emacsvox-aural-voice-workbench--logical-row (logical-voice)
  "Return one logical voice row for LOGICAL-VOICE."
  (let* ((binding
          (emacsvox-aural-voice-workbench--resolved-voice logical-voice))
         (route
          (emacsvox-aural-voice-workbench--route-description logical-voice))
         (palette (emacsvox-aural-voice-workbench--active-palette)))
    (list
     logical-voice
     (vector
      (format "%s" palette)
      (emacsvox-aural-voice-workbench--join-symbols
       (emacsvox-aural-voice-workbench--palette-aliases logical-voice))
      logical-voice
      (emacsvox-aural-voice-workbench--style-description logical-voice)
      route
      (emacsvox-aural-voice-workbench--realization-description logical-voice)
      (emacsvox-aural-voice-workbench--last-played-description logical-voice)
      (emacsvox-aural-voice-workbench--registration-description logical-voice)
      (or (plist-get binding :language) "")
      (emacsvox-aural-voice-workbench--scope-description logical-voice)
      (or (and (fboundp 'emacsvox-aural-voice-editor--status-for)
               (emacsvox-aural-voice-editor--status-for palette logical-voice))
          (if (equal route "adapter default") "unmapped" "routed"))
      (emacsvox-aural-voice-workbench--provenance-description logical-voice)
      (emacsvox-aural-voice-workbench--family-diagnostic logical-voice)))))

(defun emacsvox-aural-voice-workbench--all-engine-voices ()
  "Return (ENGINE VOICE) pairs from the current inventory."
  (cl-loop
   for engine in (plist-get emacsvox-aural-voice-workbench-inventory :engines)
   append (mapcar (lambda (voice) (list engine voice))
                  (plist-get engine :voices))))

(defun emacsvox-aural-voice-workbench--same-value-p (left right)
  "Return non-nil when optional inventory values LEFT and RIGHT match."
  (and left right (string-equal (downcase (format "%s" left))
                                (downcase (format "%s" right)))))

(defun emacsvox-aural-voice-workbench--display (value &optional fallback)
  "Return VALUE as display text, using FALLBACK when it is nil."
  (if (null value) (or fallback "") (format "%s" value)))

(defun emacsvox-aural-voice-workbench--selector-matches-p
    (selector engine voice)
  "Return non-nil when SELECTOR can select VOICE from ENGINE."
  (let ((engine-id (plist-get engine :engine-id))
        (voice-id (plist-get voice :voice-id)))
    (pcase (plist-get selector :kind)
      ('exact
       (and (equal engine-id (plist-get selector :engine-id))
            (equal voice-id (plist-get selector :voice-id))))
      ('engine-default
       (and (equal engine-id (plist-get selector :engine-id))
            (equal voice-id (plist-get engine :default-voice-id))))
      ('properties
       (and
        (or (null (plist-get selector :engine-id))
            (equal engine-id (plist-get selector :engine-id)))
        (or (null (plist-get selector :language))
            (emacsvox-aural-voice-workbench--same-value-p
             (plist-get selector :language) (plist-get voice :language)))
        (or (null (plist-get selector :gender))
            (emacsvox-aural-voice-workbench--same-value-p
             (plist-get selector :gender) (plist-get voice :gender))))))))

(defun emacsvox-aural-voice-workbench--selector-realization (selector)
  "Return the first installed engine/voice pair matching SELECTOR."
  (cl-find-if
   (lambda (pair)
     (let ((engine (car pair)) (voice (cadr pair)))
       (and
        (equal (plist-get engine :availability) "available")
        (equal (plist-get voice :availability) "available")
        (emacsvox-aural-voice-workbench--selector-matches-p
         selector engine voice))))
   (emacsvox-aural-voice-workbench--all-engine-voices)))

(defun emacsvox-aural-voice-workbench--default-tuning-selector ()
  "Return a session selector for the first usable preferred engine.

This selector auditions an otherwise unrouted logical voice without staging
or persisting a routing choice."
  (let* ((inventory emacsvox-aural-voice-workbench-inventory)
         (disabled
          (plist-get emacsvox-aural-voice-workbench-staged-profile
                     :disabled-engines))
         (candidates
          (delete-dups
           (append
            (copy-sequence
             (plist-get emacsvox-aural-voice-workbench-staged-profile
                        :engine-order))
            (copy-sequence (plist-get inventory :preferred-engine-order))
            (list (plist-get inventory :preferred-engine-id))
            (mapcar
             (lambda (engine) (plist-get engine :engine-id))
             (plist-get inventory :engines)))))
         engine-id)
    (while (and candidates (not engine-id))
      (let* ((candidate (pop candidates))
             (engine
              (and
               candidate
               (cl-find candidate (plist-get inventory :engines)
                        :key (lambda (item) (plist-get item :engine-id))
                        :test #'equal))))
        (when
            (and engine
                 (equal (plist-get engine :availability) "available")
                 (not (member candidate disabled)))
          (setq engine-id candidate))))
    (and engine-id
         (list :kind 'engine-default :scope 'session
               :engine-id engine-id))))

(defun emacsvox-aural-voice-workbench--realization-description
    (logical-voice)
  "Return the currently predicted installed route for LOGICAL-VOICE."
  (let ((selectors
         (emacsvox-aural-voice-workbench--selectors logical-voice))
        found)
    (while (and selectors (not found))
      (setq found
            (emacsvox-aural-voice-workbench--selector-realization
             (pop selectors))))
    (if found
        (format "%s/%s"
                (plist-get (car found) :engine-id)
                (plist-get (cadr found) :voice-id))
      (if (emacsvox-aural-voice-workbench--selectors logical-voice)
          "unavailable"
        "adapter default"))))

(defun emacsvox-aural-voice-workbench--last-played-description
    (logical-voice)
  "Return the last route observed during playback for LOGICAL-VOICE."
  (if-let* ((route (tts-last-realized-voice logical-voice)))
      (let ((base
             (format "%s/%s"
                     (or (plist-get route :engine-id) "unknown")
                     (or (plist-get route :voice-id) "default")))
            (acss (plist-get route :degraded-acss))
            (effects (plist-get route :degraded-effects)))
        (concat
         base
         (when (or acss effects)
           (format " omitted %s"
                   (mapconcat
                    (lambda (value) (format "%s" value))
                    (append acss effects) ",")))))
    "not observed"))

(defun emacsvox-aural-voice-workbench--registration-binding-name (binding)
  "Return logical voice name carried by registration BINDING."
  (let ((status (plist-get binding :status)))
    (cond
     ((equal status "resolved")
      (plist-get (plist-get binding :resolution) :logical_voice_id))
     ((equal status "unresolved")
      (plist-get (plist-get binding :error) :logical_voice_id)))))

(defun emacsvox-aural-voice-workbench--registration-description
    (logical-voice)
  "Return per-process registration result for LOGICAL-VOICE."
  (let ((name (format "%s" logical-voice)) parts)
    (dolist (process (plist-get emacsvox-aural-routing-apply-status :processes))
      (let ((role (or (plist-get process :role) 'speech)))
        (if (not (eq (plist-get process :status) 'applied))
            (push
             (if (eq 'timeout (plist-get process :phase))
                 (format "%s timed out; server outcome unconfirmed" role)
               (format "%s failed %s"
                       role (or (plist-get process :phase) "apply")))
             parts)
          (let* ((registration (plist-get process :registration))
                 (binding
                  (cl-find-if
                   (lambda (entry)
                     (equal name
                            (emacsvox-aural-voice-workbench--registration-binding-name
                             entry)))
                   (append (plist-get registration :bindings) nil))))
            (cond
             ((null binding)
              (push (format "%s adapter default" role) parts))
             ((equal (plist-get binding :status) "resolved")
              (let* ((resolution (plist-get binding :resolution))
                     (realized (plist-get resolution :realized)))
                (push
                 (format "%s %s/%s"
                         role
                         (plist-get realized :engine_id)
                         (plist-get realized :voice_id))
                 parts)))
             (t (push (format "%s unresolved" role) parts)))))))
    (if parts (mapconcat #'identity (nreverse parts) "; ")
      (pcase (plist-get emacsvox-aural-routing-apply-status :status)
        ('applying "applying")
        ('failed "apply failed")
        (_ "not registered")))))

(defun emacsvox-aural-voice-workbench--row-selectors ()
  "Resolve each logical voice once for a physical inventory redraw."
  (mapcar (lambda (logical)
            (cons logical (emacsvox-aural-voice-workbench--selectors logical)))
          (emacsvox-aural-voice-workbench--logical-voices)))

(defun emacsvox-aural-voice-workbench--voice-users (engine voice &optional selectors)
  "Return logical voices matching ENGINE and VOICE using resolved SELECTORS."
  (let (users)
    (dolist (entry (or selectors (emacsvox-aural-voice-workbench--row-selectors)))
      (when
          (cl-some
           (lambda (selector)
             (emacsvox-aural-voice-workbench--selector-matches-p
              selector engine voice))
           (cdr entry))
        (push (car entry) users)))
    (sort users #'string-lessp)))

(defun emacsvox-aural-voice-workbench--filter-match-p (key actual)
  "Return non-nil when physical filter KEY accepts ACTUAL."
  (let ((wanted (plist-get (emacsvox-aural-voice-workbench--physical-filter) key)))
    (or (null wanted)
        (emacsvox-aural-voice-workbench--same-value-p wanted actual))))

(defun emacsvox-aural-voice-workbench--physical-visible-p (engine voice)
  "Return non-nil when ENGINE and VOICE pass the physical filter."
  (and
   (emacsvox-aural-voice-workbench--filter-match-p
    :engine (plist-get engine :engine-id))
   (emacsvox-aural-voice-workbench--filter-match-p
    :language (plist-get voice :language))
   (emacsvox-aural-voice-workbench--filter-match-p
    :gender (plist-get voice :gender))
   (emacsvox-aural-voice-workbench--filter-match-p
    :quality (plist-get voice :quality))
   (emacsvox-aural-voice-workbench--filter-match-p
    :health (plist-get engine :health))
   (emacsvox-aural-voice-workbench--filter-match-p
    :availability (plist-get voice :availability))))

(defun emacsvox-aural-voice-workbench--physical-row (pair &optional selectors)
  "Return a row from engine/voice PAIR, reusing resolved SELECTORS when given."
  (let* ((engine (car pair))
         (voice (cadr pair))
         (users (emacsvox-aural-voice-workbench--voice-users engine voice selectors))
         (states (emacsvox-aural-voice-workbench--library-states
                  (list (plist-get engine :engine-id) (plist-get voice :voice-id)))))
    (list
     (list (plist-get engine :engine-id) (plist-get voice :voice-id))
     (vector
      (emacsvox-aural-voice-workbench--display
       (or (plist-get voice :display-name) (plist-get voice :voice-id)))
      (emacsvox-aural-voice-workbench--display
       (plist-get engine :engine-id))
      (emacsvox-aural-voice-workbench--display
       (plist-get voice :language))
      (emacsvox-aural-voice-workbench--display
       (plist-get voice :gender))
      (emacsvox-aural-voice-workbench--display
       (plist-get voice :quality))
      (if-let* ((reason (emacsvox-aural-voice-workbench--unavailable-reason pair)))
          (concat "unavailable: " reason)
        (emacsvox-aural-voice-workbench--display (plist-get voice :availability) "unknown"))
      (emacsvox-aural-voice-workbench--display
       (plist-get engine :health) "unknown")
      (if users (mapconcat #'identity users ", ") "none")
      (emacsvox-aural-voice-workbench--display
       (plist-get voice :voice-id))
      (nth 0 states)
      (nth 1 states)
      (nth 2 states)))))

(defun emacsvox-aural-voice-workbench--join-symbols (values)
  "Return printable comma-separated VALUES."
  (if values (mapconcat (lambda (value) (format "%s" value)) values ", ") "none"))

(defun emacsvox-aural-voice-workbench--engine-row (engine)
  "Return one speech ENGINE row."
  (let* ((id (plist-get engine :engine-id))
         (preferred-order
          (cl-position
           id
           (plist-get emacsvox-aural-voice-workbench-staged-profile
                      :engine-order)
           :test #'equal))
         (fallback-order
          (cl-position
           id
           (plist-get
            (plist-get emacsvox-aural-voice-workbench-staged-profile
                       :fallback)
            :engines)
           :test #'equal))
         (disabled
          (member
           id
           (plist-get emacsvox-aural-voice-workbench-staged-profile
                      :disabled-engines)))
         (live-disabled (plist-get engine :disabled-by-policy)))
    (list
     id
     (vector
      id
      (or (plist-get engine :display-name) id)
      (or (plist-get engine :availability) "unknown")
      (if preferred-order (number-to-string (1+ preferred-order))
        (if (equal id
                   (plist-get emacsvox-aural-voice-workbench-inventory
                              :preferred-engine-id))
            "server default" "unlisted"))
      (if fallback-order (number-to-string (1+ fallback-order)) "unlisted")
      (cond (disabled "disabled staged")
            (live-disabled "disabled live")
            (t "allowed"))
      (format "%s/%s"
              (or (plist-get engine :health) "unknown")
              (or (plist-get engine :circuit) "unknown"))
      (or (plist-get engine :last-failure)
          (plist-get engine :availability-reason)
          (plist-get engine :health-reason) "none")
      (if-let* ((milliseconds
                 (plist-get engine :cooldown-remaining-ms)))
          (format "%d ms" milliseconds)
        "none")
      (or (plist-get engine :audio-output) "unknown")
      (number-to-string (length (plist-get engine :voices)))
      (emacsvox-aural-voice-workbench--join-symbols
       (plist-get engine :marker-support))
      (or (plist-get engine :anchor-support) "none")
      (emacsvox-aural-voice-workbench--join-symbols
       (plist-get engine :post-synthesis-dimensions))))))

(defun emacsvox-aural-voice-workbench--post-effects ()
  "Return union of advertised post-synthesis effect dimensions."
  (let (effects)
    (dolist
        (engine
         (plist-get emacsvox-aural-voice-workbench-inventory :engines))
      (setq effects
            (append (plist-get engine :post-synthesis-dimensions) effects)))
    (delete-dups effects)))

(defun emacsvox-aural-voice-workbench--style-row (entry)
  "Return one active palette style/effect row for ENTRY."
  (let* ((palette-voice (car entry))
         (definition (cdr entry))
         (logical
          (format "%s" (if (symbolp definition) definition palette-voice)))
         (effects (emacsvox-aural-voice-workbench--post-effects))
         (dimensions
          (plist-get (tts-voice-capabilities) :dimensions)))
    (list
     logical
     (vector
      (format "%s" palette-voice)
      logical
      (emacsvox-aural-voice-workbench--style-description logical)
      (emacsvox-aural-voice-workbench--route-description logical)
      (emacsvox-aural-voice-workbench--last-played-description logical)
      (emacsvox-aural-voice-workbench--join-symbols dimensions)
      (if effects
          (emacsvox-aural-voice-workbench--join-symbols effects)
        "not advertised")
      (emacsvox-aural-voice-workbench--provenance-description logical)
      (emacsvox-aural-voice-workbench--family-diagnostic logical)))))

(defun emacsvox-aural-voice-workbench--detail-format ()
  "Return tabulated columns for the active workbench view."
  (pcase emacsvox-aural-voice-workbench-view
    ('logical
     [("Palette" 16 t) ("Canonical name" 24 t) ("Logical voice" 28 t)
      ("Requested style" 34 t) ("Selector order" 48 t)
      ("Predicted route" 24 t) ("Last played" 30 t)
      ("Registration" 36 t) ("Language" 12 t) ("Scope" 16 t)
      ("Status" 12 t) ("Provenance" 28 t) ("Diagnostic" 0 t)])
    ('physical
     [("Physical voice" 28 t) ("Engine" 14 t) ("Language" 12 t)
      ("Gender" 10 t) ("Quality" 12 t) ("Availability" 14 t)
      ("Health" 12 t) ("Selected by" 28 t) ("Native ID" 0 t)
      ("Installed" 16 t) ("Enabled" 16 t) ("Active" 28 t)])
    ('engines
     [("Engine ID" 16 t) ("Engine" 20 t) ("Availability" 14 t)
      ("Preferred" 12 t) ("Fallback" 10 t) ("Routing policy" 16 t)
      ("Health/circuit" 18 t) ("Last failure" 28 t) ("Cooldown" 12 t)
      ("Audio" 18 t) ("Voices" 8 t) ("Markers" 24 t)
      ("Anchors" 18 t) ("Effects" 0 t)])
    ('styles
     [("Palette voice" 22 t) ("Logical voice" 26 t)
      ("Portable definition" 38 t) ("Staged route" 42 t)
      ("Last played" 30 t)
      ("Adapter ACSS" 30 t) ("Supported post effects" 30 t)
      ("Provenance" 28 t)
      ("Diagnostic" 0 t)])))

(defun emacsvox-aural-voice-workbench--detail-entries ()
  "Return rows for the active workbench view."
  (pcase emacsvox-aural-voice-workbench-view
    ('logical
     (mapcar #'emacsvox-aural-voice-workbench--logical-row
             (emacsvox-aural-voice-workbench--logical-voices)))
    ('physical
     (let* ((emacsvox-aural-voice-workbench--index-snapshot
             (emacsvox-aural-voice-workbench--library-index))
            (pairs (emacsvox-aural-voice-workbench--filtered-pairs))
            (selectors (and pairs (emacsvox-aural-voice-workbench--row-selectors))))
       (mapcar (lambda (pair)
                 (emacsvox-aural-voice-workbench--physical-row pair selectors))
               pairs)))
    ('engines
     (mapcar
      #'emacsvox-aural-voice-workbench--engine-row
      (if (equal "omnivox" (plist-get emacsvox-aural-voice-workbench-inventory :adapter))
          (progn
            (require 'emacsvox-omnivox-components)
            (emacsvox-omnivox-components--browse-engines
             (plist-get emacsvox-aural-voice-workbench-inventory :engines)))
        (plist-get emacsvox-aural-voice-workbench-inventory :engines))))
    ('styles
     (let ((palette (emacsvox-aural-voice-workbench--active-palette)))
       (if (emacsvox-aural-voice-palette palette)
           (mapcar
            #'emacsvox-aural-voice-workbench--style-row
            (sort
             (copy-sequence (emacsvox-aural-effective-voice-entries palette))
             (lambda (left right)
               (string-lessp (symbol-name (car left))
                             (symbol-name (car right))))))
         nil)))))

(defun emacsvox-aural-voice-workbench--visible-columns ()
  "Return detail column indices to display in the current view."
  (pcase emacsvox-aural-voice-workbench-view
    ('logical '(2 3 4 5 6 10))
    ('physical (if (emacsvox-aural-voice-workbench--library-p)
                   '(0 1 2 9 10 11) '(0 1 2 3 4 5 6 7)))
    ('engines '(1 2 3 4 5 6 7 8 10))
    ('styles '(0 2 3 4 8))))

(defun emacsvox-aural-voice-workbench--visible-values (values)
  "Select visible columns from the full row or format VALUES."
  (vconcat (mapcar (lambda (index) (aref values index))
                  (emacsvox-aural-voice-workbench--visible-columns))))

(defun emacsvox-aural-voice-workbench--format ()
  "Return the concise table format for the current view."
  (let ((columns (emacsvox-aural-voice-workbench--visible-values
                  (emacsvox-aural-voice-workbench--detail-format))))
    (when (eq emacsvox-aural-voice-workbench-view 'physical)
      (dotimes (i (length columns))
        (let ((column i))
          (aset columns i
                (list (car (aref columns i)) (cadr (aref columns i))
                      (lambda (a b)
                        (emacsvox-aural-voice-workbench--sort-language-rows a b column)))))))
    columns))

(defun emacsvox-aural-voice-workbench--language-row-p (id)
  "Whether ID identifies a language heading rather than a physical voice."
  (eq (car-safe id) :language))

(defun emacsvox-aural-voice-workbench--language-label (tag)
  "Describe normalized language TAG, retaining unknown codes and subtags."
  (if (string-empty-p tag) "Unknown language"
    (let* ((parts (split-string tag "-" t))
           (name (cdr (assoc (car parts) emacsvox-aural-voice-workbench--language-names))))
      (if (not name) tag
        (string-join
         (cons name (mapcar (lambda (part)
                             (or (cdr (assoc part emacsvox-aural-voice-workbench--region-names))
                                 (upcase part)))
                           (cdr parts))) ", ")))))

(defun emacsvox-aural-voice-workbench--language-key (tag)
  "Return the expansion key for language TAG in the current engine scope."
  (list (plist-get (emacsvox-aural-voice-workbench--physical-filter) :engine) tag))

(defun emacsvox-aural-voice-workbench--sort-language-rows (a b column)
  "Sort voice rows A and B by COLUMN while retaining their language headings."
  (let* ((a-id (car a)) (b-id (car b))
         (a-group (emacsvox-aural-voice-workbench--language-row-p a-id))
         (b-group (emacsvox-aural-voice-workbench--language-row-p b-id))
         (a-order (gethash a-id emacsvox-aural-voice-workbench--language-order))
         (b-order (gethash b-id emacsvox-aural-voice-workbench--language-order))
         (reverse (cdr tabulated-list-sort-key)))
    (if (and (not a-group) (not b-group) (car a-order)
             (equal (car a-order) (car b-order)))
        (let ((a-value (downcase (aref (cadr a) column)))
              (b-value (downcase (aref (cadr b) column))))
          (if (equal a-value b-value)
              (string-lessp (format "%s" a-id) (format "%s" b-id))
            (string-lessp a-value b-value)))
      ;; Reverse column sorting must not reverse the tree or split a subtree.
      (< (cdr (if reverse b-order a-order))
         (cdr (if reverse a-order b-order))))))

(defun emacsvox-aural-voice-workbench--language-path (tag)
  "Return successive language and region prefixes from normalized TAG.
Private-use subtags identify voices, not extra branches such as X or GBCWMD."
  (let (prefix result)
    (catch 'private
      (dolist (part (split-string tag "-" t))
        (when (equal part "x") (throw 'private nil))
        (setq prefix (if prefix (concat prefix "-" part) part))
        (push prefix result)))
    (or (nreverse result) '(""))))

(defun emacsvox-aural-voice-workbench--group-languages (rows selected)
  "Group full physical ROWS in a language tree, revealing SELECTED's ancestors.
Single voices are direct rows.  Omit redundant branches with just one child."
  (unless emacsvox-aural-voice-workbench--language-expansion
    (setq emacsvox-aural-voice-workbench--language-expansion (make-hash-table :test #'equal)))
  (setq emacsvox-aural-voice-workbench--voice-languages (make-hash-table :test #'equal)
        emacsvox-aural-voice-workbench--language-order (make-hash-table :test #'equal))
  (let ((groups (make-hash-table :test #'equal))
        (children (make-hash-table :test #'equal))
        (leaves (make-hash-table :test #'equal))
        (order 0) selected-tag result)
    (dolist (row rows)
      (let* ((tag (downcase (string-replace "_" "-" (aref (cadr row) 2))))
             (visible (list (car row) (emacsvox-aural-voice-workbench--visible-values (cadr row))))
             parent)
        (puthash (car row) tag emacsvox-aural-voice-workbench--voice-languages)
        (dolist (prefix (emacsvox-aural-voice-workbench--language-path tag))
          (unless (gethash prefix groups)
            (puthash parent (cons prefix (gethash parent children)) children))
          (puthash prefix (cons visible (gethash prefix groups)) groups)
          (setq parent prefix))
        (puthash parent (cons visible (gethash parent leaves)) leaves)))
    (setq selected-tag
          (if (emacsvox-aural-voice-workbench--language-row-p selected) (cadr selected)
            (gethash selected emacsvox-aural-voice-workbench--voice-languages)))
    (cl-labels
        ((add-row (row depth parent)
           (aset (cadr row) 0 (concat (make-string (* 2 depth) ?\s) (aref (cadr row) 0)))
           (puthash (car row) (cons parent (cl-incf order)) emacsvox-aural-voice-workbench--language-order)
           (push row result))
         (branches (tag)
           (sort (copy-sequence (gethash tag children))
                 (lambda (a b)
                   (string-lessp (downcase (emacsvox-aural-voice-workbench--language-label a))
                                 (downcase (emacsvox-aural-voice-workbench--language-label b))))))
         (emit (tag depth automatic parent)
           (let ((members (gethash tag groups)) (nested (branches tag)) (direct (gethash tag leaves)))
             (cond
              ((= 1 (length members)) (add-row (car members) depth parent))
              ((and (null direct) (= 1 (length nested))) (emit (car nested) depth automatic parent))
              (t
               (let* ((key (emacsvox-aural-voice-workbench--language-key tag))
                      (state (gethash key emacsvox-aural-voice-workbench--language-expansion
                                      (if automatic 'expanded 'collapsed)))
                      (label (emacsvox-aural-voice-workbench--language-label tag))
                      (values (make-vector (length tabulated-list-format) "")))
                 (when (and selected-tag
                            (or (and (not (emacsvox-aural-voice-workbench--language-row-p selected))
                                     (equal tag selected-tag))
                                (string-prefix-p (concat tag "-") selected-tag)))
                   (setq state 'expanded))
                 (puthash key state emacsvox-aural-voice-workbench--language-expansion)
                 (when (> depth 0)
                   (setq label (car (last (split-string label ", " t)))))
                 (aset values 0 (emacsvox-aural-ui--expansion-text label (eq state 'expanded)))
                 (aset values 1 (format "%d voices; %s" (length members) state))
                 (add-row (list (list :language tag) values) depth parent)
                 (when (eq state 'expanded)
                   ;; Put all direct voice siblings together, including branches
                   ;; reduced to one voice, so any column sorts them consistently.
                   (dolist (child nested)
                     (when (= 1 (length (gethash child groups)))
                       (setq direct (append direct (gethash child groups)))))
                   (dolist (row (sort (copy-sequence direct)
                                     (lambda (a b) (string-lessp (downcase (aref (cadr a) 0))
                                                                (downcase (aref (cadr b) 0))))))
                     (add-row row (1+ depth) tag))
                   (dolist (child nested)
                     (when (> (length (gethash child groups)) 1)
                       (emit child (1+ depth) nil tag))))))))))
      (let ((roots (branches nil)))
        (dolist (tag roots) (emit tag 0 (= 1 (length roots)) nil))))
    (nreverse result)))

(defun emacsvox-aural-voice-workbench--entries (&optional selected)
  "Return concise rows, grouping physical voices and retaining SELECTED."
  (let ((rows (emacsvox-aural-voice-workbench--detail-entries)))
    (if (eq emacsvox-aural-voice-workbench-view 'physical)
        (emacsvox-aural-voice-workbench--group-languages rows selected)
      (mapcar (lambda (row)
                (list (car row) (emacsvox-aural-voice-workbench--visible-values (cadr row)))) rows))))

(defun emacsvox-aural-voice-workbench--physical-pair (id)
  "Return the physical engine/voice pair identified by ID."
  (when (emacsvox-aural-voice-workbench--language-row-p id)
    (user-error "Expand the language and choose a voice first"))
  (cl-find-if
   (lambda (pair)
     (equal id
            (list (plist-get (car pair) :engine-id)
                  (plist-get (cadr pair) :voice-id))))
   (emacsvox-aural-voice-workbench--browse-pairs)))

(provide 'emacsvox-aural-voice-workbench-views)

;;; emacsvox-aural-voice-workbench-views.el ends here
