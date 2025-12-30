;;; emacspeak-metapost.el --- speech-enable metapost -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:  Emacspeak module for speech-enabling
;; metapost mode
;; Keywords: Emacspeak, metapost
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacspeak| T. V. Raman |tv.raman.tv@gmail.com
;; A speech interface to Emacs |
;;
;;  $Revision: 4074 $ |
;; Location https://github.com/tvraman/emacspeak
;;

;;;   Copyright:

;; Copyright (C) 1995 -- 2024, T. V. Raman
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
;; Speech-enables metapost mode.
;; metapost is a powerful drawing package
;; typically installed as mpost by modern TeX
;; installations.

;;; Code:
;;  required modules

(cl-declaim  (optimize  (safety 0) (speed 3)))
(require 'emacspeak-preamble)

;;;   completion


(defun ems--meta-complete-symbol-around (orig-fun &rest args)
  "Say what you completed."
  (let ((result (apply orig-fun args)))
    (let
	((prior (save-excursion (skip-syntax-backward "^ >") (point)))
	 (dtk-stop-immediately dtk-stop-immediately))
      (when dtk-stop-immediately (dtk-stop)) (apply orig-fun args)
      (when (> (point) prior)
	(setq dtk-stop-immediately nil)
	(tts-with-punctuations 'all
			       (dtk-speak
				(buffer-substring prior (point)))))
      result)
    result))


(advice-add 'meta-complete-symbol :around
	    #'ems--meta-complete-symbol-around)




;;;  indentation


(defun ems--meta-indent-line-after (&rest _)
  "speak." (when (ems-interactive-p) (emacspeak-speak-line)))


(advice-add 'meta-indent-line :after #'ems--meta-indent-line-after)





(defun ems--meta-fill-paragraph-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacspeak-icon 'fill-object) (message "Filled current paragraph")))


(advice-add 'meta-fill-paragraph :after
	    #'ems--meta-fill-paragraph-after)




;;;   navigation

(defun ems--meta-beginning-of-defun-after (&rest _)
  "Speak the line."
  (when (ems-interactive-p)
    (emacspeak-icon 'large-movement) (emacspeak-speak-line)))


(advice-add 'meta-beginning-of-defun :after
	    #'ems--meta-beginning-of-defun-after)





(defun ems--meta-end-of-defun-after (&rest _)
  "Speak the line."
  (when (ems-interactive-p)
    (emacspeak-icon 'large-movement) (emacspeak-speak-line)))


(advice-add 'meta-end-of-defun :after #'ems--meta-end-of-defun-after)




;;;   commenting etc


(defun ems--meta-comment-region-after (&rest _)
  "Speak."
  (when (ems-interactive-p)
    (let ((prefix-arg (ad-get-arg 2)))
      (message "%s region containing %s lines"
	       (if (and prefix-arg (< prefix-arg 0)) "Uncommented"
		 "Commented")
	       (count-lines (point) (mark 'force))))))


(advice-add 'meta-comment-region :after
	    #'ems--meta-comment-region-after)





(defun ems--meta-comment-defun-after (&rest _)
  "Speak."
  (when (ems-interactive-p)
    (let ((prefix-arg (ad-get-arg 2)))
      (message "%s environment containing %s lines"
	       (if prefix-arg "Uncommented" "Commented")
	       (count-lines (point) (mark 'force))))))


(advice-add 'meta-comment-defun :after #'ems--meta-comment-defun-after)





(defun ems--meta-uncomment-defun-after (&rest _)
  "Speak."
  (when (ems-interactive-p)
    (message "Uncommented environment containing %s lines"
	     (count-lines (point) (mark 'force)))))


(advice-add 'meta-uncomment-defun :after
	    #'ems--meta-uncomment-defun-after)





(defun ems--meta-uncomment-region-after (&rest _)
  "Speak."
  (when (ems-interactive-p)
    (message "Uncommented  region containing %s lines"
	     (count-lines (point) (mark 'force)))))


(advice-add 'meta-uncomment-region :after
	    #'ems--meta-uncomment-region-after)





(defun ems--meta-indent-region-after (&rest _)
  "Speak."
  (when (ems-interactive-p)
    (emacspeak-icon 'fill-object)
    (message "Indented  region containing %s lines"
	     (count-lines (point) (mark 'force)))))


(advice-add 'meta-indent-region :after #'ems--meta-indent-region-after)





(defun ems--meta-indent-buffer-after (&rest _)
  "Speak."
  (when (ems-interactive-p)
    (emacspeak-icon 'fill-object)
    (message "Indented  buffer containing %s lines"
	     (count-lines (point-min) (point-max 'force)))))


(advice-add 'meta-indent-buffer :after #'ems--meta-indent-buffer-after)





(defun ems--meta-mark-defun-after (&rest _)
  "Produce an auditory icon if possible."
  (when (ems-interactive-p)
    (emacspeak-icon 'mark-object)
    (message "Marked function containing %s lines"
	     (count-lines (point) (mark 'force)))))


(advice-add 'meta-mark-defun :after #'ems--meta-mark-defun-after)





(defun ems--meta-indent-defun-after (&rest _)
  "speak."
  (when (ems-interactive-p)
    (emacspeak-icon 'fill-object) (message "Indented current defun. ")))


(advice-add 'meta-indent-defun :after #'ems--meta-indent-defun-after)




(provide 'emacspeak-metapost)
;;;  end of file
