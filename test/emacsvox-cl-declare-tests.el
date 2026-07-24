;;; emacsvox-cl-declare-tests.el --- cl-declare migration tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Keep Emacsvox source free of obsolete `cl-declare' forms and test the
;; conservative migration helper.

;;; Code:

(require 'ert)
(require 'remove-cl-declare)

(defconst emacsvox-test--cl-declare-root
  (expand-file-name
   "../"
   (file-name-directory (or load-file-name buffer-file-name)))
  "Emacsvox checkout root used by cl-declare migration tests.")

(defun emacsvox-test--cl-declare-source-files ()
  "Return repository Emacs Lisp source files checked for cl-declare."
  (cl-loop
   for directory in '("lisp" "utils" "scapes" "tvr")
   append
   (directory-files-recursively
    (expand-file-name directory emacsvox-test--cl-declare-root)
    "\\.el\\'")
   into files
   finally return
   (delete
    (expand-file-name
     "lisp/emacsvox-loaddefs.el" emacsvox-test--cl-declare-root)
    files)))

(defun emacsvox-test--buffer-has-executable-cl-declare-p ()
  "Return non-nil when the current buffer has an executable cl-declare form."
  (save-excursion
    (goto-char (point-min))
    (catch 'found
      (while (search-forward "(cl-declare" nil t)
        (unless (save-excursion
                  (nth 8 (syntax-ppss (match-beginning 0))))
          (throw 'found t)))
      nil)))

(defun emacsvox-test--executable-cl-declare-p (file)
  "Return non-nil when FILE contains an executable cl-declare form."
  (with-temp-buffer
    (insert-file-contents file)
    (emacs-lisp-mode)
    (emacsvox-test--buffer-has-executable-cl-declare-p)))

(ert-deftest emacsvox-cl-declare-repository-source-remains-clean ()
  "Repository source contains no executable cl-declare forms."
  (should-not
   (cl-remove-if-not
    #'emacsvox-test--executable-cl-declare-p
    (emacsvox-test--cl-declare-source-files))))

(ert-deftest emacsvox-cl-declare-migration-hoists-special-variables ()
  "The migration helper hoists, sorts, and deduplicates special variables."
  (with-temp-buffer
    (emacs-lisp-mode)
    (insert
     ";;; Code:\n\n"
     "(defun example ()\n"
     "  (cl-declare (special zebra alpha zebra))\n"
     "  (list alpha zebra))\n"
     ";; (cl-declare (warn 0))\n")
    (should (= 1 (remove-cl-declare-in-buffer)))
    (should-not (emacsvox-test--buffer-has-executable-cl-declare-p))
    (goto-char (point-min))
    (should (search-forward "(defvar alpha)" nil t))
    (should (search-forward "(defvar zebra)" nil t))
    (should (= 1 (how-many "^(defvar zebra)$" (point-min) (point-max))))
    (should (search-forward "(list alpha zebra)" nil t))))

(ert-deftest emacsvox-cl-declare-migration-rejects-other-declarations ()
  "The migration helper does not rewrite unrelated cl-declare forms."
  (with-temp-buffer
    (emacs-lisp-mode)
    (insert ";;; Code:\n(defun example () (cl-declare (warn 0)))\n")
    (should-error (remove-cl-declare-in-buffer))))

(provide 'emacsvox-cl-declare-tests)
;;; emacsvox-cl-declare-tests.el ends here
