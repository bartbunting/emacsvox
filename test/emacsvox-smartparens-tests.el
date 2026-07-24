;;; emacsvox-smartparens-tests.el --- Smartparens advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(mapc #'require '(smartparens smartparens-html smartparens-ruby))
(load (expand-file-name "../lisp/emacsvox-smartparens.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-smartparens-advice-is-current-and-direct ()
  "Current Smartparens targets use native advice directly."
  (dolist (entry emacsvox-smartparens--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-smartparens-delete-calls-original-once ()
  "Smartparens deletion advice preserves the result and calls once."
  (with-temp-buffer
    (insert "x")
    (let ((ems--interactive-fn-name 'sp-backward-delete-char)
          (calls 0))
      (cl-letf (((symbol-function 'emacsvox-icon) #'ignore)
                ((symbol-function 'emacsvox-speak-this-char) #'ignore))
        (should
         (eq 'deleted
             (emacsvox--advice-sp-backward-delete-char-around
              (lambda (&rest _)
                (cl-incf calls)
                'deleted)
              1)))
        (should (= calls 1))))))

(provide 'emacsvox-smartparens-tests)
;;; emacsvox-smartparens-tests.el ends here
