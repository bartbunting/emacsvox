;;; emacsvox-helpful.el --- Speech-enable HELPFUL  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable HELPFUL An Emacs Interface to helpful
;; Keywords: Emacsvox,  Audio Desktop helpful
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
;; HELPFUL == Better *Help* buffers.
;; Speech-enable helpful to provide auditory feedback for
;; richer help buffers showing source, references, and more.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'helpful nil 'noerror)

;;;  Map Faces:

(voice-setup-add-map
 '(
   (helpful-heading voice-bolden)
   (helpful-button voice-animate)
   (helpful-key-binding voice-lighten)))

;;;  Advice Interactive Commands:

(defun ems--helpful-speak-first-line ()
  "Speak the first line of the current helpful buffer."
  (let ((buf nil))
    (dolist (b (buffer-list))
      (when (and (null buf) (string-prefix-p "*helpful " (buffer-name b)))
        (setq buf b)))
    (when buf
      (with-current-buffer buf
        (goto-char (point-min))
        (emacsvox-speak-line)))))

(defconst emacsvox-helpful--help-targets
  '(helpful-callable helpful-function helpful-macro helpful-command
    helpful-variable helpful-key helpful-symbol helpful-at-point)
  "Helpful commands that display a help buffer.")

(dolist (target emacsvox-helpful--help-targets)
  (let ((advice-function
         (intern (format "emacsvox--advice-%s-after" target))))
    (eval
     `(defun ,advice-function (&rest _)
        ,(format "Speak help displayed by `%s'." target)
        (when (ems-interactive-p ',target)
          (emacsvox-icon 'help)
          (ems--helpful-speak-first-line))))))

(defun emacsvox--advice-helpful-kill-buffers-after (&rest _)
  "Announce that helpful buffers were closed."
  (when (ems-interactive-p 'helpful-kill-buffers)
    (emacsvox-icon 'close-object)
    (tts-speak "help buffers closed")))

(defconst emacsvox-helpful--advice
  (append
   (mapcar
    (lambda (target)
      (list target :after
            (intern (format "emacsvox--advice-%s-after" target))))
    emacsvox-helpful--help-targets)
   '((helpful-kill-buffers :after
      emacsvox--advice-helpful-kill-buffers-after)))
  "Current Helpful targets and their native advice functions.")

(defun emacsvox-helpful--install-advice ()
  "Install native advice after Helpful loads."
  (dolist (entry emacsvox-helpful--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target where function '((name . emacsvox)))))))

(with-eval-after-load 'helpful
  (emacsvox-helpful--install-advice))

(provide 'emacsvox-helpful)
;;;  end of file
