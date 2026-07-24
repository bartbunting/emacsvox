;;; emacsvox-slime-tests.el --- Slime advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'slime)
(slime-setup '(slime-fancy slime-asdf))
(load (expand-file-name "../lisp/emacsvox-slime.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-slime-advice-is-current-and-direct ()
  "Current Slime targets use native advice directly."
  (dolist (entry emacsvox-slime--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target where function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-slime-completion-calls-original-once ()
  "Slime completion advice preserves the result and calls once."
  (with-temp-buffer
    (insert "cl")
    (let ((ems--interactive-fn-name 'slime-complete-symbol)
          (calls 0))
      (cl-letf (((symbol-function 'dtk-speak) #'ignore)
                ((symbol-function 'emacsvox-speak-completions-if-available)
                 #'ignore))
        (should
         (eq 'completed
             (emacsvox--advice-slime-complete-symbol-around
              (lambda ()
                (cl-incf calls)
                (insert "ear")
                'completed))))
        (should (= calls 1))))))

(provide 'emacsvox-slime-tests)
;;; emacsvox-slime-tests.el ends here
