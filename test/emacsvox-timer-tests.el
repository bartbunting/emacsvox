;;; emacsvox-timer-tests.el --- Timer advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated timer advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(defconst emacsvox-test--timer-direct-advice
  '((timer-list :after emacsvox--advice-timer-list-after)
    (list-timers :after emacsvox--advice-list-timers-after))
  "Timer commands using individually defined native advice.")

(ert-deftest emacsvox-timer-advice-is-directly-registered ()
  "Migrated timer advice bypasses the compatibility bridge."
  (dolist (entry emacsvox-test--timer-direct-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target where function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-timer-list-feedback-is-target-aware ()
  "Only an interactive `timer-list' invocation speaks its mode line."
  (let ((ems--interactive-fn-name 'timer-list)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'speak-mode-line events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events))))
      (emacsvox--advice-list-timers-after)
      (emacsvox--advice-timer-list-after))
    (should
     (equal
      (nreverse events)
      '((icon open-object) speak-mode-line)))))

(ert-deftest emacsvox-list-timers-feedback-is-target-aware ()
  "Only an interactive `list-timers' invocation speaks its current line."
  (let ((ems--interactive-fn-name 'list-timers)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'speak-mode-line events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events))))
      (emacsvox--advice-timer-list-after)
      (emacsvox--advice-list-timers-after))
    (should
     (equal
      (nreverse events)
      '((icon open-object) speak-line)))))

(provide 'emacsvox-timer-tests)
;;; emacsvox-timer-tests.el ends here
