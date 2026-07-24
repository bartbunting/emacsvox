;;; emacsvox-combobulate-tests.el --- Combobulate advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'combobulate)
(load (expand-file-name "../lisp/emacsvox-combobulate.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-combobulate-advice-is-current-and-direct ()
  "Current Combobulate targets bypass the compatibility bridge."
  (dolist (target emacsvox-combobulate--advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target :after function) ems--modern-advice-wrappers))))
  (dolist (removed '(combobulate-navigate-backward
                     combobulate-navigate-down-list-maybe
                     combobulate-navigate-forward
                     combobulate-navigate-up-list-maybe))
    (should-not (fboundp removed))))

(ert-deftest emacsvox-combobulate-feedback-is-target-aware ()
  "Only the matching interactive Combobulate command speaks."
  (let ((ems--interactive-fn-name 'combobulate-navigate-next)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-combobulate-speak-line)
               (lambda () (push 'line events))))
      (emacsvox--advice-combobulate-navigate-previous-after)
      (emacsvox--advice-combobulate-navigate-next-after))
    (should (equal (nreverse events) '(select-object line)))))

(provide 'emacsvox-combobulate-tests)
;;; emacsvox-combobulate-tests.el ends here
