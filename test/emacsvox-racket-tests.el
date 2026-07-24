;;; emacsvox-racket-tests.el --- Racket advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(mapc #'require '(racket-mode racket-collection racket-profile
                  racket-xp))
(load (expand-file-name "../lisp/emacsvox-racket.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-racket-advice-is-current-and-direct ()
  "Current Racket targets use native advice directly."
  (dolist (entry emacsvox-racket--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(provide 'emacsvox-racket-tests)
;;; emacsvox-racket-tests.el ends here
