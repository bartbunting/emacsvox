;;; emacsvox-compile-tests.el --- Compilation advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated compilation advice.

;;; Code:

(require 'cl-lib)
(require 'ert)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-compile.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--compile-navigation-targets
  '(next-error previous-error
    compilation-next-file compilation-previous-file
    compile-goto-error compile-mouse-goto-error
    compilation-next-error compilation-previous-error
    next-error-no-select previous-error-no-select)
  "Compilation navigation commands using generated native after advice.")

(defconst emacsvox-test--compile-direct-advice
  '((compile :after emacsvox--advice-compile-after)
    (compilation-sentinel :after
     emacsvox--advice-compilation-sentinel-after))
  "Compilation functions using individually named native advice.")

(ert-deftest emacsvox-compile-advice-is-directly-registered ()
  "Migrated compilation advice uses native advice directly."
  (dolist (target emacsvox-test--compile-navigation-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp function))
      (should (advice-member-p function target))))
  (dolist (entry emacsvox-test--compile-direct-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-compile-navigation-feedback-is-target-aware ()
  "Interactive error navigation stops speech before cueing and speaking."
  (let ((ems--interactive-fn-name 'next-error)
        events)
    (cl-letf (((symbol-function 'tts-stop)
               (lambda (scope) (push (list 'stop scope) events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-compilation-speak-error)
               (lambda () (push 'speak-error events))))
      (emacsvox--advice-previous-error-after)
      (emacsvox--advice-next-error-after))
    (should
     (equal
      (nreverse events)
      '((stop all) (icon large-movement) speak-error)))))

(ert-deftest emacsvox-compile-selection-feedback-preserves-order ()
  "Interactive compilation selection speaks before its selection cue."
  (let ((ems--interactive-fn-name 'compilation-next-error)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-compilation-next-error-after))
    (should
     (equal
      (nreverse events)
      '(speak-line (icon select-object))))))

(ert-deftest emacsvox-compile-launch-feedback-is-target-aware ()
  "An interactive compilation reports launch before its completion cue."
  (let ((ems--interactive-fn-name 'compile)
        events)
    (cl-letf (((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push
                  (list 'message
                        (apply #'format format-string arguments))
                  events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-compile-after))
    (should
     (equal
      (nreverse events)
      '((message "Launched compilation") (icon task-done))))))

(ert-deftest emacsvox-compilation-sentinel-uses-explicit-arguments ()
  "The compilation sentinel reports its explicit process and status."
  (let (events)
    (cl-letf (((symbol-function 'process-name)
               (lambda (process)
                 (should (eq process 'test-process))
                 "compiler"))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push
                  (list 'message
                        (apply #'format format-string arguments))
                  events))))
      (emacsvox--advice-compilation-sentinel-after
       'test-process "finished\n"))
    (should
     (equal
      (nreverse events)
      '((icon task-done)
        (message "process compiler finished\n"))))))

(provide 'emacsvox-compile-tests)
;;; emacsvox-compile-tests.el ends here
