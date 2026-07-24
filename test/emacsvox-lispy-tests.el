;;; emacsvox-lispy-tests.el --- Lispy advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'lispy)
(load (expand-file-name "../lisp/emacsvox-lispy.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-lispy-advice-is-current-and-direct ()
  "Current Lispy targets use native advice directly."
  (dolist (entry emacsvox-lispy--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target where function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-lispy-navigation-calls-original-once ()
  "Lispy navigation advice preserves the result and calls once."
  (with-temp-buffer
    (let ((ems--interactive-fn-name 'lispy-forward)
          (calls 0))
      (cl-letf (((symbol-function 'dtk-notify) #'ignore)
                ((symbol-function 'emacsvox-icon) #'ignore))
        (should
         (eq 'moved
             (emacsvox--advice-lispy-forward-around
              (lambda ()
                (cl-incf calls)
                'moved))))
        (should (= calls 1))))))

(ert-deftest emacsvox-lispy-show-uses-native-argument ()
  "Lispy display advice speaks its explicit string argument."
  (let (spoken)
    (cl-letf (((symbol-function 'emacsvox-icon) #'ignore)
              ((symbol-function 'dtk-speak)
               (lambda (text) (setq spoken text))))
      (emacsvox--advice-lispy--show-before "details"))
    (should (equal spoken "details"))))

(provide 'emacsvox-lispy-tests)
;;; emacsvox-lispy-tests.el ends here
