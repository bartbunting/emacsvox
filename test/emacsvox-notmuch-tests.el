;;; emacsvox-notmuch-tests.el --- Notmuch advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'cl-lib)
(require 'ert)
(require 'package)
(package-initialize)
(require 'notmuch)
(load (expand-file-name "../lisp/emacsvox-notmuch.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-notmuch-advice-is-current-and-direct ()
  "Current Notmuch targets use native advice directly."
  (dolist (entry emacsvox-notmuch--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-notmuch-hello-navigation-speaks-search-name-and-count ()
  "Tabbing through saved searches should speak their names and counts."
  (with-temp-buffer
    (setq major-mode 'notmuch-hello-mode)
    (widget-insert "      42 ")
    (let* ((widget
            (widget-create
             'push-button
             :notmuch-search-terms "tag:inbox"
             "inbox"))
           (destination (copy-marker (widget-get widget :from)))
           (ems--interactive-fn-name 'widget-forward)
           events
           original-marker
           (original-calls 0))
      (widget-setup)
      (goto-char (point-min))
      (cl-letf (((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events)))
                ((symbol-function 'tts-speak)
                 (lambda (text) (push (list 'speak text) events))))
        (should
         (eq
          (emacsvox--advice-widget-forward-notmuch-around
           (lambda (&rest _)
             (setq original-marker ems--interactive-fn-name)
             (cl-incf original-calls)
             (goto-char destination)
             'moved))
          'moved)))
      (should (= original-calls 1))
      (should-not original-marker)
      (should
       (equal
        (nreverse events)
        '((icon item) (speak "inbox, 42 messages")))))))

(ert-deftest emacsvox-notmuch-show-visual-lines-cue-blank-content ()
  "Visual-line speech should retain Emacsvox's blank-line tones."
  (dolist (case '((notmuch-show-mode "" 130.8)
                  (notmuch-show-mode "  " 261.6)
                  (notmuch-show-mode "content" nil)
                  (fundamental-mode "" nil)))
    (with-temp-buffer
      (insert (nth 1 case))
      (goto-char (point-min))
      (setq major-mode (nth 0 case))
      (visual-line-mode 1)
      (let (events)
        (cl-letf (((symbol-function 'tts-stop)
                   (lambda (&optional all)
                     (push (list 'stop all) events)))
                  ((symbol-function 'tts-tone)
                   (lambda (pitch duration &optional force)
                     (push (list 'tone pitch duration force) events))))
          (emacsvox--advice-emacsvox-speak-visual-line-notmuch-around
           (lambda (&rest _)
             (push '(original) events))))
        (should
         (equal
          (nreverse events)
          (if (nth 2 case)
              `((stop all)
                (original)
                (tone ,(nth 2 case) 150 force))
            '((original)))))))))

(defconst emacsvox-notmuch-test--search-result
  '(:authors "Alice Smith|Bob Jones"
    :subject "Project update"
    :date_relative "yesterday"
    :matched 2
    :total 5
    :tags ("inbox" "unread" "flagged" "work")
    :orig-tags ("inbox" "unread" "flagged" "work"))
  "Representative Notmuch search result used by speech tests.")

(defconst emacsvox-notmuch-test--show-message
  '(:date_relative "today"
    :tags ("inbox" "unread" "flagged")
    :orig-tags ("inbox" "unread" "flagged")
    :headers
    (:From "Alice Smith <alice@example.com>"
     :Subject "Project update"
     :Date "Sat, 25 Jul 2026 10:30:00 +1000"
     :To "Bart Bunting <bart@example.com>"
     :Cc "Project Team <team@example.com>")
    :body
    ((:content-type "multipart/mixed"
      :content
      ((:content-type "text/plain" :content "Hello")
       (:content-type "application/pdf" :filename "report.pdf")
       (:content-type "message/rfc822"
        :content
        ((:headers (:From "Carol <carol@example.com>")
          :body
          ((:content-type "image/png" :filename "chart.png")))))))))
  "Representative Notmuch show message used by speech tests.")

(ert-deftest emacsvox-notmuch-formats-semantic-search-result ()
  "Search results use semantic fields, native faces, and silent statuses."
  (let* ((summary
          (emacsvox-notmuch-format-search-result
           emacsvox-notmuch-test--search-result))
         (plain (substring-no-properties summary)))
    (should
     (equal
      plain
      "Alice Smith, Bob Jones, Project update, yesterday, 2 of 5, inbox work"))
    (should-not (string-match-p "unread\\|flagged" plain))
    (should
     (eq (get-text-property 0 'face summary)
         'notmuch-search-matching-authors))
    (should
     (eq
      (get-text-property (string-match "Bob Jones" summary) 'face summary)
      'notmuch-search-non-matching-authors))
    (should
     (eq
      (get-text-property (string-match "Project update" summary) 'face summary)
      'notmuch-search-subject))
    (should
     (eq
      (get-text-property (string-match "yesterday" summary) 'face summary)
      'notmuch-search-date))
    (should
     (eq
      (get-text-property (string-match "2 of 5" summary) 'face summary)
      'notmuch-search-count))))

(ert-deftest emacsvox-notmuch-search-result-fields-are-configurable ()
  "Search-result fields can be reordered and omitted."
  (let ((emacsvox-notmuch-search-result-fields '(subject authors))
        (emacsvox-notmuch-search-field-separator " / "))
    (should
     (equal
      (substring-no-properties
       (emacsvox-notmuch-format-search-result
        emacsvox-notmuch-test--search-result))
      "Project update / Alice Smith, Bob Jones"))))

(ert-deftest emacsvox-notmuch-search-status-uses-icons-not-words ()
  "Configured status tags play icons and remain out of speech."
  (let (events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'tts-speak)
               (lambda (text)
                 (push
                  (list 'speak (substring-no-properties text))
                  events))))
      (emacsvox-notmuch-speak-search-result
       emacsvox-notmuch-test--search-result))
    (should
     (equal
      (nreverse events)
      '((icon new-mail)
        (icon mark-object)
        (speak
         "Alice Smith, Bob Jones, Project update, yesterday, 2 of 5, inbox work"))))))

(ert-deftest emacsvox-notmuch-formats-semantic-show-message ()
  "Show messages use configurable semantic fields and distinct faces."
  (let* ((summary
          (emacsvox-notmuch-format-show-message
           emacsvox-notmuch-test--show-message))
         (plain (substring-no-properties summary)))
    (should
     (equal
      plain
      (concat
       "Alice Smith <alice@example.com>, today, "
       "Bart Bunting <bart@example.com>, "
       "Project Team <team@example.com>, inbox, 2 attachments")))
    (should-not (string-match-p "unread\\|flagged" plain))
    (dolist
        (expectation
         '(("Alice Smith" . emacsvox-notmuch-message-from)
           ("today" . emacsvox-notmuch-message-date)
           ("Bart Bunting" . emacsvox-notmuch-message-to)
           ("Project Team" . emacsvox-notmuch-message-cc)
           ("2 attachments" . emacsvox-notmuch-message-attachments)))
      (should
       (eq
        (get-text-property
         (string-match (car expectation) summary)
         'face summary)
        (cdr expectation))))))

(ert-deftest emacsvox-notmuch-show-message-fields-are-configurable ()
  "Show-message fields can be reordered and include the subject."
  (let ((emacsvox-notmuch-show-message-fields '(subject from))
        (emacsvox-notmuch-show-field-separator " / "))
    (should
     (equal
      (substring-no-properties
       (emacsvox-notmuch-format-show-message
        emacsvox-notmuch-test--show-message))
      "Project update / Alice Smith <alice@example.com>"))))

(ert-deftest emacsvox-notmuch-show-fields-have-distinct-voices ()
  "Each semantic show-message face has an independent voice mapping."
  (dolist
      (mapping
       '((emacsvox-notmuch-message-from . voice-lighten)
         (emacsvox-notmuch-message-subject . voice-bolden)
         (emacsvox-notmuch-message-date . voice-monotone)
         (emacsvox-notmuch-message-to . voice-brighten)
         (emacsvox-notmuch-message-cc . voice-smoothen)
         (emacsvox-notmuch-message-attachments . voice-annotate)))
    (should
     (eq
      (voice-setup-get-voice-for-face (car mapping))
      (cdr mapping)))))

(ert-deftest emacsvox-notmuch-show-status-uses-icons-not-words ()
  "Message status uses auditory icons and stays out of spoken tags."
  (let (events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'tts-speak)
               (lambda (text)
                 (push
                  (list 'speak (substring-no-properties text))
                  events))))
      (emacsvox-notmuch-speak-show-message
       emacsvox-notmuch-test--show-message))
    (should
     (equal
      (mapcar #'car (nreverse events))
      '(icon icon speak)))))

(ert-deftest emacsvox-notmuch-show-position-speaks-ordinal-and-details ()
  "The manual position report combines thread position and message details."
  (with-temp-buffer
    (setq major-mode 'notmuch-show-mode)
    (let ((current-id "second")
          iterated-id
          events)
      (cl-letf (((symbol-function 'notmuch-show-get-message-id)
                 (lambda (&optional _bare) (or iterated-id current-id)))
                ((symbol-function 'notmuch-show-mapc)
                 (lambda (function)
                   (dolist (message-id '("first" "second" "third"))
                     (setq iterated-id message-id)
                     (funcall function))
                   (setq iterated-id nil)))
                ((symbol-function 'notmuch-show-get-message-properties)
                 (lambda () emacsvox-notmuch-test--show-message))
                ((symbol-function 'emacsvox-notmuch--play-status-icons)
                 (lambda (&rest _) (push '(status-icons) events)))
                ((symbol-function 'tts-speak)
                 (lambda (text)
                   (push
                    (list 'speak (substring-no-properties text))
                    events))))
        (should
         (equal
          (substring-no-properties
           (emacsvox-notmuch-speak-show-position))
          (concat
           "Message 2 of 3, Alice Smith <alice@example.com>, today, "
           "Bart Bunting <bart@example.com>, "
           "Project Team <team@example.com>, inbox, 2 attachments"))))
      (should
       (equal
        (nreverse events)
        '((status-icons)
          (speak
           "Message 2 of 3, Alice Smith <alice@example.com>, today, Bart Bunting <bart@example.com>, Project Team <team@example.com>, inbox, 2 attachments")))))))

(ert-deftest emacsvox-notmuch-show-position-has-manual-binding ()
  "The thread-position report has one explicit Notmuch Show binding."
  (should
   (eq
    (lookup-key notmuch-show-mode-map (kbd "C-c C-p"))
    #'emacsvox-notmuch-speak-show-position)))

(defconst emacsvox-notmuch-test--attachment
  '(:id 2
    :content-type "application/pdf"
    :computed-type "application/pdf"
    :content-length 59096
    :filename "report.pdf")
  "Representative Notmuch attachment used by part-feedback tests.")

(ert-deftest emacsvox-notmuch-formats-semantic-attachment ()
  "Attachment descriptions include name, MIME type, size, and voice."
  (let ((description
         (emacsvox-notmuch-format-part
          emacsvox-notmuch-test--attachment)))
    (should
     (equal
      (substring-no-properties description)
      "Attachment report.pdf, application/pdf, 58 KiB"))
    (should
     (eq
      (get-text-property 0 'face description)
      'emacsvox-notmuch-message-attachments))))

(ert-deftest emacsvox-notmuch-show-button-navigation-describes-attachment ()
  "TAB navigation gives attachment-specific semantic feedback."
  (with-temp-buffer
    (insert-text-button "[ report.pdf: application/pdf ]" 'action #'ignore)
    (put-text-property
     (point-min) (point-max)
     :notmuch-part emacsvox-notmuch-test--attachment)
    (goto-char (point-min))
    (let ((ems--interactive-fn-name 'notmuch-show-next-button)
          events)
      (cl-letf (((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events)))
                ((symbol-function 'tts-speak)
                 (lambda (text)
                   (push
                    (list 'speak (substring-no-properties text))
                    events))))
        (emacsvox--advice-notmuch-show-next-button-after))
      (should
       (equal
        (nreverse events)
        '((icon item)
          (speak
           "Attachment report.pdf, application/pdf, 58 KiB")))))))

(ert-deftest emacsvox-notmuch-show-save-part-confirms-filename ()
  "Saving one part confirms the attachment that was saved."
  (with-temp-buffer
    (insert "attachment")
    (put-text-property
     (point-min) (point-max)
     :notmuch-part emacsvox-notmuch-test--attachment)
    (goto-char (point-min))
    (let ((ems--interactive-fn-name 'notmuch-show-save-part)
          (calls 0)
          events)
      (cl-letf (((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events)))
                ((symbol-function 'tts-speak)
                 (lambda (text) (push (list 'speak text) events))))
        (should
         (eq
          (emacsvox--advice-notmuch-show-save-part-around
           (lambda ()
             (cl-incf calls)
             'saved))
          'saved)))
      (should (= calls 1))
      (should
       (equal
        (nreverse events)
        '((icon save-object)
          (speak "Saved attachment report.pdf")))))))

(ert-deftest emacsvox-notmuch-show-view-part-confirms-filename ()
  "Viewing one part confirms the attachment that was opened."
  (with-temp-buffer
    (insert "attachment")
    (put-text-property
     (point-min) (point-max)
     :notmuch-part emacsvox-notmuch-test--attachment)
    (goto-char (point-min))
    (let ((ems--interactive-fn-name 'notmuch-show-view-part)
          events)
      (cl-letf (((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events)))
                ((symbol-function 'tts-speak)
                 (lambda (text) (push (list 'speak text) events))))
        (emacsvox--advice-notmuch-show-view-part-around
         (lambda () 'opened)))
      (should
       (equal
        (nreverse events)
        '((icon open-object)
          (speak "Opened attachment report.pdf")))))))

(ert-deftest emacsvox-notmuch-part-button-default-reports-once ()
  "A part button's default save action owns its nested confirmation."
  (with-temp-buffer
    (let ((button
           (insert-text-button
            "[ report.pdf: application/pdf ]"
            'action #'ignore)))
      (put-text-property
       (point-min) (point-max)
       :notmuch-part emacsvox-notmuch-test--attachment)
      (goto-char (point-min))
      (let ((ems--interactive-fn-name
             'notmuch-show-part-button-default)
            (notmuch-show-part-button-default-action
             'notmuch-show-save-part)
            events)
        (cl-letf (((symbol-function 'emacsvox-icon)
                   (lambda (icon) (push (list 'icon icon) events)))
                  ((symbol-function 'tts-speak)
                   (lambda (text) (push (list 'speak text) events))))
          (emacsvox--advice-notmuch-show-part-button-default-around
           (lambda (&optional _button)
             (emacsvox--advice-notmuch-show-save-part-around
              (lambda () 'saved)))
           button))
        (should
         (equal
          (nreverse events)
          '((icon save-object)
            (speak "Saved attachment report.pdf"))))))))

(ert-deftest emacsvox-notmuch-part-button-announces-visibility ()
  "Toggling an inline attachment reports its resulting visibility."
  (with-temp-buffer
    (let ((button
           (insert-text-button
            "[ report.pdf: application/pdf ]"
            'action #'ignore)))
      (put-text-property
       (point-min) (point-max)
       :notmuch-part emacsvox-notmuch-test--attachment)
      (goto-char (point-min))
      (let ((ems--interactive-fn-name
             'notmuch-show-part-button-default)
            events)
        (cl-letf (((symbol-function 'emacsvox-icon)
                   (lambda (icon) (push (list 'icon icon) events)))
                  ((symbol-function 'tts-speak)
                   (lambda (text) (push (list 'speak text) events))))
          (emacsvox--advice-notmuch-show-part-button-default-around
           (lambda (&optional part-button)
             (button-put part-button :notmuch-part-hidden t)
             'hidden)
           button))
        (should
         (equal
          (nreverse events)
          '((icon close-object)
            (speak "attachment report.pdf hidden"))))))))

(ert-deftest emacsvox-notmuch-show-save-attachments-confirms-completion ()
  "Saving all message attachments gives one completion confirmation."
  (let ((ems--interactive-fn-name 'notmuch-show-save-attachments)
        events)
    (cl-letf (((symbol-function 'notmuch-show-get-message-properties)
               (lambda () emacsvox-notmuch-test--show-message))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'tts-speak)
               (lambda (text) (push (list 'speak text) events))))
      (emacsvox--advice-notmuch-show-save-attachments-around
       (lambda () 'saved)))
    (should
     (equal
      (nreverse events)
      '((icon save-object)
        (speak "Finished saving attachments"))))))

(ert-deftest emacsvox-notmuch-opening-thread-speaks-semantic-message ()
  "Opening a search result selects the line before the message body."
  (with-temp-buffer
    (setq major-mode 'notmuch-show-mode)
    (insert "Summary\nSubject: Project update\nFrom: Alice\n")
    (goto-char (point-min))
    (forward-line 1)
    (let ((headers-start (point)))
      (forward-line 2)
      (let ((headers-overlay (make-overlay headers-start (point))))
        (insert "\n")
        (let ((multipart-button
               (notmuch-show-insert-part-header
                1 "multipart/alternative" "multipart/alternative")))
          (put-text-property
           (button-start multipart-button) (button-end multipart-button)
           :notmuch-part '(:content-type "multipart/alternative")))
        (let ((html-button
               (notmuch-show-insert-part-header
                2 "text/html" "text/html")))
          (put-text-property
           (button-start html-button) (button-end html-button)
           :notmuch-part '(:content-type "text/html"))
          (let ((hidden-start (point)))
            (insert "<p>Hidden HTML alternative</p>\n")
            (overlay-put
             (make-overlay hidden-start (point))
             'invisible t)))
        (let ((plain-button
               (notmuch-show-insert-part-header
                3 "text/plain" "text/plain")))
          (put-text-property
           (button-start plain-button) (button-end plain-button)
           :notmuch-part '(:content-type "text/plain")))
        (insert "  Message body\n")
        (let ((message (list :headers-overlay headers-overlay))
              (extent (cons (point-min) (point-max)))
              (ems--interactive-fn-name 'notmuch-search-show-thread)
              events)
          (goto-char (point-min))
          (cl-letf (((symbol-function 'notmuch-show-get-message-properties)
                     (lambda () message))
                    ((symbol-function 'notmuch-show-message-extent)
                     (lambda () extent))
                    ((symbol-function 'emacsvox-icon)
                     (lambda (icon) (push (list 'icon icon) events)))
                    ((symbol-function 'emacsvox-notmuch-speak-show-message)
                     (lambda (&optional _message) (push '(message) events))))
            (emacsvox--advice-notmuch-search-show-thread-after))
          (should
           (save-excursion
             (forward-line 1)
             (skip-chars-forward " \t")
             (looking-at-p "Message body")))
          (should
           (equal
            (nreverse events)
            '((icon open-object)
              (message)))))))))

(ert-deftest emacsvox-notmuch-body-position-keeps-attachment-fallback ()
  "An attachment-only message selects its actionable leaf-part button."
  (with-temp-buffer
    (setq major-mode 'notmuch-show-mode)
    (insert "Summary\nFrom: Alice\n")
    (goto-char (point-min))
    (forward-line 1)
    (let ((headers-overlay (make-overlay (point) (line-end-position 2))))
      (goto-char (overlay-end headers-overlay))
      (insert "\n")
      (let ((attachment-button
             (notmuch-show-insert-part-header
              2 "application/pdf" "application/pdf" "report.pdf")))
        (put-text-property
         (button-start attachment-button) (button-end attachment-button)
         :notmuch-part
         '(:content-type "application/pdf" :filename "report.pdf"))
        (let ((message (list :headers-overlay headers-overlay))
              (extent (cons (point-min) (point-max))))
          (goto-char (point-min))
          (cl-letf (((symbol-function 'notmuch-show-get-message-properties)
                     (lambda () message))
                    ((symbol-function 'notmuch-show-message-extent)
                     (lambda () extent)))
            (emacsvox-notmuch--move-to-message-body))
          (should (= (point) (button-start attachment-button))))))))

(ert-deftest emacsvox-notmuch-navigation-speaks-selected-result ()
  "Only the active interactive search-navigation command speaks."
  (let ((ems--interactive-fn-name 'notmuch-search-next-thread)
        events)
    (cl-letf (((symbol-function 'emacsvox-notmuch-speak-search-result)
               (lambda (&optional _result) (push 'result events))))
      (emacsvox--advice-notmuch-search-next-thread-after)
      (emacsvox--advice-notmuch-search-previous-thread-after))
    (should (equal events '(result)))))

(ert-deftest emacsvox-notmuch-show-navigation-selects-and-speaks-message-body ()
  "Active show navigation selects the message body before speaking."
  (with-temp-buffer
    (setq major-mode 'notmuch-show-mode)
    (let ((ems--interactive-fn-name 'notmuch-show-next-open-message)
          (message-ids '("first" "second"))
          (calls 0)
          events)
      (cl-letf
          (((symbol-function 'emacsvox-notmuch--current-show-message-id)
            (lambda () (pop message-ids)))
           ((symbol-function 'emacsvox-notmuch--move-to-message-body)
            (lambda () (push 'body events)))
           ((symbol-function 'emacsvox-notmuch-speak-show-message)
            (lambda (&optional _message) (push 'message events))))
        (emacsvox--advice-notmuch-show-next-open-message-around
         (lambda ()
           (cl-incf calls)
           'moved))
        (emacsvox--advice-notmuch-show-previous-open-message-around
         (lambda ()
           (cl-incf calls)
           'unchanged)))
      (should (= calls 2))
      (should (equal (nreverse events) '(body message))))))

(ert-deftest emacsvox-notmuch-show-next-navigation-announces-thread-end ()
  "Forward navigation should not reread the final message."
  (dolist
      (case
       '((notmuch-show-next-open-message
          emacsvox--advice-notmuch-show-next-open-message-around)
         (notmuch-show-next-message
          emacsvox--advice-notmuch-show-next-message-around)
         (notmuch-show-next-matching-message
          emacsvox--advice-notmuch-show-next-matching-message-around)))
    (with-temp-buffer
      (setq major-mode 'notmuch-show-mode)
      (let ((ems--interactive-fn-name (car case))
            (calls 0)
            events)
        (cl-letf
            (((symbol-function 'emacsvox-notmuch--current-show-message-id)
              (lambda () "last"))
             ((symbol-function 'emacsvox-notmuch--move-to-message-body)
              (lambda () (push '(body) events)))
             ((symbol-function 'emacsvox-notmuch-speak-show-message)
              (lambda (&optional _message) (push '(message) events)))
             ((symbol-function 'emacsvox-icon)
              (lambda (icon) (push (list 'icon icon) events)))
             ((symbol-function 'tts-speak)
              (lambda (text) (push (list 'speak text) events))))
          (should
           (eq
            (funcall
             (cadr case)
             (lambda ()
               (cl-incf calls)
               'at-end))
            'at-end)))
        (should (= calls 1))
        (should
         (equal
          (nreverse events)
          '((body)
            (icon select-object)
            (speak "End of thread"))))))))

(ert-deftest emacsvox-notmuch-show-previous-navigation-announces-thread-start ()
  "Backward navigation should not reread the first message."
  (dolist
      (case
       '((notmuch-show-previous-open-message
          emacsvox--advice-notmuch-show-previous-open-message-around)
         (notmuch-show-previous-message
          emacsvox--advice-notmuch-show-previous-message-around)))
    (with-temp-buffer
      (setq major-mode 'notmuch-show-mode)
      (let ((ems--interactive-fn-name (car case))
            (calls 0)
            events)
        (cl-letf
            (((symbol-function 'emacsvox-notmuch--current-show-message-id)
              (lambda () "first"))
             ((symbol-function 'notmuch-show-move-to-message-top)
              (lambda () (push '(top) events)))
             ((symbol-function 'emacsvox-notmuch--move-to-message-body)
              (lambda () (push '(body) events)))
             ((symbol-function 'emacsvox-notmuch-speak-show-message)
              (lambda (&optional _message) (push '(message) events)))
             ((symbol-function 'emacsvox-icon)
              (lambda (icon) (push (list 'icon icon) events)))
             ((symbol-function 'tts-speak)
              (lambda (text) (push (list 'speak text) events))))
          (should
           (eq
            (funcall
             (cadr case)
             (lambda ()
               (cl-incf calls)
               'at-start))
            'at-start)))
        (should (= calls 1))
        (should
         (equal
          (nreverse events)
          '((top)
            (body)
            (icon select-object)
            (speak "Beginning of thread"))))))))

(ert-deftest emacsvox-notmuch-show-navigation-can-return-from-message-bodies ()
  "Previous navigation should cross messages after body positioning."
  (dolist
      (commands
       '((notmuch-show-next-open-message
          notmuch-show-previous-open-message)
         (notmuch-show-next-message
          notmuch-show-previous-message)))
    (let ((buffer (generate-new-buffer " *emacsvox-notmuch-navigation*")))
      (unwind-protect
          (save-window-excursion
            (switch-to-buffer buffer)
            (setq major-mode 'notmuch-show-mode)
            (cl-labels
                ((insert-message
                  (id)
                  (let ((start (point-marker)))
                    (insert (format "Message %s\n" id))
                    (let ((headers-start (point-marker)))
                      (insert "From: Test Sender\n")
                      (let ((headers-end (point-marker)))
                        (insert "\n")
                        (let ((body-start (point-marker)))
                          (insert (format "Body %s\n" id))
                          (let* ((end (point-marker))
                                 (headers-overlay
                                  (make-overlay headers-start headers-end))
                                 (message-overlay
                                  (make-overlay headers-start end))
                                 (properties
                                  (list
                                   :id id
                                   :headers '(:From "Test Sender")
                                   :headers-overlay headers-overlay
                                   :message-overlay message-overlay
                                   :message-visible t)))
                            (put-text-property
                             start end :notmuch-message-extent
                             (cons start end))
                            (put-text-property
                             start (1+ start)
                             :notmuch-message-properties properties)
                            body-start)))))))
              (insert-message "first")
              (insert-message "second"))
            (goto-char (point-min))
            (cl-letf
                (((symbol-function 'emacsvox-notmuch-speak-show-message)
                  #'ignore))
              (funcall-interactively (car commands))
              (should
               (save-excursion
                 (forward-line 1)
                 (looking-at-p "Body second")))
              (should
               (equal
                (plist-get
                 (notmuch-show-get-message-properties) :id)
                "second"))
              (funcall-interactively (cadr commands))
              (should
               (save-excursion
                 (forward-line 1)
                 (looking-at-p "Body first")))
              (should
               (equal
                (plist-get
                 (notmuch-show-get-message-properties) :id)
                "first"))))
        (when (buffer-live-p buffer)
          (kill-buffer buffer))))))

(ert-deftest emacsvox-notmuch-show-speaker-is-quiet-outside-show-mode ()
  "Show navigation that moves to another view does not read stale data."
  (with-temp-buffer
    (let (called)
      (cl-letf (((symbol-function 'notmuch-show-get-message-properties)
                 (lambda () (setq called t))))
        (should-not (emacsvox-notmuch-speak-show-message)))
      (should-not called))))

(ert-deftest emacsvox-notmuch-show-advance-speaks-message-transition ()
  "Space speaks a semantic summary when it advances to another message."
  (with-temp-buffer
    (setq major-mode 'notmuch-show-mode)
    (let ((ems--interactive-fn-name 'notmuch-show-advance)
          (message-ids '("first" "second"))
          (calls 0)
          events)
      (cl-letf
          (((symbol-function 'emacsvox-notmuch--current-show-message-id)
            (lambda () (pop message-ids)))
           ((symbol-function 'emacsvox-notmuch-speak-show-message)
            (lambda (&optional _message) (push 'message events))))
        (should
         (eq
          (emacsvox--advice-notmuch-show-advance-around
           (lambda ()
             (cl-incf calls)
             'advanced))
          'advanced)))
      (should (= calls 1))
      (should (equal events '(message))))))

(ert-deftest emacsvox-notmuch-show-advance-speaks-window-after-scroll ()
  "Space speaks the visible window when it scrolls within one message."
  (with-temp-buffer
    (setq major-mode 'notmuch-show-mode)
    (let ((ems--interactive-fn-name 'notmuch-show-advance)
          (calls 0)
          events)
      (insert "message body")
      (goto-char (point-min))
      (cl-letf
          (((symbol-function 'emacsvox-notmuch--current-show-message-id)
            (lambda () "same"))
           ((symbol-function 'emacsvox-icon)
            (lambda (icon) (push (list 'icon icon) events)))
           ((symbol-function 'emacsvox-speak-current-window)
            (lambda () (push '(window) events))))
        (should
         (eq
          (emacsvox--advice-notmuch-show-advance-around
           (lambda ()
             (cl-incf calls)
             'scrolled))
          'scrolled)))
      (should (= calls 1))
      (should
       (equal
        (nreverse events)
        '((icon scroll)
          (window)))))))

(ert-deftest emacsvox-notmuch-show-rewind-is-target-aware ()
  "Programmatic rewind remains quiet and preserves its return value."
  (with-temp-buffer
    (setq major-mode 'notmuch-show-mode)
    (let ((calls 0)
          events)
      (cl-letf
          (((symbol-function 'emacsvox-notmuch--current-show-message-id)
            (lambda () "same"))
           ((symbol-function 'emacsvox-icon)
            (lambda (icon) (push icon events))))
        (should
         (eq
          (emacsvox--advice-notmuch-show-rewind-around
           (lambda ()
             (cl-incf calls)
             'rewound))
          'rewound)))
      (should (= calls 1))
      (should-not events))))

(ert-deftest emacsvox-notmuch-space-uses-state-aware-reading ()
  "The command actually bound to Space uses state-aware page feedback."
  (with-temp-buffer
    (setq major-mode 'notmuch-show-mode)
    (insert "message body")
    (goto-char (point-min))
    (let ((ems--interactive-fn-name 'notmuch-show-advance-and-archive)
          (calls 0)
          events)
      (cl-letf
          (((symbol-function 'emacsvox-notmuch--current-show-message-id)
            (lambda () "same"))
           ((symbol-function 'emacsvox-icon)
            (lambda (icon) (push (list 'icon icon) events)))
           ((symbol-function 'emacsvox-speak-current-window)
            (lambda () (push '(window) events))))
        (should
         (eq
          (emacsvox--advice-notmuch-show-advance-and-archive-around
           (lambda ()
             (cl-incf calls)
             'scrolled))
          'scrolled)))
      (should (= calls 1))
      (should
       (equal
        (nreverse events)
        '((icon scroll)
          (window)))))))

(ert-deftest emacsvox-notmuch-space-confirms-end-of-thread-archive ()
  "Space confirms archiving when invoked at the end of a thread."
  (with-temp-buffer
    (setq major-mode 'notmuch-show-mode)
    (let ((ems--interactive-fn-name 'notmuch-show-advance-and-archive)
          (notmuch-archive-tags '("-inbox"))
          (calls 0)
          feedback)
      (cl-letf
          (((symbol-function 'emacsvox-notmuch--show-archive-feedback)
            (lambda (object unarchive destination)
              (setq feedback
                    (list object unarchive destination)))))
        (should
         (eq
          (emacsvox--advice-notmuch-show-advance-and-archive-around
           (lambda ()
             (cl-incf calls)
             'archived))
          'archived)))
      (should (= calls 1))
      (should (equal feedback '(thread nil t))))))

(ert-deftest emacsvox-notmuch-show-opening-message-cues-and-speaks ()
  "Opening a message body plays an opening cue and identifies it."
  (let ((ems--interactive-fn-name 'notmuch-show-toggle-message)
        events)
    (cl-letf
        (((symbol-function 'notmuch-show-get-message-properties)
          (lambda () '(:message-visible t)))
         ((symbol-function 'emacsvox-icon)
          (lambda (icon) (push (list 'icon icon) events)))
         ((symbol-function 'emacsvox-notmuch-speak-show-message)
          (lambda (&optional _message) (push '(message) events))))
      (emacsvox--advice-notmuch-show-toggle-message-after))
    (should
     (equal
      (nreverse events)
      '((icon open-object)
        (message))))))

(ert-deftest emacsvox-notmuch-show-closing-message-uses-icon-only ()
  "Closing a message body uses a concise nonverbal cue."
  (let ((ems--interactive-fn-name 'notmuch-show-toggle-message)
        events)
    (cl-letf
        (((symbol-function 'notmuch-show-get-message-properties)
          (lambda () '(:message-visible nil)))
         ((symbol-function 'emacsvox-icon)
          (lambda (icon) (push (list 'icon icon) events)))
         ((symbol-function 'emacsvox-notmuch-speak-show-message)
          (lambda (&optional _message) (push '(message) events))))
      (emacsvox--advice-notmuch-show-toggle-message-after))
    (should
     (equal
      events
      '((icon close-object))))))

(ert-deftest emacsvox-notmuch-show-open-all-feedback-is-target-aware ()
  "Opening all message bodies produces one visibility announcement."
  (let ((ems--interactive-fn-name 'notmuch-show-open-or-close-all)
        events)
    (cl-letf
        (((symbol-function 'notmuch-show-get-message-properties)
          (lambda () '(:message-visible t)))
         ((symbol-function 'emacsvox-icon)
          (lambda (icon) (push icon events)))
         ((symbol-function 'emacsvox-notmuch-speak-show-message)
          (lambda (&optional _message) (push 'message events))))
      (emacsvox--advice-notmuch-show-toggle-message-after)
      (emacsvox--advice-notmuch-show-open-or-close-all-after))
    (should (equal (nreverse events) '(open-object message)))))

(ert-deftest emacsvox-notmuch-describes-tag-changes ()
  "Tag-change summaries distinguish additions and removals."
  (should
   (equal
    (emacsvox-notmuch--tag-change-summary
     '("+work" "+urgent" "-inbox"))
    "Added work, urgent; Removed inbox")))

(ert-deftest emacsvox-notmuch-tag-feedback-runs-once ()
  "An interactive tag wrapper confirms once and speaks the updated row."
  (let ((ems--interactive-fn-name 'notmuch-search-add-tag)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'tts-speak)
               (lambda (text) (push (list 'speak text) events)))
              ((symbol-function 'emacsvox-notmuch-speak-search-result)
               (lambda (&optional _result) (push '(result) events))))
      ;; `notmuch-search-add-tag' delegates to this command internally.
      (emacsvox--advice-notmuch-search-tag-after
       '("+work" "-inbox"))
      (emacsvox--advice-notmuch-search-add-tag-after
       '("+work" "-inbox")))
    (should
     (equal
      (nreverse events)
      '((icon task-done)
        (speak "Added work; Removed inbox")
        (result))))))

(ert-deftest emacsvox-notmuch-show-tag-feedback-runs-once ()
  "An interactive Show tag wrapper confirms once and speaks the message."
  (let ((ems--interactive-fn-name 'notmuch-show-add-tag)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'tts-speak)
               (lambda (text) (push (list 'speak text) events)))
              ((symbol-function 'emacsvox-notmuch-speak-show-message)
               (lambda (&optional _message) (push '(message) events))))
      (emacsvox--advice-notmuch-show-tag-after '("+work"))
      (emacsvox--advice-notmuch-show-add-tag-after '("+work")))
    (should
     (equal
      (nreverse events)
      '((icon task-done)
        (speak "Added work")
        (message))))))

(ert-deftest emacsvox-notmuch-status-tag-changes-remain-nonverbal ()
  "Status changes use cues without speaking status names."
  (let (events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'tts-speak)
               (lambda (text) (push (list 'speak text) events))))
      (emacsvox-notmuch--tag-operation-feedback
       '("+flagged" "-unread")
       emacsvox-notmuch-show-status-icons
       (lambda () (push '(message) events))))
    (should
     (equal
      (nreverse events)
      '((icon deselect-object)
        (message))))))

(ert-deftest emacsvox-notmuch-tag-menu-reports-structured-difference ()
  "The common tag menu reports changes made by its nested tag command."
  (with-temp-buffer
    (setq major-mode 'notmuch-show-mode)
    (let ((ems--interactive-fn-name 'notmuch-tag-jump)
          (tag-states
           '(("inbox" "unread")
             ("flagged" "unread")))
          (calls 0)
          feedback)
      (cl-letf
          (((symbol-function 'emacsvox-notmuch--current-tags)
            (lambda () (pop tag-states)))
           ((symbol-function 'emacsvox-notmuch--show-tag-feedback)
            (lambda (changes) (setq feedback changes))))
        (should
         (eq
          (emacsvox--advice-notmuch-tag-jump-around
           (lambda (&rest _)
             (cl-incf calls)
             'tagged))
          'tagged)))
      (should (= calls 1))
      (should (equal feedback '("+flagged" "-inbox"))))))

(ert-deftest emacsvox-notmuch-automatic-mark-read-remains-silent ()
  "Programmatic mark-seen activity does not produce action feedback."
  (with-temp-buffer
    (setq major-mode 'notmuch-show-mode)
    (let ((tag-states
           '(("inbox" "unread")
             ("inbox")))
          (calls 0)
          events)
      (cl-letf
          (((symbol-function 'emacsvox-notmuch--current-tags)
            (lambda () (pop tag-states)))
           ((symbol-function 'emacsvox-notmuch--show-tag-feedback)
            (lambda (changes) (push changes events))))
        (should
         (eq
          (emacsvox--advice-notmuch-show-mark-read-around
           (lambda ()
             (cl-incf calls)
             'read))
          'read)))
      (should (= calls 1))
      (should-not events))))

(ert-deftest emacsvox-notmuch-manual-mark-read-reports-status-change ()
  "An explicit read-state command reports its structured status change."
  (with-temp-buffer
    (setq major-mode 'notmuch-show-mode)
    (let ((ems--interactive-fn-name 'notmuch-show-mark-read)
          (tag-states
           '(("inbox" "unread")
             ("inbox")))
          feedback)
      (cl-letf
          (((symbol-function 'emacsvox-notmuch--current-tags)
            (lambda () (pop tag-states)))
           ((symbol-function 'emacsvox-notmuch--show-tag-feedback)
            (lambda (changes) (setq feedback changes))))
        (emacsvox--advice-notmuch-show-mark-read-around
         (lambda () 'read)))
      (should (equal feedback '("-unread"))))))

(ert-deftest emacsvox-notmuch-show-archive-message-confirms-and-speaks ()
  "A direct message archive confirms completion and identifies the result."
  (let ((ems--interactive-fn-name 'notmuch-show-archive-message)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'tts-speak)
               (lambda (text) (push (list 'speak text) events)))
              ((symbol-function 'emacsvox-notmuch--speak-current-item)
               (lambda () (push '(destination) events))))
      (emacsvox--advice-notmuch-show-archive-message-after))
    (should
     (equal
      (nreverse events)
      '((icon close-object)
        (speak "Archived message")
        (destination))))))

(ert-deftest emacsvox-notmuch-show-unarchive-thread-uses-opening-cue ()
  "Reversing a thread archive uses an opening cue and clear confirmation."
  (let ((ems--interactive-fn-name 'notmuch-show-archive-thread)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'tts-speak)
               (lambda (text) (push (list 'speak text) events)))
              ((symbol-function 'emacsvox-notmuch--speak-current-item)
               #'ignore))
      (emacsvox--advice-notmuch-show-archive-thread-after t))
    (should
     (equal
      (nreverse events)
      '((icon open-object)
        (speak "Unarchived thread"))))))

(ert-deftest emacsvox-notmuch-show-archive-wrapper-reports-once ()
  "An archive-and-move wrapper owns feedback from its nested operations."
  (let
      ((ems--interactive-fn-name
        'notmuch-show-archive-message-then-next-or-exit)
       events)
    (cl-letf
        (((symbol-function 'emacsvox-notmuch--show-archive-feedback)
          (lambda (object unarchive destination)
            (push (list object unarchive destination) events))))
      (emacsvox--advice-notmuch-show-archive-message-after)
      (emacsvox--advice-notmuch-show-archive-message-then-next-or-exit-after))
    (should (equal events '((message nil t))))))

(ert-deftest emacsvox-notmuch-archive-confirms-then-speaks-next-result ()
  "Archive feedback acknowledges completion before speaking the new row."
  (let ((ems--interactive-fn-name 'notmuch-search-archive-thread)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'tts-speak)
               (lambda (text) (push (list 'speak text) events)))
              ((symbol-function 'emacsvox-notmuch-speak-search-result)
               (lambda (&optional _result) (push '(result) events))))
      (emacsvox--advice-notmuch-search-archive-thread-after))
    (should
     (equal
      (nreverse events)
      '((icon close-object)
        (speak "Archived")
        (result))))))

(ert-deftest emacsvox-notmuch-refresh-marks-its-search-process ()
  "Interactive single-buffer refresh requests completion feedback."
  (let ((ems--interactive-fn-name 'notmuch-search-refresh-view)
        (this-command 'notmuch-search-refresh-view)
        events)
    (cl-letf (((symbol-function 'get-buffer-process)
               (lambda (_buffer) 'process))
              ((symbol-function 'process-put)
               (lambda (process property value)
                 (push (list process property value) events)))
              ((symbol-function 'process-live-p) (lambda (_process) t)))
      (emacsvox--advice-notmuch-search-refresh-view-after))
    (should
     (equal
      events
      `((process ,emacsvox-notmuch--refresh-process-property t))))))

(ert-deftest emacsvox-notmuch-refresh-all-remains-silent ()
  "The command for silently refreshing every buffer requests no feedback."
  (let ((ems--interactive-fn-name 'notmuch-search-refresh-view)
        (this-command 'notmuch-refresh-all-buffers)
        marked)
    (cl-letf (((symbol-function 'emacsvox-notmuch--mark-refresh-process)
               (lambda () (setq marked t))))
      (emacsvox--advice-notmuch-search-refresh-view-after))
    (should-not marked)))

(ert-deftest emacsvox-notmuch-refresh-announces-after-process-exit ()
  "A marked successful process reports its final structured-result count."
  (let ((buffer (generate-new-buffer " *emacsvox-notmuch-refresh-test*"))
        events)
    (unwind-protect
        (progn
          (with-current-buffer buffer
            (insert "First result\nSecond result\nEnd of search results.\n")
            (goto-char (point-min))
            (put-text-property
             (point-min) (line-beginning-position 2)
             'notmuch-search-result '(:thread "one"))
            (put-text-property
             (line-beginning-position 2) (line-beginning-position 3)
             'notmuch-search-result '(:thread "two")))
          (cl-letf
              (((symbol-function 'process-get)
                (lambda (_process property)
                  (and
                   (eq property emacsvox-notmuch--refresh-process-property)
                   t)))
               ((symbol-function 'process-put)
                (lambda (_process property value)
                  (push (list 'property property value) events)))
               ((symbol-function 'process-status)
                (lambda (_process) 'exit))
               ((symbol-function 'process-exit-status)
                (lambda (_process) 0))
               ((symbol-function 'process-buffer)
                (lambda (_process) buffer))
               ((symbol-function 'emacsvox-icon)
                (lambda (icon) (push (list 'icon icon) events)))
               ((symbol-function 'tts-speak)
                (lambda (text) (push (list 'speak text) events))))
            (emacsvox--advice-notmuch-search-process-sentinel-after
             'process nil)))
      (kill-buffer buffer))
    (should
     (equal
      (nreverse events)
      `((property ,emacsvox-notmuch--refresh-process-property nil)
        (icon task-done)
        (speak "Search refreshed, 2 threads"))))))

(provide 'emacsvox-notmuch-tests)
;;; emacsvox-notmuch-tests.el ends here
