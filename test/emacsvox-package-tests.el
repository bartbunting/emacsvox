;;; emacsvox-package-tests.el --- Package advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Package advice.

;;; Code:

(require 'cl-lib)
(require 'ert)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-package.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--package-after-targets
  '(package-menu-mark-delete package-menu-mark-install package-show-package-list
    package-menu-mark-unmark package-menu-backup-unmark)
  "Package commands using generated native after advice.")

(ert-deftest emacsvox-package-advice-is-directly-registered ()
  "Migrated Package advice bypasses the compatibility bridge."
  (dolist (target emacsvox-test--package-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-package-feedback-is-target-aware ()
  "Only the matching interactive Package command produces feedback."
  (let ((ems--interactive-fn-name 'package-menu-mark-install)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-package-menu-mark-delete-after)
      (emacsvox--advice-package-menu-mark-install-after))
    (should
     (equal
      (nreverse events)
      '(speak-line (icon mark-object))))))

(provide 'emacsvox-package-tests)
;;; emacsvox-package-tests.el ends here
