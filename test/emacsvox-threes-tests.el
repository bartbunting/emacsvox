;;; emacsvox-threes-tests.el --- Threes advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'threes)
(load (expand-file-name "../lisp/emacsvox-threes.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-threes-advice-is-current-and-direct ()
  "Current Threes targets use native advice directly."
  (dolist (entry emacsvox-threes--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target where function) ems--modern-advice-wrappers)))))

(provide 'emacsvox-threes-tests)
;;; emacsvox-threes-tests.el ends here
