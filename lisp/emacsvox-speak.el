;;; emacsvox-speak.el --- Core Speech Lib -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:  Contains the functions for speaking various chunks of text
;; Keywords: Emacsvox,  Spoken Output
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;;
;;  $Revision: 4552 $ |
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

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:

;; This module defines the core speech services used by emacsvox.
;; It depends on the speech server interface modules
;; It protects other parts of emacsvox
;; from becoming dependent on the speech server modules

;;; Code:

;;; Forward variable declarations:

(defvar emacsvox-last-message)
(defvar emacsvox-wpctl (executable-find "wpctl")
  "Location of wpctl.
Normally defined by `emacsvox-preamble'; this fallback also lets the
speech library load independently during native compilation.")
(defvar ido-case-fold)
(defvar repeat-in-progress)

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'voice-setup)
(require 'voice-defs)
(require 'tts-speak)
(require 'emacsvox-pronounce)
(require 'emacsvox-sounds)
(require 'sox-gen)
(require 'shr)
(declare-function operate-on-rectangle "rect" (function start end coerce-tabs))
(declare-function which-function "which-func" nil)
(declare-function calendar-cursor-to-nearest-date "cal-move" nil)

(declare-function word-at-point "thingatpt" (&optional no-properties))
(require 'text-property-search)

;;;  This line:

(defsubst ems--this-line ()
  "Return current line as string."
  (emacsvox-aural-source-substring
   (line-beginning-position) (line-end-position)))

;;; Clause Boundary Helper:

(defun emacsvox-speak-adjust-clause-boundaries ()
  "Adjust clause boundaries so that newlines dont delimit clauses."
  
  (setq tts-chunk-separator-syntax ".)$\""))
;;; Helper: Read URL

(defun ems--read-url (&optional history)
  (or
   (shr-url-at-point nil)
   (read-string "URL:" (browse-url-url-at-point) history)))

;;; Helpers: subdirs

(defconst ems--subdirs-filter
  (eval-when-compile
    (concat (regexp-opt '("/.." "/." "/.git")) "$"))
  "Pattern to filter out dirs during traversal.")

(defsubst ems--subdirs (d)
  "Return list of subdirs in directory d"
  (cl-remove-if-not #'file-directory-p (cddr (directory-files d 'full))))

(defun ems--subdirs-recursively (d)
  "Recursive list of  subdirs"
  
  (let ((result (list d))
        (subdirs (ems--subdirs d)))
    (cond
     ((string-match ems--subdirs-filter d) nil)                              
     (t
      (cl-loop
       for dir in subdirs
       if (not (string-match ems--subdirs-filter dir)) do
       (setq result  (nconc result (ems--subdirs-recursively dir))))))
    result))

;;; Helper: Wifi ESSId:

(defsubst ems--get-essid ()
  "Return active Wifi ESSId"
  (string-trim (shell-command-to-string "iwgetid --raw")))

;;; Helper: Log Message Quietly

(defun ems--log-message (m)
  "Log  message M without echoing it."
  (let ((inhibit-read-only t))
    (with-current-buffer (messages-buffer)
      (goto-char (point-max))
      (insert (format "%s\n" m)))))

;;; Helper: Speak Frame Title

(defsubst emacsvox-speak-frame-title ()
  "Speak Frame Title"
  (tts-speak (cdr (assq 'name (frame-parameters))) ))

;;;   line, Word and Character echo

(defvar-local emacsvox-line-echo nil
  "If t, then emacsvox echoes lines as you type.
You can use \\[emacsvox-toggle-line-echo] to set this
option.")

(ems-generate-switcher 'emacsvox-toggle-line-echo
                       'emacsvox-line-echo
                       "Toggle state of  Emacsvox  line echo.
Interactive PREFIX arg means toggle  the global default value, and then set the
current local  value to the result.")

(defvar-local emacsvox-word-echo t
  "If t, then emacsvox echoes words as you type.
You can use \\[emacsvox-toggle-word-echo] to toggle this
option.")

(ems-generate-switcher 'emacsvox-toggle-word-echo
                       'emacsvox-word-echo
                       "Toggle state of  Emacsvox  word echo.
Interactive PREFIX arg means toggle  the global default value, and then set the
current local  value to the result.")

(defvar-local emacsvox-character-echo t
  "If t, then emacsvox echoes characters  as you type.
You can
use \\[emacsvox-toggle-character-echo] to toggle this
setting.")

(ems-generate-switcher 'emacsvox-toggle-character-echo
                       'emacsvox-character-echo
                       "Toggle state of  Emacsvox  character echo.
Interactive PREFIX arg means toggle  the global default value, and then set the
current local  value to the result.")

;;; Echo Typing Chars:

(defun emacsvox-post-self-insert-hook ()
  "Speaks the character if emacsvox-character-echo is true.
See  command emacsvox-toggle-word-echo bound to
\\[emacsvox-toggle-word-echo].
Speech flushes as you type."
  (when buffer-read-only (tts-speak "Buffer is read-only. "))
  (when
      (and (eq (preceding-char) last-command-event) ; Sanity check.
           (not executing-kbd-macro)
           (not noninteractive))
    (let ((display (get-char-property (1- (point)) 'display)))
      (tts-stop 'all)
      (cond
       ((stringp display) (tts-speak display))
       ((and emacsvox-word-echo
             (= (char-syntax last-command-event)32))
        (save-excursion
          (condition-case
              nil
              (forward-word -1)
            (error nil))
          (emacsvox-speak-word)))
       (emacsvox-character-echo
        (emacsvox-speak-this-char (preceding-char)))))))

(add-hook 'post-self-insert-hook 'emacsvox-post-self-insert-hook)

;;;  Shell Command Helper:

(defvar-local emacsvox-speak-messages t
  "Option indicating if messages are spoken.  If nil,
emacsvox will not speak messages as they are echoed to the
message area.  You can use command
`emacsvox-toggle-speak-messages' bound to
\\[emacsvox-toggle-speak-messages].")

;; Emacsvox silences messages from shell-command when called
;; non-interactively.  This replacement is used within Emacsvox to
;; invoke commands whose output we want to hear.

(defun emacsvox-shell-command (command)
  "Run shell command COMMANDAND speak its output."
  (interactive "sCommand:")
  
  (let ((directory default-directory)
        (output (get-buffer-create "*Emacsvox Shell Command*")))
    (with-current-buffer output
      (erase-buffer)
      (setq default-directory directory)
      (ems-with-messages-silenced
       (shell-command command output))
      (emacsvox-icon 'open-object)
      (tts-speak (buffer-string)))))

;;;  Utility command to run and tabulate shell output

;;;  Notifications:

(defun emacsvox--notifications-init ()
  "Init Notifications buffer."
  (let ((buffer (get-buffer-create " *Notifications*")))
    (with-current-buffer buffer
      (special-mode)
      buffer)))

(defvar emacsvox-notifications-buffer
  (emacsvox--notifications-init)
  "Notifications buffer. Retains at most `emacsvox-notifications-max lines.")

(defun emacsvox-view-notifications ()
  "Display notifications."
  (interactive)
  
  (unless (buffer-live-p emacsvox-notifications-buffer)
    (setq emacsvox-notifications-buffer (emacsvox--notifications-init)))
  (emacsvox-icon 'open-object)
  (funcall-interactively #'pop-to-buffer emacsvox-notifications-buffer))

(defconst emacsvox-notifications-max 128
  " notifications cache-size")

(defun emacsvox-notifications-truncate ()
  "Trim notifications cache."
  (with-current-buffer emacsvox-notifications-buffer
    (let ((lines (count-lines (point-min) (point-max)))
          (inhibit-read-only t))
      (when (> lines emacsvox-notifications-max)
        (goto-char (point-min))
        (forward-line (- lines emacsvox-notifications-max))
        (delete-region (point-min) (point))))))

(defun emacsvox-log-notification (text)
  "Log a notification in our notifications buffer."
  
  (unless (buffer-live-p emacsvox-notifications-buffer)
    (setq emacsvox-notifications-buffer (emacsvox--notifications-init)))
  (with-current-buffer emacsvox-notifications-buffer
    (let ((inhibit-read-only t))
      (goto-char (point-max))
      (insert (format "%s\n" text)))))

(defvar emacsvox-notifications-gc-timer
  (run-at-time 43200 43200 #'emacsvox-notifications-truncate)
  "Idle timer that runs every 12 hours  to cleanup notifications.")

;;;  Completion helper:

(defun emacsvox-speak-completions-if-available ()
  "Speak completions if available."
  (interactive)
  (let ((completions (get-buffer "*Completions*")))
    (cond
     ((and completions
           (window-live-p (get-buffer-window completions)))
      (with-minibuffer-completions-window
        (emacsvox-icon 'help)
        (tts-chunk-on-white-space-and-punctuations)
        (next-completion 1)
        (tts-with-punctuations
         'all (emacsvox-speak-line))))
     (t (emacsvox-speak-line)))))

;;; Minibuffer Helpers:
;;;###autoload
(defun emacsvox-filter-after ()
  "Add after:today filter"
  (interactive)
  (insert (format " after:%s" (format-time-string "%Y/%m/%d")))
  (emacsvox-icon 'yank-object)
  (emacsvox-speak-line))

;;;###autoload
(defun emacsvox-filter-before ()
  "Add before:today filter"
  (interactive)
  (insert (format " before:%s" (format-time-string "%Y/%m/%d")))
  (emacsvox-icon 'yank-object)
  (emacsvox-speak-line))

;;;   Macros

;; Save read-only and modification state, perform some actions and
;; restore state

(defmacro ems-set-personality-temporarily (start end value &rest body)
  "Temporarily set personality.
Arguments start and end specify the region.
Argument VALUE is the personality to set temporarily
Argument BODY specifies forms to execute."
  (declare (indent 1) (debug t))
  `(let ((saved-personality (get-text-property ,start 'personality)))
     (with-silent-modifications
       (unwind-protect
           (progn
             (put-text-property
              (max (point-min) ,start)
              (min (point-max) ,end)
              'personality ,value)
             ,@body)
         (put-text-property
          (max (point-min) ,start)
          (min (point-max) ,end) 'personality saved-personality)))))

(defmacro ems-set-pause-temporarily (start end duration &rest body)
  "Temporarily set property pause.
Arguments start and end specify region.
Argument duration specifies duration in milliseconds.
Argument BODY specifies forms to execute."
  (declare (indent 1) (debug t))
  `(let ((saved-pause (get-text-property ,start 'pause)))
     (with-silent-modifications
       (unwind-protect
           (progn
             (put-text-property
              (max (point-min) ,start)
              (min (point-max) ,end)
              'pause ,duration)
             ,@body)
         (put-text-property
          (max (point-min) ,start)
          (min (point-max) ,end) 'pause saved-pause)))))

(defmacro ems-with-errors-silenced (&rest body)
  "Evaluate body  after temporarily silencing auditory error feedback."
  (declare (indent 1) (debug t))
  `(let ((emacsvox-speak-messages nil))
     ,@body))

;;;   Apply audio annotations

(defun emacsvox-audio-annotate-paragraphs ()
  "Set property auditory-icon at front of all paragraphs."
  (save-excursion
    (goto-char (point-max))
    (with-silent-modifications
      (let ((sound-cue 'paragraph))
        (while (not (bobp))
          (backward-paragraph)
          (put-text-property (point) (+ 2 (point))
                             'auditory-icon sound-cue))))))

(defvar emacsvox-speak-paragraph-personality voice-animate
  "Personality used to mark start of paragraph.")

(defvar-local  emacsvox-speak-voice-annotated-paragraphs nil
  "Records if paragraphs in this buffer have been voice annotated.")

(defun emacsvox-speak-voice-annotate-paragraphs ()
  "Locate paragraphs and voice annotate the first word.
Here, paragraph is taken to mean a chunk of text preceded by a blank line.
Useful to do this before you listen to an entire buffer."
  (interactive)
  (when
      (and  emacsvox-speak-paragraph-personality
            (null emacsvox-speak-voice-annotated-paragraphs)) ; memoized
    (save-excursion
      (goto-char (point-min))
      (condition-case
          nil
          (let ((start nil)
                (blank-line "\n[ \t\n\r]*\n")
                (inhibit-modification-hooks t)
                (deactivate-mark nil))
            (with-silent-modifications
              (while
                  (re-search-forward blank-line nil t)
                (skip-syntax-forward " ")
                (setq start (point))
                (unless (get-text-property start 'personality)
                  (skip-syntax-forward "^ ")
                  (put-text-property
                   start (point)
                   'personality emacsvox-speak-paragraph-personality)))))
        (error nil))
      (setq emacsvox-speak-voice-annotated-paragraphs t))))

;;;  Showing the point:

(defvar emacsvox-show-point nil
  " If T, command `emacsvox-speak-line' \\[emacsvox-speak-line]
indicates position of point by an aural highlight.
Command `emacsvox-toggle-show-point' bound to
\\[emacsvox-toggle-show-point]  toggles this setting.")

(ems-generate-switcher 'emacsvox-toggle-show-point
                       'emacsvox-show-point
                       "Toggle state of  Emacsvox-show-point.
Interactive PREFIX arg means toggle  the global default value, and then set the
current local  value to the result.")

;;;  compute percentage into the buffer:

(defsubst emacsvox-get-current-percentage-into-buffer ()
  "Return percentage of position into current buffer."
  (let* ((pos (point))
         (total (buffer-size))
         (percent (if (> total 50000)
                      ;; Avoid overflow from multiplying by 100!
                      (/ (+ (/ total 200) (1- pos)) (max (/ total 100) 1))
                    (/ (+ (/ total 2) (* 100 (1- pos))) (max total 1)))))
    percent))

(defun emacsvox-get-current-percentage-verbosely ()
  "Return percentage of position into current buffer as a string."
  (let ((percent (emacsvox-get-current-percentage-into-buffer)))
    (propertize
     (cond
      ((= 0 percent) " top ")
      ((= 100 percent) " bottom ")
      (t (format " %d%% " percent)))
     'personality voice-monotone-extra)))

(defun emacsvox-goto-percent (percent)
  "Move to end  PERCENT of buffer like in View mode.
Display is centered at point.
Also set the mark at the position where point was."
  (interactive "nPercent:")
  (push-mark)
  (goto-char
   (if percent
       (+ (point-min)
          (floor (* (- (point-max) (point-min)) 0.01
                    (max 0 (min 100 (prefix-numeric-value percent))))))
     (point-max)))
  (recenter)
  (emacsvox-icon 'large-movement)
  (emacsvox-speak-line))

;;;   indentation:

(defvar-local emacsvox-audio-indentation nil
  "Option indicating if line indentation is cued.
You can use command `emacsvox-toggle-audio-indentation' bound to
\\[emacsvox-toggle-audio-indentation] to toggle this setting.")

(make-variable-buffer-local 'emacsvox-audio-indentation)

;; Indicate indentation.
;; Argument indent   indicates number of columns to indent.

;;;  filtering columns

(defvar-local emacsvox-speak-line-column-filter nil
  "List that specifies columns to be filtered.
The list when set holds pairs of start-col.end-col pairs
that specifies the columns that should not be spoken.
Each column contains a single character --this is inspired
by cut -c on UNIX.")

(defvar emacsvox-speak-filter-table (make-hash-table)
  "Hash table holding persistent filters.")

(defvar-local emacsvox-speak-line-invert-filter nil
  "Non-nil means the sense of `filter' is inverted when filtering
columns in a line --see
command emacsvox-speak-line-set-column-filter.")

(ems-generate-switcher 'emacsvox-toggle-speak-line-invert-filter
                       'emacsvox-speak-line-invert-filter
                       "Toggle state of   how column filter is interpreted.
Interactive PREFIX arg means toggle  the global default value, and then set the
current local  value to the result.")

(defun emacsvox-speak-line-apply-column-filter (line &optional invert)
  "Apply column filter."
  
  (let ((filter emacsvox-speak-line-column-filter)
        (l (length line))
        (pair nil)
        (personality (if invert nil
                       'inaudible)))
    (with-silent-modifications
      (when invert
        (put-text-property 0 l
                           'personality 'inaudible line))
      (while filter
        (setq pair (pop filter))
        (when (and (<= (cl-first pair) l)
                   (<= (cl-second pair) l))
          (put-text-property
           (cl-first pair) (cl-second pair)
           'personality personality line))))
    line))

(defun emacsvox-speak-persist-filter-entry (k v)
  (insert
   (format
    "(puthash
(intern \"%s\")
'%s
emacsvox-speak-filter-table)\n" k v)))

(defvar emacsvox-speak-filter-persistent-store
  (expand-file-name ".filters" emacsvox-user-directory)
  "File where emacsvox filters are persisted.")

(defvar emacsvox-speak-filters-loaded-p nil
  "Records if we    have loaded filters in this session.")

(defun emacsvox-speak-lookup-persistent-filter (key)
  "Lookup a filter setting we may have persisted."
  
  (or
   (gethash
    (if (symbolp key) key (intern key))
    emacsvox-speak-filter-table)
   (list (list 0 (current-column)))))

(defun emacsvox-speak-set-persistent-filter (key value)
  "Persist filter setting for future use."
  
  (setf (gethash (intern key) emacsvox-speak-filter-table)
        value))

(defun emacsvox-speak-persist-filter-settings ()
  "Persist emacsvox filter settings for future sessions."
  (interactive)
  (emacsvox--persist-variable
   'emacsvox-speak-filter-table
   emacsvox-speak-filter-persistent-store))

(defun emacsvox-speak-load-filter-settings ()
  "Load emacsvox filter settings."
  (interactive)
  (unless emacsvox-speak-filters-loaded-p
    ;; `ems--fastload' is defined in `emacsvox-preamble' which requires
    ;; us, so we can't require it at top-level.
    (require 'emacsvox-preamble)
    (declare-function ems--fastload "emacsvox-preamble" (file))
    (ems--fastload emacsvox-speak-filter-persistent-store)
    (setq emacsvox-speak-filters-loaded-p t)
    (add-hook 'kill-emacs-hook 'emacsvox-speak-persist-filter-settings)))

(defun emacsvox-speak-line-set-column-filter (filter)
  "Set up filter for selectively speaking or ignoring portions of lines.
The filter is specified as a list of pairs.
For example, to filter  columns 1 -- 10 and 20 -- 25,
specify filter as
((0 9) (20 25)). Filter settings are persisted across sessions.  A
persisted filter is used as the default when prompting for a filter.
This allows one to accumulate a set of filters for specific files like
/var/adm/messages and /var/adm/maillog over time.
Option emacsvox-speak-line-invert-filter determines
the sense of the filter. "
  (interactive
   (list
    (progn
      (emacsvox-speak-load-filter-settings)
      (read-minibuffer
       (format
        "Specify columns to %s: "
        (if emacsvox-speak-line-invert-filter " speak" "filter out"))
       (format
        "%s"
        (emacsvox-speak-lookup-persistent-filter
         (or (buffer-file-name) (symbol-name major-mode))))))))
  (cond
   ((and (listp filter)
         (cl-every
          #'(lambda (l)
              (and (listp l)
                   (= 2 (length l))))
          filter))
    (setq emacsvox-speak-line-column-filter filter)
    (when (or (buffer-file-name) major-mode)
      (emacsvox-speak-set-persistent-filter
       (or (buffer-file-name) (symbol-name major-mode))
       filter)))
   (t
    (setq emacsvox-speak-line-column-filter nil))))

;;; Match Parens:
(defun emacsvox-speak-matching-paren ()
  "Speak matched paren with context."
  (when-let* ((there (cl-fourth (show-paren--default))))
    (save-excursion
      (goto-char there)
      (tts-speak
       (emacsvox-aural-source-substring ; left or right context
        (if (eolp) (line-beginning-position) there)
        (line-end-position))))))

;;;   Speak units of text

(defun emacsvox-speak-spaces ()
  "Speak number of spaces at point."
  (interactive)
  (let ((beg (save-excursion (skip-syntax-backward " ")))
        (end (save-excursion (skip-syntax-forward " "))))
    (tts-notify  (format "%s spaces " (+ (- end beg))))))

(defvar ems--large-text-size 40000
  "Upper limit on what we attempt to speak in one shot.")

(defun emacsvox-speak-region (start end)
  "Speak region bounded by start and end. "
  (interactive "r")
  (let ((inhibit-modification-hooks t)
        (deactivate-mark nil))
    (when (and
           (< (abs (- start end )) ems--large-text-size)
           (not emacsvox-speak-voice-annotated-paragraphs))
      (save-restriction
        (narrow-to-region start end)
        (emacsvox-speak-voice-annotate-paragraphs)))
    (if (< (abs (- start end )) ems--large-text-size)
        (tts-speak (emacsvox-aural-source-substring start end))
      (call-interactively #' emacsvox-speak-windowful))))

(defun emacsvox-speak-extent (beg end &optional no-case)
  "Speak extent delimited by beg and end.
Match patterns beg and end define the extent; optional arg
  no-case determines if the match is case sensitive.  Point is
  left at the start of beg on success."
  (interactive
   (list (read-string "Beg:") (read-string "End: :") current-prefix-arg))
  (let ((case-fold-search no-case)
        (start nil))
    (goto-char (point-min))
    (re-search-forward beg)
    (forward-line 0)
    (setq start (point))
    (save-excursion
      (goto-char (line-end-position))
      (re-search-forward end)
      (emacsvox-speak-region start (line-beginning-position)))))

(defconst emacsvox-horizontal-rule "^\\([=_-]\\)\\1+$"
  "Regular expression to match horizontal rules in ascii text.")

(defconst emacsvox-decoration-rule
  "^[ \t!@#$%^&*()<>|_=+/\\,.;:-]+$"
  "Regular expressions to match lines that are purely decorative ascii.")

(defconst emacsvox-unspeakable-rule
  "^[^[:alnum:]]+$"
  "Pattern to match lines of special chars.
This is a regular expression that matches lines containing only
non-alphanumeric characters for the current locale.
emacsvox will generate a tone
instead of speaking such lines when punctuation mode is set
to some.")

(defvar-local ems--speak-max-length 512
  "Threshold for determining `long' lines.
Emacsvox will ask for confirmation before speaking lines
that are longer than this length.  This is to avoid accidentally
opening a binary file and torturing the speech synthesizer
with a long string of gibberish.")

(defconst emacsvox-speak-blank-line-regexp
  "^[[:space:]]+$"
  "Pattern that matches white space.")

(ems-generate-switcher 'emacsvox-toggle-audio-indentation
                       'emacsvox-audio-indentation
                       "Toggle state of  Emacsvox  audio indentation.
Interactive PREFIX arg means toggle  the global default value, and then set the
current local  value to the result.
Specifying the method of indentation as `tones'
results in the Dectalk producing a tone whose length is a function of the
line's indentation.  Specifying `speak'
results in the number of initial spaces being spoken.")

(defun emacsvox-speak-line (&optional arg)
  "Speaks current line.  With prefix ARG, speaks the rest of the
line from point.  Negative prefix optional arg speaks from start
of line to point.  Indicates indentation with a spoken message if
audio indentation is on see `emacsvox-toggle-audio-indentation'
bound to \\[emacsvox-toggle-audio-indentation].  Indicates
position of point with an aural highlight if option
`emacsvox-show-point' is on --see command
`emacsvox-toggle-show-point' bound to
\\[emacsvox-toggle-show-point].  Lines that start hidden blocks
of text, e.g.  outline header lines, or header lines of blocks
created by command `emacsvox-hide-or-expose-block' are indicated
with auditory icon ellipses. Presence of additional
presentational overlays (created via property display,
before-string, or after-string) is indicated with auditory icon
`left', `right', or `more' as appropriate.  These can then be
spoken using command \\[emacsvox-speak-overlay-properties]."
  (interactive "P")
  (tts-stop 'all)
  (when (listp arg) (setq arg (car arg)))
  (let* ((inhibit-field-text-motion t)
         (inhibit-read-only t)
         (inhibit-modification-hooks t)
         (icon (get-char-property (point) 'auditory-icon))
         (before (get-char-property (point) 'before-string))
         (after (get-char-property (point) 'after-string))
         (display (get-char-property (point) 'display))
         (start (line-beginning-position))
         (end (line-end-position))
         (line nil)
         (orig (point))
         (linenum
          (when
              (or (bound-and-true-p display-line-numbers)
                  (bound-and-true-p linenum-mode))
            (line-number-at-pos)))
         (indent nil))
    ;; determine what to speak based on prefix arg
    (cond
     ((null arg))
     ((> arg 0) (setq start orig))
     (t (setq end orig)))
    (when icon (emacsvox-icon icon))
    (when emacsvox-show-point
      (emacsvox-icon
       (cond
        ((bolp) 'left)
        ((eolp) 'right)
        (t 'tick-tick))))
    (setq line
          (if emacsvox-show-point
              (ems-set-pause-temporarily
               orig (1+ orig) 5
               (ems-set-personality-temporarily
                orig (1+ orig) voice-animate
                (emacsvox-aural-source-substring start end)))
            (emacsvox-aural-source-substring start end)))
    (when (and (null arg) emacsvox-speak-line-column-filter)
      (setq
       line
       (emacsvox-speak-line-apply-column-filter
        line emacsvox-speak-line-invert-filter)))
    (when emacsvox-audio-indentation (setq indent (current-indentation)))
    (when (or (invisible-p end)
              (get-text-property start 'emacsvox-hidden-block))
      (emacsvox-icon 'ellipses))
    (when (or display before after)
      (emacsvox-icon
       (cond
        (before 'left)
        (after 'right)
        (t 'more))))
    (cond
     ;; C1..C5
     ((string-equal "" line)
      (tts-tone 130.8 150 'force))
     ((string-match emacsvox-speak-blank-line-regexp line) ;only white space
      (tts-tone 261.6 150 'force))
     ((and (not (eq 'all tts-punctuation-mode))
           (string-match emacsvox-horizontal-rule line))
      (tts-tone 523.3 150 t))
     ((and (not (eq 'all tts-punctuation-mode))
           (string-match emacsvox-decoration-rule line))
      (tts-tone 1047 150 t))
     ((and (not (eq 'all tts-punctuation-mode))
           (string-match emacsvox-unspeakable-rule line))
      (tts-tone 2093 150 t))
     (t
      (let*
          ((l (length line))
           (speakable ;; should we speak this line?
            (cond
             ((or                       ;speakable
               selective-display
               (< l ems--speak-max-length)
               (get-text-property start 'speak-line))
              t)
             (t
              (when (y-or-n-p "use Visual Lines")
                (call-interactively #'visual-line-mode))
              (unless visual-line-mode
                (put-text-property start end 'start-line t)
                (setq ems--speak-max-length (* 2 l)))
              t))))
        (when speakable
          (when
              (and (null arg) indent (> indent 0))
            (setq indent
                  (propertize
                   (format "indent %d" indent)
                   'personality voice-indent))
            (setq line (concat indent line)))
          (when linenum
            (setq linenum (format "%d" linenum))
            (setq linenum (propertize linenum 'personality voice-lighten))
            (setq line (concat linenum line)))
          (tts-speak line)))))))

(defun ems--display-props-get ()
  "Return  speakable display, before-string or after-string property if any."
  (let ((before (get-char-property (point) 'before-string))
        (after (get-char-property (point) 'after-string))
        (display (get-char-property (point) 'display))
        (result nil))
    (setq result
          (concat
           (when (stringp before) before)
           (when (stringp display) display)
           (when (stringp after) after)))
    result))

(defun emacsvox-speak-overlay-properties ()
  "Speak display, before-string or after-string property if any."
  (interactive)
  (let (
        (disp
         (if-let*
             ((disp (get-char-property (point) 'display)))
             (prin1-to-string disp)
           "No display properties here"))
        (icon
         (cond
          ((get-char-property (point) 'before-string) 'left)
          ((get-char-property (point) 'after-string) 'right)
          ((get-char-property (point) 'display) 'more)))
        (result (ems--display-props-get)))
    (cond
     ((or (null result) (= 0 (length result)))
      (message disp))
     (t
      (emacsvox-icon icon)
      (tts-speak result)))))

(defun emacsvox-speak-visual-line ()
  "Speaks current visual line.
Cues the start of a physical line with auditory icon `left'."
  (interactive)
  
  (let ((inhibit-field-text-motion t)
        (inhibit-read-only t)
        (start nil)
        (end nil)
        (inhibit-modification-hooks t)
        (line nil)
        (orig (point)))
    (cond
     ((looking-at "^ *") (emacsvox-icon 'left))
     ((looking-at " *$") (emacsvox-icon 'right)))
    (save-excursion
      (beginning-of-visual-line)
      (setq start (point))
      (end-of-visual-line)
      (setq end (point))
      (setq line
            (if emacsvox-show-point
                (ems-set-personality-temporarily
                 orig (1+ orig)
                 voice-animate
                 (emacsvox-aural-source-substring start end))
              (emacsvox-aural-source-substring start end)))
      (tts-speak line))))

(defvar-local emacsvox-speak-last-spoken-word-position nil
  "Records position of the last word spoken  .
Local to each buffer.  Used to decide if we  spell or speak the word. ")

(defun emacsvox-speak-spell-word (word)
  "Spell WORD."
  
  (let ((result "")
        (char-string ""))
    (cl-loop for char across word
             do
             (setq char-string (format "%c " char))
             (when (and (<= ?A char)
                        (<= char ?Z))
               (put-text-property 0 1
                                  'personality voice-animate
                                  char-string)
               (setq char-string (format "cap %s " char-string)))
             (setq result
                   (concat result
                           char-string)))
    (tts-speak result)))

(defun emacsvox-speak-spell-current-word ()
  "Spell word at  point."
  (interactive)
  (emacsvox-speak-spell-word (word-at-point)))

(defun emacsvox-speak-word (&optional arg)
  "Speak current word.
With prefix ARG, speaks the rest of the word from point.
Negative prefix arg speaks from start of word to point.
If executed  on the same buffer position a second time, the word is
spelled out  instead of being spoken."
  (interactive "P")
  
  (when (listp arg) (setq arg (car arg)))
  (save-excursion
    (let ((orig (point))
          (inhibit-modification-hooks t)
          (inhibit-field-text-motion  t)
          (start nil)
          (end nil)
          (speaker 'tts-speak))
      (forward-word 1)
      (setq end (point))
      (backward-word 1)
      (setq start (min orig (point)))
      (cond
       ((null arg))
       ((> arg 0) (setq start orig))
       ((< arg 0) (setq end orig)))
      ;; select speak or spell
      (cond
       ((and (called-interactively-p 'interactive)
             (eq emacsvox-speak-last-spoken-word-position orig))
        (setq speaker 'emacsvox-speak-spell-word)
        (setq emacsvox-speak-last-spoken-word-position nil))
       (t (setq emacsvox-speak-last-spoken-word-position orig)))
      (funcall speaker (emacsvox-aural-source-substring start end)))))

(defsubst emacsvox-is-alpha-p (c)
  "Check if `C' is an alphabetic char."
  (and (= ?w (char-syntax c))
       (tts-unicode-char-untouched-p c)))

;;;   phonemic table

(defvar emacsvox-char-to-phonetic-table
  '(
    ("1" . "one")
    ("2" . "two")
    ("3" . "three")
    ("4" . "four")
    ("5" . "five")
    ("6" . "six")
    ("7" . "seven")
    ("8" . "eight")
    ("9" . "nine")
    ("0" .  "zero")
    ("a" . "alpha")
    ("b" . "bravo")
    ("c" . "charlie")
    ("d" . "delta")
    ("e" . "echo")
    ("f" . "foxtrot")
    ("g" . "golf")
    ("h" . "hotel")
    ("i" . "india")
    ("j" . "juliet")
    ("k" . "kilo")
    ("l" . "lima")
    ("m" . "mike")
    ("n" . "november")
    ("o" . "oscar")
    ("p" . "poppa")
    ("q" . "quebec")
    ("r" . "romeo")
    ("s" . "sierra")
    ("t" . "tango")
    ("u" . "uniform")
    ("v" . "victor")
    ("w" . "whisky")
    ("x" . "xray")
    ("y" . "yankee")
    ("z" . "zulu")
    ("A" . "cap alpha")
    ("B" . "cap bravo")
    ("C" . "cap charlie")
    ("D" . "cap delta")
    ("E" . "cap echo")
    ("F" . "cap foxtrot")
    ("G" . "cap golf")
    ("H" . "cap hotel")
    ("I" . "cap india")
    ("J" . "cap juliet")
    ("K" . "cap kilo")
    ("L" . "cap lima")
    ("M" . "cap mike")
    ("N" . "cap november")
    ("O" . "cap oscar")
    ("P" . "cap poppa")
    ("Q" . "cap quebec")
    ("R" . "cap romeo")
    ("S" . "cap sierra")
    ("T" . "cap tango")
    ("U" . "cap uniform")
    ("V" . "cap victor")
    ("W" . "cap whisky")
    ("X" . "cap xray")
    ("Y" . "cap yankee")
    ("Z" . "cap zulu"))
  "Mapping from characters to their phonemic equivalents.")

(defun emacsvox-get-phonetic-string (char)
  "Return the phonetic string for this CHAR or its upper case equivalent.
char is assumed to be one of a--z."
  
  (let ((char-string (char-to-string char)))
    (or (cdr
         (assoc char-string emacsvox-char-to-phonetic-table))
        (tts-unicode-full-name-for-char char)
        char-string)))

;;;  Speak Chars:

(defun emacsvox-speak-this-char (char)
  "Speak this CHAR."
  (when char
    (cond
     ((emacsvox-is-alpha-p char) (tts-letter (char-to-string char)))
     ((and tts-handle-unicode (> char 128)) (emacsvox-speak-char-name char))
     (t (tts-dispatch (tts-char-to-speech char))))))

(defun emacsvox-speak-char (&optional prefix)
  "Speak character under point.
Pronounces character phonetically unless  called with a PREFIX arg."
  (interactive "P")
  (let ((char (following-char))
        (display (get-char-property (point) 'display))
        (icon (get-char-property (point) 'auditory-icon)))
    (when icon (emacsvox-icon icon))
    (when display
      (emacsvox-icon 'ellipses)
      (and (listp display) (message "%s" (car display))))
    (when char
      (cond
       ((stringp display) (tts-speak display))
       ((and (not prefix)
             (emacsvox-is-alpha-p char))
        (tts-speak (emacsvox-get-phonetic-string char)))
       (t (emacsvox-speak-this-char char))))))

(defun emacsvox-speak-preceding-char ()
  "Speak character before point."
  (interactive)
  (let ((char (preceding-char))
        (display (get-char-property (max (point-min) (1- (point))) 'display)))
    (when char
      (cond
       ((stringp display) (tts-speak display))
       ((> char 128) (emacsvox-speak-char-name char))
       (t (emacsvox-speak-this-char char))))))

(defun emacsvox-speak-char-name (char)
  "tell me what this is"
  (interactive)
  (tts-speak (tts-unicode-name-for-char char)))

(defun emacsvox-speak-sentence (&optional arg)
  "Speak current sentence.
With prefix ARG, speaks the rest of the sentence  from point.
Negative prefix arg speaks from start of sentence to point."
  (interactive "P")
  (when (listp arg) (setq arg (car arg)))
  (save-excursion
    (let ((orig (point))
          (inhibit-modification-hooks t)
          (start nil)
          (end nil))
      (forward-sentence 1)
      (setq end (point))
      (backward-sentence 1)
      (setq start (point))
      (cond
       ((null arg))
       ((> arg 0) (setq start orig))
       ((< arg 0) (setq end orig)))
      (tts-speak (emacsvox-aural-source-substring start end)))))

(defun emacsvox-speak-sexp (&optional arg)
  "Speak current sexp.
With prefix ARG, speaks the rest of the sexp  from point.
Negative prefix arg speaks from start of sexp to point. "
  (interactive "P")
  (when (listp arg) (setq arg (car arg)))
  (save-excursion
    (let ((orig (point))
          (inhibit-modification-hooks t)
          (start nil)
          (end nil))
      (condition-case nil
          (forward-sexp 1)
        (error nil))
      (setq end (point))
      (condition-case nil
          (backward-sexp 1)
        (error nil))
      (setq start (point))
      (cond
       ((null arg))
       ((> arg 0) (setq start orig))
       ((< arg 0) (setq end orig)))
      (emacsvox-icon 'select-object)
      (tts-speak (emacsvox-aural-source-substring start end)))))

(defun emacsvox-speak-page (&optional arg)
  "Speak a page.
With prefix ARG, speaks rest of current page.
Negative prefix arg will read from start of current page to point. "
  (interactive "P")
  (when (listp arg) (setq arg (car arg)))
  (save-excursion
    (let ((orig (point))
          (start nil)
          (end nil))
      (mark-page)
      (setq start (point))
      (setq end (mark))
      (cond
       ((null arg))
       ((> arg 0) (setq start orig))
       ((< arg 0) (setq end orig)))
      (tts-speak (emacsvox-aural-source-substring start end)))))

(defun emacsvox-speak-paragraph (&optional arg)
  "Speak paragraph.
With prefix arg, speaks rest of current paragraph.
Negative prefix arg will read from start of current paragraph to point. "
  (interactive "P")
  (when (listp arg) (setq arg (car arg)))
  (save-excursion
    (let ((orig (point))
          (start nil)
          (end nil))
      (forward-paragraph 1)
      (setq end (point))
      (backward-paragraph 1)
      (setq start (point))
      (cond
       ((null arg))
       ((> arg 0) (setq start orig))
       ((< arg 0) (setq end orig)))
      (tts-speak (emacsvox-aural-source-substring start end)))))

;;;   Speak buffer objects such as help, completions minibuffer etc

(defun emacsvox-speak-buffer (&optional arg)
  "Speak current buffer  contents.
With prefix ARG, speaks the rest of the buffer from point.
Negative prefix arg speaks from start of buffer to point. "
  (interactive "P")
  (when
      (and
       (< (buffer-size) ems--large-text-size)
       (not emacsvox-speak-voice-annotated-paragraphs))
    (emacsvox-speak-voice-annotate-paragraphs))
  (when (listp arg) (setq arg (car arg)))
  (tts-stop 'all)
  (let ((start nil)
        (end nil))
    (cond
     ((null arg)
      (setq start (point-min)
            end (point-max)))
     ((> arg 0)
      (setq start (point)
            end (point-max)))
     (t (setq start (point-min)
              end (point))))
    (if (< (abs (- start end )) ems--large-text-size)
        (tts-speak (emacsvox-aural-source-substring start end))
      (emacsvox-speak-windowful))))

(defun emacsvox-speak-other-buffer (buffer)
  "Speak specified buffer.
Useful to listen to a buffer without switching  contexts."
  (interactive
   (list
    (read-buffer "Speak buffer: "
                 nil t)))
  (save-current-buffer
    (set-buffer buffer)
    (emacsvox-speak-buffer)))

(defsubst emacsvox-speak-rest-of-buffer ()
  "Speak remainder of the buffer starting at point"
  (interactive)
  (emacsvox-icon 'select-object)
  (emacsvox-speak-buffer 1))

(defun emacsvox-speak-help ()
  "Speak help buffer if one present. "
  (interactive )
  (emacsvox-icon 'help)
  (if-let* ((help-buffer (get-buffer "*Help*")))
      (with-current-buffer help-buffer
        (or (window-live-p (get-buffer-window help-buffer))
            (display-buffer help-buffer))
        (select-window (get-buffer-window help-buffer))
        (call-interactively #'emacsvox-speak-windowful))
    (tts-speak "First ask for help")))

(defun emacsvox-get-current-completion ()
  "Return the completion under point in the *Completions* buffer."
  (with-minibuffer-completions-window
    (let (beg end)
      (if (and (not (eobp)) (get-text-property (point) 'completion--string))
          (setq end (point) beg (1+ (point))))
      (if (and (not (bobp))
               (get-text-property (1- (point)) 'completion--string))
          (setq end (1- (point)) beg (point)))
      (if (and  (bobp)
                (next-completion 1))
          (setq end (1- (point)) beg (point)))
      (if (null beg) (error "No current  completion "))
      (setq beg (or
                 (previous-single-property-change beg 'completion--string)
                 (point-min)))
      (setq end
            (or (next-single-property-change end 'completion--string)
                (point-max)))
      (emacsvox-aural-source-substring beg end))))

;;;  mail check

(defcustom emacsvox-mail-spool-file
  (expand-file-name
   (user-login-name)
   (if (boundp 'rmail-spool-directory)
       rmail-spool-directory
     "/usr/spool/mail/"))
  "Mail spool file examined  to alert you about newly
arrived mail."
  :type '(choice
          (const :tag "None" nil)
          (file :tag "Mail drop location"))
  :group 'emacsvox)

(defsubst emacsvox-get-file-size (filename)
  "Return file size for file FILENAME."
  (or (nth 7 (file-attributes filename)) 0))

(defvar emacsvox-mail-last-alerted-time (list 0 0)
  "Least  significant 16 digits of the time when mail alert was last issued. ")

(defun emacsvox-mail-get-last-mail-arrival-time (f)
  "Return time when mail  last arrived."
  (if (file-exists-p f)
      (nth 5 (file-attributes f))
    0))

(defcustom emacsvox-mail-alert-interval 300
  "Interval in seconds between mail alerts for the same pending
  message."
  :type 'integer
  :group 'emacsvox)

(defun emacsvox-mail-alert-user-p (f)
  "Predicate to check if we need to play an alert for the specified spool."
  (let* ((mod-time (emacsvox-mail-get-last-mail-arrival-time f))
         (size (emacsvox-get-file-size f))
         (result
          (and (> size 0)
               (or
                (null emacsvox-mail-last-alerted-time)
                (time-less-p emacsvox-mail-last-alerted-time mod-time)
                (time-less-p            ;unattended mail
                 (time-add emacsvox-mail-last-alerted-time
                           (list 0 emacsvox-mail-alert-interval))
                 (current-time))))))
    (when result
      (setq emacsvox-mail-last-alerted-time (current-time)))
    result))

(defun emacsvox-mail-alert-user ()
  "Alerts user about the arrival of new mail."
  
  (when (and emacsvox-mail-spool-file
             (emacsvox-mail-alert-user-p emacsvox-mail-spool-file))
    (emacsvox-icon 'new-mail)))

(defvar-local emacsvox-mail-alert t
  " If t, emacsvox will alert you about newly arrived mail
with an auditory icon when
displaying the mode line.
You can use command
`emacsvox-toggle-mail-alert' bound to
\\[emacsvox-toggle-mail-alert] to set this option. ")

(ems-generate-switcher 'emacsvox-toggle-mail-alert
                       'emacsvox-mail-alert
                       "Toggle state of  Emacsvox  mail alert.
Interactive PREFIX arg means toggle  the global default value, and then set the
current local  value to the result.
Turning on this option results in Emacsvox producing an auditory icon
indicating the arrival  of new mail when displaying the mode line.")

;;;  Mode line info collectors

(defsubst emacsvox-get-voicefied-recursion-info (level)
  "Return voicefied version of this recursive-depth level."
  (cond
   ((zerop level) nil)
   (t
    (propertize
     (format " Recursive Edit %d " level) 'personality voice-smoothen))))

(defsubst emacsvox-get-voicefied-frame-info (frame)
  "Return voicefied version of this frame name."
  (cond
   ((= (length (frame-list)) 1) nil)
   (t
    (propertize
     (format " %s " (frame-parameter frame 'name))
     'personality voice-lighten-extra ))))

;;;   Speak mode line information

;; compute current line number
(defsubst emacsvox-get-current-line-number ()
  (let ((start (point)))
    (save-excursion
      (save-restriction
        (widen)
        (goto-char (point-min))
        (+ 1 (count-lines start (point)))))))

(defun emacsvox-speak-which-function ()
  "Speak which function we are on.  Uses which-function from
which-func without turning that mode on.  "
  (interactive)
  (require 'which-func)
  (message (or (which-function) "Not inside a function.")))

(defun emacsvox-speak-buffer-info ()
  "Speak buffer information."
  (message "Buffer has %s lines and %s characters %s "
           (count-lines (point-min) (point-max))
           (- (point-max) (point-min))
           (if (= 1 (point-min))
               ""
             "with narrowing in effect. ")))
(voice-setup-set-voice-for-face 'header-line 'voice-bolden)

(defun emacsvox--sox-multiwindow ()
  "Use `window-edges' and plays a sound cuew."
  (let ((corners (window-edges))
        (tr 0)
        (mr (/ (frame-height) 2))
        (br (1- (frame-height)))
        (lc 0)
        (mc (/ (frame-width) 2))
        (rc (frame-width)))
    (cond
     ((equal corners `(,lc ,tr ,mc ,br))
      (sox-multiwindow 1 2 "pluck")
      'left-half)
     ((equal corners `(,mc ,tr ,rc ,br))
      (sox-multiwindow 1 2  "pluck")
      'right-half)
     ((equal corners `(,lc ,tr ,rc ,mr))
      (sox-multiwindow nil 2)
      'top-half)
     ((equal corners `(,lc ,mr ,rc ,br))
      (sox-multiwindow nil 1.3)
      'bottom-half)
     ((equal corners `(,lc ,tr ,mc ,mr))
      (sox-multiwindow nil 2.5)
      'top-left)
     ((equal corners `(,mc ,tr ,rc ,mr))
      (sox-multiwindow t 2.5)
      'top-right)
     ((equal corners `(,lc ,mr ,mc ,br))
      (sox-multiwindow nil 0.9)
      'bottom-left)
     ((equal corners `(,mc ,mr ,rc ,br))
      (sox-multiwindow 'swap 0.9)
      'bottom-right)
     ((and (zerop (cl-first corners))
           (zerop (cl-second corners))
           (= rc (cl-third corners)))
      (sox-multiwindow nil 2)
      'top-half)
     ((and (zerop (cl-first corners))
           (= rc (cl-third corners))
           (= br (cl-fourth corners)))
      (sox-multiwindow nil 1.3)
      'bottom-half)
     ((and (zerop (cl-first corners))
           (zerop (cl-second corners))
           (= br (cl-fourth corners)))
      (sox-multiwindow)
      'left-half)
     ((and (zerop (cl-second corners))
           (= rc (cl-third corners))
           (= br (cl-fourth corners)))
      (sox-multiwindow 'swap)
      'right-half)
     (t ""))))

(defsubst ems--comint-autospeak nil
  "Predicate to test if comint autospeak applies."
  (and emacsvox-comint-autospeak
       (or (derived-mode-p 'comint-mode) (eq 'vterm-mode major-mode))))

(defun emacsvox-speak-mode-line (&optional buffer-info)
  "Speak the mode-line.
Speaks header-line if that is set when called non-interactively.
Interactive prefix arg speaks buffer info."
  (interactive "P")
  (with-current-buffer (window-buffer (selected-window))
    (tts-stop)
    (force-mode-line-update)
    (when
        (or
         (bound-and-true-p outline-minor-mode) (bound-and-true-p folding-mode))
      (emacsvox-icon 'ellipses))
    (when (and visual-line-mode (not global-visual-line-mode)) (sox-chime 2 2))
    (when emacsvox-mail-alert (emacsvox-mail-alert-user))
    (when (and mode-line-process
               (> (length (format-mode-line mode-line-process)) 0))
      (emacsvox-icon 'process-active))
    (cond
     ((and header-line-format (not (called-interactively-p 'interactive)))
      (emacsvox-speak-header-line))
     (buffer-info (emacsvox-speak-buffer-info))
     (t                                 ; main branch
      (let ((global-info (downcase (format-mode-line global-mode-string)))
            (window-count (length (window-list)))
            (autospeak
             (when (ems--comint-autospeak)
               (propertize "Autospeak" 'personality voice-lighten)))
            (vc-state
             (when (and vc-mode (buffer-file-name))
               (vc-state (buffer-file-name))))
            (frame-info (emacsvox-get-voicefied-frame-info (selected-frame)))
            (recursion-info
             (emacsvox-get-voicefied-recursion-info (recursion-depth)))
            (dir-info
             (when (or (eq major-mode 'shell-mode)
                       (eq major-mode 'comint-mode))
               (abbreviate-file-name default-directory))))
        (when (> window-count 1) (emacsvox--sox-multiwindow))
        (setq window-count ;;; int->string
              (if (> window-count 1) (format " %s " window-count) nil))
        (cond
         ((stringp mode-line-format) (tts-speak (downcase mode-line-format)))
         (t                             ;process modeline
          (unless (zerop (length global-info))
            (put-text-property
             0 (length global-info) 'personality voice-bolden-medium
             global-info))
;;; avoid pathological case
          (unless (and buffer-read-only (buffer-modified-p))
            (when (and buffer-file-name (buffer-modified-p))
              (emacsvox-icon 'modified-object))
            (when buffer-read-only
              (emacsvox-icon 'unmodified-object)))
          (tts-with-punctuations
           'all
           (tts-speak
            (concat
             autospeak
             dir-info
             (propertize (buffer-name) 'personality
                         voice-lighten-medium)
             (emacsvox-get-current-percentage-verbosely)
             (when window-count
               (propertize window-count 'personality voice-smoothen))
             (when vc-mode
               (propertize (downcase vc-mode) 'personality voice-smoothen))
             (when vc-state (format " %s " vc-state))
             (when line-number-mode
               (format "line %d" (emacsvox-get-current-line-number)))
             (when column-number-mode
               (format "column %d" (current-column)))
             (propertize
              (downcase
               (format-mode-line mode-name)) 'personality voice-animate)
             global-info frame-info recursion-info))))))))))

(defun emacsvox-return-mode-line ()
  "Debug tool: return visually displayed mode-line as a string."
  (with-temp-buffer
    (insert (format-mode-line mode-line-format))
    (buffer-substring-no-properties (point-min) (point-max))))

(defun emacsvox-return-minor-mode-line ()
  "Debug tool: return visually displayed minor-mode-line as a string."
  (with-temp-buffer
    (insert (format-mode-line minor-mode-alist))
    (buffer-substring-no-properties (point-min) (point-max))))

(defun emacsvox-speak-current-buffer-name ()
  "Speak name of current buffer."
  (tts-with-punctuations 'all
                         (tts-speak
                          (buffer-name))))

(defconst ems--vol-cmd
  (when emacsvox-wpctl "wpctl get-volume @DEFAULT_AUDIO_SINK@")
  "Shell pipeline for getting volume.")

(defsubst ems--show-current-volume ()
  "volume display in minor-mode-line"
  
  (propertize
   (format " %s " (string-trim (shell-command-to-string ems--vol-cmd)))
   'personality 'voice-bolden))

(defvar emacsvox-speak-show-volume nil
  "Temporarily turned on when speaking minor-mode line.")

(defun emacsvox-speak-minor-mode-line (&optional log-msg)
  "Speak the minor mode-information.
Optional interactive prefix arg `log-msg' logs spoken info to
*Messages*."
  (interactive "P")
  
  (let* ((emacsvox-speak-show-volume ems--vol-cmd)
         (info (format-mode-line minor-mode-alist)))
    (when log-msg (ems--log-message info))
    (tts-with-punctuations 'some
                           (tts-speak  info))))

(defun emacsvox-speak-buffer-filename (&optional filename)
  "Speak name of file being visited in current buffer.
Speak default directory if invoked in a dired buffer, or when the
buffer is not visiting any file.  Interactive prefix arg
`filename' speaks only the final path component.  The result is
put in the kill ring for convenience."
  (interactive "P")
  (let ((tts-caps t)
        (location (or (buffer-file-name) default-directory)))
    (when filename
      (setq location (file-name-nondirectory location)))
    (kill-new location)
    (tts-speak location)))

;;;  Speak header-line

(defvar emacsvox-use-header-line t
  "Use default header line defined  by Emacsvox for buffers that
dont customize the header.")

(defvar emacsvox-header-line-format
  '((:eval (buffer-name)))
  "Default header-line-format defined by Emacsvox.
Displays name of current buffer.")

(defun emacsvox-speak-header-line ()
  "Speak header line if set."
  (interactive)
  (cond
   (header-line-format
    (let ((window-count (length (window-list))))
      (emacsvox-icon 'item)
      (when (> window-count 1) (emacsvox--sox-multiwindow))
      (tts-notify (format-mode-line header-line-format))))
   (t
    (tts-notify
     (concat
      (propertize (buffer-name) 'personality voice-smoothen)
      (format-time-string emacsvox-speak-time-brief-format))))))

(defun emacsvox-toggle-header-line ()
  "Toggle Emacsvox's default header line."
  (interactive)
  (if header-line-format
      (setq header-line-format nil)
    (setq header-line-format emacsvox-header-line-format))
  (emacsvox-icon (if header-line-format 'on 'off))
  (message "Turned %s default header line."
           (if header-line-format 'on 'off)))

;;;   Speak text without moving point

;; Functions to browse without moving:
(defun emacsvox-read-line-internal (arg)
  "Read a line without moving.
Line to read is specified relative to the current line, prefix args gives the
offset. Default  is to speak the previous line. "
  (save-excursion
    (cond
     ((zerop arg) (emacsvox-speak-line))
     ((zerop (forward-line arg))
      (emacsvox-speak-line))
     (t (tts-speak "Not that many lines in buffer ")))))

(defun emacsvox-read-previous-line (&optional arg)
  "Read previous line, specified by an offset, without moving.
Default is to read the previous line. "
  (interactive "p")
  (emacsvox-read-line-internal (- (or arg 1))))

(defun emacsvox-read-next-line (&optional arg)
  "Read next line, specified by an offset, without moving.
Default is to read the next line. "
  (interactive "p")
  (emacsvox-read-line-internal (or arg 1)))

(defun emacsvox-read-word-internal (arg)
  "Read a word without moving.
word  to read is specified relative to the current word, prefix args gives the
offset. Default  is to speak the previous word. "
  (save-excursion
    (cond
     ((= arg 0) (emacsvox-speak-word))
     ((forward-word arg)
      (skip-syntax-forward " ")
      (emacsvox-speak-word 1))
     (t (tts-speak "Not that many words ")))))

;;;   Speak misc information e.g. time, version, current-kill  etc

(defcustom emacsvox-speak-time-format
  "%l %M%p on %A %B %_e"
  "Format string that specifies how the time should be spoken.
See the documentation for function
`format-time-string'"
  :group 'emacsvox
  :type 'string)

(defcustom emacsvox-speak-time-brief-format
  "%l %M"
  "Format for time in brief."
  :group 'emacsvox
  :type 'string)

(defvar emacsvox-speak-zoneinfo-directory
  "/usr/share/zoneinfo/"
  "Directory containing timezone data.")

(defun emacsvox-speak-world-clock (zone &optional set)
  "Display current date and time  for specified zone.
Optional second arg `set' sets the TZ environment variable as well."
  (interactive
   (list
    (let ((completion-ignore-case t)
          (ido-case-fold t)
          (read-file-name-completion-ignore-case t))
      (read-file-name "Timezone: " emacsvox-speak-zoneinfo-directory))
    current-prefix-arg))
  (when (and set
             (= 16 (car set)))
    ;; two interactive prefixes from caller
    (setenv "TZ" zone))
  (emacsvox-shell-command
   (format "export TZ=%s; date +\"%s\""
           zone
           (concat emacsvox-speak-time-format
                   (format
                    " in %s, %%Z, %%z "
                    (substring
                     zone
                     (length emacsvox-speak-zoneinfo-directory)))))))

(defun emacsvox-speak-brief-time ()
  "Time in brief"
  (interactive)
  
  (emacsvox-icon 'tick-tick)
  (emacsvox-pip (format-time-string emacsvox-speak-time-brief-format)))

(defun emacsvox-speak-time (&optional world)
  "Speak the time.
Spoken time  is available via \\[emacsvox-view-notifications].
Optional interactive prefix arg `C-u'invokes world clock.
Timezone is specified using minibuffer completion.
Second interactive prefix sets clock to new timezone."
  (interactive "P")
  
  (emacsvox-icon 'time)
  (cond
   (world (call-interactively 'emacsvox-speak-world-clock))
   (t
    (let ((time-string
           (format-time-string emacsvox-speak-time-format
                               (current-time) (getenv "TZ"))))
      (tts-notify time-string)))))

(defsubst ems--seconds-to-duration (sec)
  "Return seconds formatted as time if valid, otherwise return as is."
  (let ((v (car  (read-from-string sec))))
    (cond
     ((and (numberp v) (not (cl-minusp v)))
      (format-seconds "%.2h:%.2m:%.2s%z" v))
     (t sec))))

(defsubst ems--duration-to-seconds (d)
  "Convert hh:mm:ss to seconds."
  (let*
      ((sign (string-match "^-" d))
       (v
        (mapcar
         #'car
         (mapcar
          #'read-from-string
          (split-string (if sign (substring d 1) d) ":")))))
    (* (if sign -1 1)
       (+
        (* 3600 (or  (cl-first v) 0))
        (* 60 (or  (cl-second v) 0))
        (or  (cl-third v) 0)))))

(defsubst ems--format-clock (s)
  "Seconds -> mm:ss"
  (format "%02d:%02d" (floor (/ s 60)) (% (floor s) 60)))

(defun emacsvox-speak-seconds-since-epoch (seconds)
  "Speaks time value specified as seconds  since epoch."
  (interactive
   (list (read-minibuffer "Seconds: " (word-at-point))))
  
  (message
   (format-time-string
    emacsvox-speak-time-format (seconds-to-time seconds))))

(defun emacsvox-speak-microseconds-since-epoch (ms)
  "Speaks time value specified as microseconds  since epoch."
  (interactive
   (list (read-minibuffer "MicroSeconds: " (word-at-point))))
  (let ((seconds (/ ms 1000000)))
    (emacsvox-speak-seconds-since-epoch seconds)))

(defun emacsvox-speak-milliseconds-since-epoch (ms)
  "Speaks time value specified as milliseconds  since epoch.."
  (interactive
   (list (read-minibuffer "MilliSeconds: " (word-at-point))))
  (let ((seconds (/ ms 1000)))
    (emacsvox-speak-seconds-since-epoch seconds)))

(defun emacsvox-speak-date-as-seconds (time)
  "Read time value as a human-readable string, return seconds.
Seconds value is also placed in the kill-ring."
  (interactive "sTime: ")
  (let ((result (float-time (apply 'encode-time (parse-time-string time)))))
    (message "%s" result)
    (kill-new result)
    result))

;;;  Codenames etc.
(defvar emacsvox-codename
  (propertize "DreamDog" 'face 'bold)
  "Code name of present release.")
(defvar emacsvox-version
  (concat "60.0,   " emacsvox-codename " " emacsvox-git-revision)
  "Version number for Emacsvox.")

(defun emacsvox-speak-version ()
  "Announce version information for running emacsvox. "
  (interactive)
  (emacsvox-icon 'emacsvox)
  (message
   (format "Emacsvox %s " emacsvox-version )))

(defun emacsvox-speak-current-kill (&optional count)
  "Speak the current kill.
This is what will be yanked by the next \\[yank]. Prefix numeric
arg, COUNT, specifies that the text that will be yanked as a
result of a \\[yank] followed by count-1 \\[yank-pop] be
spoken. The kill number that is spoken says what numeric prefix
arg to give to command yank."
  (interactive "p")
  (let ((context
         (format "kill %s "
                 (if current-prefix-arg (+ 1 count) 1))))
    (put-text-property 0 (length context) 'personality voice-annotate context)
    (tts-speak
     (concat context (current-kill (if current-prefix-arg count 0) t)))))

(defun emacsvox-zap-tts ()
  "Send this command to the TTS directly."
  (interactive)
  (tts-dispatch
   (read-from-minibuffer "Enter TTS command string: ")))

(defun emacsvox-speak-string-to-phone-number (string)
  "Convert alphanumeric phone number to true phone number.
Argument STRING specifies the alphanumeric phone number."
  (setq string (downcase string))
  (let ((i 0))
    (cl-loop for character across string
             do
             (aset string i
                   (cl-case character
                     (?a ?2)
                     (?b ?2)
                     (?c ?2)
                     (?d ?3)
                     (?e ?3)
                     (?f ?3)
                     (?g ?4)
                     (?h ?4)
                     (?i ?4)
                     (?j ?5)
                     (?k ?5)
                     (?l ?5)
                     (?m ?6)
                     (?n ?6)
                     (?o ?6)
                     (?p ?7)
                     (?r ?7)
                     (?s ?7)
                     (?t ?8)
                     (?u ?8)
                     (?v ?8)
                     (?w ?9)
                     (?x ?9)
                     (?y ?9)
                     (?q ?1)
                     (?z ?1)
                     (otherwise character)))
             (cl-incf i))
    string))

;;;  speaking marks

;; Intelligent mark feedback for emacsvox:
;;

(defun emacsvox-speak-current-mark (count)
  "Speak the line containing the mark.
With no argument, speaks the line containing the mark--this is
where \\[exchange-point-and-mark] would
jump.  Numeric prefix arg  `COUNT' speaks line containing mark  `n'
where  `n' is one less than the number of times one has to jump
using `set-mark-command' to get to this marked position.  The
location of the mark is indicated by an aural highlight. "
  (interactive "p")
  (unless (mark) (error "No marks set in this buffer"))
  (when (and current-prefix-arg (> count (length mark-ring)))
    (error "Not that many marks in this buffer"))
  (let ((line nil)
        (pos nil)
        (context
         (format "mark %s " (if current-prefix-arg count 0))))
    (put-text-property 0 (length context)
                       'personality voice-annotate context)
    (setq pos
          (if current-prefix-arg
              (elt mark-ring (1- count))
            (mark)))
    (save-excursion
      (goto-char pos)
      (ems-set-personality-temporarily
       pos (1+ pos) voice-animate
       (setq line (ems--this-line)))
      (tts-speak
       (concat context line)))))

;;;  speaking personality chunks

;; Block navigation

;;; Face Ranges:

(defun emacsvox-speak-face-browse ()
  "Use C-f and C-b or left/right arrows to browse by current face."
  (interactive )
  (call-interactively #'emacsvox-speak-range)
  (while t
    (let ((key (read-key "" t)))
      (cond
       ((memq key '(right 6))
        (funcall-interactively #'emacsvox-speak-face-forward))
       ((memq key '(left 2))
        (funcall-interactively #'emacsvox-speak-face-backward))
       (t (keyboard-quit))))))

(defun emacsvox-speak-range (&optional prop)
  "Speak and return  range at point"
  (interactive )
  (setq prop (or prop 'face))
  (let*
      ((start (previous-single-property-change (1+ (point)) prop))
       (pre-start (previous-single-property-change (point) prop))
       (end (next-single-property-change (point) prop))
       (beg (or start pre-start)))
    (when (and  beg end)
      (emacsvox-speak-region beg end)
      (emacsvox-aural-source-substring beg end))))

(defun emacsvox-speak-face-forward ()
  "Property search for face --- see \\[text-property-search-forward]"
  (interactive)
  (when-let*
      ((match
        (funcall-interactively
         #'text-property-search-forward
         'face (get-text-property (point) 'face)
         t t)))
    (goto-char (prop-match-beginning match))))

(defun emacsvox-speak-face-backward ()
  "Property search for face at point see \\[text-property-search-backward]"
  (interactive)
  (when-let*
      ((match
        (funcall-interactively
         #'text-property-search-backward
         'face (get-text-property (point) 'face) t t)))
    (goto-char (prop-match-beginning match))))

;;;   Execute command repeatedly:

(defun emacsvox-execute-repeatedly (command)
  "Execute COMMAND repeatedly."
  (emacsvox-icon 'repeat-start)
  (let ((key "")
        (pos (point))
        (continue t)
        (message "Space Repeats."))
    (while continue
      (emacsvox-icon 'repeat-active)
      (call-interactively command)
      (cond
       ((= (point) pos) (setq continue nil))
       (t (setq pos (point))
          (setq key (read-key message))
          (when (not (= 32 key))
            (tts-stop 'all)
            (setq continue nil))))
      (emacsvox-icon 'repeat-end)
      (tts-speak "Exited continuous mode "))))

(defun emacsvox-speak-continuously ()
  "Speak a buffer continuously.
First prompts using the minibuffer for the kind of action to
perform after speaking each chunk,   E.G.  speak a line at a time
etc.  Speaking commences at current buffer position.  Pressing
\\[keyboard-quit] breaks out, leaving point on last chunk that
was spoken.  Pressing SPC  continues to speak the buffer; any other
  key quits."
  (interactive)
  (let ((command
         (key-binding (read-key-sequence "Press navigation key to repeat: "))))
    (unless command (error "You specified an invalid key sequence.  "))
    (emacsvox-execute-repeatedly command)))

;;;   skimming

(defun emacsvox-speak-skim-buffer ()
  "Skim the current buffer  a paragraph at a time."
  (interactive)
  (emacsvox-execute-repeatedly 'forward-paragraph))

;;;    quieten messages

(ems-generate-switcher 'emacsvox-toggle-speak-messages
                       'emacsvox-speak-messages
                       "Toggle  state of whether emacsvox echoes messages.")

;;;   Moving across fields:

;; Fields are defined by property 'field

;; helper function: speak a field

(defun emacsvox-speak-field ()
  "Speak current field."
  (interactive)
  (tts-speak (field-string (point))))

(defun emacsvox-speak-next-field ()
  "Move to and speak next field."
  (interactive)
  
  (let ((inhibit-field-text-motion t))
    (when
        (goto-char (next-single-property-change (point) 'field))
      (emacsvox-speak-field))))

(defun emacsvox-speak-previous-field ()
  "Move to previous field and speak it."
  (interactive)
  
  (let ((inhibit-field-text-motion t))
    (when
        (goto-char (previous-single-property-change (point) 'field))
      (emacsvox-speak-field))))

(defun emacsvox-speak-current-column ()
  "Speak the current column."
  (interactive)
  (message "Column %d" (current-column)))

(defun emacsvox-speak-current-percentage ()
  "Announce the percentage into the current buffer."
  (interactive)
  (message "Point is  %d%% into  the current buffer"
           (emacsvox-get-current-percentage-into-buffer)))

;;;   Speak the last message again:

(defvar ems--message-filter nil
  "Internal variable holding  pattern used to filter spoken messages.")

(defun emacsvox-speak-message-again (&optional from-message-cache)
  "Speak the last message from Emacs once again.
The message is also placed in the kill ring for convenient yanking "
  (interactive "P")
  
  (when  (and emacsvox-last-message (called-interactively-p 'interactive))
    (kill-new emacsvox-last-message))
  (cond
   (from-message-cache (tts-speak emacsvox-last-message))
   (t
    (save-current-buffer
      (set-buffer "*Messages*")
      (goto-char (point-max))
      (skip-syntax-backward " >")
      (emacsvox-speak-line)
      (when  (called-interactively-p 'interactive)
        (kill-new (ems--this-line)))))))

;;;   Using emacs's windows usefully:

;;Return current window contents
(defsubst emacsvox-get-window-contents ()
  "Return window contents."
  (save-excursion
    (emacsvox-aural-source-substring
     (window-start (selected-window))
     (window-end (selected-window)  'update ))))

(defun emacsvox-speak-windowful ()
  "Delete other windows, Line to top, then Speak window contents."
  (interactive)
  (delete-other-windows)
  (recenter 0)
  (emacsvox-icon 'scroll)
  (tts-speak (emacsvox-get-window-contents)))

(defun emacsvox-speak-window-information ()
  "Speaks information about current window."
  (interactive)
  (message "Current window has %s lines and %s columns with
top left %s %s "
           (window-height)
           (window-width)
           (cl-first (window-edges))
           (cl-second (window-edges))))

(defun emacsvox-speak-current-window ()
  "Speak contents of current window.
Speaks entire window irrespective of point."
  (interactive)
  (emacsvox-speak-region
   (window-start (selected-window))
   (window-end (selected-window) 'update)))

(defun emacsvox-owindow-scroll-up ()
  "Scroll up the window that command `other-window' would move to.
Speak the window contents after scrolling."
  (interactive)
  (save-window-excursion
    (other-window 1)
    (call-interactively 'scroll-up)))

(defun emacsvox-owindow-scroll-down ()
  "Scroll down  the window that command `other-window' would move to.
Speak the window contents after scrolling."
  (interactive)
  (save-window-excursion
    (other-window 1)
    (call-interactively 'scroll-down)))

(defun emacsvox-owindow-next-line (count)
  "Move to the next line in the other window and speak it.
Numeric prefix arg COUNT can specify number of lines to move."
  (interactive "p")
  (setq count (or count 1))
  (let ((residue nil))
    (save-current-buffer
      (set-buffer (window-buffer (next-window)))
      (end-of-line)
      (setq residue (forward-line count))
      (cond
       ((> residue 0) (message "At bottom of other window "))
       (t (set-window-point (get-buffer-window (current-buffer))
                            (point))
          (emacsvox-speak-line))))))

(defun emacsvox-owindow-previous-line (count)
  "Move to the next line in the other window and speak it.
Numeric prefix arg COUNT specifies number of lines to move."
  (interactive "p")
  (setq count (or count 1))
  (let ((residue nil))
    (save-current-buffer
      (set-buffer (window-buffer (next-window)))
      (end-of-line)
      (setq residue (forward-line (- count)))
      (cond
       ((> 0 residue) (message "At top of other window "))
       (t (set-window-point (get-buffer-window (current-buffer))
                            (point))
          (emacsvox-speak-line))))))

(defun emacsvox-owindow-speak-line ()
  "Speak the current line in the other window."
  (interactive)
  (save-current-buffer
    (set-buffer (window-buffer (next-window)))
    (goto-char (window-point))
    (emacsvox-speak-line)))

(defun emacsvox-speak-this-window ()
  "Speak current window."
  (interactive )
  (emacsvox-speak-region
   (window-start (selected-window))
   (window-end  (selected-window) 'update)))

(defun emacsvox-speak-other-window ()
  "Speak other window"
  (interactive )
  (save-window-excursion
    (other-window 1)
    (emacsvox-speak-region
     (window-start (selected-window))
     (window-end  (selected-window) 'update))))

(defun emacsvox-speak-predefined-window (&optional arg)
  "Speak one of the first 10 windows on the screen, 0 is current window.
Speaks entire window irrespective of point.  Semantics of `other'
is the same as for the Emacs builtin `other-window'."
  (interactive "P")
  
  (let* ((window
          (cond
           ((not (called-interactively-p 'interactive)) arg)
           (t
            (read (format "%c" last-input-event))))))
    (or (numberp window)
        (setq window  (read-number "Window   between 1 and 9:" 1)))
    (save-window-excursion
      (other-window window)
      (emacsvox-speak-region
       (window-start (selected-window))

       (window-end  (selected-window) 'update)))))

;;;   Intelligent interactive commands for reading:

;; Prompt the user if asked to prompt.
;; Prompt is:
;; press 'b' for beginning of unit,
;; 'r' for rest of unit,
;; any other key for entire unit
;; returns 1, -1, or nil accordingly.
;; If prompt is nil, does not prompt: just gets the input

(defun emacsvox-ask-how-to-speak (unit-name prompt)
  "Argument UNIT-NAME specifies kind of unit that is being spoken.
Argument PROMPT specifies the prompt to display."
  (if prompt
      (message
       (format "Press s to speak start of %s, r for rest of  %s. \
 Any  key for entire %s "
               unit-name unit-name unit-name)))
  (let ((char (read-char)))
    (cond
     ((= char ?s) -1)
     ((= char ?r) 1)
     (t nil))))

(defun emacsvox-speak-buffer-interactively ()
  "Speak the start of, rest of, or the entire buffer.
 `s' to speak the start.
 `r' to speak the rest.
any other key to speak entire buffer."
  (interactive)
  (emacsvox-speak-buffer
   (emacsvox-ask-how-to-speak "buffer" (sit-for 1))))

(defun emacsvox-speak-line-interactively ()
  "Speak the start of, rest of, or the entire line.
 `s' to speak the start.
 `r' to speak the rest.
any other key to speak entire line."
  (interactive)
  (emacsvox-speak-line
   (emacsvox-ask-how-to-speak "line" (sit-for 1))))

(defun emacsvox-speak-paragraph-interactively ()
  "Speak the start of, rest of, or the entire paragraph.
 `s' to speak the start.
 `r' to speak the rest.
any other key to speak entire paragraph."
  (interactive)
  (emacsvox-speak-paragraph
   (emacsvox-ask-how-to-speak "paragraph" (sit-for 1))))

(defun emacsvox-speak-page-interactively ()
  "Speak the start of, rest of, or the entire page.
 `s' to speak the start.
 `r' to speak the rest.
any other key to speak entire page."
  (interactive)
  (emacsvox-speak-page
   (emacsvox-ask-how-to-speak "page" (sit-for 1))))

(defun emacsvox-speak-word-interactively ()
  "Speak the start of, rest of, or the entire word.
 `s' to speak the start.
 `r' to speak the rest.
any other key to speak entire word."
  (interactive)
  (emacsvox-speak-word
   (emacsvox-ask-how-to-speak "word" (sit-for 1))))

(defun emacsvox-speak-sexp-interactively ()
  "Speak the start of, rest of, or the entire sexp.
 `s' to speak the start.
 `r' to speak the rest.
any other key to speak entire sexp."
  (interactive)
  (emacsvox-speak-sexp
   (emacsvox-ask-how-to-speak "sexp" (sit-for 1))))

;;;   emacs rectangles and regions:

;; These help you listen to columns of text. Useful for tabulated data
(defun emacsvox-speak-rectangle (start end)
  "Speak a rectangle of text.
Rectangle is delimited by point and mark.  When call from a
program, arguments specify the START and END of the rectangle."
  (interactive "r")
  (require 'rect)
  (tts-speak-list (extract-rectangle start end)))

;;;   Auxiliary functions:

(defun emacsvox-kill-buffer-carefully (buffer)
  "Kill BUFFER BUF if it exists."
  (and buffer
       (get-buffer buffer)
       (kill-buffer buffer)))

(defun emacsvox-overlay-get-text (o)
  "Return text under overlay OVERLAY.
Argument O specifies overlay."
  (save-current-buffer
    (set-buffer (overlay-buffer o))
    (emacsvox-aural-source-substring
     (overlay-start o) (overlay-end o))))

;;;  Speaking spaces

(defun emacsvox-speak-spaces-at-point ()
  "Speak the white space at point."
  (interactive)
  (cond
   ((not (= 32 (char-syntax (following-char))))
    (message "Not on white space"))
   (t
    (let ((orig (point))
          (start (save-excursion
                   (skip-syntax-backward " ")
                   (point)))
          (end (save-excursion
                 (skip-syntax-forward " ")
                 (point))))
      (message "Space %s of %s"
               (1+ (- orig start)) (- end start))))))

;;;   completion helpers

;; switching to completions window from minibuffer:

(defun emacsvox-get-minibuffer-contents ()
  "Return contents of the minibuffer."
  (save-current-buffer
    (set-buffer (window-buffer (minibuffer-window)))
    (minibuffer-contents)))

;; Make all occurrences of string inaudible
(defun emacsvox-make-string-inaudible (string)
  (unless (string-match "^ *$" string)
    (with-silent-modifications
      (save-excursion
        (goto-char (point-min))
        (while (search-forward string nil t)
          (put-text-property
           (match-beginning 0) (match-end 0)
           'personality 'inaudible))))))

(defun emacsvox-switch-to-reference-buffer ()
  "Switch back to buffer that generated completions."
  (interactive)
  
  (if completion-reference-buffer
      (switch-to-buffer completion-reference-buffer)
    (error "Reference buffer not found."))
  (when (called-interactively-p 'interactive)
    (emacsvox-speak-line)
    (emacsvox-icon 'select-object)))

(defun emacsvox-completions-move-to-completion-group ()
  "Move to group of choices beginning with character last
typed. If no such group exists, then we try to search for that
char, or dont move. "
  (interactive)
  
  (let ((pattern
         (format
          "[ \t\n]%s%c"
          (or (emacsvox-get-minibuffer-contents) "")
          last-input-event))
        (input (format "%c" last-input-event))
        (case-fold-search t))
    (when (or (re-search-forward pattern nil t)
              (re-search-backward pattern nil t)
              (search-forward input nil t)
              (search-backward input nil t))
      (skip-syntax-forward " ")
      (emacsvox-icon 'search-hit))
    (tts-speak (emacsvox-get-current-completion))))

(defun emacsvox-completion-setup-hook ()
  "Set things up for emacsvox."
  (with-minibuffer-completions-window 
    (goto-char (point-min))
    (emacsvox-icon 'help)))

(add-hook 'completion-setup-hook 'emacsvox-completion-setup-hook)

(cl-declaim (special completion-list-mode-map))
(define-key completion-list-mode-map
            "\C-o" 'emacsvox-switch-to-reference-buffer)
(define-key completion-list-mode-map
            (kbd "<backspace>") 'previous-completion)
(define-key completion-list-mode-map " " 'next-completion)
(define-key completion-list-mode-map "\C-m" 'choose-completion)
(let ((chars
       "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"))
  (cl-loop for char across chars
           do
           (define-key completion-list-mode-map
                       (format "%c" char)
                       'emacsvox-completions-move-to-completion-group)))

;;;  mark convenience commands

(defun emacsvox-mark-speak-mark-line ()
  "Helper to speak line containing mark."
  
  (emacsvox-icon 'mark-object)
  (ems-set-personality-temporarily (point) (1+ (point))
                                   voice-animate
                                   (emacsvox-speak-line)))

(defun emacsvox-mark-backward-mark ()
  "Cycle backward through the mark ring.
To cycle forward, use pop-to-mark-command bound to \\[pop-to-mark-command] "
  (interactive)
  
  (unless mark-ring (error "Mark ring is empty."))
  (let ((target (elt mark-ring (1- (length mark-ring)))))
    (when target
      (setq mark-ring
            (cons (copy-marker (mark-marker))
                  (nbutlast mark-ring 1)))
      (set-marker (mark-marker) (point) (current-buffer))
      (goto-char (marker-position target))
      (move-marker target nil)
      (when (called-interactively-p 'interactive)
        (emacsvox-mark-speak-mark-line)))))

;;;   speak message at time

(defun emacsvox-speak-message-at-time (time message)
  "Speak message at specified time.
Provides simple stop watch functionality.
See documentation for command run-at-time for details on time-spec."
  (interactive (list (read-from-minibuffer "Time specification:  ")
                     (read-from-minibuffer "Message: ")))
  (run-at-time
   time nil
   #'(lambda (m)
       (tts-notify m)
       (when emacsvox-use-icons (emacsvox-icon 'alarm))
       (sox-tones))
   message)
  (message "Set alarm for %s" time)
  (emacsvox-icon 'button))

;;;  Directory specific settings

(defvar emacsvox-speak-directory-settings
  ".espeak.el"
  "Name of file that holds directory specific settings.")

(defun emacsvox-speak-load-directory-settings (&optional dir)
  "Load a directory specific Emacsvox settings file.
This is typically used to load up settings that are specific to
an electronic book consisting of many files in the same
directory."
  (interactive "DDirectory")
  
  (unless dir (setq dir default-directory))
  (ems-with-messages-silenced
   (let ((emacsvox-speak-messages nil)
         (inhibit-message t)
         (res (locate-dominating-file dir emacsvox-speak-directory-settings)))
     (when
         (and res
              (file-exists-p
               (expand-file-name emacsvox-speak-directory-settings res)))
       (ems--fastload (expand-file-name
                       emacsvox-speak-directory-settings res))
       (when (called-interactively-p 'interactive)
         (message "loaded %s"
                  (expand-file-name emacsvox-speak-directory-settings res)))
       (emacsvox-icon 'task-done)))))

;;;  silence:

(defcustom emacsvox-silence-hook nil
  "Functions run after emacsvox-silence is called."
  :type '(repeat function)
  :group 'emacsvox)

(defun emacsvox-silence ()
  "Silence is golden. Stop speech, and pause/resume any media
streams. Runs `emacsvox-silence-hook' which can be used to
configure which media players get silenced or paused/resumed."
  (interactive)
  
  (tts-stop 'all)
  (run-hooks 'emacsvox-silence-hook))

;;;  Smart date prompe:

(defun emacsvox-speak-collect-date (prompt time-format-string)
  "Smart date collector.
Prompts with `prompt'.
`time-format-string' is format argument for format-time-string.
This function is sensitive to calendar mode when prompting."
  (let ((default (format-time-string time-format-string))) ; today is default
    (when (eq major-mode 'calendar-mode)
                                        ;get smart default from calendar
      (let ((date (calendar-cursor-to-nearest-date)))
        (setq default (format-time-string time-format-string
                                          (apply 'encode-time 0 0
                                                 0
                                                 (cl-second date)
                                                 (cl-first date)
                                                 (list (cl-third date)))))))
    (read-from-minibuffer prompt
                          default
                          nil nil nil
                          default)))

(defun emacsvox-speak-read-date-year/month/date ()
  "Return today as yyyy/mm/dd"
  (emacsvox-speak-collect-date "Date:"
                               "%Y/%m/%d"))

(defun emacsvox-speak-date-YearMonthDate ()
  "Return today as yyyymmdd"
  (emacsvox-speak-collect-date "Date:"
                               "%Y%m%d"))

(defun emacsvox-speak-date-month/date ()
  "Return today as mm/dd"
  (emacsvox-speak-collect-date "Date:"
                               "%m/%d"))

(defun emacsvox-speak-year-month-date ()
  "Return today as yyyy-mm-dd"
  (emacsvox-speak-collect-date "Date:"
                               "%Y-%m-%d"))

;; ;;;  Open Emacsvox Info Pages:

(defun emacsvox-open-info ()
  "Open Emacsvox Info Manual."
  (interactive)
  
  (funcall-interactively
   #'info
   (expand-file-name "emacsvox.info" emacsvox-info-directory)
   "*Emacsvox Info*"))

;;;  Describe help map:

(defun describe-help-keys ()
  "Show bindings under C-h."
  (interactive)
  (describe-bindings "\C-h")
  (emacsvox-icon 'help)
  (with-current-buffer (window-buffer (selected-window))
    (emacsvox-speak-mode-line)))

;;; Utility: Persist variable to a file:
(defun emacsvox--persist-variable (var file)
  "Persist variable  `var' to file `FILE'.
Arranges for `VAR' to be restored when `file' is loaded."
  (interactive)
  (when (and (not noninteractive) (boundp var))
    (let ((buffer (find-file-noselect file))
          (print-length nil)
          (print-level nil))
      (with-current-buffer buffer
        (erase-buffer)
        (insert ";;; Auto-generated.\n\n")
        (insert (format "(setq %s \n" var))
        (if (listp (symbol-value var)) (insert "'"))
        (pp (symbol-value var) (current-buffer))
        (insert (format ") ;;; set %s\n\n" var))
        (save-buffer)
        (kill-buffer)))))

;;; Tapestry --Jump to window by name:

(defun emacsvox-describe-tapestry (&optional details)
  "Describe the current layout of visible buffers in current frame.
Use interactive prefix arg to get coordinate positions of the
displayed buffers."
  (interactive "P")
  
  (let* ((window-list (window-list))
         (count (length window-list))
         (windows nil)
         (description
          (propertize
           (format
            "Displaying %s window%s "
            count
            (if (> count 1) "s" ""))
           'personality voice-annotate)))
    (setq
     windows
     (cond
      (details
       (cl-loop
        for window in window-list
        collect
        (let ((w
               (propertize
                (format "%s "  (window-buffer window))
                'personality voice-animate))
              (corners  (window-edges window))
              (tl nil)
              (br nil))
          (setq tl (format  " %d %d " (cl-second corners) (cl-first corners))
                br  (format " %d %d " (cl-fourth corners) (cl-third corners)))
          (put-text-property 0 (length tl) 'personality voice-bolden tl)
          (put-text-property 0 (length br) 'personality voice-bolden br)
          (concat w " with top left " tl " and bottom right " br))))
      (t (mapcar #'buffer-name (mapcar #'window-buffer window-list)))))
    (emacsvox--sox-multiwindow )
    (tts-speak (concat description (mapconcat #'identity windows " ")))))

(defun emacsvox-select-window-by-name (buffer-name)
  "Select window by the name of the buffer it displays.
This is useful when using modes like ECB or the new GDB UI where
  you want to preserve the window layout
but quickly switch to a window by name."
  (interactive
   (list
    (completing-read
     "Select window: "
     (mapcar
      #'(lambda (w)
          (list (buffer-name (window-buffer w))))
      (window-list))
     nil 'must-match)))
  (pop-to-buffer buffer-name)
  (emacsvox-speak-line))

;;; Battery:
(require 'battery "battery" 'no-error)
(defvar emacsvox-battery-prev nil
  "Previous battery status.")

(defun emacsvox-battery-alarm (data)
  "Battery alarm when critical."
  (when
      (and emacsvox-battery-prev
           (string=  (alist-get ?L data) "off-line")
           (< (string-to-number (alist-get ?p data)) 10)
           (>= (string-to-number (alist-get ?p emacsvox-battery-prev)) 10))
    (emacsvox-icon 'battery-low)
    (setq emacsvox-battery-prev data)))
(when (boundp 'battery-update-functions)
  (add-to-list 'battery-update-functions 'emacsvox-battery-alarm))

;;; Repeat Mode:
;; See https://karthinks.com/software/it-bears-repeating/

(defvar emacsvox-repeat-was-active nil
  "Cache repeat-progress")

(defun emacsvox-repeat-check-hook ()
  "Play appropriate repeat icon."
  
  (cond
   ((and repeat-in-progress (not emacsvox-repeat-was-active))
    (setq emacsvox-repeat-was-active t)
    (emacsvox-icon 'repeat-start))
   ((and (not repeat-in-progress)  emacsvox-repeat-was-active)
    (setq emacsvox-repeat-was-active nil)
    (emacsvox-icon 'repeat-end))
   (repeat-in-progress (emacsvox-icon 'repeat-active))))

(defun ems--repeat-sentinel (process _state)
  "Process sentinel to disable repeat. "
  (when (memq (process-status process) '(failed signal exit stop nil))
    (when repeat-mode (repeat-exit))))

(defsubst emacsvox-repeat-mode-hook ()
  "Add or remove emacsvox-repeat-check-hook from post-command-hook"
  
  (cond
   (repeat-mode
    (add-hook 'post-command-hook 'emacsvox-repeat-check-hook 'at-end))
   (t (remove-hook 'post-command-hook 'emacsvox-repeat-check-hook))))

(add-hook 'repeat-mode-hook 'emacsvox-repeat-mode-hook )

;;; go top or bottom
(defun emacsvox-beginning-or-end ()
  "Move to start or end of buffer."
  (interactive)
  (cond
   ((= (point) (point-min)) (call-interactively 'end-of-buffer))
   ((= (point) (point-max)) (call-interactively 'beginning-of-buffer))
   (t (call-interactively 'beginning-of-buffer)))
  (when (called-interactively-p 'interactive)
    (tts-notify
     (format "%s%%" (emacsvox-get-current-percentage-into-buffer)))))

;;; Utility: Accumulate

(defun emacsvox-accumulate-to-register (reg generator)
  "Call generator and append resulting content to specified register.
Appended entries are separated by newlines."
  (set-register reg
                (concat
                 (get-register reg) "\n" (funcall generator )))
  (message
   "Accumulated %d lines"
   (length (split-string (get-register reg) "\n"))))

;;;  Buffer Select:

;; Helpers:

(defsubst emacsvox-buffer-cycle-previous (mode)
  "Return previous  buffer in cycle order having same major mode as `mode'."
  (catch 'cl-loop
    (dolist (buf (reverse (cdr (buffer-list (selected-frame)))))
      (when (with-current-buffer buf (eq mode major-mode))
        (throw 'cl-loop buf)))))

(defsubst emacsvox-buffer-cycle-next (mode)
  "Return next buffer in cycle order having same major mode as `mode'."
  (catch 'cl-loop
    (dolist (buf (cdr (buffer-list (selected-frame))))
      (when (with-current-buffer buf (eq mode major-mode))
        (throw 'cl-loop buf)))))

(defun emacsvox-cycle-to-previous-buffer ()
  "Cycles to previous buffer having same mode."
  (interactive)
  (let ((prev (emacsvox-buffer-cycle-previous major-mode)))
    (cond
     (prev
      (funcall-interactively #'switch-to-buffer prev))
     (t (error "No previous buffer in mode %s" major-mode)))))

(defun emacsvox-cycle-to-next-buffer ()
  "Cycles to next buffer having same mode."
  (interactive)
  (let ((next (emacsvox-buffer-cycle-next major-mode)))
    (cond
     (next ;  (bury-buffer)
      (funcall-interactively #'switch-to-buffer next))
     (t (error "No next buffer in mode %s" major-mode)))))

;; Inspired by text-adjust-scale:

(defcustom emacsvox-buffer-select-help
  ""
  "String passed to speak help.
Set this to the empty string once you've learnt this command. "
  :type '(choice
          (const :tag "Speak Keys" :value "Repeat with %k")
          (const :tag "Silence" :value ""))
  :group 'emacsvox)

(defun emacsvox-buffer-select()
  "Select buffer by smart cycling.
Use option emacsvox-buffer-select-help to customize interactive feedback.
By default, this command is bound to multiple keys.
The final key of the initial  key-sequence, and  further invocations
of the keys below call the following bindings:

, previous-buffer
. next-buffer
b switch-to-buffer
f find-file
k emacsvox-kill-buffer-quietly
n emacsvox-cycle-to-next-buffer
o other-window
p emacsvox-cycle-to-previous-buffer
"
  (interactive )
  
  (let ((key (event-basic-type last-command-event)))
    (emacsvox-icon 'repeat-active)
    (cl-case key
      (?b (call-interactively 'switch-to-buffer))
      (?f (call-interactively 'find-file))
      (?k (call-interactively 'emacsvox-kill-buffer-quietly))
      (?p
       (call-interactively 'emacsvox-cycle-to-previous-buffer))
      (?, (call-interactively 'previous-buffer))
      (?n
       (call-interactively 'emacsvox-cycle-to-next-buffer))
      (?o (call-interactively 'other-window))
      (?. (call-interactively 'next-buffer)))
    (set-transient-map
     (let ((map (make-sparse-keymap)))
       (dolist (key '("b" "f" "k" "," "."   "p" "n" "o"))
         (define-key
          map key
          #'(lambda () (interactive) (emacsvox-buffer-select ))))
       map)
     t (lambda nil (emacsvox-icon 'repeat-end))
     emacsvox-buffer-select-help)))

;;; Network Utils:

(defun ems--get-ip-address (dev)
  "get the IP-address for device DEV "
  (setq dev
        (or
         dev
         (completing-read "Dev: " (ems--get-active-network-interfaces) nil t)))
  (format-network-address (car (network-interface-info dev)) 'omit-port))

(defun ems--get-active-network-interfaces ()
  "Return  names of active network interfaces.
Filters out loopback for convenience."
  (when (fboundp 'network-interface-list)
    (seq-remove #'(lambda (d) ( string= d "lo") ) 
                (seq-uniq (mapcar #'car (network-interface-list))))))

(defun emacsvox-speak-net-id ()
  "Shows active network interfaces in the echo area.
 The address is also copied to the kill ring for convenient yanking."
  (interactive)
  (kill-new
   (message
    "%s: %s"
    (ems--get-essid)
    (ems--get-ip-address(cl-first  (ems--get-active-network-interfaces))))))

;;; Smarter selective-display:

(defun emacsvox-selective-display (&optional arg)
  "Continuously adjust selective-display.
Use `,' and `.' to continuously decrease/increase `selective-display'.
 If not specified, `arg' defaults to current-column."
  (interactive "P")
  
  (setq selective-display
        (if arg (prefix-numeric-value arg) (current-column)))
  (let ((key (event-basic-type last-command-event)))
    (emacsvox-icon 'repeat-start)
    (cl-case key
      (?,
       (cl-assert (numberp selective-display) t
                  "Selective display is off")
       (if (> selective-display 2)
           (setq selective-display (- selective-display 2))
         (setq selective-display nil))
       (funcall-interactively #'set-selective-display selective-display))
      (?.
       (when (or (numberp selective-display) (null selective-display))
         (if (null selective-display)
             (setq selective-display 2)
           (setq selective-display (+ selective-display 2)))
         (funcall-interactively #'set-selective-display selective-display))))
    (set-transient-map
     (let ((map (make-sparse-keymap)))  ; map
       (dolist (key '("," "."))
         (define-key
          map key
          (lambda ()
            (interactive)
            (emacsvox-selective-display selective-display))))
       map)
     t                                  ; continue predicate
     (lambda nil (emacsvox-icon 'repeat-end)) ; done action
     (propertize
      (format "Selective Display: %s" selective-display)
      'personality voice-bolden))))

;;; Pip: Use Piper if available.
;; Uses pip if piper loaded, otherwise falls back to notifications

(defun emacsvox-pip (text)
  "Speak text, either using piper or regular notification stream."
  (cond
   ((featurep 'pip) (pip-speak text))
   (t (tts-notify text))))

;;; Bug Reporter:
(defconst emacsvox-bug-address "emacsvox@emacsvox.net" "List address")

(defun emacsvox-submit-bug ()
  "Function to submit a bug to the Emacsvox list"
  (interactive)
  (require 'reporter)
  (when
      (yes-or-no-p "Are you sure you want to submit a bug report? ")
    (let ((reporter-prompt-for-summary-p t)
          (vars
           '(
             window-system window-system-version emacs-version system-type
             emacsvox-version emacsvox-show-point
             tts-program tts-speech-rate tts-character-scale
             tts-split-caps tts-punctuation-mode visual-line-mode
             emacsvox-line-echo  emacsvox-word-echo emacsvox-character-echo
             emacsvox-audio-indentation)))
      (mapc
       #'(lambda (x)
           (if (not (and (boundp x) (symbol-value x)))
               (setq vars (delq x vars))))
       vars)
      (when reporter-prompt-for-summary-p ; to appease compiler
        (reporter-submit-bug-report
         emacsvox-bug-address
         (concat "Emacsvox: " emacsvox-version)
         vars nil nil
         "Description of Problem:")))))
(provide 'emacsvox-speak)

;;;  end of file
