;;; emacsvox-nov-tests.el --- Nov advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'nov)
(load (expand-file-name "../lisp/emacsvox-nov.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-nov-advice-is-current-and-direct ()
  "Current Nov targets use native advice directly."
  (dolist (entry emacsvox-nov--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target where function) ems--modern-advice-wrappers)))))

(provide 'emacsvox-nov-tests)
;;; emacsvox-nov-tests.el ends here
