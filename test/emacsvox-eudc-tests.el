;;; emacsvox-eudc-tests.el --- EUDC advice tests -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'eudc)
(load
 (expand-file-name "../lisp/emacsvox-eudc.el"
                   (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(ert-deftest emacsvox-eudc-advice-is-directly-registered ()
  (dolist
      (entry
       '((eudc-move-to-next-record
          :after emacsvox--advice-eudc-move-to-next-record-after)
         (eudc-move-to-previous-record
          :after emacsvox--advice-eudc-move-to-previous-record-after)
         (eudc-query-form :after emacsvox--advice-eudc-query-form-after)
         (eudc-print-attribute-value
          :around emacsvox--advice-eudc-print-attribute-value-around)))
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-eudc-navigation-feedback-is-target-aware ()
  (let ((ems--interactive-fn-name 'eudc-move-to-previous-record) events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events))))
      (emacsvox--advice-eudc-move-to-next-record-after)
      (emacsvox--advice-eudc-move-to-previous-record-after))
    (should (equal (nreverse events) '(select-object line)))))

(ert-deftest emacsvox-eudc-attribute-value-runs-once ()
  (with-temp-buffer
    (let ((emacsvox-eudc-attribute-value-personality 'voice-animate)
          (calls 0))
      (should
       (eq 'result
           (emacsvox--advice-eudc-print-attribute-value-around
            (lambda (field)
              (setq calls (1+ calls))
              (should (eq field 'mail))
              (insert "value")
              'result)
            'mail)))
      (should (= calls 1))
      (should
       (eq (get-text-property 2 'personality) 'voice-animate)))))

(ert-deftest emacsvox-eudc-disabled-personality-runs-once ()
  (with-temp-buffer
    (let ((emacsvox-eudc-attribute-value-personality nil)
          (calls 0))
      (should
       (eq 'result
           (emacsvox--advice-eudc-print-attribute-value-around
            (lambda (&rest _)
              (setq calls (1+ calls))
              (insert "value")
              'result))))
      (should (= calls 1))
      (should-not (get-text-property 2 'personality)))))

(provide 'emacsvox-eudc-tests)
