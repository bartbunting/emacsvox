;;; emacsvox-search-tests.el --- Search and replacement advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated search and replace advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(defconst emacsvox-test--replace-after-targets
  '(query-replace query-replace-regexp)
  "Replacement commands using generated native after advice.")

(defconst emacsvox-test--search-after-targets
  '(search-forward search-backward
    word-search-forward word-search-backward)
  "Non-incremental search commands using generated native after advice.")

(defconst emacsvox-test--replace-direct-advice
  '((perform-replace :around emacsvox--advice-perform-replace-around)
    (replace-highlight :after emacsvox--advice-replace-highlight-after))
  "Replacement functions using individually defined native advice.")

(ert-deftest emacsvox-replace-advice-is-directly-registered ()
  "Migrated replacement advice bypasses the compatibility bridge."
  (dolist (target emacsvox-test--replace-after-targets)
    (let ((function (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers))))
  (dolist (target emacsvox-test--search-after-targets)
    (let ((function (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers))))
  (dolist (entry emacsvox-test--replace-direct-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target where function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-query-replace-feedback-is-interactive-only ()
  "Query replacement completion is announced once only when interactive."
  (let ((ems--interactive-fn-name 'query-replace)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events))))
      (emacsvox--advice-query-replace-regexp-after)
      (emacsvox--advice-query-replace-after)
      (emacsvox--advice-query-replace-after))
    (should (equal events '(task-done)))))

(ert-deftest emacsvox-perform-replace-preserves-silenced-call ()
  "Replacement execution is silenced and preserves arguments and result."
  (let ((emacsvox-speak-messages t)
        (inhibit-message nil)
        observed)
    (should
     (eq
      (emacsvox--advice-perform-replace-around
       (lambda (&rest arguments)
         (setq observed
               (list arguments emacsvox-speak-messages inhibit-message))
         'replace-result)
       'first 'second)
      'replace-result))
    (should (equal observed '((first second) nil t)))
    (should emacsvox-speak-messages)
    (should-not inhibit-message)))

(ert-deftest emacsvox-replace-highlight-always-speaks-line ()
  "Replacement highlighting speaks its line for every invocation."
  (let (events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda (&rest _) (push 'speak-line events))))
      (emacsvox--advice-replace-highlight-after))
    (should (equal events '(speak-line)))))

(ert-deftest emacsvox-nonincremental-search-preserves-feedback-order ()
  "Interactive search speaks its destination before the hit icon."
  (let ((ems--interactive-fn-name 'search-forward)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda (&rest _) (push 'speak-line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-search-backward-after)
      (emacsvox--advice-search-forward-after)
      (emacsvox--advice-search-forward-after))
    (should
     (equal
      (nreverse events)
      '(speak-line (icon search-hit))))))

(provide 'emacsvox-search-tests)
;;; emacsvox-search-tests.el ends here
