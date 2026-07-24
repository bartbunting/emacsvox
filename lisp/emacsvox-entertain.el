;;; emacsvox-entertain.el --- Speech enable games  -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description: Auditory interface to diversions
;; Keywords: Emacsvox, Speak, Spoken Output, games
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

;; Auditory interface to misc games

;;; Code:

;;   Required modules:

(require 'emacsvox-preamble)

;;;  doctar

(defun emacsvox--advice-doctor-txtype-after (answer)
  "Speak Doctor's ANSWER after it is inserted."
  (dtk-speak
   (mapconcat (lambda (item) (format "%s" item)) answer " ")))

(with-eval-after-load 'doctor
  (advice-add 'doctor-txtype :after
              #'emacsvox--advice-doctor-txtype-after))

;;;  mpuz
(voice-setup-add-map
 '(
   (mpuz-trivial voice-monotone-extra)
   (mpuz-unsolved voice-bolden)
   (mpuz-solved voice-animate)))

;;;  dunnet
(cl-loop
 for target in '(dun-parse dun-unix-parse)
 for function = (intern (format "emacsvox--advice-%s-around" target))
 do
 (eval
  `(defun ,function (orig-fun &rest args)
     "Run a Dunnet parser once and speak its interactively inserted output."
     (if (not (ems-interactive-p ',target))
         (apply orig-fun args)
       (let ((start (point))
             (result (apply orig-fun args)))
         (emacsvox-icon 'mark-object)
         (emacsvox-speak-region start (point))
         result)))))

(with-eval-after-load 'dunnet
  (dolist (target '(dun-parse dun-unix-parse))
    (advice-add
     target :around
     (intern (format "emacsvox--advice-%s-around" target)))))

;;;   hangman

(defvar hm-current-guess-string)
(defvar hm-current-word)
(defvar hm-map nil)
(defvar hm-win-statistics)

(defun emacsvox-hangman-speak-statistics ()
  "Speak statistics."
  (interactive)
  
  (message "         Games won: %d    Games Lost: %d"
           (aref hm-win-statistics 0)
           (aref hm-win-statistics 1)))

(defun emacsvox-hangman-setup-pronunciations ()
  "Setup pronunciation dictionaries."
  
  (emacsvox-pronounce-add-dictionary-entry 'hm-mode "_" ".")
  (when (or (not (boundp 'emacsvox-pronounce-table))
            (not emacsvox-pronounce-table))
    (emacsvox-pronounce-toggle-dictionaries)))

(defun emacsvox--advice-hm-self-guess-char-after (&rest _)
  "Speak the char."
  (when (ems-interactive-p 'hm-self-guess-char)
    (emacsvox-icon 'select-object)))

(defun emacsvox-hangman-speak-guess ()
  "Speak current guessed string. "
  (interactive)
  (let ((string (make-string  (length hm-current-word)
                              ?\))))
    (cl-loop for i from 0 to (1- (length hm-current-word))
             do
             (aset  string  i
                    (aref hm-current-guess-string (* i 2))))
    (message  "%s:  %s "
              (length string)
              (downcase string))))

(defun emacsvox--advice-hangman-after (&rest _)
  "Speech enable hangman."
  (when (ems-interactive-p 'hangman)
    (emacsvox-hangman-setup-pronunciations)
    (emacsvox-icon 'open-object)))

(defun emacsvox-hangman--install ()
  "Install advice and bindings after the optional Hangman package loads."
  (when (fboundp 'hm-self-guess-char)
    (advice-add 'hm-self-guess-char :after
                #'emacsvox--advice-hm-self-guess-char-after))
  (when (fboundp 'hangman)
    (advice-add 'hangman :after #'emacsvox--advice-hangman-after))
  (when (and (boundp 'hm-map) (keymapp hm-map))
    (define-key hm-map " " #'emacsvox-hangman-speak-guess)
    (define-key hm-map "=" #'emacsvox-hangman-speak-statistics)))

(with-eval-after-load 'hangman
  (emacsvox-hangman--install))

(provide 'emacsvox-entertain)
;;;  end of file
