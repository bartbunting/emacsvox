;;; omnivox-explanation-tests.el --- Qualified setting explanations -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Commentary:
;; Real control framing with deterministic timers and independent wire fixtures.
;;; Code:
(require 'omnivox-parameters-tests)
(require 'omnivox-native-preview-tests)

(defun omnivox-explanation-test--draft (process callback &optional current)
  (omnivox-parameters--explain-draft process (omnivox-native-test--entry "paul-main") callback current))

(defun omnivox-explanation-test--reply (process &optional key)
  (let ((response (omnivox-native-test--message (or key :explain_response))))
    (setf (plist-get response :request_id) (plist-get (cdr (assq process omnivox-parameters-test--writes)) :request_id))
    (omnivox-parameters-test--reply process response)))

(defun omnivox-explanation-test--audio ()
  (let ((result (plist-get (omnivox-native-test--message :applied_explanation) :result)))
    (list :choice_id (plist-get result :choice_id) :realized (plist-get result :realized)
          :native_application (list :status "applied" :plan_id (plist-get result :plan_id)
                                    :identity (plist-get result :identity) :masked_parameters [] :reason :null))))

(defun omnivox-explanation-test--applied (process callback)
  (omnivox-parameters--explain-applied
   process (list (process-name process) (process-get process 'tts--speech-process-generation))
   (omnivox-explanation-test--audio) callback))

(ert-deftest omnivox-explanation-draft-is-private-asynchronous-and-frozen ()
  (omnivox-parameters-test--with-lanes
   (omnivox-native-test--bundle speaker)
   (let ((entry (omnivox-native-test--entry "paul-main")))
     (omnivox-parameters--explain-draft speaker entry (lambda (r) (push r results)))
     (setf (plist-get (car (plist-get (plist-get entry :voice) :choices)) :id) "later-edit"))
   (should-not results)
   (let* ((request (cdar omnivox-parameters-test--writes)) (source (plist-get request :source)))
     (should (equal (plist-get request :type) "explain_voice_parameters_v1"))
     (should (equal (plist-get source :mode) "draft"))
     (should-not (plist-member source :text))
     (should (eq (plist-get source :expected_base_rate) :null))
     (should (equal (plist-get (plist-get source :selection) :choice_id) "paul-main"))
     (should (plist-member (aref (plist-get (plist-get source :voice) :choices) 3) :native)))
   (omnivox-explanation-test--reply speaker)
   (should-not results)
   (omnivox-parameters-test--drain)
   (should (eq (plist-get (car results) :status) 'ready))
   (should (equal (plist-get (plist-get (car results) :explanation) :evidence) "planned"))
   (should-not (omnivox-parameters--cached speaker "dectalk" "paul"))
   (should (zerop (hash-table-count (omnivox--pending-requests speaker))))))

(ert-deftest omnivox-explanation-common-only-draft-uses-native-wire-form ()
  (omnivox-parameters-test--with-lanes
   (process-put speaker omnivox--control-capabilities-property (list :features omnivox-native-test--features))
   (omnivox-parameters--explain-draft
    speaker (omnivox-native-test--common (omnivox-native-test--entry "paul-main")) #'ignore)
   (mapc (lambda (row) (should (eq (plist-get row :native) :null)))
         (plist-get (plist-get (plist-get (cdar omnivox-parameters-test--writes) :source) :voice) :choices))))

(ert-deftest omnivox-explanation-shares-admission-with-catalogue-but-not-other-lane ()
  (omnivox-parameters-test--with-lanes
   (dolist (p (list speaker notification)) (omnivox-native-test--bundle p))
   (omnivox-explanation-test--draft speaker (lambda (r) (push r results)))
   (omnivox-parameters-test--request speaker (lambda (r) (push r results)))
   (omnivox-explanation-test--applied notification (lambda (r) (push r results)))
   (should (= 2 (length omnivox-parameters-test--writes)))
   (omnivox-parameters-test--drain)
   (should (eq (plist-get (car results) :status) 'busy))
   (omnivox-explanation-test--reply speaker)
   (omnivox-explanation-test--reply notification :applied_explanation)
   (omnivox-parameters-test--drain)
   (should (= 2 (cl-count 'ready results :key (lambda (r) (plist-get r :status)))))))

(ert-deftest omnivox-explanation-applied-correlates-all-historical-identities ()
  (dolist (mutate (list (lambda (r) (setf (plist-get r :evidence) "planned"))
                       (lambda (r) (setf (plist-get r :plan_id) "foreign-plan"))
                       (lambda (r) (setf (plist-get r :choice_id) "other-row"))
                       (lambda (r) (setf (plist-get (plist-get r :realized) :voice_id) "betty"))
                       (lambda (r) (setf (plist-get (plist-get r :identity) :runtime_generation) 8))
                       (lambda (r) (setf (plist-get (aref (plist-get r :parameters) 0) :masked_native) t
                                         (plist-get (aref (plist-get r :parameters) 0) :origin) "context_mapping"))))
    (omnivox-parameters-test--with-lanes
     (omnivox-native-test--bundle speaker)
     (omnivox-explanation-test--applied speaker (lambda (r) (push r results)))
     (let ((response (omnivox-native-test--message :applied_explanation)))
       (setf (plist-get response :request_id) (plist-get (cdar omnivox-parameters-test--writes) :request_id))
       (funcall mutate (plist-get response :result))
       (omnivox-parameters-test--reply speaker response))
     (omnivox-parameters-test--drain)
     (should (eq (plist-get (car results) :status) 'failed)))))

(ert-deftest omnivox-explanation-strict-values-origins-and-readback ()
  (let* ((row (car (plist-get (plist-get (omnivox-native-test--entry) :voice) :choices)))
         (expected (list :choice-id "paul-main" :selector (plist-get row :selector) :native (plist-get row :native))))
    (dolist (value '(0 :false t :null "soft"))
      (let ((response (omnivox-native-test--message :explain_response)))
        (setf (plist-get (aref (plist-get (plist-get response :result) :parameters) 0) :value) value)
        (should (omnivox--native-explanation response expected))))
    (dolist (mutate (list (lambda (p) (setf (plist-get p :value) nil))
                         (lambda (p) (setf (plist-get p :value) 1.0e+INF))
                         (lambda (p) (setf (plist-get p :value) (expt 2 64)))
                         (lambda (p) (setf (plist-get p :read_back) t))
                         (lambda (p) (setf (plist-get p :masked_native) t))
                         (lambda (p) (setf (plist-get p :origin) "future_origin"))))
      (let ((response (omnivox-native-test--message :explain_response)))
        (funcall mutate (aref (plist-get (plist-get response :result) :parameters) 0))
        (should-error (omnivox--native-explanation response expected))))))

(ert-deftest omnivox-explanation-expired-plan-and-busy-remain-explicit ()
  (omnivox-parameters-test--with-lanes
   (omnivox-native-test--bundle speaker)
   (omnivox-explanation-test--applied speaker (lambda (r) (push r results)))
   (omnivox-explanation-test--reply speaker :expired_explanation)
   (omnivox-parameters-test--drain)
   (should (equal (plist-get (car results) :reason) "plan_expired"))
   (omnivox-explanation-test--draft speaker (lambda (r) (push r results)))
   (let ((response (omnivox-native-test--message :explain_response)))
     (setf (plist-get response :request_id) (plist-get (cdar omnivox-parameters-test--writes) :request_id)
           (plist-get response :result) '(:status "busy" :retry_after_ms 50))
     (omnivox-parameters-test--reply speaker response))
   (omnivox-parameters-test--drain)
   (should (eq (plist-get (car results) :status) 'busy))
   (should (= 2 (length omnivox-parameters-test--writes)))))

(ert-deftest omnivox-explanation-stale-worker-or-detached-view-cannot-receive-ready ()
  (omnivox-parameters-test--with-lanes
   (omnivox-native-test--bundle speaker)
   (omnivox-explanation-test--applied speaker (lambda (r) (push r results)))
   (omnivox-explanation-test--reply speaker :applied_explanation)
   (process-put speaker 'tts--speech-process-generation 99)
   (omnivox-parameters-test--drain)
   (should (eq (plist-get (car results) :status) 'stale))
   (let ((waiter (omnivox-explanation-test--draft speaker (lambda (_) (ert-fail "Detached view called")))))
     (omnivox-parameters--cancel waiter)
     (omnivox-explanation-test--reply speaker)
     (omnivox-parameters-test--drain))
   (omnivox-parameters--explain-applied speaker '("old-worker" 1) (omnivox-explanation-test--audio)
                                        (lambda (r) (push r results)))
   (omnivox-parameters-test--drain)
   (should (eq (plist-get (car results) :status) 'stale))
   (should (= 2 (length omnivox-parameters-test--writes)))))

(ert-deftest omnivox-explanation-unsupported-is-deferred-without-any-write ()
  (omnivox-parameters-test--with-lanes
   (omnivox-explanation-test--draft speaker (lambda (r) (push r results)))
   (should-not results)
   (should-not omnivox-parameters-test--writes)
   (omnivox-parameters-test--drain)
   (should (eq (plist-get (car results) :status) 'unsupported))))

(ert-deftest omnivox-explanation-timeout-releases-admission-and-swallows-late-errors ()
  (omnivox-parameters-test--with-lanes
   (omnivox-native-test--bundle speaker)
   (let* ((waiter (omnivox-explanation-test--draft speaker (lambda (r) (push r results))))
          (query (omnivox-parameters--waiter-operation waiter))
          (id (omnivox-parameters--query-pending query)))
     (omnivox-parameters-test--tick (omnivox-parameters--query-timer query))
     (omnivox-parameters-test--drain)
     (should (eq (plist-get (car results) :status) 'timeout))
     (omnivox-parameters-test--reply speaker (list :protocol_version 1 :request_id id :type "error"
                                                 :code "cancelled" :message "Late error"))
     (should-not (process-get speaker 'omnivox-parameters--queries))
     (should (zerop (hash-table-count (omnivox--pending-requests speaker)))))))

(ert-deftest omnivox-explanation-rendering-does-not-invent-known-values-or-readback ()
  (let* ((response (list :status 'ready :explanation (plist-get (omnivox-native-test--message :explain_response) :result)))
         (parameters (plist-get (plist-get response :explanation) :parameters)))
    (setf (plist-get (aref parameters 0) :value) :null
          (plist-get (aref parameters 1) :value) :false)
    (let ((text (emacsvox-aural-voice-editor--explanation-text response)))
      (should (string-match-p "Planned settings" text))
      (should (string-match-p "ri: value unknown" text))
      (should (string-match-p "sm: false" text))
      (should-not (string-match-p "read back from the engine" text)))
    (setf (plist-get response :explanation) (plist-get (omnivox-native-test--message :applied_explanation) :result))
    (should (string-match-p "read back from the engine" (emacsvox-aural-voice-editor--explanation-text response)))))

(defun omnivox-explanation-test--context (process)
  (let* ((entry (omnivox-native-test--entry "paul-main")) (voice (plist-get entry :voice))
         (snapshot (list :definition (plist-get voice :shared) :language (plist-get voice :language)
                         :choices (plist-get voice :choices)
                         :selectors (emacsvox-aural-voice-data--selectors (plist-get voice :choices)))))
    (list :draft (emacsvox-aural-voice-drafts--make :working snapshot) :palette 'acss-default
          :tuning-choice "paul-main" :policy '(:engine-order ("dectalk") :fallback (:engines ("espeak")))
          :preview-result (list :speech-connection (list (process-name process) (process-get process 'tts--speech-process-generation))
                                :results (list (list :request-snapshot entry :last-started (omnivox-explanation-test--audio)))))))

(ert-deftest omnivox-explanation-view-displays-result-and-rejects-changed-draft ()
  (omnivox-parameters-test--with-lanes
   (omnivox-native-test--bundle speaker)
   (let ((tts-speaker-process speaker) (context (omnivox-explanation-test--context speaker))
         ;; Mode setup is independent of the read-only query being observed.
         (after-change-major-mode-hook (remove #'tts-apply-punctuation-mode-policy after-change-major-mode-hook)))
     (unwind-protect
         (save-window-excursion
           (emacsvox-aural-voice-editor--explain context nil)
           (with-current-buffer "*Voice engine settings*" (should (string-match-p "Checking" (buffer-string))))
           (omnivox-explanation-test--reply speaker)
           (omnivox-parameters-test--drain)
           (with-current-buffer "*Voice engine settings*"
             (should (string-match-p "Planned settings" (buffer-string)))
             (should (string-match-p "requested 55" (buffer-string))))
           (emacsvox-aural-voice-editor--explain context nil)
           (cl-incf (emacsvox-aural-voice-draft-revision (plist-get context :draft)))
           (omnivox-explanation-test--reply speaker)
           (omnivox-parameters-test--drain)
           (with-current-buffer "*Voice engine settings*"
             (should (string-match-p "draft changed" (buffer-string)))
             (should-not (string-prefix-p "Planned settings" (buffer-string)))))
       (when (get-buffer "*Voice engine settings*") (kill-buffer "*Voice engine settings*"))))))

(ert-deftest omnivox-explanation-view-preserves-applied-request-across-edits-and-detaches-on-kill ()
  (omnivox-parameters-test--with-lanes
   (omnivox-native-test--bundle speaker)
   (let ((tts-speaker-process speaker) (context (omnivox-explanation-test--context speaker))
         (after-change-major-mode-hook (remove #'tts-apply-punctuation-mode-policy after-change-major-mode-hook)))
     (unwind-protect
         (save-window-excursion
           (emacsvox-aural-voice-editor--explain context t)
           (cl-incf (emacsvox-aural-voice-draft-revision (plist-get context :draft)))
           (setf (plist-get context :preview-result) nil)
           (omnivox-explanation-test--reply speaker :applied_explanation)
           (omnivox-parameters-test--drain)
           (with-current-buffer "*Voice engine settings*"
             (should (string-match-p "Applied settings" (buffer-string)))
             (should (string-match-p "requested 55" (buffer-string))))
           (emacsvox-aural-voice-editor--explain context nil)
           (let ((waiter (buffer-local-value 'emacsvox-aural-voice-editor--explanation-waiter
                                            (get-buffer "*Voice engine settings*"))))
             (kill-buffer "*Voice engine settings*")
             (should (omnivox-parameters--waiter-cancelled waiter)))
           (omnivox-explanation-test--reply speaker)
           (omnivox-parameters-test--drain)
           (should-not (get-buffer "*Voice engine settings*")))
       (when (get-buffer "*Voice engine settings*") (kill-buffer "*Voice engine settings*"))))))

(ert-deftest omnivox-explanation-duplicate-and-foreign-wire-evidence-fails-closed ()
  (omnivox-parameters-test--with-lanes
   (omnivox-native-test--bundle speaker)
   (omnivox-explanation-test--draft speaker (lambda (r) (push r results)))
   (let* ((response (omnivox-native-test--message :explain_response))
          (_ (setf (plist-get response :request_id) (plist-get (cdar omnivox-parameters-test--writes) :request_id)))
          (text (replace-regexp-in-string "\"evidence\":\"planned\"" "\"evidence\":\"planned\",\"evidence\":\"planned\""
                                           (json-serialize response) t t)))
     (omnivox--handle-control-line speaker (concat omnivox-control-event-prefix (base64-encode-string text t))))
   (omnivox-parameters-test--drain)
   (should (eq (plist-get (car results) :status) 'failed))))

(ert-deftest omnivox-explanation-details-link-opens-the-selected-choice ()
  (omnivox-parameters-test--with-lanes
   (omnivox-native-test--bundle speaker)
   (let ((tts-speaker-process speaker) (context (omnivox-explanation-test--context speaker))
         (after-change-major-mode-hook (remove #'tts-apply-punctuation-mode-policy after-change-major-mode-hook)))
     (unwind-protect
         (save-window-excursion
           (with-temp-buffer
             (setq emacsvox-aural-voice-editor--context context)
             (emacsvox-aural-voice-editor-details))
           (with-current-buffer "*Voice editor details*"
             (goto-char (point-min))
             (re-search-forward "Explain planned settings for a choice")
             (button-activate (button-at (match-beginning 0))))
           (should (= 1 (length omnivox-parameters-test--writes)))
           (omnivox-explanation-test--reply speaker)
           (omnivox-parameters-test--drain)
           (with-current-buffer "*Voice engine settings*"
             (should (string-prefix-p "Planned settings" (buffer-string)))
             (when (display-graphic-p)
               (redisplay t)
               (should (get-buffer-window (current-buffer))))))
       (dolist (name '("*Voice editor details*" "*Voice engine settings*"))
         (when (get-buffer name) (kill-buffer name)))))))

(ert-deftest omnivox-explanation-view-rejects-a-replaced-selected-worker ()
  (omnivox-parameters-test--with-lanes
   (omnivox-native-test--bundle speaker)
   (let ((tts-speaker-process speaker) (context (omnivox-explanation-test--context speaker))
         (after-change-major-mode-hook (remove #'tts-apply-punctuation-mode-policy after-change-major-mode-hook)))
     (unwind-protect
         (save-window-excursion
           (emacsvox-aural-voice-editor--explain context nil)
           (omnivox-explanation-test--reply speaker)
           (setq tts-speaker-process notification)
           (omnivox-parameters-test--drain)
           (with-current-buffer "*Voice engine settings*"
             (should (string-match-p "Selected speech connection changed" (buffer-string)))
             (should-not (string-prefix-p "Planned settings" (buffer-string)))))
       (when (get-buffer "*Voice engine settings*") (kill-buffer "*Voice engine settings*"))))))

(provide 'omnivox-explanation-tests)
;;; omnivox-explanation-tests.el ends here
