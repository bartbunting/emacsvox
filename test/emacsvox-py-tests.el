;;; emacsvox-py-tests.el --- Python Mode advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'python-mode)
(defvar emacsvox-comint-autospeak)
(load (expand-file-name "../lisp/emacsvox-py.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-py-current-advice-is-direct ()
  "Every available Python Mode target uses native advice directly."
  (dolist (entry emacsvox-py--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (when (fboundp target)
        (should (advice-member-p function target))))))

(ert-deftest emacsvox-py-electric-delete-calls-original-once ()
  "Forward deletion invokes its original once and submits the captured char."
  (with-temp-buffer
    (insert "x")
    (goto-char (point-min))
    (let ((calls 0)
          (ems--interactive-fn-name 'py-electric-delete)
          submission
          events)
      (cl-letf
          (((symbol-function 'emacsvox-py--submit-text)
            (lambda (&rest arguments)
              (setq submission arguments)
              (push 'submission events))))
        (should
         (eq
          'deleted
          (emacsvox--advice-py-electric-delete-around
           (lambda (&rest arguments)
             (cl-incf calls)
             (push (cons 'original arguments) events)
             'deleted)
           2))))
      (should (= calls 1))
      (should
       (equal
        (nreverse events)
        '((original 2) submission)))
      (should
       (equal
        submission
        '("Deleted 2 characters"
          (:role code-construct :events (object-changed)
           :syntax-role character :code-edit-kind delete-character
           :edit-operation deletion)
          edit))))))

(ert-deftest emacsvox-py-whitespace-backspace-preserves-context ()
  "Whitespace backspace presents deletion before its containing block."
  (with-temp-buffer
    (insert "    ")
    (let ((calls 0)
          (ems--interactive-fn-name 'py-electric-backspace)
          events)
      (cl-letf
          (((symbol-function 'emacsvox-py--present-deletion)
            (lambda (&rest arguments)
              (push (cons 'deletion arguments) events)))
           ((symbol-function 'py-beginning-of-block)
            (lambda () (push 'beginning-of-block events)))
           ((symbol-function 'emacsvox-py--present-current-line)
            (lambda (&rest arguments)
              (push (cons 'line arguments) events))))
        (should
         (=
          (emacsvox--advice-py-electric-backspace-around
           (lambda (&rest arguments)
             (cl-incf calls)
             (push (cons 'original arguments) events)
             3)
           1)
          3)))
      (should (= calls 1))
      (should
       (equal
        (nreverse events)
        '((original 1)
          (deletion (nil 32 t) 1 3)
          beginning-of-block
          (line
           (:role code-construct :events (focus-entered)
            :syntax-role block)
           edit (close-object))))))))

(ert-deftest emacsvox-py-execution-feedback-is-started-not-completed ()
  "Executing Python code reports submission rather than false completion."
  (let ((ems--interactive-fn-name 'py-execute-buffer)
        submissions)
    (cl-letf
        (((symbol-function 'emacsvox-py--submit-actions)
          (lambda (&rest arguments)
            (push arguments submissions))))
      (emacsvox--advice-py-execute-region-after)
      (emacsvox--advice-py-execute-buffer-after))
    (should
     (equal
      submissions
      '(((:role code-operation :events (operation-started)
          :code-operation-kind py-execute-buffer)
         state-change))))))

(ert-deftest emacsvox-py-indentation-feedback-is-native ()
  "Python Mode indentation summaries carry explicit edit semantics."
  (with-temp-buffer
    (insert "one\ntwo\n")
    (set-mark (point-min))
    (activate-mark)
    (let ((ems--interactive-fn-name 'py-shift-region-right)
          submission)
      (cl-letf
          (((symbol-function 'emacsvox-py--submit-text)
            (lambda (&rest arguments)
              (setq submission arguments))))
        (emacsvox--advice-py-shift-region-right-after))
      (should
       (equal
        submission
        '("Right shifted block  containing 2 lines"
          (:role code-construct :events (object-changed)
           :syntax-role block :code-edit-kind shift-right)
          edit))))))

(ert-deftest emacsvox-py-process-filter-calls-original-once ()
  "Process output passes explicit arguments once and preserves its result."
  (with-temp-buffer
    (let ((calls 0)
          received
          (emacsvox-comint-autospeak nil))
      (should
       (eq
        'filtered
        (emacsvox--advice-py-process-filter-around
         (lambda (process output)
           (cl-incf calls)
           (setq received (list process output))
           'filtered)
         'process "output")))
      (should (= calls 1))
      (should (equal received '(process "output"))))))

(provide 'emacsvox-py-tests)
;;; emacsvox-py-tests.el ends here
