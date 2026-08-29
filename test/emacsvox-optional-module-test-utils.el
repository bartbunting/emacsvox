;;; emacsvox-optional-module-test-utils.el --- Optional module test helpers -*- lexical-binding: t; -*-

;;; Commentary:

;; Helpers for verifying optional integration modules in an isolated Emacs.

;;; Code:

(require 'ert)

(defconst emacsvox-optional-module-test--root-directory
  (expand-file-name
   "../" (file-name-directory (or load-file-name buffer-file-name)))
  "Emacsvox repository root used by optional module tests.")

(defun emacsvox-optional-module-test-load
    (module &optional before-form after-form)
  "Load MODULE in a clean child Emacs.
Evaluate BEFORE-FORM before loading and AFTER-FORM afterward.  Signal an ERT
failure containing the child output when the child exits unsuccessfully."
  (let* ((emacs (expand-file-name invocation-name invocation-directory))
         (lisp-directory
          (expand-file-name "lisp" emacsvox-optional-module-test--root-directory))
         (module-file (expand-file-name module lisp-directory))
         (arguments
          (append
           (list "-Q" "--batch" "-L" lisp-directory
                 "--eval" "(setq load-prefer-newer t)")
           (when before-form
             (list "--eval" (prin1-to-string before-form)))
           (list "-l" module-file)
           (when after-form
             (list "--eval" (prin1-to-string after-form))))))
    (with-temp-buffer
      (let ((status
             (apply #'call-process emacs nil (list (current-buffer) t) nil
                    arguments)))
        (unless (and (integerp status) (zerop status))
          (ert-fail
           (format "Clean Emacs failed loading %s (status %S):\n%s"
                   module status (buffer-string)))))))
  t)

(provide 'emacsvox-optional-module-test-utils)
;;; emacsvox-optional-module-test-utils.el ends here
