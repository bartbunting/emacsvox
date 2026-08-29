;;; emacsvox-self-document-tests.el --- Generated reference tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Unit coverage for strict, portable generated-reference production.

;;; Code:

(require 'cl-lib)
(require 'ert)

(load
 (expand-file-name
  "../utils/self-document.el"
  (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(ert-deftest emacsvox-self-document-rejects-undeclared-load-errors ()
  "An unexpected manifested-module error should abort generation."
  (let ((self-document-files '("good.elc" "bad.elc"))
        (self-document-declared-module-omissions nil)
        (self-document-module-results nil)
        loaded)
    (cl-letf (((symbol-function 'load)
               (lambda (file &optional _noerror _nomessage _must-suffix)
                 (let ((module (file-name-nondirectory file)))
                   (if (string= module "bad.elc")
                       (error "fixture failure")
                     (push module loaded))))))
      (let ((condition
             (should-error
              (self-document--load-manifest-modules) :type 'error)))
        (should
         (string-match-p
          "bad.elc: fixture failure" (error-message-string condition)))))
    (should (equal loaded '("good.elc")))
    (should
     (equal self-document-module-results
            '((:module "good.elc" :status loaded :detail nil)
              (:module "bad.elc" :status failed
               :detail "fixture failure"))))))

(ert-deftest emacsvox-self-document-skips-only-declared-omissions ()
  "Declared omissions should be deterministic and visibly recorded."
  (let ((self-document-files '("good.elc" "optional.elc"))
        (self-document-declared-module-omissions
         '(("optional.elc" . "requires a fixture")))
        (self-document-module-results nil)
        loaded)
    (cl-letf (((symbol-function 'load)
               (lambda (file &optional _noerror _nomessage _must-suffix)
                 (push (file-name-nondirectory file) loaded))))
      (self-document--load-manifest-modules))
    (should (equal loaded '("good.elc")))
    (should
     (equal self-document-module-results
            '((:module "good.elc" :status loaded :detail nil)
              (:module "optional.elc" :status omitted
               :detail "requires a fixture"))))))

(ert-deftest emacsvox-self-document-sanitizes-identity-defaults ()
  "Identity-derived option defaults should use semantic placeholders."
  (let ((rendered
         (self-document--portable-default-value
          'emacsvox-mail-spool-file "/var/mail/private-login")))
    (should (string-match-p "<system-mail-spool>/<login>" rendered))
    (should-not (string-match-p "private-login" rendered))))

(ert-deftest emacsvox-self-document-failure-preserves-destination ()
  "A staged generation failure should not overwrite either tracked output."
  (let ((directory (make-temp-file "emacsvox-self-document-output-" t)))
    (unwind-protect
        (let ((default-directory directory))
          (with-temp-file (expand-file-name "docs.texi" directory)
            (insert "original docs\n"))
          (with-temp-file (expand-file-name "keys.texi" directory)
            (insert "original keys\n"))
          (cl-letf (((symbol-function 'self-document--generate-all-modules)
                     (lambda () (error "fixture failure"))))
            (should-error (self-document-all-modules) :type 'error))
          (should
           (string=
            (with-temp-buffer
              (insert-file-contents (expand-file-name "docs.texi" directory))
              (buffer-string))
            "original docs\n"))
          (should
           (string=
            (with-temp-buffer
              (insert-file-contents (expand-file-name "keys.texi" directory))
              (buffer-string))
            "original keys\n")))
      (delete-directory directory t))))

(provide 'emacsvox-self-document-tests)
;;; emacsvox-self-document-tests.el ends here
