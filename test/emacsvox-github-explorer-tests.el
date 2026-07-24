;;; emacsvox-github-explorer-tests.el --- GitHub Explorer advice tests -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'package)
(package-initialize)
(require 'github-explorer)

(load
 (expand-file-name
  "../lisp/emacsvox-github-explorer.el"
  (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(ert-deftest emacsvox-github-explorer-current-target-contracts ()
  "GitHub Explorer advice follows the installed package API."
  (should
   (equal (help-function-arglist 'github-explorer t) '(&optional repo)))
  (should
   (equal (help-function-arglist 'github-explorer-at-point t) nil)))

(ert-deftest emacsvox-github-explorer-advice-is-directly-registered ()
  "GitHub Explorer advice bypasses the compatibility bridge."
  (dolist (target emacsvox-github-explorer--advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target :after function)
                ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-github-explorer-feedback-is-target-aware ()
  "Only the matching interactive entry command announces its buffer."
  (let ((ems--interactive-fn-name 'github-explorer-at-point)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'mode-line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events))))
      (emacsvox--advice-github-explorer-after)
      (emacsvox--advice-github-explorer-at-point-after))
    (should (equal (nreverse events) '(mode-line open-object)))))

(ert-deftest emacsvox-github-explorer-navigation-bindings-installed ()
  "The package mode map uses Emacsvox navigation commands."
  (should
   (eq
    (lookup-key github-explorer-mode-map "n")
    #'emacsvox-github-explorer-next))
  (should
   (eq
    (lookup-key github-explorer-mode-map "p")
    #'emacsvox-github-explorer-previous)))

(provide 'emacsvox-github-explorer-tests)
;;; emacsvox-github-explorer-tests.el ends here
