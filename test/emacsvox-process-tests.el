;;; emacsvox-process-tests.el --- Process advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated process advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(defconst emacsvox-test--process-direct-advice
  '((process-menu-delete-process :after
     emacsvox--advice-process-menu-delete-process-after)
    (list-processes :after emacsvox--advice-list-processes-after))
  "Process functions using individually defined native advice.")

(ert-deftest emacsvox-process-advice-is-directly-registered ()
  "Migrated process advice bypasses the compatibility bridge."
  (dolist (entry emacsvox-test--process-direct-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target where function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-process-delete-feedback-preserves-order ()
  "Interactive process deletion plays its icon before speaking the line."
  (let ((ems--interactive-fn-name 'process-menu-delete-process)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events))))
      (emacsvox--advice-process-menu-delete-process-after))
    (should
     (equal
      (nreverse events)
      '((icon delete-object) speak-line)))))

(ert-deftest emacsvox-process-list-feedback-is-target-aware ()
  "Only an interactive process-list command announces the displayed list."
  (let ((ems--interactive-fn-name 'list-processes)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push
                  (apply #'format format-string arguments)
                  events))))
      (emacsvox--advice-process-menu-delete-process-after)
      (emacsvox--advice-list-processes-after))
    (should
     (equal
      (nreverse events)
      '((icon open-object)
        "Displayed process list in other window.")))))

(provide 'emacsvox-process-tests)
;;; emacsvox-process-tests.el ends here
