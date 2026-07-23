;;; emacsvox-copyright-tests.el --- Copyright advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated copyright advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(defconst emacsvox-test--copyright-after-targets
  '(copyright copyright-update copyright-update-directory)
  "Copyright commands using generated native after advice.")

(ert-deftest emacsvox-copyright-advice-is-directly-registered ()
  "Migrated copyright advice bypasses the compatibility bridge."
  (dolist (target emacsvox-test--copyright-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-copyright-feedback-is-target-aware ()
  "Only the matching copyright command cues and speaks its updated line."
  (let ((ems--interactive-fn-name 'copyright-update)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events))))
      (emacsvox--advice-copyright-after)
      (emacsvox--advice-copyright-update-after))
    (should
     (equal
      (nreverse events)
      '((icon task-done) speak-line)))))

(ert-deftest emacsvox-copyright-directory-feedback-is-icon-only ()
  "Interactive directory updates cue completion without line speech."
  (let ((ems--interactive-fn-name 'copyright-update-directory)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events))))
      (emacsvox--advice-copyright-update-directory-after))
    (should (equal events '((icon task-done))))))

(provide 'emacsvox-copyright-tests)
;;; emacsvox-copyright-tests.el ends here
