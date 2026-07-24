;;; emacsvox-eglot-tests.el --- Eglot advice tests -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'eglot)
(require 'eldoc)
(require 'ert)
(load
 (expand-file-name "../lisp/emacsvox-eglot.el"
                   (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(ert-deftest emacsvox-eglot-advice-is-directly-registered ()
  (dolist
      (target
       '(eglot-find-declaration
         eglot-find-implementation
         eglot-find-typeDefinition))
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (commandp target))
      (should (advice-member-p function target))))
  (should
   (advice-member-p
    #'emacsvox--advice-eldoc-doc-buffer-after
    'eldoc-doc-buffer))
  (should-not (fboundp 'eglot-help-at-point)))

(ert-deftest emacsvox-eglot-navigation-feedback-is-target-aware ()
  (let ((ems--interactive-fn-name 'eglot-find-implementation) events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events))))
      (emacsvox--advice-eglot-find-declaration-after)
      (emacsvox--advice-eglot-find-implementation-after))
    (should (equal (nreverse events) '(line large-movement)))))

(ert-deftest emacsvox-eglot-help-feedback-is-mode-scoped ()
  (let ((ems--interactive-fn-name 'eldoc-doc-buffer)
        (eldoc--doc-buffer (generate-new-buffer " *emacsvox-eglot-doc*"))
        events)
    (unwind-protect
        (cl-letf (((symbol-function 'emacsvox-icon)
                   (lambda (icon) (push icon events)))
                  ((symbol-function 'emacsvox-speak-buffer)
                   (lambda () (push (current-buffer) events))))
          (let ((eglot--managed-mode nil))
            (emacsvox--advice-eldoc-doc-buffer-after))
          (setq ems--interactive-fn-name 'eldoc-doc-buffer)
          (let ((eglot--managed-mode t))
            (emacsvox--advice-eldoc-doc-buffer-after))
          (should
           (equal (nreverse events)
                  (list 'help eldoc--doc-buffer))))
      (kill-buffer eldoc--doc-buffer))))

(provide 'emacsvox-eglot-tests)
