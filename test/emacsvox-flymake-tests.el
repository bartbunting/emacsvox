;;; emacsvox-flymake-tests.el --- Flymake advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Flymake advice.

;;; Code:

(require 'cl-lib)
(require 'ert)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-flymake.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--flymake-after-targets
  '(flymake-goto-diagnostic
    flymake-goto-next-error
    flymake-goto-prev-error)
  "Flymake commands using generated native after advice.")

(ert-deftest emacsvox-flymake-advice-is-directly-registered ()
  "Migrated Flymake advice bypasses the compatibility bridge."
  (dolist (target emacsvox-test--flymake-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-flymake-defers-legacy-backend-advice ()
  "The optional bundled legacy backend is not created as a placeholder."
  (should
   (fboundp 'emacsvox--advice-flymake-proc-compile-after))
  (unless (featurep 'flymake-proc)
    (should-not (fboundp 'flymake-compile))
    (should-not (fboundp 'flymake-proc-compile))))

(ert-deftest emacsvox-flymake-feedback-is-target-aware ()
  "Only the matching interactive Flymake command produces feedback."
  (let ((ems--interactive-fn-name 'flymake-goto-next-error)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events))))
      (emacsvox--advice-flymake-goto-prev-error-after)
      (emacsvox--advice-flymake-goto-next-error-after))
    (should
     (equal
      (nreverse events)
      '((icon large-movement) speak-line)))))

(ert-deftest emacsvox-flymake-legacy-compile-feedback-is-target-aware ()
  (let ((ems--interactive-fn-name 'flymake-proc-compile) events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events))))
      (emacsvox--advice-flymake-proc-compile-after))
    (should (equal events '(task-done)))))

(ert-deftest emacsvox-flymake-proc-advice-registers-after-load ()
  (require 'flymake-proc)
  (should
   (advice-member-p
    #'emacsvox--advice-flymake-proc-compile-after
    'flymake-proc-compile))
  (should-not
   (gethash
    '(flymake-proc-compile
      :after emacsvox--advice-flymake-proc-compile-after)
    ems--modern-advice-wrappers)))

(provide 'emacsvox-flymake-tests)
;;; emacsvox-flymake-tests.el ends here
