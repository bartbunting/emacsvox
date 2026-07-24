;;; emacsvox-iedit-tests.el --- Iedit advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'iedit)
(load (expand-file-name "../lisp/emacsvox-iedit.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-iedit-advice-is-current-and-direct ()
  "Current Iedit targets use native advice directly."
  (dolist (entry emacsvox-iedit--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(provide 'emacsvox-iedit-tests)
;;; emacsvox-iedit-tests.el ends here
