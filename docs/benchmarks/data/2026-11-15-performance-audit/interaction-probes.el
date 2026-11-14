;;; interaction-probes.el --- Disposable audit check -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Commentary:
;; One-off reproduction; see the investigation report.
;;; Code:
(load (expand-file-name "bootstrap.el" (file-name-directory load-file-name)) nil t)
(require 'emacsvox-comint)
(require 'emacsvox-sound-library)
(with-temp-buffer
  (comint-mode)
  (let ((process (make-pipe-process :name "audit-comint-real-filter" :buffer (current-buffer) :noquery t))
        (emacsvox-comint-autospeak nil)
        (piece (concat (make-string 16384 ?a) "\n")))
    (unwind-protect
        (audit-measure 'comint-real-filter-autospeak-off (list :line-bytes 16384 :newline t)
                       (lambda ()
                         (erase-buffer)
                         (set-marker (process-mark process) (point-min))
                         (setq emacsvox-comint--pending-output "" emacsvox-comint--last-prompt nil
                               emacsvox-comint--prompt-awaiting-padding nil)
                         (comint-output-filter process piece)
                         (unless (string= (buffer-substring-no-properties (point-min) (point-max)) piece)
                           (error "Output filter lost text"))) 5)
      (delete-process process))))
(let* ((directory (make-temp-file "audit-library-lifecycle-" t))
       (emacsvox-sound-library-directory directory)
       (emacsvox-sound-library--cache (make-hash-table :test #'equal)) counts)
  (unwind-protect
      (cl-letf (((symbol-function 'emacsvox-sound-library--duration) #'ignore))
        (dotimes (i 5)
          (write-region (format "unique audit fixture %d" i) nil
                        (expand-file-name (format "%d.wav" i) directory) nil 'silent))
        (push (list :recordings (length (emacsvox-sound-library--scan))
                    :cache (hash-table-count emacsvox-sound-library--cache)) counts)
        (dolist (file (directory-files directory t "\\.wav\\'")) (delete-file file))
        (push (list :recordings (length (emacsvox-sound-library--scan))
                    :cache (hash-table-count emacsvox-sound-library--cache)) counts)
        (push (list :case 'sound-library-deleted-cache :observations (nreverse counts)) audit-results))
    (delete-directory directory t)))
(audit-save "interaction-probes.eld")

;;; interaction-probes.el ends here
