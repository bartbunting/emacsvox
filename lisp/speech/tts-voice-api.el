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

;; Define generic voice capabilities, inventory and configuration callbacks.
;; Speech adapters install their implementations through these existing hooks.
;; The public `tts-speak' entry point loads this module; loading these
;; definitions alone does not select an adapter or start speech processes.

;;; Code:

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

(provide 'tts-voice-api)

;;; tts-voice-api.el ends here
