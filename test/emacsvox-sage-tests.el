;;; emacsvox-sage-tests.el --- Sage advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(mapc #'require '(sage-shell-mode sage-shell-blocks))
(load (expand-file-name "../lisp/emacsvox-sage.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-sage-advice-is-current-and-direct ()
  "Current Sage targets use native advice directly."
  (dolist (entry emacsvox-sage--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-sage-delete-calls-original-once ()
  "Sage deletion advice preserves the result and calls once."
  (with-temp-buffer
    (insert "x")
    (goto-char (point-min))
    (let ((ems--interactive-fn-name 'sage-shell:delchar-or-maybe-eof)
          (calls 0))
      (cl-letf (((symbol-function 'tts-tone-deletion) #'ignore)
                ((symbol-function 'emacsvox-speak-char) #'ignore))
        (should
         (eq 'deleted
             (emacsvox--advice-sage-shell:delchar-or-maybe-eof-around
              (lambda (&rest _)
                (cl-incf calls)
                'deleted)
              1)))
        (should (= calls 1))))))

(provide 'emacsvox-sage-tests)
;;; emacsvox-sage-tests.el ends here
