;;; emacsvox-info-tests.el --- Info advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Info advice.

;;; Code:

(require 'cl-lib)
(require 'ert)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-info.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--info-after-targets
  '(info info-display-manual Info-select-node
    Info-follow-reference Info-goto-node info-emacs-manual
    Info-top-node Info-menu-last-node Info-final-node Info-up
    Info-goto-emacs-key-command-node Info-goto-emacs-command-node
    Info-history Info-virtual-index Info-directory Info-help
    Info-nth-menu-item Info-menu Info-follow-nearest-node
    Info-history-back Info-history-forward
    Info-backward-node Info-forward-node Info-next Info-prev)
  "Info commands using generated native after advice.")

(ert-deftest emacsvox-info-advice-is-directly-registered ()
  "Migrated Info advice bypasses the compatibility bridge."
  (dolist (target emacsvox-test--info-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-info-feedback-is-target-aware ()
  "Only the matching interactive Info command speaks the selected node."
  (let ((ems--interactive-fn-name 'Info-history-forward)
        events)
    (cl-letf (((symbol-function 'emacsvox-info-visit-node)
               (lambda () (push 'visit-node events))))
      (emacsvox--advice-Info-history-back-after)
      (emacsvox--advice-Info-history-forward-after))
    (should (equal events '(visit-node)))))

(provide 'emacsvox-info-tests)
;;; emacsvox-info-tests.el ends here
