;;; emacsvox-syslog-tests.el --- Syslog advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'syslog-mode)
(load (expand-file-name "../lisp/emacsvox-syslog.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-syslog-advice-is-current-and-direct ()
  "Every Syslog target exists and bypasses the bridge."
  (dolist (target emacsvox-syslog--advice-targets)
    (let ((function (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-syslog-file-feedback-is-target-aware ()
  "Only matching interactive file navigation is announced."
  (let ((ems--interactive-fn-name 'syslog-next-file) events)
    (cl-letf (((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'mode-line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events))))
      (emacsvox--advice-syslog-previous-file-after)
      (emacsvox--advice-syslog-next-file-after))
    (should (equal (nreverse events) '(mode-line open-object)))))

(provide 'emacsvox-syslog-tests)
;;; emacsvox-syslog-tests.el ends here
