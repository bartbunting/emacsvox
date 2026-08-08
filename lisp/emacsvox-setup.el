;;; emacsvox-setup.el --- Setup Emacsvox -- -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:  File for setting up and starting Emacsvox
;; Keywords: Emacsvox, Setup, Spoken Output
;;;   LCD Archive entry:
;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ |
;; Location https://github.com/robertmeta/emacsvox
;; 

;;;   Copyright:

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; All Rights Reserved.
;; 
;; This file is not part of GNU Emacs, but the same permissions apply.
;; 
;; GNU Emacs is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;; 
;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

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

(defconst emacsvox-setup--startup-sources
  '("emacsvox-preamble.el"
    "emacsvox-loaddefs.el"
    "emacsvox-keymap.el"
    "tts-speak.el"
    "voice-setup.el"
    "voice-defs.el"
    "dectalk-voices.el"
    "plain-voices.el"
    "espeak-voices.el"
    "outloud-voices.el"
    "mac-voices.el"
    "swiftmac-voices.el"
    "emacsvox-pronounce.el"
    "emacsvox-speak.el"
    "emacsvox-aural.el"
    "emacsvox-aural-concrete.el"
    "emacsvox-aural-history.el"
    "emacsvox-aural-spatial.el"
    "emacsvox-aural-rules.el"
    "emacsvox-aural-resources.el"
    "emacsvox-aural-schemes.el"
    "emacsvox-aural-routing-profiles.el"
    "emacsvox-aural-profile-service.el"
    "emacsvox-aural-providers.el"
    "emacsvox-aural-compiler.el"
    "emacsvox-aural-source.el"
    "emacsvox-aural-planner.el"
    "emacsvox-aural-submission.el"
    "emacsvox-aural-transport.el"
    "emacsvox-aural-description.el"
    "emacsvox-aural-preview.el"
    "emacsvox-aural-validation.el"
    "emacsvox-aural-ui.el"
    "emacsvox-aural-inspection.el"
    "emacsvox-aural-semantics.el"
    "emacsvox-aural-explanation.el"
    "emacsvox-aural-tools.el"
    "emacsvox-aural-recent-feedback.el"
    "emacsvox-aural-feature-fragments.el"
    "emacsvox-aural-home.el"
    "emacsvox-aural-editor.el"
    "emacsvox-aural-overrides.el"
    "emacsvox-aural-doctor.el"
    "emacsvox-aural-profiles.el"
    "emacsvox-aural-voice-palettes.el"
    "emacsvox-aural-voice-workbench.el"
    "emacsvox-aural-provider-org.el"
    "emacsvox-aural-provider-org-srs.el"
    "emacsvox-aural-provider-workflows.el"
    "emacsvox-aural-provider-markdown.el"
    "emacsvox-aural-provider-notmuch.el"
    "emacsvox-sounds.el"
    "emacsvox-aural-sound-packs.el"
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
         "Run make config && make from the repository root to rebuild it.")
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
