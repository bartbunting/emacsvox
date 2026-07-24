;;; emacsvox-calibredb-tests.el --- Calibredb advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'calibredb)
(load (expand-file-name "../lisp/emacsvox-calibredb.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-calibredb-advice-is-current-and-direct ()
  "Current Calibredb targets bypass the compatibility bridge."
  (dolist (entry emacsvox-calibredb--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target where function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-calibredb-movement-feedback-is-target-aware ()
  "Only the matching interactive movement command speaks."
  (let ((ems--interactive-fn-name 'calibredb-next-entry)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events))))
      (emacsvox--advice-calibredb-previous-entry-after)
      (emacsvox--advice-calibredb-next-entry-after))
    (should (equal (nreverse events) '(select-object line)))))

(provide 'emacsvox-calibredb-tests)
;;; emacsvox-calibredb-tests.el ends here
