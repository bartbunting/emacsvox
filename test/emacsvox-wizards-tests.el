;;; emacsvox-wizards-tests.el --- Wizards advice tests -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cperl-mode)
(load "emacsvox-wizards" nil nil)
(load "emacsvox-extras" nil nil)

(ert-deftest emacsvox-wizards-voice-sampler-follows-the-active-palette ()
  "Named samples retain their identity instead of freezing legacy presets."
  (let ((buffer (generate-new-buffer " *voice-sampler-test*"))
        (emacsvox-aural-voice-palette-registry
         (copy-hash-table emacsvox-aural-voice-palette-registry))
        (emacsvox-aural-voice-palette-override 'sampler-test))
    (unwind-protect
        (save-current-buffer
          (emacsvox-aural-register-voice-palette-data
           '(:schema-version 1 :id sampler-test :summary "Sampler test voices"
             :parent acss-default
             :entries ((bolden :personality voice-animate))))
          (cl-letf (((symbol-function 'voice-setup-defined-voices)
                     (lambda () '(voice-bolden)))
                    ((symbol-function 'get-buffer-create) (lambda (_) buffer))
                    ((symbol-function 'pop-to-buffer)
                     (lambda (target &rest _) (set-buffer target))))
            (emacsvox-wizards-show-voices))
          (with-current-buffer buffer
            (should (equal (buffer-string) "This is a sample of voice-bolden.\n"))
            (let* ((voice-lock-mode t)
                   (prepared (emacsvox-aural-prepare-text (buffer-string)))
                   (content (emacsvox-aural-concrete-plan-content
                             (emacsvox-aural-concrete-plan-at 0 prepared))))
              (should (eq (emacsvox-aural-concrete-content-voice-request content)
                          'bolden)))))
      (kill-buffer buffer))))

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
