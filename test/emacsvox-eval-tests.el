;;; emacsvox-eval-tests.el --- Evaluation advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated evaluation advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(defconst emacsvox-test--eval-direct-advice
  '((eval-last-sexp :filter-return
     emacsvox--advice-eval-last-sexp-filter-return)
    (eval-expression :filter-return
     emacsvox--advice-eval-expression-filter-return))
  "Evaluation commands using individually named native advice.")

(ert-deftest emacsvox-eval-advice-is-directly-registered ()
  "Migrated evaluation advice bypasses the compatibility bridge."
  (dolist (entry emacsvox-test--eval-direct-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target where function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-eval-result-feedback-is-target-aware ()
  "Only the matching evaluation command speaks and returns its result."
  (let ((ems--interactive-fn-name 'eval-last-sexp)
        (dtk-punctuation-mode 'all)
        events)
    (cl-letf (((symbol-function 'dtk-speak)
               (lambda (text)
                 (push
                  (list 'speak text
                        dtk-punctuation-mode
                        dtk-chunk-separator-syntax)
                  events))))
      (should
       (eq
        (emacsvox--advice-eval-expression-filter-return
         'wrong-result)
        'wrong-result))
      (should
       (equal
        (emacsvox--advice-eval-last-sexp-filter-return '(a b))
        '(a b))))
    (should
     (equal
      events
      '((speak "(a b)" all " .<>()$\"'"))))))

(ert-deftest emacsvox-eval-result-is-quiet-programmatically ()
  "A programmatic evaluation result is returned without speech."
  (let ((ems--interactive-fn-name nil)
        feedback)
    (cl-letf (((symbol-function 'dtk-speak)
               (lambda (&rest _) (setq feedback t))))
      (should
       (eq
        (emacsvox--advice-eval-expression-filter-return
         'evaluation-result)
        'evaluation-result)))
    (should-not feedback)))

(provide 'emacsvox-eval-tests)
;;; emacsvox-eval-tests.el ends here
