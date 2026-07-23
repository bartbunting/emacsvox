;;; emacsvox-vc-tests.el --- Version-control advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated version-control advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(defconst emacsvox-test--vc-direct-advice
  '((vc-toggle-read-only :around
     emacsvox--advice-vc-toggle-read-only-around)
    (vc-next-action :around emacsvox--advice-vc-next-action-around))
  "Version-control functions using individually defined native advice.")

(ert-deftest emacsvox-vc-advice-is-directly-registered ()
  "Migrated VC advice bypasses the compatibility bridge."
  (dolist (entry emacsvox-test--vc-direct-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target where function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-vc-toggle-advice-calls-original-once ()
  "An interactive VC toggle uses pre-call state and preserves the result."
  (with-temp-buffer
    (setq buffer-read-only t)
    (setq-local vc-mode " Git-42")
    (let ((ems--interactive-fn-name 'vc-toggle-read-only)
          (calls 0)
          events)
      (cl-letf (((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events)))
                ((symbol-function 'message)
                 (lambda (format-string &rest arguments)
                   (push
                    (list 'message
                          (apply #'format format-string arguments))
                    events))))
        (should
         (eq
          (emacsvox--advice-vc-toggle-read-only-around
           (lambda (&rest arguments)
             (cl-incf calls)
             (push
              (list 'original arguments buffer-read-only)
              events)
             (setq buffer-read-only nil)
             'toggle-result)
           'argument)
          'toggle-result)))
      (should (= calls 1))
      (should
       (equal
        (nreverse events)
        '((icon open-object)
          (original (argument) t)
          (message "Checking out previous  version 42 ")))))))

(ert-deftest emacsvox-vc-next-action-advice-calls-original-once ()
  "An interactive next VC action uses pre-call state and preserves its result."
  (with-temp-buffer
    (setq buffer-read-only nil)
    (setq-local vc-mode " Git-42")
    (let ((ems--interactive-fn-name 'vc-next-action)
          (calls 0)
          events)
      (cl-letf (((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events)))
                ((symbol-function 'message)
                 (lambda (format-string &rest arguments)
                   (push
                    (list 'message
                          (apply #'format format-string arguments))
                    events))))
        (should
         (eq
          (emacsvox--advice-vc-next-action-around
           (lambda (&rest arguments)
             (cl-incf calls)
             (push
              (list 'original arguments buffer-read-only)
              events)
             (setq buffer-read-only t)
             'action-result)
           'argument)
          'action-result)))
      (should (= calls 1))
      (should
       (equal
        (nreverse events)
        '((icon open-object)
          (original (argument) nil)
          (message "Checking  in new  version 42 ")))))))

(ert-deftest emacsvox-vc-action-advice-is-quiet-programmatically ()
  "A programmatic VC action calls once without auditory feedback."
  (let ((ems--interactive-fn-name nil)
        (calls 0)
        feedback)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (&rest _) (setq feedback t)))
              ((symbol-function 'message)
               (lambda (&rest _) (setq feedback t))))
      (should
       (eq
        (emacsvox--advice-vc-next-action-around
         (lambda (&rest _)
           (cl-incf calls)
           'action-result))
        'action-result)))
    (should (= calls 1))
    (should-not feedback)))

(provide 'emacsvox-vc-tests)
;;; emacsvox-vc-tests.el ends here
