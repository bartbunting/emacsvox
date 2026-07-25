;;; emacsvox-sounds.el --- auditory icons  -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:  Module for adding sound cues to emacsvox
;; Keywords:emacsvox, audio interface to emacs, auditory icons
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;;
;;  $Revision: 4670 $ |
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
;; This module provides the interface for generating auditory icons.
;;  It also defines sound themes for auditory icons.
;; @subsection Design goal:
;;
;; @itemize
;; @item   Auditory icons should be used to
;; provide additional feedback, not as a gimmick.
;; @item   The Emacsvox interface
;; should be usable at all times with the icons turned off.
;; @item  Command @code{emacsvox-toggle-icons} toggles the
;; use of auditory icons. This flag is buffer-local; use an
;; interactive prefix argosy @code{C-u} to toggle auditory icons on/off
;; globally.
;; @item  Use @code{setq-default emacsvox-use-icons nil)} to turn
;; auditory icons  off at startup; default is to use auditory icons globally.
;; @item   General principle for using auditory icons:
;; @enumerate
;; @item Convey information about events taking place in parallel.
;;@item  For instance, if making a selection automatically moves the current
;; focus to the next choice, We speak the next choice, while
;; indicating the fact that something was selected with an auditory
;; icon.
;; @item Speed up task completion --- auditory icons take less time than
;; the accompanying spoken feedback.
;; @end enumerate
;; @item This module provides  a mapping between names in the elisp
;; world and actual sound files.
;; @item icon names are symbols,
;; sound files  are strings ---  fully-qualified file-names.
;; @item Modules that  use auditory icons
;;  use icon names and not  actual file names.
;; @item Icons are played either using a local player, or by sending
;; appropriate commands to the speech server (local or cloud).
;; @item  This is determined by the value of @code{emacsvox-play-program}.
;; @item As of
;; Emacsvox 13.0, this module defines a themes architecture for
;; auditory icons.  Sound files corresponding to a given theme are
;; found in appropriate subdirectories of emacsvox-sounds-dir.
;; @item There are two supported themes: @code{chimes} and @code{3d}.
;; @item Contrast this with @code{prompts} --- they  dont belong to any theme.
;; @end itemize
;; @subsection Designing Auditory Icons
;; Here are some notes on what I have learnt while designing and using
;; auditory icons over the years:
;; @enumerate
;;@item  Auditory icons should be short  --- use command @code{soxi} or
;; @code{;} in a dired buffer to see duration of a sound file. Use
;; the bundled themes as a guide.
;; @item Sounds have many properties, eg: duration, gain, pitch, at
;; the basic level.
;;@item  Even more important is the nature of the sound and what it sounds
;; like in the context of the overall speech output  where that sound is used.
;; @item This is why  the gain of icons  @strong{should never be} normalized in
;; my view---  tuning icons is as complex as picking
;; colors from  a color palette.
;; @item The included themes have been optimized over years of use and
;; are primarily tuned for using with headphones.
;; @end enumerate
;; If @code{emacsvox-play-program} is set to @code{nil},
;; we serve icons, otherwise play
;;them using a local player.
;;; Code:
;;  required modules

