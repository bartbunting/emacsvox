;;; emacsvox-docs-check-tests.el --- Documentation gate tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Focused tests for deterministic documentation validation and publication.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-docs-check)

(cl-defmacro emacsvox-docs-check-tests--with-directory
    ((directory) &rest body)
  "Create temporary DIRECTORY and run BODY, then remove it."
  (declare (indent 1) (debug (sexp body)))
  `(let ((,directory (make-temp-file "emacsvox-docs-check-test-" t)))
     (unwind-protect
         (progn ,@body)
       (delete-directory ,directory t))))

(ert-deftest emacsvox-docs-check-rejects-generated-drift ()
  "A changed generated artifact should name the stale checked file."
  (emacsvox-docs-check-tests--with-directory (directory)
    (let ((expected (expand-file-name "docs.texi" directory))
          (actual (expand-file-name "generated.texi" directory)))
      (with-temp-file expected (insert "tracked\n"))
      (with-temp-file actual (insert "changed\n"))
      (let ((condition
             (should-error
              (emacsvox-docs-check--compare-file
               expected actual "Generated reference docs.texi"))))
        (should
         (string-match-p
          "Generated reference docs.texi is stale"
          (error-message-string condition)))))))

(ert-deftest emacsvox-docs-check-rejects-successful-process-warnings ()
  "A publication warning should fail even when makeinfo exits zero."
  (let ((condition
         (should-error
          (emacsvox-docs-check--validate-process-result
           "HTML compilation" 0
           "eat.texi:14: warning: no htmlxref.cnf entry found for `eat'"))))
    (let ((message (error-message-string condition)))
      (should (string-match-p "HTML compilation emitted diagnostics" message))
      (should (string-match-p "no htmlxref.cnf entry" message)))))

(ert-deftest emacsvox-docs-check-rejects-duplicate-texinfo-nodes ()
  "Actual Makeinfo duplicate-node diagnostics should fail the strict runner."
  (let ((makeinfo (executable-find "makeinfo")))
    (skip-unless makeinfo)
    (emacsvox-docs-check-tests--with-directory (directory)
      (with-temp-file (expand-file-name "duplicate.texi" directory)
        (insert
         "\\input texinfo\n"
         "@setfilename duplicate.info\n"
         "@node Top\n@top Duplicate fixture\n"
         "@menu\n* Same::\n@end menu\n"
         "@node Same\n@section First\n"
         "@node Same\n@section Second\n@bye\n"))
      (let ((condition
             (should-error
              (emacsvox-docs-check--run-process
               "Info fixture compilation" makeinfo directory nil
               "--output=duplicate.info" "duplicate.texi"))))
        (should
         (string-match-p
          "Info fixture compilation failed"
          (error-message-string condition)))))))

(ert-deftest emacsvox-docs-check-rejects-actual-html-xref-warning ()
  "An unresolved external-manual warning should fail actual HTML conversion."
  (let ((makeinfo (executable-find "makeinfo")))
    (skip-unless makeinfo)
    (emacsvox-docs-check-tests--with-directory (directory)
      (with-temp-file (expand-file-name "external.texi" directory)
        (insert
         "\\input texinfo\n"
         "@setfilename external.info\n"
         "@node Top\n@top External fixture\n"
         "See @xref{Top,,,missing-manual,Missing Manual}.\n@bye\n"))
      (let ((condition
             (should-error
              (emacsvox-docs-check--run-process
               "HTML fixture compilation" makeinfo directory nil
               "--html" "-c" "HTMLXREF_MODE=none"
               "--output=html" "external.texi"))))
        (let ((message (error-message-string condition)))
          (should
           (string-match-p "HTML fixture compilation emitted diagnostics"
                           message))
          (should (string-match-p "missing-manual" message)))))))

(ert-deftest emacsvox-docs-check-rejects-personal-generated-paths ()
  "Generated reference output should not expose a builder's home."
  (emacsvox-docs-check-tests--with-directory (directory)
    (let ((file (expand-file-name "docs.texi" directory)))
      (with-temp-file file
        (insert "Default Value: /home/build-user/private\n"))
      (let ((condition
             (should-error
              (emacsvox-docs-check--assert-portable-reference
               file "/srv/emacsvox" "/tmp/emacsvox-docs"))))
        (should
         (string-match-p
          "personal home path" (error-message-string condition)))))))

(ert-deftest emacsvox-docs-check-rejects-broken-public-local-links ()
  "A missing README-local target should report its source line and path."
  (emacsvox-docs-check-tests--with-directory (directory)
    (with-temp-file (expand-file-name "Readme.org" directory)
      (insert "#+title: Fixture\n\n[[file:missing.org][Missing]]\n"))
    (let ((condition
           (should-error
            (emacsvox-docs-check--check-local-links directory))))
      (should
       (string-match-p
        "Broken local link: Readme.org:3 -> missing.org"
        (error-message-string condition))))))

(ert-deftest emacsvox-docs-check-rejects-publication-inside-source-tree ()
  "Publication must not overwrite a directory in the Emacsvox checkout."
  (emacsvox-docs-check-tests--with-directory (directory)
    (make-directory (expand-file-name "html" directory))
    (let ((condition
           (should-error
            (emacsvox-docs-check--validated-publish-directory
             directory (expand-file-name "html" directory)))))
      (should
       (string-match-p
        "Refusing unsafe documentation publication directory"
        (error-message-string condition))))))

