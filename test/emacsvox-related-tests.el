;;; emacsvox-related-tests.el --- Related advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'related)
(load (expand-file-name "../lisp/emacsvox-related.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-related-advice-is-current-and-direct ()
  "Current Related targets use native advice directly."
  (dolist (target emacsvox-related--advice-targets)
    (let ((function (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target :after function) ems--modern-advice-wrappers)))))

(provide 'emacsvox-related-tests)
;;; emacsvox-related-tests.el ends here
