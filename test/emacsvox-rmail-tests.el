;;; emacsvox-rmail-tests.el --- Rmail advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Rmail advice.

;;; Code:

(require 'ert)
(require 'rmail)
(require 'rmailkwd)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-rmail.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--rmail-after-targets
  '(rmail-quit
    rmail-bury
    rmail
    rmail-expunge-and-save
    rmail-beginning-of-message
    rmail-first-message
    rmail-first-unseen-message
    rmail-last-message
    rmail-next-undeleted-message
    rmail-next-message
    rmail-previous-undeleted-message
    rmail-previous-message
    rmail-show-message
    rmail-undelete-previous-message
    rmail-delete-message
    rmail-delete-forward
    rmail-delete-backward)
  "Current Emacs 31 Rmail targets using direct after advice.")

(defconst emacsvox-test--rmail-around-targets
  '(rmail-next-labeled-message
    rmail-previous-labeled-message)
  "Current Emacs 31 Rmail targets using direct around advice.")

(ert-deftest emacsvox-rmail-advice-is-directly-registered ()
  "Rmail advice is attached directly to current Emacs 31 targets."
  (dolist (target emacsvox-test--rmail-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))))
  (dolist (target emacsvox-test--rmail-around-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-around" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-rmail-feedback-is-target-aware ()
  "Only the matching Rmail navigation command produces feedback."
  (let ((ems--interactive-fn-name 'rmail-next-message)
        (rmail-current-message 7)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-rmail-summarize-message)
               (lambda (message) (push (list 'message message) events))))
      (emacsvox--advice-rmail-previous-message-after)
      (emacsvox--advice-rmail-next-message-after))
    (should
     (equal
      (nreverse events)
      '((icon select-object) (message 7))))))

(ert-deftest emacsvox-rmail-labeled-move-calls-original-once ()
  "A labeled-message move preserves its result and reports one move."
  (let ((ems--interactive-fn-name 'rmail-next-labeled-message)
        (rmail-current-message 3)
        (calls 0)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-rmail-summarize-message)
               (lambda (message) (push (list 'message message) events))))
      (should
       (eq
        'result
        (emacsvox--advice-rmail-next-labeled-message-around
         (lambda (&rest arguments)
           (setq calls (1+ calls)
                 rmail-current-message 4)
           (should (equal arguments '(1 "work")))
           'result)
         1 "work"))))
    (should (= calls 1))
    (should
     (equal
      (nreverse events)
      '((icon select-object) (message 4))))))

(ert-deftest emacsvox-rmail-labeled-miss-calls-original-once ()
  "A labeled-message miss produces one icon after one original call."
  (let ((ems--interactive-fn-name 'rmail-previous-labeled-message)
        (rmail-current-message 3)
        (calls 0)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-rmail-summarize-message)
               (lambda (&rest _) (push 'summary events))))
      (should
       (eq
        'result
        (emacsvox--advice-rmail-previous-labeled-message-around
         (lambda (&rest _)
           (setq calls (1+ calls))
           'result)
         -1 "work"))))
    (should (= calls 1))
    (should (equal events '(search-miss)))))

(ert-deftest emacsvox-rmail-noninteractive-labeled-move-is-silent ()
  "A noninteractive labeled-message move calls the original only once."
  (let ((ems--interactive-fn-name nil)
        (rmail-current-message 3)
        (calls 0)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (&rest _) (push 'icon events)))
              ((symbol-function 'emacsvox-rmail-summarize-message)
               (lambda (&rest _) (push 'summary events))))
      (should
       (eq
        'result
        (emacsvox--advice-rmail-next-labeled-message-around
         (lambda (&rest _)
           (setq calls (1+ calls)
                 rmail-current-message 4)
           'result)
         1 "work"))))
    (should (= calls 1))
    (should-not events)))

(provide 'emacsvox-rmail-tests)
;;; emacsvox-rmail-tests.el ends here
