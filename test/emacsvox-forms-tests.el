;;; emacsvox-forms-tests.el --- Forms advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Forms advice.

;;; Code:

(require 'cl-lib)
(require 'ert)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-forms.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--forms-after-advice
  '((forms-search-forward emacsvox--advice-forms-search-forward-after)
    (forms-search-backward emacsvox--advice-forms-search-backward-after)
    (forms-next-record emacsvox--advice-forms-next-record-after)
    (forms-prev-record emacsvox--advice-forms-prev-record-after)
    (forms-first-record emacsvox--advice-forms-first-record-after)
    (forms-last-record emacsvox--advice-forms-last-record-after)
    (forms-jump-record emacsvox--advice-forms-jump-record-after)
    (forms-exit emacsvox--advice-forms-exit-after)
    (forms-next-field emacsvox--advice-forms-next-field-after)
    (forms-prev-field emacsvox--advice-forms-prev-field-after)
    (forms-delete-record emacsvox--advice-forms-delete-record-after)
    (forms-insert-record emacsvox--advice-forms-insert-record-after)
    (forms-save-buffer emacsvox--advice-forms-save-buffer-after))
  "Native after-advice registrations in the Forms integration.")

(ert-deftest emacsvox-forms-advice-is-directly-registered ()
  "Forms advice uses current targets and bypasses the compatibility bridge."
  (dolist (entry emacsvox-test--forms-after-advice)
    (pcase-let ((`(,target ,function) entry))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers))))
  (should-not
   (advice-member-p 'ems--forms-next-field-around 'forms-next-field)))

(ert-deftest emacsvox-forms-search-feedback-is-target-aware ()
  "Only the matching Forms search cues and speaks the line."
  (let ((ems--interactive-fn-name 'forms-search-forward)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events))))
      (emacsvox--advice-forms-search-backward-after)
      (emacsvox--advice-forms-search-forward-after))
    (should
     (equal
      (nreverse events)
      '((icon search-hit) speak-line)))))

(ert-deftest emacsvox-forms-record-movement-preserves-feedback-order ()
  "Record movement cues, moves to the field, and then summarizes."
  (with-temp-buffer
    (insert "abcd")
    (put-text-property 3 4 'read-only t)
    (goto-char 1)
    (let ((ems--interactive-fn-name 'forms-next-record)
          events)
      (cl-letf (((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events)))
                ((symbol-function 'emacsvox-forms-summarize-current-record)
                 (lambda () (push (list 'summary (point)) events))))
        (emacsvox--advice-forms-prev-record-after)
        (emacsvox--advice-forms-next-record-after))
      (should
       (equal
        (nreverse events)
        '((icon select-object) (summary 3)))))))

(ert-deftest emacsvox-forms-next-field-runs-original-once ()
  "The migrated field advice preserves one original call and its result."
  (let ((ems--interactive-fn-name 'forms-next-field)
        (calls 0)
        events)
    (cl-letf (((symbol-function 'emacsvox-test--forms-field-target)
               (lambda ()
                 (cl-incf calls)
                 'original-result))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-forms-speak-field)
               (lambda () (push 'speak-field events))))
      (advice-add
       'emacsvox-test--forms-field-target :after
       #'emacsvox--advice-forms-next-field-after)
      (unwind-protect
          (should
           (eq (emacsvox-test--forms-field-target) 'original-result))
        (advice-remove
         'emacsvox-test--forms-field-target
         #'emacsvox--advice-forms-next-field-after)))
    (should (= calls 1))
    (should
     (equal
      (nreverse events)
      '((icon large-movement) speak-field)))))

(provide 'emacsvox-forms-tests)
;;; emacsvox-forms-tests.el ends here
