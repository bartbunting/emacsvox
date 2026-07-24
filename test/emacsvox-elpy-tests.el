;;; emacsvox-elpy-tests.el --- Elpy advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'elpy)
(load (expand-file-name "../lisp/emacsvox-elpy.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-elpy-advice-is-current-and-direct ()
  "Current Elpy targets use native advice directly."
  (dolist (target emacsvox-elpy--advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target :after function) ems--modern-advice-wrappers))))
  (dolist (target emacsvox-elpy--removed-targets)
    (should-not (fboundp target))))

(ert-deftest emacsvox-elpy-feedback-is-target-aware ()
  "Only the matching interactive Elpy movement command speaks."
  (let ((ems--interactive-fn-name 'elpy-goto-definition)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events))))
      (emacsvox--advice-elpy-flymake-next-error-after)
      (emacsvox--advice-elpy-goto-definition-after))
    (should (equal (nreverse events) '(large-movement line)))))

(ert-deftest emacsvox-elpy-uses-current-statement-command ()
  "The current Elpy statement-and-step command receives advice."
  (should (memq 'elpy-shell-send-statement-and-step
                emacsvox-elpy--task-targets))
  (should-not (memq 'elpy-shell-send-current-statement
                    emacsvox-elpy--task-targets)))

(provide 'emacsvox-elpy-tests)
;;; emacsvox-elpy-tests.el ends here
