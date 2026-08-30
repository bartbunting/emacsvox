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

(defconst emacsvox-docs-check--manuals
  '((:name "emacsvox"
     :source "emacsvox.texi")
    (:name "emacsvox-reference"
     :source "emacsvox-reference.texi"
     :html-directory "reference"))
  "Manuals compiled and published by the documentation workflow.")

(defconst emacsvox-docs-check--compatibility-redirects
  '((:html-directory "reference"
     :inventory "etc/docs-reference-redirects.txt"))
  "Frozen inventories of legacy root HTML paths for moved manual nodes.")

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

(defun emacsvox-docs-check--normalize-info-file (file)
  "Remove trailing whitespace and excess final newlines from temporary FILE."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally file)
    (let ((changed nil))
      (goto-char (point-min))
      (while (re-search-forward "[ \t]+$" nil t)
        (replace-match "" nil nil)
        (setq changed t))
      (goto-char (point-max))
      (let ((end (point)))
        (skip-chars-backward "\n")
        (unless (= (- end (point)) 1)
          (delete-region (point) end)
          (insert "\n")
          (setq changed t)))
      (when changed
        (let ((coding-system-for-write 'no-conversion))
          (write-region (point-min) (point-max) file nil 'silent))))))

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

(defun emacsvox-docs-check--manual-info-files (directory manual)
  "Return sorted Info basenames for MANUAL below DIRECTORY."
  (let ((name (plist-get manual :name)))
    (sort
     (directory-files
      directory nil
      (format "\\`%s\\.info\\(?:-[0-9]+\\)?\\'" (regexp-quote name)))
     #'string-lessp)))

(defun emacsvox-docs-check--check-info-manual
    (source-directory output-directory makeinfo install-info manual)
  "Compile and validate one Info MANUAL from SOURCE-DIRECTORY.
Write temporary output below OUTPUT-DIRECTORY using MAKEINFO and validate its
directory entry with INSTALL-INFO."
  (let* ((name (plist-get manual :name))
         (source (plist-get manual :source))
         (output (expand-file-name (concat name ".info") output-directory))
         (file-regexp
          (format "\\`%s\\.info\\(?:-[0-9]+\\)?\\'" (regexp-quote name))))
    (emacsvox-docs-check--run-process
     (format "%s Info compilation" name) makeinfo source-directory nil
     "--error-limit=0" (concat "--output=" output) source)
    (dolist (file (directory-files output-directory t file-regexp))
      (emacsvox-docs-check--normalize-info-file file))
    (let ((expected-files
           (emacsvox-docs-check--manual-info-files source-directory manual))
          (actual-files
           (emacsvox-docs-check--manual-info-files output-directory manual)))
      (unless (equal expected-files actual-files)
        (error "%s checked Info file set is stale: expected %S, generated %S"
               name expected-files actual-files))
      (dolist (file expected-files)
        (emacsvox-docs-check--compare-file
         (expand-file-name file source-directory)
         (expand-file-name file output-directory)
         (format "Checked Info output %s" file))))
    (emacsvox-docs-check--run-process
     (format "%s Info directory validation" name)
     install-info source-directory
     "\\`test mode, not updating dir file .+\\'"
     "--test" output (expand-file-name "dir" source-directory))))

(defun emacsvox-docs-check--check-info
    (root temporary-directory makeinfo install-info)
  "Compile and validate every checked Info manual for ROOT."
  (let* ((source-directory (expand-file-name "info" root))
         (output-directory
          (file-name-as-directory
           (expand-file-name "info" temporary-directory))))
    (make-directory output-directory)
    (dolist (manual emacsvox-docs-check--manuals)
      (emacsvox-docs-check--check-info-manual
       source-directory output-directory makeinfo install-info manual))))

(defun emacsvox-docs-check--compile-html-manual
    (source-directory output-root makeinfo htmlxref manual)
  "Compile one HTML MANUAL below OUTPUT-ROOT from SOURCE-DIRECTORY."
  (let* ((name (plist-get manual :name))
         (source (plist-get manual :source))
         (relative-directory (plist-get manual :html-directory))
         (output-directory
          (if relative-directory
              (expand-file-name relative-directory output-root)
            output-root)))
    (when (file-exists-p output-directory)
      (error "%s HTML output already exists: %s" name output-directory))
    (when relative-directory
      (make-directory output-root t))
    (emacsvox-docs-check--run-process
     (format "%s HTML compilation" name) makeinfo source-directory nil
     "--error-limit=0" "--html"
     "-c" "HTMLXREF_MODE=file"
     "-c" (concat "HTMLXREF_FILE=" htmlxref)
     "--css-ref=https://www.w3.org/StyleSheets/Core/Modernist"
     (concat "--output=" output-directory) source)
    (mapcar
     (lambda (file) (file-relative-name file output-root))
     (directory-files-recursively output-directory "\\.html\\'"))))

(defun emacsvox-docs-check--html-escape (string)
  "Return STRING escaped for HTML text and attribute contexts."
  (let ((escaped (replace-regexp-in-string "&" "&amp;" string t t)))
    (setq escaped (replace-regexp-in-string "<" "&lt;" escaped t t))
    (setq escaped (replace-regexp-in-string ">" "&gt;" escaped t t))
    (replace-regexp-in-string "\"" "&quot;" escaped t t)))

(defun emacsvox-docs-check--redirect-inventory (root relative-file)
  "Read a frozen redirect inventory RELATIVE-FILE below ROOT."
  (let ((file (expand-file-name relative-file root)))
    (unless (file-regular-p file)
      (error "Compatibility redirect inventory is missing: %s" relative-file))
    (with-temp-buffer
      (insert-file-contents file)
      (let (names)
        (dolist (line (split-string (buffer-string) "\n" t "[ \t]+"))
          (unless (or (string-prefix-p "#" line)
                      (and (string= line (file-name-nondirectory line))
                           (string-match-p "\\.html\\'" line)))
            (error "Unsafe compatibility redirect entry in %s: %s"
                   relative-file line))
          (unless (string-prefix-p "#" line)
            (push line names)))
        (sort (delete-dups names) #'string-lessp)))))

(defun emacsvox-docs-check--write-html-redirect (file target)
  "Write an accessible static redirect FILE pointing to relative TARGET."
  (let ((escaped-target (emacsvox-docs-check--html-escape target)))
    (with-temp-file file
      (insert
       "<!doctype html>\n<html lang=\"en\">\n<head>\n"
       "<meta charset=\"utf-8\">\n"
       (format "<meta http-equiv=\"refresh\" content=\"0; url=%s\">\n"
               escaped-target)
       (format "<link rel=\"canonical\" href=\"%s\">\n" escaped-target)
       "<title>Emacsvox documentation moved</title>\n</head>\n<body>\n"
       "<p>This Emacsvox reference page moved to "
       (format "<a href=\"%s\">its maintained location</a>.</p>\n"
               escaped-target)
       "</body>\n</html>\n"))))

(defun emacsvox-docs-check--add-compatibility-redirects
    (root output-root generated)
  "Add inventoried legacy root redirects to GENERATED below OUTPUT-ROOT."
  (let ((generated (copy-sequence generated)))
    (dolist (specification emacsvox-docs-check--compatibility-redirects)
      (let ((directory (plist-get specification :html-directory))
            (inventory (plist-get specification :inventory)))
        (dolist (name (emacsvox-docs-check--redirect-inventory root inventory))
          (let ((target (concat directory "/" name))
                (alias (expand-file-name name output-root)))
            (unless (member target generated)
              (error "Compatibility redirect target was not generated: %s"
                     target))
            (when (member name generated)
              (error "Compatibility redirect collides with current HTML: %s"
                     name))
            (emacsvox-docs-check--write-html-redirect alias target)
            (push name generated)))))
    (sort (delete-dups generated) #'string-lessp)))

(defun emacsvox-docs-check--compile-html
    (root output-directory makeinfo)
  "Compile warning-free split HTML manuals for ROOT below OUTPUT-DIRECTORY."
  (let ((source-directory (expand-file-name "info" root))
        (htmlxref (expand-file-name "info/htmlxref.cnf" root))
        files)
    (dolist (manual emacsvox-docs-check--manuals)
      (setq files
            (append
             files
             (emacsvox-docs-check--compile-html-manual
              source-directory output-directory makeinfo htmlxref manual))))
    (setq files
          (emacsvox-docs-check--add-compatibility-redirects
           root output-directory files))
    (unless (and (member "index.html" files)
                 (member "reference/index.html" files))
      (error "HTML compilation did not produce both manual entry points"))
    files))

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

(defun emacsvox-docs-check--managed-html-name-p (name)
  "Return non-nil when NAME is a safe relative managed HTML path."
  (and (stringp name)
       (not (string-empty-p name))
       (not (file-name-absolute-p name))
       (not (string-match-p "\\\\" name))
       (string-match-p "\\.html\\'" name)
       (cl-every
        (lambda (component)
          (not (member component '("" "." ".."))))
        (split-string name "/" nil))))

(defun emacsvox-docs-check--managed-target (destination name description)
  "Return a safe target below DESTINATION for managed NAME.
DESCRIPTION identifies the operation when a symbolic-link or path conflict is
reported."
  (unless (emacsvox-docs-check--managed-html-name-p name)
    (error "Unsafe managed documentation path: %s" name))
  (let ((directory (file-name-as-directory destination))
        (components (split-string name "/" nil)))
    (dolist (component (butlast components))
      (setq directory (expand-file-name component directory))
      (when (file-symlink-p directory)
        (error "Refusing symlinked %s directory: %s" description directory))
      (when (and (file-exists-p directory) (not (file-directory-p directory)))
        (error "Refusing non-directory %s path: %s" description directory)))
    (let ((target (expand-file-name name destination)))
      (when (file-symlink-p target)
        (error "Refusing symlinked %s file: %s" description target))
      target)))

(defun emacsvox-docs-check--read-publish-manifest (destination)
  "Return managed relative HTML paths recorded below DESTINATION."
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
            (unless (emacsvox-docs-check--managed-html-name-p name)
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
    (dolist (name names)
      (unless (emacsvox-docs-check--managed-html-name-p name)
        (error "Unsafe generated documentation path: %s" name)))
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
            (let ((target
                   (emacsvox-docs-check--managed-target
                    destination name "documentation publication")))
              (make-directory (file-name-directory target) t)
              (copy-file (expand-file-name name staging) target t)))
          (dolist (name stale)
            (let ((target
                   (emacsvox-docs-check--managed-target
                    destination name "stale documentation")))
              (when (file-exists-p target)
                (delete-file target))))
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
