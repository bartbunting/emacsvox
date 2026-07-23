;;; emacsvox-mail-tests.el --- Mail advice migration tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Focused coverage for the native Mail advice in emacsvox-advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-speak)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-advice.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise the source under test even when a compiled core module exists.
  (load module nil nil))

;; Define the advised autoloads after registration.  This is the path that
;; produced `ad-handle-definition' warnings with the legacy advice.
(require 'sendmail)

(defconst emacsvox-test--mail-compose-targets
  '(mail mail-other-window mail-other-frame)
  "Mail composition commands converted to shared native advice.")

(defconst emacsvox-test--mail-field-targets
  '(mail-text mail-subject mail-cc mail-bcc
    mail-to mail-reply-to mail-fcc)
  "Mail field commands converted to per-target native advice.")

(defun emacsvox-test--mail-field-advice-function (target)
  "Return the native Emacsvox Mail advice function for TARGET."
  (intern (format "emacsvox--advice-%s-after" target)))

(ert-deftest emacsvox-mail-converted-advice-is-directly-registered ()
  "Every converted Mail advice bypasses the compatibility bridge."
  (dolist (target emacsvox-test--mail-compose-targets)
    (should
     (advice-member-p #'emacsvox--mail-compose-after target))
    (should-not
     (gethash
      (list target :after #'emacsvox--mail-compose-after)
      ems--modern-advice-wrappers)))
  (dolist (target emacsvox-test--mail-field-targets)
    (let ((function (emacsvox-test--mail-field-advice-function target)))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-mail-compose-advice-preserves-feedback-and-point ()
  "Composition feedback speaks the first line without moving point."
  (with-temp-buffer
    (insert "To: person@example.com\nSubject: Test\n")
    (goto-char (point-max))
    (let ((original-point (point))
          events)
      (cl-letf (((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events)))
                ((symbol-function 'emacsvox-speak-line)
                 (lambda () (push (list 'speak-line (point)) events))))
        ;; The old advice deliberately had no interactive-only guard.
        (let ((ems--interactive-fn-name nil))
          (emacsvox--mail-compose-after)))
      (should
       (equal
        (nreverse events) '((icon open-object) (speak-line 1))))
      (should (= (point) original-point)))))

(ert-deftest emacsvox-mail-field-advice-preserves-interactive-check ()
  "Field feedback occurs once interactively and not programmatically."
  (let ((function
         (emacsvox-test--mail-field-advice-function 'mail-subject))
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events))))
      (let ((ems--interactive-fn-name nil))
        (funcall function))
      (let ((ems--interactive-fn-name 'mail-subject))
        (funcall function)
        (funcall function)))
    (should (equal events '(speak-line)))))

(provide 'emacsvox-mail-tests)
;;; emacsvox-mail-tests.el ends here
