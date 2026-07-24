;;; emacsvox-gud-tests.el --- GUD advice tests -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'gud)
(load
 (expand-file-name "../lisp/emacsvox-gud.el"
                   (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(ert-deftest emacsvox-gud-advice-is-directly-registered ()
  (should
   (advice-member-p
    #'emacsvox--advice-gud-display-line-after
    'gud-display-line))
  (dolist (target emacsvox-gud--command-targets)
    (should
     (fboundp
      (intern (format "emacsvox--advice-%s-around" target))))
    (should-not (fboundp target))))

(ert-deftest emacsvox-gud-generated-command-registers-when-defined ()
  (let ((calls 0) events)
    (unwind-protect
        (progn
          (fset
           'gud-break
           (lambda (arg)
             (setq calls (1+ calls))
             (should (= arg 3))
             'result))
          (emacsvox-gud--install-command-advice)
          (should
           (advice-member-p
            #'emacsvox--advice-gud-break-around
            'gud-break))
          (cl-letf (((symbol-function 'emacsvox-icon)
                     (lambda (icon) (push icon events))))
            (should (eq 'result (gud-break 3))))
          (should (= calls 1))
          (should (equal events '(select-object))))
      (when (fboundp 'gud-break)
        (advice-remove 'gud-break #'emacsvox--advice-gud-break-around)
        (fmakunbound 'gud-break)))))

(ert-deftest emacsvox-gud-display-line-speaks-source-position ()
  (with-temp-buffer
    (insert "first\nsecond\n")
    (let ((gud-overlay-arrow-position (copy-marker 7)) events)
      (cl-letf (((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push icon events)))
                ((symbol-function 'emacsvox-speak-line)
                 (lambda () (push (line-number-at-pos) events))))
        (emacsvox--advice-gud-display-line-after))
      (should (equal (nreverse events) '(large-movement 2))))))

(provide 'emacsvox-gud-tests)
