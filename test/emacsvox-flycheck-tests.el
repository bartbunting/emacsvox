;;; emacsvox-flycheck-tests.el --- Flycheck advice tests -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'package)
(package-initialize)
(require 'flycheck)

(load
 (expand-file-name
  "../lisp/emacsvox-flycheck.el"
  (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(ert-deftest emacsvox-flycheck-current-targets-exist ()
  "Every advised Flycheck target exists."
  (dolist (entry emacsvox-flycheck--advice)
    (should (fboundp (car entry)))))

(ert-deftest emacsvox-flycheck-advice-is-directly-registered ()
  "Flycheck advice uses native advice directly."
  (dolist (entry emacsvox-flycheck--advice)
    (pcase-let ((`(,target ,function) entry))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-flycheck-navigation-is-target-aware ()
  "Only matching interactive Flycheck navigation speaks."
  (let ((ems--interactive-fn-name 'flycheck-next-error)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events))))
      (emacsvox--advice-flycheck-previous-error-after)
      (emacsvox--advice-flycheck-next-error-after))
    (should (equal (nreverse events) '(large-movement line)))))

(provide 'emacsvox-flycheck-tests)
;;; emacsvox-flycheck-tests.el ends here
