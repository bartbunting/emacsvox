;;; emacsvox-2048-tests.el --- 2048 advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require '2048-game)
(load (expand-file-name "../lisp/emacsvox-2048.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-2048-advice-is-current-and-direct ()
  "Every 2048 target exists and bypasses the bridge."
  (dolist (target emacsvox-2048--advice-targets)
    (let ((function (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-2048-movement-is-target-aware ()
  "Only matching interactive movement announces the board."
  (let ((ems--interactive-fn-name '2048-left)
        (*2048-combines-this-move* [nil])
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-2048-speak-board)
               (lambda () (push 'board events)))
              ((symbol-function '2048-game-was-won) (lambda () nil))
              ((symbol-function '2048-game-was-lost) (lambda () nil)))
      (emacsvox--advice-2048-right-after)
      (emacsvox--advice-2048-left-after))
    (should (equal (nreverse events) '(close-object board)))))

(provide 'emacsvox-2048-tests)
;;; emacsvox-2048-tests.el ends here
