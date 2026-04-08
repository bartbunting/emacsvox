;;; emacsvox-corfu.el --- Speech-enable Corfu -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable CORFU An Emacs Interface to corfu
;; Keywords: Emacsvox,  Audio Desktop corfu
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
;; CORFU ==  Completion Overlay Region FUnction.
;; This module speech-enables corfu.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'corfu nil 'noerror)

;;;  Map Faces:

(voice-setup-add-map
 '(
   (corfu-default voice-smoothen)
   (corfu-current voice-bolden)
   (corfu-bar voice-monotone)
   (corfu-border voice-smoothen)
   (corfu-annotations voice-annotate)
   (corfu-deprecated voice-monotone-extra)))

;;;  State tracking:

(defvar emacsvox-corfu--prev-candidate nil
  "Previously spoken candidate.")

(defvar emacsvox-corfu--prev-index -1
  "Previously spoken candidate index.")

;;;  Helper functions:

(defun emacsvox-corfu--current-candidate ()
  "Return current corfu candidate or nil."
  (when (and (bound-and-true-p corfu--candidates)
             (bound-and-true-p corfu--index)
             (>= corfu--index 0)
             (< corfu--index (length corfu--candidates)))
    (nth corfu--index corfu--candidates)))

(defun emacsvox-corfu--candidate-with-annotation ()
  "Return current candidate with annotation if available."
  (when-let* ((cand (emacsvox-corfu--current-candidate)))
    (let ((ann (and (bound-and-true-p corfu--metadata)
                    (completion-metadata-get corfu--metadata
                                             'annotation-function))))
      (if (and ann (functionp ann))
          (let ((annotation (funcall ann cand)))
            (if (and annotation (not (string-empty-p annotation)))
                (format "%s  %s" cand (string-trim annotation))
              cand))
        cand))))

(defun emacsvox-corfu--speak-candidate ()
  "Speak current corfu candidate if it changed."
  (when-let* ((text (emacsvox-corfu--candidate-with-annotation)))
    (unless (and (equal text emacsvox-corfu--prev-candidate)
                 (equal corfu--index emacsvox-corfu--prev-index))
      (setq emacsvox-corfu--prev-candidate text
            emacsvox-corfu--prev-index corfu--index)
      (dtk-speak text))))

;;;  Advice Interactive Commands:

(defun ems--corfu-insert-around (orig-fun &rest args)
  "Speak inserted completion."
  (let ((result (apply orig-fun args)))
    (cond
     ((ems-interactive-p)
      (emacsvox-icon 'complete)
      (emacsvox-speak-line))
     (t nil))
    result))

(advice-add 'corfu-insert :around #'ems--corfu-insert-around)

(defun ems--corfu-quit-after (&rest _)
  "Speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'close-object)
    (setq emacsvox-corfu--prev-candidate nil
          emacsvox-corfu--prev-index -1)))

(advice-add 'corfu-quit :after #'ems--corfu-quit-after)

(defun ems--corfu-reset-after (&rest _)
  "Speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'close-object)
    (setq emacsvox-corfu--prev-candidate nil
          emacsvox-corfu--prev-index -1)))

(advice-add 'corfu-reset :after #'ems--corfu-reset-after)

(defun ems--corfu-insert-separator-after (&rest _)
  "Speak."
  (when (ems-interactive-p)
    (emacsvox-icon 'select-object)
    (dtk-tone 500 50)))

(advice-add 'corfu-insert-separator :after
            #'ems--corfu-insert-separator-after)

(defun ems--corfu-complete-after (&rest _)
  "Speak completed text."
  (when (ems-interactive-p)
    (emacsvox-icon 'complete)
    (emacsvox-speak-line)))

(advice-add 'corfu-complete :after #'ems--corfu-complete-after)

;;;  Navigation advice:

(cl-loop
 for f in
 '(corfu-next corfu-previous corfu-first corfu-last
   corfu-scroll-up corfu-scroll-down)
 do
 (eval
  `(defadvice ,f (after emacsvox pre act comp)
     "Speak current candidate."
     (when (ems-interactive-p)
       (emacsvox-corfu--speak-candidate)))))

;;;  Internal advice:

(defun ems--corfu--update-after (&rest _)
  "Speak candidate after corfu updates."
  (when (and (bound-and-true-p corfu-mode)
             (bound-and-true-p corfu--candidates))
    (emacsvox-corfu--speak-candidate)))

(advice-add 'corfu--update :after #'ems--corfu--update-after)

;;;  Hooks:

(defun emacsvox-corfu--completion-hook ()
  "Reset state when completion-in-region-mode changes."
  (unless completion-in-region-mode
    (setq emacsvox-corfu--prev-candidate nil
          emacsvox-corfu--prev-index -1)))

(add-hook 'completion-in-region-mode-hook
          #'emacsvox-corfu--completion-hook)

;;;  eval-after-load:

(eval-after-load 'corfu
  '(progn
     (when (bound-and-true-p corfu-mode)
       (setq emacsvox-corfu--prev-candidate nil
             emacsvox-corfu--prev-index -1))))

(provide 'emacsvox-corfu)
;;;  end of file
