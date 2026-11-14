;;; graphical-count.el --- Disposable audit check -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Commentary:
;; One-off reproduction; see the investigation report.
;;; Code:
(load (expand-file-name "bootstrap.el" (file-name-directory load-file-name)) nil t)
(require 'markdown-mode)
(require 'emacsvox-markdown)
(condition-case failure
    (progn
      (unless (display-graphic-p) (error "Graphical frame required"))
      (with-temp-buffer
        (switch-to-buffer (current-buffer))
        (delay-mode-hooks (markdown-mode))
        (insert "| Name | Status | Count | Notes |\n|---|---|---|---|\n")
        (dotimes (i 2000) (insert (format "| row-%d | ready | %d | Plain cell content |\n" i i)))
        (font-lock-ensure)
        (goto-char (point-min)) (forward-line 1002)
        (emacsvox-table-reader--enter (emacsvox-markdown--table-snapshot) t)
        (let ((counts (make-hash-table :test #'eq)) (fixture-mode major-mode) advices)
          (unwind-protect
              (progn
                (dolist (name '(emacsvox-table-reader--source-cell
                                emacsvox-markdown--table-region emacsvox-markdown--table-line-p
                                emacsvox-table-reader--pipe-spans emacsvox-markdown--table-plain-text))
                  (let ((counter (lambda (&rest _) (puthash name (1+ (gethash name counts 0)) counts))))
                    (advice-add name :before counter)
                    (push (cons name counter) advices)))
                (cl-letf (((symbol-function 'emacsvox-table-reader--submit) #'ignore))
                  (execute-kbd-macro (kbd "<down>")))
                (with-temp-file (expand-file-name "graphical-counts.eld" audit-out)
                  (prin1 (list :mode fixture-mode :rows 2000 :counts
                               (let (pairs) (maphash (lambda (k v) (push (cons k v) pairs)) counts) pairs))
                         (current-buffer))))
            (dolist (entry advices) (advice-remove (car entry) (cdr entry))))))
      (kill-emacs 0))
  (error
   (with-temp-file (expand-file-name "graphical-count-error.txt" audit-out)
     (insert (prin1-to-string failure)))
   (kill-emacs 1)))

;;; graphical-count.el ends here
