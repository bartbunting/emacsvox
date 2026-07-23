;;; emacsvox-diff-mode-tests.el --- Diff Mode advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Diff Mode advice.

;;; Code:

(require 'cl-lib)
(require 'ert)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-diff-mode.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--diff-mode-after-targets
  '(diff-next-complex-hunk
    diff-hunk-prev diff-hunk-next
    diff-file-next diff-file-prev)
  "Diff Mode commands using generated native after advice.")

(ert-deftest emacsvox-diff-mode-advice-is-directly-registered ()
  "Migrated Diff Mode advice bypasses the compatibility bridge."
  (dolist (target emacsvox-test--diff-mode-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-diff-mode-feedback-is-target-aware ()
  "Only the matching interactive Diff Mode command produces feedback."
  (let ((ems--interactive-fn-name 'diff-hunk-next)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events))))
      (emacsvox--advice-diff-hunk-prev-after)
      (emacsvox--advice-diff-hunk-next-after))
    (should
     (equal
      (nreverse events)
      '((icon large-movement) speak-line)))))

(provide 'emacsvox-diff-mode-tests)
;;; emacsvox-diff-mode-tests.el ends here
