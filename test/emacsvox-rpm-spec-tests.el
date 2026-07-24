;;; emacsvox-rpm-spec-tests.el --- rpm-spec advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'rpm-spec-mode)
(load (expand-file-name "../lisp/emacsvox-rpm-spec.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-rpm-spec-advice-is-current-and-direct ()
  "Current rpm-spec targets use native advice directly."
  (dolist (entry emacsvox-rpm-spec--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(provide 'emacsvox-rpm-spec-tests)
;;; emacsvox-rpm-spec-tests.el ends here
