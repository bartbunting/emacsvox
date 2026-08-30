;;; emacsvox-flyspell.el --- Speech enable flyspell -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox, Ispell, Spoken Output, fly spell checking
;; URL: https://github.com/bartbunting/emacsvox

;; This file is part of Emacsvox.
;;
;; Emacsvox is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; Emacsvox is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with Emacsvox.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This module speech enables flyspell.
;; It loads flyspell-correct if available and uses its native completion
;; interface by default, allowing the active completion frontend (such as
;; Vertico) to present corrections.  Three alternate styles remain available:
;; @itemize @bullet
;; @item ido: IDO-like completion with C-s and C-r moving through choices.
;; @item popup:Use  up and down arrows to move through  corrections.
;; @item helm: A helm interface for picking amongst  corrections.
;; @end itemize
;; See documentation for package flyspell-correct for additional
;; details.
;;
;; Use Customization emacsvox-flyspell-correct to choose native completion or
;; an explicit IDO, Popup, or Helm interface.

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
            (tts-notify (cl-second flyspell-auto-correct-ring)))
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

;;;  Use flyspell-correct if available:

(defvar flyspell-correct-interface)
(declare-function flyspell-correct-completing-read
                  "flyspell-correct" (candidates word))

(defvar emacsvox-flyspell--suggestion-count nil
  "Number of suggestions in the active native Flyspell correction.")

(defun emacsvox-flyspell-correct-completing-read (candidates word)
  "Correct WORD from CANDIDATES through native completion.
Publish the suggestion count dynamically so a speech-enabled completion
frontend can include it in the initial presentation."
  (let ((emacsvox-flyspell--suggestion-count (length candidates)))
    (flyspell-correct-completing-read candidates word)))

(defcustom emacsvox-flyspell-correct
  (and (locate-library "flyspell-correct") 'flyspell-correct)
  "Correction interface module to use with Flyspell.
The default `flyspell-correct' value uses standard completion and therefore
honors the active completion frontend.  Alternate IDO, Popup, and Helm modules
remain available for explicit selection."
  :type
  '(choice
    (const :tag "Native completion" flyspell-correct)
    (const :tag "IDO" flyspell-correct-ido)
    (const :tag "Popup" flyspell-correct-popup)
    (const :tag "Helm" flyspell-correct-helm)
    (const :tag "Disabled" nil)))

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
  (require emacsvox-flyspell-correct)
  (when (eq emacsvox-flyspell-correct 'flyspell-correct)
    (setq flyspell-correct-interface
          #'emacsvox-flyspell-correct-completing-read)))

(defconst emacsvox-flyspell--correct-targets
  '(flyspell-correct-next
    flyspell-correct-previous
    flyspell-correct-at-point
    flyspell-correct-wrapper
    flyspell-correct-region)
  "Commands supplied by the optional flyspell-correct package.")

(defun emacsvox-flyspell--completion-owns-feedback-p ()
  "Return non-nil when Vertico owns native correction feedback."
  (and
   (bound-and-true-p vertico-mode)
   (boundp 'flyspell-correct-interface)
   (memq
    flyspell-correct-interface
    '(emacsvox-flyspell-correct-completing-read
      flyspell-correct-completing-read))))

(defmacro emacsvox-flyspell--define-correct-feedback (targets)
  "Define feedback functions for flyspell-correct TARGETS."
  (declare (indent 1) (debug (sexp)))
  `(progn
     ,@(mapcar
        (lambda (target)
          (let ((function
                 (intern (format "emacsvox--advice-%s-after" target))))
            `(defun ,function (&rest _)
               "Speak the corrected word when completion did not own feedback."
               (when (and (ems-interactive-p ',target)
                          (not
                           (emacsvox-flyspell--completion-owns-feedback-p)))
                 (when-let* ((details (ignore-errors (flyspell-get-word nil)))
                             (word (car-safe details))
                             ((stringp word)))
                   (tts-speak word))))))
        targets)))

(emacsvox-flyspell--define-correct-feedback
    (flyspell-correct-next
     flyspell-correct-previous
     flyspell-correct-at-point
     flyspell-correct-wrapper
     flyspell-correct-region))

(defun emacsvox-flyspell--install-correct-advice ()
  "Attach feedback to available flyspell-correct commands."
  (dolist (target emacsvox-flyspell--correct-targets)
    (when (fboundp target)
      (let ((function
             (intern (format "emacsvox--advice-%s-after" target))))
        (unless (advice-member-p function target)
          (advice-add target :after function))))))

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
