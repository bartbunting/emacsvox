;;; emacsvox-flyspell.el --- Speech enable flyspell -*- lexical-binding: t; -*-
;;
;; $Author: tv.raman.tv $
;; Description:  Emacsvox extension to speech enable flyspell
;; Keywords: Emacsvox, Ispell, Spoken Output, fly spell checking
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

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:

;; This module speech enables flyspell.
;; it loads flyspell-correct if available,
;; And when loading flyspell-correct sets up that module
;; to use  one of   three supported correction styles:
;; @itemize @bullet
;; @item ido: IDO-like completion with C-s and C-r moving through choices.
;; @item popup:Use  up and down arrows to move through  corrections.
;; @item helm: A helm interface for picking amongst  corrections.
;; @end itemize
;; See documentation for package flyspell-correct for additional
;; details.
;;
;; Use Customization emacsvox-flyspell-correct to pick
;; between ido, popup and helm.

;;; Code:

;;;  Requires

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'flyspell)

;;;  define personalities

(defgroup emacsvox-flyspell nil
  "Emacsvox support for on the
fly spell checking."
  :group 'emacsvox
  :group 'flyspell
  :prefix "emacsvox-flyspell-")

(voice-setup-add-map
 '((flyspell-incorrect voice-bolden)
   (flyspell-duplicate voice-monotone-extra)
   (flyspell-correct-highlight-face voice-animate)))

;;;  advice

(defun emacsvox--advice-flyspell-buffer-around (orig-fun &rest args)
  "Silence icon."
  (let ((emacsvox-use-icons nil)) (apply orig-fun args)))

(advice-add 'flyspell-buffer :around
            #'emacsvox--advice-flyspell-buffer-around)

(defun emacsvox--advice-flyspell-region-around (orig-fun &rest args)
  "Silence icon."
  (let ((emacsvox-use-icons nil)) (apply orig-fun args)))

(advice-add 'flyspell-region :around
            #'emacsvox--advice-flyspell-region-around)

(defun emacsvox--advice-flyspell-auto-correct-word-around
    (orig-fun &rest args)
  "Speak the correction we inserted."
  (if (ems-interactive-p 'flyspell-auto-correct-word)
      (ems-with-messages-silenced
        (let ((result (apply orig-fun args)))
          (tts-speak (car (flyspell-get-word nil)))
          (when (sit-for 1)
            (dtk-notify (cl-second flyspell-auto-correct-ring)))
          (when (sit-for 1)
            (emacsvox-speak-message-again))
          (emacsvox-icon 'select-object)
          result))
    (apply orig-fun args)))

(advice-add 'flyspell-auto-correct-word :around
            #'emacsvox--advice-flyspell-auto-correct-word-around)

(defun emacsvox--advice-flyspell-unhighlight-at-before (position)
  "handle highlight/unhighlight."
  (let ((overlay-list (overlays-at position)) (o nil))
    (while overlay-list
      (setq o (car overlay-list))
      (when (flyspell-overlay-p o)
        (put-text-property (overlay-start o) (overlay-end o)
                           'personality nil))
      (setq overlay-list (cdr overlay-list)))))

(advice-add 'flyspell-unhighlight-at :before
            #'emacsvox--advice-flyspell-unhighlight-at-before)

(add-hook
 'flyspell-incorrect-hook
 #'(lambda (_s _e p)
     (unless (eq p 'doublon) (emacsvox-icon 'help))
     nil))

;;;  use flyspell-correct if available:
(defcustom emacsvox-flyspell-correct
  (cond
   ((locate-library "flyspell-correct-ido") 'flyspell-correct-ido)
   ((locate-library "flyspell-correct-popup") 'flyspell-correct-popup)
   ((locate-library "flyspell-correct-helm") 'flyspell-correct-helm)
   (t nil))
  "Correction style to use with flyspell."
  :type 'symbol)

;; flyspell-correct is available on melpa:
(cl-declaim (special flyspell-mode-map))
(when
    (and (bound-and-true-p flyspell-mode-map)
         (locate-library "flyspell-correct"))
  (define-key flyspell-mode-map (kbd "s-b") 'flyspell-buffer)
  (define-key flyspell-mode-map (kbd "s-r") 'flyspell-region)
  (define-key flyspell-mode-map (kbd "C-x .") 'flyspell-correct-at-point)
  (define-key flyspell-mode-map (kbd "C-'") 'flyspell-correct-previous)
  (define-key flyspell-mode-map (kbd "C-;") 'flyspell-correct-wrapper)
  (require emacsvox-flyspell-correct))

(defconst emacsvox-flyspell--correct-targets
  '(flyspell-correct-next
    flyspell-correct-previous
    flyspell-correct-at-point)
  "Commands supplied by the optional flyspell-correct package.")

(defmacro emacsvox-flyspell--define-correct-feedback (targets)
  "Define feedback functions for flyspell-correct TARGETS."
  (declare (indent 1) (debug (sexp)))
  `(progn
     ,@(mapcar
        (lambda (target)
          (let ((function
                 (intern (format "emacsvox--advice-%s-after" target))))
            `(defun ,function (&rest _)
               "Speak the corrected word."
               (when (ems-interactive-p ',target)
                 (tts-speak (car (flyspell-get-word nil)))))))
        targets)))

(emacsvox-flyspell--define-correct-feedback
    (flyspell-correct-next
     flyspell-correct-previous
     flyspell-correct-at-point))

(defun emacsvox-flyspell--install-correct-advice ()
  "Attach feedback to available flyspell-correct commands."
  (dolist (target emacsvox-flyspell--correct-targets)
    (when (fboundp target)
      (advice-add
       target :after
       (intern (format "emacsvox--advice-%s-after" target))))))

(with-eval-after-load 'flyspell-correct
  (emacsvox-flyspell--install-correct-advice))

(defun emacsvox--advice-flyspell-goto-next-error-after (&rest _)
  "Speak the destination after interactive error movement."
  (when (ems-interactive-p 'flyspell-goto-next-error)
    (emacsvox-speak-line)))

(advice-add 'flyspell-goto-next-error :after
            #'emacsvox--advice-flyspell-goto-next-error-after)

(provide 'emacsvox-flyspell)
;;;  emacs local variables

;;; emacsvox-flyspell.el ends here
