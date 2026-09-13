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
     (re-search-forward (format "^  Span %d\\." (1+ (car indices))))
     (beginning-of-line)
     (should-error (emacsvox-aural-feedback-details-change) :type 'user-error)
     (re-search-forward (format "^  Span %d\\." (1+ last-index)))
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

(provide 'emacsvox-aural-feedback-details-tests)
;;; emacsvox-aural-feedback-details-tests.el ends here
