;;; emacsvox-paradox-tests.el --- Paradox advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'paradox)
(load (expand-file-name "../lisp/emacsvox-paradox.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-paradox-advice-is-current-and-direct ()
  "Current Paradox targets use native advice directly."
  (dolist (entry emacsvox-paradox--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target where function) ems--modern-advice-wrappers)))))

(provide 'emacsvox-paradox-tests)
;;; emacsvox-paradox-tests.el ends here
