;;; emacsvox-ivy-tests.el --- Ivy advice tests -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'package)
(package-initialize)
(require 'ivy)

(load
 (expand-file-name
  "../lisp/emacsvox-ivy.el"
  (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(ert-deftest emacsvox-ivy-current-targets-exist ()
  "Every advised Ivy target exists in the installed package."
  (dolist (entry emacsvox-ivy--advice)
    (should (fboundp (car entry)))))

(ert-deftest emacsvox-ivy-advice-is-directly-registered ()
  "Ivy advice bypasses the compatibility bridge."
  (dolist (entry emacsvox-ivy--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target where function)
                ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-ivy-read-uses-explicit-prompt ()
  "Ivy prompt advice uses its native PROMPT argument."
  (let (events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'dtk-speak)
               (lambda (text) (push text events))))
      (emacsvox--advice-ivy-read-before "Choose: " '(a b)))
    (should (equal (nreverse events) '(open-object "Choose: ")))))

(ert-deftest emacsvox-ivy-navigation-is-target-aware ()
  "Only matching interactive candidate navigation speaks."
  (let ((ems--interactive-fn-name 'ivy-next-line)
        events)
    (cl-letf (((symbol-function 'emacsvox-ivy-speak-selection)
               (lambda () (push 'selection events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events))))
      (emacsvox--advice-ivy-previous-line-after)
      (emacsvox--advice-ivy-next-line-after))
    (should (equal (nreverse events) '(selection select-object)))))

(provide 'emacsvox-ivy-tests)
;;; emacsvox-ivy-tests.el ends here
