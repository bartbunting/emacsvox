;;; emacsvox-sdcv-tests.el --- SDCV advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'sdcv)
(cl-letf (((symbol-function 'shell-command-to-string)
           (lambda (&rest _) "[]")))
  (load (expand-file-name "../lisp/emacsvox-sdcv.el"
                          (file-name-directory
                           (or load-file-name buffer-file-name)))
        nil nil))

(ert-deftest emacsvox-sdcv-advice-is-current-and-direct ()
  "Current SDCV targets use native advice directly."
  (dolist (entry emacsvox-sdcv--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(provide 'emacsvox-sdcv-tests)
;;; emacsvox-sdcv-tests.el ends here
