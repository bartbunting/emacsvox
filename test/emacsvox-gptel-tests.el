;;; emacsvox-gptel-tests.el --- GPTel advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'cl-lib)
(require 'ert)
(require 'package)
(package-initialize)
(require 'gptel)
(require 'gptel-transient)
(load (expand-file-name "../lisp/emacsvox-gptel.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-gptel-advice-is-current-and-direct ()
  "Current GPTel targets use native advice directly."
  (dolist (entry emacsvox-gptel--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target where function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-gptel-feedback-is-target-aware ()
  "Only the matching interactive GPTel command produces feedback."
  (let ((ems--interactive-fn-name 'gptel-menu)
        (gptel-model "test-model")
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'dtk-speak)
               (lambda (text) (push (list 'speak text) events))))
      (emacsvox--advice-gptel-send-after)
      (emacsvox--advice-gptel-menu-after))
    (should
     (equal (nreverse events)
            '((icon open-object)
              (speak "gptel menu, model test-model"))))))

(provide 'emacsvox-gptel-tests)
;;; emacsvox-gptel-tests.el ends here