(ert-deftest emacsvox-docs-publish-removes-only-manifested-stale-html ()
  "Publishing should preserve unrelated HTML and remove only managed stale files."
  (emacsvox-docs-check-tests--with-directory (root)
    (emacsvox-docs-check-tests--with-directory (destination)
      (with-temp-file (expand-file-name "unrelated.html" destination)
        (insert "unrelated\n"))
      (with-temp-file (expand-file-name "old-generated.html" destination)
        (insert "old\n"))
      (emacsvox-docs-check--write-publish-manifest
       destination '("old-generated.html"))
      (cl-letf
          (((symbol-function 'emacsvox-docs-check--compile-html)
            (lambda (_root staging _makeinfo)
              (make-directory staging)
              (with-temp-file (expand-file-name "index.html" staging)
                (insert "new\n"))
              '("index.html"))))
        (let ((result (emacsvox-docs-publish destination root "makeinfo")))
          (should (equal result '(:written 1 :removed 1)))))
      (should (file-exists-p (expand-file-name "index.html" destination)))
      (should (file-exists-p (expand-file-name "unrelated.html" destination)))
      (should-not
       (file-exists-p (expand-file-name "old-generated.html" destination)))
      (should
       (equal
        (emacsvox-docs-check--read-publish-manifest destination)
        '("index.html"))))))

(ert-deftest emacsvox-docs-publish-rejects-symlinked-managed-output ()
  "Publishing must not overwrite a managed path through a symbolic link."
  (emacsvox-docs-check-tests--with-directory (root)
    (emacsvox-docs-check-tests--with-directory (destination)
      (emacsvox-docs-check-tests--with-directory (outside)
        (let ((protected (expand-file-name "protected.html" outside)))
          (with-temp-file protected
            (insert "protected\n"))
          (make-symbolic-link
           protected (expand-file-name "index.html" destination))
          (cl-letf
              (((symbol-function 'emacsvox-docs-check--compile-html)
                (lambda (_root staging _makeinfo)
                  (make-directory staging)
                  (with-temp-file (expand-file-name "index.html" staging)
                    (insert "generated\n"))
                  '("index.html"))))
            (let ((condition
                   (should-error
                    (emacsvox-docs-publish destination root "makeinfo"))))
              (should
               (string-match-p
                "Refusing symlinked documentation publication file"
                (error-message-string condition)))))
          (should
           (equal
            (with-temp-buffer
              (insert-file-contents protected)
              (buffer-string))
            "protected\n")))))))

(ert-deftest emacsvox-docs-pages-publish-rejects-dirty-source ()
  "Pages publication must identify and reject uncommitted source files."
  (cl-letf
      (((symbol-function 'emacsvox-docs-check--capture-process)
        (lambda (_label _program _directory &rest arguments)
          (if (member "status" arguments)
              " M Readme.org"
            (make-string 40 ?a)))))
    (let ((condition
           (should-error
            (emacsvox-docs-check--source-revision default-directory))))
      (should
       (string-match-p
        "Refusing Pages publication from an uncommitted source tree"
        (error-message-string condition))))))

(ert-deftest emacsvox-docs-pages-publish-writes-provenance ()
  "Pages publication should identify the exact source and local toolchain."
  (emacsvox-docs-check-tests--with-directory (root)
    (emacsvox-docs-check-tests--with-directory (destination)
      (let ((revision (make-string 40 ?a)))
        (cl-letf
            (((symbol-function 'emacsvox-docs-check--source-revision)
              (lambda (_root) revision))
             ((symbol-function 'emacsvox-docs-check--makeinfo-version)
              (lambda (_root _makeinfo) "texi2any (GNU texinfo) 7.2"))
             ((symbol-function 'emacsvox-docs-publish)
              (lambda (_destination _root _makeinfo)
                '(:written 387 :removed 0))))
          (let ((result
                 (emacsvox-docs-publish-pages
                  destination root "makeinfo")))
            (should (= (plist-get result :written) 387))
            (should (equal (plist-get result :source) revision))))
        (let ((marker (expand-file-name ".nojekyll" destination))
              (provenance
               (expand-file-name "emacsvox-source.txt" destination)))
          (should (file-exists-p marker))
          (should (zerop (file-attribute-size (file-attributes marker))))
          (with-temp-buffer
            (insert-file-contents provenance)
            (should (search-forward revision nil t))
            (should (search-forward emacs-version nil t))
            (should
             (search-forward "texi2any (GNU texinfo) 7.2" nil t))))))))

(ert-deftest emacsvox-docs-pages-publish-rejects-symlinked-metadata ()
  "Pages publication must not replace metadata through a symbolic link."
  (emacsvox-docs-check-tests--with-directory (root)
    (emacsvox-docs-check-tests--with-directory (destination)
      (emacsvox-docs-check-tests--with-directory (outside)
        (let ((protected (expand-file-name "protected" outside)))
          (with-temp-file protected
            (insert "protected\n"))
          (make-symbolic-link
           protected (expand-file-name ".nojekyll" destination))
          (let ((condition
                 (should-error
                  (emacsvox-docs-publish-pages
                   destination root "makeinfo"))))
            (should
             (string-match-p
              "Refusing symlinked Pages metadata file"
              (error-message-string condition))))
          (should
           (equal
            (with-temp-buffer
              (insert-file-contents protected)
              (buffer-string))
            "protected\n")))))))

(provide 'emacsvox-docs-check-tests)
;;; emacsvox-docs-check-tests.el ends here
