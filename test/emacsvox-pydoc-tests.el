;;; emacsvox-pydoc-tests.el --- Pydoc advice tests -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'package)
(package-initialize)
(require 'pydoc)

(load
 (expand-file-name
  "../lisp/emacsvox-pydoc.el"
  (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(ert-deftest emacsvox-pydoc-current-target-contract ()
  "Pydoc retains its current single-name argument."
  (should (equal (help-function-arglist 'pydoc t) '(name))))

(ert-deftest emacsvox-pydoc-advice-is-directly-registered ()
  "Pydoc advice uses native advice directly."
  (should
   (advice-member-p #'emacsvox--advice-pydoc-after 'pydoc)))

(ert-deftest emacsvox-pydoc-feedback-is-target-aware ()
  "Only an interactive Pydoc invocation announces help."
  (let ((ems--interactive-fn-name 'other-command)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-speak-buffer)
               (lambda () (push 'buffer events))))
      (emacsvox--advice-pydoc-after)
      (setq ems--interactive-fn-name 'pydoc)
      (emacsvox--advice-pydoc-after))
    (should (equal (nreverse events) '(help buffer)))))

(provide 'emacsvox-pydoc-tests)
;;; emacsvox-pydoc-tests.el ends here
