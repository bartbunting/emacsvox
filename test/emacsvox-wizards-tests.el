;;; emacsvox-wizards-tests.el --- Wizards advice tests -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cperl-mode)
(load "emacsvox-wizards" nil nil)
(load "emacsvox-extras" nil nil)

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

(ert-deftest emacsvox-wizards-display-pod-uses-current-cperl-program ()
  "POD rendering uses the current CPerl program variable."
  (let ((cperl-pod2man-program "current-pod2man")
        (buffer-name "Man /tmp/emacsvox-example.pod")
        process-arguments
        sentinel-arguments)
    (unwind-protect
        (cl-letf (((symbol-function 'cperl-pod2man-build-command)
                   (lambda () "render-pod %s"))
                  ((symbol-function 'start-process)
                   (lambda (&rest arguments)
                     (setq process-arguments arguments)
                     'pod-process))
                  ((symbol-function 'set-process-sentinel)
                   (lambda (&rest arguments)
                     (setq sentinel-arguments arguments))))
          (emacsvox-wizards-display-pod-as-manpage
           "/tmp/emacsvox-example.pod")
          (should
           (equal process-arguments
                  (list
                   "current-pod2man" (get-buffer buffer-name)
                   "sh" "-c"
                   "render-pod /tmp/emacsvox-example.pod | nroff -man ")))
          (should
           (equal sentinel-arguments
                  '(pod-process Man-bgproc-sentinel))))
      (let ((buffer (get-buffer buffer-name)))
        (when buffer (kill-buffer buffer))))))

(provide 'emacsvox-wizards-tests)
;;; emacsvox-wizards-tests.el ends here
