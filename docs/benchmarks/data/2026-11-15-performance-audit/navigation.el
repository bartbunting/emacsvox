;;; navigation.el --- Disposable performance investigation -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Commentary:
;; One-off audit reproduction. Use the report's environment and commands.
;; This file is not loaded by Emacsvox.
;;; Code:
(load (expand-file-name "bootstrap.el" (file-name-directory load-file-name)) nil t)
(require 'agent-shell)
(require 'emacsvox-agent-shell)
(dolist (count '(10 100 500))
  (with-temp-buffer
    (setq major-mode 'agent-shell-mode)
    (dotimes (i count)
      (agent-shell-ui-update-fragment
       (agent-shell-ui-make-fragment-model
        :namespace-id "audit" :block-id (format "%d-agent_message_chunk" i)
        :body (apply #'concat (make-list 80 "A normal response line with plain text and a number 42.\n")))
       :navigation 'never :expanded t))
    (goto-char (+ 100 (/ (+ (point-min) (point-max)) 2)))
    (beginning-of-line)
    (unless (and (< (point) (line-end-position))
                 (eq (plist-get (emacsvox-agent-shell--block-location-at-point) :type) (quote agent-response)))
      (error "Invalid transcript fixture point"))
    (let ((dims (list :fragments count :characters (buffer-size))))
      (audit-measure 'agent-local-block-classification dims #'emacsvox-agent-shell--block-location-at-point 25)
      (audit-measure 'agent-previous-response-location dims
                     (lambda () (emacsvox-agent-shell--fragment-location-in-direction
                                 'agent-response 'backward (point))) 25)
      (audit-measure 'agent-source-line-copy dims
                     (lambda () (emacsvox-aural-source-substring
                                 (line-beginning-position) (line-end-position))) 25)
      (audit-measure 'agent-input-sync-hook dims #'emacsvox-agent-shell--input-sync 25))))
(dolist (rows '(10 100 500))
  (with-temp-buffer
    (insert "| Name | Status | Count | Notes |\n|---|---|---|---|\n")
    (dotimes (i rows) (insert (format "| row-%d | ready | %d | Plain cell content |\n" i i)))
    (let ((start (current-time)))
      (agent-shell-markdown-replace-markup :complete t)
      (message "Agent table setup render: %d rows %.3f ms" rows (* 1000 (float-time (time-since start)))))
    (setq major-mode 'agent-shell-viewport-view-mode)
    (goto-char (point-min))
    (let* ((region (emacsvox-agent-shell--markdown-table-region-at-point))
           (starts (emacsvox-agent-shell--markdown-table-cell-starts region))
           (dims (list :rows rows :columns 4 :rendered-characters (buffer-size))))
      (goto-char (nth (/ (length starts) 2) starts))
      (unless (emacsvox-agent-shell--table-snapshot) (error "Invalid rendered table fixture"))
      (audit-measure 'agent-rendered-table-snapshot dims #'emacsvox-agent-shell--table-snapshot 20)
      (let ((emacsvox-table-reader--suspended t))
        (audit-measure 'agent-suspended-table-post-command dims
                       #'emacsvox-agent-shell--table-navigation-post-command 20)))))
(audit-save "navigation.eld" (list :agent-version agent-shell--version
                                  :agent-source (symbol-file 'agent-shell-ui-update-fragment)
                                  :adapter (symbol-file 'emacsvox-agent-shell--block-location-at-point)))

;;; navigation.el ends here
