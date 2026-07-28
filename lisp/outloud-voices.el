;;; outloud-voices.el --- Define  OutLoud tags  -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:  Module to set up Eloquent voices and personalities
;; Keywords: Voice, Personality, IBM ViaVoice Outloud
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
;;  Interface to outloud server.
;; This module is IBM ViaVoice Outloud specific.
;;; Code:

;;  Required modules: 

(require 'cl-lib)
(require 'emacsvox-preamble)           ;For `ems--fastload'.

(defvar tts-default-speech-rate)
(defvar tts-default-voice)
(defvar tts-speech-rate)
(defvar tts-speech-rate-base)
(defvar tts-speech-rate-step)
(defvar tts-voice-capabilities-function)

;;;  Customizations:

(defcustom outloud-default-speech-rate 50
  "Default speech rate."
  :group 'tts
  :type 'integer
  :set #'(lambda(sym val)
           
           (set-default sym val)
           (when (string-match "outloud" tts-program)
             (setq-default tts-speech-rate val))))

;;;  Top level TTS  switcher

;;;###autoload
(defun outloud ()
  "Start Outloud."
  (interactive )
  (outloud-configure-tts)
  (ems--fastload "voice-defs")
  (funcall-interactively #'tts-select-server "outloud" )
  (tts-initialize))

;;;   voice table

(defvar outloud-default-voice-string "`v1"
  "Default voice")

(defvar outloud-voice-table (make-hash-table :test #'eq)
  "Association between symbols and strings to set Outloud  voices. ")

(defun outloud-define-voice (name command-string)
  "Map  voice `name' to `command-string'. "
  
  (puthash name command-string outloud-voice-table))

(defun outloud-get-voice-command  (name)
  "Retrieve command string for  voice NAME."
  
  (cond
   ((listp name)
    (mapconcat #'outloud-get-voice-command name " "))
   (t (or  (gethash name outloud-voice-table) outloud-default-voice-string))))

(defun outloud-voice-defined-p (name)
  "Check if voice `name' is  defined."
  
  (gethash name outloud-voice-table))

;;;  voice definitions

(defconst outloud-family-definitions
  '((paul
     :label "Adult male 1"
     :native-id "v1"
     :command " `v1 "
     :aliases (outloud-v1 v1)
     :generic (male)
     :gender male
     :age adult
     :variant 1
     :default t)
    (outloud-v2
     :label "Adult female 1"
     :native-id "v2"
     :command " `v2 "
     :aliases (v2)
     :generic (female)
     :gender female
     :age adult
     :variant 1)
    (outloud-v3
     :label "Child 1"
     :native-id "v3"
     :command " `v3 "
     :aliases (v3)
     :generic (child)
     :age child
     :variant 1)
    (outloud-v4
     :label "Adult male 2"
     :native-id "v4"
     :command " `v4 "
     :aliases (v4)
     :generic (male)
     :gender male
     :age adult
     :variant 2)
    (outloud-v5
     :label "Adult male 3"
     :native-id "v5"
     :command " `v5 "
     :aliases (v5)
     :generic (male)
     :gender male
     :age adult
     :variant 3)
    (outloud-v6
     :label "Elderly female 2"
     :native-id "v6"
     :command " `v6 "
     :aliases (v6)
     :generic (female)
     :gender female
     :age old
     :variant 2)
    (outloud-v7
     :label "Elderly female 1"
     :native-id "v7"
     :command " `v7 "
     :aliases (v7)
     :generic (female)
     :gender female
     :age old
     :variant 1)
    (outloud-v8
     :label "Adult male 1 variant"
     :native-id "v8"
     :command " `v8 "
     :aliases (v8)
     :generic (male)
     :gender male
     :age adult
     :variant 4))
  "Eloquence preset voices and their portable selection metadata.")

(defun outloud--family-name (value)
  "Return a comparison name for Eloquence family VALUE."
  (cond
   ((symbolp value) (symbol-name value))
   ((stringp value) value)
   (t nil)))

(defun outloud--family-name-equal-p (left right)
  "Return non-nil when Eloquence family names LEFT and RIGHT match."
  (let ((left-name (outloud--family-name left))
        (right-name (outloud--family-name right)))
    (and
     left-name right-name
     (string-equal (downcase left-name) (downcase right-name)))))

(defun outloud-family-definition (family)
  "Return the Eloquence preset definition matching FAMILY."
  (let (exact generic)
    (dolist (entry outloud-family-definitions)
      (when
          (or
           (outloud--family-name-equal-p family (car entry))
           (cl-some
            (lambda (alias)
              (outloud--family-name-equal-p family alias))
            (plist-get (cdr entry) :aliases)))
        (setq exact entry))
      (when
          (and
           (null generic)
           (cl-some
            (lambda (name)
              (outloud--family-name-equal-p family name))
            (plist-get (cdr entry) :generic)))
        (setq generic entry)))
    (or exact generic)))

(defun outloud-get-family-code (family)
  "Return the native Eloquence preset command for FAMILY."
  (or
   (plist-get
    (cdr (outloud-family-definition family))
    :command)
   ""))

(defun outloud--capability-family (entry)
  "Return public capability data for Eloquence family ENTRY."
  (let ((properties (cdr entry)))
    (list
     (car entry)
     :label (plist-get properties :label)
     :native-id (plist-get properties :native-id)
     :aliases (copy-sequence (plist-get properties :aliases))
     :generic (copy-sequence (plist-get properties :generic))
     :gender (plist-get properties :gender)
     :age (plist-get properties :age)
     :variant (plist-get properties :variant)
     :default (plist-get properties :default))))

(defun outloud-voice-capabilities ()
  "Return static Eloquence voice and normalized ACSS capabilities."
  (list
   :adapter 'outloud
   :source 'static
   :family-selection 'enumerated
   :families
   (mapcar #'outloud--capability-family outloud-family-definitions)
   :generic-families '(male female child)
   :dimensions '(family average-pitch pitch-range stress richness)
   :parameters
   '((family :type choice :default paul)
     (average-pitch :type integer :minimum 0 :maximum 9 :default 5)
     (pitch-range :type integer :minimum 0 :maximum 9 :default 5)
     (stress :type integer :minimum 0 :maximum 9 :default 5)
     (richness :type integer :minimum 0 :maximum 9 :default 5))))

(dolist (entry outloud-family-definitions)
  (let ((id (car entry))
        (properties (cdr entry)))
    (outloud-define-voice id (plist-get properties :command))
    (dolist (alias (plist-get properties :aliases))
      (outloud-define-voice alias (plist-get properties :command)))))

;;  mapping css parameters to tts codes
;;  --- see../servers /linux-outloud/lib/voice-params.org
;;;   hash table for mapping families to their dimensions

(defvar outloud-css-code-tables (make-hash-table)
  "Hash table holding vectors of outloud codes. ")

(defun outloud-css-set-code-table (family dimension table)
  "Set up voice FAMILY. "
  
  (let ((key (intern (format "%s-%s" family dimension))))
    (puthash key table outloud-css-code-tables)))

(defun outloud-css-get-code-table (family dimension)
  "Retrieve table of values for  FAMILY and DIMENSION."
  
  (let* ((definition (outloud-family-definition family))
         (canonical (or (car-safe definition) 'paul))
         (key (intern (format "%s-%s" canonical dimension)))
         (fallback (intern (format "paul-%s" dimension))))
    (or
     (gethash key outloud-css-code-tables)
     (gethash fallback outloud-css-code-tables))))

;;;   average pitch

;; Average pitch for standard male voice is 65 --this is mapped to
;; a setting of 5.
;; head-size for default male is 50.
;; Average pitch varies inversely with speaker head size --a child
;; has a small head and a higher pitched voice.
;; We change parameter head-size in conjunction with average pitch to
;; produce a more natural change on the TTS engine.

;;;   paul average pitch

;; median: pitch: 65  head-size 50
(let ((table (make-vector 10 "")))
  (mapc
   #'(lambda (setting)
       (aset table
             (cl-first setting)
             (format
              " `vb%s `vh%s "
              (cl-second setting) (cl-third setting))))
   '(
     (0 40 75) ; pitch, head-size
     (1 45 70)
     (2 50 65)
     (3 55 60)
     (4 60 55)
     (5 65 50)
     (6 70 45)
     (7 75 40)
     (8 80 35)
     (9 85 30)))
  (outloud-css-set-code-table 'paul 'average-pitch table))

(defun outloud-get-average-pitch-code (value family)
  "Get  AVERAGE-PITCH for  VALUE and  FAMILY."
  (or family (setq family 'paul))
  (if value
      (aref (outloud-css-get-code-table family 'average-pitch)
            value)
    ""))

;;;   pitch range

;;  Standard pitch range is 30 and is  mapped to
;; a setting of 5.
;; A value of 0 produces a flat monotone voice --maximum value of 100
;; produces a highly animated voice.

;;;   paul pitch range

(let ((table (make-vector 10 "")))
  (mapc
   #'(lambda (setting)
       (aset table
             (cl-first setting)
             (format
              " `vf%s  " (cl-second setting))))
   '(
     (0 0)
     (1 5)
     (2  15)
     (3  20)
     (4  25)
     (5  30)
     (6  47)
     (7  64)
     (8  81)
     (9  100)))
  (outloud-css-set-code-table 'paul 'pitch-range table))

(defun outloud-get-pitch-range-code (value family)
  "Get pitch-range code for  VALUE and FAMILY."
  (or family (setq family 'paul))
  (if value
      (aref (outloud-css-get-code-table family 'pitch-range)
            value)
    ""))

;;;   stress

;; On the outloud we map stress to roughness
;;;   paul stress

(let ((table (make-vector 10 "")))
  (mapc
   #'(lambda (setting)
       (aset table (cl-first setting)
             (format " `vr%s  "
                     (cl-second setting))))
   '(
     (0 0 )
     (1 10 )
     (2  20 )
     (3  30 )
     (4  40 )
     (5  50 )
     (6  60 )
     (7  70 )
     (8  80 )
     (9  90 )))
  (outloud-css-set-code-table 'paul 'stress table))

(defun outloud-get-stress-code (value family)
  (or family (setq family 'paul))
  (if value
      (aref (outloud-css-get-code-table family 'stress)
            value)
    ""))

;;;   richness

;;;   paul richness

(let ((table (make-vector 10 "")))
  (mapc
   #'(lambda (setting)
       (aset table
             (cl-first setting)
             (format
              " `vy%s  `vv%s "
              (cl-second setting) (cl-third setting))))
   '(; whisper, volume
     (0 0 60)
     (1 4 78)
     (2 8 80)
     (3 12 84)
     (4 16 88)
     (5 20 92)
     (6 24 93)
     (7 28 95)
     (8 32 97)
     (9 36 100)))
  (outloud-css-set-code-table 'paul 'richness table))

(defun outloud-get-richness-code (value family)
  (or family (setq family 'paul))
  (if value
      (aref (outloud-css-get-code-table family 'richness)
            value)
    ""))

;;;   outloud-define-voice-from-acss

(defun outloud-define-voice-from-acss (name style)
  "Define NAME  as  per   STYLE."
  (let* ((family(acss-family style))
         (command
          (concat
           (outloud-get-family-code family)
           (outloud-get-average-pitch-code (acss-average-pitch style) family)
           (outloud-get-pitch-range-code (acss-pitch-range style) family)
           (outloud-get-stress-code (acss-stress style) family)
           (outloud-get-richness-code (acss-richness style) family))))
    (outloud-define-voice name command)))

;;;  Configurater

;;;###autoload
(defun outloud-configure-tts ()
  "Configure TTS  to use Outloud."
  (fset 'tts-voice-defined-p 'outloud-voice-defined-p)
  (fset 'tts-get-voice-command 'outloud-get-voice-command)
  (fset
   'tts-define-voice-from-acss 'outloud-define-voice-from-acss)
  (setq tts-voice-capabilities-function #'outloud-voice-capabilities)
  (setq tts-default-voice 'paul)
  (setq tts-default-speech-rate outloud-default-speech-rate)
  (set-default 'tts-default-speech-rate outloud-default-speech-rate)
  (setq tts-speech-rate-step 10
        tts-speech-rate-base 50
        tts-speech-rate outloud-default-speech-rate)
  (setq-default tts-speech-rate-step 10
                tts-speech-rate outloud-default-speech-rate
                tts-speech-rate-base 50)
  (tts-set-character-scale 1.5 'default)
  (setq tts-handle-unicode t)
  (tts-unicode-update-untouched-charsets
   '(ascii latin-iso8859-1 latin-iso8859-15 latin-iso8859-9
           eight-bit-graphic)))

(provide 'outloud-voices)
