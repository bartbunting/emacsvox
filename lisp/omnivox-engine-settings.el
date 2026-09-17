;;; omnivox-engine-settings.el --- Local engine startup settings -*- lexical-binding: t; -*-

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

;; Project typed settings into the bundled local launcher environment.  The
;; launcher converts paths for its selected native target.  Explicit Omnivox
;; environment settings retain precedence.  No remote provisioning or speech
;; restart occurs when settings are edited.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'json)
(defvar emacsvox-servers-directory)
(defvar tts-program)
(declare-function omnivox-remote-enabled-p "omnivox-remote" ())

(defgroup omnivox-engine-settings nil
  "Local engine settings for the bundled Omnivox launcher.
Choose files as seen by Emacs; the WSL launcher converts them to Windows
paths.  Existing OMNIVOX environment overrides take precedence.  Settings
affect new speech workers only; editing never restarts speech.  Save through
Customize to retain them in this Emacs profile.  Remote speech and direct
native executable launches do not consume these settings."
  :group 'tts)

(defcustom omnivox-piper-model-file nil
  "Local Piper ONNX model; nil keeps environment or launcher defaults.
The matching JSON configuration must remain beside the model.  This selects
one model with the existing loader; it is not a multi-model voice library."
  :type '(choice (const :tag "Use existing configuration" nil) file)
  :group 'omnivox-engine-settings)

(defcustom omnivox-eloquence-runtime-file nil
  "Local Eloquence ECI.DLL; nil keeps existing runtime discovery.
Use the supported 32-bit runtime with its required companion files."
  :type '(choice (const :tag "Use existing configuration" nil) file)
  :group 'omnivox-engine-settings)

(defcustom omnivox-dectalk-runtime-file nil
  "Local DECtalk DLL; nil keeps existing runtime discovery.
Keep its dictionaries and other required runtime files in place."
  :type '(choice (const :tag "Use existing configuration" nil) file)
  :group 'omnivox-engine-settings)

(defcustom omnivox-flite-voice-files nil
  "External Flite files and whether to load each at the next speech start.
Each entry is (LOAD FILE).  FILE is an absolute local .flitevox path.
Turning LOAD off retains the file and saved palette references, but omits
it from newly started helpers.  Existing workers retain their loaded voices
until restarted.  Built-in SLT remains loaded.  Both speech workers load
the selected files, so their native memory costs are duplicated.
An explicit OMNIVOX_FLITE_VOICES environment value overrides this list.
Native discovery must validate compatibility; saving is not a load check."
  :type '(repeat (list (boolean :tag "Load file") (file :tag "Voice file")))
  :group 'omnivox-engine-settings)

(defcustom omnivox-espeak-variants nil
  "Retained legacy eSpeak combination settings, no longer used by Emacsvox.
Variants are available on demand; choose them directly in the variants picker.
Existing palette references do not need conversion."
  :type '(repeat (list (boolean :tag "Enabled")
                       (string :tag "Base voice ID") (string :tag "Variant ID")))
  :group 'omnivox-engine-settings)

(make-obsolete-variable 'omnivox-espeak-variants
                        "Choose variants directly with M-x omnivox-espeak-variants."
                        "2026.9")

(defun omnivox-engine-settings--variants-json (entries)
  "Validate ENTRIES and encode bounded native eSpeak startup JSON."
  (unless (and (proper-list-p entries) (<= (length entries) 64))
    (user-error "Use at most 64 eSpeak variant combinations"))
  (let (seen rows)
    (dolist (entry entries)
      (unless (and (proper-list-p entry) (= (length entry) 3)
                   (memq (car entry) '(nil t))
                   (stringp (nth 1 entry)) (stringp (nth 2 entry))
                   (string-match-p "\\`espeak:[A-Za-z0-9_-]+\\(?:[/\\\\][A-Za-z0-9_-]+\\)*\\'" (nth 1 entry))
                   (string-match-p "\\`[A-Za-z_-][A-Za-z0-9_-]*\\'" (nth 2 entry))
                   (<= (+ (- (string-bytes (nth 1 entry)) 7) 1 (string-bytes (nth 2 entry))) 39))
        (user-error "Choose a valid eSpeak base and variant from the speech host"))
      (when (member (cdr entry) seen) (user-error "Repeated eSpeak combination"))
      (push (cdr entry) seen)
      (push (list :base_voice_id (nth 1 entry) :variant_id (nth 2 entry)
                  :enabled (if (car entry) t :false)) rows))
    (let ((json (json-serialize (vconcat (nreverse rows)))))
      (when (> (string-bytes json) (* 16 1024)) (user-error "eSpeak settings exceed 16 KiB"))
      json)))

(defconst omnivox-engine-settings--providers
  '(("piper" omnivox-piper-model-file "OMNIVOX_PIPER_MODEL" "EMACSVOX_LOCAL_PIPER_MODEL" ".onnx")
    ("eloquence" omnivox-eloquence-runtime-file "OMNIVOX_ECI_DLL" "EMACSVOX_LOCAL_ECI_DLL" ".dll")
    ("dectalk" omnivox-dectalk-runtime-file "OMNIVOX_DECTALK_DLL" "EMACSVOX_LOCAL_DECTALK_DLL" ".dll")
    ("flite" omnivox-flite-voice-files "OMNIVOX_FLITE_VOICES" "EMACSVOX_LOCAL_FLITE_VOICES" ".flitevox"))
  "Engine, option, native override, private launcher input and file suffix.")

(defun omnivox-engine-settings--supported-p ()
  "Whether this session selects the bundled local POSIX Omnivox launcher."
  (and (not (eq system-type 'windows-nt))
       (not (and (fboundp 'omnivox-remote-enabled-p) (omnivox-remote-enabled-p)))
       (boundp 'tts-program)
       (member tts-program (list "omnivox" (expand-file-name "omnivox" emacsvox-servers-directory)))))

(defun omnivox-engine-settings--path (path suffix)
  "Validate local PATH syntax for SUFFIX without loading or probing it."
  (when (and (stringp path) (not (file-remote-p path)) (file-name-absolute-p path))
    (setq path (expand-file-name path)))
  (unless (and (stringp path) (not (file-remote-p path))
               (file-name-absolute-p path)
               (not (string-match-p "[\n\r\0\";:]" path))
               (string-suffix-p suffix path t))
    (user-error "Choose an absolute local %s file without path-list delimiters" suffix))
  path)

(defun omnivox-engine-settings--override (provider)
  "Return the explicit environment override name for PROVIDER, if present."
  (cl-find-if (lambda (name) (and (getenv name) (not (string-empty-p (getenv name)))))
              (append (list (nth 2 provider))
                      (pcase (car provider)
                        ("eloquence" '("EMACSVOX_ECI_DLL"))
                        ("dectalk" '("EMACSVOX_DECTALK_DLL"))))))

(defun omnivox-engine-settings--environment (program)
  "Return a private environment for local launcher PROGRAM.
Keep process-wide environment and explicit native overrides unchanged."
  (if (not (equal program (expand-file-name "omnivox" emacsvox-servers-directory)))
      process-environment
    (let ((process-environment (copy-sequence process-environment)))
      (setenv "EMACSVOX_LOCAL_ESPEAK_VARIANTS" nil)
      (dolist (provider omnivox-engine-settings--providers)
        (pcase-let ((`(,id ,option ,_override ,input ,suffix) provider))
          (setenv input nil)
          (unless (omnivox-engine-settings--override provider)
            (when-let* ((value (symbol-value option)))
              (setenv input
                      (if (equal id "flite")
                          (progn
                            (unless (and (proper-list-p value) (<= (length value) 64)
                                         (cl-every (lambda (entry)
                                                     (and (proper-list-p entry) (= (length entry) 2)
                                                          (memq (car entry) '(nil t)))) value))
                              (user-error "Use at most 64 Flite (LOAD FILE) entries"))
                            (mapconcat (lambda (entry) (omnivox-engine-settings--path (cadr entry) suffix))
                                       (cl-remove-if-not #'car value) "\n"))
                        (omnivox-engine-settings--path value suffix)))))))
      process-environment)))

(defun omnivox-engine-settings--description (id)
  "Describe desired settings for ID without claiming live application."
  (when-let* ((provider (assoc id omnivox-engine-settings--providers)))
    (let ((override (omnivox-engine-settings--override provider))
          (value (symbol-value (nth 1 provider))))
      (cond
       ((not (omnivox-engine-settings--supported-p))
        "Configure files on the speech host; this launcher settings provider is unavailable")
       (override
        (format "Overridden by %s; edit that environment setting on the speech host" override))
       ((and (member id '("flite" "piper")) (null value))
        "No manual file override; installed voice library or launcher defaults apply")
       ((equal id "flite")
        (format "%d of %d manual voice files selected for new workers; overrides the installed Flite library"
                (cl-count-if #'car value) (length value)))
       (value (format "%s; used by new workers only, load not checked" value))
       (t "Using existing environment, launcher or engine defaults")))))

(provide 'omnivox-engine-settings)
;;; omnivox-engine-settings.el ends here
