;;; emacsvox-speak.el --- Core Speech Lib -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Spoken Output
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

;; This module defines the core speech services used by emacsvox.
;; It depends on the speech server interface modules
;; It protects other parts of emacsvox
;; from becoming dependent on the speech server modules
;; Tracked buffer reading lives in `emacsvox-tracked-reading'.
;; Column filtering and saved filters live in `emacsvox-speak-filters'.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'subr-x)
(require 'voice-setup)
(require 'voice-defs)
(require 'tts-speak)
(require 'emacsvox-pronounce)
(require 'emacsvox-sounds)
(require 'emacsvox-aural-submission)
(require 'sox-gen)
(require 'shr)
(declare-function operate-on-rectangle "rect" (function start end coerce-tabs))

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

(require 'emacsvox-speak-status)

(require 'emacsvox-speak-messages)

(require 'emacsvox-speak-characters)

(add-hook 'post-self-insert-hook 'emacsvox-post-self-insert-hook)

;;;  Shell Command Helper:

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

(defvar emacsvox-notifications-buffer
  (emacsvox--notifications-init)
  "Notifications buffer. Retains at most `emacsvox-notifications-max lines.")

(defvar emacsvox-notifications-gc-timer
  (run-at-time 43200 43200 #'emacsvox-notifications-truncate)
  "Idle timer that runs every 12 hours  to cleanup notifications.")

(require 'emacsvox-speak-completion)

(require 'emacsvox-speak-time)

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

(defvar emacsvox-speak-paragraph-personality 'voice-animate
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

(require 'emacsvox-speak-presentation)

(require 'emacsvox-speak-navigation)

;;; Column filtering and saved settings:

(require 'emacsvox-speak-filters)

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

(defun emacsvox-speak-region-content (start end)
  "Prepare and return speech content from START to END.

For a region smaller than `ems--large-text-size', preserve source formatting
and apply the paragraph voice annotation used by `emacsvox-speak-region'.
Return nil for a region large enough to require windowful speech."
  (let ((inhibit-modification-hooks t)
        (deactivate-mark nil))
    (when (< (abs (- start end)) ems--large-text-size)
      (unless emacsvox-speak-voice-annotated-paragraphs
        (save-restriction
          (narrow-to-region start end)
          (emacsvox-speak-voice-annotate-paragraphs)))
      (emacsvox-aural-source-substring start end))))

(defun emacsvox-speak-region (start end)
  "Speak region bounded by start and end. "
  (interactive "r")
  (let ((inhibit-modification-hooks t)
        (deactivate-mark nil))
    (let ((content (emacsvox-speak-region-content start end)))
      (if content
          (tts-speak content)
        (call-interactively #'emacsvox-speak-windowful)))))

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
  "Length above which nontext lines require confirmation.
Ordinary prose does not change reading mode or prompt.  Lines containing
control bytes beyond this length, and lines over 100,000 characters, ask
before speaking.  Confirmation applies only to the current reading.")

(defconst emacsvox-speak-blank-line-regexp
  "\\`[[:space:]]+\\'"
  "Pattern that matches a string containing only white space.")

(defun emacsvox-speak--line-condition (line)
  "Return the semantic condition represented by LINE, or nil for speech."
  (cond
   ((string-empty-p line) 'empty)
   ((string-match-p emacsvox-speak-blank-line-regexp line)
    'whitespace-only)
   ((or (eq 'all tts-punctuation-mode)
        (omnivox-punctuation-profiles--mode-p tts-punctuation-mode)) nil)
   ((string-match-p emacsvox-horizontal-rule line) 'separator)
   ((string-match-p emacsvox-decoration-rule line) 'decorative)
   ((string-match-p emacsvox-unspeakable-rule line) 'unspeakable)))

(defun emacsvox-speak--visual-line-condition ()
  "Return the blank condition at the current visual line, or nil.

An empty visual segment counts only when its containing physical line is
empty or whitespace-only.  This avoids treating the empty segment at a wrap
boundary as a blank line."
  (save-excursion
    (let* ((inhibit-field-text-motion t)
           (physical-start (line-beginning-position))
           (physical-end (line-end-position)))
      (beginning-of-visual-line)
      (let ((start (point)))
        (end-of-visual-line)
        (let ((line (buffer-substring-no-properties start (point))))
          (cond
           ((string-empty-p line)
            (let ((physical-line
                   (buffer-substring-no-properties
                    physical-start physical-end)))
              (cond
               ((string-empty-p physical-line) 'empty)
               ((string-match-p
                 emacsvox-speak-blank-line-regexp physical-line)
                'whitespace-only))))
           ((string-match-p emacsvox-speak-blank-line-regexp line)
            'whitespace-only)))))))

(defun emacsvox-speak--action-facts (key value)
  "Return current semantic facts extended with KEY and VALUE.

Object content belongs to text-bearing submissions and is deliberately
excluded from this action-only presentation."
  (let ((tail emacsvox-aural-submission-facts)
        facts)
    (while tail
      (unless (eq (car tail) :content)
        (setq
         facts
         (append
          facts
          (list (car tail) (copy-tree (cadr tail))))))
      (setq tail (cddr tail)))
    (plist-put facts key value)))

(defun emacsvox-speak--present-action-fact
    (key value default-occasion
         &optional inherit-facts compatibility-actions)
  "Present KEY and VALUE under DEFAULT-OCCASION without text content.

When INHERIT-FACTS is non-nil, compose with compatible outer submission facts.
COMPATIBILITY-ACTIONS are delivered in the same native transaction.  Preserve
the silence and server-lifecycle behavior of legacy tone helpers."
  (unless
      (or
       tts-quiet
       (not (process-live-p tts-speaker-process)))
    (let* ((facts
            (if inherit-facts
                (emacsvox-speak--action-facts key value)
              (list key value)))
           (emacsvox-aural-submission-facts facts))
      (emacsvox-aural-submit-actions
       :facts facts
       :module emacsvox-aural-submission-module
       :occasion
       (or emacsvox-aural-submission-occasion default-occasion)
       :compatibility-actions compatibility-actions))))

(defun emacsvox-speak--present-line-condition
    (condition &optional compatibility-actions)
  "Present semantic line CONDITION with COMPATIBILITY-ACTIONS.

Preserve the legacy silence and server-lifecycle policy."
  (emacsvox-speak--present-action-fact
   :line-condition condition 'navigation t compatibility-actions))

;;;###autoload
(defun emacsvox-speak-edit-operation (operation)
  "Present semantic editing OPERATION without text content.

This compatibility adapter preserves the silence and server-lifecycle
behavior of legacy edit-tone helpers.  It deliberately does not inherit
surrounding object facts or content."
  (emacsvox-speak--present-action-fact
   :edit-operation operation 'edit))

(defvar-local emacsvox-speak--reading-transform-function nil
  "Optional mode function preparing a selected reading unit for speech.
Called with TEXT, source START and END, and UNIT (`line', `partial-line', or
`word'; `word-navigation' for a word reached by movement) before presentation
prefixes and concrete speech plans are added.")

(defvar emacsvox-speak--word-navigation-p nil
  "Non-nil while speaking the destination of a word movement command.")

(defun emacsvox-speak--reading-text (text start end unit)
  "Prepare source TEXT between START and END for reading UNIT."
  (if emacsvox-speak--reading-transform-function
      (funcall emacsvox-speak--reading-transform-function text start end unit)
    text))

(defun emacsvox-speak--remove-captured-line-icon
    (content icon source-offset source-length)
  "Return CONTENT without the ICON captured at SOURCE-OFFSET.

SOURCE-LENGTH is the selected source-line length before indentation or line
number prefixes are added.  Other text properties and auditory icons remain."
  (if (null icon)
      content
    (let* ((result (copy-sequence content))
           (prefix-length (max 0 (- (length result) source-length)))
           (expected
            (min
             (max 0 (+ prefix-length source-offset))
             (max 0 (1- (length result)))))
           (position
            (and
             (<= 0 source-offset)
             (< source-offset source-length)
             (< expected (length result))
             (eq
              (get-text-property expected 'auditory-icon result)
              icon)
             expected)))
      (when position
        (let ((start
               (or
                (previous-single-property-change
                 (1+ position) 'auditory-icon result)
                0))
              (end
               (or
                (next-single-property-change
                 position 'auditory-icon result)
                (length result))))
          (remove-text-properties
           start end '(auditory-icon nil) result)))
      result)))

(defun emacsvox-speak-line-with-speaker (speaker &optional arg)
  "Present the current line, delivering speakable text to SPEAKER.

ARG and all line-selection and presentation behavior match
`emacsvox-speak-line'.  SPEAKER is called only when line policy selects
speech; empty, whitespace, decorative, and otherwise unspeakable lines retain
their established tone paths without calling SPEAKER.  The caller owns
interruption so native submissions can apply their complete delivery policy."
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
         (point-facts nil)
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
    (setq point-facts (emacsvox-speak--point-facts orig start end))
    (when icon (emacsvox-icon icon))
    (setq line
          (emacsvox-speak--annotate-point
           (emacsvox-speak--remove-captured-line-icon
            (emacsvox-aural-source-substring start end)
            icon (- orig start) (- end start))
           orig start end point-facts))
    (when (and (null arg) emacsvox-speak-line-column-filter)
      (setq
       line
       (emacsvox-speak-line-apply-column-filter
        line emacsvox-speak-line-invert-filter)))
    (setq line
          (emacsvox-speak--reading-text
           line start end (if arg 'partial-line 'line)))
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
    (if-let* ((condition (emacsvox-speak--line-condition line)))
        (emacsvox-speak--present-line-condition condition)
      (let ((speakable
             (or (not (or (> (length line) 100000)
                          (and (> (length line) ems--speak-max-length)
                               (string-match-p "[\000-\010\013\014\016-\037\177]" line))))
                 (y-or-n-p "Read this unusually large or nontext line? "))))
        (when speakable
          (when
              (and (null arg) indent (> indent 0))
            (setq
             line
             (emacsvox-speak--annotate-indentation
              line (emacsvox-speak--indentation-facts indent))))
          (when linenum
            (setq linenum (format "%d" linenum))
            (setq linenum (propertize linenum 'personality 'voice-lighten))
            (setq line (concat linenum line)))
          (funcall speaker line))))))

(defun emacsvox-speak--present-physical-line
    (&optional arg compatibility-actions)
  "Present the current physical line as one native transaction.

ARG has the same selection meaning as in `emacsvox-speak-line'.  Cues emitted
while extracting the line become ordered compatibility actions, and semantic
line conditions remain action-only submissions.  COMPATIBILITY-ACTIONS are
placed around the same content without escaping replaceable delivery."
  (when (listp arg) (setq arg (car arg)))
  (let* ((context
          (or
           emacsvox-aural-submission-context
           (emacsvox-aural-capture-context
            emacsvox-aural-submission-module
            (or emacsvox-aural-submission-occasion 'navigation))))
         (module
          (or
           emacsvox-aural-submission-module
           (plist-get context :module)))
         (occasion
          (or
           emacsvox-aural-submission-occasion
           (plist-get context :occasion)
           'navigation))
         (facts (copy-tree emacsvox-aural-submission-facts))
         action-arguments
         content
         icons)
    (let ((emacsvox-aural-submission-context context)
          (emacsvox-aural-submission-module module)
          (emacsvox-aural-submission-occasion occasion))
      (cl-letf
          (((symbol-function 'emacsvox-icon)
            (lambda (icon)
              (setq icons (append icons (list icon)))))
           ((symbol-function 'emacsvox-aural-submit-actions)
            (lambda (&rest arguments)
              (setq action-arguments arguments))))
        (emacsvox-speak-line-with-speaker
         (lambda (text) (setq content text))
         arg))
      (let ((compatibility-actions
             (append
              compatibility-actions
              (mapcar #'emacsvox-aural-compatibility-icon icons))))
        (cond
         (content
          (emacsvox-aural-submit
           content
           :facts facts
           :context context
           :module module
           :occasion occasion
           :compatibility-actions compatibility-actions))
         (action-arguments
          (let ((emacsvox-aural-submission-facts
                 (plist-get action-arguments :facts)))
            (apply
             #'emacsvox-aural-submit-actions
             (plist-put
              (plist-put
               action-arguments :context context)
              :compatibility-actions
              (append
               compatibility-actions
               (plist-get action-arguments :compatibility-actions)))))))))))

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
  (emacsvox-speak--present-physical-line arg))

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

(defun emacsvox-speak--visible-text-p (start end)
  "Return non-nil if START to END contains visible, nonblank text."
  (save-excursion
    (goto-char start)
    (catch 'visible
      (while (re-search-forward "[^[:space:]]" end t)
        (let ((position (match-beginning 0)))
          (if (invisible-p position)
              (goto-char (min end (next-char-property-change position end)))
            (throw 'visible t))))
      nil)))

(defun emacsvox-speak--visual-row (start end)
  "Describe visible row START to END within its source line.
Ignore hidden text and wrap whitespace when deciding whether readable text
continues above or below.  The caller supplies bounds from the current window;
no layout is cached, so edits and window changes take effect immediately."
  (save-excursion
    (goto-char start)
    (let* ((source-start (line-beginning-position))
           (source-end (progn (goto-char end) (line-end-position)))
           (above (emacsvox-speak--visible-text-p source-start start))
           (below (emacsvox-speak--visible-text-p end source-end)))
      (list :type (cond ((and above below) 'middle) (above 'last)
                        (below 'first) (t 'complete))
            :source-start source-start :source-end source-end
            :start start :end end))))

(defun emacsvox-speak-visual-line ()
  "Speaks current visual line.
Cues the start of a physical line with auditory icon `left'."
  (interactive)
  (let* ((inhibit-field-text-motion t)
         (inhibit-read-only t)
         (inhibit-modification-hooks t)
         (orig (point))
         (condition (emacsvox-speak--visual-line-condition))
         (icon
          (cond
           ((looking-at "^ *") 'left)
           ((looking-at " *$") 'right)))
         (context
          (or
           emacsvox-aural-submission-context
           (emacsvox-aural-capture-context
            emacsvox-aural-submission-module
            (or emacsvox-aural-submission-occasion 'navigation))))
         (module
          (or
           emacsvox-aural-submission-module
           (plist-get context :module)))
         (occasion
          (or
           emacsvox-aural-submission-occasion
           (plist-get context :occasion)
           'navigation))
         (facts (copy-tree emacsvox-aural-submission-facts))
         (compatibility-actions
          (when
              (and icon (not (memq condition '(empty whitespace-only))))
            (list (emacsvox-aural-compatibility-icon icon))))
         start end line point-facts)
    (save-excursion
      (beginning-of-visual-line)
      (setq start (point))
      (end-of-visual-line)
      (setq end (point))
      (setq point-facts (emacsvox-speak--point-facts orig start end))
      (setq line
            (emacsvox-speak--annotate-point
             (emacsvox-aural-source-substring start end)
             orig start end point-facts)))
    (let ((emacsvox-aural-submission-context context)
          (emacsvox-aural-submission-module module)
          (emacsvox-aural-submission-occasion occasion)
          (emacsvox-aural-submission-facts facts))
      (cond
       (condition
        (emacsvox-speak--present-line-condition
         condition compatibility-actions))
       ((not (string-empty-p line))
        (emacsvox-aural-submit
         line
         :facts facts
         :context context
         :module module
         :occasion occasion
         :compatibility-actions compatibility-actions))))))

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
             (when (char-uppercase-p char)
               (put-text-property 0 1
                                  'personality 'voice-animate
                                  char-string))
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
      (let ((text (emacsvox-aural-source-substring start end)))
        (funcall speaker
                 (if (eq speaker 'tts-speak)
                     (emacsvox-speak--reading-text
                      text start end
                      (if (and emacsvox-speak--word-navigation-p (null arg))
                          'word-navigation
                        'word))
                   text))))))

;; `:init-value' initializes the option but does not run the mode body.
;; Respect a previously customized value when installing the cancellation hooks.
(emacsvox-delayed-phonetic-mode (if emacsvox-delayed-phonetic-mode 1 -1))

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

(require 'emacsvox-tracked-reading)

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

(voice-setup-add-map '((header-line voice-bolden)))

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

;;;  Codenames etc.
(defvar emacsvox-codename
  (propertize "DreamDog" 'face 'bold)
  "Code name of present release.")
(defvar emacsvox-version
  (format
   "%s, %s%s"
   emacsvox-version-number
   emacsvox-codename
   (if (> (length emacsvox-git-revision) 0)
       (concat " " emacsvox-git-revision)
     ""))
  "Display version for Emacsvox, including codename and Git revision.")

(defun emacsvox-speak-version ()
  "Announce version information for running emacsvox. "
  (interactive)
  (emacsvox-icon 'emacsvox)
  (message "Emacsvox %s" emacsvox-version))

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
    (put-text-property 0 (length context) 'personality 'voice-annotate context)
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
                       'personality 'voice-annotate context)
    (setq pos
          (if current-prefix-arg
              (elt mark-ring (1- count))
            (mark)))
    (save-excursion
      (goto-char pos)
      (ems-set-personality-temporarily
       pos (1+ pos) 'voice-animate
       (setq line (ems--this-line)))
      (tts-speak
       (concat context line)))))

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
  (let ((char
         (read-char
          (when prompt
            (format
             "Press s to speak start of %s, r for rest of %s. Any key for entire %s "
             unit-name unit-name unit-name)))))
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
                                   'voice-animate
                                   (emacsvox-speak-line)))

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

;;; Battery:
(require 'battery "battery" 'no-error)
(when (boundp 'battery-update-functions)
  (add-to-list 'battery-update-functions 'emacsvox-battery-alarm))

(add-hook 'repeat-mode-hook 'emacsvox-repeat-mode-hook )

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
             emacsvox-show-point-presentation
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

;;; emacsvox-speak.el ends here
