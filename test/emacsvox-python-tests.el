;;; emacsvox-python-tests.el --- Python advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Python advice.

;;; Code:

(require 'ert)
(require 'python)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-python.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--python-after-targets
  '(python-check
    python-shell-send-region
    python-shell-send-defun
    python-shell-send-file
    python-shell-send-buffer
    python-shell-send-string
    python-fill-paragraph
    python-indent-shift-left
    python-indent-shift-right
    python-indent-region
    python-mark-defun
    python-nav-up-list
    python-nav-if-name-main
    python-nav-forward-statement
    python-nav-forward-sexp-safe
    python-nav-forward-sexp
    python-nav-forward-defun
    python-nav-forward-block
    python-nav-end-of-statement
    python-nav-end-of-defun
    python-nav-end-of-block
    python-nav-beginning-of-statement
    python-nav-beginning-of-block
    python-nav-backward-up-list
    python-nav-backward-statement
    python-nav-backward-sexp-safe
    python-nav-backward-sexp
    python-nav-backward-defun
    python-nav-backward-block)
  "Current Emacs 31 Python targets using direct after advice.")

(ert-deftest emacsvox-python-advice-is-directly-registered ()
  "Python advice is attached directly to current Emacs 31 targets."
  (dolist (target emacsvox-test--python-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))))
  (should
   (advice-member-p
    #'emacsvox--advice-python-indent-dedent-line-backspace-around
    'python-indent-dedent-line-backspace))
  (should
   (advice-member-p
    #'emacsvox--advice-python-indent-dedent-line-around
    'python-indent-dedent-line))
  (should-not (commandp 'python-shell-send-string-no-output)))

(ert-deftest emacsvox-python-backspace-calls-original-once ()
  "Python backspace performs one deletion and submits the deleted character."
  (with-temp-buffer
    (insert "x")
    (let ((ems--interactive-fn-name
           'python-indent-dedent-line-backspace)
          (calls 0)
          submission
          events)
      (cl-letf
          (((symbol-function 'emacsvox-python--submit-text)
            (lambda (&rest arguments)
              (setq submission arguments)
              (push 'submission events))))
        (should
         (eq
          'result
          (emacsvox--advice-python-indent-dedent-line-backspace-around
           (lambda (arg)
             (setq calls (1+ calls))
             (should (= arg 1))
             (push 'original events)
             (delete-char -1)
             'result)
           1))))
      (should (= calls 1))
      (should (equal (buffer-string) ""))
      (should
       (equal
        (nreverse events)
        '(original submission)))
      (should
       (equal
        submission
        '("x"
          (:role code-construct :events (object-changed)
           :syntax-role character :code-edit-kind delete-character
           :edit-operation deletion)
          edit))))))

(ert-deftest emacsvox-python-whitespace-backspace-reports-indent ()
  "Whitespace backspace reports resulting indentation in one submission."
  (with-temp-buffer
    (insert "    ")
    (let ((ems--interactive-fn-name
           'python-indent-dedent-line-backspace)
          (calls 0)
          submission
          events)
      (cl-letf
          (((symbol-function 'emacsvox-python--submit-text)
            (lambda (&rest arguments)
              (setq submission arguments)
              (push 'submission events))))
        (should
         (eq
          'result
          (emacsvox--advice-python-indent-dedent-line-backspace-around
           (lambda (_arg)
             (setq calls (1+ calls))
             (push 'original events)
             (delete-char -1)
             'result)
           1))))
      (should (= calls 1))
      (should
       (equal
        (nreverse events)
        '(original submission)))
      (should (equal (car submission) "Indent 3"))
      (should
       (equal
        (plist-get (cadr submission) :edit-operation)
        'deletion)))))

(ert-deftest emacsvox-python-shell-feedback-cues-only-outer-command ()
  "Nested sends produce one semantic start event for the outer command."
  (let ((ems--interactive-fn-name 'python-shell-send-buffer)
        submissions)
    (cl-letf
        (((symbol-function 'emacsvox-python--submit-actions)
          (lambda (&rest arguments)
            (push arguments submissions))))
      (emacsvox--advice-python-shell-send-string-after "code")
      (emacsvox--advice-python-shell-send-region-after 1 2)
      (emacsvox--advice-python-shell-send-buffer-after))
    (should
     (equal
      submissions
      '(((:role code-operation :events (operation-started)
          :code-operation-kind python-shell-send-buffer)
         state-change))))))

(ert-deftest emacsvox-python-indentation-uses-native-bounds ()
  "Python indentation submits explicit bounds as one aural transaction."
  (with-temp-buffer
    (insert "one\ntwo\nthree\n")
    (let ((ems--interactive-fn-name 'indent-region)
          submitted)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (setq submitted (cons content arguments)))))
        (emacsvox--advice-python-indent-region-after
         (point-min) (point-max)))
      (let* ((arguments (cdr submitted))
             (facts (plist-get arguments :facts)))
        (should
         (equal
          (car submitted)
          "Indented region   containing 3 lines"))
        (should
         (equal
          facts
          '(:role code-construct :events (object-changed)
            :syntax-role block :code-edit-kind indent-region)))
        (should (eq (plist-get arguments :module) 'python))
        (should (eq (plist-get arguments :occasion) 'edit))
        (should-not (plist-get arguments :compatibility-actions))))))

(ert-deftest emacsvox-python-shift-feedback-is-target-aware ()
  "Only the matching block shift submits its explicit result."
  (with-temp-buffer
    (insert "one\ntwo\n")
    (let ((ems--interactive-fn-name 'python-indent-shift-left)
          submitted)
      (cl-letf
          (((symbol-function 'emacsvox-python--submit-text)
            (lambda (&rest arguments)
              (push arguments submitted))))
        (emacsvox--advice-python-indent-shift-right-after
         (point-min) (point-max))
        (emacsvox--advice-python-indent-shift-left-after
         (point-min) (point-max)))
      (should
       (equal
        submitted
        '(("Left shifted block  containing 2 lines"
           (:role code-construct :events (object-changed)
            :syntax-role block :code-edit-kind shift-left)
           edit)))))))

(ert-deftest emacsvox-python-indent-native-plan-resolves-cue-once ()
  "Python indent speech and compatibility cue share one resolved object."
  (with-temp-buffer
    (python-mode)
    (insert "one\ntwo\n")
    (let ((ems--interactive-fn-name 'indent-region)
          prepared)
      (cl-letf
          (((symbol-function 'tts-speak)
            (lambda (text) (setq prepared text)))
           ((symbol-function 'emacsvox-icon)
            (lambda (&rest _)
              (ert-fail "Native indentation called legacy icon transport"))))
        (emacsvox--advice-python-indent-region-after
         (point-min) (point-max)))
      (let* ((plan (emacsvox-aural-concrete-plan-at 0 prepared))
             (before (emacsvox-aural-concrete-plan-before plan)))
        (should
         (equal
          (substring-no-properties prepared)
          "Indented region   containing 2 lines"))
        (should
         (= 1
            (cl-count
             'right before
             :key #'emacsvox-aural-concrete-action-cue)))
        (should
         (equal
          (emacsvox-aural-concrete-plan-facts plan)
          '(:role code-construct :events (object-changed)
            :code-edit-kind indent-region :syntax-role block)))
        (should
         (natnump
          (plist-get
           (emacsvox-aural-concrete-plan-context plan)
           :presentation-transaction-id)))))))

(ert-deftest emacsvox-python-line-speaker-keeps-native-and-supplied-delivery ()
  "The line callback boundary preserves native and supplied speech delivery."
  (with-temp-buffer
    (insert "line")
    (goto-char (point-min))
    (let ((emacsvox-show-point nil)
          (emacsvox-audio-indentation nil)
          (tts-punctuation-mode 'all)
          standard
          standard-arguments
          supplied)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (text &rest arguments)
              (setq
               standard text
               standard-arguments arguments))))
        (emacsvox-speak-line)
        (emacsvox-speak-line-with-speaker
         (lambda (text) (setq supplied text))))
      (should (equal standard "line"))
      (should
       (eq (plist-get standard-arguments :occasion) 'navigation))
      (should (equal supplied "line")))))

(ert-deftest emacsvox-python-navigation-feedback-is-target-aware ()
  "Only the matching Python navigation command produces feedback."
  (let ((ems--interactive-fn-name 'python-nav-backward-block)
        submissions)
    (cl-letf
        (((symbol-function 'emacsvox-python--present-current-line)
          (lambda (&rest arguments)
            (push arguments submissions))))
      (emacsvox--advice-python-nav-forward-block-after)
      (emacsvox--advice-python-nav-backward-block-after))
    (should
     (equal
      submissions
      '(((:role code-construct
          :events (boundary-entered focus-entered)
          :syntax-role block)
         navigation))))))

(ert-deftest emacsvox-python-navigation-carries-code-semantics ()
  "Python navigation passes code semantics to the line transaction."
  (let ((ems--interactive-fn-name 'python-nav-forward-defun)
        captured)
    (cl-letf
        (((symbol-function 'emacsvox-python--present-current-line)
          (lambda (&rest arguments)
            (setq captured arguments))))
      (emacsvox--advice-python-nav-forward-defun-after))
    (pcase-let ((`(,facts ,occasion) captured))
      (should (eq (plist-get facts :role) 'code-construct))
      (should (eq (plist-get facts :syntax-role) 'function))
      (should
       (equal
        (plist-get facts :events)
        '(boundary-entered focus-entered)))
      (should (eq occasion 'navigation)))))

(ert-deftest emacsvox-python-navigation-preserves-line-properties ()
  "Ordinary navigation preserves line voice and post-speech cue order."
  (with-temp-buffer
    (insert (propertize "value = 1" 'personality 'voice-lighten))
    (goto-char (point-min))
    (let ((ems--interactive-fn-name 'python-nav-forward-statement)
          (emacsvox-show-point nil)
          (emacsvox-audio-indentation nil)
          (tts-punctuation-mode 'all)
          captured)
      (cl-letf
          (((symbol-function 'tts-stop) #'ignore)
           ((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (setq captured (cons content arguments))))
           ((symbol-function 'emacsvox-icon)
            (lambda (&rest _)
              (ert-fail "Ordinary navigation used a legacy icon"))))
        (emacsvox--advice-python-nav-forward-statement-after))
      (pcase-let* ((`(,speech . ,arguments) captured)
                   (facts (plist-get arguments :facts))
                   (context (plist-get arguments :context)))
        (should (equal speech "value = 1"))
        (should
         (eq
          (get-text-property 0 'personality speech)
          'voice-lighten))
        (should (eq (plist-get facts :role) 'code-construct))
        (should
         (equal
          (plist-get facts :events)
          '(boundary-entered focus-entered)))
        (should (eq (plist-get facts :syntax-role) 'statement))
        (should (eq (plist-get context :module) 'python))
        (should-not (plist-get arguments :compatibility-actions))))))

(ert-deftest emacsvox-python-navigation-captures-line-and-point-cues ()
  "Line-local and show-point cues are inputs to the one line submission."
  (with-temp-buffer
    (insert (propertize "value" 'auditory-icon 'item))
    (goto-char (+ (point-min) 2))
    (let ((ems--interactive-fn-name 'python-nav-forward-statement)
          (emacsvox-show-point t)
          (emacsvox-show-point-presentation 'voice)
          (emacsvox-audio-indentation nil)
          (tts-punctuation-mode 'all)
          submission)
      (cl-letf
          (((symbol-function 'tts-stop) #'ignore)
           ((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (setq submission (cons content arguments))))
           ((symbol-function 'emacsvox-icon)
            (lambda (&rest _)
              (ert-fail "Python line cues escaped the native submission"))))
        (emacsvox--advice-python-nav-forward-statement-after))
      (let* ((spoken (car submission))
             (actions
              (plist-get (cdr submission) :compatibility-actions)))
        (should (equal spoken "value"))
        (should
         (equal
          (get-text-property
           2 emacsvox-aural-facts-property spoken)
          '(:events (point-located)
            :point-boundary before
            :point-position interior
            :point-presentation voice)))
        (should
         (equal
          (mapcar
           #'emacsvox-aural-compatibility-action-value actions)
          '(item)))
        (should-not (get-text-property 2 'auditory-icon spoken)))
      (should-not (get-text-property 2 'personality (buffer-string)))
      (should-not (get-text-property 2 'pause (buffer-string))))))

(ert-deftest emacsvox-python-navigation-captures-structural-line-cues ()
  "Hidden and displayed line cues are captured in source order."
  (with-temp-buffer
    (insert "hidden")
    (put-text-property
     (point-min) (1+ (point-min)) 'emacsvox-hidden-block t)
    (let ((overlay (make-overlay (point-min) (1+ (point-min)))))
      (overlay-put overlay 'before-string "prefix"))
    (goto-char (point-min))
    (let ((ems--interactive-fn-name 'python-nav-forward-block)
          (emacsvox-show-point nil)
          (emacsvox-audio-indentation nil)
          (tts-punctuation-mode 'all)
          submission)
      (cl-letf
          (((symbol-function 'tts-stop) #'ignore)
           ((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (setq submission (cons content arguments))))
           ((symbol-function 'emacsvox-icon)
            (lambda (&rest _)
              (ert-fail "Structural line cue escaped native submission"))))
        (emacsvox--advice-python-nav-forward-block-after))
      (should
       (equal
        (mapcar
         #'emacsvox-aural-compatibility-action-value
         (plist-get (cdr submission) :compatibility-actions))
        '(ellipses left))))))

(ert-deftest emacsvox-python-navigation-composes-semantic-line-conditions ()
  "Blank navigation composes line condition with Python facts and final cue."
  (dolist (case '(("" empty) ("   " whitespace-only)))
    (with-temp-buffer
      (insert (car case))
      (goto-char (point-min))
      (let ((ems--interactive-fn-name 'python-nav-forward-statement)
            (emacsvox-show-point nil)
            (emacsvox-audio-indentation nil)
            (tts-punctuation-mode 'all)
            events)
        (cl-letf
            (((symbol-function 'tts-stop) #'ignore)
             ((symbol-function 'process-live-p) (lambda (_process) t))
             ((symbol-function 'tts-speak)
              (lambda (&rest _)
                (ert-fail "Blank line reached speech transport")))
             ((symbol-function 'emacsvox-aural-submit)
              (lambda (&rest _)
                (ert-fail "Blank line entered native submission")))
             ((symbol-function 'emacsvox-aural-submit-actions)
              (lambda (&rest arguments)
                (let ((facts (plist-get arguments :facts)))
                  (push
                   (list
                    'actions
                    (plist-get facts :line-condition)
                    (plist-get facts :role)
                    (plist-get facts :events)
                    emacsvox-aural-submission-module
                    emacsvox-aural-submission-occasion
                    (mapcar
                     #'emacsvox-aural-compatibility-action-value
                     (plist-get arguments :compatibility-actions)))
                   events))))
             ((symbol-function 'tts-tone)
              (lambda (&rest _)
                (ert-fail "Blank line used a raw legacy tone")))
             ((symbol-function 'emacsvox-icon)
              (lambda (&rest _)
                (ert-fail "Blank navigation used a separate icon"))))
          (emacsvox--advice-python-nav-forward-statement-after))
        (setq events (nreverse events))
        (should
         (equal
          (car events)
          (list
           'actions (cadr case) 'code-construct
           '(boundary-entered focus-entered)
           'python 'navigation nil)))
        (should (= (length events) 1))))))

(ert-deftest emacsvox-python-navigation-preserves-long-line-confirmation ()
  "Long navigation retains confirmation, source marking, speech, and cue order."
  (with-temp-buffer
    (insert "long")
    (goto-char (point-min))
    (let ((ems--interactive-fn-name 'python-nav-forward-statement)
          (emacsvox-show-point nil)
          (emacsvox-audio-indentation nil)
          (ems--speak-max-length 3)
          (tts-punctuation-mode 'all)
          (visual-line-mode nil)
          (selective-display nil)
          events)
      (cl-letf
          (((symbol-function 'tts-stop) #'ignore)
           ((symbol-function 'y-or-n-p)
            (lambda (_prompt)
              (push '(confirm) events)
              nil))
           ((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (push
               (list
                'submission content
                (car
                 (plist-get arguments :compatibility-actions)))
               events)))
           ((symbol-function 'emacsvox-icon)
            (lambda (&rest _)
              (ert-fail "Long speech used a legacy icon"))))
        (emacsvox--advice-python-nav-forward-statement-after))
      (should
       (equal
        (mapcar #'car (nreverse events))
        '(confirm submission)))
      (should (get-text-property (point-min) 'start-line))
      (should (= ems--speak-max-length 8)))))

(ert-deftest emacsvox-python-navigation-native-submission-presents-once ()
  "Python line speech and its trailing cue form one native transaction."
  (dolist (icons-enabled '(t nil))
    (with-temp-buffer
      (insert (propertize "value = 1" 'personality 'voice-lighten))
      (goto-char (point-min))
      (let ((ems--interactive-fn-name 'python-nav-forward-statement)
            (emacsvox-show-point nil)
            (emacsvox-audio-indentation nil)
            (tts-punctuation-mode 'all)
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
        (cl-letf
            (((symbol-function 'emacsvox-aural-submit)
              (lambda (&rest arguments)
                (setq submission (apply submit-function arguments))))
             ((symbol-function 'tts-stop) #'ignore)
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
          (emacsvox--advice-python-nav-forward-statement-after))
        (should (emacsvox-aural-submission-p submission))
        (should
         (equal
          (nreverse events)
          (if icons-enabled
              '((text "value = 1") cue)
            '((text "value = 1")))))
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
          (should (eq (plist-get facts :role) 'code-construct))
          (should
           (equal
            (plist-get facts :events)
            '(boundary-entered focus-entered)))
          (should (eq (plist-get facts :syntax-role) 'statement))
          (should-not (emacsvox-aural-concrete-plan-before plan))
          (should
           (equal
            (mapcar
             #'emacsvox-aural-concrete-action-cue
             (emacsvox-aural-concrete-plan-after plan))
            (and icons-enabled '(paragraph))))
          (should
           (eq
            (emacsvox-aural-concrete-content-voice-request content)
            'voice-lighten))
          (should (eq (plist-get context :module) 'python))
          (should (eq (plist-get context :occasion) 'navigation))
          (should
           (eq (plist-get context :icons-enabled) icons-enabled)))))))

(ert-deftest emacsvox-python-structural-cues-resolve-in-one-line-transaction ()
  "Source icons, point position, speech, and Python navigation resolve once."
  (with-temp-buffer
    (insert (propertize "value" 'auditory-icon 'item))
    (goto-char (+ (point-min) 2))
    (let ((ems--interactive-fn-name 'python-nav-forward-statement)
          (emacsvox-show-point t)
          (emacsvox-show-point-presentation 'voice)
          (emacsvox-audio-indentation nil)
          (tts-punctuation-mode 'all)
          (emacsvox-aural-active-scheme 'default)
          (emacsvox-aural-enabled-feature-fragments nil)
          (emacsvox-aural-user-rules nil)
          (emacsvox-aural-session-rules nil)
          (emacsvox-aural-buffer-rules nil)
          (emacsvox-aural-presentation-history nil)
          (emacsvox-aural--presentation-sequence 0)
          (emacsvox-aural--submission-sequence 0)
          (emacsvox-use-icons t)
          (submit-function (symbol-function 'emacsvox-aural-submit))
          submission)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (&rest arguments)
              (setq submission (apply submit-function arguments))))
           ((symbol-function 'tts-stop) #'ignore)
           ((symbol-function 'tts-speak)
            (lambda (prepared)
              (with-temp-buffer
                (insert prepared)
                (tts-audio-format (point-min) (point-max)))))
           ((symbol-function 'emacsvox-queue-resource) #'ignore)
           ((symbol-function 'tts-voice-reset-code) (lambda () "RESET"))
           ((symbol-function 'tts--protocol-queue-code) #'ignore)
           ((symbol-function 'tts--protocol-queue-text) #'ignore)
           ((symbol-function 'tts--protocol-silence) #'ignore))
        (emacsvox--advice-python-nav-forward-statement-after))
      (should (emacsvox-aural-submission-p submission))
      (let ((plans (emacsvox-aural-submission-plans submission)))
        (should
         (equal
          (mapcar
           #'emacsvox-aural-concrete-action-cue
           (apply
            #'append
            (mapcar #'emacsvox-aural-concrete-plan-before plans)))
          '(item)))
        (should
         (equal
          (mapcar
           #'emacsvox-aural-concrete-action-cue
           (apply
            #'append
            (mapcar #'emacsvox-aural-concrete-plan-after plans)))
          '(paragraph))))
      (should
       (eq
        (emacsvox-aural-concrete-content-voice-request
         (emacsvox-aural-concrete-plan-content
          (emacsvox-aural-concrete-plan-at 2
           (emacsvox-aural-submission-prepared-content submission))))
        'animate))
      (should (= (length emacsvox-aural-presentation-history) 1)))))

(ert-deftest emacsvox-python-backspace-is-one-native-edit-transaction ()
  "Deletion tone and deleted character share facts and one concrete plan."
  (with-temp-buffer
    (insert "x")
    (let ((ems--interactive-fn-name
           'python-indent-dedent-line-backspace)
          (emacsvox-aural-active-scheme 'default)
          (emacsvox-aural-enabled-feature-fragments nil)
          (emacsvox-aural-user-rules nil)
          (emacsvox-aural-session-rules nil)
          (emacsvox-aural-buffer-rules nil)
          prepared)
      (cl-letf
          (((symbol-function 'tts-speak)
            (lambda (text) (setq prepared text))))
        (emacsvox--advice-python-indent-dedent-line-backspace-around
         (lambda (_arg)
           (delete-char -1)
           'deleted)
         1))
      (should (equal (buffer-string) ""))
      (let* ((plan (emacsvox-aural-concrete-plan-at 0 prepared))
             (facts (emacsvox-aural-concrete-plan-facts plan)))
        (should (equal (substring-no-properties prepared) "x"))
        (should (eq (plist-get facts :edit-operation) 'deletion))
        (should (eq (plist-get facts :code-edit-kind) 'delete-character))
        (should
         (equal
          (mapcar
           #'emacsvox-aural-concrete-action-tone
           (emacsvox-aural-concrete-plan-before plan))
          '(edit-deletion)))))))

(ert-deftest emacsvox-python-dedent-reports-success-and-no-op-distinctly ()
  "Dedent presents the changed line; a no-op is a failed operation."
  (let ((ems--interactive-fn-name 'python-indent-dedent-line)
        line-presentation
        message-submission)
    (cl-letf
        (((symbol-function 'emacsvox-python--present-current-line)
          (lambda (&rest arguments)
            (setq line-presentation arguments)))
         ((symbol-function 'emacsvox-python--submit-message)
          (lambda (&rest arguments)
            (setq message-submission arguments))))
      (should
       (emacsvox--advice-python-indent-dedent-line-around
        (lambda () t))))
    (should
     (equal
      line-presentation
      '((:role code-construct :events (object-changed)
         :syntax-role indentation :code-edit-kind dedent-line)
        edit)))
    (setq ems--interactive-fn-name 'python-indent-dedent-line)
    (cl-letf
        (((symbol-function 'emacsvox-python--present-current-line)
          (lambda (&rest _)
            (ert-fail "A no-op dedent presented a changed line")))
         ((symbol-function 'emacsvox-python--submit-message)
          (lambda (&rest arguments)
            (setq message-submission arguments))))
      (should-not
       (emacsvox--advice-python-indent-dedent-line-around
        (lambda () nil))))
    (should
     (equal
      message-submission
      '("Line indentation unchanged"
        (:role code-operation :events (operation-failed)
         :code-operation-kind dedent-line)
        state-change)))))

(ert-deftest emacsvox-python-mark-defun-is-native-selection-feedback ()
  "Marking a function submits its size and selection event together."
  (with-temp-buffer
    (insert "def one():\n    pass\n")
    (goto-char (point-min))
    (set-mark (point-max))
    (let ((ems--interactive-fn-name 'python-mark-defun)
          submission)
      (cl-letf
          (((symbol-function 'emacsvox-python--submit-message)
            (lambda (&rest arguments)
              (setq submission arguments))))
        (emacsvox--advice-python-mark-defun-after))
      (should
       (equal
        submission
        '("Marked function containing 2 lines"
          (:role code-construct :events (code-selection-created)
           :syntax-role function)
          state-change))))))

(ert-deftest emacsvox-python-code-semantics-are-registered ()
  "Shared programming operations and selections have vocabulary records."
  (dolist
      (semantic
       '(code-operation code-edit-kind code-operation-kind
         code-selection-created))
    (should (emacsvox-aural-semantic semantic))))

(ert-deftest emacsvox-python-fragment-distinguishes-feedback-meanings ()
  "Python rules distinguish submission, dedent, fill, and selection cues."
  (dolist
      (case
       '(((:role code-operation :events (operation-started)
           :code-operation-kind python-check)
          state-change (progress) nil)
         ((:role code-construct :events (object-changed)
           :syntax-role indentation :code-edit-kind dedent-line)
          edit nil (left))
         ((:role code-construct :events (object-changed)
           :syntax-role paragraph :code-edit-kind fill-paragraph)
          edit (fill-object) nil)
         ((:role code-construct :events (code-selection-created)
           :syntax-role function)
          state-change (mark-object) nil)))
    (pcase-let* ((`(,facts ,occasion ,expected-before ,expected-after) case)
                 (context
                  (list
                   :module 'python
                   :mode 'python-mode
                   :mode-lineage '(python-mode prog-mode)
                   :occasion occasion
                   :icons-enabled t))
                 (plan (emacsvox-aural-resolve-active facts context)))
      (should
       (equal
        (mapcar
         #'emacsvox-aural-action-cue
         (emacsvox-aural-render-plan-before plan))
        expected-before))
      (should
       (equal
        (mapcar
         #'emacsvox-aural-action-cue
         (emacsvox-aural-render-plan-after plan))
        expected-after)))))

(provide 'emacsvox-python-tests)
;;; emacsvox-python-tests.el ends here
