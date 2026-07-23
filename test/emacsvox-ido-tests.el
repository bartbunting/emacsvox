;;; emacsvox-ido-tests.el --- IDO advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated IDO advice.

;;; Code:

(require 'cl-lib)
(require 'ert)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-ido.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--ido-after-targets
  '(ido-switch-buffer ido-switch-buffer-other-window
    ido-switch-buffer-other-frame ido-display-buffer
    ido-find-file ido-find-file-other-frame ido-find-file-other-window
    ido-find-alternate-file ido-find-file-read-only
    ido-find-file-read-only-other-window ido-find-file-read-only-other-frame)
  "IDO commands using generated native after advice.")

(ert-deftest emacsvox-ido-advice-is-directly-registered ()
  "Migrated IDO advice bypasses the compatibility bridge."
  (dolist (target emacsvox-test--ido-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-ido-feedback-is-target-aware ()
  "Only the matching interactive IDO command produces feedback."
  (let ((ems--interactive-fn-name 'ido-find-file-other-window)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'speak-mode-line events))))
      (emacsvox--advice-ido-find-file-after)
      (emacsvox--advice-ido-find-file-other-window-after))
    (should
     (equal
      (nreverse events)
      '((icon open-object) speak-mode-line)))))

(provide 'emacsvox-ido-tests)
;;; emacsvox-ido-tests.el ends here
