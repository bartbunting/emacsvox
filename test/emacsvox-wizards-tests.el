;;; emacsvox-wizards-tests.el --- Wizards advice tests -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(load "emacsvox-wizards" nil nil)

(defun emacsvox-test--remove-wizards-advice (target advice)
  "Remove ADVICE from TARGET and discard both test functions."
  (when (advice-member-p advice target)
    (advice-remove target advice))
  (fmakunbound target)
  (fmakunbound advice))

(ert-deftest emacsvox-wizards-detects-native-advice-by-function-name ()
  "Native Emacsvox advice is recognized from its function name."
  (let ((target 'emacsvox-test--wizards-target)
        (advice 'emacsvox--advice-wizards-test-after))
    (fset target (lambda () (interactive)))
    (fset advice (lambda (&rest _)))
    (unwind-protect
        (progn
          (should-not (emacsvox-wizards--advised-p target))
          (advice-add target :after advice)
          (should (emacsvox-wizards--advised-p target)))
      (emacsvox-test--remove-wizards-advice target advice))))

(ert-deftest emacsvox-wizards-detects-native-advice-by-property ()
  "Named Emacsvox advice is recognized even with a generic function name."
  (let ((target 'emacsvox-test--wizards-property-target)
        (advice 'emacsvox-test--generic-after))
    (fset target (lambda () (interactive)))
    (fset advice (lambda (&rest _)))
    (unwind-protect
        (progn
          (advice-add target :after advice '((name . emacsvox-wizards)))
          (should (emacsvox-wizards--advised-p target)))
      (emacsvox-test--remove-wizards-advice target advice))))

(provide 'emacsvox-wizards-tests)
;;; emacsvox-wizards-tests.el ends here
