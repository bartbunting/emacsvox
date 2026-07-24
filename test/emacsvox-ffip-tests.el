;;; emacsvox-ffip-tests.el --- FFIP advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'find-file-in-project)
(load (expand-file-name "../lisp/emacsvox-ffip.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-ffip-advice-is-current-and-direct ()
  "Current FFIP targets use native advice directly."
  (dolist (target emacsvox-ffip--advice-targets)
    (let ((function (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target :after function) ems--modern-advice-wrappers)))))

(provide 'emacsvox-ffip-tests)
;;; emacsvox-ffip-tests.el ends here
