;;; emacsvox-pipewire-tests.el --- Pipewire advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'pipewire)
(load (expand-file-name "../lisp/emacsvox-pipewire.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-pipewire-advice-is-current-and-direct ()
  "Current Pipewire targets use native advice directly."
  (dolist (entry emacsvox-pipewire--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target where function) ems--modern-advice-wrappers)))))

(provide 'emacsvox-pipewire-tests)
;;; emacsvox-pipewire-tests.el ends here
