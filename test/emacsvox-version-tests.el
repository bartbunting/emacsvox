;;; emacsvox-version-tests.el --- Version identity tests -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Check the canonical calendar version, derived metadata, runtime display,
;; and the fast release-version validator.

;;; Code:

(require 'ert)
(require 'emacsvox-version)
(require 'emacsvox)

(defconst emacsvox-version-tests--root
  (expand-file-name "../" (file-name-directory load-file-name)))

(defconst emacsvox-version-tests--checker
  (expand-file-name
   "utils/emacsvox-version-check" emacsvox-version-tests--root))

(defun emacsvox-version-tests--file-string (relative)
  "Return the contents of RELATIVE below the repository root."
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name relative emacsvox-version-tests--root))
    (buffer-string)))

(defun emacsvox-version-tests--run-checker (&optional root mode)
  "Run the version checker for ROOT in MODE and return status and output."
  (let ((process-environment (copy-sequence process-environment)))
    (setenv
     "EMACSVOX_VERSION_ROOT"
     (or root emacsvox-version-tests--root))
    (with-temp-buffer
      (let ((status
             (call-process
              emacsvox-version-tests--checker nil '(t t) nil
              (or mode "--check"))))
        (list status (buffer-string))))))

(defun emacsvox-version-tests--write-fixture
    (root version package-version news-version)
  "Write a minimal version-check fixture below ROOT."
  (make-directory (expand-file-name "lisp" root) t)
  (make-directory (expand-file-name "etc" root) t)
  (with-temp-file (expand-file-name "VERSION" root)
    (insert version "\n"))
  (with-temp-file (expand-file-name "lisp/emacsvox.el" root)
    (insert ";; Version: " package-version "\n"))
  (with-temp-file (expand-file-name "etc/NEWS" root)
    (insert
     "* Emacsvox " news-version " --- Current User-Visible Changes\n")))

