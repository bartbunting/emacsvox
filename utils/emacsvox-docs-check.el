;;; emacsvox-docs-check.el --- Reproducible documentation checks -*- lexical-binding: t; -*-

;;; Commentary:

;; Validate generated and published Emacsvox documentation without changing
;; the source tree.  The root Makefile supplies the selected Emacs and runs the
;; byte-code preflight before invoking this file.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(declare-function self-document-all-modules "self-document")
(declare-function org-element-map "org-element")
(declare-function org-element-parse-buffer "org-element")
(declare-function org-element-property "org-element")
(declare-function org-link-unescape "ol")

(defconst emacsvox-docs-check--root
  (file-name-as-directory
   (expand-file-name
    ".." (file-name-directory (or load-file-name buffer-file-name))))
  "Emacsvox repository root.")

(defconst emacsvox-docs-check--generated-reference-files
  '("docs.texi" "keys.texi")
  "Generated reference files checked against isolated regeneration.")

(defconst emacsvox-docs-check--public-org-files
  '("Readme.org")
  "Current public Org entry points whose local links must resolve.")

(defconst emacsvox-docs-check--publish-manifest
  ".emacsvox-generated-html"
  "Manifest of HTML files managed by `emacsvox-docs-publish'.")

(defconst emacsvox-docs-check--pages-metadata
  '(".nojekyll" "emacsvox-source.txt")
  "Metadata files managed by `emacsvox-docs-publish-pages'.")

(defun emacsvox-docs-check--program (environment fallback)
  "Return the program named by ENVIRONMENT, or FALLBACK when it is unset."
  (let ((value (getenv environment)))
    (if (string-empty-p (or value "")) fallback value)))

(defun emacsvox-docs-check--validate-process-result
    (label status diagnostics)
  "Require zero STATUS and no DIAGNOSTICS for LABEL."
  (let ((diagnostics (string-trim diagnostics)))
    (unless (and (integerp status) (zerop status))
      (error "%s failed (exit %s)%s"
             label status
             (if (string-empty-p diagnostics)
                 ""
               (format ":\n%s" diagnostics))))
    (unless (string-empty-p diagnostics)
      (error "%s emitted diagnostics:\n%s" label diagnostics))))

(defun emacsvox-docs-check--run-process
    (label program directory accepted-diagnostics &rest arguments)
  "Run PROGRAM with ARGUMENTS in DIRECTORY strictly for LABEL.
Warnings and other diagnostics are failures, even when PROGRAM exits zero.
ACCEPTED-DIAGNOSTICS may name one exact successful output pattern."
  (let ((default-directory (file-name-as-directory directory))
        (process-environment
         (append
          '("LC_ALL=C" "TZ=UTC")
          (cl-remove-if
           (lambda (entry)
             (or (string-prefix-p "LC_ALL=" entry)
                 (string-prefix-p "TZ=" entry)))
           process-environment))))
    (with-temp-buffer
      (let ((status
             (condition-case condition
                 (apply #'process-file
                        program nil (list (current-buffer) t) nil arguments)
               (file-missing
                (error "%s could not run %s: %s"
                       label program (error-message-string condition))))))
        (let ((diagnostics (string-trim (buffer-string))))
          (if (and (integerp status)
                   (zerop status)
                   accepted-diagnostics
                   (string-match-p accepted-diagnostics diagnostics))
              t
            (emacsvox-docs-check--validate-process-result
             label status diagnostics)))))))

(defun emacsvox-docs-check--capture-process
    (label program directory &rest arguments)
  "Run PROGRAM with ARGUMENTS in DIRECTORY and return output for LABEL."
  (let ((default-directory (file-name-as-directory directory))
        (process-environment
         (append
          '("LC_ALL=C" "TZ=UTC")
          (cl-remove-if
           (lambda (entry)
             (or (string-prefix-p "LC_ALL=" entry)
                 (string-prefix-p "TZ=" entry)))
           process-environment))))
    (with-temp-buffer
      (let ((status
             (condition-case condition
                 (apply #'process-file
                        program nil (list (current-buffer) t) nil arguments)
               (file-missing
                (error "%s could not run %s: %s"
                       label program (error-message-string condition))))))
        (let ((output (string-trim (buffer-string))))
          (unless (and (integerp status) (zerop status))
            (error "%s failed (exit %s)%s"
                   label status
                   (if (string-empty-p output) "" (format ":\n%s" output))))
          output)))))

