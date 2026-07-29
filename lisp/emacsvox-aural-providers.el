;;; emacsvox-aural-providers.el --- Effective aural providers -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; One explicit runtime selection boundary for sound packs and voice
;; palettes.  This preserves the current precedence while exposing which
;; configuration layer supplied the effective provider.

;;; Code:

(require 'cl-lib)
(require 'emacsvox-aural-schemes)

(defvar emacsvox-sounds-current-pack)
(defvar emacsvox-aural-voice-palette-override)

(cl-defstruct
    (emacsvox-aural-provider-selection
     (:constructor emacsvox-aural--make-provider-selection))
  "One effective provider and the configuration layer that selected it."
  kind id source)

(defun emacsvox-aural-resource-provider-selection ()
  "Return the effective sound-pack provider selection.

The active compatibility sound state wins when it names a registered pack,
followed by the active scheme provider and the bundled `chimes' fallback."
  (let* ((active
          (and
           (boundp 'emacsvox-sounds-current-pack)
           emacsvox-sounds-current-pack
           (emacsvox-aural-resource-pack emacsvox-sounds-current-pack)
           emacsvox-sounds-current-pack))
         (scheme
          (and
           (not active)
           (emacsvox-aural-effective-scheme-provider 'resource-pack))))
    (emacsvox-aural--make-provider-selection
     :kind 'resource-pack
     :id (or active scheme 'chimes)
     :source
     (cond
      (active 'sound-state)
      (scheme 'scheme)
      (t 'fallback)))))

(defun emacsvox-aural-voice-provider-selection ()
  "Return the effective voice-palette provider selection.

A registered explicit override wins, followed by the active scheme provider
and the built-in `acss-default' fallback."
  (let* ((override
          (and
           emacsvox-aural-voice-palette-override
           (emacsvox-aural-voice-palette
            emacsvox-aural-voice-palette-override)
           emacsvox-aural-voice-palette-override))
         (scheme
          (and
           (not override)
           (emacsvox-aural-effective-scheme-provider 'voice-palette))))
    (emacsvox-aural--make-provider-selection
     :kind 'voice-palette
     :id (or override scheme 'acss-default)
     :source
     (cond
      (override 'explicit-override)
      (scheme 'scheme)
      (t 'fallback)))))

(defun emacsvox-aural-effective-resource-pack ()
  "Return the identifier of the effective runtime sound pack."
  (emacsvox-aural-provider-selection-id
   (emacsvox-aural-resource-provider-selection)))

(defun emacsvox-aural-effective-voice-palette ()
  "Return the identifier of the effective runtime voice palette."
  (emacsvox-aural-provider-selection-id
   (emacsvox-aural-voice-provider-selection)))

(provide 'emacsvox-aural-providers)
;;; emacsvox-aural-providers.el ends here
