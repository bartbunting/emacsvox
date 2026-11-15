;;; agent-suspended.el --- Performance fix verification -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Commentary:
;; Disposable reproduction; see the performance fixes report.
;;; Code:
(load (expand-file-name "../2026-11-15-performance-audit/bootstrap.el" (file-name-directory load-file-name)) nil t)
(require 'agent-shell)
(require 'emacsvox-agent-shell)
(dolist (rows '(10 100 500))
  (with-temp-buffer
    (insert "| Name | Status | Count | Notes |\n|---|---|---|---|\n")
    (dotimes (i rows) (insert (format "| row-%d | ready | %d | Plain cell content |\n" i i)))
    (agent-shell-markdown-replace-markup :complete t)
    (setq major-mode 'agent-shell-viewport-view-mode)
    (goto-char (point-min))
    (let* ((region (emacsvox-agent-shell--markdown-table-region-at-point))
           (starts (emacsvox-agent-shell--markdown-table-cell-starts region)))
      (goto-char (nth (/ (length starts) 2) starts))
      (unless (emacsvox-agent-shell--table-snapshot) (error "Invalid fixture"))
      (let ((emacsvox-table-reader--suspended t))
        (audit-measure 'agent-suspended-table-post-command
                       (list :rows rows :columns 4 :rendered-characters (buffer-size))
                       #'emacsvox-agent-shell--table-navigation-post-command 20)))))
(audit-save "agent-suspended.eld"
            (list :agent-version agent-shell--version
                  :agent-source (symbol-file 'agent-shell-ui-update-fragment)
                  :adapter (symbol-file 'emacsvox-agent-shell--table-navigation-post-command)))

;;; agent-suspended.el ends here