(defun emacsvox-docs-check--file-hash (file)
  "Return the SHA-256 digest of FILE's literal contents."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally file)
    (secure-hash 'sha256 (current-buffer))))

(defun emacsvox-docs-check--compare-file (expected actual description)
  "Require EXPECTED and ACTUAL to match byte-for-byte for DESCRIPTION."
  (unless (file-regular-p actual)
    (error "%s was not generated: %s" description actual))
  (unless (string= (emacsvox-docs-check--file-hash expected)
                   (emacsvox-docs-check--file-hash actual))
    (error "%s is stale: %s (run make docs-generate)"
           description expected)))

(defun emacsvox-docs-check--strip-trailing-whitespace (file)
  "Remove trailing horizontal whitespace from temporary FILE."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally file)
    (goto-char (point-min))
    (when (re-search-forward "[ \t]+$" nil t)
      (goto-char (point-min))
      (while (re-search-forward "[ \t]+$" nil t)
        (replace-match "" nil nil))
      (let ((coding-system-for-write 'no-conversion))
        (write-region (point-min) (point-max) file nil 'silent)))))

(defun emacsvox-docs-check--assert-portable-reference (file root temporary-root)
  "Reject machine-local paths in generated FILE.
ROOT and TEMPORARY-ROOT identify the current checkout and staging directory."
  (with-temp-buffer
    (insert-file-contents file)
    (let ((case-fold-search nil)
          (literal-paths
           (delete-dups
            (mapcar #'directory-file-name
                    (list (expand-file-name root)
                          (expand-file-name "~/")
                          (expand-file-name temporary-root))))))
      (dolist (path literal-paths)
        (goto-char (point-min))
        (when (and (> (length path) 1)
                   (search-forward path nil t))
          (error "Generated reference contains a machine-local path in %s: %s"
                 file path)))
      (goto-char (point-min))
      (when (re-search-forward
             (concat
              "\\(?:/home/[^/[:space:]]+/"
              "\\|/Users/[^/[:space:]]+/"
              "\\|[[:alpha:]]:[/\\\\]Users[/\\\\][^/\\\\[:space:]]+[/\\\\]\\)")
             nil t)
        (error "Generated reference contains a personal home path in %s: %s"
               file (match-string-no-properties 0))))))

(defun emacsvox-docs-check--generate-reference (root output-directory)
  "Regenerate the command, option, and key reference below OUTPUT-DIRECTORY."
  (let ((default-directory (file-name-as-directory output-directory))
        (inhibit-message t)
        (message-log-max nil))
    (load (expand-file-name "utils/self-document.el" root) nil t)
    (self-document-all-modules)))

(defun emacsvox-docs-check--check-generated-reference
    (root temporary-directory)
  "Check isolated reference regeneration for ROOT in TEMPORARY-DIRECTORY."
  (let ((output-directory
         (file-name-as-directory
          (expand-file-name "reference" temporary-directory))))
    (make-directory output-directory)
    (emacsvox-docs-check--generate-reference root output-directory)
    (dolist (name emacsvox-docs-check--generated-reference-files)
      (let ((expected (expand-file-name (concat "info/" name) root))
            (actual (expand-file-name name output-directory)))
        (emacsvox-docs-check--compare-file
         expected actual (format "Generated reference %s" name))
        (emacsvox-docs-check--assert-portable-reference
         actual root temporary-directory)))))

(defun emacsvox-docs-check--manual-info-files (directory)
  "Return sorted current-manual Info basenames below DIRECTORY."
  (sort
   (directory-files
    directory nil "\\`emacsvox\\.info\\(?:-[0-9]+\\)?\\'")
   #'string-lessp))

(defun emacsvox-docs-check--check-info
    (root temporary-directory makeinfo install-info)
  "Compile and validate current Info documentation for ROOT."
  (let* ((source-directory (expand-file-name "info" root))
         (output-directory
          (file-name-as-directory
           (expand-file-name "info" temporary-directory)))
         (output (expand-file-name "emacsvox.info" output-directory)))
    (make-directory output-directory)
    (emacsvox-docs-check--run-process
     "Info compilation" makeinfo source-directory nil
     "--error-limit=0" (concat "--output=" output) "emacsvox.texi")
    (dolist (file (directory-files output-directory t "\\`emacsvox\\.info"))
      (emacsvox-docs-check--strip-trailing-whitespace file))
    (let ((expected-files
           (emacsvox-docs-check--manual-info-files source-directory))
          (actual-files
           (emacsvox-docs-check--manual-info-files output-directory)))
      (unless (equal expected-files actual-files)
        (error "Checked Info file set is stale: expected %S, generated %S"
               expected-files actual-files))
      (dolist (name expected-files)
        (emacsvox-docs-check--compare-file
         (expand-file-name name source-directory)
         (expand-file-name name output-directory)
         (format "Checked Info output %s" name))))
    (emacsvox-docs-check--run-process
     "Info directory validation" install-info source-directory
     "\\`test mode, not updating dir file .+\\'"
     "--test" output (expand-file-name "dir" source-directory))))

(defun emacsvox-docs-check--compile-html
    (root output-directory makeinfo)
  "Compile warning-free split HTML for ROOT below OUTPUT-DIRECTORY."
  (let ((source-directory (expand-file-name "info" root))
        (htmlxref (expand-file-name "info/htmlxref.cnf" root)))
    (emacsvox-docs-check--run-process
     "HTML compilation" makeinfo source-directory nil
     "--error-limit=0" "--html"
     "-c" "HTMLXREF_MODE=file"
     "-c" (concat "HTMLXREF_FILE=" htmlxref)
     "--css-ref=https://www.w3.org/StyleSheets/Core/Modernist"
     (concat "--output=" output-directory) "emacsvox.texi")
    (let ((files (directory-files output-directory nil "\\.html\\'")))
      (unless (and files (member "index.html" files))
        (error "HTML compilation did not produce index.html"))
      files)))

(defun emacsvox-docs-check--check-html
    (root temporary-directory makeinfo)
  "Compile current HTML documentation without changing ROOT."
  (emacsvox-docs-check--compile-html
   root (expand-file-name "html" temporary-directory) makeinfo))

(defun emacsvox-docs-check--org-local-links (file)
  "Return relative local file links as (PATH LINE) entries from Org FILE."
  (require 'org)
  (require 'org-element)
  (with-temp-buffer
    (insert-file-contents file)
    (let (links)
      (org-element-map (org-element-parse-buffer) 'link
        (lambda (link)
          (when (string= (org-element-property :type link) "file")
            (let ((path
                   (org-link-unescape (org-element-property :path link))))
              (unless (or (file-name-absolute-p path)
                          (string-prefix-p "~" path)
                          (file-remote-p path))
                (push
                 (list path
                       (line-number-at-pos
                        (org-element-property :begin link)))
                 links))))))
      (nreverse links))))

(defun emacsvox-docs-check--check-local-links (root)
  "Require relative links in current public Org entry points below ROOT."
  (dolist (relative emacsvox-docs-check--public-org-files)
    (let ((document (expand-file-name relative root)))
      (unless (file-regular-p document)
        (error "Public documentation file is missing: %s" relative))
      (dolist (link (emacsvox-docs-check--org-local-links document))
        (let ((target
               (expand-file-name (car link) (file-name-directory document))))
          (unless (file-exists-p target)
            (error "Broken local link: %s:%d -> %s"
                   relative (cadr link) (car link))))))))

(defun emacsvox-docs-check-run
    (&optional root makeinfo install-info)
  "Run the complete non-mutating documentation check.
ROOT defaults to `emacsvox-docs-check--root'."
  (let* ((root
          (file-name-as-directory
           (expand-file-name (or root emacsvox-docs-check--root))))
         (makeinfo
          (or makeinfo
              (emacsvox-docs-check--program "EMACSVOX_MAKEINFO" "makeinfo")))
         (install-info
          (or install-info
              (emacsvox-docs-check--program
               "EMACSVOX_INSTALL_INFO" "install-info")))
         (temporary-directory
          (make-temp-file "emacsvox-docs-check-" t)))
    (unwind-protect
        (progn
          (emacsvox-docs-check--check-generated-reference
           root temporary-directory)
          (emacsvox-docs-check--check-info
           root temporary-directory makeinfo install-info)
          (emacsvox-docs-check--check-html
           root temporary-directory makeinfo)
          (emacsvox-docs-check--check-local-links root)
          t)
      (when (file-directory-p temporary-directory)
        (delete-directory temporary-directory t)))))

(defun emacsvox-docs-check-batch ()
  "Run `emacsvox-docs-check-run' as a batch command."
  (condition-case condition
      (progn
        (emacsvox-docs-check-run)
        (princ "Emacsvox documentation is current and structurally valid.\n"))
    (error
     (princ
      (format "Documentation check failed: %s\n"
              (error-message-string condition))
      'external-debugging-output)
     (let ((kill-emacs-hook nil)
           (kill-emacs-query-functions nil))
       (kill-emacs 1)))))

(defun emacsvox-docs-check--validated-publish-directory (root destination)
  "Return safe absolute DESTINATION for publishing documentation from ROOT."
  (when (string-empty-p (or destination ""))
    (error "Set DOCS_PUBLISH_DIR to an existing publication directory"))
  (let* ((destination (file-name-as-directory (expand-file-name destination)))
         (true-destination
          (file-name-as-directory (file-truename destination)))
         (true-root (file-name-as-directory (file-truename root)))
         (true-home (file-name-as-directory (file-truename "~/"))))
    (unless (file-directory-p destination)
      (error "Documentation publication directory does not exist: %s"
             destination))
    (when (or (string= true-destination "/")
              (string= true-destination true-home)
              (file-in-directory-p true-destination true-root)
              (file-in-directory-p true-root true-destination))
      (error "Refusing unsafe documentation publication directory: %s"
             destination))
    destination))

(defun emacsvox-docs-check--read-publish-manifest (destination)
  "Return managed HTML basenames recorded below DESTINATION."
  (let ((manifest
         (expand-file-name emacsvox-docs-check--publish-manifest destination)))
    (when (file-symlink-p manifest)
      (error "Refusing symlinked documentation publication manifest: %s"
             manifest))
    (when (file-exists-p manifest)
      (with-temp-buffer
        (insert-file-contents manifest)
        (let ((names (split-string (buffer-string) "\n" t "[ \t]+")))
          (dolist (name names)
            (unless (and (string= name (file-name-nondirectory name))
                         (string-match-p "\\.html\\'" name))
              (error "Unsafe entry in documentation publication manifest: %s"
                     name)))
          (sort (delete-dups names) #'string-lessp))))))

(defun emacsvox-docs-check--write-publish-manifest (destination names)
  "Record generated HTML NAMES below DESTINATION."
  (let ((manifest
         (expand-file-name emacsvox-docs-check--publish-manifest destination)))
    (when (file-symlink-p manifest)
      (error "Refusing symlinked documentation publication manifest: %s"
             manifest))
    (with-temp-file manifest
      (dolist (name (sort (copy-sequence names) #'string-lessp))
        (insert name "\n")))))

(defun emacsvox-docs-check--validate-pages-metadata (destination)
  "Refuse symbolic-link Pages metadata below DESTINATION."
  (dolist (name emacsvox-docs-check--pages-metadata)
    (let ((target (expand-file-name name destination)))
      (when (file-symlink-p target)
        (error "Refusing symlinked Pages metadata file: %s" target)))))

(defun emacsvox-docs-check--write-pages-metadata
    (destination name contents)
  "Atomically write CONTENTS to Pages metadata NAME below DESTINATION."
  (let ((target (expand-file-name name destination))
        (temporary
         (make-temp-file (expand-file-name ".emacsvox-pages-" destination))))
    (unwind-protect
        (progn
          (when (file-symlink-p target)
            (error "Refusing symlinked Pages metadata file: %s" target))
          (let ((coding-system-for-write 'utf-8-unix))
            (with-temp-file temporary
              (insert contents)))
          (rename-file temporary target t)
          (setq temporary nil))
      (when (and temporary (file-exists-p temporary))
        (delete-file temporary)))))

(defun emacsvox-docs-check--source-revision (root)
  "Return ROOT's committed revision, refusing any uncommitted files."
  (let ((status
         (emacsvox-docs-check--capture-process
          "Source status" "git" root
          "status" "--porcelain=v1" "--untracked-files=all")))
    (unless (string-empty-p status)
      (error "Refusing Pages publication from an uncommitted source tree:\n%s"
             status)))
  (let ((revision
         (emacsvox-docs-check--capture-process
          "Source revision" "git" root
          "rev-parse" "--verify" "HEAD^{commit}")))
    (unless (string-match-p "\\`[0-9a-f]\\{40,64\\}\\'" revision)
      (error "Git returned an invalid source revision: %s" revision))
    revision))

(defun emacsvox-docs-check--makeinfo-version (root makeinfo)
  "Return MAKEINFO's first version line when run below ROOT."
  (let* ((output
          (emacsvox-docs-check--capture-process
           "Texinfo version" makeinfo root "--version"))
         (line (car (split-string output "\n" t))))
    (unless line
      (error "Texinfo version command returned no output"))
    line))

(defun emacsvox-docs-publish
    (destination &optional root makeinfo)
  "Render current HTML into explicit DESTINATION without committing or pushing."
  (let* ((root
          (file-name-as-directory
           (expand-file-name (or root emacsvox-docs-check--root))))
         (makeinfo
          (or makeinfo
              (emacsvox-docs-check--program "EMACSVOX_MAKEINFO" "makeinfo")))
         (destination
          (emacsvox-docs-check--validated-publish-directory root destination))
         (temporary-directory
          (make-temp-file "emacsvox-docs-publish-" t)))
    (unwind-protect
        (let* ((staging (expand-file-name "html" temporary-directory))
               (generated
                (emacsvox-docs-check--compile-html root staging makeinfo))
               (previous
                (emacsvox-docs-check--read-publish-manifest destination))
               (stale
                (cl-set-difference previous generated :test #'string=)))
          (dolist (name generated)
            (let ((target (expand-file-name name destination)))
              (when (file-symlink-p target)
                (error "Refusing symlinked documentation publication file: %s"
                       target))
              (copy-file (expand-file-name name staging) target t)))
          (dolist (name stale)
            (let ((target (expand-file-name name destination)))
              (when (file-symlink-p target)
                (error "Refusing symlinked stale documentation file: %s"
                       target))
              (delete-file target)))
          (emacsvox-docs-check--write-publish-manifest
           destination generated)
          (list :written (length generated) :removed (length stale)))
      (when (file-directory-p temporary-directory)
        (delete-directory temporary-directory t)))))

(defun emacsvox-docs-publish-pages
    (destination &optional root makeinfo)
  "Publish committed documentation and Pages metadata to DESTINATION.
ROOT must be a clean Git worktree.  This function never commits or pushes."
  (let* ((root
          (file-name-as-directory
           (expand-file-name (or root emacsvox-docs-check--root))))
         (makeinfo
          (or makeinfo
              (emacsvox-docs-check--program "EMACSVOX_MAKEINFO" "makeinfo")))
         (destination
          (emacsvox-docs-check--validated-publish-directory root destination)))
    (emacsvox-docs-check--validate-pages-metadata destination)
    (let* ((revision (emacsvox-docs-check--source-revision root))
           (texinfo-version
            (emacsvox-docs-check--makeinfo-version root makeinfo))
           (result (emacsvox-docs-publish destination root makeinfo))
           (provenance
            (format
             (concat
              "Emacsvox browser manual provenance\n"
              "Source commit: %s\n"
              "Emacs: %s\n"
              "Texinfo: %s\n")
             revision emacs-version texinfo-version)))
      (emacsvox-docs-check--write-pages-metadata destination ".nojekyll" "")
      (emacsvox-docs-check--write-pages-metadata
       destination "emacsvox-source.txt" provenance)
      (append result
              (list :source revision :texinfo-version texinfo-version)))))

(defun emacsvox-docs-publish-batch ()
  "Publish HTML to `EMACSVOX_DOCS_PUBLISH_DIR' as a batch command."
  (condition-case condition
      (let* ((destination (getenv "EMACSVOX_DOCS_PUBLISH_DIR"))
             (result (emacsvox-docs-publish destination)))
        (princ
         (format
          "Published %d HTML files to %s; removed %d stale HTML files.\n"
          (plist-get result :written) destination (plist-get result :removed))))
    (error
     (princ
      (format "Documentation publication failed: %s\n"
              (error-message-string condition))
      'external-debugging-output)
     (let ((kill-emacs-hook nil)
           (kill-emacs-query-functions nil))
       (kill-emacs 1)))))

(defun emacsvox-docs-publish-pages-batch ()
  "Publish committed Pages output to `EMACSVOX_DOCS_PUBLISH_DIR'."
  (condition-case condition
      (let* ((destination (getenv "EMACSVOX_DOCS_PUBLISH_DIR"))
             (result (emacsvox-docs-publish-pages destination)))
        (princ
         (format
          (concat
           "Published %d HTML files from %s to %s; "
           "removed %d stale HTML files.\n")
          (plist-get result :written)
          (plist-get result :source)
          destination
          (plist-get result :removed))))
    (error
     (princ
      (format "Pages publication failed: %s\n"
              (error-message-string condition))
      'external-debugging-output)
     (let ((kill-emacs-hook nil)
           (kill-emacs-query-functions nil))
       (kill-emacs 1)))))

(provide 'emacsvox-docs-check)
;;; emacsvox-docs-check.el ends here