(eval-when-compile (require 'cl-lib))

(defvar emacsvox-sounds-dir
  (eval-when-compile
    (expand-file-name
     "../sounds/"
     (file-name-directory
      (or load-file-name byte-compile-current-file buffer-file-name))))
  "Auditory icons directory.
Normally defined by `emacsvox-preamble'; this fallback also lets the
sound library load independently during native compilation.")

(defvar sox-play (executable-find "play")
  "Location of the SoX play command.
Normally defined by `emacsvox-preamble'; this fallback also lets the
sound library load independently during native compilation.")

(require 'emacsvox-aural-resources)
(emacsvox-aural-register-bundled-resources emacsvox-sounds-dir)
(require 'emacsvox-aural-schemes)
(require 'emacsvox-aural-transport)

(defvar tts-speaker-process)

;;;   Auditory Icons:

(defvar-local emacsvox-use-icons t
  "Turn on auditory icons.
Use `emacsvox-toggle-icons' bound to
\\[emacsvox-toggle-icons].")

(defun emacsvox-toggle-icons (&optional prefix)
  "Toggle use of auditory icons.
Optional interactive PREFIX arg toggles global value."
  (interactive "P")
  
  (setq  emacsvox-use-icons (not emacsvox-use-icons))
  (when prefix (setq-default emacsvox-use-icons emacsvox-use-icons))
  (when (called-interactively-p 'interactive)
    (message "Turned %s auditory icons %s"
             (if emacsvox-use-icons  'on 'off)
             (if prefix "" "locally"))
    (when emacsvox-use-icons (emacsvox-icon 'on))))

(defun emacsvox-icon (icon)
  "Produce an auditory ICON."
  
  (when emacsvox-use-icons
    (emacsvox-aural-present-legacy-icon icon)))
;;;  emacsvox-prompts:

(defvar emacsvox-prompts-dir
  (expand-file-name "prompts" emacsvox-sounds-dir)
  "Where pre-defined prompt files are located.")

(defun emacsvox-sounds-cache-prompts ()
  "Populate sounds cache with prompts"
  (emacsvox-sounds-cache-rebuild emacsvox-prompts-dir))

;;; Sounds Cache:

(defvar emacsvox-sounds-cache (make-hash-table)
  "Cache sound file names.
Key is a sound-name --- a symbol.
Value is a string, a fully qualified filename. ")

(defsubst emacsvox-sounds-cache-put (sound file)
  "Map  sound to file."
  
  (puthash sound file emacsvox-sounds-cache))

(defsubst emacsvox-sounds-cache-get (sound )
  "Return file that is mapped to sound."
  
  (gethash sound emacsvox-sounds-cache ; or default to button
           (gethash 'button emacsvox-sounds-cache)))

(defun emacsvox-sounds-resource (icon)
  "Return  resource, either a fully qualified file name or an
icon-name, as string."
  
  (let ((f (emacsvox-sounds-cache-get icon)))
    (cond
     ((null emacsvox-play-program) f)
     ((string= emacsvox-play-program emacsvox-pactl) ; pactl->sample-name
      (if (gethash icon emacsvox-sounds-cache) (symbol-name icon)
        "button"))
                                        ; sox-play -> filename
     (t f))))

;;;Sound themes

(defvar emacsvox-sounds-current-theme
  (expand-file-name "chimes/" emacsvox-sounds-dir)
  "Current theme for  icons, a fully-qualified directory. ")

(defconst emacsvox-pactl (executable-find "pactl") "PaCtl Executable.")

(defvar emacsvox-sounds-owned-samples (make-hash-table :test #'equal)
  "Pulse/PipeWire samples uploaded and therefore owned by Emacsvox.

Keys are sample identifiers and values are their concrete resource paths.")

(defun emacsvox-sounds-ensure-sample (resource sample-id)
  "Ensure RESOURCE is uploaded to Pulse/PipeWire as SAMPLE-ID."
  (unless emacsvox-pactl
    (error "Pulse/PipeWire sample playback is unavailable"))
  (let ((existing
         (gethash sample-id emacsvox-sounds-owned-samples)))
    (unless (equal existing resource)
      (when existing
        (call-process
         emacsvox-pactl nil 0 nil "unload-sample" sample-id))
      (let ((status
             (call-process
              emacsvox-pactl nil 0 nil
              "upload-sample" resource sample-id)))
        (unless (and (integerp status) (zerop status))
          (error
           "Could not upload Pulse/PipeWire sample %s from %s"
           sample-id resource))
        (puthash
         sample-id resource emacsvox-sounds-owned-samples))))
  sample-id)

(defun emacsvox-sounds-release-samples (&optional keep)
  "Unload owned Pulse/PipeWire samples except identifiers in KEEP."
  (let (remove)
    (maphash
     (lambda (sample-id _resource)
       (unless (member sample-id keep)
         (push sample-id remove)))
     emacsvox-sounds-owned-samples)
    (dolist (sample-id remove)
      (when emacsvox-pactl
        (call-process
         emacsvox-pactl nil 0 nil "unload-sample" sample-id))
      (remhash sample-id emacsvox-sounds-owned-samples)))
  t)

(add-hook 'kill-emacs-hook #'emacsvox-sounds-release-samples)

;; Called when  selecting themes.
(defun emacsvox-sounds-cache-rebuild (dir)
  "Rebuild sound cache for `dir', a directory containing sound files.
It is called  to cache sounds in our theme and prompts directories."
  (when (file-exists-p dir)
    (cl-loop
     for f in (directory-files dir 'full "\\.ogg$") do
     (emacsvox-sounds-cache-put (intern (file-name-base f)) f))))

(defun emacsvox-sounds-cache-install-fallbacks ()
  "Populate registered cue aliases and fallbacks in the current cache."
  (maphash
   (lambda (cue _record)
     (unless (gethash cue emacsvox-sounds-cache)
       (when-let* ((resource
                    (emacsvox-aural--resolve-cue-in-assets
                     cue emacsvox-sounds-cache)))
         (puthash cue resource emacsvox-sounds-cache))))
   emacsvox-aural-cue-registry))

(defsubst ems--upload-pulse-samples ()
  "Upload samples to Pulse"
  (cl-loop
   for k being the hash-keys of emacsvox-sounds-cache
   using (hash-values v) do
   (let* ((sample-id (symbol-name k))
          (status
           (call-process emacsvox-pactl nil 0 nil
                         "upload-sample" v sample-id)))
     (when (and (integerp status) (zerop status))
       (puthash
        sample-id v emacsvox-sounds-owned-samples)))))

(defsubst ems--samples-not-loaded-p (sample)
  "Verify if sample loaded"
  (= 1 (call-process emacsvox-pactl nil nil nil "play-sample" sample)))

(defvar emacsvox-sounds-current-pack 'chimes
  "Registered resource pack supplying the current auditory cues.

The value is nil when a compatibility caller selects an unregistered
directory.")

(defun emacsvox-sounds--pack-for-theme (theme)
  "Return the registered sound pack selected by THEME, or nil."
  (cond
   ((and (symbolp theme)
         (emacsvox-aural-resource-pack theme)
         (eq
          (emacsvox-aural-resource-pack-kind
           (emacsvox-aural-resource-pack theme))
          'sound))
    theme)
   ((stringp theme)
    (let ((named (intern-soft theme)))
      (or
       (and named
            (emacsvox-aural-resource-pack named)
            (eq
             (emacsvox-aural-resource-pack-kind
              (emacsvox-aural-resource-pack named))
             'sound)
            named)
       (let ((expanded (directory-file-name (expand-file-name theme)))
             found)
         (maphash
          (lambda (id pack)
            (when
                (and
                 (eq (emacsvox-aural-resource-pack-kind pack) 'sound)
                 (equal
                  expanded
                  (directory-file-name
                   (emacsvox-aural-resource-pack-directory pack))))
              (setq found id)))
          emacsvox-aural-resource-pack-registry)
         found))))))

(defun emacsvox-sounds-select-theme (&optional theme)
  "Select registered resource pack or compatibility directory THEME."
  (interactive
   (list
    (intern
     (completing-read
      "Theme: "
      (emacsvox-aural-resource-pack-candidates 'sound)
      nil 'must-match nil nil "chimes"))))
  (setq theme (or theme 'chimes))
  (let* ((pack-id (emacsvox-sounds--pack-for-theme theme))
         (theme-directory
          (if pack-id
              (emacsvox-aural-resource-pack-directory
               (emacsvox-aural-resource-pack pack-id))
            (expand-file-name theme))))
    (emacsvox-sounds-release-samples)
    (clrhash emacsvox-sounds-cache)
    (cond
     (pack-id
      (when (emacsvox-aural-resource-pack 'prompts)
        (emacsvox-aural-refresh-resource-pack 'prompts))
      (emacsvox-aural-refresh-resource-pack pack-id)
      (maphash
       #'emacsvox-sounds-cache-put
       (emacsvox-aural-effective-assets pack-id t)))
     (t
      (emacsvox-sounds-cache-prompts)
      (emacsvox-sounds-cache-rebuild theme-directory)))
    (emacsvox-sounds-cache-install-fallbacks)
  (when                                 ; upload samples if needed
      (and
       emacsvox-play-program           ; avoid nil nil comparison
       emacsvox-pactl
       (string= emacsvox-play-program emacsvox-pactl)
       (or
        (called-interactively-p 'interactive) ; upload on theme change
        (ems--samples-not-loaded-p "item")
        (ems--samples-not-loaded-p "waking-up")))
    (ems--upload-pulse-samples))
    (setq
     emacsvox-sounds-current-pack pack-id
     emacsvox-sounds-current-theme theme-directory)
    (emacsvox-icon 'button)))

(defun emacsvox-sounds-follow-aural-scheme ()
  "Select the sound pack inherited by the active aural scheme."
  (when-let* ((pack
               (emacsvox-aural-effective-scheme-provider 'resource-pack)))
    (unless (eq pack emacsvox-sounds-current-pack)
      (emacsvox-sounds-select-theme pack))))

(with-eval-after-load 'emacsvox-aural-schemes
  (add-hook
   'emacsvox-aural-active-scheme-changed-hook
   #'emacsvox-sounds-follow-aural-scheme))

(defvar ems--play-args nil
  "Arguments passed to play program.
Automatically Set when the player is selected, do not set by hand.")

(defcustom emacsvox-play-program
  (or emacsvox-pactl sox-play)
  "Play program.
Pulse: For systems running Pipewire or Pulseaudio.
sox-play: For systems using SoX as the local player.
None: For systems that rely on the speech server playing the icon."
  :type
  `(choice
    (const  :tag "None" nil)
    (const  :tag "Pulse" ,emacsvox-pactl)
    (const  :tag "SoX" ,sox-play))
  :set
  #'(lambda(sym val)
      (set-default sym val)
      (cond; only 3 valid states:
       ((null val) (setq ems--play-args nil)) ; serve icons
       ((string= emacsvox-pactl val) (setq ems--play-args "play-sample"))
       ((string= sox-play val) (setq ems--play-args "-q"))))
  :group 'emacsvox)

;;; Implementation: emacsvox-icon methods

(defun emacsvox-queue-resource (resource)
  "Queue concrete auditory RESOURCE on the ordered speech stream."
  (process-send-string
   tts-speaker-process
   (format "a %s\n" resource)))

(defun emacsvox-sounds-play-concrete-cue (resource sample-id)
  "Play concrete cue RESOURCE, using SAMPLE-ID for Pulse/PipeWire."
  (let ((process-connection-type nil))
    (cond
     ((null emacsvox-play-program)
      (process-send-string
       tts-speaker-process
       (format "p %s\n" resource)))
     ((and
       emacsvox-pactl
       (string= emacsvox-play-program emacsvox-pactl))
      (emacsvox-sounds-ensure-sample resource sample-id)
      (start-process
       "Play" nil emacsvox-pactl "play-sample" sample-id))
     (t
      (start-process
       "Play" nil emacsvox-play-program ems--play-args resource)))))

;;;;   queue an auditory icon
(defun emacsvox-queue-icon (icon)
  "Queue auditory icon ICON.
Used by TTS layer to play icons that are found as text property
`auditory-icon' on text being spoken.
This is a private function and  might go away."
  (emacsvox-aural-queue-legacy-icon icon))

;;;;   serve an auditory icon
(defun emacsvox-serve-icon (icon)
  "Serve auditory icon ICON."
  
  (process-send-string
   tts-speaker-process
   (format "p %s\n" (emacsvox-sounds-cache-get icon))))

;;;;   Play an icon

;; Should never be called if local player not available
;; ems--play-args is set when emacsvox-play-program is selected.

(defun emacsvox-play-icon(icon)
  "Produce auditory icon ICON using a local player.
Linux: Pipewire and Pulse: pactl.
without Pipewire/Pulse: play from sox."
  
  (emacsvox-aural-present-legacy-icon icon))

(provide  'emacsvox-sounds)
