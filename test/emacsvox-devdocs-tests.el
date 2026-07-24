;;; emacsvox-devdocs-tests.el --- DevDocs advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'devdocs)
(load (expand-file-name "../lisp/emacsvox-devdocs.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-devdocs-advice-is-current-and-direct ()
  "Current DevDocs targets use native advice directly."
  (dolist (target emacsvox-devdocs--advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-devdocs-feedback-is-target-aware ()
  "Only the matching interactive DevDocs command speaks."
  (let ((ems--interactive-fn-name 'devdocs-search)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events))))
      (emacsvox--advice-devdocs-lookup-after)
      (emacsvox--advice-devdocs-search-after))
    (should (equal (nreverse events) '(open-object line)))))

(provide 'emacsvox-devdocs-tests)
;;; emacsvox-devdocs-tests.el ends here
