;;; emacsvox-elisp-refs-tests.el --- Elisp Refs advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'elisp-refs)
(load (expand-file-name "../lisp/emacsvox-elisp-refs.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-elisp-refs-advice-is-current-and-direct ()
  "Current Elisp Refs targets use native advice directly."
  (dolist (target emacsvox-elisp-refs--advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-elisp-refs-feedback-is-target-aware ()
  "Only the matching interactive Elisp Refs command speaks."
  (let ((ems--interactive-fn-name 'elisp-refs-next-match)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events))))
      (emacsvox--advice-elisp-refs-prev-match-after)
      (emacsvox--advice-elisp-refs-next-match-after))
    (should (equal (nreverse events) '(select-object line)))))

(provide 'emacsvox-elisp-refs-tests)
;;; emacsvox-elisp-refs-tests.el ends here
