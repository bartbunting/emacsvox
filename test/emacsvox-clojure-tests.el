;;; emacsvox-clojure-tests.el --- Clojure Mode advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'clojure-mode)
(load (expand-file-name "../lisp/emacsvox-clojure.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-clojure-advice-is-current-and-direct ()
  "Current Clojure Mode targets bypass the compatibility bridge."
  (dolist (entry emacsvox-clojure--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target where function) ems--modern-advice-wrappers))))
  (should-not (fboundp 'clojure-view-grimoire)))

(ert-deftest emacsvox-clojure-feedback-is-target-aware ()
  "Only the matching interactive Clojure command speaks."
  (let ((ems--interactive-fn-name 'clojure-cycle-when)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events))))
      (emacsvox--advice-clojure-cycle-not-after)
      (emacsvox--advice-clojure-cycle-when-after))
    (should (equal (nreverse events) '(button line)))))

(provide 'emacsvox-clojure-tests)
;;; emacsvox-clojure-tests.el ends here
