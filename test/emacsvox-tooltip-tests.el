;;; emacsvox-tooltip-tests.el --- Tooltip advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated tooltip advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(defconst emacsvox-test--tooltip-direct-advice
  '((tooltip-show-help :around
     emacsvox--advice-tooltip-show-help-around)
    (tooltip-show-help-non-mode :around
     emacsvox--advice-tooltip-show-help-non-mode-around)
    (tooltip-show-help-non-mode :after
     emacsvox--advice-tooltip-show-help-non-mode-after)
    (tooltip-sho :after emacsvox--advice-tooltip-sho-after))
  "Tooltip functions using individually named native advice.")

(ert-deftest emacsvox-tooltip-advice-is-directly-registered ()
  "Migrated tooltip advice bypasses the compatibility bridge."
  (dolist (entry emacsvox-test--tooltip-direct-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target where function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-tooltip-around-preserves-one-silenced-call ()
  "Tooltip around advice calls once, quietly, then speaks and returns."
  (let ((emacsvox-speak-tooltips t)
        (emacsvox-speak-messages t)
        (inhibit-message nil)
        (calls 0)
        events)
    (cl-letf (((symbol-function 'dtk-speak)
               (lambda (text) (push (list 'speak text) events))))
      (should
       (eq
        (emacsvox--advice-tooltip-show-help-around
         (lambda (&rest arguments)
           (cl-incf calls)
           (push
            (list 'original arguments
                  emacsvox-speak-messages inhibit-message)
            events)
           'tooltip-result)
         "Tooltip text")
        'tooltip-result)))
    (should (= calls 1))
    (should
     (equal
      (nreverse events)
      '((original ("Tooltip text") nil t)
        (speak "Tooltip text"))))
    (should emacsvox-speak-messages)
    (should-not inhibit-message)))

(ert-deftest emacsvox-tooltip-after-preserves-speech-and-icon-order ()
  "Tooltip after advice speaks its explicit text before the help icon."
  (let ((emacsvox-speak-tooltips t)
        events)
    (cl-letf (((symbol-function 'dtk-speak)
               (lambda (text) (push (list 'speak text) events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-tooltip-show-help-non-mode-after
       "Tooltip text"))
    (should
     (equal
      (nreverse events)
      '((speak "Tooltip text") (icon help))))))

(provide 'emacsvox-tooltip-tests)
;;; emacsvox-tooltip-tests.el ends here
