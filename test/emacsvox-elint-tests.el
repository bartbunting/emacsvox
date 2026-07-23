;;; emacsvox-elint-tests.el --- Elint advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Elint advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(defconst emacsvox-test--elint-direct-advice
  '((elint-current-buffer :around
     emacsvox--advice-elint-current-buffer-around)
    (elint-file :around emacsvox--advice-elint-file-around)
    (elint-defun :around emacsvox--advice-elint-defun-around))
  "Elint commands using individually named native advice.")

(ert-deftest emacsvox-elint-advice-is-directly-registered ()
  "Migrated Elint advice bypasses the compatibility bridge."
  (dolist (entry emacsvox-test--elint-direct-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target where function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-elint-interactive-call-preserves-order ()
  "Interactive Elint calls once, quietly, then announces and returns."
  (let ((ems--interactive-fn-name 'elint-file)
        (emacsvox-speak-messages t)
        (inhibit-message nil)
        (calls 0)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon)
                 (push
                  (list 'icon icon
                        emacsvox-speak-messages inhibit-message)
                  events)))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push
                  (list 'message
                        (apply #'format format-string arguments)
                        emacsvox-speak-messages inhibit-message)
                  events))))
      (should
       (eq
        (emacsvox--advice-elint-file-around
         (lambda (&rest arguments)
           (cl-incf calls)
           (push
            (list 'original arguments
                  emacsvox-speak-messages inhibit-message)
            events)
           'elint-result)
         "example.el")
        'elint-result)))
    (should (= calls 1))
    (should
     (equal
      (nreverse events)
      '((original ("example.el") nil t)
        (icon task-done nil t)
        (message "Displayed lint results in other window. " nil t))))
    (should emacsvox-speak-messages)
    (should-not inhibit-message)))

(ert-deftest emacsvox-elint-programmatic-call-is-quiet ()
  "Programmatic Elint calls once without feedback."
  (let ((ems--interactive-fn-name nil)
        (calls 0)
        feedback)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (&rest _) (setq feedback t)))
              ((symbol-function 'message)
               (lambda (&rest _) (setq feedback t))))
      (should
       (eq
        (emacsvox--advice-elint-defun-around
         (lambda (&rest _)
           (cl-incf calls)
           'elint-result))
        'elint-result)))
    (should (= calls 1))
    (should-not feedback)))

(provide 'emacsvox-elint-tests)
;;; emacsvox-elint-tests.el ends here
