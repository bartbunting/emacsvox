;;; emacsvox-woman-tests.el --- WoMan advice tests -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'woman)
(load
 (expand-file-name "../lisp/emacsvox-woman.el"
                   (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(ert-deftest emacsvox-woman-advice-is-directly-registered ()
  (dolist (target '(WoMan-next-manpage WoMan-previous-manpage))
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (commandp target))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-woman-feedback-is-target-aware ()
  (let ((ems--interactive-fn-name 'WoMan-previous-manpage) events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'mode-line events))))
      (emacsvox--advice-WoMan-next-manpage-after)
      (emacsvox--advice-WoMan-previous-manpage-after))
    (should
     (equal (nreverse events) '(select-object mode-line)))))

(provide 'emacsvox-woman-tests)
