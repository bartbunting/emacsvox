;;; emacsvox-comint.el --- Speech-enable COMINT  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable COMINT An Emacs Interface to comint
;; Keywords: Emacsvox,  Audio Desktop comint
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |raman@cs.cornell.edu
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ |
;; Location https://github.com/robertmeta/emacsvox
;; 

;;;   Copyright:

;; Copyright (C) 1995 -- 2007, 2019, T. V. Raman
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
;; MERCHANTABILITY or FITNCOMINT FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:

;; comint == command interaction.
;; Advice comint and friends to speak.
;; 

;;; Code:

;;   Required modules:

(require 'cl-lib)
(require 'emacsvox-preamble)
(require 'emacsvox-aural-provider-workflows)
(require 'emacsvox-aural-submission)
(require 'comint)
(require 'shell)

;;;  comint
;;;###autoload
(defcustom emacsvox-comint-autospeak nil
  "Speak comint output.
Use \\[emacsvox-toggle-comint-autospeak] to toggle this
setting. Do not set this globally. Also see custom option
`emacsvox-wizards-project-shells' for starting up
project-specific shells that have autospeak turned on. The
default is intentionally nil, since this option should only be
turned on where needed."
  :group 'emacsvox-speak
  :type 'boolean)

(make-variable-buffer-local 'emacsvox-comint-autospeak)
(defun emacsvox-toggle-comint-autospeak (&optional prefix)
  "Toggle comint autospeak.
Interactive PREFIX arg means toggle  global default value. "
  (interactive "P")
  
  (cond
   (prefix
    (setq-default
     emacsvox-comint-autospeak
     (not (default-value 'emacsvox-comint-autospeak)))
    (setq emacsvox-comint-autospeak
          (default-value 'emacsvox-comint-autospeak)))
   (t (make-local-variable 'emacsvox-comint-autospeak)
      (setq emacsvox-comint-autospeak (not emacsvox-comint-autospeak))))
  (when (called-interactively-p 'interactive)
    (emacsvox-icon (if emacsvox-comint-autospeak 'on 'off))
    (message
     (format "Turned emacsvox-comint-autospeak %s  %s."
             (if emacsvox-comint-autospeak "on" "off")
             (if prefix "" " locally")))))

;;;###autoload
(defun emacsvox-toggle-inaudible-or-comint-autospeak ()
  "Toggle comint-autospeak when in a comint or vterm buffer.
Otherwise call voice-setup-toggle-silence-personality which
toggles personality under point."
  (interactive)
  (cond
   ((or (derived-mode-p 'comint-mode)
        (eq 'vterm-mode major-mode))
    (funcall-interactively #'emacsvox-toggle-comint-autospeak))
   (t (funcall-interactively #'voice-setup-toggle-silence-personality))))

(defvar emacsvox-comint-output-monitor nil
  " Monitor comint output.
When  on,  comint output is spoken even when the
buffer is not current or its window live.")

(make-variable-buffer-local 'emacsvox-comint-output-monitor)

(defvar-local emacsvox-comint--pending-output ""
  "Normalized process output waiting for a logical line or prompt boundary.")

(defvar-local emacsvox-comint--last-prompt nil
  "Most recently recognized command prompt, without text properties.")

(defvar-local emacsvox-comint--prompt-awaiting-padding nil
  "Non-nil when a just-recognized prompt may receive trailing whitespace.")

;;;###autoload
(ems-generate-switcher 'emacsvox-toggle-comint-output-monitor
                       'emacsvox-comint-output-monitor
                       "Toggle  Emacsvox comint monitor.
Interactive PREFIX arg means toggle the global default value. ")

;;; Semantic aural presentation:

(defun emacsvox-comint--module ()
  "Return the aural module for the current command-interaction buffer."
  (if (derived-mode-p 'shell-mode) 'shell 'comint))

(defun emacsvox-comint--interaction-kind ()
  "Return the semantic command-interaction kind for the current buffer."
  (if (derived-mode-p 'shell-mode) 'shell 'repl))

(defun emacsvox-comint-enable-aural-context ()
  "Identify the current command-interaction buffer to aural schemes."
  (setq-local emacsvox-aural-module (emacsvox-comint--module)))

(defun emacsvox-comint-facts (role &optional event operation properties)
  "Return command-interaction facts for ROLE.
EVENT and OPERATION describe the interaction.  PROPERTIES is an additional
property list appended to the result."
  (append
   (list :role role
         :command-interaction-kind
         (emacsvox-comint--interaction-kind))
   (when event (list :events (list event)))
   (when operation (list :command-operation operation))
   properties))

(defun emacsvox-comint--call-with-aural-presentation
    (facts occasion function &rest arguments)
  "Call FUNCTION with ARGUMENTS in one frozen command presentation.
FACTS describe the object or event, and OCCASION describes the interaction."
  (emacsvox-aural-call-with-submission
   function
   :facts (or facts (emacsvox-comint-facts 'command-interaction))
   :module (emacsvox-comint--module)
   :occasion (or occasion 'navigation)
   :arguments arguments))

(defun emacsvox-comint--present-feedback
    (facts occasion icon function &rest arguments)
  "Under FACTS and OCCASION, present ICON then call FUNCTION with ARGUMENTS."
  (emacsvox-comint--call-with-aural-presentation
   facts occasion
   (lambda ()
     (when icon (emacsvox-icon icon))
     (apply function arguments))))

(defun emacsvox-comint--submit
    (content facts occasion &optional icon icon-phase)
  "Submit CONTENT with FACTS and OCCASION as one aural transaction.
When ICON is non-nil, preserve it in ICON-PHASE, which defaults to `before'."
  (emacsvox-aural-submit
   content
   :facts facts
   :module (emacsvox-comint--module)
   :occasion occasion
   :compatibility-actions
   (when icon
     (list
      (emacsvox-aural-compatibility-icon icon icon-phase)))))

(defun emacsvox-comint--full-prompt-match-p (text)
  "Return non-nil when TEXT is exactly a configured Comint prompt."
  (and
   (> (length text) 0)
   (cl-some
    (lambda (regexp)
      (and
       (stringp regexp)
       (> (length regexp) 0)
       (condition-case nil
           (string-match-p
            (concat "\\`\\(?:" regexp "\\)\\'")
            (substring-no-properties text))
         (invalid-regexp nil))))
    (delq
     nil
     (list
      comint-prompt-regexp
      (and (derived-mode-p 'shell-mode) shell-prompt-pattern))))))

(defun emacsvox-comint--split-final-prompt (text)
  "Split a recognized final prompt from TEXT.
Return (OUTPUT . PROMPT), or nil when TEXT does not end in a prompt.  A
previously observed prompt can delimit output that did not end in a newline."
  (let* ((plain (substring-no-properties text))
         (known emacsvox-comint--last-prompt)
         (known-start
          (and
           (stringp known)
           (> (length known) 0)
           (string-suffix-p known plain)
           (- (length text) (length known)))))
    (cond
     (known-start
      (cons
       (substring text 0 known-start)
       (substring text known-start)))
     (t
      (let* ((line-start
              (if-let* ((newline (string-match "[^\n]*\\'" plain)))
                  newline
                0))
             (tail (substring text line-start)))
        (when (emacsvox-comint--full-prompt-match-p tail)
          (cons (substring text 0 line-start) tail)))))))

(defun emacsvox-comint--partition-output (text replace-p)
  "Partition normalized inserted TEXT into output, prompt, and pending text.
When REPLACE-P is non-nil, TEXT replaces pending carriage-motion output."
  (let ((plain-text (substring-no-properties text)))
    (if
        (and
         (not replace-p)
         emacsvox-comint--prompt-awaiting-padding
         (string-match-p "\\`[ \t]+\\'" plain-text))
        (progn
          (setq emacsvox-comint--last-prompt
                (concat emacsvox-comint--last-prompt plain-text)
                emacsvox-comint--prompt-awaiting-padding nil)
          (list :output nil :prompt nil :pending ""))
      (setq emacsvox-comint--prompt-awaiting-padding nil)
      (let* ((combined
              (if replace-p
                  text
                (concat emacsvox-comint--pending-output text)))
             (prompt-split (emacsvox-comint--split-final-prompt combined))
             output prompt)
        (if prompt-split
            (setq output (car prompt-split)
                  prompt (cdr prompt-split)
                  emacsvox-comint--pending-output ""
                  emacsvox-comint--last-prompt
                  (substring-no-properties prompt)
                  emacsvox-comint--prompt-awaiting-padding
                  (string-match-p
                   "[$#%>]\\'" emacsvox-comint--last-prompt))
          (let* ((plain (substring-no-properties combined))
                 (pending-start
                  (if-let* ((newline (string-match "[^\n]*\\'" plain)))
                      newline
                    0)))
            (setq output (substring combined 0 pending-start)
                  emacsvox-comint--pending-output
                  (substring combined pending-start))))
        (list :output output :prompt prompt
              :pending emacsvox-comint--pending-output)))))

(defun emacsvox-comint--automatic-feedback-p ()
  "Return non-nil when process output should be presented in this buffer."
  (and
   emacsvox-comint-autospeak
   (or
    emacsvox-comint-output-monitor
    (eq (current-buffer) (window-buffer (selected-window))))))

(defun emacsvox-comint--present-process-output (text raw-output)
  "Present normalized inserted TEXT corresponding to RAW-OUTPUT.
Arbitrary process chunks are assembled into complete output and prompt
events.  Carriage-return chunks replace pending progress output."
  (let* ((partition
          (emacsvox-comint--partition-output
           text (string-prefix-p "\r" raw-output)))
         (output (plist-get partition :output))
         (prompt (plist-get partition :prompt))
         (present-p (emacsvox-comint--automatic-feedback-p)))
    (when
        (and
         prompt
         (derived-mode-p 'shell-mode)
         (bound-and-true-p dirtrack-procfs-mode))
      (emacsvox-shell-dirtrack-procfs))
    (if (not present-p)
        ;; Never announce output later merely because autospeak or monitoring
        ;; was enabled after it arrived.
        (setq emacsvox-comint--pending-output "")
      (when
          (and
           output
           (not (string-empty-p (string-trim output))))
        (emacsvox-comint--submit
         output
         (emacsvox-comint-facts
          'command-output 'command-output-received)
         'continuous))
      (when prompt
        (emacsvox-comint--present-feedback
         (emacsvox-comint-facts
          'command-prompt 'command-prompt-ready)
         'notification 'item #'ignore)))))

(defun emacsvox-comint--inserted-output (process start)
  "Return normalized output inserted for PROCESS since marker START."
  (when-let* ((buffer (process-buffer process))
              ((buffer-live-p buffer))
              ((eq buffer (marker-buffer start)))
              (process-mark (process-mark process))
              ((eq buffer (marker-buffer process-mark))))
    (with-current-buffer buffer
      (let ((beginning (marker-position start))
            (end (marker-position process-mark)))
        (when (<= beginning end)
          (buffer-substring beginning end))))))

;;;###autoload
(defun emacsvox-comint-speech-setup ()
  "Speech setup."
  (emacsvox-comint-enable-aural-context)
  (setq buffer-undo-list  t)
  (define-key comint-mode-map "\C-o" 'switch-to-completions)
  (when emacsvox-use-header-line
    (setq
     header-line-format
     '((:eval
        (concat
         (format-time-string emacsvox-speak-time-brief-format)
         (propertize (buffer-name) 'personality voice-annotate)
         (abbreviate-file-name default-directory)
         (when (ems--comint-autospeak)
           (propertize "Autospeak" 'personality voice-lighten))
         (when (> (length (window-list)) 1)
           (format "%s" (length (window-list)))))))))
  (tts-set-punctuations 'all)
  (emacsvox-pronounce-add-dictionary-entry
   'comint-mode
   emacsvox-pronounce-uuid-pattern
   (cons 're-search-forward
         'emacsvox-pronounce-uuid))
  (emacsvox-pronounce-add-dictionary-entry
   'comint-mode
   emacsvox-pronounce-sha-checksum-pattern
   (cons 're-search-forward
         'emacsvox-pronounce-sha-checksum))
  (emacsvox-pronounce-add-dictionary-entry
   'comint-mode
   emacsvox-pronounce-date-mm-dd-yyyy-pattern
   (cons 're-search-forward
         'emacsvox-pronounce-mm-dd-yyyy-date))
  (emacsvox-pronounce-add-dictionary-entry
   'comint-mode
   emacsvox-pronounce-date-yyyy-mm-dd-pattern
   (cons 're-search-forward
         'emacsvox-pronounce-yyyy-mm-dd-date))
  (emacsvox-pronounce-add-dictionary-entry
   'comint-mode
   emacsvox-pronounce-rfc-3339-datetime-pattern
   (cons 're-search-forward
         'emacsvox-pronounce-decode-rfc-3339-datetime))
  (emacsvox-pronounce-refresh-pronunciations))

(add-hook 'comint-mode-hook 'emacsvox-comint-speech-setup)

;;;  Advice comint:

(defun emacsvox--advice-comint-delete-output-after (&rest _)
  "Cue and speak after interactively deleting Comint output."
  (when (ems-interactive-p 'comint-delete-output)
    (emacsvox-icon 'delete-object)
    (emacsvox-speak-line)))

(advice-add
 'comint-delete-output :after
 #'emacsvox--advice-comint-delete-output-after
 '((name . emacsvox)))

(cl-loop
 for target in
 '(comint-history-isearch-backward
   comint-history-isearch-backward-regexp)
 for function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after an interactive Comint history search."
       (when (ems-interactive-p ',target)
         (save-excursion
           (comint-bol-or-process-mark)
           (emacsvox-icon 'select-object)
           (emacsvox-speak-line 1))))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-comint-clear-buffer-after (&rest _)
  "Cue and speak after interactively clearing a Comint buffer."
  (when (ems-interactive-p 'comint-clear-buffer)
    (emacsvox-icon 'delete-object)
    (emacsvox-speak-line)))

(advice-add
 'comint-clear-buffer :after
 #'emacsvox--advice-comint-clear-buffer-after
 '((name . emacsvox)))

(defun emacsvox--advice-comint-magic-space-around
    (original argument)
  "Call ORIGINAL once with ARGUMENT, then speak its interactive result."
  (let ((interactive-p (ems-interactive-p 'comint-magic-space)))
    (if (not interactive-p)
        (funcall original argument)
      (ems-with-messages-silenced
       (let ((origin (point))
             (count (or argument 1)))
         (let ((result (funcall original argument)))
           (if (= (point) (+ origin count))
               (save-excursion
                 (forward-word -1)
                 (emacsvox-speak-word))
             (emacsvox-icon 'complete)
             (emacsvox-speak-region
              (comint-line-beginning-position) (point)))
           result))))))

(advice-add
 'comint-magic-space :around
 #'emacsvox--advice-comint-magic-space-around
 '((name . emacsvox)))

(defun emacsvox--advice-comint-insert-previous-argument-around
    (original index)
  "Call ORIGINAL once with INDEX, then speak inserted text interactively."
  (let ((interactive-p
         (ems-interactive-p 'comint-insert-previous-argument)))
    (if (not interactive-p)
        (funcall original index)
      (let ((origin (point))
            (result (funcall original index)))
        (emacsvox-speak-region origin (point))
        (emacsvox-icon 'yank-object)
        result))))

(advice-add
 'comint-insert-previous-argument :around
 #'emacsvox--advice-comint-insert-previous-argument-around
 '((name . emacsvox)))

;; Customize comint:

(add-hook 'comint-output-filter-functions
          'comint-truncate-buffer)
(when (locate-library "ansi-color")
  (autoload 'ansi-color-for-comint-mode-on "ansi-color" nil t)
  (add-hook 'comint-mode-hook 'ansi-color-for-comint-mode-on))
(add-hook 'comint-output-filter-functions 'comint-strip-ctrl-m)
(add-hook 'comint-output-filter-functions 'comint-watch-for-password-prompt)
(voice-setup-add-map
 '(
   (comint-highlight-prompt voice-lighten-extra)
   (comint-highlight-input voice-bolden-medium)))

(cl-loop
 for mode in
 '(conf-space-mode conf-unix-mode conf-mode)
 do
 (emacsvox-pronounce-add-dictionary-entry
  mode
  emacsvox-pronounce-uuid-pattern
  (cons 're-search-forward
        'emacsvox-pronounce-uuid)))

(defun emacsvox--advice-shell-dirstack-message-around
    (original &rest arguments)
  "Call ORIGINAL once with ARGUMENTS while silencing its messages."
  (ems-with-messages-silenced
   (apply original arguments)))

(advice-add
 'shell-dirstack-message :around
 #'emacsvox--advice-shell-dirstack-message-around
 '((name . emacsvox)))

(defun emacsvox--advice-comint-delchar-or-maybe-eof-around
    (original &optional argument)
  "Give deletion or EOF feedback, then call ORIGINAL once with ARGUMENT."
  (when (ems-interactive-p 'comint-delchar-or-maybe-eof)
    (if (= (point) (point-max))
        (message "Sending EOF to comint process")
      (emacsvox-speak-edit-operation 'deletion)
      (emacsvox-speak-char t)))
  (funcall original argument))

(advice-add
 'comint-delchar-or-maybe-eof :around
 #'emacsvox--advice-comint-delchar-or-maybe-eof-around
 '((name . emacsvox)))

(defun emacsvox--advice-comint-send-eof-before (&rest _)
  "Announce an interactive EOF sent to the subprocess."
  (when (ems-interactive-p 'comint-send-eof)
    (message "Sending EOF to subprocess")))

(advice-add
 'comint-send-eof :before
 #'emacsvox--advice-comint-send-eof-before
 '((name . emacsvox)))

(defun emacsvox--advice-comint-accumulate-before (&rest _)
  "Cue and speak an interactively accumulated Comint line."
  (when (ems-interactive-p 'comint-accumulate)
    (save-excursion
      (comint-bol)
      (emacsvox-icon 'select-object)
      (emacsvox-speak-line 1))))

(advice-add
 'comint-accumulate :before
 #'emacsvox--advice-comint-accumulate-before
 '((name . emacsvox)))

(cl-loop
 for target in
 '(comint-next-matching-input-from-input
   comint-previous-matching-input-from-input)
 for function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after matching input from the current input."
       (when (ems-interactive-p ',target)
         (save-excursion
           (goto-char (comint-line-beginning-position))
           (emacsvox-speak-line 1))
         (emacsvox-icon 'select-object)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(cl-loop
 for target in
 '(shell-forward-command shell-backward-command)
 for function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after interactive shell command movement."
       (when (ems-interactive-p ',target)
         (let ((emacsvox-show-point t))
           (emacsvox-speak-line)
           (emacsvox-icon 'item))))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-comint-show-output-after (&rest _)
  "Speak the output selected by an interactive Comint command."
  (when (ems-interactive-p 'comint-show-output)
    (let ((emacsvox-show-point t))
      (emacsvox-icon 'large-movement)
      (emacsvox-speak-region (point) (mark)))))

(advice-add
 'comint-show-output :after
 #'emacsvox--advice-comint-show-output-after
 '((name . emacsvox)))

(defun emacsvox--advice-comint-show-maximum-output-after (&rest _)
  "Cue and speak after showing maximum Comint output."
  (when (ems-interactive-p 'comint-show-maximum-output)
    (let ((emacsvox-show-point t))
      (emacsvox-speak-line)
      (emacsvox-icon 'scroll))))

(advice-add
 'comint-show-maximum-output :after
 #'emacsvox--advice-comint-show-maximum-output-after
 '((name . emacsvox)))

(defun emacsvox--advice-comint-bol-or-process-mark-after (&rest _)
  "Cue and speak after moving to the Comint input boundary."
  (when (ems-interactive-p 'comint-bol-or-process-mark)
    (let ((emacsvox-show-point t))
      (emacsvox-speak-line)
      (emacsvox-icon 'select-object))))

(advice-add
 'comint-bol-or-process-mark :after
 #'emacsvox--advice-comint-bol-or-process-mark-after
 '((name . emacsvox)))

(defun emacsvox--advice-comint-copy-old-input-after (&rest _)
  "Cue and speak input copied interactively from Comint history."
  (when (ems-interactive-p 'comint-copy-old-input)
    (emacsvox-icon 'yank-object)
    (emacsvox-speak-line)))

(advice-add
 'comint-copy-old-input :after
 #'emacsvox--advice-comint-copy-old-input-after
 '((name . emacsvox)))

(defun emacsvox--advice-comint-output-filter-around
    (original process output)
  "Call ORIGINAL once, then present normalized logical PROCESS output."
  (let* ((buffer (ignore-errors (process-buffer process)))
         (start
          (and
           (buffer-live-p buffer)
           (ignore-errors (copy-marker (process-mark process))))))
    (unwind-protect
        (let ((result (funcall original process output)))
          (when-let* ((text
                       (and start
                            (ignore-errors
                              (emacsvox-comint--inserted-output
                               process start)))))
            (with-current-buffer (marker-buffer start)
              (emacsvox-comint--present-process-output text output)))
          result)
      (when start (set-marker start nil)))))

(advice-add
 'comint-output-filter :around
 #'emacsvox--advice-comint-output-filter-around
 '((name . emacsvox)))

(defun emacsvox--advice-comint-dynamic-list-completions-around
    (_original completions &optional _common-substring)
  "Replace the stock display with a sorted, keyboard-friendly COMPLETIONS list."
  (let ((completions (sort completions #'string-lessp)))
    (with-output-to-temp-buffer "*Completions*"
      (display-completion-list completions))
    (with-current-buffer (get-buffer "*Completions*")
      (setq-local comint-displayed-dynamic-completions completions))
    (next-completion 1)
    (tts-speak (buffer-substring (point) (point-max)))))

(advice-add
 'comint-dynamic-list-completions :around
 #'emacsvox--advice-comint-dynamic-list-completions-around
 '((name . emacsvox)))

(cl-loop
 for target in
 '(comint-next-input
   comint-next-matching-input
   comint-previous-input
   comint-previous-matching-input)
 for function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak input selected interactively from Comint history."
       (when (ems-interactive-p ',target)
         (tts-with-punctuations
          'all
          (save-excursion
            (goto-char (comint-line-beginning-position))
            (emacsvox-speak-line 1)))
         (emacsvox-icon 'item)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-comint-send-input-after (&rest _)
  "Flush speech and cue an interactively submitted Comint input."
  (setq emacsvox-comint--prompt-awaiting-padding nil)
  (when (ems-interactive-p 'comint-send-input)
    (tts-stop 'all)
    (emacsvox-icon 'more)))

(advice-add
 'comint-send-input :after
 #'emacsvox--advice-comint-send-input-after
 '((name . emacsvox)))

(cl-loop
 for target in '(comint-previous-prompt comint-next-prompt)
 for function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak after interactive movement between Comint prompts."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'item)
         (if (eolp)
             (emacsvox-speak-line)
           (emacsvox-speak-line 1))))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-comint-get-next-from-history-after (&rest _)
  "Cue and speak after interactively fetching the next history item."
  (when (ems-interactive-p 'comint-get-next-from-history)
    (emacsvox-icon 'item)
    (save-excursion (comint-bol) (emacsvox-speak-line 1))))

(advice-add
 'comint-get-next-from-history :after
 #'emacsvox--advice-comint-get-next-from-history-after
 '((name . emacsvox)))

(defun emacsvox--advice-comint-dynamic-list-input-ring-around (original)
  "Use an accessible history display interactively, otherwise call ORIGINAL."
  (if (not (ems-interactive-p 'comint-dynamic-list-input-ring))
      (funcall original)
    (if
        (or (not (ring-p comint-input-ring))
            (ring-empty-p comint-input-ring))
        (message "No history")
      (let
          ((history nil)
           (history-buffer " *Input History*")
           (index (1- (ring-length comint-input-ring))))
        (while (>= index 0)
          (setq history
                (cons (ring-ref comint-input-ring index) history)
                index (1- index)))
        (with-output-to-temp-buffer history-buffer
          (display-completion-list history)
          (switch-to-buffer history-buffer)
          (forward-line 3)
          (while (search-backward "completion" nil 'move)
            (replace-match "history reference")))
        (emacsvox-icon 'help)
        (next-completion 1)
        (tts-speak (emacsvox-get-current-completion))))))

(advice-add
 'comint-dynamic-list-input-ring :around
 #'emacsvox--advice-comint-dynamic-list-input-ring-around
 '((name . emacsvox)))

(cl-loop
 for (target announcement) in
 '((comint-quit-subjob "Sent quit signal to subjob ")
   (comint-stop-subjob "Stopped the subjob")
   (comint-interrupt-subjob "Interrupted the subjob"))
 for function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Report an interactive signal sent to a Comint subjob."
       (when (ems-interactive-p ',target)
         (message ,announcement)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-comint-kill-input-before (&rest _)
  "Cue and speak input about to be killed interactively."
  (when (ems-interactive-p 'comint-kill-input)
    (emacsvox-icon 'delete-object)
    (let
        ((pmark (process-mark (get-buffer-process (current-buffer)))))
      (when (> (point) (marker-position pmark))
        (emacsvox-speak-region pmark (point))))))

(advice-add
 'comint-kill-input :before
 #'emacsvox--advice-comint-kill-input-before
 '((name . emacsvox)))

(defun emacsvox--advice-comint-dynamic-list-filename-completions-after
    (&rest _)
  "Speak filename completions displayed by an interactive Comint command."
  (when (ems-interactive-p 'comint-dynamic-list-filename-completions)
    (emacsvox-speak-completions-if-available)))

(advice-add
 'comint-dynamic-list-filename-completions :after
 #'emacsvox--advice-comint-dynamic-list-filename-completions-after
 '((name . emacsvox)))

;;; dirtrack-procfs:

(declare-function shell-dirtrack-mode "shell" (&optional arg))
;; Directory tracking for shell buffers on  systems that have  /proc
;; Adapted from Emacs Wiki:
(defun emacsvox-shell--procfs-directory ()
  "Return the local shell process directory reported by procfs, or nil."
  (when
      (and
       (derived-mode-p 'shell-mode)
       (not (file-remote-p default-directory)))
    (when-let* ((process (get-buffer-process (current-buffer)))
                ((process-live-p process))
                (pid (process-id process))
                ((integerp pid))
                (path (format "/proc/%d/cwd" pid))
                ((file-symlink-p path))
                (directory (ignore-errors (file-truename path)))
                ((file-directory-p directory)))
      (file-name-as-directory directory))))

(defun emacsvox-shell-dirtrack-procfs (&optional output)
  "Update `default-directory' from procfs and return OUTPUT unchanged.
This is called when the logical output assembler recognizes a complete prompt,
so prompts split across process chunks still update the directory."
  (prog1 output
    (when-let* ((directory (emacsvox-shell--procfs-directory))
                ((not
                  (file-equal-p
                   directory (expand-file-name default-directory)))))
      (condition-case nil
          (cd directory)
        (file-error nil)))))

(defun emacsvox-shell--procfs-dirtrack-available-p ()
  "Return non-nil when procfs tracking can serve the current shell."
  (and
   (derived-mode-p 'shell-mode)
   (not (file-remote-p default-directory))
   (file-directory-p "/proc")
   (emacsvox-shell--procfs-directory)))

(define-minor-mode dirtrack-procfs-mode
  "Toggle procfs-based directory tracking (Dirtrack-Procfs mode).
With a prefix argument ARG, enable Dirtrack-Procfs mode if ARG is
positive, and disable it otherwise. If called from Lisp, enable
the mode if ARG is omitted or nil.

This is an alternative to `shell-dirtrack-mode' which works by
examining the shell process's current directory with procfs. It
only works on systems that have a /proc filesystem that looks
like Linux's; specifically, /proc/PID/cwd should be a symlink to
process PID's current working directory.

Turning on Dirtrack-Procfs mode automatically turns off
Shell-Dirtrack mode; turning it off does not re-enable it.  Remote shells and
shells without a live local procfs entry retain Shell-Dirtrack mode."
  :init-value nil
  :lighter ""
  :keymap nil
  (when dirtrack-procfs-mode
    (if (emacsvox-shell--procfs-dirtrack-available-p)
        (shell-dirtrack-mode 0)
      (setq dirtrack-procfs-mode nil))))

(defun emacsvox-shell-maybe-enable-dirtrack-procfs ()
  "Enable procfs tracking when it is safe for the current local shell."
  (when (emacsvox-shell--procfs-dirtrack-available-p)
    (dirtrack-procfs-mode 1)))

(when (file-exists-p "/proc")
  (add-hook 'shell-mode-hook #'emacsvox-shell-maybe-enable-dirtrack-procfs))

;;; zoxide:
;;; Inspired by zoxide.el
(defconst emacsvox-comint-zoxide (executable-find "zoxide")
  "Zoxide Executable")
;;;###autoload
(defun emacsvox-zoxide (q)
  "Query zoxide  and launch dired.
Shell Utility zoxide --- implemented in Rust --- lets you jump to
directories that are used often. "
  (interactive "sZoxide:")
  (if-let*
      ((z emacsvox-comint-zoxide)
       (target
        (with-temp-buffer; match found here if process returns 0
          (if (= 0 (call-process z nil t nil "query" q))
              (string-trim (buffer-string))))))
      (funcall-interactively #'dired  target)
    (unless z (error "Install zoxide"))
    (unless target (error "No Match"))))

(provide 'emacsvox-wizards)
(provide 'emacsvox-comint)
;;;  end of file
