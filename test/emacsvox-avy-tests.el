;;; emacsvox-avy-tests.el --- Avy advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'avy)
(load (expand-file-name "../lisp/emacsvox-avy.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-avy-advice-is-current-and-direct ()
  "Current Avy targets use native advice directly."
  (dolist (target emacsvox-avy--advice-targets)
    (let ((function (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (advice-member-p function target))))
  (should-not (fboundp 'avy-kill-ring-save)))

(ert-deftest emacsvox-avy-jump-feedback-is-target-aware ()
  "Only matching interactive Avy jumps speak."
  (let ((ems--interactive-fn-name 'avy-goto-line) events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events))))
      (emacsvox--advice-avy-goto-char-after)
      (emacsvox--advice-avy-goto-line-after))
    (should (equal (nreverse events) '(large-movement line)))))

(provide 'emacsvox-avy-tests)
;;; emacsvox-avy-tests.el ends here
