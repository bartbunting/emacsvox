;;; emacsvox-help-tests.el --- Help advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Help advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(defconst emacsvox-test--help-direct-advice
  '((describe-mode :after emacsvox--advice-describe-mode-after)
    (describe-repeat-maps :after
     emacsvox--advice-describe-repeat-maps-after)
    (describe-bindings :after
     emacsvox--advice-describe-bindings-after)
    (describe-prefix-bindings :after
     emacsvox--advice-describe-prefix-bindings-after)
    (isearch-describe-bindings :after
     emacsvox--advice-isearch-describe-bindings-after))
  "Help commands using individually named native advice.")

(ert-deftest emacsvox-help-advice-is-directly-registered ()
  "Migrated Help advice bypasses the compatibility bridge."
  (dolist (entry emacsvox-test--help-direct-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target where function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-describe-mode-feedback-preserves-order ()
  "Interactive mode help announces its message before the Help icon."
  (let ((ems--interactive-fn-name 'describe-mode)
        events)
    (cl-letf (((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push
                  (list 'message
                        (apply #'format format-string arguments))
                  events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-describe-repeat-maps-after)
      (emacsvox--advice-describe-mode-after))
    (should
     (equal
      (nreverse events)
      '((message "Displayed mode help") (icon help))))))

(ert-deftest emacsvox-describe-bindings-feedback-is-target-aware ()
  "Only the matching binding-description command announces its Help window."
  (let ((ems--interactive-fn-name 'describe-prefix-bindings)
        events)
    (cl-letf (((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push
                  (list 'message
                        (apply #'format format-string arguments))
                  events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-describe-bindings-after)
      (emacsvox--advice-describe-prefix-bindings-after))
    (should
     (equal
      (nreverse events)
      '((message "Displayed key bindings in help window")
        (icon help))))))

(provide 'emacsvox-help-tests)
;;; emacsvox-help-tests.el ends here
