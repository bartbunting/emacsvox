;;; emacsvox-consult-tests.el --- Consult advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'consult)
(require 'consult-compile)
(load (expand-file-name "../lisp/emacsvox-consult.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-consult-advice-is-current-and-direct ()
  "Current Consult targets bypass the compatibility bridge."
  (dolist (target emacsvox-consult--advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-consult-feedback-is-target-aware ()
  "Only the matching interactive Consult command speaks."
  (let ((ems--interactive-fn-name 'consult-buffer-other-window)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'mode-line events))))
      (emacsvox--advice-consult-buffer-other-frame-after)
      (emacsvox--advice-consult-buffer-other-window-after))
    (should (equal (nreverse events) '(open-object mode-line)))))

(provide 'emacsvox-consult-tests)
;;; emacsvox-consult-tests.el ends here
