;;; emacsvox-forge.el --- Speech-enable FORGE  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2007, 2011, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop forge
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
;; FORGE ==  Work with Github, Gitlab etc from inside magit.
;; This module speech-enables magit/forge.

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  Map Faces:

(voice-setup-add-map 
 '(
   (forge-post-author voice-lighten)
   (forge-post-date voice-animate)
   (forge-topic-closed voice-lighten)
   (forge-topic-merged voice-monotone)
   (forge-topic-open voice-bolden)
   (forge-topic-unmerged voice-animate)
   (forge-topic-unread voice-animate)))

;;;  Interactive Commands:

(defconst emacsvox-forge--advice-targets
  '(forge-create-issue forge-create-post forge-create-pullreq
    forge-list-issues forge-list-notifications forge-list-pullreqs
    forge-visit-issue forge-visit-pullreq forge-visit-topic)
  "Current Forge commands that receive native advice.")

(dolist (target emacsvox-forge--advice-targets)
  (let ((advice-function
         (intern (format "emacsvox--advice-%s-after" target))))
    (eval
     `(defun ,advice-function (&rest _)
        ,(format "Provide speech feedback after `%s'." target)
        (when (ems-interactive-p ',target)
          (emacsvox-icon 'open-object)
          (emacsvox-speak-line))))))

(defun emacsvox-forge--install-advice ()
  "Install native advice after Forge loads."
  (dolist (target emacsvox-forge--advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (when (and (fboundp target)
                 (not (advice-member-p function target)))
        (advice-add target :after function '((name . emacsvox)))))))

(with-eval-after-load 'forge
  (emacsvox-forge--install-advice))

(provide 'emacsvox-forge)

;;; emacsvox-forge.el ends here
