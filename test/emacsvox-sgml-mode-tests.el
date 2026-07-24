;;; emacsvox-sgml-mode-tests.el --- SGML advice tests -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'sgml-mode)
(load
 (expand-file-name "../lisp/emacsvox-sgml-mode.el"
                   (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(ert-deftest emacsvox-sgml-advice-is-directly-registered ()
  (dolist
      (entry
       '((sgml-skip-tag-forward :after)
         (sgml-skip-tag-backward :after)
         (sgml-slash :after)
         (sgml-delete-tag :after)
         (sgml-name-char :around)
         (sgml-tags-invisible :after)))
    (pcase-let ((`(,target ,where) entry))
      (let ((function
             (intern (format "emacsvox--advice-%s-%s"
                             target (substring (symbol-name where) 1)))))
        (should (commandp target))
        (should (advice-member-p function target))
        (should-not
         (gethash (list target where function)
                  ems--modern-advice-wrappers))))))

(ert-deftest emacsvox-sgml-navigation-feedback-is-target-aware ()
  (let ((ems--interactive-fn-name 'sgml-skip-tag-backward) events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events))))
      (emacsvox--advice-sgml-skip-tag-forward-after)
      (emacsvox--advice-sgml-skip-tag-backward-after))
    (should (equal (nreverse events) '(large-movement line)))))

(ert-deftest emacsvox-sgml-name-char-runs-once ()
  (with-temp-buffer
    (let ((ems--interactive-fn-name 'sgml-name-char) (calls 0) events)
      (cl-letf (((symbol-function 'message) #'ignore)
                ((symbol-function 'emacsvox-speak-region)
                 (lambda (start end)
                   (push (buffer-substring start end) events))))
        (should
         (eq 'result
             (emacsvox--advice-sgml-name-char-around
              (lambda (&optional char)
                (setq calls (1+ calls))
                (insert (or char "x"))
                'result)
              "n"))))
      (should (= calls 1))
      (should (equal events '("n"))))))

(ert-deftest emacsvox-sgml-programmatic-name-char-runs-once-quietly ()
  (let ((calls 0) events)
    (cl-letf (((symbol-function 'emacsvox-speak-region)
               (lambda (&rest args) (push args events))))
      (should
       (eq 'result
           (emacsvox--advice-sgml-name-char-around
            (lambda (&rest _) (setq calls (1+ calls)) 'result)))))
    (should (= calls 1))
    (should-not events)))

(provide 'emacsvox-sgml-mode-tests)
