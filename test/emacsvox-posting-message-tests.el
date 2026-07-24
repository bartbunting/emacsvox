;;; emacsvox-posting-message-tests.el --- Message integration tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Message advice.

;;; Code:

(require 'ert)
(require 'message)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-message.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--posting-message-after-targets
  '(message-send
    message-send-and-exit
    message-goto-to
    message-goto-summary
    message-goto-subject
    message-goto-cc
    message-goto-bcc
    message-goto-fcc
    message-goto-keywords
    message-goto-newsgroups
    message-goto-followup-to
    message-goto-reply-to
    message-goto-body
    message-goto-signature
    message-goto-distribution
    message-insert-citation-line
    message-insert-to
    message-insert-signature
    message-insert-newsgroups
    message-insert-courtesy-copy
    message-goto-from
    message-goto-mail-followup-to
    message-newline-and-reformat)
  "Current Emacs 31 Message targets using direct after advice.")

(ert-deftest emacsvox-posting-message-advice-is-directly-registered ()
  "Message advice is attached directly to current Emacs 31 targets."
  (dolist (target emacsvox-test--posting-message-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers))))
  (should
   (advice-member-p
    #'emacsvox--advice-message-beginning-of-line-before
    'message-beginning-of-line))
  (should-not
   (gethash
    '(message-beginning-of-line
      :before
      emacsvox--advice-message-beginning-of-line-before)
    ems--modern-advice-wrappers)))

(ert-deftest emacsvox-posting-message-send-feedback-is-target-aware ()
  "Only the matching Message send command produces feedback."
  (let ((ems--interactive-fn-name 'message-send-and-exit)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'mode-line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-message-send-after)
      (emacsvox--advice-message-send-and-exit-after))
    (should
     (equal
      (nreverse events)
      '(mode-line (icon close-object))))))

(ert-deftest emacsvox-posting-message-movement-feedback-is-target-aware ()
  "Only the matching Message field command produces feedback."
  (let ((ems--interactive-fn-name 'message-goto-subject)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda (&rest _) (push 'line events))))
      (emacsvox--advice-message-goto-to-after)
      (emacsvox--advice-message-goto-subject-after))
    (should
     (equal
      (nreverse events)
      '((icon large-movement) line)))))

(ert-deftest emacsvox-posting-message-body-and-format-feedback-differ ()
  "Body movement and newline formatting retain distinct announcements."
  (let ((ems--interactive-fn-name 'message-newline-and-reformat)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push
                  (list 'message (apply #'format format-string arguments))
                  events))))
      (emacsvox--advice-message-goto-body-after)
      (emacsvox--advice-message-newline-and-reformat-after))
    (should
     (equal
      (nreverse events)
      '((icon fill-object) (message "newline and reformat"))))))

(ert-deftest emacsvox-posting-message-line-start-preserves-feedback-order ()
  "Message line-start feedback stops speech before its spoken cue."
  (let ((ems--interactive-fn-name 'message-beginning-of-line)
        events)
    (cl-letf (((symbol-function 'dtk-stop)
               (lambda (scope) (push (list 'stop scope) events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'dtk-speak)
               (lambda (text) (push (list 'speak text) events))))
      (emacsvox--advice-message-beginning-of-line-before))
    (should
     (equal
      (nreverse events)
      '((stop all)
        (icon select-object)
        (speak "beginning of line"))))))

(provide 'emacsvox-posting-message-tests)
;;; emacsvox-posting-message-tests.el ends here
