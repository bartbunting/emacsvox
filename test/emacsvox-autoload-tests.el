;;; emacsvox-autoload-tests.el --- Autoload generation tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Verify the Emacs 31 loaddefs generation path.

;;; Code:

(require 'cl-lib)
(require 'ert)

(load
 (expand-file-name
  "../lisp/emacsvox-autoload.el"
  (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(defvar emacsvox-auto-autoloads-file)
(defvar emacsvox-lisp-directory)

(ert-deftest emacsvox-autoload-generation-uses-loaddefs-gen ()
  "Autoload generation calls the supported Emacs 31 API directly."
  (let ((emacsvox-lisp-directory "/tmp/emacsvox-lisp")
        (emacsvox-auto-autoloads-file "/tmp/emacsvox-loaddefs.el")
        observed)
    (cl-letf (((symbol-function 'loaddefs-generate)
               (lambda (&rest arguments)
                 (setq observed arguments)
                 'generated))
              ((symbol-function 'locate-library)
               (lambda (&rest _)
                 (error "Legacy loaddefs probe invoked")))
              ((symbol-function 'update-directory-autoloads)
               (lambda (&rest _)
                 (error "Legacy autoload generator invoked"))))
      (should (eq (emacsvox-auto-generate-autoloads) 'generated)))
    (should
     (equal
      observed
      '("/tmp/emacsvox-lisp" "/tmp/emacsvox-loaddefs.el")))))

(provide 'emacsvox-autoload-tests)
;;; emacsvox-autoload-tests.el ends here
