;;; emacsvox-gnuplot-tests.el --- Gnuplot advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'cl-lib)
(require 'ert)
(require 'package)
(package-initialize)
(require 'gnuplot)
(load (expand-file-name "../lisp/emacsvox-gnuplot.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-gnuplot-advice-is-current-and-direct ()
  "Current Gnuplot targets use native advice directly."
  (dolist (entry emacsvox-gnuplot--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target where function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-gnuplot-removed-targets-remain-absent ()
  "Retired Gnuplot commands are not recreated as phantom targets."
  (dolist (target '(gnuplot-kill-gnuplot-buffer
                    gnuplot-show-gnuplot-buffer
                    gnuplot-complete-keyword))
    (should-not (fboundp target))))

(ert-deftest emacsvox-gnuplot-delete-calls-original-once ()
  "Interactive deletion gives feedback and invokes its original once."
  (with-temp-buffer
    (insert "x")
    (goto-char (point-min))
    (let ((calls 0)
          (ems--interactive-fn-name 'gnuplot-delchar-or-maybe-eof)
          events)
      (cl-letf (((symbol-function 'dtk-tone)
                 (lambda (&rest _) (push 'tone events)))
                ((symbol-function 'emacsvox-speak-char)
                 (lambda (&rest _) (push 'speak-char events))))
        (should
         (eq 'deleted
             (emacsvox--advice-gnuplot-delchar-or-maybe-eof-around
              (lambda (arg)
                (cl-incf calls)
                (delete-char arg)
                'deleted)
              1))))
      (should (= calls 1))
      (should (equal (buffer-string) ""))
      (should (equal (nreverse events) '(tone speak-char))))))

(provide 'emacsvox-gnuplot-tests)
;;; emacsvox-gnuplot-tests.el ends here
