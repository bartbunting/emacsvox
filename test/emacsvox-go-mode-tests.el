;;; emacsvox-go-mode-tests.el --- Go mode advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'go-mode)
(load (expand-file-name "../lisp/emacsvox-go-mode.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-go-mode-advice-is-current-and-direct ()
  "Current Go mode targets use native advice directly."
  (dolist (entry emacsvox-go-mode--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(provide 'emacsvox-go-mode-tests)
;;; emacsvox-go-mode-tests.el ends here
