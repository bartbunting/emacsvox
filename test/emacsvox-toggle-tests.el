;;; emacsvox-toggle-tests.el --- State toggle advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated state-toggle advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(defconst emacsvox-test--toggle-after-targets
  '(toggle-debug-on-error toggle-debug-on-quit overwrite-mode
    transient-mark-mode toggle-input-method)
  "State toggle commands using native after advice.")

(ert-deftest emacsvox-toggle-advice-is-directly-registered ()
  "Migrated state-toggle advice bypasses the compatibility bridge."
  (dolist (target emacsvox-test--toggle-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-debug-on-quit-feedback-uses-quit-state ()
  "The debug-on-quit icon follows its own state, not debug-on-error."
  (let ((ems--interactive-fn-name 'toggle-debug-on-quit)
        (debug-on-error t)
        (debug-on-quit nil)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push
                  (list 'message
                        (apply #'format format-string arguments))
                  events))))
      (emacsvox--advice-toggle-debug-on-error-after)
      (emacsvox--advice-toggle-debug-on-quit-after))
    (should
     (equal
      (nreverse events)
      '((icon off) (message "Turned nil debug on quit"))))))

(ert-deftest emacsvox-overwrite-mode-feedback-is-target-aware ()
  "Interactive overwrite mode changes cue warning and report state."
  (let ((ems--interactive-fn-name 'overwrite-mode)
        (overwrite-mode 'overwrite-mode-binary)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push
                  (list 'message
                        (apply #'format format-string arguments))
                  events))))
      (emacsvox--advice-overwrite-mode-after))
    (should
     (equal
      (nreverse events)
      '((icon warn-user)
        (message "Turned overwrite-mode-binary overwrite mode"))))))

(ert-deftest emacsvox-transient-mark-feedback-reports-state ()
  "Interactive transient mark toggles cue and report the new state."
  (let ((ems--interactive-fn-name 'transient-mark-mode)
        (transient-mark-mode nil)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push
                  (list 'message
                        (apply #'format format-string arguments))
                  events))))
      (emacsvox--advice-transient-mark-mode-after))
    (should
     (equal
      (nreverse events)
      '((icon off) (message "Turned off transient mark."))))))

(ert-deftest emacsvox-input-method-feedback-reports-method ()
  "Interactive input-method toggles cue and speak the selected method."
  (let ((ems--interactive-fn-name 'toggle-input-method)
        (current-input-method "test-method")
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'dtk-speak)
               (lambda (text) (push (list 'speak text) events))))
      (emacsvox--advice-toggle-input-method-after))
    (should
     (equal
      (nreverse events)
      '((icon on) (speak "Current input method is test-method"))))))

(provide 'emacsvox-toggle-tests)
;;; emacsvox-toggle-tests.el ends here
