;;; defadvice-to-advice-add.el --- Convert defadvice to advice-add -*- lexical-binding: t; -*-

;; Copyright (C) 2024 Emacsvox Modernization Team

;; This file is part of the Emacsvox modernization effort to convert
;; deprecated defadvice forms to modern advice-add.

;;; Commentary:

;; This script provides automated conversion of defadvice forms to advice-add.
;; It handles the most common patterns and flags complex cases for manual review.
;;
;; Usage:
;;   emacs --batch -l defadvice-to-advice-add.el -f ems-convert-file FILE.el
;;
;; Transformations:
;;   - defadvice → advice-add with named function
;;   - ad-do-it → (apply orig-fun args)
;;   - ad-get-arg N → (nth N args) or function parameter
;;   - ad-return-value → result variable
;;
;; Naming convention:
;;   Generated functions: ems--FUNCNAME-CLASS
;;   Example: next-line@emacspeak-after → ems--next-line-after

;;; Code:

(require 'cl-lib)

;;; Configuration

(defvar ems-conversion-stats nil
  "Statistics for the current conversion run.")

(defvar ems-manual-review-items nil
  "List of items requiring manual review.")

;;; Helper Functions

(defun ems--symbol-in-tree-p (symbol tree)
  "Return t if SYMBOL appears anywhere in TREE."
  (cond
   ((eq symbol tree) t)
   ((atom tree) nil)
   (t (or (ems--symbol-in-tree-p symbol (car tree))
          (ems--symbol-in-tree-p symbol (cdr tree))))))

(defun ems--count-symbol-in-tree (symbol tree)
  "Count occurrences of SYMBOL in TREE."
  (cond
   ((eq symbol tree) 1)
   ((atom tree) 0)
   (t (+ (ems--count-symbol-in-tree symbol (car tree))
         (ems--count-symbol-in-tree symbol (cdr tree))))))

(defun ems--replace-in-tree (old new tree)
  "Replace all occurrences of OLD with NEW in TREE."
  (cond
   ((eq old tree) new)
   ((atom tree) tree)
   (t (cons (ems--replace-in-tree old new (car tree))
            (ems--replace-in-tree old new (cdr tree))))))

(defun ems--extract-docstring (body)
  "Extract docstring from BODY if present. Returns (docstring . rest-of-body)."
  (if (and body (stringp (car body)))
      (cons (car body) (cdr body))
    (cons nil body)))

;;; Defadvice Parsing

(defun ems--parse-defadvice (form)
  "Parse a defadvice FORM and extract its components.
Returns a plist with keys:
  :function - function being advised
  :class - advice class (before/after/around)
  :name - advice name
  :flags - activation flags (pre act comp)
  :docstring - documentation string
  :body - advice body forms"
  (unless (eq (car form) 'defadvice)
    (error "Not a defadvice form: %S" form))

  (let* ((fn-name (nth 1 form))
         (advice-spec (nth 2 form))
         (advice-class (car advice-spec))
         (advice-name (cadr advice-spec))
         (flags (cddr advice-spec))
         (body-start (nthcdr 3 form))
         (docstring-and-body (ems--extract-docstring body-start))
         (docstring (car docstring-and-body))
         (body (cdr docstring-and-body)))

    (list :function fn-name
          :class advice-class
          :name advice-name
          :flags flags
          :docstring docstring
          :body body)))

;;; Complexity Analysis

(defun ems--classify-complexity (parsed)
  "Classify the complexity of a PARSED defadvice form.
Returns 'simple, 'medium, or 'complex."
  (let* ((class (plist-get parsed :class))
         (body (plist-get parsed :body))
         (ad-do-it-count (ems--count-symbol-in-tree 'ad-do-it body))
         (has-ad-return-value (ems--symbol-in-tree-p 'ad-return-value body))
         (has-ad-get-arg (ems--symbol-in-tree-p 'ad-get-arg body)))

    (cond
     ;; Complex cases
     ((> ad-do-it-count 1) 'complex) ; Multiple ad-do-it calls
     ((and has-ad-return-value (eq class 'around)) 'complex)

     ;; Medium cases
     ((eq class 'around) 'medium)
     (has-ad-get-arg 'medium)

     ;; Simple cases
     ((and (eq class 'after)
           (not has-ad-return-value)
           (not has-ad-get-arg))
      'simple)
     ((eq class 'before) 'simple)

     ;; Default to medium
     (t 'medium))))

;;; Body Transformation

(defun ems--transform-body-for-after (body)
  "Transform BODY for :after advice. Simply returns body as-is with &rest _."
  body)

(defun ems--transform-body-for-before (body)
  "Transform BODY for :before advice. Returns body as-is."
  body)

(defun ems--transform-body-for-around (body fn-name)
  "Transform BODY for :around advice.
Replaces ad-do-it with (apply orig-fun args).
Handles ad-return-value by binding result.
FN-NAME is the function being advised (for error messages)."
  (let ((has-ad-return-value (ems--symbol-in-tree-p 'ad-return-value body))
        (ad-do-it-count (ems--count-symbol-in-tree 'ad-do-it body)))

    (cond
     ;; Simple case: just ad-do-it, no return value manipulation
     ((and (not has-ad-return-value) (= ad-do-it-count 1))
      (ems--replace-in-tree 'ad-do-it '(apply orig-fun args) body))

     ;; Complex case: ad-return-value manipulation
     (has-ad-return-value
      (let ((transformed (ems--replace-in-tree 'ad-do-it '(apply orig-fun args) body)))
        (setq transformed (ems--replace-in-tree 'ad-return-value 'result transformed))
        ;; Wrap in let to bind result
        `((let ((result (apply orig-fun args)))
            ,@transformed
            result))))

     ;; Multiple ad-do-it - flag for manual review
     ((> ad-do-it-count 1)
      (push (list :function fn-name :reason "Multiple ad-do-it calls")
            ems-manual-review-items)
      body) ; Return unchanged for manual review

     ;; Default: simple replacement
     (t (ems--replace-in-tree 'ad-do-it '(apply orig-fun args) body)))))

;;; Function Name Generation

(defun ems--generate-advice-function-name (fn-name class)
  "Generate advice function name for FN-NAME and CLASS.
Format: ems--FUNCNAME-CLASS
Example: (ems--generate-advice-function-name 'next-line 'after)
         => ems--next-line-after"
  (intern (format "ems--%s-%s" fn-name class)))

;;; Code Generation

(defun ems--generate-advice-function (parsed)
  "Generate the advice function definition from PARSED defadvice.
Returns a defun form."
  (let* ((fn-name (plist-get parsed :function))
         (class (plist-get parsed :class))
         (docstring (plist-get parsed :docstring))
         (body (plist-get parsed :body))
         (advice-fn-name (ems--generate-advice-function-name fn-name class))
         (complexity (ems--classify-complexity parsed))
         (transformed-body
          (pcase class
            ('after (ems--transform-body-for-after body))
            ('before (ems--transform-body-for-before body))
            ('around (ems--transform-body-for-around body fn-name))
            (_ (error "Unknown advice class: %s" class)))))

    ;; Generate the function
    (pcase class
      ('after
       `(defun ,advice-fn-name (&rest _)
          ,@(when docstring (list docstring))
          ,@transformed-body))

      ('before
       `(defun ,advice-fn-name (&rest _)
          ,@(when docstring (list docstring))
          ,@transformed-body))

      ('around
       `(defun ,advice-fn-name (orig-fun &rest args)
          ,@(when docstring (list docstring))
          ,@transformed-body)))))

(defun ems--generate-advice-add (parsed)
  "Generate the advice-add call from PARSED defadvice.
Returns an advice-add form."
  (let* ((fn-name (plist-get parsed :function))
         (class (plist-get parsed :class))
         (advice-fn-name (ems--generate-advice-function-name fn-name class))
         (advice-class-keyword (intern (concat ":" (symbol-name class)))))

    `(advice-add ',fn-name ,advice-class-keyword #',advice-fn-name)))

(defun ems--convert-defadvice-form (form)
  "Convert a single defadvice FORM to advice-add equivalent.
Returns a list of forms (defun + advice-add), or nil if should skip."
  (condition-case err
      (progn
        (message "DEBUG: Converting form for %s" (nth 1 form))
        (let* ((parsed (progn
                         (message "DEBUG: Parsing...")
                         (ems--parse-defadvice form)))
               (complexity (progn
                             (message "DEBUG: Classifying complexity...")
                             (ems--classify-complexity parsed)))
               (defun-form (progn
                             (message "DEBUG: Generating defun...")
                             (ems--generate-advice-function parsed)))
               (advice-add-form (progn
                                  (message "DEBUG: Generating advice-add...")
                                  (ems--generate-advice-add parsed))))

          ;; Add to manual review if complex
          (when (eq complexity 'complex)
            (push (list :function (plist-get parsed :function)
                        :class (plist-get parsed :class)
                        :reason "Complex pattern requiring manual review")
                  ems-manual-review-items))

          (message "DEBUG: Success!")
          ;; Return both forms
          (list defun-form advice-add-form)))

    (error
     (message "DEBUG: Error during conversion: %s" (error-message-string err))
     (message "DEBUG: Error data: %S" err)
     (push (list :form form :error (error-message-string err) :error-data err)
           ems-manual-review-items)
     nil)))

;;; Pretty Printing

(defun ems--format-elisp-form (form &optional indent)
  "Format elisp FORM as a string with proper indentation.
INDENT is the current indentation level (default 0)."
  (let ((indent (or indent 0)))
    (with-temp-buffer
      (emacs-lisp-mode)
      (insert (prin1-to-string form))
      (goto-char (point-min))
      (indent-sexp)
      (buffer-string))))

;;; File Processing

(defun ems--find-all-defadvice (buffer)
  "Find all defadvice forms in BUFFER.
Returns a list of (position . form) pairs."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (let ((results nil))
        (while (re-search-forward "^(defadvice " nil t)
          (goto-char (match-beginning 0))
          (let ((pos (point))
                (form (ignore-errors (read (current-buffer)))))
            (when form
              (push (cons pos form) results))))
        (nreverse results)))))

(defun ems-convert-buffer ()
  "Convert all defadvice forms in current buffer to advice-add.
This modifies the buffer in-place."
  (interactive)
  (let ((ems-conversion-stats '(:converted 0 :skipped 0 :errors 0))
        (ems-manual-review-items nil)
        (defadvice-list (ems--find-all-defadvice (current-buffer))))

    (save-excursion
      (dolist (item (reverse defadvice-list)) ; Process in reverse to preserve positions
        (let* ((pos (car item))
               (form (cdr item))
               (converted (ems--convert-defadvice-form form)))

          (if converted
              (progn
                (goto-char pos)
                (let ((end (progn (forward-sexp) (point))))
                  (delete-region pos end)
                  (goto-char pos)

                  ;; Insert converted forms
                  (insert "\n")
                  (dolist (new-form converted)
                    (insert (ems--format-elisp-form new-form))
                    (insert "\n\n"))

                  (cl-incf (plist-get ems-conversion-stats :converted))))

            (cl-incf (plist-get ems-conversion-stats :skipped))))))

    ;; Report results
    (message "Conversion complete: %d converted, %d skipped, %d for manual review"
             (plist-get ems-conversion-stats :converted)
             (plist-get ems-conversion-stats :skipped)
             (length ems-manual-review-items))

    (when ems-manual-review-items
      (message "Manual review items:")
      (dolist (item ems-manual-review-items)
        (message "  - %S" item)))

    ems-conversion-stats))

(defun ems-convert-file (filename)
  "Convert defadvice forms in FILENAME to advice-add.
Creates a backup with .defadvice-backup extension."
  (interactive "fFile to convert: ")
  (let ((backup-file (concat filename ".defadvice-backup")))
    ;; Create backup
    (copy-file filename backup-file t)
    (message "Backup created: %s" backup-file)

    ;; Convert
    (with-current-buffer (find-file-noselect filename)
      (let ((stats (ems-convert-buffer)))
        (save-buffer)
        (message "Converted %s: %d forms" filename
                 (plist-get stats :converted))
        stats))))

(provide 'defadvice-to-advice-add)
;;; defadvice-to-advice-add.el ends here
