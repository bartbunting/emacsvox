;;; tts-voice-api.el --- Generic speech adapter voice API -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: TTS  Emacs Elisp
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

;; Define generic voice capabilities, inventory, configuration, selection and
;; preview callbacks. Preview preparation uses the shared speech helpers in
;; `tts-speak'; dispatch and process ownership remain in the speech runtime.
;; Speech adapters install their implementations through these existing hooks.
;; The public `tts-speak' entry point loads this module; loading these
;; definitions alone does not select an adapter or start speech processes.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defvar emacsvox-pronounce-personality)

(declare-function tts-voice-defined-p "tts-speak" (voice))
(declare-function tts-get-voice-command "tts-speak" (voice))
(declare-function tts-stop "tts-speak" (&optional all))
(declare-function tts--protocol-queue-code "tts-speak" (code))
(declare-function tts--protocol-queue-text "tts-speak" (text))
(declare-function tts-voice-reset-code "tts-speak" ())
(declare-function tts--protocol-dispatch "tts-speak" ())
(declare-function tts-apply-pronunciations "tts-speak" (pronunciation-table))
(declare-function emacsvox-aural-inspection-source-buffer
                  "emacsvox-aural-inspection" (&optional buffer))
(declare-function emacsvox-emoji--snapshot "emacsvox-emoji" ())
(declare-function emacsvox-emoji--item-policy "emacsvox-emoji" (text policy))
(declare-function emacsvox-emoji--prepare "emacsvox-emoji" (text policy))

(defun tts-default-voice-capabilities ()
  "Return the compatibility capability descriptor for an unknown adapter."
  '(:adapter unknown
    :source compatibility
    :language-selection legacy
    :family-selection unsupported
    :families nil
    :generic-families nil
    :dimensions nil
    :parameters nil))

