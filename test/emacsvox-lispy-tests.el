;;; emacsvox-lispy-tests.el --- Lispy advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'lispy)
(load (expand-file-name "../lisp/emacsvox-lispy.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-lispy-advice-is-current-and-direct ()
  "Current Lispy targets use native advice directly."
  (dolist (entry emacsvox-lispy--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-lispy-navigation-calls-original-once ()
  "Lispy navigation advice preserves the result and calls once."
  (with-temp-buffer
    (let ((ems--interactive-fn-name 'lispy-forward)
          (calls 0))
      (cl-letf (((symbol-function 'tts-notify) #'ignore)
                ((symbol-function 'emacsvox-icon) #'ignore))
        (should
         (eq 'moved
             (emacsvox--advice-lispy-forward-around
              (lambda ()
                (cl-incf calls)
                'moved))))
        (should (= calls 1))))))

(ert-deftest emacsvox-lispy-delete-preserves-feedback-order ()
  "Interactive forward deletion presents feedback before calling once."
  (with-temp-buffer
    (insert "xy")
    (goto-char (point-min))
    (let ((ems--interactive-fn-name 'lispy-delete)
          (calls 0)
          events)
      (cl-letf
          (((symbol-function 'emacsvox-speak-edit-operation)
            (lambda (operation)
              (push (list 'edit operation) events)))
           ((symbol-function 'emacsvox-speak-char)
            (lambda (delete-p)
              (push (list 'character delete-p) events))))
        (should
         (eq
          (emacsvox--advice-lispy-delete-around
           (lambda (argument)
             (cl-incf calls)
             (push (list 'original argument) events)
             'deleted)
           2)
          'deleted)))
      (should (= calls 1))
      (should
       (equal
        (nreverse events)
        '((edit deletion) (character t) (original 2)))))))

(ert-deftest emacsvox-lispy-delete-is-quiet-programmatically ()
  "Programmatic forward deletion calls once without feedback."
  (let ((ems--interactive-fn-name nil)
        (calls 0)
        feedback)
    (cl-letf
        (((symbol-function 'emacsvox-speak-edit-operation)
          (lambda (&rest _) (setq feedback t)))
         ((symbol-function 'emacsvox-speak-char)
          (lambda (&rest _) (setq feedback t))))
      (should
       (eq
        (emacsvox--advice-lispy-delete-around
         (lambda (&rest _)
           (cl-incf calls)
           'programmatic-result)
         1)
        'programmatic-result)))
    (should (= calls 1))
    (should-not feedback)))

(ert-deftest emacsvox-lispy-show-uses-native-argument ()
  "Lispy display advice speaks its explicit string argument."
  (let (spoken)
    (cl-letf (((symbol-function 'emacsvox-icon) #'ignore)
              ((symbol-function 'tts-speak)
               (lambda (text) (setq spoken text))))
      (emacsvox--advice-lispy--show-before "details"))
    (should (equal spoken "details"))))

(provide 'emacsvox-lispy-tests)
;;; emacsvox-lispy-tests.el ends here
