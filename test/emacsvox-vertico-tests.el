;;; emacsvox-vertico-tests.el --- Vertico advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'vertico)
(load (expand-file-name "../lisp/emacsvox-vertico.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-vertico-advice-is-current-and-direct ()
  "Current Vertico targets use native advice directly."
  (dolist (entry emacsvox-vertico--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target where function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-vertico-insert-calls-original-once ()
  "Vertico insertion advice preserves the result and calls once."
  (with-temp-buffer
    (let ((calls 0))
      (cl-letf (((symbol-function 'emacsvox-icon) #'ignore)
                ((symbol-function 'emacsvox-speak-region) #'ignore))
        (should
         (eq 'inserted
             (emacsvox--advice-vertico-insert-around
              (lambda ()
                (cl-incf calls)
                (insert "candidate")
                'inserted))))
        (should (= calls 1))))))

(provide 'emacsvox-vertico-tests)
;;; emacsvox-vertico-tests.el ends here
