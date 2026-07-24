;;; emacsvox-m-player.el --- Media Player -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description: Controlling mplayer from emacs
;; Keywords: Emacsvox, m-player streaming media
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;;
;;  $Revision: 4532 $ |
;; Location https://github.com/robertmeta/emacsvox
;;

;;;   Copyright:

;; Copyright (c) 1995 -- 2024, T. V. Raman
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

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

:

;;; Commentary:

;; Defines an Emacsvox front-end for interacting with @code{mplayer}.
;; Program @code{mplayer}  is a versatile media player capable of playing many
;; streaming media formats.
;; This module provides complete access to all @code{mplayer} functionality
;; from a convenient Emacs interface.
;;
;; @subsection Usage
;;
;; The main entry-point is command @code{emacsvox-multimedia} bound
;; to @kbd{C-e ;}.  This prompts for and launches the desired media
;; stream.  Once a stream is playing, you can control it with
;; single-letter keystrokes in the @code{*M-Player*} buffer.
;; Alternatively, you can switch away from that buffer to do real
;; work, And invoke @code{m-player} commands by first pressing
;; prefix-key @kbd{C-e ;}.  If your Emacs supports @code{repeat-mode},
;; --- @xref{repeating, , , emacs} you can avoid the need to
;; repeatedly press the prefix-key @code{C-e ;} each time; with
;; @code{repeat-mode} active, you only need to press the prefix
;; @code{C-e ;} the first time; subsequent invocations can happen via
;; single-letter presses as long as they are performed in a sequence.
;; As an example, pressing @kbd{v} in the @code{*M-Player*} buffer
;; prompts for and sets the volume; When not in the @code{*M-Player*}
;; buffer, you can achieve the same by pressing @kbd{C-e ; v}.  Press
;; @kbd{C-h b} in the @code{*M-Player*} buffer to list @code{m-player}
;; keybindings.
;;
;;; Code:

;;; Forward variable declarations:

