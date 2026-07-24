;;; emacsvox-js2-tests.el --- JS2 advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'js2-mode)
(load (expand-file-name "../lisp/emacsvox-js2.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-js2-advice-is-current-and-direct ()
  "Current JS2 targets use native advice directly."
  (dolist (entry emacsvox-js2--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target where function) ems--modern-advice-wrappers)))))

(provide 'emacsvox-js2-tests)
;;; emacsvox-js2-tests.el ends here
