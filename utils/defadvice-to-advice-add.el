;;; defadvice-to-advice-add.el --- Conservatively convert advice -*- lexical-binding: t; -*-

;; Copyright (C) 2024--2026 Emacsvox Contributors

;;; Commentary:

;; Convert only legacy advice whose semantics map directly to native
;; `advice-add'.  Anything involving positional arguments, argument mutation,
;; explicit original calls, return-value access, around advice, or generated
;; targets is left unchanged and reported for manual review.
;;
;; Usage:
;;   emacs --batch -l utils/defadvice-to-advice-add.el \
;;     --eval '(ems-convert-file "lisp/example.el")'

;;; Code:

(require 'cl-lib)
(require 'pp)
(require 'subr-x)

(defvar ems-conversion-stats nil
  "Statistics for the current conversion run.")

(defvar ems-manual-review-items nil
  "Advice forms refused by the current conversion run.")

(defconst ems--unsafe-advice-symbols
  '(ad-get-arg ad-set-arg ad-do-it ad-return-value)
  "Legacy constructs that require manual semantic conversion.")

(defun ems--symbol-in-tree-p (symbol tree)
  "Return non-nil when SYMBOL occurs in parsed Lisp TREE."
  (cond
   ((eq symbol tree) t)
   ((consp tree)
    (or (ems--symbol-in-tree-p symbol (car tree))
        (ems--symbol-in-tree-p symbol (cdr tree))))
   ((vectorp tree)
    (cl-some (lambda (item) (ems--symbol-in-tree-p symbol item)) tree))
   (t nil)))

(defun ems--extract-docstring (body)
  "Return BODY as a pair of its optional docstring and remaining forms."
  (if (stringp (car-safe body))
      (cons (car body) (cdr body))
    (cons nil body)))

(defun ems--parse-defadvice (form)
  "Parse literal legacy advice FORM and return a property list."
  (unless (eq (car-safe form) 'defadvice)
    (error "Not a defadvice form: %S" form))
  (let* ((target (nth 1 form))
         (specification (nth 2 form))
         (class (car-safe specification))
         (name (cadr specification))
         (flags (cddr specification))
         (doc-and-body (ems--extract-docstring (nthcdr 3 form))))
    (list
     :function target
     :class class
     :name name
     :flags flags
     :docstring (car doc-and-body)
     :body (cdr doc-and-body))))

(defun ems--literal-advice-target-p (target)
  "Return non-nil when TARGET names one function literally."
  (and (symbolp target) target))

(defun ems--literal-advice-name-p (name)
  "Return non-nil when legacy advice NAME is a literal symbol."
  (and (symbolp name) name))

(defun ems--conversion-review-reasons (parsed)
  "Return reasons why PARSED advice cannot be converted automatically."
  (let ((target (plist-get parsed :function))
        (class (plist-get parsed :class))
        (name (plist-get parsed :name))
        (body (plist-get parsed :body))
        reasons)
    (unless (ems--literal-advice-target-p target)
      (push "generated or non-literal target" reasons))
    (unless (ems--literal-advice-name-p name)
      (push "generated or missing advice name" reasons))
    (unless (memq class '(before after))
      (push (format "advice class %S requires manual review" class) reasons))
    (dolist (symbol ems--unsafe-advice-symbols)
      (when (ems--symbol-in-tree-p symbol body)
        (push (format "uses %s" symbol) reasons)))
    (nreverse reasons)))

(defun ems--transform-interactive-checks (tree target)
  "Give argument-less `ems-interactive-p' calls in TREE an explicit TARGET."
  (cond
   ((atom tree) tree)
   ;; Do not rewrite documentation or quoted example data.
   ((eq (car tree) 'quote) tree)
   ((and (eq (car tree) 'ems-interactive-p) (null (cdr tree)))
    `(ems-interactive-p ',target))
   (t
    (cons
     (ems--transform-interactive-checks (car tree) target)
     (ems--transform-interactive-checks (cdr tree) target)))))

(defun ems--generate-advice-function-name (target name class)
  "Return a collision-resistant helper name for TARGET, NAME, and CLASS."
  (intern (format "ems--%s-%s-%s" target name class)))

(defun ems--generate-advice-function (parsed)
  "Generate a native advice helper from safe PARSED legacy advice."
  (let* ((target (plist-get parsed :function))
         (class (plist-get parsed :class))
         (name (plist-get parsed :name))
         (docstring (plist-get parsed :docstring))
         (body
          (mapcar
           (lambda (form)
             (ems--transform-interactive-checks form target))
           (plist-get parsed :body)))
         (helper (ems--generate-advice-function-name target name class)))
    `(defun ,helper (&rest _)
       ,@(when docstring (list docstring))
       ,@body)))

(defun ems--generate-advice-add (parsed)
  "Generate a named `advice-add' registration from PARSED legacy advice."
  (let* ((target (plist-get parsed :function))
         (class (plist-get parsed :class))
         (name (plist-get parsed :name))
         (helper (ems--generate-advice-function-name target name class))
         (where (intern (format ":%s" class))))
    `(advice-add ',target ,where #',helper '((name . ,name)))))

(defun ems--convert-defadvice-form (form)
  "Convert safe legacy advice FORM, or return nil and record review reasons."
  (condition-case error-data
      (let* ((parsed (ems--parse-defadvice form))
             (reasons (ems--conversion-review-reasons parsed)))
        (if reasons
            (progn
              (push
               (list
                :function (plist-get parsed :function)
                :class (plist-get parsed :class)
                :reasons reasons)
               ems-manual-review-items)
              nil)
          (list
           (ems--generate-advice-function parsed)
           (ems--generate-advice-add parsed))))
    (error
     (push
      (list :form form :reasons (list (error-message-string error-data)))
      ems-manual-review-items)
     nil)))

(defun ems--format-elisp-form (form)
  "Return pretty-printed Lisp FORM as a string."
  (with-temp-buffer
    (emacs-lisp-mode)
    (let ((print-level nil)
          (print-length nil))
      (pp form (current-buffer)))
    (buffer-string)))

(defun ems--find-top-level-defadvice (buffer)
  "Return positions and forms for literal top-level advice in BUFFER."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (let (results)
        (while (re-search-forward "^[ \t]*\\([(]defadvice\\_>\\)" nil t)
          (let ((start (match-beginning 1))
                (next (match-end 1)))
            (when (and (= 0 (car (syntax-ppss start)))
                       (not (nth 8 (syntax-ppss start))))
              (goto-char start)
              (let ((form (read (current-buffer)))
                    (end (point)))
                (push (list start end form) results)))
            (when (< (point) next) (goto-char next))))
        (nreverse results)))))

(defun ems--count-nested-defadvice (buffer)
  "Count nested or generated legacy advice templates in BUFFER."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (let ((count 0))
        (while (re-search-forward "(defadvice\\_>" nil t)
          (let* ((start (match-beginning 0))
                 (next (match-end 0))
                 (state (syntax-ppss start)))
            (when (and (> (car state) 0) (not (nth 8 state)))
              (cl-incf count))
            (goto-char next)))
        count))))

(defun ems-convert-buffer ()
  "Conservatively convert safe top-level legacy advice in this buffer."
  (interactive)
  (let* ((ems-conversion-stats
          '(:converted 0 :skipped 0 :nested 0))
         (ems-manual-review-items nil)
         (candidates (ems--find-top-level-defadvice (current-buffer)))
         (nested (ems--count-nested-defadvice (current-buffer))))
    (plist-put ems-conversion-stats :nested nested)
    (when (> nested 0)
      (push
       (list
        :count nested
        :reasons (list "nested or generated defadvice templates"))
       ems-manual-review-items))
    (save-excursion
      (dolist (item (reverse candidates))
        (pcase-let ((`(,start ,end ,form) item))
          (let ((converted (ems--convert-defadvice-form form)))
            (if (not converted)
                (cl-incf (plist-get ems-conversion-stats :skipped))
              (delete-region start end)
              (goto-char start)
              (dolist (new-form converted)
                (insert (ems--format-elisp-form new-form) "\n"))
              (cl-incf (plist-get ems-conversion-stats :converted)))))))
    (message
     "Conversion: %d safe, %d refused, %d nested templates"
     (plist-get ems-conversion-stats :converted)
     (plist-get ems-conversion-stats :skipped)
     nested)
    (when ems-manual-review-items
      (message "Manual review required for %d items"
               (length ems-manual-review-items)))
    (setq ems-conversion-stats
          (plist-put
           ems-conversion-stats :manual-review
           (nreverse ems-manual-review-items)))
    ems-conversion-stats))

(defun ems-convert-file (filename)
  "Conservatively convert safe advice in FILENAME and save a backup."
  (interactive "fFile to convert: ")
  (let ((backup-file (concat filename ".defadvice-backup")))
    (copy-file filename backup-file t)
    (with-current-buffer (find-file-noselect filename)
      (let ((stats (ems-convert-buffer)))
        (save-buffer)
        (message "Converted %s; backup is %s" filename backup-file)
        stats))))

(provide 'defadvice-to-advice-add)
;;; defadvice-to-advice-add.el ends here
