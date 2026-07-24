;;; emacsvox-windmove-tests.el --- Windmove advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Windmove advice.

;;; Code:

(require 'cl-lib)
(require 'ert)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-windmove.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--windmove-after-targets
  '(windmove-left windmove-right windmove-up windmove-down)
  "Windmove commands using generated native after advice.")

(ert-deftest emacsvox-windmove-advice-is-directly-registered ()
  "Migrated Windmove advice uses native advice directly."
  (dolist (target emacsvox-test--windmove-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-windmove-feedback-is-target-aware ()
  "Only the matching interactive Windmove command produces feedback."
  (let ((ems--interactive-fn-name 'windmove-right)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'speak-mode-line events))))
      (emacsvox--advice-windmove-left-after)
      (emacsvox--advice-windmove-right-after))
    (should
     (equal
      (nreverse events)
      '((icon select-object) speak-mode-line)))))

(provide 'emacsvox-windmove-tests)
;;; emacsvox-windmove-tests.el ends here
