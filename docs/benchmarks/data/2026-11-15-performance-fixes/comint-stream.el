;;; comint-stream.el --- Performance fix verification -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Commentary:
;; Disposable reproduction; see the performance fixes report.
;;; Code:
(load (expand-file-name "../2026-11-15-performance-audit/bootstrap.el" (file-name-directory load-file-name)) nil t)
(require 'emacsvox-comint)
(dolist (chunks '(16 64 256))
 (let ((piece (make-string 4096 ?a)))
  (audit-measure 'comint-incremental-stream (list :chunks chunks :chunk-characters 4096)
   (lambda ()
    (with-temp-buffer
     (let ((comint-prompt-regexp "^SHELL> "))
      (dotimes (_ chunks) (emacsvox-comint--partition-output piece nil))
      (unless (= (length (emacsvox-comint--pending-output-text)) (* chunks 4096))
       (error "Lost pending output"))))) 10)))
(audit-save "comint-stream.eld" (list :loaded (symbol-file 'emacsvox-comint--partition-output)))

;;; comint-stream.el ends here
