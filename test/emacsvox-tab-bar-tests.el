;;; emacsvox-tab-bar-tests.el --- Tab Bar advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Tab Bar advice.

;;; Code:

(require 'ert)
(require 'tab-bar)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-tab-bar.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--tab-bar-removed-list-targets
  '(tab-bar-list
    tab-bar-list-execute
    tab-bar-list-prev-line
    tab-bar-list-next-line
    tab-bar-list-unmark
    tab-bar-list-delete
    tab-bar-list-delete-backwards
    tab-bar-list-select)
  "Tab-list commands absent from Emacs 31.")

(ert-deftest emacsvox-tab-bar-obsolete-list-targets-remain-absent ()
  "The integration must not recreate commands removed before Emacs 31."
  (dolist (target emacsvox-test--tab-bar-removed-list-targets)
    (should-not (fboundp target))))

(ert-deftest emacsvox-tab-bar-emacs31-switcher-targets-exist ()
  "Current Tab Switcher commands and bindings are available."
  (dolist
      (target
       '(tab-list
         tab-switcher
         tab-switcher-execute
         tab-switcher-prev-line
         tab-switcher-next-line
         tab-switcher-unmark
         tab-switcher-delete
         tab-switcher-delete-backwards
         tab-switcher-select))
    (should (fboundp target)))
  (with-temp-buffer
    (tab-switcher-mode)
    (should (eq (key-binding (kbd "RET")) 'tab-switcher-select))
    (should (eq (key-binding (kbd "d")) 'tab-switcher-delete))
    (should (eq (key-binding (kbd "x")) 'tab-switcher-execute))
    (should (eq (key-binding (kbd "n")) 'tab-switcher-next-line))
    (should (eq (key-binding (kbd "p")) 'tab-switcher-prev-line))))

(provide 'emacsvox-tab-bar-tests)
;;; emacsvox-tab-bar-tests.el ends here
