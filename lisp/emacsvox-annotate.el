;;; emacsvox-annotate.el --- Annotations  -*- lexical-binding: t; -*-
;; $Author: tv.raman.tv $
;; Description:  Speech-enable ANNOTATE An Emacs Interface to annotate
;; Keywords: Emacsvox,  Audio Desktop annotate
;;;   LCD Archive entry:

;; LCD Archive Entry:
;; emacsvox| T. V. Raman |raman@cs.cornell.edu
;; A speech interface to Emacs |
;;  $Revision: 4532 $ |
;; Location https://github.com/robertmeta/emacsvox
;; 

;;;   Copyright:
;; Copyright (C) 1995 -- 2007, 2019, T. V. Raman
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
;; MERCHANTABILITY or FITNANNOTATE FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; Commentary:
;; ANNOTATE == annotate.el from melpa
;; Speech-enable creation and navigation of annotations.
;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'annotate "annotate" 'noerror)

;;;  Map Faces:

(voice-setup-add-map 
 '(
   (annotate-annotation voice-animate)
   (annotate-annotation-secondary voice-monotone)
   (annotate-highlight voice-smoothen)
   (annotate-highlight-secondary voice-lighten)
   (annotate-prefix voice-bolden)))

;;;  Interactive Commands:

(defun emacsvox--advice-annotate-annotate-after (&rest _)
  "speak."
  (when (ems-interactive-p 'annotate-annotate)
    (dtk-notify "Added annotation")))

(cl-loop
 for target in
 '(annotate-goto-next-annotation
   annotate-goto-previous-annotation)
 for advice-function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     "speak."
     (when (ems-interactive-p ',target)
       (let ((o (cl-first (overlays-at (point)))))
         (emacsvox-icon 'large-movement)
         (emacsvox-speak-line)
         (dtk-notify (overlay-get o 'annotation)))))))

(defconst emacsvox-annotate--advice-targets
  '(annotate-annotate
    annotate-goto-next-annotation
    annotate-goto-previous-annotation)
  "Current Annotate targets that receive native after advice.")

(defun emacsvox-annotate--install-advice ()
  "Install advice after the optional Annotate package loads."
  (dolist (target emacsvox-annotate--advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target :after function '((name . emacsvox)))))))

(with-eval-after-load 'annotate
  (emacsvox-annotate--install-advice))

(provide 'emacsvox-annotate)
;;;  end of file
