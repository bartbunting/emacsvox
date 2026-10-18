;;; emacsvox-pydoc.el --- Speech-enable PYDOC  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2007, 2011, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop pydoc
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
;; PYDOC ==  Python Documentation Viewer

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(require 'emacsvox-aural-submission)
(require 'emacsvox-aural-provider-workflows)

;;;  Map Faces->Voices

(defconst emacsvox-pydoc--face-voice-map
  '((pydoc-example-leader-face voice-annotate))
  "Voice personalities for the current Pydoc interface faces.")

(voice-setup-add-map emacsvox-pydoc--face-voice-map)

(defun emacsvox-pydoc-enable-aural-context ()
  "Identify the current Pydoc buffer to Aural Presentation."
  (setq-local emacsvox-aural-module 'python))

(add-hook 'pydoc-mode-hook #'emacsvox-pydoc-enable-aural-context)

(defun emacsvox-pydoc--present-buffer ()
  "Present the current Pydoc buffer as one native transaction."
  (let ((content
         (emacsvox-aural-source-substring (point-min) (point-max)))
        (facts
         '(:role code-construct
           :events (focus-entered)
           :syntax-role documentation)))
    (if (> (length content) 0)
        (emacsvox-aural-submit
         content
         :facts facts
         :module 'python
         :occasion 'navigation
         :compatibility-actions
         (list (emacsvox-aural-compatibility-icon 'help)))
      (emacsvox-aural-submit-actions
       :facts facts
       :module 'python
       :occasion 'navigation
       :compatibility-actions
       (list (emacsvox-aural-compatibility-icon 'help))))))

;;;  Advice Interactive Commands:

(defun emacsvox--advice-pydoc-after (&rest _)
  "Present documentation displayed by an interactive Pydoc command."
  (when (ems-interactive-p 'pydoc)
    (emacsvox-pydoc--present-buffer)))

(defun emacsvox-pydoc--install-advice ()
  "Install advice after the optional Pydoc package loads."
  (when (and (fboundp 'pydoc)
             (not (advice-member-p
                   #'emacsvox--advice-pydoc-after 'pydoc)))
    (advice-add
     'pydoc :after #'emacsvox--advice-pydoc-after
     '((name . emacsvox)))))

(with-eval-after-load 'pydoc
  (emacsvox-pydoc--install-advice))

(provide 'emacsvox-pydoc)

;;; emacsvox-pydoc.el ends here
