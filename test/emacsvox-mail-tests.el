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

(defconst emacsvox-test--mail-action-targets
  '(mail-signature mail-send-and-exit compose-mail expand-mail-aliases)
  "Mail actions converted to per-target native advice.")

(defun emacsvox-test--mail-field-advice-function (target)
  "Return the native Emacsvox Mail advice function for TARGET."
  (intern (format "emacsvox--advice-%s-after" target)))

(ert-deftest emacsvox-mail-converted-advice-is-directly-registered ()
  "Every converted Mail advice uses native advice directly."
  (dolist (target emacsvox-test--mail-compose-targets)
    (should
     (advice-member-p #'emacsvox--mail-compose-after target)))
  (dolist (target emacsvox-test--mail-field-targets)
    (let ((function (emacsvox-test--mail-field-advice-function target)))
      (should (fboundp function))
      (should (advice-member-p function target))))
  (dolist (target emacsvox-test--mail-action-targets)
    (let ((function (emacsvox-test--mail-field-advice-function target)))
      (should (fboundp function))
      (should (advice-member-p function target)))))

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

(ert-deftest emacsvox-mail-signature-feedback-is-target-aware ()
  "Only interactive signature insertion reports that the message was signed."
  (let ((ems--interactive-fn-name 'mail-signature)
        events)
    (cl-letf (((symbol-function 'message)
               (lambda (text) (push (list 'message text) events))))
      (emacsvox--advice-mail-send-and-exit-after)
      (emacsvox--advice-mail-signature-after))
    (should
     (equal events '((message "Signed your message"))))))

(ert-deftest emacsvox-mail-send-feedback-preserves-order ()
  "Sending mail cues closure before speaking the resulting mode line."
  (let ((ems--interactive-fn-name 'mail-send-and-exit)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'speak-mode-line events))))
      (emacsvox--advice-mail-send-and-exit-after))
    (should
     (equal
      (nreverse events)
      '((icon close-object) speak-mode-line)))))

(ert-deftest emacsvox-compose-mail-feedback-preserves-order ()
  "Interactive composition cues opening before speaking its current line."
  (let ((ems--interactive-fn-name 'compose-mail)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events))))
      (emacsvox--advice-compose-mail-after))
    (should
     (equal
      (nreverse events)
      '((icon open-object) speak-line)))))

(ert-deftest emacsvox-expand-mail-aliases-speaks-expanded-address ()
  "Interactive alias expansion reports the address before its selection cue."
  (with-temp-buffer
    (insert "To: person@example.com")
    (let ((ems--interactive-fn-name 'expand-mail-aliases)
          events)
      (cl-letf (((symbol-function 'message)
                 (lambda (format-string &rest arguments)
                   (push
                    (list 'message
                          (apply #'format format-string arguments))
                    events)))
                ((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events))))
        (emacsvox--advice-expand-mail-aliases-after))
      (should
       (equal
        (nreverse events)
        '((message " person@example.com")
          (icon select-object)))))))

(provide 'emacsvox-mail-tests)
;;; emacsvox-mail-tests.el ends here
