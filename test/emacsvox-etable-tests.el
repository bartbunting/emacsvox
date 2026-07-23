;;; emacsvox-etable-tests.el --- Table advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated table advice.

;;; Code:

(require 'cl-lib)
(require 'ert)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-etable.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--etable-advice
  '((table--make-cell-map
     :after emacsvox--advice-table--make-cell-map-after)
    (*table--cell-delete-char
     :around emacsvox--advice-*table--cell-delete-char-around)
    (*table--cell-delete-backward-char
     :around emacsvox--advice-*table--cell-delete-backward-char-around)
    (*table--cell-self-insert-command
     :after emacsvox--advice-*table--cell-self-insert-command-after)
    (*table--cell-quoted-insert
     :after emacsvox--advice-*table--cell-quoted-insert-after)
    (*table--cell-newline
     :before emacsvox--advice-*table--cell-newline-before)
    (*table--cell-newline-and-indent
     :around emacsvox--advice-*table--cell-newline-and-indent-around)
    (*table--cell-open-line
     :after emacsvox--advice-*table--cell-open-line-after)
    (table-forward-cell :after emacsvox--advice-table-forward-cell-after)
    (table-backward-cell :after emacsvox--advice-table-backward-cell-after))
  "Native advice registrations in the table integration.")

(ert-deftest emacsvox-etable-advice-is-directly-registered ()
  "Table advice bypasses the compatibility bridge."
  (dolist (entry emacsvox-test--etable-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target where function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-etable-delete-char-calls-original-once-after-feedback ()
  "Interactive forward deletion cues once before one original call."
  (let ((ems--interactive-fn-name '*table--cell-delete-char)
        events)
    (cl-letf (((symbol-function 'dtk-tone)
               (lambda (&rest _) (push 'tone events)))
              ((symbol-function 'emacsvox-speak-char)
               (lambda (&rest _) (push 'speak-char events))))
      (should
       (eq
        'original-result
        (emacsvox--advice-*table--cell-delete-char-around
         (lambda (&rest _)
           (push 'original events)
           'original-result)
         1)))
      (should
       (equal (nreverse events) '(tone speak-char original))))))

(ert-deftest emacsvox-etable-delete-char-is-quiet-programmatically ()
  "Programmatic forward deletion calls the original exactly once."
  (let ((calls 0)
        events)
    (cl-letf (((symbol-function 'dtk-tone)
               (lambda (&rest _) (push 'tone events)))
              ((symbol-function 'emacsvox-speak-char)
               (lambda (&rest _) (push 'speak-char events))))
      (should
       (eq
        'original-result
        (emacsvox--advice-*table--cell-delete-char-around
         (lambda (&rest _)
           (cl-incf calls)
           'original-result)
         1)))
      (should (= calls 1))
      (should-not events))))

(ert-deftest
    emacsvox-etable-delete-backward-calls-original-once-after-feedback ()
  "Interactive backward deletion speaks once before one original call."
  (let ((ems--interactive-fn-name '*table--cell-delete-backward-char)
        events)
    (with-temp-buffer
      (insert "x")
      (cl-letf (((symbol-function 'dtk-tone)
                 (lambda (&rest _) (push 'tone events)))
                ((symbol-function 'emacsvox-speak-this-char)
                 (lambda (character)
                   (push (list 'speak-char character) events))))
        (should
         (eq
          'original-result
          (emacsvox--advice-*table--cell-delete-backward-char-around
           (lambda (&rest _)
             (push 'original events)
             'original-result)
           1)))
        (should
         (equal
          (nreverse events)
          '(tone (speak-char 120) original)))))))

(ert-deftest emacsvox-etable-newline-and-indent-calls-original-once-last ()
  "Indent feedback precedes one original call and preserves its result."
  (let ((ems--interactive-fn-name '*table--cell-newline-and-indent)
        (emacsvox-line-echo nil)
        events)
    (cl-letf (((symbol-function 'dtk-speak-using-voice)
               (lambda (_voice text) (push (list 'speak text) events)))
              ((symbol-function 'dtk-interp-speak)
               (lambda () (push 'speak-now events))))
      (should
       (eq
        'original-result
        (emacsvox--advice-*table--cell-newline-and-indent-around
         (lambda ()
           (push 'original events)
           'original-result))))
      (should
       (equal
        (nreverse events)
        '((speak "indent 0") speak-now original))))))

(ert-deftest emacsvox-etable-open-line-uses-explicit-count ()
  "Open-line feedback uses its native COUNT argument."
  (let ((ems--interactive-fn-name '*table--cell-open-line)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'message)
               (lambda (format-string &rest args)
                 (push (apply #'format format-string args) events))))
      (emacsvox--advice-*table--cell-open-line-after 3))
    (should
     (equal
      (nreverse events)
      '((icon open-object) "Opened 3 blank lines")))))

(ert-deftest emacsvox-etable-navigation-feedback-is-target-aware ()
  "Only the matching interactive table navigation command speaks."
  (let ((ems--interactive-fn-name 'table-forward-cell)
        events)
    (cl-letf (((symbol-function 'table--finish-delayed-tasks)
               (lambda () (push 'finish events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-etable-speak-cell)
               (lambda () (push 'speak-cell events))))
      (emacsvox--advice-table-backward-cell-after)
      (emacsvox--advice-table-forward-cell-after))
    (should
     (equal
      (nreverse events)
      '(finish (icon select-object) speak-cell)))))

(provide 'emacsvox-etable-tests)
;;; emacsvox-etable-tests.el ends here