(defun emacsvox-version-tests--git (root &rest arguments)
  "Run Git with ARGUMENTS in ROOT, failing the current test on error."
  (with-temp-buffer
    (let ((status
           (apply
            #'call-process "git" nil '(t t) nil
            "-C" root arguments)))
      (unless (equal status 0)
        (ert-fail
         (format
          "git %s failed with %s: %s"
          (mapconcat #'identity arguments " ") status (buffer-string)))))))

(defun emacsvox-version-tests--initialize-repository (root)
  "Initialize and commit the version fixture below ROOT."
  (emacsvox-version-tests--git root "init" "--quiet")
  (emacsvox-version-tests--git
   root "config" "user.name" "Emacsvox Version Tests")
  (emacsvox-version-tests--git
   root "config" "user.email" "version-tests@example.invalid")
  (emacsvox-version-tests--git root "add" ".")
  (emacsvox-version-tests--git
   root "commit" "--quiet" "-m" "Version fixture"))

(defun emacsvox-version-tests--current-release ()
  "Return a patch-zero version for the current local calendar month."
  (format
   "%s.%d.0"
   (format-time-string "%Y")
   (string-to-number (format-time-string "%m"))))

(defun emacsvox-version-tests--adjacent-patch-release (direction)
  "Return a patch-one release one month in DIRECTION from the current month."
  (let ((year (string-to-number (format-time-string "%Y")))
        (month (string-to-number (format-time-string "%m"))))
    (setq month (+ month direction))
    (cond
     ((= month 0)
      (setq year (1- year)
            month 12))
     ((= month 13)
      (setq year (1+ year)
            month 1)))
    (format "%d.%d.1" year month)))

(ert-deftest emacsvox-version-canonical-source-is-valid ()
  "The runtime value comes from the one-line canonical CalVer source."
  (should
   (string-match-p
    (concat "\\`" emacsvox-version-regexp "\\'")
    emacsvox-version-number))
  (should
   (equal
    (emacsvox-version-tests--file-string "VERSION")
    (concat emacsvox-version-number "\n"))))

(ert-deftest emacsvox-version-derived-metadata-is-consistent ()
  "Package metadata and current NEWS agree with the canonical version."
  (let ((package-source
         (emacsvox-version-tests--file-string "lisp/emacsvox.el"))
        (news (emacsvox-version-tests--file-string "etc/NEWS")))
    (should
     (string-match-p
      (concat
       "^;; Version: " (regexp-quote emacsvox-version-number) "$")
      package-source))
    (should
     (string-match-p
      (concat
       "^\\* Emacsvox " (regexp-quote emacsvox-version-number)
       " --- Current User-Visible Changes$")
      news))))

(ert-deftest emacsvox-version-runtime-display-uses-canonical-version ()
  "Spoken and startup versions cannot retain a compiled legacy number."
  (should (boundp 'emacsvox-version))
  (should
   (string-prefix-p emacsvox-version-number emacsvox-version))
  (should
   (string-match-p
    (regexp-quote emacsvox-version-number) emacsvox-startup)))

(ert-deftest emacsvox-release-tag-policy-is-annotated-and-unsigned ()
  "The guarded release target creates the tag form accepted by ADR 0006."
  (let* ((makefile (emacsvox-version-tests--file-string "Makefile"))
         (repository-resolution
          (string-match
           (regexp-quote
            "$$(git remote get-url \"$(RELEASE_REMOTE)\")")
           makefile))
         (tag-push
          (string-match
           (regexp-quote
            "git push \"$(RELEASE_REMOTE)\" \"refs/tags/$(VERSION)\"")
           makefile)))
    (should
     (string-match-p
      (regexp-quote
       "git tag -a \"$(VERSION)\" -m \"Emacsvox $(VERSION)\"")
      makefile))
    (should-not
     (string-match-p (regexp-quote "git tag -s") makefile))
    (should repository-resolution)
    (should tag-push)
    (should (< repository-resolution tag-push))
    (should
     (string-match-p
      (regexp-quote "--repo \"$$release_repository\"")
      makefile))))

(ert-deftest emacsvox-version-checker-accepts-the-repository ()
  "The fast non-mutating checker accepts all maintained version metadata."
  (pcase-let ((`(,status ,output) (emacsvox-version-tests--run-checker)))
    (should (equal status 0))
    (should
     (string-match-p
      (concat (regexp-quote emacsvox-version-number) " is valid")
      output))))

(ert-deftest emacsvox-version-checker-rejects-invalid-month ()
  "The checker rejects a numeric value outside the calendar month range."
  (let ((root (make-temp-file "emacsvox-version-invalid-" t)))
    (unwind-protect
        (progn
          (emacsvox-version-tests--write-fixture
           root "2026.13.0" "2026.13.0" "2026.13.0")
          (pcase-let
              ((`(,status ,output)
                (emacsvox-version-tests--run-checker root)))
            (should-not (equal status 0))
            (should (string-match-p "not an unpadded" output))))
      (delete-directory root t))))

(ert-deftest emacsvox-version-checker-rejects-metadata-drift ()
  "The checker rejects derived package or NEWS versions that drift."
  (let ((root (make-temp-file "emacsvox-version-drift-" t)))
    (unwind-protect
        (progn
          (emacsvox-version-tests--write-fixture
           root "2026.9.0" "2026.9.1" "2026.9.0")
          (pcase-let
              ((`(,status ,output)
                (emacsvox-version-tests--run-checker root)))
            (should-not (equal status 0))
            (should (string-match-p "Version is.*expected" output))))
      (delete-directory root t))))

(ert-deftest emacsvox-version-release-check-requires-clean-current-series ()
  "Release mode accepts a clean current series and rejects later changes."
  (let* ((root (make-temp-file "emacsvox-version-release-" t))
         (version (emacsvox-version-tests--current-release)))
    (unwind-protect
        (progn
          (emacsvox-version-tests--write-fixture
           root version version version)
          (emacsvox-version-tests--initialize-repository root)
          (pcase-let
              ((`(,status ,output)
                (emacsvox-version-tests--run-checker root "--release")))
            (should (equal status 0))
            (should (string-match-p "valid for release" output)))
          (with-temp-file (expand-file-name "uncommitted" root)
            (insert "dirty\n"))
          (pcase-let
              ((`(,status ,output)
                (emacsvox-version-tests--run-checker root "--release")))
            (should-not (equal status 0))
            (should (string-match-p "worktree is not clean" output))))
      (delete-directory root t))))

(ert-deftest emacsvox-version-release-check-allows-delayed-patch ()
  "A patch may be published after the month that opened its release series."
  (let* ((root (make-temp-file "emacsvox-version-backport-" t))
         (version (emacsvox-version-tests--adjacent-patch-release -1)))
    (unwind-protect
        (progn
          (emacsvox-version-tests--write-fixture
           root version version version)
          (emacsvox-version-tests--initialize-repository root)
          (pcase-let
              ((`(,status ,output)
                (emacsvox-version-tests--run-checker root "--release")))
            (should (equal status 0))
            (should (string-match-p "valid for release" output))))
      (delete-directory root t))))

(ert-deftest emacsvox-version-release-check-rejects-future-patch-series ()
  "A patch cannot claim a release series that has not begun."
  (let* ((root (make-temp-file "emacsvox-version-future-" t))
         (version (emacsvox-version-tests--adjacent-patch-release 1)))
    (unwind-protect
        (progn
          (emacsvox-version-tests--write-fixture
           root version version version)
          (emacsvox-version-tests--initialize-repository root)
          (pcase-let
              ((`(,status ,output)
                (emacsvox-version-tests--run-checker root "--release")))
            (should-not (equal status 0))
            (should (string-match-p "future release series" output))))
      (delete-directory root t))))

(ert-deftest emacsvox-version-tag-and-publish-check-release-lineage ()
  "Tag mode prevents reuse and publish mode requires the tag at HEAD."
  (let* ((root (make-temp-file "emacsvox-version-tag-" t))
         (version (emacsvox-version-tests--current-release)))
    (unwind-protect
        (progn
          (emacsvox-version-tests--write-fixture
           root version version version)
          (emacsvox-version-tests--initialize-repository root)
          (should
           (equal
            (car
             (emacsvox-version-tests--run-checker root "--tag"))
            0))
          (emacsvox-version-tests--git root "tag" version)
          (pcase-let
              ((`(,status ,output)
                (emacsvox-version-tests--run-checker root "--tag")))
            (should-not (equal status 0))
            (should (string-match-p "already exists" output)))
          (pcase-let
              ((`(,status ,output)
                (emacsvox-version-tests--run-checker root "--publish")))
            (should (equal status 0))
            (should (string-match-p "valid for publish" output)))
          (with-temp-file (expand-file-name "later" root)
            (insert "later commit\n"))
          (emacsvox-version-tests--git root "add" "later")
          (emacsvox-version-tests--git
           root "commit" "--quiet" "-m" "Later fixture commit")
          (pcase-let
              ((`(,status ,output)
                (emacsvox-version-tests--run-checker root "--publish")))
            (should-not (equal status 0))
            (should (string-match-p "does not identify HEAD" output))))
      (delete-directory root t))))

(provide 'emacsvox-version-tests)

;;; emacsvox-version-tests.el ends here
