;;; emacsvox-marginalia-tests.el --- Marginalia advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'cl-lib)
(require 'ert)
(require 'package)
(package-initialize)
(require 'marginalia)
(load (expand-file-name "../lisp/emacsvox-marginalia.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-marginalia-advice-is-current-and-direct ()
  "Current Marginalia targets use native advice directly."
  (dolist (entry emacsvox-marginalia--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-marginalia-feedback-is-target-aware ()
  "Only the matching interactive Marginalia command produces feedback."
  (let ((ems--interactive-fn-name 'marginalia-cycle)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'dtk-speak)
               (lambda (text) (push (list 'speak text) events))))
      (emacsvox--advice-marginalia-mode-after)
      (emacsvox--advice-marginalia-cycle-after))
    (should
     (equal (nreverse events)
            '((icon select-object)
              (speak "Cycled marginalia annotator."))))))

(provide 'emacsvox-marginalia-tests)
;;; emacsvox-marginalia-tests.el ends here
