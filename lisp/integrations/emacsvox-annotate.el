;;; emacsvox-annotate.el --- Annotations  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2007, 2019, T. V. Raman
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop annotate
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
    (tts-notify "Added annotation")))

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
         (tts-notify (overlay-get o 'annotation)))))))

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

;;; emacsvox-annotate.el ends here
