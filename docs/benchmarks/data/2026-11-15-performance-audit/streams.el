;;; streams.el --- Disposable performance investigation -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Commentary:
;; One-off audit reproduction. Use the report's environment and commands.
;; This file is not loaded by Emacsvox.
;;; Code:
(load (expand-file-name "bootstrap.el" (file-name-directory load-file-name)) nil t)
(require 'emacsvox-comint)
(dolist (bytes '(256 1024 4096 8192 16384))
  (dolist (newline '(nil t))
    (with-temp-buffer
      (setq major-mode 'comint-mode comint-prompt-regexp "^SHELL> ")
      (let ((piece (concat (make-string bytes ?a) (when newline "\n"))))
        (audit-measure 'comint-single-line
                       (list :line-bytes bytes :newline newline)
                       (lambda ()
                         (setq emacsvox-comint--pending-output ""
                               emacsvox-comint--last-prompt nil
                               emacsvox-comint--prompt-awaiting-padding nil)
                         (emacsvox-comint--partition-output piece nil))
                       (if (> bytes 8192) 5 20))))))
(let ((chunk (make-string 4096 ?a)))
  (dolist (chunks '(16 64 256))
    (with-temp-buffer
      (setq major-mode 'comint-mode comint-prompt-regexp "^SHELL> ")
      (audit-measure 'comint-unterminated-chunks (list :chunks chunks :chunk-bytes 4096)
                     (lambda ()
                       (setq emacsvox-comint--pending-output ""
                             emacsvox-comint--last-prompt nil
                             emacsvox-comint--prompt-awaiting-padding nil)
                       (dotimes (_ chunks) (emacsvox-comint--partition-output chunk nil))) 5)
      (princ (format "Retained bytes: %d\n" (length emacsvox-comint--pending-output))))))
(let ((process (make-pipe-process :name "audit-lines" :noquery t)))
  (unwind-protect
      (dolist (lines '(100 500 1500 4000))
        (let ((output (apply #'concat (make-list lines "__EMACSVOX_TRACKED__ 123456 completed\n"))))
          (audit-measure 'speech-line-drain
                         (list :lines lines :bytes (length output))
                         (lambda ()
                           (tts--consume-process-lines process output 'audit-fragment 'audit-busy #'ignore
                                                       (* 4 1024 1024))) 10)))
    (delete-process process)))
(let ((file (make-temp-file "emacsvox-audit-log-")))
  (unwind-protect
      (dolist (logging '(nil t))
        (let ((emacsvox-aural-diagnostic-log-file (and logging file)))
          (audit-measure 'diagnostic-event-batch (list :logging logging :events 12)
                         (lambda ()
                           (dotimes (_ 12)
                             (emacsvox-aural-diagnostic-log-event
                              'audit :command 'next-line :mode 'text-mode :submission-id 1
                              :text "A short line with ordinary text."))) 25)))
    (delete-file file)))
(audit-save "streams.eld" (list :comint (symbol-file 'emacsvox-comint--partition-output)
                               :filter (symbol-file 'tts--consume-process-lines)))

;;; streams.el ends here
