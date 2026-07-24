;;; emacsvox-ess-tests.el --- ESS advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(dolist (feature '(ess-site ess-mode ess-inf ess-help))
  (require feature nil t))
(load (expand-file-name "../lisp/emacsvox-ess.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-ess-advice-is-current-and-direct ()
  "Current ESS targets use native advice directly."
  (dolist (entry emacsvox-ess--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target))))
  (dolist (target emacsvox-ess--removed-targets)
    (should-not (fboundp target))))

(ert-deftest emacsvox-ess-feedback-is-target-aware ()
  "Only the matching interactive ESS evaluator provides feedback."
  (let ((ems--interactive-fn-name 'ess-eval-buffer)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events))))
      (emacsvox--advice-ess-eval-region-after)
      (emacsvox--advice-ess-eval-buffer-after))
    (should (equal events '(select-object)))))

(ert-deftest emacsvox-ess-smart-underscore-calls-original-once ()
  "Native smart-underscore advice does not duplicate insertion."
  (with-temp-buffer
    (let ((ems--interactive-fn-name 'ess-smart-underscore)
          (calls 0)
          spoken)
      (cl-letf (((symbol-function 'dtk-speak)
                 (lambda (text) (setq spoken text))))
        (should
         (eq 'result
             (emacsvox--advice-ess-smart-underscore-around
              (lambda (&rest _)
                (cl-incf calls)
                (insert "__")
                'result))))
      (should (= calls 1))
      (should (equal (buffer-string) "__"))
      (should (equal spoken "__"))))))

(provide 'emacsvox-ess-tests)
;;; emacsvox-ess-tests.el ends here
