;;; emacsvox-folding-tests.el --- Folding advice tests -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'package)
(package-initialize)
(require 'folding)

(load
 (expand-file-name
  "../lisp/emacsvox-folding.el"
  (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(ert-deftest emacsvox-folding-current-targets-exist ()
  "Every advised Folding target exists in the installed package."
  (dolist (target emacsvox-folding--advice-targets)
    (should (fboundp target))))

(ert-deftest emacsvox-folding-advice-is-directly-registered ()
  "Folding advice uses native advice directly."
  (dolist (target emacsvox-folding--advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-folding-open-feedback-is-target-aware ()
  "Only the matching interactive fold command produces feedback."
  (let ((ems--interactive-fn-name 'folding-show-all)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events))))
      (emacsvox--advice-folding-hide-current-subtree-after)
      (emacsvox--advice-folding-show-all-after))
    (should (equal (nreverse events) '(open-object line)))))

(provide 'emacsvox-folding-tests)
;;; emacsvox-folding-tests.el ends here
