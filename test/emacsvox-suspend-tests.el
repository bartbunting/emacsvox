;;; emacsvox-suspend-tests.el --- Suspend advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated suspend safety advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(ert-deftest emacsvox-suspend-advice-is-directly-registered ()
  "Migrated suspend advice bypasses the compatibility bridge."
  (should (fboundp 'emacsvox--advice-suspend-emacs-around))
  (should
   (advice-member-p
    #'emacsvox--advice-suspend-emacs-around 'suspend-emacs))
  (should-not
   (gethash
    '(suspend-emacs :around emacsvox--advice-suspend-emacs-around)
    ems--modern-advice-wrappers)))

(ert-deftest emacsvox-suspend-confirmation-calls-original-once ()
  "Confirmed suspension calls the original once with unchanged arguments."
  (let ((calls 0)
        events)
    (cl-letf (((symbol-function 'yes-or-no-p)
               (lambda (prompt)
                 (push (list 'question prompt) events)
                 t))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push
                  (list 'message
                        (apply #'format format-string arguments))
                  events))))
      (should
       (eq
        (emacsvox--advice-suspend-emacs-around
         (lambda (&rest arguments)
           (cl-incf calls)
           (push (list 'original arguments) events)
           'suspended)
         "display")
        'suspended)))
    (should (= calls 1))
    (should
     (equal
      (nreverse events)
      '((question "Do you want to suspend emacs ")
        (message "Suspending Emacs ")
        (original ("display")))))))

(ert-deftest emacsvox-suspend-refusal-skips-original ()
  "Refused suspension does not call the original and preserves the message result."
  (let ((calls 0)
        events)
    (cl-letf (((symbol-function 'yes-or-no-p)
               (lambda (prompt)
                 (push (list 'question prompt) events)
                 nil))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push
                  (list 'message
                        (apply #'format format-string arguments))
                  events)
                 'refused)))
      (should
       (eq
        (emacsvox--advice-suspend-emacs-around
         (lambda (&rest _)
           (cl-incf calls))
         "display")
        'refused)))
    (should (zerop calls))
    (should
     (equal
      (nreverse events)
      '((question "Do you want to suspend emacs ")
        (message "Not suspending emacs"))))))

(provide 'emacsvox-suspend-tests)
;;; emacsvox-suspend-tests.el ends here
