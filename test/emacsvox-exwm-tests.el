;;; emacsvox-exwm-tests.el --- EXWM advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(mapc #'require '(exwm exwm-floating exwm-input exwm-layout exwm-workspace))
(load (expand-file-name "../lisp/emacsvox-exwm.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-exwm-advice-is-current-and-direct ()
  "Current EXWM targets use native advice directly."
  (dolist (entry emacsvox-exwm--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-exwm-prompt-advice-uses-native-argument ()
  "Workspace prompt advice speaks its explicit PROMPT argument."
  (let (spoken)
    (cl-letf (((symbol-function 'dtk-speak)
               (lambda (text) (setq spoken text))))
      (emacsvox--advice-exwm-workspace--prompt-for-workspace-before
       "Workspace: "))
    (should (equal spoken "Workspace: "))))

(provide 'emacsvox-exwm-tests)
;;; emacsvox-exwm-tests.el ends here
