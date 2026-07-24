;;; emacsvox-deadgrep-tests.el --- Deadgrep advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'deadgrep)
(load (expand-file-name "../lisp/emacsvox-deadgrep.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-deadgrep-advice-is-current-and-direct ()
  "Current Deadgrep targets bypass the compatibility bridge."
  (dolist (target emacsvox-deadgrep--advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-deadgrep-movement-is-target-aware ()
  "Only the matching interactive Deadgrep movement command speaks."
  (let ((ems--interactive-fn-name 'deadgrep-forward-match)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events))))
      (emacsvox--advice-deadgrep-backward-match-after)
      (emacsvox--advice-deadgrep-forward-match-after))
    (should (equal (nreverse events) '(large-movement line)))))

(provide 'emacsvox-deadgrep-tests)
;;; emacsvox-deadgrep-tests.el ends here
