;;; emacsvox-undo-tests.el --- Undo advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated undo advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(defconst emacsvox-test--undo-targets
  '(undo undo-redo undo-only)
  "Undo commands using generated native after advice.")

(ert-deftest emacsvox-undo-advice-is-directly-registered ()
  "Migrated undo advice uses native advice directly."
  (dolist (target emacsvox-test--undo-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-undo-feedback-is-target-aware ()
  "Only the matching undo command speaks with point highlighted."
  (with-temp-buffer
    (set-buffer-modified-p t)
    (let ((ems--interactive-fn-name 'undo-redo)
          (emacsvox-show-point nil)
          events)
      (cl-letf (((symbol-function 'emacsvox-speak-line)
                 (lambda ()
                   (push
                    (list 'speak-line emacsvox-show-point)
                    events)))
                ((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events))))
        (emacsvox--advice-undo-after)
        (emacsvox--advice-undo-redo-after))
      (should-not emacsvox-show-point)
      (should
       (equal
        (nreverse events)
        '((speak-line t) (icon modified-object)))))))

(ert-deftest emacsvox-undo-feedback-reports-unmodified-buffer ()
  "Undo feedback uses the unmodified icon when the buffer is clean."
  (with-temp-buffer
    (set-buffer-modified-p nil)
    (let ((ems--interactive-fn-name 'undo-only)
          events)
      (cl-letf (((symbol-function 'emacsvox-speak-line) #'ignore)
                ((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push icon events))))
        (emacsvox--advice-undo-only-after))
      (should (equal events '(unmodified-object))))))

(provide 'emacsvox-undo-tests)
;;; emacsvox-undo-tests.el ends here
