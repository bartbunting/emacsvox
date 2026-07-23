;;; emacsvox-tabulated-list-tests.el --- Tabulated List advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Tabulated List advice.

;;; Code:

(require 'cl-lib)
(require 'ert)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-tabulated-list.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--tabulated-list-after-advice
  '((tabulated-list-next-column
     emacsvox--advice-tabulated-list-next-column-after)
    (tabulated-list-previous-column
     emacsvox--advice-tabulated-list-previous-column-after))
  "Native after-advice registrations in the Tabulated List integration.")

(ert-deftest emacsvox-tabulated-list-advice-is-directly-registered ()
  "Tabulated List advice bypasses the compatibility bridge."
  (dolist (entry emacsvox-test--tabulated-list-after-advice)
    (pcase-let ((`(,target ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-tabulated-list-feedback-is-target-aware ()
  "Only the matching column movement cues and speaks the selected cell."
  (let ((ems--interactive-fn-name 'tabulated-list-next-column)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-tabulated-list-speak-cell)
               (lambda () (push 'speak-cell events))))
      (emacsvox--advice-tabulated-list-previous-column-after)
      (emacsvox--advice-tabulated-list-next-column-after))
    (should
     (equal
      (nreverse events)
      '((icon select-object) speak-cell)))))

(provide 'emacsvox-tabulated-list-tests)
;;; emacsvox-tabulated-list-tests.el ends here
