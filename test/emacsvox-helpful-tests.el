;;; emacsvox-helpful-tests.el --- Helpful advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'helpful)
(load (expand-file-name "../lisp/emacsvox-helpful.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-helpful-advice-is-current-and-direct ()
  "Current Helpful targets use native advice directly."
  (dolist (entry emacsvox-helpful--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target where function) ems--modern-advice-wrappers)))))

(provide 'emacsvox-helpful-tests)
;;; emacsvox-helpful-tests.el ends here
