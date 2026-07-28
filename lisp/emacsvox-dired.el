;;; emacsvox-dired.el --- Speech enable Dired Mode -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:  Emacsvox extension to speech enable dired
;; Keywords: Emacsvox, Dired, Spoken Output
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

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Commentary:
;; This module speech enables dired.
;; It reduces the amount of speech you hear:
;; Typically you hear the file names as you move through the dired buffer
;; Voicification is used to indicate directories, marked files etc.

;;; Code:

;;; Forward variable declarations:

(defvar emacsvox-m-player-options)

;;;   required packages

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'emacsvox-aural-transport)
(require 'emacsvox-aural-representative)
(require 'dired)

;;;  Define personalities

(voice-setup-add-map
 '(
   (dired-broken-symlink 'voice-monotone-extra)
   (dired-set-id  voice-animate)
   (dired-special voice-lighten)
   (dired-header voice-smoothen)
   (dired-mark voice-lighten)
   (dired-marked voice-lighten)
   (dired-perm-write voice-lighten-extra)
   (dired-warning voice-animate-extra)
   (dired-directory voice-bolden)
   (dired-symlink voice-animate)
   (dired-ignored voice-lighten-extra)
   (dired-flagged voice-animate-extra)))

(defconst emacsvox-dired-aural-fragment
  '(:schema-version 1
    :id dired-entry-navigation
    :summary "State-aware navigation feedback for Dired entries"
    :rules
    ((:id dired-marked-navigation
      :match
      (:role filesystem-entry :module dired :state marked
       :occasion navigation)
      :render
      (:before
       (:remove (legacy-cue)
        :append
        ((:id dired-marked-navigation-cue
          :kind cue :cue mark-object)))))))
  "Always-on Dired presentation rules supplied by the module.")

(unless
    (gethash
     'dired-entry-navigation emacsvox-aural-module-fragment-registry)
  (emacsvox-aural-register-module-fragment
   'dired emacsvox-dired-aural-fragment :source "emacsvox-dired"))

;;;   functions:

(defun emacsvox-dired--speak-line-compatibility ()
  "Speak the dired line intelligently.
If in locate-mode, speak full pathname."
  
  (let ((filename
         (dired-get-filename (if (eq major-mode 'locate-mode) nil 'no-dir) t))
        (personality (tts-get-style)))
    (cond
     (filename (tts-speak (propertize filename 'personality personality))
               (setq emacsvox-speak-last-spoken-word-position (point)))
     (t (emacsvox-speak-line)
        (ding)))))

(defun emacsvox-dired-speak-line ()
  "Speak the current Dired entry with semantic navigation context."
  (emacsvox-dired--call-with-aural-presentation
   (emacsvox-dired-entry-facts 'focus-entered)
   'navigation #'emacsvox-dired--speak-line-compatibility))

;;; Semantic aural presentation:

(defun emacsvox-dired-enable-aural-context ()
  "Identify the current Dired buffer to aural presentation schemes."
  (setq-local emacsvox-aural-module 'dired))

(add-hook 'dired-mode-hook #'emacsvox-dired-enable-aural-context)

(defun emacsvox-dired--call-with-aural-presentation
    (facts occasion function &rest arguments)
  "Call FUNCTION with ARGUMENTS in a frozen Dired presentation.
FACTS describe the object or event, and OCCASION describes the interaction."
  (let* ((effective-facts
          (or emacsvox-aural-submission-facts facts
              '(:role filesystem-listing)))
         (effective-occasion
          (or emacsvox-aural-submission-occasion occasion 'navigation))
         (effective-module
          (or emacsvox-aural-submission-module 'dired))
         (context
          (or emacsvox-aural-submission-context
              (emacsvox-aural-capture-context
               effective-module effective-occasion)))
         (emacsvox-aural-submission-facts effective-facts)
         (emacsvox-aural-submission-context context)
         (emacsvox-aural-submission-module effective-module)
         (emacsvox-aural-submission-occasion effective-occasion))
    (apply function arguments)))

(defun emacsvox-dired--present-feedback
    (facts occasion icon function &rest arguments)
  "Under FACTS and OCCASION, present ICON then call FUNCTION with ARGUMENTS."
  (emacsvox-dired--call-with-aural-presentation
   facts occasion
   (lambda ()
     (when icon (emacsvox-icon icon))
     (apply function arguments))))

(defun emacsvox-dired-entry-facts (&optional event extra-states)
  "Return semantic facts for the Dired entry at point.

EVENT names an optional state change and EXTRA-STATES augments states inferred
from the Dired marker column."
  (let* ((filename (ignore-errors (dired-get-filename nil t)))
         (marker (char-after (line-beginning-position)))
         (kind
          (cond
           ((null filename) 'other)
           ((file-symlink-p filename) 'symbolic-link)
           ((file-directory-p filename) 'directory)
           ((file-regular-p filename) 'file)
           (t 'other)))
         (states (copy-sequence extra-states)))
    (when (eq marker ?*) (push 'marked states))
    (when (eq marker ?D) (push 'deletion-flagged states))
    (append
     (list :role 'filesystem-entry :entry-kind kind)
     (when event (list :events (list event)))
     (when states (list :states (delete-dups (nreverse states)))))))

(defun emacsvox-dired-present-current
    (icon occasion event &optional speaker)
  "Present the current entry with ICON, OCCASION, EVENT, and SPEAKER.

The established icon-then-speech ordering is preserved."
  (emacsvox-dired--present-feedback
   (emacsvox-dired-entry-facts event)
   occasion icon (or speaker #'emacsvox-dired-speak-line)))

(defun emacsvox-dired-inspection-facts (kind)
  "Return current-entry facts for inspection KIND."
  (append
   (emacsvox-dired-entry-facts 'entry-inspected)
   (list :entry-inspection-kind kind)))

(defun emacsvox-dired-action-facts (event &optional state)
  "Return frozen current-entry facts for action EVENT and resulting STATE."
  (let ((entry (emacsvox-dired-entry-facts)))
    (append
     (list
      :role 'filesystem-entry
      :entry-kind (plist-get entry :entry-kind)
      :events (list event))
     (when state (list :states (list state))))))

(defun emacsvox-dired--marking-around
    (orig-fun arguments target icon event &optional state)
  "Call ORIG-FUN with ARGUMENTS and present a Dired marking action.

TARGET controls interactive feedback.  ICON, EVENT, and resulting STATE
describe the entry at point before the command advances to the next row."
  (if (ems-interactive-p target)
      (let* ((facts (emacsvox-dired-action-facts event state))
             (context
              (emacsvox-aural-capture-context 'dired 'state-change))
             (result (apply orig-fun arguments)))
        (let ((emacsvox-aural-submission-context context))
          (emacsvox-dired--present-feedback
           facts 'state-change icon #'ignore))
        (emacsvox-dired-present-current
         nil 'navigation 'focus-entered)
        result)
    (apply orig-fun arguments)))

;;;   advice:

(defun emacsvox--advice-dired-sort-toggle-or-edit-around
    (orig-fun &rest args)
  "speak."
  (if (ems-interactive-p 'dired-sort-toggle-or-edit)
      (let (result)
        (ems-with-messages-silenced
          (setq result (apply orig-fun args)))
        (emacsvox-dired--present-feedback
         (emacsvox-dired-entry-facts 'operation-completed)
         'state-change 'task-done #'emacsvox-speak-mode-line)
        result)
    (apply orig-fun args)))

(advice-add 'dired-sort-toggle-or-edit :around
            #'emacsvox--advice-dired-sort-toggle-or-edit-around)

(defun emacsvox--advice-dired-query-before (&rest _)
  "Present a Dired confirmation request."
  (emacsvox-dired--present-feedback
   '(:role confirmation-request) 'notification
   'ask-short-question #'ignore))

(advice-add 'dired-query :before
            #'emacsvox--advice-dired-query-before)

(defun emacsvox-dired-initialize ()
  "Set up emacsvox dired."
  (emacsvox-dired-enable-aural-context)
  (emacsvox-dired-label-fields)
  (emacsvox-dired-setup-keys))

(defmacro emacsvox-dired--define-after-advice
    (targets docstring &rest body)
  "Define native after advice for each command in TARGETS.
DOCSTRING and BODY define the feedback function for each command."
  (declare (indent 2) (debug (sexp stringp body)))
  `(progn
     ,@(mapcar
        (lambda (target)
          (let ((function
                 (intern (format "emacsvox--dired-%s-after" target))))
            `(progn
               (defun ,function (&rest _)
                 ,docstring
                 (when (ems-interactive-p ',target)
                   ,@body))
               (advice-add
                ',target :after #',function '((name . emacsvox))))))
        targets)))

(emacsvox-dired--define-after-advice
    (dired ido-dired dired-jump dired-other-window dired-other-frame)
    "Set up Emacsvox."
  (emacsvox-dired-initialize)
  (emacsvox-dired--present-feedback
   (emacsvox-dired-entry-facts 'entry-opened)
   'state-change 'open-object #'emacsvox-speak-mode-line))

(defun emacsvox--advice-dired-find-file-around (orig-fun &rest args)
  "Produce an auditory icon."
  (if (ems-interactive-p 'dired-find-file)
      (let* ((directory-p (file-directory-p (dired-get-filename t t)))
             (facts (emacsvox-dired-entry-facts 'entry-opened))
             (context
              (emacsvox-aural-capture-context 'dired 'state-change))
            result)
        (setq result (apply orig-fun args))
        (when directory-p
          (emacsvox-dired-label-fields))
        (let ((emacsvox-aural-submission-context context))
          (emacsvox-dired--call-with-aural-presentation
           facts 'state-change
           (lambda ()
             (emacsvox-speak-mode-line)
             (emacsvox-icon 'open-object))))
        result)
    (apply orig-fun args)))

(advice-add 'dired-find-file :around
            #'emacsvox--advice-dired-find-file-around)

(emacsvox-dired--define-after-advice
    (dired-next-subdir dired-prev-subdir
     dired-tree-up dired-tree-down dired-up-directory
     dired-next-marked-file dired-prev-marked-file
     dired-next-dirline dired-prev-dirline)
    "Speak the filename."
  (emacsvox-dired-present-current
   'large-movement 'navigation 'focus-entered))

(emacsvox-dired--define-after-advice
    (dired-next-line dired-previous-line
     dired-unmark-backward dired-maybe-insert-subdir)
    "Speak the filename."
  (emacsvox-dired-present-current
   'select-object 'navigation 'focus-entered))

;; Producing auditory icons:
;; These dired commands do some action that causes a state change:
;; e.g. marking a file, and then change
;; the current selection, ie
;; move to the next line:
;; We speak the line moved to, and indicate the state change
;; with an auditory icon.

(defun emacsvox--advice-dired-mark-around (orig-fun &rest arguments)
  "Present the entry marked by Dired while preserving its next-row speech."
  (emacsvox-dired--marking-around
   orig-fun arguments 'dired-mark 'mark-object 'entry-marked 'marked))

(advice-add 'dired-mark :around
            #'emacsvox--advice-dired-mark-around)

(defun emacsvox--advice-dired-flag-file-deletion-around
    (orig-fun &rest arguments)
  "Present the Dired entry flagged for deletion and then the next row."
  (emacsvox-dired--marking-around
   orig-fun arguments 'dired-flag-file-deletion
   'delete-object 'entry-deletion-flagged 'deletion-flagged))

(advice-add 'dired-flag-file-deletion :around
            #'emacsvox--advice-dired-flag-file-deletion-around)

(defun emacsvox--advice-dired-unmark-around (orig-fun &rest arguments)
  "Present the entry unmarked by Dired and then the newly selected row."
  (emacsvox-dired--marking-around
   orig-fun arguments 'dired-unmark
   'deselect-object 'entry-unmarked))

(advice-add 'dired-unmark :around
            #'emacsvox--advice-dired-unmark-around)

;;;   labeling fields in the dired buffer:

(defun emacsvox-dired-label-fields-on-current-line ()
  "Labels the fields on a dired line.
Assumes that `dired-listing-switches' contains  -l"
  (let ((start nil)
        (fields (list "permissions"
                      "links"
                      "owner"
                      "group"
                      "size"
                      "modified in"
                      "modified on"
                      "modified at"
                      "name")))
    (save-excursion
      (forward-line 0)
      (skip-syntax-forward " ")
      (while (and fields
                  (not (eolp)))
        (setq start (point))
        (skip-syntax-forward "^ ")
        (put-text-property start (point)
                           'field-name (car fields))
        (setq fields (cdr fields))
        (skip-syntax-forward " ")))))

(defun emacsvox-dired-label-fields ()
  "Labels the fields of the listing in the dired buffer.
Currently is a no-op  unless
unless `dired-listing-switches' contains -l"
  (interactive)
  
  (when
      (save-match-data
        (string-match  "l" dired-listing-switches))
    (let ((read-only buffer-read-only))
      (unwind-protect
          (progn
            (setq buffer-read-only nil)
            (save-excursion
              (goto-char (point-min))
              (dired-goto-next-nontrivial-file)
              (while (not (eobp))
                (emacsvox-dired-label-fields-on-current-line)
                (forward-line 1))))
        (setq buffer-read-only read-only)))))

;;;  Additional status speaking commands

(defvar emacsvox-dired-file-cmd-options "-b"
  "Options passed to Unix builtin `file' command.")

(defun emacsvox-dired-show-file-type (&optional file deref-symlinks)
  "Displays type of current file by running command file.
Like Emacs' built-in dired-show-file-type but allows user to customize
options passed to command `file'."
  (interactive (list (dired-get-filename t) current-prefix-arg))
  (emacsvox-dired--call-with-aural-presentation
   (append
    (emacsvox-dired-entry-facts 'entry-inspected)
    '(:entry-inspection-kind file-type))
   'inspection
   (lambda ()
     (with-temp-buffer
       (if deref-symlinks
           (call-process "file" nil t t "-l"
                         emacsvox-dired-file-cmd-options file)
         (call-process "file" nil t t
                       emacsvox-dired-file-cmd-options file))
       (when (bolp)
         (delete-char -1))
       (message (buffer-string))))))

(defun emacsvox-dired-speak-header-line()
  "Speak the header line of the dired buffer. "
  (interactive)
  (emacsvox-dired--present-feedback
   '(:role filesystem-listing) 'inspection 'section
   (lambda ()
     (save-excursion
       (goto-char (point-min))
       (forward-line 2)
       (emacsvox-speak-region (point-min) (point))))))

(defun emacsvox-dired-speak-file-size ()
  "Speak the size of the current file.
On a directory line, run du -s on the directory to speak its size."
  (interactive)
  (let ((filename (dired-get-filename nil t))
        (size 0))
    (cond
     ((and filename
           (file-directory-p filename))
      (emacsvox-dired--present-feedback
       (emacsvox-dired-inspection-facts 'size)
       'inspection 'progress #'emacsvox-shell-command
       (format "du -s \"%s\"" filename)))
     (filename
      (setq size (nth 7 (file-attributes filename)))
                                        ; check for ange-ftp
      (when (= size -1)
        (setq size
              (nth  4
                    (split-string (ems--this-line)))))
      (emacsvox-dired--present-feedback
       (emacsvox-dired-inspection-facts 'size)
       'inspection 'select-object #'message
       "File size %s" size))
     (t (message "No file on current line")))))

(defun emacsvox-dired-speak-file-modification-time ()
  "Speak modification time  of the current file."
  (interactive)
  (let ((filename (dired-get-filename nil t)))
    (cond
     (filename
      (emacsvox-dired--present-feedback
       (emacsvox-dired-inspection-facts 'modification-time)
       'inspection 'select-object #'message
       "Modified on : %s"
       (format-time-string
        emacsvox-speak-time-format
        (nth 5 (file-attributes filename)))))
     (t (message "No file on current line")))))

(defun emacsvox-dired-speak-file-access-time ()
  "Speak access time  of the current file."
  (interactive)
  (let ((filename (dired-get-filename nil t)))
    (cond
     (filename
      (emacsvox-dired--present-feedback
       (emacsvox-dired-inspection-facts 'access-time)
       'inspection 'select-object #'message
       "Last accessed   on  %s"
       (format-time-string
        emacsvox-speak-time-format
        (nth 4 (file-attributes filename)))))
     (t (message "No file on current line")))))
(defun emacsvox-dired-speak-symlink-target ()
  "Speaks the target of the symlink on the current line."
  (interactive)
  (let ((filename (dired-get-filename nil t)))
    (cond
     (filename
      (emacsvox-dired--present-feedback
       (emacsvox-dired-inspection-facts 'symbolic-link-target)
       'inspection 'select-object
       (lambda ()
         (cond
          ((file-symlink-p filename)
           (message "Target is %s"
                    (file-chase-links filename)))
          (t (message "%s is not a symbolic link" filename))))))
     (t (message "No file on current line")))))
(defun emacsvox-dired-speak-file-permissions ()
  "Speak the permissions of the current file."
  (interactive)
  (let ((filename (dired-get-filename nil t)))
    (cond
     (filename
      (emacsvox-dired--present-feedback
       (emacsvox-dired-inspection-facts 'permissions)
       'inspection 'select-object #'message
       "Permissions %s" (nth 8 (file-attributes filename))))
     (t (message "No file on current line")))))

;;;   keys
(cl-eval-when (load))

(defun emacsvox-dired-setup-keys ()
  "Add emacsvox keys to dired."
  
  (define-key dired-mode-map "F" 'emacsvox-wizards-find-file-as-root)
  (define-key dired-mode-map "E" 'emacsvox-dired-epub-eww)
  (define-key dired-mode-map (kbd "C-j") 'emacsvox-dired-open-this-file)
  (define-key dired-mode-map (kbd "C-RET") 'emacsvox-dired-open-this-file)
  (define-key dired-mode-map [C-return] 'emacsvox-dired-open-this-file)
  (define-key dired-mode-map "'" 'emacsvox-dired-show-file-type)
  (define-key  dired-mode-map "/" 'emacsvox-dired-speak-file-permissions)
  (define-key  dired-mode-map ";" 'emacsvox-dired-play-duration)
  (define-key  dired-mode-map
               (kbd "M-;") 'emacsvox-m-player-add-dynamic)
  (define-key  dired-mode-map "a" 'emacsvox-dired-speak-file-access-time)
  (define-key dired-mode-map "c" 'emacsvox-dired-speak-file-modification-time)
  (define-key dired-mode-map "z" 'emacsvox-dired-speak-file-size)
  (define-key dired-mode-map "\M-t" 'emacsvox-dired-speak-symlink-target)
  (define-key dired-mode-map "\C-i" 'emacsvox-speak-next-field)
  (define-key dired-mode-map  "," 'emacsvox-dired-speak-header-line))

;;;  Advice locate:
(defun emacsvox-dired-open-this-directory ()
  "Open directory corresponding to file on current line."
  (interactive)
  (cl-assert (dired-get-filename) t "No file here.")
  (funcall-interactively
   #'dired (file-name-directory    (dired-get-filename))))

(emacsvox-dired--define-after-advice
    (locate locate-with-filter)
    "Speak the Locate results."
  (emacsvox-dired--call-with-aural-presentation
   '(:role filesystem-listing :events (entry-opened))
   'state-change
   (lambda ()
     (emacsvox-speak-line)
     (emacsvox-icon 'open-object))))
(load "locate" t t)

(cl-declaim (special locate-mode-map))
(define-key locate-mode-map  "j" 'emacsvox-dired-open-this-directory)
(define-key locate-mode-map  (kbd "C-j") 'emacsvox-dired-open-this-file)
(define-key locate-mode-map  [C-return] 'emacsvox-dired-open-this-file)

;;;  Context-sensitive openers:

(defun emacsvox-dired-play-this-media ()
  "Plays media on current line."
  (emacsvox-empv-play-file (dired-get-filename)))

(defun emacsvox-dired-play-this-playlist ()
  "Plays playlist on current line."
  (emacsvox-m-player (dired-get-filename) 'playlist))
(declare-function emacsvox-epub-eww "emacsvox-dired" t)

(defun emacsvox-dired-rpm-query-in-dired ()
  "Run rpm -qi on current dired entry."
  (interactive)
  
  (unless (eq major-mode 'dired-mode)
    (error "This command should be used in dired mode."))
  (let ((facts (emacsvox-dired-entry-facts 'entry-inspected)))
    (emacsvox-dired--call-with-aural-presentation
     facts 'inspection
     (lambda ()
       (shell-command
        (format "rpm -qi ` rpm -qf %s`"
                (dired-get-filename 'no-location)))
       (other-window 1)
       (search-forward "Summary" nil t)
       (emacsvox-speak-line)))))

(defconst emacsvox-dired-opener-table
  `(("\\.am$"  emacsvox-amark-file-load)
    ("\\.epub$"  emacsvox-dired-epub-eww)
    ("\\.rpm$" emacsvox-dired-rpm-query-in-dired)
    ("\\.mid$"  emacsvox-dired-midi-play)
    ("\\.xhtml" emacsvox-dired-eww-open)
    ("\\.html" emacsvox-dired-eww-open)
    ("\\.htm" emacsvox-dired-eww-open)
    ("\\.pdf" emacsvox-dired-pdf-open)
    ("\\.md" emacsvox-dired-md-open)
    ("\\.csv" emacsvox-dired-csv-open)
    (,emacsvox-media-extensions emacsvox-dired-play-this-media)
    (,emacsvox-playlist-pattern emacsvox-dired-play-this-playlist))
  "Association of filename extension patterns to Emacsvox handlers.")

(defun emacsvox-dired-open-this-file  ()
  "Smart dired opener. Invokes appropriate Emacsvox handler on
current file in DirEd."
  (interactive)
  (let* ((f (dired-get-filename nil t))
         (ext (file-name-extension f))
         (case-fold-search t)
         (handler nil))
    (unless f (error "No file here."))
    (unless ext (error "This entry has no extension."))
    (setq handler
          (cl-second
           (cl-find
            (format ".%s" ext)
            emacsvox-dired-opener-table
            :key #'car                  ; extract pattern from entry 
            :test #'(lambda (e pattern) (string-match  pattern e)))))
    (cond
     ((and handler (fboundp handler))
      (funcall-interactively handler))
     (t (call-interactively #'dired-find-file)))))

(defun emacsvox-dired-eww-open ()
  "Open HTML file on current dired line."
  (interactive)
  (eww-open-file (dired-get-filename)))
(declare-function markdown-preview "markdown-mode" (&optional output))
(defun emacsvox-dired-md-open ()
  "Preview markdown  file on current dired line."
  (interactive)
  (let ((buffer (find-file-noselect  (dired-get-filename))))
    (with-current-buffer buffer
      (markdown-preview))))

(declare-function emacsvox-wizards-pdf-open
                  "emacsvox-wizards" (filename &optional ask-pwd))

(defun emacsvox-dired-pdf-open ()
  "Open PDF file on current dired line."
  (interactive)
  (emacsvox-wizards-pdf-open (dired-get-filename current-prefix-arg)))

(defun emacsvox-dired-midi-play ()
  "Play midi  file on current dired line."
  (interactive)
  (emacsvox-wizards-midi-using-m-score
   (dired-get-filename current-prefix-arg)))

(defun emacsvox-dired-epub-eww ()
  "Open epub on current line  in EWW"
  (interactive)
  (let ((filename (dired-get-filename))
        (facts (emacsvox-dired-entry-facts 'entry-opened)))
    (emacsvox-dired--call-with-aural-presentation
     facts 'state-change
     (lambda ()
       (emacsvox-epub-eww (shell-quote-argument filename))
       (emacsvox-icon 'open-object)))))

(defun emacsvox-dired-csv-open ()
  "Open CSV file on current dired line."
  (interactive)
  (emacsvox-table-find-csv-file (dired-get-filename current-prefix-arg)))

;;;  Locate results as a play-list:

(defun emacsvox-locate-play-results-as-playlist (&optional shuffle)
  "Treat locate results as a play-list.
Optional interactive prefix arg shuffles playlist."
  (interactive "P")
  
  (cl-assert (eq major-mode 'locate-mode) t "Not in a locate buffer")
  (save-excursion
    (goto-char (point-min))
    (dired-next-line 3)
    (let* ((m3u (make-temp-file "locate-playlist" nil ".m3u"))
           (buff (find-file-noselect m3u))
           (results nil)
           (file (dired-file-name-at-point)))
      (while file
        (push file results)
        (dired-next-line 1)
        (setq file  (dired-file-name-at-point)))
      (setq results (nreverse results))
      (message "%s tracks matching " (length results))
      (with-current-buffer buff
        (cl-loop
         for f in results do
         (insert (format "%s\n" (expand-file-name f))))
        (save-buffer))
      (let ((emacsvox-m-player-options
             (if shuffle
                 (append emacsvox-m-player-options (list "-shuffle"))
               emacsvox-m-player-options)))
        (emacsvox-m-player  m3u 'play-list)))))

;;;  Play Duration Using Soxi:

(defun emacsvox-dired-play-duration ()
  "Speak duration of sound files.
If on a file, speak its duration.
If on a directory, speak the total duration of all sound files under
  that directory."
  (interactive)
  
  (cl-assert sox-soxi
             t "This command needs soxi installed.")
  (cl-assert (eq major-mode 'dired-mode)
             t "This command is only available in dired buffers.")
  (let ((f   (dired-get-filename))
        (case-fold-search t))
    (cond
     ((and (not (file-directory-p f))
           (string-match emacsvox-media-extensions f))
      (message "%s %s"
               (shell-command-to-string (format "soxi -d '%s'" f))
               (file-name-base f)))
     ((file-directory-p f)
      (message
       "%s in %s"
       (shell-command-to-string
        (format
         "find %s -name '*.mp3' -print0 | xargs -0 soxi -Td 2>/dev/null"
         (shell-quote-argument f)))
       (file-name-base f)))
     (t (message "No mp3  on current line.")))))

;;;  Open Downloads:

(defun emacsvox-dired-downloads ()
  "Open Downloads directory."
  (interactive)
  (funcall-interactively 'dired (expand-file-name "~/Downloads") "-alt"))

;;; Smarter replacement for find-dired wizard:

(defvar ems--find-switches
  '(
    "name" "iname" "path" "ipath" "regexp" "iregexp" "exec" "ok"
    "newer" "anewer" "cnewer" "used" "user" "uid" "nouser"
    "nogroup" "perm" "fstype" "lname" "ilname" "empty" "prune"
    "or" "not" "inum" "atime" "ctime" "mtime" "amin" "mmin"
    "cmin" "size" "type" "maxdepth" "mindepth" "mount" "noleaf" "xdev"
    )
  "Find switches")

;;;###autoload
(defun emacsvox-find-dired ()
  "Prompt for find-dired arguments using context and completion."
  (interactive)
  
  (let ((directory (read-directory-name "Directory:"))
        (f-args nil)
        (arg (completing-read "Switch:" ems--find-switches nil t)))
    (while (not (string= "" arg))
      (cl-pushnew (concat "-" arg) f-args :test #'string=)
      (cl-pushnew (read-string "Value:") f-args)
      (setq arg (completing-read "Switch:" ems--find-switches nil t)))
    (find-dired directory (mapconcat #'identity (nreverse f-args) " "))))

(provide 'emacsvox-dired)
;;;  emacs local variables
