;;; emacsvox-elpher-tests.el --- Elpher advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'elpher)
(load (expand-file-name "../lisp/emacsvox-elpher.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-elpher-advice-is-current-and-direct ()
  "Current Elpher targets use native advice directly."
  (dolist (target emacsvox-elpher--advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-elpher-feedback-is-target-aware ()
  "Only the matching interactive Elpher command provides feedback."
  (let ((ems--interactive-fn-name 'elpher-go)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'mode-line events))))
      (emacsvox--advice-elpher-jump-after)
      (emacsvox--advice-elpher-go-after))
    (should (equal (nreverse events) '(mode-line open-object)))))

(provide 'emacsvox-elpher-tests)
;;; emacsvox-elpher-tests.el ends here
