;;; emacsvox-forge-tests.el --- Forge advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'forge)
(load (expand-file-name "../lisp/emacsvox-forge.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-forge-advice-is-current-and-direct ()
  "Current Forge targets use native advice directly."
  (dolist (target emacsvox-forge--advice-targets)
    (let ((function (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target :after function) ems--modern-advice-wrappers)))))

(provide 'emacsvox-forge-tests)
;;; emacsvox-forge-tests.el ends here
