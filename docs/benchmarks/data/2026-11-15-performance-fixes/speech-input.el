;;; speech-input.el --- Performance fix verification -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Commentary:
;; Disposable reproduction; see the performance fixes report.
;;; Code:
(load (expand-file-name "../2026-11-15-performance-audit/bootstrap.el" (file-name-directory load-file-name)) nil t)
(require 'tts-speak)
(dolist (lines '(100 500 1500 4000))
 (let* ((process (make-pipe-process :name "audit-input" :noquery t))
        (output (apply #'concat (make-list lines "__EMACSVOX_TRACKED__ 123456 completed\n")))
        (count 0) (handler (lambda (&rest _) (cl-incf count))))
  (unwind-protect
   (progn
    (audit-measure 'input-first-return (list :lines lines :bytes (string-bytes output))
     (lambda ()
      (setq count 0)
      (tts--consume-process-lines process output 'audit-input 'audit-busy handler (* 4 1024 1024))
      (tts--release-process-input process)) 20)
    (audit-measure 'input-full-drain (list :lines lines :bytes (string-bytes output))
     (lambda ()
      (setq count 0)
      (tts--consume-process-lines process output 'audit-input 'audit-busy handler (* 4 1024 1024))
      (while (process-get process 'audit-input) (tts--resume-process-input process 'audit-input))
      (unless (= count lines) (error "Lost input lines"))) 20)
    (when (> lines 256)
      (audit-measure 'input-scheduled-drain (list :lines lines :bytes (string-bytes output))
       (lambda ()
        (setq count 0)
        (let ((deadline (+ (float-time) 5)) heartbeat)
         (let ((timer (run-at-time 0 nil (lambda () (setq heartbeat count)))))
          (unwind-protect
           (progn
            (tts--consume-process-lines process output 'audit-input 'audit-busy handler (* 4 1024 1024))
            (while (and (process-get process 'audit-input) (< (float-time) deadline))
             (accept-process-output nil 0.001))
            (unless (and (= count lines) heartbeat (< heartbeat lines)
                         (not (process-get process 'audit-input)))
             (error "Scheduled drain did not yield or lost input")))
           (cancel-timer timer))))) 20)))
   (delete-process process))))
(audit-save "speech-input.eld" (list :loaded (symbol-file 'tts--consume-process-lines)))

;;; speech-input.el ends here
