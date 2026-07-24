;;; emacsvox-spinner-tests.el --- Spinner advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated spinner advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(defconst emacsvox-test--spinner-direct-advice
  '((spinner-start :after emacsvox--advice-spinner-start-after)
    (spinner-stop :after emacsvox--advice-spinner-stop-after))
  "Spinner lifecycle functions using individually named native advice.")

(ert-deftest emacsvox-spinner-advice-is-directly-registered ()
  "Migrated spinner advice uses native advice directly."
  (dolist (entry emacsvox-test--spinner-direct-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-spinner-lifecycle-cues-are-unconditional ()
  "Spinner start and stop always produce their lifecycle cues."
  (let ((ems--interactive-fn-name nil)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-spinner-start-after)
      (emacsvox--advice-spinner-stop-after))
    (should
     (equal
      (nreverse events)
      '((icon repeat-start) (icon repeat-stop))))))

(provide 'emacsvox-spinner-tests)
;;; emacsvox-spinner-tests.el ends here
