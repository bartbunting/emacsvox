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

(ert-deftest emacsvox-sox-redraw-uses-current-face-symbols ()
  "SoX applies current quoted face symbols to its file heading."
  (with-temp-buffer
    (sox-redraw
     (make-sox-context :file "/tmp/emacsvox-audio.wav"))
    (should
     (eq
      (get-text-property (point-min) 'face)
      'font-lock-doc-face))
    (goto-char (point-min))
    (search-forward "/tmp/emacsvox-audio.wav")
    (should
     (eq
      (get-text-property (1- (point)) 'face)
      'font-lock-keyword-face))))

(ert-deftest emacsvox-sox-mode-initializes-buffer-local-context ()
  "SoX mode initializes its workbench state without changing the default."
  (let ((default-context (default-value 'sox-context)))
    (with-temp-buffer
      (sox-mode)
      (should (local-variable-p 'sox-context))
      (should (sox-context-p sox-context))
      (should-not (sox-context-file sox-context))
      (should-not (sox-context-effects sox-context)))
    (should (eq (default-value 'sox-context) default-context))))

(provide 'emacsvox-sox-tests)
;;; emacsvox-sox-tests.el ends here
