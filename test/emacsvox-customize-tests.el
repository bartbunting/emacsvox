;;; emacsvox-customize-tests.el --- Customize advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Customize advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(defconst emacsvox-test--customize-direct-advice
  '((customize-save-variable :around
     emacsvox--advice-customize-save-variable-around))
  "Customize functions using individually named native advice.")

(ert-deftest emacsvox-customize-advice-is-directly-registered ()
  "Migrated Customize advice uses native advice directly."
  (dolist (entry emacsvox-test--customize-direct-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target))))
  (should
   (advice-member-p
    (if (featurep 'emacsvox-custom)
        #'emacsvox-custom--advice-customize-after
      #'emacsvox--advice-customize-after)
    'customize)))

(ert-deftest emacsvox-customize-feedback-is-target-aware ()
  "Only an interactive Customize command produces status feedback."
  (let ((ems--interactive-fn-name 'customize)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'speak-mode-line events))))
      (emacsvox--advice-customize-after))
    (should
     (equal
      (nreverse events)
      '((icon open-object) speak-mode-line)))))

(ert-deftest emacsvox-customize-save-variable-runs-quietly-once ()
  "Saving a variable preserves arguments, result, and dynamic state."
  (let ((emacsvox-speak-messages t)
        (inhibit-message nil)
        (tts-quiet nil)
        (calls 0)
        observed-state)
    (should
     (eq
      (emacsvox--advice-customize-save-variable-around
       (lambda (&rest arguments)
         (cl-incf calls)
         (setq observed-state
               (list arguments emacsvox-speak-messages
                     inhibit-message tts-quiet))
         'saved)
       'variable 'value "comment")
      'saved))
    (should (= calls 1))
    (should
     (equal
      observed-state
      '((variable value "comment") nil t t)))
    (should emacsvox-speak-messages)
    (should-not inhibit-message)
    (should-not tts-quiet)))

(provide 'emacsvox-customize-tests)
;;; emacsvox-customize-tests.el ends here
