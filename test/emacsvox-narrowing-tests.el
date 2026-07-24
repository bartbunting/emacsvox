;;; emacsvox-narrowing-tests.el --- Narrowing advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated narrowing advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)
(require 'which-func)

(defconst emacsvox-test--narrowing-direct-advice
  '((narrow-to-region :after
     emacsvox--advice-narrow-to-region-after)
    (narrow-to-page :after
     emacsvox--advice-narrow-to-page-after)
    (narrow-to-defun :after
     emacsvox--advice-narrow-to-defun-after)
    (widen :after emacsvox--advice-widen-after))
  "Narrowing commands using individually named native advice.")

(ert-deftest emacsvox-narrowing-advice-is-directly-registered ()
  "Migrated narrowing advice uses native advice directly."
  (dolist (entry emacsvox-test--narrowing-direct-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-page-narrowing-counts-accessible-restriction ()
  "Page narrowing reports accessible lines without requiring a mark."
  (with-temp-buffer
    (insert "one\ntwo\nthree\n")
    (save-restriction
      (narrow-to-region (point-min) 9)
      (set-marker (mark-marker) nil)
      (let ((ems--interactive-fn-name 'narrow-to-page)
            events)
        (cl-letf (((symbol-function 'emacsvox-icon)
                   (lambda (icon) (push (list 'icon icon) events)))
                  ((symbol-function 'message)
                   (lambda (format-string &rest arguments)
                     (push
                      (list 'message
                            (apply #'format format-string arguments))
                      events))))
          (emacsvox--advice-narrow-to-region-after
           (point-min) (point-max))
          (emacsvox--advice-narrow-to-page-after))
        (should
         (equal
          (nreverse events)
          '((icon mark-object)
            (message "Narrowed editing region to 2 lines"))))))))

(ert-deftest emacsvox-defun-narrowing-feedback-is-target-aware ()
  "Interactive defun narrowing reports its function after the mark icon."
  (let ((ems--interactive-fn-name 'narrow-to-defun)
        events)
    (cl-letf (((symbol-function 'which-function)
               (lambda () "sample-function"))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push
                  (list 'message
                        (apply #'format format-string arguments))
                  events))))
      (emacsvox--advice-widen-after)
      (emacsvox--advice-narrow-to-defun-after))
    (should
     (equal
      (nreverse events)
      '((icon mark-object)
        (message "Narrowed to function sample-function"))))))

(ert-deftest emacsvox-widen-feedback-preserves-order ()
  "Interactive widening emits its icon before the restoration message."
  (let ((ems--interactive-fn-name 'widen)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push
                  (list 'message
                        (apply #'format format-string arguments))
                  events))))
      (emacsvox--advice-widen-after))
    (should
     (equal
      (nreverse events)
      '((icon open-object)
        (message "You can now edit the entire buffer "))))))

(provide 'emacsvox-narrowing-tests)
;;; emacsvox-narrowing-tests.el ends here
