;;; emacsvox-elfeed-tests.el --- Elfeed advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(dolist (feature '(elfeed elfeed-db elfeed-search elfeed-show))
  (require feature))
(load (expand-file-name "../lisp/emacsvox-elfeed.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-elfeed-advice-is-current-and-direct ()
  "Current Elfeed targets use native advice directly."
  (dolist (entry emacsvox-elfeed--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target where function) ems--modern-advice-wrappers))))
  (dolist (target emacsvox-elfeed--removed-targets)
    (should-not (fboundp target))))

(ert-deftest emacsvox-elfeed-feedback-is-target-aware ()
  "Only the matching interactive Elfeed command provides feedback."
  (let ((ems--interactive-fn-name 'elfeed-show-tag)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events))))
      (emacsvox--advice-elfeed-show-untag-after)
      (emacsvox--advice-elfeed-show-tag-after))
    (should (equal (nreverse events) '(select-object line)))))

(ert-deftest emacsvox-elfeed-silencing-advice-preserves-result ()
  "The Elfeed around advice calls its original exactly once."
  (let ((calls 0))
    (should
     (eq 'result
         (emacsvox--advice-elfeed-update-around
          (lambda (&rest _)
            (cl-incf calls)
            'result))))
    (should (= calls 1))))

(provide 'emacsvox-elfeed-tests)
;;; emacsvox-elfeed-tests.el ends here
