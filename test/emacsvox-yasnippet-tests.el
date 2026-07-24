;;; emacsvox-yasnippet-tests.el --- Yasnippet advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'yasnippet)
(load (expand-file-name "../lisp/emacsvox-yasnippet.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-yasnippet-advice-is-current-and-direct ()
  "Every Yasnippet target exists and bypasses the bridge."
  (dolist (target emacsvox-yasnippet--advice-targets)
    (let ((function (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-yasnippet-insert-feedback-is-target-aware ()
  "Snippet insertion announces only an interactive invocation."
  (let ((ems--interactive-fn-name 'yas-insert-snippet) events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events))))
      (emacsvox--advice-yas-insert-snippet-after))
    (should (equal (nreverse events) '(select-object line)))))

(provide 'emacsvox-yasnippet-tests)
;;; emacsvox-yasnippet-tests.el ends here
