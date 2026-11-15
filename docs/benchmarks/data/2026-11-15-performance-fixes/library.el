;;; library.el --- Performance fix verification -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Commentary:
;; Disposable reproduction; see the performance fixes report.
;;; Code:
(load (expand-file-name "../2026-11-15-performance-audit/bootstrap.el" (file-name-directory load-file-name)) nil t)
(require 'emacsvox-sound-library)
(when-let* ((file (getenv "EMACSVOX_AUDIT_ENV_FILE")))
  (let ((env (with-temp-buffer (insert-file-contents file)
               (json-parse-buffer :object-type 'alist :array-type 'list))))
    (setq exec-path (alist-get 'exec-path env))))
(let ((emacsvox-sound-library-directory (expand-file-name "recordings-40" audit-out))
      (emacsvox-sound-library--cache (make-hash-table :test #'equal)))
  (unless (= (length (emacsvox-sound-library--scan)) 40)
    (error "Generate the 40 WAV fixtures in EMACSVOX_AUDIT_OUTPUT first"))
  (audit-measure 'library-cold (list :files 40 :exec-path-count (length exec-path))
    (lambda () (clrhash emacsvox-sound-library--cache) (emacsvox-sound-library--scan)) 10)
  (audit-measure 'library-warm (list :files 40) #'emacsvox-sound-library--scan 20))
(audit-save "library.eld" (list :loaded (symbol-file 'emacsvox-sound-library--scan)))

;;; library.el ends here
