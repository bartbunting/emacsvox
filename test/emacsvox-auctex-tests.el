;;; emacsvox-auctex-tests.el --- AUCTeX advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'tex-site)
(require 'latex)
(load (expand-file-name "../lisp/emacsvox-auctex.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-auctex-advice-is-current-and-direct ()
  "Every retained AUCTeX target exists and bypasses the bridge."
  (dolist (entry emacsvox-auctex--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target where function) ems--modern-advice-wrappers))))
  (dolist
      (removed
       '(LaTeX-format-paragraph
         LaTeX-format-region
         TeX-comment-region
         TeX-un-comment
         TeX-un-comment-region
         TeX-comment-paragraph))
    (should-not (fboundp removed))))

(ert-deftest emacsvox-auctex-insert-macro-calls-original-once ()
  "Macro insertion calls once and preserves its result."
  (with-temp-buffer
    (let ((calls 0))
      (cl-letf (((symbol-function 'emacsvox-speak-region) #'ignore))
        (should
         (eq
          'inserted
          (emacsvox--advice-TeX-insert-macro-around
           (lambda (symbol)
             (cl-incf calls)
             (should (eq symbol 'section))
             (insert "section")
             'inserted)
           'section))))
      (should (= calls 1)))))

(ert-deftest emacsvox-auctex-font-calls-original-once ()
  "Font insertion uses explicit arguments once and preserves its result."
  (with-temp-buffer
    (let ((calls 0)
          (ems--interactive-fn-name 'TeX-font)
          events)
      (cl-letf (((symbol-function 'emacsvox-speak-region)
                 (lambda (start end) (push (list start end) events))))
        (should
         (eq
          'fonted
          (emacsvox--advice-TeX-font-around
           (lambda (replace what)
             (cl-incf calls)
             (should-not replace)
             (should (eq what 'bold))
             (insert "bold")
             'fonted)
           nil 'bold))))
      (should (= calls 1))
      (should (equal events '((1 5)))))))

(provide 'emacsvox-auctex-tests)
;;; emacsvox-auctex-tests.el ends here
