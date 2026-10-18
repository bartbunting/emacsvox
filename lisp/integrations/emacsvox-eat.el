;;; emacsvox-eat.el --- Speech-enable EAT  -*- lexical-binding: t; -*-

;; Copyright (C) 1995 -- 2024, T. V. Raman
;; Copyright (c) 1994, 1995 by Digital Equipment Corporation.
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox, Audio Desktop, eat
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
;; Public entry point for Emacsvox speech access to EAT terminals.
;;
;; The implementation is split by responsibility:
;; - `emacsvox-eat-core' owns screen observation, lifecycle, and output.
;; - `emacsvox-eat-input' owns input, deletion, navigation, and completion.
;; - `emacsvox-eat-review' owns frozen screen review and inspection.
;;
;; Keep requiring `emacsvox-eat'; the internal features are load-order details.

;;; Code:

(require 'emacsvox-eat-core)
(require 'emacsvox-eat-input)
(require 'emacsvox-eat-review)

(with-eval-after-load 'eat
  (emacsvox-eat--install-advice))

(add-hook 'eat-update-hook #'emacsvox-eat-update-hook)
(add-hook 'eat-exec-hook #'emacsvox-eat--process-started)
(add-hook 'eat-exit-hook #'emacsvox-eat--process-exited)
(add-hook 'eat-eshell-update-hook #'emacsvox-eat-update-hook)
(add-hook 'eat-eshell-exec-hook #'emacsvox-eat--eshell-process-started)
(add-hook 'eat-eshell-exit-hook #'emacsvox-eat--eshell-process-exited)
(add-hook 'eshell-after-prompt-hook #'emacsvox-eat--eshell-prompt-ready)

(provide 'emacsvox-eat)

;;; emacsvox-eat.el ends here
