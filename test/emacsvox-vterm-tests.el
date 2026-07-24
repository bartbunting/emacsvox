;;; emacsvox-vterm-tests.el --- Vterm advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)

;; Loading the Elisp interface does not need to compile the optional native
;; module.  Supply only the module entry point advised by Emacsvox.
(unless (featurep 'vterm-module)
  (defun vterm--redraw (&rest _))
  (provide 'vterm-module))
(require 'vterm)
(load (expand-file-name "../lisp/emacsvox-vterm.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-vterm-advice-is-current-and-direct ()
  "Current Vterm targets use native advice directly."
  (dolist (entry emacsvox-vterm--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target where function) ems--modern-advice-wrappers)))))

(provide 'emacsvox-vterm-tests)
;;; emacsvox-vterm-tests.el ends here
