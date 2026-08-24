;;; emacsvox-eat.el --- Speech-enable EAT  -*- lexical-binding: t; -*-
;;; $Author: tv.raman.tv $
;;; Keywords: Emacsvox, Audio Desktop, eat

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
