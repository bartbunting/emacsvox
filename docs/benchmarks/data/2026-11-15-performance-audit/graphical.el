;;; graphical.el --- Disposable performance investigation -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Commentary:
;; One-off audit reproduction. Use the report's environment and commands.
;; This file is not loaded by Emacsvox.
;;; Code:
(load (expand-file-name "bootstrap.el" (file-name-directory load-file-name)) nil t)
(when (getenv "EMACSVOX_AUDIT_LIVE_CONFIG")
  (let ((environment (with-temp-buffer
                       (insert-file-contents (expand-file-name "live-environment.json" audit-out))
                       (json-parse-buffer :object-type 'alist :array-type 'list))))
    (setq exec-path (alist-get 'exec-path environment))
    (load (alist-get 'markdown-path environment) nil t t)))
(require 'org)
(require 'markdown-mode)
(require 'emacsvox-org)
(require 'emacsvox-markdown)
(condition-case failure
    (progn
      (unless (display-graphic-p) (error "A graphical frame is required"))
      (save-window-excursion
        (dolist (mode '(org-mode markdown-mode))
          (dolist (rows '(500 2000))
            (with-temp-buffer
              (switch-to-buffer (current-buffer))
              (delay-mode-hooks (funcall mode))
              (insert "| Name | Status | Count | Notes |\n|---|---|---|---|\n")
              (dotimes (i rows) (insert (format "| row-%d | ready | %d | Plain cell content |\n" i i)))
              (font-lock-ensure)
              (goto-char (point-min)) (forward-line (+ 2 (/ rows 2)))
              (let ((position (point))
                    (snapshot (if (eq mode 'org-mode) #'emacsvox-org--table-snapshot
                                #'emacsvox-markdown--table-snapshot)))
                (emacsvox-table-reader--enter (funcall snapshot) t)
                (cl-letf (((symbol-function 'emacsvox-table-reader--submit) #'ignore))
                  (audit-measure 'graphical-down-arrow
                                 (list :mode mode :rows rows :characters (buffer-size)
                                       :binding (key-binding (kbd "<down>")))
                                 (lambda ()
                                   (goto-char position)
                                   (execute-kbd-macro (kbd "<down>"))
                                   (unless (> (point) position) (error "Arrow did not move"))) 10)))))))
      (audit-save (if (getenv "EMACSVOX_AUDIT_LIVE_CONFIG") "graphical-live.eld" "graphical.eld") (list :display (display-graphic-p)
                                      :markdown (symbol-file 'markdown-mode)))
      (kill-emacs 0))
  (error
   (with-temp-file (expand-file-name "graphical-error.txt" audit-out)
     (insert (prin1-to-string failure)))
   (kill-emacs 1)))

;;; graphical.el ends here
