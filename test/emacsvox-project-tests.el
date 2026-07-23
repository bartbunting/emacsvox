;;; emacsvox-project-tests.el --- Project advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Project advice.

;;; Code:

(require 'cl-lib)
(require 'ert)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-project.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--project-after-targets
  '(project-vc-dir project-switch-to-buffer project-find-file project-dired)
  "Project commands using generated native after advice.")

(ert-deftest emacsvox-project-advice-is-directly-registered ()
  "Migrated Project advice bypasses the compatibility bridge."
  (dolist (target emacsvox-test--project-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-project-feedback-is-target-aware ()
  "Only the matching interactive Project command produces feedback."
  (let ((ems--interactive-fn-name 'project-find-file)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'speak-mode-line events))))
      (emacsvox--advice-project-dired-after)
      (emacsvox--advice-project-find-file-after))
    (should
     (equal
      (nreverse events)
      '((icon open-object) speak-mode-line)))))

(provide 'emacsvox-project-tests)
;;; emacsvox-project-tests.el ends here
