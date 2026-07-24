;;; emacsvox-browser-tests.el --- Browser advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated browser advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(defconst emacsvox-test--browser-direct-advice
  '((browse-url-of-buffer :around
     emacsvox--advice-browse-url-of-buffer-around)
    (browse-url-of-region :around
     emacsvox--advice-browse-url-of-region-around))
  "Browser commands using individually named native advice.")

(ert-deftest emacsvox-browser-advice-is-directly-registered ()
  "Migrated browser advice uses native advice directly."
  (dolist (entry emacsvox-test--browser-direct-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-browser-interactive-call-preserves-order ()
  "Interactive browsing prepares speech before one original call."
  (let ((ems--interactive-fn-name 'browse-url-of-region)
        (calls 0)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-eww-autospeak)
               (lambda () (push 'autospeak events))))
      (should
       (eq
        (emacsvox--advice-browse-url-of-region-around
         (lambda (&rest arguments)
           (cl-incf calls)
           (push (list 'original arguments) events)
           'browse-result)
         2 7)
        'browse-result)))
    (should (= calls 1))
    (should
     (equal
      (nreverse events)
      '((icon open-object) autospeak (original (2 7)))))))

(ert-deftest emacsvox-browser-programmatic-call-is-quiet ()
  "Programmatic browsing calls once without speech preparation."
  (let ((ems--interactive-fn-name nil)
        (calls 0)
        feedback)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (&rest _) (setq feedback t)))
              ((symbol-function 'emacsvox-eww-autospeak)
               (lambda () (setq feedback t))))
      (should
       (eq
        (emacsvox--advice-browse-url-of-buffer-around
         (lambda (&rest _)
           (cl-incf calls)
           'browse-result))
        'browse-result)))
    (should (= calls 1))
    (should-not feedback)))

(provide 'emacsvox-browser-tests)
;;; emacsvox-browser-tests.el ends here
