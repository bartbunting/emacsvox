;;; emacsvox-company-tests.el --- Company advice tests -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'package)
(package-initialize)
(require 'company)

(load
 (expand-file-name
  "../lisp/emacsvox-company.el"
  (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(ert-deftest emacsvox-company-current-target-contracts ()
  "Use the current Company completion command, not its obsolete alias."
  (should (equal (help-function-arglist 'company-complete-selection t) nil))
  (should
   (equal (help-function-arglist 'company-complete-tooltip-row t) '(number)))
  (should
   (equal
    (help-function-arglist 'company-show-doc-buffer t)
    '(&optional toggle-auto-update)))
  (should-not
   (advice-member-p
    #'emacsvox--advice-company-complete-tooltip-row-after
    'company-complete-number)))

(ert-deftest emacsvox-company-advice-is-directly-registered ()
  "Company advice uses native advice directly."
  (dolist (entry emacsvox-company--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-company-completion-feedback-is-target-aware ()
  "Only matching interactive completion speaks."
  (let ((ems--interactive-fn-name 'company-complete-tooltip-row)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'dtk-speak)
               (lambda (text) (push text events))))
      (emacsvox--advice-company-complete-selection-before)
      (emacsvox--advice-company-complete-tooltip-row-after))
    (should (equal events '(line)))))

(ert-deftest emacsvox-company-doc-advice-handles-buffer-position-pair ()
  "Company documentation may return a buffer-position pair."
  (let ((company-selection 0)
        (company-candidates '("candidate"))
        spoken)
    (with-temp-buffer
      (insert "Documentation")
      (let ((buffer (current-buffer)))
        (cl-letf (((symbol-function 'company-call-backend)
                   (lambda (&rest _) (cons buffer 4)))
                  ((symbol-function 'dtk-speak)
                   (lambda (text) (setq spoken text))))
          (emacsvox--advice-company-show-doc-buffer-before))))
    (should (equal spoken "Documentation"))))

(provide 'emacsvox-company-tests)
;;; emacsvox-company-tests.el ends here
