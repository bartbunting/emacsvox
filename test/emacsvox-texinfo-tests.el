;;; emacsvox-texinfo-tests.el --- Texinfo advice tests -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'texinfo)
(load
 (expand-file-name "../lisp/emacsvox-texinfo.el"
                   (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(ert-deftest emacsvox-texinfo-advice-is-directly-registered ()
  (dolist
      (entry
       '((texinfo-insert-@end
          :after emacsvox--advice-texinfo-insert-@end-after)
         (texinfo-insert-block
          :after emacsvox--advice-texinfo-insert-block-after)
         (texinfo-insert-@item
          :after emacsvox--advice-texinfo-insert-@item-after)
         (texinfo-insert-@node
          :after emacsvox--advice-texinfo-insert-@node-after)))
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target))))
  (should-not (fboundp 'TeXinfo-insert-environment)))

(ert-deftest emacsvox-texinfo-feedback-is-target-aware ()
  (let ((ems--interactive-fn-name 'texinfo-insert-@item) events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events))))
      (emacsvox--advice-texinfo-insert-@end-after)
      (emacsvox--advice-texinfo-insert-block-after)
      (emacsvox--advice-texinfo-insert-@item-after)
      (emacsvox--advice-texinfo-insert-@node-after))
    (should (equal (nreverse events) '(item line)))))

(provide 'emacsvox-texinfo-tests)
