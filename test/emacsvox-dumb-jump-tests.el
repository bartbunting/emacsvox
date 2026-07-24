;;; emacsvox-dumb-jump-tests.el --- Dumb Jump advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'dumb-jump)
(load (expand-file-name "../lisp/emacsvox-dumb-jump.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-dumb-jump-advice-is-current-and-direct ()
  "Current Dumb Jump targets use native advice directly."
  (dolist (target emacsvox-dumb-jump--advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-dumb-jump-feedback-is-target-aware ()
  "Only the matching interactive Dumb Jump command speaks."
  (let ((ems--interactive-fn-name 'dumb-jump-go)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events))))
      (emacsvox--advice-dumb-jump-back-after)
      (emacsvox--advice-dumb-jump-go-after))
    (should (equal (nreverse events) '(line large-movement)))))

(provide 'emacsvox-dumb-jump-tests)
;;; emacsvox-dumb-jump-tests.el ends here
