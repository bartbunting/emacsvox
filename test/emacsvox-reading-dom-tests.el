;;; emacsvox-reading-dom-tests.el --- Reading DOM tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Regression coverage for Emacs 30.2 and newer DOM text extraction in reading clients.

;;; Code:

(require 'cl-lib)
(require 'ert)

(defconst emacsvox-test--reading-dom-root
  (expand-file-name
   "../"
   (file-name-directory (or load-file-name buffer-file-name)))
  "Emacsvox checkout root used by reading DOM tests.")

(dolist (module '("emacsvox-bookshare.el"
                  "emacsvox-epub.el"
                  "emacsvox-librivox.el"))
  (load
   (expand-file-name
    module
    (expand-file-name "lisp/" emacsvox-test--reading-dom-root))
   nil nil))

(defconst emacsvox-test--reading-dom-source-files
  '("lisp/emacsvox-bookshare.el"
    "lisp/emacsvox-epub.el"
    "lisp/emacsvox-eww.el"
    "lisp/emacsvox-librivox.el")
  "Source files migrated from obsolete DOM text APIs.")

(defun emacsvox-test--has-obsolete-dom-text-call-p (file)
  "Return non-nil when FILE uses obsolete dom-text or dom-texts."
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name file emacsvox-test--reading-dom-root))
    (emacs-lisp-mode)
    (goto-char (point-min))
    (catch 'found
      (while (re-search-forward "\\_<dom-texts?\\_>" nil t)
        (unless (save-excursion
                  (nth 8 (syntax-ppss (match-beginning 0))))
          (throw 'found t)))
      nil)))

(ert-deftest emacsvox-reading-dom-uses-supported-text-api ()
  "Reading clients contain no executable obsolete DOM text calls."
  (should-not
   (cl-remove-if-not
    #'emacsvox-test--has-obsolete-dom-text-call-p
    emacsvox-test--reading-dom-source-files)))

(ert-deftest emacsvox-reading-dom-fallback-preserves-text ()
  "Fallback keeps whitespace and order, ignores scripts/comments, and copies text."
  (let ((leaf (copy-sequence "single leaf")))
    (cl-letf (((symbol-function 'dom-inner-text) nil))
      (should (equal "" (emacsvox-dom-inner-text nil)))
      (should (equal " One\n two three "
                     (emacsvox-dom-inner-text
                      '(div nil " One\n" (b nil " two")
                            (script nil "hidden" (span nil "also hidden"))
                            (comment nil "hidden") " three "))))
      (let ((result (emacsvox-dom-inner-text `(p nil ,leaf))))
        (should (equal leaf result))
        (should-not (eq leaf result))))))

(ert-deftest emacsvox-reading-dom-fallback-matches-native ()
  "Compare the fallback with the native Emacs 31 implementation when available."
  (skip-unless (fboundp 'dom-inner-text))
  (dolist (node '(nil (p nil) (p nil "hello")
                 (div nil "one" (b nil "two") " three")
                 (p nil "a" (comment nil "hidden") (script nil "hidden") "b")
                 (script nil "root text") (comment nil "root comment")
                 (p nil (style nil "retained") (br nil) "\tend\n")))
    (let ((expected (dom-inner-text node)))
      (cl-letf (((symbol-function 'dom-inner-text) nil))
        (should (equal expected (emacsvox-dom-inner-text node)))))))

(ert-deftest emacsvox-bookshare-dom-text-decodes-entities ()
  "Bookshare extracts and decodes XML metadata text."
  (should
   (equal
    (emacsvox-bookshare-dom-clean-text
     '(result nil (title nil "Fish &amp; Chips"))
     'title)
    "Fish & Chips")))

(ert-deftest emacsvox-epub-dom-text-populates-metadata ()
  "EPUB construction extracts title and author with the current DOM API."
  (cl-letf (((symbol-function 'emacsvox-epub-do-ls)
             (lambda (&rest _)
               '("OPS/content.opf" "OPS/toc.ncx" "OPS/chapter.xhtml")))
            ((symbol-function 'emacsvox-epub-do-toc)
             (lambda (&rest _) "OPS/toc.ncx"))
            ((symbol-function 'emacsvox-epub-do-opf)
             (lambda (&rest _) "OPS/content.opf"))
            ((symbol-function 'emacsvox-epub-dom-from-archive)
             (lambda (&rest _)
               '(package nil
                         (metadata nil
                                   (title nil "Accessible Emacs")
                                   (creator nil "Ada Reader")))))
            ((symbol-function 'emacsvox-epub-nav-files)
             (lambda (&rest _) nil)))
    (let ((epub (emacsvox-epub-make-epub "book.epub")))
      (should (equal (emacsvox-epub-title epub) "Accessible Emacs"))
      (should (equal (emacsvox-epub-author epub) "Ada Reader")))))

(ert-deftest emacsvox-librivox-dom-text-names-playlist ()
  "Librivox derives a filesystem-safe playlist name from RSS text."
  (let ((rss
         (make-temp-file
          "emacsvox-librivox-" nil ".xml"
          "<rss><channel><title>Public Domain Book</title></channel></rss>"))
        (emacsvox-librivox-local-cache temporary-file-directory))
    (unwind-protect
        (cl-letf (((symbol-function 'emacsvox-librivox-ensure-cache)
                   #'ignore))
          (should
           (equal
            (file-name-nondirectory
             (emacsvox-librivox-get-m3u-name rss))
            "Public-Domain-Book.m3u")))
      (delete-file rss))))

(provide 'emacsvox-reading-dom-tests)
;;; emacsvox-reading-dom-tests.el ends here
