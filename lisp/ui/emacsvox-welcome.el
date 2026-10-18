;;; emacsvox-welcome.el --- Getting started with the audio desktop -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: Emacsvox contributors
;; Maintainer: Emacsvox contributors
;; Keywords: accessibility, multimedia
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

;; A short, keyboard-accessible introduction.  The startup preference belongs
;; to the Emacs profile, independently of the application installation.

;;; Code:

(require 'button)
(require 'subr-x)
(require 'seq)

(declare-function tts-speak "tts-speak" (text))
(declare-function tts-set-rate "tts-speak" (rate &optional prefix))
(declare-function emacsvox-open-info "emacsvox-speak" ())
(declare-function emacsvox-aural-home-browse-voices "emacsvox-aural-home" ())
(defvar tts-speaker-process)
(defvar tts-program)

(defgroup emacsvox-welcome nil
  "Getting started with Emacsvox."
  :group 'emacsvox)

(defcustom emacsvox-welcome-show-at-startup t
  "Whether to offer the welcome screen at startup.
The screen's toggle remembers an explicit choice in this Emacs profile.
A saved choice takes precedence over this default.  Explicitly opened files,
automated speech checks, and sessions already in use keep their current buffer."
  :type 'boolean :group 'emacsvox-welcome)

(defvar emacsvox-welcome--startup-finished nil)
(defvar emacsvox-welcome--ready nil)
(defvar emacsvox-welcome--offered nil)
(defvar emacsvox-welcome--initial-input nil)
(defvar emacsvox-welcome--timer nil)

(defun emacsvox-welcome--preference-file ()
  "Return the preference file for the current profile."
  (expand-file-name "emacsvox-welcome-state" user-emacs-directory))

(defun emacsvox-welcome--enabled-p ()
  "Read the saved preference as data, falling back to the configured default."
  (condition-case nil
      (with-temp-buffer
        (insert-file-contents (emacsvox-welcome--preference-file) nil 0 16)
        (pcase (buffer-string)
          ("show\n" t) ("hide\n" nil)
          (_ emacsvox-welcome-show-at-startup)))
    (file-error emacsvox-welcome-show-at-startup)))

(defun emacsvox-welcome-toggle-startup ()
  "Toggle and persist the startup welcome choice in this Emacs profile."
  (interactive)
  (let* ((enabled (not (emacsvox-welcome--enabled-p)))
         (file (emacsvox-welcome--preference-file)) temporary)
    (make-directory (file-name-directory file) t)
    (unwind-protect
        (progn
          (setq temporary (make-temp-file (concat file "-")))
          (with-temp-file temporary (insert (if enabled "show\n" "hide\n")))
          (rename-file temporary file t))
      (when (and temporary (file-exists-p temporary)) (delete-file temporary)))
    (emacsvox-welcome--render)
    (goto-char (point-max))
    (search-backward "Show this welcome")
    (tts-speak (if enabled "Show welcome at startup: on" "Show welcome at startup: off"))))

(defun emacsvox-welcome-test-speech ()
  "Play a short sample using the current speech settings."
  (interactive)
  (tts-speak "Welcome to Emacsvox. This is your current speaking voice."))

(defun emacsvox-welcome-output ()
  "Open the speech, tones, earcons and notification output settings."
  (interactive)
  (customize-group 'tts-output))

(defun emacsvox-welcome-voices ()
  "Open voice and engine browsing."
  (interactive)
  (require 'emacsvox-aural-home)
  (emacsvox-aural-home-browse-voices))

(defun emacsvox-welcome-next (&optional backward)
  "Move to and speak the next action, or the previous with BACKWARD."
  (interactive)
  (forward-button (if backward -1 1) t t)
  (when-let* ((button (button-at (point))))
    (tts-speak (button-label button))))

(defun emacsvox-welcome-previous ()
  "Move to and speak the previous action."
  (interactive)
  (emacsvox-welcome-next t))

(defvar-keymap emacsvox-welcome-mode-map
  :parent special-mode-map
  "TAB" #'emacsvox-welcome-next
  "<backtab>" #'emacsvox-welcome-previous
  "n" #'emacsvox-welcome-next
  "p" #'emacsvox-welcome-previous
  "RET" #'push-button
  "SPC" #'push-button)

(define-derived-mode emacsvox-welcome-mode special-mode "Emacsvox Welcome"
  "Getting started.  TAB and Shift-TAB choose actions; RET activates; q returns."
  (setq-local truncate-lines nil))

(defun emacsvox-welcome--render ()
  "Render the welcome page without playing speech."
  (let ((inhibit-read-only t))
    (erase-buffer)
    (insert "Welcome to Emacsvox\n\n"
            "Emacsvox speaks as you work in Emacs.\n"
            "TAB / Shift-TAB: choose an action. RET: activate. q: return.\n\n")
    (dolist (entry '(("Test speech" . emacsvox-welcome-test-speech)
                     ("Adjust speech rate" . tts-set-rate)
                     ("Adjust volumes and output" . emacsvox-welcome-output)
                     ("Choose voices and engines" . emacsvox-welcome-voices)
                     ("Emacs tutorial" . help-with-tutorial)
                     ("Emacsvox manual" . emacsvox-open-info)
                     ("Start using Emacs" . quit-window)))
      (insert-text-button (car entry) 'follow-link t
                          'action (lambda (_) (call-interactively (cdr entry))))
      (insert "\n"))
    (insert "\nBasic keys\n"
            "Arrow keys move and speak. C-e l speaks the current line.\n"
            "C-e s stops speech. C-e H opens voices, sounds and settings.\n"
            "C-h t opens the Emacs tutorial. C-h C-e describes Emacsvox.\n"
            "C-g cancels an unfinished command. C-x C-c exits Emacs.\n\n")
    (insert-text-button
     (format "[%s] Show this welcome screen at startup"
             (if (emacsvox-welcome--enabled-p) "X" " "))
     'follow-link t 'action (lambda (_) (emacsvox-welcome-toggle-startup)))
    (insert "\nReopen at any time with C-h W or M-x emacsvox-welcome.\n")
    (goto-char (point-min))))

;;;###autoload
(defun emacsvox-welcome ()
  "Open the Emacsvox getting-started screen and speak a short introduction."
  (interactive)
  (let ((buffer (get-buffer-create "*Emacsvox Welcome*")))
    (with-current-buffer buffer
      (emacsvox-welcome-mode)
      (emacsvox-welcome--render))
    (pop-to-buffer-same-window buffer)
    (tts-speak "Welcome to Emacsvox. Press Tab to choose an action, Enter to open it, or q to return.")))

(defun emacsvox-welcome--maybe-show ()
  "Offer welcome once after startup and speech readiness, before user activity."
  (setq emacsvox-welcome--timer nil)
  (when (and emacsvox-welcome--startup-finished emacsvox-welcome--ready
             (not emacsvox-welcome--offered))
    (setq emacsvox-welcome--offered t)
    (when (and (not noninteractive)
               (not (getenv "EMACSVOX_NATIVE_RESULT"))
               (emacsvox-welcome--enabled-p)
               (equal emacsvox-welcome--initial-input num-input-keys)
               (not (active-minibuffer-window))
               (member (buffer-name) '("*scratch*" "*GNU Emacs*"))
               (not (buffer-modified-p))
               (not (seq-some (lambda (buffer) (buffer-file-name buffer)) (buffer-list))))
      (emacsvox-welcome))))

(defun emacsvox-welcome--routing-ready (process)
  "Defer the welcome screen until outside main speech PROCESS's filter."
  (when (eq process tts-speaker-process)
    (setq emacsvox-welcome--ready t)
    (unless emacsvox-welcome--timer
      (setq emacsvox-welcome--timer (run-at-time 0.1 nil #'emacsvox-welcome--maybe-show)))))

(defun emacsvox-welcome--startup ()
  "Record startup completion and offer welcome when speech is ready."
  (setq emacsvox-welcome--startup-finished t)
  (emacsvox-welcome--maybe-show))

(defun emacsvox-welcome--initialize ()
  "Arrange the first startup offer without blocking initialization."
  (unless (or noninteractive emacsvox-welcome--initial-input)
    (setq emacsvox-welcome--initial-input num-input-keys)
    (add-hook 'emacs-startup-hook #'emacsvox-welcome--startup)
    (add-hook 'omnivox-initial-routing-ready-hook #'emacsvox-welcome--routing-ready)
    ;; Other adapters have synchronous initialization rather than this hook.
    (unless (string-match-p "omnivox" (or tts-program ""))
      (setq emacsvox-welcome--ready t))))

(provide 'emacsvox-welcome)
;;; emacsvox-welcome.el ends here
