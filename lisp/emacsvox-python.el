;;; emacsvox-python.el --- Speech enable Python -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description: Auditory interface to python mode
;; Keywords: Emacsvox, Speak, Spoken Output, python
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


;;; Commentary:

;; This speech-enables python-mode bundled with Emacs

;;; Code:

;;   Required modules:
(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'emacsvox-aural-submission)
(require 'emacsvox-aural-transport)
(require 'emacsvox-aural-provider-workflows)

(require 'python "python" 'no-error)

;;;  Semantic aural presentation:

(defun emacsvox-python-enable-aural-context ()
  "Identify the current Python buffer to aural presentation schemes."
  (setq-local emacsvox-aural-module 'python))

(add-hook 'python-mode-hook #'emacsvox-python-enable-aural-context)

(defun emacsvox-python-navigation-facts (target)
  "Return semantic navigation facts for Python command TARGET."
  (let* ((name (symbol-name target))
         (syntax-role
          (cond
           ((string-match-p "defun" name) 'function)
           ((string-match-p "block" name) 'block)
           ((string-match-p "statement" name) 'statement)
           ((string-match-p "sexp\\|list" name) 'expression)
           ((string-match-p "if-name-main" name) 'main-guard)
           (t 'construct))))
    (list
     :role 'code-construct
     :events '(boundary-entered focus-entered)
     :syntax-role syntax-role)))

(defun emacsvox-python--edit-facts (kind &optional syntax-role)
  "Return semantic facts for Python edit KIND and optional SYNTAX-ROLE."
  (list
   :role 'code-construct
   :events '(object-changed)
   :syntax-role (or syntax-role 'construct)
   :code-edit-kind kind))

(defun emacsvox-python--operation-facts (target outcome)
  "Return facts for Python operation TARGET with OUTCOME.
OUTCOME is `started', `completed', or `failed'."
  (list
   :role 'code-operation
   :events
   (list
    (pcase outcome
      ('started 'operation-started)
      ('completed 'operation-completed)
      (_ 'operation-failed)))
   :code-operation-kind target))

(defun emacsvox-python--submit-actions (facts occasion)
  "Submit Python FACTS under OCCASION without spoken content."
  (emacsvox-aural-submit-actions
   :facts facts :module 'python :occasion occasion))

(defun emacsvox-python--submit-text (text facts occasion)
  "Submit Python TEXT under FACTS and OCCASION."
  (emacsvox-aural-submit
   text
   :facts facts
   :module 'python
   :occasion occasion))

(defun emacsvox-python--submit-message (text facts occasion)
  "Display and natively present Python TEXT under FACTS and OCCASION."
  (let ((emacsvox-speak-messages nil))
    (message "%s" text))
  (emacsvox-python--submit-text text facts occasion))

(defun emacsvox-python--remove-captured-source-icon
    (content icon source-offset source-length)
  "Return CONTENT without the ICON already captured at SOURCE-OFFSET.
SOURCE-LENGTH is the unprefixed source-line length.  Other text properties and
other auditory icons are preserved."
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

(defun emacsvox-python--present-current-line (facts occasion)
  "Present the current line as one Python transaction.
FACTS and OCCASION describe the selected construct.  Structural line cues
are captured as compatibility actions instead of resolving independently."
  (let* ((source-icon (get-char-property (point) 'auditory-icon))
         (source-offset (- (point) (line-beginning-position)))
         (source-length
          (- (line-end-position) (line-beginning-position)))
         (context (emacsvox-aural-capture-context 'python occasion))
         (submit-actions
          (symbol-function 'emacsvox-aural-submit-actions))
         icons
         submitted)
    (let ((emacsvox-aural-submission-facts facts)
          (emacsvox-aural-submission-context context)
          (emacsvox-aural-submission-module 'python)
          (emacsvox-aural-submission-occasion occasion))
      (cl-letf
          (((symbol-function 'emacsvox-icon)
            (lambda (icon)
              (setq icons (append icons (list icon)))))
           ((symbol-function 'emacsvox-aural-submit-actions)
            (lambda (&rest arguments)
              (setq submitted t)
              (apply
               submit-actions
               (plist-put
                arguments :compatibility-actions
                (append
                 (mapcar #'emacsvox-aural-compatibility-icon icons)
                 (plist-get arguments :compatibility-actions)))))))
        (emacsvox-speak-line-with-speaker
         (lambda (content)
           (setq submitted t)
           (emacsvox-aural-submit
            (emacsvox-python--remove-captured-source-icon
             content source-icon source-offset source-length)
            :facts facts
            :context context
            :module 'python
            :occasion occasion
            :compatibility-actions
            (mapcar #'emacsvox-aural-compatibility-icon icons))))))
    (unless submitted
      (emacsvox-aural-submit-actions
       :facts facts
       :context context
       :module 'python
       :occasion occasion
       :compatibility-actions
       (mapcar #'emacsvox-aural-compatibility-icon icons)))))

;;;  interactive programming

(defun emacsvox-python--operation-started (target)
  "Present TARGET as started when it is the interactive Python command."
  (when (ems-interactive-p target)
    (emacsvox-python--submit-actions
     (emacsvox-python--operation-facts target 'started)
     'state-change)))

(defun emacsvox--advice-python-check-after (&rest _)
  "Report starting an interactive asynchronous Python check."
  (emacsvox-python--operation-started 'python-check))

(advice-add 'python-check :after
            #'emacsvox--advice-python-check-after)

(defun emacsvox--advice-python-shell-send-region-after (&rest _)
  "Report submitting a region to an inferior Python process."
  (emacsvox-python--operation-started 'python-shell-send-region))

(advice-add 'python-shell-send-region :after
            #'emacsvox--advice-python-shell-send-region-after)

(defun emacsvox--advice-python-shell-send-defun-after (&rest _)
  "Report submitting a defun to an inferior Python process."
  (emacsvox-python--operation-started 'python-shell-send-defun))

(advice-add 'python-shell-send-defun :after
            #'emacsvox--advice-python-shell-send-defun-after)

(defun emacsvox--advice-python-shell-send-file-after (&rest _)
  "Report submitting a file to an inferior Python process."
  (emacsvox-python--operation-started 'python-shell-send-file))

(advice-add 'python-shell-send-file :after
            #'emacsvox--advice-python-shell-send-file-after)

(defun emacsvox--advice-python-shell-send-buffer-after (&rest _)
  "Report submitting a buffer to an inferior Python process."
  (emacsvox-python--operation-started 'python-shell-send-buffer))

(advice-add 'python-shell-send-buffer :after
            #'emacsvox--advice-python-shell-send-buffer-after)

(defun emacsvox--advice-python-shell-send-string-after (&rest _)
  "Report submitting a string to an inferior Python process."
  (emacsvox-python--operation-started 'python-shell-send-string))

(advice-add 'python-shell-send-string :after
            #'emacsvox--advice-python-shell-send-string-after)

;;;   whitespace management and indentation

(defun emacsvox--advice-python-indent-dedent-line-around
    (orig-fun &rest arguments)
  "Present the result of interactively dedenting the current line."
  (if (ems-interactive-p 'python-indent-dedent-line)
      (let ((result (apply orig-fun arguments)))
        (if result
            (emacsvox-python--present-current-line
             (emacsvox-python--edit-facts 'dedent-line 'indentation)
             'edit)
          (emacsvox-python--submit-message
           "Line indentation unchanged"
           (emacsvox-python--operation-facts 'dedent-line 'failed)
           'state-change))
        result)
    (apply orig-fun arguments)))

(advice-add 'python-indent-dedent-line :around
            #'emacsvox--advice-python-indent-dedent-line-around)

(defun emacsvox--advice-python-indent-dedent-line-backspace-around
    (orig-fun arg)
  "Speak character you're deleting."
  (if (ems-interactive-p 'python-indent-dedent-line-backspace)
      (let* ((selection-p (use-region-p))
             (character
              (and
               (not selection-p)
               (> (point) (point-min))
               (preceding-char)))
             (whitespace-p
              (and character (= 32 (char-syntax character))))
             (result (funcall orig-fun arg))
             (kind (if selection-p 'delete-selection 'delete-character))
             (text
              (cond
               (selection-p "Deleted selection")
               (whitespace-p (format "Indent %s" (current-column)))
               ((and (integerp arg) (> (abs arg) 1))
                (format "Deleted %d characters" (abs arg)))
               (character
                (or (tts-char-to-speech character)
                    (char-to-string character)))
               (t "Deleted character"))))
        (emacsvox-python--submit-text
         text
         (append
          (emacsvox-python--edit-facts kind 'character)
          '(:edit-operation deletion))
         'edit)
        result)
    (funcall orig-fun arg)))

(advice-add 'python-indent-dedent-line-backspace :around
            #'emacsvox--advice-python-indent-dedent-line-backspace-around)

(defun emacsvox--advice-python-fill-paragraph-after (&rest _)
  "Cue an interactive paragraph fill."
  (when (ems-interactive-p 'python-fill-paragraph)
    (emacsvox-python--submit-actions
     (emacsvox-python--edit-facts 'fill-paragraph 'paragraph)
     'edit)))

(advice-add 'python-fill-paragraph :after
            #'emacsvox--advice-python-fill-paragraph-after)

(defun emacsvox--advice-python-indent-shift-left-after
    (start end &rest _)
  "Speak number of lines that were shifted"
  (when (ems-interactive-p 'python-indent-shift-left)
    (emacsvox-python--submit-text
     (format "Left shifted block  containing %s lines"
             (count-lines start end))
     (emacsvox-python--edit-facts 'shift-left 'block)
     'edit)))

(advice-add 'python-indent-shift-left :after
            #'emacsvox--advice-python-indent-shift-left-after)

(defun emacsvox--advice-python-indent-shift-right-after
    (start end &rest _)
  "Speak number of lines that were shifted"
  (when (ems-interactive-p 'python-indent-shift-right)
    (emacsvox-python--submit-text
     (format "Right shifted block  containing %s lines"
             (count-lines start end))
     (emacsvox-python--edit-facts 'shift-right 'block)
     'edit)))

(advice-add 'python-indent-shift-right :after
            #'emacsvox--advice-python-indent-shift-right-after)

(defun emacsvox--advice-python-indent-region-after (start end)
  "Speak number of lines that were shifted"
  (when (ems-interactive-p 'indent-region)
    (emacsvox-python--submit-text
     (format "Indented region   containing %s lines"
             (count-lines start end))
     (emacsvox-python--edit-facts 'indent-region 'block)
     'edit)))

(advice-add 'python-indent-region :after
            #'emacsvox--advice-python-indent-region-after)

;;;   buffer navigation

(defun emacsvox--advice-python-mark-defun-after (&rest _)
  "Present the function selected by an interactive mark command."
  (when (ems-interactive-p 'python-mark-defun)
    (emacsvox-python--submit-message
     (format
      "Marked function containing %s lines"
      (count-lines (point) (mark 'force)))
     '(:role code-construct
       :events (code-selection-created)
       :syntax-role function)
     'state-change)))

(advice-add 'python-mark-defun :after
            #'emacsvox--advice-python-mark-defun-after)

(defun emacsvox-python--navigation-feedback (target)
  "Speak the current line when TARGET is the interactive command."
  (when (ems-interactive-p target)
    (emacsvox-python--present-current-line
     (emacsvox-python-navigation-facts target)
     'navigation)))

(defun emacsvox--advice-python-nav-up-list-after (&rest _)
  "Speak after navigating up a list."
  (emacsvox-python--navigation-feedback 'python-nav-up-list))

(advice-add 'python-nav-up-list :after
            #'emacsvox--advice-python-nav-up-list-after)

(defun emacsvox--advice-python-nav-if-name-main-after (&rest _)
  "Speak after navigating to the main guard."
  (emacsvox-python--navigation-feedback 'python-nav-if-name-main))

(advice-add 'python-nav-if-name-main :after
            #'emacsvox--advice-python-nav-if-name-main-after)

(defun emacsvox--advice-python-nav-forward-statement-after (&rest _)
  "Speak after navigating forward by statement."
  (emacsvox-python--navigation-feedback 'python-nav-forward-statement))

(advice-add 'python-nav-forward-statement :after
            #'emacsvox--advice-python-nav-forward-statement-after)

(defun emacsvox--advice-python-nav-forward-sexp-safe-after (&rest _)
  "Speak after safe forward expression navigation."
  (emacsvox-python--navigation-feedback 'python-nav-forward-sexp-safe))

(advice-add 'python-nav-forward-sexp-safe :after
            #'emacsvox--advice-python-nav-forward-sexp-safe-after)

(defun emacsvox--advice-python-nav-forward-sexp-after (&rest _)
  "Speak after forward expression navigation."
  (emacsvox-python--navigation-feedback 'python-nav-forward-sexp))

(advice-add 'python-nav-forward-sexp :after
            #'emacsvox--advice-python-nav-forward-sexp-after)

(defun emacsvox--advice-python-nav-forward-defun-after (&rest _)
  "Speak after forward defun navigation."
  (emacsvox-python--navigation-feedback 'python-nav-forward-defun))

(advice-add 'python-nav-forward-defun :after
            #'emacsvox--advice-python-nav-forward-defun-after)

(defun emacsvox--advice-python-nav-forward-block-after (&rest _)
  "Speak after forward block navigation."
  (emacsvox-python--navigation-feedback 'python-nav-forward-block))

(advice-add 'python-nav-forward-block :after
            #'emacsvox--advice-python-nav-forward-block-after)

(defun emacsvox--advice-python-nav-end-of-statement-after (&rest _)
  "Speak after moving to the end of a statement."
  (emacsvox-python--navigation-feedback 'python-nav-end-of-statement))

(advice-add 'python-nav-end-of-statement :after
            #'emacsvox--advice-python-nav-end-of-statement-after)

(defun emacsvox--advice-python-nav-end-of-defun-after (&rest _)
  "Speak after moving to the end of a defun."
  (emacsvox-python--navigation-feedback 'python-nav-end-of-defun))

(advice-add 'python-nav-end-of-defun :after
            #'emacsvox--advice-python-nav-end-of-defun-after)

(defun emacsvox--advice-python-nav-end-of-block-after (&rest _)
  "Speak after moving to the end of a block."
  (emacsvox-python--navigation-feedback 'python-nav-end-of-block))

(advice-add 'python-nav-end-of-block :after
            #'emacsvox--advice-python-nav-end-of-block-after)

(defun emacsvox--advice-python-nav-beginning-of-statement-after (&rest _)
  "Speak after moving to the beginning of a statement."
  (emacsvox-python--navigation-feedback 'python-nav-beginning-of-statement))

(advice-add 'python-nav-beginning-of-statement :after
            #'emacsvox--advice-python-nav-beginning-of-statement-after)

(defun emacsvox--advice-python-nav-beginning-of-block-after (&rest _)
  "Speak after moving to the beginning of a block."
  (emacsvox-python--navigation-feedback 'python-nav-beginning-of-block))

(advice-add 'python-nav-beginning-of-block :after
            #'emacsvox--advice-python-nav-beginning-of-block-after)

(defun emacsvox--advice-python-nav-backward-up-list-after (&rest _)
  "Speak after navigating backward up a list."
  (emacsvox-python--navigation-feedback 'python-nav-backward-up-list))

(advice-add 'python-nav-backward-up-list :after
            #'emacsvox--advice-python-nav-backward-up-list-after)

(defun emacsvox--advice-python-nav-backward-statement-after (&rest _)
  "Speak after navigating backward by statement."
  (emacsvox-python--navigation-feedback 'python-nav-backward-statement))

(advice-add 'python-nav-backward-statement :after
            #'emacsvox--advice-python-nav-backward-statement-after)

(defun emacsvox--advice-python-nav-backward-sexp-safe-after (&rest _)
  "Speak after safe backward expression navigation."
  (emacsvox-python--navigation-feedback 'python-nav-backward-sexp-safe))

(advice-add 'python-nav-backward-sexp-safe :after
            #'emacsvox--advice-python-nav-backward-sexp-safe-after)

(defun emacsvox--advice-python-nav-backward-sexp-after (&rest _)
  "Speak after backward expression navigation."
  (emacsvox-python--navigation-feedback 'python-nav-backward-sexp))

(advice-add 'python-nav-backward-sexp :after
            #'emacsvox--advice-python-nav-backward-sexp-after)

(defun emacsvox--advice-python-nav-backward-defun-after (&rest _)
  "Speak after backward defun navigation."
  (emacsvox-python--navigation-feedback 'python-nav-backward-defun))

(advice-add 'python-nav-backward-defun :after
            #'emacsvox--advice-python-nav-backward-defun-after)

(defun emacsvox--advice-python-nav-backward-block-after (&rest _)
  "Speak after backward block navigation."
  (emacsvox-python--navigation-feedback 'python-nav-backward-block))

(advice-add 'python-nav-backward-block :after
            #'emacsvox--advice-python-nav-backward-block-after)

(provide 'emacsvox-python)
;;;  end of file
