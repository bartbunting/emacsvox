;;; emacsvox-ido.el --- speech-enable ido  -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:   extension to speech enable ido
;; Keywords: Emacsvox, Audio Desktop
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;; 
;;  $Revision: 4555 $ |
;; Location https://github.com/robertmeta/emacsvox
;; 

;;;   Copyright:

;; Copyright (C) 1995 -- 2024, T. V. Raman<tv.raman.tv@gmail.com>
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

;; speech-enable ido.el This is an interesting task since most of the
;; value-add provided by package ido.el is visual feedback.  Speech UI
;; Challenge: What is the most efficient means of conveying a
;; dynamically updating set of choices?  current strategy is to walk
;; the list using c-s and c-r as provided by ido Set number matches
;; shown (ido-max-prospects) to 2 or 3 using Custom so you dont hear the
;; entire list. You can also customize @var{ido-decorations} to taste.
;; See
;; @url{https://emacsvox.blogspot.com/2018/06/\
;;effective-suggest-and-complete-in-eyes.html},
;; for an article on how to reason about designing  good auditory
;; interfaces for these types of situations.
;;; Code:


;;  required modules

(require 'emacsvox-preamble)
(require 'ido)

;;;  speech-enable feedback routines

(defvar emacsvox-ido-cache nil
  "Cached value of ido-current-directory.")

(defun emacsvox--advice-ido-set-current-directory-before (&rest _)
  "Cache previous value of ido-current-directory."
  (emacsvox-icon 'item)
  (setq emacsvox-ido-cache ido-current-directory))

(advice-add
 'ido-set-current-directory :before
 #'emacsvox--advice-ido-set-current-directory-before
 '((name . emacsvox--advice-ido-set-current-directory-before)))

(defgroup emacsvox-ido nil
  "IDO Completions On The emacsvox Audio Desktop."
  :group  'emacsvox)

(defvar emacsvox-ido-typing-delay 0.15
  "How long we wait before speaking completions.")

(defun emacsvox--advice-ido-exhibit-after (&rest _)
  "Speak ido minibuffer intelligently."
  (when ido-matches
    (when (> (length ido-matches) ido-max-prospects)
      (emacsvox-icon 'ellipses))
    (dtk-notify
     (concat (minibuffer-contents)
             (format " %d choices: " (length ido-matches))
             (if
                 (or (null ido-current-directory)
                     (string-equal ido-current-directory
                                   emacsvox-ido-cache))
                 " "
               (format "In %s"
                       (abbreviate-file-name ido-current-directory)))))))

(advice-add
 'ido-exhibit :after
 #'emacsvox--advice-ido-exhibit-after
 '((name . emacsvox--advice-ido-exhibit-after)))

;;;  speech-enable interactive commands:

(defmacro emacsvox-ido--define-advice (target where &rest body)
  "Define direct WHERE advice for interactive IDO TARGET."
  (declare (indent 2))
  (let ((function
         (intern (format "emacsvox--advice-%s-%s"
                         target
                         (substring (symbol-name where) 1)))))
    `(progn
       (defun ,function (&rest _)
         ,(format "Provide spoken feedback %s `%s'." where target)
         (when (ems-interactive-p ',target)
           ,@body))
       (advice-add
        ',target ,where #',function
        '((name . ,function))))))

(emacsvox-ido--define-advice ido-mode :after
  (emacsvox-icon (if ido-mode 'on 'off))
  (dtk-speak (format "IDo set to %s" ido-mode)))

(emacsvox-ido--define-advice ido-everywhere :after
  (emacsvox-icon (if ido-everywhere 'on 'off))
  (dtk-speak
   (format "Turned %s IDo everywhere."
           (if ido-everywhere " on " " off "))))

(emacsvox-ido--define-advice ido-toggle-case :after
  (emacsvox-icon (if ido-case-fold 'on 'off))
  (dtk-speak (format "Case %s" (if ido-case-fold 'on 'off))))

(emacsvox-ido--define-advice ido-toggle-regexp :after
  (emacsvox-icon (if ido-enable-regexp 'on 'off))
  (dtk-speak (format "Regexp %s" (if ido-enable-regexp 'on 'off))))

(emacsvox-ido--define-advice ido-toggle-prefix :after
  (emacsvox-icon (if ido-enable-prefix 'on 'off))
  (dtk-speak (format "Prefix %s" (if ido-enable-prefix 'on 'off))))

(emacsvox-ido--define-advice ido-toggle-ignore :after
  (emacsvox-icon (if ido-ignore-files 'on 'off))
  (dtk-speak
   (format "File ignoring  %s" (if ido-ignore-files 'on 'off))))

(emacsvox-ido--define-advice ido-complete :after
  (dtk-speak (car ido-matches)))

(cl-loop
 for target in
 '(
   ido-switch-buffer ido-switch-buffer-other-window
   ido-switch-buffer-other-frame ido-display-buffer
   ido-find-file ido-find-file-other-frame ido-find-file-other-window
   ido-find-alternate-file ido-find-file-read-only
   ido-find-file-read-only-other-window ido-find-file-read-only-other-frame)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak the result of an interactive IDO command."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'open-object)
         (emacsvox-speak-mode-line)))
     (advice-add
      ',target :after #',function '((name . ,function))))))

(dolist
    (target '(ido-bury-buffer-at-head ido-kill-buffer-at-head))
  (eval
   `(emacsvox-ido--define-advice ,target :after
      (emacsvox-icon 'close-object))))

(emacsvox-ido--define-advice ido-kill-buffer :after
  (emacsvox-icon 'close-object)
  (emacsvox-speak-mode-line))

(emacsvox-ido--define-advice ido-fallback-command :before
  (emacsvox-icon 'close-object)
  (emacsvox-icon 'open-object))

;;;  define personalities 

(voice-setup-add-map
 '(
   (ido-virtual voice-smoothen)
   (ido-first-match voice-bolden)
   (ido-only-match voice-lighten)
   (ido-subdir voice-monotone)
   (ido-indicator voice-brighten)
   (ido-incomplete-regexp voice-monotone-extra)
   (flx-highlight-face voice-animate)))

;;;  Additional keybindings 

(defun emacsvox-ido-keys ()
  "Setup additional  keybindings within ido."
  
  (when (boundp 'ido-common-completion-map)
    (define-key  ido-common-completion-map
                 (kbd "C-z") 'emacsvox-z-keymap)
    (define-key ido-common-completion-map (kbd "C-f") 'ido-enter-find-file)
    (define-key ido-common-completion-map "^" 'ido-up-directory)
    (define-key ido-common-completion-map emacsvox-prefix 'emacsvox-keymap)
    (define-key ido-common-completion-map (kbd "M-e")  'ido-edit-input)))

(emacsvox-ido-keys)

(provide 'emacsvox-ido)
;;;  end of file
