;;; emacsvox-posting-message-tests.el --- Message integration tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Message advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'message)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-message.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--posting-message-after-targets
  '(message-goto-to
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
    message-newline-and-reformat
    message-setup-1
    mml-attach-file
    mml-attach-buffer)
  "Current Emacs 31 Message targets using direct after advice.")

(ert-deftest emacsvox-posting-message-advice-is-directly-registered ()
  "Message advice is attached directly to current Emacs 31 targets."
  (should
   (advice-member-p
    #'emacsvox--advice-message-send-around
    'message-send))
  (dolist (target emacsvox-test--posting-message-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))))
  (should
   (advice-member-p
    #'emacsvox--advice-message-beginning-of-line-before
    'message-beginning-of-line)))

(ert-deftest emacsvox-posting-message-send-announces-success ()
  "The low-level Message send path reports start and definite success."
  (let (events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'tts-speak)
               (lambda (text) (push (list 'speak text) events))))
      (should
       (eq
        (emacsvox--advice-message-send-around
         (lambda (&rest arguments)
           (push (list 'original arguments) events)
           'sent)
         'prefix)
        'sent)))
    (should
     (equal
      (nreverse events)
      '((icon progress)
        (speak "Sending message")
        (original (prefix))
        (icon task-done)
        (speak "Message sent"))))))

(ert-deftest emacsvox-posting-message-send-reports-incomplete-errors ()
  "A send error is announced with detail and re-signalled unchanged."
  (let (events caught)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'tts-speak)
               (lambda (text) (push (list 'speak text) events))))
      (condition-case error-data
          (emacsvox--advice-message-send-around
           (lambda (&rest _)
             (push 'original events)
             (error "SMTP unavailable")))
        (error (setq caught error-data))))
    (should (equal caught '(error "SMTP unavailable")))
    (should
     (equal
      (nreverse events)
      '((icon progress)
        (speak "Sending message")
        original
        (icon warn-user)
        (speak "Send failed or incomplete: SMTP unavailable"))))))

(ert-deftest emacsvox-posting-message-send-reports-interruption ()
  "Quitting a send warns that its delivery state may be uncertain."
  (let (events caught)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'tts-speak)
               (lambda (text) (push (list 'speak text) events))))
      (condition-case error-data
          (emacsvox--advice-message-send-around
           (lambda (&rest _)
             (push 'original events)
             (signal 'quit nil)))
        (quit (setq caught error-data))))
    (should (equal caught '(quit)))
    (should
     (equal
      (nreverse events)
      '((icon progress)
        (speak "Sending message")
        original
        (icon warn-user)
        (speak "Send interrupted; delivery status unknown"))))))

(ert-deftest emacsvox-posting-message-setup-announces-composition ()
  "A prepared compose buffer announces itself and its current line."
  (let (events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'tts-speak)
               (lambda (text) (push (list 'speak text) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events))))
      (emacsvox--advice-message-setup-1-after))
    (should
     (equal
      (nreverse events)
      '((icon open-object) (speak "Compose message") line)))))

(ert-deftest emacsvox-posting-message-compose-status-is-informative ()
  "The on-demand compose report includes fields, attachments, and location."
  (with-temp-buffer
    (setq major-mode 'message-mode)
    (insert
     "From: Bart <bart@example.com>\n"
     "To: Della <della@example.com>\n"
     "Cc: Alex <alex@example.com>\n"
     "Subject: Status test\n"
     "--text follows this line--\n"
     "Body\n"
     "<#part type=\"text/plain\" filename=\"notes.txt\" "
     "disposition=attachment>\n"
     "<#/part>\n")
    (goto-char (point-max))
    (let (spoken)
      (cl-letf (((symbol-function 'tts-speak)
                 (lambda (text) (setq spoken text))))
        (emacsvox-message-speak-compose-status))
      (should
       (equal
        spoken
        (concat
         "Compose message. From Bart <bart@example.com>. "
         "To Della <della@example.com>. Subject Status test. "
         "C C Alex <alex@example.com>. 1 attachment. "
         "Point is in the message body"))))))

(ert-deftest emacsvox-posting-message-compose-status-has-a-specific-key ()
  "Message mode exposes the on-demand compose report on a free key."
  (should
   (eq
    (lookup-key message-mode-map (kbd "C-c C-f C-p"))
    #'emacsvox-message-speak-compose-status)))

(ert-deftest emacsvox-posting-message-attachment-is-confirmed ()
  "Adding a file announces its basename and an auditory icon."
  (with-temp-buffer
    (setq major-mode 'message-mode)
    (let (events)
      (cl-letf (((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events)))
                ((symbol-function 'tts-speak)
                 (lambda (text) (push (list 'speak text) events))))
        (emacsvox--advice-mml-attach-file-after
         "/tmp/reports/status.txt"))
      (should
       (equal
        (nreverse events)
        '((icon save-object) (speak "Attached status.txt")))))))

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
    (cl-letf (((symbol-function 'tts-stop)
               (lambda (scope) (push (list 'stop scope) events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'tts-speak)
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
