;;; emacsvox-calc-tests.el --- Calc advice tests -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'calc)
(require 'calc-prog)
(load
 (expand-file-name "../lisp/emacsvox-calc.el"
                   (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(ert-deftest emacsvox-calc-advice-is-directly-registered ()
  (dolist
      (entry
       '((calc-dispatch :after emacsvox--advice-calc-dispatch-after)
         (calc-quit :after emacsvox--advice-calc-quit-after)
         (calc-call-last-kbd-macro
          :around emacsvox--advice-calc-call-last-kbd-macro-around)
         (calc-do :around emacsvox--advice-calc-do-around)
         (calc-trail-here
          :after emacsvox--advice-calc-trail-here-after)))
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-calc-command-feedback-is-target-aware ()
  (let ((ems--interactive-fn-name 'calc-quit) events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'mode-line events))))
      (emacsvox--advice-calc-dispatch-after)
      (emacsvox--advice-calc-quit-after))
    (should (equal (nreverse events) '(close-object mode-line)))))

(ert-deftest emacsvox-calc-kbd-macro-runs-once ()
  (let ((ems--interactive-fn-name 'calc-call-last-kbd-macro)
        (calls 0) events)
    (cl-letf (((symbol-function 'emacsvox-read-previous-line)
               (lambda () (push 'line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events))))
      (should
       (eq 'result
           (emacsvox--advice-calc-call-last-kbd-macro-around
            (lambda (&rest args)
              (setq calls (1+ calls))
              (should (equal args '(3)))
              (should-not emacsvox-speak-messages)
              'result)
            3))))
    (should (= calls 1))
    (should (equal (nreverse events) '(line task-done)))))

(ert-deftest emacsvox-calc-do-runs-once ()
  (let ((calls 0) events)
    (cl-letf (((symbol-function 'emacsvox-read-previous-line)
               (lambda () (push 'line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events))))
      (should
       (eq 'result
           (emacsvox--advice-calc-do-around
            (lambda (&rest args)
              (setq calls (1+ calls))
              (should (equal args '(body t)))
              (should-not emacsvox-speak-messages)
              'result)
            'body t))))
    (should (= calls 1))
    (should (equal (nreverse events) '(line select-object)))))

(ert-deftest emacsvox-calc-programmatic-kbd-macro-runs-once-quietly ()
  (let ((calls 0) events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (&rest args) (push args events))))
      (should
       (eq 'result
           (emacsvox--advice-calc-call-last-kbd-macro-around
            (lambda () (setq calls (1+ calls)) 'result)))))
    (should (= calls 1))
    (should-not events)))

(provide 'emacsvox-calc-tests)
