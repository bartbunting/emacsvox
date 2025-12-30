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
;; Location https://github.com/tvraman/emacsvox
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

;;   Required modules:

(cl-declaim  (optimize  (safety 0) (speed 3)))
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
      (dtk-speak 
       (concat indent (ems--this-line))))))

;;;  Advice interactive commands:


(defun ems--speedbar-close-frame-after (&rest _)
  "Cue buffer that becomes active"
  (when (ems-interactive-p)
    (emacsvox-icon 'close-object) (emacsvox-speak-mode-line)))


(advice-add 'speedbar-close-frame :after
	    #'ems--speedbar-close-frame-after)





(defun ems--speedbar-next-around (orig-fun &rest args)
  "Provide reasonable spoken feedback"
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p)
      (let ((emacsvox-speak-messages nil))
	(apply orig-fun args) (emacsvox-speedbar-speak-line)
	(emacsvox-icon 'select-object)))
     (t (apply orig-fun args)))
    result))


(advice-add 'speedbar-next :around #'ems--speedbar-next-around)




(defun ems--speedbar-prev-around (orig-fun &rest args)
  "Provide reasonable spoken feedback"
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p)
      (let ((emacsvox-speak-messages nil))
	(apply orig-fun args) (emacsvox-speedbar-speak-line)
	(emacsvox-icon 'select-object)))
     (t (apply orig-fun args)))
    result))


(advice-add 'speedbar-prev :around #'ems--speedbar-prev-around)




(defun ems--speedbar-edit-line-after (&rest _)
  "Speak line you jumped to"
  (when (ems-interactive-p) (emacsvox-icon 'large-movement)))


(advice-add 'speedbar-edit-line :after #'ems--speedbar-edit-line-after)





(defun ems--speedbar-tag-find-after (&rest _)
  "Speak the line you jumped to" (emacsvox-speedbar-speak-line))


(advice-add 'speedbar-tag-find :after #'ems--speedbar-tag-find-after)





(defun ems--speedbar-find-file-after (&rest _)
  "Speak modeline of buffer we switched to"
  (emacsvox-icon 'select-object) (emacsvox-speak-mode-line))


(advice-add 'speedbar-find-file :after #'ems--speedbar-find-file-after)





(defun ems--speedbar-expand-line-after (&rest _)
  "Speak the line we just expanded"
  (when (ems-interactive-p)
    (emacsvox-speedbar-speak-line) (emacsvox-icon 'open-object)))


(advice-add 'speedbar-expand-line :after
	    #'ems--speedbar-expand-line-after)





(defun ems--speedbar-contract-line-after (&rest _)
  "Speak the line we just contracted"
  (when (ems-interactive-p)
    (emacsvox-speedbar-speak-line) (emacsvox-icon 'close-object)))


(advice-add 'speedbar-contract-line :after
	    #'ems--speedbar-contract-line-after)





(defun ems--speedbar-up-directory-around (orig-fun &rest args)
  " Auditory icon and speech feedback indicate result of the\naction"
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p) (apply orig-fun args)
      (emacsvox-icon 'large-movement) (emacsvox-speedbar-speak-line))
     (t (apply orig-fun args)))
    result))


(advice-add 'speedbar-up-directory :around
	    #'ems--speedbar-up-directory-around)





(defun ems--speedbar-restricted-next-after (&rest _)
  "Speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (emacsvox-speedbar-speak-line)))


(advice-add 'speedbar-restricted-next :after
	    #'ems--speedbar-restricted-next-after)





(defun ems--speedbar-restricted-prev-after (&rest _)
  "Speak"
  (when (ems-interactive-p)
    (emacsvox-icon 'large-movement) (emacsvox-speedbar-speak-line)))


(advice-add 'speedbar-restricted-prev :after
	    #'ems--speedbar-restricted-prev-after)




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
  (dtk-speak
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
  (cl-declare (special speedbar-mode-map
                       speedbar-hide-button-brackets-flag))
  (dtk-set-punctuations 'all)
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


(defun ems--speedbar-make-button-after (&rest _)
  "Voiceify the button"
  (let
      ((start (ad-get-arg 0)) (end (ad-get-arg 1))
       (face (ad-get-arg 2)) (personality nil))
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
	    #'ems--speedbar-make-button-after)




;;;  keys 
(cl-declaim (special emacsvox-keymap))

(provide 'emacsvox-speedbar)
;;;  end of file 

