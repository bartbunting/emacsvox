;;; gweb-tests.el --- Gweb advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'cl-lib)
(require 'ert)
(require 'ido)
(load (expand-file-name "../lisp/gweb.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest gweb-completion-advice-is-current-and-direct ()
  "Current completion targets use native Gweb advice directly."
  (dolist (entry gweb--completion-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(ert-deftest gweb-completion-advice-calls-original-once ()
  "Ordinary completion calls its original once and preserves its result."
  (let ((calls 0)
        (spoken 0)
        (gweb-completion-flag nil))
    (cl-letf (((symbol-function 'emacsvox-speak-word)
               (lambda () (cl-incf spoken))))
      (should
       (eq 'completed
           (gweb--advice-minibuffer-complete-word-around
            (lambda ()
              (cl-incf calls)
              'completed)))))
    (should (= calls 1))
    (should (= spoken 1))))

(ert-deftest gweb-completion-advice-inserts-space-without-original ()
  "Google completion inserts a space without invoking normal completion."
  (with-temp-buffer
    (let ((calls 0)
          (spoken 0)
          (gweb-completion-flag t))
      (cl-letf (((symbol-function 'emacsvox-speak-word)
                 (lambda () (cl-incf spoken))))
        (should-not
         (gweb--advice-ido-complete-space-around
          (lambda ()
            (cl-incf calls)
            'unexpected))))
      (should (equal (buffer-string) " "))
      (should (zerop calls))
      (should (= spoken 1)))))

(provide 'gweb-tests)
;;; gweb-tests.el ends here
