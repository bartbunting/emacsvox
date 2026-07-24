;;; emacsvox-ace-window-tests.el --- Ace Window advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'ace-window)
(load (expand-file-name "../lisp/emacsvox-ace-window.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-ace-window-advice-is-current-and-direct ()
  "Current Ace Window targets bypass the bridge."
  (dolist (target emacsvox-ace-window--advice-targets)
    (let ((function (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target :after function) ems--modern-advice-wrappers))))
  (should-not (fboundp 'ace-maximize-window)))

(ert-deftest emacsvox-ace-window-selection-is-target-aware ()
  "Only interactive window selection announces its destination."
  (let ((ems--interactive-fn-name 'ace-window) events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'mode-line events))))
      (emacsvox--advice-ace-window-after))
    (should (equal (nreverse events) '(select-object mode-line)))))

(provide 'emacsvox-ace-window-tests)
;;; emacsvox-ace-window-tests.el ends here
