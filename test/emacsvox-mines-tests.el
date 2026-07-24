;;; emacsvox-mines-tests.el --- Mines advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'mines)
(load (expand-file-name "../lisp/emacsvox-mines.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-mines-advice-is-current-and-direct ()
  "Current Mines targets use native advice directly."
  (dolist (entry emacsvox-mines--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target where function) ems--modern-advice-wrappers)))))

(provide 'emacsvox-mines-tests)
;;; emacsvox-mines-tests.el ends here
