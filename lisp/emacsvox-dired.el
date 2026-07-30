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
(require 'emacsvox-aural-submission)
(require 'emacsvox-aural-transport)
(require 'emacsvox-aural-provider-workflows)
(require 'dired)

;;;  Define personalities

(defconst emacsvox-dired--face-voice-map
  '((dired-broken-symlink voice-monotone-extra)
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
    (dired-flagged voice-animate-extra))
  "Voice personalities for the current Dired interface faces.")

(voice-setup-add-map emacsvox-dired--face-voice-map)

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

(defun emacsvox-dired--current-entry-content ()
  "Return voice-preserving speech content for the current Dired entry."
  (let ((filename
         (dired-get-filename (if (eq major-mode 'locate-mode) nil 'no-dir) t))
        (personality (tts-get-style)))
    (when filename
      (propertize filename 'personality personality))))

(defun emacsvox-dired--speak-line-compatibility ()
  "Speak the Dired line intelligently.
If in locate-mode, speak the full pathname."
  (if-let* ((content (emacsvox-dired--current-entry-content)))
      (progn
        (tts-speak content)
        (setq emacsvox-speak-last-spoken-word-position (point)))
    (emacsvox-speak-line)
    (ding)))

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
  (emacsvox-aural-call-with-submission
   function
   :facts (or facts '(:role filesystem-listing))
   :module 'dired
   :occasion (or occasion 'navigation)
   :arguments arguments))

(defun emacsvox-dired--present-feedback
    (facts occasion icon function &rest arguments)
  "Under FACTS and OCCASION, present ICON then call FUNCTION with ARGUMENTS."
  (emacsvox-dired--call-with-aural-presentation
   facts occasion
   (lambda ()
     (when icon (emacsvox-icon icon))
     (apply function arguments))))

(defun emacsvox-dired--submit-actions (facts occasion &rest icons)
  "Submit FACTS and compatibility ICONS as one action-only transaction."
  (emacsvox-aural-submit-actions
   :facts facts
   :module 'dired
   :occasion occasion
   :compatibility-actions
   (mapcar #'emacsvox-aural-compatibility-icon icons)))

(defun emacsvox-dired--submit-text
    (content facts occasion &optional icon icon-phase module)
  "Submit CONTENT under FACTS and OCCASION with optional compatibility ICON.
ICON-PHASE defaults to `before'.  MODULE defaults to `dired'."
  (if (and (stringp content) (> (length content) 0))
      (emacsvox-aural-submit
       content
       :facts facts
       :module (or module 'dired)
       :occasion occasion
       :compatibility-actions
       (when icon
         (list
          (emacsvox-aural-compatibility-icon icon icon-phase))))
    (when icon
      (emacsvox-dired--submit-actions facts occasion icon))))

(defun emacsvox-dired--submit-message
    (content facts occasion &optional icon)
  "Display and natively present CONTENT under FACTS and OCCASION.
Optional ICON precedes the spoken result.  Ordinary message speech is
suppressed because the aural submission owns audible presentation."
  (let ((emacsvox-speak-messages nil))
    (message "%s" content))
  (emacsvox-dired--submit-text content facts occasion icon))

(defun emacsvox-dired--buffer-summary ()
  "Return a concise voice-preserving summary of the selected Dired buffer."
  (concat
   (propertize (buffer-name) 'personality voice-lighten-medium)
   ", "
   (propertize
    (downcase
     (or
      (and (stringp mode-name) mode-name)
      (and (listp mode-name) (cl-find-if #'stringp mode-name))
      "Dired"))
    'personality voice-animate)))

(defun emacsvox-dired--line-content ()
  "Return the current line with speech-relevant properties intact."
  (concat
   (buffer-substring (line-beginning-position) (line-end-position))
   (ems--display-props-get)))

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
  (let ((facts (emacsvox-dired-entry-facts event)))
    (if speaker
        (emacsvox-dired--present-feedback
         facts occasion icon speaker)
      (if-let* ((content (emacsvox-dired--current-entry-content)))
          (prog1
              (emacsvox-aural-submit
               content
               :facts facts
               :module 'dired
               :occasion occasion
               :compatibility-actions
               ;; The Dired fragment owns marked-entry navigation cues.
               (when
                   (and
                    icon
                    (not (memq 'marked (plist-get facts :states))))
                 (list (emacsvox-aural-compatibility-icon icon))))
            (setq emacsvox-speak-last-spoken-word-position (point)))
        (emacsvox-dired--present-feedback
         facts occasion icon #'emacsvox-dired-speak-line)))))

(defun emacsvox-dired-inspection-facts (kind &optional failed)
  "Return current-entry facts for inspection KIND.
When FAILED is non-nil, include a failed-operation event."
  (append
   (emacsvox-dired-entry-facts)
   (list
    :events
    (if failed
        '(entry-inspected operation-failed)
      '(entry-inspected)))
   (list :entry-inspection-kind kind)))

(defun emacsvox-dired--present-inspection
    (kind content &optional icon failed)
  "Present CONTENT as entry inspection KIND.
ICON defaults to `select-object'.  FAILED marks unsuccessful inspection."
  (emacsvox-dired--submit-message
   content
   (emacsvox-dired-inspection-facts kind failed)
   'inspection
   (or icon 'select-object)))

(defun emacsvox-dired--present-missing-entry (kind)
  "Present a failed entry inspection of KIND at a non-entry row."
  (emacsvox-dired--present-inspection
   kind "No file on current line" 'warn-user t))

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
describe the entry at point before the command advances to the next row.
The next row is spoken before the action cue so its speech cannot cancel the
cue on single-stream speech servers."
  (if (ems-interactive-p target)
      (let* ((facts (emacsvox-dired-action-facts event state))
             (context
              (emacsvox-aural-capture-context 'dired 'state-change))
             (result (apply orig-fun arguments)))
        (emacsvox-dired-present-current
         nil 'navigation 'focus-entered)
        (let ((emacsvox-aural-submission-context context))
          (emacsvox-dired--present-feedback
           facts 'state-change icon #'ignore))
        result)
    (apply orig-fun arguments)))

(defun emacsvox--advice-dired-quit-window-around (orig-fun &rest arguments)
  "Call ORIG-FUN and report an interactive dismissal originating in Dired."
  (let* ((dired-p (derived-mode-p 'dired-mode))
         (interactive-p
          (and dired-p (ems-interactive-p 'quit-window)))
         (context
          (and
           interactive-p
           (emacsvox-aural-capture-context 'dired 'state-change)))
         (result (apply orig-fun arguments)))
    (when interactive-p
      (let ((emacsvox-aural-submission-context context))
        (emacsvox-dired--present-feedback
         '(:role filesystem-listing
           :events (filesystem-listing-closed))
         'state-change 'close-object #'emacsvox-speak-mode-line)))
    result))

(advice-add
 'quit-window :around
 #'emacsvox--advice-dired-quit-window-around
 '((name . emacsvox-dired)))

;;;   advice:

(defun emacsvox--advice-dired-sort-toggle-or-edit-around
    (orig-fun &rest args)
  "Present the updated Dired sort state."
  (if (ems-interactive-p 'dired-sort-toggle-or-edit)
      (let (result)
        (ems-with-messages-silenced
          (setq result (apply orig-fun args)))
        (emacsvox-dired--submit-text
         (emacsvox-dired--buffer-summary)
         (emacsvox-dired-operation-facts 'sort)
         'state-change 'task-done)
        result)
    (apply orig-fun args)))

(advice-add 'dired-sort-toggle-or-edit :around
            #'emacsvox--advice-dired-sort-toggle-or-edit-around)

(defun emacsvox-dired--new-current-message (prior-message)
  "Return a non-empty current message different from PRIOR-MESSAGE."
  (let ((current (current-message)))
    (and
     (stringp current)
     (not (string-empty-p current))
     (not (equal current prior-message))
     current)))

(defun emacsvox-dired-operation-facts (operation &optional failed)
  "Return facts for filesystem OPERATION.
When FAILED is non-nil, describe an unsuccessful operation."
  (list
   :role 'filesystem-operation
   :filesystem-operation-kind operation
   :events (list (if failed 'operation-failed 'operation-completed))))

(defun emacsvox-dired--failed-result-message-p (text)
  "Return non-nil when Dired result TEXT describes failure or cancellation."
  (and
   (stringp text)
   (string-match-p
    (rx word-start
        (or (seq "cancel" (* alpha)) "error" "failed" "failure"
            (seq "no" (+ space) (*? anychar) "requested"))
        word-end)
    (downcase text))))

(defun emacsvox-dired--operation-around
    (orig-fun arguments target operation icon fallback)
  "Call ORIG-FUN with ARGUMENTS and present a Dired operation result.
TARGET restricts feedback to the matching interactive command.  OPERATION
identifies the semantic operation, ICON indicates success, and FALLBACK is
spoken when Dired did not produce a new result message."
  (if (ems-interactive-p target)
      (let* ((prior-message (current-message))
             (context
              (emacsvox-aural-capture-context 'dired 'state-change))
             result text failed)
        (let ((emacsvox-speak-messages nil))
          (setq result (apply orig-fun arguments)))
        (setq
         text (or (emacsvox-dired--new-current-message prior-message)
                  fallback)
         failed (emacsvox-dired--failed-result-message-p text))
        (let ((emacsvox-aural-submission-context context))
          (emacsvox-dired--submit-message
           text
           (emacsvox-dired-operation-facts operation failed)
           'state-change
           (if failed 'warn-user icon)))
        result)
    (apply orig-fun arguments)))

(defmacro emacsvox-dired--define-operation-advice (&rest specifications)
  "Define Dired operation advice from SPECIFICATIONS.
Each specification has the form (TARGET OPERATION ICON FALLBACK)."
  (declare (indent 0) (debug (&rest (symbolp symbolp symbolp stringp))))
  `(progn
     ,@(mapcar
        (lambda (specification)
          (pcase-let*
              ((`(,target ,operation ,icon ,fallback) specification)
               (function
                (intern (format "emacsvox--dired-%s-around" target))))
            `(progn
               (defun ,function (orig-fun &rest arguments)
                 ,(format "Present interactive `%s' feedback." target)
                 (emacsvox-dired--operation-around
                  orig-fun arguments ',target ',operation ',icon ,fallback))
               (advice-add
                ',target :around #',function '((name . emacsvox))))))
        specifications)))

(emacsvox-dired--define-operation-advice
  (dired-create-directory create-directory save-object "Directory created")
  (dired-create-empty-file create-file save-object "File created")
  (dired-do-copy copy save-object "Copy completed")
  (dired-do-copy-regexp copy-regexp save-object "Regexp copy completed")
  (dired-do-rename rename task-done "Rename completed")
  (dired-do-rename-regexp rename-regexp task-done
                          "Regexp rename completed")
  (dired-do-delete delete delete-object "Deletion completed")
  (dired-do-flagged-delete delete-flagged delete-object
                           "Flagged deletion completed")
  (dired-do-symlink create-symbolic-link save-object
                    "Symbolic link created")
  (dired-do-symlink-regexp create-symbolic-link-regexp save-object
                           "Regexp symbolic links created")
  (dired-do-relsymlink create-relative-symbolic-link save-object
                       "Relative symbolic link created")
  (dired-do-relsymlink-regexp create-relative-symbolic-link-regexp
                              save-object
                              "Regexp relative symbolic links created")
  (dired-do-hardlink create-hard-link save-object "Hard link created")
  (dired-do-hardlink-regexp create-hard-link-regexp save-object
                            "Regexp hard links created")
  (dired-do-compress compress save-object "Compression completed")
  (dired-do-compress-to compress-to save-object "Compression completed")
  (dired-do-chmod change-mode task-done "File mode changed")
  (dired-do-chown change-owner task-done "File owner changed")
  (dired-do-chgrp change-group task-done "File group changed")
  (dired-do-touch change-time task-done "File timestamp changed")
  (dired-downcase downcase-name task-done "File names downcased")
  (dired-upcase upcase-name task-done "File names upcased"))

(emacsvox-dired--define-operation-advice
  (dired-toggle-marks toggle-marks mark-object "Marks toggled")
  (dired-unmark-all-files clear-marks deselect-object "Marks cleared")
  (dired-unmark-all-marks clear-marks deselect-object "Marks cleared")
  (dired-change-marks change-marks mark-object "Marks changed")
  (dired-mark-directories mark-directories mark-object
                          "Directories marked")
  (dired-mark-executables mark-executables mark-object
                          "Executable files marked")
  (dired-mark-files-containing-regexp mark-containing mark-object
                                      "Matching files marked")
  (dired-mark-files-regexp mark-regexp mark-object "Matching files marked")
  (dired-mark-subdir-files mark-subdirectory mark-object
                           "Subdirectory files marked")
  (dired-mark-symlinks mark-symbolic-links mark-object
                       "Symbolic links marked")
  (dired-flag-auto-save-files flag-auto-save-files delete-object
                              "Auto-save files flagged")
  (dired-flag-backup-files flag-backup-files delete-object
                           "Backup files flagged")
  (dired-flag-files-regexp flag-regexp delete-object
                           "Matching files flagged")
  (dired-flag-garbage-files flag-garbage-files delete-object
                            "Garbage files flagged")
  (dired-clean-directory clean-directory delete-object
                         "Old versions flagged")
  (dired-copy-filename-as-kill copy-filenames mark-object
                               "File names copied")
  (dired-do-kill-lines hide-entries close-object "Entries hidden")
  (dired-do-redisplay redisplay task-done "Entries redisplayed")
  (dired-undo undo task-done "Dired change undone"))

(defun emacsvox-dired--marked-files-summary ()
  "Return Dired's count and total-size summary for marked files."
  (let* ((files (dired-get-marked-files nil nil nil t))
         (count
          (cond
           ((null (cdr files)) 0)
           ((and (= (length files) 2) (eq (car files) t)) 1)
           (t (length files))))
         (size
          (cl-loop
           for file in files
           when (stringp file)
           sum (file-attribute-size (file-attributes file)))))
    (if (zerop count)
        "No marked files"
      (format
       "%d marked file%s (%s total size)"
       count
       (if (= count 1) "" "s")
       (funcall byte-count-to-string-function size)))))

(defun emacsvox--advice-dired-number-of-marked-files-around
    (orig-fun &rest arguments)
  "Present an interactive summary of marked Dired files."
  (if (ems-interactive-p 'dired-number-of-marked-files)
      (let ((context
             (emacsvox-aural-capture-context 'dired 'inspection))
            result)
        (let ((emacsvox-speak-messages nil))
          (setq result (apply orig-fun arguments)))
        (let ((emacsvox-aural-submission-context context))
          (emacsvox-dired--submit-message
           (emacsvox-dired--marked-files-summary)
           '(:role filesystem-listing
             :events (entry-inspected)
             :entry-inspection-kind marked-summary)
           'inspection 'select-object))
        result)
    (apply orig-fun arguments)))

(advice-add
 'dired-number-of-marked-files :around
 #'emacsvox--advice-dired-number-of-marked-files-around
 '((name . emacsvox)))

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
  (emacsvox-dired--submit-text
   (emacsvox-dired--buffer-summary)
   '(:role filesystem-listing
     :events (filesystem-listing-opened))
   'state-change 'open-object))

(defun emacsvox-dired--opened-destination-buffer (result filename)
  "Return the destination buffer represented by RESULT and FILENAME."
  (cond
   ((bufferp result) result)
   ((windowp result) (window-buffer result))
   ((and filename (get-file-buffer filename)))
   ((buffer-live-p (current-buffer)) (current-buffer))))

(defun emacsvox-dired--present-opened-destination
    (destination source-buffer directory-p source-facts)
  "Present DESTINATION after opening an entry from SOURCE-BUFFER.
DIRECTORY-P distinguishes directory listings from ordinary files, and
SOURCE-FACTS preserve the selected Dired entry."
  (if
      (and
       directory-p
       (buffer-live-p source-buffer)
       (eq destination source-buffer))
      (with-current-buffer source-buffer
        (emacsvox-dired-present-current
         'large-movement 'navigation 'focus-entered))
    (when (buffer-live-p destination)
      (with-current-buffer destination
        (when (derived-mode-p 'dired-mode)
          (emacsvox-dired-label-fields))
        (emacsvox-dired--submit-text
         (emacsvox-dired--buffer-summary)
         (if directory-p
             '(:role filesystem-listing
               :events (filesystem-listing-opened))
           source-facts)
         'state-change 'open-object nil
         (or emacsvox-aural-module 'dired))))))

(defun emacsvox-dired--open-around
    (orig-fun arguments target)
  "Call ORIG-FUN with ARGUMENTS and present TARGET's opened destination."
  (if (ems-interactive-p target)
      (let* ((source-buffer (current-buffer))
             (filename (dired-get-file-for-visit))
             (directory-p (file-directory-p filename))
             (facts (emacsvox-dired-entry-facts 'entry-opened))
             (result (apply orig-fun arguments))
             (destination
              (emacsvox-dired--opened-destination-buffer result filename)))
        (emacsvox-dired--present-opened-destination
         destination source-buffer directory-p facts)
        result)
    (apply orig-fun arguments)))

(defmacro emacsvox-dired--define-open-advice (&rest targets)
  "Define destination-aware Dired opening advice for TARGETS."
  (declare (indent 0) (debug (&rest symbolp)))
  `(progn
     ,@(mapcar
        (lambda (target)
          (let ((function
                 (intern (format "emacsvox--advice-%s-around" target))))
            `(progn
               (defun ,function (orig-fun &rest arguments)
                 ,(format "Present the destination opened by `%s'." target)
                 (emacsvox-dired--open-around
                  orig-fun arguments ',target))
               (advice-add
                ',target :around #',function '((name . emacsvox))))))
        targets)))

(emacsvox-dired--define-open-advice
  dired-find-file
  dired-find-alternate-file
  dired-find-file-other-window
  dired-display-file
  dired-view-file)

(defun emacsvox-dired--present-listing-visibility
    (aspect visibility text)
  "Present TEXT after listing ASPECT changes to VISIBILITY."
  (emacsvox-dired--submit-text
   text
   (list
    :role 'filesystem-listing
    :events '(visibility-changed)
    :visibility visibility
    :filesystem-listing-aspect aspect)
   'state-change
   (if (eq visibility 'folded) 'close-object 'open-object)))

(defun emacsvox--advice-dired-hide-details-mode-around
    (orig-fun &rest arguments)
  "Present interactive changes to Dired detail visibility."
  (if (ems-interactive-p 'dired-hide-details-mode)
      (let ((result (apply orig-fun arguments)))
        (emacsvox-dired--present-listing-visibility
         'details
         (if dired-hide-details-mode 'folded 'expanded)
         (if dired-hide-details-mode
             "File details hidden"
           "File details shown"))
        result)
    (apply orig-fun arguments)))

(advice-add
 'dired-hide-details-mode :around
 #'emacsvox--advice-dired-hide-details-mode-around
 '((name . emacsvox)))

(defun emacsvox--advice-dired-hide-subdir-around
    (orig-fun &rest arguments)
  "Present interactive changes to one Dired subdirectory's visibility."
  (if (ems-interactive-p 'dired-hide-subdir)
      (let* ((directory (dired-current-directory))
             (hidden-before (dired-subdir-hidden-p directory))
             (context
              (emacsvox-aural-capture-context 'dired 'state-change))
             (result (apply orig-fun arguments))
             (visibility (if hidden-before 'expanded 'folded)))
        (let ((emacsvox-aural-submission-context context))
          (emacsvox-dired--present-listing-visibility
           'subdirectory visibility
           (format
            "Subdirectory %s %s"
            (file-name-nondirectory (directory-file-name directory))
            (if (eq visibility 'folded) "hidden" "shown"))))
        result)
    (apply orig-fun arguments)))

(advice-add
 'dired-hide-subdir :around
 #'emacsvox--advice-dired-hide-subdir-around
 '((name . emacsvox)))

(defun emacsvox--advice-dired-hide-all-around
    (orig-fun &rest arguments)
  "Present interactive changes to all Dired subdirectory visibility."
  (if (ems-interactive-p 'dired-hide-all)
      (let* ((hidden-before
              (text-property-any
               (point-min) (point-max) 'invisible 'dired))
             (result (apply orig-fun arguments))
             (visibility (if hidden-before 'expanded 'folded)))
        (emacsvox-dired--present-listing-visibility
         'all-subdirectories visibility
         (if (eq visibility 'folded)
             "All subdirectories hidden"
           "All subdirectories shown"))
        result)
    (apply orig-fun arguments)))

(advice-add
 'dired-hide-all :around
 #'emacsvox--advice-dired-hide-all-around
 '((name . emacsvox)))

(defun emacsvox--advice-dired-revert-buffer-around
    (orig-fun &rest arguments)
  "Present an interactive Dired listing refresh."
  (if
      (and
       (derived-mode-p 'dired-mode)
       (ems-interactive-p 'revert-buffer))
      (let ((result
             (let ((emacsvox-speak-messages nil))
               (apply orig-fun arguments))))
        (emacsvox-dired-label-fields)
        (emacsvox-dired--submit-text
         (emacsvox-dired--buffer-summary)
         (emacsvox-dired-operation-facts 'refresh)
         'state-change 'task-done)
        result)
    (apply orig-fun arguments)))

(advice-add
 'revert-buffer :around
 #'emacsvox--advice-dired-revert-buffer-around
 '((name . emacsvox-dired)))

(emacsvox-dired--define-after-advice
    (dired-next-subdir dired-prev-subdir
     dired-tree-up dired-tree-down dired-up-directory
     dired-goto-file dired-goto-subdir
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
  (let (status output)
    (with-temp-buffer
      (let ((arguments
             (append
              (and deref-symlinks '("-L"))
              (split-string-and-unquote emacsvox-dired-file-cmd-options)
              (list "--" file))))
        (setq
         status (apply #'call-process "file" nil t nil arguments)
         output (string-trim-right (buffer-string)))))
    (if (and (integerp status) (zerop status))
        (emacsvox-dired--present-inspection 'file-type output)
      (emacsvox-dired--present-inspection
       'file-type
       (if (string-empty-p output)
           (format "Could not determine file type for %s" file)
         output)
       'warn-user t))))

(defun emacsvox-dired-speak-header-line()
  "Speak the header line of the dired buffer. "
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (forward-line 2)
    (emacsvox-dired--submit-text
     (string-trim-right
      (buffer-substring (point-min) (point)))
     '(:role filesystem-listing
       :events (entry-inspected)
       :entry-inspection-kind header)
     'inspection 'section)))

(defun emacsvox-dired-speak-file-size ()
  "Speak the size of the current file.
On a directory line, run du -s on the directory to speak its size."
  (interactive)
  (let ((filename (dired-get-filename nil t))
        (size 0))
    (cond
     ((and filename
           (file-directory-p filename))
      (emacsvox-dired--submit-actions
       (emacsvox-dired-inspection-facts 'size)
       'inspection 'progress)
      (let (status output)
        (with-temp-buffer
          (setq
           status (call-process "du" nil t nil "-s" "--" filename)
           output (string-trim-right (buffer-string))))
        (emacsvox-dired--present-inspection
         'size
         (if (and (integerp status) (zerop status))
             output
           (format "Could not determine directory size for %s" filename))
         (if (and (integerp status) (zerop status))
             'select-object
           'warn-user)
         (not (and (integerp status) (zerop status))))))
     (filename
      (setq size (nth 7 (file-attributes filename)))
                                        ; check for ange-ftp
      (when (= size -1)
        (setq size
              (nth  4
                    (split-string (ems--this-line)))))
      (emacsvox-dired--present-inspection
       'size (format "File size %s" size)))
     (t (emacsvox-dired--present-missing-entry 'size)))))

(defun emacsvox-dired-speak-file-modification-time ()
  "Speak modification time  of the current file."
  (interactive)
  (let ((filename (dired-get-filename nil t)))
    (cond
     (filename
      (emacsvox-dired--present-inspection
       'modification-time
       (format
        "Modified on: %s"
        (format-time-string
         emacsvox-speak-time-format
         (nth 5 (file-attributes filename))))))
     (t (emacsvox-dired--present-missing-entry 'modification-time)))))

(defun emacsvox-dired-speak-file-access-time ()
  "Speak access time  of the current file."
  (interactive)
  (let ((filename (dired-get-filename nil t)))
    (cond
     (filename
      (emacsvox-dired--present-inspection
       'access-time
       (format
        "Last accessed on %s"
        (format-time-string
         emacsvox-speak-time-format
         (nth 4 (file-attributes filename))))))
     (t (emacsvox-dired--present-missing-entry 'access-time)))))

(defun emacsvox-dired-speak-symlink-target ()
  "Speaks the target of the symlink on the current line."
  (interactive)
  (let ((filename (dired-get-filename nil t)))
    (cond
     (filename
      (if (file-symlink-p filename)
          (emacsvox-dired--present-inspection
           'symbolic-link-target
           (format "Target is %s" (file-chase-links filename)))
        (emacsvox-dired--present-inspection
         'symbolic-link-target
         (format "%s is not a symbolic link" filename)
         'warn-user t)))
     (t
      (emacsvox-dired--present-missing-entry 'symbolic-link-target)))))

(defun emacsvox-dired-speak-file-permissions ()
  "Speak the permissions of the current file."
  (interactive)
  (let ((filename (dired-get-filename nil t)))
    (cond
     (filename
      (emacsvox-dired--present-inspection
       'permissions
       (format "Permissions %s" (nth 8 (file-attributes filename)))))
     (t (emacsvox-dired--present-missing-entry 'permissions)))))

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
  (emacsvox-dired--submit-text
   (emacsvox-dired--line-content)
   '(:role filesystem-listing
     :events (filesystem-listing-opened))
   'state-change 'open-object 'after))
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
