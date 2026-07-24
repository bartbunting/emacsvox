;;; emacsvox-sql-tests.el --- SQL advice tests -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'sql)

(load
 (expand-file-name "../lisp/emacsvox-sql.el"
                   (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(ert-deftest emacsvox-sql-advice-is-directly-registered ()
  (dolist (target '(sql-send-region sql-send-buffer))
    (let ((function (intern (format "emacsvox--advice-%s-around" target))))
      (should (commandp target))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-sql-defers-optional-sqlplus-advice ()
  (dolist (target emacsvox-sql--sqlplus-targets)
    (should-not (fboundp target))
    (should
     (fboundp (intern (format "emacsvox--advice-%s-after" target))))))

(ert-deftest emacsvox-sql-send-region-runs-once ()
  (let ((ems--interactive-fn-name 'sql-send-region) (calls 0) events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events))))
      (should
       (eq 'result
           (emacsvox--advice-sql-send-region-around
            (lambda (&rest args)
              (setq calls (1+ calls))
              (should (equal args '(2 7)))
              'result)
            2 7))))
    (should (= calls 1))
    (should (equal (nreverse events) '(select-object mark-object)))))

(ert-deftest emacsvox-sql-programmatic-send-runs-once-quietly ()
  (let ((calls 0) events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (&rest args) (push args events))))
      (should
       (eq 'result
           (emacsvox--advice-sql-send-buffer-around
            (lambda () (setq calls (1+ calls)) 'result)))))
    (should (= calls 1))
    (should-not events)))

(provide 'emacsvox-sql-tests)
