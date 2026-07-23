;;; emacsvox-vc-tests.el --- Version-control advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated version-control advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(defconst emacsvox-test--vc-direct-advice
  '((vc-toggle-read-only :around
     emacsvox--advice-vc-toggle-read-only-around)
    (vc-refresh-state :around
     emacsvox--advice-vc-refresh-state-around)
    (vc-next-action :around emacsvox--advice-vc-next-action-around)
    (vc-revert-buffer :after
     emacsvox--advice-vc-revert-buffer-after)
    (vc-finish-logentry :after
     emacsvox--advice-vc-finish-logentry-after)
    (vc-dir-next-line :after
     emacsvox--advice-vc-dir-next-line-after)
    (vc-dir-previous-line :after
     emacsvox--advice-vc-dir-previous-line-after)
    (vc-dir-next-directory :after
     emacsvox--advice-vc-dir-next-directory-after)
    (vc-dir-previous-directory :after
     emacsvox--advice-vc-dir-previous-directory-after)
    (vc-dir-mark-file :after
     emacsvox--advice-vc-dir-mark-file-after)
    (vc-dir-mark :after emacsvox--advice-vc-dir-mark-after)
    (vc-dir :after emacsvox--advice-vc-dir-after)
    (vc-dir-hide-up-to-date :after
     emacsvox--advice-vc-dir-hide-up-to-date-after)
    (vc-dir-kill-line :after
     emacsvox--advice-vc-dir-kill-line-after))
  "Version-control functions using individually defined native advice.")

(ert-deftest emacsvox-vc-advice-is-directly-registered ()
  "Migrated VC advice bypasses the compatibility bridge."
  (dolist (entry emacsvox-test--vc-direct-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target where function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-vc-toggle-advice-calls-original-once ()
  "An interactive VC toggle uses pre-call state and preserves the result."
  (with-temp-buffer
    (setq buffer-read-only t)
    (setq-local vc-mode " Git-42")
    (let ((ems--interactive-fn-name 'vc-toggle-read-only)
          (calls 0)
          events)
      (cl-letf (((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events)))
                ((symbol-function 'message)
                 (lambda (format-string &rest arguments)
                   (push
                    (list 'message
                          (apply #'format format-string arguments))
                    events))))
        (should
         (eq
          (emacsvox--advice-vc-toggle-read-only-around
           (lambda (&rest arguments)
             (cl-incf calls)
             (push
              (list 'original arguments buffer-read-only)
              events)
             (setq buffer-read-only nil)
             'toggle-result)
           'argument)
          'toggle-result)))
      (should (= calls 1))
      (should
       (equal
        (nreverse events)
        '((icon open-object)
          (original (argument) t)
          (message "Checking out previous  version 42 ")))))))

(ert-deftest emacsvox-vc-next-action-advice-calls-original-once ()
  "An interactive next VC action uses pre-call state and preserves its result."
  (with-temp-buffer
    (setq buffer-read-only nil)
    (setq-local vc-mode " Git-42")
    (let ((ems--interactive-fn-name 'vc-next-action)
          (calls 0)
          events)
      (cl-letf (((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events)))
                ((symbol-function 'message)
                 (lambda (format-string &rest arguments)
                   (push
                    (list 'message
                          (apply #'format format-string arguments))
                    events))))
        (should
         (eq
          (emacsvox--advice-vc-next-action-around
           (lambda (&rest arguments)
             (cl-incf calls)
             (push
              (list 'original arguments buffer-read-only)
              events)
             (setq buffer-read-only t)
             'action-result)
           'argument)
          'action-result)))
      (should (= calls 1))
      (should
       (equal
        (nreverse events)
        '((icon open-object)
          (original (argument) nil)
          (message "Checking  in new  version 42 ")))))))

(ert-deftest emacsvox-vc-action-advice-is-quiet-programmatically ()
  "A programmatic VC action calls once without auditory feedback."
  (let ((ems--interactive-fn-name nil)
        (calls 0)
        feedback)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (&rest _) (setq feedback t)))
              ((symbol-function 'message)
               (lambda (&rest _) (setq feedback t))))
      (should
       (eq
        (emacsvox--advice-vc-next-action-around
         (lambda (&rest _)
           (cl-incf calls)
           'action-result))
        'action-result)))
    (should (= calls 1))
    (should-not feedback)))

(ert-deftest emacsvox-vc-refresh-state-remains-silenced ()
  "VC refresh calls its original once with messages silenced."
  (let ((emacsvox-speak-messages t)
        (inhibit-message nil)
        (calls 0)
        observed-state)
    (should
     (eq
      (emacsvox--advice-vc-refresh-state-around
       (lambda (&rest arguments)
         (cl-incf calls)
         (setq observed-state
               (list arguments emacsvox-speak-messages inhibit-message))
         'refresh-result)
       'argument)
      'refresh-result))
    (should (= calls 1))
    (should (equal observed-state '((argument) nil t)))
    (should emacsvox-speak-messages)
    (should-not inhibit-message)))

(ert-deftest emacsvox-vc-directory-movement-feedback-is-target-aware ()
  "Only the matching VC directory movement speaks and cues its destination."
  (let ((ems--interactive-fn-name 'vc-dir-previous-directory)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-vc-dir-next-line-after 1)
      (emacsvox--advice-vc-dir-previous-directory-after))
    (should
     (equal
      (nreverse events)
      '(speak-line (icon select-object))))))

(ert-deftest emacsvox-vc-directory-mark-feedback-preserves-order ()
  "An interactive VC directory mark speaks before its auditory icon."
  (let ((ems--interactive-fn-name 'vc-dir-mark-file)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-vc-dir-mark-after)
      (emacsvox--advice-vc-dir-mark-file-after))
    (should
     (equal
      (nreverse events)
      '(speak-line (icon mark-object))))))

(ert-deftest emacsvox-vc-directory-action-feedback-preserves-order ()
  "VC directory actions retain their command-specific icon and speech order."
  (let ((ems--interactive-fn-name 'vc-dir-hide-up-to-date)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-vc-dir-after ".")
      (emacsvox--advice-vc-dir-kill-line-after)
      (emacsvox--advice-vc-dir-hide-up-to-date-after))
    (should
     (equal
      (nreverse events)
      '((icon task-done) speak-line)))))

(ert-deftest emacsvox-vc-finish-logentry-announces-version ()
  "An interactive VC log completion retains its icon and version message."
  (let ((ems--interactive-fn-name 'vc-finish-logentry)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-vc-get-version-id)
               (lambda () "42"))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push
                  (list 'message
                        (apply #'format format-string arguments))
                  events))))
      (emacsvox--advice-vc-finish-logentry-after))
    (should
     (equal
      (nreverse events)
      '((icon close-object)
        (message "Checked in version 42 "))))))

(provide 'emacsvox-vc-tests)
;;; emacsvox-vc-tests.el ends here
