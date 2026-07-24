;;; emacsvox-server-tests.el --- Emacs server advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Emacs server advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(defconst emacsvox-test--server-after-targets
  '(server-start server-edit)
  "Emacs server commands using generated native after advice.")

(ert-deftest emacsvox-server-advice-is-directly-registered ()
  "Migrated Emacs server advice uses native advice directly."
  (dolist (target emacsvox-test--server-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-server-feedback-is-target-aware ()
  "Only the matching interactive server command produces feedback."
  (let ((ems--interactive-fn-name 'server-edit)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'speak-mode-line events))))
      (emacsvox--advice-server-start-after)
      (emacsvox--advice-server-edit-after))
    (should (equal events '(speak-mode-line)))))

(ert-deftest emacsvox-server-start-cues-completion ()
  "Interactive server startup produces its task completion cue."
  (let ((ems--interactive-fn-name 'server-start)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-server-start-after))
    (should (equal events '((icon task-done))))))

(provide 'emacsvox-server-tests)
;;; emacsvox-server-tests.el ends here
