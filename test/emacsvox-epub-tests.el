;;; emacsvox-epub-tests.el --- EPUB integration tests -*- lexical-binding: t; -*-

;;; Commentary:

;; EPUB archive boundaries, saved filename compatibility and commands.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-reading-dom-tests)

(defvar locate-command)
(defvar locate-make-command-line)

(defun emacsvox-test--epub-create (directory name &optional omit-opf)
  "Create a small EPUB named NAME in DIRECTORY; optionally OMIT-OPF."
  (let* ((default-directory (file-name-as-directory directory))
         (book (expand-file-name name))
         (members
          `(("OPS/package.opf" . ,(concat "<package><metadata>"
                                        "<title>Fixture Book</title>"
                                        "<creator>Fixture Author</creator>"
                                        "</metadata></package>"))
            ("OPS/toc.ncx" . ,(concat "<ncx><navMap><navPoint>"
                                    "<content src=\"chapter one's [1].xhtml\"/>"
                                    "</navPoint></navMap></ncx>"))
            ("OPS/chapter one's [1].xhtml" . "<html><body><p>Fixture chapter.</p></body></html>"))))
    (make-directory (expand-file-name "OPS") t)
    (when omit-opf (setq members (cdr members)))
    (dolist (entry members)
      (with-temp-file (expand-file-name (car entry)) (insert (cdr entry))))
    (should (zerop (apply #'call-process "zip" nil nil nil
                         "-q" book (mapcar #'car members))))
    book))

(ert-deftest emacsvox-epub-legacy-filenames-decode-without-a-shell ()
  "Decode saved filename syntax without expansions or subprocesses."
  (cl-letf (((symbol-function 'shell-command-to-string)
             (lambda (&rest _) (ert-fail "Filename decoding invoked a shell"))))
    (dolist (file '("/tmp/plain.epub" "/tmp/a b's;$(printf expanded).epub"
                    "/tmp/back\\slash.epub" "/tmp/line\nbreak.epub"))
      (should (equal (emacsvox-epub-shell-unquote (shell-quote-argument file t))
                     file)))
    (should-error (emacsvox-epub-shell-unquote "missing;printf injected"))))

(ert-deftest emacsvox-epub-real-archive-handles-literal-and-legacy-paths ()
  "Read real metadata and chapter names through raw and legacy entry points."
  (skip-unless (and (executable-find "zip") emacsvox-epub-unzip
                    emacsvox-epub-zipinfo (libxml-available-p)))
  (let ((directory (make-temp-file "emacsvox-epub-" t)))
    (unwind-protect
        (let ((book (emacsvox-test--epub-create
                     directory "a book's;$cash.epub")))
          (cl-letf (((symbol-function 'shell-command)
                     (lambda (&rest _) (ert-fail "Archive reader invoked a shell")))
                    ((symbol-function 'shell-command-to-string)
                     (lambda (&rest _) (ert-fail "Archive reader invoked a shell"))))
            (dolist (name (list book (shell-quote-argument book)))
              (let ((epub (emacsvox-epub-make-epub name)))
                (should (equal (emacsvox-epub-path epub) book))
                (should (equal (emacsvox-epub-title epub) "Fixture Book"))
                (should (equal (emacsvox-epub-author epub) "Fixture Author"))
                (should (equal (emacsvox-epub-html epub) '("OPS/chapter one's [1].xhtml")))
                (should (equal (emacsvox-epub-navs epub) '("OPS/chapter one's [1].xhtml")))
                (with-current-buffer
                    (emacsvox-epub-get-contents epub "OPS/chapter one's [1].xhtml")
                  (unwind-protect
                      (should (string-match-p "Fixture chapter" (buffer-string)))
                    (kill-buffer)))))))
      (delete-directory directory t))))

(ert-deftest emacsvox-epub-native-legacy-filenames-decode-without-a-shell ()
  "Native Windows quoting round-trips without executing cmd."
  (let ((system-type 'windows-nt))
    (cl-letf (((symbol-function 'w32-shell-dos-semantics) (lambda () t)))
      (dolist (file '("C:/Books/a book.epub" "C:/Books/a%book!^.epub"
                      "C:\\Books\\a book.epub" "C:\\Books\\"))
        (should (equal (emacsvox-epub-shell-unquote (shell-quote-argument file))
                       file))))))

(ert-deftest emacsvox-epub-custom-archive-templates-receive-one-literal-path ()
  "Preserve explicit command templates while quoting the filename input."
  (skip-unless (and (not (eq system-type 'windows-nt)) (executable-find "sh")))
  (let* ((shell-file-name (executable-find "sh"))
         (shell-command-switch "-c")
         (file "/missing/a book';printf injected;#.epub")
         (emacsvox-epub-ls-command "printf '%%s\\n' %s")
         (emacsvox-epub-toc-command "printf '%%s\\n' %s")
         (emacsvox-epub-opf-command "printf '%%s\\n' %s"))
    (should (equal (emacsvox-epub-do-ls file) (list file)))
    (should (equal (emacsvox-epub-do-toc file) file))
    (should (equal (emacsvox-epub-do-opf file) file))))

(ert-deftest emacsvox-epub-dired-open-and-legacy-mark-use-the-same-book ()
  "Dired can open a literal filename and an old mark reuses its buffer."
  (skip-unless (and (executable-find "zip") emacsvox-epub-unzip
                    emacsvox-epub-zipinfo (libxml-available-p)))
  (let ((directory (make-temp-file "emacsvox-epub-" t))
        (eww-mode-hook nil)
        (emacsvox-eww-post-hook nil)
        output)
    (unwind-protect
        (save-window-excursion
          (let ((book (emacsvox-test--epub-create directory "a book's;$cash.epub")))
            (with-temp-buffer
              (setq major-mode 'dired-mode)
              (cl-letf (((symbol-function 'dired-get-filename) (lambda (&rest _) book))
                        ((symbol-function 'shell-command-to-string)
                         (lambda (&rest _) (ert-fail "Dired EPUB open invoked a shell")))
                        ((symbol-function 'emacsvox-speak-load-directory-settings) #'ignore)
                        ((symbol-function 'emacsvox-speak-mode-line) #'ignore)
                        ((symbol-function 'emacsvox-icon) #'ignore))
                (call-interactively #'emacsvox-epub-eww)
                (setq output (current-buffer))
                (should (string-match-p "Fixture[[:space:]]+chapter" (buffer-string)))
                (should (equal default-directory (file-name-as-directory directory)))
                (should (equal emacsvox-epub-this-epub book))
                (with-temp-buffer
                  (should
                   (emacsvox-eww-jump-to-mark
                    (make-emacsvox-eww-mark :type 'epub :book (shell-quote-argument book))))
                  (should (eq (current-buffer) output)))))))
      (when (buffer-live-p output) (kill-buffer output))
      (delete-directory directory t))))

(ert-deftest emacsvox-epub-raw-existing-filename-wins-over-legacy-decoding ()
  "A literal backslash in an existing filename must not open another book."
  (skip-unless (not (eq system-type 'windows-nt)))
  (let* ((directory (make-temp-file "emacsvox-epub-" t))
         (raw (expand-file-name "a\\ b.epub" directory))
         (other (expand-file-name "a b.epub" directory)))
    (unwind-protect
        (progn
          (with-temp-file raw)
          (with-temp-file other)
          (should (equal (emacsvox-epub--filename raw) raw)))
      (delete-directory directory t))))

(ert-deftest emacsvox-epub-archive-errors-retain-filename-and-failure ()
  "Missing archives and malformed metadata produce contextual errors."
  (skip-unless (and (executable-find "zip") emacsvox-epub-unzip
                    emacsvox-epub-zipinfo))
  (let* ((directory (make-temp-file "emacsvox-epub-" t))
         (missing (expand-file-name "missing;printf injected.epub" directory)))
    (unwind-protect
        (progn
          (let ((failure (should-error (emacsvox-epub-do-ls missing))))
            (should (string-match-p (regexp-quote missing)
                                    (error-message-string failure))))
          (let* ((book (emacsvox-test--epub-create directory "no-package.epub" t))
                 (failure (should-error (emacsvox-epub-make-epub book))))
            (should (string-match-p "No Package" (error-message-string failure)))
            (should (string-match-p (regexp-quote book) (error-message-string failure))))
          (let* ((default-directory (file-name-as-directory directory))
                 (book (emacsvox-test--epub-create directory "broken-package.epub")))
            (with-temp-file (expand-file-name "OPS/package.opf") (insert "<"))
            (should (zerop (call-process "zip" nil nil nil "-q" book "OPS/package.opf")))
            (let ((failure (should-error (emacsvox-epub-make-epub book))))
              (should (string-match-p "invalid XML" (error-message-string failure))))))
      (delete-directory directory t))))

(ert-deftest emacsvox-epub-bookshelf-retains-legacy-keys ()
  "An old bookshelf can be loaded, refreshed and saved without changing keys."
  (let* ((directory (make-temp-file "emacsvox-epub-" t))
         (emacsvox-epub-library-directory directory)
         (emacsvox-epub-db-file (expand-file-name "shelf.bsf" directory))
         (book (expand-file-name "a book's;$cash.epub" directory))
         (key (shell-quote-argument book))
         (emacsvox-epub-db (make-hash-table :test #'equal))
         (metadata (make-emacsvox-epub-metadata :title "Old title" :author "Old author")))
    (unwind-protect
        (progn
          (with-temp-file book)
          (puthash key metadata emacsvox-epub-db)
          (with-temp-file emacsvox-epub-db-file (prin1 emacsvox-epub-db (current-buffer)))
          (setq emacsvox-epub-db nil)
          (emacsvox-epub-bookshelf-load)
          (cl-letf (((symbol-function 'shell-command-to-string)
                     (lambda (&rest _) (ert-fail "Shelf refresh invoked a shell")))
                    ((symbol-function 'emacsvox-epub-make-epub)
                     (lambda (&rest _) (ert-fail "Existing book was reimported"))))
            (emacsvox-epub-bookshelf-update))
          (emacsvox-epub-bookshelf-save)
          (with-temp-buffer
            (insert-file-contents emacsvox-epub-db-file)
            (let ((saved (read (current-buffer))))
              (should (= 1 (hash-table-count saved)))
              (should (equal (gethash key saved) metadata)))))
      (delete-directory directory t))))

(ert-deftest emacsvox-epub-delete-decodes-only-the-selected-bookshelf-key ()
  "Deleting a bookshelf entry passes its literal filename to the file API."
  (let ((file "/tmp/a book's;$cash.epub") deleted)
    (with-temp-buffer
      (insert (propertize "Book" 'epub (shell-quote-argument file)))
      (goto-char (point-min))
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) t))
                ((symbol-function 'delete-file) (lambda (name &rest _) (setq deleted name)))
                ((symbol-function 'emacsvox-epub-bookshelf-refresh) #'ignore)
                ((symbol-function 'emacsvox-icon) #'ignore))
        (call-interactively #'emacsvox-epub-delete))
      (should (equal deleted file)))))

(ert-deftest emacsvox-epub-locate-uses-case-insensitive-command ()
  "EPUB Locate searches dynamically install a case-insensitive command."
  (let ((locate-command "plocate")
        observed)
    (cl-letf (((symbol-function 'locate-with-filter)
               (lambda (search-string filter &optional arg)
                 (setq observed
                       (list
                        search-string
                        filter
                        arg
                        (funcall locate-make-command-line search-string)))
                 'locate-result)))
      (should
       (eq
        (emacsvox-epub-locate-epubs "Accessible Emacs")
        'locate-result)))
    (should
     (equal
      observed
      '("Accessible Emacs"
        "\\.epub\\'"
        nil
        ("plocate" "-i" "Accessible Emacs"))))))

(provide 'emacsvox-epub-tests)
;;; emacsvox-epub-tests.el ends here
