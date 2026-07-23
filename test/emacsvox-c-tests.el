;;; emacsvox-c-tests.el --- C mode advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated CC Mode advice.

;;; Code:

(require 'ert)
(require 'cc-mode)
(require 'cc-awk)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-c.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(ert-deftest emacsvox-c-obsolete-targets-remain-absent ()
  "The integration must not recreate commands absent from Emacs 31."
  (dolist (target '(c-awk-end-of-defunm c-toggle-auto-state))
    (should-not (fboundp target))))

(ert-deftest emacsvox-c-emacs31-awk-targets-and-bindings-exist ()
  "Current AWK navigation commands and bindings are available."
  (dolist (target '(c-awk-beginning-of-defun c-awk-end-of-defun))
    (should (fboundp target)))
  (with-temp-buffer
    (awk-mode)
    (should
     (eq (key-binding (kbd "C-M-a")) 'c-awk-beginning-of-defun))
    (should (eq (key-binding (kbd "C-M-e")) 'c-awk-end-of-defun))))

(ert-deftest emacsvox-c-custom-navigation-bindings-are-installed ()
  "Emacsvox C statement navigation retains its established bindings."
  (with-temp-buffer
    (c-mode)
    (should
     (eq (key-binding (kbd "C-c s")) 'emacsvox-c-speak-semantics))
    (should (eq (key-binding (kbd "M-n")) 'c-next-statement))
    (should (eq (key-binding (kbd "M-p")) 'c-previous-statement))))

(provide 'emacsvox-c-tests)
;;; emacsvox-c-tests.el ends here
