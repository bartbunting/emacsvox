;;; emacsvox-aural-providers.el --- Effective aural providers -*- lexical-binding: t; -*-

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

;; One explicit runtime selection boundary for sound packs and voice
;; palettes.  This preserves precedence while exposing which configuration
;; layer supplied the effective provider.

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
followed by the fixed baseline provider and the bundled `chimes' fallback."
  (let* ((active
          (and
           (boundp 'emacsvox-sounds-current-pack)
           emacsvox-sounds-current-pack
           (emacsvox-aural-resource-pack emacsvox-sounds-current-pack)
           emacsvox-sounds-current-pack))
         (baseline
          (and
           (not active)
           (emacsvox-aural-effective-scheme-provider 'resource-pack))))
    (emacsvox-aural--make-provider-selection
     :kind 'resource-pack
     :id (or active baseline 'chimes)
     :source
     (cond
      (active 'sound-state)
      (baseline 'baseline)
      (t 'fallback)))))

(defun emacsvox-aural-voice-provider-selection ()
  "Return the effective voice-palette provider selection.

A registered explicit override wins, followed by the fixed baseline provider
and the built-in `acss-default' fallback."
  (let* ((override
          (and
           emacsvox-aural-voice-palette-override
           (emacsvox-aural-voice-palette
            emacsvox-aural-voice-palette-override)
           emacsvox-aural-voice-palette-override))
         (baseline
          (and
           (not override)
           (emacsvox-aural-effective-scheme-provider 'voice-palette))))
    (emacsvox-aural--make-provider-selection
     :kind 'voice-palette
     :id (or override baseline 'acss-default)
     :source
     (cond
      (override 'explicit-override)
      (baseline 'baseline)
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
