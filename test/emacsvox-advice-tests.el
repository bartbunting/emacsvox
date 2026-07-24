;;; emacsvox-advice-tests.el --- Advice migration tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Regression tests for native advice and interactive target tracking.

;;; Code:

(require 'ert)
(require 'emacsvox-preamble)

(defun emacsvox-test--call (function &rest arguments)
  "Call FUNCTION with ARGUMENTS without compiler assumptions about FUNCTION."
  (apply function arguments))

(defun emacsvox-test--call-interactively (function &rest arguments)
  "Call FUNCTION interactively with ARGUMENTS."
  (apply #'funcall-interactively function arguments))

(defun emacsvox-test--remove-native-advice (target advice)
  "Remove ADVICE from TARGET and discard both test functions."
  (when (advice-member-p advice target)
    (advice-remove target advice))
  (fmakunbound target)
  (fmakunbound advice))

(ert-deftest emacsvox-native-advice-identifies-the-outer-interactive-command ()
  "A normal nested command does not consume the outer interactive marker."
  (let ((outer 'emacsvox-test--outer-command)
        (inner 'emacsvox-test--inner-command)
        (outer-advice 'emacsvox--test-outer-after)
        (inner-advice 'emacsvox--test-inner-after)
        events)
    (fset inner (lambda () 'inner-result))
    (fset outer
          (lambda ()
            (interactive)
            (emacsvox-test--call inner)
            'outer-result))
    (fset inner-advice
          (lambda (&rest _)
            (push (list 'inner (ems-interactive-p inner)) events)))
    (fset outer-advice
          (lambda (&rest _)
            (push (list 'outer (ems-interactive-p outer)) events)))
    (unwind-protect
        (progn
          (advice-add inner :after inner-advice)
          (advice-add outer :after outer-advice)
          (emacsvox-test--call-interactively outer)
          (should
           (equal (nreverse events) '((inner nil) (outer t)))))
      (emacsvox-test--remove-native-advice inner inner-advice)
      (emacsvox-test--remove-native-advice outer outer-advice))))

(ert-deftest emacsvox-native-advice-survives-target-definition ()
  "Native advice added before its target is defined remains active."
  (let ((target 'emacsvox-test--autoloaded-target)
        (advice 'emacsvox--test-autoloaded-after)
        events)
    (fmakunbound target)
    (fset advice
          (lambda (&rest arguments)
            (push arguments events)))
    (unwind-protect
        (progn
          (advice-add target :after advice)
          ;; `defun' installs source definitions through `defalias', which
          ;; preserves pending nadvice.  A raw `fset' intentionally does not.
          (defalias target (lambda (value) (list 'first value)))
          (should (equal (emacsvox-test--call target 1) '(first 1)))
          (defalias target (lambda (value) (list 'second value)))
          (should (equal (emacsvox-test--call target 2) '(second 2)))
          (should (equal (nreverse events) '((1) (2)))))
      (emacsvox-test--remove-native-advice target advice))))

(ert-deftest emacsvox-native-advice-is-directly-removable ()
  "Native advice is registered and removed through native advice APIs."
  (let ((target 'emacsvox-test--membership-target)
        (advice 'emacsvox--test-membership-after)
        called)
    (fset target (lambda () 'result))
    (fset advice (lambda (&rest _) (setq called t)))
    (unwind-protect
        (progn
          (advice-add target :after advice)
          (should (advice-member-p advice target))
          (advice-remove target advice)
          (should-not (advice-member-p advice target))
          (emacsvox-test--call target)
          (should-not called))
      (emacsvox-test--remove-native-advice target advice))))

(ert-deftest emacsvox-native-advice-uses-an-explicit-interactive-target ()
  "Native advice uses native advice directly and detects interactive invocation."
  (let ((target 'emacsvox-test--native-target)
        (advice 'emacsvox--test-native-after)
        events)
    (fset target (lambda () (interactive) 'result))
    (fset advice
          (lambda (&rest _)
            (push (ems-interactive-p target) events)))
    (unwind-protect
        (progn
          (advice-add target :after advice)
          (should (advice-member-p advice target))
          (emacsvox-test--call target)
          (emacsvox-test--call-interactively target)
          (should (equal (nreverse events) '(nil t))))
      (emacsvox-test--remove-native-advice target advice))))

(ert-deftest emacsvox-native-advice-does-not-consume-a-different-target ()
  "A failed explicit target check leaves the interactive marker available."
  (let ((target 'emacsvox-test--native-target-selection)
        (advice 'emacsvox--test-native-target-selection-after)
        result)
    (fset target (lambda () (interactive) 'result))
    (fset advice
          (lambda (&rest _)
            (setq result
                  (list
                   (ems-interactive-p 'different-command)
                   (ems-interactive-p target)))))
    (unwind-protect
        (progn
          (advice-add target :after advice)
          (emacsvox-test--call-interactively target)
          (should (equal result '(nil t))))
      (emacsvox-test--remove-native-advice target advice))))

(ert-deftest emacsvox-interactive-p-requires-an-explicit-target ()
  "Interactive advice checks cannot fall back to compatibility state."
  (should-error (ems-interactive-p) :type 'wrong-number-of-arguments))

(ert-deftest emacsvox-unicode-cache-advice-is-native ()
  "Unicode data caching uses its native around-advice function directly."
  (should
   (advice-member-p
    #'emacsvox--advice-describe-char-unicode-data-around
    'describe-char-unicode-data)))

(provide 'emacsvox-advice-tests)
;;; emacsvox-advice-tests.el ends here
