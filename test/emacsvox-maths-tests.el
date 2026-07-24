;;; emacsvox-maths-tests.el --- Maths advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'cl-lib)
(require 'ert)
(require 'package)
(package-initialize)
(require 'preview)
(load (expand-file-name "../lisp/emacsvox-maths.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-maths-advice-is-current-and-direct ()
  "The current preview target uses native advice directly."
  (dolist (entry emacsvox-maths--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target where function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-maths-preview-feedback-is-target-aware ()
  "Only interactive preview sends the expression to the Maths client."
  (with-temp-buffer
    (insert "x")
    (let ((overlay (make-overlay (point-min) (point-max)))
          (emacsvox-maths (make-emacsvox-maths :client-process 'fake))
          calls)
      (overlay-put overlay 'preview-state 'active)
      (goto-char (point-min))
      (cl-letf (((symbol-function 'process-live-p)
                 (lambda (process) (eq process 'fake)))
                ((symbol-function 'emacsvox-maths-guess-tex)
                 (lambda () "$x$"))
                ((symbol-function 'emacsvox-maths-enter)
                 (lambda (latex) (push latex calls))))
        (let ((ems--interactive-fn-name 'other-command))
          (emacsvox--advice-preview-at-point-after))
        (let ((ems--interactive-fn-name 'preview-at-point))
          (emacsvox--advice-preview-at-point-after)))
      (should (equal calls '("$x$"))))))

(provide 'emacsvox-maths-tests)
;;; emacsvox-maths-tests.el ends here
