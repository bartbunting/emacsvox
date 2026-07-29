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
      (cl-letf (((symbol-function 'emacsvox-icon) #'ignore)
                ((symbol-function 'emacsvox-speak-region) #'ignore))
        (should
         (eq 'inserted
             (emacsvox--advice-vertico-insert-around
              (lambda ()
                (cl-incf calls)
                (insert "candidate")
                'inserted))))
        (should (= calls 1))))))

(ert-deftest emacsvox-vertico-acceptance-carries-candidate-semantics ()
  "Accepted-candidate cue and speech share completion facts and context."
  (with-temp-buffer
    (let ((vertico--index 2)
          captured)
      (cl-letf
          (((symbol-function 'emacsvox-icon)
            (lambda (icon)
              (push
               (list
                icon
                (copy-tree emacsvox-aural-submission-facts)
                (copy-tree emacsvox-aural-submission-context))
               captured)))
           ((symbol-function 'emacsvox-speak-region)
            (lambda (&rest _)
              (push
               (list
                'speech
                (copy-tree emacsvox-aural-submission-facts)
                (copy-tree emacsvox-aural-submission-context))
               captured))))
        (emacsvox--advice-vertico-insert-around
         (lambda () (insert "candidate"))))
      (setq captured (nreverse captured))
      (should (equal (mapcar #'car captured) '(complete speech)))
      (dolist (entry captured)
        (should (eq (plist-get (cadr entry) :role) 'candidate))
        (should (equal (plist-get (cadr entry) :events) '(accepted)))
        (should (equal (plist-get (cadr entry) :states) '(selected)))
        (should (= (plist-get (cadr entry) :completion-index) 2))
        (should (eq (plist-get (caddr entry) :module) 'vertico))
        (should
         (eq (plist-get (caddr entry) :occasion) 'state-change))))))

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

(provide 'emacsvox-vertico-tests)
;;; emacsvox-vertico-tests.el ends here