(defvar ansi-color-control-seq-regexp)
(defvar clip-end)
(defvar clip-start)
(defvar default-directory)
(defvar emacsvox-m-player-active-filters)
(defvar emacsvox-m-player-clips)
(defvar emacsvox-m-player-cue-info)
(defvar emacsvox-m-player-default-options)
(defvar emacsvox-m-player-directory)
(defvar emacsvox-m-player-equalizer)
(defvar emacsvox-m-player-filters)
(defvar emacsvox-m-player-hotkey-p)
(defvar emacsvox-m-player-openal-options)
(defvar emacsvox-m-player-options)
(defvar emacsvox-m-player-process)
(defvar emacsvox-m-player-reverb-filter)
(defvar emacsvox-m-player-reverb-table)
(defvar emacsvox-m-player-tap-reverbs)
(defvar emacsvox-media)
(defvar emacsvox-media-directory-regexp)
(defvar emacsvox-media-dynamic-playlist)
(defvar emacsvox-media-extensions)
(defvar emacsvox-media-history)
(defvar ems--media-data)
(defvar locate-command)
(defvar locate-make-command-line)
(defvar sox-sox)

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'dired)
(require 'emacsvox-dired)
(require 'emacsvox-amark)
(require 'ladspa)
(require 'emacsvox-amark)

(declare-function emacsvox-xslt-get "emacsvox-xslt" (style))

;;;  Stream Metadata:

(cl-defstruct ems--media-data
  title artist album info
  year comment track genre)

(defvar-local ems--media-data nil
  "Instance of stream metadata for this buffer.")

(defun emacsvox-m-player-show-data ()
  "Display metadata after refreshing it if needed."
  (interactive)
  (let ((data (emacsvox-m-player-data-refresh)))
    (with-output-to-temp-buffer "M Player Metadata"
      (cl-loop
       for f in
       (cl-rest
        (mapcar #'car (cl-struct-slot-info 'ems--media-data)))
       do
       (when (cl-struct-slot-value 'ems--media-data f data)
         (princ
          (format
           "%s:\t%s\n"
           f
           (cl-struct-slot-value 'ems--media-data f data))))))
    (message "Displayed metadata in other window.")
    (emacsvox-icon 'task-done)))

;;;  define a derived mode for m-player interaction
(define-derived-mode emacsvox-m-player-mode special-mode
  "M-Player Interaction"
  "Major mode for m-player interaction. \n\n
\\{emacsvox-m-player-mode-map}"
  (progn
    (setq-local ems--media-data (make-ems--media-data)
                buffer-undo-list t
                buffer-read-only nil)))

(defvar emacsvox-m-player-process nil
  "Process handle to m-player.")

(defun ems--mp-send (command)
  "Dispatch command to m-player."
  
  (with-current-buffer (process-buffer emacsvox-m-player-process)
    (erase-buffer)
    (process-send-string
     emacsvox-m-player-process
     (format "pausing_keep %s\n" command))
    (accept-process-output emacsvox-m-player-process 0.1)
    (unless (zerop (buffer-size))
      (buffer-substring-no-properties (point-min) (1-  (point-max))))))

(defvar-local  emacsvox-m-player-directory nil
  "Records current directory of media being played.
This is set to nil when playing Internet  streams.")

(defun emacsvox-m-player-mode-line ()
  "Mode-line for M-Player buffers."
  (interactive)
  
  (tts-notify
   (cond
    ((eq 'run (process-status emacsvox-m-player-process))
     (let ((info (emacsvox-m-player-get-position)))
       (when info
         (concat
          (propertize "Position:  " 'pause 90)
          (ems--seconds-to-duration (cl-first info))
          (propertize " of " 'personality voice-smoothen-extra)
          (ems--seconds-to-duration (cl-third info))
          (propertize " in " 'personality voice-smoothen-extra)
          (cl-second info)))))
    (t (format "Process MPlayer not running.")))))

;;; Dynamic playlist:

;; Dynamic playlists are one-shot, and managed directly by emacsvox,
;; i.e. no playlist file.

(defvar emacsvox-media-dynamic-playlist  nil
  "Dynamic --- lists files in the playlist.
Reset immediately after being used.")

;;;###autoload
(defun emacsvox-m-player-add-dynamic (file)
  "Add file to the current  dynamic playlist."
  (interactive
   (list
    (or
     (dired-get-filename  nil t)
     (read-file-name "MP3 File:"))))
  
  (cond
   ((file-directory-p file)
    (cl-loop
     for f in
     (directory-files-recursively file  "\\.mp3\\'") do
     (cl-pushnew f emacsvox-media-dynamic-playlist))
    (message
     (format "Added files from directory %s" (file-name-base file))))
   ((string-match "\\.mp3$" file)
    (cl-pushnew file emacsvox-media-dynamic-playlist)
    (message
     (format
      "Added %s with duration %s to dynamic playlist."
      (file-name-base file)
      (shell-command-to-string (format "soxi -d '%s'" file)))))
   (t (message "No MP3 here.")))
  (forward-line 1)
  (emacsvox-dired-speak-line))

(defun ems--dynamic-playlist-duration ()
  "Return duration of dynamic playlist."
  
  (cl-assert emacsvox-media-dynamic-playlist t "No dynamic playlist")
  (ems-with-messages-silenced
   (let* ((result nil)
          (buff  " *soxi*")
          (proc
           (apply
            #'start-process
            "soxi" buff
            "soxi" "-Td"
            emacsvox-media-dynamic-playlist)))
     (accept-process-output proc 0 100)
     (with-current-buffer buff
       (goto-char (point-min))
       (setq result
             (buffer-substring-no-properties
              (line-beginning-position) (line-end-position))))
     result)))

;;;  emacsvox-m-player

(defgroup emacsvox-m-player nil
  "Emacsvox media player."
  :group 'emacsvox)

(defvar emacsvox-m-player-openal-options
  '("-ao" "openal")
  "Options to use openal  --- this gives us hrtf etc..")

(defvar emacsvox-m-player-default-options
  (list
   "-msglevel"          ; reduce chattiness  while preserving metadata
   (mapconcat
    #'identity
    '("all=4"
      "header=0" "vo=0" "ao=0"
      "decaudio=0" "decvideo=0" "open=0"
      "network=0" "statusline=0" "cplayer=0"
      "seek=0"
      ) ":")
   "-slave"  "-softvol" "-softvol-max" "300" "-quiet" "-use-filedir-conf")
  "Default options for MPlayer.")

(defvar emacsvox-m-player-options
  (copy-sequence emacsvox-m-player-default-options)
  "Options passed to mplayer.")

(defcustom emacsvox-m-player-custom-filters
  nil
  "Additional filters to apply to streams."
  :type
  '(repeat
    (string :tag "filter"))
  :group 'emacsvox-m-player)

;;;###autoload
(defcustom emacsvox-media-location-bindings  nil
  "Map  keys  to launch MPlayer on a  directory."
  :group 'emacsvox-m-player
  :group 'emacsvox-media
  :type
  '(repeat
    :tag "Media Locations"
    (list
     (string :tag "Key")
     (directory :tag "Directory")))
  :set
  #'(lambda (sym val)
      (mapc
       #'(lambda (binding)
           (let ((key (cl-first binding))
                 (directory (cl-second binding)))
             (emacsvox-m-player-bind-hotkey directory (kbd key))))
       val)
      (set-default sym val)))

(defvar emacsvox-media-directory-regexp
  (regexp-opt '("mp3" "audio" ))
  "Pattern matching locations where we store media.")

;;;###autoload
(defun emacsvox-multimedia  ()
  "Start or control Emacsvox multimedia player.
Controls media playback when already playing.

\\{emacsvox-m-player-mode-map}"
  (interactive)
  
  (cond
   ((and emacsvox-m-player-process
         (eq 'run (process-status emacsvox-m-player-process))
         (buffer-live-p (process-buffer emacsvox-m-player-process)))
    (with-current-buffer (process-buffer emacsvox-m-player-process)
      (call-interactively #'emacsvox-m-player-command)))
   (t (call-interactively #'emacsvox-m-player))))

(defun emacsvox-m-player-pop-to-player ()
  "Pop to m-player buffer."
  (interactive)
  
  (unless (process-live-p emacsvox-m-player-process)
    (emacsvox-multimedia))
  (funcall-interactively
   #'switch-to-buffer (process-buffer emacsvox-m-player-process)))

(defun emacsvox-m-player-command (key)
  "Invoke MPlayer commands."
  (interactive (list (read-key-sequence "Key: ")))
  (call-interactively
   (when emacsvox-m-player-process
     (or
      (lookup-key emacsvox-m-player-mode-map key)
      'undefined))))

(defsubst emacsvox-m-player-playlist-p (resource)
  "Check if specified resource matches a playlist type."
  
  (string-match emacsvox-playlist-pattern resource))

(defun emacsvox-m-player-bind-hotkey (directory key)
  "Binds key to invoke m-player  on specified directory."
  (interactive
   (list
    (read-directory-name"Media Directory: ")
    (read-key-sequence "Key: ")))
  (let
      ((command
        (eval
         `(defun
              ,(intern
                (format "emacsvox-media-%s"
                        (file-name-base (directory-file-name directory))))
              (&optional prefix)
            ,(format "Launch media from directory %s. Prefix arg
plays result as a directory." directory)
            (interactive)
            (let ((default-directory ,directory))
              (setq emacsvox-m-player-directory ,directory)
              (emacsvox-m-player-hotkey ,directory))))))
    (global-set-key key command)
    (put command 'repeat-map 'emacsvox-m-player-mode-map)))

(defvar emacsvox-m-player-hotkey-p nil
  "Flag set by hotkeys. Let-binding this causes default-directory
 to be ignored when guessing directory.")

(defun emacsvox-m-player-hotkey (_dir)
  "Launch MPlayer on   `directory'."
  (let ((ido-case-fold t)
        (emacsvox-m-player-hotkey-p t))
    (call-interactively #'emacsvox-multimedia)
    (emacsvox-icon 'select-object)))

(defun emacsvox-media-guess-directory ()
  "Guess media directory.
1. If default directory matches emacsvox-media-directory-regexp,use it.
2.  If default directory contains media files, then use it.
3. If default directory contains directory emacsvox-media --- then use it.
4. Otherwise use emacsvox-media-shortcuts as the fallback."
  (let ((case-fold-search t))
    (cond
     ((or (eq major-mode 'dired-mode) (eq major-mode 'locate-mode)) nil)
     (emacsvox-m-player-hotkey-p   emacsvox-media-shortcuts)
     ((or                               ;  dir  contains media:
       (string-match emacsvox-media-directory-regexp default-directory)
       (directory-files default-directory   nil emacsvox-media-extensions))
      default-directory)
     ((file-in-directory-p emacsvox-media default-directory) emacsvox-media)
     (t   emacsvox-media-shortcuts))))

;;;###autoload
(defun emacsvox-m-player-url (url &optional playlist-p)
  "Call emacsvox-m-player on  URL.
URL fragment specifies optional start position."
  (interactive (list (car (browse-url-interactive-arg "Media URL: "))))
  
  (ems-with-messages-silenced
   (cl-multiple-value-bind
       (link offset ) (split-string url "#")
     (cond
      ((and  offset
             (string-match "[[:digit:].]+" offset))
       (let ((emacsvox-m-player-options
              (append emacsvox-m-player-options (list "-ss" offset))))
         (emacsvox-m-player link playlist-p)))
      (t (emacsvox-m-player link playlist-p))))))

(defsubst emacsvox-m-player-directory-files (directory)
  "Return media files in directory. "
  
  (let ((case-fold-search t))
    (directory-files-recursively directory emacsvox-media-extensions)))

(defvar-local emacsvox-m-player-url-p nil
  "Records if  playing a URL")

(defvar-local emacsvox-m-player-url nil
  "Records   currently playing URL")

(defvar-local emacsvox-m-player-resource nil
  "Records   currently playing resource")

(defun emacsvox-media-local-resource (prefix)
  "Read local filename starting from default-directory or
  emacsvox-m-player-directory using completion over all
subfiles.  Interactive prefix arg causes it to read a directory
rather than completing over all subfiles."
  
  (let ((completion-ignore-case t)
        (case-fold-search t))
    (cond
     (prefix
      (setq current-prefix-arg nil)
      (read-directory-name "Media:" emacsvox-m-player-directory))
     (t
      (completing-read
       "Media: "
       (directory-files-recursively
        default-directory emacsvox-media-extensions))))))
(defvar emacsvox-media-history nil
  "Media history when prompting in minibuffer.")

(defun emacsvox-media-read-resource (&optional prefix)
  "Read resource from minibuffer.
If a dynamic playlist exists, just use it."
  (cond
   (emacsvox-media-dynamic-playlist nil) ; do nothing if dynamic playlist
   (emacsvox-m-player-hotkey-p (emacsvox-media-local-resource prefix))
   (t                               ; not hotkey, not dynamic playlist
    (let* ((completion-ignore-case t)
           (minibuffer-completing-file-name t)
           (read-file-name-completion-ignore-case t)
           (filename
            (when (memq major-mode '(dired-mode locate-mode))
              (dired-get-filename 'local 'no-error)))
           (dir (emacsvox-media-guess-directory))
           (collection
            (or
             filename                   ; short-circuit expensive call
             (if prefix
                 (ems--subdirs-recursively  dir) ;list dirs
               (directory-files-recursively dir emacsvox-media-extensions)))))
      (or filename
          (completing-read "Media: "  collection
                           nil nil nil 'emacsvox-media-history))))))

(defun emacsvox-m-player-data-refresh ()
  "Populate metadata fields from current  stream."
  
  (with-current-buffer (process-buffer emacsvox-m-player-process)
    (cl-loop
     for  f in
     '(title artist album year comment track genre)
     do
     (aset ems--media-data
           (cl-struct-slot-offset 'ems--media-data f)
           (cl-second
            (split-string
             (emacsvox-m-player-slave-command (format "get_meta_%s" f))
             "="))))
    ems--media-data))

(defvar emacsvox-m-player-cue-info nil
  "Set to T if  ICY info cued automatically.")

(defun ems--mp-filter (process output)
  "Filter function to captures metadata.
 Cleanup ANSI escape sequences."
  (when (process-live-p process)
    (with-current-buffer (process-buffer process)
      (when (and ems--media-data
                 (ems--media-data-p ems--media-data)
                 (string-match "ICY Info:" output))
        (setf
         (ems--media-data-info ems--media-data)
         (format "%s" output))
        (when emacsvox-m-player-cue-info
          (emacsvox-icon 'progress)
          (emacsvox-m-player-stream-info)))
      (goto-char (process-mark process))
      (let ((start (point)))
        (insert output)
        (save-excursion
          (goto-char start)
          (while
              (re-search-forward ansi-color-control-seq-regexp
                                 (point-max) 'no-error)
            (delete-region (match-beginning 0) (match-end 0))))))))

(defun emacsvox-m-player-amark-save ()
  "Save amarks."
  (interactive)
  (when
      (and  emacsvox-m-player-directory
            (process-live-p emacsvox-m-player-process))
    (with-current-buffer
        (process-buffer emacsvox-m-player-process)
      (emacsvox-amark-save))))

(defvar emacsvox-m-player-paused nil
  "Pause/unpased state of player.")

;;;###autoload
(defun emacsvox-m-player (resource &optional play-list)
  "Play  resource, or play dynamic playlist if set.  Optional prefix argument
play-list interprets resource as a play-list.  Second interactive
prefix arg adds option -allow-dangerous-playlist-parsing to mplayer.
See command \\[emacsvox-m-player-add-dynamic] for adding to the
dynamic playlist. "
  (interactive
   (list
    (emacsvox-media-read-resource current-prefix-arg)
    current-prefix-arg))
  (when
      (and emacsvox-m-player-process
           (eq 'run (process-status emacsvox-m-player-process))
           (y-or-n-p "Stop "))
    (emacsvox-m-player-quit)
    (setq emacsvox-m-player-process nil))
  (tts-notify (file-name-base resource))
  (let ((buffer (get-buffer-create "*M-Player*"))
        (process-connection-type nil)
        (playlist-p
         (and resource
              (not (file-directory-p resource))
              (or play-list (emacsvox-m-player-playlist-p resource))))
        (options (copy-sequence emacsvox-m-player-options))
        (file-list  (reverse emacsvox-media-dynamic-playlist))
        (duration
         (when emacsvox-media-dynamic-playlist
           (ems--dynamic-playlist-duration))))
    (when emacsvox-m-player-custom-filters
      (cl-pushnew
       (mapconcat #'identity emacsvox-m-player-custom-filters ",")
       options)
      (push "-af" options))
    (with-current-buffer buffer
      (emacsvox-m-player-mode)
      (setq emacsvox-m-player-resource resource
            emacsvox-m-player-url-p
            (and resource (string-match "^http" resource)))
      (when emacsvox-m-player-url-p
        (setq emacsvox-m-player-url resource))
      (unless emacsvox-m-player-url-p
        (when resource
          (setq resource (expand-file-name resource))
          (emacsvox-speak-load-directory-settings)
          (setq emacsvox-m-player-directory (file-name-directory resource)))
        (unless emacsvox-media-dynamic-playlist
          (if   (file-directory-p resource)
              (setq file-list (emacsvox-m-player-directory-files resource))
            (setq file-list (list resource)))))
      (setq emacsvox-media-dynamic-playlist nil) ; consume it
      (setq options
            (cond
             ((and play-list  (listp play-list)(< 4   (car play-list)))
              (nconc options
                     (list "-allow-dangerous-playlist-parsing" "-playlist"
                           resource)))
             (playlist-p
              (nconc options (list "-playlist" resource)))
             (file-list (nconc options file-list))
             (t
              (nconc options (list resource)))))
      (setq buffer-undo-list  t)
      (setq emacsvox-m-player-process
            (apply
             #'start-process "MPLayer" buffer
             emacsvox-mplayer options))
      (set-process-sentinel
       emacsvox-m-player-process #'ems--repeat-sentinel)
      (set-process-filter  emacsvox-m-player-process #'ems--mp-filter)
      (setq emacsvox-m-player-paused nil)
      (when
          (and
           emacsvox-m-player-directory
           (file-exists-p emacsvox-m-player-directory))
        (cd emacsvox-m-player-directory)
        (emacsvox-amark-load))
      (when (called-interactively-p 'interactive)
        (message
         "%s"
         (cond
          ((null resource)
           (format
            "Dynamic playlist with %s tracks and duration %s"
            (length file-list) duration))
          ((file-directory-p resource)
           (car (last (split-string resource "/" t))))
          (t
           (file-name-base  resource))))))))

(defun emacsvox-m-player-using-openal ()
  "Use openal.  "
  (interactive)
  (let ((emacsvox-m-player-options
         (append emacsvox-m-player-options
                 emacsvox-m-player-openal-options)))
    (call-interactively #'emacsvox-m-player )))

(defvar emacsvox-m-player-hrtf-options
  '("-af" "hrtf=s" "-af" "resample=48000")
  "Additional options to use built-in HRTF.")

(defun emacsvox-m-player-using-hrtf ()
  "Add af resample=48000,hrtf to startup options.
This will work if the soundcard is set to 48000."
  (interactive)
  (let ((emacsvox-m-player-options
         (append emacsvox-m-player-options
                 emacsvox-m-player-hrtf-options)))
    (call-interactively #'emacsvox-m-player)))

;;;###autoload
(defun emacsvox-m-player-shuffle ()
  "M-Player with shuffle turned on."
  (interactive)
  
  (let ((emacsvox-m-player-options
         (append emacsvox-m-player-options (list "-shuffle"))))
    (call-interactively #'emacsvox-m-player)))

(defun emacsvox-m-player-loop (&optional raw)
  "M-Player with repeat indefinitely  turned on.
Interactive prefix `raw' reads a raw URL."
  (interactive "P")
  
  (let ((emacsvox-m-player-options
         (append emacsvox-m-player-options (list "-loop" "0"))))
    (cond
     (raw (emacsvox-m-player (read-from-minibuffer "URL: ")))
     (t (call-interactively #'emacsvox-m-player)))))

;;;  Table of slave commands:

(defvar emacsvox-m-player-command-list nil
  "Cache of MPlayer slave commands.")

(defun emacsvox-m-player-command-list ()
  "Return MPlayer slave command table, populating it if
necessary."
  
  (cond
   (emacsvox-m-player-command-list emacsvox-m-player-command-list)
   (t
    (let ((commands
           (split-string
            (shell-command-to-string
             (format "%s -input cmdlist"
                     emacsvox-mplayer))
            "\n" 'omit-nulls)))
      (setq emacsvox-m-player-command-list
            (cl-loop  for c in commands
                      collect
                      (split-string c " " 'omit-nulls)))))))

;;;  commands

(defun emacsvox-m-player-toggle-extrastereo ()
  "Toggle application of extrastereo filter to all streams."
  (interactive )
  
  (cond
   ((member "extrastereo" emacsvox-m-player-custom-filters)
    (setq
     emacsvox-m-player-custom-filters
     (remove "extrastereo" emacsvox-m-player-custom-filters))
    (message "Effect extrastereo no longer applied to all streams")
    (emacsvox-icon 'off))
   (t
    (cl-pushnew "extrastereo" emacsvox-m-player-custom-filters
                :test #'string-equal)
    (message "Effect extrastereo  applied to all streams")
    (emacsvox-icon 'on))))

(defun emacsvox-m-player-get-position ()
  "Return list (position filename length)  to use as an amark. "
  
  (with-current-buffer (process-buffer emacsvox-m-player-process)
    ;; try accept-process-output instead of
    ;; dispatching  command twice to avoid flakiness in mplayer
    (accept-process-output emacsvox-m-player-process 0.1)
    (let* ((output
            (ems--mp-send
             "get_time_pos\nget_file_name\nget_time_length\n") )
           (lines (when output (split-string output "\n" 'omit-nulls)))
           (fields
            (cl-loop
             for l in lines
             collect (cl-second (split-string l "=")))))
      (list
       (format "%s" (cl-first fields))  ; position
       (if (cl-second fields)
           (substring (cl-second  fields) 1 -1)
         "")
       (format "%s" (cl-third fields))))))

(defun emacsvox-m-player-filename ()
  "Return filename of current  track."
  (substring ;; strip quotes
   (cl-second
    (split-string
     (ems--mp-send "get_file_name\n")
     "="))
   1 -1))

(defun emacsvox-m-player-scale-speed (factor)
  "Scale speed by factor."
  (interactive "nFactor:")
  (ems--mp-send
   (format "af_add scaletempo=scale=%f:speed=pitch" factor)))

(defun emacsvox-m-player-slower ()
  "Slow down playback. "
  (interactive)
  (emacsvox-m-player-scale-speed 0.9091))

(defun emacsvox-m-player-faster ()
  "Speed up  playback. "
  (interactive)
  (emacsvox-m-player-scale-speed 1.1))

(defun emacsvox-m-player-half-speed ()
  "Scale speed by 0.5."
  (interactive)
  (emacsvox-m-player-scale-speed 0.5))

(defun emacsvox-m-player-double-speed()
  "Scale speed by 2.0"
  (interactive)
  (emacsvox-m-player-scale-speed 2.0))

(defun emacsvox-m-player-reset-speed ()
  "Reset  speed."
  (interactive)
  (ems--mp-send
   "speed_set 1.0"))

(defun emacsvox-m-player-skip-tracks (step)
  "Skip tracks."
  (interactive"nSkip Tracks:")
  (unless (zerop step)
    (ems--mp-send
     (format "pt_step %d" step))))

(defun emacsvox-m-player-previous-track ()
  "Previous track."
  (interactive)
  (emacsvox-m-player-skip-tracks -1))

(defun emacsvox-m-player-next-track ()
  "Next track."
  (interactive)
  (emacsvox-m-player-skip-tracks 1))

(defun emacsvox-m-player-play-tree-up (step)
  "Move within the play tree."
  (interactive
   (list
    (read-from-minibuffer "Move by: ")))
  (ems--mp-send
   (format "pt_up %s" step)))

(defun emacsvox-m-player-alt-src-step (step)
  "Move within an ASF playlist."
  (interactive
   (list
    (read-from-minibuffer "Move by: ")))
  (ems--mp-send
   (format "alt_src_step %s" step)))

(defun emacsvox-m-player-seek-relative (offset)
  "Seek  by offset from current position.
Time offset can be specified as a number of seconds, or as HH:MM:SS."
  (interactive
   (list
    (read-from-minibuffer "Offset: ")))
  (when (string-match ":" offset)
    (setq offset (ems--duration-to-seconds offset)))
  (ems--mp-send (format "seek %s" offset)))

(defun emacsvox-m-player-seek-percentage (pos)
  "Seek  to absolute pos in percent."
  (interactive
   (list
    (read-from-minibuffer "Seek to percentage: ")))
  (ems--mp-send
   (format "seek %s 1" pos)))

(defun emacsvox-m-player-seek-absolute (pos)
  "Seek  to absolute pos in seconds.
The time position can also be specified as HH:MM:SS."
  (interactive
   (list
    (read-from-minibuffer "Seek to time position: ")))
  (when (string-match ":" pos)
    (setq pos (ems--duration-to-seconds pos)))
  (ems--mp-send (format "seek %s 2" pos)))

(defun emacsvox-m-player-start-track()
  "Move to beginning."
  (interactive)
  (emacsvox-m-player-seek-absolute "0"))

(defun emacsvox-m-player-end-track()
  "Move to end."
  (interactive)
  (emacsvox-m-player-seek-absolute "99"))

(defun emacsvox-m-player-backward-10s ()
  "Move back 10 seconds."
  (interactive)
  (emacsvox-m-player-seek-relative "-10"))

(defun emacsvox-m-player-forward-10s ()
  "Move forward 10 seconds."
  (interactive)
  (emacsvox-m-player-seek-relative "10"))

(defun emacsvox-m-player-backward-1min ()
  "Move back 1 minute."
  (interactive)
  (emacsvox-m-player-seek-relative "-60"))

(defun emacsvox-m-player-forward-1min ()
  "Move forward by 1 minute."
  (interactive)
  (emacsvox-m-player-seek-relative "60"))

(defun emacsvox-m-player-backward-10min ()
  "Move backward ten minutes."
  (interactive)
  (emacsvox-m-player-seek-relative "-600"))

(defun emacsvox-m-player-forward-10min ()
  "Move forward ten minutes."
  (interactive)
  (emacsvox-m-player-seek-relative "600"))

(defun emacsvox-m-player-pause ()
  "Pause or unpause."
  (interactive)
  
  (tts-stop 'all)
  (ems--mp-send "pause")
  (setq emacsvox-m-player-paused (not emacsvox-m-player-paused)))

(defvar ems--m-player-mark "00-LastStopped"
  "Name used to  mark position where we stopped.")

(defun emacsvox-m-player-quit ()
  "Quit."
  (interactive)
  (repeat-exit)
  (let ((kill-buffer-query-functions nil)
        (emacsvox-speak-messages nil))
    (when (eq (process-status emacsvox-m-player-process) 'run)
      (let ((buffer (process-buffer emacsvox-m-player-process)))
        (with-current-buffer buffer
          (when emacsvox-m-player-url
            (let ((time  (cl-first (emacsvox-m-player-get-position))))
              (setq
               emacsvox-m-player-media-history
               (cl-remove-if
                #'(lambda(u)
                    (string=
                     (cl-first (split-string u "#"))
                     (cl-first
                      (split-string emacsvox-m-player-url "#"))))
                emacsvox-m-player-media-history))
              (cl-pushnew
               (format
                "%s#%s"
                (cl-first (split-string emacsvox-m-player-url "#"))
                (or time "0"))
               emacsvox-m-player-media-history
               :test #'string=)))
          ;;dont amark shortcut streams
          (unless
              (or
               emacsvox-m-player-url-p
               (and emacsvox-m-player-resource
                    (string-match
                     emacsvox-media-shortcuts
                     emacsvox-m-player-resource))
               (cl-minusp (emacsvox-m-player-get-length)))
            (emacsvox-m-player-amark-add ems--m-player-mark)
            (emacsvox-m-player-amark-save))
          (ems--mp-send "quit")
          (unless (eq (process-status emacsvox-m-player-process) 'exit)
            (delete-process  emacsvox-m-player-process))
          (setq emacsvox-m-player-process nil)
          (and (buffer-live-p buffer) (kill-buffer buffer))
          (emacsvox-speak-mode-line)
          (emacsvox-icon 'close-object))))))

(defun emacsvox-m-player-volume-up ()
  "Volume up."
  (interactive)
  (ems--mp-send "volume 1")
  (emacsvox-icon 'right))

(defun emacsvox-m-player-volume-down ()
  "Volume down."
  (interactive)
  (ems--mp-send "volume -1")
  (emacsvox-icon 'left))

(defvar-local emacsvox-m-player-active-filters nil
  "Active filters.")

(defun emacsvox-m-player-volume-change (value)
  "Set volume."
  (interactive"sChange Volume to:")
  
  (cl-pushnew "volume" emacsvox-m-player-active-filters :test #'string=)
  (ems--mp-send
   (format "volume %s, 1" value)))

(defun emacsvox-m-player-balance ()
  "Set left/right balance."
  (interactive)
  (ems--mp-send
   (format "balance %s"
           (read-from-minibuffer "Balance -- Between -1 and 1:"))))

(defun emacsvox-m-player-slave-command (command)
  "Dispatch slave command."
  (interactive
   (list
    (completing-read "Slave Command: " (emacsvox-m-player-command-list))))
  (with-current-buffer (process-buffer emacsvox-m-player-process)
    (let* ((args
            (when (cdr (assoc command emacsvox-m-player-command-list))
              (read-from-minibuffer
               (mapconcat
                #'identity
                (cdr (assoc command emacsvox-m-player-command-list))
                " "))))
           (result
            (ems--mp-send (format "%s %s" command args))))
      (when result
        (setq result (replace-regexp-in-string  "^ans_" "" result))
        (setq result (replace-regexp-in-string  "_" " " result)))
      (when (called-interactively-p 'interactive)
        (message   "%s"
                   (or result "Waiting")))
      result)))

(defun emacsvox-m-player-delete-filter (filter)
  "Delete filter."
  (interactive
   (list
    (with-current-buffer (process-buffer emacsvox-m-player-process)
      (completing-read "Filter:"
                       (or emacsvox-m-player-active-filters
                           emacsvox-m-player-filters nil nil)))))
  (with-current-buffer (process-buffer emacsvox-m-player-process)
    (let* ((result (ems--mp-send (format "af_del %s" filter))))
      (setq emacsvox-m-player-active-filters
            (remove  filter emacsvox-m-player-active-filters))
      (when result
        (setq result (replace-regexp-in-string  "^ans_" "" result))
        (setq result (replace-regexp-in-string  "_" " " result)))
      (message   "%s" (or result "Waiting")))))

(defun emacsvox-m-player-display-percent ()
  "Display current percentage."
  (interactive)
  (message (emacsvox-m-player-slave-command "get_percent_pos")))

(defun emacsvox-m-player-stream-info (&optional toggle-cue)
  "Speak and display metadata.
Interactive prefix arg toggles automatic cueing of ICY info updates."
  (interactive "P")
  (with-current-buffer (process-buffer emacsvox-m-player-process)
    (unless   ems--media-data  (error "No metadata"))
    (let* ((m (ems--media-data-info  ems--media-data))
           (info (and m (cl-second (split-string m "=")))))
      (when toggle-cue
        (setq emacsvox-m-player-cue-info
              (not emacsvox-m-player-cue-info))
        (when  emacsvox-m-player-cue-info
          (emacsvox-icon
           (if emacsvox-m-player-cue-info 'on 'off))))
      (message (format "%s" (or info  "No Stream Info"))))))

(defun emacsvox-m-player-get-length ()
  "Display length of track."
  (interactive)
  (let ((a
         (read
          (cl-second (split-string (ems--mp-send "get_time_length") "=")))))
    (message (format "%s" a))
    a))

(defconst emacsvox-m-player-display-cmd
  "get_time_pos\nget_percent_pos\nget_time_length\nget_file_name\n"
  "Command we send MPlayer to display position.")

(defun emacsvox-m-player-show-pos ()
  "Display current position in track."
  (interactive)
  
  (let ((fields nil)
        (result (ems--mp-send emacsvox-m-player-display-cmd)))
    (when result
      (setq result (replace-regexp-in-string  "^ans_" "" result))
      (setq fields
            (mapcar
             #'(lambda (s) (split-string s "="))
             (split-string  result "\n"))))
    (cond
     (fields                       ; speak them after audio formatting
      (cl-loop
       for f in fields do
       (put-text-property 0 (length (cl-first f))
                          'personality 'voice-smoothen (cl-first f))
       (put-text-property 0 (length (cl-second f))
                          'personality 'voice-bolden (cl-second f)))
      (setq result
            (cl-loop
             for f in fields
             collect
             (concat (cl-first f) " " (cl-second f) "\n ")))
      (tts-with-punctuations 'some
                             (message (apply #'concat result))))
     (t (message "Waiting")))))

(defconst emacsvox-m-player-filters
  '( "extrastereo" "extrastereo=1.5" "volnorm" "surround"
     "channels=2:2:1:0:0:1"
     "channels=1:0:0:0:1"
     "channels=1:1:0:1:1"
     "channels=1:2"
     "ladspa=bs2b:bs2b:700:4.5"
     "ladspa=ZamAutoSat-ladspa.so:ZamAutoSat:"
     "ladspa=tap_pinknoise.so:tap_pinknoise:0.5:-2:-12"
     "ladspa=ZamHeadX2-ladspa.so:ZamHeadX2:0:60:2.5"
     "ladspa=ZamHeadX2-ladspa.so:ZamHeadX2:0:30:2.5"
     "ladspa=ZamHeadX2-ladspa.so:ZamHeadX2:0:45:2.5"
     "ladspa=ZamHeadX2-ladspa.so:ZamHeadX2:0:15:2.5"
     "ladspa=amp:amp_stereo:2"
     "ladspa=amp:amp_stereo:0.5"
     (concat  "ladspa=tap_autopan:tap_autopan:.0016:100:1.5,"
              " ladspa=tap_autopan:tap_autopan:.06:33:2")
     "bs2b profile=cmoy" "bs2b profile=jmeier" "bs2b")
  "Table of MPlayer filters.")

(defun emacsvox-m-player-add-autopan ()
  "Add autopan effect."
  (interactive)
  (emacsvox-m-player-add-filter
   (concat
    "ladspa=tap_autopan:tap_autopan:.0016:100:1,"
    "ladspa=tap_autopan:tap_autopan:.016:33:1")))

(defun emacsvox-m-player-add-autosat ()
  "Add ZamAutoSat (auto saturation) effect."
  (interactive)
  (emacsvox-m-player-add-filter
   "ladspa=ZamAutoSat-ladspa.so:ZamAutoSat:"))

(defun emacsvox-m-player-add-filter (filter-name &optional edit)
  "Adds  filter with completion.
 Optional interactive prefix arg `edit' edits the."
  (interactive
   (list
    (completing-read "Filter:"
                     emacsvox-m-player-filters
                     nil nil)
    current-prefix-arg))
  (when edit
    (setq filter-name
          (read-from-minibuffer
           "Edit Filter: " filter-name)))
  (when (process-live-p  emacsvox-m-player-process)
    (push filter-name emacsvox-m-player-active-filters)
    (ems--mp-send (format "af_add %s" filter-name))))

(defun emacsvox-m-player-left-channel ()
  "Play both channels on left."
  (interactive)
  (let ((filter-name "channels=2:1:0:0:1:0"))
    (when (process-live-p  emacsvox-m-player-process)
      (ems--mp-send (format "af_add %s" filter-name)))))

(defun emacsvox-m-player-add-loop (&optional prompt)
  "Add loop 10 is default."
  (interactive "P")
  (when (process-live-p  emacsvox-m-player-process)
    (ems--mp-send
     (format "loop %d" (if prompt (read-number "Count:") 10)))))

(defun emacsvox-m-player-right-channel ()
  "Play on right channel."
  (interactive)
  (let ((filter-name "channels=2:1:0:1:1:1"))
    (when (process-live-p  emacsvox-m-player-process)
      (ems--mp-send (format "af_add %s" filter-name)))))

(defun emacsvox-m-player-balance-channels ()
  "Mono to stereo."
  (interactive)
  (let ((filter-name "channels=1:2"))
    (when (process-live-p  emacsvox-m-player-process)
      (ems--mp-send (format "af_add %s" filter-name)))))
(defun emacsvox-m-player-clear-filters ()
  "Clear all filters"
  (interactive)
  (setq emacsvox-m-player-active-filters nil)
  (when (process-live-p emacsvox-m-player-process)
    (ems--mp-send "af_clr")
    (emacsvox-icon 'delete-object)))

(defun emacsvox-m-player-customize ()
  "Use Customize to set MPlayer options."
  (interactive)
  (customize-variable 'emacsvox-m-player-options)
  (goto-char (point-min))
  (search-forward "INS"))

;;;  Media History:

;;;###autoload
(defvar emacsvox-m-player-media-history nil
  "Record media urls we played.")

(defun emacsvox-m-player-rem-history (url)
  "Remove URL from media history"
  (interactive (list (ems--read-url)))
  
  (setq emacsvox-m-player-media-history
        (cl-remove-if
         #'(lambda(u) (string= u url))
         emacsvox-m-player-media-history))
  (emacsvox-icon 'delete-object)
  (kill-buffer)
  (call-interactively 'emacsvox-m-player-browse-history))

;;;###autoload
(defun emacsvox-m-player-from-history (&optional prefix)
  "Play media from the front of media-history.
   Interactive prefix arg invokes media history browser."
  (interactive "P")
  
  (cond
   ((and prefix emacsvox-m-player-media-history) 
    (call-interactively 'emacsvox-m-player-browse-history))
   (emacsvox-m-player-media-history
    (let ((url (car emacsvox-m-player-media-history ))
          (fields nil))
      (when (string-match "#" url)
        (setq fields (split-string url "#"))
        (unless (string-match "[[:digit:].]+" (cl-second fields))
          (setq url (cl-first fields))))
      (emacsvox-m-player-url url)))
   (t (error "No media history"))))

(defvar emacsvox-m-player-history-map
  (let ((map (make-sparse-keymap)))
    (define-key map ";" 'emacsvox-eww-play-media-at-point)
    (define-key map "k" 'shr-copy-url)
    (define-key map "r" 'emacsvox-m-player-rem-history)
    map)
  "Keymap used in media history browser.")

(defun emacsvox-m-player-browse-history ()
  "Create a  media history browser from media-history."
  (interactive )
  (with-temp-buffer
    (insert "<html>\n
<head><title>Emacsvox Media History</title></head>\n
<body>\n<p>Press ';' to play, 'r'  to remove the link  from the history.</p>\n
<ol>\n")
    (cl-loop
     for u in emacsvox-m-player-media-history do
     (insert
      (format "<li><a href='%s'>%s: %s</a></li>\n"
              u (url-host (url-generic-parse-url u)) (file-name-base  u))))
    (insert "</ol></body></html>\n")
    (add-hook
     'browse-url-of-file-hook
     #'(lambda ()
         (let ((inhibit-read-only t))
           (put-text-property
            (point-min) (point-max)
            'keymap  emacsvox-m-player-history-map)
           (pop browse-url-of-file-hook)
           (emacsvox-icon 'open-object)
           (emacsvox-speak-line))))
    (call-interactively #'browse-url-of-buffer)))

;;;  Reset Options:

(defun emacsvox-m-player-reset-options ()
  "Reset MPlayer options."
  (interactive)
  (setq emacsvox-m-player-options
        (copy-sequence emacsvox-m-player-default-options))
  (message "Reset options."))

;;;  equalizer

;; Equalizer presets:
;; Cloned from VLC and munged for m-player.
;; VLC uses -20db .. 20db; mplayer uses -12db .. 12db
;; See http://advantage-bash.blogspot.com/2013/05/mplayer-presets.html

(defvar ems--eq-presets
  '(
      ("flat" . [0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0])
      ("classical" . [0.0 0.0 0.0 0.0 0.0 -4.4 -4.4 -4.4 -5.8 -6.5])
      ("club" . [0.0 0.0 4.8 3.3 3.3 3.3 1.9 0.0 0.0 0.0])
      ("dance" . [5.7 4.3 1.4 0.0 0.0 -3.4 -4.4 -4.3 0.0 0.0])
      ("full-bass" . [-4.8 5.7 5.7 3.3 1.0 -2.4 -4.8 -6.3 -6.7 -6.7])
      ("full-bass-and-treble" . [4.3 3.3 0.0 -4.4 -2.9 1.0 4.8 6.7 7.2 7.2])
      ("full-treble" . [-5.8 -5.8 -5.8 -2.4 1.4 6.7 9.6 9.6 9.6 10.1])
      ("headphones" . [2.8 6.7 3.3 -2.0 -1.4 1.0 2.8 5.7 7.7 8.6])
      ("large-hall" . [6.2 6.2 3.3 3.3 0.0 -2.9 -2.9 -2.9 0.0 0.0])
      ("live" . [-2.9 0.0 2.4 3.3 3.3 3.3 2.4 1.4 1.4 1.4])
      ("party" . [4.3 4.3 0.0 0.0 0.0 0.0 0.0 0.0 4.3 4.3])
      ("pop" . [-1.0 2.8 4.3 4.8 3.3 0.0 -1.4 -1.4 -1.0 -1.0])
      ("reggae" . [0.0 0.0 0.0 -3.4 0.0 3.8 3.8 0.0 0.0 0.0])
      ("rock" . [4.8 2.8 -3.4 -4.8 -2.0 2.4 5.3 6.7 6.7 6.7])
      ("ska" . [-1.4 -2.9 -2.4 0.0 2.4 3.3 5.3 5.7 6.7 5.8])
      ("soft" . [2.8 1.0 0.0 -1.4 0.0 2.4 4.8 5.7 6.7 7.2])
      ("soft-rock" . [2.4 2.4 1.4 0.0 -2.4 -3.4 -2.0 0.0 1.4 5.3])
      ("techno" . [4.8 3.3 0.0 -3.4 -2.9 0.0 4.8 5.7 5.8 5.3]))
  "MPlayer equalizer presets.")

(defsubst ems--eq-preset-get (name)
  "Return vector of numbers for specified preset."
  
  (cdr (assoc name ems--eq-presets)))

(defconst emacsvox-m-player-equalizer (make-vector 10 0)
  "Vector holding equalizer settings.")

(defconst  emacsvox-m-player-equalizer-bands
  ["31.25 Hz"
   "62.50 Hz"
   "125.00 Hz"
   "250.00 Hz"
   "500.00 Hz"
   "1.00 kHz"
   "2.00 kHz"
   "4.00 kHz"
   "8.00 kHz"
   "16.00 kHz"]
  "Center frequencies for the 10 equalizer bands in MPlayer.")

(defun emacsvox-m-player-eq-controls (v)
  "Manipulate values in  vector using minibuffer.
Applies  the resulting value at each step."
  (interactive)
  
  (let ((column 0)
        (key nil)
        (result  (mapconcat #'number-to-string v  ":"))
        (continue t))
    ;; First, clear any equalizers in effect:
    (ems--mp-send "af_del equalizer")
    ;; Apply specified vector:
    (ems--mp-send (format "af_add equalizer=%s" result))
    (while  continue
      (setq key
            (read-key-sequence
             (format "G%s:%s (%s)" column (aref v column)
                     (aref emacsvox-m-player-equalizer-bands column))))
      (cond
       ((equal key "e")
        (aset
         v column
         (read-number
          (format
           "Value for G%s:%s (%s)"
           column (aref v column)
           (aref emacsvox-m-player-equalizer-bands column)))))
       ((equal key [left])
        (setq column (% (+ 9  column) 10)))
       ((equal key [right])
        (setq column (% (1+ column) 10)))
       ((equal key [up])
        (aset v   column (min 12 (1+ (aref v column)))))
       ((equal key [down])
        (aset v   column (max -12 (1- (aref v column)))))
       ((equal key [prior])
        (aset v   column (min 12 (+ 4  (aref v column)))))
       ((equal key [next])
        (aset v   column (max -12 (- (aref v column)  4))))
       ((equal key [home])
        (aset v   column 12))
       ((equal key [end])
        (aset v   column -12))
       ((equal key "\C-g")
        (ems--mp-send "af_del equalizer")
        (error "Did not change equalizer."))
       ((equal key "\C-m")
        (setq emacsvox-m-player-equalizer v)
        (setq continue nil))
       (t (message "Invalid key")))
      (setq result (mapconcat #'number-to-string v  ":"))
      (ems--mp-send
       (format "af_cmdline equalizer %s" result)))
    result))

(defun emacsvox-m-player-add-equalizer (&optional reset)
  "Add equalizer.  Equalizer is updated as each change
is made, and the final effect set by pressing RET.  Interactive prefix
arg `reset' starts with all filters set to 0."
  (interactive "P")
  (cond
   ((eq 'run  (process-status emacsvox-m-player-process))
    (emacsvox-m-player-eq-controls
     (if reset  (make-vector 10 0)
       emacsvox-m-player-equalizer))
    (emacsvox-icon 'close-object)
    (push "equalizer" emacsvox-m-player-active-filters))
   (t (message "No stream playing"))))

(defun emacsvox-m-player-eq-preset  (name)
  "Prompts for  and apply equalizer preset.

The following presets are available:

flat classical club dance full-bass full-bass-and-treble
 full-treble headphones large-hall live party pop reggae rock
 ska soft soft-rock techno "
  (interactive
   (list
    (completing-read
     "MPlayer Equalizer Preset:"
     ems--eq-presets
     nil 'must-match)))
  
  (let ((result nil)
        (p (ems--eq-preset-get name)))
    (setq emacsvox-m-player-equalizer p)
    (setq result  (mapconcat #'number-to-string p  ":"))
    (ems--mp-send "af_del equalizer")
    (cl-pushnew "equalizer" emacsvox-m-player-active-filters :test #'string=)
    (ems--mp-send (format "af_add equalizer=%s" result))))

;;;  Key Bindings:

(cl-declaim (special emacsvox-m-player-mode-map))

(defvar emacsvox-m-player-bindings
  '(
    ("%" emacsvox-m-player-display-percent)
    ("(" emacsvox-m-player-left-channel)
    (")" emacsvox-m-player-right-channel)
    ("'" emacsvox-m-player-add-loop)
    ("+" emacsvox-m-player-volume-up)
    ("," emacsvox-m-player-backward-10s)
    ("-" emacsvox-m-player-volume-down)
    ("." emacsvox-m-player-forward-10s)
    ("/" emacsvox-m-player-restore-process)
    (";" emacsvox-m-player-pop-to-player)
    ("<" emacsvox-m-player-backward-1min)
    ("<down>" emacsvox-m-player-forward-1min)
    ("<end>" emacsvox-m-player-end-track)
    ("<home>" emacsvox-m-player-start-track)
    ("<left>" emacsvox-m-player-backward-10s)
    ("<next>" emacsvox-m-player-forward-10min)
    ("<prior>" emacsvox-m-player-backward-10min)
    ("<right>" emacsvox-m-player-forward-10s)
    ("<up>" emacsvox-m-player-backward-1min)
    ("=" emacsvox-m-player-volume-up)
    (">" emacsvox-m-player-forward-1min)
    ("?" emacsvox-m-player-show-pos)
    ("T" emacsvox-speak-brief-time)
    ("A" emacsvox-m-player-amark-add)
    ("b" emacsvox-m-player-balance-channels)
    ("C" emacsvox-m-player-clear-filters)
    ("C-a" emacsvox-amark-browse)
    ("C-l" ladspa)
    ("DEL" emacsvox-m-player-reset-speed)
    ("E" emacsvox-m-player-add-equalizer)
    ("G" emacsvox-m-player-seek-percentage)
    ("L" emacsvox-m-player-get-length)
    ("M" emacsvox-m-player-show-data)
    ("M-," emacsvox-m-player-set-clip-start)
    ("M-." emacsvox-m-player-set-clip-end)
    ("O" emacsvox-m-player-reset-options)
    ("P" emacsvox-m-player-apply-reverb)
    ("Q" emacsvox-m-player-quit)
    ("R" emacsvox-m-player-edit-reverb)
    ("S" emacsvox-m-player-amark-save)
    ("SPC" emacsvox-m-player-pause)
    ("[" emacsvox-m-player-slower)
    ("\\" emacsvox-m-player-persist-process)
    ("]" emacsvox-m-player-faster)
    ("a" emacsvox-m-player-add-autopan)
    ("c" emacsvox-m-player-slave-command)
    ("d" emacsvox-m-player-delete-filter)
    ("e" emacsvox-m-player-eq-preset)
    ("f" emacsvox-m-player-add-filter)
    ("g" emacsvox-m-player-seek-absolute)
    ("h" emacsvox-m-player-from-history)
    ("i" emacsvox-m-player-stream-info)
    ("j" emacsvox-m-player-amark-jump)
    ("k" emacsvox-m-player-quit)
    ("l" emacsvox-m-player-store-link)
    ("m" emacsvox-m-player-mode-line)
    ("n" emacsvox-m-player-next-track)
    ("o" emacsvox-m-player-customize)
    ("p" emacsvox-m-player-previous-track)
    ("r" emacsvox-m-player-seek-relative)
    ("s" emacsvox-m-player-scale-speed)
    ("t" emacsvox-m-player-skip-tracks)
    ("v" emacsvox-m-player-volume-change)
    ("w" emacsvox-m-player-write-clip)
    ("x" emacsvox-m-player-pan)
    ("z" emacsvox-m-player-add-autosat)
    ("{" emacsvox-m-player-half-speed)
    ("}" emacsvox-m-player-double-speed)
    )
  "M-Player Key bindings.")

(cl-loop
 for k in emacsvox-m-player-bindings do
 (emacsvox-keymap-update  emacsvox-m-player-mode-map k))

(put 'emacsvox-m-player-shuffle 'repeat-map 'emacsvox-m-player-mode-map)
(put 'emacsvox-m-player-loop 'repeat-map 'emacsvox-m-player-mode-map)
(put 'emacsvox-multimedia 'repeat-map  'emacsvox-m-player-mode-map)
(put 'emacsvox-m-player-using-openal
     'repeat-map
     'emacsvox-m-player-mode-map)
(put 'emacsvox-m-player-volume-set 'repeat-map
     'emacsvox-m-player-mode-map)
;;; repeat-mode
(map-keymap
 (lambda (_key cmd)
   (when
       (and
        (symbolp cmd)
        (not (eq cmd 'digit-argument)))
     (put cmd 'repeat-map 'emacsvox-m-player-mode-map)))
 emacsvox-m-player-mode-map)

;;; disable on stop:
(put 'emacsvox-m-player-quit  'repeat-map nil)
(put 'ladspa  'repeat-map nil)

(defun emacsvox-m-player-volume-set (&optional arg)
  "Set Volume in steps from 1 to 9."
  (interactive "P")
  
  (let ((vol-step
         (cond
          ((not (called-interactively-p 'interactive)) arg)
          (t
           (read (format "%c" last-input-event))))))
    (cl-assert
     (and (integerp vol-step) (< 0 vol-step) (< vol-step 10))
     nil "Volume step should be between 1 and 9")
    (emacsvox-m-player-volume-change (* 11 vol-step))
    (emacsvox-icon 'button)))

(cl-loop
 for i from 1 to 9 do
 (define-key emacsvox-m-player-mode-map
             (kbd (format "%s" i)) 'emacsvox-m-player-volume-set))

(declare-function emacsvox-google-result-url-prefix "emacsvox-google" nil)
;; yt player using mplayer is broken  due to xml manifests
(declare-function
 emacsvox-google-canonicalize-result-url "emacsvox-google" (url))
(declare-function mpv-start "mpv" (&rest args))
(declare-function
 emacsvox-empv-play-url "emacsvox-empv" (url &optional left-channel))

;;;  pause/resume

(defun emacsvox-m-player-pause-or-resume ()
  "Pause/resume if m-player is running. For use  in
emacsvox-silence-hook."
  
  (when (and emacsvox-m-player-process
             (eq 'run (process-status emacsvox-m-player-process)))
    (emacsvox-m-player-pause)))
(add-hook 'emacsvox-silence-hook 'emacsvox-m-player-pause-or-resume)

;;;  AMarks:

(defun emacsvox-m-player-amark-add (name &optional prompt-position)
  "Set AMark `name' at current position.
Interactive prefix arg prompts for position.
As the default, use current position."
  (interactive "sAMark Name:\nP")
  (let* ((pos (emacsvox-m-player-get-position))
         (file-name (cl-second pos)))
    (when
        (and file-name  (not (zerop (length file-name))))
      (setq pos
            (cond
             (prompt-position (read-number "Position: "))
             (t  (cl-first pos))))
      (emacsvox-amark-add file-name name pos)
      (message "Added Amark %s in %s at %s" name file-name pos))))

(defun emacsvox-m-player-store-link ()
  "Store an org-link to currently playing stream at current position."
  (interactive)
  
  (when emacsvox-m-player-url
    (cl-pushnew
     `(
       ,(format "e-media:%s#%s"
                (cl-first (split-string emacsvox-m-player-url "#"))
                (cl-first (emacsvox-m-player-get-position)))
       "URL")
     org-stored-links)))

(defun ems-file-index (name file-list)
  "Return index of name in file-list."
  (cl-position (expand-file-name name) file-list :test #'string=))

(defun emacsvox-m-player-amark-jump ()
  "Jump to AMark."
  (interactive)
  
  (with-current-buffer
      (process-buffer emacsvox-m-player-process)
    (let ((amark (call-interactively #'emacsvox-amark-find)))
      (cond ;; seek if in current  file
       ((string=
         (emacsvox-m-player-filename)
         (emacsvox-amark-path amark))
        (emacsvox-m-player-seek-absolute (emacsvox-amark-position amark)))
       (t (emacsvox-amark-play amark))))))

;;;  Adding specific Ladspa filters:

;; tap_reverb filter

(defvar emacsvox-m-player-reverb-filter
  '("ladspa=tap_reverb:tap_reverb" 10000 -2 -10 1 1 1 1 6)
  "Tap Reverb Settings."
  )

(defun emacsvox-m-player-edit-reverb ()
  "Edit ladspa reverb filter.
  You need to use mplayer built with ladspa support, and have package
  tap-reverb already installed."
  (interactive)
  
  (let ((ladspa(or  (getenv "LADSPA_PATH")
                    "/usr/lib/ladspa"))
        (filter nil)
        (orig-filter
         (mapconcat
          #'(lambda (v) (format "%s" v))
          emacsvox-m-player-reverb-filter ":")))
    (unless ladspa (error "Environment variable LADSPA_PATH not set."))
    (unless (getenv "LADSPA_PATH") (setenv "LADSPA_PATH" ladspa))
    (unless (file-exists-p (expand-file-name "tap_reverb.so" ladspa))
      (error "Package tap_reverb not installed."))
    (setq filter (read-from-minibuffer "Reverb: " orig-filter))
    (setq emacsvox-m-player-reverb-filter(split-string filter ":"))
    (ems--mp-send "af_clr")
    (ems--mp-send (format "af_add %s" filter))))

(defconst emacsvox-m-player-reverb-table
  '(
    ("AfterBurn"   0)
    ("AfterBurn (Long)"   1)
    ("Ambience"   2)
    ("Ambience (Thick)"   3)
    ("Ambience (Thick) - HD"   4)
    ("Cathedral"   5)
    ("Cathedral - HD"   6)
    ("Drum Chamber"   7)
    ("Garage"   8)
    ("Garage (Bright)"   9)
    ("Gymnasium"   10)
    ("Gymnasium (Bright)"   11)
    ("Gymnasium (Bright) - HD"   12)
    ("Hall (Small)"   13)
    ("Hall (Medium)"   14)
    ("Hall (Large)"   15)
    ("Hall (Large) - HD"   16)
    ("Plate (Small)"   17)
    ("Plate (Medium)"   18)
    ("Plate (Large)"   19)
    ("Plate (Large) - HD"   20)
    ("Pulse Chamber"   21)
    ("Pulse Chamber (Reverse)"   22)
    ("Resonator (96 ms)"   23)
    ("Resonator (152 ms)"   24)
    ("Resonator (28 ms)"   25)
    ("Room (Small)"   26)
    ("Room (Medium)"   27)
    ("Room (Large)"   28)
    ("Room (Large) - HD"   29)
    ("Slap Chamber"   30)
    ("Slap Chamber - HD"   31)
    ("Slap Chamber (Bright)"   32)
    ("Slap Chamber (Bright) - HD"   33)
    ("Smooth Hall (Small)"   34)
    ("Smooth Hall (Medium)"   35)
    ("Smooth Hall (Large)"   36)
    ("Smooth Hall (Large) - HD"   37)
    ("Vocal Plate"   38)
    ("Vocal Plate - HD"   39)
    ("Warble Chamber"   40)
    ("Warehouse"   41)
    ("Warehouse - HD"   42))
  "Table mapping tap reverb preset names to values.")

(defconst emacsvox-m-player-tap-reverbs
  '(("AfterBurn" 2.8)
    ("AfterBurn (Long)" 4.8)
    ("Ambience" 1.1)
    ("Ambience (Thick)" 1.2)
    ("Ambience (Thick) - HD" 1.2)
    ("Cathedral" 10)
    ("Cathedral - HD" 10)
    ("Drum Chamber" 3.6)
    ("Garage" 2.3)
    ("Garage (Bright)" 2.3)
    ("Gymnasium" 5.9)
    ("Gymnasium (Bright)" 5.9)
    ("Gymnasium (Bright) - HD" 5.9)
    ("Hall (Small)" 2.0)
    ("Hall (Medium)" 3.0)
    ("Hall (Large)" 5.1)
    ("Hall (Large) - HD" 5.1)
    ("Plate (Small)" 1.7)
    ("Plate (Medium)" 2.6)
    ("Plate (Large)" 5.7)
    ("Plate (Large) - HD" 5.7)
    ("Pulse Chamber" 3.1)
    ("Pulse Chamber (Reverse)" 3.1)
    ("Resonator (96 ms)" 4.0)
    ("Resonator (152 ms)" 4.2)
    ("Resonator (208 ms)" 5.1)
    ("Room (Small)" 1.9)
    ("Room (Medium)" 2.8)
    ("Room (Large)" 4.4)
    ("Room (Large) - HD" 4.4)
    ("Slap Chamber" 2.3)
    ("Slap Chamber - HD" 2.9)
    ("Slap Chamber (Bright)" 3.4)
    ("Slap Chamber (Bright) - HD" 3.7)
    ("Smooth Hall (Small)" 1.8)
    ("Smooth Hall (Medium)" 3.0)
    ("Smooth Hall (Large)" 5.9)
    ("Smooth Hall (Large) - HD" 5.9)
    ("Vocal Plate" 3.1)
    ("Vocal Plate - HD" 3.1)
    ("Warble Chamber" 4.0)
    ("Warehouse" 6.0)
    ("Warehouse - HD" 6.0))
  "Table of tap-reverb presets along with recommended decay values.")

(defun emacsvox-m-player-apply-reverb (preset)
  "Prompt for and apply a reverb preset.
  You need to use mplayer built with ladspa support, and have package
  tap-reverb already installed."
  (interactive
   (list
    (let ((completion-ignore-case t))
      (completing-read "Preset: "
                       emacsvox-m-player-tap-reverbs
                       nil 'must-match))))
  (let ((setting (assoc preset emacsvox-m-player-tap-reverbs))
        (ladspa (getenv "LADSPA_PATH"))
        (filter-spec nil)
        (filter nil))
    (unless (process-live-p emacsvox-m-player-process)
      (error "No media playing"))
    (unless ladspa
      (setq ladspa (setenv "LADSPA_PATH" "/usr/lib/ladspa")))
    (unless (file-exists-p (expand-file-name "tap_reverb.so" ladspa))
      (error "Package tap_reverb not installed."))
    (setq filter-spec
          `("ladspa=tap_reverb:tap_reverb"
            ,(round (* 1000 (cl-second setting))) ;  delay  in ms
            0 -7                               ; dry and wet db
            1 1 1 1
                                        ; preset name
            ,(cadr (assoc (cl-first setting)
                          emacsvox-m-player-reverb-table))))
    (setq emacsvox-m-player-reverb-filter filter-spec)
    (setq filter (mapconcat #'(lambda (v) (format "%s" v)) filter-spec ":"))
    (ems--mp-send "af_clr")
    (ems--mp-send
     (format "af_add %s" filter))
    (emacsvox-icon 'button)))

;;;  Play RSS Stream:

;;;###autoload
(defun emacsvox-m-player-play-rss (rss-url)
  "Play an RSS stream."
  (interactive
   (list
    (ems--read-url)))
  (let* ((file (make-temp-file  "rss-media" nil ".m3u"))
         (buffer (find-file-noselect file)))
    (message "Retrieving playlist.")
    (with-current-buffer buffer
      (insert-buffer-substring
       (emacsvox-xslt-xml-url
        (emacsvox-xslt-get "rss2m3u.xsl")
        rss-url))
      (save-buffer))
    (emacsvox-m-player file 'playlist)))

;;;  Use locate to construct media playlist:

(defvar emacsvox-locate-media-map
  (let ((map (make-sparse-keymap)))
    (define-key map ";" 'emacsvox-dired-play-duration)
    (define-key  map (kbd "M-;") 'emacsvox-m-player-add-dynamic)
    (define-key map "\C-m" 'emacsvox-locate-play-results-as-playlist)
    map)
  "Keymap used to play locate results.")
(add-hook 'locate-mode-hook
          #'emacsvox-pronounce-refresh-pronunciations)
;;;###autoload
(defun emacsvox-m-player-locate-media (pattern)
  "Locate media matching  pattern.  The results can be
played as a play-list by pressing [RET] on the first line, see
 \\[emacsvox-dired-open-this-file] locally bound to C-RET
to play  tracks."
  (interactive "sSearch Pattern: ")
  (let ((inhibit-read-only t)
        (case-fold-search t)
        (locate-make-command-line
         #'(lambda (s) (list locate-command "-i" "--regexp" s))))
    (locate-with-filter
     (mapconcat #'identity
                (split-string pattern)
                "[ '/\"_.,-]")
     emacsvox-media-extensions)
    (goto-char (point-min))
    (message "Buffer: %s" (current-buffer))
    (put-text-property
     (point-min) (point-max)
     'keymap  emacsvox-locate-media-map)
    (emacsvox-icon 'open-object)
    (rename-buffer (format "Media  matching %s" pattern))
    (emacsvox-speak-mode-line)))

;;;  MultiPlayer Support:

(defun emacsvox-m-player-persist-process (&optional name)
  "Persists  m-player process instance by renaming its buffer.
Optional interactive prefix arg prompts for name to use for  player."
  (interactive "P")
  
  (when (process-live-p emacsvox-m-player-process)
    (with-current-buffer  (process-buffer emacsvox-m-player-process)
      (set (make-local-variable 'emacsvox-m-player-process)
           emacsvox-m-player-process)
      (set-default 'emacsvox-m-player-process nil)
      (rename-buffer
       (if name
           (format "*%s*" (read-from-minibuffer "Name: "))
         "Persisted-M-Player*")
       'unique))
    (when (called-interactively-p 'interactive)
      (emacsvox-icon 'task-done)
      (tts-notify
       "persisted current process. You can now start another player."))))

(defun emacsvox-m-player-restore-process ()
  "Restore emacsvox-m-player-process from current buffer.
Check first if current buffer is in emacsvox-m-player-mode."
  (interactive)
  
  (unless (eq major-mode 'emacsvox-m-player-mode)
    (error "This is not an MPlayer buffer."))
  (let ((proc
         (or (get-buffer-process (current-buffer))
             emacsvox-m-player-process)))
    (cond
     ((process-live-p proc)
      (setq emacsvox-m-player-process proc)
      (set-default 'emacsvox-m-player-process proc)
      (emacsvox-icon 'open-object)
      (message "Restored  player process."))
     (t (error "No live player here.")))))

;;;  Panning:

(defvar-local emacsvox-m-player-panner 0
  "The 11 pre-defined panning locations.")

(defun emacsvox-m-player-pan ()
  "Pan from left to right   and back  one step at a time."
  (interactive)
  
  (unless (process-live-p emacsvox-m-player-process) (error "No   player."))
  (let* ((this (abs  (/ emacsvox-m-player-panner 10.0)))
         (pan (format "%.1f:%.1f" (- 1  this)  this)))
    (ems--mp-send  "af_del pan, channels")
    (ems--mp-send (format "af_add pan=2:%s:%s" pan pan))
    (setq emacsvox-m-player-panner (1+ emacsvox-m-player-panner))
    (when (= 10 emacsvox-m-player-panner)
      (setq emacsvox-m-player-panner -10))
    (message "Panned  to %.1f %.1f" (- 1 this) this)))

;;;  Apply Ladspa to MPlayer:

(defun emacsvox-m-player-ladspa-cmd (plugin)
  "Convert Ladspa Plugin to M-Player command args."
  (format
   "ladspa=%s:%s:%s"
   (ladspa-plugin-library plugin) (ladspa-plugin-label plugin)
   (mapconcat #'ladspa-control-value (ladspa-plugin-controls plugin) ":")))

(defun emacsvox-m-player-add-ladspa ()
  "Apply plugin to running MPlayer.
Copies  invocation string to kill-ring so it can be added easily to
our pre-defined filters if appropriate."
  (interactive)
  
  (unless (eq major-mode 'ladspa-mode) (error "This is not a Ladspa buffer"))
  (unless (get-text-property (point) 'ladspa)
    (error "No Ladspa Plugin here."))
  (unless (process-live-p emacsvox-m-player-process)
    (error "No running MPlayer."))
  (let ((result nil)
        (plugin (get-text-property (point) 'ladspa))
        (args nil))
    (when
        (cl-some
         #'null
         (mapcar #'ladspa-control-value (ladspa-plugin-controls plugin)))
      (ladspa-instantiate))
    (setq args (emacsvox-m-player-ladspa-cmd plugin))
    (kill-new args)
    (setq result
          (ems--mp-send (format "af_add %s" args)))
    (when (called-interactively-p 'interactive)
      (message   "%s"
                 (or result "Waiting")))))

(defun emacsvox-m-player-delete-ladspa ()
  "Delete plugin from  running MPlayer."
  (interactive)
  
  (unless (eq major-mode 'ladspa-mode) (error "This is not a Ladspa buffer"))
  (unless (process-live-p emacsvox-m-player-process)
    (error "No running MPlayer."))

  (ems--mp-send "af_del ladspa"))

;;;  Clipping:

(defcustom emacsvox-m-player-clips
  (expand-file-name "~/mp3/clips")
  "Directory where we store clips."
  :type 'directory
  :group 'emacsvox-m-player)

;; Functionality restored from emacsvox-alsaplayer.el:

(defvar-local clip-start nil
  "Start position of clip.")

(defvar-local clip-end nil
  "End position of clip.")

(defun emacsvox-m-player-set-clip-start    ( )
  "Set start of clip. "
  (interactive )
  (setq clip-start
        (read-number
         "Start Time: "
         (read (cl-first (emacsvox-m-player-get-position)))))
  (when  (called-interactively-p 'interactive)
    (message "Start: %s" clip-start)
    (emacsvox-icon 'mark-object)))

(defun emacsvox-m-player-set-clip-end    ()
  "Set end of clip mark."
  (interactive )
  
  (setq clip-end
        (read-number
         "End time: "
         (read (cl-first (emacsvox-m-player-get-position)))))
  (when  (called-interactively-p 'interactive)
    (message "End: %s" clip-end)
    (emacsvox-icon 'mark-object)))

(defun emacsvox-m-player-write-clip ()
  "Split selected range using SoX"
  (interactive)
  (cl-assert
   sox-sox  nil "SoX needs to be installed to use this command.")
  (cl-assert
   (eq major-mode 'emacsvox-m-player-mode) nil "Not in an MPlayer buffer.")
  (cl-assert (numberp clip-start) nil "Set start of clip with M-[")
  (cl-assert (numberp clip-end) nil "Set end of clip with M-]")
  (let ((file (cl-second (emacsvox-m-player-get-position)))
        (tmp
         (concat
          (make-temp-name
           (expand-file-name  "clip-" temporary-file-directory))
          ".wav")))
    (shell-command
     (format "%s '%s' %s  trim %s %s"
             sox-sox file tmp
             clip-start
             (- clip-end clip-start)))
    (shell-command
     (format
      "%s '%s' '%s/clip-%s-%s-%s'"
      sox-sox tmp
      emacsvox-m-player-clips
      clip-start clip-end file))
    (delete-file tmp)
    (message
     "Clip saved to '%s/clip-%s-%s-%s'."
     emacsvox-m-player-clips
     clip-start clip-end file)))

(provide 'emacsvox-m-player)
;;;  end of file

