;;; emacsvox-region-tests.el --- Region editing advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated region-editing advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(defconst emacsvox-test--region-direct-advice
  '((delete-region :around
     emacsvox--advice-delete-region-around)
    (kill-region :around
     emacsvox--advice-kill-region-around)
    (completion-kill-region :around
     emacsvox--advice-completion-kill-region-around)
    (downcase-region :after
     emacsvox--advice-downcase-region-after)
    (upcase-region :after
     emacsvox--advice-upcase-region-after))
  "Region-editing commands using individually named native advice.")

(ert-deftest emacsvox-region-advice-is-directly-registered ()
  "Migrated region advice uses native advice directly."
  (dolist (entry emacsvox-test--region-direct-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-region-deletion-calls-original-once ()
  "Interactive deletion counts first, calls once, and preserves its result."
  (with-temp-buffer
    (insert "one\ntwo\nthree\n")
    (let ((ems--interactive-fn-name 'delete-region)
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
          (emacsvox--advice-delete-region-around
           (lambda (beginning end)
             (cl-incf calls)
             (push (list 'original beginning end) events)
             (delete-region beginning end)
             'delete-result)
           (point-min) (point-max))
          'delete-result)))
      (should (= calls 1))
      (should (= (point-min) (point-max)))
      (should
       (equal
        (nreverse events)
        '((original 1 15)
          (icon delete-object)
          (message "Killed region containing 3 lines")))))))

(ert-deftest emacsvox-kill-region-preserves-optional-argument ()
  "Interactive kill advice passes its optional argument through unchanged."
  (let ((ems--interactive-fn-name 'kill-region)
        (calls 0)
        observed-arguments)
    (cl-letf (((symbol-function 'emacsvox-icon) #'ignore)
              ((symbol-function 'message) #'ignore)
              ((symbol-function 'count-lines)
               (lambda (beginning end)
                 (should (= beginning 2))
                 (should (= end 7))
                 1)))
      (should
       (eq
        (emacsvox--advice-kill-region-around
         (lambda (&rest arguments)
           (cl-incf calls)
           (setq observed-arguments arguments)
           'kill-result)
         2 7 'region)
        'kill-result)))
    (should (= calls 1))
    (should (equal observed-arguments '(2 7 region)))))

(ert-deftest emacsvox-region-deletion-is-quiet-programmatically ()
  "Programmatic region deletion calls once without feedback."
  (let ((ems--interactive-fn-name nil)
        (calls 0)
        feedback)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (&rest _) (setq feedback t)))
              ((symbol-function 'message)
               (lambda (&rest _) (setq feedback t)))
              ((symbol-function 'count-lines)
               (lambda (&rest _)
                 (setq feedback t)
                 1)))
      (should
       (eq
        (emacsvox--advice-completion-kill-region-around
         (lambda (&rest _)
           (cl-incf calls)
           'completion-result)
         1 2)
        'completion-result)))
    (should (= calls 1))
    (should-not feedback)))

(ert-deftest emacsvox-region-case-feedback-uses-explicit-range ()
  "Case conversion reports its arguments without consulting the mark."
  (with-temp-buffer
    (insert "one\ntwo\nthree\n")
    (set-marker (mark-marker) nil)
    (let ((ems--interactive-fn-name 'downcase-region)
          events)
      (cl-letf (((symbol-function 'message)
                 (lambda (format-string &rest arguments)
                   (push
                    (apply #'format format-string arguments)
                    events))))
        (emacsvox--advice-upcase-region-after
         (point-min) (point-max) nil)
        (emacsvox--advice-downcase-region-after
         (point-min) (point-max) nil))
      (should
       (equal events
              '("Downcased region containing 3 lines"))))))

(provide 'emacsvox-region-tests)
;;; emacsvox-region-tests.el ends here
