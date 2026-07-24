;;; emacsvox-haskell-tests.el --- Haskell advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(mapc #'require '(haskell-mode haskell-cabal haskell-indentation))
(load (expand-file-name "../lisp/emacsvox-haskell.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-haskell-advice-is-current-and-direct ()
  "Current Haskell targets use native advice directly."
  (dolist (entry emacsvox-haskell--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target where function) ems--modern-advice-wrappers)))))

(provide 'emacsvox-haskell-tests)
;;; emacsvox-haskell-tests.el ends here
