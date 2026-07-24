;;; emacsvox-corfu-tests.el --- Corfu advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'corfu)
(load (expand-file-name "../lisp/emacsvox-corfu.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-corfu-advice-is-current-and-direct ()
  "Current Corfu targets bypass the compatibility bridge."
  (dolist (entry emacsvox-corfu--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target where function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-corfu-navigation-is-target-aware ()
  "Only the matching interactive Corfu navigation command speaks."
  (let ((ems--interactive-fn-name 'corfu-next)
        (calls 0))
    (cl-letf (((symbol-function 'emacsvox-corfu--speak-candidate)
               (lambda () (cl-incf calls))))
      (emacsvox--advice-corfu-previous-after)
      (emacsvox--advice-corfu-next-after))
    (should (= calls 1))))

(provide 'emacsvox-corfu-tests)
;;; emacsvox-corfu-tests.el ends here
