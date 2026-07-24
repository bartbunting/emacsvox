;;; emacsvox-py-tests.el --- Python Mode advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'python-mode)
(defvar emacsvox-comint-autospeak)
(load (expand-file-name "../lisp/emacsvox-py.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-py-current-advice-is-direct ()
  "Every available Python Mode target bypasses the bridge."
  (dolist (entry emacsvox-py--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (fboundp target)
        (should (advice-member-p function target))
        (should-not
         (gethash (list target where function)
                  ems--modern-advice-wrappers))))))

(ert-deftest emacsvox-py-electric-delete-calls-original-once ()
  "Electric deletion invokes its original command exactly once."
  (with-temp-buffer
    (insert "x")
    (let ((calls 0)
          (ems--interactive-fn-name 'py-electric-delete))
      (cl-letf (((symbol-function 'dtk-tone) #'ignore)
                ((symbol-function 'emacsvox-speak-this-char) #'ignore))
        (should
         (eq
          'deleted
          (emacsvox--advice-py-electric-delete-around
           (lambda (&rest _) (cl-incf calls) 'deleted)))))
      (should (= calls 1)))))

(ert-deftest emacsvox-py-process-filter-calls-original-once ()
  "Process output passes explicit arguments once and preserves its result."
  (with-temp-buffer
    (let ((calls 0)
          received
          (emacsvox-comint-autospeak nil))
      (should
       (eq
        'filtered
        (emacsvox--advice-py-process-filter-around
         (lambda (process output)
           (cl-incf calls)
           (setq received (list process output))
           'filtered)
         'process "output")))
      (should (= calls 1))
      (should (equal received '(process "output"))))))

(provide 'emacsvox-py-tests)
;;; emacsvox-py-tests.el ends here
