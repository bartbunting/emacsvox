;;; emacsvox-speedbar.el --- speedbar - -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $ 
;; Description: Auditory interface to speedbar
;; Keywords: Emacsvox, Speedbar
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

;;;   Introduction

;;; Commentary:

;; This module advises speedbar.el for use with Emacs.  The
;; latest speedbar can be obtained from
;; ftp://ftp.ultranet.com/pub/zappo/ This module ensures
;; that speedbar works smoothly outside a windowing system
;; in addition to speech enabling all interactive
;; commands. Emacsvox also adds an Emacsvox environment
;; specific entry point to speedbar
;; --emacsvox-speedbar-goto-speedbar-- and binds this

;;; Code:

;;; Forward variable declarations:

(defvar speedbar-hide-button-brackets-flag)
(defvar speedbar-mode-map)

;;   Required modules:

(require 'emacsvox-preamble)
(require 'speedbar "speedbar" 'no-error)

;;;  Helper:

(defun emacsvox-speedbar-speak-line()
  "Speak a line in the speedbar display"
  (let ((indent nil))  
    (save-excursion
      (beginning-of-line)
      (setq indent 
            (save-excursion
              (save-match-data
                (beginning-of-line)
                (string-to-number
                 (if (looking-at "[0-9]+")
                     (buffer-substring-no-properties
                      (match-beginning 0) (match-end 0))
                   "0")))))
      (setq indent 
            (if (zerop indent) "" indent))
      (tts-speak
       (concat indent (ems--this-line))))))

;;;  Advice interactive commands:

(defun emacsvox--advice-dframe-close-frame-around (orig-fun &rest args)
  "Cue the buffer selected after closing a Speedbar frame."
  (let ((speedbar-p (derived-mode-p 'speedbar-mode)))
    (prog1 (apply orig-fun args)
      (when (and speedbar-p
                 (ems-interactive-p 'dframe-close-frame))
        (emacsvox-icon 'close-object)
        (emacsvox-speak-mode-line)))))

(advice-add 'dframe-close-frame :around
            #'emacsvox--advice-dframe-close-frame-around)

(defun emacsvox--advice-speedbar-next-around (orig-fun arg)
  "Provide spoken feedback after moving forward by ARG."
  (if (ems-interactive-p 'speedbar-next)
      (let ((emacsvox-speak-messages nil))
        (prog1 (funcall orig-fun arg)
          (emacsvox-speedbar-speak-line)
          (emacsvox-icon 'select-object)))
    (funcall orig-fun arg)))

(advice-add 'speedbar-next :around
            #'emacsvox--advice-speedbar-next-around)

(defun emacsvox--advice-speedbar-prev-around (orig-fun arg)
  "Provide spoken feedback after moving backward by ARG."
  (if (ems-interactive-p 'speedbar-prev)
      (let ((emacsvox-speak-messages nil))
        (prog1 (funcall orig-fun arg)
          (emacsvox-speedbar-speak-line)
          (emacsvox-icon 'select-object)))
    (funcall orig-fun arg)))

(advice-add 'speedbar-prev :around
            #'emacsvox--advice-speedbar-prev-around)

(defun emacsvox--advice-speedbar-edit-line-after (&rest _)
  "Cue a successful interactive selection."
  (when (ems-interactive-p 'speedbar-edit-line)
    (emacsvox-icon 'large-movement)))

(advice-add 'speedbar-edit-line :after
            #'emacsvox--advice-speedbar-edit-line-after)

(defun emacsvox--advice-speedbar-tag-find-after (&rest _)
  "Speak the line selected by a tag operation."
  (emacsvox-speedbar-speak-line))

(advice-add 'speedbar-tag-find :after
            #'emacsvox--advice-speedbar-tag-find-after)

(defun emacsvox--advice-speedbar-find-file-after (&rest _)
  "Speak the mode line after selecting a file."
  (emacsvox-icon 'select-object)
  (emacsvox-speak-mode-line))

(advice-add 'speedbar-find-file :after
            #'emacsvox--advice-speedbar-find-file-after)

(defun emacsvox--advice-speedbar-expand-line-after (&rest _)
  "Speak the line expanded interactively."
  (when (ems-interactive-p 'speedbar-expand-line)
    (emacsvox-speedbar-speak-line)
    (emacsvox-icon 'open-object)))

(advice-add 'speedbar-expand-line :after
            #'emacsvox--advice-speedbar-expand-line-after)

(defun emacsvox--advice-speedbar-contract-line-after (&rest _)
  "Speak the line contracted interactively."
  (when (ems-interactive-p 'speedbar-contract-line)
    (emacsvox-speedbar-speak-line)
    (emacsvox-icon 'close-object)))

(advice-add 'speedbar-contract-line :after
            #'emacsvox--advice-speedbar-contract-line-after)

(defun emacsvox--advice-speedbar-up-directory-around (orig-fun)
  "Cue and speak the directory selected by an interactive move."
  (prog1 (funcall orig-fun)
    (when (ems-interactive-p 'speedbar-up-directory)
      (emacsvox-icon 'large-movement)
      (emacsvox-speedbar-speak-line))))

(advice-add 'speedbar-up-directory :around
            #'emacsvox--advice-speedbar-up-directory-around)

(defun emacsvox--advice-speedbar-restricted-next-after (&rest _)
  "Speak after restricted forward movement."
  (when (ems-interactive-p 'speedbar-restricted-next)
    (emacsvox-icon 'large-movement)
    (emacsvox-speedbar-speak-line)))

(advice-add 'speedbar-restricted-next :after
            #'emacsvox--advice-speedbar-restricted-next-after)

(defun emacsvox--advice-speedbar-restricted-prev-after (&rest _)
  "Speak after restricted backward movement."
  (when (ems-interactive-p 'speedbar-restricted-prev)
    (emacsvox-icon 'large-movement)
    (emacsvox-speedbar-speak-line)))

(advice-add 'speedbar-restricted-prev :after
            #'emacsvox--advice-speedbar-restricted-prev-after)

;;;  additional navigation

(defvar emacsvox-speedbar-disable-updates t
  "Non nil means speedbar does not automatically update.
An automatically updating speedbar consumes resources.")

(defun emacsvox-speedbar-goto-speedbar ()
  "Switch to the speedbar"
  (interactive)
  
  (unless (get-buffer " SPEEDBAR")
    (speedbar-frame-mode))
  (pop-to-buffer (get-buffer " SPEEDBAR"))
  (set-window-dedicated-p (selected-window) nil)
  (setq voice-lock-mode t)
  (when emacsvox-speedbar-disable-updates 
    (speedbar-stealthy-updates)
    (speedbar-disable-update))
  (emacsvox-icon 'select-object)
  (tts-speak
   (concat "Speedbar: "
           (let ((start nil))
             (save-excursion 
               (beginning-of-line)
               (setq start (point))
               (end-of-line)
               (buffer-substring start (point)))))))

(defun emacsvox-speedbar-click ()
  "Does the equivalent of the mouse click from the keyboard"
  (interactive)
  (save-excursion
    (beginning-of-line)
    (let ((target
           (if (get-text-property (point) 'speedbar-function)
               (point)
             (next-single-property-change (point)
                                          'speedbar-function)))
          (action-char nil))
      (cond 
       (target (goto-char target)
               (speedbar-do-function-pointer)
               (forward-char 1)
               (setq action-char (following-char))
               (emacsvox-speedbar-speak-line)
               (emacsvox-icon
                (cl-case action-char
                  (?+ 'open-object)
                  (?- 'close-object)
                  (t 'large-movement))))
       (t (message "No target on this line"))))))

;;;   hooks
(cl-eval-when (load)
  )
(defun emacsvox-speedbar-enter-hook ()
  "Actions taken when we enter the Speedbar"
  (tts-set-punctuations 'all)
  (setq speedbar-hide-button-brackets-flag t)
  (define-key speedbar-mode-map "f"
              'emacsvox-speedbar-click)
                                        ;(define-key speedbar-mode-map "\M-n"
                                        ;'emacsvox-speedbar-forward)
                                        ;(define-key speedbar-mode-map "\M-p"
                                        ;'emacsvox-speedbar-backward)
  )

(add-hook 'speedbar-mode-hook
          'emacsvox-speedbar-enter-hook)

;;;   voice locking 
;; Map speedbar faces to voices
;;
(defvar emacsvox-speedbar-button-personality  voice-bolden
  "personality used for speedbar buttons")

(defvar emacsvox-speedbar-selected-personality  voice-animate
  "Personality used to indicate speedbar selection")

(defvar emacsvox-speedbar-directory-personality voice-bolden-medium
  "Speedbar personality for directory buttons"
  )

(defvar emacsvox-speedbar-file-personality  'paul
  "Personality used for file buttons")

(defvar emacsvox-speedbar-highlight-personality voice-animate
  "Personality used for for speedbar highlight.")

(defvar emacsvox-speedbar-tag-personality voice-monotone-extra
  "Personality used for speedbar tags")

(defvar emacsvox-speedbar-default-personality 'paul
  "Default personality used in speedbar buffers")

(defun emacsvox--advice-speedbar-make-button-after
    (start end face &rest _)
  "Voiceify the button between START and END according to FACE."
  (let ((personality nil))
    (setq personality
          (cond
           ((eq face 'speedbar-button-face)
            emacsvox-speedbar-button-personality)
           ((eq face 'speedbar-selected-face)
            emacsvox-speedbar-selected-personality)
           ((eq face 'speedbar-directory-face)
            emacsvox-speedbar-directory-personality)
           ((eq face 'speedbar-file-face)
            emacsvox-speedbar-file-personality)
           ((eq face 'speedbar-highlight-face)
            emacsvox-speedbar-highlight-personality)
           ((eq face 'speedbar-tag-face)
            emacsvox-speedbar-tag-personality)
           (t 'emacsvox-speedbar-default-personality)))
    (put-text-property start end 'personality personality)
    (save-excursion (save-match-data (beginning-of-line)))))

(advice-add 'speedbar-make-button :after
            #'emacsvox--advice-speedbar-make-button-after)

;;;  keys 
(cl-declaim (special emacsvox-keymap))

(provide 'emacsvox-speedbar)
;;;  end of file 
