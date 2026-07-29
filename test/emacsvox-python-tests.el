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
    python-indent-dedent-line
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
  (should-not (commandp 'python-shell-send-string-no-output)))

(ert-deftest emacsvox-python-backspace-calls-original-once ()
  "Python backspace speaks before exactly one original deletion."
  (with-temp-buffer
    (insert "x")
    (let ((ems--interactive-fn-name
           'python-indent-dedent-line-backspace)
          (calls 0)
          events)
      (cl-letf (((symbol-function 'tts-tone)
                 (lambda (&rest _) (push 'tone events)))
                ((symbol-function 'emacsvox-speak-this-char)
                 (lambda (character)
                   (push (list 'character character) events))))
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
        '(tone (character 120) original))))))

(ert-deftest emacsvox-python-whitespace-backspace-reports-indent ()
  "Whitespace backspace reports indentation after one original call."
  (with-temp-buffer
    (insert "    ")
    (let ((ems--interactive-fn-name
           'python-indent-dedent-line-backspace)
          (calls 0)
          events)
      (cl-letf (((symbol-function 'tts-tone)
                 (lambda (&rest _) (push 'tone events)))
                ((symbol-function 'tts-notify)
                 (lambda (text) (push (list 'notify text) events))))
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
        '(tone original (notify "Indent 3 ")))))))

(ert-deftest emacsvox-python-shell-feedback-cues-only-outer-command ()
  "Nested send operations produce one cue for the interactive command."
  (let ((ems--interactive-fn-name 'python-shell-send-buffer)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-python-shell-send-string-after "code")
      (emacsvox--advice-python-shell-send-region-after 1 2)
      (emacsvox--advice-python-shell-send-buffer-after))
    (should (equal events '((icon task-done))))))

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
             (action
              (car (plist-get arguments :compatibility-actions))))
        (should
         (equal
          (car submitted)
          "Indented region   containing 3 lines"))
        (should
         (equal
          (plist-get arguments :facts)
          '(:role code-construct :events (object-changed)
            :syntax-role block)))
        (should (eq (plist-get arguments :module) 'python))
        (should (eq (plist-get arguments :occasion) 'edit))
        (should
         (eq
          (emacsvox-aural-compatibility-action-value action)
          'right))))))

(ert-deftest emacsvox-python-shift-feedback-is-target-aware ()
  "Only the matching block shift submits its explicit result."
  (with-temp-buffer
    (insert "one\ntwo\n")
    (let ((ems--interactive-fn-name 'python-indent-shift-left)
          submitted)
      (cl-letf
          (((symbol-function 'emacsvox-python--submit-edit-feedback)
            (lambda (icon text) (push (list icon text) submitted))))
        (emacsvox--advice-python-indent-shift-right-after
         (point-min) (point-max))
        (emacsvox--advice-python-indent-shift-left-after
         (point-min) (point-max)))
      (should
       (equal
        submitted
        '((left "Left shifted block  containing 2 lines")))))))

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
            :syntax-role block)))
        (should
         (natnump
          (plist-get
           (emacsvox-aural-concrete-plan-context plan)
           :presentation-transaction-id)))))))

(ert-deftest emacsvox-python-line-speaker-keeps-standard-transport ()
  "The line callback boundary preserves normal and supplied speech delivery."
  (with-temp-buffer
    (insert "line")
    (goto-char (point-min))
    (let ((emacsvox-show-point nil)
          (emacsvox-audio-indentation nil)
          (tts-punctuation-mode 'all)
          standard
          supplied)
      (cl-letf
          (((symbol-function 'tts-stop) #'ignore)
           ((symbol-function 'tts-speak)
            (lambda (text) (setq standard text))))
        (emacsvox-speak-line)
        (emacsvox-speak-line-with-speaker
         (lambda (text) (setq supplied text))))
      (should (equal standard "line"))
      (should (equal supplied "line")))))

(ert-deftest emacsvox-python-navigation-feedback-is-target-aware ()
  "Only the matching Python navigation command produces feedback."
  (let ((ems--interactive-fn-name 'python-nav-backward-block)
        events)
    (cl-letf
        (((symbol-function 'emacsvox-speak-line-with-speaker)
          (lambda (speaker &optional _arg)
            (push 'line events)
            (funcall speaker "line")))
         ((symbol-function 'emacsvox-aural-submit)
          (lambda (content &rest arguments)
            (let ((action
                   (car
                    (plist-get arguments :compatibility-actions))))
              (push
               (list
                'submission content
                (emacsvox-aural-compatibility-action-value action)
                (emacsvox-aural-compatibility-action-phase action))
               events))))
         ((symbol-function 'emacsvox-icon)
          (lambda (&rest _)
            (ert-fail "Speech-producing navigation used legacy fallback"))))
      (emacsvox--advice-python-nav-forward-block-after)
      (emacsvox--advice-python-nav-backward-block-after))
    (should
     (equal
      (nreverse events)
      '(line (submission "line" paragraph after))))))

(ert-deftest emacsvox-python-navigation-carries-code-semantics ()
  "Python navigation speech and its cue share one semantic submission."
  (let ((ems--interactive-fn-name 'python-nav-forward-defun)
        captured)
    (cl-letf
        (((symbol-function 'emacsvox-speak-line-with-speaker)
          (lambda (speaker &optional _arg)
            (funcall speaker "line")))
         ((symbol-function 'emacsvox-aural-submit)
          (lambda (content &rest arguments)
            (setq captured (cons content arguments))))
         ((symbol-function 'emacsvox-icon)
          (lambda (&rest _)
            (ert-fail "Speech-producing navigation used legacy fallback"))))
      (emacsvox--advice-python-nav-forward-defun-after))
    (pcase-let* ((`(,content . ,arguments) captured)
                 (facts (plist-get arguments :facts))
                 (context (plist-get arguments :context))
                 (action
                  (car
                   (plist-get arguments :compatibility-actions))))
      (should (equal content "line"))
      (should (eq (plist-get facts :role) 'code-construct))
      (should (eq (plist-get facts :syntax-role) 'function))
      (should
       (equal
        (plist-get facts :events)
        '(boundary-entered focus-entered)))
      (should (eq (plist-get arguments :module) 'python))
      (should (eq (plist-get arguments :occasion) 'navigation))
      (should (eq (plist-get context :module) 'python))
      (should
       (eq
        (emacsvox-aural-compatibility-action-value action)
        'paragraph))
      (should
       (eq
        (emacsvox-aural-compatibility-action-phase action)
        'after)))))

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
                   (context (plist-get arguments :context))
                   (action
                    (car
                     (plist-get arguments :compatibility-actions))))
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
        (should
         (eq
          (emacsvox-aural-compatibility-action-value action)
          'paragraph))
        (should
         (eq
          (emacsvox-aural-compatibility-action-phase action)
          'after))))))

(ert-deftest emacsvox-python-navigation-preserves-line-and-point-cues ()
  "Line-local and show-point cues precede speech and the paragraph cue."
  (with-temp-buffer
    (insert (propertize "value" 'auditory-icon 'item))
    (goto-char (+ (point-min) 2))
    (let ((ems--interactive-fn-name 'python-nav-forward-statement)
          (emacsvox-show-point t)
          (emacsvox-audio-indentation nil)
          (tts-punctuation-mode 'all)
          events)
      (cl-letf
          (((symbol-function 'tts-stop) #'ignore)
           ((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (push
               (list
                'submission content
                (car
                 (plist-get arguments :compatibility-actions)))
               events)))
           ((symbol-function 'emacsvox-icon)
            (lambda (icon) (push (list 'icon icon) events))))
        (emacsvox--advice-python-nav-forward-statement-after))
      (setq events (nreverse events))
      (should
       (equal
        (mapcar
         (lambda (event)
           (if (eq (car event) 'icon) (cadr event) (car event)))
         events)
        '(item tick-tick submission)))
      (let* ((submission (nth 2 events))
             (spoken (cadr submission))
             (action (nth 2 submission)))
        (should (equal spoken "value"))
        (should
         (eq (get-text-property 2 'personality spoken) voice-animate))
        (should (= (get-text-property 2 'pause spoken) 5))
        (should
         (eq
          (emacsvox-aural-compatibility-action-value action)
          'paragraph))
        (should
         (eq
          (emacsvox-aural-compatibility-action-phase action)
          'after)))
      (should-not (get-text-property 2 'personality (buffer-string)))
      (should-not (get-text-property 2 'pause (buffer-string))))))

(ert-deftest emacsvox-python-navigation-preserves-structural-line-cues ()
  "Hidden and displayed line structure cues precede speech."
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
          events)
      (cl-letf
          (((symbol-function 'tts-stop) #'ignore)
           ((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest _)
              (push (list 'submission content) events)))
           ((symbol-function 'emacsvox-icon)
            (lambda (icon) (push (list 'icon icon) events))))
        (emacsvox--advice-python-nav-forward-block-after))
      (should
       (equal
        (mapcar
         (lambda (event)
           (if (eq (car event) 'icon) (cadr event) (car event)))
         (nreverse events))
        '(ellipses left submission))))))

(ert-deftest emacsvox-python-navigation-preserves-blank-line-tones ()
  "Empty and whitespace navigation retain their distinct tones and final cue."
  (dolist (case '(("" 130.8) ("   " 261.6)))
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
             ((symbol-function 'tts-speak)
              (lambda (&rest _)
                (ert-fail "Blank line reached speech transport")))
             ((symbol-function 'emacsvox-aural-submit)
              (lambda (&rest _)
                (ert-fail "Blank line entered native submission")))
             ((symbol-function 'tts-tone)
              (lambda (&rest arguments)
                (push (cons 'tone arguments) events)))
             ((symbol-function 'emacsvox-icon)
              (lambda (icon) (push (list 'icon icon) events))))
          (emacsvox--advice-python-nav-forward-statement-after))
        (setq events (nreverse events))
        (should (equal (mapcar #'car events) '(tone icon)))
        (should (= (cadar events) (cadr case)))
        (should (equal (cdar events) (list (cadr case) 150 'force)))
        (should (equal (cadr events) '(icon paragraph)))))))

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

(provide 'emacsvox-python-tests)
;;; emacsvox-python-tests.el ends here
