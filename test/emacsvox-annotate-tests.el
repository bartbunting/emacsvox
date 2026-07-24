;;; emacsvox-annotate-tests.el --- Annotate advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'annotate)
(load (expand-file-name "../lisp/emacsvox-annotate.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-annotate-advice-is-current-and-direct ()
  "Every Annotate target exists and uses native advice directly."
  (dolist (target emacsvox-annotate--advice-targets)
    (let ((function (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-annotate-add-feedback-is-target-aware ()
  "Annotation creation is announced only interactively."
  (let ((ems--interactive-fn-name 'annotate-annotate) events)
    (cl-letf (((symbol-function 'dtk-notify)
               (lambda (text) (push text events))))
      (emacsvox--advice-annotate-annotate-after))
    (should (equal events '("Added annotation")))))

(provide 'emacsvox-annotate-tests)
;;; emacsvox-annotate-tests.el ends here
