;;; emacsvox-add-log.el --- Speech-enable add-log  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop ChangeLogs
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
;; Speech-enable Changelog mode

;;; Code:

;;   Required modules:

(eval-when-compile (require 'cl-lib))
(require 'emacsvox-preamble)

;;;  define personalities

(defgroup emacsvox-add-log nil
  "Customize Emacsvox for change-log-mode and friends."
  :group 'emacsvox)

(voice-setup-add-map
 '(
   (change-log-acknowledgment voice-smoothen)
   (change-log-conditionals voice-animate)
   (change-log-email voice-lighten)
   (change-log-function voice-bolden-extra)
   (change-log-file voice-bolden)
   (change-log-email voice-lighten)
   (change-log-list voice-lighten)
   (change-log-name voice-lighten-extra)
   (change-log-date voice-monotone-extra)
   ))

(provide 'emacsvox-add-log)

;;; emacsvox-add-log.el ends here
