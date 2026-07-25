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

(ert-deftest emacsvox-notmuch-opening-thread-speaks-semantic-message ()
  "Opening a search result speaks the first structured message."
  (let ((ems--interactive-fn-name 'notmuch-search-show-thread)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-notmuch-speak-show-message)
               (lambda (&optional _message) (push '(message) events))))
      (emacsvox--advice-notmuch-search-show-thread-after))
    (should
     (equal
      (nreverse events)
      '((icon open-object)
        (message))))))

(ert-deftest emacsvox-notmuch-navigation-speaks-selected-result ()
  "Only the active interactive search-navigation command speaks."
  (let ((ems--interactive-fn-name 'notmuch-search-next-thread)
        events)
    (cl-letf (((symbol-function 'emacsvox-notmuch-speak-search-result)
               (lambda (&optional _result) (push 'result events))))
      (emacsvox--advice-notmuch-search-next-thread-after)
      (emacsvox--advice-notmuch-search-previous-thread-after))
    (should (equal events '(result)))))

(ert-deftest emacsvox-notmuch-show-navigation-speaks-selected-message ()
  "Only the active interactive show-navigation command speaks."
  (let ((ems--interactive-fn-name 'notmuch-show-next-open-message)
        events)
    (cl-letf (((symbol-function 'emacsvox-notmuch-speak-show-message)
               (lambda (&optional _message) (push 'message events))))
      (emacsvox--advice-notmuch-show-next-open-message-after)
      (emacsvox--advice-notmuch-show-previous-open-message-after))
    (should (equal events '(message)))))

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
