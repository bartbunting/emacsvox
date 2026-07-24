;;; emacsvox-helm-tests.el --- Helm advice tests -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'package)
(package-initialize)
(require 'helm-core)
(require 'helm-mode)
(require 'helm-net)

(load
 (expand-file-name
  "../lisp/emacsvox-helm.el"
  (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(ert-deftest emacsvox-helm-current-target-contracts ()
  "Every advised target exists with its current arguments."
  (dolist
      (entry
       '((helm-mode (&optional arg))
         (helm-google-suggest nil)
         (helm-recenter-top-bottom-other-window (&optional arg))
         (helm-yank-selection (arg))))
    (pcase-let ((`(,target ,arguments) entry))
      (should (equal (help-function-arglist target t) arguments)))))

(ert-deftest emacsvox-helm-advice-is-directly-registered ()
  "Helm advice uses native advice directly."
  (dolist (entry emacsvox-helm--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-helm-yank-feedback-is-target-aware ()
  "Only interactive Helm yanking announces the result."
  (let ((ems--interactive-fn-name 'helm-yank-selection)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events))))
      (emacsvox--advice-helm-mode-after)
      (emacsvox--advice-helm-yank-selection-after))
    (should (equal (nreverse events) '(yank-object line)))))

(provide 'emacsvox-helm-tests)
;;; emacsvox-helm-tests.el ends here
