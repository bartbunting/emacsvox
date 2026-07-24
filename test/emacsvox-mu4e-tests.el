;;; emacsvox-mu4e-tests.el --- Mu4e advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)

(defconst emacsvox-mu4e-test--available (require 'mu4e nil t)
  "Non-nil when the optional Mu4e system package is installed.")

(load (expand-file-name "../lisp/emacsvox-mu4e.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-mu4e-advice-is-current-and-direct ()
  "Current Mu4e targets use native advice directly."
  (skip-unless emacsvox-mu4e-test--available)
  (mapc #'require '(mu4e-compose mu4e-headers mu4e-mark mu4e-search
                    mu4e-update mu4e-view))
  (emacsvox-mu4e--install-advice)
  (dolist (entry emacsvox-mu4e--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target where function) ems--modern-advice-wrappers)))))

(provide 'emacsvox-mu4e-tests)
;;; emacsvox-mu4e-tests.el ends here
