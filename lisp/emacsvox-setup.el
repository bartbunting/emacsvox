;;; emacsvox-setup.el --- Setup Emacsvox -- -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox, Setup, Spoken Output
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
;; Entry point for Emacsvox.
;; The simplest and most basic way to start emacsvox is:
;; emacs -q -l <emacsvox-dir>/lisp/emacsvox-setup.el
;; The above starts a vanilla Emacs with just Emacsvox loaded.
;; Loading this source file also detects newer startup sources that would
;; otherwise be hidden by stale byte-code and temporarily prefers those
;; sources.  Rebuild a changed checkout rather than relying on that fallback.
;; Once the above has been verified to work,
;; You can  add
;; (load-library "emacsvox-setup")
;; To your .emacs file when using an installed, already-built copy.
;; See tvr/emacs-startup.el in the Emacsvox Git repository for  my setup.

;;; Code:

(require 'cl-lib)

(declare-function emacsvox "emacsvox" ())

;; Tests compare this guard with the maintained TTS/speech build groups and
;; the core load path.  Optional package preparation remains demand-driven.
(defconst emacsvox-setup--startup-sources
  '("emacsvox-version.el"
    "emacsvox-paths.el"
    "emacsvox-preamble.el"
    "emacsvox-loaddefs.el"
    "core/emacsvox-keymap.el"
    "ui/emacsvox-indentation.el"
    "ui/emacsvox-aural-menu.el"
    "ui/emacsvox-aural-voice-menu.el"
    "ui/emacsvox-capitalization.el"
    "ui/emacsvox-interaction.el"
    "ui/emacsvox-spelling.el"
    "ui/emacsvox-tone-editor.el"
    "ui/emacsvox-line-cues.el"
    "ui/emacsvox-output-settings.el"
    "ui/emacsvox-settings.el"
    "ui/emacsvox-settings-workflows.el"
    "ui/emacsvox-settings-integrations.el"
    "ui/emacsvox-settings-changes.el"
    "ui/emacsvox-welcome.el"
    "speech/tts-lifecycle.el"
    "speech/tts-voice-api.el"
    "speech/tts-speak.el"
    "speech/tts-queue-state.el"
    "core/emacsvox-emoji.el"
    "speech/voice-setup.el"
    "voices/voice-defs.el"
    "speech/dectalk-voices.el"
    "speech/plain-voices.el"
    "speech/espeak-voices.el"
    "speech/outloud-voices.el"
    "speech/mac-voices.el"
    "speech/swiftmac-voices.el"
    "speech/omnivox-control-codec.el"
    "speech/omnivox-choice-codec.el"
    "ui/omnivox-espeak-variants.el"
    "speech/omnivox-parameters-codec.el"
    "speech/omnivox-parameters.el"
    "speech/omnivox-native-codec.el"
    "speech/omnivox-library-apply.el"
    "speech/omnivox-library-runtime.el"
    "ui/omnivox-library.el"
    "ui/omnivox-catalogue.el"
    "speech/omnivox-preview.el"
    "speech/omnivox-inventory.el"
    "speech/omnivox-discovery.el"
    "speech/omnivox-voices.el"
    "speech/omnivox-remote.el"
    "speech/omnivox-engine-settings.el"
    "ui/omnivox-punctuation.el"
    "speech/omnivox-punctuation-profiles.el"
    "ui/omnivox-engine-configuration.el"
    "core/emacsvox-pronounce.el"
    "core/emacsvox-tracked-reading.el"
    "core/emacsvox-speak-characters.el"
    "core/emacsvox-speak-filters.el"
    "core/emacsvox-speak.el"
    "aural/sox-gen.el"
    "core/emacsvox-advice-completion.el"
    "core/emacsvox-advice-input.el"
    "core/emacsvox-advice-messages.el"
    "core/emacsvox-advice.el"
    "integrations/emacsvox-websearch.el"
    "integrations/emacsvox-google.el"
    "integrations/emacsvox-we.el"
    "core/emacsvox-xslt.el"
    "core/gweb.el"
    "core/g-utils.el"
    "aural/emacsvox-aural.el"
    "aural/emacsvox-aural-concrete.el"
    "aural/emacsvox-aural-history.el"
    "aural/emacsvox-aural-spatial.el"
    "aural/emacsvox-aural-rules.el"
    "aural/emacsvox-aural-resources.el"
    "aural/emacsvox-aural-schemes.el"
    "aural/emacsvox-aural-routing-profiles.el"
    "voices/emacsvox-aural-voice-data.el"
    "voices/emacsvox-aural-voice-runtime.el"
    "voices/emacsvox-aural-voice-drafts.el"
    "voices/emacsvox-aural-voice-editing.el"
    "ui/emacsvox-aural-voice-editor.el"
    "ui/emacsvox-aural-voice-bulk.el"
    "ui/emacsvox-aural-voice-engine-controls.el"
    "ui/emacsvox-aural-voice-context.el"
    "aural/emacsvox-aural-profile-service.el"
    "aural/emacsvox-aural-compatibility-voice.el"
    "aural/emacsvox-aural-providers.el"
    "aural/emacsvox-aural-compiler.el"
    "aural/emacsvox-aural-source.el"
    "aural/emacsvox-aural-planner.el"
    "aural/emacsvox-aural-submission.el"
    "aural/emacsvox-aural-timeline-codec.el"
    "aural/emacsvox-aural-transport.el"
    "aural/emacsvox-aural-description.el"
    "aural/emacsvox-aural-preview.el"
    "aural/emacsvox-aural-replay.el"
    "aural/emacsvox-aural-validation.el"
    "ui/emacsvox-aural-ui.el"
    "aural/emacsvox-aural-inspection.el"
    "ui/emacsvox-aural-semantics.el"
    "aural/emacsvox-aural-explanation.el"
    "aural/emacsvox-aural-tools.el"
    "ui/emacsvox-aural-recent-feedback.el"
    "ui/emacsvox-aural-feedback-details.el"
    "ui/emacsvox-aural-feature-fragments.el"
    "ui/emacsvox-omnivox-components.el"
    "ui/emacsvox-aural-home.el"
    "ui/emacsvox-aural-editor.el"
    "ui/emacsvox-aural-overrides.el"
    "ui/emacsvox-aural-doctor.el"
    "ui/emacsvox-aural-profiles.el"
    "ui/emacsvox-aural-voice-palettes.el"
    "ui/emacsvox-aural-voice-workbench-views.el"
    "ui/emacsvox-aural-voice-workbench.el"
    "ui/emacsvox-aural-change-feedback.el"
    "aural/emacsvox-aural-provider-org.el"
    "aural/emacsvox-aural-provider-org-srs.el"
    "aural/emacsvox-aural-provider-workflows.el"
    "aural/emacsvox-aural-provider-markdown.el"
    "aural/emacsvox-aural-provider-notmuch.el"
    "aural/emacsvox-sounds.el"
    "ui/emacsvox-aural-sound-packs.el"
    "ui/emacsvox-sound-library.el"
    "emacsvox.el"
    "emacsvox-setup.el")
  "Sources whose byte-code must not shadow a newer aural startup.")

