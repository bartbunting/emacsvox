;;; emacsvox-embark-tests.el --- Embark advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'cl-lib)
(require 'ert)
(require 'package)
(package-initialize)
(require 'embark)
(load (expand-file-name "../lisp/emacsvox-embark.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-embark-advice-is-current-and-direct ()
  "Current Embark targets use native advice directly."
  (dolist (entry emacsvox-embark--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-embark-feedback-is-target-aware ()
  "Only the matching interactive Embark command produces feedback."
  (let ((ems--interactive-fn-name 'embark-become)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'mode-line events))))
      (emacsvox--advice-embark-act-after)
      (emacsvox--advice-embark-become-after))
    (should
     (equal (nreverse events)
            '((icon select-object) mode-line)))))

(provide 'emacsvox-embark-tests)
;;; emacsvox-embark-tests.el ends here
