;;; tts-audit.el --- Inventory legacy DTK TTS names -*- lexical-binding: t; -*-

;;; Commentary:

;; Parse Lisp source rather than searching raw text, so comments do not inflate
;; the TTS namespace migration inventory.  Symbols and strings are reported
;; separately: a string can be an environment variable, load target, or
;; user-facing reference that also needs review.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defconst ems-tts-audit-definition-forms
  '(cl-defun defalias defconst defcustom defmacro defsubst defun defvar
    defvar-local)
  "Forms whose second element names a definition.")

(defconst ems-tts-audit-extra-symbols
  '(emacsvox-dtk-submap)
  "Legacy TTS symbols that do not begin with `dtk-'.")

(defconst ems-tts-audit-backend-string-names
  '("dtk-exp" "dtk-soft")
  "Names that identify real DECtalk backends rather than generic TTS APIs.")

(defconst ems-tts-audit-generated-files
  '("emacsvox-loaddefs.el")
  "Generated Lisp files excluded from namespace audits.")

(defconst ems-tts-audit-active-text-exclusions
  '("announcements/"
    "archive/"
    "blog-archive/"
    "etc/NEWS"
    "lisp/"
    "test/"
    "utils/tts-audit.el")
  "Path prefixes excluded from the active non-Lisp text audit.")

(defun ems-tts-audit--legacy-symbol-p (object)
  "Return non-nil when OBJECT is a legacy generic TTS symbol."
  (and
   (symbolp object)
   (or
    (string-prefix-p "dtk-" (symbol-name object))
    (memq object ems-tts-audit-extra-symbols))))

(defun ems-tts-audit--literal-symbol (object)
  "Return the literal symbol represented by OBJECT, or nil."
  (cond
   ((symbolp object) object)
   ((and (eq (car-safe object) 'quote)
         (symbolp (cadr object)))
    (cadr object))))

(defun ems-tts-audit--walk (object function)
  "Call FUNCTION for every node reachable in Lisp OBJECT."
  (funcall function object)
  (cond
   ((consp object)
    (ems-tts-audit--walk (car object) function)
    (ems-tts-audit--walk (cdr object) function))
   ((vectorp object)
    (mapc
     (lambda (item) (ems-tts-audit--walk item function))
     object))))

(defun ems-tts-audit--increment (key alist)
  "Increment KEY in ALIST and return the resulting alist."
  (let ((entry (assoc key alist)))
    (if entry
        (cl-incf (cdr entry))
      (push (cons key 1) alist)))
  alist)

(defun ems-tts-audit--string-matches (string regexp)
  "Return every non-overlapping match for REGEXP in STRING."
  (let ((start 0)
        matches)
    (while (string-match regexp string start)
      (push (match-string 0 string) matches)
      (setq start (match-end 0)))
    (nreverse matches)))

(defun ems-tts-audit--legacy-string-names (string)
  "Return legacy TTS names embedded in STRING."
  (append
   (cl-remove-if
    (lambda (name)
      (member name ems-tts-audit-backend-string-names))
    (ems-tts-audit--string-matches
     string "\\_<dtk-[[:alnum:]-]+\\_>"))
   (ems-tts-audit--string-matches
    string "\\_<DTK_[[:upper:][:digit:]_]+\\_>")))

(defun ems-tts-audit--sorted-counts (counts)
  "Return COUNTS sorted alphabetically by printed key."
  (sort
   counts
   (lambda (left right)
     (string< (format "%s" (car left))
              (format "%s" (car right))))))

(defun ems-tts-audit-forms (forms &optional source)
  "Audit parsed Lisp FORMS originating from SOURCE."
  (let (definitions symbol-counts string-counts)
    (dolist (form forms)
      (ems-tts-audit--walk
       form
       (lambda (node)
         (cond
          ((ems-tts-audit--legacy-symbol-p node)
           (setq symbol-counts
                 (ems-tts-audit--increment node symbol-counts)))
          ((stringp node)
           (dolist (name (ems-tts-audit--legacy-string-names node))
             (setq string-counts
                   (ems-tts-audit--increment name string-counts)))))
         (when
             (and
              (consp node)
              (memq (car node) ems-tts-audit-definition-forms))
           (let ((name (ems-tts-audit--literal-symbol (nth 1 node))))
             (when (ems-tts-audit--legacy-symbol-p name)
               (cl-pushnew name definitions)))))))
    (list
     :source source
     :definitions
     (sort definitions
           (lambda (left right)
             (string< (symbol-name left) (symbol-name right))))
     :symbol-counts (ems-tts-audit--sorted-counts symbol-counts)
     :string-counts (ems-tts-audit--sorted-counts string-counts))))

(defun ems-tts-audit-buffer (&optional source)
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
      (ems-tts-audit-forms (nreverse forms) source))))

(defun ems-tts-audit-file (filename)
  "Read and audit Lisp source FILENAME."
  (with-temp-buffer
    (insert-file-contents filename)
    (ems-tts-audit-buffer filename)))

(defun ems-tts-audit--merge-counts (target source)
  "Add SOURCE counts to TARGET and return the resulting alist."
  (dolist (entry source)
    (dotimes (_ (cdr entry))
      (setq target (ems-tts-audit--increment (car entry) target))))
  target)

