;;; emacsvox-file-tests.el --- File operation advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated file operation advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(defconst emacsvox-test--file-direct-advice
  '((byte-compile-file :around
     emacsvox--advice-byte-compile-file-around)
    (not-modified :after emacsvox--advice-not-modified-after)
    (find-file :after emacsvox--advice-find-file-after)
    (revert-buffer-quick :after
     emacsvox--advice-revert-buffer-quick-after)
    (ask-user-about-lock :around
     emacsvox--advice-ask-user-about-lock-around))
  "File functions using individually defined native advice.")

(defconst emacsvox-test--file-after-targets
  '(save-buffer save-some-buffers)
  "File commands using generated native after advice.")

(ert-deftest emacsvox-file-advice-is-directly-registered ()
  "Migrated file advice uses native advice directly."
  (dolist (target emacsvox-test--file-after-targets)
    (let ((function (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp function))
      (should (advice-member-p function target))))
  (dolist (entry emacsvox-test--file-direct-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target)))))

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

(ert-deftest emacsvox-save-feedback-is-target-aware ()
  "Only the interactive save command emits its completion icon."
  (let ((ems--interactive-fn-name 'save-some-buffers)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events))))
      (emacsvox--advice-save-buffer-after)
      (emacsvox--advice-save-some-buffers-after))
    (should (equal events '(save-object)))))

(ert-deftest emacsvox-not-modified-feedback-reflects-argument ()
  "The modified-state icon reflects `not-modified's optional argument."
  (let (events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events))))
      (let ((ems--interactive-fn-name 'not-modified))
        (emacsvox--advice-not-modified-after nil))
      (let ((ems--interactive-fn-name 'not-modified))
        (emacsvox--advice-not-modified-after t)))
    (should (equal (nreverse events)
                   '(unmodified-object modified-object)))))

(ert-deftest emacsvox-file-visit-feedback-is-target-aware ()
  "Visiting and reverting announce only the matching interactive command."
  (let ((ems--interactive-fn-name 'find-file)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'mode-line events))))
      (emacsvox--advice-revert-buffer-quick-after)
      (emacsvox--advice-find-file-after))
    (should
     (equal
      (nreverse events)
      '((icon open-object) mode-line)))))

(ert-deftest emacsvox-lock-question-advice-calls-original-once ()
  "An interactive lock question preserves call order, arguments, and result."
  (let ((ems--interactive-fn-name 'ask-user-about-lock)
        (calls 0)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (should-not
       (emacsvox--advice-ask-user-about-lock-around
        (lambda (&rest arguments)
          (cl-incf calls)
          (push (list 'original arguments) events)
          nil)
        "example.el" "other-user")))
    (should (= calls 1))
    (should
     (equal
      (nreverse events)
      '((icon ask-short-question)
        (original ("example.el" "other-user"))
        (icon n-answer))))))

(ert-deftest emacsvox-lock-question-advice-is-quiet-programmatically ()
  "A programmatic lock question calls once without auditory feedback."
  (let ((ems--interactive-fn-name nil)
        (calls 0)
        feedback)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (&rest _) (setq feedback t))))
      (should
       (eq
        (emacsvox--advice-ask-user-about-lock-around
         (lambda (&rest _)
           (cl-incf calls)
           'lock-result)
         "example.el" "other-user")
        'lock-result)))
    (should (= calls 1))
    (should-not feedback)))

(provide 'emacsvox-file-tests)
;;; emacsvox-file-tests.el ends here
