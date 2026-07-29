;;; emacsvox-vertico-tests.el --- Vertico advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'vertico)
(load (expand-file-name "../lisp/emacsvox-vertico.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-vertico-advice-is-current-and-direct ()
  "Current Vertico targets use native advice directly."
  (dolist (entry emacsvox-vertico--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-vertico-insert-calls-original-once ()
  "Vertico insertion advice preserves the result and calls once."
  (with-temp-buffer
    (let ((calls 0))
      (cl-letf
          (((symbol-function 'emacsvox-speak-region-content)
            (lambda (&rest _) "candidate"))
           ((symbol-function 'emacsvox-aural-submit) #'ignore))
        (should
         (eq 'inserted
             (emacsvox--advice-vertico-insert-around
              (lambda ()
                (cl-incf calls)
                (insert "candidate")
                'inserted))))
        (should (= calls 1))))))

(ert-deftest emacsvox-vertico-acceptance-carries-candidate-semantics ()
  "Accepted-candidate content and cue share one semantic submission."
  (with-temp-buffer
    (let ((vertico--index 2)
          bounds
          captured)
      (cl-letf
          (((symbol-function 'emacsvox-speak-region-content)
            (lambda (start end)
              (setq bounds (list start end))
              (buffer-substring start end)))
           ((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (setq captured (cons content arguments))))
           ((symbol-function 'emacsvox-icon)
            (lambda (&rest _)
              (ert-fail "Normal acceptance used the legacy icon path")))
           ((symbol-function 'emacsvox-speak-region)
            (lambda (&rest _)
              (ert-fail "Normal acceptance used legacy region speech"))))
        (emacsvox--advice-vertico-insert-around
         (lambda () (insert "candidate"))))
      (should (equal bounds '(1 10)))
      (pcase-let* ((`(,content . ,arguments) captured)
                   (facts (plist-get arguments :facts))
                   (actions
                    (plist-get arguments :compatibility-actions)))
        (should (equal content "candidate"))
        (should (eq (plist-get facts :role) 'candidate))
        (should (equal (plist-get facts :events) '(accepted)))
        (should (equal (plist-get facts :states) '(selected)))
        (should (= (plist-get facts :completion-index) 2))
        (should (eq (plist-get arguments :module) 'vertico))
        (should (eq (plist-get arguments :occasion) 'state-change))
        (should
         (equal
          (mapcar
           #'emacsvox-aural-compatibility-action-value
           actions)
          '(complete)))))))

(ert-deftest emacsvox-vertico-acceptance-preserves-region-content ()
  "Accepted-candidate speech preserves bounds, properties, and return value."
  (with-temp-buffer
    (insert "prefix ")
    (let ((vertico--index 2)
          (emacsvox-speak-voice-annotated-paragraphs t)
          captured)
      (should
       (eq
        'inserted
        (cl-letf
            (((symbol-function 'emacsvox-aural-submit)
              (lambda (content &rest arguments)
                (setq captured (cons content arguments))))
             ((symbol-function 'emacsvox-icon)
              (lambda (&rest _)
                (ert-fail "Normal acceptance used the legacy icon path")))
             ((symbol-function 'tts-speak)
              (lambda (&rest _)
                (ert-fail "Normal acceptance used direct speech"))))
          (emacsvox--advice-vertico-insert-around
           (lambda ()
             (insert (propertize "candidate" 'personality 'voice-lighten))
             'inserted)))))
      (pcase-let* ((`(,spoken . ,arguments) captured)
                   (actions
                    (plist-get arguments :compatibility-actions)))
        (should (equal spoken "candidate"))
        (should
         (eq (get-text-property 0 'personality spoken) 'voice-lighten))
        (should
         (equal
          (mapcar
           #'emacsvox-aural-compatibility-action-value
           actions)
          '(complete))))
      (should (equal (buffer-string) "prefix candidate"))
      (should
       (eq
        (get-text-property 7 'personality (buffer-string))
        'voice-lighten)))))

(ert-deftest emacsvox-vertico-acceptance-annotates-paragraphs-before-speech ()
  "Accepted multiline text retains region-reader paragraph annotation."
  (with-temp-buffer
    (let ((vertico--index 2)
          (emacsvox-speak-paragraph-personality 'voice-animate)
          captured)
      (setq-local emacsvox-speak-voice-annotated-paragraphs nil)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest _) (setq captured content)))
           ((symbol-function 'emacsvox-icon)
            (lambda (&rest _)
              (ert-fail "Normal acceptance used the legacy icon path")))
           ((symbol-function 'tts-speak)
            (lambda (&rest _)
              (ert-fail "Normal acceptance used direct speech"))))
        (emacsvox--advice-vertico-insert-around
         (lambda () (insert "first\n\nsecond"))))
      (should emacsvox-speak-voice-annotated-paragraphs)
      (should (equal captured "first\n\nsecond"))
      (should
       (eq (get-text-property 7 'personality captured) 'voice-animate))
      (should
       (eq (get-text-property 8 'personality (buffer-string))
           'voice-animate)))))

(ert-deftest emacsvox-vertico-empty-acceptance-keeps-region-reader-behavior ()
  "An empty insertion still cues and sends an empty speech request."
  (with-temp-buffer
    (let ((vertico--index 2)
          events)
      (setq-local emacsvox-speak-voice-annotated-paragraphs nil)
      (cl-letf
          (((symbol-function 'emacsvox-icon)
            (lambda (icon) (push (list 'icon icon) events)))
           ((symbol-function 'tts-speak)
            (lambda (text) (push (list 'speak text) events))))
        (emacsvox--advice-vertico-insert-around (lambda () 'unchanged)))
      (should
       (equal
        (nreverse events)
        '((icon complete) (speak ""))))
      (should emacsvox-speak-voice-annotated-paragraphs))))

(ert-deftest emacsvox-vertico-large-acceptance-keeps-windowful-fallback ()
  "An oversized insertion retains cue order and the windowful fallback."
  (with-temp-buffer
    (let ((vertico--index 2)
          (ems--large-text-size 3)
          events)
      (setq-local emacsvox-speak-voice-annotated-paragraphs nil)
      (cl-letf
          (((symbol-function 'emacsvox-icon)
            (lambda (icon) (push (list 'icon icon) events)))
           ((symbol-function 'tts-speak)
            (lambda (&rest _)
              (ert-fail "Oversized insertion reached direct speech")))
           ((symbol-function 'emacsvox-speak-windowful)
            (lambda ()
              (interactive)
              (push '(windowful) events))))
        (emacsvox--advice-vertico-insert-around
         (lambda () (insert "large"))))
      (should
       (equal
        (nreverse events)
        '((icon complete) (windowful))))
      (should-not emacsvox-speak-voice-annotated-paragraphs))))

(ert-deftest emacsvox-vertico-candidate-navigation-submits-once ()
  "Candidate navigation submits trimmed text and its conditional cue once."
  (dolist
      (case
       '((-1 select-object)
         (2 select-object)
         (1 nil)))
    (with-temp-buffer
      (let ((vertico--index 2)
            (vertico--base "pre")
            captured)
        (setq-local
         emacsvox-vertico--prev-candidate "old"
         emacsvox-vertico--prev-index (car case))
        (cl-letf
            (((symbol-function 'vertico--candidate)
              (lambda (&optional _highlight) "precandidate"))
             ((symbol-function 'emacsvox-aural-submit)
              (lambda (content &rest arguments)
                (setq captured (cons content arguments))
                'submission)))
          (emacsvox--advice-vertico--exhibit-after))
        (pcase-let* ((`(,content . ,arguments) captured)
                     (facts (plist-get arguments :facts))
                     (actions
                      (plist-get arguments :compatibility-actions)))
          (should (equal content "candidate"))
          (should (eq (plist-get facts :role) 'candidate))
          (should (equal (plist-get facts :events) '(focus-entered)))
          (should (equal (plist-get facts :states) '(selected)))
          (should (= (plist-get facts :completion-index) 2))
          (should (eq (plist-get arguments :module) 'vertico))
          (should (eq (plist-get arguments :occasion) 'navigation))
          (should
           (equal
            (mapcar
             #'emacsvox-aural-compatibility-action-value
             actions)
            (when (cadr case) (list (cadr case))))))
        (should
         (equal emacsvox-vertico--prev-candidate "candidate"))
        (should (= emacsvox-vertico--prev-index 2))))))

(ert-deftest emacsvox-vertico-empty-candidate-keeps-legacy-fallback ()
  "An empty trimmed candidate still cues and calls legacy speech."
  (with-temp-buffer
    (let ((vertico--index 2)
          (vertico--base "pre")
          events)
      (setq-local
       emacsvox-vertico--prev-candidate "old"
       emacsvox-vertico--prev-index -1)
      (cl-letf
          (((symbol-function 'vertico--candidate)
            (lambda (&optional _highlight) "pre"))
           ((symbol-function 'emacsvox-aural-submit)
            (lambda (&rest _)
              (ert-fail "Empty candidate entered native submission")))
           ((symbol-function 'emacsvox-icon)
            (lambda (icon) (push (list 'icon icon) events)))
           ((symbol-function 'tts-speak)
            (lambda (text) (push (list 'speak text) events))))
        (emacsvox--advice-vertico--exhibit-after))
      (should
       (equal
        (nreverse events)
        '((icon select-object) (speak ""))))
      (should (equal emacsvox-vertico--prev-candidate ""))
      (should (= emacsvox-vertico--prev-index 2)))))

(ert-deftest emacsvox-vertico-native-candidate-presents-one-transaction ()
  "Candidate voice, cue order, and icon policy survive native submission."
  (dolist (icons-enabled '(t nil))
    (let ((vertico--index 2)
          (emacsvox-aural-active-scheme 'default)
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
         (emacsvox-vertico--submit-candidate-feedback
          (emacsvox-vertico-candidate-facts)
          'select-object
          (propertize "candidate" 'personality 'voice-lighten))))
      (should (emacsvox-aural-submission-p submission))
      (should
       (equal
        (nreverse events)
        (if icons-enabled
            '(cue (text "candidate"))
          '((text "candidate")))))
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
        (should (eq (plist-get facts :role) 'candidate))
        (should (equal (plist-get facts :events) '(focus-entered)))
        (should (= (plist-get facts :completion-index) 2))
        (should
         (equal
          (mapcar
           #'emacsvox-aural-concrete-action-cue
           (emacsvox-aural-concrete-plan-before plan))
          (and icons-enabled '(select-object))))
        (should
         (eq
          (emacsvox-aural-concrete-content-voice-request content)
          'voice-lighten))
        (should (eq (plist-get context :module) 'vertico))
        (should (eq (plist-get context :occasion) 'navigation))
        (should
         (eq (plist-get context :icons-enabled) icons-enabled))))))

(ert-deftest emacsvox-vertico-native-acceptance-presents-one-transaction ()
  "Accepted content and its completion cue form one native transaction."
  (dolist (icons-enabled '(t nil))
    (with-temp-buffer
      (let ((vertico--index 2)
            (emacsvox-aural-active-scheme 'default)
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
            (submit-function (symbol-function 'emacsvox-aural-submit))
            events
            submission)
        (setq-local emacsvox-speak-voice-annotated-paragraphs t)
        (cl-letf
            (((symbol-function 'emacsvox-aural-submit)
              (lambda (&rest arguments)
                (setq submission (apply submit-function arguments))))
             ((symbol-function 'tts-speak)
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
          (should
           (eq
            'inserted
            (emacsvox--advice-vertico-insert-around
             (lambda ()
               (insert
                (propertize
                 "candidate" 'personality 'voice-lighten))
               'inserted)))))
        (should (emacsvox-aural-submission-p submission))
        (should
         (equal
          (nreverse events)
          (if icons-enabled
              '(cue (text "candidate"))
            '((text "candidate")))))
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
          (should (eq (plist-get facts :role) 'candidate))
          (should (equal (plist-get facts :events) '(accepted)))
          (should (equal (plist-get facts :states) '(selected)))
          (should (= (plist-get facts :completion-index) 2))
          (should
           (equal
            (mapcar
             #'emacsvox-aural-concrete-action-cue
             (emacsvox-aural-concrete-plan-before plan))
            (and icons-enabled '(complete))))
          (should
           (eq
            (emacsvox-aural-concrete-content-voice-request content)
            'voice-lighten))
          (should (eq (plist-get context :module) 'vertico))
          (should (eq (plist-get context :occasion) 'state-change))
          (should
           (eq (plist-get context :icons-enabled) icons-enabled)))))))

(provide 'emacsvox-vertico-tests)
;;; emacsvox-vertico-tests.el ends here
