;;; emacsvox-entertain-tests.el --- Entertainment advice tests -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(load
 (expand-file-name "../lisp/emacsvox-entertain.el"
                   (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(ert-deftest emacsvox-entertain-builtins-defer-and-register-directly ()
  (unless (featurep 'doctor)
    (should-not (fboundp 'doctor-txtype)))
  (unless (featurep 'dunnet)
    (should-not (fboundp 'dun-parse))
    (should-not (fboundp 'dun-unix-parse)))
  (require 'doctor)
  (require 'dunnet)
  (dolist
      (entry
       '((doctor-txtype :after emacsvox--advice-doctor-txtype-after)
         (dun-parse :around emacsvox--advice-dun-parse-around)
         (dun-unix-parse
          :around emacsvox--advice-dun-unix-parse-around)))
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target where function)
                ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-entertain-doctor-uses-native-answer ()
  (let (spoken)
    (cl-letf (((symbol-function 'dtk-speak)
               (lambda (text) (setq spoken text))))
      (emacsvox--advice-doctor-txtype-after
       '(please "tell" me more)))
    (should (equal spoken "please tell me more"))))

(ert-deftest emacsvox-entertain-dunnet-runs-once-and-preserves-result ()
  (with-temp-buffer
    (insert "> look")
    (goto-char (point-max))
    (let ((ems--interactive-fn-name 'dun-parse)
          (calls 0)
          events)
      (cl-letf (((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push icon events)))
                ((symbol-function 'emacsvox-speak-region)
                 (lambda (start end)
                   (push (list start end) events))))
        (should
         (eq 'result
             (emacsvox--advice-dun-parse-around
              (lambda (arg)
                (setq calls (1+ calls))
                (should (= arg 1))
                (insert "\nA room")
                'result)
              1))))
      (should (= calls 1))
      (should
       (equal (nreverse events)
              '(mark-object (7 14)))))))

(ert-deftest emacsvox-entertain-dunnet-programmatic-call-is-quiet ()
  (let ((calls 0) events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (&rest args) (push args events))))
      (should
       (eq 'result
           (emacsvox--advice-dun-unix-parse-around
            (lambda (&rest _)
              (setq calls (1+ calls))
              'result)
            1))))
    (should (= calls 1))
    (should-not events)))

(provide 'emacsvox-entertain-tests)
