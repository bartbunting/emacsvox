;;; remove-cl-declare.el --- Modernize obsolete cl-declare forms -*- lexical-binding: t; -*-

(require 'cl-lib)

(defun remove-cl-declare--special-variables (form)
  "Return the special variables declared by cl-declare FORM.
Signal an error when FORM is not a single `(special ...)' declaration."
  (let ((spec (and (= (length form) 2) (cadr form))))
    (unless (and (consp spec)
                 (eq (car spec) 'special)
                 (cdr spec)
                 (cl-every #'symbolp (cdr spec)))
      (error "Unsupported cl-declare form: %S" form))
    (cdr spec)))

(defun remove-cl-declare--delete-form (start end)
  "Delete the declaration between START and END.
Delete its complete source line when it contains no other code."
  (let* ((line-start (save-excursion
                       (goto-char start)
                       (line-beginning-position)))
         (line-end (save-excursion
                     (goto-char end)
                     (line-end-position)))
         (prefix (buffer-substring-no-properties line-start start))
         (suffix (buffer-substring-no-properties end line-end)))
    (if (and (string-match-p "\\`[ \t\C-x]*\\'" prefix)
             (string-match-p "\\`[ \t]*\\'" suffix))
        (delete-region
         line-start
         (min (point-max) (1+ line-end)))
      (delete-region start end))))

(defun remove-cl-declare--insert-defvars (variables)
  "Insert top-level forward declarations for VARIABLES."
  (goto-char (point-min))
  (unless (re-search-forward "^;;; Code:[ \t]*$" nil t)
    (error "No `;;; Code:' marker in %s" (or buffer-file-name (buffer-name))))
  (forward-line 1)
  (insert "\n;;; Forward variable declarations:\n\n")
  (dolist (variable
           (sort (delete-dups variables)
                 (lambda (left right)
                   (string< (symbol-name left) (symbol-name right)))))
    (insert (format "(defvar %S)\n" variable)))
  nil)

(defun remove-cl-declare-in-buffer ()
  "Replace obsolete cl-declare special forms in the current buffer.
Hoist their variables into top-level `defvar' forward declarations."
  (goto-char (point-min))
  (let ((count 0)
        variables)
    (while (search-forward "(cl-declare" nil t)
      (let ((start (match-beginning 0)))
        (unless (save-excursion
                  (nth 8 (syntax-ppss start)))
          (goto-char start)
          (let* ((form (read (current-buffer)))
                 (end (point)))
            (setq variables
                  (nconc
                   (remove-cl-declare--special-variables form)
                   variables))
            (remove-cl-declare--delete-form start end)
            (goto-char start)
            (cl-incf count)))))
    (when variables
      (remove-cl-declare--insert-defvars variables))
    count))

(defun remove-cl-declare-in-file (file)
  "Modernize obsolete cl-declare forms in FILE."
  (with-current-buffer (find-file-noselect file)
    (let ((count (remove-cl-declare-in-buffer)))
      (when (> count 0)
        (save-buffer)
        (message "Modernized %d cl-declare forms in %s" count file))
      count)))

(provide 'remove-cl-declare)
