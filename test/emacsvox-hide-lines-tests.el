;;; emacsvox-hide-lines-tests.el --- hide-lines advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'hide-lines)
(load (expand-file-name "../lisp/emacsvox-hide-lines.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-hide-lines-advice-is-current-and-direct ()
  "Current hide-lines targets use native advice directly."
  (dolist (target emacsvox-hide-lines--advice-targets)
    (let ((function (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target :after function) ems--modern-advice-wrappers)))))

(provide 'emacsvox-hide-lines-tests)
;;; emacsvox-hide-lines-tests.el ends here
