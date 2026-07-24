;;; emacsvox-muse-tests.el --- Muse advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'muse-mode)
(load (expand-file-name "../lisp/emacsvox-muse.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-muse-advice-is-current-and-direct ()
  "Current Muse targets use native advice directly."
  (dolist (target emacsvox-muse--advice-targets)
    (let ((function (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(provide 'emacsvox-muse-tests)
;;; emacsvox-muse-tests.el ends here
