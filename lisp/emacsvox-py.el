;;; emacsvox-py.el --- Speech enable Python -*- lexical-binding: t; -*-

;; Copyright (c) 1995 -- 2024, T. V. Raman
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox, Speak, Spoken Output, python
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

;; This speech-enables python-mode available on sourceforge and ELPA

;;; Code:

;;   Required modules:
(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'emacsvox-aural-submission)
(require 'emacsvox-aural-transport)
(require 'emacsvox-aural-provider-workflows)

(with-no-warnings (require 'python-mode "python-mode" 'no-error))

;;;  Semantic aural presentation:

(defun emacsvox-py-enable-aural-context ()
  "Identify the current Python Mode buffer to Aural Presentation."
  (setq-local emacsvox-aural-module 'python))

(add-hook 'python-mode-hook #'emacsvox-py-enable-aural-context)

(defun emacsvox-py--edit-facts (kind &optional syntax-role)
  "Return facts for Python Mode edit KIND and optional SYNTAX-ROLE."
  (list
   :role 'code-construct
   :events '(object-changed)
   :syntax-role (or syntax-role 'construct)
   :code-edit-kind kind))

(defun emacsvox-py--operation-facts (target outcome)
  "Return facts for Python Mode operation TARGET with OUTCOME."
  (list
   :role 'code-operation
   :events
   (list
    (pcase outcome
      ('started 'operation-started)
      ('completed 'operation-completed)
      (_ 'operation-failed)))
   :code-operation-kind target))

(defun emacsvox-py--submit-actions
    (facts occasion &optional icons)
  "Submit Python Mode FACTS under OCCASION with compatibility ICONS."
  (emacsvox-aural-submit-actions
   :facts facts
   :module 'python
   :occasion occasion
   :compatibility-actions
   (mapcar #'emacsvox-aural-compatibility-icon icons)))

(defun emacsvox-py--submit-text
    (text facts occasion &optional before-icons after-icons)
  "Submit Python Mode TEXT under FACTS and OCCASION.
BEFORE-ICONS and AFTER-ICONS preserve package feedback inside the transaction."
  (emacsvox-aural-submit
   text
   :facts facts
   :module 'python
   :occasion occasion
   :compatibility-actions
   (append
    (mapcar #'emacsvox-aural-compatibility-icon before-icons)
    (mapcar
     (lambda (icon)
       (emacsvox-aural-compatibility-icon icon 'after))
     after-icons))))

(defun emacsvox-py--submit-message
    (text facts occasion &optional before-icons after-icons)
  "Display and natively present Python Mode TEXT."
  (let ((emacsvox-speak-messages nil))
    (message "%s" text))
  (emacsvox-py--submit-text
   text facts occasion before-icons after-icons))

(defun emacsvox-py--buffer-summary ()
  "Return a concise voice-preserving summary of the selected buffer."
  (concat
   (propertize (buffer-name) 'personality voice-lighten-medium)
   ", "
   (propertize
    (downcase (format-mode-line mode-name))
    'personality voice-animate)))

(defun emacsvox-py--remove-captured-source-icon
    (content icon source-offset source-length)
  "Return CONTENT without ICON already captured at SOURCE-OFFSET.
SOURCE-LENGTH is the length of the source line before spoken prefixes."
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

(defun emacsvox-py--present-current-line
    (facts occasion &optional before-icons after-icons)
  "Present the current line as one Python Mode transaction.
FACTS and OCCASION describe the line.  BEFORE-ICONS and AFTER-ICONS add
package-specific feedback around speech."
  (let* ((source-icon (get-char-property (point) 'auditory-icon))
         (source-offset (- (point) (line-beginning-position)))
         (source-length
          (- (line-end-position) (line-beginning-position)))
         (context (emacsvox-aural-capture-context 'python occasion))
         (submit-actions
          (symbol-function 'emacsvox-aural-submit-actions))
         (icons (copy-sequence before-icons))
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
                 (plist-get arguments :compatibility-actions)
                 (mapcar
                  (lambda (icon)
                    (emacsvox-aural-compatibility-icon icon 'after))
                  after-icons)))))))
        (emacsvox-speak-line-with-speaker
         (lambda (content)
           (setq submitted t)
           (emacsvox-aural-submit
            (emacsvox-py--remove-captured-source-icon
             content source-icon source-offset source-length)
            :facts facts
            :context context
            :module 'python
            :occasion occasion
            :compatibility-actions
            (append
             (mapcar #'emacsvox-aural-compatibility-icon icons)
             (mapcar
              (lambda (icon)
                (emacsvox-aural-compatibility-icon icon 'after))
              after-icons)))))))
    (unless submitted
      (emacsvox-aural-submit-actions
       :facts facts
       :context context
       :module 'python
       :occasion occasion
       :compatibility-actions
       (append
        (mapcar #'emacsvox-aural-compatibility-icon icons)
        (mapcar
         (lambda (icon)
           (emacsvox-aural-compatibility-icon icon 'after))
         after-icons))))))

(defun emacsvox-py--navigation-facts (target)
  "Return source navigation facts for Python Mode command TARGET."
  (let ((name (symbol-name target)))
    (list
     :role 'code-construct
     :events '(boundary-entered focus-entered)
     :syntax-role
     (cond
      ((string-match-p "class" name) 'class)
      ((string-match-p "def\\|function" name) 'function)
      ((string-match-p "block\\|clause" name) 'block)
      ((string-match-p "statement" name) 'statement)
      ((string-match-p "expression\\|paren\\|list" name) 'expression)
      ((string-match-p "comment" name) 'comment)
      ((string-match-p "section" name) 'section)
      (t 'construct)))))

;;;   electric editing

(defvar emacsvox-py--advice nil
  "Python Mode targets and their native advice functions.")

(defun emacsvox-py--deletion-input (&optional forward)
  "Return (SELECTION-P CHARACTER WHITESPACE-P) before deletion.
When FORWARD is non-nil, capture the character at point instead of before it."
  (let* ((selection-p (use-region-p))
         (character
          (and
           (not selection-p)
           (if forward
               (and (< (point) (point-max)) (following-char))
             (and (> (point) (point-min)) (preceding-char))))))
    (list
     selection-p character
     (and character (= 32 (char-syntax character))))))

(defun emacsvox-py--present-deletion (input &optional count indent)
  "Present deletion described by INPUT, COUNT, and resulting INDENT."
  (pcase-let ((`(,selection-p ,character ,whitespace-p) input))
    (emacsvox-py--submit-text
     (cond
      (selection-p "Deleted selection")
      (whitespace-p (format "Indent %s" (or indent (current-column))))
      ((and count (> count 1))
       (format "Deleted %d characters" count))
      (character
       (or (tts-char-to-speech character)
           (char-to-string character)))
      (t "Deleted character"))
     (append
      (emacsvox-py--edit-facts
       (if selection-p 'delete-selection 'delete-character)
       'character)
      '(:edit-operation deletion))
     'edit)))

(defun emacsvox--advice-py-electric-backspace-around (orig-fun &rest args)
  "Present deletion and block context after an interactive backspace."
  (if (ems-interactive-p 'py-electric-backspace)
      (let* ((input (emacsvox-py--deletion-input))
             (result (apply orig-fun args)))
        (emacsvox-py--present-deletion
         input
         (and (numberp (car args)) (abs (car args)))
         (and (numberp result) result))
        (when (nth 2 input)
          (save-excursion
            (when (ignore-errors (py-beginning-of-block) t)
              (emacsvox-py--present-current-line
               '(:role code-construct
                 :events (focus-entered)
                 :syntax-role block)
               'edit '(close-object)))))
        result)
    (apply orig-fun args)))

(push '(py-electric-backspace :around
        emacsvox--advice-py-electric-backspace-around)
      emacsvox-py--advice)

(defun emacsvox--advice-py-electric-delete-around (orig-fun &rest args)
  "Present an interactive Python Mode deletion."
  (if (ems-interactive-p 'py-electric-delete)
      (let* ((input (emacsvox-py--deletion-input t))
             (result (apply orig-fun args)))
        (emacsvox-py--present-deletion
         input (and (numberp (car args)) (abs (car args))))
        result)
    (apply orig-fun args)))

(push '(py-electric-delete :around
        emacsvox--advice-py-electric-delete-around)
      emacsvox-py--advice)

;;;  interactive programming

(defun emacsvox--advice-py-shell-after (&rest _)
  "Present the destination of an interactive Python Mode shell command."
  (when (ems-interactive-p 'py-shell)
    (emacsvox-py--submit-text
     (emacsvox-py--buffer-summary)
     '(:role command-interaction
       :events (focus-entered)
       :command-interaction-kind repl)
     'state-change '(open-object))))

(cl-loop
 for target in '(py-clear-queue py-execute-region py-execute-buffer)
 for advice-function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "Present an interactive Python operation as started."
     (when (ems-interactive-p ',target)
       (emacsvox-py--submit-actions
        (emacsvox-py--operation-facts ',target 'started)
        'state-change))))
 (push (list target :after advice-function) emacsvox-py--advice))

(cl-loop
 for target in '(py-goto-exception py-down-exception py-up-exception)
 for advice-function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "Speak the exception destination."
     (when (ems-interactive-p ',target)
       (emacsvox-py--present-current-line
        '(:role code-construct
          :events (focus-entered)
          :syntax-role exception)
        'navigation '(large-movement)))))
 (push (list target :after advice-function) emacsvox-py--advice))

(push '(py-shell :after emacsvox--advice-py-shell-after)
      emacsvox-py--advice)

;;;   whitespace management and indentation

(cl-loop
 for target in
 (list 'py-fill-paragraph 'py-fill-comment 'py-fill-string)
 for advice-function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "Present an interactive Python Mode fill operation."
     (when (ems-interactive-p ',target)
       (emacsvox-py--submit-actions
        (emacsvox-py--edit-facts 'fill-paragraph 'paragraph)
        'edit))))
 (push (list target :after advice-function) emacsvox-py--advice))

(defun emacsvox--advice-py-newline-and-indent-after (&rest _)
  "Present the indentation of a newly inserted line."
  (when (ems-interactive-p 'py-newline-and-indent)
    (emacsvox-py--submit-text
     (propertize
      (format "indent %s" (current-column))
      'personality voice-annotate)
     (emacsvox-py--edit-facts 'newline-and-indent 'indentation)
     'edit)))

(defun emacsvox-py--region-line-count ()
  "Return the active region line count, or one for the current line."
  (if (use-region-p)
      (count-lines (region-beginning) (region-end))
    1))

(defun emacsvox--advice-py-shift-region-left-after (&rest _)
  "Speak number of lines that were shifted"
  (when (ems-interactive-p 'py-shift-region-left)
    (emacsvox-py--submit-text
     (format "Left shifted block  containing %s lines"
             (emacsvox-py--region-line-count))
     (emacsvox-py--edit-facts 'shift-left 'block)
     'edit)))

(defun emacsvox--advice-py-shift-region-right-after (&rest _)
  "Speak number of lines that were shifted"
  (when (ems-interactive-p 'py-shift-region-right)
    (emacsvox-py--submit-text
     (format "Right shifted block  containing %s lines"
             (emacsvox-py--region-line-count))
     (emacsvox-py--edit-facts 'shift-right 'block)
     'edit)))

(defun emacsvox--advice-py-indent-region-after (&rest _)
  "Speak number of lines that were shifted"
  (when (ems-interactive-p 'py-indent-region)
    (emacsvox-py--submit-text
     (format "Indented region   containing %s lines"
             (emacsvox-py--region-line-count))
     (emacsvox-py--edit-facts 'indent-region 'block)
     'edit)))

(defun emacsvox--advice-py-comment-region-after (&rest _)
  "Speak number of lines that were shifted"
  (when (ems-interactive-p 'py-comment-region)
    (emacsvox-py--submit-text
     (format "Commented  block  containing %s lines"
             (emacsvox-py--region-line-count))
     (emacsvox-py--edit-facts 'comment-region 'block)
     'edit)))

(dolist
    (entry
     '((py-newline-and-indent emacsvox--advice-py-newline-and-indent-after)
       (py-shift-region-left emacsvox--advice-py-shift-region-left-after)
       (py-shift-region-right emacsvox--advice-py-shift-region-right-after)
       (py-indent-region emacsvox--advice-py-indent-region-after)
       (py-comment-region emacsvox--advice-py-comment-region-after)))
  (push (list (car entry) :after (cadr entry)) emacsvox-py--advice))

;;;   buffer navigation
(cl-loop
 for target in
 '(
   py-goto-block-or-clause-up py-goto-clause-up
   py-previous-class py-previous-clause py-previous-def-or-class
   py-forward-block
   py-forward-block-bol
   py-forward-block-or-clause
   py-forward-block-or-clause-bol
   py-forward-buffer
   py-forward-class
   py-forward-class-bol
   py-forward-clause
   py-forward-clause-bol
   py-forward-comment
   py-forward-decorator
   py-forward-def-bol
   py-forward-def-or-class-bol
   py-forward-elif-block
   py-forward-elif-block-bol
   py-forward-else-block
   py-forward-else-block-bol
   py-forward-except-block
   py-forward-except-block-bol
   py-forward-expression
   py-forward-for-block
   py-forward-for-block-bol
   py-forward-function
   py-forward-if-block
   py-forward-if-block-bol
   py-forward-line
   py-forward-minor-block
   py-forward-minor-block-bol
   py-forward-paragraph
   py-forward-partial-expression
   py-forward-section
   py-forward-statement-bol
   py-forward-statements
   py-forward-top-level
   py-forward-top-level-bol
   py-forward-try-block
   py-forward-try-block-bol
   py-backward-block py-backward-block-bol
   py-backward-block-or-clause py-backward-block-or-clause-bol
   py-backward-class py-backward-class-bol
   py-backward-clause py-backward-clause-bol
   py-backward-comment py-backward-decorator py-backward-decorator-bol
   py-backward-def-bol py-backward-def-or-class-bol
   py-backward-elif-block py-backward-elif-block-bol
   py-backward-else-block py-backward-else-block-bol
   py-backward-except-block py-backward-except-block-bol
   py-backward-expression py-backward-for-block py-backward-for-block-bol
   py-backward-function py-backward-if-block py-backward-if-block-bol
   py-backward-line py-backward-minor-block py-backward-minor-block-bol
   py-backward-paragraph py-backward-partial-expression py-backward-same-level
   py-backward-section py-backward-statement-bol py-backward-statements
   py-backward-top-level py-backward-top-level-p
   py-backward-try-block py-backward-try-block-bol
   py-match-paren py-indent-or-complete
   py-beginning py-beginning-of-block-bol
   py-beginning-of-block-current-column
   py-beginning-of-block-or-clause py-beginning-of-class
   py-beginning-of-class-bol
   py-beginning-of-clause-bol py-beginning-of-comment
   py-beginning-of-declarations
   py-beginning-of-decorator py-beginning-of-decorator-bol
   py-beginning-of-expression py-beginning-of-line
   py-beginning-of-list-pps
   py-beginning-of-minor-block
   py-beginning-of-partial-expression
   py-beginning-of-section py-beginning-of-statement-bol
   py-beginning-of-top-level
   py-forward-declarations py-backward-declarations
   py-down py-up
   py-down-block py-down-block-bol
   py-down-block-or-clause py-down-block-or-clause-bol
   py-down-class py-down-class-bol
   py-down-clause py-down-clause-bol
   py-down-def py-down-def-bol
   py-down-def-or-class py-down-def-or-class-bol
   py-down-minor-block py-down-minor-block-bol
   py-down-section py-down-section-bol
   py-down-statement py-down-top-level
   py-backward-statement py-forward-statement
   py-goto-block-up  py-go-to-beginning-of-comment
   py-end py-end-of-block-or-clause
   py-end-of-class py-end-of-comment
   py-end-of-decorator py-end-of-expression
   py-end-of-line py-end-of-list-position
   py-end-of-partial-expression py-end-of-section
   py-end-of-statement-bol py-end-of-string
   py-end-of-top-level
   py-beginning-of-statement py-end-of-statement
   py-beginning-of-block py-end-of-block
   py-beginning-of-clause py-end-of-clause
   py-next-statement py-previous-statement
   py-backward-def py-forward-def
   py-backward-def-or-class py-forward-def-or-class
   py-beginning-of-def-or-class py-end-of-def-or-class)
 for advice-function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "Speak current statement after moving"
     (when (ems-interactive-p ',target)
       (emacsvox-py--present-current-line
        (emacsvox-py--navigation-facts ',target)
        'navigation))))
 (push (list target :after advice-function) emacsvox-py--advice))

(cl-loop
 for target in
 '(
   py-mark-class-bol py-mark-clause py-mark-clause-bol py-mark-comment
   py-mark-comment-bol py-mark-def py-mark-def-bol
   py-mark-def-or-class py-mark-def-or-class-bol py-mark-except-block
   py-mark-except-block-bol py-mark-expression py-mark-expression-bol
   py-mark-if-block py-mark-if-block-bol py-mark-line py-mark-line-bol
   py-mark-minor-block py-mark-minor-block-bol py-mark-paragraph
   py-mark-paragraph-bol py-mark-partial-expression
   py-mark-partial-expression-bol py-mark-section py-mark-statement
   py-mark-statement-bol py-mark-top-level py-mark-top-level-bol
   py-mark-try-block py-mark-try-block-bol)
 for advice-function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "Speak number of lines marked"
     (when (ems-interactive-p ',target)
       (emacsvox-py--submit-message
        (format
         "Marked block containing %s lines"
         (emacsvox-py--region-line-count))
        '(:role code-construct
          :events (code-selection-created)
          :syntax-role construct)
        'state-change))))
 (push (list target :after advice-function) emacsvox-py--advice))

(cl-loop
 for target in
 '(
   py-narrow-to-block py-narrow-to-block-or-clause py-narrow-to-class
   py-narrow-to-clause         py-narrow-to-def
   py-narrow-to-def-or-class
   py-narrow-to-statement
   )
 for advice-function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "Present the narrowed Python Mode region."
     (when (ems-interactive-p ',target)
       (emacsvox-py--submit-message
        (format
         "Narrowed %s lines"
         (count-lines (point-min) (point-max)))
        (emacsvox-py--operation-facts ',target 'completed)
        'state-change))))
 (push (list target :after advice-function) emacsvox-py--advice))

(defun emacsvox-py--word-tail ()
  "Return the identifier text from point to its syntactic end."
  (let ((start (point)))
    (save-excursion
      (skip-syntax-forward "w_")
      (when (> (point) start)
        (emacsvox-aural-source-substring start (point))))))

(defun emacsvox-py--present-word-tail ()
  "Present the current identifier tail as navigation."
  (if-let* ((content (emacsvox-py--word-tail)))
      (emacsvox-py--submit-text
       content
       '(:role code-construct
         :events (focus-entered)
         :syntax-role identifier)
       'navigation)
    (emacsvox-py--submit-actions
     '(:role code-construct
       :events (focus-entered)
       :syntax-role identifier)
     'navigation)))

(defun emacsvox--advice-py-forward-into-nomenclature-after (&rest _)
  "Speak rest of current word"
  (when (ems-interactive-p 'py-forward-into-nomenclature)
    (emacsvox-py--present-word-tail)))

(defun emacsvox--advice-py-backward-into-nomenclature-after (&rest _)
  "Speak rest of current word"
  (when (ems-interactive-p 'py-backward-into-nomenclature)
    (emacsvox-py--present-word-tail)))

(dolist
    (entry
     '((py-forward-into-nomenclature
        emacsvox--advice-py-forward-into-nomenclature-after)
       (py-backward-into-nomenclature
        emacsvox--advice-py-backward-into-nomenclature-after)))
  (push (list (car entry) :after (cadr entry)) emacsvox-py--advice))

;;;  the process buffer

(defun emacsvox--advice-py-process-filter-around
    (orig-fun process output)
  "Submit newly inserted visible Python process output for autospeech."
  (let* ((buffer
          (and
           emacsvox-comint-autospeak
           (processp process)
           (process-buffer process)))
         (prior
          (and
           (buffer-live-p buffer)
           (with-current-buffer buffer (point-max))))
         (tts-stop-immediately nil)
         (result (funcall orig-fun process output)))
    (when
        (and
         emacsvox-comint-autospeak
         (buffer-live-p buffer)
         (window-live-p (get-buffer-window buffer)))
      (with-current-buffer buffer
        (let ((end (point-max)))
          (when (and prior (< prior end))
            (emacsvox-py--submit-text
             (emacsvox-aural-source-substring prior end)
             '(:role command-output
               :events (command-output-received)
               :command-interaction-kind repl)
             'continuous)))))
    result))

(push '(py-process-filter :around emacsvox--advice-py-process-filter-around)
      emacsvox-py--advice)

;;;  Voice Mappings:
(voice-setup-add-map
 '(
   (py-number-face voice-lighten)
   (py-XXX-tag-face voice-animate)
   (py-pseudo-keyword-face voice-animate-medium)
   (py-variable-name-face  voice-animate)
   (py-decorators-face voice-lighten)
   (py-builtins-face voice-smoothen)
   (py-class-name-face voice-bolden-extra)
   (py-exception-name-face voice-brighten)
   (py-def-class-face voice-lighten)
   (py-import-from-face voice-animate)
   (py-object-reference-face voice-bolden-and-animate)
   (py-try-if-face voice-lighten)
   ))

;;;  pydoc advice:

(defun emacsvox--advice-py-pydoc-after (&rest _)
  "Present documentation opened by an interactive Pydoc command."
  (when (ems-interactive-p 'pydoc)
    (let ((content
           (emacsvox-aural-source-substring (point) (point-max))))
      (if (> (length content) 0)
          (emacsvox-py--submit-text
           content
           '(:role code-construct
             :events (focus-entered)
             :syntax-role documentation)
           'navigation '(open-object))
        (emacsvox-py--submit-actions
         '(:role code-construct
           :events (focus-entered)
           :syntax-role documentation)
         'navigation '(open-object))))))

(defun emacsvox--advice-py-help-at-point-after (&rest _)
  "Present the buffer displayed by interactive Python Mode help."
  (when (ems-interactive-p 'py-help-at-point)
    (let ((content
           (emacsvox-aural-source-substring (point-min) (point-max))))
      (if (> (length content) 0)
          (emacsvox-py--submit-text
           content
           '(:role code-construct
             :events (focus-entered)
             :syntax-role documentation)
           'navigation '(help))
        (emacsvox-py--submit-actions
         '(:role code-construct
           :events (focus-entered)
           :syntax-role documentation)
         'navigation '(help))))))

(push '(pydoc :after emacsvox--advice-py-pydoc-after)
      emacsvox-py--advice)
(push '(py-help-at-point :after emacsvox--advice-py-help-at-point-after)
      emacsvox-py--advice)

(defun emacsvox-py--install-advice ()
  "Install advice for functions present in Python Mode and Pydoc."
  (dolist (entry emacsvox-py--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox-py)))))))

(emacsvox-py--install-advice)
(dolist (feature '(python-mode pydoc))
  (eval-after-load feature #'emacsvox-py--install-advice))

(provide 'emacsvox-py)

;;; emacsvox-py.el ends here
