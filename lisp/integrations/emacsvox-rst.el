;;; emacsvox-rst.el --- Speech-enable RST  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2007, 2011, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop rst
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
;; RST ==  rst-mode for editing rst text files.
;; This module speech-enables rst-mode.
;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Map Faces

(voice-setup-add-map
 '(
   (rst-block   voice-annotate)
   (rst-external   voice-animate)
   (rst-definition   voice-bolden-medium)
   (rst-directive voice-smoothen)
   (rst-comment   voice-monotone-extra)
   (rst-emphasis1   voice-animate)
   (rst-emphasis2   voice-animate-extra)
   (rst-literal   voice-monotone-medium)
   (rst-reference   voice-bolden)
   (rst-transition   voice-lighten)
   (rst-adornment   voice-animate)
   (rst-level-1 voice-bolden)
   (rst-level-2  voice-bolden-medium)
   (rst-level-3  voice-lighten-medium)
   (rst-level-4 voice-lighten-extra)
   ))

;;;  Speech-enable interactive commands:

(defmacro emacsvox-rst--define-after-advice (target &rest body)
  "Define direct after advice for interactive RST TARGET using BODY."
  (declare (indent 1))
  (let ((function
         (intern (format "emacsvox--advice-%s-after" target))))
    `(progn
       (defun ,function (&rest _)
         ,(format "Provide spoken feedback after `%s'." target)
         (when (ems-interactive-p ',target)
           ,@body))
       (advice-add
        ',target :after #',function '((name . emacsvox))))))

(emacsvox-rst--define-after-advice rst-shift-region
  (emacsvox-icon 'large-movement)
  (emacsvox-speak-line))

(dolist
    (target
     '(rst-goto-section
       rst-forward-section
       rst-backward-section
       rst-forward-indented-block))
  (eval
   `(emacsvox-rst--define-after-advice ,target
      (emacsvox-icon 'section)
      (emacsvox-speak-line))))

(dolist
    (target
     '(rst-compile
       rst-compile-alt-toolset
       rst-adjust
       rst-adjust-section-title
       rst-compile-find-conf
       rst-compile-pdf-preview
       rst-compile-pseudo-region
       rst-compile-slides-preview
       rst-display-adornments-hierarchy))
  (eval
   `(emacsvox-rst--define-after-advice ,target
      (emacsvox-icon 'task-done)
      (emacsvox-speak-line))))

(emacsvox-rst--define-after-advice rst-toc
  (emacsvox-icon 'open-object)
  (emacsvox-speak-mode-line))

(emacsvox-rst--define-after-advice rst-toc-mode-goto-section
  (emacsvox-icon 'large-movement)
  (emacsvox-speak-line))

(emacsvox-rst--define-after-advice rst-toc-quit-window
  (emacsvox-icon 'close-object)
  (emacsvox-speak-mode-line))

(emacsvox-rst--define-after-advice rst-force-fill-paragraph
  (emacsvox-icon 'fill-object)
  (emacsvox-speak-mode-line))

(emacsvox-rst--define-after-advice rst-mark-section
  (emacsvox-icon 'mark-object)
  (emacsvox-speak-line))

(dolist
    (target
     '(rst-bullet-list-region
       rst-convert-bullets-to-enumeration
       rst-enumerate-region))
  (eval
   `(emacsvox-rst--define-after-advice ,target
      (emacsvox-icon 'item)
      (message "Bulletized. "))))

(dolist
    (target
     '(rst-insert-list
       rst-insert-list-new-item
       rst-toc-insert))
  (eval
   `(emacsvox-rst--define-after-advice ,target
      (emacsvox-icon 'open-object)
      (emacsvox-speak-line))))

(dolist
    (target
     '(rst-join-paragraph
       rst-line-block-region
       rst-straighten-adornments
       rst-straighten-bullets-region))
  (eval
   `(emacsvox-rst--define-after-advice ,target
      (emacsvox-icon 'task-done)
      (emacsvox-speak-line))))

(provide 'emacsvox-rst)

;;; emacsvox-rst.el ends here
