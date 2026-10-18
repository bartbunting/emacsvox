;;; emacsvox-ffap.el --- Speech-enable FFAP  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2007, 2019, T. V. Raman
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop ffap
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
;;; FFAP ==  Find file at point and friends

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)
(eval-when-compile (require 'ffap))

;;;  Map Faces:

(voice-setup-add-map 
 '((ffap voice-bolden)))

;;;  Interactive Commands:

(cl-loop
 for target in
 '(
   ffap ffap-alternate-file ffap-alternate-file-other-window ffap-at-mouse
   ffap-dired-other-frame ffap-dired-other-window
   ffap-list-directory ffap-literally
   ffap-next ffap-next-url
   ffap-other-frame ffap-other-tab ffap-other-window
   ffap-read-only ffap-read-only-other-frame
   ffap-read-only-other-tab ffap-read-only-other-window)
 for function = (intern (format "emacsvox--advice-%s-after" target))
 do
 (eval
  `(progn
     (defun ,function (&rest _)
       "Cue and speak the result of an interactive FFAP command."
       (when (ems-interactive-p ',target)
         (emacsvox-icon 'open-object)
         (emacsvox-speak-mode-line)))
     (advice-add
      ',target :after #',function '((name . emacsvox))))))

(provide 'emacsvox-ffap)
;;;  end of file

                                        ; 
                                        ; 
                                        ;

;;; emacsvox-ffap.el ends here
