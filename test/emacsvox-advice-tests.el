;;; emacsvox-advice-tests.el --- Advice migration tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Regression tests for the temporary converted-advice compatibility bridge.
;; These tests establish behaviour that native advice must preserve during the
;; Emacs 31 advice migration.

;;; Code:

(require 'ert)
(require 'emacsvox-preamble)

(defun emacsvox-test--call (function &rest arguments)
  "Call FUNCTION with ARGUMENTS without compiler assumptions about FUNCTION."
  (apply function arguments))

(defun emacsvox-test--call-interactively (function &rest arguments)
  "Call FUNCTION interactively with ARGUMENTS."
  (apply #'funcall-interactively function arguments))

(defun emacsvox-test--bridge-wrapper (target where advice)
  "Return the compatibility wrapper for ADVICE on TARGET at WHERE."
  (gethash (list target where advice) ems--modern-advice-wrappers))

(defun emacsvox-test--remove-bridge-advice (target where advice)
  "Remove bridged ADVICE from TARGET at WHERE and discard test functions."
  (let ((wrapper (emacsvox-test--bridge-wrapper target where advice)))
    (when wrapper
      (advice-remove target wrapper)
      (remhash (list target where advice) ems--modern-advice-wrappers)))
  ;; Also handle a future implementation that registers ADVICE directly.
  (when (advice-member-p advice target)
    (advice-remove target advice))
  (fmakunbound target)
  (fmakunbound advice))

(ert-deftest emacsvox-bridge-before-advice-can-replace-an-argument ()
  "Converted before advice can retain legacy `ad-set-arg' behaviour."
  (let ((target 'emacsvox-test--before-target)
        (advice 'ems--emacsvox-test-before)
        received)
    (fset target
          (lambda (first second)
            (setq received (list first second))))
    (fset advice
          (lambda (&rest _)
            (ad-set-arg 0 'replacement)))
    (unwind-protect
        (progn
          (advice-add target :before advice)
          (emacsvox-test--call target 'original 'unchanged)
          (should (equal received '(replacement unchanged))))
      (emacsvox-test--remove-bridge-advice target :before advice))))

(ert-deftest emacsvox-bridge-after-advice-can-replace-the-return-value ()
  "Converted after advice can retain legacy `ad-return-value' behaviour."
  (let ((target 'emacsvox-test--after-target)
        (advice 'ems--emacsvox-test-after))
    (fset target (lambda (value) (list 'original value)))
    (fset advice
          (lambda (&rest _)
            (setq ad-return-value '(replacement result))))
    (unwind-protect
        (progn
          (advice-add target :after advice)
          (should
           (equal
            (emacsvox-test--call target 'argument)
            '(replacement result))))
      (emacsvox-test--remove-bridge-advice target :after advice))))

(ert-deftest emacsvox-bridge-around-advice-can-read-an-argument ()
  "Converted around advice can retain legacy `ad-get-arg' behaviour."
  (let ((target 'emacsvox-test--around-target)
        (advice 'ems--emacsvox-test-around))
    (fset target (lambda (value) (list 'target value)))
    (fset advice
          (lambda (original &rest arguments)
            (list (ad-get-arg 0) (apply original arguments))))
    (unwind-protect
        (progn
          (advice-add target :around advice)
          (should
           (equal
            (emacsvox-test--call target 'argument)
            '(argument (target argument)))))
      (emacsvox-test--remove-bridge-advice target :around advice))))

(ert-deftest emacsvox-bridge-distinguishes-interactive-invocation ()
  "`ems-interactive-p' is true only for interactive advice invocation."
  (let ((target 'emacsvox-test--interactive-target)
        (advice 'ems--emacsvox-test-interactive-after)
        events)
    (fset target (lambda () (interactive) 'result))
    (fset advice
          (lambda (&rest _)
            (push (ems-interactive-p) events)))
    (unwind-protect
        (progn
          (advice-add target :after advice)
          (emacsvox-test--call target)
          (emacsvox-test--call-interactively target)
          (should (equal (nreverse events) '(nil t))))
      (emacsvox-test--remove-bridge-advice target :after advice))))

(ert-deftest emacsvox-bridge-identifies-the-outer-interactive-command ()
  "A normal nested command does not consume the outer interactive marker."
  (let ((outer 'emacsvox-test--outer-command)
        (inner 'emacsvox-test--inner-command)
        (outer-advice 'ems--emacsvox-test-outer-after)
        (inner-advice 'ems--emacsvox-test-inner-after)
        events)
    (fset inner (lambda () 'inner-result))
    (fset outer
          (lambda ()
            (interactive)
            (emacsvox-test--call inner)
            'outer-result))
    (fset inner-advice
          (lambda (&rest _)
            (push (list 'inner (ems-interactive-p)) events)))
    (fset outer-advice
          (lambda (&rest _)
            (push (list 'outer (ems-interactive-p)) events)))
    (unwind-protect
        (progn
          (advice-add inner :after inner-advice)
          (advice-add outer :after outer-advice)
          (emacsvox-test--call-interactively outer)
          (should
           (equal (nreverse events) '((inner nil) (outer t)))))
      (emacsvox-test--remove-bridge-advice inner :after inner-advice)
      (emacsvox-test--remove-bridge-advice outer :after outer-advice))))

(ert-deftest emacsvox-bridge-advice-survives-target-definition ()
  "Bridged advice added before its target is defined remains active."
  (let ((target 'emacsvox-test--autoloaded-target)
        (advice 'ems--emacsvox-test-autoloaded-after)
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
      (emacsvox-test--remove-bridge-advice target :after advice))))

(ert-deftest emacsvox-bridge-registers-a-removable-stable-wrapper ()
  "The bridge registers its cached wrapper with native advice APIs."
  (let ((target 'emacsvox-test--membership-target)
        (advice 'ems--emacsvox-test-membership-after)
        called)
    (fset target (lambda () 'result))
    (fset advice (lambda (&rest _) (setq called t)))
    (unwind-protect
        (progn
          (advice-add target :after advice)
          (let ((wrapper
                 (emacsvox-test--bridge-wrapper target :after advice)))
            (should wrapper)
            (should (advice-member-p wrapper target))
            (should-not (advice-member-p advice target))
            (advice-remove target wrapper)
            (emacsvox-test--call target)
            (should-not called)))
      (emacsvox-test--remove-bridge-advice target :after advice))))

(ert-deftest emacsvox-interactive-p-requires-advice-context ()
  "The compatibility predicate is false outside an advised command."
  (let ((ems--interactive-fn-name nil)
        (ems--modern-advice-target nil))
    (should-not (ems-interactive-p))))

(ert-deftest emacsvox-native-advice-uses-an-explicit-interactive-target ()
  "Native advice bypasses the bridge and detects interactive invocation."
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
          (should-not
           (emacsvox-test--bridge-wrapper target :after advice))
          (emacsvox-test--call target)
          (emacsvox-test--call-interactively target)
          (should (equal (nreverse events) '(nil t))))
      (emacsvox-test--remove-bridge-advice target :after advice))))

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
      (emacsvox-test--remove-bridge-advice target :after advice))))

(provide 'emacsvox-advice-tests)
;;; emacsvox-advice-tests.el ends here
