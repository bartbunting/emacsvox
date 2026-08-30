;;; emacsvox-name-audit.el --- Audit removed Emacspeak names -*- lexical-binding: t; -*-

;;; Commentary:

;; Audit tracked, active text files for removed technical names.  Historical
;; documents, migration records, and the pinned upstream-comparison harness are
;; explicitly excluded.  External URLs remain valid references to upstream
;; Emacspeak resources and are ignored at match level.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(defconst ems-name-audit-patterns
  '(("\\_<emacspeak-[[:alnum:]-]+\\_>" . "legacy API or file name")
    ("\\_<EMACSPEAK_[[:upper:][:digit:]_]+\\_>" . "legacy environment name")
    ("\\(?:\\`\\|[/~]\\)\\.emacspeak\\(?:/\\|\\_>\\)"
     . "legacy user directory")
    ("/emacspeak/" . "legacy installation path"))
  "Patterns and descriptions for removed technical names.")

(defconst ems-name-audit-excluded-prefixes
  '("announcements/"
    "blog-archive/"
    "etc/NEWS"
    "etc/ai/"
    "html/"
    "info/emacspeak-significance"
    "info/inc-turning-twenty"
    "info/introducing-emacspeak"
    "info/tutorial."
    "test/golden/"
    "tvr/not-used/")
  "Tracked historical path prefixes excluded from the audit.")

(defconst ems-name-audit-excluded-files
  '("etc/advice-migration.org"
    "etc/tts-modernization.org"
    "docs/manual/chapters/provenance.org"
    "info/emacsvox-body.texi"
    "info/Makefile"
    "lisp/elpa-readme"
    "readme-attic"
    "test/README.org"
    "test/emacsvox-name-audit-tests.el"
    "test/emacsvox-trace.el"
    "test/emacsvox-tts-tests.el"
    "test/run-scenarios.el"
    "utils/emacsvox-name-audit.el"
    "utils/rename-files.sh"
    "utils/rename-to-emacsvox.sh"
    "utils/test-defadvice.el")
  "Individual historical, migration, and comparison files excluded.")

(defconst ems-name-audit-allowed-names
  '(("CLAUDE.md" "EMACSPEAK_DIR" "EMACSPEAK_PLAY")
    ("Makefile" "EMACSPEAK_DIR" "EMACSPEAK_TRACE_GOLDEN")
    ("Readme.org" "EMACSPEAK_DIR" "EMACSPEAK_PLAY")
    ("info/dir" "emacspeak-significance")
    ("info/emacsvox-heritage.texi" "emacspeak-significance")
    ("servers/windows-speech-NOTICE.md" "emacspeak-support")
    ("test/emacsvox-launcher-tests.el"
     "EMACSPEAK_DIR" "EMACSPEAK_PLAY"))
  "Removed names intentionally documented in otherwise active files.")

(defun ems-name-audit--tracked-files (directory)
  "Return tracked paths relative to Git DIRECTORY."
  (let ((default-directory
         (file-name-as-directory (expand-file-name directory))))
    (process-lines "git" "ls-files")))

(defun ems-name-audit--excluded-path-p (relative)
  "Return non-nil when tracked path RELATIVE is explicitly excluded."
  (or
   (member relative ems-name-audit-excluded-files)
   (seq-some
    (lambda (prefix) (string-prefix-p prefix relative))
    ems-name-audit-excluded-prefixes)
   (string-match-p
    "\\`info/emacsvox\\(?:-heritage\\|-reference\\)?\\.info\\(?:-[[:digit:]]+\\)?\\'"
    relative)))

(defun ems-name-audit--allowed-name-p (relative name)
  "Return non-nil when NAME is explicitly allowed in RELATIVE."
  (member name (cdr (assoc relative ems-name-audit-allowed-names))))

(defun ems-name-audit--inside-url-p (line begin end)
  "Return non-nil when LINE positions BEGIN through END lie in a URL."
  (let ((start 0)
        found)
    (while
        (and
         (not found)
         (string-match
          "https?://[^][(){}<>\"'[:space:]]+"
          line start))
      (when
          (and
           (>= begin (match-beginning 0))
           (<= end (match-end 0)))
        (setq found t))
      (setq start (match-end 0)))
    found))

(defun ems-name-audit--line-matches (relative line line-number)
  "Return audit matches in LINE from RELATIVE at LINE-NUMBER."
  (let ((case-fold-search nil)
        matches)
    (dolist (entry ems-name-audit-patterns)
      (let ((start 0)
            (regexp (car entry))
            (description (cdr entry)))
        (while (string-match regexp line start)
          (let ((begin (match-beginning 0))
                (end (match-end 0))
                (name (match-string 0 line)))
            (unless
                (or
                 (ems-name-audit--inside-url-p line begin end)
                 (ems-name-audit--allowed-name-p relative name))
              (push
               (list relative line-number name description)
               matches))
            (setq start (max end (1+ begin)))))))
    (nreverse matches)))

(defun ems-name-audit-file (root relative)
  "Audit tracked file RELATIVE below ROOT."
  (let ((filename (expand-file-name relative root))
        matches)
    (when (file-regular-p filename)
      (with-temp-buffer
        (insert-file-contents-literally filename)
        (unless (save-excursion (search-forward "\0" nil t))
          (goto-char (point-min))
          (let ((line-number 1))
            (while (not (eobp))
              (setq
               matches
               (nconc
                matches
                (ems-name-audit--line-matches
                 relative
                 (buffer-substring-no-properties
                  (line-beginning-position) (line-end-position))
                 line-number)))
              (forward-line 1)
              (cl-incf line-number))))))
    matches))

(defun ems-name-audit-directory (directory)
  "Audit tracked active files below Git DIRECTORY."
  (let* ((root (file-name-as-directory (expand-file-name directory)))
         (files
          (cl-remove-if
           #'ems-name-audit--excluded-path-p
           (ems-name-audit--tracked-files root)))
         matches)
    (dolist (relative files)
      (setq
       matches
       (nconc matches (ems-name-audit-file root relative))))
    (list
     :directory root
     :file-count (length files)
     :matches matches)))

(defun ems-name-audit-clean-p (audit)
  "Return non-nil when AUDIT contains no removed technical names."
  (null (plist-get audit :matches)))

(defun ems-name-audit-format (audit)
  "Format AUDIT as a deterministic text report."
  (let ((matches (plist-get audit :matches)))
    (concat
     (format
      "Emacsvox name audit: %d active tracked files, %d stale names\n"
      (plist-get audit :file-count)
      (length matches))
     (mapconcat
      (lambda (match)
        (pcase-let ((`(,file ,line ,name ,description) match))
          (format "%s:%d: %s (%s)" file line name description)))
      matches
      "\n")
     (if matches "\n" ""))))

(defun ems-name-audit-batch (directory)
  "Audit DIRECTORY, print the report, and fail batch Emacs if dirty."
  (let ((audit (ems-name-audit-directory directory)))
    (princ (ems-name-audit-format audit))
    (unless (ems-name-audit-clean-p audit)
      (kill-emacs 1))
    audit))

(provide 'emacsvox-name-audit)
;;; emacsvox-name-audit.el ends here