(defun emacsvox-setup--stale-byte-code (&optional directory)
  "Return startup sources newer than their byte-code in DIRECTORY."
  (let ((directory
         (file-name-as-directory
          (or directory
              (file-name-directory
               (or load-file-name buffer-file-name)))))
        stale)
    (dolist (name emacsvox-setup--startup-sources)
      (let* ((source (expand-file-name name directory))
             (compiled (concat source "c")))
        (when
            (and
             (file-exists-p source)
             (file-exists-p compiled)
             (file-newer-than-file-p source compiled))
          (push source stale))))
    (nreverse stale)))

(defun emacsvox-setup--load (directory)
  "Load Emacsvox from DIRECTORY without allowing stale byte-code to win."
  (let* ((stale (emacsvox-setup--stale-byte-code directory))
         (load-prefer-newer (or load-prefer-newer (and stale t))))
    (when stale
      (display-warning
       'emacsvox
       (format
        (concat
         "Newer Emacsvox source will be loaded instead of stale byte-code: %s. "
         "Run make bytecode from the repository root to rebuild it.")
        (mapconcat #'file-name-nondirectory stale ", "))
       :warning))
    (add-to-list 'load-path directory)
    (require 'emacsvox-preamble)

    ;; Load and start Emacsvox if interactive.
    (require 'emacsvox)
    (unless noninteractive
      (let ((file-name-handler-alist nil)
            (load-source-file-function nil))
        (load "emacsvox-loaddefs")
        (emacsvox)))))

;;; Load-path:
(emacsvox-setup--load
 (file-name-directory (or load-file-name buffer-file-name)))

(provide 'emacsvox-setup)

;; mode: emacs-lisp

;;; emacsvox-setup.el ends here
