;;; emacsvox-vertico-tests.el --- Vertico advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'vertico)
(load (expand-file-name "../lisp/emacsvox-vertico.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)
(require 'emacsvox-advice)

(ert-deftest emacsvox-vertico-advice-is-current-and-direct ()
  "Current Vertico targets use native advice directly."
  (dolist (entry emacsvox-vertico--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-vertico-face-map-covers-current-interface ()
  "Every mapped Vertico face exists in the installed package."
  (dolist (entry emacsvox-vertico--face-map)
    (should (facep (car entry)))))

(ert-deftest emacsvox-vertico-insert-updates-input-once ()
  "Direct insertion is an input edit, not completion acceptance."
  (with-temp-buffer
    (let ((vertico--index 2)
          (ems--interactive-fn-name 'vertico-insert)
          (calls 0)
          captured)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (setq captured (cons content arguments)))))
        (should
         (eq
          'inserted
          (emacsvox--advice-vertico-insert-around
           (lambda ()
             (cl-incf calls)
             (insert
              (propertize "candidate" 'personality 'voice-lighten))
             'inserted)))))
      (should (= calls 1))
      (pcase-let* ((`(,content . ,arguments) captured)
                   (facts (plist-get arguments :facts))
                   (actions
                    (plist-get arguments :compatibility-actions)))
        (should (equal content "candidate"))
        (should
         (eq (get-text-property 0 'personality content) 'voice-lighten))
        (should
         (equal (plist-get facts :events)
                '(completion-input-updated)))
        (should (equal (plist-get facts :states) '(selected)))
        (should (= (plist-get facts :completion-index) 2))
        (should (eq (plist-get arguments :occasion) 'state-change))
        (should
         (equal
          (mapcar
           #'emacsvox-aural-compatibility-action-value
           actions)
          '(item)))))))

(ert-deftest emacsvox-vertico-insert-is-quiet-when-nested ()
  "Nested insertion during `vertico-exit' does not duplicate feedback."
  (with-temp-buffer
    (let ((ems--interactive-fn-name 'vertico-exit)
          events)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (&rest _) (push 'content events)))
           ((symbol-function 'emacsvox-aural-submit-actions)
            (lambda (&rest _) (push 'actions events))))
        (emacsvox--advice-vertico-insert-around
         (lambda () (insert "candidate"))))
      (should-not events)
      (should (eq ems--interactive-fn-name 'vertico-exit)))))

(ert-deftest emacsvox-vertico-insert-suppresses-follow-up-exhibit ()
  "Direct insertion and its post-command display update speak only once."
  (with-temp-buffer
    (let ((vertico--index 2)
          (vertico--base "")
          (ems--interactive-fn-name 'vertico-insert)
          events)
      (setq-local
       emacsvox-vertico--prev-candidate "old"
       emacsvox-vertico--prev-index 1)
      (cl-letf
          (((symbol-function 'vertico--candidate)
            (lambda (&optional _) "candidate"))
           ((symbol-function 'emacsvox-aural-submit)
            (lambda (&rest _) (push 'submission events))))
        (emacsvox--advice-vertico-insert-around
         (lambda () (insert "candidate")))
        (emacsvox--advice-vertico--exhibit-after))
      (should (equal events '(submission)))
      (should-not emacsvox-vertico--suppress-next-exhibit-p)
      (should
       (equal emacsvox-vertico--prev-candidate "candidate")))))

(ert-deftest emacsvox-vertico-empty-insert-is-action-only ()
  "An unchanged direct insertion creates one native action transaction."
  (with-temp-buffer
    (let ((vertico--index 2)
          (ems--interactive-fn-name 'vertico-insert)
          captured)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (&rest _)
              (ert-fail "Empty insertion submitted spoken content")))
           ((symbol-function 'emacsvox-aural-submit-actions)
            (lambda (&rest arguments) (setq captured arguments))))
        (emacsvox--advice-vertico-insert-around
         (lambda () 'unchanged)))
      (should
       (equal
        (plist-get (plist-get captured :facts) :events)
        '(completion-input-updated)))
      (should
       (equal
        (mapcar
         #'emacsvox-aural-compatibility-action-value
         (plist-get captured :compatibility-actions))
        '(item))))))

(ert-deftest emacsvox-vertico-large-insert-remains-native ()
  "Inserted content is not diverted to the legacy windowful reader."
  (with-temp-buffer
    (let ((vertico--index 2)
          (ems--interactive-fn-name 'vertico-insert)
          (ems--large-text-size 3)
          captured)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest _) (setq captured content)))
           ((symbol-function 'emacsvox-speak-windowful)
            (lambda () (ert-fail "Used legacy windowful fallback"))))
        (emacsvox--advice-vertico-insert-around
         (lambda () (insert "large"))))
      (should (equal captured "large")))))

(ert-deftest emacsvox-vertico-exit-accepts-one-selected-candidate ()
  "Exiting with a selection presents acceptance once before exit."
  (with-temp-buffer
    (let ((vertico--index 2)
          (ems--interactive-fn-name 'vertico-exit)
          calls
          captured)
      (cl-letf
          (((symbol-function 'vertico--candidate)
            (lambda (&optional _) "candidate"))
           ((symbol-function 'vertico--match-p) (lambda (_) t))
           ((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (push 'feedback calls)
              (setq captured (cons content arguments)))))
        (should
         (eq
          'exited
          (emacsvox--advice-vertico-exit-around
           (lambda (&rest _)
             (push 'original calls)
             'exited)))))
      (should (equal (nreverse calls) '(feedback original)))
      (pcase-let* ((`(,content . ,arguments) captured)
                   (facts (plist-get arguments :facts)))
        (should (equal content "candidate"))
        (should (equal (plist-get facts :events) '(accepted)))
        (should (equal (plist-get facts :states) '(selected)))
        (should (= (plist-get facts :completion-index) 2))
        (should
         (equal
          (mapcar
           #'emacsvox-aural-compatibility-action-value
           (plist-get arguments :compatibility-actions))
          '(complete)))))))

(ert-deftest emacsvox-vertico-exit-input-accepts-raw-input ()
  "Raw-input exit does not claim that the highlighted candidate was selected."
  (with-temp-buffer
    (insert "typed input")
    (let ((vertico--index 2)
          (ems--interactive-fn-name 'vertico-exit-input)
          captured)
      (cl-letf
          (((symbol-function 'minibuffer-contents)
            (lambda () "typed input"))
           ((symbol-function 'vertico--match-p) (lambda (_) t))
           ((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (setq captured (cons content arguments)))))
        (emacsvox--advice-vertico-exit-around #'ignore t))
      (pcase-let* ((`(,content . ,arguments) captured)
                   (facts (plist-get arguments :facts)))
        (should (equal content "typed input"))
        (should (equal (plist-get facts :events) '(accepted)))
        (should-not (plist-member facts :states))
        (should (= (plist-get facts :completion-index) -1))))))

(ert-deftest emacsvox-vertico-refused-exit-is-quiet ()
  "An input rejected by Vertico's match predicate is not announced."
  (with-temp-buffer
    (let ((vertico--index 2)
          (ems--interactive-fn-name 'vertico-exit)
          events)
      (cl-letf
          (((symbol-function 'vertico--candidate)
            (lambda (&optional _) "candidate"))
           ((symbol-function 'vertico--match-p) (lambda (_) nil))
           ((symbol-function 'emacsvox-aural-submit)
            (lambda (&rest _) (push 'feedback events))))
        (emacsvox--advice-vertico-exit-around
         (lambda (&rest _) (push 'original events))))
      (should (equal events '(original))))))

(ert-deftest emacsvox-vertico-candidate-navigation-submits-once ()
  "Candidate navigation folds its cue and trimmed text into one submission."
  (dolist
      (case
       '((vertico-next -1 select-object)
         (vertico-first 2 large-movement)
         (nil 1 nil)))
    (with-temp-buffer
      (let ((vertico--index 2)
            (vertico--base "pre")
            (ems--interactive-fn-name (nth 0 case))
            captured)
        (setq-local
         emacsvox-vertico--prev-candidate "old"
         emacsvox-vertico--prev-index (nth 1 case))
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
            (when (nth 2 case) (list (nth 2 case))))))
        (should
         (equal emacsvox-vertico--prev-candidate "candidate"))
        (should (= emacsvox-vertico--prev-index 2))))))

(ert-deftest emacsvox-vertico-initial-candidate-includes-minibuffer-prompt ()
  "The first candidate follows its prompt in one spoken submission."
  (with-temp-buffer
    (let ((vertico--index 0)
          (vertico--base "")
          captured)
      (cl-letf
          (((symbol-function 'minibuffer-prompt)
            (lambda () "Voice for filesystem entry: "))
           ((symbol-function 'vertico--candidate)
            (lambda (&optional _highlight) "default"))
           ((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (setq captured (cons content arguments)))))
        (emacsvox--advice-vertico--exhibit-after))
      (pcase-let ((`(,content . ,arguments) captured))
        (should
         (equal content "Voice for filesystem entry: default"))
        (should (eq (plist-get arguments :module) 'vertico))
        (should (eq (plist-get arguments :occasion) 'navigation)))
      (should (equal emacsvox-vertico--prev-candidate "default"))
      (should (= emacsvox-vertico--prev-index 0)))))

(ert-deftest emacsvox-vertico-flyspell-entry-includes-suggestion-count ()
  "Flyspell correction enters with its word, count, and first suggestion."
  (with-temp-buffer
    (let ((vertico--index 0)
          (vertico--base "")
          (emacsvox-flyspell--suggestion-count 2)
          submission)
      (cl-letf (((symbol-function 'minibuffer-prompt)
                 (lambda () "Suggestions for \"mispeled\": "))
                ((symbol-function 'vertico--candidate)
                 (lambda (&optional _) "misspelled"))
                ((symbol-function 'emacsvox-aural-submit)
                 (lambda (content &rest arguments)
                   (setq submission (list content arguments)))))
        (emacsvox--advice-vertico--exhibit-after))
      (should
       (equal
        (car submission)
        "Suggestions for \"mispeled\": 2 suggestions misspelled")))))

(ert-deftest emacsvox-vertico-initial-unselected-input-speaks-prompt ()
  "An unrestricted prompt is spoken once before the user types."
  (with-temp-buffer
    (let ((vertico--index -1)
          (vertico--base "")
          captured)
      (cl-letf
          (((symbol-function 'minibuffer-prompt) (lambda () "Todo: "))
           ((symbol-function 'vertico--candidate) (lambda (&optional _) ""))
           ((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest _) (setq captured content))))
        (emacsvox--advice-vertico--exhibit-after))
      (should (equal captured "Todo:"))
      (should (equal emacsvox-vertico--prev-candidate ""))
      (should (= emacsvox-vertico--prev-index -1)))))

(ert-deftest emacsvox-vertico-unselected-input-update-is-quiet ()
  "Raw minibuffer input is left to normal typing echo."
  (with-temp-buffer
    (let ((vertico--index -1)
          (vertico--base ""))
      (setq-local
       emacsvox-vertico--prev-candidate "a"
       emacsvox-vertico--prev-index -1)
      (cl-letf
          (((symbol-function 'vertico--candidate)
            (lambda (&optional _) "ab"))
           ((symbol-function 'emacsvox-aural-submit)
            (lambda (&rest _)
              (ert-fail "Raw input was submitted as candidate speech")))
           ((symbol-function 'emacsvox-aural-submit-actions)
            (lambda (&rest _)
              (ert-fail "Raw input update produced a candidate cue"))))
        (emacsvox--advice-vertico--exhibit-after))
      (should (equal emacsvox-vertico--prev-candidate "ab"))
      (should (= emacsvox-vertico--prev-index -1)))))

(ert-deftest emacsvox-vertico-owns-initial-minibuffer-content ()
  "Generic setup leaves initial content to an active Vertico session."
  (with-temp-buffer
    (let ((emacsvox-minibuffer-dictionary (make-hash-table :test #'equal))
          (emacsvox-pronounce-table nil)
          (default-directory "/mnt/c/Users/bart/bin/")
          (minibuffer-default "/mnt/c/Users/bart/bin/")
          (vertico--index 0)
          (vertico--base "")
          (minibuffer-setup-hook
           '(vertico--setup emacsvox-minibuffer-setup-hook))
          events)
      (cl-letf
          (((symbol-function 'tts-stop)
            (lambda (scope) (push (list 'stop scope) events)))
           ((symbol-function 'emacsvox-icon)
            (lambda (icon) (push (list 'icon icon) events)))
           ((symbol-function 'tts-notify)
            (lambda (&rest _)
              (ert-fail "Generic minibuffer setup duplicated Vertico speech")))
           ((symbol-function 'minibuffer-prompt)
            (lambda () "Find file: "))
           ((symbol-function 'vertico--candidate)
            (lambda (&optional _highlight) "/mnt/c/Users/bart/bin/"))
           ((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (let ((pronunciation-table emacsvox-pronounce-table)
                    processed)
                (with-temp-buffer
                  (insert content)
                  (tts-apply-pronunciations pronunciation-table)
                  (setq processed (buffer-string)))
                (push
                 (list 'aural processed (plist-get arguments :module))
                 events)))))
        (run-hooks 'minibuffer-setup-hook)
        (should (local-variable-p 'vertico--input))
        (should
         (eq
          (gethash default-directory emacsvox-pronounce-table 'missing)
          'missing))
        (emacsvox--advice-vertico--exhibit-after))
      (should
       (equal
        (nreverse events)
        '((stop all)
          (icon open-object)
          (icon help)
          (aural "Find file: /mnt/c/Users/bart/bin/" vertico)))))))

(ert-deftest emacsvox-vertico-loaded-but-inactive-keeps-minibuffer-speech ()
  "Generic setup still speaks when Vertico is loaded but not active."
  (with-temp-buffer
    (insert "Shell command: ")
    (let ((emacsvox-minibuffer-dictionary (make-hash-table :test #'equal))
          (emacsvox-pronounce-table nil)
          (default-directory "/mnt/c/Users/bart/bin/")
          (minibuffer-default nil)
          (tts-punctuation-mode 'all)
          (vertico--input nil)
          spoken)
      (cl-letf
          (((symbol-function 'tts-stop) #'ignore)
           ((symbol-function 'emacsvox-icon) #'ignore)
           ((symbol-function 'tts-notify)
            (lambda (content &rest _) (setq spoken content))))
        (emacsvox-minibuffer-setup-hook))
      (should
       (equal
        (gethash default-directory emacsvox-pronounce-table)
        ""))
      (should (equal spoken "Shell command: ")))))

(ert-deftest emacsvox-vertico-later-candidate-does-not-repeat-prompt ()
  "Candidate movement after entry speaks only the changed candidate."
  (with-temp-buffer
    (let ((vertico--index 1)
          (vertico--base "")
          captured)
      (setq-local
       emacsvox-vertico--prev-candidate "default"
       emacsvox-vertico--prev-index 0)
      (cl-letf
          (((symbol-function 'minibuffer-prompt)
            (lambda ()
              (ert-fail "Later candidate movement repeated the prompt")))
           ((symbol-function 'vertico--candidate)
            (lambda (&optional _highlight) "expressive"))
           ((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest _arguments)
              (setq captured content))))
        (emacsvox--advice-vertico--exhibit-after))
      (should (equal captured "expressive")))))

(ert-deftest emacsvox-vertico-repeated-boundary-is-action-only ()
  "Repeated boundary navigation cues without repeating candidate content."
  (with-temp-buffer
    (let ((vertico--index 2)
          (vertico--base "pre")
          (ems--interactive-fn-name 'vertico-next)
          captured)
      (setq-local
       emacsvox-vertico--prev-candidate "candidate"
       emacsvox-vertico--prev-index 2)
      (cl-letf
          (((symbol-function 'vertico--candidate)
            (lambda (&optional _highlight) "precandidate"))
           ((symbol-function 'emacsvox-aural-submit)
            (lambda (&rest _)
              (ert-fail "Boundary navigation repeated content")))
           ((symbol-function 'emacsvox-aural-submit-actions)
            (lambda (&rest arguments) (setq captured arguments))))
        (emacsvox--advice-vertico--exhibit-after))
      (should
       (equal
        (mapcar
         #'emacsvox-aural-compatibility-action-value
         (plist-get captured :compatibility-actions))
        '(select-object)))
      (should
       (equal
        (plist-get (plist-get captured :facts) :events)
        '(focus-entered)))
      (should
       (equal emacsvox-vertico--prev-candidate "candidate"))
      (should (= emacsvox-vertico--prev-index 2)))))

(ert-deftest emacsvox-vertico-empty-candidate-is-action-only ()
  "An empty trimmed candidate uses the native action-only path."
  (with-temp-buffer
    (let ((vertico--index 2)
          (vertico--base "pre")
          captured)
      (setq-local
       emacsvox-vertico--prev-candidate "old"
       emacsvox-vertico--prev-index -1)
      (cl-letf
          (((symbol-function 'vertico--candidate)
            (lambda (&optional _highlight) "pre"))
           ((symbol-function 'emacsvox-aural-submit)
            (lambda (&rest _)
              (ert-fail "Empty candidate submitted spoken content")))
           ((symbol-function 'emacsvox-aural-submit-actions)
            (lambda (&rest arguments) (setq captured arguments))))
        (emacsvox--advice-vertico--exhibit-after))
      (should
       (equal
        (mapcar
         #'emacsvox-aural-compatibility-action-value
         (plist-get captured :compatibility-actions))
        '(select-object)))
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
            (ems--interactive-fn-name 'vertico-exit)
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
             ((symbol-function 'tts--protocol-silence) #'ignore)
             ((symbol-function 'vertico--candidate)
              (lambda (&optional _)
                (propertize
                 "candidate" 'personality 'voice-lighten)))
             ((symbol-function 'vertico--match-p) (lambda (_) t)))
          (should
           (eq
            'exited
            (emacsvox--advice-vertico-exit-around
             (lambda (&rest _) 'exited)))))
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
