;;; emacsvox-elpy-tests.el --- Elpy advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'elpy)
(load (expand-file-name "../lisp/emacsvox-elpy.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-elpy-advice-is-current-and-direct ()
  "Current Elpy targets use native advice directly."
  (dolist (target emacsvox-elpy--advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (advice-member-p function target))))
  (dolist (target emacsvox-elpy--removed-targets)
    (should-not (fboundp target))))

(ert-deftest emacsvox-elpy-feedback-is-target-aware ()
  "Only the matching interactive Elpy navigation command submits its line."
  (let ((ems--interactive-fn-name 'elpy-goto-definition)
        submissions)
    (cl-letf
        (((symbol-function 'emacsvox-python--present-current-line)
          (lambda (&rest arguments)
            (push arguments submissions))))
      (emacsvox--advice-elpy-flymake-next-error-after)
      (emacsvox--advice-elpy-goto-definition-after))
    (should
     (equal
      submissions
      '(((:role code-construct :events (focus-entered)
          :syntax-role construct :code-navigation-kind elpy)
         navigation))))))

(ert-deftest emacsvox-elpy-uses-current-statement-command ()
  "The current Elpy statement-and-step command receives advice."
  (should (memq 'elpy-shell-send-statement-and-step
                emacsvox-elpy--task-targets))
  (should-not (memq 'elpy-shell-send-current-statement
                    emacsvox-elpy--task-targets)))

(ert-deftest emacsvox-elpy-started-and-completed-operations-are-distinct ()
  "Elpy does not claim asynchronous checks or submissions have completed."
  (let (submissions)
    (cl-letf
        (((symbol-function 'emacsvox-elpy--present-operation)
          (lambda (&rest arguments)
            (push arguments submissions))))
      (setq ems--interactive-fn-name 'elpy-check)
      (emacsvox--advice-elpy-check-after)
      (setq ems--interactive-fn-name 'elpy-autopep8-fix-code)
      (emacsvox--advice-elpy-autopep8-fix-code-after))
    (should
     (equal
      (nreverse submissions)
      '((elpy-check started)
        (elpy-autopep8-fix-code completed))))))

(ert-deftest emacsvox-elpy-edit-feedback-carries-direction ()
  "Elpy indentation edits use source-edit semantics rather than navigation."
  (let ((ems--interactive-fn-name 'elpy-nav-indent-shift-left)
        submission)
    (cl-letf
        (((symbol-function 'emacsvox-python--present-current-line)
          (lambda (&rest arguments)
            (setq submission arguments))))
      (emacsvox--advice-elpy-nav-indent-shift-left-after))
    (should
     (equal
      submission
      '((:role code-construct :events (object-changed)
         :syntax-role block :code-edit-kind shift-left)
        edit)))))

(ert-deftest emacsvox-elpy-enable-feedback-is-one-native-message ()
  "Enabling Elpy submits its state and compatibility cue together."
  (let ((ems--interactive-fn-name 'elpy-enable)
        submission)
    (cl-letf
        (((symbol-function 'emacsvox-elpy--submit-message)
          (lambda (&rest arguments)
            (setq submission arguments))))
      (emacsvox--advice-elpy-enable-after))
    (should
     (equal
      submission
      '("Enabled Elpy"
        (:role code-operation :events (state-changed)
         :code-operation-kind elpy-enable)
        state-change on)))))

(ert-deftest emacsvox-elpy-policy-cues-navigation-and-editing ()
  "Shared Python policy preserves Elpy navigation and shift cues."
  (dolist
      (case
       '(((:role code-construct :events (focus-entered)
           :syntax-role construct :code-navigation-kind elpy)
          navigation large-movement)
         ((:role code-construct :events (object-changed)
           :syntax-role block :code-edit-kind shift-left)
          edit left)))
    (pcase-let* ((`(,facts ,occasion ,cue) case)
                 (context
                  (list
                   :module 'python :mode 'python-mode
                   :mode-lineage '(python-mode prog-mode)
                   :occasion occasion :icons-enabled t))
                 (plan (emacsvox-aural-resolve-active facts context)))
      (should
       (memq
        cue
        (mapcar
         #'emacsvox-aural-action-cue
         (emacsvox-aural-render-plan-before plan)))))))

(provide 'emacsvox-elpy-tests)
;;; emacsvox-elpy-tests.el ends here
