;;; emacsvox-evil-tests.el --- Evil advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'evil)
(load (expand-file-name "../lisp/emacsvox-evil.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-evil-advice-is-current-and-direct ()
  "Current Evil targets use native advice directly."
  (dolist (entry emacsvox-evil--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-evil-feedback-is-target-aware ()
  "Only the matching interactive Evil movement command speaks."
  (let ((ems--interactive-fn-name 'evil-next-line)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events))))
      (emacsvox--advice-evil-previous-line-after)
      (emacsvox--advice-evil-next-line-after))
    (should (equal events '(line)))))

(ert-deftest emacsvox-evil-delete-uses-native-arguments ()
  "Evil deletion feedback uses its explicit BEG and END arguments."
  (let ((ems--interactive-fn-name 'evil-delete)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'emacsvox-speak-region)
               (lambda (beg end) (push (list beg end) events))))
      (emacsvox--advice-evil-delete-before 3 8))
    (should (equal (nreverse events) '(delete-object (3 8))))))

(ert-deftest emacsvox-evil-completion-calls-original-once ()
  "Native Evil completion advice preserves result and invocation count."
  (with-temp-buffer
    (insert "hel")
    (goto-char (point-max))
    (let ((ems--interactive-fn-name 'evil-complete-next)
          (calls 0)
          spoken)
      (cl-letf (((symbol-function 'emacsvox-icon) #'ignore)
                ((symbol-function 'dtk-speak)
                 (lambda (text) (setq spoken text))))
        (should
         (eq 'result
             (emacsvox--advice-evil-complete-next-around
              (lambda (&rest _)
                (cl-incf calls)
                (insert "p")
                'result))))
      (should (= calls 1))
      (should (equal spoken "help"))))))

(provide 'emacsvox-evil-tests)
;;; emacsvox-evil-tests.el ends here
