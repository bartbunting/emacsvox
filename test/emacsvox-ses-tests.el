;;; emacsvox-ses-tests.el --- SES advice tests -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'ses)
(load
 (expand-file-name "../lisp/emacsvox-ses.el"
                   (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(ert-deftest emacsvox-ses-advice-is-directly-registered ()
  (dolist
      (target '(ses-forward-or-insert ses-recalculate-cell ses-jump))
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (commandp target))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-ses-feedback-is-target-aware ()
  (let ((ems--interactive-fn-name 'ses-recalculate-cell) events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-ses-summarize-current-cell)
               (lambda () (push 'cell events))))
      (emacsvox--advice-ses-forward-or-insert-after)
      (emacsvox--advice-ses-recalculate-cell-after)
      (emacsvox--advice-ses-jump-after))
    (should (equal (nreverse events) '(cell task-done)))))

(provide 'emacsvox-ses-tests)
