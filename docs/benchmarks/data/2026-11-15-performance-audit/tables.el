;;; tables.el --- Disposable performance investigation -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Commentary:
;; One-off audit reproduction. Use the report's environment and commands.
;; This file is not loaded by Emacsvox.
;;; Code:
(load (expand-file-name "bootstrap.el" (file-name-directory load-file-name)) nil t)
(require 'org)
(require 'markdown-mode)
(require 'emacsvox-org)
(require 'emacsvox-markdown)
(audit-measure 'timer-baseline nil #'ignore 25)
(dolist (mode '(org-mode markdown-mode))
  (dolist (rows '(10 100 500 2000))
    (with-temp-buffer
      (delay-mode-hooks (funcall mode))
      (insert "| Name | Status | Count | Notes |\n|---|---|---|---|\n")
      (dotimes (i rows) (insert (format "| row-%d | ready | %d | Plain cell content |\n" i i)))
      (goto-char (point-min)) (forward-line (+ 2 (/ rows 2)))
      (let* ((snapshot (if (eq mode 'org-mode) #'emacsvox-org--table-snapshot
                         #'emacsvox-markdown--table-snapshot))
             (position (point))
             (dims (list :mode mode :rows rows :columns 4 :characters (buffer-size))))
        (audit-measure 'source-table-snapshot dims snapshot 20)
        (emacsvox-table-reader--enter (funcall snapshot) t)
        (cl-letf (((symbol-function 'emacsvox-table-reader--submit) #'ignore))
          (audit-measure 'source-table-next-row-and-post-command dims
                         (lambda ()
                           (goto-char position)
                           (emacsvox-table-reader-next-row 1)
                           (emacsvox-table-reader--post-command)) 10))
        (let* ((calls 0) (counter (lambda (&rest _) (cl-incf calls))))
          (advice-add 'emacsvox-table-reader--source-cell :before counter)
          (unwind-protect
              (cl-letf (((symbol-function 'emacsvox-table-reader--submit) #'ignore))
                (goto-char position)
                (emacsvox-table-reader-next-row 1)
                (emacsvox-table-reader--post-command))
            (advice-remove 'emacsvox-table-reader--source-cell counter))
          (princ (format "Snapshot-count %s %d rows: %d\n" mode rows calls)))))))
(audit-save "tables.eld" (list :org (symbol-file 'org-mode) :markdown (symbol-file 'markdown-mode)
                              :reader (symbol-file 'emacsvox-table-reader--source-cell)))

;;; tables.el ends here
