;;; emacsvox-comint-tests.el --- Comint advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Comint advice.

;;; Code:

(require 'ert)
(require 'comint)
(require 'shell)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-comint.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--comint-removed-targets
  '(comint-dynamic-complete comint-kill-output)
  "Comint commands absent from Emacs 31.")

(ert-deftest emacsvox-comint-obsolete-targets-remain-absent ()
  "The integration must not recreate commands removed before Emacs 31."
  (dolist (target emacsvox-test--comint-removed-targets)
    (should-not (fboundp target))))

(ert-deftest emacsvox-comint-emacs31-replacement-targets-exist ()
  "Current completion and output-deletion facilities are available."
  (dolist (target
           '(completion-at-point
             comint-completion-at-point
             comint-delete-output))
    (should (fboundp target)))
  (with-temp-buffer
    (comint-mode)
    (should
     (equal completion-at-point-functions
            '(comint-completion-at-point t)))
    (should (eq (key-binding (kbd "TAB")) 'indent-for-tab-command))
    (should (eq (key-binding (kbd "C-c C-o")) 'comint-delete-output))))

(defconst emacsvox-test--comint-navigation-history-after-targets
  '(comint-history-isearch-backward
    comint-history-isearch-backward-regexp
    comint-next-matching-input-from-input
    comint-previous-matching-input-from-input
    shell-forward-command
    shell-backward-command
    comint-show-output
    comint-show-maximum-output
    comint-bol-or-process-mark
    comint-copy-old-input
    comint-next-input
    comint-next-matching-input
    comint-previous-input
    comint-previous-matching-input
    comint-previous-prompt
    comint-next-prompt
    comint-get-next-from-history)
  "Comint navigation and history commands with direct after advice.")

(ert-deftest emacsvox-comint-navigation-history-advice-is-directly-registered ()
  "Comint navigation and history advice bypasses the bridge."
  (dolist (target emacsvox-test--comint-navigation-history-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-comint-navigation-feedback-is-target-aware ()
  "Only matching interactive Comint navigation speaks and cues."
  (let ((ems--interactive-fn-name 'shell-forward-command)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda (&rest _) (push 'line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-shell-backward-command-after)
      (emacsvox--advice-shell-forward-command-after))
    (should
     (equal
      (nreverse events)
      '(line (icon item))))))

(provide 'emacsvox-comint-tests)
;;; emacsvox-comint-tests.el ends here
