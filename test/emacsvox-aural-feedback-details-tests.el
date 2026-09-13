;;; emacsvox-aural-feedback-details-tests.el --- Recorded field review tests -*- lexical-binding: t; -*-
;;; Commentary:
;; Exercise real Notmuch formatting and native planning with device-free playback.
;;; Code:
(require 'emacsvox-aural-change-feedback-tests)
(require 'package)
(package-initialize)
(require 'notmuch)
(require 'emacsvox-notmuch)

(defun emacsvox-test--feedback-record ()
  "Capture a real Notmuch search presentation, with a multivoice count."
  (let ((formatter (symbol-function 'emacsvox-notmuch--format-search-field))
        (emacsvox-notmuch-search-result-fields '(authors subject date count tags))
        (emacsvox-use-icons t)
        prepared)
    (cl-letf (((symbol-function 'emacsvox-notmuch--format-search-field)
               (lambda (field result)
                 (let ((text (funcall formatter field result)))
                   (when (eq field 'count)
                     (put-text-property 0 1 'personality 'voice-bolden text)
                     (put-text-property (1- (length text)) (length text) 'personality 'voice-lighten text))
                   text)))
              ((symbol-function 'tts-speak) (lambda (text) (setq prepared text))))
      (emacsvox-notmuch--submit-search-result
       '(:authors "Alice, Bob" :subject "Meeting arrangements" :date_relative "Yesterday"
                  :matched 2 :total 5 :tags ("inbox" "unread"))
       (append (emacsvox-notmuch-thread-facts nil nil) '(:states (unread)))
       'navigation 'select-object))
    (let ((position 0) plans)
      (while (< position (length prepared))
        (let* ((plan (emacsvox-aural-concrete-plan-at position prepared))
               (end (next-single-property-change position emacsvox-aural-concrete-plan-property
                                                 prepared (length prepared))))
          (push (emacsvox-aural--freeze-presentation-plan
                 plan (substring prepared position end)) plans)
          (setq position end)))
      (emacsvox-aural--make-history-record (nreverse plans) nil 421))))

(defmacro emacsvox-test--with-feedback-report (&rest body)
  "Run BODY with a native Notmuch RECORD and selected REPORT buffer."
  (declare (indent 0) (debug t))
  `(emacsvox-test--with-home-context
    (with-current-buffer source
      (setq major-mode 'notmuch-search-mode)
      (setq-local voice-lock-mode t))
    (let* ((record (with-current-buffer source (emacsvox-test--feedback-record)))
           (emacsvox-aural-presentation-history (list record))
           (report (progn (emacsvox-aural-list-recent-feedback source)
                          (emacsvox-aural-recent-feedback-explain))))
      ,@body)))

(defun emacsvox-test--feedback-field (field)
  "Move to FIELD's heading in the selected report, returning its run indices."
  (goto-char (point-min))
  (re-search-forward (concat "^" (regexp-quote field) " ("))
  (beginning-of-line)
  (emacsvox-aural-feedback-details--target))

(ert-deftest emacsvox-aural-feedback-details-enter-selects-quiet-pinned-report ()
  "Enter selects a readable report; q restores the exact history cell."
  (emacsvox-test--with-feedback-report
   (should (eq (current-buffer) report))
   (should (derived-mode-p 'emacsvox-aural-feedback-details-mode))
   (should buffer-read-only)
   (emacsvox-aural-ui-help-quit)
   (emacsvox-aural-ui-goto-tabulated-column 3)
   (let ((origin (current-buffer)) (position (point)) spoken)
     (cl-letf (((symbol-function 'tts-speak) (lambda (text) (setq spoken text))))
       (call-interactively (key-binding (kbd "RET"))))
     (should (eq (current-buffer) report))
     (should (< (length spoken) 150))
     (should (string-prefix-p "Feedback details" spoken))
     (let ((before (buffer-string)))
       (setq emacsvox-aural-presentation-history nil)
       (with-current-buffer (get-buffer-create "*Help*") (let ((inhibit-read-only t)) (erase-buffer) (insert "Other help")))
       (should (equal before (buffer-string))))
     (call-interactively (key-binding (kbd "q")))
     (should (eq (current-buffer) origin))
     (should (= (point) position)))))

(ert-deftest emacsvox-aural-feedback-details-groups-voices-and-replays-original ()
  "Fields retain native voice spans and original ordered replay remains frozen."
  (emacsvox-test--with-feedback-report
   (let* ((indices (emacsvox-test--feedback-field "Message count"))
          (runs (emacsvox-aural-presentation-record-runs record)) played spoken)
     (should (> (length indices) 1))
     (should (> (length (delete-dups
                         (mapcar (lambda (i)
                                   (emacsvox-aural-concrete-content-voice-style
                                    (emacsvox-aural-concrete-plan-content (car (nth i runs)))))
                                 indices))) 1))
     (emacsvox-aural-feedback-details-toggle)
     (should (search-forward "Voice:" nil t))
     (should (string-match-p "from the text's voice annotation" (buffer-string)))
     (emacsvox-test--feedback-field "Message count")
     (cl-letf (((symbol-function 'tts-speak) (lambda (text) (setq spoken text))))
       (emacsvox-aural-feedback-details-next-line))
     (should (string-match-p "2 of 5" spoken))
     (let* ((plan (emacsvox-aural-concrete-plan-at 0 spoken))
            (original (car (nth (car indices) runs))))
       (should (equal (emacsvox-aural-concrete-content-voice-style
                       (emacsvox-aural-concrete-plan-content plan))
                      (emacsvox-aural-concrete-content-voice-style
                       (emacsvox-aural-concrete-plan-content original)))))
     (cl-letf (((symbol-function 'emacsvox-aural-preview-play-runs)
                (lambda (value &rest _) (setq played value)
                  (should emacsvox-aural--history-recording-inhibited))))
       (emacsvox-aural-feedback-details-play-field)
       (should (equal played (mapcar (lambda (i) (nth i runs)) indices)))
       (emacsvox-aural-feedback-details-play)
       (should (equal played runs)))
     (should (equal emacsvox-aural-presentation-history (list record))))))

(ert-deftest emacsvox-aural-feedback-details-preview-subject-and-after-count ()
  "Two field drafts preview together; the count cue occurs once at its boundary."
  (emacsvox-test--with-feedback-report
   (let* ((original (emacsvox-aural--history-value record))
          (baseline (emacsvox-aural-replan-runs (emacsvox-aural-presentation-record-runs record)))
          (subject-indices (emacsvox-test--feedback-field "Subject"))
          subject-editor count-indices proposed)
     (emacsvox-aural-feedback-details-change)
     (setq subject-editor (current-buffer))
     (should (equal (plist-get emacsvox-aural-change-feedback-selector :mode) 'notmuch-search-mode))
     (emacsvox-test--guided-choose "Change the content voice" "lighten")
     (pop-to-buffer report)
     (setq count-indices (emacsvox-test--feedback-field "Message count"))
     (emacsvox-aural-feedback-details-change)
     (emacsvox-test--guided-choose "Add a sound" "After content" "close-object")
     (should (eq (plist-get (car (plist-get (plist-get emacsvox-aural-change-feedback-render :after) :append)) :anchor)
                 'transition))
     (with-current-buffer report
       (setq proposed (emacsvox-aural-feedback-details--proposal-runs)))
     (should (= (length baseline) (length proposed)))
     (cl-loop for (plan . _) in proposed for index from 0
              for original-run in baseline
              do
              (let ((voice (emacsvox-aural-concrete-content-voice-request
                            (emacsvox-aural-concrete-plan-content plan))))
                (if (memq index subject-indices)
                    (should (eq voice 'lighten))
                  (should (equal voice (emacsvox-aural-concrete-content-voice-request
                                        (emacsvox-aural-concrete-plan-content (car original-run))))))))
     (let ((cue-positions
            (cl-loop for (plan . _) in proposed for index from 0
                     append (cl-loop for action in (emacsvox-aural-concrete-plan-after plan)
                                     when (eq (emacsvox-aural-concrete-action-cue action) 'close-object)
                                     collect index))))
       (should (equal cue-positions (last count-indices))))
     ;; Source adapters are re-resolved in place, not lost or duplicated.
     (should (equal (emacsvox-aural-concrete-plan-before (caar proposed))
                    (emacsvox-aural-concrete-plan-before (caar baseline))))
     (should (equal record original))
     (should-not emacsvox-aural-user-rules)
     (should-not emacsvox-aural-session-rules)
     (should-not (buffer-local-value 'emacsvox-aural-buffer-rules source))
     ;; Applying the count rule must have the same placement on a new native
     ;; presentation, not merely in our replay preview.
     (setq emacsvox-aural-change-feedback-scope 'buffer)
     (emacsvox-aural-change-feedback-apply)
     (should emacsvox-aural-change-feedback-applied)
     (let* ((next (with-current-buffer source (emacsvox-test--feedback-record)))
            (plans (emacsvox-aural-presentation-record-effective-plans next))
            (cues (cl-loop for plan in plans
                           append (cl-remove-if-not
                                   (lambda (action) (eq (emacsvox-aural-concrete-action-cue action) 'close-object))
                                   (emacsvox-aural-concrete-plan-after plan)))))
       (should (= (length cues) 1))
       (save-window-excursion
         (emacsvox-aural-feedback-details next)
         (emacsvox-test--feedback-field "Message count")
         (emacsvox-aural-feedback-details-change)
         (should (member "Replace a sound" (emacsvox-aural-change-feedback--operations)))
         (should (= (length (emacsvox-aural-change-feedback--components 'cue)) 1))))
     (pop-to-buffer report)
     (emacsvox-test--feedback-field "Subject")
     (emacsvox-aural-feedback-details-change)
     (should (eq (current-buffer) subject-editor))
     (should emacsvox-aural-change-feedback-render))))

(ert-deftest emacsvox-aural-feedback-details-span-targets-distinct-voice-only ()
  "A uniquely annotated span can change without broadening to its shared face."
  (emacsvox-test--with-feedback-report
   (let* ((indices (emacsvox-test--feedback-field "Message count"))
          (last-index (car (last indices))))
     (emacsvox-aural-feedback-details-toggle)
     (goto-char (point-min))
     (re-search-forward "^  Span 1\\.")
     (beginning-of-line)
     (should-error (emacsvox-aural-feedback-details-change) :type 'user-error)
     (re-search-forward (format "^  Span %d\\." (length indices)))
     (beginning-of-line)
     (emacsvox-aural-feedback-details-change)
     (should (eq (plist-get emacsvox-aural-change-feedback-selector :legacy-personality) 'voice-lighten))
     (should-not (plist-member emacsvox-aural-change-feedback-selector :legacy-face))
     (emacsvox-test--guided-choose "Change the content voice" "bolden")
     (with-current-buffer report
       (let ((proposal (emacsvox-aural-feedback-details--proposal-runs)))
         (should (eq (emacsvox-aural-concrete-content-voice-request
                      (emacsvox-aural-concrete-plan-content (car (nth last-index proposal)))) 'bolden))
         (should (eq (emacsvox-aural-concrete-content-voice-request
                      (emacsvox-aural-concrete-plan-content
                       (emacsvox-aural-feedback-details--plan last-index))) 'lighten)))))))

(ert-deftest emacsvox-aural-feedback-details-keeps-reports-and-drafts-separate ()
  "Opening another record cannot retarget an earlier field draft."
  (emacsvox-test--with-feedback-report
   (emacsvox-test--feedback-field "Subject")
   (emacsvox-aural-feedback-details-change)
   (let ((editor (current-buffer))
         (other (with-current-buffer source (emacsvox-test--feedback-record))))
     (emacsvox-aural-feedback-details other)
     (should-not (eq report (current-buffer)))
     (with-current-buffer editor
       (should (eq emacsvox-aural-change-feedback--review-buffer report))
       (should (eq emacsvox-aural-change-feedback-record record))))))

(ert-deftest emacsvox-aural-feedback-details-truncated-and-old-record-guards ()
  "Incomplete history cannot masquerade as comparable original/proposed output."
  (emacsvox-test--with-feedback-report
   (setf (emacsvox-aural-presentation-record-payload-truncated-p record) t)
   (should-error (emacsvox-aural-feedback-details-play) :type 'user-error)
   (emacsvox-test--feedback-field "Subject")
   (should-error (emacsvox-aural-feedback-details-change) :type 'user-error)
   (setf (emacsvox-aural-presentation-record-payload-truncated-p record) nil)
   (dolist (plan (emacsvox-aural-presentation-record-effective-plans record))
     (setf (emacsvox-aural-concrete-plan-context plan)
           (cl-loop for (key value) on (emacsvox-aural-concrete-plan-context plan) by #'cddr
                    unless (eq key :aural-source-compatibility-actions) append (list key value))))
   (should-error (emacsvox-aural-replan-runs (emacsvox-aural-presentation-record-runs record)) :type 'user-error)
   (let (played)
     (cl-letf (((symbol-function 'emacsvox-aural-preview-play-runs)
                (lambda (runs &rest _) (setq played runs))))
       (emacsvox-aural-feedback-details-play))
     (should played))))

(ert-deftest emacsvox-aural-feedback-details-home-explain-keeps-record-and-return-cell ()
  "Home explains its captured item quietly and q restores the exact Home cell."
  (emacsvox-test--with-feedback-report
   (emacsvox-aural source)
   (emacsvox-aural-home--goto 'explain)
   (emacsvox-aural-ui-goto-tabulated-column 2)
   (let ((home (current-buffer)) (position (point)) spoken)
     (with-current-buffer source (goto-char (point-max)))
     (cl-letf (((symbol-function 'tts-speak) (lambda (text) (setq spoken text))))
       (let ((noninteractive nil)) (call-interactively #'emacsvox-aural-home-explain)))
     (should (eq (window-buffer (selected-window)) report))
     (with-current-buffer report
       (should (eq record emacsvox-aural-feedback-details--record))
       (should-not emacsvox-aural-feedback-details--simulation)
       (should (string-match-p "Play original whole presentation" (buffer-string)))
       (should (< (length spoken) 150))
       (call-interactively (key-binding (kbd "q"))))
     (should (eq (window-buffer (selected-window)) home))
     (with-current-buffer home (should (= position (point)))))))

(ert-deftest emacsvox-aural-feedback-details-simulation-is-labelled-and-editable ()
  "An unrecorded shell item has a playable simulation, separate from history."
  (require 'shell)
  (require 'emacsvox-comint)
  (emacsvox-test--with-home-context
   (switch-to-buffer source)
   (erase-buffer)
   (shell-mode)
   (insert (propertize "user$ " 'font-lock-face 'comint-highlight-prompt))
   (goto-char 1)
   (let ((position (point)) report spoken played)
     (cl-letf (((symbol-function 'tts-speak) (lambda (text) (setq spoken text)))
               ((symbol-function 'completing-read) (lambda (&rest _) (error "No question expected"))))
       (let ((noninteractive nil)) (call-interactively #'emacsvox-aural-explain-presentation)))
     (setq report (window-buffer (selected-window)))
     (with-current-buffer report
       (should (derived-mode-p 'emacsvox-aural-feedback-details-mode))
       (should emacsvox-aural-feedback-details--simulation)
       (should (string-match-p "not recorded speech" spoken))
       (should (< (length spoken) 150))
       (should (string-match-p "Play simulation" (buffer-string)))
       (should (string-match-p "Open raw snapshot in a separate buffer" (buffer-string)))
       (should-not (string-match-p "Play original\\|Submitted:\\|Exact retained" (buffer-string)))
       (cl-letf (((symbol-function 'emacsvox-aural-preview-play-runs)
                  (lambda (runs &rest _) (setq played runs))))
         (call-interactively (key-binding (kbd "P"))))
       (should (equal (cadar played) "user$ "))
       (goto-char (text-property-not-all (point-min) (point-max) 'emacsvox-aural-feedback-target nil))
       (emacsvox-aural-feedback-details-change))
     (with-current-buffer (window-buffer (selected-window))
       (should emacsvox-aural-change-feedback--simulation)
       (should (string-match-p "Play simulated field" (buffer-string)))
       (should-not (string-match-p "Play original\\|Recent Feedback" (buffer-string)))
       (save-window-excursion
         (cl-letf (((symbol-function 'emacsvox-aural-ui-speak)
                    (lambda (text) (setq spoken text))))
           (emacsvox-aural-change-feedback-help))
         (should (string-match-p "O plays the simulated baseline" spoken))
         (should-not (string-match-p "original" spoken)))
       (should (eq (plist-get emacsvox-aural-change-feedback-selector :legacy-face) 'comint-highlight-prompt))
       (emacsvox-test--guided-choose "Change the content voice" "bolden")
       (cl-letf (((symbol-function 'emacsvox-aural-preview-play-runs)
                  (lambda (runs &rest _) (setq played runs))))
         (emacsvox-aural-change-feedback-preview-whole))
       (should (equal (cadar played) "user$ "))
       (should (eq (emacsvox-aural-concrete-content-voice-request
                    (emacsvox-aural-concrete-plan-content (caar played))) 'bolden)))
     (should-not emacsvox-aural-presentation-history)
     (should-not emacsvox-aural-user-rules)
     (with-current-buffer report (emacsvox-aural-ui-help-quit))
     (should (eq (window-buffer (selected-window)) source))
     (with-current-buffer source (should (= position (point)))))))

(ert-deftest emacsvox-aural-feedback-details-prefix-forces-simulation ()
  "An explicit occasion uses a simulation even when a current record exists."
  (emacsvox-test--with-feedback-report
   (switch-to-buffer source)
   (let ((current-prefix-arg '(4)) asked)
     (cl-letf (((symbol-function 'completing-read)
                (lambda (prompt &rest _) (setq asked prompt) "navigation")))
       (let ((noninteractive nil)) (call-interactively #'emacsvox-aural-explain-presentation)))
     (should (string-match-p "occasion" asked))
     (with-current-buffer (window-buffer (selected-window))
       (should emacsvox-aural-feedback-details--simulation)
       (should-not (eq record emacsvox-aural-feedback-details--record))))))

(ert-deftest emacsvox-aural-feedback-details-folds-content-and-single-span-controls ()
  "Collapsed fields hide their content; one span never creates a duplicate section."
  (emacsvox-test--with-feedback-report
   (let ((subject (emacsvox-test--feedback-field "Subject")) spoken)
     (should-not (string-match-p "Meeting arrangements\\|^Play field\\|  Span " (buffer-string)))
     (forward-line -1)
     (cl-letf (((symbol-function 'tts-speak) (lambda (text) (setq spoken text))))
       (emacsvox-aural-feedback-details-next-heading))
     (should (string-match-p "Subject" spoken))
     (should (eq (plist-get (get-text-property 0 'emacsvox-aural-facts spoken) :visibility) 'folded))
     (should-not (string-match-p "Meeting arrangements" spoken))
     (call-interactively (key-binding (kbd "RET")))
     (should (equal subject (emacsvox-aural-feedback-details--target)))
     (should (eq (emacsvox-aural-ui--control-visibility) 'expanded))
     (should (string-match-p "Meeting arrangements\nPlay field" (buffer-string)))
     (should-not (string-match-p "  Span " (buffer-string)))
     (should (= 1 (how-many "Meeting arrangements" (point-min) (point-max))))
     (call-interactively (key-binding (kbd "RET")))
     (should (equal subject (emacsvox-aural-feedback-details--target)))
     (should-not (string-match-p "Meeting arrangements\\|^Play field" (buffer-string))))
   (let ((count (emacsvox-test--feedback-field "Message count")))
     (emacsvox-aural-feedback-details-toggle)
     (re-search-forward "^  Span 2\\.")
     (beginning-of-line)
     (call-interactively (key-binding (kbd "RET")))
     (should (equal count (emacsvox-aural-feedback-details--target)))
     (should (eq (emacsvox-aural-ui--control-visibility) 'folded))
     (should-not (string-match-p "  Span " (buffer-string))))))

(ert-deftest emacsvox-aural-feedback-details-explains-only-field-winners-and-limitations ()
  "Object-wide rule lists cannot masquerade as each field's voice source."
  (emacsvox-test--with-feedback-report
   (let* ((authors (emacsvox-aural-feedback-details--plan (car (emacsvox-test--feedback-field "Authors"))))
          (tags (emacsvox-aural-feedback-details--plan (car (emacsvox-test--feedback-field "Tags"))))
          (rules '((:id saved-tags :origin user) (:id unrelated-subject :origin session))))
     ;; Native plans carry object-wide provenance, but content tracks its winner.
     (setf (emacsvox-aural-concrete-plan-rule-provenance authors) rules
           (emacsvox-aural-concrete-plan-rule-provenance tags) rules
           (emacsvox-aural-concrete-content-provenance (emacsvox-aural-concrete-plan-content tags))
           '((voice . saved-tags))
           (emacsvox-aural-concrete-content-voice-provenance (emacsvox-aural-concrete-plan-content tags))
           '((preset . saved-tags))
           (emacsvox-aural-concrete-plan-degradations tags)
           '((:reason unsupported-voice-dimension :adapter omnivox :dimension family :requested outloud-v6)))
     (emacsvox-test--feedback-field "Authors")
     (emacsvox-aural-feedback-details-toggle)
     (should (string-match-p "from the visual face" (buffer-string)))
     (should-not (string-match-p "personal override\\|outloud-v6" (buffer-string)))
     (emacsvox-test--feedback-field "Tags")
     (emacsvox-aural-feedback-details-toggle)
     (should (string-match-p "from your personal override" (buffer-string)))
     (should (string-match-p "Limitation: omnivox could not use the requested family outloud-v6" (buffer-string)))
     (should-not (string-match-p "unrelated-subject\\|saved-tags\\|session override\\|Rules involved" (buffer-string)))
     (emacsvox-aural-feedback-details-toggle)
     (should-not (string-match-p "personal override\\|outloud-v6" (buffer-string))))))

(ert-deftest emacsvox-aural-feedback-details-debug-is-separate-pinned-and-quiet ()
  "Raw data opens quietly outside the report, and q restores its exact position."
  (emacsvox-test--with-feedback-report
   (goto-char (point-min))
   (search-forward "Open raw snapshot")
   (let ((position (point)) (contents (buffer-string)) debug spoken)
     (cl-letf (((symbol-function 'tts-speak) (lambda (text) (setq spoken text))))
       (call-interactively (key-binding (kbd "RET"))))
     (setq debug (window-buffer (selected-window)))
     (should-not (eq debug report))
     (with-current-buffer debug
       (should buffer-read-only)
       (should (string-match-p "#s(emacsvox-aural-presentation-record" (buffer-string)))
       (should (< (length spoken) 100))
       (should (string-prefix-p "Debug details" spoken))
       (call-interactively (key-binding (kbd "q"))))
     (should (eq (window-buffer (selected-window)) report))
     (with-current-buffer report
       (should (= position (point)))
       (should (equal contents (buffer-string)))
       (should-not (string-match-p "#s(" (buffer-string)))
       (should (eq record emacsvox-aural-feedback-details--record))
       (emacsvox-aural-feedback-details-debug))
     (should (eq debug (window-buffer (selected-window))))
     (should (equal (list record) emacsvox-aural-presentation-history)))))

(ert-deftest emacsvox-aural-feedback-details-play-button-adds-no-confirmation-cue ()
  "Enter plays exactly the selected field, retaining only its captured sounds."
  (require 'emacsvox-advice)
  (emacsvox-test--with-feedback-report
   (let* ((indices (emacsvox-test--feedback-field "Subject"))
          (plan (emacsvox-aural-feedback-details--plan (car indices)))
          (cue (emacsvox-aural--make-concrete-action :kind 'cue :cue 'close-object)))
     (dolist (after (list nil (list cue)))
       (setf (emacsvox-aural-concrete-plan-after plan) after)
       (setq emacsvox-aural-feedback-details--expanded (list indices))
       (emacsvox-aural-feedback-details--render indices)
       (search-forward "Play field")
       (backward-char 3)
       (let (events)
         (cl-letf (((symbol-function 'emacsvox-icon)
                    (lambda (icon) (push (list 'extra-cue icon) events)))
                   ((symbol-function 'emacsvox-aural-preview-play-runs)
                    (lambda (runs &rest _) (push (list 'play runs) events))))
           (let ((noninteractive nil))
             (call-interactively (key-binding (kbd "RET")))))
         (should (equal (mapcar #'car events) '(play)))
         (should (equal (cadar events)
                        (mapcar (lambda (i) (nth i (emacsvox-aural-presentation-record-runs record))) indices)))
         (should (equal (emacsvox-aural-concrete-plan-after (caar (cadar events))) after)))))))

(ert-deftest emacsvox-aural-feedback-details-visibility-is-aural-metadata ()
  "Headings carry visibility cues and optional speech without literal state labels."
  (require 'emacsvox-advice)
  (emacsvox-test--with-feedback-report
   (emacsvox-aural-register-workflow-provider)
   (let (prepared)
     (cl-letf (((symbol-function 'tts-speak)
                (lambda (text) (setq prepared (emacsvox-aural-prepare-text text)))))
       (cl-labels
           ((check (command visibility occasion)
              (setq prepared nil)
              (funcall command)
              (let* ((plan (emacsvox-aural-concrete-plan-at 0 prepared))
                     (cues (emacsvox-aural-concrete-plan-before plan)))
                (should (eq (plist-get (emacsvox-aural-concrete-plan-facts plan) :visibility) visibility))
                (should (eq (plist-get (emacsvox-aural-concrete-plan-context plan) :occasion) occasion))
                (should (equal (mapcar #'emacsvox-aural-concrete-action-cue cues)
                               (list (if (eq visibility 'expanded) 'open-object 'close-object)))))
              (should-not (string-match-p "\\b\\(expanded\\|collapsed\\)\\b" (buffer-string)))))
         (emacsvox-test--feedback-field "Subject")
         (forward-line -1)
         (check #'emacsvox-aural-feedback-details-next-heading 'folded 'navigation)
         (check (lambda () (call-interactively (key-binding (kbd "RET")))) 'expanded 'state-change)
         (forward-line -1)
         (check #'emacsvox-aural-feedback-details-next-heading 'expanded 'navigation)
         (check (lambda () (call-interactively (key-binding (kbd "RET")))) 'folded 'state-change)
         (forward-line -1)
         (check #'emacsvox-aural-feedback-details-next-line 'folded 'navigation)
         (emacsvox-test--feedback-field "Authors")
         (check #'emacsvox-aural-feedback-details-next-button 'folded 'navigation)
         (emacsvox-aural-set-enabled-feature-fragments '(aural-panel-state-labels))
         (check #'emacsvox-aural-feedback-details-speak-line 'folded 'navigation)
         (should (equal (mapcar #'emacsvox-aural-concrete-action-text
                                (emacsvox-aural-concrete-plan-after
                                 (emacsvox-aural-concrete-plan-at 0 prepared))) '("collapsed"))))))))

(provide 'emacsvox-aural-feedback-details-tests)
;;; emacsvox-aural-feedback-details-tests.el ends here
