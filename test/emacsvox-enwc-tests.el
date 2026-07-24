;;; emacsvox-enwc-tests.el --- ENWC advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'enwc)
(load (expand-file-name "../lisp/emacsvox-enwc.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-enwc-advice-is-current-and-direct ()
  "Current ENWC targets use native advice directly."
  (dolist (target emacsvox-enwc--advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-enwc-feedback-is-target-aware ()
  "Only the matching interactive ENWC connection command speaks."
  (let ((ems--interactive-fn-name 'enwc-connect-to-network)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events))))
      (emacsvox--advice-enwc-connect-to-network-at-point-after)
      (emacsvox--advice-enwc-connect-to-network-after))
    (should (equal events '(select-object)))))

(provide 'emacsvox-enwc-tests)
;;; emacsvox-enwc-tests.el ends here
