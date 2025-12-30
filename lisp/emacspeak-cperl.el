;;; emacspeak-cperl.el --- Speech enable CPerl -*- lexical-binding: t; -*- 
;;
;; $Author: tv.raman.tv $ 
;; DescriptionEmacspeak extensions for CPerl mode
;; Keywords:emacspeak, audio interface to emacs CPerl
;;;   LCD Archive entry: 

;; LCD Archive Entry:
;; emacspeak| T. V. Raman |tv.raman.tv@gmail.com 
;; A speech interface to Emacs |
;; 
;;  $Revision: 4532 $ | 
;; Location https://github.com/tvraman/emacspeak
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

(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacspeak-preamble)

;;; Commentary:

;; Provide additional advice to CPerl mode 

;;; Code:

;;;  voice locking:

;; first pull in emacspeak-perl for voice lock definitions 
(require 'emacspeak-perl)

;;;   Advice electric insertion to talk:


(defun ems--cperl-electric-backspace-around (orig-fun &rest args)
  "Speak character you're deleting."
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p) (dtk-tone 500 100 'force)
      (emacspeak-speak-this-char (preceding-char))
      (apply orig-fun args))
     (t (apply orig-fun args)))
    result))


(advice-add 'cperl-electric-backspace :around
	    #'ems--cperl-electric-backspace-around)





(defun ems--cperl-linefeed-around (orig-fun &rest args)
  "Speak the previous line if line echo is on. \n  See command \\[emacspeak-toggle-line-echo].\nOtherwise cue user to the line just created. "
  (let ((result (apply orig-fun args)))
    (cl-declare (special emacspeak-line-echo))
    (cond
     ((ems-interactive-p)
      (cond (emacspeak-line-echo (emacspeak-speak-line))
	    (t
	     (dtk-speak-using-voice voice-annotate
				    (format "indent %s"
					    (current-column)))
	     (dtk-interp-speak)))))
    (apply orig-fun args) result))


(advice-add 'cperl-linefeed :around #'ems--cperl-linefeed-around)





(defun ems--cperl-indent-exp-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacspeak-icon 'fill-object)
    (message "Indented current s expression ")))


(advice-add 'cperl-indent-exp :after #'ems--cperl-indent-exp-after)




;;;  Advice info to talk:


(defun ems--cperl-info-on-current-command-after (&rest _)
  "Speak the displayed info"
  (when (ems-interactive-p)
    (emacspeak-icon 'help) (message "Displayed info in other window")))


(advice-add 'cperl-info-on-current-command :after
	    #'ems--cperl-info-on-current-command-after)





(defun ems--cperl-info-on-command-after (&rest _)
  "Speak the displayed info"
  (when (ems-interactive-p)
    (emacspeak-icon 'help) (message "Displayed help in other window.")))


(advice-add 'cperl-info-on-command :after
	    #'ems--cperl-info-on-command-after)




;;;  structured editing


(defun ems--cperl-invert-if-unless-after (&rest _)
  "Speak updated line"
  (when (ems-interactive-p)
    (emacspeak-speak-line) (emacspeak-icon 'select-object)))


(advice-add 'cperl-invert-if-unless :after
	    #'ems--cperl-invert-if-unless-after)





(defun ems--cperl-comment-region-after (&rest _)
  "Speak."
  (when (ems-interactive-p)
    (let ((prefix-arg (ad-get-arg 2)))
      (message "%s region containing %s lines"
	       (if (and prefix-arg (< prefix-arg 0)) "Uncommented"
		 "Commented")
	       (count-lines (point) (mark))))))


(advice-add 'cperl-comment-region :after
	    #'ems--cperl-comment-region-after)





(defun ems--cperl-uncomment-region-after (&rest _)
  "Speak."
  (when (ems-interactive-p)
    (let ((prefix-arg (ad-get-arg 2)))
      (message "%s region containing %s lines"
	       (if (and prefix-arg (< prefix-arg 0)) "Commented"
		 "Uncommented")
	       (count-lines (point) (mark))))))


(advice-add 'cperl-uncomment-region :after
	    #'ems--cperl-uncomment-region-after)





(defun ems--cperl-indent-command-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacspeak-speak-line) (emacspeak-icon 'large-movement)))


(advice-add 'cperl-indent-command :after
	    #'ems--cperl-indent-command-after)





(defun ems--cperl-indent-region-after (&rest _)
  "speak when done"
  (when (ems-interactive-p)
    (emacspeak-icon 'fill-object)
    (message "Filled region containing %s lines"
	     (count-lines (region-beginning) (region-end)))))


(advice-add 'cperl-indent-region :after
	    #'ems--cperl-indent-region-after)




(defun ems--cperl-fill-paragraph-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacspeak-icon 'fill-object) (message "Filled current paragraph")))


(advice-add 'cperl-fill-paragraph :after
	    #'ems--cperl-fill-paragraph-after)




;;;   misc


(defun ems--cperl-switch-to-doc-buffer-after (&rest _)
  "speak"
  (when (ems-interactive-p)
    (emacspeak-speak-mode-line) (emacspeak-icon 'open-object)))


(advice-add 'cperl-switch-to-doc-buffer :after
	    #'ems--cperl-switch-to-doc-buffer-after)





(defun ems--cperl-find-bad-style-after (&rest _)
  "speak when done."
  (when (ems-interactive-p)
    (emacspeak-speak-mode-line) (emacspeak-icon 'task-done)))


(advice-add 'cperl-find-bad-style :after
	    #'ems--cperl-find-bad-style-after)




;;;  set up hooks 

(add-hook 'cperl-mode-hook
          #'(lambda ()
              (dtk-set-punctuations 'all)
              (or dtk-split-caps
                  (dtk-toggle-split-caps))
              (or emacspeak-audio-indentation
                  (emacspeak-toggle-audio-indentation))))

(provide  'emacspeak-cperl)

