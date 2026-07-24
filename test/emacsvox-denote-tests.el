;;; emacsvox-denote-tests.el --- Denote advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'cl-lib)
(require 'ert)
(require 'package)
(package-initialize)
(require 'denote)
(load (expand-file-name "../lisp/emacsvox-denote.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-denote-advice-is-current-and-direct ()
  "Current Denote targets use native advice directly."
  (dolist (entry emacsvox-denote--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target where function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-denote-feedback-is-target-aware ()
  "Only the matching interactive Denote command produces feedback."
  (let ((ems--interactive-fn-name 'denote-link)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'dtk-speak)
               (lambda (text) (push (list 'speak text) events))))
      (emacsvox--advice-denote-rename-file-after)
      (emacsvox--advice-denote-link-after))
    (should
     (equal (nreverse events)
            '((icon complete) (speak "Linked"))))))

(provide 'emacsvox-denote-tests)
;;; emacsvox-denote-tests.el ends here
