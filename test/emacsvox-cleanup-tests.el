;;; emacsvox-cleanup-tests.el --- Cleanup advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated cleanup advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(defconst emacsvox-test--cleanup-direct-advice
  '((whitespace-cleanup :around
    emacsvox--advice-whitespace-cleanup-around)
    (whitespace-cleanup-internal :around
     emacsvox--advice-whitespace-cleanup-internal-around)
    (clean-buffer-list :around emacsvox--silence-messages-around))
  "Cleanup functions using individually named native advice.")

(ert-deftest emacsvox-cleanup-advice-is-directly-registered ()
  "Migrated cleanup advice uses native advice directly."
  (dolist (entry emacsvox-test--cleanup-direct-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-whitespace-cleanup-calls-original-once ()
  "Whitespace cleanup calls once, quietly, and preserves args and result."
  (let ((emacsvox-speak-messages t)
        (inhibit-message nil)
        (calls 0)
        observed-state)
    (should
     (eq
      (emacsvox--advice-whitespace-cleanup-around
       (lambda (&rest arguments)
         (cl-incf calls)
         (setq observed-state
               (list arguments emacsvox-speak-messages inhibit-message))
         'cleanup-result)
       'argument)
      'cleanup-result))
    (should (= calls 1))
    (should (equal observed-state '((argument) nil t)))
    (should emacsvox-speak-messages)
    (should-not inhibit-message)))

(ert-deftest emacsvox-whitespace-cleanup-wrappers-share-semantics ()
  "Public and internal whitespace cleanup wrappers preserve the same result."
  (let ((emacsvox-speak-messages t)
        (inhibit-message nil))
    (should
     (eq
      (emacsvox--advice-whitespace-cleanup-internal-around
       (lambda () 'internal-result))
      'internal-result))
    (should emacsvox-speak-messages)
    (should-not inhibit-message)))

(ert-deftest emacsvox-clean-buffer-list-runs-once-with-messages-silenced ()
  "Background buffer cleanup runs once and restores message state."
  (let ((emacsvox-speak-messages t)
        (inhibit-message nil)
        (calls 0)
        observed-state)
    (should
     (eq
      (emacsvox--silence-messages-around
       (lambda (&rest arguments)
         (cl-incf calls)
         (setq observed-state
               (list arguments emacsvox-speak-messages inhibit-message))
         'cleanup-result)
       'argument)
      'cleanup-result))
    (should (= calls 1))
    (should (equal observed-state '((argument) nil t)))
    (should emacsvox-speak-messages)
    (should-not inhibit-message)))

(provide 'emacsvox-cleanup-tests)
;;; emacsvox-cleanup-tests.el ends here
