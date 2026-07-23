;;; emacsvox-button-tests.el --- Button advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated button creation advice.

;;; Code:

(require 'ert)
(require 'emacsvox-advice)

(defconst emacsvox-test--button-direct-advice
  '((make-button :after emacsvox--advice-make-button-after)
    (make-text-button :after
     emacsvox--advice-make-text-button-after)
    (push-button :after emacsvox--advice-push-button-after))
  "Button creation functions using individually named native advice.")

(ert-deftest emacsvox-button-advice-is-directly-registered ()
  "Migrated button creation advice bypasses the compatibility bridge."
  (dolist (entry emacsvox-test--button-direct-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target where function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-button-advice-marks-explicit-range ()
  "Button creation feedback marks the native start and end range."
  (with-temp-buffer
    (insert "abcdef")
    (emacsvox--advice-make-button-after 2 5)
    (should (eq (get-text-property 2 'auditory-icon) 'button))
    (should-not (get-text-property 5 'auditory-icon))))

(ert-deftest emacsvox-button-advice-silently-ignores-invalid-range ()
  "The button marker preserves the legacy silent error handling."
  (with-temp-buffer
    (insert "abcdef")
    (should-not
     (emacsvox--advice-make-text-button-after "button" nil))
    (should-not (get-text-property 1 'auditory-icon))))

(ert-deftest emacsvox-push-button-feedback-is-target-aware ()
  "Only interactive button activation produces its auditory cue."
  (let ((ems--interactive-fn-name 'push-button)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-push-button-after))
    (should (equal events '((icon button))))))

(provide 'emacsvox-button-tests)
;;; emacsvox-button-tests.el ends here
