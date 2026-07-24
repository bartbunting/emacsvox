;;; emacsvox-typo-tests.el --- Typo advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'typo)
(load (expand-file-name "../lisp/emacsvox-typo.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-typo-advice-is-current-and-direct ()
  "Current Typo targets use native advice directly."
  (dolist (target emacsvox-typo--advice-targets)
    (let ((function (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target :after function) ems--modern-advice-wrappers)))))

(provide 'emacsvox-typo-tests)
;;; emacsvox-typo-tests.el ends here
