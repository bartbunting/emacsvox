;;; emacsvox-devdocs.el --- Speech-enable DEVDOCS  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop devdocs
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
;;; DEVDOCS == Browse DevDocs

;;; Code:

;;   Required modules:

(eval-when-compile  (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Map Faces:

(voice-setup-add-map 
 '(
   (devdocs-code-block voice-monotone)))

;;;  Interactive Commands:

'(
  devdocs-delete

  devdocs-peruse

  devdocs-update-all
  )

(defconst emacsvox-devdocs--advice-targets
  '(devdocs-first-page
    devdocs-go-back devdocs-go-forward
    devdocs-goto-page devdocs-goto-target
    devdocs-last-page devdocs-lookup devdocs-peruse
    devdocs-next-entry devdocs-next-page
    devdocs-previous-entry devdocs-previous-page devdocs-search)
  "Current DevDocs commands that receive speech feedback.")

(cl-loop
 for target in emacsvox-devdocs--advice-targets
 for advice-function =
 (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(defun ,advice-function (&rest _)
     ,(format "Speak after `%s'." target)
     (when (ems-interactive-p ',target)
       (emacsvox-icon 'open-object)
       (emacsvox-speak-line)))))

(defun emacsvox-devdocs--install-advice ()
  "Install native advice after the optional DevDocs package loads."
  (dolist (target emacsvox-devdocs--advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target :after function '((name . emacsvox)))))))

(with-eval-after-load 'devdocs
  (emacsvox-devdocs--install-advice))

(provide 'emacsvox-devdocs)
;;;  end of file

                                        ; 
                                        ; 
                                        ;

;;; emacsvox-devdocs.el ends here
