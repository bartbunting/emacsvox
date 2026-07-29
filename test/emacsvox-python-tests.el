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

(ert-deftest emacsvox-python-navigation-feedback-is-target-aware ()
  "Only the matching Python navigation command produces feedback."
  (let ((ems--interactive-fn-name 'python-nav-backward-block)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-python-nav-forward-block-after)
      (emacsvox--advice-python-nav-backward-block-after))
    (should
     (equal
      (nreverse events)
      '(line (icon paragraph))))))

(ert-deftest emacsvox-python-navigation-carries-code-semantics ()
  "Python navigation speech and its cue share construct facts and context."
  (let ((ems--interactive-fn-name 'python-nav-forward-defun)
        captured)
    (cl-letf
        (((symbol-function 'emacsvox-speak-line)
          (lambda ()
            (push
             (list
              'line
              (copy-tree emacsvox-aural-submission-facts)
              (copy-tree emacsvox-aural-submission-context))
             captured)))
         ((symbol-function 'emacsvox-icon)
          (lambda (icon)
            (push
             (list
              icon
              (copy-tree emacsvox-aural-submission-facts)
              (copy-tree emacsvox-aural-submission-context))
             captured))))
      (emacsvox--advice-python-nav-forward-defun-after))
    (setq captured (nreverse captured))
    (should (equal (mapcar #'car captured) '(line paragraph)))
    (dolist (entry captured)
      (should (eq (plist-get (cadr entry) :role) 'code-construct))
      (should (eq (plist-get (cadr entry) :syntax-role) 'function))
      (should
       (equal
        (plist-get (cadr entry) :events)
        '(boundary-entered focus-entered)))
      (should (eq (plist-get (caddr entry) :module) 'python)))))

(ert-deftest emacsvox-python-navigation-preserves-line-properties ()
  "Ordinary navigation preserves line voice and post-speech cue order."
  (with-temp-buffer
    (insert (propertize "value = 1" 'personality 'voice-lighten))
    (goto-char (point-min))
    (let ((ems--interactive-fn-name 'python-nav-forward-statement)
          (emacsvox-show-point nil)
          (emacsvox-audio-indentation nil)
          (tts-punctuation-mode 'all)
          events)
      (cl-letf
          (((symbol-function 'tts-stop) #'ignore)
           ((symbol-function 'tts-speak)
            (lambda (text)
              (push
               (list
                'speak
                text
                (copy-tree emacsvox-aural-submission-facts)
                (copy-tree emacsvox-aural-submission-context))
               events)))
           ((symbol-function 'emacsvox-icon)
            (lambda (icon) (push (list 'icon icon) events))))
        (emacsvox--advice-python-nav-forward-statement-after))
      (setq events (nreverse events))
      (should (equal (mapcar #'car events) '(speak icon)))
      (should (eq (cadadr events) 'paragraph))
      (let ((speech (car events)))
        (should (equal (cadr speech) "value = 1"))
        (should
         (eq
          (get-text-property 0 'personality (cadr speech))
          'voice-lighten))
        (should (eq (plist-get (nth 2 speech) :role) 'code-construct))
        (should
         (equal
          (plist-get (nth 2 speech) :events)
          '(boundary-entered focus-entered)))
        (should
         (eq (plist-get (nth 2 speech) :syntax-role) 'statement))
        (should (eq (plist-get (nth 3 speech) :module) 'python))))))

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
           ((symbol-function 'tts-speak)
            (lambda (text) (push (list 'speak text) events)))
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
        '(item tick-tick speak paragraph)))
      (let ((spoken (cadr (nth 2 events))))
        (should (equal spoken "value"))
        (should
         (eq (get-text-property 2 'personality spoken) voice-animate))
        (should (= (get-text-property 2 'pause spoken) 5)))
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
           ((symbol-function 'tts-speak)
            (lambda (text) (push (list 'speak text) events)))
           ((symbol-function 'emacsvox-icon)
            (lambda (icon) (push (list 'icon icon) events))))
        (emacsvox--advice-python-nav-forward-block-after))
      (should
       (equal
        (mapcar
         (lambda (event)
           (if (eq (car event) 'icon) (cadr event) (car event)))
         (nreverse events))
        '(ellipses left speak paragraph))))))

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
           ((symbol-function 'tts-speak)
            (lambda (text) (push (list 'speak text) events)))
           ((symbol-function 'emacsvox-icon)
            (lambda (icon) (push (list 'icon icon) events))))
        (emacsvox--advice-python-nav-forward-statement-after))
      (should
       (equal
        (mapcar #'car (nreverse events))
        '(confirm speak icon)))
      (should (get-text-property (point-min) 'start-line))
      (should (= ems--speak-max-length 8)))))

(provide 'emacsvox-python-tests)
;;; emacsvox-python-tests.el ends here
