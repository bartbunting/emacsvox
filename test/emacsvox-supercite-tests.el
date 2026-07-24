;;; emacsvox-supercite-tests.el --- Supercite advice tests -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'supercite)
(load
 (expand-file-name "../lisp/emacsvox-supercite.el"
                   (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(ert-deftest emacsvox-supercite-advice-is-directly-registered ()
  (dolist
      (entry
       '((sc-cite-region :after emacsvox--advice-sc-cite-region-after)
         (sc-recite-region :after emacsvox--advice-sc-recite-region-after)
         (sc-uncite-region :after emacsvox--advice-sc-uncite-region-after)
         (sc-insert-reference
          :around emacsvox--advice-sc-insert-reference-around)
         (sc-insert-citation
          :after emacsvox--advice-sc-insert-citation-after)
         (sc-open-line :after emacsvox--advice-sc-open-line-after)))
    (pcase-let ((`(,target ,where ,function) entry))
      (should (commandp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target where function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-supercite-region-feedback-uses-native-bounds ()
  (with-temp-buffer
    (insert "one\ntwo\nthree\n")
    (let ((ems--interactive-fn-name 'sc-recite-region) events)
      (cl-letf (((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push icon events)))
                ((symbol-function 'message)
                 (lambda (format-string &rest args)
                   (push (apply #'format format-string args) events))))
        (emacsvox--advice-sc-cite-region-after 1 9)
        (emacsvox--advice-sc-recite-region-after 1 9))
      (should
       (equal (nreverse events)
              '(mark-object "Re-cited region containing 2 lines"))))))

(ert-deftest emacsvox-supercite-insert-reference-runs-once ()
  (with-temp-buffer
    (let ((ems--interactive-fn-name 'sc-insert-reference)
          (calls 0) events)
      (cl-letf (((symbol-function 'emacsvox-speak-region)
                 (lambda (start end)
                   (push (list start end (buffer-string)) events)))
                ((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push icon events))))
        (should
         (eq 'result
             (emacsvox--advice-sc-insert-reference-around
              (lambda (arg)
                (setq calls (1+ calls))
                (should (= arg 2))
                (insert "Reference")
                'result)
              2))))
      (should (= calls 1))
      (should
       (equal (nreverse events)
              '((1 10 "Reference") yank-object))))))

(ert-deftest emacsvox-supercite-programmatic-reference-runs-once-quietly ()
  (let ((calls 0) events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (&rest args) (push args events))))
      (should
       (eq 'result
           (emacsvox--advice-sc-insert-reference-around
            (lambda (&rest _) (setq calls (1+ calls)) 'result)
            1))))
    (should (= calls 1))
    (should-not events)))

(provide 'emacsvox-supercite-tests)
