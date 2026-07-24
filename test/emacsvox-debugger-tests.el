;;; emacsvox-debugger-tests.el --- Debugger advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Debugger advice.

;;; Code:

(require 'cl-lib)
(require 'ert)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-debugger.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--debugger-advice
  '((debugger-continue :after emacsvox--advice-debugger-continue-after)
    (backtrace-forward-frame
     :after emacsvox--advice-backtrace-forward-frame-after)
    (backtrace-backward-frame
     :after emacsvox--advice-backtrace-backward-frame-after)
    (debugger-eval-expression
     :filter-return
     emacsvox--advice-debugger-eval-expression-filter-return)
    (debugger-list-functions
     :after emacsvox--advice-debugger-list-functions-after)
    (debugger-quit :after emacsvox--advice-debugger-quit-after))
  "Native advice registrations in the Debugger integration.")

(ert-deftest emacsvox-debugger-advice-is-directly-registered ()
  "Debugger advice uses native advice directly."
  (dolist (entry emacsvox-test--debugger-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-debugger-navigation-feedback-is-target-aware ()
  "Only the matching interactive backtrace command produces feedback."
  (let ((ems--interactive-fn-name 'backtrace-forward-frame)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events))))
      (emacsvox--advice-backtrace-backward-frame-after)
      (emacsvox--advice-backtrace-forward-frame-after))
    (should
     (equal
      (nreverse events)
      '((icon large-movement) speak-line)))))

(ert-deftest emacsvox-debugger-eval-speaks-and-preserves-interactive-result ()
  "Interactive evaluation speaks its result without replacing it."
  (let ((ems--interactive-fn-name 'debugger-eval-expression)
        spoken)
    (cl-letf (((symbol-function 'dtk-speak)
               (lambda (value) (setq spoken value) 'speech-result)))
      (should
       (equal
        '(evaluated value)
        (emacsvox--advice-debugger-eval-expression-filter-return
         '(evaluated value))))
      (should (equal spoken '(evaluated value))))))

(ert-deftest emacsvox-debugger-eval-is-quiet-programmatically ()
  "Programmatic evaluation preserves its result without speaking."
  (let (spoken)
    (cl-letf (((symbol-function 'dtk-speak)
               (lambda (value) (setq spoken value))))
      (should
       (eq
        'result
        (emacsvox--advice-debugger-eval-expression-filter-return 'result)))
      (should-not spoken))))

(provide 'emacsvox-debugger-tests)
;;; emacsvox-debugger-tests.el ends here
