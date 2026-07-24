;;; emacsvox-projectile-tests.el --- Projectile advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'projectile)
(load (expand-file-name "../lisp/emacsvox-projectile.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-projectile-advice-is-current-and-direct ()
  "Current Projectile targets use native advice directly."
  (dolist (entry emacsvox-projectile--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target where function) ems--modern-advice-wrappers)))))

(provide 'emacsvox-projectile-tests)
;;; emacsvox-projectile-tests.el ends here
