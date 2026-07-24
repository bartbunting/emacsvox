;;; emacsvox-calculator-tests.el --- Calculator advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Calculator advice.

;;; Code:

(require 'ert)
(require 'calculator)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-calculator.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--calculator-around-targets
  '(calculator
    calculator-digit
    calculator-exp
    calculator-op
    calculator-op-or-exp
    calculator-open-paren
    calculator-close-paren
    calculator-saved-up
    calculator-saved-down
    calculator-backspace)
  "Current Emacs 31 Calculator targets using direct around advice.")

(defconst emacsvox-test--calculator-after-targets
  '(calculator
    calculator-save-on-list
    calculator-clear-saved
    calculator-enter
    calculator-clear
    calculator-copy
    calculator-paste
    calculator-get-register
    calculator-quit
    calculator-save-and-quit
    calculator-update-display)
  "Current Emacs 31 Calculator targets using direct after advice.")

(ert-deftest emacsvox-calculator-advice-is-directly-registered ()
  "Calculator advice is attached directly to current Emacs 31 targets."
  (dolist (target emacsvox-test--calculator-around-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-around" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))))
  (dolist (target emacsvox-test--calculator-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-calculator-launch-calls-original-once ()
  "Calculator launch preserves its result and suppresses the header once."
  (let ((ems--interactive-fn-name 'calculator)
        (header-line-format 'header)
        calls)
    (should
     (eq
      'result
      (emacsvox--advice-calculator-around
       (lambda ()
         (push header-line-format calls)
         'result))))
    (should (equal calls '(nil)))))

(ert-deftest emacsvox-calculator-insertion-calls-original-once ()
  "Calculator insertion speaks only text inserted by one original call."
  (with-temp-buffer
    (let ((ems--interactive-fn-name 'calculator-digit)
          (calls 0)
          regions)
      (cl-letf (((symbol-function 'emacsvox-speak-region)
                 (lambda (start end)
                   (push (buffer-substring start end) regions))))
        (should
         (eq
          'result
          (emacsvox--advice-calculator-digit-around
           (lambda ()
             (setq calls (1+ calls))
             (insert "8")
             'result)))))
      (should (= calls 1))
      (should (equal regions '("8"))))))

(ert-deftest emacsvox-calculator-selection-calls-original-once ()
  "Calculator selection summarizes after one original call."
  (let ((ems--interactive-fn-name 'calculator-op)
        (calls 0)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-calculator-summarize)
               (lambda () (push 'summary events))))
      (should
       (eq
        'result
        (emacsvox--advice-calculator-op-around
         (lambda ()
           (setq calls (1+ calls))
           'result)))))
    (should (= calls 1))
    (should
     (equal
      (nreverse events)
      '((icon select-object) summary)))))

(ert-deftest emacsvox-calculator-backspace-feedback-precedes-one-call ()
  "Calculator backspace gives feedback before calling the original once."
  (with-temp-buffer
    (insert "9")
    (let ((ems--interactive-fn-name 'calculator-backspace)
          (calls 0)
          events)
      (cl-letf (((symbol-function 'tts-tone)
                 (lambda (&rest _) (push 'tone events)))
                ((symbol-function 'emacsvox-speak-this-char)
                 (lambda (char) (push (list 'char char) events))))
        (should
         (eq
          'result
          (emacsvox--advice-calculator-backspace-around
           (lambda ()
             (setq calls (1+ calls))
             (push 'original events)
             'result)))))
      (should (= calls 1))
      (should
       (equal
        (nreverse events)
        '(tone (char 57) original))))))

(ert-deftest emacsvox-calculator-after-feedback-is-target-aware ()
  "Only the matching Calculator after advice produces feedback."
  (let ((ems--interactive-fn-name 'calculator-clear)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-calculator-summarize)
               (lambda () (push 'summary events))))
      (emacsvox--advice-calculator-enter-after)
      (emacsvox--advice-calculator-clear-after))
    (should
     (equal
      (nreverse events)
      '((icon delete-object) summary)))))

(provide 'emacsvox-calculator-tests)
;;; emacsvox-calculator-tests.el ends here
