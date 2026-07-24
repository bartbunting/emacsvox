;;; emacsvox-tempo-tests.el --- Tempo advice tests -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'tempo)
(load
 (expand-file-name "../lisp/emacsvox-tempo.el"
                   (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(ert-deftest emacsvox-tempo-advice-is-directly-registered ()
  (dolist (target '(tempo-forward-mark tempo-backward-mark))
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (commandp target))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-tempo-defers-html-helper-advice ()
  (should
   (fboundp 'emacsvox--advice-html-helper-smart-insert-item-after))
  (unless (featurep 'html-helper-mode)
    (should-not (fboundp 'html-helper-smart-insert-item))))

(ert-deftest emacsvox-tempo-feedback-is-target-aware ()
  (let ((ems--interactive-fn-name 'tempo-backward-mark) events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events))))
      (emacsvox--advice-tempo-forward-mark-after)
      (emacsvox--advice-tempo-backward-mark-after)
      (emacsvox--advice-html-helper-smart-insert-item-after))
    (should (equal events '(line)))))

(provide 'emacsvox-tempo-tests)
