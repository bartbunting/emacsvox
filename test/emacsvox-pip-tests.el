;;; emacsvox-pip-tests.el --- Piper integration tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Verify that Piper remains optional until the user invokes it.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-optional-module-test-utils)

(load (expand-file-name
       "../lisp/pip.el"
       (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-pip-loads-without-piper-or-voices ()
  "The Piper module should load before its runtime prerequisites exist."
  (emacsvox-optional-module-test-load
   "pip.el"
   '(setq exec-path nil
          pip-data-dir "/nonexistent/emacsvox-piper-voices")
   '(unless (featurep 'pip)
      (error "Piper module did not load independently"))))

(ert-deftest emacsvox-pip-start-reports-missing-piper ()
  "Starting Piper should explain a missing executable at point of use."
  (let ((pip-piper nil))
    (cl-letf (((symbol-function 'executable-find) #'ignore))
      (let ((condition (should-error (pip-start) :type 'user-error)))
        (should
         (string-match-p
          "Install Piper.*PATH" (error-message-string condition)))))))

(ert-deftest emacsvox-pip-start-discovers-a-voice-lazily ()
  "Starting Piper should discover voice data without eager module setup."
  (let* ((directory (make-temp-file "emacsvox-piper-voices-" t))
         (model (expand-file-name "test.onnx" directory))
         (pip-data-dir directory)
         (pip-device "test-device")
         (pip-model nil)
         (pip-piper nil)
         (pip-voices nil)
         invocation)
    (unwind-protect
        (progn
          (with-temp-file model)
          (cl-letf (((symbol-function 'executable-find)
                     (lambda (program)
                       (and (string= program "piper") "/bin/piper")))
                    ((symbol-function 'file-executable-p) (lambda (_) t))
                    ((symbol-function 'start-process)
                     (lambda (&rest arguments)
                       (setq invocation arguments)
                       'piper-process)))
            (pip-start))
          (should
           (equal invocation
                  (list "pip" nil pip-pip model "test-device")))
          (should (equal pip-model model))
          (should (equal pip-voices (list model))))
      (delete-directory directory t))))

(provide 'emacsvox-pip-tests)
;;; emacsvox-pip-tests.el ends here
