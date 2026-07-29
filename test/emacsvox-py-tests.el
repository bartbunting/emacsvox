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
  "Electric deletion invokes its original command exactly once."
  (with-temp-buffer
    (insert "x")
    (let ((calls 0)
          (ems--interactive-fn-name 'py-electric-delete)
          events)
      (cl-letf
          (((symbol-function 'emacsvox-speak-edit-operation)
            (lambda (operation)
              (push (list 'edit operation) events)))
           ((symbol-function 'emacsvox-speak-this-char)
            (lambda (character)
              (push (list 'character character) events))))
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
        '((original 2) (edit deletion) (character 120)))))))

(ert-deftest emacsvox-py-whitespace-backspace-preserves-feedback-order ()
  "Whitespace backspace reports its resulting block after deletion."
  (with-temp-buffer
    (insert "    ")
    (let ((calls 0)
          (ems--interactive-fn-name 'py-electric-backspace)
          events)
      (cl-letf
          (((symbol-function 'emacsvox-speak-edit-operation)
            (lambda (operation)
              (push (list 'edit operation) events)))
           ((symbol-function 'tts-notify)
            (lambda (text) (push (list 'notify text) events)))
           ((symbol-function 'emacsvox-icon)
            (lambda (icon) (push (list 'icon icon) events)))
           ((symbol-function 'sit-for)
            (lambda (seconds) (push (list 'sit-for seconds) events)))
           ((symbol-function 'py-beginning-of-block)
            (lambda () (push 'beginning-of-block events)))
           ((symbol-function 'emacsvox-speak-line)
            (lambda () (push 'line events))))
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
          (edit deletion)
          (notify "Indent 3 ")
          (icon close-object)
          (sit-for 0.2)
          beginning-of-block
          line))))))

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
