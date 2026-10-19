;;; emacsvox-aural-voice-workbench.el --- Spoken voice routing UI -*- lexical-binding: t; -*-

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

;; A single accessible workbench presents logical voices, physical inventory,
;; engines, and portable style/effect information. Transactional previews use
;; the same sample text without changing saved palettes or routing profiles.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'tabulated-list)
(require 'tts-speak)
(require 'emacsvox-aural-resources)
(require 'emacsvox-aural-schemes)
(require 'emacsvox-aural-routing-profiles)
(require 'emacsvox-aural-ui)
(require 'emacsvox-aural-inspection)
(require 'emacsvox-aural-preview)
(require 'emacsvox-aural-voice-palettes)
(require 'omnivox-library)
(require 'emacsvox-aural-voice-workbench-views)
(require 'emacsvox-aural-voice-workbench-library)
(require 'emacsvox-aural-voice-workbench-preview)
(declare-function emacsvox-aural-voice-editor-open "emacsvox-aural-voice-editor" (palette voice &optional source text))
(declare-function emacsvox-aural-voice-editor-experiment "emacsvox-aural-voice-editor" (pair source text))
(declare-function emacsvox-aural-voice-editor--status-for "emacsvox-aural-voice-editor" (palette voice))
(declare-function emacsvox-aural-voice-bulk-open "emacsvox-aural-voice-bulk" (pair &optional origin))
(autoload 'emacsvox-aural-voice-bulk-resume "emacsvox-aural-voice-bulk" nil t)

(declare-function emacsvox-aural "emacsvox-aural-home"
                  (&optional source-buffer))
(declare-function emacsvox-speak-help "emacsvox-speak" ())
(declare-function tts-speak "tts-speak" (text))
(declare-function emacsvox-omnivox-components--open-engine
                  "emacsvox-omnivox-components" (id parent))
(declare-function emacsvox-omnivox-components--browse-engines
                  "emacsvox-omnivox-components" (engines))

(defconst emacsvox-aural-voice-workbench--views
  '((logical . "Logical voices")
    (physical . "Physical voices")
    (engines . "Engines")
    (styles . "Styles and effects"))
  "Workbench view identifiers and spoken titles.")

(defvar-local emacsvox-aural-voice-workbench-view 'logical
  "View displayed by the current Voice Workbench.")

(defvar-local emacsvox-aural-voice-workbench-inventory nil
  "Normalized speech-adapter inventory displayed by this workbench.")

(defvar-local emacsvox-aural-voice-workbench-committed-profile nil
  "Routing-profile snapshot committed when this workbench opened.")

(defvar-local emacsvox-aural-voice-workbench-staged-profile nil
  "Mutable routing-profile snapshot staged in this workbench.")

(defvar-local emacsvox-aural-voice-workbench-selections nil
  "Hash table retaining the selected row in each workbench view.")

(defvar-local emacsvox-aural-voice-workbench-rendered-view nil
  "View owning the currently rendered rows.")

(defvar-local emacsvox-aural-voice-workbench-columns nil
  "Hash table retaining the selected column for each view.")

(defvar-local emacsvox-aural-voice-workbench--voice-list-parent nil
  "Engine whose row opened the current physical voice list, or nil.")

(defvar-local emacsvox-aural-voice-workbench--details-parent nil
  "Engine details buffer to return to from a dedicated voice browser.")

(defvar-local emacsvox-aural-voice-workbench-filter nil
  "Physical-voice filter plist for this workbench.")

(defconst emacsvox-aural-voice-workbench--quick-filters
  '((all . "All voices") (downloaded . "Downloaded")
    (enabled . "Enabled") (needs-apply . "Needs Apply"))
  "Quick filters in shortcut order, from 1 to 4.")

(defvar-local emacsvox-aural-voice-workbench--quick-filter 'all
  "Current quick filter for physical voices.")

(defvar-local emacsvox-aural-voice-workbench--filter-counts nil
  "Counts from the latest redraw, before applying the quick filter.")

(defvar-local emacsvox-aural-voice-workbench--filter-positions nil
  "Rows and columns remembered for each engine scope and quick filter.")

(defvar-local emacsvox-aural-voice-workbench--language-expansion nil
  "Expansion choices indexed by engine scope and normalized language tag.")

(defvar-local emacsvox-aural-voice-workbench--voice-languages nil
  "Language tags indexed by the physical voice IDs in the latest redraw.")

(defvar-local emacsvox-aural-voice-workbench--language-order nil
  "Visible parent and tree order indexed by row ID for column sorting.")

(defconst emacsvox-aural-voice-workbench--language-names
  '(("af" . "Afrikaans") ("ar" . "Arabic") ("bg" . "Bulgarian")
    ("bn" . "Bengali") ("ca" . "Catalan") ("cs" . "Czech")
    ("cy" . "Welsh") ("da" . "Danish") ("de" . "German")
    ("el" . "Greek") ("en" . "English") ("eo" . "Esperanto")
    ("es" . "Spanish") ("et" . "Estonian") ("eu" . "Basque")
    ("fa" . "Persian") ("fi" . "Finnish") ("fr" . "French")
    ("ga" . "Irish") ("gl" . "Galician") ("gu" . "Gujarati")
    ("he" . "Hebrew") ("hi" . "Hindi") ("hr" . "Croatian")
    ("hu" . "Hungarian") ("hy" . "Armenian") ("id" . "Indonesian")
    ("is" . "Icelandic") ("it" . "Italian") ("ja" . "Japanese")
    ("ka" . "Georgian") ("kn" . "Kannada") ("ko" . "Korean")
    ("la" . "Latin") ("lt" . "Lithuanian") ("lv" . "Latvian")
    ("ml" . "Malayalam") ("ms" . "Malay") ("mt" . "Maltese")
    ("nb" . "Norwegian Bokmål") ("ne" . "Nepali") ("nl" . "Dutch")
    ("nn" . "Norwegian Nynorsk") ("no" . "Norwegian") ("pl" . "Polish")
    ("pt" . "Portuguese") ("ro" . "Romanian") ("ru" . "Russian")
    ("sk" . "Slovak") ("sl" . "Slovenian") ("sq" . "Albanian")
    ("sr" . "Serbian") ("sv" . "Swedish") ("sw" . "Swahili")
    ("ta" . "Tamil") ("te" . "Telugu") ("th" . "Thai") ; codespell:ignore te
    ("tr" . "Turkish") ("uk" . "Ukrainian") ("ur" . "Urdu")
    ("vi" . "Vietnamese") ("yue" . "Cantonese") ("zh" . "Chinese"))
  "Readable language labels; unrecognized tags remain visible verbatim.")

(defconst emacsvox-aural-voice-workbench--region-names
  '(("au" . "Australia") ("be" . "Belgium") ("br" . "Brazil")
    ("ca" . "Canada") ("ch" . "Switzerland") ("cn" . "China")
    ("de" . "Germany") ("es" . "Spain") ("fr" . "France")
    ("gb" . "United Kingdom") ("hk" . "Hong Kong") ("ie" . "Ireland")
    ("in" . "India") ("mx" . "Mexico") ("nz" . "New Zealand")
    ("pt" . "Portugal") ("tw" . "Taiwan") ("us" . "United States")
    ("za" . "South Africa"))
  "Readable region labels; other subtags retain their original identity.")

(defvar-local emacsvox-aural-voice-workbench-undo-stack nil
  "Snapshots preceding staged Voice Workbench routing edits.")

(defvar-local emacsvox-aural-voice-workbench-last-edit nil
  "Description of the most recent staged routing edit.")

(defvar-local emacsvox-aural-voice-workbench-applied-undo nil
  "Previous known-good profile available after one successful save.")

(defvar-local emacsvox-aural-voice-workbench-diagnostics nil
  "Current inventory and apply diagnostics for the staged profile.")

(defvar-local emacsvox-aural-voice-workbench-provenance nil
  "Ephemeral explanations for imported, preset, and suggested staged edits.")

(defconst emacsvox-aural-voice-workbench--session-profile-source
  'current-runtime-session
  "Source marker for an in-memory first-run routing profile.")

(defun emacsvox-aural-voice-workbench--active-palette ()
  "Return the currently effective portable voice palette."
  (or
   emacsvox-aural-voice-palette-override
   (emacsvox-aural-effective-scheme-provider 'voice-palette)
   'acss-default))

(defun emacsvox-aural-voice-workbench--current-profile-data (&optional inventory)
  "Return a safe routing snapshot using optional live INVENTORY."
  (if-let* ((entry
             (emacsvox-aural-routing-profile
              emacsvox-aural-active-routing-profile)))
      (copy-tree (emacsvox-aural-routing-profile-entry-data entry))
    (let* ((inventory (or inventory (tts-voice-inventory)))
           (profile
            (emacsvox-aural-routing-profile-from-omnivox
             (let ((id 'current-runtime)
                   (suffix 2))
               (while (emacsvox-aural-routing-profile id)
                 (setq id (intern (format "current-runtime-%d" suffix))
                       suffix (1+ suffix)))
               id)
             "Current unsaved adapter routing"))
           (preferred
            (or (copy-sequence
                 (plist-get inventory :preferred-engine-order))
                (and-let* ((engine-id
                            (plist-get inventory :preferred-engine-id)))
                  (list engine-id))))
           (fallback
            (copy-sequence (plist-get inventory :fallback-engine-order)))
           (disabled
            (copy-sequence (plist-get inventory :disabled-engine-ids))))
      (when preferred
        (setq profile (plist-put profile :engine-order preferred)))
      (when fallback
        (setf (plist-get (plist-get profile :fallback) :engines) fallback))
      (when disabled
        (setq profile (plist-put profile :disabled-engines disabled)))
      (emacsvox-aural-validate-routing-profile-data profile))))

(defun emacsvox-aural-voice-workbench--dirty-p ()
  "Return non-nil when staged routing differs from committed routing."
  (not
   (equal emacsvox-aural-voice-workbench-staged-profile
          emacsvox-aural-voice-workbench-committed-profile)))

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

(defun emacsvox-aural-voice-workbench-status ()
  "Return concise Voice Workbench status for Aural Home."
  (let* ((inventory (tts-voice-inventory))
         (engines (plist-get inventory :engines))
         (voices
          (cl-loop for engine in engines
                   sum (length (plist-get engine :voices)))))
    (format
     "%s; %s%s; %d engine%s, %d voice%s; routing %s; %s"
     (or (plist-get inventory :adapter) "unknown adapter")
     (or (plist-get inventory :source) "unknown inventory")
     (if (plist-get inventory :stale) " stale" "")
     (length engines) (if (= (length engines) 1) "" "s")
     voices (if (= voices 1) "" "s")
     (or emacsvox-aural-active-routing-profile "runtime")
     (emacsvox-aural-voice-workbench--engine-order-description))))

(defun emacsvox-aural-voice-workbench-use-across-palette ()
  "Review the selected physical voice across every named voice in a palette."
  (interactive)
  (unless (eq emacsvox-aural-voice-workbench-view 'physical)
    (user-error "Choose a physical voice in Browse voices first"))
  (let ((pair (or (emacsvox-aural-voice-workbench--physical-pair (tabulated-list-get-id))
                  (user-error "Choose a physical voice"))))
    (when-let* ((reason (emacsvox-aural-voice-workbench--unavailable-reason pair)))
      (user-error "%s" reason))
    (emacsvox-aural-voice-workbench-stop-preview)
    (require 'emacsvox-aural-voice-bulk)
    (emacsvox-aural-voice-bulk-open pair (current-buffer))))

(defun emacsvox-aural-voice-workbench--explicit-selectors (logical-voice)
  "Return LOGICAL-VOICE's explicitly staged selectors."
  (copy-tree
   (plist-get
    (emacsvox-aural-voice-workbench--resolved-voice logical-voice)
    :selectors)))

(defun emacsvox-aural-voice-workbench--announce (format-string &rest arguments)
  "Speak or display FORMAT-STRING with ARGUMENTS."
  (let ((text (apply #'format format-string arguments)))
    (if (fboundp 'tts-speak) (tts-speak text) (message "%s" text))
    text))

(defun emacsvox-aural-voice-workbench--active-profile ()
  "Return active routing profile data, or signal a user error."
  (if-let* ((entry
             (emacsvox-aural-routing-profile
              emacsvox-aural-active-routing-profile)))
      (emacsvox-aural-routing-profile-entry-data entry)
    (user-error "No active voice routing profile")))

(defun emacsvox-aural-voice-workbench--dirty-buffer ()
  "Return a live Voice Workbench buffer containing staged edits."
  (cl-find-if
   (lambda (buffer)
     (with-current-buffer buffer
       (and (derived-mode-p 'emacsvox-aural-voice-workbench-mode)
            (emacsvox-aural-voice-workbench--dirty-p))))
   (buffer-list)))

(defun emacsvox-aural-voice-workbench--ensure-clean ()
  "Reject a quick routing change while Workbench edits are staged."
  (when-let* ((buffer (emacsvox-aural-voice-workbench--dirty-buffer)))
    (user-error
     "Save or cancel staged Voice Workbench edits in %s first"
     (buffer-name buffer))))

(defun emacsvox-aural-voice-workbench--usable-engine-p
    (engine disabled-engines)
  "Return non-nil when ENGINE can be preferred under DISABLED-ENGINES."
  (let ((engine-id (plist-get engine :engine-id))
        (health (format "%s" (or (plist-get engine :health) "unknown"))))
    (and engine-id
         (equal (plist-get engine :availability) "available")
         (not (member health '("failed" "unavailable")))
         (not (member engine-id disabled-engines)))))

(defun emacsvox-aural-voice-workbench--engine-candidates
    (&optional inventory profile)
  "Return readable usable-engine candidates from INVENTORY under PROFILE."
  (let* ((inventory (or inventory (tts-voice-inventory)))
         (profile (or profile
                      (emacsvox-aural-voice-workbench--current-profile-data
                       inventory)))
         (effective
          (emacsvox-aural-routing-effective-profile-data profile))
         (order (plist-get effective :engine-order))
         (disabled (plist-get profile :disabled-engines)))
    (cl-loop
     for engine in (plist-get inventory :engines)
     when (emacsvox-aural-voice-workbench--usable-engine-p engine disabled)
     collect
     (let* ((engine-id (plist-get engine :engine-id))
            (position (cl-position engine-id order :test #'equal)))
       (cons
        (format "%s [%s; %s; %s]"
                (or (plist-get engine :display-name) engine-id)
                engine-id
                (or (plist-get engine :health) "unknown")
                (if position
                    (format "position %d" (1+ position))
                  "not ranked"))
        engine-id)))))

(defun emacsvox-aural-voice-workbench--read-engine ()
  "Read one currently usable speech engine ID."
  (let ((candidates
         (emacsvox-aural-voice-workbench--engine-candidates)))
    (unless candidates
      (user-error "No available speech engine can be preferred"))
    (cdr
     (assoc-string
      (completing-read
       "Prefer speech engine: " candidates nil 'must-match)
      candidates))))

(defun emacsvox-aural-voice-workbench--engine (engine-id inventory)
  "Return ENGINE-ID from normalized INVENTORY."
  (cl-find
   engine-id (plist-get inventory :engines)
   :key (lambda (engine) (plist-get engine :engine-id))
   :test #'equal))

(defun emacsvox-aural-voice-workbench--validate-engine
    (engine-id inventory profile)
  "Return ENGINE-ID when INVENTORY and PROFILE permit preferring it."
  (let ((engine
         (emacsvox-aural-voice-workbench--engine engine-id inventory)))
    (unless engine
      (user-error "Speech engine %s is not in the current inventory" engine-id))
    (when (member engine-id (plist-get profile :disabled-engines))
      (user-error "Speech engine %s is disabled by the active profile"
                  engine-id))
    (unless (equal (plist-get engine :availability) "available")
      (user-error "Speech engine %s is currently unavailable" engine-id))
    (when (member (format "%s" (plist-get engine :health))
                  '("failed" "unavailable"))
      (user-error "Speech engine %s is currently %s"
                  engine-id (plist-get engine :health)))
    engine-id))

(defun emacsvox-aural-voice-workbench--engine-display-name
    (engine-id inventory)
  "Return readable ENGINE-ID name from INVENTORY."
  (let ((engine
         (emacsvox-aural-voice-workbench--engine engine-id inventory)))
    (or (plist-get engine :display-name) engine-id)))

(defun emacsvox-aural-voice-workbench--preference-callback
    (display-name scope)
  "Return terminal apply callback for DISPLAY-NAME and preference SCOPE."
  (lambda (status)
    (pcase (plist-get status :status)
      ('applied
       (if (and (memq scope '(restored runtime-restored))
                (not display-name))
           (emacsvox-aural-voice-workbench--announce
            (if (eq scope 'runtime-restored)
                "Initial engine order restored"
              "Saved engine order restored"))
         (emacsvox-aural-voice-workbench--announce
          (pcase scope
            ('saved "%s is now the saved preferred engine")
            ('restored "Saved engine order restored; %s is preferred")
            ('runtime-restored
             "Initial engine order restored; %s is preferred")
            (_ "%s is now preferred for this session"))
          display-name)))
      ('partial
       (emacsvox-aural-voice-workbench--announce
        "%s preference applied to only some speech processes"
        display-name))
      (_
       (emacsvox-aural-voice-workbench--announce
        "Could not apply %s as preferred engine: %s"
        display-name (or (plist-get status :status) "unknown status"))))))

(defun emacsvox-aural-prefer-engine (engine-id &optional save)
  "Prefer ENGINE-ID globally while preserving explicit voice routes.

By default the change lasts for this Emacs session.  With prefix argument
SAVE, atomically save it in the active routing profile.  Remaining engines
keep their relative order; explicit logical-voice routes and fallback policy
are unchanged.  When no profile has been saved yet, the live adapter policy
becomes an in-memory baseline; SAVE explicitly persists that baseline.  The
command does not stop speech already playing."
  (interactive
   (progn
     (emacsvox-aural-voice-workbench--ensure-clean)
     (list (emacsvox-aural-voice-workbench--read-engine)
           current-prefix-arg)))
  (emacsvox-aural-voice-workbench--ensure-clean)
  (let* ((active-entry
          (emacsvox-aural-routing-profile
           emacsvox-aural-active-routing-profile))
         (inventory (tts-voice-inventory))
         (profile
          (if active-entry
              (emacsvox-aural-routing-profile-entry-data active-entry)
            (emacsvox-aural-voice-workbench--current-profile-data inventory)))
         (engine-id
          (emacsvox-aural-voice-workbench--validate-engine
           engine-id inventory profile))
         (display-name
          (emacsvox-aural-voice-workbench--engine-display-name
           engine-id inventory)))
    (if (not save)
        (progn
          (unless active-entry
            (emacsvox-aural-register-routing-profile-data
             profile
             emacsvox-aural-voice-workbench--session-profile-source)
            (setq emacsvox-aural-active-routing-profile
                  (plist-get profile :id))
            (run-hooks 'emacsvox-aural-routing-profile-changed-hook))
          (emacsvox-aural-prefer-engine-for-session
           engine-id
           (emacsvox-aural-voice-workbench--preference-callback
            display-name 'session)))
      (let ((previous-session
             (copy-sequence emacsvox-aural-session-engine-order))
            (preferred
             (emacsvox-aural-routing-prefer-engine-in-data
              profile engine-id)))
        (setq emacsvox-aural-session-engine-order nil)
        (condition-case error-data
            (emacsvox-aural-commit-routing-profile-data
             preferred emacsvox-aural-routing-profiles-file
             (emacsvox-aural-voice-workbench--preference-callback
              display-name 'saved))
          (error
           (setq emacsvox-aural-session-engine-order previous-session)
           (signal (car error-data) (cdr error-data))))))
    engine-id))

(defun emacsvox-aural-restore-saved-engine-order ()
  "Clear the temporary preference and restore the saved or initial order."
  (interactive)
  (emacsvox-aural-voice-workbench--ensure-clean)
  (unless emacsvox-aural-session-engine-order
    (user-error "No temporary engine preference is active"))
  (let* ((entry
          (emacsvox-aural-routing-profile
           emacsvox-aural-active-routing-profile))
         (profile (emacsvox-aural-voice-workbench--active-profile))
         (engine-id (car (plist-get profile :engine-order)))
         (inventory (tts-voice-inventory))
         (display-name
          (emacsvox-aural-voice-workbench--engine-display-name
           engine-id inventory))
         (scope
          (if (eq (emacsvox-aural-routing-profile-entry-source entry)
                  emacsvox-aural-voice-workbench--session-profile-source)
              'runtime-restored
            'restored)))
    (emacsvox-aural-clear-session-engine-order
     (emacsvox-aural-voice-workbench--preference-callback
      display-name scope))))

(defun emacsvox-aural-voice-workbench--stage
    (description mutation &optional provenance)
  "Apply MUTATION and record DESCRIPTION and optional PROVENANCE for undo."
  (let ((before (copy-tree emacsvox-aural-voice-workbench-staged-profile))
        (before-provenance
         (copy-tree emacsvox-aural-voice-workbench-provenance)))
    (condition-case error-data
        (progn
          (funcall mutation)
          (setq emacsvox-aural-voice-workbench-staged-profile
                (emacsvox-aural-validate-routing-profile-data
                 emacsvox-aural-voice-workbench-staged-profile))
          (if (equal before emacsvox-aural-voice-workbench-staged-profile)
              (progn
                (emacsvox-aural-voice-workbench--announce
                 "No routing changes were needed")
                nil)
            (when provenance
              (push (copy-tree provenance)
                    emacsvox-aural-voice-workbench-provenance))
            (push (list :profile before :description description
                        :provenance before-provenance)
                  emacsvox-aural-voice-workbench-undo-stack)
            (setq emacsvox-aural-voice-workbench-last-edit description)
            (emacsvox-aural-voice-workbench-refresh)
            (emacsvox-aural-voice-workbench--announce
             "%s staged. Save is not yet applied" description)
            t))
      (error
       (setq emacsvox-aural-voice-workbench-staged-profile before
             emacsvox-aural-voice-workbench-provenance before-provenance)
       (signal (car error-data) (cdr error-data))))))

(defun emacsvox-aural-voice-workbench--current-engine-id ()
  "Return the engine ID on the current engine row."
  (unless (eq emacsvox-aural-voice-workbench-view 'engines)
    (user-error "Switch to the engine view first"))
  (or (tabulated-list-get-id)
      (user-error "Move to an engine row first")))

(defun emacsvox-aural-voice-workbench--policy-engine-list (field)
  "Return a copy of staged routing-policy engine FIELD."
  (copy-sequence
   (pcase field
     ('preferred
      (plist-get emacsvox-aural-voice-workbench-staged-profile
                 :engine-order))
     ('fallback
      (plist-get
       (plist-get emacsvox-aural-voice-workbench-staged-profile :fallback)
       :engines))
     ('disabled
      (plist-get emacsvox-aural-voice-workbench-staged-profile
                 :disabled-engines))
     (_ (error "Unknown routing-policy list: %S" field)))))

(defun emacsvox-aural-voice-workbench--set-policy-engine-list (field engines)
  "Set staged routing-policy FIELD to ordered ENGINES."
  (pcase field
    ('preferred
     (setf (plist-get emacsvox-aural-voice-workbench-staged-profile
                      :engine-order)
           engines))
    ('fallback
     (let ((fallback
            (copy-tree
             (plist-get emacsvox-aural-voice-workbench-staged-profile
                        :fallback))))
       (setf (plist-get fallback :engines) engines)
       (setf (plist-get emacsvox-aural-voice-workbench-staged-profile
                        :fallback)
             fallback)))
    ('disabled
     (setf (plist-get emacsvox-aural-voice-workbench-staged-profile
                      :disabled-engines)
           engines))))

(defun emacsvox-aural-voice-workbench--move-policy-engine
    (field direction label)
  "Move current engine in policy FIELD by DIRECTION, described by LABEL."
  (let* ((engine-id
          (emacsvox-aural-voice-workbench--current-engine-id))
         (engines
          (emacsvox-aural-voice-workbench--policy-engine-list field))
         (index (cl-position engine-id engines :test #'equal)))
    (unless index
      (user-error "%s is not in the %s; use its toggle command first"
                  engine-id label))
    (let ((destination (+ index direction))
          (total (length engines)))
      (unless (<= 0 destination (1- (length engines)))
        (user-error
         "%s is already at position %d of %d, the %s boundary"
         engine-id (1+ index) total label))
      (cl-rotatef (nth index engines) (nth destination engines))
      (emacsvox-aural-voice-workbench--stage
       (format "Moved %s to position %d of %d in global %s"
               engine-id (1+ destination) total label)
       (lambda ()
         (emacsvox-aural-voice-workbench--set-policy-engine-list
          field engines))))))

(defun emacsvox-aural-voice-workbench--toggle-policy-engine
    (field label)
  "Toggle current engine membership in policy FIELD described by LABEL."
  (let* ((engine-id
          (emacsvox-aural-voice-workbench--current-engine-id))
         (engines
          (emacsvox-aural-voice-workbench--policy-engine-list field))
         (present (member engine-id engines)))
    (emacsvox-aural-voice-workbench--stage
     (format "%s %s in %s"
             (if present "Removed" "Added") engine-id label)
     (lambda ()
       (emacsvox-aural-voice-workbench--set-policy-engine-list
        field
        (if present
            (delete engine-id engines)
          (append engines (list engine-id))))))))

(defun emacsvox-aural-voice-workbench-move-preferred-engine-up ()
  "Move the selected engine earlier in preferred engine order."
  (interactive)
  (emacsvox-aural-voice-workbench--move-policy-engine 'preferred -1 "preferred order"))

(defun emacsvox-aural-voice-workbench-move-preferred-engine-down ()
  "Move the selected engine later in preferred engine order."
  (interactive)
  (emacsvox-aural-voice-workbench--move-policy-engine 'preferred 1 "preferred order"))

(defun emacsvox-aural-voice-workbench-toggle-preferred-engine ()
  "Add or remove the current engine from global preferred order."
  (interactive)
  (emacsvox-aural-voice-workbench--toggle-policy-engine
   'preferred "global preferred order"))

(defun emacsvox-aural-voice-workbench-toggle-fallback-engine ()
  "Add or remove the current engine from global fallback order."
  (interactive)
  (emacsvox-aural-voice-workbench--toggle-policy-engine
   'fallback "global fallback order"))

(defun emacsvox-aural-voice-workbench-move-fallback-engine-up ()
  "Move the current engine earlier in global fallback order."
  (interactive)
  (emacsvox-aural-voice-workbench--move-policy-engine
   'fallback -1 "fallback order"))

(defun emacsvox-aural-voice-workbench-move-fallback-engine-down ()
  "Move the current engine later in global fallback order."
  (interactive)
  (emacsvox-aural-voice-workbench--move-policy-engine
   'fallback 1 "fallback order"))

(defun emacsvox-aural-voice-workbench-toggle-disabled-engine ()
  "Disable or restore the current engine in the staged policy."
  (interactive)
  (emacsvox-aural-voice-workbench--toggle-policy-engine
   'disabled "disabled engine list"))

(defun emacsvox-aural-voice-workbench-request-recovery-probe ()
  "Request a live recovery probe for the current failed engine."
  (interactive)
  (let ((engine-id
         (emacsvox-aural-voice-workbench--current-engine-id))
        (buffer (current-buffer)))
    (tts-request-engine-recovery-probe
     engine-id
     (lambda (result)
       (when (buffer-live-p buffer)
         (with-current-buffer buffer
           (emacsvox-aural-voice-workbench-refresh engine-id)
           (emacsvox-aural-voice-workbench--announce
            "%s recovery probe for %s"
            (if (equal (plist-get result :type)
                       "engine_recovery_probe_requested")
                "Armed" "Could not arm")
            engine-id)))))
    (emacsvox-aural-voice-workbench--announce
     "Requested recovery probe for %s" engine-id)))

(defun emacsvox-aural-voice-workbench-export-profile ()
  "Export the staged routing profile without activating it."
  (interactive)
  (let* ((kind
          (completing-read
           "Export routing: "
           '("portable copy without exact native IDs"
             "complete machine-local profile")
           nil 'must-match))
         (portable (string-prefix-p "portable" kind))
         (file
          (read-file-name
           "Export routing profile to: " emacsvox-user-directory nil nil
           (format "%s-routing.el"
                   (plist-get emacsvox-aural-voice-workbench-staged-profile
                              :id)))))
    (emacsvox-aural-export-routing-profile
     emacsvox-aural-voice-workbench-staged-profile file portable
     emacsvox-aural-voice-workbench-inventory)
    (emacsvox-aural-voice-workbench--announce
     "%s routing profile exported to %s"
     (if portable "Portable" "Complete") file)))

(defun emacsvox-aural-voice-workbench-import-profile ()
  "Read one data-only routing profile into the staged workbench copy."
  (interactive)
  (let* ((file
          (read-file-name
           "Import routing profile: " emacsvox-user-directory nil 'must-match))
         (profile (emacsvox-aural-read-routing-profile file)))
    (when
        (y-or-n-p
         (format "Replace staged routing with profile %s from %s? "
                 (plist-get profile :id) file))
      (emacsvox-aural-voice-workbench--stage
       (format "Imported routing profile %s" (plist-get profile :id))
       (lambda ()
         (setq emacsvox-aural-voice-workbench-staged-profile
               (copy-tree profile)))
       (list :kind 'imported :detail (abbreviate-file-name file))))))

(defun emacsvox-aural-voice-workbench-undo ()
  "Undo the most recent staged routing edit without changing saved state."
  (interactive)
  (let ((snapshot (pop emacsvox-aural-voice-workbench-undo-stack)))
    (unless snapshot (user-error "No staged routing edit to undo"))
    (setq emacsvox-aural-voice-workbench-staged-profile
          (copy-tree (plist-get snapshot :profile))
          emacsvox-aural-voice-workbench-provenance
          (copy-tree (plist-get snapshot :provenance))
          emacsvox-aural-voice-workbench-last-edit
          (format "Undid %s" (plist-get snapshot :description)))
    (emacsvox-aural-voice-workbench-refresh)
    (emacsvox-aural-voice-workbench--announce
     "%s" emacsvox-aural-voice-workbench-last-edit)))

(defun emacsvox-aural-voice-workbench-cancel-staged ()
  "Restore the exact profile snapshot from when the workbench opened."
  (interactive)
  (when
      (or (not (emacsvox-aural-voice-workbench--dirty-p))
          (y-or-n-p "Discard every staged routing edit? "))
    (setq emacsvox-aural-voice-workbench-staged-profile
          (copy-tree emacsvox-aural-voice-workbench-committed-profile)
          emacsvox-aural-voice-workbench-undo-stack nil
          emacsvox-aural-voice-workbench-provenance nil
          emacsvox-aural-voice-workbench-last-edit "Cancelled staged edits")
    (emacsvox-aural-voice-workbench-refresh)
    (emacsvox-aural-voice-workbench--announce "Staged routing edits cancelled")))

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

(defun emacsvox-aural-voice-workbench-tune ()
  "Open the common editor for a named voice or physical experiment."
  (interactive)
  (require 'emacsvox-aural-voice-editor)
  (if (eq emacsvox-aural-voice-workbench-view 'physical)
      (emacsvox-aural-voice-editor-experiment
       (emacsvox-aural-voice-workbench--physical-pair (tabulated-list-get-id))
       (current-buffer) emacsvox-aural-voice-workbench-preview-text)
    (unless (memq emacsvox-aural-voice-workbench-view '(logical styles))
      (user-error "Choose a named or physical voice to edit"))
    (emacsvox-aural-voice-editor-open
     (emacsvox-aural-voice-workbench--active-palette)
     (or (tabulated-list-get-id) (user-error "Choose a named voice"))
     (current-buffer) emacsvox-aural-voice-workbench-preview-text)))

(defun emacsvox-aural-voice-workbench-refresh (&optional id)
  "Refresh inventory and preserve each view's row and column independently."
  (interactive)
  (unless (eq emacsvox-aural-voice-workbench-view 'physical)
    (setq emacsvox-aural-voice-workbench--voice-list-parent nil))
  (when emacsvox-aural-voice-workbench-rendered-view
    (when-let* ((current (tabulated-list-get-id)))
      (puthash emacsvox-aural-voice-workbench-rendered-view current
               emacsvox-aural-voice-workbench-selections))
    (puthash emacsvox-aural-voice-workbench-rendered-view
             (emacsvox-aural-ui-tabulated-column-index)
             emacsvox-aural-voice-workbench-columns))
  (setq emacsvox-aural-voice-workbench-inventory (tts-voice-inventory)
        tabulated-list-format (emacsvox-aural-voice-workbench--format)
        header-line-format '(:eval (emacsvox-aural-voice-workbench--header)))
  (when (and tabulated-list-sort-key
             (not (assoc (car tabulated-list-sort-key) (append tabulated-list-format nil))))
    (setq tabulated-list-sort-key nil))
  (tabulated-list-init-header)
  (let* ((selected (or id (gethash emacsvox-aural-voice-workbench-view
                                 emacsvox-aural-voice-workbench-selections)))
         (entries (emacsvox-aural-voice-workbench--entries selected))
         (single (and (eq emacsvox-aural-voice-workbench-view 'physical)
                      (= 1 (cl-count-if (lambda (row) (emacsvox-aural-voice-workbench--language-row-p (car row))) entries))
                      (cl-every (lambda (row)
                                  (or (emacsvox-aural-voice-workbench--language-row-p (car row))
                                      (car (gethash (car row) emacsvox-aural-voice-workbench--language-order))))
                                entries)
                      (cl-find-if-not (lambda (row) (emacsvox-aural-voice-workbench--language-row-p (car row))) entries))))
    (emacsvox-aural-ui-refresh-tabulated
     (lambda () (setq tabulated-list-entries entries))
     (if (assoc selected entries) selected (car single))))
  (emacsvox-aural-ui-goto-tabulated-column
   (gethash emacsvox-aural-voice-workbench-view emacsvox-aural-voice-workbench-columns 0))
  (setq emacsvox-aural-voice-workbench-rendered-view emacsvox-aural-voice-workbench-view))

(defun emacsvox-aural-voice-workbench-speak-current ()
  "Speak the complete current Workbench row with titled values."
  (interactive)
  (let* ((entry
          (or (tabulated-list-get-entry)
              (user-error "Move to a Voice Workbench row first")))
         parts)
    (if (emacsvox-aural-voice-workbench--language-row-p (tabulated-list-get-id))
        (setq parts (list (aref entry 1) (aref entry 0)))
      (dotimes (index (length entry))
        (let ((value (aref entry index)))
          (push
           (format "%s, %s"
                   (car (aref tabulated-list-format index))
                   (if (string-empty-p (format "%s" value)) "blank" value))
           parts))))
    (let ((text (mapconcat #'identity (nreverse parts) ". ")))
      (if (fboundp 'tts-speak) (tts-speak text) (message "%s" text))
      text)))

(defun emacsvox-aural-voice-workbench--speak-row-name ()
  "Speak a language heading with its count, or the destination voice cell."
  (if (emacsvox-aural-voice-workbench--language-row-p (tabulated-list-get-id))
      (emacsvox-aural-voice-workbench-speak-current)
    (emacsvox-aural-ui-speak-current-cell t)))

(defun emacsvox-aural-voice-workbench--switch (view)
  "Switch to Workbench VIEW and announce its selected row."
  (when-let* ((current (tabulated-list-get-id)))
    (puthash emacsvox-aural-voice-workbench-view current
             emacsvox-aural-voice-workbench-selections))
  (setq emacsvox-aural-voice-workbench-view view)
  (emacsvox-aural-voice-workbench-refresh)
  (let ((row
         (and (tabulated-list-get-id)
              (emacsvox-aural-voice-workbench-speak-current))))
    (unless row
      (let ((text
             (format "%s view has no rows"
                     (alist-get view
                                emacsvox-aural-voice-workbench--views))))
        (if (fboundp 'tts-speak) (tts-speak text) (message "%s" text))))))

(defun emacsvox-aural-voice-workbench-logical-view ()
  "Show logical voices."
  (interactive)
  (emacsvox-aural-voice-workbench--switch 'logical))

(defun emacsvox-aural-voice-workbench-physical-view ()
  "Browse the selected engine's voices, or show the physical voice inventory.
Outside the engine view, leave any temporary engine browsing scope."
  (interactive)
  (if (eq emacsvox-aural-voice-workbench-view 'engines)
      (progn
        (setq emacsvox-aural-voice-workbench--voice-list-parent
              (or (tabulated-list-get-id) (user-error "Select an engine first")))
        (emacsvox-aural-voice-workbench--switch 'physical))
    (setq emacsvox-aural-voice-workbench--voice-list-parent nil)
    (emacsvox-aural-voice-workbench--switch 'physical))
  (emacsvox-aural-voice-workbench--library-start))

(defun emacsvox-aural-voice-workbench-engine-view ()
  "Show speech engines and their capabilities."
  (interactive)
  (emacsvox-aural-voice-workbench--switch 'engines))

(defun emacsvox-aural-voice-workbench-style-view ()
  "Show portable styles, routes, and advertised effects."
  (interactive)
  (emacsvox-aural-voice-workbench--switch 'styles))

(defun emacsvox-aural-voice-workbench-refresh-inventory ()
  "Request fresh adapter inventory and quietly rebuild the current view."
  (interactive)
  (setq emacsvox-aural-voice-workbench-inventory
        (tts-refresh-voice-inventory))
  (emacsvox-aural-voice-workbench-refresh)
  (emacsvox-aural-voice-workbench--library-start)
  (let ((text
         (format "Inventory refresh requested. %s"
                 (emacsvox-aural-voice-workbench--header))))
    (if (fboundp 'tts-speak) (tts-speak text) (message "%s" text))
    text))

(defun emacsvox-aural-voice-workbench--filter-values (field)
  "Return available physical inventory values for filter FIELD."
  (let (values)
    (dolist (pair (emacsvox-aural-voice-workbench--browse-pairs))
      (let ((engine (car pair)) (voice (cadr pair)))
        (when-let* ((value
                     (pcase field
                       ('engine (plist-get engine :engine-id))
                       ('health (plist-get engine :health))
                       ('language (plist-get voice :language))
                       ('gender (plist-get voice :gender))
                       ('quality (plist-get voice :quality))
                       ('availability (plist-get voice :availability)))))
          (push (format "%s" value) values))))
    (sort (delete-dups values) #'string-lessp)))

(defun emacsvox-aural-voice-workbench-set-filter ()
  "Set or clear one physical-voice inventory filter."
  (interactive)
  (let* ((field
          (intern
           (completing-read
            "Filter field: "
            '("engine" "language" "gender" "quality" "health"
              "availability") nil 'must-match)))
         (key (intern (concat ":" (symbol-name field))))
         (current (plist-get emacsvox-aural-voice-workbench-filter key))
         (value
          (completing-read
           (format "%s value (blank clears): " (capitalize (symbol-name field)))
           (emacsvox-aural-voice-workbench--filter-values field)
           nil nil nil nil current)))
    (setq emacsvox-aural-voice-workbench-filter
          (plist-put emacsvox-aural-voice-workbench-filter key
                     (unless (string-empty-p value) value)))
    (when (eq field 'engine)
      (setq emacsvox-aural-voice-workbench--voice-list-parent nil))
    (unless (eq emacsvox-aural-voice-workbench-view 'physical)
      (setq emacsvox-aural-voice-workbench-view 'physical))
    (emacsvox-aural-voice-workbench-refresh)
    (let ((text
           (format "Physical voice filter: %s"
                   (emacsvox-aural-voice-workbench--filter-description))))
      (if (fboundp 'tts-speak) (tts-speak text) (message "%s" text))
      text)))

(defun emacsvox-aural-voice-workbench-quick-filter (&optional filter)
  "Choose a quick FILTER with voice counts, or use shortcuts 1 through 4.
Counts respect engine and explicit filters, including collapsed languages.
Downloaded means catalogue packages; Enabled means desired library selection."
  (interactive)
  (unless (emacsvox-aural-voice-workbench--library-p)
    (user-error "Open Omnivox physical voices first"))
  (emacsvox-aural-voice-workbench--filtered-pairs t)
  (let* ((key last-command-event)
         (choices (mapcar (lambda (entry)
                           (cons (emacsvox-aural-voice-workbench--quick-description (car entry)) (car entry)))
                         emacsvox-aural-voice-workbench--quick-filters))
         (filter (or filter (and (integerp key) (<= ?1 key ?4)
                                 (car (nth (- key ?1) emacsvox-aural-voice-workbench--quick-filters)))
                     (cdr (assoc (completing-read "Show voices: " choices nil t) choices))))
         (scope (copy-tree (emacsvox-aural-voice-workbench--physical-filter))))
    (unless (assq filter emacsvox-aural-voice-workbench--quick-filters)
      (user-error "Unknown voice filter"))
    (unless emacsvox-aural-voice-workbench--filter-positions
      (setq emacsvox-aural-voice-workbench--filter-positions (make-hash-table :test #'equal)))
    (when-let* ((id (tabulated-list-get-id)))
      (puthash (list scope emacsvox-aural-voice-workbench--quick-filter)
               (list id (emacsvox-aural-ui-tabulated-column-index))
               emacsvox-aural-voice-workbench--filter-positions))
    (setq emacsvox-aural-voice-workbench--quick-filter filter)
    (let ((position (gethash (list scope filter) emacsvox-aural-voice-workbench--filter-positions)))
      (emacsvox-aural-voice-workbench-refresh (car position))
      (when position (emacsvox-aural-ui-goto-tabulated-column (cadr position)))))
  (emacsvox-aural-ui-speak
   (concat (emacsvox-aural-voice-workbench--quick-description emacsvox-aural-voice-workbench--quick-filter)
           (unless tabulated-list-entries ". No matching voices; 1 shows all voices"))))

(defun emacsvox-aural-voice-workbench-find-voice ()
  "Find a voice by name and reveal it across collapsed language groups.
Search respects engine and explicit filters.  If the quick filter hides the
chosen voice, switch to All voices.  Nothing is enabled or played."
  (interactive)
  (unless (eq emacsvox-aural-voice-workbench-view 'physical)
    (user-error "Open physical voices first"))
  (let* ((pairs (emacsvox-aural-voice-workbench--filtered-pairs t))
         (choices (mapcar
                   (lambda (pair)
                     (let ((engine (plist-get (car pair) :engine-id))
                           (voice (cadr pair)))
                       (cons (format "%s — %s; %s; %s"
                                     (or (plist-get voice :display-name) (plist-get voice :voice-id))
                                     engine (or (plist-get voice :language) "Unknown language")
                                     (plist-get voice :voice-id))
                             (list engine (plist-get voice :voice-id))))) pairs))
         (completion-ignore-case t)
         (completion-styles '(substring basic)))
    (unless choices (user-error "No voices in this scope; R refreshes, C clears filters"))
    (let* ((id (cdr (assoc (completing-read "Find voice: " choices nil t) choices)))
           (pair (emacsvox-aural-voice-workbench--physical-pair id)))
      (unless (or (not (emacsvox-aural-voice-workbench--library-p))
                  (memq emacsvox-aural-voice-workbench--quick-filter
                        (emacsvox-aural-voice-workbench--quick-memberships pair)))
        (emacsvox-aural-voice-workbench-quick-filter 'all))
      (emacsvox-aural-voice-workbench-refresh id)
      (emacsvox-aural-ui-goto-tabulated-column 0)
      (emacsvox-aural-voice-workbench-speak-current))))

(defun emacsvox-aural-voice-workbench-clear-filters ()
  "Clear all physical-voice filters and refresh."
  (interactive)
  (setq emacsvox-aural-voice-workbench-filter nil
        emacsvox-aural-voice-workbench--quick-filter 'all
        emacsvox-aural-voice-workbench--voice-list-parent nil)
  (emacsvox-aural-voice-workbench-refresh)
  (if (fboundp 'tts-speak)
      (tts-speak "Physical voice filters cleared")
    (message "Physical voice filters cleared")))

(defun emacsvox-aural-voice-workbench-open-row ()
  "Open engine details, toggle a language, or preview the selected voice."
  (interactive)
  (cond
   ((emacsvox-aural-voice-workbench--language-row-p (tabulated-list-get-id))
    (let* ((id (tabulated-list-get-id))
           (key (emacsvox-aural-voice-workbench--language-key (cadr id)))
           (expanded (not (eq 'expanded (gethash key emacsvox-aural-voice-workbench--language-expansion)))))
      (puthash key (if expanded 'expanded 'collapsed) emacsvox-aural-voice-workbench--language-expansion)
      (emacsvox-aural-voice-workbench-refresh id)
      (emacsvox-aural-ui--announce-expansion expanded
                                             (emacsvox-aural-voice-workbench--language-label (cadr id)))))
   ((eq emacsvox-aural-voice-workbench-view 'engines)
    (if (equal "omnivox" (plist-get emacsvox-aural-voice-workbench-inventory :adapter))
        (progn
          (require 'emacsvox-omnivox-components)
          (emacsvox-omnivox-components--open-engine
           (or (tabulated-list-get-id) (user-error "Select an engine first")) (current-buffer)))
      (emacsvox-aural-voice-workbench-physical-view)))
   (t (emacsvox-aural-voice-workbench-preview))))

(defun emacsvox-aural-voice-workbench-quit ()
  "Return from an engine's voice list, or dismiss the workbench.

When an engine row opened this voice list, restore its selected row and
column.  A dedicated browser returns to its engine details.  Otherwise
hide the workbench, retaining staged edits and warning
when they remain unsaved."
  (interactive)
  (cond
   ((buffer-live-p emacsvox-aural-voice-workbench--details-parent)
    (let ((warning (emacsvox-aural-voice-workbench--dismiss-warning))
          (parent emacsvox-aural-voice-workbench--details-parent))
      (quit-window)
      (emacsvox-aural-ui-pop-to-buffer parent)
      (when warning (tts-speak warning))))
   ((and (eq emacsvox-aural-voice-workbench-view 'physical)
           emacsvox-aural-voice-workbench--voice-list-parent)
    (puthash 'engines emacsvox-aural-voice-workbench--voice-list-parent
             emacsvox-aural-voice-workbench-selections)
    (emacsvox-aural-voice-workbench--switch 'engines))
   (t (emacsvox-aural-quit))))

(defun emacsvox-aural-voice-workbench-describe ()
  "Display and speak exact Workbench row and configuration details."
  (interactive)
  (when (emacsvox-aural-voice-workbench--language-row-p (tabulated-list-get-id))
    (user-error "Expand the language and choose a voice for details"))
  (let* ((summary (emacsvox-aural-voice-workbench-speak-current))
         (details (cadr (assoc (tabulated-list-get-id)
                              (emacsvox-aural-voice-workbench--detail-entries))))
         (format (emacsvox-aural-voice-workbench--detail-format))
         (status (emacsvox-aural-voice-workbench--header))
         (inventory emacsvox-aural-voice-workbench-inventory)
         (profile emacsvox-aural-voice-workbench-staged-profile)
         (diagnostics emacsvox-aural-voice-workbench-diagnostics)
         (provenance emacsvox-aural-voice-workbench-provenance))
    (emacsvox-aural-ui-with-help-window
      (princ (format "%s\n\n" summary))
      (when details
        (dotimes (index (length details))
          (princ (format "%s: %s\n" (car (aref format index))
                         (aref details index))))
        (princ "\n"))
      (princ (format "Status: %s\n\n"
                     status))
      (princ
       (format "Inventory:\n%S\n\n"
               inventory))
      (princ
       (format "Staged routing profile:\n%S\n"
               profile))
      (princ
       (format "\nApply status:\n%S\n"
               emacsvox-aural-routing-apply-status))
      (princ
       (format "\nCurrent diagnostics:\n%S\n"
               diagnostics))
      (princ
       (format "\nStaged provenance:\n%S\n"
               provenance)))
    summary))

(defun emacsvox-aural-voice-workbench-help ()
  "Display and speak Voice Workbench navigation help."
  (interactive)
  (emacsvox-aural-ui-with-help-window
    (princ
     (concat
      "Voice Workbench\n\n"
      "e engines; v physical voices; l named voices; s styles and effects.\n"
      "On an Omnivox engine, RET opens status, downloads, and settings.\n"
      "v browses its voices directly; q returns to the engine.\n"
      "Physical voices are grouped by language; RET expands or collapses a heading.\n"
      "On a voice, RET plays a sample. P also previews; x shows details; t edits.\n"
      "V reviews this physical voice across all voices in a new or existing palette.\n"
      "Single-language lists start expanded. Groups and selected voices survive refresh.\n"
      "Column sorting keeps languages together and sorts the voices within them.\n"
      "n/p or up/down moves rows; left/right moves columns.\n"
      ". speaks the cell; SPC speaks the whole row; x shows details.\n\n"
      "P previews; S stops; T changes the comparison text.\n"
      "In physical voices, A plays voices in expanded groups and B compares two.\n"
      "Omnivox voices: + enables/disables; a reviews Apply; d downloads; b includes SLT.\n"
      "i imports a validated operation; C-c r shows the last library Apply result.\n"
      "C-c u reviews package uninstallation; C-c U resumes incomplete cleanup.\n"
      "Installed records library membership; Enabled is desired; Active is stream eligibility.\n"
      "Active does not mean a model is resident in memory. Unknown needs a fresh status check.\n"
      "1 All voices; 2 Downloaded; 3 Enabled; 4 Needs Apply; Q chooses with counts.\n"
      "Downloaded excludes imports and built-ins. Enabled is the desired library selection.\n"
      "Needs Apply compares selection with both workers; unchecked voices are reported separately.\n"
      "A selection change does not establish runtime health or remove engine overrides.\n"
      "/ finds a voice across collapsed groups, revealing it in All if needed.\n"
      "F filters voices; C clears filters; R refreshes the inventory.\n"
      "t opens the complete editor for a named voice or physical experiment.\n"
      "Physical experiments stay unsaved until kept in a named voice draft.\n"
      "Save the named voice in that editor, with or without applying it.\n\n"
      "Engine policy is shared across palettes. In the engine view:\n"
      "O toggles preferred engines; [ and ] reorder them.\n"
      "f toggles fallback engines; { and } reorder them.\n"
      "D disables or enables an engine; K requests a recovery probe.\n"
      "w or C-c C-c saves and applies engine policy; u undoes a staged edit.\n"
      "C-c C-k cancels staged policy edits; r retries a saved apply.\n"
      "U restores the previous saved policy; E exports and I imports it.\n\n"
      "C-c C-a offers available actions; C-c C-i opens the offline manual.\n"
      "h opens settings; q leaves the Workbench, retaining staged policy edits.\n")))
  (when (fboundp 'emacsvox-speak-help) (emacsvox-speak-help)))

(defun emacsvox-aural-voice-workbench--dismiss-warning ()
  "Return a warning when physical routing changes remain staged."
  (when (emacsvox-aural-voice-workbench--dirty-p)
    (concat
     "Voice Workbench hidden. Engine policy changes remain staged, "
     "not saved. Return to the Workbench and press w to save and apply.")))

(defun emacsvox-aural-voice-workbench--action-applicable-p (command)
  "Return whether COMMAND applies to the current Workbench view and state."
  (let ((row (tabulated-list-get-id))
        (view emacsvox-aural-voice-workbench-view))
    (pcase command
      ((or 'emacsvox-aural-voice-workbench-preview
           'emacsvox-aural-voice-workbench-describe
           'emacsvox-aural-voice-workbench--library-toggle)
       (and row (not (emacsvox-aural-voice-workbench--language-row-p row))
            (or (not (eq command 'emacsvox-aural-voice-workbench--library-toggle))
                (emacsvox-aural-voice-workbench--library-p))))
      ('emacsvox-aural-voice-workbench-find-voice (eq view 'physical))
      ('emacsvox-aural-voice-workbench-quick-filter
       (emacsvox-aural-voice-workbench--library-p))
      ('emacsvox-aural-voice-bulk-resume t)
      ((or 'emacsvox-aural-voice-workbench-compare
           'emacsvox-aural-voice-workbench-use-across-palette)
       (and row (eq view 'physical) (not (emacsvox-aural-voice-workbench--language-row-p row))))
      ((or 'emacsvox-aural-voice-workbench--library-apply
           'emacsvox-aural-voice-workbench--library-download
           'emacsvox-aural-voice-workbench--library-slt
           'emacsvox-aural-voice-workbench--library-import
           'omnivox-library-uninstall
           'omnivox-library-resume-uninstall
           'omnivox-library-show-result)
       (emacsvox-aural-voice-workbench--library-p))
      ((or 'emacsvox-aural-voice-workbench-logical-view
           'emacsvox-aural-voice-workbench-physical-view
           'emacsvox-aural-voice-workbench-engine-view
           'emacsvox-aural-voice-workbench-style-view
           'emacsvox-aural-voice-workbench-set-filter
           'emacsvox-aural-voice-workbench-clear-filters
           'emacsvox-aural-voice-workbench-refresh-inventory
           'emacsvox-aural-voice-workbench-edit-preview-text
           'emacsvox-aural-voice-workbench-stop-preview
           'emacsvox-aural-voice-workbench-import-profile
           'emacsvox-aural-voice-workbench-export-profile
           'emacsvox-aural-ui-refresh 'emacsvox-aural-voice-workbench-quit
           'emacsvox-aural-quit
           'emacsvox-aural 'emacsvox-aural-voice-workbench-help) t)
      ((or 'emacsvox-aural-voice-workbench-undo
           'emacsvox-aural-voice-workbench-cancel-staged)
       (emacsvox-aural-voice-workbench--dirty-p))
      ('emacsvox-aural-voice-workbench-preview-all
       (and row (eq view 'physical)))
      ((or 'emacsvox-aural-voice-workbench-move-preferred-engine-up
           'emacsvox-aural-voice-workbench-move-preferred-engine-down
           'emacsvox-aural-voice-workbench-toggle-preferred-engine
           'emacsvox-aural-voice-workbench-toggle-fallback-engine
           'emacsvox-aural-voice-workbench-move-fallback-engine-up
           'emacsvox-aural-voice-workbench-move-fallback-engine-down
           'emacsvox-aural-voice-workbench-toggle-disabled-engine
           'emacsvox-aural-voice-workbench-request-recovery-probe)
       (and row (eq view 'engines)))
      ('emacsvox-aural-voice-workbench-tune
       (and row (not (emacsvox-aural-voice-workbench--language-row-p row))
            (memq view '(physical logical styles))))
      (_ row))))

(define-derived-mode
    emacsvox-aural-voice-workbench-mode
    emacsvox-aural-tabulated-mode
  "Aural-Voice-Workbench"
  "Spoken workbench for logical styles and physical voice routing."
  (setq-local emacsvox-aural-ui-action-filter
              #'emacsvox-aural-voice-workbench--action-applicable-p)
  (setq-local emacsvox-aural-ui-extra-actions
              '(("Use this voice across a palette" . emacsvox-aural-voice-workbench-use-across-palette)
                ("Resume palette voice review" . emacsvox-aural-voice-bulk-resume)))
  (setq-local emacsvox-aural-voice-workbench-view 'logical)
  (setq-local emacsvox-aural-voice-workbench-inventory (tts-voice-inventory))
  (setq-local emacsvox-aural-voice-workbench-committed-profile
              (emacsvox-aural-voice-workbench--current-profile-data
               emacsvox-aural-voice-workbench-inventory))
  (setq-local emacsvox-aural-voice-workbench-staged-profile
              (copy-tree emacsvox-aural-voice-workbench-committed-profile))
  (setq-local emacsvox-aural-voice-workbench-selections
              (make-hash-table :test #'eq))
  (setq-local emacsvox-aural-voice-workbench-columns (make-hash-table :test #'eq))
  (setq-local emacsvox-aural-voice-workbench-filter nil)
  (setq-local emacsvox-aural-voice-workbench-last-preview nil)
  (setq-local emacsvox-aural-voice-workbench-undo-stack nil)
  (setq-local emacsvox-aural-voice-workbench-last-edit nil)
  (setq-local emacsvox-aural-voice-workbench-applied-undo nil)
  (setq-local emacsvox-aural-voice-workbench-diagnostics
              (emacsvox-aural-voice-workbench--profile-diagnostics
               emacsvox-aural-voice-workbench-staged-profile))
  (setq-local emacsvox-aural-voice-workbench-provenance nil)
  (setq-local emacsvox-aural-ui-dismiss-warning-function
              #'emacsvox-aural-voice-workbench--dismiss-warning)
  (emacsvox-aural-ui-configure-tabulated
   "voice workbench"
   #'emacsvox-aural-voice-workbench-speak-current
   #'emacsvox-aural-voice-workbench-refresh
   #'emacsvox-aural-voice-workbench--speak-row-name)
  (setq tabulated-list-format (emacsvox-aural-voice-workbench--format)
        tabulated-list-padding 2
        header-line-format '(:eval (emacsvox-aural-voice-workbench--header)))
  (add-hook 'kill-buffer-hook #'emacsvox-aural-voice-workbench--library-stop nil t)
  (add-hook 'change-major-mode-hook #'emacsvox-aural-voice-workbench--library-stop nil t)
  (add-hook 'tabulated-list-revert-hook
            #'emacsvox-aural-voice-workbench-refresh nil t)
  (tabulated-list-init-header))

(dolist
    (binding
     '(("RET" . emacsvox-aural-voice-workbench-open-row)
       ("V" . emacsvox-aural-voice-workbench-use-across-palette)
       ("l" . emacsvox-aural-voice-workbench-logical-view)
       ("v" . emacsvox-aural-voice-workbench-physical-view)
       ("e" . emacsvox-aural-voice-workbench-engine-view)
       ("s" . emacsvox-aural-voice-workbench-style-view)
       ("F" . emacsvox-aural-voice-workbench-set-filter)
       ("Q" . emacsvox-aural-voice-workbench-quick-filter)
       ("1" . emacsvox-aural-voice-workbench-quick-filter)
       ("2" . emacsvox-aural-voice-workbench-quick-filter)
       ("3" . emacsvox-aural-voice-workbench-quick-filter)
       ("4" . emacsvox-aural-voice-workbench-quick-filter)
       ("/" . emacsvox-aural-voice-workbench-find-voice)
       ("C" . emacsvox-aural-voice-workbench-clear-filters)
       ("R" . emacsvox-aural-voice-workbench-refresh-inventory)
       ("+" . emacsvox-aural-voice-workbench--library-toggle)
       ("a" . emacsvox-aural-voice-workbench--library-apply)
       ("d" . emacsvox-aural-voice-workbench--library-download)
       ("b" . emacsvox-aural-voice-workbench--library-slt)
       ("i" . emacsvox-aural-voice-workbench--library-import)
       ("C-c r" . omnivox-library-show-result)
       ("C-c u" . omnivox-library-uninstall)
       ("C-c U" . omnivox-library-resume-uninstall)
       ("P" . emacsvox-aural-voice-workbench-preview)
       ("A" . emacsvox-aural-voice-workbench-preview-all)
       ("B" . emacsvox-aural-voice-workbench-compare)
       ("T" . emacsvox-aural-voice-workbench-edit-preview-text)
       ("S" . emacsvox-aural-voice-workbench-stop-preview)
       ("t" . emacsvox-aural-voice-workbench-tune)
       ("[" . emacsvox-aural-voice-workbench-move-preferred-engine-up)
       ("]" . emacsvox-aural-voice-workbench-move-preferred-engine-down)
       ("O" . emacsvox-aural-voice-workbench-toggle-preferred-engine)
       ("f" . emacsvox-aural-voice-workbench-toggle-fallback-engine)
       ("{" . emacsvox-aural-voice-workbench-move-fallback-engine-up)
       ("}" . emacsvox-aural-voice-workbench-move-fallback-engine-down)
       ("D" . emacsvox-aural-voice-workbench-toggle-disabled-engine)
       ("K" . emacsvox-aural-voice-workbench-request-recovery-probe)
       ("E" . emacsvox-aural-voice-workbench-export-profile)
       ("I" . emacsvox-aural-voice-workbench-import-profile)
       ("u" . emacsvox-aural-voice-workbench-undo)
       ("x" . emacsvox-aural-voice-workbench-describe)
       ("w" . emacsvox-aural-voice-workbench-save-and-apply)
       ("C-c C-c" . emacsvox-aural-voice-workbench-save-and-apply)
       ("C-c C-k" . emacsvox-aural-voice-workbench-cancel-staged)
       ("r" . emacsvox-aural-voice-workbench-retry-apply)
       ("U" . emacsvox-aural-voice-workbench-undo-applied)
       ("q" . emacsvox-aural-voice-workbench-quit)
       ("h" . emacsvox-aural-menu)
       ("?" . emacsvox-aural-voice-workbench-help)))
  (define-key emacsvox-aural-voice-workbench-mode-map
              (kbd (car binding)) (cdr binding)))

(defun emacsvox-aural-voice-workbench--speak-opening ()
  "Announce the prepared view and selected engine without starting discovery."
  (cond
   ((not (tabulated-list-get-id)) (tts-speak "Voice Workbench has no rows"))
   ((eq emacsvox-aural-voice-workbench-view 'engines)
    (let* ((entry (tabulated-list-get-entry))
           (count (string-to-number (aref entry 8))))
      (tts-speak
       (format "Browse voices. %s. %s. %d voice%s. %s"
               (aref entry 0) (aref entry 1)
               count (if (= count 1) "" "s")
               (if (equal "omnivox" (plist-get emacsvox-aural-voice-workbench-inventory :adapter))
                   "Return opens engine details; v browses voices"
                 "Return browses voices")))))
   (t (emacsvox-aural-voice-workbench-speak-current))))

;;;###autoload
(defun emacsvox-aural-voice-workbench (&optional view)
  "Open the accessible Voice Workbench in VIEW."
  (interactive)
  (let ((source (emacsvox-aural-inspection-remember-source-buffer))
        (buffer (get-buffer-create "*Aural Voice Workbench*")))
    (with-current-buffer buffer
      (unless (derived-mode-p 'emacsvox-aural-voice-workbench-mode)
        (emacsvox-aural-voice-workbench-mode))
      (setq-local emacsvox-aural-ui--return-function nil)
      (emacsvox-aural-inspection-attach-source source)
      (when view (setq emacsvox-aural-voice-workbench-view view))
      (emacsvox-aural-voice-workbench-refresh))
    (emacsvox-aural-ui--pop-to-buffer
     buffer #'emacsvox-aural-voice-workbench--speak-opening)
    (with-current-buffer buffer (emacsvox-aural-voice-workbench--library-start))
    buffer))

(defun emacsvox-aural-voice-workbench--open-engine (engine parent)
  "Browse ENGINE on the main speech target, returning to details PARENT.
Keep the general workbench's filters, selection and staged edits intact."
  (let ((source (emacsvox-aural-inspection-source-buffer parent))
        (buffer (get-buffer-create (format "*Omnivox Voices: %s*" engine))))
    (with-current-buffer buffer
      (unless (derived-mode-p 'emacsvox-aural-voice-workbench-mode)
        (emacsvox-aural-voice-workbench-mode))
      (emacsvox-aural-inspection-attach-source source)
      (setq emacsvox-aural-voice-workbench--details-parent parent
            emacsvox-aural-voice-workbench--voice-list-parent engine
            emacsvox-aural-voice-workbench-view 'physical)
      (emacsvox-aural-voice-workbench-refresh))
    (emacsvox-aural-ui--pop-to-buffer
     buffer
     (lambda ()
       (tts-speak
        (format "%s voices. Return expands a language or plays a sample; Q filters with counts; slash finds a voice; plus enables or disables; a reviews Apply; q returns.%s"
                engine (if (tabulated-list-get-id) "" " Loading library information.")))))
    (with-current-buffer buffer (emacsvox-aural-voice-workbench--library-start))
    buffer))

(defun emacsvox-aural-voice-workbench-refresh-if-live (&rest _ignored)
  "Quietly refresh a live Voice Workbench after configuration changes."
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (derived-mode-p 'emacsvox-aural-voice-workbench-mode)
        (unless (emacsvox-aural-voice-workbench--dirty-p)
          (setq emacsvox-aural-voice-workbench-committed-profile
                (emacsvox-aural-voice-workbench--current-profile-data)
                emacsvox-aural-voice-workbench-staged-profile
                (copy-tree
                 emacsvox-aural-voice-workbench-committed-profile)))
        (emacsvox-aural-voice-workbench-refresh)
        (emacsvox-aural-voice-workbench--library-check-lanes)))))

(defun emacsvox-aural-voice-workbench--realized-voice-changed (&rest _ignored)
  "Refresh Last played in the views that display it."
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (and (derived-mode-p 'emacsvox-aural-voice-workbench-mode)
                 (memq emacsvox-aural-voice-workbench-view '(logical styles)))
        (emacsvox-aural-voice-workbench-refresh)))))

(add-hook 'emacsvox-aural-routing-profile-changed-hook
          #'emacsvox-aural-voice-workbench-refresh-if-live)
(add-hook 'emacsvox-aural-voice-palette-changed-hook
          #'emacsvox-aural-voice-workbench-refresh-if-live)
(add-hook 'emacsvox-aural-routing-apply-status-hook
          #'emacsvox-aural-voice-workbench-refresh-if-live)
(add-hook 'omnivox-library--changed-hook
          #'emacsvox-aural-voice-workbench--library-changed)
(add-hook 'tts-voice-inventory-changed-hook
          #'emacsvox-aural-voice-workbench-refresh-if-live)
;; Remove the former broad redraw hook when loading into an existing session.
(remove-hook 'tts-realized-voice-changed-hook
             #'emacsvox-aural-voice-workbench-refresh-if-live)
(add-hook 'tts-realized-voice-changed-hook
          #'emacsvox-aural-voice-workbench--realized-voice-changed)

(provide 'emacsvox-aural-voice-workbench)

;;; emacsvox-aural-voice-workbench.el ends here