(defvar tts-voice-capabilities-function
  #'tts-default-voice-capabilities
  "Function returning the active speech adapter's voice capabilities.

The returned data is a plist.  `:adapter' identifies the adapter;
`:source' says whether its data is static, discovered, or a compatibility
fallback; `:family-selection' is `enumerated', `free-form', or
`unsupported'; `:language-selection' is `legacy' or `logical-voices';
`:families' contains entries of the form
(ID :label LABEL ...); `:dimensions' lists supported normalized ACSS
dimensions; and `:parameters' describes their accepted values.")

(defun tts-voice-capabilities ()
  "Return an isolated copy of the active adapter's voice capabilities."
  (let ((capabilities
         (and
          (functionp tts-voice-capabilities-function)
          (funcall tts-voice-capabilities-function))))
    (copy-tree
     (if (and (listp capabilities) (plist-get capabilities :adapter))
         capabilities
       (tts-default-voice-capabilities)))))

(defun tts--inventory-name (value)
  "Return VALUE as a stable display and comparison string."
  (cond
   ((stringp value) value)
   ((symbolp value) (symbol-name value))
   (t (format "%s" value))))

(defun tts--static-inventory-voice (engine-id entry)
  "Return a normalized static voice for ENGINE-ID from capability ENTRY."
  (let ((properties (cdr entry)))
    (list
     :engine-id engine-id
     :voice-id (tts--inventory-name (car entry))
     :display-name
     (or (plist-get properties :label)
         (tts--inventory-name (car entry)))
     :language (plist-get properties :language)
     :gender (plist-get properties :gender)
     :quality (plist-get properties :quality)
     :availability "available"
     :aliases (copy-sequence (plist-get properties :aliases))
     :generic (copy-sequence (plist-get properties :generic))
     :native-id (plist-get properties :native-id))))

(defun tts-default-voice-inventory ()
  "Derive a normalized inventory from the active adapter capabilities.

This is the fallback for adapters with static families, free-form selection,
or no discovery.  Server-backed adapters should install their own inventory
function."
  (let* ((capabilities (tts-voice-capabilities))
         (adapter (plist-get capabilities :adapter))
         (engine-id (tts--inventory-name adapter))
         (selection
          (or (plist-get capabilities :family-selection) 'unsupported))
         (source
          (pcase selection
            ('enumerated "static")
            ('free-form "free-form")
            (_ "unavailable")))
         (available (not (eq selection 'unsupported)))
         (families (plist-get capabilities :families))
         (voices
          (mapcar
           (lambda (entry)
             (tts--static-inventory-voice engine-id entry))
           families)))
    (list
     :adapter engine-id
     :source source
     :status (if available "available" "unavailable")
     :generation 0
     :received-at nil
     :stale nil
     :preferred-engine-id engine-id
     :process-agreement "single-adapter"
     :preview-support
     (pcase selection
       ('enumerated "family")
       ('free-form "free-form")
       (_ "unsupported"))
     :complete-preview-support "unsupported"
     :routing-policy-support "unsupported"
     :engines
     (list
      (list
       :engine-id engine-id
       :display-name (capitalize engine-id)
       :availability (if available "available" "unavailable")
       :health (if available "healthy" "unavailable")
       :inventory-kind source
       :acss-dimensions (copy-sequence
                         (plist-get capabilities :dimensions))
       :post-synthesis-dimensions nil
       :preview-support
       (pcase selection
         ('enumerated "family")
         ('free-form "free-form")
         (_ "unsupported"))
       :routing-policy-support "unsupported"
       :capabilities (copy-tree capabilities)
       :voices voices)))))

(defvar tts-voice-inventory-function #'tts-default-voice-inventory
  "Function returning the active speech adapter's normalized inventory.

The result is a plist containing adapter/source/status metadata and an
`:engines' list.  Every engine contains a stable `:engine-id', capabilities,
and normalized voices whose engine and voice IDs remain separate fields.")

(defun tts-default-refresh-voice-inventory ()
  "Return the static inventory of the active speech adapter."
  (tts-default-voice-inventory))

(defvar tts-voice-inventory-refresh-function
  #'tts-default-refresh-voice-inventory
  "Function refreshing and returning the active adapter's voice inventory.")

(defvar tts-engine-recovery-probe-function nil
  "Optional function requesting recovery of one speech engine.

The function receives an engine ID and optional callback.  Adapters without
runtime engine health leave this nil.")

(defun tts-default-apply-voice-configuration (&optional callback)
  "Apply configuration for a standalone adapter and call CALLBACK.

Standalone adapters read the active Emacs variables when compiling speech, so
there is no remote process registry to replace."
  (let ((result
         (list :status 'applied :adapter 'standalone
               :completion-guarantee 'local :processes nil
               :time (current-time))))
    (when (functionp callback) (funcall callback (copy-tree result)))
    result))

(defvar tts-voice-configuration-apply-function
  #'tts-default-apply-voice-configuration
  "Function atomically applying the active adapter's complete voice state.

The function receives an optional callback.  Server-backed adapters call it
once with an overall result containing a terminal result for every targeted
speech process.")

(defun tts-apply-voice-configuration (&optional callback)
  "Apply the active adapter's complete voice configuration.
Call CALLBACK once with the adapter's terminal result when supplied."
  (unless (functionp tts-voice-configuration-apply-function)
    (error "The active speech adapter cannot apply voice configuration"))
  (funcall tts-voice-configuration-apply-function callback))

(defun tts-default-last-realized-voice (_logical-voice)
  "Return no realized route for an adapter without playback route events."
  nil)

(defvar tts-last-realized-voice-function
  #'tts-default-last-realized-voice
  "Function returning the last observed route for one logical voice.")

(defvar tts-realized-voice-changed-hook nil
  "Hook run with one updated playback-observed logical voice route.")

(defun tts-last-realized-voice (logical-voice)
  "Return an isolated last-played route for LOGICAL-VOICE, or nil."
  (copy-tree
   (and (functionp tts-last-realized-voice-function)
        (funcall tts-last-realized-voice-function logical-voice))))

(defun tts-voice-inventory ()
  "Return an isolated snapshot of the active adapter's voice inventory."
  (let ((inventory
         (and
          (functionp tts-voice-inventory-function)
          (funcall tts-voice-inventory-function))))
    (copy-tree
     (if (and (listp inventory) (plist-member inventory :engines))
         inventory
       (tts-default-voice-inventory)))))

(defvar tts-voice-inventory-changed-hook nil
  "Hook run when the adapter receives a fresh main-stream voice inventory.")

(defun tts-refresh-voice-inventory ()
  "Refresh and return the active speech adapter's voice inventory.

For asynchronous server adapters, the returned snapshot may remain pending
until the server response is received."
  (if (functionp tts-voice-inventory-refresh-function)
      (funcall tts-voice-inventory-refresh-function)
    (tts-voice-inventory)))

(defun tts-request-engine-recovery-probe (engine-id &optional callback)
  "Ask the active adapter to probe failed ENGINE-ID.
Call CALLBACK with the adapter result when it completes."
  (unless (functionp tts-engine-recovery-probe-function)
    (user-error "The active speech adapter does not support recovery probes"))
  (funcall tts-engine-recovery-probe-function engine-id callback))

(defun tts--voice-preview-callback (callback result)
  "Call voice preview CALLBACK safely with RESULT and return RESULT."
  (when (functionp callback)
    (condition-case error-data
        (funcall callback result)
      (error
       (message "Voice preview callback failed: %s"
                (error-message-string error-data)))))
  result)

(defun tts--voice-preview-selector-kind (selector)
  "Return normalized kind symbol from voice preview SELECTOR."
  (let ((kind (plist-get selector :kind)))
    (if (stringp kind) (intern kind) kind)))

(defun tts--voice-preview-available-p (value)
  "Return non-nil when inventory availability VALUE is usable."
  (or (null value) (equal (format "%s" value) "available")))

(defun tts--voice-preview-engine (engine-id inventory)
  "Return usable ENGINE-ID from INVENTORY, or signal a preview error."
  (let ((engine
         (cl-find engine-id (plist-get inventory :engines)
                  :key (lambda (entry) (plist-get entry :engine-id))
                  :test #'equal)))
    (unless engine
      (error "Preview engine %s is not installed" engine-id))
    (unless (and
             (tts--voice-preview-available-p
              (plist-get engine :availability))
             (not (equal (format "%s" (plist-get engine :health)) "failed")))
      (error "Preview engine %s is unavailable" engine-id))
    engine))

(defun tts--voice-preview-property-equal-p (wanted actual)
  "Return non-nil when optional voice property WANTED matches ACTUAL."
  (or
   (null wanted)
   (and actual
        (string-equal (downcase (format "%s" wanted))
                      (downcase (format "%s" actual))))))

(defun tts--inventory-exact-voice (engine voice-id)
  "Find VOICE-ID in ENGINE, resolving bundled eSpeak variants on demand."
  (or (cl-find voice-id (plist-get engine :voices)
               :key (lambda (voice) (plist-get voice :voice-id)) :test #'equal)
      (when (and (equal (plist-get engine :engine-id) "espeak")
                 (stringp voice-id)
                 (string-match
                  "\\`\\(espeak:[A-Za-z0-9_-]+\\(?:[/\\\\][A-Za-z0-9_-]+\\)*\\)[+]\\([A-Za-z_-][A-Za-z0-9_-]*\\)\\'"
                  voice-id)
                 (<= (- (string-bytes voice-id) 7) 39))
        (let* ((base-id (match-string 1 voice-id))
               (variant-id (match-string 2 voice-id))
               (base (cl-find base-id (plist-get engine :voices)
                              :key (lambda (voice) (plist-get voice :voice-id)) :test #'equal))
               (variant (cl-find variant-id (plist-get engine :espeak-variants)
                                 :key (lambda (entry) (plist-get entry :id)) :test #'equal)))
          (when (and base variant)
            (let ((voice (copy-tree base)))
              (setq voice (plist-put voice :voice-id voice-id)
                    voice (plist-put voice :gender nil))
              (plist-put voice :display-name
                         (format "%s + %s" (plist-get base :display-name)
                                 (plist-get variant :display-name)))))))))

(defun tts--resolve-voice-preview-selector (selector &optional inventory)
  "Resolve normalized preview SELECTOR against INVENTORY.
Return a plist with separate `:engine-id' and `:voice-id' fields."
  (unless (listp selector)
    (signal 'wrong-type-argument (list 'listp selector)))
  (let* ((inventory (or inventory (tts-voice-inventory)))
         (kind (tts--voice-preview-selector-kind selector))
         (engine-id (plist-get selector :engine-id)))
    (pcase kind
      ('exact
       (let* ((voice-id (plist-get selector :voice-id))
              (engine (tts--voice-preview-engine engine-id inventory))
              (voice (tts--inventory-exact-voice engine voice-id)))
         (unless (and voice
                      (tts--voice-preview-available-p
                       (plist-get voice :availability)))
           (error "Preview voice %s/%s is unavailable" engine-id voice-id))
         (list :engine-id engine-id :voice-id voice-id :voice voice)))
      ('engine-default
       (let* ((engine (tts--voice-preview-engine engine-id inventory))
              (voices (plist-get engine :voices))
              (voice-id (or (plist-get engine :default-voice-id)
                            (plist-get (car voices) :voice-id))))
         (unless voice-id
           (error "Preview engine %s has no voices" engine-id))
         (tts--resolve-voice-preview-selector
          (list :kind 'exact :engine-id engine-id :voice-id voice-id)
          inventory)))
      ('properties
       (let ((engines
              (if engine-id
                  (list (tts--voice-preview-engine engine-id inventory))
                (plist-get inventory :engines)))
             found)
         (while (and engines (null found))
           (let ((engine (pop engines)))
             (when (and
                    (tts--voice-preview-available-p
                     (plist-get engine :availability))
                    (not (equal (format "%s" (plist-get engine :health))
                                "failed")))
               (dolist (voice (plist-get engine :voices))
                 (when (and
                        (null found)
                        (tts--voice-preview-available-p
                         (plist-get voice :availability))
                        (tts--voice-preview-property-equal-p
                         (plist-get selector :language)
                         (plist-get voice :language))
                        (tts--voice-preview-property-equal-p
                         (plist-get selector :gender)
                         (plist-get voice :gender)))
                   (setq found
                         (list
                          :engine-id (plist-get engine :engine-id)
                          :voice-id (plist-get voice :voice-id)
                          :voice voice)))))))
         (or found (error "No installed voice matches the preview selector"))))
      (_ (error "Invalid voice preview selector: %S" selector)))))

(defun tts-default-voice-preview-code (selector)
  "Return queued native voice code for standalone preview SELECTOR."
  (let* ((resolved (tts--resolve-voice-preview-selector selector))
         (voice-id (plist-get resolved :voice-id))
         (family (and (stringp voice-id) (intern-soft voice-id))))
    (unless (and family (tts-voice-defined-p family))
      (error "The active adapter cannot preview native voice %s" voice-id))
    (tts-get-voice-command family)))

(defvar tts-voice-preview-code-function #'tts-default-voice-preview-code
  "Function returning queued native code for one preview selector.")

(defun tts--voice-preview-dimensions (values)
  "Return the non-nil dimension keys in preview plist VALUES."
  (let (dimensions)
    (while values
      (let ((key (pop values)) (value (pop values)))
        (when value (push key dimensions))))
    (nreverse dimensions)))

(defun tts-default-voice-preview-sequence (entries callback)
  "Queue standalone preview ENTRIES once and call CALLBACK.
Legacy servers cannot acknowledge playback, so the result truthfully reports
`queued' after one dispatch. Each entry restores the configured default voice
before the following entry or subsequent ordinary speech."
  (when (cl-some (lambda (entry) (plist-member entry :selectors)) entries)
    (user-error "This adapter cannot preview complete voice chains; use an individual audition"))
  (let ((prepared
         (mapcar
          (lambda (entry)
            (let* ((selector (plist-get entry :selector))
                   (realized (tts--resolve-voice-preview-selector selector))
                   (code (funcall tts-voice-preview-code-function selector)))
              (list
               :entry entry :code code :realized realized
               :result
               (list
                :status 'queued
                :completion-guarantee 'queued-only
                :requested (copy-tree selector)
                :realized
                (list :engine-id (plist-get realized :engine-id)
                      :voice-id (plist-get realized :voice-id))
                :degraded-acss
                (append
                 (tts--voice-preview-dimensions (plist-get entry :acss))
                 (and
                  (numberp (plist-get entry :rate-offset))
                  (not (zerop (plist-get entry :rate-offset)))
                  '(rate-offset)))
                :degraded-effects
                (tts--voice-preview-dimensions (plist-get entry :effects))))))
          entries)))
    (tts-stop)
    (dolist (item prepared)
      (tts--protocol-queue-code (plist-get item :code))
      (tts--protocol-queue-text
       (or (plist-get (plist-get item :entry) :text) ""))
      (tts--protocol-queue-code (tts-voice-reset-code)))
    (tts--protocol-dispatch)
    (tts--voice-preview-callback
     callback
     (list :status 'queued :completion-guarantee 'queued-only
           :results (mapcar (lambda (item) (plist-get item :result))
                            prepared)))))

(defvar tts-voice-preview-function #'tts-default-voice-preview-sequence
  "Function previewing a sequence of normalized voice entries.

The function receives ENTRIES and CALLBACK. Each entry is a plist containing
`:text', `:acss', `:rate-offset', `:effects', and `:language', plus exactly
one of `:selector' for an individual audition or `:selectors' for a complete
voice.  Complete entries require explicit `:fallback-policy' and
`:disabled-engine-ids'; nil selectors mean Automatic.  The fallback policy
contains `:preferred-engines', `:allow-same-language-on-requested-engine',
`:global-default' and `:fallback-engines'.
CALLBACK receives one terminal result. Adapters without playback
acknowledgement use `queued' and `queued-only' rather than claiming natural
completion.")

(defun tts--validate-voice-preview-entry (entry)
  "Validate the common shape of individual or complete preview ENTRY."
  (unless (and (proper-list-p entry) (zerop (% (length entry) 2)))
    (error "Voice preview entry must be a plist"))
  (unless (and (stringp (plist-get entry :text))
               (not (string-empty-p (plist-get entry :text))))
    (error "Each voice preview entry requires nonempty text"))
  (when (eq (not (plist-member entry :selector)) (not (plist-member entry :selectors)))
    (error "Preview requires exactly one of :selector or :selectors")))

(defvar tts--emoji-preview-prepared nil
  "Non-nil while forwarding an already prepared editor preview.")

(defun tts--emoji-preview-wire-entries (entries)
  "Remove Emacs-only naming metadata from private adapter ENTRIES."
  (mapcar (lambda (entry)
            (let ((copy (copy-sequence entry)))
              (dolist (key '(:emoji-policy :emoji-prepared :emoji-naming))
                (cl-remf copy key))
              copy)) entries))

(defun tts--emoji-preview-entries (entries &optional captured-policy)
  "Prepare fresh preview ENTRIES with the remembered source's frozen policy.
CAPTURED-POLICY, when supplied as a one-element list, overrides current policy.
Resolve the source before entering a scratch buffer or asynchronous adapter."
  (let* ((source (if (fboundp 'emacsvox-aural-inspection-source-buffer)
                     (emacsvox-aural-inspection-source-buffer)
                   (current-buffer)))
         (policy (if captured-policy (car captured-policy)
                   (and (buffer-live-p source)
                        (with-current-buffer source (emacsvox-emoji--snapshot)))))
         (pronunciations (and (buffer-live-p source)
                              (buffer-local-value 'emacsvox-pronounce-table source)))
         (personality (and (buffer-live-p source)
                           (buffer-local-value 'emacsvox-pronounce-personality source))))
    (mapcar
     (lambda (entry)
       (let* ((entry (copy-tree entry))
              (policy (if (plist-member entry :emoji-policy) (plist-get entry :emoji-policy) policy))
              (text (plist-get entry :text))
              (retained (and (stringp text)
                             (text-property-any 0 (length text) 'emacsvox-emoji-retained t text))))
         (when retained
           (setq entry (plist-put entry :emoji-prepared t))
           (setq entry (plist-put entry :emoji-naming
                                  (get-text-property retained 'emacsvox-emoji-evidence text))))
         (unless (or (plist-get entry :emoji-prepared)
                     (not (plist-get policy :enabled)))
           (let* ((original (plist-get entry :text))
                  (policy (emacsvox-emoji--item-policy original policy))
                  (text (if pronunciations
                            (with-temp-buffer
                              (let ((emacsvox-pronounce-personality personality))
                                (insert original)
                                (tts-apply-pronunciations pronunciations)
                                (buffer-string)))
                          original))
                  (result (emacsvox-emoji--prepare text policy)))
             (setq entry (plist-put entry :text (plist-get result :text)))
             (setq entry (plist-put entry :emoji-naming
                                    (list :replacements (plist-get result :replacements)
                                          :diagnostics (plist-get result :diagnostics))))))
         (setq entry (plist-put entry :emoji-prepared t))
         entry)) entries)))

(defun tts-preview-voices (entries callback)
  "Preview normalized ENTRIES and call CALLBACK with one terminal result."
  (unless (and (listp entries) entries)
    (error "Voice preview requires at least one entry"))
  (mapc #'tts--validate-voice-preview-entry entries)
  (unless (functionp tts-voice-preview-function)
    (error "The active speech adapter does not support voice preview"))
  (let ((prepared (if tts--emoji-preview-prepared (copy-tree entries)
                    (tts--emoji-preview-entries entries))))
    (funcall tts-voice-preview-function (tts--emoji-preview-wire-entries prepared)
             (lambda (result)
               (cl-loop for item in (plist-get result :results) for entry in prepared do
                        (plist-put item :request-snapshot (copy-tree entry)))
               (when callback (funcall callback result))))))

(cl-defun tts-preview-voice
    (text selector &key acss rate-offset effects language callback)
  "Preview TEXT through SELECTOR without changing saved routing.
ACSS and EFFECTS are unsaved normalized plists. RATE-OFFSET is a signed point
adjustment to the current speech rate. LANGUAGE constrains portable selection.
CALLBACK receives a normalized terminal result plist."
  (unless (and (stringp text) (not (string-empty-p text)))
    (error "Voice preview text must be a nonempty string"))
  (tts-preview-voices
   (list
    (list :text text :selector selector :acss acss
          :rate-offset rate-offset :effects effects :language language))
   (when callback
     (lambda (result)
       (let ((single
              (or (car (plist-get result :results))
                  (list :status (plist-get result :status)
                        :completion-guarantee
                        (plist-get result :completion-guarantee)))))
         (funcall callback
                  (append single
                          (list :sequence-status (plist-get result :status)))))))))

(defun tts--voice-family-name (value)
  "Return a comparison name for voice-family VALUE."
  (cond
   ((symbolp value) (symbol-name value))
   ((stringp value) value)
   (t nil)))

(defun tts--voice-family-name-equal-p (left right)
  "Return non-nil when voice-family names LEFT and RIGHT are equal."
  (let ((left-name (tts--voice-family-name left))
        (right-name (tts--voice-family-name right)))
    (and
     left-name right-name
     (string-equal
      (downcase left-name)
      (downcase right-name)))))

(defun tts-voice-family-capability (family &optional capabilities)
  "Return the family entry matching FAMILY in CAPABILITIES.

Exact identifiers and aliases win.  Generic family names such as `female'
then select the first entry advertising that generic characteristic."
  (let* ((capabilities (or capabilities (tts-voice-capabilities)))
         (families (plist-get capabilities :families))
         exact)
    (dolist (entry families)
      (when
          (or
           (tts--voice-family-name-equal-p family (car entry))
           (cl-some
            (lambda (alias)
              (tts--voice-family-name-equal-p family alias))
            (plist-get (cdr entry) :aliases)))
        (setq exact entry)))
    (or
     exact
     (cl-find-if
      (lambda (entry)
        (cl-some
         (lambda (generic)
           (tts--voice-family-name-equal-p family generic))
         (plist-get (cdr entry) :generic)))
      families))))

(defun tts-voice-family-id (family &optional capabilities)
  "Return the canonical adapter family identifier matching FAMILY."
  (car-safe (tts-voice-family-capability family capabilities)))

(defun tts-voice-parameter-capability (dimension &optional capabilities)
  "Return the parameter descriptor for ACSS DIMENSION."
  (assq
   dimension
   (plist-get
    (or capabilities (tts-voice-capabilities))
    :parameters)))

(provide 'tts-voice-api)

;;; tts-voice-api.el ends here
