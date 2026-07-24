;;; emacsvox-sox-tests.el --- SoX advice tests -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'sox)

(ert-deftest emacsvox-sox-advice-is-current-and-direct ()
  "Current SoX targets use native advice directly."
  (dolist (entry
           '((sox-open-file emacsvox--advice-sox-open-file-after)
             (sox-refresh emacsvox--advice-sox-refresh-after)
             (sox-delete-effect-at-point
              emacsvox--advice-sox-delete-effect-at-point-after)))
    (pcase-let ((`(,target ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-sox-feedback-is-target-aware ()
  "Each SoX feedback function responds only to its interactive command."
  (let (events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events))))
      (dolist (entry
               '((sox-open-file
                  emacsvox--advice-sox-open-file-after select-object)
                 (sox-refresh
                  emacsvox--advice-sox-refresh-after task-done)
                 (sox-delete-effect-at-point
                  emacsvox--advice-sox-delete-effect-at-point-after
                  delete-object)))
        (pcase-let ((`(,target ,function ,icon) entry))
          (let ((ems--interactive-fn-name 'other-command))
            (funcall function))
          (should-not events)
          (let ((ems--interactive-fn-name target))
            (funcall function))
          (should (equal (pop events) icon)))))))

(provide 'emacsvox-sox-tests)
;;; emacsvox-sox-tests.el ends here
