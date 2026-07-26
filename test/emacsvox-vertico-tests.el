;;; emacsvox-vertico-tests.el --- Vertico advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'vertico)
(load (expand-file-name "../lisp/emacsvox-vertico.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-vertico-advice-is-current-and-direct ()
  "Current Vertico targets use native advice directly."
  (dolist (entry emacsvox-vertico--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-vertico-insert-calls-original-once ()
  "Vertico insertion advice preserves the result and calls once."
  (with-temp-buffer
    (let ((calls 0))
      (cl-letf (((symbol-function 'emacsvox-icon) #'ignore)
                ((symbol-function 'emacsvox-speak-region) #'ignore))
        (should
         (eq 'inserted
             (emacsvox--advice-vertico-insert-around
              (lambda ()
                (cl-incf calls)
                (insert "candidate")
                'inserted))))
        (should (= calls 1))))))

(ert-deftest emacsvox-vertico-acceptance-carries-candidate-semantics ()
  "Accepted-candidate cue and speech share completion facts and context."
  (with-temp-buffer
    (let ((vertico--index 2)
          captured)
      (cl-letf
          (((symbol-function 'emacsvox-icon)
            (lambda (icon)
              (push
               (list
                icon
                (copy-tree emacsvox-aural-submission-facts)
                (copy-tree emacsvox-aural-submission-context))
               captured)))
           ((symbol-function 'emacsvox-speak-region)
            (lambda (&rest _)
              (push
               (list
                'speech
                (copy-tree emacsvox-aural-submission-facts)
                (copy-tree emacsvox-aural-submission-context))
               captured))))
        (emacsvox--advice-vertico-insert-around
         (lambda () (insert "candidate"))))
      (setq captured (nreverse captured))
      (should (equal (mapcar #'car captured) '(complete speech)))
      (dolist (entry captured)
        (should (eq (plist-get (cadr entry) :role) 'candidate))
        (should (equal (plist-get (cadr entry) :events) '(accepted)))
        (should (equal (plist-get (cadr entry) :states) '(selected)))
        (should (= (plist-get (cadr entry) :completion-index) 2))
        (should (eq (plist-get (caddr entry) :module) 'vertico))
        (should
         (eq (plist-get (caddr entry) :occasion) 'state-change))))))

(provide 'emacsvox-vertico-tests)
;;; emacsvox-vertico-tests.el ends here
