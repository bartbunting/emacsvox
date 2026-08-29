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

(defun emacsvox-test--notmuch-submission-recorder (record)
  "Return a native submission stub that passes logical events to RECORD."
  (lambda (content &rest arguments)
    (dolist (action (plist-get arguments :compatibility-actions))
      (funcall
       record
       (list
        'icon
        (emacsvox-aural-compatibility-action-value action))))
    (funcall record (list 'speak (substring-no-properties content)))
    'submission))

(cl-defmacro emacsvox-notmuch-test--with-fake-search-process
    ((process buffer properties status exit-status) &rest body)
  "Run BODY with PROCESS backed by mutable PROPERTIES for BUFFER.
STATUS and EXIT-STATUS supply its terminal state."
  (declare (indent 1) (debug t))
  `(cl-letf
       (((symbol-function 'get-buffer-process)
         (lambda (&optional target)
           (when (or (null target) (eq target ,buffer)) ,process)))
        ((symbol-function 'process-get)
         (lambda (_process property)
           (alist-get property ,properties)))
        ((symbol-function 'process-put)
         (lambda (_process property value)
           (setf (alist-get property ,properties) value)))
        ((symbol-function 'process-buffer)
         (lambda (_process) ,buffer))
        ((symbol-function 'process-status)
         (lambda (_process) ,status))
        ((symbol-function 'process-exit-status)
         (lambda (_process) ,exit-status)))
     ,@body))

(defun emacsvox-notmuch-test--insert-search-result (label result)
  "Insert a search row named LABEL carrying structured RESULT.
Return the beginning of the inserted row."
  (let ((start (point)))
    (insert label "\n")
    (put-text-property start (point) 'notmuch-search-result result)
    start))

(defun emacsvox-notmuch-test--insert-rendered-search-result (result)
  "Render synthetic Notmuch search RESULT and return its beginning."
  (let ((start (point-max)))
    (notmuch-search-show-result result start)
    start))

(defun emacsvox-notmuch-test--insert-show-message (label message)
  "Insert a synthetic Show MESSAGE row named LABEL and return its start."
  (let ((start (point)))
    (insert label "\n")
    (put-text-property
     start (1+ start) :notmuch-message-properties message)
    start))

(cl-defmacro emacsvox-notmuch-test--with-synthetic-show-tags (&rest body)
  "Run BODY with Show tag accessors backed by message properties per line."
  (declare (indent 0) (debug t))
  `(cl-letf
       (((symbol-function 'notmuch-show-move-to-message-top)
         (lambda () (beginning-of-line)))
        ((symbol-function 'notmuch-show-get-message-properties)
         (lambda ()
           (get-text-property
            (line-beginning-position) :notmuch-message-properties)))
        ((symbol-function 'notmuch-show-get-tags)
         (lambda ()
           (plist-get
            (get-text-property
             (line-beginning-position) :notmuch-message-properties)
            :tags)))
        ((symbol-function 'notmuch-show-get-message-id)
         (lambda (&optional _)
           (plist-get
            (get-text-property
             (line-beginning-position) :notmuch-message-properties)
            :id)))
        ((symbol-function 'notmuch-show-set-tags)
         (lambda (tags)
           (let ((message
                  (get-text-property
                   (line-beginning-position)
                   :notmuch-message-properties)))
             (setf (plist-get message :tags) tags)
             'updated)))
        ((symbol-function 'notmuch-show-mapc)
         (lambda (function)
           (save-excursion
             (goto-char (point-min))
             (while (< (point) (point-max))
               (funcall function)
               (forward-line 1)))))
        ((symbol-function 'notmuch-show-get-messages-ids-search)
         (lambda () "id:synthetic")))
     ,@body))

(ert-deftest emacsvox-notmuch-advice-is-current-and-direct ()
  "Current Notmuch targets use native advice directly."
  (dolist (entry emacsvox-notmuch--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-notmuch-mode-hooks-set-semantic-module ()
  "Notmuch buffers identify their semantic module independently of text."
  (with-temp-buffer
    (emacsvox-notmuch-enable-aural-context)
    (should (eq emacsvox-aural-module 'notmuch))
    (should (local-variable-p 'emacsvox-aural-module))))

(ert-deftest emacsvox-notmuch-search-arrows-match-thread-navigation ()
  "Search-buffer arrows use the same semantic navigation as n and p."
  (with-temp-buffer
    (use-local-map notmuch-search-mode-map)
    (dolist (keys '(("<down>" . "n")
                    ("<up>" . "p")))
      (should
       (eq
        (key-binding (kbd (car keys)))
        (key-binding (kbd (cdr keys))))))))

(ert-deftest emacsvox-notmuch-registers-mail-preview-examples ()
  "Notmuch supplies validated simulations for optional mail presentation."
  (dolist
      (definition
       '((notmuch-unread-message workflow-mail-unread)
         (notmuch-message-with-attachment workflow-mail-attachments)
         (notmuch-forwarded-message workflow-mail-forwarded)
         (notmuch-replied-message workflow-mail-replied)))
    (let ((example
           (emacsvox-aural-feature-fragment-example
            'mail-message-status-cues (car definition))))
      (should example)
      (should
       (eq
        (emacsvox-aural-feature-fragment-example-rule example)
        (cadr definition)))
      (should
       (equal
        (emacsvox-aural-feature-fragment-example-source example)
        "emacsvox-aural-provider-notmuch")))))

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
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (emacsvox-test--notmuch-submission-recorder
             (lambda (event) (push event events)))))
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

(ert-deftest emacsvox-notmuch-hello-widget-label-is-bounded ()
  "Automatic Hello navigation does not submit an arbitrary widget label."
  (with-temp-buffer
    (setq major-mode 'notmuch-hello-mode)
    (let* ((label (make-string 200000 ?w))
           (widget (widget-create 'push-button label))
           spoken)
      (widget-setup)
      (goto-char (widget-get widget :from))
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest _arguments)
              (setq spoken (substring-no-properties content)))))
        (emacsvox-notmuch--hello-widget-summary))
      (should
       (<=
        (length spoken)
        emacsvox-notmuch-automatic-field-character-limit))
      (should
       (equal
        spoken
        (concat
         "… [widget label shortened: 200000 characters omitted; "
         "RET opens full details] button"))))))

(ert-deftest emacsvox-notmuch-show-visual-lines-leave-blank-policy-to-core ()
  "Notmuch should not duplicate core visual-line blank presentation."
  (dolist (case '((notmuch-show-mode "")
                  (notmuch-show-mode "  ")
                  (notmuch-show-mode "content")
                  (fundamental-mode "")))
    (with-temp-buffer
      (insert (nth 1 case))
      (goto-char (point-min))
      (setq major-mode (nth 0 case))
      (let (events)
        (cl-letf (((symbol-function 'tts-stop)
                   (lambda (&rest _)
                     (ert-fail "Notmuch stopped core visual speech")))
                  ((symbol-function 'emacsvox-speak--present-line-condition)
                   (lambda (&rest _)
                     (ert-fail "Notmuch duplicated core blank feedback"))))
          (emacsvox--advice-emacsvox-speak-visual-line-notmuch-around
           (lambda (&rest _)
             (push '(original) events))))
        (should (equal (nreverse events) '((original))))))))

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

(defun emacsvox-notmuch-test--nested-mime-body (depth &optional attachment)
  "Return a synthetic MIME body with ATTACHMENT below DEPTH containers."
  (let ((node
         (or attachment '(:content-type "text/plain" :content "body"))))
    (dotimes (_ depth)
      (setq node
            (list :content-type "multipart/mixed" :content node)))
    (list node)))

(ert-deftest emacsvox-notmuch-mime-scan-is-complete-for-normal-message ()
  "The iterative scan preserves exact attachment results for ordinary mail."
  (let ((scan
         (emacsvox-notmuch--attachment-scan
          (plist-get emacsvox-notmuch-test--show-message :body))))
    (should (= (plist-get scan :count) 2))
    (should (plist-get scan :complete))
    (should (<= (plist-get scan :nodes) emacsvox-notmuch-mime-node-limit))))

(ert-deftest emacsvox-notmuch-mime-scan-bounds-deep-input ()
  "A deeply nested MIME body returns unknown instead of recursing in Lisp."
  (let* ((emacsvox-notmuch-mime-depth-limit 16)
         (body
          (emacsvox-notmuch-test--nested-mime-body
           250
           '(:content-type "application/pdf" :filename "deep.pdf")))
         (scan (emacsvox-notmuch--attachment-scan body)))
    (should-not (plist-get scan :complete))
    (should (= (plist-get scan :count) 0))
    (should
     (equal
      (emacsvox-notmuch--attachment-summary scan)
      "attachment scan incomplete"))))

(ert-deftest emacsvox-notmuch-mime-scan-reports-conservative-lower-bound ()
  "A found attachment remains truthful when another MIME branch is too deep."
  (let* ((emacsvox-notmuch-mime-depth-limit 8)
         (body
          (list
           '(:content-type "application/pdf" :filename "visible.pdf")
           (car
            (emacsvox-notmuch-test--nested-mime-body
             100
             '(:content-type "image/png" :filename "deep.png")))))
         (scan (emacsvox-notmuch--attachment-scan body))
         (facts (emacsvox-notmuch-message-facts (list :body body))))
    (should-not (plist-get scan :complete))
    (should (= (plist-get scan :count) 1))
    (should
     (equal
      (emacsvox-notmuch--attachment-summary scan)
      "at least 1 attachment"))
    (should (memq 'has-attachments (plist-get facts :states)))))

(ert-deftest emacsvox-notmuch-mime-scan-bounds-broad-input ()
  "A broad MIME list cannot exceed the configured node budget."
  (let* ((emacsvox-notmuch-mime-node-limit 40)
         (body
          (make-list
           5000
           '(:content-type "application/pdf" :filename "broad.pdf")))
         (scan (emacsvox-notmuch--attachment-scan body)))
    (should-not (plist-get scan :complete))
    (should (<= (plist-get scan :nodes) 40))
    (should (<= (plist-get scan :count) 5000))))

(ert-deftest emacsvox-notmuch-mime-scan-handles-cycles-and-improper-lists ()
  "Malformed MIME graphs terminate and expose an incomplete result."
  (let* ((cycle (list nil))
         (improper
          (cons
           '(:content-type "application/pdf" :filename "seen.pdf")
           'malformed-tail)))
    (setcar cycle cycle)
    (dolist (body (list cycle improper))
      (let ((scan (emacsvox-notmuch--attachment-scan body)))
        (should-not (plist-get scan :complete))
        (should
         (<=
          (plist-get scan :nodes)
          emacsvox-notmuch-mime-node-limit))))))

(ert-deftest emacsvox-notmuch-incomplete-scan-never-claims-no-attachment ()
  "Unknown attachment state stays unknown in fields and semantic facts."
  (let* ((emacsvox-notmuch-mime-depth-limit 1)
         (body (emacsvox-notmuch-test--nested-mime-body 20))
         (message (list :body body))
         (facts (emacsvox-notmuch-message-facts message))
         (field
          (substring-no-properties
           (emacsvox-notmuch--format-show-field 'attachments message))))
    (should (equal field "attachment scan incomplete"))
    (should-not (memq 'has-attachments (plist-get facts :states)))))

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

(ert-deftest emacsvox-notmuch-fields-carry-semantic-facts ()
  "Formatted fields retain voices while exposing semantic kind and module."
  (let* ((summary
          (emacsvox-notmuch-format-search-result
           emacsvox-notmuch-test--search-result))
         (subject (string-match "Project update" summary)))
    (should
     (eq
      (get-text-property subject 'face summary)
      'notmuch-search-subject))
    (should
     (equal
      (get-text-property
       subject emacsvox-aural-facts-property summary)
      '(:role field :field-kind subject)))
    (should
     (eq
      (get-text-property
       subject emacsvox-aural-module-property summary)
      'notmuch))))

(ert-deftest emacsvox-notmuch-fields-validate-while-opening-message ()
  "Message fields remain semantic content during a state-change opening."
  (let* ((summary
          (emacsvox-notmuch-format-show-message
           emacsvox-notmuch-test--show-message))
         (facts
          (get-text-property
           0 emacsvox-aural-facts-property summary)))
    (should
     (emacsvox-aural-normalize-input
      facts
      '(:module notmuch :mode notmuch-show-mode
        :occasion state-change)))))

(ert-deftest emacsvox-notmuch-status-feedback-shares-message-facts ()
  "Status cues and message speech enter one semantic submission."
  (let (captured)
    (cl-letf
        (((symbol-function 'emacsvox-aural-submit)
          (lambda (content &rest arguments)
            (setq captured (list content arguments)))))
      (emacsvox-notmuch-speak-search-result
       emacsvox-notmuch-test--search-result))
    (let ((arguments (cadr captured)))
      (should (stringp (car captured)))
      (should (eq (plist-get arguments :module) 'notmuch))
      (should (eq (plist-get arguments :occasion) 'navigation))
      (should
       (eq (plist-get (plist-get arguments :facts) :role) 'message))
      (should
       (equal
        (plist-get (plist-get arguments :facts) :states)
        '(unread flagged)))
      (should
       (equal
        (mapcar
         #'emacsvox-aural-compatibility-action-value
         (plist-get arguments :compatibility-actions))
        '(mail-unread mark-object))))))

(ert-deftest emacsvox-notmuch-recognizes-replied-and-forwarded-statuses ()
  "Replied and forwarded tags produce portable facts and distinct cues."
  (let* ((message '(:tags ("forwarded" "replied")))
         (facts (emacsvox-notmuch-message-facts message))
         (actions
          (emacsvox-notmuch--status-compatibility-actions
           message emacsvox-notmuch-search-status-icons 'navigation)))
    (should
     (equal
      (plist-get facts :states)
      '(replied forwarded)))
    (should
     (equal
      (mapcar
       #'emacsvox-aural-compatibility-action-value
       actions)
      '(mail-replied mail-forwarded)))))

(ert-deftest emacsvox-notmuch-attachment-cue-follows-message-content ()
  "The compatibility path places one attachment cue after the message."
  (let* ((emacsvox-aural-enabled-feature-fragments nil)
         (actions
          (emacsvox-notmuch--status-compatibility-actions
           emacsvox-notmuch-test--show-message
           nil 'navigation t)))
    (should (= (length actions) 1))
    (should
     (eq
      (emacsvox-aural-compatibility-action-value (car actions))
      'mail-has-attachment))
    (should
     (eq
      (emacsvox-aural-compatibility-action-phase (car actions))
      'after))))

(ert-deftest emacsvox-notmuch-inspection-retains-compatibility-status-cues ()
  "Navigation-only semantic rules do not silence inspection feedback."
  (let* ((emacsvox-aural-enabled-feature-fragments
          '(mail-message-status-cues))
         (actions
          (emacsvox-notmuch--status-compatibility-actions
           emacsvox-notmuch-test--show-message
           emacsvox-notmuch-show-status-icons 'inspection t)))
    (should
     (equal
      (mapcar
       (lambda (action)
         (list
          (emacsvox-aural-compatibility-action-value action)
          (emacsvox-aural-compatibility-action-phase action)))
       actions)
      '((mail-unread before)
        (mark-object before)
        (mail-has-attachment after))))))

(ert-deftest emacsvox-notmuch-boundary-feedback-uses-one-native-submission ()
  "A search boundary carries its cue and semantics in one submission."
  (let (captured)
    (cl-letf
        (((symbol-function 'emacsvox-aural-submit)
          (lambda (content &rest arguments)
            (setq captured (cons content arguments))
            'submission)))
      (should
       (eq
        (emacsvox-notmuch--search-boundary-feedback 'forward)
        'submission)))
    (pcase-let* ((`(,content . ,arguments) captured)
                 (actions
                  (plist-get arguments :compatibility-actions)))
      (should (equal content "End of search results"))
      (should
       (equal
        (plist-get arguments :facts)
        '(:role mail-view :mail-view-kind search
          :mail-action-kind select :events (operation-failed))))
      (should (eq (plist-get arguments :module) 'notmuch))
      (should (eq (plist-get arguments :occasion) 'navigation))
      (should (= (length actions) 1))
      (should
       (eq
        (emacsvox-aural-compatibility-action-value (car actions))
        'warn-user)))))

(ert-deftest emacsvox-notmuch-empty-text-feedback-is-action-only ()
  "Empty feedback uses one native action transaction without empty speech."
  (let (captured)
    (cl-letf
        (((symbol-function 'emacsvox-aural-submit)
          (lambda (&rest _)
            (ert-fail "Empty text entered content submission")))
         ((symbol-function 'emacsvox-aural-submit-actions)
          (lambda (&rest arguments) (setq captured arguments))))
      (emacsvox-notmuch--submit-text-feedback
       '(:role mail-view :mail-view-kind search)
       'navigation 'warn-user ""))
    (should
     (equal
      (plist-get captured :facts)
      '(:role mail-view :mail-view-kind search)))
    (should (eq (plist-get captured :module) 'notmuch))
    (should (eq (plist-get captured :occasion) 'navigation))
    (should
     (equal
      (mapcar
       #'emacsvox-aural-compatibility-action-value
       (plist-get captured :compatibility-actions))
      '(warn-user)))))

(ert-deftest emacsvox-notmuch-native-boundary-presents-one-transaction ()
  "A search boundary resolves once and obeys the auditory-icon setting."
  (dolist (icons-enabled '(t nil))
    (let ((emacsvox-aural-active-scheme 'default)
          (emacsvox-aural-enabled-feature-fragments nil)
          (emacsvox-aural-user-rules nil)
          (emacsvox-aural-session-rules nil)
          (emacsvox-aural-buffer-rules nil)
          (emacsvox-aural-presentation-history nil)
          (emacsvox-aural-presentation-history-limit 20)
          (emacsvox-aural--presentation-sequence 0)
          (emacsvox-aural--submission-sequence 0)
          (emacsvox-aural-plan-presented-hook nil)
          (emacsvox-use-icons icons-enabled)
          (emacsvox-aural-face-presentation-enabled t)
          (voice-lock-mode t)
          events
          submission)
      (cl-letf
          (((symbol-function 'tts-speak)
            (lambda (prepared)
              (with-temp-buffer
                (insert prepared)
                (tts-audio-format (point-min) (point-max)))))
           ((symbol-function 'emacsvox-queue-resource)
            (lambda (_resource) (push 'cue events)))
           ((symbol-function 'tts-voice-reset-code)
            (lambda () "RESET"))
           ((symbol-function 'tts--protocol-queue-code) #'ignore)
           ((symbol-function 'tts--protocol-queue-text)
            (lambda (text) (push (list 'text text) events)))
           ((symbol-function 'tts--protocol-silence) #'ignore))
        (setq
         submission
         (emacsvox-notmuch--search-boundary-feedback 'forward)))
      (should (emacsvox-aural-submission-p submission))
      (should
       (equal
        (nreverse events)
        (if icons-enabled
            '(cue (text "End of search results"))
          '((text "End of search results")))))
      (should (= (length emacsvox-aural-presentation-history) 1))
      (should
       (= (emacsvox-aural-presentation-record-transaction-id
           (emacsvox-aural-last-presentation))
          1))
      (let* ((plans (emacsvox-aural-submission-plans submission))
             (plan (car plans))
             (content (emacsvox-aural-concrete-plan-content plan))
             (context (emacsvox-aural-concrete-plan-context plan)))
        (should (= (length plans) 1))
        (should
         (equal
          (emacsvox-aural-concrete-plan-facts plan)
          '(:role mail-view :events (operation-failed)
            :mail-action-kind select :mail-view-kind search)))
        (should
         (equal
          (mapcar
           #'emacsvox-aural-concrete-action-cue
           (emacsvox-aural-concrete-plan-before plan))
          (and icons-enabled '(warn-user))))
        (should-not
         (emacsvox-aural-concrete-content-voice-request content))
        (should (eq (plist-get context :module) 'notmuch))
        (should (eq (plist-get context :occasion) 'navigation))
        (should
         (eq (plist-get context :icons-enabled) icons-enabled))))))

(ert-deftest emacsvox-notmuch-status-fragment-resolves-once-per-message ()
  "One message transaction emits each status action once."
  (let* ((message (copy-tree emacsvox-notmuch-test--show-message))
         (emacsvox-notmuch-show-status-icons
          '(("unread" . mail-unread)
            ("replied" . mail-replied)
            ("forwarded" . mail-forwarded)
            ("flagged" . mark-object)))
         (emacsvox-aural-enabled-feature-fragments
          '(mail-message-status-cues))
         (emacsvox-aural-feature-fragment-order nil)
         (emacsvox-aural-user-rules nil)
         (emacsvox-aural-session-rules nil)
         (emacsvox-aural-buffer-rules nil)
         (emacsvox-aural-active-scheme 'default)
         (emacsvox-aural-configuration-generation 0)
         (emacsvox-aural--current-rules-cache
          (make-hash-table :test #'equal))
         (emacsvox-aural--provider-cache
          (make-hash-table :test #'equal))
         (emacsvox-sounds-current-pack 'chimes)
         (emacsvox-use-icons t)
         traces)
    (setf
     (plist-get message :tags)
     '("inbox" "unread" "replied" "forwarded" "flagged"))
    (cl-labels
        ((record-plan
          (kind text plan)
          (push
           (list
            kind
            text
            (mapcar
             #'emacsvox-aural-concrete-action-id
             (emacsvox-aural-concrete-plan-before plan))
            (mapcar
             #'emacsvox-aural-concrete-action-id
             (emacsvox-aural-concrete-plan-after plan)))
           traces)))
      (cl-letf
          (((symbol-function 'tts-speak)
            (lambda (text)
              (let ((position 0))
                (while (< position (length text))
                  (let* ((next
                          (next-single-property-change
                           position
                           emacsvox-aural-concrete-plan-property
                           text
                           (length text)))
                         (plan
                          (emacsvox-aural-concrete-plan-at
                           position text)))
                    (record-plan
                     'speech
                     (substring-no-properties text position next)
                     plan)
                    (setq position next)))))))
        (emacsvox-notmuch-speak-show-message message)))
    (setq traces (nreverse traces))
    (let* ((separators
            (cl-remove-if-not
             (lambda (trace)
               (and
                (eq (car trace) 'speech)
                (equal (cadr trace) ", ")))
             traces))
           (before (apply #'append (mapcar #'caddr traces)))
           (after (apply #'append (mapcar #'cadddr traces))))
      (should
       (equal
        (caddr (car traces))
        '(workflow-mail-unread-cue
          workflow-mail-replied-cue
          workflow-mail-forwarded-cue
          workflow-mail-flagged-cue)))
      (should
       (equal
        (cadddr (car (last traces)))
        '(workflow-mail-attachments-cue)))
      (should (= (length separators) 5))
      (dolist (separator separators)
        (should (equal (cddr separator) '(nil nil))))
      (should
       (= (cl-count 'compatibility-mail-unread-1-legacy-cue before) 0))
      (should
       (= (cl-count 'compatibility-mail-replied-1-legacy-cue before) 0))
      (should
       (= (cl-count 'compatibility-mail-forwarded-1-legacy-cue before) 0))
      (should (= (cl-count 'workflow-mail-unread-cue before) 1))
      (should (= (cl-count 'workflow-mail-replied-cue before) 1))
      (should (= (cl-count 'workflow-mail-forwarded-cue before) 1))
      (should (= (cl-count 'workflow-mail-flagged-cue before) 1))
      (should (= (cl-count 'workflow-mail-attachments-cue after) 1)))))

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

(ert-deftest emacsvox-notmuch-automatic-field-defaults-are-explicit ()
  "Automatic mail fields have documented character and UTF-8 byte budgets."
  (should (= emacsvox-notmuch-automatic-field-character-limit 256))
  (should (= emacsvox-notmuch-automatic-field-byte-limit 1024))
  (should (= emacsvox-notmuch-automatic-total-character-limit 1000))
  (should (= emacsvox-notmuch-automatic-total-byte-limit 4096))
  (should (= emacsvox-notmuch-mime-node-limit 4096))
  (should (= emacsvox-notmuch-mime-depth-limit 64)))

(ert-deftest emacsvox-notmuch-automatic-field-character-boundary-is-exact ()
  "The character limit accepts its boundary and reports the next character."
  (let ((major-mode 'notmuch-search-mode)
        (emacsvox-notmuch-search-result-fields '(subject))
        (emacsvox-notmuch-automatic-field-byte-limit nil))
    (should
     (equal
      (substring-no-properties
       (emacsvox-notmuch-format-search-result
        (list :subject (make-string 256 ?x))))
      (make-string 256 ?x)))
    (should
     (equal
      (substring-no-properties
       (emacsvox-notmuch-format-search-result
        (list :subject (make-string 257 ?x))))
      (concat
       "… [subject shortened: 257 characters omitted; "
       "C-c C-p gives full details]")))))

(ert-deftest emacsvox-notmuch-automatic-field-byte-boundary-is-utf8 ()
  "The byte limit uses UTF-8 and never splits a multibyte character."
  (let ((major-mode 'notmuch-search-mode)
        (emacsvox-notmuch-automatic-field-character-limit nil)
        (emacsvox-notmuch-automatic-field-byte-limit 100))
    (should
     (equal
      (emacsvox-notmuch--prepare-field-text
       (make-string 50 ?é) "subject")
      (make-string 50 ?é)))
    (let ((bounded
           (emacsvox-notmuch--prepare-field-text
            (make-string 51 ?é) "subject")))
      (should
       (equal
        bounded
        (concat
         "… [subject shortened: 51 characters omitted; "
         "C-c C-p gives full details]")))
      (should
       (<= (emacsvox-notmuch--utf8-byte-length bounded) 100)))))

(ert-deftest emacsvox-notmuch-bounds-mail-before-header-transforms ()
  "Huge authors and recipients are bounded before Notmuch transforms them."
  (let ((major-mode 'notmuch-show-mode)
        (huge (make-string 200000 ?x))
        sanitize-lengths
        clean-lengths)
    (cl-letf
        (((symbol-function 'notmuch-sanitize)
          (lambda (text)
            (push (length text) sanitize-lengths)
            text))
         ((symbol-function 'notmuch-show-clean-address)
          (lambda (text)
            (push (length text) clean-lengths)
            text)))
      (emacsvox-notmuch--format-authors huge)
      (emacsvox-notmuch--format-show-field
       'from (list :headers (list :From huge))))
    (should sanitize-lengths)
    (should clean-lengths)
    (should
     (cl-every
      (lambda (length)
        (<= length emacsvox-notmuch-automatic-field-character-limit))
      sanitize-lengths))
    (should
     (cl-every
      (lambda (length)
        (<= length emacsvox-notmuch-automatic-field-character-limit))
      clean-lengths))))

(ert-deftest emacsvox-notmuch-bounds-tags-before-native-formatting ()
  "Huge tag strings never reach Notmuch's formatter in full."
  (let* ((major-mode 'notmuch-search-mode)
         (huge (make-string 200000 ?t))
         (result
          (list :tags (list "inbox" huge)
                :orig-tags (list "inbox" huge)))
         calls)
    (cl-letf
        (((symbol-function 'notmuch-tag-format-tags)
          (lambda (tags orig-tags &optional _face)
            (push (list tags orig-tags) calls)
            (string-join tags " "))))
      (let ((formatted
             (substring-no-properties
              (emacsvox-notmuch--format-tags result nil))))
        (should (string-match-p "tags shortened" formatted))))
    (should (= (length calls) 1))
    (dolist (tag (append (caar calls) (cadar calls)))
      (should (< (length tag) 200000)))))

(ert-deftest emacsvox-notmuch-bounds-custom-formatter-output ()
  "A custom field cannot bypass automatic Notmuch presentation limits."
  (let ((major-mode 'notmuch-search-mode)
        (emacsvox-notmuch-search-result-fields
         (list (lambda (_result) (make-string 200000 ?c)))))
    (let ((summary
           (substring-no-properties
            (emacsvox-notmuch-format-search-result nil))))
      (should
       (<=
        (length summary)
        emacsvox-notmuch-automatic-field-character-limit))
      (should (string-match-p "custom field shortened" summary)))))

(ert-deftest emacsvox-notmuch-total-budget-preserves-semantic-actions ()
  "Total text truncation leaves structured status facts and cues intact."
  (let* ((major-mode 'notmuch-search-mode)
         (emacsvox-notmuch-search-result-fields '(subject))
         (emacsvox-notmuch-automatic-total-character-limit 120)
         (result
          (list :subject (string-join (make-list 600 "word") " ")
                :tags '("unread" "flagged")))
         captured)
    (cl-letf
        (((symbol-function 'emacsvox-aural-submit)
          (lambda (content &rest arguments)
            (setq captured (cons content arguments)))))
      (emacsvox-notmuch-speak-search-result result))
    (pcase-let ((`(,content . ,arguments) captured))
      (should (<= (length content) 120))
      (should (string-match-p "shortened" content))
      (should
       (equal
        (plist-get (plist-get arguments :facts) :states)
        '(unread flagged)))
      (should
       (equal
        (mapcar
         #'emacsvox-aural-compatibility-action-value
         (plist-get arguments :compatibility-actions))
        '(mail-unread mark-object))))))

(ert-deftest emacsvox-notmuch-tag-truncation-never-creates-status-word ()
  "Truncation drops a long tag whole instead of speaking a status-like prefix."
  (let* ((major-mode 'notmuch-search-mode)
         (emacsvox-notmuch-search-result-fields '(tags))
         (status-like (concat "unread" (make-string 200000 ?x)))
         (result
          (list :tags (list "unread" "flagged" status-like)
                :orig-tags (list "unread" "flagged" status-like)))
         (summary
          (substring-no-properties
           (emacsvox-notmuch-format-search-result result))))
    (should (string-match-p "tags shortened" summary))
    (should-not (string-match-p "unreadx" summary))
    (should-not (string-match-p "flagged" summary))))

(ert-deftest emacsvox-notmuch-explicit-search-details-are-untruncated ()
  "C-c C-p inspection speaks the full configured Search fields."
  (let* ((major-mode 'notmuch-search-mode)
         (emacsvox-notmuch-search-result-fields '(subject))
         (subject (make-string 2000 ?s))
         (result (list :subject subject))
         spoken)
    (cl-letf
        (((symbol-function 'emacsvox-aural-submit)
          (lambda (content &rest _arguments)
            (push (substring-no-properties content) spoken))))
      (emacsvox-notmuch-speak-search-result result)
      (emacsvox-notmuch-speak-search-details result))
    (setq spoken (nreverse spoken))
    (should (< (length (car spoken)) (length subject)))
    (should (string-match-p "shortened" (car spoken)))
    (should (equal (cadr spoken) subject))))

(ert-deftest emacsvox-notmuch-search-details-have-manual-binding ()
  "Search exposes complete current-result details on C-c C-p."
  (should
   (eq
    (lookup-key notmuch-search-mode-map (kbd "C-c C-p"))
    #'emacsvox-notmuch-speak-search-details)))

(ert-deftest emacsvox-notmuch-search-status-uses-icons-not-words ()
  "Configured status tags play icons and remain out of speech."
  (let ((status-actions
         (symbol-function
          'emacsvox-notmuch--status-compatibility-actions))
        events)
    (cl-letf (((symbol-function
                'emacsvox-notmuch--status-compatibility-actions)
               (lambda (&rest arguments)
                 (let ((actions (apply status-actions arguments)))
                   (dolist (action actions)
                     (push
                      (list
                       'icon
                       (emacsvox-aural-compatibility-action-value action))
                      events))
                   actions)))
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
      '((icon mail-unread)
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
  (let ((status-actions
         (symbol-function
          'emacsvox-notmuch--status-compatibility-actions))
        events)
    (cl-letf (((symbol-function
                'emacsvox-notmuch--status-compatibility-actions)
               (lambda (&rest arguments)
                 (let ((actions (apply status-actions arguments)))
                   (dolist (action actions)
                     (push
                      (list
                       'icon
                       (emacsvox-aural-compatibility-action-value action))
                      events))
                   actions)))
              ((symbol-function 'tts-speak)
               (lambda (text)
                 (push
                  (list 'speak (substring-no-properties text))
                  events))))
      (emacsvox-notmuch-speak-show-message
       emacsvox-notmuch-test--show-message))
    (should
     (equal
      (nreverse events)
      '((icon mail-unread)
        (icon mark-object)
        (icon mail-has-attachment)
        (speak
         "Alice Smith <alice@example.com>, today, Bart Bunting <bart@example.com>, Project Team <team@example.com>, inbox, 2 attachments"))))))

(ert-deftest emacsvox-notmuch-landed-message-speaks-first-body-line ()
  "Landing on a message speaks its summary followed by visible body text."
  (with-temp-buffer
    (setq major-mode 'notmuch-show-mode)
    (insert "Body separator\n  Message body\nSecond body line\n")
    (goto-char (point-min))
    (let (spoken)
      (cl-letf
          (((symbol-function 'notmuch-show-message-extent)
           (lambda () (cons (point-min) (point-max))))
           ((symbol-function
             'emacsvox-notmuch--status-compatibility-actions)
            #'ignore)
           ((symbol-function 'tts-speak)
            (lambda (text) (setq spoken text))))
        (emacsvox-notmuch--speak-landed-message
         emacsvox-notmuch-test--show-message))
      (should
       (string-suffix-p
        "\n  Message body"
        (substring-no-properties spoken)))
      (should-not
       (string-match-p
        "Second body line"
        (substring-no-properties spoken)))
      (should (= (point) (point-min))))))

(ert-deftest emacsvox-notmuch-limits-body-copy-before-source-preparation ()
  "A huge landed body line is copied only up to the per-field ingress budget."
  (with-temp-buffer
    (setq major-mode 'notmuch-show-mode)
    (insert "Body separator\n" (make-string 200000 ?b) "\n")
    (goto-char (point-min))
    (let ((source-substring
           (symbol-function 'emacsvox-aural-source-substring))
          copied
          line)
      (cl-letf
          (((symbol-function 'notmuch-show-message-extent)
            (lambda () (cons (point-min) (point-max))))
           ((symbol-function 'emacsvox-aural-source-substring)
            (lambda (start end &optional buffer)
              (setq copied (- end start))
              (funcall source-substring start end buffer))))
        (setq line
              (substring-no-properties
               (emacsvox-notmuch--landed-body-line))))
      (should
       (<= copied emacsvox-notmuch-automatic-field-character-limit))
      (should
       (equal
        line
        (concat
         "… [body line shortened: 200000 characters omitted; "
         "C-c C-p gives full details]"))))))

(ert-deftest emacsvox-notmuch-limits-visible-page-before-source-preparation ()
  "Scrolled Show feedback copies no more than the total presentation budget."
  (with-temp-buffer
    (setq major-mode 'notmuch-show-mode)
    (insert (make-string 200000 ?p))
    (let ((source-substring
           (symbol-function 'emacsvox-aural-source-substring))
          copied
          page)
      (cl-letf
          (((symbol-function 'emacsvox-aural-source-substring)
            (lambda (start end &optional buffer)
              (setq copied (- end start))
              (funcall source-substring start end buffer))))
        (setq page
              (emacsvox-notmuch--bounded-source-range
               (point-min) (point-max) "visible page"
               emacsvox-notmuch-automatic-total-character-limit
               emacsvox-notmuch-automatic-total-byte-limit)))
      (should
       (<= copied emacsvox-notmuch-automatic-total-character-limit))
      (should
       (<= (length page) emacsvox-notmuch-automatic-total-character-limit))
      (should
       (<=
        (emacsvox-notmuch--utf8-byte-length page)
        emacsvox-notmuch-automatic-total-byte-limit))
      (should (string-match-p "visible page shortened" page)))))

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
                ((symbol-function
                  'emacsvox-notmuch--status-compatibility-actions)
                 (lambda (&rest _)
                   (push '(status-icons) events)
                   nil))
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

(ert-deftest emacsvox-notmuch-automatic-part-filename-is-bounded ()
  "Automatic part feedback identifies a shortened hostile filename explicitly."
  (let* ((major-mode 'notmuch-show-mode)
         (filename (make-string 200000 ?f))
         (part (list :filename filename :content-type "application/pdf"))
         (automatic
          (substring-no-properties (emacsvox-notmuch-format-part part)))
         (full
          (let ((emacsvox-notmuch--automatic-presentation-p nil))
            (substring-no-properties
             (emacsvox-notmuch-format-part part)))))
    (should (string-match-p "filename shortened: 200000" automatic))
    (should (< (length automatic) (length filename)))
    (should (string-search filename full))))

(ert-deftest emacsvox-notmuch-show-inspection-reveals-full-part-filename ()
  "C-c C-p on a MIME part bypasses automatic filename truncation."
  (with-temp-buffer
    (setq major-mode 'notmuch-show-mode)
    (let* ((filename (make-string 2000 ?f))
           (part (list :filename filename :content-type "application/pdf"))
           spoken)
      (insert-text-button "attachment" 'action #'ignore)
      (put-text-property (point-min) (point-max) :notmuch-part part)
      (goto-char (point-min))
      (cl-letf
          (((symbol-function 'notmuch-show-get-message-properties)
            (lambda () emacsvox-notmuch-test--show-message))
           ((symbol-function 'emacsvox-notmuch--show-message-position)
            (lambda () '(1 . 1)))
           ((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest _arguments)
              (setq spoken (substring-no-properties content)))))
        (emacsvox-notmuch-speak-show-position))
      (should (string-search filename spoken))
      (should-not (string-match-p "shortened" spoken)))))

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
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (emacsvox-test--notmuch-submission-recorder
             (lambda (event) (push event events)))))
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
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (emacsvox-test--notmuch-submission-recorder
             (lambda (event) (push event events)))))
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
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (emacsvox-test--notmuch-submission-recorder
             (lambda (event) (push event events)))))
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
        (cl-letf
            (((symbol-function 'emacsvox-aural-submit)
              (emacsvox-test--notmuch-submission-recorder
               (lambda (event) (push event events)))))
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
        (cl-letf
            (((symbol-function 'emacsvox-aural-submit)
              (emacsvox-test--notmuch-submission-recorder
               (lambda (event) (push event events)))))
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

(ert-deftest emacsvox-notmuch-part-action-has-semantic-context ()
  "A MIME-part action submits its cue, text, and structured intent once."
  (let ((part '(:filename "report.pdf" :content-type "application/pdf"))
        captured)
    (cl-letf
        (((symbol-function 'emacsvox-aural-submit)
          (lambda (content &rest arguments)
            (setq captured (cons content arguments))
            'submission)))
      (should
       (eq
        (emacsvox-notmuch--part-action-feedback 'save part)
        'submission)))
    (pcase-let* ((`(,content . ,arguments) captured)
                 (actions
                  (plist-get arguments :compatibility-actions)))
      (should (equal content "Saved attachment report.pdf"))
      (should
       (equal
        (plist-get arguments :facts)
        '(:role message-part :message-part-kind attachment
          :mail-action-kind save :events (operation-completed))))
      (should (eq (plist-get arguments :module) 'notmuch))
      (should (eq (plist-get arguments :occasion) 'state-change))
      (should (= (length actions) 1))
      (should
       (eq
        (emacsvox-aural-compatibility-action-value (car actions))
        'save-object)))))

(ert-deftest emacsvox-notmuch-native-part-navigation-presents-once ()
  "Attachment navigation preserves voice and one ordered transaction."
  (dolist (icons-enabled '(t nil))
    (with-temp-buffer
      (insert-text-button
       "[ report.pdf: application/pdf ]" 'action #'ignore)
      (put-text-property
       (point-min) (point-max)
       :notmuch-part emacsvox-notmuch-test--attachment)
      (goto-char (point-min))
      (let ((emacsvox-aural-active-scheme 'default)
            (emacsvox-aural-enabled-feature-fragments nil)
            (emacsvox-aural-user-rules nil)
            (emacsvox-aural-session-rules nil)
            (emacsvox-aural-buffer-rules nil)
            (emacsvox-aural-presentation-history nil)
            (emacsvox-aural-presentation-history-limit 20)
            (emacsvox-aural--presentation-sequence 0)
            (emacsvox-aural--submission-sequence 0)
            (emacsvox-aural-plan-presented-hook nil)
            (emacsvox-use-icons icons-enabled)
            (emacsvox-aural-face-presentation-enabled t)
            (voice-lock-mode t)
            events
            submission)
        (cl-letf
            (((symbol-function 'tts-speak)
              (lambda (prepared)
                (with-temp-buffer
                  (insert prepared)
                  (tts-audio-format (point-min) (point-max)))))
             ((symbol-function 'emacsvox-queue-resource)
              (lambda (_resource) (push 'cue events)))
             ((symbol-function 'tts-voice-reset-code)
              (lambda () "RESET"))
             ((symbol-function 'tts--protocol-queue-code) #'ignore)
             ((symbol-function 'tts--protocol-queue-text)
              (lambda (text) (push (list 'text text) events)))
             ((symbol-function 'tts--protocol-silence) #'ignore))
          (setq submission (emacsvox-notmuch--speak-show-button)))
        (should (emacsvox-aural-submission-p submission))
        (should
         (equal
          (nreverse events)
          (if icons-enabled
              '(cue
                (text
                 "Attachment report.pdf, application/pdf, 58 KiB"))
            '((text
               "Attachment report.pdf, application/pdf, 58 KiB")))))
        (should (= (length emacsvox-aural-presentation-history) 1))
        (should
         (= (emacsvox-aural-presentation-record-transaction-id
             (emacsvox-aural-last-presentation))
            1))
        (let* ((plans (emacsvox-aural-submission-plans submission))
               (plan (car plans))
               (facts (emacsvox-aural-concrete-plan-facts plan))
               (content (emacsvox-aural-concrete-plan-content plan))
               (context (emacsvox-aural-concrete-plan-context plan)))
          (should (= (length plans) 1))
          (should (eq (plist-get facts :role) 'message-part))
          (should
           (eq (plist-get facts :message-part-kind) 'attachment))
          (should (eq (plist-get facts :mail-action-kind) 'select))
          (should (equal (plist-get facts :events) '(focus-entered)))
          (should
           (equal
            (mapcar
             #'emacsvox-aural-concrete-action-cue
             (emacsvox-aural-concrete-plan-before plan))
            (and icons-enabled '(item))))
          (should
           (eq
            (emacsvox-aural-concrete-content-voice-request content)
            'voice-annotate))
          (should (eq (plist-get context :module) 'notmuch))
          (should (eq (plist-get context :occasion) 'navigation))
          (should
           (eq
            (plist-get context :icons-enabled)
            icons-enabled)))))))

(ert-deftest emacsvox-notmuch-show-save-attachments-confirms-completion ()
  "Saving all message attachments gives one completion confirmation."
  (let ((ems--interactive-fn-name 'notmuch-show-save-attachments)
        events)
    (cl-letf (((symbol-function 'notmuch-show-get-message-properties)
               (lambda () emacsvox-notmuch-test--show-message))
              ((symbol-function 'emacsvox-aural-submit)
               (emacsvox-test--notmuch-submission-recorder
                (lambda (event) (push event events)))))
      (emacsvox--advice-notmuch-show-save-attachments-around
       (lambda () 'saved)))
    (should
     (equal
      (nreverse events)
      '((icon save-object)
        (speak "Finished saving attachments"))))))

(ert-deftest emacsvox-notmuch-save-attachments-keeps-incomplete-scan-truthful ()
  "A bounded unknown scan never produces a false no-attachment confirmation."
  (let* ((ems--interactive-fn-name 'notmuch-show-save-attachments)
         (emacsvox-notmuch-mime-depth-limit 1)
         (message
          (list :body (emacsvox-notmuch-test--nested-mime-body 20)))
         events)
    (cl-letf
        (((symbol-function 'notmuch-show-get-message-properties)
          (lambda () message))
         ((symbol-function 'emacsvox-aural-submit)
          (emacsvox-test--notmuch-submission-recorder
           (lambda (event) (push event events)))))
      (emacsvox--advice-notmuch-show-save-attachments-around
       (lambda () 'saved)))
    (should
     (equal
      (nreverse events)
      '((icon select-object)
        (speak
         "Finished saving attachments; attachment scan incomplete"))))))

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
              captured)
          (goto-char (point-min))
          (cl-letf (((symbol-function 'notmuch-show-get-message-properties)
                     (lambda () message))
                    ((symbol-function 'notmuch-show-message-extent)
                     (lambda () extent))
                    ((symbol-function
                      'emacsvox-notmuch--submit-show-message)
                     (lambda (&rest arguments)
                       (setq captured arguments))))
            (emacsvox--advice-notmuch-search-show-thread-after))
          (should
           (save-excursion
             (forward-line 1)
             (skip-chars-forward " \t")
             (looking-at-p "Message body")))
          (should
           (equal
            (substring-no-properties (nth 1 captured))
            "  Message body"))
          (should (eq (nth 0 captured) message))
          (should
           (equal
            (plist-get (nth 2 captured) :events)
            '(message-opened)))
          (should (eq (nth 3 captured) 'state-change))
          (should (eq (nth 4 captured) 'open-object)))))))

(ert-deftest emacsvox-notmuch-opening-thread-is-one-native-submission ()
  "View opening, message status, content, and attachment share one submission."
  (let ((emacsvox-aural-enabled-feature-fragments
         '(mail-message-status-cues))
        (calls 0)
        captured)
    (cl-letf
        (((symbol-function 'emacsvox-aural-submit)
          (lambda (content &rest arguments)
            (cl-incf calls)
            (setq captured (cons content arguments))
            'submission)))
      (emacsvox-notmuch--submit-show-message
       emacsvox-notmuch-test--show-message
       "Message body"
       (emacsvox-notmuch-message-facts
        emacsvox-notmuch-test--show-message 'message-opened)
       'state-change
       'open-object))
    (should (= calls 1))
    (pcase-let* ((`(,content . ,arguments) captured)
                 (facts (plist-get arguments :facts))
                 (actions
                  (plist-get arguments :compatibility-actions)))
      (should (string-suffix-p "\nMessage body" content))
      (should (equal (plist-get facts :events) '(message-opened)))
      (should
       (equal
        (plist-get facts :states)
        '(unread flagged has-attachments)))
      (should (eq (plist-get arguments :module) 'notmuch))
      (should (eq (plist-get arguments :occasion) 'state-change))
      (should
       (equal
        (mapcar
         (lambda (action)
           (list
            (emacsvox-aural-compatibility-action-value action)
            (emacsvox-aural-compatibility-action-phase action)))
         actions)
        '((open-object before)
          (mail-unread before)
          (mark-object before)
          (mail-has-attachment after)))))))

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

(ert-deftest emacsvox-notmuch-search-navigation-speaks-selected-result ()
  "Only the active interactive search-navigation command speaks."
  (with-temp-buffer
    (setq major-mode 'notmuch-search-mode)
    (let ((ems--interactive-fn-name 'notmuch-search-next-thread)
          (thread-ids '("first" "second"))
          (calls 0)
          events)
      (cl-letf
          (((symbol-function 'emacsvox-notmuch--current-search-thread-id)
            (lambda () (pop thread-ids)))
           ((symbol-function 'emacsvox-notmuch-speak-search-result)
            (lambda (&optional _result) (push 'result events))))
        (should
         (eq
          (emacsvox--advice-notmuch-search-next-thread-around
           (lambda ()
             (cl-incf calls)
             'moved))
          'moved))
        (should
         (eq
          (emacsvox--advice-notmuch-search-previous-thread-around
           (lambda ()
             (cl-incf calls)
             'ignored))
          'ignored)))
      (should (= calls 2))
      (should (equal events '(result))))))

(ert-deftest emacsvox-notmuch-search-navigation-announces-boundaries ()
  "Search navigation announces rather than rereads its boundary result."
  (dolist
      (case
       '((notmuch-search-next-thread
          emacsvox--advice-notmuch-search-next-thread-around
          ("last" nil)
          "End of search results")
         (notmuch-search-previous-thread
          emacsvox--advice-notmuch-search-previous-thread-around
          ("first" "first")
          "Beginning of search results")))
    (with-temp-buffer
      (setq major-mode 'notmuch-search-mode)
      (let ((ems--interactive-fn-name (nth 0 case))
            (thread-ids (copy-sequence (nth 2 case)))
            (calls 0)
            events)
        (cl-letf
            (((symbol-function 'emacsvox-notmuch--current-search-thread-id)
              (lambda () (pop thread-ids)))
             ((symbol-function 'emacsvox-notmuch-speak-search-result)
              (lambda (&optional _result) (push '(result) events)))
             ((symbol-function 'emacsvox-aural-submit)
              (emacsvox-test--notmuch-submission-recorder
               (lambda (event) (push event events)))))
          (should
           (eq
            (funcall
             (nth 1 case)
             (lambda ()
               (cl-incf calls)
               'unchanged))
            'unchanged)))
        (should (= calls 1))
        (should
         (equal
          (nreverse events)
          `((icon warn-user)
            (speak ,(nth 3 case)))))))))

(ert-deftest emacsvox-notmuch-search-navigation-detects-real-boundaries ()
  "Actual Notmuch movement functions expose both search boundaries."
  (with-temp-buffer
    (let ((first-start (point)))
      (insert "First result\n")
      (put-text-property
       first-start (point) 'notmuch-search-result '(:thread "first")))
    (let ((last-start (point)))
      (insert "Last result\n")
      (put-text-property
       last-start (point) 'notmuch-search-result '(:thread "last"))
      (insert "End of search results.\n")
      (setq major-mode 'notmuch-search-mode)
      (goto-char (point-min))
      (let ((ems--interactive-fn-name
             'notmuch-search-previous-thread)
            events)
        (cl-letf
            (((symbol-function 'emacsvox-aural-submit)
              (emacsvox-test--notmuch-submission-recorder
               (lambda (event) (push event events)))))
          (notmuch-search-previous-thread)
          (should
           (equal
            (nreverse events)
            '((icon warn-user)
              (speak "Beginning of search results"))))
          (setq events nil
                ems--interactive-fn-name 'notmuch-search-next-thread)
          (goto-char last-start)
          (notmuch-search-next-thread)
          (should
           (equal
            (nreverse events)
            '((icon warn-user)
              (speak "End of search results")))))))))

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
           ((symbol-function 'emacsvox-notmuch--landed-body-line)
            (lambda () "Message body"))
           ((symbol-function 'emacsvox-notmuch-speak-show-message)
            (lambda (&optional _message body-line)
              (push (list 'message body-line) events))))
        (emacsvox--advice-notmuch-show-next-open-message-around
         (lambda ()
           (cl-incf calls)
           'moved))
        (emacsvox--advice-notmuch-show-previous-open-message-around
         (lambda ()
           (cl-incf calls)
           'unchanged)))
      (should (= calls 2))
      (should
       (equal
        (nreverse events)
        '(body (message "Message body")))))))

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
             ((symbol-function 'emacsvox-aural-submit)
              (emacsvox-test--notmuch-submission-recorder
               (lambda (event) (push event events)))))
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
             ((symbol-function 'emacsvox-aural-submit)
              (emacsvox-test--notmuch-submission-recorder
               (lambda (event) (push event events)))))
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
          captured)
      (insert "message body")
      (goto-char (point-min))
      (cl-letf
          (((symbol-function 'emacsvox-notmuch--current-show-message-id)
            (lambda () "same"))
           ((symbol-function 'emacsvox-notmuch--bounded-source-range)
            (lambda (&rest _) "visible window"))
           ((symbol-function 'emacsvox-notmuch--submit-content)
            (lambda (&rest arguments) (setq captured arguments))))
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
        (car captured)
        "visible window"))
      (should (eq (nth 2 captured) 'navigation))
      (should
       (equal
        (mapcar
         #'emacsvox-aural-compatibility-action-value
         (nth 3 captured))
        '(scroll))))))

(ert-deftest emacsvox-notmuch-show-advance-announces-thread-end ()
  "Space submits one semantic boundary when it cannot advance."
  (with-temp-buffer
    (setq major-mode 'notmuch-show-mode)
    (insert "message body")
    (goto-char (point-max))
    (let ((ems--interactive-fn-name 'notmuch-show-advance)
          (calls 0)
          feedback)
      (cl-letf
          (((symbol-function 'emacsvox-notmuch--current-show-message-id)
            (lambda () "same"))
           ((symbol-function 'emacsvox-notmuch--submit-text-feedback)
            (lambda (&rest arguments)
              (setq feedback arguments)
              'submission)))
        (should
         (eq
          (emacsvox--advice-notmuch-show-advance-around
           (lambda ()
             (cl-incf calls)
             'at-end))
          'at-end)))
      (should (= calls 1))
      (should
       (equal
        feedback
        '((:role message-thread :mail-action-kind select
           :events (focus-entered))
          navigation select-object "End of thread"))))))

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
          captured)
      (cl-letf
          (((symbol-function 'emacsvox-notmuch--current-show-message-id)
            (lambda () "same"))
           ((symbol-function 'emacsvox-notmuch--bounded-source-range)
            (lambda (&rest _) "visible window"))
           ((symbol-function 'emacsvox-notmuch--submit-content)
            (lambda (&rest arguments) (setq captured arguments))))
        (should
         (eq
          (emacsvox--advice-notmuch-show-advance-and-archive-around
           (lambda ()
             (cl-incf calls)
             'scrolled))
          'scrolled)))
      (should (= calls 1))
      (should (equal (car captured) "visible window"))
      (should (eq (nth 2 captured) 'navigation))
      (should
       (equal
        (mapcar
         #'emacsvox-aural-compatibility-action-value
         (nth 3 captured))
        '(scroll))))))

(ert-deftest emacsvox-notmuch-space-delegates-end-of-thread-archive-state ()
  "Space delegates its end-of-thread operation to the archive owner."
  (with-temp-buffer
    (setq major-mode 'notmuch-show-mode)
    (let ((ems--interactive-fn-name 'notmuch-show-advance-and-archive)
          (calls 0)
          lifecycle)
      (cl-letf
          (((symbol-function 'emacsvox-notmuch--archive-state-around)
            (lambda (target object original arguments all-show observe-state)
              (setq lifecycle
                    (list target object arguments all-show observe-state))
              (apply original arguments))))
        (should
         (eq
          (emacsvox--advice-notmuch-show-advance-and-archive-around
           (lambda ()
             (cl-incf calls)
             'archived))
          'archived)))
      (should (= calls 1))
      (should
       (equal
        lifecycle
        '(notmuch-show-advance-and-archive thread nil t nil))))))

(ert-deftest emacsvox-notmuch-show-opening-message-cues-and-speaks ()
  "Opening a message body plays an opening cue and identifies it."
  (let ((ems--interactive-fn-name 'notmuch-show-toggle-message)
        captured)
    (cl-letf
        (((symbol-function 'notmuch-show-get-message-properties)
          (lambda () '(:message-visible t)))
         ((symbol-function 'emacsvox-notmuch--submit-show-message)
          (lambda (&rest arguments) (setq captured arguments))))
      (emacsvox--advice-notmuch-show-toggle-message-after))
    (should (equal (car captured) '(:message-visible t)))
    (should
     (equal
      (plist-get (nth 2 captured) :events)
      '(visibility-changed)))
    (should (eq (nth 3 captured) 'state-change))
    (should (eq (nth 4 captured) 'open-object))))

(ert-deftest emacsvox-notmuch-show-closing-message-uses-icon-only ()
  "Closing a message body uses a concise nonverbal cue."
  (let ((ems--interactive-fn-name 'notmuch-show-toggle-message)
        captured)
    (cl-letf
        (((symbol-function 'notmuch-show-get-message-properties)
          (lambda () '(:message-visible nil)))
         ((symbol-function 'emacsvox-notmuch--submit-text-feedback)
          (lambda (&rest arguments) (setq captured arguments))))
      (emacsvox--advice-notmuch-show-toggle-message-after))
    (should
     (equal
      (plist-get (car captured) :events)
      '(visibility-changed)))
    (should (eq (nth 1 captured) 'state-change))
    (should (eq (nth 2 captured) 'close-object))
    (should-not (nth 3 captured))))

(ert-deftest emacsvox-notmuch-show-open-all-feedback-is-target-aware ()
  "Opening all message bodies produces one visibility announcement."
  (let ((ems--interactive-fn-name 'notmuch-show-open-or-close-all)
        submissions)
    (cl-letf
        (((symbol-function 'notmuch-show-get-message-properties)
          (lambda () '(:message-visible t)))
         ((symbol-function 'emacsvox-notmuch--submit-show-message)
          (lambda (&rest arguments) (push arguments submissions))))
      (emacsvox--advice-notmuch-show-toggle-message-after)
      (emacsvox--advice-notmuch-show-open-or-close-all-after))
    (should (= (length submissions) 1))
    (should (eq (nth 4 (car submissions)) 'open-object))))

(ert-deftest emacsvox-notmuch-describes-tag-changes ()
  "Tag-change summaries distinguish additions and removals."
  (should
   (equal
    (emacsvox-notmuch--tag-change-summary
     '("+work" "+urgent" "-inbox"))
    "Added work, urgent; Removed inbox")))

(ert-deftest emacsvox-notmuch-search-tag-reports-actual-change-once ()
  "A public interactive Search tag wrapper reports its actual delta once."
  (with-temp-buffer
    (setq major-mode 'notmuch-search-mode)
    (let* ((result (copy-tree emacsvox-notmuch-test--search-result))
           (ems--interactive-fn-name 'notmuch-search-add-tag)
           backend-calls
           events)
      (setf (plist-get result :thread) "thread:one"
            (plist-get result :tags) '("inbox")
            (plist-get result :orig-tags) '("inbox"))
      (let ((start
             (emacsvox-notmuch-test--insert-rendered-search-result result)))
        (goto-char start)
        (let ((initial-point (point)))
          (cl-letf
              (((symbol-function 'notmuch-search-find-stable-query-region)
                (lambda (&rest _) "thread:one"))
               ((symbol-function 'notmuch-tag)
                (lambda (&rest arguments)
                  (push arguments backend-calls)))
               ((symbol-function 'emacsvox-aural-submit)
                (emacsvox-test--notmuch-submission-recorder
                 (lambda (event) (push event events)))))
            (should-not
             (notmuch-search-add-tag
              '("+work" "-inbox") start start)))
          (should (= (point) initial-point))
          (should
           (equal (plist-get (notmuch-search-get-result) :tags) '("work")))
          (should (= (length backend-calls) 1))
          (setq events (nreverse events))
          (should (equal (car events) '(icon task-done)))
          (should (= (length events) 2))
          (should
           (string-prefix-p
            "Added work; Removed inbox\nAlice Smith"
            (cadr (cadr events)))))))))

(ert-deftest emacsvox-notmuch-search-tag-no-ops-are-explicit ()
  "Adding an existing or removing an absent Search tag says it is unchanged."
  (dolist
      (case
       '((notmuch-search-add-tag "+work")
         (notmuch-search-remove-tag "-absent")))
    (with-temp-buffer
      (setq major-mode 'notmuch-search-mode)
      (let* ((target (car case))
             (change (cadr case))
             (result (copy-tree emacsvox-notmuch-test--search-result))
             (ems--interactive-fn-name target)
             backend-calls
             submissions)
        (setf (plist-get result :thread) "thread:one"
              (plist-get result :tags) '("work")
              (plist-get result :orig-tags) '("work"))
        (let ((start
               (emacsvox-notmuch-test--insert-rendered-search-result result)))
          (goto-char start)
          (let ((initial-point (point)))
            (cl-letf
                (((symbol-function 'notmuch-search-find-stable-query-region)
                  (lambda (&rest _) "thread:one"))
                 ((symbol-function 'notmuch-tag)
                  (lambda (&rest arguments)
                    (push arguments backend-calls)))
                 ((symbol-function 'emacsvox-aural-submit)
                  (lambda (content &rest arguments)
                    (push
                     (cons (substring-no-properties content) arguments)
                     submissions))))
              (should-not (funcall target (list change) start start)))
            (should (= (point) initial-point))
            (should
             (equal
              (plist-get (notmuch-search-get-result) :tags)
              '("work")))
            (should (= (length backend-calls) 1))
            (should (= (length submissions) 1))
            (pcase-let* ((`(,content . ,arguments) (car submissions))
                         (facts (plist-get arguments :facts)))
              (should (equal content "Tags unchanged"))
              (should
               (equal facts '(:role message :mail-action-kind tag)))
              (should-not (plist-get facts :events))
              (should-not
               (plist-get arguments :compatibility-actions)))))))))

(ert-deftest emacsvox-notmuch-search-region-reports-only-actual-tag-delta ()
  "A mixed Search region reports tags changed on at least one target."
  (with-temp-buffer
    (setq major-mode 'notmuch-search-mode)
    (let* ((first (copy-tree emacsvox-notmuch-test--search-result))
           (second (copy-tree emacsvox-notmuch-test--search-result))
           (ems--interactive-fn-name 'notmuch-search-add-tag)
           backend-calls
           events)
      (setf (plist-get first :thread) "thread:one"
            (plist-get first :tags) '("work")
            (plist-get first :orig-tags) '("work")
            (plist-get second :thread) "thread:two"
            (plist-get second :authors) "Bob Jones"
            (plist-get second :subject) "Second result"
            (plist-get second :tags) '("inbox")
            (plist-get second :orig-tags) '("inbox"))
      (let ((first-start
             (emacsvox-notmuch-test--insert-rendered-search-result first))
            (second-start
             (emacsvox-notmuch-test--insert-rendered-search-result second)))
        (goto-char second-start)
        (cl-letf
            (((symbol-function 'notmuch-search-find-stable-query-region)
              (lambda (&rest _) "thread:one or thread:two"))
             ((symbol-function 'notmuch-tag)
              (lambda (&rest arguments)
                (push arguments backend-calls)))
             ((symbol-function 'emacsvox-aural-submit)
              (emacsvox-test--notmuch-submission-recorder
               (lambda (event) (push event events)))))
          (should-not
           (notmuch-search-add-tag '("+work") first-start (point-max))))
        (should (= (length backend-calls) 1))
        (should
         (member
          "work"
          (plist-get (notmuch-search-get-result first-start) :tags)))
        (should
         (member
          "work"
          (plist-get (notmuch-search-get-result second-start) :tags)))
        (setq events (nreverse events))
        (should (equal (car events) '(icon task-done)))
        (should (= (length events) 2))
        (should
         (string-prefix-p
          "Added work\nBob Jones"
          (cadr (cadr events))))))))

(ert-deftest emacsvox-notmuch-show-tag-reports-actual-change-once ()
  "A public interactive Show tag wrapper preserves and reports its result."
  (with-temp-buffer
    (setq major-mode 'notmuch-show-mode)
    (let* ((message (copy-tree emacsvox-notmuch-test--show-message))
           (ems--interactive-fn-name 'notmuch-show-add-tag)
           backend-calls
           events)
      (setf (plist-get message :id) "message:one"
            (plist-get message :tags) '("inbox")
            (plist-get message :orig-tags) '("inbox"))
      (let ((start
             (emacsvox-notmuch-test--insert-show-message "Message" message)))
        (goto-char start)
        (let ((initial-point (point)))
          (emacsvox-notmuch-test--with-synthetic-show-tags
            (cl-letf
                (((symbol-function 'notmuch-tag)
                  (lambda (&rest arguments)
                    (push arguments backend-calls)))
                 ((symbol-function 'emacsvox-aural-submit)
                  (emacsvox-test--notmuch-submission-recorder
                   (lambda (event) (push event events)))))
              (should
               (eq (notmuch-show-add-tag '("+work")) 'updated))))
          (should (= (point) initial-point))
          (should (equal (plist-get message :tags) '("inbox" "work")))
          (should (= (length backend-calls) 1))
          (setq events (nreverse events))
          (should (equal (car events) '(icon task-done)))
          (should (= (length events) 3))
          (should (equal (cadr events) '(icon mail-has-attachment)))
          (should
           (string-prefix-p
            "Added work\nAlice Smith"
            (cadr (nth 2 events)))))))))

(ert-deftest emacsvox-notmuch-show-tag-no-op-is-explicit ()
  "A public Show tag no-op speaks no success cue or message summary."
  (with-temp-buffer
    (setq major-mode 'notmuch-show-mode)
    (let* ((message (copy-tree emacsvox-notmuch-test--show-message))
           (ems--interactive-fn-name 'notmuch-show-add-tag)
           backend-calls
           events)
      (setf (plist-get message :id) "message:one"
            (plist-get message :tags) '("work")
            (plist-get message :orig-tags) '("work"))
      (let ((start
             (emacsvox-notmuch-test--insert-show-message "Message" message)))
        (goto-char start)
        (let ((initial-point (point)))
          (emacsvox-notmuch-test--with-synthetic-show-tags
            (cl-letf
                (((symbol-function 'notmuch-tag)
                  (lambda (&rest arguments)
                    (push arguments backend-calls)))
                 ((symbol-function 'emacsvox-aural-submit)
                  (emacsvox-test--notmuch-submission-recorder
                   (lambda (event) (push event events)))))
              (should-not (notmuch-show-add-tag '("+work")))))
          (should (= (point) initial-point))
          (should (equal (plist-get message :tags) '("work")))
          (should (= (length backend-calls) 1))
          (should
           (equal (nreverse events) '((speak "Tags unchanged")))))))))

(ert-deftest emacsvox-notmuch-show-tag-all-compares-every-message ()
  "Thread-wide Show tagging reports a change made to any message."
  (with-temp-buffer
    (setq major-mode 'notmuch-show-mode)
    (let* ((first (copy-tree emacsvox-notmuch-test--show-message))
           (second (copy-tree emacsvox-notmuch-test--show-message))
           (ems--interactive-fn-name 'notmuch-show-tag-all)
           backend-calls
           events)
      (setf (plist-get first :id) "message:one"
            (plist-get first :tags) '("work")
            (plist-get first :orig-tags) '("work")
            (plist-get second :id) "message:two"
            (plist-get second :tags) '("inbox")
            (plist-get second :orig-tags) '("inbox")
            (plist-get (plist-get second :headers) :From) "Bob Jones")
      (let ((first-start
             (emacsvox-notmuch-test--insert-show-message "First" first))
            (second-start
             (emacsvox-notmuch-test--insert-show-message "Second" second)))
        (goto-char second-start)
        (emacsvox-notmuch-test--with-synthetic-show-tags
          (cl-letf
              (((symbol-function 'notmuch-tag)
                (lambda (&rest arguments)
                  (push arguments backend-calls)))
               ((symbol-function 'emacsvox-aural-submit)
                (emacsvox-test--notmuch-submission-recorder
                 (lambda (event) (push event events)))))
            (should-not (notmuch-show-tag-all '("+work")))))
        (should (= (length backend-calls) 1))
        (should (member "work" (plist-get first :tags)))
        (should (member "work" (plist-get second :tags)))
        (should (= (point) second-start))
        (should (= first-start (point-min)))
        (setq events (nreverse events))
        (should (equal (car events) '(icon task-done)))
        (should (= (length events) 3))
        (should
         (string-prefix-p
          "Added work\nBob Jones"
          (cadr (nth 2 events))))))))

(ert-deftest emacsvox-notmuch-direct-tag-errors-do-not-announce ()
  "A failed public tag command re-signals without feedback."
  (with-temp-buffer
    (setq major-mode 'notmuch-search-mode)
    (let* ((result (copy-tree emacsvox-notmuch-test--search-result))
           (ems--interactive-fn-name 'notmuch-search-add-tag)
           events)
      (setf (plist-get result :thread) "thread:one"
            (plist-get result :tags) '("inbox")
            (plist-get result :orig-tags) '("inbox"))
      (let ((start
             (emacsvox-notmuch-test--insert-rendered-search-result result)))
        (goto-char start)
        (cl-letf
            (((symbol-function 'notmuch-search-find-stable-query-region)
              (lambda (&rest _) "thread:one"))
             ((symbol-function 'notmuch-tag)
              (lambda (&rest _) (error "Synthetic tag failure")))
             ((symbol-function 'emacsvox-aural-submit)
              (lambda (&rest arguments) (push arguments events))))
          (should-error
           (notmuch-search-add-tag '("+work") start start)
           :type 'error))
        (should-not events)
        (should
         (equal
          (plist-get (notmuch-search-get-result) :tags)
          '("inbox")))))))

(ert-deftest emacsvox-notmuch-programmatic-direct-tag-remains-silent ()
  "Programmatic public tag calls still change state without feedback."
  (with-temp-buffer
    (setq major-mode 'notmuch-search-mode)
    (let ((result (copy-tree emacsvox-notmuch-test--search-result))
          events)
      (setf (plist-get result :thread) "thread:one"
            (plist-get result :tags) '("inbox")
            (plist-get result :orig-tags) '("inbox"))
      (let ((start
             (emacsvox-notmuch-test--insert-rendered-search-result result)))
        (goto-char start)
        (cl-letf
            (((symbol-function 'notmuch-search-find-stable-query-region)
              (lambda (&rest _) "thread:one"))
             ((symbol-function 'notmuch-tag) (lambda (&rest _) nil))
             ((symbol-function 'emacsvox-aural-submit)
              (lambda (&rest arguments) (push arguments events))))
          (notmuch-search-add-tag '("+work") start start))
        (should
         (member
          "work" (plist-get (notmuch-search-get-result) :tags)))
        (should-not events)))))

(ert-deftest emacsvox-notmuch-status-tag-changes-remain-nonverbal ()
  "Status changes use cues without speaking status names."
  (let ((message (copy-tree emacsvox-notmuch-test--show-message))
        captured)
    (setf (plist-get message :tags) '("inbox" "flagged")
          (plist-get message :orig-tags) '("inbox" "flagged"))
    (cl-letf
        (((symbol-function 'emacsvox-aural-submit)
          (lambda (content &rest arguments)
            (setq captured (cons content arguments)))))
      (emacsvox-notmuch--tag-operation-feedback
       '("+flagged" "-unread")
       emacsvox-notmuch-show-status-icons
       message t))
    (pcase-let* ((`(,content . ,arguments) captured)
                 (facts (plist-get arguments :facts))
                 (actions
                  (plist-get arguments :compatibility-actions)))
      (should-not (string-match-p "flagged\\|unread" content))
      (should (string-match-p "2 attachments" content))
      (should
       (equal
        (plist-get facts :states)
        '(flagged has-attachments)))
      (should
     (equal
        (mapcar
         (lambda (action)
           (list
            (emacsvox-aural-compatibility-action-value action)
            (emacsvox-aural-compatibility-action-phase action)))
         actions)
        '((deselect-object before)
          (mark-object before)
          (mail-has-attachment after)))))))

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

(ert-deftest emacsvox-notmuch-show-archive-message-reports-actual-change ()
  "Public message archive and unarchive report actual mutations."
  (dolist
      (case
       '((nil ("inbox" "work") "Archived message" close-object nil)
         (t ("work") "Unarchived message" open-object t)))
    (with-temp-buffer
      (setq major-mode 'notmuch-show-mode)
      (let* ((unarchive (nth 0 case))
             (message (copy-tree emacsvox-notmuch-test--show-message))
             (notmuch-archive-tags '("-inbox"))
             (ems--interactive-fn-name 'notmuch-show-archive-message)
             backend-calls submissions)
        (setf (plist-get message :id) "message:one"
              (plist-get message :tags) (copy-sequence (nth 1 case))
              (plist-get message :orig-tags) (copy-sequence (nth 1 case)))
        (emacsvox-notmuch-test--insert-show-message "message" message)
        (goto-char (point-min))
        (emacsvox-notmuch-test--with-synthetic-show-tags
          (cl-letf
              (((symbol-function 'notmuch-tag)
                (lambda (&rest arguments)
                  (push arguments backend-calls)))
               ((symbol-function 'emacsvox-aural-submit)
                (lambda (content &rest arguments)
                  (push
                   (cons (substring-no-properties content) arguments)
                   submissions))))
            (should
             (eq (notmuch-show-archive-message unarchive) 'updated))))
        (should (= (length backend-calls) 1))
        (should
         (eq
          (and (member "inbox" (plist-get message :tags)) t)
          (nth 4 case)))
        (should (= (length submissions) 1))
        (pcase-let* ((`(,content . ,arguments) (car submissions))
                     (facts (plist-get arguments :facts))
                     (actions
                      (mapcar
                       #'emacsvox-aural-compatibility-action-value
                       (plist-get arguments :compatibility-actions))))
          (should (string-prefix-p (nth 2 case) content))
          (should
           (equal
            facts
            '(:role message :mail-action-kind archive
              :events (operation-completed))))
          (should (eq (car actions) (nth 3 case))))))))

(ert-deftest emacsvox-notmuch-show-archive-no-ops-are-truthful ()
  "Configured and disabled message archive no-ops have distinct outcomes."
  (dolist
      (case
       '((("-inbox") ("work") "Archive tags unchanged")
         (nil ("inbox") "Archive tags are not configured")))
    (with-temp-buffer
      (setq major-mode 'notmuch-show-mode)
      (let* ((notmuch-archive-tags (nth 0 case))
             (message (copy-tree emacsvox-notmuch-test--show-message))
             (ems--interactive-fn-name 'notmuch-show-archive-message)
             backend-calls submissions)
        (setf (plist-get message :id) "message:one"
              (plist-get message :tags) (copy-sequence (nth 1 case))
              (plist-get message :orig-tags) (copy-sequence (nth 1 case)))
        (emacsvox-notmuch-test--insert-show-message "message" message)
        (goto-char (point-min))
        (emacsvox-notmuch-test--with-synthetic-show-tags
          (cl-letf
              (((symbol-function 'notmuch-tag)
                (lambda (&rest arguments)
                  (push arguments backend-calls)))
               ((symbol-function 'emacsvox-aural-submit)
                (lambda (content &rest arguments)
                  (push
                   (cons (substring-no-properties content) arguments)
                   submissions))))
            (should-not (notmuch-show-archive-message))))
        (should-not backend-calls)
        (should (equal (plist-get message :tags) (nth 1 case)))
        (should (= (length submissions) 1))
        (pcase-let* ((`(,content . ,arguments) (car submissions))
                     (facts (plist-get arguments :facts)))
          (should (equal content (nth 2 case)))
          (should
           (equal facts '(:role message :mail-action-kind archive)))
          (should-not (plist-get facts :events))
          (should-not
           (plist-get arguments :compatibility-actions)))))))

(ert-deftest emacsvox-notmuch-show-archive-thread-observes-every-message ()
  "A public thread archive derives success from all shown messages."
  (with-temp-buffer
    (setq major-mode 'notmuch-show-mode)
    (let* ((first (copy-tree emacsvox-notmuch-test--show-message))
           (second (copy-tree emacsvox-notmuch-test--show-message))
           (notmuch-archive-tags '("-inbox"))
           (ems--interactive-fn-name 'notmuch-show-archive-thread)
           backend-calls submissions)
      (setf (plist-get first :id) "message:one"
            (plist-get first :tags) '("inbox")
            (plist-get first :orig-tags) '("inbox")
            (plist-get second :id) "message:two"
            (plist-get second :tags) nil
            (plist-get second :orig-tags) nil)
      (emacsvox-notmuch-test--insert-show-message "first" first)
      (emacsvox-notmuch-test--insert-show-message "second" second)
      (goto-char (point-min))
      (emacsvox-notmuch-test--with-synthetic-show-tags
        (cl-letf
            (((symbol-function 'notmuch-tag)
              (lambda (&rest arguments)
                (push arguments backend-calls)))
             ((symbol-function 'emacsvox-aural-submit)
              (lambda (content &rest arguments)
                (push
                 (cons (substring-no-properties content) arguments)
                 submissions))))
          (should-not (notmuch-show-archive-thread))))
      (should (= (length backend-calls) 1))
      (should-not (member "inbox" (plist-get first :tags)))
      (should-not (plist-get second :tags))
      (should (= (length submissions) 1))
      (should
       (string-prefix-p "Archived thread\n" (caar submissions)))
      (should
       (equal
        (plist-get (cdar submissions) :facts)
        '(:role message-thread :mail-action-kind archive
          :events (operation-completed)))))))

(ert-deftest emacsvox-notmuch-show-archive-wrapper-has-one-owner ()
  "Archive-and-move wrappers report one outcome followed by the destination."
  (dolist
      (case
       '((("inbox") "Archived message" t)
         (("work") "Archive tags unchanged" nil)))
    (with-temp-buffer
      (setq major-mode 'notmuch-show-mode)
      (let* ((first (copy-tree emacsvox-notmuch-test--show-message))
             (second (copy-tree emacsvox-notmuch-test--show-message))
             (notmuch-archive-tags '("-inbox"))
             (ems--interactive-fn-name
              'notmuch-show-archive-message-then-next-or-exit)
             backend-calls submissions)
        (setf (plist-get first :id) "message:one"
              (plist-get first :tags) (copy-sequence (nth 0 case))
              (plist-get first :orig-tags) (copy-sequence (nth 0 case))
              (plist-get second :id) "message:two"
              (plist-get second :tags) '("work")
              (plist-get second :orig-tags) '("work")
              (plist-get (plist-get second :headers) :From)
              "Bob Jones <bob@example.com>")
        (emacsvox-notmuch-test--insert-show-message "first" first)
        (emacsvox-notmuch-test--insert-show-message "second" second)
        (goto-char (point-min))
        (emacsvox-notmuch-test--with-synthetic-show-tags
          (cl-letf
              (((symbol-function 'notmuch-tag)
                (lambda (&rest arguments)
                  (push arguments backend-calls)))
               ((symbol-function 'notmuch-show-next-open-message)
                (lambda (&optional _)
                  (forward-line 1)
                  'moved))
               ((symbol-function 'emacsvox-aural-submit)
                (lambda (content &rest arguments)
                  (push
                   (cons (substring-no-properties content) arguments)
                   submissions))))
            (should
             (eq
              (notmuch-show-archive-message-then-next-or-exit)
              'moved))))
        (should (= (length backend-calls) (if (nth 2 case) 1 0)))
        (should (= (length submissions) 1))
        (pcase-let* ((`(,content . ,arguments) (car submissions))
                     (facts (plist-get arguments :facts))
                     (actions
                      (mapcar
                       #'emacsvox-aural-compatibility-action-value
                       (plist-get arguments :compatibility-actions))))
          (should
           (string-prefix-p
            (concat (nth 1 case) "\nBob Jones") content))
          (if (nth 2 case)
              (progn
                (should
                 (equal (plist-get facts :events)
                        '(operation-completed)))
                (should (eq (car actions) 'close-object)))
            (should-not (plist-get facts :events))
            (should-not (memq 'close-object actions))
            (should-not (memq 'open-object actions))))))))

(ert-deftest emacsvox-notmuch-search-archive-reports-state-and-destination ()
  "Search archive distinguishes changed, reversed, unchanged, and disabled."
  (dolist
      (case
       '((:config ("-inbox") :unarchive nil :tags ("inbox" "work")
          :inbox-after nil :text "Archived thread" :cue close-object
          :backend 1)
         (:config ("-inbox") :unarchive t :tags ("work")
          :inbox-after t :text "Unarchived thread" :cue open-object
          :backend 1)
         (:config ("-inbox") :unarchive nil :tags ("work")
          :inbox-after nil :text "Archive tags unchanged" :backend 1)
         (:config nil :unarchive nil :tags ("inbox" "work")
          :inbox-after t :text "Archive tags are not configured"
          :backend 0)))
    (with-temp-buffer
      (setq major-mode 'notmuch-search-mode)
      (let* ((first (copy-tree emacsvox-notmuch-test--search-result))
             (second (copy-tree emacsvox-notmuch-test--search-result))
             (notmuch-archive-tags (plist-get case :config))
             (ems--interactive-fn-name 'notmuch-search-archive-thread)
             backend-calls submissions)
        (setf (plist-get first :thread) "thread:one"
              (plist-get first :tags) (copy-sequence (plist-get case :tags))
              (plist-get first :orig-tags)
              (copy-sequence (plist-get case :tags))
              (plist-get second :thread) "thread:two"
              (plist-get second :authors) "Bob Jones"
              (plist-get second :subject) "Destination"
              (plist-get second :tags) '("work")
              (plist-get second :orig-tags) '("work"))
        (let ((first-start
               (emacsvox-notmuch-test--insert-rendered-search-result first)))
          (emacsvox-notmuch-test--insert-rendered-search-result second)
          (goto-char first-start)
          (cl-letf
              (((symbol-function 'notmuch-search-find-stable-query-region)
                (lambda (&rest _) "thread:one"))
               ((symbol-function 'notmuch-tag)
                (lambda (&rest arguments)
                  (push arguments backend-calls)))
               ((symbol-function 'emacsvox-aural-submit)
                (lambda (content &rest arguments)
                  (push
                   (cons (substring-no-properties content) arguments)
                   submissions))))
            (let ((result
                   (notmuch-search-archive-thread
                    (plist-get case :unarchive) first-start first-start)))
              (should (integerp result))
              (should (= result (point))))))
        (should
         (equal
          (plist-get (notmuch-search-get-result) :thread)
          "thread:two"))
        (should
         (eq
          (and
           (member
            "inbox"
            (plist-get (notmuch-search-get-result (point-min)) :tags))
           t)
          (plist-get case :inbox-after)))
        (should (= (length backend-calls) (plist-get case :backend)))
        (should (= (length submissions) 1))
        (pcase-let* ((`(,content . ,arguments) (car submissions))
                     (facts (plist-get arguments :facts))
                     (actions
                      (mapcar
                       #'emacsvox-aural-compatibility-action-value
                       (plist-get arguments :compatibility-actions))))
          (should
           (string-prefix-p
            (concat (plist-get case :text) "\nBob Jones") content))
          (if-let* ((cue (plist-get case :cue)))
              (progn
                (should
                 (equal (plist-get facts :events)
                        '(operation-completed)))
                (should (eq (car actions) cue)))
            (should-not (plist-get facts :events))
            (should-not (memq 'close-object actions))
            (should-not (memq 'open-object actions))))))))

(ert-deftest emacsvox-notmuch-space-archive-reports-state-before-destination ()
  "Space reports a real thread change or disabled configuration before moving."
  (dolist
      (case
       '((("-inbox") "Archived thread" 1 t)
         (nil "Archive tags are not configured" 0 nil)))
    (with-temp-buffer
      (setq major-mode 'notmuch-show-mode)
      (let* ((message (copy-tree emacsvox-notmuch-test--show-message))
             (destination (copy-tree emacsvox-notmuch-test--search-result))
             (notmuch-archive-tags (nth 0 case))
             (ems--interactive-fn-name 'notmuch-show-advance-and-archive)
             backend-calls submissions)
        (setf (plist-get message :id) "message:one"
              (plist-get message :tags) '("inbox")
              (plist-get message :orig-tags) '("inbox")
              (plist-get destination :thread) "thread:two"
              (plist-get destination :authors) "Bob Jones"
              (plist-get destination :subject) "Destination"
              (plist-get destination :tags) '("work")
              (plist-get destination :orig-tags) '("work"))
        (emacsvox-notmuch-test--insert-show-message "message" message)
        (goto-char (point-max))
        (emacsvox-notmuch-test--with-synthetic-show-tags
          (cl-letf
              (((symbol-function 'notmuch-show-advance) (lambda () t))
               ((symbol-function 'notmuch-tag)
                (lambda (&rest arguments)
                  (push arguments backend-calls)))
               ((symbol-function 'notmuch-show-next-thread)
                (lambda (&rest _)
                  (let ((inhibit-read-only t))
                    (erase-buffer)
                    (setq major-mode 'notmuch-search-mode)
                    (emacsvox-notmuch-test--insert-rendered-search-result
                     destination)
                    (goto-char (point-min)))
                  'moved))
               ((symbol-function 'emacsvox-aural-submit)
                (lambda (content &rest arguments)
                  (push
                   (cons (substring-no-properties content) arguments)
                   submissions))))
            (should
             (eq (notmuch-show-advance-and-archive) 'moved))))
        (should (= (length backend-calls) (nth 2 case)))
        (should
         (eq (and (member "inbox" (plist-get message :tags)) t)
             (not (nth 3 case))))
        (should (= (length submissions) 1))
        (pcase-let* ((`(,content . ,arguments) (car submissions))
                     (facts (plist-get arguments :facts))
                     (actions
                      (mapcar
                       #'emacsvox-aural-compatibility-action-value
                       (plist-get arguments :compatibility-actions))))
          (should
           (string-prefix-p (concat (nth 1 case) "\nBob Jones") content))
          (if (nth 3 case)
              (progn
                (should
                 (equal (plist-get facts :events)
                        '(operation-completed)))
                (should (eq (car actions) 'close-object)))
            (should-not (plist-get facts :events))
            (should-not (memq 'close-object actions))))))))

(ert-deftest emacsvox-notmuch-archive-errors-do-not-announce ()
  "A failed public archive re-signals without changing tags or announcing."
  (with-temp-buffer
    (setq major-mode 'notmuch-show-mode)
    (let* ((message (copy-tree emacsvox-notmuch-test--show-message))
           (notmuch-archive-tags '("-inbox"))
           (ems--interactive-fn-name 'notmuch-show-archive-message)
           submissions)
      (setf (plist-get message :id) "message:one"
            (plist-get message :tags) '("inbox")
            (plist-get message :orig-tags) '("inbox"))
      (emacsvox-notmuch-test--insert-show-message "message" message)
      (goto-char (point-min))
      (emacsvox-notmuch-test--with-synthetic-show-tags
        (cl-letf
            (((symbol-function 'notmuch-tag)
              (lambda (&rest _) (error "Synthetic archive failure")))
             ((symbol-function 'emacsvox-aural-submit)
              (lambda (&rest arguments) (push arguments submissions))))
          (should-error (notmuch-show-archive-message) :type 'error)))
      (should (equal (plist-get message :tags) '("inbox")))
      (should-not submissions))))

(ert-deftest emacsvox-notmuch-programmatic-archive-remains-silent ()
  "Programmatic archive calls still mutate without user feedback."
  (with-temp-buffer
    (setq major-mode 'notmuch-show-mode)
    (let* ((message (copy-tree emacsvox-notmuch-test--show-message))
           (notmuch-archive-tags '("-inbox"))
           backend-calls submissions)
      (setf (plist-get message :id) "message:one"
            (plist-get message :tags) '("inbox")
            (plist-get message :orig-tags) '("inbox"))
      (emacsvox-notmuch-test--insert-show-message "message" message)
      (goto-char (point-min))
      (emacsvox-notmuch-test--with-synthetic-show-tags
        (cl-letf
            (((symbol-function 'notmuch-tag)
              (lambda (&rest arguments)
                (push arguments backend-calls)))
             ((symbol-function 'emacsvox-aural-submit)
              (lambda (&rest arguments) (push arguments submissions))))
          (should (eq (notmuch-show-archive-message) 'updated))))
      (should (= (length backend-calls) 1))
      (should-not (member "inbox" (plist-get message :tags)))
      (should-not submissions))))

(ert-deftest emacsvox-notmuch-search-completion-style-is-customizable ()
  "Search completion defaults to the approved interaction-aware policy."
  (should (custom-variable-p 'emacsvox-notmuch-search-completion-style))
  (should (eq (default-value 'emacsvox-notmuch-search-completion-style)
              'adaptive)))

(ert-deftest emacsvox-notmuch-search-identifies-user-owned-entry-paths ()
  "Direct, Hello, filter, toggle, and refresh searches retain their owner."
  (dolist
      (case
       '((notmuch-search notmuch-search search)
         (widget-button-press widget-button-press search)
         (notmuch-search-filter notmuch-search-filter search)
         (notmuch-search-toggle-order notmuch-search-toggle-order search)
         (notmuch-search-refresh-view notmuch-search-refresh-view refresh)
         (notmuch-refresh-this-buffer notmuch-refresh-this-buffer refresh)
         (nil nil nil)
         (notmuch-refresh-all-buffers notmuch-refresh-all-buffers nil)
         (notmuch-search-refresh-view notmuch-refresh-all-buffers nil)))
    (let ((ems--interactive-fn-name (nth 0 case))
          (this-command (nth 1 case)))
      (should (eq (emacsvox-notmuch--search-request-kind) (nth 2 case))))))

(ert-deftest emacsvox-notmuch-delayed-search-defers-result-presentation ()
  "A running search gets a progress cue without premature empty speech."
  (let ((buffer (generate-new-buffer " *emacsvox-notmuch-running-test*"))
        properties events)
    (unwind-protect
        (save-window-excursion
          (set-window-buffer (selected-window) buffer)
          (with-current-buffer buffer
            (emacsvox-notmuch-test--with-fake-search-process
                ('process buffer properties 'run 0)
              (cl-letf
                  (((symbol-function 'emacsvox-aural-submit-actions)
                    (lambda (&rest arguments)
                      (push
                       (mapcar
                        #'emacsvox-aural-compatibility-action-value
                        (plist-get arguments :compatibility-actions))
                       events)
                      'submission))
                   ((symbol-function 'emacsvox-aural-submit)
                    (lambda (&rest _)
                      (ert-fail "Search spoke content before it completed")))
                   ((symbol-function 'tts-notify)
                    (lambda (&rest _)
                      (ert-fail "Search notified before it completed"))))
                (let ((ems--interactive-fn-name 'notmuch-search)
                      (this-command 'notmuch-search))
                  (should
                   (eq
                    (emacsvox--advice-notmuch-search-around
                     (lambda () 'started))
                    'started))))
              (should
               (equal
                (alist-get
                 emacsvox-notmuch--search-process-property properties)
                '(:kind search :interacted nil)))
              (should (eq emacsvox-notmuch--tracked-search-process 'process))
              (should
               (memq #'emacsvox-notmuch--note-search-interaction
                     pre-command-hook)))))
      (when (buffer-live-p buffer) (kill-buffer buffer)))
    (should (equal events '((progress))))))

(ert-deftest emacsvox-notmuch-untouched-search-speaks-final-row-and-count ()
  "A focused untouched search presents complete data once without moving."
  (let ((buffer (generate-new-buffer " *emacsvox-notmuch-complete-test*"))
        (properties
         `((,emacsvox-notmuch--search-process-property
            . (:kind search :interacted nil))))
        captured initial-point)
    (unwind-protect
        (save-window-excursion
          (set-window-buffer (selected-window) buffer)
          (with-current-buffer buffer
            (setq major-mode 'notmuch-search-mode)
            (emacsvox-notmuch-test--insert-search-result
             "First result" (copy-tree emacsvox-notmuch-test--search-result))
            (emacsvox-notmuch-test--insert-search-result
             "Second result" '(:thread "two"))
            (insert "End of search results.\n")
            (goto-char (point-min))
            (setq initial-point (point)
                  emacsvox-notmuch--tracked-search-process 'process)
            (add-hook
             'pre-command-hook
             #'emacsvox-notmuch--note-search-interaction nil t))
          (emacsvox-notmuch-test--with-fake-search-process
              ('process buffer properties 'exit 0)
            (cl-letf
                (((symbol-function 'emacsvox-aural-submit)
                  (lambda (content &rest arguments)
                    (push (cons content arguments) captured)
                    'submission))
                 ((symbol-function 'tts-notify)
                  (lambda (&rest _)
                    (ert-fail "Untouched foreground search used notifications")))
                 ((symbol-function 'tts-notify-icon)
                  (lambda (&rest _)
                    (ert-fail "Untouched foreground search used notifications"))))
              (emacsvox--advice-notmuch-search-process-sentinel-after
               'process nil)))
          (should (= (length captured) 1))
          (pcase-let ((`(,content . ,arguments) (car captured)))
            (should
             (equal
              (substring-no-properties content)
              (concat
               "Search complete, 2 threads\n"
               "Alice Smith, Bob Jones, Project update, yesterday, "
               "2 of 5, inbox work")))
            (should
             (equal
              (mapcar
               #'emacsvox-aural-compatibility-action-value
               (plist-get arguments :compatibility-actions))
              '(task-done mail-unread mark-object))))
          (with-current-buffer buffer
            (should (= (point) initial-point))
            (should-not emacsvox-notmuch--tracked-search-process)
            (should-not
             (memq #'emacsvox-notmuch--note-search-interaction
                   pre-command-hook)))
          (should-not
           (alist-get emacsvox-notmuch--search-process-property properties)))
      (when (buffer-live-p buffer) (kill-buffer buffer)))))

(ert-deftest emacsvox-notmuch-empty-search-is-explicit-after-completion ()
  "An untouched empty search reports zero only after its sentinel."
  (let ((buffer (generate-new-buffer " *emacsvox-notmuch-empty-test*"))
        (properties
         `((,emacsvox-notmuch--search-process-property
            . (:kind search :interacted nil))))
        captured)
    (unwind-protect
        (save-window-excursion
          (set-window-buffer (selected-window) buffer)
          (emacsvox-notmuch-test--with-fake-search-process
              ('process buffer properties 'exit 0)
            (cl-letf
                (((symbol-function 'emacsvox-aural-submit)
                  (lambda (content &rest arguments)
                    (setq captured (cons content arguments))
                    'submission))
                 ((symbol-function 'tts-notify)
                  (lambda (&rest _)
                    (ert-fail "Focused empty search used notifications"))))
              (emacsvox--advice-notmuch-search-process-sentinel-after
               'process nil)))
          (should (equal (substring-no-properties (car captured))
                         "Search complete, 0 threads")))
      (when (buffer-live-p buffer) (kill-buffer buffer)))))

(ert-deftest emacsvox-notmuch-navigation-during-search-gets-summary-only ()
  "Completion never replays a row after the user navigates streamed results."
  (let ((buffer (generate-new-buffer " *emacsvox-notmuch-interaction-test*"))
        (properties
         `((,emacsvox-notmuch--search-process-property
            . (:kind search :interacted nil))))
        events facts second-point)
    (unwind-protect
        (save-window-excursion
          (set-window-buffer (selected-window) buffer)
          (with-current-buffer buffer
            (setq major-mode 'notmuch-search-mode)
            (emacsvox-notmuch-test--insert-search-result
             "First result" (copy-tree emacsvox-notmuch-test--search-result))
            (setq second-point
                  (emacsvox-notmuch-test--insert-search-result
                   "Second result" '(:thread "two")))
            (goto-char second-point)
            (setq emacsvox-notmuch--tracked-search-process 'process)
            (add-hook
             'pre-command-hook
             #'emacsvox-notmuch--note-search-interaction nil t))
          (emacsvox-notmuch-test--with-fake-search-process
              ('process buffer properties 'exit 0)
            (with-current-buffer buffer
              (emacsvox-notmuch--note-search-interaction))
            (cl-letf
                (((symbol-function 'emacsvox-aural-submit)
                  (lambda (&rest _)
                    (ert-fail "Interacted search replayed message content")))
                 ((symbol-function 'tts-notify-icon)
                  (lambda (icon) (push (list 'icon icon) events)))
                 ((symbol-function 'tts-notify)
                  (lambda (text &optional _)
                    (setq facts (copy-tree emacsvox-aural-submission-facts))
                    (push (list 'notify text) events))))
              (emacsvox--advice-notmuch-search-process-sentinel-after
               'process nil)))
          (should
           (equal
            (nreverse events)
            '((icon task-done) (notify "Search complete, 2 threads"))))
          (should
           (equal
            facts
            '(:role mail-view :mail-view-kind search
              :mail-action-kind search :events (refresh-completed))))
          (with-current-buffer buffer
            (should (= (point) second-point))))
      (when (buffer-live-p buffer) (kill-buffer buffer)))))

(ert-deftest emacsvox-notmuch-background-search-notification-is-generic ()
  "Background completion omits query and message metadata from notifications."
  (let ((buffer (generate-new-buffer " *emacsvox-notmuch-background-test*"))
        events)
    (unwind-protect
        (progn
          (with-current-buffer buffer
            (emacsvox-notmuch-test--insert-search-result
             "First result" (copy-tree emacsvox-notmuch-test--search-result)))
          (cl-letf
              (((symbol-function 'emacsvox-notmuch--search-buffer-focused-p)
                (lambda (_buffer) nil))
               ((symbol-function 'emacsvox-aural-submit)
                (lambda (&rest _)
                  (ert-fail "Background completion used primary speech")))
               ((symbol-function 'tts-notify-icon)
                (lambda (icon) (push (list 'icon icon) events)))
               ((symbol-function 'tts-notify)
                (lambda (text &optional _)
                  (push (list 'notify text) events))))
            (emacsvox-notmuch--announce-search-complete
             '(:kind search :interacted nil) buffer)))
      (when (buffer-live-p buffer) (kill-buffer buffer)))
    (should
     (equal
      (nreverse events)
      '((icon task-done) (notify "Search complete, 1 thread"))))))

(ert-deftest emacsvox-notmuch-refresh-announces-on-notification-stream ()
  "An explicit refresh reports its final count without replaying a row."
  (let ((buffer (generate-new-buffer " *emacsvox-notmuch-refresh-test*"))
        (properties
         `((,emacsvox-notmuch--search-process-property
            . (:kind refresh :interacted nil))))
        events)
    (unwind-protect
        (progn
          (with-current-buffer buffer
            (emacsvox-notmuch-test--insert-search-result
             "First result" '(:thread "one"))
            (emacsvox-notmuch-test--insert-search-result
             "Second result" '(:thread "two")))
          (emacsvox-notmuch-test--with-fake-search-process
              ('process buffer properties 'exit 0)
            (cl-letf
                (((symbol-function 'emacsvox-aural-submit)
                  (lambda (&rest _)
                    (ert-fail "Refresh replayed primary row speech")))
                 ((symbol-function 'tts-notify-icon)
                  (lambda (icon) (push (list 'icon icon) events)))
                 ((symbol-function 'tts-notify)
                  (lambda (text &optional _)
                    (push (list 'notify text) events))))
              (emacsvox--advice-notmuch-search-process-sentinel-after
               'process nil))))
      (when (buffer-live-p buffer) (kill-buffer buffer)))
    (should
     (equal
      (nreverse events)
      '((icon task-done) (notify "Search refreshed, 2 threads"))))))

(ert-deftest emacsvox-notmuch-refresh-all-remains-silent ()
  "The command for silently refreshing every buffer tracks no process."
  (let ((buffer (generate-new-buffer " *emacsvox-notmuch-refresh-all-test*"))
        properties)
    (unwind-protect
        (with-current-buffer buffer
          (emacsvox-notmuch-test--with-fake-search-process
              ('process buffer properties 'run 0)
            (cl-letf
                (((symbol-function 'emacsvox-aural-submit-actions)
                  (lambda (&rest _)
                    (ert-fail "Global refresh produced feedback"))))
              (let ((ems--interactive-fn-name 'notmuch-search-refresh-view)
                    (this-command 'notmuch-refresh-all-buffers))
                (emacsvox--advice-notmuch-search-around #'ignore))))
          (should-not
           (alist-get emacsvox-notmuch--search-process-property properties))
          (should-not emacsvox-notmuch--tracked-search-process))
      (when (buffer-live-p buffer) (kill-buffer buffer)))))

(ert-deftest emacsvox-notmuch-fast-search-completes-exactly-once ()
  "A sentinel that ran before advice marking still produces one completion."
  (let ((buffer (generate-new-buffer " *emacsvox-notmuch-fast-test*"))
        (properties
         `((,emacsvox-notmuch--search-sentinel-finished-property . t)))
        (emacsvox-notmuch-search-completion-style 'summary)
        events)
    (unwind-protect
        (with-current-buffer buffer
          (emacsvox-notmuch-test--insert-search-result
           "First result" '(:thread "one"))
          (emacsvox-notmuch-test--with-fake-search-process
              ('process buffer properties 'exit 0)
            (cl-letf
                (((symbol-function 'emacsvox-aural-submit-actions)
                  (lambda (&rest _)
                    (ert-fail "Completed search emitted a progress cue")))
                 ((symbol-function 'tts-notify-icon)
                  (lambda (icon) (push (list 'icon icon) events)))
                 ((symbol-function 'tts-notify)
                  (lambda (text &optional _)
                    (push (list 'notify text) events))))
              (emacsvox-notmuch--track-search-process 'search)
              (emacsvox--advice-notmuch-search-process-sentinel-after
               'process nil)))
          (should-not
           (alist-get emacsvox-notmuch--search-process-property properties))
          (should-not emacsvox-notmuch--tracked-search-process)
          (should-not
           (memq #'emacsvox-notmuch--note-search-interaction
                 pre-command-hook)))
      (when (buffer-live-p buffer) (kill-buffer buffer)))
    (should
     (equal
      (nreverse events)
      '((icon task-done) (notify "Search complete, 1 thread"))))))

(ert-deftest emacsvox-notmuch-search-completion-cue-and-silent-styles ()
  "The concise completion styles emit exactly their configured output."
  (let ((buffer (generate-new-buffer " *emacsvox-notmuch-style-test*")))
    (unwind-protect
        (dolist (case '((cue ((icon task-done))) (silent nil)))
          (let ((emacsvox-notmuch-search-completion-style (car case))
                events)
            (cl-letf
                (((symbol-function 'emacsvox-notmuch--search-buffer-focused-p)
                  (lambda (_buffer) nil))
                 ((symbol-function 'tts-notify-icon)
                  (lambda (icon) (push (list 'icon icon) events)))
                 ((symbol-function 'tts-notify)
                  (lambda (text &optional _)
                    (push (list 'notify text) events))))
              (emacsvox-notmuch--announce-search-complete
               '(:kind search :interacted nil) buffer))
            (should (equal (nreverse events) (nth 1 case)))))
      (when (buffer-live-p buffer) (kill-buffer buffer)))))

(ert-deftest emacsvox-notmuch-killed-search-owner-cancels-silently ()
  "Killing a real search owner produces no late failure notification."
  (let* ((owner
          (generate-new-buffer " *emacsvox-notmuch-cancelled-owner*"))
         (parse-buffer
          (generate-new-buffer " *emacsvox-notmuch-cancelled-parse*"))
         (emacs-program
          (expand-file-name invocation-name invocation-directory))
         process events)
    (unwind-protect
        (progn
          (setq process
                (make-process
                 :name "emacsvox-notmuch-cancelled-search"
                 :buffer owner
                 :command
                 (list emacs-program "-Q" "--batch" "--eval"
                       "(sleep-for 60)")
                 :connection-type 'pipe
                 :noquery t
                 :sentinel #'notmuch-start-notmuch-sentinel))
          (process-put process 'sub-sentinel #'notmuch-search-process-sentinel)
          (process-put process 'parse-buf parse-buffer)
          (process-put
           process emacsvox-notmuch--search-process-property
           '(:kind refresh :interacted nil))
          (with-current-buffer owner
            (setq-local emacsvox-notmuch--tracked-search-process process)
            (add-hook
             'pre-command-hook
             #'emacsvox-notmuch--note-search-interaction nil t))
          (should (process-live-p process))
          (cl-letf
              (((symbol-function 'emacsvox-aural-submit)
                (lambda (&rest arguments)
                  (push (cons 'submit arguments) events)))
               ((symbol-function 'emacsvox-aural-submit-actions)
                (lambda (&rest arguments)
                  (push (cons 'actions arguments) events)))
               ((symbol-function 'tts-notify-icon)
                (lambda (&rest arguments)
                  (push (cons 'icon arguments) events)))
               ((symbol-function 'tts-notify)
                (lambda (&rest arguments)
                  (push (cons 'notify arguments) events))))
            (should (kill-buffer owner))
            (let ((deadline (+ (float-time) 2.0)))
              (while (and (process-live-p process)
                          (< (float-time) deadline))
                (accept-process-output process 0.05)))
            (accept-process-output process 0.05)
            (should-not (buffer-live-p owner))
            (should-not (process-live-p process))
            (should (memq (process-status process) '(exit signal)))
            (should-not
             (process-get
              process emacsvox-notmuch--search-process-property))
            (should-not (buffer-live-p parse-buffer))
            (should-not events)
            ;; A duplicate terminal callback must remain silent too.
            (notmuch-start-notmuch-sentinel process "killed\n")
            (should-not events)))
      (when process
        (process-put
         process emacsvox-notmuch--search-process-property nil)
        (set-process-sentinel process #'ignore)
        (when (process-live-p process) (delete-process process)))
      (when (buffer-live-p owner) (kill-buffer owner))
      (when (buffer-live-p parse-buffer) (kill-buffer parse-buffer)))))

(ert-deftest emacsvox-notmuch-refresh-failure-uses-notification-stream ()
  "A failed live, undisplayed owner warns even when success is silent."
  (let ((buffer (generate-new-buffer " *emacsvox-notmuch-failure-test*"))
        (properties
         `((,emacsvox-notmuch--search-process-property
            . (:kind refresh :interacted nil))))
        (emacsvox-notmuch-search-completion-style 'silent)
        events facts)
    (unwind-protect
        (emacsvox-notmuch-test--with-fake-search-process
            ('process buffer properties 'signal 1)
          (should (buffer-live-p buffer))
          (should-not (get-buffer-window buffer t))
          (cl-letf
              (((symbol-function 'tts-notify-icon)
                (lambda (icon) (push (list 'icon icon) events)))
               ((symbol-function 'tts-notify)
                (lambda (text &optional _)
                  (setq facts (copy-tree emacsvox-aural-submission-facts))
                  (push (list 'notify text) events))))
            (emacsvox--advice-notmuch-search-process-sentinel-after
             'process nil)))
      (when (buffer-live-p buffer) (kill-buffer buffer)))
    (should
     (equal
      (nreverse events)
      '((icon warn-user) (notify "Search refresh failed"))))
    (should
     (equal
      facts
      '(:role mail-view :mail-view-kind search
        :mail-action-kind refresh :events (refresh-failed))))
    (should-not
     (alist-get emacsvox-notmuch--search-process-property properties))))

(provide 'emacsvox-notmuch-tests)
;;; emacsvox-notmuch-tests.el ends here
