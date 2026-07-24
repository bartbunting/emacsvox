;;; emacsvox-which-key.el --- Speech-enable Which-Key -*- lexical-binding: t; -*-
;;
;; Description: Speech-enable Which-Key, a package that displays available keybindings
;; Keywords: Emacsvox, Audio Desktop, Which-Key, keybindings
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;;
;; Location https://github.com/robertmeta/emacsvox
;;

;;;   Copyright:

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

;;; Commentary:
;; Which-Key displays available keybindings in a popup after pressing
;; a prefix key. This module speech-enables Which-Key to provide auditory
;; feedback for available bindings, supporting navigation through pages
;; and speaking the current binding options.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'which-key nil 'noerror)

;;;  Silence byte-compiler about special variables:

(defvar which-key--buffer)
(defvar which-key--pages-obj)
(defvar which-key-init-buffer-hook)

;;;  Forward declarations:

(declare-function which-key--pages-height "which-key")
(declare-function which-key--pages-widths "which-key")
(declare-function which-key--popup-showing-p "which-key")
(declare-function which-key--current-key-string "which-key")

;;;  Map faces to voices:

(voice-setup-add-map
 '((which-key-key-face voice-bolden)
   (which-key-separator-face voice-smoothen)
   (which-key-note-face voice-annotate)
   (which-key-command-description-face voice-monotone)
   (which-key-local-map-description-face voice-brighten)
   (which-key-highlighted-command-face voice-animate)
   (which-key-group-description-face voice-bolden-medium)
   (which-key-special-key-face voice-lighten)
   (which-key-docstring-face voice-annotate)))

;;;  Bookkeeping variables:

(defvar emacsvox-which-key--page-cache nil
  "Cache of last which-key page content for speaking.")

(defvar emacsvox-which-key--auto-speak t
  "When non-nil, automatically speak which-key popups.")

;;;  Helper functions:

(defun emacsvox-which-key--speak-page ()
  "Speak current which-key page content."
  (when (and (bound-and-true-p which-key--buffer)
             (buffer-live-p which-key--buffer))
    (with-current-buffer which-key--buffer
      (let ((content (buffer-string)))
        (unless (string-empty-p content)
          (setq emacsvox-which-key--page-cache content)
          (tts-speak content))))))

(defun emacsvox-which-key--page-info ()
  "Return current page info as string."
  (when (bound-and-true-p which-key--pages-obj)
    (let* ((pages which-key--pages-obj)
           (current (1+ (plist-get pages :page-nums)))
           (total (plist-get pages :num-pages)))
      (when (and current total (> total 1))
        (format "page %d of %d" current total)))))

(defun emacsvox-which-key--speak-page-with-info ()
  "Speak current page with page number info."
  (let ((page-info (emacsvox-which-key--page-info)))
    (when page-info
      (tts-speak page-info))
    (emacsvox-which-key--speak-page)))

;;;  Interactive command to speak cached content:

(defun emacsvox-which-key-speak ()
  "Speak the current or last which-key popup content."
  (interactive)
  (cond
   ((and (bound-and-true-p which-key--buffer)
         (buffer-live-p which-key--buffer)
         (which-key--popup-showing-p))
    (emacsvox-which-key--speak-page-with-info))
   (emacsvox-which-key--page-cache
    (tts-speak emacsvox-which-key--page-cache))
   (t (message "No which-key content available"))))

;;;  Advice interactive commands:

(defun emacsvox--advice-which-key--show-page-after (&rest _)
  "Speak the which-key page."
  (when emacsvox-which-key--auto-speak
    (emacsvox-icon 'help)
    (emacsvox-which-key--speak-page)))

(advice-add
 'which-key--show-page :after
 #'emacsvox--advice-which-key--show-page-after
 '((name . emacsvox)))

(defun emacsvox--advice-which-key--hide-popup-after (&rest _)
  "Announce popup hidden."
  (when (ems-interactive-p 'which-key--hide-popup)
    (tts-stop 'all)
    (emacsvox-icon 'close-object)))

(advice-add
 'which-key--hide-popup :after
 #'emacsvox--advice-which-key--hide-popup-after
 '((name . emacsvox)))

(defun emacsvox--advice-which-key-abort-after (&rest _)
  "Speak abort feedback."
  (when (ems-interactive-p 'which-key-abort)
    (tts-stop 'all)
    (emacsvox-icon 'close-object)))

(advice-add
 'which-key-abort :after
 #'emacsvox--advice-which-key-abort-after
 '((name . emacsvox)))

(defun emacsvox--advice-which-key-undo-key-after (&rest _)
  "Speak undo feedback."
  (when (ems-interactive-p 'which-key-undo-key)
    (emacsvox-icon 'item)
    (tts-speak "undo")))

(advice-add
 'which-key-undo-key :after
 #'emacsvox--advice-which-key-undo-key-after
 '((name . emacsvox)))

(defun emacsvox--advice-which-key-show-standard-help-before (&rest _)
  "Announce showing help."
  (when (ems-interactive-p 'which-key-show-standard-help)
    (emacsvox-icon 'help)))

(advice-add
 'which-key-show-standard-help :before
 #'emacsvox--advice-which-key-show-standard-help-before
 '((name . emacsvox)))

;;; Batch advice for paging commands:

(cl-loop
 for target in
 '(which-key-show-next-page-cycle
   which-key-show-previous-page-cycle
   which-key-show-next-page-no-cycle
   which-key-show-previous-page-no-cycle)
 for function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Speak page info after interactive Which-Key paging."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'scroll)
         (let ((page-info (emacsvox-which-key--page-info)))
           (when page-info (tts-speak page-info)))))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

;;; Batch advice for show commands:

(cl-loop
 for target in
 '(which-key-show-top-level
   which-key-show-major-mode
   which-key-show-full-major-mode
   which-key-show-minor-mode-keymap
   which-key-show-keymap)
 for function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Announce an interactive Which-Key display."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'open-object)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

;;;  Toggle auto-speak:

(defun emacsvox-which-key-toggle-auto-speak ()
  "Toggle automatic speaking of which-key popups."
  (interactive)
  (setq emacsvox-which-key--auto-speak (not emacsvox-which-key--auto-speak))
  (emacsvox-icon (if emacsvox-which-key--auto-speak 'on 'off))
  (message "Which-key auto-speak %s"
           (if emacsvox-which-key--auto-speak "enabled" "disabled")))

;;;  Setup:

(defun emacsvox-which-key-setup ()
  "Setup Emacsvox support for Which-Key."
  (when (boundp 'which-key-init-buffer-hook)
    (add-hook 'which-key-init-buffer-hook
              #'(lambda () (emacsvox-icon 'open-object)))))

(eval-after-load "which-key" #'emacsvox-which-key-setup)

(provide 'emacsvox-which-key)
;;;  end of file
