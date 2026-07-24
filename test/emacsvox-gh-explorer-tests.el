;;; emacsvox-gh-explorer-tests.el --- GitHub Explorer advice tests -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'package)
(package-initialize)
(require 'github-explorer)

(load
 (expand-file-name
  "../lisp/emacsvox-gh-explorer.el"
  (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(ert-deftest emacsvox-gh-explorer-current-target-contracts ()
  "GitHub Explorer advice follows the installed package API."
  (should
   (equal (help-function-arglist 'github-explorer t) '(&optional repo)))
  (should
   (equal (help-function-arglist 'github-explorer-at-point t) nil)))

(ert-deftest emacsvox-gh-explorer-advice-is-directly-registered ()
  "GitHub Explorer advice bypasses the compatibility bridge."
  (dolist (target emacsvox-gh-explorer--advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target :after function)
                ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-gh-explorer-feedback-is-target-aware ()
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

(ert-deftest emacsvox-gh-explorer-navigation-bindings-installed ()
  "The package mode map uses Emacsvox navigation commands."
  (should
   (eq
    (lookup-key github-explorer-mode-map "n")
    #'emacsvox-gh-explorer-next))
  (should
   (eq
    (lookup-key github-explorer-mode-map "p")
    #'emacsvox-gh-explorer-previous)))

(provide 'emacsvox-gh-explorer-tests)
;;; emacsvox-gh-explorer-tests.el ends here
