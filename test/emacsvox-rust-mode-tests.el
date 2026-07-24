;;; emacsvox-rust-mode-tests.el --- Rust advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'rust-mode)
(require 'rustic)
(load (expand-file-name "../lisp/emacsvox-rust-mode.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-rust-mode-advice-is-current-and-direct ()
  "Every retained Rust target exists and bypasses the bridge."
  (dolist (target emacsvox-rust-mode--advice-targets)
    (let ((function (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target :after function) ems--modern-advice-wrappers))))
  (should-not (fboundp 'rustic-end-of-string)))

(ert-deftest emacsvox-rust-mode-navigation-is-target-aware ()
  "Only matching interactive Rust navigation speaks."
  (let ((ems--interactive-fn-name 'rust-beginning-of-defun) events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events))))
      (emacsvox--advice-rust-end-of-defun-after)
      (emacsvox--advice-rust-beginning-of-defun-after))
    (should (equal (nreverse events) '(large-movement line)))))

(provide 'emacsvox-rust-mode-tests)
;;; emacsvox-rust-mode-tests.el ends here
