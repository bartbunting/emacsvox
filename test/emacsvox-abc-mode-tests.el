;;; emacsvox-abc-mode-tests.el --- ABC Mode advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'abc-mode)
(load (expand-file-name "../lisp/emacsvox-abc-mode.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-abc-mode-advice-is-current-and-direct ()
  "Every ABC Mode target exists and bypasses the bridge."
  (dolist (target emacsvox-abc-mode--advice-targets)
    (let ((function (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-abc-mode-navigation-is-target-aware ()
  "Only matching interactive song navigation speaks."
  (let ((ems--interactive-fn-name 'abc-forward-song) events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events))))
      (emacsvox--advice-abc-backward-song-after)
      (emacsvox--advice-abc-forward-song-after))
    (should (equal (nreverse events) '(line button)))))

(provide 'emacsvox-abc-mode-tests)
;;; emacsvox-abc-mode-tests.el ends here
