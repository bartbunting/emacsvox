;;; swiftmac-voices.el --- Define  Swiftmac tags  -*- lexical-binding: t; -*-
;; $Id: swiftmac-voices.el 6342 2024-04-20 19:12:40Z tv.raman.tv $
;; $Author: Robert Melton $
;; Description:  Module to set up Swiftmac voices and personalities
;; Keywords: Voice, Personality, Swiftmac
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
;; This module defines the various voices used in voice-lock mode by SwiftMac.

;;; Code:

;;  Required modules: 

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)           ;For `ems--fastload'.
(require 'json)
(require 'subr-x)

(defvar tts-default-speech-rate)
(defvar tts-default-voice)
(defvar tts-voice-capabilities-function)
(defvar tts-voice-inventory-function)
(defvar tts-voice-inventory-refresh-function)

(defvar swiftmac-voice-inventory-cache nil
  "Most recently discovered installed SwiftMac voices.")

(defvar swiftmac-voice-inventory-time nil
  "Time at which `swiftmac-voice-inventory-cache' was refreshed.")

(defvar swiftmac-voice-inventory-error nil
  "Most recent SwiftMac inventory discovery error, or nil.")

(defun swiftmac-voice-capabilities ()
  "Return SwiftMac voice and normalized ACSS capabilities.

The server accepts installed voice names.  The capability remains free-form,
while `swiftmac-voice-inventory' enumerates installed voices when the local
discovery helper is available."
  '(:adapter swiftmac
    :source static
    :family-selection free-form
    :families nil
    :generic-families nil
    :dimensions (family average-pitch pitch-range)
    :parameters
    ((family :type string)
     (average-pitch :type integer :minimum 0 :maximum 9 :default 5)
     (pitch-range :type integer :minimum 0 :maximum 9 :default 5))))

(defun swiftmac--voice-discovery-program ()
  "Return the Swift executable and discovery script, or nil."
  (let ((swift (and (eq system-type 'darwin) (executable-find "swift")))
        (script
         (expand-file-name
          "mac-swiftmac/show-voices.swift" emacsvox-servers-directory)))
    (and swift (file-readable-p script) (list swift script))))

(defun swiftmac--quality-name (quality)
  "Return a stable name for AVFoundation voice QUALITY."
  (pcase quality
    (1 "default")
    (2 "enhanced")
    (3 "premium")
    (_ (format "%s" quality))))

(defun swiftmac--normalize-installed-voice (voice)
  "Normalize one installed SwiftMac VOICE returned by the enumerator."
  (let ((identifier (plist-get voice :identifier)))
    (list
     :engine-id "swiftmac"
     :voice-id identifier
     :display-name (or (plist-get voice :name) identifier)
     :language (plist-get voice :language)
     :gender (plist-get voice :gender)
     :quality (swiftmac--quality-name (plist-get voice :quality))
     :availability "available")))

(defun swiftmac--voice-inventory-snapshot ()
  "Return the current normalized SwiftMac inventory snapshot."
  (let* ((cached swiftmac-voice-inventory-cache)
         (source
          (cond (swiftmac-voice-inventory-error "cached")
                (cached "live")
                (t "free-form")))
         (stale (and cached swiftmac-voice-inventory-error t))
         (capabilities (swiftmac-voice-capabilities)))
    (list
     :adapter "swiftmac"
     :source source
     :status "available"
     :generation (and cached 1)
     :received-at swiftmac-voice-inventory-time
     :age-seconds
     (and swiftmac-voice-inventory-time
          (float-time (time-subtract nil swiftmac-voice-inventory-time)))
     :stale stale
     :preferred-engine-id "swiftmac"
     :process-agreement "single-adapter"
     :preview-support (if cached "exact" "free-form")
     :routing-policy-support "unsupported"
     :error (and swiftmac-voice-inventory-error
                 (error-message-string swiftmac-voice-inventory-error))
     :engines
     (list
      (list
       :engine-id "swiftmac"
       :display-name "SwiftMac"
       :availability "available"
       :health (if swiftmac-voice-inventory-error "degraded" "healthy")
       :health-reason
       (and swiftmac-voice-inventory-error
            (error-message-string swiftmac-voice-inventory-error))
       :inventory-kind source
       :acss-dimensions '(family average-pitch pitch-range)
       :post-synthesis-dimensions nil
       :preview-support (if cached "exact" "free-form")
       :routing-policy-support "unsupported"
       :capabilities capabilities
       :voices (copy-tree cached))))))

(defun swiftmac-refresh-voice-inventory ()
  "Refresh installed SwiftMac voices and return the resulting snapshot."
  (let ((program (swiftmac--voice-discovery-program)))
    (if (not program)
        (setq swiftmac-voice-inventory-error
              '(error "Swift voice discovery is unavailable on this host"))
      (condition-case error-data
          (with-temp-buffer
            (let ((status
                   (process-file
                    (car program) nil t nil (cadr program) "--json")))
              (unless (zerop status)
                (error "Swift voice discovery exited with status %s" status))
              (goto-char (point-min))
              (let ((voices
                     (json-parse-buffer
                      :object-type 'plist :array-type 'list
                      :null-object nil :false-object nil)))
                (unless (listp voices)
                  (error "Swift voice discovery returned invalid JSON"))
                (setq swiftmac-voice-inventory-cache
                      (mapcar #'swiftmac--normalize-installed-voice voices)
                      swiftmac-voice-inventory-time (current-time)
                      swiftmac-voice-inventory-error nil))))
        (error (setq swiftmac-voice-inventory-error error-data))))
    (swiftmac--voice-inventory-snapshot)))

(defun swiftmac-voice-inventory ()
  "Return installed SwiftMac voices, refreshing once when possible."
  (if (and (null swiftmac-voice-inventory-cache)
           (swiftmac--voice-discovery-program))
      (swiftmac-refresh-voice-inventory)
    (swiftmac--voice-inventory-snapshot)))

(defun swiftmac-voice-preview-code (selector)
  "Return an exact queued SwiftMac voice tag for preview SELECTOR."
  (let* ((resolved (tts--resolve-voice-preview-selector selector))
         (voice-id (plist-get resolved :voice-id)))
    (format " [{voice %s}] " voice-id)))

;;; swiftmac:
;;;###autoload
(defun swiftmac ()
  "SwiftMac TTS."
  (interactive)
  (swiftmac-configure-tts)
  (ems--fastload "voice-defs")
  (tts-select-server "swiftmac")
  (tts-initialize))

;;;  Customizations:

(defcustom swiftmac-default-speech-rate 0.65
  "Default speech rate for swiftmac."
  :group 'tts
  :type 'float
  :set #'(lambda(sym val)
           (set-default sym val)
           (when (string-match "swiftmac\\'" tts-program)
             (setq-default tts-speech-rate val))))

;;;   voice table

                                        ; when this is set it makes tts-set-language do nothing
                                        ; (defvar swiftmac-default-voice-string "[{voice en-US:Alex}]"
(defvar swiftmac-default-voice-string "[{voice :Alex}] [[pitch 1]]"
  "Default swiftmac tag for  default . Empty uses system default")

(defvar swiftmac-voice-table (make-hash-table)
  "Association between symbols and strings to set SwiftMac  voices.
The string can set any voice parameter.")

(defun swiftmac-define-voice (name command-string)
  "Define a SwiftMac  voice named NAME.
This voice will be set   by sending the string
COMMAND-STRING to the TTS engine."
  
  (puthash name command-string swiftmac-voice-table))

(defun swiftmac-get-voice-command-internal  (name)
  "Retrieve command string for  voice NAME."
  
  (cond
   ((listp name)
    (mapconcat #'swiftmac-get-voice-command name " "))
   (t (or  (gethash name swiftmac-voice-table)
           swiftmac-default-voice-string))))

(defun swiftmac-get-voice-command (name)
  "Retrieve command string for  voice NAME."
  (swiftmac-get-voice-command-internal name))

(defun swiftmac-voice-defined-p (name)
  "Check if there is a voice named NAME defined."
  
  (gethash name swiftmac-voice-table))

;;;  voice definitions

;; the predefined voices:
(swiftmac-define-voice 'paul  swiftmac-default-voice-string)

;; Modified voices:

;;;   Mapping css parameters to tts codes

;;;  voice family codes

(defun swiftmac-get-family-code (name)
  "Get control code for voice family NAME."
  (cond
   ((null name) swiftmac-default-voice-string)
   ((gethash name swiftmac-voice-table))
   (t
    (let ((name (if (symbolp name) (symbol-name name) name)))
      (format
       " [{voice %s}] "
       (if (string-match-p ":" name) name (concat ":" name)))))))

;;;   hash table for mapping families to their dimensions

(defvar swiftmac-css-code-tables (make-hash-table)
  "Hash table holding vectors of swiftmac codes.
Keys are symbols of the form <FamilyName-Dimension>.
Values are vectors holding the control codes for the 10 settings.")

(defun swiftmac-css-set-code-table (family dimension table)
  "Set up voice FAMILY.
Argument DIMENSION is the dimension being set,
and TABLE gives the values along that dimension."
  
  (let ((key (intern (format "%s-%s" family dimension))))
    (puthash key table swiftmac-css-code-tables)))

(defun swiftmac-css-get-code-table (family dimension)
  "Retrieve table of values for specified FAMILY and DIMENSION."
  
  (let ((key (intern (format "%s-%s" (or family 'paul) dimension)))
        (fallback (intern (format "paul-%s" dimension))))
    (or
     (gethash key swiftmac-css-code-tables)
     (gethash fallback swiftmac-css-code-tables))))

;;;   average pitch

;; Average pitch for standard male voice is 65 --this is mapped to
;; a setting of 5.
;; Average pitch varies inversely with speaker head size --a child
;; has a small head and a higher pitched voice.
;; We change parameter head-size in conjunction with average pitch to
;; produce a more natural change on the TTS engine.

;;;   paul average pitch

(let ((table (make-vector 10 "")))
  (mapc
   #'(lambda (setting)
       (aset table
             (cl-first setting)
             (format " [[average-pitch %s]] "
                     (cl-second setting))))
   '(
     (0 1)
     (1 10)
     (2 20)
     (3 35)
     (4 40)
     (5 45)
     (6 50)
     (7 55)
     (8 58)
     (9 62)))
  (swiftmac-css-set-code-table 'paul 'average-pitch table))

(defun swiftmac-get-average-pitch-code (value family)
  "Get  AVERAGE-PITCH for specified VALUE and  FAMILY."
  (or family (setq family 'paul))
  (if value 
      (aref (swiftmac-css-get-code-table family 'average-pitch)
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
             (format " [[pitch-range %s]] "
                     (cl-second setting))))
   '(
     (0 0)
     (1 14.1)
     (2  28.2)
     (3  42.3)
     (4  56.4)
     (5  70.5)
     (6  84.6)
     (7 98.7)
     (8  112.8)
     (9  127)))
  (swiftmac-css-set-code-table 'paul 'pitch-range table))

(defun swiftmac-get-pitch-range-code (value family)
  "Get pitch-range code for specified VALUE and FAMILY."
  (or family (setq family 'paul))
  (if value 
      (aref (swiftmac-css-get-code-table family 'pitch-range)
            value)
    ""))

;;;   stress

;;;   paul stress TODO

(let ((table (make-vector 10 "")))
  (mapc
   #'(lambda (setting)
       (aset table
             (cl-first setting)
             (format " [[stress %s %s %s %s]] "
                     (cl-second setting)
                     (cl-third setting)
                     (cl-fourth setting)
                     (cl-fifth setting)
                     )))
   '(
     (0 1 1 0.1 0.1)
     (1 1 1 10 .1)
     (2  1 1 20 .2)
     (3  1 1 30 .2)
     (4  1 1 40 .3)
     (5  1 1 50 .3)
     (6  1 1 60 .3)
     (7  1 1 70 .3)
     (8  1 1 80 .3)
     (9  1 1 90 .3)))
  (swiftmac-css-set-code-table 'paul 'stress table))

(defun swiftmac-get-stress-code (value family)
  (or family (setq family 'paul))
  (if value 
      (aref (swiftmac-css-get-code-table family 'stress)
            value)
    ""))

;;;   richness

;;;   paul richness TODO
(let ((table (make-vector 10 "")))
  (swiftmac-css-set-code-table 'paul 'richness table))

(defun swiftmac-get-richness-code (value family)
  (or family (setq family 'paul))
  (if value 
      (aref (swiftmac-css-get-code-table family 'richness)
            value)
    ""))

;;;   swiftmac-define-voice-from-acss

(defun swiftmac-define-voice-from-acss (name style)
  "Define NAME to be a swiftmac voice as specified by settings in STYLE."
  (let* ((family(acss-family style))
         (command
          (concat 
           (swiftmac-get-family-code family)
           (swiftmac-get-average-pitch-code (acss-average-pitch style) family)
           (swiftmac-get-pitch-range-code (acss-pitch-range style) family)
           (swiftmac-get-stress-code (acss-stress style) family)
           (swiftmac-get-richness-code (acss-richness style) family))))
    (swiftmac-define-voice name command)))

;;;  Configurater 
;;;###autoload
(defun swiftmac-configure-tts ()
  "Configure TTS  to use swiftmac."
  (setq tts-default-voice 'paul)
  (fset 'tts-voice-defined-p 'swiftmac-voice-defined-p)
  (fset 'tts-get-voice-command 'swiftmac-get-voice-command)
  (fset 'tts-define-voice-from-acss 'swiftmac-define-voice-from-acss)
  (setq tts-voice-capabilities-function #'swiftmac-voice-capabilities)
  (setq tts-voice-inventory-function #'swiftmac-voice-inventory)
  (setq tts-voice-inventory-refresh-function
        #'swiftmac-refresh-voice-inventory)
  (setq tts-voice-preview-function #'tts-default-voice-preview-sequence)
  (setq tts-voice-preview-code-function #'swiftmac-voice-preview-code)
  (setq tts-default-speech-rate swiftmac-default-speech-rate)
  (set-default 'tts-default-speech-rate swiftmac-default-speech-rate)
  (tts-unicode-update-untouched-charsets
   '(ascii latin-iso8859-1 latin-iso8859-15 latin-iso8859-9
           eight-bit-graphic))
  (setq emacsvox-play-program nil))

;;;  tts-env for Mac:

(provide 'swiftmac-voices)
