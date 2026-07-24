;;; emacsvox-journalctl-tests.el --- journalctl advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'journalctl-mode)
(load (expand-file-name "../lisp/emacsvox-journalctl.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-journalctl-advice-is-current-and-direct ()
  "Current journalctl-mode targets use native advice directly."
  (dolist (entry emacsvox-journalctl--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target where function) ems--modern-advice-wrappers)))))

(provide 'emacsvox-journalctl-tests)
;;; emacsvox-journalctl-tests.el ends here
