;;; emacsvox-package-tests.el --- Package advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Package advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'package)

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
  "Migrated Package advice uses native advice directly."
  (dolist (target emacsvox-test--package-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp function))
      (should (advice-member-p function target))))
  (dolist
      (entry
       '((package-menu-describe-package
          :after emacsvox--advice-package-menu-describe-package-after)
         (package-menu-execute
          :around emacsvox--advice-package-menu-execute-around)
         (package-menu-mark-upgrades
          :after emacsvox--advice-package-menu-mark-upgrades-after)))
    (pcase-let ((`(,target ,where ,function) entry))
      (should (commandp target))
      (should (advice-member-p function target)))))

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

(ert-deftest emacsvox-package-execute-runs-once-quietly ()
  "Package execution preserves its result after one silenced call."
  (let ((calls 0) feedback)
    (cl-letf (((symbol-function 'emacsvox-speak-message-again)
               (lambda () (setq feedback t))))
      (should
       (eq
        'result
        (emacsvox--advice-package-menu-execute-around
         (lambda (&rest arguments)
           (setq calls (1+ calls))
           (should (equal arguments '(t)))
           (should-not emacsvox-speak-messages)
           'result)
         t))))
    (should (= calls 1))
    (should feedback)))

(ert-deftest emacsvox-package-upgrade-feedback-is-target-aware ()
  "Interactive upgrade marking reports the selected package names."
  (let ((ems--interactive-fn-name 'package-menu-mark-upgrades)
        notifications)
    (cl-letf (((symbol-function 'package-menu--find-upgrades)
               (lambda () '((alpha . old) (beta . old))))
              ((symbol-function 'tts-notify)
               (lambda (text) (push text notifications))))
      (emacsvox--advice-package-menu-mark-upgrades-after))
    (should (equal notifications '("(alpha beta)")))))

(provide 'emacsvox-package-tests)
;;; emacsvox-package-tests.el ends here
