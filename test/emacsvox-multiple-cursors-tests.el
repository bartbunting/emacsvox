;;; emacsvox-multiple-cursors-tests.el --- multiple-cursors tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'multiple-cursors)
(load (expand-file-name "../lisp/emacsvox-multiple-cursors.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-multiple-cursors-advice-is-current-and-direct ()
  "Current multiple-cursors targets use native advice directly."
  (dolist (entry emacsvox-multiple-cursors--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(provide 'emacsvox-multiple-cursors-tests)
;;; emacsvox-multiple-cursors-tests.el ends here
