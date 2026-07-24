;;; advice-audit.el --- Inventory Emacsvox advice migration -*- lexical-binding: t; -*-

;;; Commentary:

;; Parse Lisp source rather than searching raw text, so comments and strings do
;; not inflate migration counts.  Nested and backquoted advice templates are
;; included because they still generate executable advice.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defconst ems-advice-audit-legacy-symbols
  '(ad-get-arg ad-set-arg ad-do-it ad-return-value
    ad-find-some-advice ems-interactive-p)
  "Legacy or compatibility symbols tracked by the advice audit.")

(defun ems-advice-audit--walk (object function)
  "Call FUNCTION for every node reachable in Lisp OBJECT."
  (funcall function object)
  (cond
   ((consp object)
    (ems-advice-audit--walk (car object) function)
    (ems-advice-audit--walk (cdr object) function))
   ((vectorp object)
    (mapc
     (lambda (item) (ems-advice-audit--walk item function))
     object))))

(defun ems-advice-audit--count-symbol (symbol object)
  "Count occurrences of SYMBOL in parsed Lisp OBJECT."
  (let ((count 0))
    (ems-advice-audit--walk
     object (lambda (node) (when (eq node symbol) (cl-incf count))))
    count))

(defun ems-advice-audit--literal-symbol (object)
  "Return the literal symbol represented by OBJECT, or nil."
  (cond
   ((symbolp object) object)
   ((and (eq (car-safe object) 'quote)
         (symbolp (cadr object)))
    (cadr object))))

(defun ems-advice-audit--defadvice-risk (form)
  "Classify legacy advice FORM as simple, review, or complex."
  (let* ((target (ems-advice-audit--literal-symbol (nth 1 form)))
         (specification (nth 2 form))
         (class (car-safe specification))
         (body (nthcdr 3 form))
         (get-arg (ems-advice-audit--count-symbol 'ad-get-arg body))
         (set-arg (ems-advice-audit--count-symbol 'ad-set-arg body))
         (do-it (ems-advice-audit--count-symbol 'ad-do-it body))
         (return-value
          (ems-advice-audit--count-symbol 'ad-return-value body)))
    (cond
     ((or (> set-arg 0) (> return-value 0) (> do-it 1)) 'complex)
     ((or (null target)
          (not (memq class '(before after around)))
          (eq class 'around)
          (> get-arg 0)
          (> do-it 0))
      'review)
     (t 'simple))))

(defun ems-advice-audit--analyze-defadvice (form)
  "Return a migration description for legacy advice FORM."
  (let ((body (nthcdr 3 form)))
    (list
     :target (or (ems-advice-audit--literal-symbol (nth 1 form)) 'dynamic)
     :class (or (car-safe (nth 2 form)) 'unknown)
     :risk (ems-advice-audit--defadvice-risk form)
     :ad-get-arg (ems-advice-audit--count-symbol 'ad-get-arg body)
     :ad-set-arg (ems-advice-audit--count-symbol 'ad-set-arg body)
     :ad-do-it (ems-advice-audit--count-symbol 'ad-do-it body)
     :ad-return-value
     (ems-advice-audit--count-symbol 'ad-return-value body))))

(defun ems-advice-audit--empty-symbol-counts ()
  "Return a fresh zeroed alist for tracked compatibility symbols."
  (mapcar (lambda (symbol) (cons symbol 0))
          ems-advice-audit-legacy-symbols))

(defun ems-advice-audit-forms (forms &optional source)
  "Audit parsed Lisp FORMS originating from SOURCE."
  (let ((symbol-counts (ems-advice-audit--empty-symbol-counts))
        defadvice-forms
        advice-add-forms)
    (dolist (form forms)
      (ems-advice-audit--walk
       form
       (lambda (node)
         (when (symbolp node)
           (let ((entry (assq node symbol-counts)))
             (when entry (cl-incf (cdr entry)))))
         (when (consp node)
           (pcase (car node)
             ('defadvice
              (push (ems-advice-audit--analyze-defadvice node)
                    defadvice-forms))
             ('advice-add (push node advice-add-forms)))))))
    (list
     :source source
     :defadvice (nreverse defadvice-forms)
     :advice-add-count (length advice-add-forms)
     :symbol-counts symbol-counts)))

(defun ems-advice-audit-buffer (&optional source)
  "Read and audit the current buffer, labelled with SOURCE."
  (save-excursion
    (goto-char (point-min))
    (let (forms)
      (condition-case error-data
          (while t (push (read (current-buffer)) forms))
        (end-of-file)
        (error
         (error "Could not read %s: %s"
                (or source "buffer")
                (error-message-string error-data))))
      (ems-advice-audit-forms (nreverse forms) source))))

(defun ems-advice-audit-file (filename)
  "Read and audit Lisp source FILENAME."
  (with-temp-buffer
    (insert-file-contents filename)
    (ems-advice-audit-buffer filename)))

(defun ems-advice-audit-directory (directory)
  "Return deterministic advice audit data for Lisp files in DIRECTORY."
  (let* ((root (file-name-as-directory (expand-file-name directory)))
         (files
          (sort
           (directory-files-recursively root (rx ".el" string-end))
           #'string<))
         (symbol-counts (ems-advice-audit--empty-symbol-counts))
         (risk-counts '((simple . 0) (review . 0) (complex . 0)))
         (defadvice-count 0)
         (defadvice-file-count 0)
         (advice-add-count 0)
         (advice-add-file-count 0)
         (compatibility-file-count 0)
         (interactive-file-count 0)
         file-results)
    (dolist (filename files)
      (let* ((result (ems-advice-audit-file filename))
             (legacy (plist-get result :defadvice)))
        (cl-incf defadvice-count (length legacy))
        (when legacy (cl-incf defadvice-file-count))
        (cl-incf advice-add-count (plist-get result :advice-add-count))
        (when (> (plist-get result :advice-add-count) 0)
          (cl-incf advice-add-file-count))
        (when
            (cl-some
             (lambda (entry)
               (and (not (eq (car entry) 'ems-interactive-p))
                    (> (cdr entry) 0)))
             (plist-get result :symbol-counts))
          (cl-incf compatibility-file-count))
        (when
            (> (alist-get 'ems-interactive-p
                          (plist-get result :symbol-counts))
               0)
          (cl-incf interactive-file-count))
        (dolist (entry (plist-get result :symbol-counts))
          (cl-incf (alist-get (car entry) symbol-counts) (cdr entry)))
        (dolist (item legacy)
          (cl-incf (alist-get (plist-get item :risk) risk-counts)))
        (when
            (or legacy
                (> (plist-get result :advice-add-count) 0)
                (cl-some (lambda (entry) (> (cdr entry) 0))
                         (plist-get result :symbol-counts)))
          (setq result
                (plist-put
                 result :source (file-relative-name filename root)))
          (push result file-results))))
    (list
     :directory root
     :file-count (length files)
     :defadvice-count defadvice-count
     :defadvice-file-count defadvice-file-count
     :defadvice-risks risk-counts
     :advice-add-count advice-add-count
     :advice-add-file-count advice-add-file-count
     :compatibility-file-count compatibility-file-count
     :interactive-file-count interactive-file-count
     :symbol-counts symbol-counts
     :files (nreverse file-results))))

(defun ems-advice-audit-format (audit)
  "Return a concise human-readable report for AUDIT."
  (let ((risks (plist-get audit :defadvice-risks))
        (symbols (plist-get audit :symbol-counts)))
    (concat
     (format "Advice migration audit: %d Lisp files\n"
             (plist-get audit :file-count))
     (format "defadvice: %d in %d files (simple %d, review %d, complex %d)\n"
             (plist-get audit :defadvice-count)
             (plist-get audit :defadvice-file-count)
             (alist-get 'simple risks)
             (alist-get 'review risks)
             (alist-get 'complex risks))
     (format "advice-add: %d in %d files\n"
             (plist-get audit :advice-add-count)
             (plist-get audit :advice-add-file-count))
     (format "bridge compatibility symbols: %d files\n"
             (plist-get audit :compatibility-file-count))
     (format "ems-interactive-p: %d files\n"
             (plist-get audit :interactive-file-count))
     (mapconcat
      (lambda (entry) (format "%s: %d" (car entry) (cdr entry)))
      symbols "\n")
     "\n")))

(defun ems-advice-audit-batch (directory)
  "Audit DIRECTORY and print the migration inventory for batch use."
  (princ (ems-advice-audit-format
          (ems-advice-audit-directory directory))))

(provide 'advice-audit)
;;; advice-audit.el ends here
