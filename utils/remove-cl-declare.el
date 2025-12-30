;;; remove-cl-declare.el --- Remove obsolete cl-declare forms -*- lexical-binding: t; -*-

(require 'cl-lib)

(defun remove-cl-declare-in-buffer ()
  "Remove all cl-declare (special ...) forms from current buffer."
  (goto-char (point-min))
  (let ((count 0))
    (while (search-forward "(cl-declare" nil t)
      (goto-char (match-beginning 0))
      (let ((start (point)))
        (condition-case nil
            (progn
              (forward-sexp)
              (delete-region start (point))
              (when (looking-at "[ \t]*\n")
                (delete-region (point) (match-end 0)))
              (cl-incf count))
          (error nil))))
    count))

(defun remove-cl-declare-in-file (file)
  "Remove cl-declare from FILE."
  (with-current-buffer (find-file-noselect file)
    (let ((count (remove-cl-declare-in-buffer)))
      (when (> count 0)
        (save-buffer)
        (message "Removed %d cl-declare from %s" count file))
      count)))

(provide 'remove-cl-declare)
