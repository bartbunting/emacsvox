;;; library.el --- Disposable performance investigation -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Commentary:
;; One-off audit reproduction. Use the report's environment and commands.
;; This file is not loaded by Emacsvox.
;;; Code:
(load (expand-file-name "bootstrap.el" (file-name-directory load-file-name)) nil t)
(require 'emacsvox-sound-library)
(dolist (count '(1 10 40))
  (let* ((emacsvox-sound-library-directory (expand-file-name (format "recordings-%d" count) audit-out))
         (emacsvox-sound-library--cache (make-hash-table :test #'equal)))
    (audit-measure 'sound-library-cold (list :files count :ffprobe (executable-find "ffprobe"))
                   (lambda () (clrhash emacsvox-sound-library--cache) (emacsvox-sound-library--scan)) 5)
    (audit-measure 'sound-library-warm (list :files count) #'emacsvox-sound-library--scan 20)))
(audit-save "library.eld")

;;; library.el ends here
