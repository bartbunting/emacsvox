;;; indent.el --- Indent Emacsvox Source Code.  -*- lexical-binding: t; -*-

(require 'cl-lib)
(load (expand-file-name "../lisp/emacsvox-paths.el"
                        (file-name-directory load-file-name)) nil t t)

(defun batch-indent-files ()
  "Batch indent  elisp files in directory."
  (let ((file-list (emacsvox-paths--files default-directory ".el")))
    (setq-default indent-tabs-mode nil)
    (cl-loop
     for f in file-list do
     (let ((indent-tabs-mode nil))
       (find-file f)
       (emacs-lisp-mode)
       (goto-char (point-min))
       (indent-region (point-min) (point-max))
       (shell-command-on-region (point-min) (point-max)
                                "cat -s" (current-buffer) 'replace)
       (untabify (point-min) (point-max))
       (save-buffer)))))

(batch-indent-files)
