;;; emacsvox-view.el --- Speech enable View mode - -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; DescriptionEmacsvox extensions for view
;; Keywords:emacsvox, audio interface to emacs, view-mode
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
;; Copyright (c) 1996 by T. V. Raman
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



;;; Commentary:
;; Provide additional advice to view-mode
;;; Code:

;;;  requires
(require 'emacsvox-preamble)
(require 'view)

;;;   Setup view mode to work with emacsvox

;; restore emacsvox keybindings:
(cl-declaim (special emacsvox-prefix))

(add-hook
 'view-mode-hook
 #'(lambda ()
     (local-unset-key emacsvox-prefix)
     (emacsvox-speak-load-directory-settings)
     (outline-minor-mode 1))
 'at-end)

;;;  Advise additional interactive commands:

(defun emacsvox--advice-view-mode-after (&rest _)
  "Announce an interactive change to View mode."
  (when (ems-interactive-p 'view-mode)
    (emacsvox-icon 'open-object)
    (if view-mode
        (message "Entered view mode Press %s to exit"
                 (key-description
                  (where-is-internal 'View-exit view-mode-map
                                     'firstonly)))
      (message "Exited view mode"))))

(advice-add
 'view-mode :after #'emacsvox--advice-view-mode-after
 '((name . emacsvox)))

(cl-loop
 for target in
 '(View-exit-and-edit View-kill-and-leave View-quit-all View-quit)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue an interactive View exit and speak the resulting mode line."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'close-object)
         (emacsvox-speak-mode-line)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(cl-loop
 for target in
 '(view-buffer view-buffer-other-frame view-buffer-other-window
   view-emacs-FAQ view-emacs-debugging view-emacs-problems
   view-emacs-todo view-external-packages view-file-other-frame
   view-file-other-window view-hello-file view-lossage)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue an interactive View entry and speak the resulting mode line."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'open-object)
         (emacsvox-speak-mode-line)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(cl-loop
 for target in
 '(View-search-regexp-forward View-search-regexp-backward
   View-search-last-regexp-backward View-search-last-regexp-forward)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Speak and cue an interactive View search result."
       (when (ems-interactive-p ',target)
         (let ((emacsvox-show-point t))
           (emacsvox-speak-line))
         (emacsvox-icon 'search-hit)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(cl-loop
 for target in
 '(View-scroll-half-page-backward View-scroll-half-page-forward
   View-scroll-line-backward View-scroll-line-forward
   View-scroll-page-backward View-scroll-page-forward
   View-scroll-page-backward-set-page-size
   View-scroll-page-forward-set-page-size)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue an interactive View scroll and speak the resulting window."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'scroll)
         (emacsvox-speak-windowful)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(defun emacsvox--advice-View-back-to-mark-after (&rest _)
  "Speak after interactively returning to a View mark."
  (when (ems-interactive-p 'View-back-to-mark)
    (emacsvox-icon 'large-movement)
    (let ((emacsvox-show-point t)) (emacsvox-speak-line))))

(advice-add
 'View-back-to-mark :after #'emacsvox--advice-View-back-to-mark-after
 '((name . emacsvox)))

(defun emacsvox--advice-View-goto-line-after (&optional line)
  "Speak LINE after an interactive `View-goto-line'."
  (when (ems-interactive-p 'View-goto-line)
    (let ((line-number (format "line %s" line)))
      (put-text-property 0 (length line-number) 'personality
                         voice-annotate line-number)
      (emacsvox-icon 'large-movement)
      (dtk-speak (concat line-number (ems--this-line))))))

(advice-add
 'View-goto-line :after #'emacsvox--advice-View-goto-line-after
 '((name . emacsvox)))

(defun emacsvox--advice-View-scroll-to-buffer-end-after (&rest _)
  "Speak after interactively scrolling to the end of a View buffer."
  (when (ems-interactive-p 'View-scroll-to-buffer-end)
    (emacsvox-speak-line) (emacsvox-icon 'large-movement)))

(advice-add
 'View-scroll-to-buffer-end :after
 #'emacsvox--advice-View-scroll-to-buffer-end-after
 '((name . emacsvox)))

(defun emacsvox--advice-View-goto-percent-after (&rest _)
  "Speak after interactively moving to a percentage of a View buffer."
  (when (ems-interactive-p 'View-goto-percent)
    (emacsvox-icon 'scroll)
    (dtk-speak (emacsvox-get-window-contents))))

(advice-add
 'View-goto-percent :after #'emacsvox--advice-View-goto-percent-after
 '((name . emacsvox)))

;;;  bind convenience keys

(defun emacsvox-view-setup-keys()
  "Setup emacsvox convenience keys"
  
  (cl-loop
   for  b in
   '(
     ("," 'emacsvox-speak-current-window)
     ("C-j" 'emacsvox-hide-speak-block-sans-prefix)
     ("M-d" 'emacsvox-pronounce-dispatch)
     ("M-n" 'outline-next-visible-heading)
     ("M-p" 'outline-previous-visible-heading)
     ("SPC" 'scroll-up)
     ("[" 'backward-page)
     ("]" 'forward-page)
     ("b" backward-word)
     ("c" 'emacsvox-speak-char)
     ("d" 'scroll-down)
     ("f" forward-word)
     ("h" left-char)
     ("j" next-line)
     ("k" previous-line)
     ("l" right-char)
     ("w" emacsvox-speak-word)
     )
   do
   (emacsvox-keymap-update view-mode-map b))
  (cl-loop
   for i from 0 to 9
   do
   (define-key view-mode-map (format "%s" i) 'dtk-set-predefined-rate)))

(emacsvox-view-setup-keys)

(provide  'emacsvox-view)
