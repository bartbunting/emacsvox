;;; emacsvox-cperl.el --- Speech enable CPerl -*- lexical-binding: t; -*- 
;;
;; $Author: tv.raman.tv $ 
;; DescriptionEmacsvox extensions for CPerl mode
;; Keywords:emacsvox, audio interface to emacs CPerl
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


;;  required modules 

(require 'emacsvox-preamble)

;;; Commentary:

;; Provide additional advice to CPerl mode 

;;; Code:

;;;  voice locking:

;; first pull in emacsvox-perl for voice lock definitions 
(require 'emacsvox-perl)

;;;   Advice electric insertion to talk:

(defun emacsvox--advice-cperl-electric-backspace-around
    (original &rest arguments)
  "Speak character you're deleting."
  (when (ems-interactive-p 'cperl-electric-backspace)
    (tts-tone 500 100 'force)
    (emacsvox-speak-this-char (preceding-char)))
  (apply original arguments))

(advice-add
 'cperl-electric-backspace :around
 #'emacsvox--advice-cperl-electric-backspace-around
 '((name . emacsvox--advice-cperl-electric-backspace-around)))

(defun emacsvox--advice-cperl-linefeed-around
    (original &rest arguments)
  "Speak the previous line if line echo is on. \n  See command \\[emacsvox-toggle-line-echo].\nOtherwise cue user to the line just created. "
  (when (ems-interactive-p 'cperl-linefeed)
    (if emacsvox-line-echo
        (emacsvox-speak-line)
      (dtk-speak-using-voice
       voice-annotate
       (format "indent %s" (current-column)))
      (tts--protocol-dispatch)))
  (apply original arguments))

(advice-add
 'cperl-linefeed :around
 #'emacsvox--advice-cperl-linefeed-around
 '((name . emacsvox--advice-cperl-linefeed-around)))

(defmacro emacsvox-cperl--define-advice (target where &rest body)
  "Define direct WHERE advice for interactive CPerl TARGET."
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

(emacsvox-cperl--define-advice cperl-indent-exp :after
  (emacsvox-icon 'fill-object)
  (message "Indented current s expression "))

;;;  Advice info to talk:

(emacsvox-cperl--define-advice cperl-info-on-current-command :after
  (emacsvox-icon 'help)
  (message "Displayed info in other window"))

(emacsvox-cperl--define-advice cperl-info-on-command :after
  (emacsvox-icon 'help)
  (message "Displayed help in other window."))

;;;  structured editing

(emacsvox-cperl--define-advice cperl-invert-if-unless :after
  (emacsvox-speak-line)
  (emacsvox-icon 'select-object))

(defmacro emacsvox-cperl--define-comment-advice
    (target negative-label positive-label)
  "Define region feedback for TARGET using its native arguments."
  (let ((function
         (intern (format "emacsvox--advice-%s-after" target))))
    `(progn
       (defun ,function (begin end prefix &rest _)
         ,(format "Report the region changed by `%s'." target)
         (when (ems-interactive-p ',target)
           (message
            "%s region containing %s lines"
            (if (and prefix (< prefix 0))
                ,negative-label
              ,positive-label)
            (count-lines begin end))))
       (advice-add
        ',target :after #',function
        '((name . ,function))))))

(emacsvox-cperl--define-comment-advice
 cperl-comment-region "Uncommented" "Commented")
(emacsvox-cperl--define-comment-advice
 cperl-uncomment-region "Commented" "Uncommented")

(emacsvox-cperl--define-advice cperl-indent-command :after
  (emacsvox-speak-line)
  (emacsvox-icon 'large-movement))

(defun emacsvox--advice-cperl-indent-region-after
    (start end &rest _)
  "Report the region indented by `cperl-indent-region'."
  (when (ems-interactive-p 'cperl-indent-region)
    (emacsvox-icon 'fill-object)
    (message "Filled region containing %s lines"
             (count-lines start end))))

(advice-add
 'cperl-indent-region :after
 #'emacsvox--advice-cperl-indent-region-after
 '((name . emacsvox--advice-cperl-indent-region-after)))

(emacsvox-cperl--define-advice cperl-fill-paragraph :after
  (emacsvox-icon 'fill-object)
  (message "Filled current paragraph"))

;;;   misc

(emacsvox-cperl--define-advice cperl-switch-to-doc-buffer :after
  (emacsvox-speak-mode-line)
  (emacsvox-icon 'open-object))

(emacsvox-cperl--define-advice cperl-find-bad-style :after
  (emacsvox-speak-mode-line)
  (emacsvox-icon 'task-done))

;;;  set up hooks 

(add-hook 'cperl-mode-hook
          #'(lambda ()
              (tts-set-punctuations 'all)
              (or dtk-split-caps
                  (dtk-toggle-split-caps))
              (or emacsvox-audio-indentation
                  (emacsvox-toggle-audio-indentation))))

(provide  'emacsvox-cperl)
