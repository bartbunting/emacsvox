;;; emacsvox-sdcv-tests.el --- SDCV advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'sdcv)
(cl-letf (((symbol-function 'shell-command-to-string)
           (lambda (&rest _) "[]")))
  (load (expand-file-name "../lisp/emacsvox-sdcv.el"
                          (file-name-directory
                           (or load-file-name buffer-file-name)))
        nil nil))

(ert-deftest emacsvox-sdcv-advice-is-current-and-direct ()
  "Current SDCV targets use native advice directly."
  (dolist (entry emacsvox-sdcv--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target))))
  (should
   (advice-member-p
    #'emacsvox--advice-sdcv-quit-after
    'sdcv-quit)))

(ert-deftest emacsvox-sdcv-quit-feedback-is-target-aware ()
  "SDCV quit feedback is limited to its interactive command."
  (let (events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'mode-line events))))
      (let ((ems--interactive-fn-name 'other-command))
        (emacsvox--advice-sdcv-quit-after))
      (should-not events)
      (let ((ems--interactive-fn-name 'sdcv-quit))
        (emacsvox--advice-sdcv-quit-after))
      (should (equal (nreverse events) '(close-object mode-line))))))

(provide 'emacsvox-sdcv-tests)
;;; emacsvox-sdcv-tests.el ends here
