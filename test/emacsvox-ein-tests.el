;;; emacsvox-ein-tests.el --- EIN advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(dolist (feature
         '(ein ein-cell ein-classes ein-notebook ein-notebooklist
               ein-pytools ein-traceback ein-worksheet))
  (require feature))
(load (expand-file-name "../lisp/emacsvox-ein.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-ein-advice-is-current-and-direct ()
  "Current EIN targets use native advice directly."
  (dolist (entry emacsvox-ein--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target))))
  (dolist (target emacsvox-ein--removed-targets)
    (should-not (fboundp target))))

(ert-deftest emacsvox-ein-feedback-is-target-aware ()
  "Only the matching interactive EIN command provides feedback."
  (let ((ems--interactive-fn-name 'ein:tb-next-item)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events))))
      (emacsvox--advice-ein:tb-prev-item-after)
      (emacsvox--advice-ein:tb-next-item-after))
    (should (equal (nreverse events) '(line large-movement)))))

(ert-deftest emacsvox-ein-yank-cell-feedback-is-consolidated ()
  "Yanking a cell gives one current-cell announcement and one icon."
  (let ((ems--interactive-fn-name 'ein:worksheet-yank-cell)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-ein-speak-current-cell)
               (lambda () (push 'cell events))))
      (emacsvox--advice-ein:worksheet-yank-cell-after))
    (should (equal (nreverse events) '(cell yank-object)))))

(provide 'emacsvox-ein-tests)
;;; emacsvox-ein-tests.el ends here
