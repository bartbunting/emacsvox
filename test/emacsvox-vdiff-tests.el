;;; emacsvox-vdiff-tests.el --- VDiff advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'vdiff)
(load (expand-file-name "../lisp/emacsvox-vdiff.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-vdiff-advice-is-current-and-direct ()
  "Current VDiff targets use native advice directly."
  (dolist (entry emacsvox-vdiff--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target where function) ems--modern-advice-wrappers)))))

(provide 'emacsvox-vdiff-tests)
;;; emacsvox-vdiff-tests.el ends here
