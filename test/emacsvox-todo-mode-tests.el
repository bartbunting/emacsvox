;;; emacsvox-todo-mode-tests.el --- Todo Mode advice tests -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'todo-mode)
(load
 (expand-file-name "../lisp/emacsvox-todo-mode.el"
                   (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(defconst emacsvox-test--todo-navigation-targets
  '(todo-forward-item
    todo-backward-item
    todo-next-item
    todo-previous-item
    todo-forward-category
    todo-backward-category
    todo-jump-to-category))

(ert-deftest emacsvox-todo-advice-is-directly-registered ()
  (dolist
      (target
       (append emacsvox-test--todo-navigation-targets
               '(todo-save todo-quit)))
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers))))
  (should-not (fboundp 'todo-next-category))
  (should-not (fboundp 'todo-previous-category)))

(ert-deftest emacsvox-todo-navigation-feedback-is-target-aware ()
  (let ((ems--interactive-fn-name 'todo-backward-category) events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events))))
      (emacsvox--advice-todo-forward-category-after)
      (emacsvox--advice-todo-backward-category-after))
    (should (equal (nreverse events) '(select-object line)))))

(ert-deftest emacsvox-todo-lifecycle-feedback-is-target-aware ()
  (let ((ems--interactive-fn-name 'todo-quit) events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'mode-line events))))
      (emacsvox--advice-todo-save-after)
      (emacsvox--advice-todo-quit-after))
    (should
     (equal (nreverse events) '(close-object mode-line)))))

(provide 'emacsvox-todo-mode-tests)
