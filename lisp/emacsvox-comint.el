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
;; Location https://github.com/tvraman/emacsvox
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

(eval-when-compile (require 'cl-lib))
(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacsvox-preamble)
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

;;;###autoload
(ems-generate-switcher 'emacsvox-toggle-comint-output-monitor
                       'emacsvox-comint-output-monitor
                       "Toggle  Emacsvox comint monitor.
Interactive PREFIX arg means toggle the global default value. ")

;;;###autoload
(defun emacsvox-comint-speech-setup ()
  "Speech setup."
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
  (dtk-set-punctuations 'all)
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

(defun ems--comint-delete-output-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'delete-object) (emacsvox-speak-line)))

(advice-add 'comint-delete-output :after
            #'ems--comint-delete-output-after)

(cl-loop
 for f in
 '(comint-history-isearch-backward comint-history-isearch-backward-regexp)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "speak."
     (when (ems-interactive-p)
       (save-excursion
         (comint-bol-or-process-mark)
         (emacsvox-icon 'select-object)
         (emacsvox-speak-line 1))))))

(defun ems--comint-clear-buffer-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'delete-object) (emacsvox-speak-line)))

(advice-add 'comint-clear-buffer :after
            #'ems--comint-clear-buffer-after)

(defun ems--comint-magic-space-around (orig-fun &rest args)
  "Speak word or completion."
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p)
      (ems-with-messages-silenced
       (let ((orig (point)) (count (ad-get-arg 0)))
         (setq count (or count 1)) (apply orig-fun args)
         (cond
          ((= (point) (+ count orig))
           (save-excursion (forward-word -1) (emacsvox-speak-word)))
          (t (emacsvox-icon 'complete)
             (emacsvox-speak-region (comint-line-beginning-position)
                                    (point)))))))
     (t (apply orig-fun args)))
    result))

(advice-add 'comint-magic-space :around
            #'ems--comint-magic-space-around)

(defun ems--comint-insert-previous-argument-around
    (orig-fun &rest args)
  "speak."
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p)
      (let ((orig (point)))
        (apply orig-fun args) (emacsvox-speak-region orig (point))
        (emacsvox-icon 'yank-object)))
     (t (apply orig-fun args)))
    result))

(advice-add 'comint-insert-previous-argument :around
            #'ems--comint-insert-previous-argument-around)

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

(defun ems--shell-dirstack-message-around (orig-fun &rest args)
  "Silence messages"
  (ems-with-messages-silenced (apply orig-fun args)))

(advice-add 'shell-dirstack-message :around
            #'ems--shell-dirstack-message-around)

(defun ems--comint-delchar-or-maybe-eof-around (orig-fun &rest args)
  "Speak character you're deleting."
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p)
      (cond
       ((= (point) (point-max))
        (message "Sending EOF to comint process"))
       (t (dtk-tone-deletion) (emacsvox-speak-char t)))
      (apply orig-fun args))
     (t (apply orig-fun args)))
    result))

(advice-add 'comint-delchar-or-maybe-eof :around
            #'ems--comint-delchar-or-maybe-eof-around)

(defun ems--comint-send-eof-before (&rest _)
  "Announce what we are doing."
  (when (ems-interactive-p) (message "Sending EOF to subprocess")))

(advice-add 'comint-send-eof :before #'ems--comint-send-eof-before)

(defun ems--comint-accumulate-before (&rest _)
  "Speak the accumulateed line."
  (when (ems-interactive-p)
    (save-excursion
      (comint-bol) (emacsvox-icon 'select-object)
      (emacsvox-speak-line 1))))

(advice-add 'comint-accumulate :before #'ems--comint-accumulate-before)

(cl-loop
 for f in
 '(
   comint-next-matching-input-from-input
   comint-previous-matching-input-from-input)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "Speak matched input."
     (when (ems-interactive-p)
       (save-excursion
         (goto-char (comint-line-beginning-position))
         (emacsvox-speak-line 1))
       (emacsvox-icon 'select-object)))))

(defun ems--shell-forward-command-after (&rest _)
  "Speak  line."
  (when (ems-interactive-p)
    (let ((emacsvox-show-point t))
      (emacsvox-speak-line) (emacsvox-icon 'item))))

(advice-add 'shell-forward-command :after
            #'ems--shell-forward-command-after)

(defun ems--shell-backward-command-after (&rest _)
  "Speak  line."
  (when (ems-interactive-p)
    (let ((emacsvox-show-point t))
      (emacsvox-speak-line) (emacsvox-icon 'item))))

(advice-add 'shell-backward-command :after
            #'ems--shell-backward-command-after)

(defun ems--comint-show-output-after (&rest _)
  "Speak  line."
  (when (ems-interactive-p)
    (let ((emacsvox-show-point t))
      (emacsvox-icon 'large-movement)
      (emacsvox-speak-region (point) (mark)))))

(advice-add 'comint-show-output :after #'ems--comint-show-output-after)

(defun ems--comint-show-maximum-output-after (&rest _)
  "Speak line."
  (when (ems-interactive-p)
    (let ((emacsvox-show-point t))
      (emacsvox-speak-line) (emacsvox-icon 'scroll))))

(advice-add 'comint-show-maximum-output :after
            #'ems--comint-show-maximum-output-after)

(defun ems--comint-bol-or-process-mark-after (&rest _)
  "Speak line."
  (when (ems-interactive-p)
    (let ((emacsvox-show-point t))
      (emacsvox-speak-line) (emacsvox-icon 'select-object))))

(advice-add 'comint-bol-or-process-mark :after
            #'ems--comint-bol-or-process-mark-after)

(defun ems--comint-copy-old-input-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'yank-object) (emacsvox-speak-line)))

(advice-add 'comint-copy-old-input :after
            #'ems--comint-copy-old-input-after)

(defun ems--comint-output-filter-around (orig-fun &rest args)
  "Make comint speak its output.\nTry not to speak the shell prompt,\ninstead, always play an auditory icon when the shell prompt is displayed."
  (let ((result (apply orig-fun args)))
    (let
        ((monitor emacsvox-comint-output-monitor)
         (buffer (process-buffer (ad-get-arg 0)))
         (output (ad-get-arg 1)))
      (apply orig-fun args)
      (with-current-buffer buffer
        (when
            (and (not (string-match "^" output))
                 comint-last-output-start
                 (or monitor (eq (window-buffer) buffer)))
          (let
              ((prompt-p
                (save-excursion
                  (goto-char comint-last-output-start)
                  (or (looking-at shell-prompt-pattern)
                      (looking-at comint-prompt-regexp)))))
            (cond
             ((and emacsvox-comint-autospeak (not prompt-p))
              (dtk-speak output))
             (prompt-p
              (when emacsvox-comint-autospeak (emacsvox-icon 'item))))))
        result))
    result))

(advice-add 'comint-output-filter :around
            #'ems--comint-output-filter-around)

(defun ems--comint-dynamic-list-completions-around
    (orig-fun &rest args)
  "Replacing default with keyboard friendly completer"
  (let
      ((completions (sort (ad-get-arg 0) 'string-lessp))
       (_common (ad-get-arg 1)))
    (with-output-to-temp-buffer "*Completions*"
      (display-completion-list completions))
    (when nil (apply orig-fun args))
    (with-current-buffer (get-buffer "*Completions*")
      (set (make-local-variable 'comint-displayed-dynamic-completions)
           completions))
    (next-completion 1)
    (dtk-speak (buffer-substring (point) (point-max)))))

(advice-add 'comint-dynamic-list-completions :around
            #'ems--comint-dynamic-list-completions-around)

(defun ems--comint-dynamic-complete-around (orig-fun &rest args)
  "Say what you completed."
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p)
      (ems-with-messages-silenced
       (let
           ((prior
             (save-excursion (skip-syntax-backward "^ >") (point))))
         (apply orig-fun args)
         (if (> (point) prior)
             (tts-with-punctuations 'all (emacsvox-icon 'complete)
                                    (dtk-speak
                                     (buffer-substring prior (point))))
           (emacsvox-speak-completions-if-available)))))
     (t (apply orig-fun args)))
    result))

(advice-add 'comint-dynamic-complete :around
            #'ems--comint-dynamic-complete-around)

(defun ems--comint-next-input-after (&rest _)
  "Speak line."
  (when (ems-interactive-p)
    (tts-with-punctuations 'all
                           (save-excursion
                             (goto-char
                              (comint-line-beginning-position))
                             (emacsvox-speak-line 1)))
    (emacsvox-icon 'item)))

(advice-add 'comint-next-input :after #'ems--comint-next-input-after)

(defun ems--comint-next-matching-input-after (&rest _)
  "Speak line."
  (when (ems-interactive-p)
    (tts-with-punctuations 'all
                           (save-excursion
                             (goto-char
                              (comint-line-beginning-position))
                             (emacsvox-speak-line 1)))
    (emacsvox-icon 'item)))

(advice-add 'comint-next-matching-input :after
            #'ems--comint-next-matching-input-after)

(defun ems--comint-previous-input-after (&rest _)
  "Speak line."
  (when (ems-interactive-p)
    (tts-with-punctuations 'all
                           (save-excursion
                             (goto-char
                              (comint-line-beginning-position))
                             (emacsvox-speak-line 1)))
    (emacsvox-icon 'item)))

(advice-add 'comint-previous-input :after
            #'ems--comint-previous-input-after)

(defun ems--comint-previous-matching-input-after (&rest _)
  "Speak line."
  (when (ems-interactive-p)
    (tts-with-punctuations 'all
                           (save-excursion
                             (goto-char
                              (comint-line-beginning-position))
                             (emacsvox-speak-line 1)))
    (emacsvox-icon 'item)))

(advice-add 'comint-previous-matching-input :after
            #'ems--comint-previous-matching-input-after)

(defun ems--comint-send-input-after (&rest _)
  "Flush any ongoing speech."
  (when (ems-interactive-p) (dtk-stop 'all) (emacsvox-icon 'more)))

(advice-add 'comint-send-input :after #'ems--comint-send-input-after)

(defun ems--comint-previous-prompt-after (&rest _)
  "Speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'item)
    (if (eolp) (emacsvox-speak-line) (emacsvox-speak-line 1))))

(advice-add 'comint-previous-prompt :after
            #'ems--comint-previous-prompt-after)

(defun ems--comint-next-prompt-after (&rest _)
  "Speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'item)
    (if (eolp) (emacsvox-speak-line) (emacsvox-speak-line 1))))

(advice-add 'comint-next-prompt :after #'ems--comint-next-prompt-after)

(defun ems--comint-get-next-from-history-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'item)
    (save-excursion (comint-bol) (emacsvox-speak-line 1))))

(advice-add 'comint-get-next-from-history :after
            #'ems--comint-get-next-from-history-after)

(defun ems--comint-dynamic-list-input-ring-around
    (orig-fun &rest args)
  "List  the buffer's input history."
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p)
      (if
          (or (not (ring-p comint-input-ring))
              (ring-empty-p comint-input-ring))
          (message "No history")
        (let
            ((history nil) (history-buffer " *Input History*")
             (index (1- (ring-length comint-input-ring))))
          (while (>= index 0)
            (setq history
                  (cons (ring-ref comint-input-ring index) history)
                  index (1- index)))
          (with-output-to-temp-buffer history-buffer
            (display-completion-list history)
            (switch-to-buffer history-buffer) (forward-line 3)
            (while (search-backward "completion" nil 'move)
              (replace-match "history reference")))
          (emacsvox-icon 'help) (next-completion 1)
          (dtk-speak (emacsvox-get-current-completion)))))
     (t (apply orig-fun args)))
    result))

(advice-add 'comint-dynamic-list-input-ring :around
            #'ems--comint-dynamic-list-input-ring-around)

(defun ems--comint-kill-output-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'delete-object)
    (message "Nuked output of last command ")))

(advice-add 'comint-kill-output :after #'ems--comint-kill-output-after)

(defun ems--comint-quit-subjob-after (&rest _)
  "speak."
  (when (ems-interactive-p) (message "Sent quit signal to subjob ")))

(advice-add 'comint-quit-subjob :after #'ems--comint-quit-subjob-after)

(defun ems--comint-stop-subjob-after (&rest _)
  "speak." (when (ems-interactive-p) (message "Stopped the subjob")))

(advice-add 'comint-stop-subjob :after #'ems--comint-stop-subjob-after)

(defun ems--comint-interrupt-subjob-after (&rest _)
  "speak."
  (when (ems-interactive-p) (message "Interrupted the subjob")))

(advice-add 'comint-interrupt-subjob :after
            #'ems--comint-interrupt-subjob-after)

(defun ems--comint-kill-input-before (&rest _)
  "Speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'delete-object)
    (let
        ((pmark (process-mark (get-buffer-process (current-buffer)))))
      (when (> (point) (marker-position pmark))
        (emacsvox-speak-region pmark (point))))))

(advice-add 'comint-kill-input :before #'ems--comint-kill-input-before)

(defun ems--comint-dynamic-list-filename-completions-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacsvox-speak-completions-if-available)))

(advice-add 'comint-dynamic-list-filename-completions :after
            #'ems--comint-dynamic-list-filename-completions-after)

;;; dirtrack-procfs:

(declare-function shell-dirtrack-mode "shell" (&optional arg))
;; Directory tracking for shell buffers on  systems that have  /proc
;; Adapted from Emacs Wiki:
(defun emacsvox-shell-dirtrack-procfs (str)
  "Directory tracking using /proc.
/proc/pid/cwd is a symlink to working directory."
  
  (prog1
      str
    (when (string-match comint-prompt-regexp str)
      (condition-case nil
          (cd
           (file-symlink-p
            (format "/proc/%s/cwd"
                    (process-id (get-buffer-process (current-buffer))))))
        (error)))))

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
Shell-Dirtrack mode; turning it off does not re-enable it."
  :init-value nil
  :lighter ""
  :keymap nil
  (if (not dirtrack-procfs-mode)
      (remove-hook 'comint-preoutput-filter-functions
                   #'emacsvox-shell-dirtrack-procfs t)
    (add-hook
     'comint-preoutput-filter-functions
     #'emacsvox-shell-dirtrack-procfs nil t)
    (shell-dirtrack-mode 0)))
(when (file-exists-p "/proc")
  (add-hook 'shell-mode-hook 'dirtrack-procfs-mode))

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
  (if-let
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

