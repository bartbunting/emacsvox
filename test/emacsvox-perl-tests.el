;;; emacsvox-perl-tests.el --- Perl advice tests -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'perl-mode)
(load
 (expand-file-name "../lisp/emacsvox-perl.el"
                   (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(ert-deftest emacsvox-perl-advice-is-directly-registered ()
  (dolist
      (target
       '(mark-perl-function
         perl-beginning-of-function
         perl-end-of-function))
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (commandp target))
      (should (advice-member-p function target))))
  (should-not (fboundp 'electric-perl-terminator))
  (should (fboundp 'emacsvox--advice-perl-electric-terminator-after))
  (if (memq 'emacsvox-post-self-insert-hook post-self-insert-hook)
      (should-not
       (advice-member-p
        #'emacsvox--advice-perl-electric-terminator-after
        'perl-electric-terminator))
    (should
     (advice-member-p
      #'emacsvox--advice-perl-electric-terminator-after
      'perl-electric-terminator))))

(ert-deftest emacsvox-perl-navigation-feedback-is-target-aware ()
  (let ((ems--interactive-fn-name 'perl-beginning-of-function) events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events))))
      (emacsvox--advice-mark-perl-function-after)
      (emacsvox--advice-perl-beginning-of-function-after)
      (emacsvox--advice-perl-end-of-function-after))
    (should
     (equal (nreverse events) '(large-movement line)))))

(ert-deftest emacsvox-perl-electric-feedback-uses-current-target ()
  (let ((ems--interactive-fn-name 'perl-electric-terminator)
        (last-input-event ?\;)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-this-char)
               (lambda (char) (push char events))))
      (emacsvox--advice-perl-electric-terminator-after))
    (should (equal events '(?\;)))))

(provide 'emacsvox-perl-tests)
