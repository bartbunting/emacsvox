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

(provide 'emacsvox-comint-tests)
;;; emacsvox-comint-tests.el ends here
