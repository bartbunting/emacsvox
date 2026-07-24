;;; emacsvox-orgalist-tests.el --- Orgalist advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'orgalist)
(load (expand-file-name "../lisp/emacsvox-orgalist.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-orgalist-advice-is-current-and-direct ()
  "Current Orgalist targets use native advice directly."
  (dolist (target emacsvox-orgalist--advice-targets)
    (let ((function (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target :after function) ems--modern-advice-wrappers)))))

(provide 'emacsvox-orgalist-tests)
;;; emacsvox-orgalist-tests.el ends here
