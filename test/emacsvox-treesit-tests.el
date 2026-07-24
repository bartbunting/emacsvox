;;; emacsvox-treesit-tests.el --- Treesit advice tests -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'treesit)
(load
 (expand-file-name "../lisp/emacsvox-treesit.el"
                   (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(ert-deftest emacsvox-treesit-advice-is-directly-registered ()
  (dolist
      (target
       '(treesit-end-of-defun
         treesit-beginning-of-defun
         treesit-forward-sexp))
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (commandp target))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-treesit-feedback-is-target-aware ()
  (let ((ems--interactive-fn-name 'treesit-beginning-of-defun) events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events))))
      (emacsvox--advice-treesit-end-of-defun-after)
      (emacsvox--advice-treesit-beginning-of-defun-after)
      (emacsvox--advice-treesit-forward-sexp-after))
    (should
     (equal (nreverse events) '(large-movement line)))))

(provide 'emacsvox-treesit-tests)