(defun ems-tts-audit-directory (directory)
  "Return deterministic TTS namespace audit data for DIRECTORY."
  (let* ((root (file-name-as-directory (expand-file-name directory)))
         (files
          (sort
           (cl-remove-if
            (lambda (filename)
              (member
               (file-name-nondirectory filename)
               ems-tts-audit-generated-files))
            (directory-files-recursively root (rx ".el" string-end)))
           #'string<))
         definitions
         symbol-counts
         string-counts
         file-results)
    (dolist (filename files)
      (let ((result (ems-tts-audit-file filename)))
        (setq definitions
              (append (plist-get result :definitions) definitions))
        (setq symbol-counts
              (ems-tts-audit--merge-counts
               symbol-counts (plist-get result :symbol-counts)))
        (setq string-counts
              (ems-tts-audit--merge-counts
               string-counts (plist-get result :string-counts)))
        (when
            (or
             (plist-get result :symbol-counts)
             (plist-get result :string-counts))
          (setq result
                (plist-put
                 result :source (file-relative-name filename root)))
          (push result file-results))))
    (setq definitions (delete-dups definitions))
    (list
     :directory root
     :file-count (length files)
     :legacy-file-count (length file-results)
     :definition-count (length definitions)
     :definitions
     (sort definitions
           (lambda (left right)
             (string< (symbol-name left) (symbol-name right))))
     :symbol-counts (ems-tts-audit--sorted-counts symbol-counts)
     :string-counts (ems-tts-audit--sorted-counts string-counts)
     :files (nreverse file-results))))

(defun ems-tts-audit--count-total (counts)
  "Return the total number of occurrences in COUNTS."
  (apply #'+ (mapcar #'cdr counts)))

(defun ems-tts-audit--most-used (counts &optional limit)
  "Return COUNTS ordered by use count, restricted to LIMIT entries."
  (let ((ordered
         (sort
          (copy-sequence counts)
          (lambda (left right)
            (if (= (cdr left) (cdr right))
                (string< (format "%s" (car left))
                         (format "%s" (car right)))
              (> (cdr left) (cdr right)))))))
    (seq-take ordered (or limit (length ordered)))))

(defun ems-tts-audit-clean-p (audit)
  "Return non-nil when AUDIT contains no generic legacy TTS names."
  (and
   (null (plist-get audit :symbol-counts))
   (null (plist-get audit :string-counts))))

(defun ems-tts-audit--active-text-path-p (filename)
  "Return non-nil when tracked FILENAME belongs in the active text audit."
  (not
   (seq-some
    (lambda (prefix) (string-prefix-p prefix filename))
    ems-tts-audit-active-text-exclusions)))

(defun ems-tts-audit--tracked-files (directory)
  "Return tracked files relative to Git DIRECTORY."
  (let ((default-directory
         (file-name-as-directory (expand-file-name directory))))
    (process-lines "git" "ls-files")))

(defun ems-tts-audit-active-text (directory)
  "Audit tracked active non-Lisp text files below Git DIRECTORY."
  (let* ((root (file-name-as-directory (expand-file-name directory)))
         (files
          (cl-remove-if-not
           #'ems-tts-audit--active-text-path-p
           (ems-tts-audit--tracked-files root)))
         matches)
    (dolist (relative files)
      (let ((filename (expand-file-name relative root)))
        (when (file-regular-p filename)
          (with-temp-buffer
            (insert-file-contents-literally filename)
            (unless (save-excursion (search-forward "\0" nil t))
              (goto-char (point-min))
              (let ((line 1))
                (while (not (eobp))
                  (let ((text
                         (buffer-substring-no-properties
                          (line-beginning-position) (line-end-position))))
                    (dolist (name (ems-tts-audit--legacy-string-names text))
                      (push (list relative line name) matches)))
                  (forward-line 1)
                  (cl-incf line))))))))
    (list
     :directory root
     :file-count (length files)
     :matches (nreverse matches))))

(defun ems-tts-audit-active-text-clean-p (audit)
  "Return non-nil when active-text AUDIT has no generic legacy names."
  (null (plist-get audit :matches)))

(defun ems-tts-audit-active-text-format (audit)
  "Return a concise human-readable report for active-text AUDIT."
  (let ((matches (plist-get audit :matches)))
    (concat
     (format "Active text audit: %d tracked files\n"
             (plist-get audit :file-count))
     (format "generic legacy names: %d occurrences\n" (length matches))
     (mapconcat
      (lambda (match)
        (format "  %s:%d: %s" (nth 0 match) (nth 1 match) (nth 2 match)))
      matches
      "\n")
     (when matches "\n"))))

(defun ems-tts-audit-format (audit)
  "Return a concise human-readable report for AUDIT."
  (let ((symbols (plist-get audit :symbol-counts))
        (strings (plist-get audit :string-counts)))
    (concat
     (format "TTS namespace audit: %d Lisp files\n"
             (plist-get audit :file-count))
     (format "generic legacy names: %d files, %d definitions\n"
             (plist-get audit :legacy-file-count)
             (plist-get audit :definition-count))
     (format "symbol occurrences: %d\n"
             (ems-tts-audit--count-total symbols))
     (format "string occurrences: %d\n"
             (ems-tts-audit--count-total strings))
     "most-used symbols:\n"
     (mapconcat
      (lambda (entry) (format "  %s: %d" (car entry) (cdr entry)))
      (ems-tts-audit--most-used symbols 20)
      "\n")
     "\n")))

(defun ems-tts-audit-batch (directory &optional repository)
  "Audit Lisp DIRECTORY and active text in REPOSITORY.
Print the inventories and fail if generic legacy names remain."
  (let ((lisp-audit (ems-tts-audit-directory directory))
        (text-audit (ems-tts-audit-active-text (or repository "."))))
    (princ (ems-tts-audit-format lisp-audit))
    (princ (ems-tts-audit-active-text-format text-audit))
    (unless
        (and
         (ems-tts-audit-clean-p lisp-audit)
         (ems-tts-audit-active-text-clean-p text-audit))
      (kill-emacs 1))))

(provide 'tts-audit)
;;; tts-audit.el ends here
