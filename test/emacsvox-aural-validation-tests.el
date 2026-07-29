;;; emacsvox-aural-validation-tests.el --- Aural validation tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Focused tests for the shared scheme and presentation-option diagnostic
;; pipeline.

;;; Code:

(require 'ert)
(require 'emacsvox-aural-validation)
(require 'emacsvox-sounds)

(defmacro emacsvox-test--with-aural-validation (&rest body)
  "Run BODY with isolated aural configuration registries."
  (declare (indent 0) (debug t))
  `(let ((emacsvox-aural-scheme-registry
          (make-hash-table :test #'eq))
         (emacsvox-aural-module-fragment-registry
          (make-hash-table :test #'eq))
         (emacsvox-aural-feature-fragment-registry
          (make-hash-table :test #'eq))
         (emacsvox-aural-enabled-feature-fragments nil)
         (emacsvox-aural-feature-fragment-order nil)
         (emacsvox-aural-user-rules nil)
         (emacsvox-aural-session-rules nil)
         (emacsvox-aural-buffer-rules nil)
         (emacsvox-aural-active-scheme 'default)
         (emacsvox-aural-configuration-generation 0)
         (emacsvox-aural-configuration-changed-hook nil)
         (emacsvox-aural-active-scheme-changed-hook nil)
         (emacsvox-aural-effective-resource-pack-changed-hook nil)
         (emacsvox-aural-feature-fragments-changed-hook nil)
         (emacsvox-aural--current-rules-cache
          (make-hash-table :test #'equal))
         (emacsvox-aural--provider-cache
          (make-hash-table :test #'equal)))
     (emacsvox-aural--register-default-scheme)
     ,@body))

(ert-deftest
    emacsvox-aural-validation-scheme-and-fragment-share-rule-diagnostics ()
  "Schemes and presentation options receive the same rule diagnostics."
  (emacsvox-test--with-aural-validation
    (let ((rules
           '((:id no-effect
              :match (:role heading)
              :render ())
             (:id tie-a
              :order 5
              :match (:role heading)
              :render (:content (:voice bolden)))
             (:id tie-b
              :order 5
              :match (:role heading)
              :render (:content (:voice lighten)))
             (:id parked
              :enabled nil
              :match (:role heading)
              :render (:content (:voice smoothen))))))
      (emacsvox-aural-register-scheme
       (list
        :schema-version 1
        :id 'diagnostic-scheme
        :summary "Diagnostic scheme"
        :parent 'default
        :rules rules)
       :source "test")
      (emacsvox-aural-register-feature-fragment
       (list
        :schema-version 1
        :id 'diagnostic-option
        :summary "Diagnostic option"
        :rules rules)
       :source "test")
      (let ((scheme
             (emacsvox-aural-validate-scheme 'diagnostic-scheme))
            (fragment
             (emacsvox-aural-validate-feature-fragment
              'diagnostic-option)))
        (dolist
            (accessor
             '(emacsvox-aural-validation-report-valid
               emacsvox-aural-validation-report-warnings
               emacsvox-aural-validation-report-unreachable-rules
               emacsvox-aural-validation-report-ambiguous-ties
               emacsvox-aural-validation-report-disabled-rules
               emacsvox-aural-validation-report-semantic-diagnostics))
          (should
           (equal (funcall accessor scheme)
                  (funcall accessor fragment))))
        (should
         (equal
          (emacsvox-aural-validation-report-unreachable-rules scheme)
          '(no-effect)))
        (should
         (equal
          (emacsvox-aural-validation-report-ambiguous-ties scheme)
          '((tie-a . tie-b))))
        (should
         (equal
          (emacsvox-aural-validation-report-disabled-rules scheme)
          '(parked)))))))

(ert-deftest emacsvox-aural-validation-unknown-objects-return-reports ()
  "Unknown schemes and options produce invalid reports rather than escaping."
  (emacsvox-test--with-aural-validation
    (dolist
        (report
         (list
          (emacsvox-aural-validate-scheme 'missing-scheme)
          (emacsvox-aural-validate-feature-fragment 'missing-option)))
      (should-not (emacsvox-aural-validation-report-valid report))
      (should (emacsvox-aural-validation-report-errors report)))))

(ert-deftest emacsvox-aural-validation-reports-unavailable-tones ()
  "Validation rejects declarative actions naming unregistered tones."
  (emacsvox-test--with-aural-validation
    (emacsvox-aural-register-scheme
     '(:schema-version 1
       :id missing-tone
       :summary "Missing tone"
       :parent default
       :rules
       ((:id line
         :match (:role heading)
         :render
         (:before
          ((:id signal :kind tone :tone not-registered))))))
     :source "test")
    (let ((report (emacsvox-aural-validate-scheme 'missing-tone)))
      (should-not (emacsvox-aural-validation-report-valid report))
      (should
       (equal
        (emacsvox-aural-validation-report-unavailable-tones report)
        '(not-registered)))
      (should
       (member
        "Unavailable tones: (not-registered)"
        (emacsvox-aural-validation-report-errors report))))))

(provide 'emacsvox-aural-validation-tests)

;;; emacsvox-aural-validation-tests.el ends here
