;;; emacsvox-eat.el --- Speech-enable EAT  -*- lexical-binding: t; -*-
;;; $Author: tv.raman.tv $
;;; Keywords: Emacsvox,  Audio Desktop eat
;;;   LCD Archive entry:

;;; LCD Archive Entry:
;;; emacsvox| T. V. Raman |raman@cs.cornell.edu
;;; A speech interface to Emacs |
;;;  $Revision: 4532 $ |
;;; Location https://github.com/robertmeta/emacsvox
;;;

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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; EAT ==  Emacs Terminal Emulator

;;; Code:

;;; Forward variable declarations:

(defvar eat-char-mode-map)
(defvar eat-line-mode-map)
(defvar eat-mode-map)
(defvar eat-semi-char-mode-map)
(defvar eat--semi-char-mode)
(defvar eat-terminal)

;;   Required modules:

(eval-when-compile  (require 'cl-lib))
(require 'emacsvox-preamble)
(eval-when-compile (require 'eat "eat" 'no-error))
(declare-function eat-term-display-cursor "eat" (terminal))

;;;  Lifecycle state:

(defvar-local emacsvox-eat--generation 0
  "Monotonic identity for the current EAT terminal presentation.")

(defvar-local emacsvox-eat--active-process nil
  "Process associated with the current EAT generation.")

(defvar-local emacsvox-eat--last-exited-process nil
  "Most recent EAT process whose exit was observed in this buffer.")

(defvar-local emacsvox-eat--completion-snapshot nil
  "Line and token captured before EAT sends terminal completion input.")

(defun emacsvox-eat--clear-transient-state ()
  "Clear asynchronous EAT interaction state in the current buffer."
  (setq emacsvox-eat--completion-snapshot nil))

(defun emacsvox-eat--advance-generation ()
  "Invalidate asynchronous state and advance the current EAT generation."
  (setq emacsvox-eat--generation (1+ emacsvox-eat--generation))
  (emacsvox-eat--clear-transient-state)
  emacsvox-eat--generation)

(defun emacsvox-eat--process-started (process)
  "Start a new EAT generation for PROCESS."
  (emacsvox-eat--advance-generation)
  (setq emacsvox-eat--active-process process
        emacsvox-eat--last-exited-process nil))

(defun emacsvox-eat--process-exited (process)
  "End the EAT generation belonging to PROCESS.
Ignore a stale or duplicate exit after another process has become active."
  (when
      (and
       (not (eq process emacsvox-eat--last-exited-process))
       (or
        (null emacsvox-eat--active-process)
        (eq process emacsvox-eat--active-process)))
    (emacsvox-eat--advance-generation)
    (setq emacsvox-eat--active-process nil
          emacsvox-eat--last-exited-process process)))

(defun emacsvox-eat--invalidate-all-buffer-state ()
  "Advance the generation of every initialized EAT speech buffer."
  (dolist (buffer (buffer-list))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (when (local-variable-p 'emacsvox-eat--generation)
          (emacsvox-eat--advance-generation))))))

(defun emacsvox--advice-eat-reset-before (&rest _)
  "Invalidate pending EAT speech state before resetting the terminal."
  (emacsvox-eat--advance-generation))

(defun emacsvox--advice-eat-reload-before (&rest _)
  "Invalidate pending speech state in every EAT buffer before reload."
  (emacsvox-eat--invalidate-all-buffer-state))

;;;  Map Faces:

(voice-setup-add-map
 '(
   (eat-shell-prompt-annotation-failure voice-lighten)
   (eat-shell-prompt-annotation-running voice-monotone)
   (eat-shell-prompt-annotation-success voice-animate)
   (eat-term-bold voice-bolden)
   (eat-term-italic voice-smoothen)))
;;; Eat Setup:

(defun emacsvox-eat-mode-setup ()
  "Placed on eat-mode-hook to do Emacsvox setup."
  (unless (local-variable-p 'emacsvox-eat--generation)
    (setq-local emacsvox-eat--generation 0
                emacsvox-eat--active-process
                (get-buffer-process (current-buffer))
                emacsvox-eat--last-exited-process nil))
  (define-key eat-semi-char-mode-map emacsvox-prefix 'emacsvox-keymap)
  (cl-loop
   for map in
   '(eat-line-mode-map eat-mode-map eat-char-mode-map)
   do
   (when (keymapp map) (define-key map emacsvox-prefix  'emacsvox-keymap))))

(add-hook 'eat-mode-hook 'emacsvox-eat-mode-setup)

;;;  Interactive Commands:

'(

  eat-input-char
  eat-kill-process
  eat-line-delchar-or-eof
  eat-line-find-input
  eat-line-history-isearch-backward
  eat-line-history-isearch-backward-regexp
  eat-line-load-input-history-from-file
  eat-line-next-input
  eat-line-next-matching-input
  eat-line-next-matching-input-from-input
  eat-line-previous-input
  eat-line-previous-matching-input
  eat-line-previous-matching-input-from-input
  eat-line-restore-input
  eat-line-send-input
  eat-line-send-interrupt
  eat-mouse-yank-primary
  eat-mouse-yank-secondary
  eat-narrow-to-shell-prompt
  eat-next-shell-prompt
  eat-other-window
  eat-previous-shell-prompt
  eat-project
  eat-project-other-window
  eat-quoted-input
  eat-reload
  eat-reset
  eat-self-input
  eat-send-password
  eat-trace-replay
  eat-trace-replay-next-frame
  eat-xterm-paste
  )

(defconst emacsvox-eat--yank-targets
  '(eat-yank eat-yank-from-kill-ring)
  "Eat commands that yank terminal input.")

(cl-loop
 for target in emacsvox-eat--yank-targets
 for advice-function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     ,(format "Play a yank icon after `%s'." target)
     (when (ems-interactive-p ',target)
       (emacsvox-icon 'yank-object)))))

(defun emacsvox--advice-eat-reload-after (&rest _)
  "Speak after reloading Eat."
  (emacsvox-eat--install-advice)
  (when (ems-interactive-p 'eat-reload)
    (emacsvox-icon 'task-done) (tts-speak "Reloaded Eat")))

(defun emacsvox--advice-eat-reset-after (&rest _)
  "Speak after resetting Eat."
  (when (ems-interactive-p 'eat-reset)
    (emacsvox-icon 'task-done) (tts-speak "Reset Eat")))

(defconst emacsvox-eat--mode-targets
  '(eat-blink-mode eat-char-mode eat-emacs-mode
    eat-eshell-char-mode eat-eshell-emacs-mode eat-eshell-mode
    eat-eshell-semi-char-mode eat-eshell-visual-command-mode
    eat-line-mode eat-mode eat-semi-char-mode
    eat-trace-mode eat-trace-replay-mode)
  "Eat mode-switching commands that receive speech feedback.")

(cl-loop
 for target in emacsvox-eat--mode-targets
 for advice-function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     ,(format "Speak after `%s'." target)
     (when (ems-interactive-p ',target)
       (emacsvox-icon 'button)
       (message "%s " ,(symbol-name target))))))

(defun emacsvox--advice-eat-after (&rest _)
  "Speak after opening Eat."
  (when (ems-interactive-p 'eat)
    (emacsvox-icon 'open-object) (emacsvox-speak-mode-line)))

(defconst emacsvox-eat--advice-targets
  (append emacsvox-eat--yank-targets
          '(eat-reload eat-reset)
          emacsvox-eat--mode-targets
          '(eat))
  "Current Eat targets that receive native after advice.")

(defconst emacsvox-eat--before-advice
  '((eat-reset . emacsvox--advice-eat-reset-before)
    (eat-reload . emacsvox--advice-eat-reload-before))
  "EAT targets and native before-advice used for state invalidation.")

(defun emacsvox-eat--install-advice ()
  "Install native advice after the optional Eat package loads."
  (dolist (target emacsvox-eat--advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target :after function '((name . emacsvox))))))
  (dolist (entry emacsvox-eat--before-advice)
    (let ((target (car entry))
          (function (cdr entry)))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target :before function '((name . emacsvox-state))))))
  (when
      (and
       (fboundp 'eat-self-input)
       (not
        (advice-member-p
         #'emacsvox--advice-eat-self-input-before 'eat-self-input)))
    (advice-add
     'eat-self-input :before #'emacsvox--advice-eat-self-input-before
     '((name . emacsvox)))))

(defun emacsvox-eat--tab-event-p (event)
  "Return non-nil when EVENT is a Tab key event."
  (and event (memq (event-basic-type event) '(9 tab))))

(defun emacsvox-eat--token-before-cursor (cursor)
  "Return the terminal token immediately before CURSOR."
  (when cursor
    (save-excursion
      (goto-char cursor)
      (skip-chars-backward " \t")
      (let ((end (point)))
        (skip-chars-backward "^ \t\n;|&<>()")
        (buffer-substring-no-properties (point) end)))))

(defun emacsvox-eat--capture-completion (cursor)
  "Capture the line and token at EAT terminal CURSOR."
  (setq emacsvox-eat--completion-snapshot
        (and cursor
             (cons (line-number-at-pos cursor)
                   (emacsvox-eat--token-before-cursor cursor)))))

(defun emacsvox--advice-eat-self-input-before (_count &optional event)
  "Capture same-line completion context before EAT sends Tab EVENT."
  (let ((event (or event last-command-event)))
    (if (and eat-terminal
             (bound-and-true-p eat--semi-char-mode)
             (emacsvox-eat--tab-event-p event))
        (emacsvox-eat--capture-completion
         (eat-term-display-cursor eat-terminal))
      (setq emacsvox-eat--completion-snapshot nil))))

(defun emacsvox-eat--completion-label (token)
  "Return the final path component of completed TOKEN."
  (let* ((length (length token))
         (directory-p (and (> length 0) (= (aref token (1- length)) ?/)))
         (trimmed (if directory-p (substring token 0 -1) token))
         (component (file-name-nondirectory trimmed)))
    (concat (if (zerop (length component)) trimmed component)
            (if directory-p "/" ""))))

(defun emacsvox-eat--speak-same-line-completion (cursor)
  "Speak a token extended by terminal completion at CURSOR.
Return non-nil after providing completion feedback.  Candidate listings that
move the cursor to another line deliberately fall through to ordinary EAT
update feedback."
  (let ((snapshot emacsvox-eat--completion-snapshot))
    (setq emacsvox-eat--completion-snapshot nil)
    (when snapshot
      (let ((old-line (car snapshot))
            (old-token (cdr snapshot))
            (new-token (emacsvox-eat--token-before-cursor cursor)))
        (when (and (= old-line (line-number-at-pos cursor))
                   (> (length old-token) 0)
                   (> (length new-token) (length old-token))
                   (string-prefix-p old-token new-token))
          (tts-speak (emacsvox-eat--completion-label new-token))
          t)))))

(defun emacsvox-eat--selected-buffer-p ()
  "Return non-nil when the current EAT buffer is selected."
  (eq (current-buffer) (window-buffer (selected-window))))

(with-eval-after-load 'eat
  (emacsvox-eat--install-advice))

;;; Speech-Enable Terminal Emulation:

(defun emacsvox-eat-update-hook ()
  "Speak an EAT update when its buffer is selected."
  (if (not (emacsvox-eat--selected-buffer-p))
      (setq emacsvox-eat--completion-snapshot nil)
    (let* ((emacsvox-show-point t)
           (cursor (eat-term-display-cursor eat-terminal))
           (char (and cursor (char-before cursor))))
      (unless (emacsvox-eat--speak-same-line-completion cursor)
        (cond
         ((eq char ?\s) (emacsvox-speak-line))
         (char (emacsvox-speak-this-char char)))))))

(add-hook 'eat-update-hook #'emacsvox-eat-update-hook)
(add-hook 'eat-exec-hook #'emacsvox-eat--process-started)
(add-hook 'eat-exit-hook #'emacsvox-eat--process-exited)
(provide 'emacsvox-eat)
;;;  end of file
