;;; emacsvox-rg-tests.el --- rg advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'rg)
(load (expand-file-name "../lisp/emacsvox-rg.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-rg-advice-is-current-and-direct ()
  "Current rg targets use native advice directly."
  (dolist (entry emacsvox-rg--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(provide 'emacsvox-rg-tests)
;;; emacsvox-rg-tests.el ends here
