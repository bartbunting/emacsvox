;;; emacsvox-advice-audit-tests.el --- Tests for advice audit -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for syntax-aware advice migration inventory.

;;; Code:

(require 'ert)
(require 'advice-audit)

(defun emacsvox-test--audit-source (source)
  "Return advice audit data parsed from SOURCE."
  (with-temp-buffer
    (insert source)
    (ems-advice-audit-buffer "fixture.el")))

(ert-deftest emacsvox-advice-audit-ignores-comments-and-strings ()
  "Text that merely mentions legacy constructs is not executable advice."
  (let ((result
         (emacsvox-test--audit-source
          ";; (defadvice ignored (after test) (ad-do-it))\n\
           (defconst text \"ad-get-arg defadvice\")\n")))
    (should-not (plist-get result :defadvice))
    (should
     (equal
      (plist-get result :symbol-counts)
      '((ad-get-arg . 0) (ad-set-arg . 0) (ad-do-it . 0)
        (ad-return-value . 0) (ad-find-some-advice . 0)
        (ems-interactive-p . 0))))))

(ert-deftest emacsvox-advice-audit-finds-backquoted-templates ()
  "Advice generated inside a backquoted macro is included in the audit."
  (let* ((result
          (emacsvox-test--audit-source
           "(defmacro fixture (target)\n\
              `(defadvice ,target (after emacsvox)\n\
                 (when (ems-interactive-p) (message \"done\"))))\n"))
         (legacy (car (plist-get result :defadvice))))
    (should (eq (plist-get legacy :target) 'dynamic))
    (should (eq (plist-get legacy :class) 'after))
    (should (eq (plist-get legacy :risk) 'review))
    (should
     (= 1 (alist-get 'ems-interactive-p
                     (plist-get result :symbol-counts))))))

(ert-deftest emacsvox-advice-audit-classifies-risky-semantics ()
  "Argument and return mutation make legacy advice complex."
  (let* ((result
          (emacsvox-test--audit-source
           "(defadvice target (around emacsvox)\n\
              (ad-set-arg 0 'changed)\n\
              ad-do-it\n\
              (setq ad-return-value 'replacement))\n"))
         (legacy (car (plist-get result :defadvice))))
    (should (eq (plist-get legacy :risk) 'complex))
    (should (= 1 (plist-get legacy :ad-set-arg)))
    (should (= 1 (plist-get legacy :ad-do-it)))
    (should (= 1 (plist-get legacy :ad-return-value)))))

(ert-deftest emacsvox-advice-audit-counts-modern-and-legacy-forms ()
  "The audit reports modern registrations and parsed compatibility uses."
  (let ((result
         (emacsvox-test--audit-source
          "(defun ems--target-after (&rest args)\n\
             (message \"%s\" (ad-get-arg 0)))\n\
           (advice-add 'target :after #'ems--target-after)\n")))
    (should (= 1 (plist-get result :advice-add-count)))
    (should
     (= 1 (alist-get 'ad-get-arg (plist-get result :symbol-counts))))))

(ert-deftest emacsvox-advice-audit-counts-legacy-introspection ()
  "The audit includes legacy advice introspection APIs."
  (let ((result
         (emacsvox-test--audit-source
          "(ad-find-some-advice 'target 'any \"emacsvox\")\n")))
    (should
     (= 1
        (alist-get
         'ad-find-some-advice
         (plist-get result :symbol-counts))))))

(provide 'emacsvox-advice-audit-tests)
;;; emacsvox-advice-audit-tests.el ends here
