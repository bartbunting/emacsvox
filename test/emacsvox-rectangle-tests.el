;;; emacsvox-rectangle-tests.el --- Rectangle advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated rectangle advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(defconst emacsvox-test--rectangle-direct-advice
  '((rectangle-next-line :after
     emacsvox--advice-rectangle-next-line-after)
    (rectangle-previous-line :after
     emacsvox--advice-rectangle-previous-line-after)
    (rectangle-mark-mode :after
     emacsvox--advice-rectangle-mark-mode-after)
    (rectangle-backward-char :after
     emacsvox--advice-rectangle-backward-char-after)
    (rectangle-forward-char :after
     emacsvox--advice-rectangle-forward-char-after)
    (rectangle-right-char :after
     emacsvox--advice-rectangle-right-char-after)
    (rectangle-left-char :after
     emacsvox--advice-rectangle-left-char-after))
  "Rectangle commands using individually named native advice.")

(ert-deftest emacsvox-rectangle-advice-is-directly-registered ()
  "Migrated rectangle advice bypasses the compatibility bridge."
  (dolist (entry emacsvox-test--rectangle-direct-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target where function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-rectangle-vertical-feedback-is-target-aware ()
  "Only the matching vertical rectangle command speaks its line."
  (let ((ems--interactive-fn-name 'rectangle-previous-line)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events))))
      (emacsvox--advice-rectangle-next-line-after)
      (emacsvox--advice-rectangle-previous-line-after))
    (should (equal events '(speak-line)))))

(ert-deftest emacsvox-rectangle-horizontal-feedback-is-target-aware ()
  "Only the matching horizontal rectangle command speaks its character."
  (let ((ems--interactive-fn-name 'rectangle-right-char)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-char)
               (lambda (&rest arguments)
                 (push (cons 'speak-char arguments) events))))
      (emacsvox--advice-rectangle-left-char-after)
      (emacsvox--advice-rectangle-right-char-after))
    (should (equal events '((speak-char t))))))

(ert-deftest emacsvox-rectangle-mark-mode-announces-state ()
  "An interactive rectangle mark toggle announces its new state."
  (let ((ems--interactive-fn-name 'rectangle-mark-mode)
        (rectangle-mark-mode t)
        events)
    (cl-letf (((symbol-function 'dtk-notify)
               (lambda (text &rest _)
                 (push (list 'notify text) events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-rectangle-mark-mode-after))
    (should
     (equal
      (nreverse events)
      '((notify "Turned on rectangle mark mode") (icon on))))))

(provide 'emacsvox-rectangle-tests)
;;; emacsvox-rectangle-tests.el ends here
