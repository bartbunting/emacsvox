;;; emacsvox-docs-check-tests.el --- Documentation gate tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Focused tests for deterministic documentation validation and publication.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-docs-check)
(require 'emacsvox-org-export)

(cl-defmacro emacsvox-docs-check-tests--with-directory
    ((directory) &rest body)
  "Create temporary DIRECTORY and run BODY, then remove it."
  (declare (indent 1) (debug (sexp body)))
  `(let ((,directory (make-temp-file "emacsvox-docs-check-test-" t)))
     (unwind-protect
         (progn ,@body)
       (delete-directory ,directory t))))

(cl-defmacro emacsvox-docs-check-tests--without-live-export-feedback
    (&rest body)
  "Run BODY without optional Emacsvox Org export-completion feedback."
  (declare (indent 0) (debug body))
  `(if (not (fboundp 'emacsvox-org--submit-message-feedback))
       (progn ,@body)
     (cl-letf
         (((symbol-function 'emacsvox-org--submit-message-feedback)
           (lambda (&rest _arguments) nil)))
       ,@body)))

(ert-deftest emacsvox-org-export-requires-batch-environment ()
  "The batch exporter should identify a missing source setting."
  (let ((process-environment (copy-sequence process-environment)))
    (setenv "EMACSVOX_ORG_SOURCE" nil)
    (should-error
     (emacsvox-org-export--required-environment "EMACSVOX_ORG_SOURCE")
     :type 'error)))

(ert-deftest emacsvox-org-export-preserves-alternate-node-title ()
  "An Org printed heading may retain a stable Info node name."
  (emacsvox-docs-check-tests--with-directory (directory)
    (let ((source (expand-file-name "manual.org" directory))
          (output (expand-file-name "build/manual.texi" directory)))
      (with-temp-file source
        (insert "#+title: Test Manual\n"
                "#+texinfo_filename: test.info\n\n"
                "* Friendly Printed Chapter\n"
                ":PROPERTIES:\n"
                ":ALT_TITLE: Stable Info Node\n"
                ":END:\n\n"
                "Text.\n"))
      (emacsvox-docs-check-tests--without-live-export-feedback
        (emacsvox-org-export source output))
      (with-temp-buffer
        (insert-file-contents output)
        (should (search-forward "@node Stable Info Node" nil t))
        (should (search-forward "@chapter Friendly Printed Chapter" nil t))))))

(ert-deftest emacsvox-org-export-preserves-exact-node-names ()
  "TEXINFO_NODE_NAME should preserve punctuation and historical spelling."
  (emacsvox-docs-check-tests--with-directory (directory)
    (let ((source (expand-file-name "manual.org" directory))
          (output (expand-file-name "manual.texi" directory)))
      (with-temp-file source
        (insert "#+title: Test Manual\n"
                "#+texinfo_filename: test.info\n\n"
                "* Friendly Heading\n"
                ":PROPERTIES:\n"
                ":TEXINFO_NODE_NAME: Stable node.\n"
                ":END:\n\nText.\n"))
      (emacsvox-docs-check-tests--without-live-export-feedback
        (emacsvox-org-export source output))
      (with-temp-buffer
        (insert-file-contents output)
        (should (search-forward "@node Stable node." nil t))))))

(ert-deftest emacsvox-org-export-supports-structural-non-node-headings ()
  "TEXINFO_NODE=no should omit both the node and automatic menu entry."
  (emacsvox-docs-check-tests--with-directory (directory)
    (let ((source (expand-file-name "manual.org" directory))
          (output (expand-file-name "manual.texi" directory)))
      (with-temp-file source
        (insert "#+title: Test Manual\n"
                "#+texinfo_filename: test.info\n\n"
                "* Chapter\n\n"
                "** Structural Detail\n"
                ":PROPERTIES:\n:TEXINFO_NODE: no\n:END:\n\nText.\n"))
      (emacsvox-docs-check-tests--without-live-export-feedback
        (emacsvox-org-export source output))
      (with-temp-buffer
        (insert-file-contents output)
        (should (search-forward "@section Structural Detail" nil t))
        (goto-char (point-min))
        (should-not (search-forward "@node Structural Detail" nil t))
        (goto-char (point-min))
        (should-not (search-forward "* Structural Detail::" nil t))))))

(ert-deftest emacsvox-org-export-can-write-a-release-body ()
  "A body-only export should omit the standalone Texinfo wrapper."
  (emacsvox-docs-check-tests--with-directory (directory)
    (let ((source (expand-file-name "manual.org" directory))
          (output (expand-file-name "manual.texi" directory)))
      (with-temp-file source
        (insert "#+title: Test Manual\n"
                "#+texinfo_filename: test.info\n\n* Chapter\n\nText.\n"))
      (emacsvox-docs-check-tests--without-live-export-feedback
        (emacsvox-org-export source output t))
      (with-temp-buffer
        (insert-file-contents output)
        (should (search-forward "@node Chapter" nil t))
        (goto-char (point-min))
        (should-not (search-forward "\\input texinfo" nil t))
        (should-not (search-forward "@bye" nil t))))))

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

(ert-deftest emacsvox-docs-check-normalizes-checked-info-output ()
  "Checked Info output should not retain spaces or blank lines at EOF."
  (emacsvox-docs-check-tests--with-directory (directory)
    (let ((file (expand-file-name "manual.info" directory)))
      (with-temp-file file
        (insert "first  \nsecond\t\n\n"))
      (emacsvox-docs-check--normalize-info-file file)
      (should
       (equal
        (with-temp-buffer
          (insert-file-contents-literally file)
          (buffer-string))
        "first\nsecond\n")))))

(ert-deftest emacsvox-docs-check-normalizes-generated-html-lines ()
  "Generated HTML should be clean without changing its final blank lines."
  (emacsvox-docs-check-tests--with-directory (directory)
    (let ((file (expand-file-name "page.html" directory)))
      (with-temp-file file
        (insert "<p>first</p>  \n<p>&nbsp;</p> \n\n"))
      (emacsvox-docs-check--normalize-generated-text-file file)
      (should
       (equal
        (with-temp-buffer
          (insert-file-contents-literally file)
          (buffer-string))
        "<p>first</p>\n<p>&nbsp;</p>\n\n")))))

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

(ert-deftest emacsvox-docs-check-publishes-standalone-html-below-heritage ()
  "A retained standalone manual should render as one nested HTML file."
  (let ((makeinfo (executable-find "makeinfo")))
    (skip-unless makeinfo)
    (emacsvox-docs-check-tests--with-directory (source)
      (emacsvox-docs-check-tests--with-directory (output)
        (let ((texinfo (expand-file-name "standalone.texi" source))
              (htmlxref (expand-file-name "htmlxref.cnf" source)))
          (with-temp-file texinfo
            (insert
             "\\input texinfo\n"
             "@setfilename standalone.info\n"
             "@node Top\n@top Standalone fixture\n@bye\n"))
          (with-temp-file htmlxref)
          (should
           (equal
            (emacsvox-docs-check--compile-html-manual
             source output makeinfo htmlxref
             '(:name "standalone"
               :source "standalone.texi"
               :html-file "heritage/standalone.html"))
            '("heritage/standalone.html")))
          (should
           (file-regular-p
            (expand-file-name "heritage/standalone.html" output)))
          (should-not
           (file-exists-p (expand-file-name "heritage/index.html" output))))))))

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
    (with-temp-file (expand-file-name "README.org" directory)
      (insert "#+title: Fixture\n\n[[file:missing.org][Missing]]\n"))
    (let ((condition
           (should-error
            (emacsvox-docs-check--check-local-links directory))))
      (should
       (string-match-p
        "Broken local link: README.org:3 -> missing.org"
        (error-message-string condition))))))

(ert-deftest emacsvox-docs-check-rejects-broken-manual-chapter-links ()
  "Every maintained Org chapter should participate in local-link checks."
  (emacsvox-docs-check-tests--with-directory (directory)
    (make-directory (expand-file-name "docs/manual/chapters" directory) t)
    (with-temp-file
        (expand-file-name "docs/manual/chapters/example.org" directory)
      (insert "* Chapter\n\n[[file:missing.org][Missing]]\n"))
    (let* ((emacsvox-docs-check--public-org-entry-files nil)
           (condition
           (should-error
            (emacsvox-docs-check--check-local-links directory))))
      (should
       (string-match-p
        "Broken local link: docs/manual/chapters/example.org:3 -> missing.org"
        (error-message-string condition))))))

(ert-deftest emacsvox-docs-check-rejects-broken-developer-links ()
  "Maintained developer Org sources should participate in local-link checks."
  (emacsvox-docs-check-tests--with-directory (directory)
    (make-directory (expand-file-name "docs/developer" directory) t)
    (with-temp-file (expand-file-name "docs/developer/example.org" directory)
      (insert "* Developer chapter\n\n[[file:missing.org][Missing]]\n"))
    (let* ((emacsvox-docs-check--public-org-entry-files nil)
           (condition
            (should-error
             (emacsvox-docs-check--check-local-links directory))))
      (should
       (string-match-p
        "Broken local link: docs/developer/example.org:3 -> missing.org"
        (error-message-string condition))))))

(ert-deftest emacsvox-docs-check-ignores-editor-transient-org-files ()
  "Org lock and backup files should not become public documentation inputs."
  (emacsvox-docs-check-tests--with-directory (directory)
    (let ((chapter-directory
           (expand-file-name "docs/manual/chapters" directory)))
      (make-directory chapter-directory t)
      (with-temp-file (expand-file-name "example.org" chapter-directory)
        (insert "* Chapter\n"))
      (make-symbolic-link
       "editor@host.123:456"
       (expand-file-name ".#example.org" chapter-directory))
      (with-temp-file (expand-file-name "#example.org#" chapter-directory)
        (insert "* Backup\n"))
      (let* ((emacsvox-docs-check--public-org-entry-files nil)
             (files (emacsvox-docs-check--public-org-files directory)))
        (should (equal files '("docs/manual/chapters/example.org")))))))

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

(ert-deftest emacsvox-docs-publish-copies-nested-manual-output ()
  "Publishing should preserve the selected manual directory topology."
  (emacsvox-docs-check-tests--with-directory (root)
    (emacsvox-docs-check-tests--with-directory (destination)
      (cl-letf
          (((symbol-function 'emacsvox-docs-check--compile-html)
            (lambda (_root staging _makeinfo)
              (make-directory (expand-file-name "reference" staging) t)
              (with-temp-file (expand-file-name "index.html" staging)
                (insert "user\n"))
              (with-temp-file
                  (expand-file-name "reference/index.html" staging)
                (insert "reference\n"))
              (make-directory (expand-file-name "heritage" staging) t)
              (with-temp-file
                  (expand-file-name "heritage/index.html" staging)
                (insert "heritage\n"))
              '("heritage/index.html" "index.html"
                "reference/index.html"))))
        (let ((result (emacsvox-docs-publish destination root "makeinfo")))
          (should (equal result '(:written 3 :removed 0)))))
      (should (file-exists-p (expand-file-name "index.html" destination)))
      (should
       (file-exists-p
        (expand-file-name "reference/index.html" destination)))
      (should
       (file-exists-p
        (expand-file-name "heritage/index.html" destination)))
      (should
       (equal
        (emacsvox-docs-check--read-publish-manifest destination)
        '("heritage/index.html" "index.html"
          "reference/index.html"))))))

(ert-deftest emacsvox-docs-check-and-publish-reuses-validated-html ()
  "Release publication should copy the HTML produced by its validation pass."
  (emacsvox-docs-check-tests--with-directory (root)
    (emacsvox-docs-check-tests--with-directory (destination)
      (let ((prepare-count 0))
        (cl-letf
            (((symbol-function 'emacsvox-docs-check--prepare)
              (lambda (_root temporary-directory _makeinfo _install-info)
                (setq prepare-count (1+ prepare-count))
                (let ((staging
                       (expand-file-name "html" temporary-directory)))
                  (make-directory staging)
                  (with-temp-file (expand-file-name "index.html" staging)
                    (insert "validated\n"))
                  (list :html-directory staging
                        :generated '("index.html"))))))
          (should
           (equal
            (emacsvox-docs-check-and-publish
             destination root "makeinfo" "install-info")
            '(:written 1 :removed 0))))
        (should (= prepare-count 1))
        (should
         (equal
          (with-temp-buffer
            (insert-file-contents
             (expand-file-name "index.html" destination))
            (buffer-string))
          "validated\n"))))))

(ert-deftest emacsvox-docs-publish-rejects-manifest-traversal ()
  "Nested manual paths must not permit a manifest to escape publication."
  (emacsvox-docs-check-tests--with-directory (destination)
    (with-temp-file
        (expand-file-name ".emacsvox-generated-html" destination)
      (insert "reference/../outside.html\n"))
    (let ((condition
           (should-error
            (emacsvox-docs-check--read-publish-manifest destination))))
      (should
       (string-match-p
        "Unsafe entry in documentation publication manifest"
        (error-message-string condition))))))

(ert-deftest emacsvox-docs-publish-rejects-symlinked-manual-directory ()
  "Publishing must not enter a symbolic-link manual directory."
  (emacsvox-docs-check-tests--with-directory (root)
    (emacsvox-docs-check-tests--with-directory (destination)
      (emacsvox-docs-check-tests--with-directory (outside)
        (make-symbolic-link outside (expand-file-name "reference" destination))
        (cl-letf
            (((symbol-function 'emacsvox-docs-check--compile-html)
              (lambda (_root staging _makeinfo)
                (make-directory (expand-file-name "reference" staging) t)
                (with-temp-file
                    (expand-file-name "reference/index.html" staging)
                  (insert "generated\n"))
                '("reference/index.html"))))
          (let ((condition
                 (should-error
                  (emacsvox-docs-publish destination root "makeinfo"))))
            (should
             (string-match-p
              "Refusing symlinked documentation publication directory"
              (error-message-string condition)))))))))

(ert-deftest emacsvox-docs-compatibility-redirect-is-accessible-and-frozen ()
  "A moved node should retain only its inventoried root compatibility path."
  (emacsvox-docs-check-tests--with-directory (root)
    (emacsvox-docs-check-tests--with-directory (output)
      (make-directory (expand-file-name "etc" root))
      (make-directory (expand-file-name "reference" output))
      (with-temp-file (expand-file-name "etc/redirects.txt" root)
        (insert "Emacsvox-Keymaps.html\n"))
      (with-temp-file
          (expand-file-name "reference/Emacsvox-Keymaps.html" output)
        (insert "reference\n"))
      (let ((emacsvox-docs-check--compatibility-redirects
             '((:html-directory "reference"
                :inventory "etc/redirects.txt"))))
        (should
         (equal
          (emacsvox-docs-check--add-compatibility-redirects
           root output '("reference/Emacsvox-Keymaps.html"))
          '("Emacsvox-Keymaps.html"
            "reference/Emacsvox-Keymaps.html"))))
      (with-temp-buffer
        (insert-file-contents
         (expand-file-name "Emacsvox-Keymaps.html" output))
        (should
         (search-forward
          "content=\"0; url=reference/Emacsvox-Keymaps.html\"" nil t))
        (should
         (search-forward
          "href=\"reference/Emacsvox-Keymaps.html\"" nil t))))))

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
              " M README.org"
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
             ((symbol-function 'emacsvox-docs-check-and-publish)
              (lambda (_destination _root _makeinfo _install-info)
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
