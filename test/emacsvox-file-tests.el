;;; emacsvox-file-tests.el --- File operation advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated file operation advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(defconst emacsvox-test--file-direct-advice
  '((byte-compile-file :around
     emacsvox--advice-byte-compile-file-around))
  "File functions using individually defined native advice.")

(ert-deftest emacsvox-file-advice-is-directly-registered ()
  "Migrated file advice bypasses the compatibility bridge."
  (dolist (entry emacsvox-test--file-direct-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target where function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-byte-compile-advice-calls-original-once ()
  "Interactive compilation is silenced, announced, and called exactly once."
  (let ((ems--interactive-fn-name 'byte-compile-file)
        (emacsvox-speak-messages t)
        (inhibit-message nil)
        (calls 0)
        events)
    (cl-letf (((symbol-function 'dtk-speak)
               (lambda (text) (push (list 'speak text) events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (should
       (eq
        (emacsvox--advice-byte-compile-file-around
         (lambda (&rest arguments)
           (cl-incf calls)
           (push
            (list 'original arguments
                  emacsvox-speak-messages inhibit-message)
            events)
           'compile-result)
         "example.el" 'load)
        'compile-result)))
    (should (= calls 1))
    (should
     (equal
      (nreverse events)
      '((speak "Byte compiling ")
        (original ("example.el" load) nil t)
        (icon task-done)
        (speak "Done byte compiling "))))
    (should emacsvox-speak-messages)
    (should-not inhibit-message)))

(ert-deftest emacsvox-byte-compile-advice-is-quiet-programmatically ()
  "Programmatic compilation calls once without speech feedback."
  (let ((ems--interactive-fn-name nil)
        (calls 0)
        feedback)
    (cl-letf (((symbol-function 'dtk-speak)
               (lambda (&rest _) (setq feedback t)))
              ((symbol-function 'emacsvox-icon)
               (lambda (&rest _) (setq feedback t))))
      (should
       (eq
        (emacsvox--advice-byte-compile-file-around
         (lambda (&rest _)
           (cl-incf calls)
           'compile-result)
         "example.el")
        'compile-result)))
    (should (= calls 1))
    (should-not feedback)))

(provide 'emacsvox-file-tests)
;;; emacsvox-file-tests.el ends here
