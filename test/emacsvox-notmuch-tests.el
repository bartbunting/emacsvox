;;; emacsvox-notmuch-tests.el --- Notmuch advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'notmuch)
(load (expand-file-name "../lisp/emacsvox-notmuch.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-notmuch-advice-is-current-and-direct ()
  "Current Notmuch targets use native advice directly."
  (dolist (entry emacsvox-notmuch--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(provide 'emacsvox-notmuch-tests)
;;; emacsvox-notmuch-tests.el ends here
