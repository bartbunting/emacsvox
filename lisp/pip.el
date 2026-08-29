;;; pip --- Interface To Piper TTS -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Keywords: Emacsvox,  Audio Desktop Piper TTS
;;; LCD Archive Entry:
;; emacsvox| T. V. Raman |raman@cs.cornell.edu
;; A speech interface to Emacs |
;;  $Revision: 4532 $ |
;; Location https://github.com/robertmeta/emacsvox
;;;   Copyright:

;; Copyright (C) 1995 -- 2022, T. V. Raman
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

;;; Commentary:
;; Piper TTS is an Open Source neural-net TTS engine.
;; This module exposes Piper TTS to Emacs.

;; @enumerate
;;  @item  Sandbox for
;; @url{https://github.com/OHF-Voice/piper1-gpl}
;; @item Install piper-tts in a virtual environment whose bin directory is on
;; Emacs's PATH.
;; @item Set location of voice data in @code{pip-data-dir}.
;; Default is @code{~/.local/share/voices-piper}
;; @item Use that environment's Python to run
;; @code{-m piper.download_voices}.  Download a voice with its
;; @code{--data-dir} option set to @code{pip-data-dir}.
;; @item @code{M-x pip-speak} to speak.  @item At present
;; @code{piper} is not suitable for use as a primary TTS engine for
;; Emacsvox through this experimental per-request wrapper, given its model-load
;; latency and fixed 22,050 Hz raw-output assumption.
;; @item However it might be
;; interesting to use it for lower-priority speech where quality
;; trumps latency.
;; @end enumerate

;;; Code:

;;   Required modules
(require 'cl-lib)

(defvar pip-data-dir
  (expand-file-name "~/.local/share/voices-piper")
  "Where voice models live.")

(defvar pip-voices
  nil
  "Available voices.")

(defvar pip-pip
  (expand-file-name
   "../servers/piper/pipspeak" (file-name-directory load-file-name))
  "Launch Piper TTS pipeline")

(defvar pip-piper nil "process handle")

(defvar pip-model nil
  "Current voice model.")

(defun pip--refresh-voices ()
  "Refresh `pip-voices' from `pip-data-dir'."
  (setq pip-voices
        (and (file-directory-p pip-data-dir)
             (directory-files pip-data-dir 'full "\\.onnx\\'")))
  (unless (and (stringp pip-model) (file-readable-p pip-model))
    (setq pip-model (cl-first pip-voices)))
  pip-voices)

(defun pip--ensure-ready ()
  "Signal a useful error unless Piper is ready to start."
  (unless (executable-find "piper")
    (user-error "Install Piper and put the piper executable on Emacs's PATH"))
  (unless (file-executable-p pip-pip)
    (user-error "Piper wrapper is not executable: %s" pip-pip))
  (pip--refresh-voices)
  (unless (and (stringp pip-model) (file-readable-p pip-model))
    (user-error
     "No Piper voice model found; set pip-model or add an .onnx file to %s"
     pip-data-dir)))

(defun pip-model-select (voice)
  "Select default from available choices.
Restarts piper pipeline if already running."
  (interactive
   (list
    (completing-read "Voice Model:" (pip--refresh-voices) nil t)))
  
  (setq pip-model voice)
  (when (process-live-p pip-piper) (pip-stop))
  (when (called-interactively-p 'interactive)
    (pip-speak (format "Selected voice %s" (file-name-base
                                            pip-model)))))

(defvar pip-device "tts_quarter_right"
  "Alsa device for Piper.")

(defvar pip-devices
  '("default"  "tts_mono_left" "tts_mid_left" "tts_mono_right"
    "tts_mid_right"
    "tts_quarter_right" "tts_quarter_left")
  "Alsa devices.")

(defun pip-device-select (device)
  "Select default from available choices.
Restarts piper pipeline if already running."
  (interactive
   (list (completing-read "Device" pip-devices nil t)))
  
  (setq pip-device device )
  (when (process-live-p pip-piper) (pip-stop))
  (when (called-interactively-p 'interactive)
    (pip-speak (format "Selected device %s" pip-device))))

(defun pip-start ()
  "Start the Piper process"
  (interactive)
  
  (unless (process-live-p pip-piper)
    (pip--ensure-ready)
    (let ((process-connection-type nil))
      (setq  pip-piper
             (start-process  "pip" nil  pip-pip pip-model pip-device))))
  (when (called-interactively-p 'interactive)
    (pip-speak (format  "Piper is running with %s!" pip-model))))

(defun pip-stop ()
  "Stop Piper TTS"
  (interactive)
  
  (delete-process pip-piper))
;;;###autoload
(defun pip-speak (text)
  "Speak text"
  (interactive "sText:")
  
  (unless (process-live-p pip-piper) (pip-start))
  (process-send-string pip-piper  (format "%s\n" text))
  (process-send-eof pip-piper))

(provide 'pip)
;;; End of file
