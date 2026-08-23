;;; emacsvox-eat-tests.el --- Eat advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'eat)
(load (expand-file-name "../lisp/emacsvox-eat.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)
(require 'emacsvox-aural-provider-workflows)

(defun emacsvox-eat-test--screen (text &optional width generation)
  "Return a minimal public-screen fixture ending at the cursor in TEXT."
  (let ((rows (emacsvox-eat--split-screen-rows text)))
    (list :generation (or generation 1)
          :text text
          :rows rows
          :styles nil
          :cursor-offset (length text)
          :cursor-row (1- (length rows))
          :cursor-column (string-width (car (last rows)))
          :cursor-type :block
          :size (cons (or width 80) 24)
          :alternate-screen nil
          :title nil
          :cwd "/tmp/")))

(defun emacsvox-eat-test--wait-until (process predicate &optional timeout)
  "Wait for PROCESS output and timers until PREDICATE or TIMEOUT seconds."
  (let ((deadline (+ (float-time) (or timeout 3.0))))
    (while (and (not (funcall predicate))
                (< (float-time) deadline)
                (or (null process) (process-live-p process)))
      (when process (accept-process-output process 0.03))
      (sleep-for 0.01))
    (funcall predicate)))

(defun emacsvox-eat-test--screen-text ()
  "Return the current EAT fixture's visible text."
  (or (plist-get (emacsvox-eat--capture-screen) :text) ""))

(defun emacsvox-eat-test--traits-for-text (snapshot text)
  "Return normalized style traits for the first run equal to TEXT."
  (let ((screen-text (plist-get snapshot :text)))
    (seq-some
     (lambda (run)
       (when (equal (substring screen-text (car run) (cadr run)) text)
         (plist-get (caddr run) :traits)))
     (plist-get snapshot :styles))))

(defun emacsvox-eat-test--stop-process (process)
  "Stop disposable test PROCESS without touching any other terminal."
  (when (and process (process-live-p process))
    (process-send-string process "exit\n")
    (accept-process-output process 0.2)
    (when (process-live-p process) (delete-process process))))

(defun emacsvox-eat-test--finish-screen-burst ()
  "Synchronously finish the current deterministic screen-update burst."
  (when emacsvox-eat--quiescence-timer
    (when (timerp emacsvox-eat--quiescence-timer)
      (cancel-timer emacsvox-eat--quiescence-timer))
    (emacsvox-eat--finish-quiescence
     (current-buffer) emacsvox-eat--generation
     emacsvox-eat--update-serial)))

(defun emacsvox-eat-test--deliver-screen (terminal output &optional event)
  "Deliver OUTPUT through TERMINAL and synchronously observe it.
When EVENT is non-nil, record it through EAT's real input-advice path first."
  (when event
    (emacsvox--advice-eat-self-input-before 1 event))
  (eat-term-process-output terminal output)
  (eat-term-redisplay terminal)
  (emacsvox-eat-update-hook)
  (emacsvox-eat-test--finish-screen-burst))

(ert-deftest emacsvox-eat-advice-is-current-and-direct ()
  "Current Eat targets use native advice directly."
  (dolist (target emacsvox-eat--advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (advice-member-p function target))))
  (should
   (advice-member-p
    #'emacsvox--advice-eat-self-input-before 'eat-self-input))
  (dolist (entry emacsvox-eat--before-advice)
    (should (advice-member-p (cdr entry) (car entry))))
  (dolist (entry emacsvox-eat--around-advice)
    (should (advice-member-p (cdr entry) (car entry))))
  (should (memq #'emacsvox-eat--process-started eat-exec-hook))
  (should (memq #'emacsvox-eat--process-exited eat-exit-hook))
  (should (memq #'emacsvox-eat-update-hook eat-eshell-update-hook))
  (should
   (memq #'emacsvox-eat--eshell-process-started eat-eshell-exec-hook))
  (should
   (memq #'emacsvox-eat--eshell-process-exited eat-eshell-exit-hook)))

(ert-deftest emacsvox-eat-state-facts-use-registered-vocabulary ()
  "EAT lifecycle and mode facts satisfy the native semantic contract."
  (dolist
      (case
       (list
        (cons
         (emacsvox-eat--facts 'command-interaction 'operation-started)
         'state-change)
        (cons
         (emacsvox-eat--facts 'command-interaction 'operation-completed)
         'state-change)
        (cons
         (emacsvox-eat--facts 'command-interaction 'state-changed)
         'state-change)
        (cons
         (emacsvox-eat--facts
          'command-input 'object-changed nil
          '(:command-input-origin copied))
         'edit)
        (cons
         (emacsvox-eat--facts 'command-interaction 'object-changed)
         'notification)))
    (should
     (emacsvox-aural-normalize-input
      (car case)
      (list :module 'eat :mode 'eat-mode :occasion (cdr case))))))

(ert-deftest emacsvox-eat-verbosity-is-buffer-local ()
  "Terminal verbosity defaults to normal and may differ by buffer."
  (should (eq (default-value 'emacsvox-eat-verbosity) 'normal))
  (with-temp-buffer
    (should (eq emacsvox-eat-verbosity 'normal))
    (setq-local emacsvox-eat-verbosity 'verbose)
    (should (eq emacsvox-eat-verbosity 'verbose))
    (with-temp-buffer
      (should (eq emacsvox-eat-verbosity 'normal)))))

(ert-deftest emacsvox-eat-background-monitoring-is-buffer-local-and-explicit ()
  "Background monitoring defaults off and its command clears old counts."
  (should-not
   (default-value 'emacsvox-eat-monitor-background-output))
  (with-temp-buffer
    (let ((major-mode 'eat-mode)
          submissions)
      (cl-letf (((symbol-function 'emacsvox-eat--submit)
                 (lambda (&rest arguments) (push arguments submissions))))
        (should (emacsvox-eat-toggle-background-monitoring))
        (should emacsvox-eat-monitor-background-output)
        (setq emacsvox-eat--unread-output-count 4
              emacsvox-eat--background-output-pending-p t)
        (should-not (emacsvox-eat-toggle-background-monitoring -1)))
      (should-not emacsvox-eat-monitor-background-output)
      (should (= emacsvox-eat--unread-output-count 0))
      (should-not emacsvox-eat--background-output-pending-p)
      (should
       (equal
        (mapcar #'car (nreverse submissions))
        '("Background terminal monitoring enabled"
          "Background terminal monitoring disabled")))
      (with-temp-buffer
        (should-not emacsvox-eat-monitor-background-output)))))

(ert-deftest emacsvox-eat-mode-setup-installs-selection-monitor ()
  "EAT buffers observe selection changes for deferred unread reports."
  (with-temp-buffer
    (let (eat-terminal)
      (emacsvox-eat-mode-setup)
      (should
       (local-variable-p 'window-selection-change-functions))
      (should
       (memq #'emacsvox-eat--window-selection-changed
             window-selection-change-functions)))))

(ert-deftest emacsvox-eat-yank-feedback-is-target-aware ()
  "A nested EAT yank cannot duplicate its interactive xterm paste feedback."
  (let ((ems--interactive-fn-name 'eat-xterm-paste)
        submissions)
    (cl-letf (((symbol-function 'emacsvox-aural-compatibility-icon)
               (lambda (icon) (list 'icon icon)))
              ((symbol-function 'emacsvox-aural-submit)
               (lambda (content &rest arguments)
                 (push (list content arguments) submissions))))
      ;; `eat-xterm-paste' can call `eat-yank' internally.  Only the outer
      ;; command owns the interactive marker and may announce the operation.
      (emacsvox--advice-eat-yank-after "never speak this secret")
      (should (eq ems--interactive-fn-name 'eat-xterm-paste))
      (emacsvox--advice-eat-xterm-paste-after
       '(xterm-paste "never speak this secret")))
    (should
     (equal
      submissions
      '(("Pasted clipboard input"
         (:facts
          (:role command-input
           :command-interaction-kind shell
           :events (object-changed)
           :command-input-origin copied)
          :module eat
          :occasion edit
          :compatibility-actions ((icon yank-object)))))))
    (should-not
     (string-match-p "never speak this secret"
                     (format "%S" submissions)))))

(ert-deftest emacsvox-eat-paste-feedback-covers-every-public-entry-point ()
  "Keyboard, kill-ring, xterm, and mouse paste paths have human labels."
  (dolist (entry emacsvox-eat--yank-labels)
    (let ((target (car entry))
          (expected (cdr entry))
          (ems--interactive-fn-name (car entry))
          content)
      (cl-letf (((symbol-function 'emacsvox-aural-submit)
                 (lambda (text &rest _) (setq content text))))
        (funcall
         (intern (format "emacsvox--advice-%s-after" target))))
      (should (equal content expected)))))

(ert-deftest emacsvox-eat-paste-invalidates-completion-before-content-is-sent ()
  "Any terminal paste clears stale completion and character echo state."
  (with-temp-buffer
    (let ((emacsvox-eat--completion-snapshot
           '(:screen (:text "private candidate")))
          (emacsvox-eat--completion-timer (run-at-time 60 nil #'ignore))
          (emacsvox-eat--recent-input '(0 ?x 9999999999.0)))
      (emacsvox-eat--before-terminal-paste "never speak this secret")
      (should-not emacsvox-eat--completion-snapshot)
      (should-not emacsvox-eat--completion-timer)
      (should-not emacsvox-eat--recent-input))))

(ert-deftest emacsvox-eat-password-command-never-presents-secret-content ()
  "Protected EAT input clears snapshots and reports only its outcome."
  (with-temp-buffer
    (let ((eat-terminal 'test-terminal)
          (ems--interactive-fn-name 'eat-send-password)
          (secret "terminal-secret-sentinel")
          (emacsvox-eat--screen-snapshot
           '(:text "terminal-secret-sentinel"))
          (emacsvox-eat--last-screen-diff
           '(:text-change "terminal-secret-sentinel"))
          (emacsvox-eat--last-changed-screen
           '(:text "terminal-secret-sentinel"))
          (emacsvox-eat--last-likely-focus
           '(:kind highlight :text "terminal-secret-sentinel"))
          (emacsvox-eat--last-focus-presentation-identity
           '(highlight "terminal-secret-sentinel"))
          (emacsvox-eat--completion-snapshot
           '(:screen (:text "terminal-secret-sentinel")))
          (emacsvox-eat--last-completion-output
           '(:rows ("terminal-secret-sentinel")))
          (emacsvox-eat--last-status-text "terminal-secret-sentinel")
          transported
          return-input
          submissions)
      (cl-letf (((symbol-function 'emacsvox-eat--selected-buffer-p)
                 (lambda () t))
                ((symbol-function 'read-passwd)
                 (lambda (&rest _)
                   (should emacsvox-eat--secure-input-active-p)
                   (should-not emacsvox-eat--screen-snapshot)
                   (should-not emacsvox-eat--completion-snapshot)
                   secret))
                ((symbol-function 'eat-term-send-string)
                 (lambda (terminal content)
                   (setq transported (list terminal content))))
                ((symbol-function 'eat-self-input)
                 (lambda (count event)
                   (setq return-input (list count event))))
                ((symbol-function 'emacsvox-aural-compatibility-icon)
                 (lambda (icon) (list 'icon icon)))
                ((symbol-function 'emacsvox-aural-submit)
                 (lambda (content &rest arguments)
                   (push (list content arguments) submissions))))
        (eat-send-password))
      (should (equal transported (list 'test-terminal secret)))
      (should (equal return-input '(1 return)))
      (should-not emacsvox-eat--secure-input-active-p)
      (should-not emacsvox-eat--screen-snapshot)
      (should-not emacsvox-eat--last-screen-diff)
      (should-not emacsvox-eat--last-changed-screen)
      (should-not emacsvox-eat--last-likely-focus)
      (should-not emacsvox-eat--last-focus-presentation-identity)
      (should-not emacsvox-eat--completion-snapshot)
      (should-not emacsvox-eat--last-completion-output)
      (should-not emacsvox-eat--last-status-text)
      (should
       (equal
        submissions
        '(("Secure terminal input sent"
           (:facts
            (:role command-interaction
             :command-interaction-kind shell
             :events (operation-completed))
            :module eat
            :occasion state-change
            :compatibility-actions ((icon task-done)))))))
      (should-not (string-match-p secret (format "%S" submissions))))))

(ert-deftest emacsvox-eat-password-cancellation-clears-secure-state ()
  "A quit from protected input is re-signalled after content-free cleanup."
  (with-temp-buffer
    (let ((ems--interactive-fn-name 'eat-send-password)
          (emacsvox-eat--screen-snapshot '(:text "stale secret"))
          submissions
          quit-seen)
      (cl-letf (((symbol-function 'emacsvox-eat--selected-buffer-p)
                 (lambda () t))
                ((symbol-function 'emacsvox-eat--submit)
                 (lambda (&rest arguments) (push arguments submissions))))
        (condition-case nil
            (emacsvox--advice-eat-send-password-around
             (lambda ()
               (should emacsvox-eat--secure-input-active-p)
               (signal 'quit nil)))
          (quit (setq quit-seen t))))
      (should quit-seen)
      (should-not emacsvox-eat--secure-input-active-p)
      (should-not emacsvox-eat--screen-snapshot)
      (should
       (equal
        submissions
        '(("Secure terminal input cancelled"
           (:role command-interaction
            :command-interaction-kind shell
            :events (state-changed))
           state-change close-object)))))))

(ert-deftest emacsvox-eat-secure-input-suppresses-screen-observation ()
  "Terminal updates during protected input cannot capture or speak content."
  (with-temp-buffer
    (let ((emacsvox-eat--secure-input-active-p t)
          (emacsvox-eat--screen-snapshot '(:text "stale secret"))
          (emacsvox-eat--recent-input '(0 ?s 9999999999.0)))
      (cl-letf (((symbol-function 'emacsvox-eat--install-bell-observer)
                 #'ignore)
                ((symbol-function 'emacsvox-eat--observe-screen)
                 (lambda () (ert-fail "secure update captured the screen")))
                ((symbol-function 'emacsvox-eat--speak-input-correlated-update)
                 (lambda (&rest _)
                   (ert-fail "secure update reached input speech"))))
        (emacsvox-eat-update-hook))
      (should emacsvox-eat--secure-input-active-p)
      (should-not emacsvox-eat--screen-snapshot)
      (should-not emacsvox-eat--recent-input))))

(ert-deftest emacsvox-eat-mode-feedback-is-human-and-semantic ()
  "Eat mode feedback describes the resulting input mode without Lisp names."
  (let ((ems--interactive-fn-name 'eat-line-mode)
        submission)
    (cl-letf (((symbol-function 'emacsvox-aural-compatibility-icon)
               (lambda (icon) (list 'icon icon)))
              ((symbol-function 'emacsvox-aural-submit)
               (lambda (content &rest arguments)
                 (setq submission (list content arguments)))))
      (emacsvox--advice-eat-line-mode-after))
    (should
     (equal
      submission
      '("Line input mode"
        (:facts
         (:role command-interaction
          :command-interaction-kind shell
          :events (state-changed))
         :module eat
         :occasion state-change
         :compatibility-actions ((icon button))))))))

(ert-deftest emacsvox-eat-toggle-mode-feedback-includes-resulting-state ()
  "EAT feature toggles say whether their human-readable state is enabled."
  (let ((ems--interactive-fn-name 'eat-blink-mode)
        (eat-blink-mode t)
        submissions)
    (cl-letf (((symbol-function 'emacsvox-aural-submit)
               (lambda (content &rest _)
                 (push content submissions))))
      (emacsvox--advice-eat-blink-mode-after)
      (setq eat-blink-mode nil
            ems--interactive-fn-name 'eat-blink-mode)
      (emacsvox--advice-eat-blink-mode-after))
    (should
     (equal
      (nreverse submissions)
      '("Terminal blinking enabled" "Terminal blinking disabled")))))

(ert-deftest emacsvox-eat-speaks-same-line-directory-completion ()
  "A quiesced terminal completion speaks its final path component."
  (with-temp-buffer
    (let ((eat-terminal (eat-term-make (current-buffer) (point-min)))
          submissions)
      (unwind-protect
          (progn
            (eat-term-resize eat-terminal 30 4)
            (eat-term-process-output eat-terminal "$ ~/sr")
            (eat-term-redisplay eat-terminal)
            (emacsvox-eat--capture-completion
             (eat-term-display-cursor eat-terminal))
            (let ((old
                   (plist-get emacsvox-eat--completion-snapshot :screen)))
              (eat-term-process-output eat-terminal "\r$ ~/src/")
              (eat-term-redisplay eat-terminal)
              (let* ((new (emacsvox-eat--capture-screen))
                     (diff (emacsvox-eat--screen-diff old new)))
                (cl-letf (((symbol-function 'emacsvox-aural-submit)
                           (lambda (content &rest arguments)
                             (push (list content arguments) submissions))))
                  (emacsvox-eat--screen-quiesced diff new))))
            (should-not emacsvox-eat--completion-snapshot)
            (should-not emacsvox-eat--completion-timer)
            (should (equal (caar submissions) "src/"))
            (should
             (equal (plist-get (cadar submissions) :facts)
                    '(:role candidate
                      :events (completion-input-updated)))))
        (emacsvox-eat--cancel-completion)
        (when (eat-term-live-p eat-terminal)
          (eat-term-delete eat-terminal))))))

(ert-deftest emacsvox-eat-multiline-completion-defers-to-quiesced-output ()
  "A candidate listing does not trigger arbitrary immediate cursor speech."
  (with-temp-buffer
    (insert "$ ~/sr")
    (let ((eat-terminal 'terminal)
          events)
      (cl-letf (((symbol-function 'eat-term-display-cursor)
                 (lambda (_terminal) (point-marker)))
                ((symbol-function 'emacsvox-eat--capture-screen)
                 (lambda () '(:generation 0 :rows ("$ ~/sr"))))
                ((symbol-function 'emacsvox-eat--observe-screen) #'ignore)
                ((symbol-function 'emacsvox-eat--selected-buffer-p)
                 (lambda () t))
                ((symbol-function 'tts-speak)
                 (lambda (text) (push (list 'speak text) events)))
                ((symbol-function 'emacsvox-speak-line)
                 (lambda () (push '(line) events)))
                ((symbol-function 'emacsvox-speak-this-char)
                 (lambda (char) (push (list 'char char) events))))
        (emacsvox--advice-eat-self-input-before 1 ?\t)
        (erase-buffer)
        (insert "src/ source/\n$ ~/src/")
        (emacsvox-eat-update-hook))
      (should emacsvox-eat--completion-snapshot)
      (should (timerp emacsvox-eat--completion-timer))
      (should-not events)
      (emacsvox-eat--cancel-completion))))

(ert-deftest emacsvox-eat-input-correlates-immediate-cursor-feedback ()
  "Only a recent user input can trigger the legacy immediate cursor cue."
  (with-temp-buffer
    (insert "x")
    (let ((eat-terminal 'terminal)
          (emacsvox-eat--generation 2)
          (emacsvox-eat--recent-input (list 2 ?x (+ (float-time) 1)))
          (emacsvox-eat--pending-screen-diff '(:changes (text)))
          events)
      (cl-letf (((symbol-function 'emacsvox-eat--observe-screen) #'ignore)
                ((symbol-function 'emacsvox-eat--selected-buffer-p)
                 (lambda () t))
                ((symbol-function 'eat-term-display-cursor)
                 (lambda (_terminal) (point-marker)))
                ((symbol-function 'emacsvox-speak-line)
                 (lambda () (push '(line) events)))
                ((symbol-function 'emacsvox-speak-this-char)
                 (lambda (char) (push (list 'char char) events))))
        (emacsvox-eat-update-hook)
        (emacsvox-eat-update-hook))
      (should (equal events '((char 120))))
      (should-not emacsvox-eat--recent-input))))

(ert-deftest emacsvox-eat-asynchronous-update-has-no-immediate-cursor-speech ()
  "Process output without recent input waits for semantic quiesced delivery."
  (with-temp-buffer
    (insert "background result")
    (let ((eat-terminal 'terminal)
          (emacsvox-eat--pending-screen-diff '(:changes (text)))
          events)
      (cl-letf (((symbol-function 'emacsvox-eat--observe-screen) #'ignore)
                ((symbol-function 'emacsvox-eat--selected-buffer-p)
                 (lambda () t))
                ((symbol-function 'eat-term-display-cursor)
                 (lambda (_terminal) (point-marker)))
                ((symbol-function 'emacsvox-speak-line)
                 (lambda () (push '(line) events)))
                ((symbol-function 'emacsvox-speak-this-char)
                 (lambda (char) (push (list 'char char) events))))
        (emacsvox-eat-update-hook))
      (should-not events))))

(ert-deftest emacsvox-eat-input-recording-excludes-submit-and-completion ()
  "Submit and Tab clear input echo state; printable keys retain no raw history."
  (with-temp-buffer
    (let ((eat-terminal 'terminal))
      (emacsvox--advice-eat-self-input-before 1 ?x)
      (should (= (cadr emacsvox-eat--recent-input) ?x))
      (emacsvox--advice-eat-self-input-before 1 13)
      (should-not emacsvox-eat--recent-input)
      (cl-letf (((symbol-function 'eat-term-display-cursor)
                 (lambda (_terminal) nil)))
        (emacsvox--advice-eat-self-input-before 1 ?\t))
      (should-not emacsvox-eat--recent-input))))

(ert-deftest emacsvox-eat-tab-detection-accepts-raw-and-symbolic-events ()
  "Control-character normalization does not disguise a raw Tab as `i'."
  (should (emacsvox-eat--tab-event-p 9))
  (should (emacsvox-eat--tab-event-p 'tab))
  (should-not (emacsvox-eat--tab-event-p ?i)))

(ert-deftest emacsvox-eat-navigation-events-have-content-free-directions ()
  "Terminal navigation keys normalize without retaining typed content."
  (dolist
      (case
       '((up . up) (prior . up) (16 . up)
         (down . down) (next . down) (14 . down)
         (left . left) (home . left) (2 . left)
         (right . right) (end . right) (6 . right)
         (9 . forward) (tab . forward)
         (backtab . backward) (iso-lefttab . backward)))
    (should
     (eq (emacsvox-eat--navigation-direction (car case)) (cdr case))))
  (should-not (emacsvox-eat--navigation-direction ?j))
  (should-not (emacsvox-eat--navigation-direction 'return)))

(ert-deftest emacsvox-eat-alternate-screen-tab-records-navigation-not-completion ()
  "Tab on an application screen is navigation, not shell completion."
  (with-temp-buffer
    (let ((eat-terminal 'terminal)
          (emacsvox-eat--generation 4)
          (emacsvox-eat--screen-snapshot
           '(:generation 4 :alternate-screen t
             :cursor-row 2 :cursor-column 7)))
      (emacsvox--advice-eat-self-input-before 1 'tab)
      (should-not emacsvox-eat--completion-snapshot)
      (should-not emacsvox-eat--recent-input)
      (should
       (equal
        (plist-get emacsvox-eat--recent-navigation-intent :direction)
        'forward))
      (should
       (= (plist-get emacsvox-eat--recent-navigation-intent :generation) 4))
      (should
       (= (plist-get emacsvox-eat--recent-navigation-intent :cursor-row) 2))
      (should-not
       (plist-member emacsvox-eat--recent-navigation-intent :event)))))

(ert-deftest emacsvox-eat-navigation-intents-merge-only-one-direction ()
  "A mixed navigation burst is marked ambiguous instead of misclassified."
  (with-temp-buffer
    (let ((emacsvox-eat--generation 2)
          (up (list :generation 2 :direction 'up
                    :deadline (+ (float-time) 1) :count 1))
          (later-up (list :generation 2 :direction 'up
                          :deadline (+ (float-time) 2) :count 1))
          (down (list :generation 2 :direction 'down
                      :deadline (+ (float-time) 2) :count 1)))
      (emacsvox-eat--merge-pending-navigation-intent up)
      (emacsvox-eat--merge-pending-navigation-intent later-up)
      (should
       (= (plist-get emacsvox-eat--pending-navigation-intent :count) 2))
      (emacsvox-eat--merge-pending-navigation-intent down)
      (should
       (plist-get emacsvox-eat--pending-navigation-intent :ambiguous)))))

(ert-deftest emacsvox-eat-quiescence-carries-current-navigation-intent ()
  "Quiescence passes normalized navigation to classification exactly once."
  (with-temp-buffer
    (let ((emacsvox-eat--generation 5)
          (emacsvox-eat--update-serial 8)
          (emacsvox-eat--quiescence-timer t)
          (emacsvox-eat--pending-screen-baseline
           '(:generation 5 :text "One" :rows ("One")))
          (emacsvox-eat--pending-screen-diff '(:changes (style cursor)))
          (emacsvox-eat--screen-snapshot
           '(:generation 5 :text "Two" :rows ("Two")))
          (emacsvox-eat--pending-navigation-intent
           (list :generation 5 :direction 'down
                 :deadline (+ (float-time) 1) :count 1))
          delivered-diff)
      (cl-letf (((symbol-function 'emacsvox-eat--selected-buffer-p)
                 (lambda () t))
                ((symbol-function 'emacsvox-eat--following-live-p)
                 (lambda () t))
                ((symbol-function 'emacsvox-eat--likely-focus-change)
                 (lambda (old new _diff navigation)
                   (should
                    (equal (plist-get old :text) "One"))
                   (should
                    (equal (plist-get new :text) "Two"))
                   (should
                    (eq (plist-get navigation :direction) 'down))
                   '(:kind highlight :text "Two")))
                ((symbol-function 'emacsvox-eat--screen-quiesced)
                 (lambda (diff _snapshot) (setq delivered-diff diff))))
        (emacsvox-eat--finish-quiescence (current-buffer) 5 8))
      (should
       (equal
        (plist-get (plist-get delivered-diff :navigation) :direction)
        'down))
      (should
       (equal
        (plist-get delivered-diff :likely-focus)
        '(:kind highlight :text "Two")))
      (should-not emacsvox-eat--pending-navigation-intent)
      (should-not emacsvox-eat--quiescence-timer))))

(ert-deftest emacsvox-eat-terminal-tab-does-not-require-private-mode-state ()
  "Any Tab delivered by `eat-self-input' starts terminal completion tracking."
  (with-temp-buffer
    (let ((eat-terminal 'terminal)
          captured-cursor)
      (cl-letf (((symbol-function 'eat-term-display-cursor)
                 (lambda (_terminal) 'cursor))
                ((symbol-function 'emacsvox-eat--capture-completion)
                 (lambda (cursor) (setq captured-cursor cursor))))
        (emacsvox--advice-eat-self-input-before 1 'tab))
      (should (eq captured-cursor 'cursor)))))

(ert-deftest emacsvox-eat-completion-captures-bounded-public-screen-state ()
  "Pre-Tab state includes generation, deadline, cursor facts, and screen data."
  (with-temp-buffer
    (let ((eat-terminal (eat-term-make (current-buffer) (point-min)))
          (emacsvox-eat--generation 6))
      (unwind-protect
          (progn
            (eat-term-resize eat-terminal 30 4)
            (eat-term-process-output eat-terminal "$ ~/sr")
            (eat-term-redisplay eat-terminal)
            (emacsvox-eat--capture-completion
             (eat-term-display-cursor eat-terminal))
            (let* ((transaction emacsvox-eat--completion-snapshot)
                   (screen (plist-get transaction :screen)))
              (should (= (plist-get transaction :generation) 6))
              (should (= (plist-get transaction :serial) 1))
              (should
               (= (- (plist-get transaction :deadline)
                     (plist-get transaction :started-at))
                  emacsvox-eat--completion-timeout))
              (should (equal (plist-get screen :rows) '("$ ~/sr")))
              (should (= (plist-get screen :cursor-row) 0))
              (should (= (plist-get screen :cursor-column) 6))
              (should (integerp (plist-get screen :display-beginning)))
              (should (integerp (plist-get screen :display-end)))
              (should (timerp emacsvox-eat--completion-timer))))
        (emacsvox-eat--cancel-completion)
        (when (eat-term-live-p eat-terminal)
          (eat-term-delete eat-terminal))))))

(ert-deftest emacsvox-eat-completion-survives-compatible-intermediate-update ()
  "An unchanged or resized batch before expansion does not consume completion."
  (with-temp-buffer
    (let* ((emacsvox-eat--generation 2)
           (old (emacsvox-eat-test--screen "$ ~/sr" 30 2))
           (resized (emacsvox-eat-test--screen "$ ~/sr" 40 2))
           (new (emacsvox-eat-test--screen "$ ~/src/" 40 2))
          (emacsvox-eat--completion-snapshot
           (list :generation 2 :serial 4
                 :deadline (+ (float-time) 1) :screen old)))
      (should-not (emacsvox-eat--pending-inline-completion old))
      (should emacsvox-eat--completion-snapshot)
      (should-not (emacsvox-eat--pending-inline-completion resized))
      (should emacsvox-eat--completion-snapshot)
      (should
       (equal (plist-get
               (emacsvox-eat--pending-inline-completion new) :text)
              "src/"))
      (should emacsvox-eat--completion-snapshot))))

(ert-deftest emacsvox-eat-inline-completion-is-screen-based-and-path-aware ()
  "Inline labels handle wrapping, quoting, escapes, Unicode, and punctuation."
  (dolist
      (case
       '(("$ ~/sr" "$ ~/src/" 30 "src/")
         ("$ git pul" "$ git pull " 30 "pull")
         ("$ cat alpha" "$ cat alpha\\ beta " 30 "alpha\\ beta")
         ("$ cat \"alpha b" "$ cat \"alpha beta\" "
          30 "$ cat \"alpha beta\"")
         ("$ cat caf" "$ cat café " 30 "café")
         ("$ cat foo" "$ cat foo\\(bar\\) " 30 "foo\\(bar\\)")
         ("$ cat semi" "$ cat semi\\;colon " 30 "semi\\;colon")
         ("$ pick foo" "$ pick bar" 30 "bar")
         ("$ cmd | gi" "$ cmd | git " 30 "git")
         ("$ 123~/sr" "$ 123~/src\n/" 10 "src/")))
    (pcase-let ((`(,old-text ,new-text ,width ,expected) case))
      (let* ((old (emacsvox-eat-test--screen old-text width))
             (new (emacsvox-eat-test--screen new-text width))
             (result (emacsvox-eat--inline-completion-change old new)))
        (should (equal (plist-get result :text) expected))
        (should (plist-get (plist-get result :diff) :user-input))))))

(ert-deftest emacsvox-eat-inline-completion-rejects-output-and-unsafe-state ()
  "Candidate rows, shorter replacements, alternate screens, and generations fail closed."
  (let* ((old (emacsvox-eat-test--screen "$ git pu" 30 2))
         (candidate-and-expansion
          (emacsvox-eat-test--screen "pull  push\n$ git pul" 30 2))
         (shorter (emacsvox-eat-test--screen "$ git p" 30 2))
         (alternate (copy-tree (emacsvox-eat-test--screen "$ git pull" 30 2)))
         (replacement (emacsvox-eat-test--screen "$ git pull" 30 3)))
    (setf (plist-get alternate :alternate-screen) t)
    (should-not
     (emacsvox-eat--inline-completion-change old candidate-and-expansion))
    (should-not (emacsvox-eat--inline-completion-change old shorter))
    (should-not (emacsvox-eat--inline-completion-change old alternate))
    (should-not (emacsvox-eat--inline-completion-change old replacement))))

(ert-deftest emacsvox-eat-completion-output-preserves-columns-and-help-rows ()
  "Bash columns and router descriptions remain ordered screen rows."
  (dolist
      (case
       '(("$ git pu"
          "$ git pu\npull    push\n$ git pu"
          ("pull    push") items ("pull" "push"))
         ("router# sh"
          "router# sh\nshow      Display system information\nshutdown  Halt the device\nrouter# sh"
          ("show      Display system information"
           "shutdown  Halt the device") rows nil)))
    (pcase-let ((`(,old-text ,new-text ,expected ,layout ,items) case))
      (let ((result
             (emacsvox-eat--completion-output-change
              (emacsvox-eat-test--screen old-text 80)
              (emacsvox-eat-test--screen new-text 80))))
        (should (equal (plist-get result :rows) expected))
        (should (= (plist-get result :row-count) (length expected)))
        (should (eq (plist-get result :layout) layout))
        (should (equal (plist-get result :items) items))
        (should (eq (plist-get result :confidence) 'anchored))))))

(ert-deftest emacsvox-eat-completion-output-aligns-scroll-and-fails-closed ()
  "Retained history is removed; a lost old anchor is explicitly uncertain."
  (let* ((old
          (emacsvox-eat-test--screen
           "history one\nhistory two\n$ git pu" 80))
         (scrolled
          (emacsvox-eat-test--screen
           "history two\n$ git pu\npull\npush\n$ git pu" 80))
         (unanchored
          (emacsvox-eat-test--screen
           "candidate one\ncandidate two\n$ git pu" 80))
         (scrolled-result
          (emacsvox-eat--completion-output-change old scrolled))
         (unanchored-result
          (emacsvox-eat--completion-output-change old unanchored)))
    (should (equal (plist-get scrolled-result :rows) '("pull" "push")))
    (should (eq (plist-get scrolled-result :confidence) 'anchored))
    (should
     (equal (plist-get unanchored-result :rows)
            '("candidate one" "candidate two")))
    (should (eq (plist-get unanchored-result :confidence) 'unanchored))))

(ert-deftest emacsvox-eat-completion-output-waits-for-redrawn-input ()
  "Partial candidate chunks do not end the completion transaction."
  (with-temp-buffer
    (let* ((emacsvox-eat--generation 1)
           (old (emacsvox-eat-test--screen "$ git pu" 80))
           (partial
            (emacsvox-eat-test--screen "$ git pu\npull    push" 80))
           (final
            (emacsvox-eat-test--screen
             "$ git pu\npull    push\n$ git pu" 80))
           (emacsvox-eat--completion-snapshot
            (list :generation 1 :serial 1
                  :deadline (+ (float-time) 1) :screen old)))
      (should-not (emacsvox-eat--pending-completion-output partial))
      (should emacsvox-eat--completion-snapshot)
      (should
       (equal
        (plist-get (emacsvox-eat--pending-completion-output final) :rows)
        '("pull    push")))
      (should emacsvox-eat--completion-snapshot))))

(ert-deftest emacsvox-eat-real-split-candidate-output-waits-for-prompt ()
  "Real EAT candidate chunks classify only after the input is redrawn."
  (with-temp-buffer
    (let ((eat-terminal (eat-term-make (current-buffer) (point-min))))
      (unwind-protect
          (progn
            (eat-term-resize eat-terminal 40 6)
            (eat-term-process-output eat-terminal "$ git pu")
            (eat-term-redisplay eat-terminal)
            (let ((old (emacsvox-eat--capture-screen)))
              (eat-term-process-output eat-terminal "\r\npull")
              (eat-term-redisplay eat-terminal)
              (should-not
               (emacsvox-eat--completion-output-change
                old (emacsvox-eat--capture-screen)))
              (eat-term-process-output
               eat-terminal "    push\r\n$ git pu")
              (eat-term-redisplay eat-terminal)
              (let ((result
                     (emacsvox-eat--completion-output-change
                      old (emacsvox-eat--capture-screen))))
                (should (equal (plist-get result :rows)
                               '("pull    push")))
                (should (eq (plist-get result :confidence) 'anchored)))))
        (when (eat-term-live-p eat-terminal)
          (eat-term-delete eat-terminal))))))

(ert-deftest emacsvox-eat-bash-readline-unique-ambiguous-and-repeated-tab ()
  "A disposable Bash PTY drives inline, list, bell, and repeat transactions."
  (skip-unless (executable-find "bash"))
  (let ((buffer (generate-new-buffer " *emacsvox-eat-bash*"))
        process submissions bells)
    (unwind-protect
        (save-window-excursion
          (switch-to-buffer buffer)
          (cl-letf (((symbol-function 'emacsvox-aural-submit)
                     (lambda (content &rest arguments)
                       (push (list content arguments) submissions)))
                    ((symbol-function 'ding)
                     (lambda (&rest _) (push 'bell bells))))
            (unwind-protect
                (progn
                  (eat-mode)
                  (let ((process-environment
                         (cons "INPUTRC=/dev/null" process-environment)))
                    (eat-exec
                     buffer "emacsvox-eat-bash" (executable-find "bash") nil
                     '("--noprofile" "--norc" "-i")))
                  (setq process (get-buffer-process buffer))
                  (eat-semi-char-mode)
                  (should
                   (emacsvox-eat-test--wait-until
                    process
                    (lambda ()
                      (string-match-p
                       "bash-[^ ]+[$#] "
                       (emacsvox-eat-test--screen-text)))))
                  (eat-term-send-string
                   eat-terminal
                   (concat
                    "PS1='EATTEST> '; PROMPT_COMMAND=; "
                    "_eat_git() { COMPREPLY=( $(compgen -W 'pull push' -- "
                    "\"${COMP_WORDS[COMP_CWORD]}\") ); }; "
                    "complete -F _eat_git git; "
                    "bind 'set page-completions off'\n"))
                  (should
                   (emacsvox-eat-test--wait-until
                    process
                    (lambda ()
                      (string-suffix-p
                       "EATTEST> " (emacsvox-eat-test--screen-text)))))

                  ;; Unique programmable completion.
                  (eat-term-send-string eat-terminal "git pul")
                  (should
                   (emacsvox-eat-test--wait-until
                    process
                    (lambda ()
                      (string-suffix-p
                       "EATTEST> git pul"
                       (emacsvox-eat-test--screen-text)))))
                  (setq submissions nil bells nil)
                  (eat-self-input 1 'tab)
                  (should
                   (emacsvox-eat-test--wait-until
                    process
                    (lambda ()
                      (string-suffix-p
                       "EATTEST> git pull "
                       (emacsvox-eat-test--screen-text)))))
                  (should
                   (emacsvox-eat-test--wait-until
                    process
                    (lambda ()
                      (and (null emacsvox-eat--completion-snapshot)
                           (null emacsvox-eat--quiescence-timer)))))
                  (should
                   (cl-find-if
                    (lambda (submission)
                      (and (equal (car submission) "pull")
                           (equal
                            (plist-get (cadr submission) :facts)
                            '(:role candidate
                              :events (completion-input-updated)))))
                    submissions))

                  ;; Ambiguous completion needs a second Tab to display rows.
                  (eat-term-send-string eat-terminal (concat "\C-u" "git pu"))
                  (should
                   (emacsvox-eat-test--wait-until
                    process
                    (lambda ()
                      (string-suffix-p
                       "EATTEST> git pu"
                       (emacsvox-eat-test--screen-text)))))
                  (setq submissions nil bells nil
                        emacsvox-eat--last-completion-output nil)
                  (eat-self-input 1 'tab)
                  (emacsvox-eat-test--wait-until
                   process (lambda () bells) 0.4)
                  (eat-self-input 1 'tab)
                  (should
                   (emacsvox-eat-test--wait-until
                    process
                    (lambda () emacsvox-eat--last-completion-output)))
                  (should bells)
                  (should
                   (equal
                    (plist-get emacsvox-eat--last-completion-output :items)
                    '("pull" "push")))
                  (should
                   (cl-find-if
                    (lambda (submission)
                      (string-prefix-p "2 candidates\n" (car submission)))
                    submissions))

                  ;; Repeating the same display reports its count only.
                  (setq submissions nil)
                  (eat-self-input 1 'tab)
                  (unless
                      (emacsvox-eat-test--wait-until
                       process
                       (lambda ()
                         (cl-find-if
                          (lambda (submission)
                            (equal (car submission) "Same 2 candidates"))
                          submissions))
                       0.4)
                    (eat-self-input 1 'tab))
                  (should
                   (emacsvox-eat-test--wait-until
                    process
                    (lambda ()
                      (cl-find-if
                       (lambda (submission)
                         (equal (car submission) "Same 2 candidates"))
                       submissions)))))
              (emacsvox-eat-test--stop-process process))))
      (when (buffer-live-p buffer) (kill-buffer buffer)))))

(ert-deftest emacsvox-eat-bash-readline-files-preserve-visible-spelling ()
  "Real file completion handles spaces, Unicode, punctuation, and directories."
  (skip-unless (executable-find "bash"))
  (let ((buffer (generate-new-buffer " *emacsvox-eat-bash-files*"))
        (directory (make-temp-file "emacsvox-eat-files-" t))
        process submissions)
    (unwind-protect
        (progn
          (dolist (name '("alpha beta" "café" "foo(bar)" "semi;colon"))
            (write-region "" nil (expand-file-name name directory) nil 'silent))
          (make-directory (expand-file-name "srcunique" directory))
          (save-window-excursion
            (switch-to-buffer buffer)
            (cl-letf (((symbol-function 'emacsvox-aural-submit)
                       (lambda (content &rest arguments)
                         (push (list content arguments) submissions)))
                      ((symbol-function 'ding) #'ignore))
              (unwind-protect
                  (progn
                    (eat-mode)
                    (let ((process-environment
                           (cons "INPUTRC=/dev/null" process-environment)))
                      (eat-exec
                       buffer "emacsvox-eat-bash-files"
                       (executable-find "bash") nil
                       '("--noprofile" "--norc" "-i")))
                    (setq process (get-buffer-process buffer))
                    (eat-semi-char-mode)
                    (should
                     (emacsvox-eat-test--wait-until
                      process
                      (lambda ()
                        (string-match-p
                         "bash-[^ ]+[$#] "
                         (emacsvox-eat-test--screen-text)))))
                    (eat-term-send-string
                     eat-terminal
                     (format
                      "PS1='EATFILE> '; PROMPT_COMMAND=; cd -- %s\n"
                      (shell-quote-argument directory)))
                    (should
                     (emacsvox-eat-test--wait-until
                      process
                      (lambda ()
                        (string-suffix-p
                         "EATFILE> " (emacsvox-eat-test--screen-text)))))
                    (cl-labels
                        ((complete
                          (input expected)
                          (eat-term-send-string
                           eat-terminal (concat "\C-u" input))
                          (should
                           (emacsvox-eat-test--wait-until
                            process
                            (lambda ()
                              (string-suffix-p
                               (concat "EATFILE> " input)
                               (emacsvox-eat-test--screen-text)))))
                          (setq submissions nil)
                          (eat-self-input 1 'tab)
                          (should
                           (emacsvox-eat-test--wait-until
                            process
                            (lambda ()
                              (cl-find-if
                               (lambda (submission)
                                 (and (equal (car submission) expected)
                                      (equal
                                       (plist-get
                                        (cadr submission) :facts)
                                       '(:role candidate
                                         :events
                                         (completion-input-updated)))))
                               submissions))))))
                      (complete "cat alpha" "alpha\\ beta")
                      (complete "cat caf" "café")
                      (complete "cat foo" "foo\\(bar\\)")
                      (complete "cat semi" "semi\\;colon")
                      (complete "cd srcu" "srcunique/")))
                (emacsvox-eat-test--stop-process process)))))
      (when (buffer-live-p buffer) (kill-buffer buffer))
      (when (file-directory-p directory) (delete-directory directory t)))))

(ert-deftest emacsvox-eat-router-help-fixture-coalesces-delayed-rows-and-bell ()
  "A local raw-terminal fixture models delayed router help without networking."
  (skip-unless (executable-find "python3"))
  (let ((buffer (generate-new-buffer " *emacsvox-eat-router*"))
        (script
         (concat
          "import os,sys,time,tty\n"
          "tty.setraw(0)\n"
          "sys.stdout.write('router# sh'); sys.stdout.flush()\n"
          "while True:\n"
          " c=os.read(0,1)\n"
          " if c==b'\\t':\n"
          "  sys.stdout.write('\\r\\nshow      Display system information\\r\\n'); sys.stdout.flush()\n"
          "  time.sleep(0.08)\n"
          "  sys.stdout.write('shutdown  Halt the device\\a\\r\\nrouter# sh'); sys.stdout.flush()\n"
          " elif c in (b'\\x03',b'\\x04'):\n"
          "  break\n"))
        process submissions bells)
    (unwind-protect
        (save-window-excursion
          (switch-to-buffer buffer)
          (cl-letf (((symbol-function 'emacsvox-aural-submit)
                     (lambda (content &rest arguments)
                       (push (list content arguments) submissions)))
                    ((symbol-function 'ding)
                     (lambda (&rest _) (push 'bell bells))))
            (unwind-protect
                (progn
                  (eat-mode)
                  (eat-exec
                   buffer "emacsvox-eat-router"
                   (executable-find "python3") nil
                   (list "-u" "-c" script))
                  (setq process (get-buffer-process buffer))
                  (eat-semi-char-mode)
                  (should
                   (emacsvox-eat-test--wait-until
                    process
                    (lambda ()
                      (equal (emacsvox-eat-test--screen-text)
                             "router# sh"))))
                  (setq submissions nil bells nil)
                  (eat-self-input 1 'tab)
                  (should
                   (emacsvox-eat-test--wait-until
                    process
                    (lambda () emacsvox-eat--last-completion-output)))
                  (should
                   (equal
                    (plist-get emacsvox-eat--last-completion-output :rows)
                    '("show      Display system information"
                      "shutdown  Halt the device")))
                  (should
                   (eq (plist-get
                        emacsvox-eat--last-completion-output :layout)
                       'rows))
                  (should bells)
                  (let ((candidate-submissions
                         (cl-remove-if-not
                          (lambda (submission)
                            (eq (plist-get
                                 (cadr submission) :occasion)
                                'state-change))
                          submissions)))
                    (should (= (length candidate-submissions) 1))
                    (should
                     (equal
                      (caar candidate-submissions)
                      (concat
                       "2 completion rows\n"
                       "show      Display system information\n"
                       "shutdown  Halt the device")))))
              (emacsvox-eat-test--stop-process process))))
      (when (buffer-live-p buffer) (kill-buffer buffer)))))

(ert-deftest emacsvox-eat-partial-candidate-rows-do-not-speak-twice ()
  "A completed partial row waits silently for the redrawn completion input."
  (with-temp-buffer
    (let* ((emacsvox-eat--generation 1)
           (old (emacsvox-eat-test--screen "$ git pu" 80))
           (partial
            (emacsvox-eat-test--screen "$ git pu\npull    push\n" 80))
           (final
            (emacsvox-eat-test--screen
             "$ git pu\npull    push\n$ git pu" 80))
           (emacsvox-eat--completion-snapshot
            (list :generation 1 :serial 1
                  :deadline (+ (float-time) 1) :screen old))
           submissions)
      (cl-letf (((symbol-function 'emacsvox-aural-submit)
                 (lambda (&rest arguments) (push arguments submissions))))
        (emacsvox-eat--screen-quiesced
         (emacsvox-eat--screen-diff old partial) partial)
        (should-not submissions)
        (should emacsvox-eat--completion-snapshot)
        (emacsvox-eat--screen-quiesced
         (emacsvox-eat--screen-diff partial final) final))
      (should (= (length submissions) 1))
      (should (equal (caar submissions) "2 candidates\npull\npush"))
      (should-not emacsvox-eat--completion-snapshot))))

(ert-deftest emacsvox-eat-candidate-output-is-semantic-retained-and-singular ()
  "Completion rows replace ordinary output speech and remain reviewable."
  (with-temp-buffer
    (let* ((emacsvox-eat--generation 1)
           (old (emacsvox-eat-test--screen "$ git pu" 80))
           (new
            (emacsvox-eat-test--screen
             "$ git pu\npull    push\n$ git pu" 80))
           (diff (emacsvox-eat--screen-diff old new))
           (emacsvox-eat--completion-snapshot
            (list :generation 1 :serial 1
                  :deadline (+ (float-time) 1) :screen old))
           submissions)
      (cl-letf (((symbol-function 'emacsvox-aural-submit)
                 (lambda (content &rest arguments)
                   (push (list content arguments) submissions))))
        (emacsvox-eat--screen-quiesced diff new))
      (should (= (length submissions) 1))
      (should (equal (caar submissions) "2 candidates\npull\npush"))
      (should
       (equal (plist-get (cadar submissions) :facts)
              '(:role candidate :events (operation-completed))))
      (should-not emacsvox-eat--completion-snapshot)
      (should
       (equal (plist-get emacsvox-eat--last-completion-output :rows)
              '("pull    push")))
      (should
       (eq (plist-get emacsvox-eat--last-completion-output :confidence)
           'anchored)))))

(ert-deftest emacsvox-eat-completion-presentation-counts-without-inventing-items ()
  "Candidate cells get item counts; descriptive output keeps row counts."
  (let ((candidates
         '(:rows ("pull    push") :row-count 1
           :items ("pull" "push") :item-count 2 :layout items
           :confidence anchored))
        (help
         '(:rows ("show      Display system information"
                  "shutdown  Halt the device")
           :row-count 2 :items nil :item-count nil :layout rows
           :confidence anchored))
        (uncertain
         '(:rows ("pull" "push") :row-count 2
           :items ("pull" "push") :item-count 2 :layout items
           :confidence unanchored))
        submissions)
    (cl-letf (((symbol-function 'emacsvox-aural-submit)
               (lambda (content &rest _) (push content submissions))))
      (emacsvox-eat--present-completion-output candidates)
      (emacsvox-eat--present-completion-output help)
      (emacsvox-eat--present-completion-output uncertain))
    (should
     (equal
      (nreverse submissions)
      '("2 candidates\npull\npush"
        "2 completion rows\nshow      Display system information\nshutdown  Halt the device"
        "At least 2 visible candidates\npull\npush")))))

(ert-deftest emacsvox-eat-completion-presentation-bounds-large-item-lists ()
  "A large inferred list announces its count, subset, and truncation."
  (let* ((items
          (mapcar (lambda (number) (format "candidate-%02d" number))
                  (number-sequence 1 12)))
         (completion
          (list :rows items :row-count 12 :items items :item-count 12
                :layout 'items :confidence 'anchored))
         submission)
    (cl-letf (((symbol-function 'emacsvox-aural-submit)
               (lambda (content &rest _) (setq submission content))))
      (emacsvox-eat--present-completion-output completion))
    (should
     (equal
      submission
      (concat
       "12 candidates\n"
       (string-join (emacsvox-eat--list-slice items 0 8) "\n")
       "\n4 additional candidates not spoken")))
    (should (= (length (plist-get completion :rows)) 12))))

(ert-deftest emacsvox-eat-real-overflowing-list-reports-a-visible-lower-bound ()
  "A list that scrolls away its anchor does not claim a false total count."
  (with-temp-buffer
    (let ((eat-terminal (eat-term-make (current-buffer) (point-min))))
      (unwind-protect
          (progn
            (eat-term-resize eat-terminal 40 6)
            (eat-term-process-output eat-terminal "$ c")
            (eat-term-redisplay eat-terminal)
            (let ((old (emacsvox-eat--capture-screen)))
              (eat-term-process-output
               eat-terminal
               (concat
                "\r\n"
                (mapconcat
                 (lambda (number) (format "candidate-%02d" number))
                 (number-sequence 1 20) "\r\n")
                "\r\n$ c"))
              (eat-term-redisplay eat-terminal)
              (let ((result
                     (emacsvox-eat--completion-output-change
                      old (emacsvox-eat--capture-screen))))
                (should (eq (plist-get result :confidence) 'unanchored))
                (should (= (plist-get result :item-count) 5))
                (should
                 (equal (emacsvox-eat--completion-count-text result)
                        "At least 5 visible candidates")))))
        (when (eat-term-live-p eat-terminal)
          (eat-term-delete eat-terminal))))))

(ert-deftest emacsvox-eat-repeated-completion-output-is-deduplicated ()
  "Normalized repeated output announces only the unchanged count."
  (with-temp-buffer
    (let* ((signature
           (emacsvox-eat--completion-signature
             'items '("pull    push   ") '("pull" "push")))
           (emacsvox-eat--last-completion-output
            (list :signature signature))
           (completion
            (list :rows '("pull    push") :row-count 1
                  :items '("pull" "push") :item-count 2 :layout 'items
                  :confidence 'anchored
                  :signature
                  (emacsvox-eat--completion-signature
                   'items '("pull" "push") '("pull" "push"))))
           submission)
      (should (emacsvox-eat--completion-repeated-p completion))
      (setq completion (plist-put completion :repeated t))
      (cl-letf (((symbol-function 'emacsvox-aural-submit)
                 (lambda (content &rest _) (setq submission content))))
        (emacsvox-eat--present-completion-output completion))
      (should (equal submission "Same 2 candidates")))))

(ert-deftest emacsvox-eat-real-wrapped-inline-completion-is-one-result ()
  "Public EAT rows reconstruct a completion that crosses a visual wrap."
  (with-temp-buffer
    (let ((eat-terminal (eat-term-make (current-buffer) (point-min))))
      (unwind-protect
          (progn
            (eat-term-resize eat-terminal 10 4)
            (eat-term-process-output eat-terminal "$ 123~/sr")
            (eat-term-redisplay eat-terminal)
            (let ((old (emacsvox-eat--capture-screen)))
              (eat-term-process-output eat-terminal "\r$ 123~/src/")
              (eat-term-redisplay eat-terminal)
              (let* ((new (emacsvox-eat--capture-screen))
                     (result
                      (emacsvox-eat--inline-completion-change old new)))
                (should (equal (plist-get new :rows)
                               '("$ 123~/src" "/")))
                (should (equal (plist-get result :text) "src/")))))
        (when (eat-term-live-p eat-terminal)
          (eat-term-delete eat-terminal))))))

(ert-deftest emacsvox-eat-completion-timeout-is-generation-and-serial-safe ()
  "A stale timeout cannot clear a replacement completion transaction."
  (with-temp-buffer
    (let ((emacsvox-eat--generation 3)
          (emacsvox-eat--completion-serial 2)
          (emacsvox-eat--completion-snapshot
           '(:generation 3 :serial 2 :deadline 100.0)))
      (emacsvox-eat--expire-completion (current-buffer) 3 1)
      (should emacsvox-eat--completion-snapshot)
      (emacsvox-eat--expire-completion (current-buffer) 2 2)
      (should emacsvox-eat--completion-snapshot)
      (emacsvox-eat--expire-completion (current-buffer) 3 2)
      (should-not emacsvox-eat--completion-snapshot)
      (should-not emacsvox-eat--completion-timer))))

(ert-deftest emacsvox-eat-background-update-is-silent ()
  "An EAT resize while another buffer is selected produces no speech."
  (with-temp-buffer
    (insert "shell-prompt$ ")
    (let ((eat-terminal 'terminal)
          (emacsvox-eat--completion-snapshot '(1 . "~/sr"))
          events)
      (cl-letf (((symbol-function 'emacsvox-eat--selected-buffer-p)
                 (lambda () nil))
                ((symbol-function 'emacsvox-eat--observe-screen) #'ignore)
                ((symbol-function 'eat-term-display-cursor)
                 (lambda (_terminal) (point-marker)))
                ((symbol-function 'tts-speak)
                 (lambda (text) (push (list 'speak text) events)))
                ((symbol-function 'emacsvox-speak-line)
                 (lambda () (push '(line) events)))
                ((symbol-function 'emacsvox-speak-this-char)
                 (lambda (char) (push (list 'char char) events))))
        (emacsvox-eat-update-hook))
      (should-not emacsvox-eat--completion-snapshot)
      (should-not events))))

(ert-deftest emacsvox-eat-background-monitor-classifies-only-text-output ()
  "Cursor, style, generation, and resized text changes do not count as output."
  (let* ((old (emacsvox-eat-test--screen "$ " 20 3))
         (text (emacsvox-eat-test--screen "$ command" 20 3))
         (cursor (copy-tree old))
         (style (copy-tree old))
         (resized (emacsvox-eat-test--screen "$ command" 30 3))
         (generation (emacsvox-eat-test--screen "$ command" 20 4)))
    (setf (plist-get cursor :cursor-column) 1
          (plist-get cursor :cursor-offset) 1
          (plist-get style :styles) '((0 2 (:face bold))))
    (should (emacsvox-eat--background-output-change-p old text))
    (should-not (emacsvox-eat--background-output-change-p old old))
    (should-not (emacsvox-eat--background-output-change-p old cursor))
    (should-not (emacsvox-eat--background-output-change-p old style))
    (should-not (emacsvox-eat--background-output-change-p old resized))
    (should-not (emacsvox-eat--background-output-change-p old generation))))

(ert-deftest emacsvox-eat-background-monitor-coalesces-counts-and-cues ()
  "Monitored chunks form unread bursts with rate-limited content-free cues."
  (with-temp-buffer
    (let ((emacsvox-eat-monitor-background-output t)
          (emacsvox-eat--generation 3)
          (now 10.0)
          minibuffer-active-p
          icons)
      (cl-letf (((symbol-function 'float-time)
                 (lambda (&optional _) now))
                ((symbol-function 'run-at-time)
                 (lambda (&rest _) 'background-test-timer))
                ((symbol-function 'emacsvox-eat--selected-buffer-p)
                 (lambda () nil))
                ((symbol-function 'active-minibuffer-window)
                 (lambda () minibuffer-active-p))
                ((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push icon icons))))
        (emacsvox-eat--schedule-background-output-burst)
        (let ((stale-serial emacsvox-eat--background-output-serial))
          (emacsvox-eat--schedule-background-output-burst)
          (emacsvox-eat--finish-background-output-burst
           (current-buffer) 3 stale-serial)
          (should (= emacsvox-eat--unread-output-count 0)))
        (emacsvox-eat--finish-background-output-burst
         (current-buffer) 3 emacsvox-eat--background-output-serial)
        (should (= emacsvox-eat--unread-output-count 1))
        (should (equal icons '(more)))
        (setq now 11.0)
        (emacsvox-eat--schedule-background-output-burst)
        (emacsvox-eat--finish-background-output-burst
         (current-buffer) 3 emacsvox-eat--background-output-serial)
        (should (= emacsvox-eat--unread-output-count 2))
        (should (= (length icons) 1))
        (setq now 16.0
              minibuffer-active-p t)
        (emacsvox-eat--schedule-background-output-burst)
        (emacsvox-eat--finish-background-output-burst
         (current-buffer) 3 emacsvox-eat--background-output-serial)
        (should (= emacsvox-eat--unread-output-count 3))
        (should (= (length icons) 1))
        (setq now 16.1
              minibuffer-active-p nil)
        (emacsvox-eat--schedule-background-output-burst)
        (emacsvox-eat--finish-background-output-burst
         (current-buffer) 3 emacsvox-eat--background-output-serial))
      (should (= emacsvox-eat--unread-output-count 4))
      (should (equal icons '(more more))))))

(ert-deftest emacsvox-eat-background-monitor-reports-count-only-on-return ()
  "Selecting a monitored terminal acknowledges count without name or content."
  (with-temp-buffer
    (rename-buffer "router-secret-host" t)
    (let ((emacsvox-eat-monitor-background-output t)
          (emacsvox-eat--unread-output-count 2)
          (emacsvox-eat--background-output-pending-p t)
          (emacsvox-eat--background-output-timer 'background-test-timer)
          submission)
      (cl-letf (((symbol-function 'window-live-p) (lambda (_) t))
                ((symbol-function 'selected-window)
                 (lambda () 'selected-test-window))
                ((symbol-function 'emacsvox-eat--selected-buffer-p)
                 (lambda () t))
                ((symbol-function 'emacsvox-eat--submit)
                 (lambda (&rest arguments) (setq submission arguments))))
        (emacsvox-eat--window-selection-changed 'selected-test-window))
      (should
       (equal
        submission
        '("3 unread terminal output bursts"
          (:role command-interaction
           :command-interaction-kind shell
           :events (object-changed))
          notification)))
      (should-not
       (string-match-p "router-secret-host\\|secret output"
                       (format "%S" submission)))
      (should (= emacsvox-eat--unread-output-count 0))
      (should-not emacsvox-eat--background-output-pending-p)
      (should-not emacsvox-eat--background-output-timer))))

(ert-deftest emacsvox-eat-real-background-monitor-never-speaks-output ()
  "A real background EAT update cues once and reports only its burst count."
  (with-temp-buffer
    (let ((eat-terminal (eat-term-make (current-buffer) (point-min)))
          (emacsvox-eat-monitor-background-output t)
          selected-p
          pending-timer
          icons
          submissions)
      (unwind-protect
          (cl-letf (((symbol-function 'emacsvox-eat--selected-buffer-p)
                     (lambda () selected-p))
                    ((symbol-function 'active-minibuffer-window)
                     (lambda () nil))
                    ((symbol-function 'emacsvox-icon)
                     (lambda (icon) (push icon icons)))
                    ((symbol-function 'emacsvox-aural-submit)
                     (lambda (content &rest arguments)
                       (push (list content arguments) submissions))))
            (eat-term-resize eat-terminal 40 5)
            (eat-term-process-output eat-terminal "$ ")
            (eat-term-redisplay eat-terminal)
            (emacsvox-eat-update-hook)
            (eat-term-process-output
             eat-terminal "\r\nsecret output sentinel\r\n$ ")
            (eat-term-redisplay eat-terminal)
            (emacsvox-eat-update-hook)
            (setq pending-timer emacsvox-eat--background-output-timer)
            (emacsvox-eat--finish-background-output-burst
             (current-buffer) emacsvox-eat--generation
             emacsvox-eat--background-output-serial)
            (should (equal icons '(more)))
            (should-not submissions)
            (setq selected-p t)
            (emacsvox-eat-update-hook)
            (should (= (length submissions) 1))
            (should (equal (caar submissions)
                           "One unread terminal output burst"))
            (should-not
             (string-match-p "secret output sentinel"
                             (format "%S" submissions))))
        (when (timerp pending-timer) (cancel-timer pending-timer))
        (emacsvox-eat--clear-background-monitor-state)
        (emacsvox-eat--cancel-quiescence)
        (when (eat-term-live-p eat-terminal)
          (eat-term-delete eat-terminal))))))

(ert-deftest emacsvox-eat-empty-terminal-update-is-safe ()
  "An empty EAT terminal update is quiet and does not signal."
  (with-temp-buffer
    (let ((eat-terminal (eat-term-make (current-buffer) (point-min)))
          events)
      (unwind-protect
          (cl-letf (((symbol-function 'emacsvox-eat--selected-buffer-p)
                     (lambda () t))
                    ((symbol-function 'emacsvox-speak-line)
                     (lambda () (push '(line) events)))
                    ((symbol-function 'emacsvox-speak-this-char)
                     (lambda (char) (push (list 'char char) events))))
            (emacsvox-eat-update-hook)
            (should-not events))
        (when (eat-term-live-p eat-terminal)
          (eat-term-delete eat-terminal))))))

(ert-deftest emacsvox-eat-empty-terminal-reset-completes-feedback ()
  "Resetting an empty EAT terminal reaches its explicit feedback."
  (with-temp-buffer
    (let ((eat-terminal (eat-term-make (current-buffer) (point-min)))
          (ems--interactive-fn-name 'eat-reset)
          events)
      (unwind-protect
          (cl-letf (((symbol-function 'emacsvox-eat--selected-buffer-p)
                     (lambda () t))
                    ((symbol-function 'emacsvox-icon)
                     (lambda (icon)
                       (setq events (append events (list (list 'icon icon))))))
                    ((symbol-function 'tts-speak)
                     (lambda (text)
                       (setq events
                             (append events (list (list 'speak text))))))
                    ((symbol-function 'emacsvox-speak-line)
                     (lambda () (push '(unexpected-line) events)))
                    ((symbol-function 'emacsvox-speak-this-char)
                     (lambda (char)
                       (push (list 'unexpected-char char) events))))
            (eat-reset)
            (should
             (equal events
                    '((icon task-done) (speak "Reset Eat")))))
        (when (eat-term-live-p eat-terminal)
          (eat-term-delete eat-terminal))))))

(ert-deftest emacsvox-eat-empty-alternate-screen-updates-are-safe ()
  "Empty alternate-screen entry and exit are quiet and do not signal."
  (with-temp-buffer
    (let ((eat-terminal (eat-term-make (current-buffer) (point-min)))
          events)
      (unwind-protect
          (cl-letf (((symbol-function 'emacsvox-eat--selected-buffer-p)
                     (lambda () t))
                    ((symbol-function 'emacsvox-speak-line)
                     (lambda () (push '(line) events)))
                    ((symbol-function 'emacsvox-speak-this-char)
                     (lambda (char) (push (list 'char char) events))))
            (eat-term-process-output eat-terminal "\e[?1049h")
            (eat-term-redisplay eat-terminal)
            (should (eat-term-in-alternative-display-p eat-terminal))
            (emacsvox-eat-update-hook)
            (eat-term-process-output eat-terminal "\e[?1049l")
            (eat-term-redisplay eat-terminal)
            (should-not (eat-term-in-alternative-display-p eat-terminal))
            (emacsvox-eat-update-hook)
            (should-not events))
        (when (eat-term-live-p eat-terminal)
          (eat-term-delete eat-terminal))))))

(ert-deftest emacsvox-eat-bell-wrapper-preserves-and-deduplicates ()
  "EAT's public bell callback always runs while semantic speech is throttled."
  (with-temp-buffer
    (let* ((eat-terminal (eat-term-make (current-buffer) (point-min)))
           (now 10.0)
           (original-calls 0)
           (original
            (lambda (terminal)
              (should (eq terminal eat-terminal))
              (setq original-calls (1+ original-calls))))
           (emacsvox-eat--completion-snapshot '(:pending t))
           (emacsvox-eat--recent-input '(0 ?x 9999999999.0))
           submissions)
      (unwind-protect
          (progn
            (setf (eat-term-parameter eat-terminal 'ring-bell-function)
                  original)
            (emacsvox-eat--install-bell-observer)
            (emacsvox-eat--install-bell-observer)
            (should
             (eq
              (eat-term-parameter
               eat-terminal 'emacsvox-eat-original-ring-bell-function)
              original))
            (should
             (eq (eat-term-parameter eat-terminal 'ring-bell-function)
                 #'emacsvox-eat--ring-bell))
            (cl-letf (((symbol-function 'float-time)
                       (lambda (&optional _) now))
                      ((symbol-function 'emacsvox-eat--selected-buffer-p)
                       (lambda () t))
                      ((symbol-function 'emacsvox-eat--following-live-p)
                       (lambda () t))
                      ((symbol-function 'emacsvox-eat--submit)
                       (lambda (content facts occasion &rest arguments)
                         (push
                          (list content facts occasion arguments)
                          submissions))))
              (eat-term-process-output eat-terminal "\a\a")
              (should (= original-calls 2))
              (should (= (length submissions) 1))
              (should-not emacsvox-eat--recent-input)
              (should emacsvox-eat--completion-snapshot)
              (setq now 10.6)
              (eat-term-process-output eat-terminal "\a")
              (should (= original-calls 3))
              (should (= (length submissions) 2))
              (setq now 11.2
                    emacsvox-eat--secure-input-active-p t)
              (eat-term-process-output eat-terminal "\a")
              (should (= original-calls 4))
              (should (= (length submissions) 2)))
            (should
             (equal
              (car submissions)
              '("Terminal bell"
                (:role command-interaction
                 :command-interaction-kind shell
                 :events (object-changed))
                notification nil))))
        (when (eat-term-live-p eat-terminal)
          (eat-term-delete eat-terminal))))))

(ert-deftest emacsvox-eat-background-bell-keeps-eat-behavior-without-speech ()
  "A background terminal still invokes EAT's bell but discloses no feedback."
  (with-temp-buffer
    (let ((eat-terminal (eat-term-make (current-buffer) (point-min)))
          original-called
          submissions)
      (unwind-protect
          (progn
            (setf
             (eat-term-parameter eat-terminal 'ring-bell-function)
             (lambda (_) (setq original-called t)))
            (emacsvox-eat--install-bell-observer)
            (cl-letf (((symbol-function 'emacsvox-eat--selected-buffer-p)
                       (lambda () nil))
                      ((symbol-function 'emacsvox-eat--submit)
                       (lambda (&rest event) (push event submissions))))
              (eat-term-process-output eat-terminal "\a"))
            (should original-called)
            (should-not submissions)
            (should emacsvox-eat--last-bell-at)
            (should-not emacsvox-eat--last-bell-spoken-at))
        (when (eat-term-live-p eat-terminal)
          (eat-term-delete eat-terminal))))))

(ert-deftest emacsvox-eat-alternate-screen-transitions-are-semantic ()
  "Application-screen entry and exit are distinct singular state changes."
  (with-temp-buffer
    (let ((emacsvox-eat--completion-snapshot '(:generation 0))
          (emacsvox-eat--last-completion-output '(:rows ("stale")))
          (emacsvox-eat--last-status-text "Progress 40%")
          submissions)
      (cl-letf (((symbol-function 'emacsvox-aural-compatibility-icon)
                 (lambda (icon) (list 'icon icon)))
                ((symbol-function 'emacsvox-aural-submit)
                 (lambda (content &rest arguments)
                   (setq submissions
                         (append submissions (list (list content arguments))))))
                ((symbol-function 'emacsvox-eat--present-output-rows)
                 (lambda (&rest _)
                   (ert-fail "alternate-screen repaint reached output speech"))))
        (emacsvox-eat--screen-quiesced
         '(:alternate-screen-changed t
           :alternate-screen-transitions (t nil)
           :text-changed t)
         '(:alternate-screen nil)))
      (should-not emacsvox-eat--completion-snapshot)
      (should-not emacsvox-eat--last-completion-output)
      (should-not emacsvox-eat--last-status-text)
      (should
       (equal
        submissions
        '(("Terminal application screen entered"
           (:facts
            (:role command-interaction
             :command-interaction-kind shell
             :events (operation-started))
            :module eat
            :occasion state-change
            :compatibility-actions ((icon open-object))))
          ("Terminal application screen exited"
           (:facts
            (:role command-interaction
             :command-interaction-kind shell
             :events (operation-completed))
            :module eat
            :occasion state-change
            :compatibility-actions ((icon close-object))))))))))

(ert-deftest emacsvox-eat-real-alternate-screen-repaint-is-one-boundary ()
  "A real entry, repaint, and resize produce one application boundary."
  (with-temp-buffer
    (let ((eat-terminal (eat-term-make (current-buffer) (point-min)))
          submissions
          pending-timer)
      (unwind-protect
          (cl-letf (((symbol-function 'emacsvox-eat--selected-buffer-p)
                     (lambda () t))
                    ((symbol-function 'emacsvox-eat--following-live-p)
                     (lambda () t))
                    ((symbol-function 'emacsvox-aural-compatibility-icon)
                     (lambda (icon) (list 'icon icon)))
                    ((symbol-function 'emacsvox-aural-submit)
                     (lambda (content &rest arguments)
                       (push (list content arguments) submissions))))
            (eat-term-resize eat-terminal 20 4)
            (eat-term-process-output eat-terminal "Main")
            (eat-term-redisplay eat-terminal)
            (emacsvox-eat--observe-screen)
            (setq emacsvox-eat--completion-snapshot '(:generation 0)
                  emacsvox-eat--last-completion-output '(:rows ("stale"))
                  emacsvox-eat--last-status-text "Progress 40%")

            (eat-term-process-output eat-terminal "\e[?1049hAlt")
            (eat-term-redisplay eat-terminal)
            (emacsvox-eat--observe-screen)
            (eat-term-process-output eat-terminal "\rALT")
            (eat-term-resize eat-terminal 30 5)
            (eat-term-redisplay eat-terminal)
            (emacsvox-eat--observe-screen)
            (should (equal emacsvox-eat--pending-alternate-screen-transitions
                           '(t)))
            (should-not emacsvox-eat--completion-snapshot)
            (should-not emacsvox-eat--last-completion-output)
            (should-not emacsvox-eat--last-status-text)
            (setq pending-timer emacsvox-eat--quiescence-timer)
            (emacsvox-eat--finish-quiescence
             (current-buffer) emacsvox-eat--generation
             emacsvox-eat--update-serial)
            (should
             (equal (mapcar #'car (nreverse submissions))
                    '("Terminal application screen entered"))))
        (when (timerp pending-timer) (cancel-timer pending-timer))
        (emacsvox-eat--cancel-quiescence)
        (when (eat-term-live-p eat-terminal)
          (eat-term-delete eat-terminal))))))

(ert-deftest emacsvox-eat-rapid-alternate-screen-round-trip-keeps-boundaries ()
  "Entry and exit before quiescence are retained even if text is restored."
  (with-temp-buffer
    (let ((eat-terminal (eat-term-make (current-buffer) (point-min)))
          submissions
          pending-timer)
      (unwind-protect
          (cl-letf (((symbol-function 'emacsvox-eat--selected-buffer-p)
                     (lambda () t))
                    ((symbol-function 'emacsvox-eat--following-live-p)
                     (lambda () t))
                    ((symbol-function 'emacsvox-aural-submit)
                     (lambda (content &rest _)
                       (push content submissions))))
            (eat-term-process-output eat-terminal "Main")
            (eat-term-redisplay eat-terminal)
            (emacsvox-eat--observe-screen)
            (eat-term-process-output eat-terminal "\e[?1049hAlt")
            (eat-term-redisplay eat-terminal)
            (emacsvox-eat--observe-screen)
            (eat-term-process-output eat-terminal "\e[?1049l")
            (eat-term-redisplay eat-terminal)
            (emacsvox-eat--observe-screen)
            (should
             (equal emacsvox-eat--pending-alternate-screen-transitions
                    '(nil t)))
            (should (timerp emacsvox-eat--quiescence-timer))
            (setq pending-timer emacsvox-eat--quiescence-timer)
            (emacsvox-eat--finish-quiescence
             (current-buffer) emacsvox-eat--generation
             emacsvox-eat--update-serial)
            (should
             (equal (nreverse submissions)
                    '("Terminal application screen entered"
                      "Terminal application screen exited"))))
        (when (timerp pending-timer) (cancel-timer pending-timer))
        (emacsvox-eat--cancel-quiescence)
        (when (eat-term-live-p eat-terminal)
          (eat-term-delete eat-terminal))))))

(ert-deftest emacsvox-eat-alternate-screen-focus-loss-discards-delivery ()
  "An application boundary that loses selection stays private."
  (with-temp-buffer
    (let ((emacsvox-eat--generation 3)
          (emacsvox-eat--update-serial 7)
          (emacsvox-eat--quiescence-timer t)
          (emacsvox-eat--pending-screen-diff
           '(:alternate-screen-changed t :text-changed t))
          (emacsvox-eat--pending-alternate-screen-transitions '(t))
          (emacsvox-eat--screen-snapshot '(:alternate-screen t))
          submissions)
      (cl-letf (((symbol-function 'emacsvox-eat--selected-buffer-p)
                 (lambda () nil))
                ((symbol-function 'emacsvox-aural-submit)
                 (lambda (&rest arguments) (push arguments submissions))))
        (emacsvox-eat--finish-quiescence
         (current-buffer) emacsvox-eat--generation
         emacsvox-eat--update-serial))
      (should-not submissions)
      (should-not emacsvox-eat--pending-alternate-screen-transitions)
      (should-not emacsvox-eat--quiescence-timer))))

(ert-deftest emacsvox-eat-process-generations-clear-transient-state ()
  "Process start and matching exit invalidate asynchronous EAT state."
  (with-temp-buffer
    (let ((emacsvox-eat--generation 7)
          (emacsvox-eat--secure-input-active-p t)
          (emacsvox-eat--completion-snapshot '(12 . "stale"))
          (emacsvox-eat--completion-timer
           (run-at-time 60 nil #'ignore))
          (emacsvox-eat--screen-snapshot '(:generation 7 :text "stale"))
          (emacsvox-eat--pending-screen-baseline
           '(:generation 7 :text "older"))
          (emacsvox-eat--pending-screen-diff '(:changes (text)))
          (emacsvox-eat--pending-alternate-screen-transitions '(t))
          (emacsvox-eat--pending-user-input-p t)
          (emacsvox-eat--recent-navigation-intent
           '(:generation 7 :direction down :deadline 9999999999.0))
          (emacsvox-eat--pending-navigation-intent
           '(:generation 7 :direction down :deadline 9999999999.0))
          (emacsvox-eat--quiescence-started-at 10.0)
          (emacsvox-eat--last-status-text "Progress 40%")
          (emacsvox-eat--last-status-spoken-at 20.0)
          (emacsvox-eat--last-completion-output
           '(:rows ("stale candidate")))
          (emacsvox-eat--last-likely-focus
           '(:kind highlight :text "stale focus"))
          (emacsvox-eat--last-focus-presentation-identity
           '(highlight 7 1 0 selected "stale focus"))
          (emacsvox-eat--last-bell-at 19.0)
          (emacsvox-eat--last-bell-spoken-at 18.0)
          (emacsvox-eat--last-metadata-change
           '(:title "stale title" :cwd "/stale/"))
          (emacsvox-eat--last-metadata-spoken-at 17.0)
          (emacsvox-eat--background-output-pending-p t)
          (emacsvox-eat--background-output-timer
           (run-at-time 60 nil #'ignore))
          (emacsvox-eat--unread-output-count 6)
          (emacsvox-eat--last-background-cue-at 16.0)
          (emacsvox-eat--quiescence-timer
           (run-at-time 60 nil #'ignore))
          process-a process-b)
      (setq process-a (make-symbol "process-a")
            process-b (make-symbol "process-b"))
      (emacsvox-eat--process-started process-a)
      (should (= emacsvox-eat--generation 8))
      (should (eq emacsvox-eat--active-process process-a))
      (should-not emacsvox-eat--secure-input-active-p)
      (should-not emacsvox-eat--completion-snapshot)
      (should-not emacsvox-eat--completion-timer)
      (should-not emacsvox-eat--screen-snapshot)
      (should-not emacsvox-eat--pending-screen-baseline)
      (should-not emacsvox-eat--pending-screen-diff)
      (should-not emacsvox-eat--pending-alternate-screen-transitions)
      (should-not emacsvox-eat--pending-user-input-p)
      (should-not emacsvox-eat--recent-navigation-intent)
      (should-not emacsvox-eat--pending-navigation-intent)
      (should-not emacsvox-eat--quiescence-started-at)
      (should-not emacsvox-eat--quiescence-timer)
      (should-not emacsvox-eat--last-status-text)
      (should (= emacsvox-eat--last-status-spoken-at 0.0))
      (should-not emacsvox-eat--last-completion-output)
      (should-not emacsvox-eat--last-likely-focus)
      (should-not emacsvox-eat--last-focus-presentation-identity)
      (should-not emacsvox-eat--last-bell-at)
      (should-not emacsvox-eat--last-bell-spoken-at)
      (should-not emacsvox-eat--last-metadata-change)
      (should-not emacsvox-eat--last-metadata-spoken-at)
      (should-not emacsvox-eat--background-output-pending-p)
      (should-not emacsvox-eat--background-output-timer)
      (should (= emacsvox-eat--unread-output-count 0))
      (should-not emacsvox-eat--last-background-cue-at)
      (setq emacsvox-eat--completion-snapshot '(13 . "pending"))
      (emacsvox-eat--process-exited process-b)
      (should (= emacsvox-eat--generation 8))
      (should emacsvox-eat--completion-snapshot)
      (emacsvox-eat--process-exited process-a)
      (should (= emacsvox-eat--generation 9))
      (should-not emacsvox-eat--active-process)
      (should-not emacsvox-eat--completion-snapshot)
      (setq emacsvox-eat--completion-snapshot '(14 . "new"))
      (emacsvox-eat--process-exited process-a)
      (should (= emacsvox-eat--generation 9))
      (should emacsvox-eat--completion-snapshot))))

(ert-deftest emacsvox-eat-process-lifecycle-is-semantic-and-singular ()
  "Selected process exit and restart use singular native lifecycle events."
  (with-temp-buffer
    (let ((emacsvox-eat--generation 0)
          submissions
          process-a process-b)
      (setq process-a (make-symbol "process-a")
            process-b (make-symbol "process-b"))
      (cl-letf (((symbol-function 'emacsvox-eat--selected-buffer-p)
                 (lambda () t))
                ((symbol-function 'process-status)
                 (lambda (process)
                   (should (memq process (list process-a process-b)))
                   'exit))
                ((symbol-function 'process-exit-status)
                 (lambda (_process) 0))
                ((symbol-function 'emacsvox-aural-compatibility-icon)
                 (lambda (icon) (list 'icon icon)))
                ((symbol-function 'emacsvox-aural-submit)
                 (lambda (content &rest arguments)
                   (setq submissions
                         (append
                          submissions
                          (list (list content arguments)))))))
        ;; Initial exec is already covered by the interactive `eat' opening.
        (emacsvox-eat--process-started process-a)
        (should-not submissions)
        (emacsvox-eat--process-exited process-a)
        (emacsvox-eat--process-exited process-a)
        (emacsvox-eat--process-started process-b))
      (should
       (equal
        submissions
        '(("Terminal process exited"
           (:facts
            (:role command-interaction
             :command-interaction-kind shell
             :events (command-process-exited)
             :command-operation process-exit
             :command-exit-status 0)
            :module eat
            :occasion notification
            :compatibility-actions ((icon close-object))))
          ("Terminal process restarted"
           (:facts
            (:role command-interaction
             :command-interaction-kind shell
             :events (operation-started))
            :module eat
            :occasion state-change
            :compatibility-actions ((icon open-object))))))))))

(ert-deftest emacsvox-eat-eshell-lifecycle-is-shared-without-start-chatter ()
  "Embedded Eshell processes share state while each command start stays quiet."
  (with-temp-buffer
    (setq major-mode 'eshell-mode)
    (let ((eat-terminal (eat-term-make (current-buffer) (point-min)))
          process
          submissions)
      (unwind-protect
          (progn
            (setq process
                  (make-pipe-process
                   :name "emacsvox-eat-eshell-lifecycle"
                   :buffer (current-buffer) :noquery t))
            (eat-term-resize eat-terminal 24 4)
            (cl-letf (((symbol-function 'emacsvox-eat--selected-buffer-p)
                       (lambda () t))
                      ((symbol-function 'emacsvox-aural-submit)
                       (lambda (content &rest arguments)
                         (push (list content arguments) submissions))))
              (emacsvox-eat--eshell-process-started)
              (should (= emacsvox-eat--generation 1))
              (should (eq emacsvox-eat--active-process process))
              (should emacsvox-eat--eshell-output-owned-p)
              (should emacsvox-eat--screen-snapshot)
              (should-not submissions)
              (cl-letf (((symbol-function 'process-status)
                         (lambda (candidate)
                           (should (eq candidate process))
                           'exit))
                        ((symbol-function 'process-exit-status)
                         (lambda (candidate)
                           (should (eq candidate process))
                           0)))
                (emacsvox-eat--eshell-process-exited)))
            (should (= emacsvox-eat--generation 2))
            (should-not emacsvox-eat--active-process)
            (should emacsvox-eat--eshell-output-owned-p)
            (should-not emacsvox-eat--screen-snapshot)
            (should
             (equal (mapcar #'car submissions)
                    '("Terminal process exited")))
            (emacsvox-eat--eshell-prompt-ready)
            (should-not emacsvox-eat--eshell-output-owned-p))
        (when (and process (process-live-p process))
          (delete-process process))
        (emacsvox-eat--cancel-quiescence)
        (when (eat-term-live-p eat-terminal)
          (eat-term-delete eat-terminal))))))

(ert-deftest emacsvox-eat-eshell-update-speaks-one-rendered-output-transaction ()
  "The shared hook presents EAT-rendered Eshell output once and ignores resize."
  (with-temp-buffer
    (setq major-mode 'eshell-mode)
    (let ((eat-terminal (eat-term-make (current-buffer) (point-min)))
          submissions)
      (unwind-protect
          (cl-letf (((symbol-function 'emacsvox-eat--selected-buffer-p)
                     (lambda () t))
                    ((symbol-function 'emacsvox-eat--following-live-p)
                     (lambda () t))
                    ((symbol-function 'emacsvox-aural-submit)
                     (lambda (content &rest arguments)
                       (push (list content arguments) submissions))))
            (eat-term-resize eat-terminal 30 5)
            (emacsvox-eat--setup-buffer-state)
            (should (emacsvox-eat--terminal-buffer-p))
            (setq emacsvox-eat--screen-snapshot
                  (emacsvox-eat--capture-screen))
            (emacsvox-eat-test--deliver-screen
             eat-terminal "\r\none\r\ntwo\r\n")
            (should (= (length submissions) 1))
            (should (equal (caar submissions) "one\ntwo"))
            (should
             (equal
              (plist-get (cadar submissions) :facts)
              '(:role command-output
                :command-interaction-kind shell
                :events (command-output-received))))
            (eat-term-resize eat-terminal 40 6)
            (eat-term-redisplay eat-terminal)
            (emacsvox-eat-update-hook)
            (emacsvox-eat-test--finish-screen-burst)
            (should (= (length submissions) 1)))
        (emacsvox-eat--cancel-quiescence)
        (when (eat-term-live-p eat-terminal)
          (eat-term-delete eat-terminal))))))

(ert-deftest emacsvox-eat-real-eshell-process-is-singular-and-restores-generic-hook ()
  "A disposable EAT-backed Eshell command has one output owner end to end."
  (require 'emacsvox-eshell)
  (let ((buffer (generate-new-buffer " *emacsvox-eat-real-eshell*"))
        (was-enabled eat-eshell-mode)
        submissions
        generic-output-calls
        started)
    (unwind-protect
        (save-window-excursion
          (switch-to-buffer buffer)
          (eshell-mode)
          (cl-letf (((symbol-function 'emacsvox-aural-submit)
                     (lambda (content &rest arguments)
                       (push (list (substring-no-properties content)
                                   arguments)
                             submissions)))
                    ((symbol-function 'emacsvox-speak-region)
                     (lambda (&rest arguments)
                       (push arguments generic-output-calls)))
                    ((symbol-function 'emacsvox-icon) #'ignore)
                    ((symbol-function 'tts-speak) #'ignore))
            (unless was-enabled (eat-eshell-mode 1))
            (goto-char (point-max))
            (insert
             (concat
              "python3 -c \"import time;print(111);print(222);"
              "time.sleep(.1)\""))
            (eshell-send-input)
            (setq started (not (null eat-terminal)))
            (should
             (emacsvox-eat-test--wait-until
              nil
              (lambda ()
                (when eat-terminal (setq started t))
                (and started (null eat-terminal)))
              5.0))
            (should started)
            (should-not eat-terminal)
            (should-not generic-output-calls)
            (should
             (equal
              (mapcar #'car (nreverse submissions))
              '("111\n222" "Terminal process exited")))
            (should
             (memq #'emacsvox-eshell-speak-output
                   eshell-output-filter-functions))
            (should (string-match-p "111\n222" (buffer-string)))
            (should (= emacsvox-eat--generation 2))
            (should-not emacsvox-eat--eshell-output-owned-p)
            (should-not emacsvox-eat--active-process)))
      (when (buffer-live-p buffer)
        (when-let* ((process (get-buffer-process buffer))
                    ((process-live-p process)))
          (delete-process process))
        (kill-buffer buffer))
      (when (and (not was-enabled) eat-eshell-mode)
        (eat-eshell-mode -1)))))

(ert-deftest emacsvox-eat-eshell-background-update-remains-private ()
  "An embedded terminal retains background output without speaking content."
  (with-temp-buffer
    (setq major-mode 'eshell-mode)
    (let ((eat-terminal (eat-term-make (current-buffer) (point-min)))
          submissions)
      (unwind-protect
          (progn
            (eat-term-resize eat-terminal 30 4)
            (emacsvox-eat--setup-buffer-state)
            (setq emacsvox-eat--screen-snapshot
                  (emacsvox-eat--capture-screen))
            (cl-letf (((symbol-function 'emacsvox-eat--selected-buffer-p)
                       (lambda () nil))
                      ((symbol-function 'emacsvox-aural-submit)
                       (lambda (&rest arguments)
                         (push arguments submissions))))
              (eat-term-process-output eat-terminal "private\r\n")
              (eat-term-redisplay eat-terminal)
              (emacsvox-eat-update-hook))
            (should-not submissions)
            (should
             (string-match-p
              "private" (plist-get emacsvox-eat--screen-snapshot :text)))
            (should-not emacsvox-eat--quiescence-timer))
        (emacsvox-eat--cancel-quiescence)
        (when (eat-term-live-p eat-terminal)
          (eat-term-delete eat-terminal))))))

(ert-deftest emacsvox-eat-background-lifecycle-is-private-by-default ()
  "Background process lifecycle advances state without disclosing content."
  (with-temp-buffer
    (let ((emacsvox-eat--generation 0)
          submissions
          (process (make-symbol "background-process")))
      (cl-letf (((symbol-function 'emacsvox-eat--selected-buffer-p)
                 (lambda () nil))
                ((symbol-function 'emacsvox-aural-submit)
                 (lambda (&rest arguments) (push arguments submissions))))
        (emacsvox-eat--process-started process)
        (emacsvox-eat--process-exited process))
      (should (= emacsvox-eat--generation 2))
      (should-not emacsvox-eat--active-process)
      (should-not submissions))))

(ert-deftest emacsvox-eat-signalled-process-uses-warning-lifecycle ()
  "A signalled terminal process is distinct from a normal exit."
  (with-temp-buffer
    (let* ((process (make-symbol "signalled-process"))
           (emacsvox-eat--generation 1)
           (emacsvox-eat--active-process process)
           submission)
      (cl-letf (((symbol-function 'emacsvox-eat--selected-buffer-p)
                 (lambda () t))
                ((symbol-function 'process-status)
                 (lambda (_process) 'signal))
                ((symbol-function 'process-exit-status)
                 (lambda (_process) 9))
                ((symbol-function 'emacsvox-aural-compatibility-icon)
                 (lambda (icon) (list 'icon icon)))
                ((symbol-function 'emacsvox-aural-submit)
                 (lambda (content &rest arguments)
                   (setq submission (list content arguments)))))
        (emacsvox-eat--process-exited process))
      (should
       (equal
        submission
        '("Terminal process ended by signal 9"
          (:facts
           (:role command-interaction
            :command-interaction-kind shell
            :events (command-process-exited)
            :command-operation process-exit
            :command-exit-status 9)
           :module eat
           :occasion notification
           :compatibility-actions ((icon warn-user)))))))))

(ert-deftest emacsvox-eat-output-uses-one-native-bounded-transaction ()
  "Terminal rows use command-output semantics, sanitization, and hard caps."
  (let ((emacsvox-eat--maximum-output-lines 2)
        (emacsvox-eat--maximum-output-characters 20)
        submissions)
    (cl-letf (((symbol-function 'emacsvox-aural-submit)
               (lambda (content &rest arguments)
                 (push (list content arguments) submissions))))
      (emacsvox-eat--present-output-rows
       (list (concat "one" (string 1) "unsafe")
             "second line is deliberately long"
             "third")))
    (should (= (length submissions) 1))
    (let ((content (caar submissions))
          (arguments (cadar submissions)))
      (should (equal content
                     "one unsafe\nsecond li … output truncated\n1 additional lines not spoken"))
      (should
       (equal
        arguments
        '(:facts
          (:role command-output
           :command-interaction-kind shell
           :events (command-output-received))
          :module eat
          :occasion continuous
          :compatibility-actions nil))))))

(ert-deftest emacsvox-eat-output-suppresses-empty-presentations ()
  "Whitespace-only terminal changes do not submit empty speech."
  (let (submissions)
    (cl-letf (((symbol-function 'emacsvox-aural-submit)
               (lambda (&rest arguments) (push arguments submissions))))
      (emacsvox-eat--present-output-rows '("" "   ")))
    (should-not submissions)))

(ert-deftest emacsvox-eat-terse-suppresses-routine-output-but-retains-it ()
  "Terse terminals retain output and status without automatic speech."
  (with-temp-buffer
    (let* ((emacsvox-eat-verbosity 'terse)
           (output-diff
            '(:text-changed t :size-changed nil
              :alternate-screen-changed nil
              :old-rows ("$ command")
              :new-rows ("$ command" "result" "$ ")
              :row-change
              (:start 1 :old-end 1 :new-end 3 :old-rows nil
               :new-rows ("result" "$ "))))
           (output-snapshot '(:cursor-row 2 :alternate-screen nil))
           (status-diff
            '(:text-changed t :user-input nil :size-changed nil
              :alternate-screen-changed nil
              :row-change
              (:start 0 :old-rows ("Progress 10%")
               :new-rows ("Progress 20%"))))
           (status-snapshot '(:cursor-row 0 :alternate-screen nil))
           submissions)
      (cl-letf (((symbol-function 'emacsvox-aural-submit)
                 (lambda (&rest arguments) (push arguments submissions))))
        (emacsvox-eat--screen-quiesced output-diff output-snapshot)
        (emacsvox-eat--screen-quiesced status-diff status-snapshot)
        (should-not submissions)
        (should (eq emacsvox-eat--last-screen-diff status-diff))
        (should (equal emacsvox-eat--last-status-text "Progress 20%"))
        (setq emacsvox-eat-verbosity 'normal)
        (emacsvox-eat--screen-quiesced output-diff output-snapshot))
      (should (= (length submissions) 1))
      (should (equal (caar submissions) "result")))))

(ert-deftest emacsvox-eat-output-classifier-excludes-the-prompt-row ()
  "Only newly inserted complete main-screen rows before the cursor qualify."
  (let* ((diff
          '(:text-changed t :size-changed nil
            :alternate-screen-changed nil
            :old-rows ("$ command")
            :new-rows ("$ command" "one" "two" "$ ")
            :row-change
            (:start 1 :old-end 1 :new-end 4 :old-rows nil
             :new-rows ("one" "two" "$ "))))
         (snapshot '(:cursor-row 3 :alternate-screen nil)))
    (should
     (equal (emacsvox-eat--complete-output-rows diff snapshot)
            '("one" "two")))
    (dolist (change '(:size-changed :alternate-screen-changed))
      (let ((changed (copy-tree diff)))
        (setf (plist-get changed change) t)
        (should-not
         (emacsvox-eat--complete-output-rows changed snapshot))))
    (let ((alternate (copy-tree snapshot)))
      (setf (plist-get alternate :alternate-screen) t)
      (should-not (emacsvox-eat--complete-output-rows diff alternate)))
    (let ((replacement (copy-tree diff)))
      (setf (plist-get replacement :old-rows) '("old status")
            (plist-get replacement :new-rows) '("new status")
            (plist-get (plist-get replacement :row-change) :start) 0
            (plist-get (plist-get replacement :row-change) :old-rows)
            '("old status")
            (plist-get (plist-get replacement :row-change) :new-rows)
            '("new status")
            (plist-get snapshot :cursor-row) 1)
      (should-not
       (emacsvox-eat--complete-output-rows replacement snapshot)))))

(ert-deftest emacsvox-eat-output-row-overlap-is-linear-and-scroll-aware ()
  "Row overlap recognizes the unchanged suffix shifted to the screen top."
  (should
   (= (emacsvox-eat--suffix-prefix-row-overlap
       '("old" "same" "same" "$ command")
       '("same" "same" "$ command" "output" "$ "))
      3))
  (should
   (= (emacsvox-eat--suffix-prefix-row-overlap
       '("a" "b") '("different" "rows"))
      0))
  (should
   (= (emacsvox-eat--suffix-prefix-row-overlap nil '("new")) 0))
  (should
   (= (emacsvox-eat--suffix-prefix-row-overlap '("old") nil) 0)))

(ert-deftest emacsvox-eat-output-classifier-handles-scroll-without-repetition ()
  "A shifted visible screen presents only rows following its old suffix."
  (let* ((diff
          '(:text-changed t :size-changed nil
            :alternate-screen-changed nil
            :old-rows ("history one" "history two" "$ command")
            :new-rows ("history two" "$ command" "result" "$ ")
            :row-change
            (:start 0 :old-end 3 :new-end 4
             :old-rows ("history one" "history two" "$ command")
             :new-rows ("history two" "$ command" "result" "$ "))))
         (snapshot '(:cursor-row 3 :alternate-screen nil)))
    (should
     (equal (emacsvox-eat--complete-output-rows diff snapshot)
            '("result")))
    (let ((repaint (copy-tree diff)))
      (setf (plist-get repaint :new-rows)
            '("new heading" "new body" "$ ")
            (plist-get (plist-get repaint :row-change) :new-rows)
            '("new heading" "new body" "$ "))
      (should-not
       (emacsvox-eat--complete-output-rows repaint snapshot)))))

(ert-deftest emacsvox-eat-status-classifier-is-conservative ()
  "Only recognizable, non-input same-row main-screen updates are status."
  (let* ((diff
          '(:text-changed t :user-input nil :size-changed nil
            :alternate-screen-changed nil
            :row-change
            (:start 0 :old-rows ("Progress 0%")
             :new-rows ("Progress 10%"))))
         (snapshot '(:cursor-row 0 :alternate-screen nil)))
    (should
     (equal (emacsvox-eat--status-row diff snapshot) "Progress 10%"))
    (dolist (change '(:user-input :size-changed :alternate-screen-changed))
      (let ((changed (copy-tree diff)))
        (setf (plist-get changed change) t)
        (should-not (emacsvox-eat--status-row changed snapshot))))
    (let ((alternate (copy-tree snapshot)))
      (setf (plist-get alternate :alternate-screen) t)
      (should-not (emacsvox-eat--status-row diff alternate)))
    (let ((ordinary (copy-tree diff)))
      (setf (plist-get (plist-get ordinary :row-change) :new-rows)
            '("ordinary replacement"))
      (should-not (emacsvox-eat--status-row ordinary snapshot)))))

(ert-deftest emacsvox-eat-application-status-is-retained-but-not-automatic ()
  "Only styled bottom-row application status qualifies for explicit review."
  (let* ((diff
          '(:text-changed t :user-input t :size-changed nil
            :alternate-screen-changed nil
            :row-change
            (:start 1 :old-rows ("NORMAL")
             :new-rows ("-- INSERT --"))))
         (snapshot
          '(:text "alpha\n-- INSERT --"
            :rows ("alpha" "-- INSERT --")
            :styles
            ((6 18
              (:face (:attributes ((:background . "selected")))
               :traits (background-color))))
            :cursor-row 0 :alternate-screen t)))
    (should-not (emacsvox-eat--status-row diff snapshot))
    (should
     (equal (emacsvox-eat--application-status-row diff snapshot)
            "-- INSERT --"))
    (should
     (equal (emacsvox-eat--retained-status-row diff snapshot)
            "-- INSERT --"))
    (let ((unstyled (copy-tree snapshot)))
      (setf (plist-get unstyled :styles) nil)
      (should-not (emacsvox-eat--application-status-row diff unstyled)))
    (let ((cursor-status (copy-tree snapshot)))
      (setf (plist-get cursor-status :cursor-row) 1)
      (should-not
       (emacsvox-eat--application-status-row diff cursor-status)))
    (let ((ordinary (copy-tree diff)))
      (setf (plist-get (plist-get ordinary :row-change) :new-rows)
            '("Selected"))
      (should-not (emacsvox-eat--application-status-row ordinary snapshot)))
    (let ((resized (copy-tree diff)))
      (setf (plist-get resized :size-changed) t)
      (should-not (emacsvox-eat--application-status-row resized snapshot)))))

(ert-deftest emacsvox-eat-status-is-rate-limited-and-replaceable ()
  "Intermediate progress is throttled while completion remains immediate."
  (with-temp-buffer
    (let ((emacsvox-eat--generation 4)
          (emacsvox-eat--last-status-spoken-at 0.0)
          (times '(100.0 100.5 100.6))
          submissions)
      (cl-letf (((symbol-function 'float-time)
                 (lambda (&optional _) (pop times)))
                ((symbol-function 'emacsvox-aural-submit)
                 (lambda (content &rest arguments)
                   (push (list content arguments) submissions))))
        (emacsvox-eat--present-status "Progress 10%")
        (emacsvox-eat--present-status "Progress 20%")
        (emacsvox-eat--present-status "Progress 100%"))
      (setq submissions (nreverse submissions))
      (should
       (equal (mapcar #'car submissions)
              '("Progress 10%" "Progress 100%")))
      (should (equal emacsvox-eat--last-status-text "Progress 100%"))
      (let* ((oldest-arguments (cadr (car submissions)))
             (newest-arguments (cadr (car (last submissions))))
             (oldest-key
              (plist-get oldest-arguments :replacement-key))
             (newest-key
              (plist-get newest-arguments :replacement-key)))
        (should
         (eq (plist-get newest-arguments :delivery-policy) 'replaceable))
        (should (equal oldest-key newest-key))
        (should (equal (butlast newest-key 2) '(eat status)))
        (should (= (car (last newest-key)) 4))))))

(ert-deftest emacsvox-eat-metadata-is-retained-below-verbose ()
  "Normal and terse terminals retain metadata without announcing it."
  (dolist (verbosity '(terse normal))
    (with-temp-buffer
      (let ((emacsvox-eat-verbosity verbosity)
            submissions)
        (cl-letf (((symbol-function 'emacsvox-aural-submit)
                   (lambda (&rest arguments) (push arguments submissions))))
          (emacsvox-eat--screen-quiesced
           '(:title-changed t :cwd-changed t)
           '(:generation 3 :title "Router" :cwd "/srv/config/")))
        (should-not submissions)
        (should
         (equal
          (plist-get emacsvox-eat--last-metadata-change :generation) 3))
        (should
         (equal
          (plist-get emacsvox-eat--last-metadata-change :title) "Router"))
        (should
         (equal
          (plist-get emacsvox-eat--last-metadata-change :cwd)
          "/srv/config/"))))))

(ert-deftest emacsvox-eat-verbose-metadata-is-semantic-and-replaceable ()
  "Verbose terminals announce one bounded title and directory transaction."
  (with-temp-buffer
    (let ((emacsvox-eat-verbosity 'verbose)
          (emacsvox-eat--generation 4)
          submissions)
      (cl-letf (((symbol-function 'emacsvox-aural-submit)
                 (lambda (content &rest arguments)
                   (push (list content arguments) submissions))))
        (emacsvox-eat--screen-quiesced
         '(:title-changed t :cwd-changed t)
         '(:generation 4 :title "Router" :cwd "/srv/config/")))
      (should (= (length submissions) 1))
      (let* ((submission (car submissions))
             (arguments (cadr submission))
             (key (plist-get arguments :replacement-key)))
        (should
         (equal
          (car submission)
          "Terminal title: Router\nWorking directory: /srv/config/"))
        (should
         (equal
          (plist-get arguments :facts)
          '(:role command-interaction
            :command-interaction-kind shell
            :events (state-changed))))
        (should (eq (plist-get arguments :occasion) 'state-change))
        (should (eq (plist-get arguments :delivery-policy) 'replaceable))
        (should (equal (butlast key 2) '(eat metadata)))
        (should (= (car (last key)) 4))))))

(ert-deftest emacsvox-eat-verbose-metadata-is-rate-limited ()
  "Rapid metadata changes retain replaceable speech bandwidth."
  (with-temp-buffer
    (let ((emacsvox-eat-verbosity 'verbose)
          (emacsvox-eat--generation 2)
          (times '(100.0 100.5 101.1))
          submissions)
      (cl-letf (((symbol-function 'float-time)
                 (lambda (&optional _) (pop times)))
                ((symbol-function 'emacsvox-aural-submit)
                 (lambda (content &rest _)
                   (push content submissions))))
        (dolist (title '("one" "two" "three"))
          (emacsvox-eat--present-metadata-change
           '(:title-changed t) (list :title title))))
      (should (equal (nreverse submissions)
                     '("Terminal title: one" "Terminal title: three")))
      (should (= emacsvox-eat--last-metadata-spoken-at 101.1)))))

(ert-deftest emacsvox-eat-real-carriage-return-is-status-not-output ()
  "A real EAT carriage-return rewrite is retained as a status row."
  (with-temp-buffer
    (let ((eat-terminal (eat-term-make (current-buffer) (point-min))))
      (unwind-protect
          (progn
            (eat-term-resize eat-terminal 30 3)
            (eat-term-process-output eat-terminal "Progress 0%")
            (eat-term-redisplay eat-terminal)
            (let ((old (emacsvox-eat--capture-screen)))
              (eat-term-process-output eat-terminal "\rProgress 10%")
              (eat-term-redisplay eat-terminal)
              (let* ((new (emacsvox-eat--capture-screen))
                     (diff (emacsvox-eat--screen-diff old new)))
                (should-not
                 (emacsvox-eat--complete-output-rows diff new))
                (should
                 (equal (emacsvox-eat--status-row diff new)
                        "Progress 10%")))))
        (when (eat-term-live-p eat-terminal)
          (eat-term-delete eat-terminal))))))

(ert-deftest emacsvox-eat-real-multiline-output-is-one-quiesced-transaction ()
  "A real terminal screen presents complete result rows and omits its prompt."
  (with-temp-buffer
    (let ((eat-terminal (eat-term-make (current-buffer) (point-min)))
          submissions
          pending-timer)
      (unwind-protect
          (cl-letf (((symbol-function 'emacsvox-eat--selected-buffer-p)
                     (lambda () t))
                    ((symbol-function 'emacsvox-eat--following-live-p)
                     (lambda () t))
                    ((symbol-function 'emacsvox-aural-submit)
                     (lambda (content &rest arguments)
                       (push (list content arguments) submissions))))
            (eat-term-resize eat-terminal 40 8)
            (eat-term-process-output eat-terminal "$ command")
            (eat-term-redisplay eat-terminal)
            (emacsvox-eat--observe-screen)
            (eat-term-process-output
             eat-terminal "\r\none\r\ntwo\r\n$ ")
            (eat-term-redisplay eat-terminal)
            (emacsvox-eat--observe-screen)
            (setq pending-timer emacsvox-eat--quiescence-timer)
            (emacsvox-eat--finish-quiescence
             (current-buffer) emacsvox-eat--generation
             emacsvox-eat--update-serial)
            (should (= (length submissions) 1))
            (should (equal (caar submissions) "one\ntwo"))
            (should
             (equal
              (plist-get (cadar submissions) :facts)
              '(:role command-output
                :command-interaction-kind shell
                :events (command-output-received))))
            (should emacsvox-eat--last-screen-diff)
            (should emacsvox-eat--last-changed-screen))
        (when (timerp pending-timer) (cancel-timer pending-timer))
        (emacsvox-eat--cancel-quiescence)
        (when (eat-term-live-p eat-terminal)
          (eat-term-delete eat-terminal))))))

(ert-deftest emacsvox-eat-screen-snapshot-uses-public-visible-state ()
  "A screen snapshot captures visible text, cursor, style, and metadata."
  (with-temp-buffer
    (let ((eat-terminal (eat-term-make (current-buffer) (point-min)))
          (emacsvox-eat--generation 6))
      (unwind-protect
          (progn
            (eat-term-resize eat-terminal 20 4)
            (eat-term-process-output
             eat-terminal
             "\e]2;Audit title\a\e[1mBold\e[0m \e[4mUnder\e[0m")
            (eat-term-redisplay eat-terminal)
            (let* ((snapshot (emacsvox-eat--capture-screen))
                   (styles (plist-get snapshot :styles))
                   (style-data (mapcar #'caddr styles)))
              (should (= (plist-get snapshot :generation) 6))
              (should (= (plist-get snapshot :style-version) 1))
              (should (integerp (plist-get snapshot :display-beginning)))
              (should (integerp (plist-get snapshot :display-end)))
              (should (equal (plist-get snapshot :text) "Bold Under"))
              (should (equal (plist-get snapshot :rows) '("Bold Under")))
              (should (equal (plist-get snapshot :size) '(20 . 4)))
              (should (equal (plist-get snapshot :title) "Audit title"))
              (should-not (plist-get snapshot :alternate-screen))
              (should (= (plist-get snapshot :cursor-row) 0))
              (should (= (plist-get snapshot :cursor-column) 10))
              (should (= (plist-get snapshot :cursor-offset) 10))
              (should
               (seq-some
                (lambda (style)
                  (memq
                   'eat-term-bold
                   (plist-get (plist-get style :face) :faces)))
                style-data))
              (should
               (seq-some
                (lambda (style)
                  (alist-get
                   :underline
                   (plist-get
                    (plist-get style :face) :attributes)))
                style-data))
              (should
               (equal (emacsvox-eat-test--traits-for-text snapshot "Bold")
                      '(bold)))
              (should
               (equal (emacsvox-eat-test--traits-for-text snapshot "Under")
                      '(underline))))
        (when (eat-term-live-p eat-terminal)
          (eat-term-delete eat-terminal)))))))

(ert-deftest emacsvox-eat-style-traits-normalize-rendered-properties ()
  "Named and anonymous rendered faces produce stable semantic traits."
  (cl-letf (((symbol-function 'face-foreground)
             (lambda (&rest _) "default-fg"))
            ((symbol-function 'face-background)
             (lambda (&rest _) "default-bg")))
    (should
     (equal
      (emacsvox-eat--style-traits
       '(:faces (eat-term-bold eat-term-faint eat-term-italic
                 eat-term-slow-blink eat-term-font-2)
         :attributes
         ((:underline :style wave) (:strike-through . t)
          (:foreground . "default-bg") (:background . "default-fg")
          (:overline . t) (:box . line)))
       '(:faces (highlight)) t)
      '(bold faint italic underline blink crossed-out inverse-like
        foreground-color background-color alternate-font overline boxed
        mouse-highlight interactive)))
    (should
     (equal
      (emacsvox-eat--style-traits
       '(:attributes ((:foreground . "same") (:background . "same")))
       nil nil)
      '(concealed foreground-color background-color)))))

(ert-deftest emacsvox-eat-concealed-redaction-preserves-screen-coordinates ()
  "Concealed cells are blanked without changing offsets or row boundaries."
  (let* ((text "shown\nsecret\nend")
         (styles '((6 12 (:traits (concealed foreground-color)))))
         (redacted (emacsvox-eat--redact-concealed-text text styles)))
    (should (equal redacted "shown\n      \nend"))
    (should (= (length redacted) (length text)))
    (should (= (aref redacted 5) ?\n))
    (should (= (aref redacted 12) ?\n))
    (should-not (string-match-p "secret" redacted))
    (should (equal text "shown\nsecret\nend"))))

(ert-deftest emacsvox-eat-real-concealed-output-is-never-retained-or-spoken ()
  "A real EAT conceal sequence cannot disclose its underlying characters."
  (with-temp-buffer
    (let ((eat-terminal (eat-term-make (current-buffer) (point-min)))
          (secret "terminal-secret-sentinel")
          submissions)
      (unwind-protect
          (progn
            (eat-term-resize eat-terminal 50 5)
            (eat-term-process-output eat-terminal "$ ")
            (eat-term-redisplay eat-terminal)
            (let ((old (emacsvox-eat--capture-screen)))
              (eat-term-process-output
               eat-terminal
               (concat "\r\nvisible \e[8m" secret "\e[0m\r\n$ "))
              (eat-term-redisplay eat-terminal)
              (should (string-match-p secret (buffer-string)))
              (let* ((new (emacsvox-eat--capture-screen))
                     (diff (emacsvox-eat--screen-diff old new)))
                (should-not (string-match-p secret (format "%S" new)))
                (cl-letf (((symbol-function 'emacsvox-aural-submit)
                           (lambda (content &rest arguments)
                             (push (list content arguments) submissions))))
                  (emacsvox-eat--screen-quiesced diff new))
                (should (= (length submissions) 1))
                (should (string-match-p "visible" (caar submissions)))
                (should-not
                 (string-match-p
                  secret
                  (format
                   "%S"
                   (list submissions emacsvox-eat--last-screen-diff
                         emacsvox-eat--last-changed-screen)))))))
        (when (eat-term-live-p eat-terminal)
          (eat-term-delete eat-terminal))))))

(ert-deftest emacsvox-eat-real-inverse-move-is-a-likely-highlight ()
  "A real EAT SGR inverse transfer is classified from public snapshots."
  (with-temp-buffer
    (let ((eat-terminal (eat-term-make (current-buffer) (point-min))))
      (unwind-protect
          (progn
            (eat-term-resize eat-terminal 30 4)
            (eat-term-process-output
             eat-terminal
             "\e[?1049h\e[2J\e[H\e[7mOne\e[0m\r\nTwo")
            (eat-term-redisplay eat-terminal)
            (let ((old (emacsvox-eat--capture-screen)))
              (eat-term-process-output
               eat-terminal
               "\e[1;1H\e[0mOne\e[2;1H\e[7mTwo\e[0m")
              (eat-term-redisplay eat-terminal)
              (let* ((new (emacsvox-eat--capture-screen))
                     (diff (emacsvox-eat--screen-diff old new))
                     (focus
                      (emacsvox-eat--likely-focus-change
                       old new diff
                       '(:generation 0 :direction down))))
                (should-not (plist-get diff :text-changed))
                (should (plist-get diff :style-changed))
                (should (eq (plist-get focus :kind) 'highlight))
                (should (equal (plist-get focus :text) "Two"))
                (should (eq (plist-get focus :confidence) 'high)))))
        (when (eat-term-live-p eat-terminal)
          (eat-term-delete eat-terminal))))))

(ert-deftest emacsvox-eat-real-navigation-speaks-one-replaceable-highlight ()
  "A real input/update/quiescence path presents one inferred highlight."
  (with-temp-buffer
    (let ((eat-terminal (eat-term-make (current-buffer) (point-min)))
          submissions
          pending-timer)
      (unwind-protect
          (cl-letf (((symbol-function 'emacsvox-eat--selected-buffer-p)
                     (lambda () t))
                    ((symbol-function 'emacsvox-eat--following-live-p)
                     (lambda () t))
                    ((symbol-function 'emacsvox-aural-submit)
                     (lambda (content &rest arguments)
                       (push (list content arguments) submissions))))
            (eat-term-resize eat-terminal 30 4)
            (eat-term-process-output
             eat-terminal
             "\e[?1049h\e[2J\e[H\e[7mOne\e[0m\r\nTwo")
            (eat-term-redisplay eat-terminal)
            (emacsvox-eat-update-hook)
            (should-not submissions)
            (emacsvox--advice-eat-self-input-before 1 'down)
            (eat-term-process-output
             eat-terminal
             "\e[1;1H\e[0mOne\e[2;1H\e[7mTwo\e[0m")
            (eat-term-redisplay eat-terminal)
            (emacsvox-eat-update-hook)
            (setq pending-timer emacsvox-eat--quiescence-timer)
            (emacsvox-eat--finish-quiescence
             (current-buffer) emacsvox-eat--generation
             emacsvox-eat--update-serial)
            (should (= (length submissions) 1))
            (should (equal (caar submissions) "Highlight: Two"))
            (should
             (eq
              (plist-get (cadar submissions) :delivery-policy)
              'replaceable))
            (should
             (equal (plist-get emacsvox-eat--last-likely-focus :text)
                    "Two")))
        (when (timerp pending-timer) (cancel-timer pending-timer))
        (emacsvox-eat--cancel-quiescence)
        (when (eat-term-live-p eat-terminal)
          (eat-term-delete eat-terminal))))))

(ert-deftest emacsvox-eat-pager-fixture-bounds-repaint-and-retains-review ()
  "A less-shaped repaint stays quiet but remains explicitly reviewable."
  (with-temp-buffer
    (setq major-mode 'eat-mode)
    (let ((eat-terminal (eat-term-make (current-buffer) (point-min)))
          submissions)
      (unwind-protect
          (cl-letf (((symbol-function 'emacsvox-eat--selected-buffer-p)
                     (lambda () t))
                    ((symbol-function 'emacsvox-eat--following-live-p)
                     (lambda () t))
                    ((symbol-function 'emacsvox-aural-submit)
                     (lambda (content &rest arguments)
                       (push (list (substring-no-properties content)
                                   arguments)
                             submissions))))
            (eat-term-resize eat-terminal 32 5)
            (emacsvox-eat-test--deliver-screen eat-terminal "shell$ ")
            (emacsvox-eat-test--deliver-screen
             eat-terminal
             (concat
              "\e[?1049h\e[2J\e[HPage one line 1"
              "\e[2;1HPage one line 2\e[5;1H\e[7m(END)\e[0m"))
            (should
             (equal (mapcar #'car submissions)
                    '("Terminal application screen entered")))
            (setq submissions nil)
            (emacsvox-eat-test--deliver-screen
             eat-terminal
             (concat
              "\e[2J\e[HPage two line 1"
              "\e[2;1HPage two line 2\e[5;1H\e[7m(END)\e[0m")
             'down)
            (should-not submissions)
            (should (plist-get emacsvox-eat--last-screen-diff :text-changed))
            (should (plist-get emacsvox-eat--last-changed-screen
                               :alternate-screen))
            (emacsvox-eat-speak-last-change)
            (emacsvox-eat-speak-visible-screen)
            (should (= (length submissions) 2))
            (should
             (seq-some
              (lambda (submission)
                (string-match-p "Page two line 1" (car submission)))
              submissions))
            (setq submissions nil)
            (emacsvox-eat-test--deliver-screen eat-terminal "\e[?1049l")
            (should
             (equal (mapcar #'car submissions)
                    '("Terminal application screen exited"))))
        (emacsvox-eat--cancel-quiescence)
        (when (eat-term-live-p eat-terminal)
          (eat-term-delete eat-terminal))))))

(ert-deftest emacsvox-eat-pager-search-fixture-retains-styled-match ()
  "A less-shaped search match is silent automatically but frozen with style."
  (with-temp-buffer
    (setq major-mode 'eat-mode)
    (let ((eat-terminal (eat-term-make (current-buffer) (point-min)))
          submissions)
      (unwind-protect
          (cl-letf (((symbol-function 'emacsvox-eat--selected-buffer-p)
                     (lambda () t))
                    ((symbol-function 'emacsvox-eat--following-live-p)
                     (lambda () t))
                    ((symbol-function 'emacsvox-aural-submit)
                     (lambda (content &rest arguments)
                       (push (list (substring-no-properties content)
                                   arguments)
                             submissions))))
            (eat-term-resize eat-terminal 24 4)
            (emacsvox-eat-test--deliver-screen eat-terminal "shell$ ")
            (emacsvox-eat-test--deliver-screen
             eat-terminal
             (concat
              "\e[?1049h\e[2J\e[HItem 41"
              "\e[2;1HItem 42\e[4;1H(END)"))
            (setq submissions nil)
            (emacsvox-eat-test--deliver-screen
             eat-terminal "\e[2;6H\e[7m42\e[0m\e[4;1H" 'return)
            (should-not submissions)
            (should (plist-get emacsvox-eat--last-screen-diff :style-changed))
            (should-not emacsvox-eat--last-likely-focus)
            (should
             (memq
              'inverse-like
              (emacsvox-eat-test--traits-for-text
               emacsvox-eat--last-changed-screen "42")))
            (emacsvox-eat-speak-last-change)
            (emacsvox-eat-speak-visible-screen)
            (should (= (length submissions) 2))
            (should
             (seq-some
              (lambda (submission)
                (string-match-p "Item 42" (car submission)))
              submissions)))
        (emacsvox-eat--cancel-quiescence)
        (when (eat-term-live-p eat-terminal)
          (eat-term-delete eat-terminal))))))

(ert-deftest emacsvox-eat-editor-fixture-speaks-cursor-and-retains-status ()
  "A Vim-shaped cursor move speaks its row and retains a status rewrite."
  (with-temp-buffer
    (setq major-mode 'eat-mode)
    (let ((eat-terminal (eat-term-make (current-buffer) (point-min)))
          submissions)
      (unwind-protect
          (cl-letf (((symbol-function 'emacsvox-eat--selected-buffer-p)
                     (lambda () t))
                    ((symbol-function 'emacsvox-eat--following-live-p)
                     (lambda () t))
                    ((symbol-function 'emacsvox-aural-submit)
                     (lambda (content &rest arguments)
                       (push (list (substring-no-properties content)
                                   arguments)
                             submissions))))
            (eat-term-resize eat-terminal 30 4)
            (emacsvox-eat-test--deliver-screen eat-terminal "shell$ ")
            (emacsvox-eat-test--deliver-screen
             eat-terminal
             (concat
              "\e[?1049h\e[2J\e[Halpha\e[2;1Hbeta\e[3;1Hgamma"
              "\e[4;1H\e[7mNORMAL\e[0m\e[1;1H"))
            (setq submissions nil)
            (emacsvox-eat-test--deliver-screen
             eat-terminal "\e[2;1H" 'down)
            (should
             (equal (mapcar #'car submissions)
                    '("Terminal row: beta")))
            (setq submissions nil)
            (emacsvox-eat-test--deliver-screen
             eat-terminal
             "\e[4;1H\e[7m-- INSERT --\e[K\e[0m\e[2;1H")
            (should-not submissions)
            (should (equal emacsvox-eat--last-status-text "-- INSERT --"))
            (emacsvox-eat-speak-retained-status)
            (should (= (length submissions) 1))
            (should
             (equal (caar submissions)
                    "Retained terminal status: -- INSERT --")))
        (emacsvox-eat--cancel-quiescence)
        (when (eat-term-live-p eat-terminal)
          (eat-term-delete eat-terminal))))))

(ert-deftest emacsvox-eat-menu-fixture-tracks-selection-with-fixed-cursor ()
  "A whiptail-shaped style transfer speaks one selected row."
  (with-temp-buffer
    (setq major-mode 'eat-mode)
    (let ((eat-terminal (eat-term-make (current-buffer) (point-min)))
          submissions)
      (unwind-protect
          (cl-letf (((symbol-function 'emacsvox-eat--selected-buffer-p)
                     (lambda () t))
                    ((symbol-function 'emacsvox-eat--following-live-p)
                     (lambda () t))
                    ((symbol-function 'emacsvox-aural-submit)
                     (lambda (content &rest arguments)
                       (push (list (substring-no-properties content)
                                   arguments)
                             submissions))))
            (eat-term-resize eat-terminal 24 5)
            (emacsvox-eat-test--deliver-screen eat-terminal "shell$ ")
            (emacsvox-eat-test--deliver-screen
             eat-terminal
             (concat
              "\e[?1049h\e[2J\e[H\e[7mMenu\e[0m"
              "\e[2;1H\e[7mOne\e[0m\e[3;1HTwo"
              "\e[4;1HChoose\e[?25l"))
            (setq submissions nil)
            (emacsvox-eat-test--deliver-screen
             eat-terminal
             "\e[2;1H\e[0mOne\e[3;1H\e[7mTwo\e[0m\e[4;7H"
             'down)
            (should
             (equal (mapcar #'car submissions) '("Highlight: Two")))
            (should
             (equal (plist-get emacsvox-eat--last-likely-focus :text)
                    "Two"))
            (should
             (eq (plist-get emacsvox-eat--last-likely-focus :confidence)
                 'high)))
        (emacsvox-eat--cancel-quiescence)
        (when (eat-term-live-p eat-terminal)
          (eat-term-delete eat-terminal))))))

(ert-deftest emacsvox-eat-progress-fixture-coalesces-real-rewrites ()
  "Real carriage-return progress is replaceable, throttled, and final-aware."
  (with-temp-buffer
    (setq major-mode 'eat-mode)
    (let ((eat-terminal (eat-term-make (current-buffer) (point-min)))
          (now 100.0)
          submissions)
      (unwind-protect
          (cl-letf (((symbol-function 'float-time) (lambda (&optional _) now))
                    ((symbol-function 'emacsvox-eat--selected-buffer-p)
                     (lambda () t))
                    ((symbol-function 'emacsvox-eat--following-live-p)
                     (lambda () t))
                    ((symbol-function 'emacsvox-aural-submit)
                     (lambda (content &rest arguments)
                       (push (list (substring-no-properties content)
                                   arguments)
                             submissions))))
            (eat-term-resize eat-terminal 24 3)
            (emacsvox-eat-test--deliver-screen eat-terminal "Progress 0%")
            (emacsvox-eat-test--deliver-screen
             eat-terminal "\rProgress 10%")
            (setq now 100.5)
            (emacsvox-eat-test--deliver-screen
             eat-terminal "\rProgress 20%")
            (should (equal emacsvox-eat--last-status-text "Progress 20%"))
            (setq now 100.6)
            (emacsvox-eat-test--deliver-screen
             eat-terminal "\rProgress 100%")
            (setq submissions (nreverse submissions))
            (should
             (equal (mapcar #'car submissions)
                    '("Progress 10%" "Progress 100%")))
            (dolist (submission submissions)
              (should
               (eq (plist-get (cadr submission) :delivery-policy)
                   'replaceable))))
        (emacsvox-eat--cancel-quiescence)
        (when (eat-term-live-p eat-terminal)
          (eat-term-delete eat-terminal))))))

(ert-deftest emacsvox-eat-real-sgr-styles-have-normalized-traits ()
  "Every recoverable EAT SGR category has a data-only semantic trait."
  (with-temp-buffer
    (let ((eat-terminal (eat-term-make (current-buffer) (point-min))))
      (unwind-protect
          (progn
            (eat-term-resize eat-terminal 120 4)
            (eat-term-process-output
             eat-terminal
             (concat
              "plain "
              "\e[1mbold\e[0m \e[2mfaint\e[0m "
              "\e[3mitalic\e[0m \e[4munder\e[0m "
              "\e[5mblink\e[0m \e[6mfast\e[0m "
              "\e[7minverse\e[0m \e[8mconceal\e[0m "
              "\e[9mcross\e[0m \e[31mred\e[0m "
              "\e[44mbluebg\e[0m \e[11mfont1\e[0m"))
            (eat-term-redisplay eat-terminal)
            (let ((snapshot (emacsvox-eat--capture-screen)))
              (dolist
                  (case
                   '(("bold" bold)
                     ("faint" faint)
                     ("italic" italic)
                     ("under" underline)
                     ("blink" blink)
                     ("fast" blink)
                     ("inverse" inverse-like foreground-color
                      background-color)
                     ("cross" crossed-out)
                     ("red" foreground-color)
                     ("bluebg" background-color)
                     ("font1" alternate-font)))
                (should
                 (equal
                  (emacsvox-eat-test--traits-for-text snapshot (car case))
                  (cdr case))))
              (should
               (seq-some
                (lambda (run)
                  (memq 'concealed (plist-get (caddr run) :traits)))
                (plist-get snapshot :styles)))
              (should-not
               (seq-some
                (lambda (run)
                  (memq 'eat-term-font-0
                        (plist-get
                         (plist-get (caddr run) :face) :faces)))
                (plist-get snapshot :styles)))))
        (when (eat-term-live-p eat-terminal)
          (eat-term-delete eat-terminal))))))

(ert-deftest emacsvox-eat-screen-metadata-is-control-free-and-bounded ()
  "Untrusted terminal metadata loses controls, properties, and excess text."
  (let* ((short
          (propertize
           (concat "  Router" (string 7) "CLI" (string 10) "  ")
           'face 'bold))
         (clean (emacsvox-eat--sanitize-metadata-value short))
         (long
          (emacsvox-eat--sanitize-metadata-value
           (concat (make-string 300 ?x) (string 7)))))
    (should (equal clean "Router CLI"))
    (should-not (text-properties-at 0 clean))
    (should-not (string-match-p "[[:cntrl:]]" clean))
    (should (string-suffix-p "…" long))
    (should (<= (length long)
                (1+ emacsvox-eat--maximum-metadata-characters)))
    (should-not (string-match-p "[[:cntrl:]]" long))))

(ert-deftest emacsvox-eat-real-title-snapshot-is-bounded ()
  "A long OSC title is bounded in the public EAT screen snapshot."
  (with-temp-buffer
    (let ((eat-terminal (eat-term-make (current-buffer) (point-min))))
      (unwind-protect
          (progn
            (eat-term-process-output
             eat-terminal
             (concat "\e]2;" (make-string 300 ?x) "\a"))
            (eat-term-redisplay eat-terminal)
            (let ((title
                   (plist-get (emacsvox-eat--capture-screen) :title)))
              (should (string-suffix-p "…" title))
              (should (= (length title)
                         (1+ emacsvox-eat--maximum-metadata-characters)))))
        (when (eat-term-live-p eat-terminal)
          (eat-term-delete eat-terminal))))))

(ert-deftest emacsvox-eat-screen-snapshot-excludes-scrollback ()
  "A screen snapshot begins at EAT's public visible-display boundary."
  (with-temp-buffer
    (let ((eat-terminal (eat-term-make (current-buffer) (point-min))))
      (unwind-protect
          (progn
            (eat-term-resize eat-terminal 12 2)
            (eat-term-process-output
             eat-terminal "old-one\r\nold-two\r\nvisible")
            (eat-term-redisplay eat-terminal)
            (let ((snapshot (emacsvox-eat--capture-screen)))
              (should-not
               (string-match-p "old-one" (plist-get snapshot :text)))
              (should
               (string-match-p "visible" (plist-get snapshot :text)))
              (should
               (=
                (plist-get snapshot :display-beginning)
                (marker-position
                 (eat-term-display-beginning eat-terminal))))))
        (when (eat-term-live-p eat-terminal)
          (eat-term-delete eat-terminal))))))

(ert-deftest emacsvox-eat-screen-snapshot-tracks-alternate-display ()
  "A screen snapshot records alternate-screen state without private data."
  (with-temp-buffer
    (let ((eat-terminal (eat-term-make (current-buffer) (point-min))))
      (unwind-protect
          (progn
            (eat-term-resize eat-terminal 20 4)
            (eat-term-process-output eat-terminal "Main")
            (eat-term-process-output eat-terminal "\e[?1049hAlt")
            (eat-term-redisplay eat-terminal)
            (let ((snapshot (emacsvox-eat--capture-screen)))
              (should (plist-get snapshot :alternate-screen))
              (should (equal (plist-get snapshot :text) "Alt")))
            (eat-term-process-output eat-terminal "\e[?1049l")
            (eat-term-redisplay eat-terminal)
            (let ((snapshot (emacsvox-eat--capture-screen)))
              (should-not (plist-get snapshot :alternate-screen))
              (should (equal (plist-get snapshot :text) "Main"))))
        (when (eat-term-live-p eat-terminal)
          (eat-term-delete eat-terminal))))))

(ert-deftest emacsvox-eat-screen-diff-classifies-unchanged-and-cursor-only ()
  "Screen diffs keep cursor motion separate from content changes."
  (let* ((old '(:generation 3 :text "one\ntwo" :rows ("one" "two")
                :styles nil :cursor-row 0 :cursor-column 1
                :cursor-type box :size (20 . 4) :alternate-screen nil
                :title "shell" :cwd "/tmp/"))
         (unchanged (emacsvox-eat--screen-diff old (copy-tree old)))
         (new (copy-tree old)))
    (should (plist-get unchanged :comparable))
    (should (plist-get unchanged :unchanged))
    (should-not (plist-get unchanged :changes))
    (setf (plist-get new :cursor-row) 1
          (plist-get new :cursor-column) 2)
    (let ((diff (emacsvox-eat--screen-diff old new)))
      (should (equal (plist-get diff :changes) '(cursor)))
      (should (plist-get diff :cursor-moved))
      (should-not (plist-get diff :text-changed))
      (should-not (plist-get diff :style-changed)))))

(ert-deftest emacsvox-eat-screen-diff-extracts-inserted-rows ()
  "Screen diffs retain inserted completion or help rows in display order."
  (let* ((old '(:generation 1 :text "$ git pu" :rows ("$ git pu")
                :styles nil :cursor-row 0 :cursor-column 8
                :cursor-type box :size (80 . 24) :alternate-screen nil
                :title nil :cwd "/tmp/"))
         (new (copy-tree old)))
    (setf (plist-get new :text) "pull  push\n$ git pu"
          (plist-get new :rows) '("pull  push" "$ git pu")
          (plist-get new :cursor-row) 1)
    (let* ((diff (emacsvox-eat--screen-diff old new))
           (rows (plist-get diff :row-change)))
      (should (equal (plist-get diff :changes) '(text cursor)))
      (should (equal (plist-get diff :text-change)
                     '(:start 0 :old-end 0 :new-end 11)))
      (should (= (plist-get rows :start) 0))
      (should (= (plist-get rows :old-end) 0))
      (should (= (plist-get rows :new-end) 1))
      (should-not (plist-get rows :old-rows))
      (should (equal (plist-get rows :new-rows) '("pull  push"))))))

(ert-deftest emacsvox-eat-screen-diff-finds-same-length-and-style-changes ()
  "Screen diffs detect carriage-return-like and style-only replacement."
  (let* ((plain '(:generation 1 :text "progress 10%" :rows ("progress 10%")
                  :styles nil :cursor-row 0 :cursor-column 12
                  :cursor-type box :size (20 . 2) :alternate-screen nil
                  :title nil :cwd "/tmp/"))
         (progress (copy-tree plain))
         (highlight (copy-tree plain)))
    (setf (plist-get progress :text) "progress 20%"
          (plist-get progress :rows) '("progress 20%")
          (plist-get highlight :styles)
          '((0 8 (:face (:faces (eat-term-bold))))))
    (let ((diff (emacsvox-eat--screen-diff plain progress)))
      (should (equal (plist-get diff :changes) '(text)))
      (should (equal (plist-get diff :text-change)
                     '(:start 9 :old-end 10 :new-end 10))))
    (let ((diff (emacsvox-eat--screen-diff plain highlight)))
      (should (equal (plist-get diff :changes) '(style)))
      (should-not (plist-get diff :text-changed))
      (should (plist-get diff :style-changed))
      (should (equal (plist-get diff :style-change)
                     '(:start 0 :old-end 8 :new-end 8))))))

(ert-deftest emacsvox-eat-screen-diff-classifies-metadata-independently ()
  "Resize, alternate display, title, CWD, and cursor type stay semantic."
  (let* ((old '(:generation 4 :text "prompt" :rows ("prompt")
                :styles nil :cursor-row 0 :cursor-column 6
                :cursor-type box :size (80 . 24) :alternate-screen nil
                :title "local" :cwd "/tmp/"))
         (new (copy-tree old)))
    (setf (plist-get new :cursor-type) 'bar
          (plist-get new :size) '(100 . 30)
          (plist-get new :alternate-screen) t
          (plist-get new :title) "editor"
          (plist-get new :cwd) "/tmp/project/")
    (let ((diff (emacsvox-eat--screen-diff old new)))
      (should
       (equal
        (plist-get diff :changes)
        '(cursor-type size alternate-screen title cwd)))
      (should-not (plist-get diff :text-changed))
      (should-not (plist-get diff :cursor-moved)))))

(ert-deftest emacsvox-eat-screen-diff-refuses-cross-generation-comparison ()
  "Initial and replacement generations do not manufacture content diffs."
  (let* ((old '(:generation 4 :text "old secret" :rows ("old secret")
                :styles nil :cursor-row 0 :cursor-column 10
                :cursor-type box :size (80 . 24) :alternate-screen nil))
         (new '(:generation 5 :text "new prompt" :rows ("new prompt")
                :styles nil :cursor-row 0 :cursor-column 10
                :cursor-type box :size (80 . 24) :alternate-screen nil))
         (initial (emacsvox-eat--screen-diff nil new))
         (replacement (emacsvox-eat--screen-diff old new)))
    (should (equal (plist-get initial :changes) '(initial)))
    (should (plist-get initial :initial))
    (should-not (plist-get initial :comparable))
    (should (equal (plist-get replacement :changes) '(generation)))
    (should (plist-get replacement :generation-changed))
    (should-not (plist-get replacement :text-changed))
    (should-not (plist-get replacement :row-change))))

(ert-deftest emacsvox-eat-focus-classifier-finds-one-paired-style-move ()
  "A compact inverse region moved by navigation is a likely highlight."
  (let* ((text "Header\nOne\nTwo\nFooter")
         (selected
          '(:face
            (:attributes
             ((:foreground . "default-bg")
              (:background . "default-fg")))
            :traits
            (inverse-like foreground-color background-color)))
         (old
          (list :generation 3 :text text
                :rows '("Header" "One" "Two" "Footer")
                :styles (list (list 0 6 selected) (list 7 10 selected))
                :cursor-row 1 :cursor-column 1 :cursor-type nil
                :size '(40 . 4) :alternate-screen t))
         (new
          (list :generation 3 :text text
                :rows '("Header" "One" "Two" "Footer")
                :styles (list (list 0 6 selected) (list 11 14 selected))
                :cursor-row 2 :cursor-column 1 :cursor-type nil
                :size '(40 . 4) :alternate-screen t))
         (diff (emacsvox-eat--screen-diff old new))
         (navigation '(:generation 3 :direction down))
         (focus
          (emacsvox-eat--likely-focus-change old new diff navigation)))
    (should (equal (plist-get focus :kind) 'highlight))
    (should (equal (plist-get focus :text) "Two"))
    (should (= (plist-get focus :row-start) 2))
    (should (memq 'inverse-like (plist-get focus :traits)))
    (should (eq (plist-get focus :confidence) 'high))
    (should (>= (plist-get focus :score) 8))))

(ert-deftest emacsvox-eat-focus-classifier-rejects-weak-style-evidence ()
  "Static headers, theme repaint, resize, and wrong direction fail closed."
  (let* ((text "Header\nOne\nTwo")
         (selected
          '(:face (:attributes ((:background . "selected")))
            :traits (background-color)))
         (rethemed
          '(:face (:attributes ((:background . "other-theme")))
            :traits (background-color)))
         (underline '(:face (:attributes ((:underline . t)))
                      :traits (underline)))
         (old
          (list :generation 1 :text text :rows '("Header" "One" "Two")
                :styles (list (list 0 6 selected))
                :cursor-row 0 :cursor-column 0
                :size '(30 . 3) :alternate-screen t))
         (static-new (copy-tree old))
         (theme-new (copy-tree old)))
    (setf (plist-get static-new :styles)
          (list (list 0 6 selected) (list 11 14 underline))
          (plist-get theme-new :styles) (list (list 0 6 rethemed)))
    (should-not
     (emacsvox-eat--likely-focus-change
      old static-new (emacsvox-eat--screen-diff old static-new)
      '(:generation 1 :direction down)))
    (should-not
     (emacsvox-eat--likely-focus-change
      old theme-new (emacsvox-eat--screen-diff old theme-new)
      '(:generation 1 :direction down)))
    (let* ((moved (copy-tree old))
           (moved-styles (list (list 7 10 selected))))
      (setf (plist-get moved :styles) moved-styles
            (plist-get moved :cursor-row) 1)
      (let ((diff (emacsvox-eat--screen-diff old moved)))
        (should-not
         (emacsvox-eat--likely-focus-change
          old moved diff '(:generation 1 :direction up)))
        (setf (plist-get diff :size-changed) t)
        (should-not
         (emacsvox-eat--likely-focus-change
          old moved diff '(:generation 1 :direction down)))))))

(ert-deftest emacsvox-eat-focus-classifier-rejects-multiple-style-moves ()
  "Multiple simultaneous highlight transfers are not assigned one focus."
  (let* ((text "A\nB\nC\nD")
         (selected
          '(:face (:attributes ((:background . "selected")))
            :traits (background-color)))
         (old
          (list :generation 2 :text text :rows '("A" "B" "C" "D")
                :styles (list (list 0 1 selected) (list 4 5 selected))
                :cursor-row 0 :cursor-column 0
                :size '(20 . 4) :alternate-screen t))
         (new (copy-tree old)))
    (setf (plist-get new :styles)
          (list (list 2 3 selected) (list 6 7 selected))
          (plist-get new :cursor-row) 1)
    (should-not
     (emacsvox-eat--likely-focus-change
      old new (emacsvox-eat--screen-diff old new)
      '(:generation 2 :direction down)))))

(ert-deftest emacsvox-eat-focus-classifier-uses-alternate-screen-cursor-row ()
  "Correlated vertical cursor motion can identify an unchanged TUI row."
  (let* ((old
          '(:generation 7 :text "One\nTwo" :rows ("One" "Two")
            :styles nil :cursor-row 0 :cursor-column 0
            :size (20 . 2) :alternate-screen t))
         (new (copy-tree old)))
    (setf (plist-get new :cursor-row) 1)
    (let* ((diff (emacsvox-eat--screen-diff old new))
           (focus
            (emacsvox-eat--likely-focus-change
             old new diff '(:generation 7 :direction down))))
      (should (eq (plist-get focus :kind) 'cursor-row))
      (should (equal (plist-get focus :text) "Two"))
      (should (eq (plist-get focus :confidence) 'medium)))
    (setf (plist-get new :alternate-screen) nil)
    (should-not
     (emacsvox-eat--likely-focus-change
      old new (emacsvox-eat--screen-diff old new)
      '(:generation 7 :direction down)))))

(ert-deftest emacsvox-eat-high-confidence-focus-is-native-and-replaceable ()
  "A high-confidence highlight is retained and submitted only once."
  (with-temp-buffer
    (let* ((emacsvox-eat--generation 6)
           (focus
            '(:kind highlight :text "Two" :confidence high :score 11
              :identity (highlight 6 2 0 selected "Two")))
           (diff (list :style-changed t :likely-focus focus))
           submissions)
      (cl-letf (((symbol-function 'emacsvox-aural-submit)
                 (lambda (content &rest arguments)
                   (push (list content arguments) submissions))))
        (emacsvox-eat--screen-quiesced diff '(:generation 6))
        (emacsvox-eat--screen-quiesced diff '(:generation 6)))
      (should (= (length submissions) 1))
      (should (eq emacsvox-eat--last-likely-focus focus))
      (should
       (equal
        emacsvox-eat--last-focus-presentation-identity
        (plist-get focus :identity)))
      (let* ((submission (car submissions))
             (arguments (cadr submission))
             (facts (plist-get arguments :facts))
             (key (plist-get arguments :replacement-key)))
        (should (equal (car submission) "Highlight: Two"))
        (should
         (equal
          facts
          '(:role command-output
            :command-interaction-kind shell
            :events (focus-entered)
            :command-operation output-navigation)))
        (should
         (emacsvox-aural-normalize-input
          facts '(:module eat :occasion navigation)))
        (should (eq (plist-get arguments :occasion) 'navigation))
        (should (eq (plist-get arguments :delivery-policy) 'replaceable))
        (should (equal (butlast key 2) '(eat focus)))
        (should (= (car (last key)) 6))))))

(ert-deftest emacsvox-eat-medium-highlight-is-retained-but-not-automatic ()
  "Uncertain style focus remains reviewable without automatic speech."
  (with-temp-buffer
    (let* ((focus
            '(:kind highlight :text "Possible" :confidence medium :score 8
              :identity (highlight 0 1 0 selected "Possible")))
           submissions)
      (cl-letf (((symbol-function 'emacsvox-eat--submit)
                 (lambda (&rest arguments) (push arguments submissions))))
        (emacsvox-eat--screen-quiesced
         (list :style-changed t :likely-focus focus)
         '(:generation 0)))
      (should-not submissions)
      (should (eq emacsvox-eat--last-likely-focus focus))
      (should-not emacsvox-eat--last-focus-presentation-identity))))

(ert-deftest emacsvox-eat-alternate-cursor-row-is-automatic-navigation ()
  "A correlated alternate-screen cursor row is spoken despite medium score."
  (with-temp-buffer
    (let* ((focus
            '(:kind cursor-row :text "Second row" :confidence medium :score 8
              :identity (cursor-row 0 1 "Second row")))
           submissions)
      (cl-letf (((symbol-function 'emacsvox-eat--submit)
                 (lambda (&rest arguments) (push arguments submissions))))
        (emacsvox-eat--screen-quiesced
         (list :cursor-moved t :likely-focus focus)
         '(:generation 0)))
      (should (= (length submissions) 1))
      (should (equal (caar submissions) "Terminal row: Second row"))
      (should (eq (nth 2 (car submissions)) 'navigation))
      (should (eq (nth 4 (car submissions)) 'replaceable)))))

(ert-deftest emacsvox-eat-unclassified-change-invalidates-retained-focus ()
  "Any later unclassified visible change prevents stale focus review."
  (with-temp-buffer
    (let ((emacsvox-eat--last-likely-focus
           '(:kind highlight :text "Old" :identity old))
          (emacsvox-eat--last-focus-presentation-identity 'old))
      (emacsvox-eat--retain-screen-change
       '(:cursor-moved t) '(:generation 0))
      (should-not emacsvox-eat--last-likely-focus)
      (should-not emacsvox-eat--last-focus-presentation-identity))))

(ert-deftest emacsvox-eat-review-prefix-is-available-in-every-input-mode ()
  "Every EAT input map reaches the shared C-e q snapshot-review map."
  (with-temp-buffer
    (let (eat-terminal)
      (emacsvox-eat-mode-setup)))
  (should
   (eq (lookup-key emacsvox-keymap (kbd "q"))
       'emacsvox-eat-review-map))
  (dolist (map-symbol
           '(eat-line-mode-map eat-semi-char-mode-map
             eat-char-mode-map eat-mode-map
             eat-eshell-emacs-mode-map eat-eshell-semi-char-mode-map
             eat-eshell-char-mode-map))
    (let ((map (symbol-value map-symbol)))
      (should (keymapp map))
      (should
       (eq (lookup-key map emacsvox-prefix) 'emacsvox-keymap))))
  (dolist (binding
           '(("l" . emacsvox-eat-speak-current-row)
             ("d" . emacsvox-eat-speak-last-change)
             ("h" . emacsvox-eat-speak-likely-focus)
             ("c" . emacsvox-eat-speak-completion-output)
             ("s" . emacsvox-eat-speak-visible-screen)
             ("r" . emacsvox-eat-review-screen)
             ("t" . emacsvox-eat-speak-retained-status)
             ("i" . emacsvox-eat-speak-retained-metadata)
             ("v" . emacsvox-eat-cycle-verbosity)
             ("m" . emacsvox-eat-toggle-background-monitoring)))
    (should
     (eq (lookup-key emacsvox-eat-review-map (kbd (car binding)))
         (cdr binding)))))

(ert-deftest emacsvox-eat-current-row-review-uses-only-retained-snapshot ()
  "Current-row review cannot read later mutable terminal-buffer content."
  (with-temp-buffer
    (setq major-mode 'eat-mode)
    (insert "LIVE-BUFFER-SECRET")
    (let ((emacsvox-eat--screen-snapshot
           '(:text "First\nSnapshot row"
             :rows ("First" "Snapshot row")
             :cursor-row 1 :cursor-column 4))
          submission)
      (cl-letf (((symbol-function 'emacsvox-eat--submit)
                 (lambda (&rest arguments) (setq submission arguments))))
        (emacsvox-eat-speak-current-row))
      (should
       (equal
        submission
        '("Current terminal row 2 of 2: Snapshot row"
          (:role command-output :command-interaction-kind shell
           :command-operation output-navigation)
          inspection)))
      (should-not
       (string-match-p "LIVE-BUFFER-SECRET" (format "%S" submission)))
      (should
       (emacsvox-aural-normalize-input
        (nth 1 submission) '(:module eat :mode eat-mode
                             :occasion inspection))))))

(ert-deftest emacsvox-eat-last-change-review-presents-retained-row-window ()
  "Last-change review presents all bounded new rows and their location."
  (with-temp-buffer
    (setq major-mode 'eat-mode)
    (let ((emacsvox-eat--last-screen-diff
           '(:text-changed t :row-change
             (:start 1 :old-rows nil :new-rows ("first" "second"))))
          (emacsvox-eat--last-changed-screen
           '(:text "$ \nfirst\nsecond\n$ "
             :rows ("$ " "first" "second" "$ ")
             :cursor-row 3 :cursor-column 2))
          content)
      (cl-letf (((symbol-function 'emacsvox-eat--submit)
                 (lambda (text &rest _) (setq content text))))
        (emacsvox-eat-speak-last-change))
      (should
       (equal content
              "Last terminal text change, rows 2 through 3:\nfirst\nsecond")))))

(ert-deftest emacsvox-eat-last-change-review-locates-style-only-change ()
  "A retained style-only change is described by its rendered row range."
  (with-temp-buffer
    (setq major-mode 'eat-mode)
    (let ((emacsvox-eat--last-screen-diff
           '(:style-changed t
             :style-change (:start 4 :old-end 7 :new-end 7)))
          (emacsvox-eat--last-changed-screen
           '(:text "One\nTwo" :rows ("One" "Two")))
          content)
      (cl-letf (((symbol-function 'emacsvox-eat--submit)
                 (lambda (text &rest _) (setq content text))))
        (emacsvox-eat-speak-last-change))
      (should
       (equal content
              "The last terminal change affected styling on row 2")))))

(ert-deftest emacsvox-eat-likely-focus-review-labels-uncertainty ()
  "Explicit focus review exposes kind, confidence, row, and retained text."
  (with-temp-buffer
    (setq major-mode 'eat-mode)
    (let ((emacsvox-eat--last-likely-focus
           '(:kind highlight :text "Possible choice" :confidence medium
             :score 8 :row-start 2 :row-end 2))
          content)
      (cl-letf (((symbol-function 'emacsvox-eat--submit)
                 (lambda (text &rest _) (setq content text))))
        (emacsvox-eat-speak-likely-focus))
      (should
       (equal
        content
        "Likely terminal highlight, medium confidence, row 3: Possible choice")))))

(ert-deftest emacsvox-eat-completion-review-preserves-retained-layout ()
  "Candidate review uses exact retained rows and an honest visible count."
  (with-temp-buffer
    (setq major-mode 'eat-mode)
    (let ((emacsvox-eat--last-completion-output
           '(:layout items :items ("pull" "push") :item-count 2
             :row-count 1 :confidence unanchored :rows ("pull  push")))
          content
          facts)
      (cl-letf (((symbol-function 'emacsvox-eat--submit)
                 (lambda (text semantic &rest _)
                   (setq content text facts semantic))))
        (emacsvox-eat-speak-completion-output))
      (should
       (equal content
              "At least 2 visible candidates retained:\npull  push"))
      (should
       (equal facts
              '(:role command-output :command-interaction-kind shell
                :command-operation completion)))
      (should
       (emacsvox-aural-normalize-input
        facts '(:module eat :mode eat-mode :occasion inspection))))))

(ert-deftest emacsvox-eat-visible-screen-review-is-a-frozen-copy ()
  "Visible-screen review presents retained rows, never later live text."
  (with-temp-buffer
    (setq major-mode 'eat-mode)
    (insert "UNRETAINED-LIVE-CONTENT")
    (let ((emacsvox-eat--screen-snapshot
           '(:text "Menu\nSelected"
             :rows ("Menu" "Selected") :cursor-row 1
             :alternate-screen t))
          content)
      (cl-letf (((symbol-function 'emacsvox-eat--submit)
                 (lambda (text &rest _) (setq content text))))
        (emacsvox-eat-speak-visible-screen))
      (should
       (equal
        content
        "Frozen application terminal screen, 2 rows, cursor row 2:\nMenu\nSelected"))
      (should-not (string-match-p "UNRETAINED" content)))))

(ert-deftest emacsvox-eat-review-reports-absent-state-accessibly ()
  "Review commands submit an explicit no-data result instead of failing."
  (with-temp-buffer
    (setq major-mode 'eat-mode)
    (let (contents)
      (cl-letf (((symbol-function 'emacsvox-eat--submit)
                 (lambda (content &rest _) (push content contents))))
        (emacsvox-eat-speak-current-row)
        (emacsvox-eat-speak-last-change)
        (emacsvox-eat-speak-likely-focus)
        (emacsvox-eat-speak-completion-output)
        (emacsvox-eat-speak-retained-status)
        (emacsvox-eat-speak-retained-metadata)
        (emacsvox-eat-speak-visible-screen))
      (should
       (equal
        (nreverse contents)
        '("No terminal screen snapshot is available"
          "No terminal screen change is retained"
          "No likely terminal focus is retained"
          "No terminal completion output is retained"
          "No terminal status is retained"
          "No terminal metadata change is retained"
          "No terminal screen snapshot is available"))))))

(ert-deftest emacsvox-eat-review-is-blocked-during-secure-input ()
  "No explicit review command can expose state inside a secure-input scope."
  (with-temp-buffer
    (setq major-mode 'eat-mode)
    (let ((emacsvox-eat--secure-input-active-p t)
          (emacsvox-eat--screen-snapshot
           '(:text "DO-NOT-SPEAK" :rows ("DO-NOT-SPEAK") :cursor-row 0))
          submitted)
      (cl-letf (((symbol-function 'emacsvox-eat--submit)
                 (lambda (&rest _) (setq submitted t))))
        (dolist (command
                 '(emacsvox-eat-speak-current-row
                   emacsvox-eat-speak-last-change
                   emacsvox-eat-speak-likely-focus
                   emacsvox-eat-speak-completion-output
                   emacsvox-eat-speak-retained-status
                   emacsvox-eat-speak-retained-metadata
                   emacsvox-eat-speak-visible-screen))
          (should-error (funcall command) :type 'user-error)))
      (should-not submitted))))

(ert-deftest emacsvox-eat-frozen-review-copies-screen-style-and-anchors ()
  "Opening review copies retained data and never follows later live mutation."
  (let ((source (generate-new-buffer " *emacsvox-eat-review-source*"))
        review
        spoken
        source-point)
    (unwind-protect
        (save-window-excursion
          (switch-to-buffer source)
          (setq major-mode 'eat-mode)
          (insert "UNRETAINED-LIVE-CONTENT")
          (goto-char 7)
          (setq source-point (point)
                emacsvox-eat--screen-snapshot
                '(:generation 4 :text "Menu\nSelected"
                  :rows ("Menu" "Selected")
                  :styles
                  ((0 4 (:face (:faces (eat-term-bold)) :traits (bold))))
                  :cursor-row 1 :cursor-column 2 :alternate-screen t)
                emacsvox-eat--last-likely-focus
                '(:kind highlight :text "Selected" :confidence medium
                  :row-start 1 :row-end 1))
          (cl-letf (((symbol-function 'emacsvox-eat--submit)
                     (lambda (text &rest _) (setq spoken text))))
            (setq review (emacsvox-eat-review-screen)))
          (should (eq (current-buffer) review))
          (should (derived-mode-p 'emacsvox-eat-review-mode))
          (should buffer-read-only)
          (should truncate-lines)
          (should (eq buffer-undo-list t))
          (should (equal (buffer-substring-no-properties (point-min) (point-max))
                         "Menu\nSelected\n"))
          (should (= (emacsvox-eat-review--row-at-point) 1))
          (should (get-text-property (point) 'emacsvox-eat-review-cursor))
          (should (get-text-property (point) 'emacsvox-eat-review-focus))
          (should (eq (get-text-property (point-min) 'face) 'eat-term-bold))
          (should
           (equal (get-text-property (point-min) 'emacsvox-eat-style-traits)
                  '(bold)))
          (should
           (string-match-p
            "captured cursor, likely focus, medium confidence: Selected"
            spoken))
          (should-not (string-match-p "UNRETAINED" spoken))
          (with-current-buffer source
            (should (= (point) source-point))
            (aset (car (plist-get emacsvox-eat--screen-snapshot :rows))
                  0 ?X)
            (setf (plist-get emacsvox-eat--screen-snapshot :rows)
                  '("MUTATED-SOURCE"))
            (insert "MORE-LIVE-CONTENT"))
          (should (equal (buffer-substring-no-properties (point-min) (point-max))
                         "Menu\nSelected\n"))
          (should-not (string-match-p "MUTATED\|MORE-LIVE" (buffer-string))))
      (when (buffer-live-p review) (kill-buffer review))
      (when (buffer-live-p source) (kill-buffer source)))))

(ert-deftest emacsvox-eat-frozen-review-navigation-is-row-bounded ()
  "Frozen navigation speaks destinations and explicit first/last boundaries."
  (let ((source (generate-new-buffer " *emacsvox-eat-review-nav*"))
        review
        submissions)
    (unwind-protect
        (save-window-excursion
          (switch-to-buffer source)
          (setq major-mode 'eat-mode
                emacsvox-eat--screen-snapshot
                '(:text "One\nTwo\nThree" :rows ("One" "Two" "Three")
                  :styles nil :cursor-row 1 :alternate-screen nil))
          (cl-letf (((symbol-function 'emacsvox-eat--submit)
                     (lambda (text &rest _)
                       (push (substring-no-properties text) submissions))))
            (setq review (emacsvox-eat-review-screen))
            (emacsvox-eat-review-next-line)
            (emacsvox-eat-review-next-line)
            (emacsvox-eat-review-previous-line 2))
          (should (= (emacsvox-eat-review--row-at-point) 0))
          (should
           (equal
            (nreverse submissions)
            '("Frozen screen review opened. Terminal row 2 of 3, captured cursor: Two"
              "Terminal row 3 of 3: Three"
              "Last retained row. Terminal row 3 of 3: Three"
              "Terminal row 1 of 3: One"))))
      (when (buffer-live-p review) (kill-buffer review))
      (when (buffer-live-p source) (kill-buffer source)))))

(ert-deftest emacsvox-eat-frozen-review-navigates-selection-like-styles ()
  "Styled-region review reaches matches without asserting terminal focus."
  (let ((source (generate-new-buffer " *emacsvox-eat-review-styles*"))
        review
        submissions)
    (unwind-protect
        (save-window-excursion
          (switch-to-buffer source)
          (setq major-mode 'eat-mode
                emacsvox-eat--screen-snapshot
                '(:text "Header\nItem 42\nFooter"
                  :rows ("Header" "Item 42" "Footer")
                  :styles
                  ((0 6
                    (:face (:attributes ((:background . "selected")))
                     :traits (background-color)))
                   (12 14
                    (:face
                     (:attributes
                      ((:foreground . "unspecified-bg")
                       (:background . "unspecified-fg")))
                     :traits
                     (inverse-like foreground-color background-color))))
                  :cursor-row 2 :alternate-screen t))
          (cl-letf (((symbol-function 'emacsvox-eat--submit)
                     (lambda (text &rest _) (push text submissions))))
            (setq review (emacsvox-eat-review-screen))
            (setq submissions nil)
            (emacsvox-eat-review-previous-styled-region)
            (should (= (- (point) (point-min)) 12))
            (emacsvox-eat-review-previous-styled-region)
            (should (= (point) (point-min)))
            (emacsvox-eat-review-next-styled-region)
            (should (= (- (point) (point-min)) 12))
            (emacsvox-eat-review-next-styled-region))
          (setq submissions (nreverse submissions))
          (should
           (equal
            (mapcar #'substring-no-properties submissions)
            '("Selection-like styled region 2 of 2, row 2: 42"
              "Selection-like styled region 1 of 2, row 1: Header"
              "Selection-like styled region 2 of 2, row 2: 42"
              "No later selection-like styled region is frozen")))
          (let* ((first (car submissions))
                 (match (string-match "42" first)))
            (should match)
            (should
             (memq
              'inverse-like
              (get-text-property
               match 'emacsvox-eat-style-traits first)))))
          (with-current-buffer source
            (should (eq major-mode 'eat-mode))))
      (when (buffer-live-p review) (kill-buffer review))
      (when (buffer-live-p source) (kill-buffer source))))

(ert-deftest emacsvox-eat-frozen-review-keeps-exact-completion-copy ()
  "Completion view preserves frozen columns after source state changes."
  (let ((source (generate-new-buffer " *emacsvox-eat-review-completion*"))
        review
        spoken)
    (unwind-protect
        (save-window-excursion
          (switch-to-buffer source)
          (setq major-mode 'eat-mode
                emacsvox-eat--screen-snapshot
                '(:text "$ git pu" :rows ("$ git pu") :styles nil
                  :cursor-row 0 :alternate-screen nil)
                emacsvox-eat--last-completion-output
                '(:layout rows :row-count 2 :confidence anchored
                  :rows ("pull  Update from remote"
                         "push  Upload to remote")))
          (cl-letf (((symbol-function 'emacsvox-eat--submit)
                     (lambda (text &rest _)
                       (setq spoken (substring-no-properties text)))))
            (setq review (emacsvox-eat-review-screen))
            (with-current-buffer source
              (setf (plist-get emacsvox-eat--last-completion-output :rows)
                    '("MUTATED-CANDIDATE")))
            (with-current-buffer review
              (emacsvox-eat-review-show-completion)))
          (should (eq emacsvox-eat-review--view 'completion))
          (should
           (equal
            (buffer-substring-no-properties (point-min) (point-max))
            "pull  Update from remote\npush  Upload to remote\n"))
          (should
           (equal
            spoken
            (concat
             "2 retained completion rows. Completion row 1 of 2: "
             "pull  Update from remote")))
          (should-not (string-match-p "MUTATED" (buffer-string))))
      (when (buffer-live-p review) (kill-buffer review))
      (when (buffer-live-p source) (kill-buffer source)))))

(ert-deftest emacsvox-eat-frozen-review-never-overwrites-name-collision ()
  "Opening an EAT review preserves an unrelated buffer with the target name."
  (let* ((source (generate-new-buffer " *emacsvox-eat-review-collision*"))
         (target-name (format "*EAT Review: %s*" (buffer-name source)))
         (collision (generate-new-buffer target-name))
         review)
    (unwind-protect
        (save-window-excursion
          (with-current-buffer collision (insert "KEEP-THIS-CONTENT"))
          (switch-to-buffer source)
          (setq major-mode 'eat-mode
                emacsvox-eat--screen-snapshot
                '(:text "SCREEN" :rows ("SCREEN") :styles nil
                  :cursor-row 0 :alternate-screen nil))
          (cl-letf (((symbol-function 'emacsvox-eat--submit) #'ignore))
            (setq review (emacsvox-eat-review-screen)))
          (should-not (eq review collision))
          (with-current-buffer collision
            (should (equal (buffer-string) "KEEP-THIS-CONTENT")))
          (with-current-buffer review
            (should (equal (buffer-substring-no-properties
                            (point-min) (point-max))
                           "SCREEN\n"))))
      (when (buffer-live-p review) (kill-buffer review))
      (when (buffer-live-p collision) (kill-buffer collision))
      (when (buffer-live-p source) (kill-buffer source)))))

(ert-deftest emacsvox-eat-frozen-review-jumps-without-touching-terminal ()
  "Cursor and likely-focus commands navigate only the copied screen rows."
  (let ((source (generate-new-buffer " *emacsvox-eat-review-jump*"))
        review
        source-point)
    (unwind-protect
        (save-window-excursion
          (switch-to-buffer source)
          (setq major-mode 'eat-mode)
          (insert "LIVE")
          (goto-char 3)
          (setq source-point (point)
                emacsvox-eat--screen-snapshot
                '(:text "Top\nMiddle\nBottom"
                  :rows ("Top" "Middle" "Bottom") :styles nil
                  :cursor-row 0 :alternate-screen t)
                emacsvox-eat--last-likely-focus
                '(:kind highlight :text "Bottom" :confidence high
                  :row-start 2 :row-end 2))
          (cl-letf (((symbol-function 'emacsvox-eat--submit) #'ignore))
            (setq review (emacsvox-eat-review-screen))
            (emacsvox-eat-review-goto-focus)
            (should (= (emacsvox-eat-review--row-at-point) 2))
            (emacsvox-eat-review-goto-cursor)
            (should (= (emacsvox-eat-review--row-at-point) 0)))
          (with-current-buffer source
            (should (= (point) source-point))
            (should (equal (buffer-string) "LIVE"))))
      (when (buffer-live-p review) (kill-buffer review))
      (when (buffer-live-p source) (kill-buffer source)))))

(ert-deftest emacsvox-eat-sensitive-boundary-kills-frozen-review ()
  "Secure and lifecycle clearing cannot leave copied terminal content alive."
  (let ((source (generate-new-buffer " *emacsvox-eat-review-private*"))
        review)
    (unwind-protect
        (save-window-excursion
          (switch-to-buffer source)
          (setq major-mode 'eat-mode
                emacsvox-eat--screen-snapshot
                '(:text "PRIVATE" :rows ("PRIVATE") :styles nil
                  :cursor-row 0 :alternate-screen nil))
          (cl-letf (((symbol-function 'emacsvox-eat--submit) #'ignore))
            (setq review (emacsvox-eat-review-screen)))
          (with-current-buffer source
            (emacsvox-eat--clear-sensitive-screen-state)
            (should-not emacsvox-eat--review-buffer)
            (should-not emacsvox-eat--screen-snapshot))
          (should-not (buffer-live-p review)))
      (when (buffer-live-p review) (kill-buffer review))
      (when (buffer-live-p source) (kill-buffer source)))))

(ert-deftest emacsvox-eat-killing-source-kills-frozen-review ()
  "A source terminal cannot die while leaving its copied review buffer."
  (let ((source (generate-new-buffer " *emacsvox-eat-review-death*"))
        review)
    (unwind-protect
        (save-window-excursion
          (switch-to-buffer source)
          (setq major-mode 'eat-mode
                emacsvox-eat--screen-snapshot
                '(:text "COPY" :rows ("COPY") :styles nil
                  :cursor-row 0 :alternate-screen nil))
          (emacsvox-eat-mode-setup)
          (cl-letf (((symbol-function 'emacsvox-eat--submit) #'ignore))
            (setq review (emacsvox-eat-review-screen)))
          (kill-buffer source)
          (should-not (buffer-live-p review)))
      (when (buffer-live-p review) (kill-buffer review))
      (when (buffer-live-p source) (kill-buffer source)))))

(ert-deftest emacsvox-eat-verbosity-command-cycles-buffer-local-policy ()
  "The explicit control cycles all three policies with semantic feedback."
  (with-temp-buffer
    (setq major-mode 'eat-mode)
    (let (submissions)
      (cl-letf (((symbol-function 'emacsvox-eat--submit)
                 (lambda (&rest arguments) (push arguments submissions))))
        (should (eq (emacsvox-eat-cycle-verbosity) 'verbose))
        (should (eq emacsvox-eat-verbosity 'verbose))
        (should (eq (emacsvox-eat-cycle-verbosity) 'terse))
        (should (eq (emacsvox-eat-cycle-verbosity) 'normal)))
      (should (eq emacsvox-eat-verbosity 'normal))
      (setq submissions (nreverse submissions))
      (should
       (equal
        (mapcar #'car submissions)
        (list
         (concat
          "Terminal verbosity verbose; bounded output, status, title, and "
          "directory changes are spoken")
         "Terminal verbosity terse; routine output is retained for review"
         "Terminal verbosity normal; bounded output and status are spoken")))
      (dolist (submission submissions)
        (should
         (equal
          (nth 1 submission)
          '(:role command-interaction :command-interaction-kind shell
            :events (state-changed))))
        (should (eq (nth 2 submission) 'state-change))))))

(ert-deftest emacsvox-eat-frozen-review-controls-source-and-keeps-frozen-state ()
  "Review settings target the source while status and metadata stay frozen."
  (let ((source (generate-new-buffer " *emacsvox-eat-review-controls*"))
        review
        submissions
        status
        title)
    (unwind-protect
        (save-window-excursion
          (switch-to-buffer source)
          (setq status (copy-sequence "Progress 40%")
                title (copy-sequence "Router")
                major-mode 'eat-mode
                emacsvox-eat--screen-snapshot
                '(:text "Progress 40%" :rows ("Progress 40%") :styles nil
                  :cursor-row 0 :alternate-screen nil)
                emacsvox-eat--last-status-text status
                emacsvox-eat--last-metadata-change
                (list :title-changed t :title title
                      :cwd-changed t :cwd "/srv/router/"))
          (cl-letf (((symbol-function 'emacsvox-eat--submit)
                     (lambda (text &rest _)
                       (push (substring-no-properties text) submissions))))
            (setq review (emacsvox-eat-review-screen))
            (setq submissions nil)
            (with-current-buffer source
              (aset status 0 ?X)
              (aset title 0 ?X)
              (setq emacsvox-eat--last-status-text "Progress 90%"
                    emacsvox-eat--last-metadata-change
                    '(:title-changed t :title "Changed")))
            (with-current-buffer review
              (emacsvox-eat-speak-retained-status)
              (emacsvox-eat-speak-retained-metadata)
              (should (eq (emacsvox-eat-cycle-verbosity) 'verbose))
              (should (emacsvox-eat-toggle-background-monitoring))))
          (should
           (equal
            (nreverse submissions)
            (list
             "Retained terminal status: Progress 40%"
             "Terminal title: Router\nWorking directory: /srv/router/"
             (concat
              "Terminal verbosity verbose; bounded output, status, title, and "
              "directory changes are spoken")
             "Background terminal monitoring enabled")))
          (with-current-buffer source
            (should (eq emacsvox-eat-verbosity 'verbose))
            (should emacsvox-eat-monitor-background-output))
          (should (buffer-live-p review)))
      (when (buffer-live-p review) (kill-buffer review))
      (when (buffer-live-p source) (kill-buffer source)))))

(ert-deftest emacsvox-eat-major-mode-change-kills-frozen-review ()
  "Leaving EAT major mode clears its content-bearing frozen screen copy."
  (let ((source (generate-new-buffer " *emacsvox-eat-review-mode-change*"))
        review)
    (unwind-protect
        (save-window-excursion
          (switch-to-buffer source)
          (setq major-mode 'eat-mode
                emacsvox-eat--screen-snapshot
                '(:text "COPY" :rows ("COPY") :styles nil
                  :cursor-row 0 :alternate-screen nil))
          (emacsvox-eat-mode-setup)
          (cl-letf (((symbol-function 'emacsvox-eat--submit) #'ignore))
            (setq review (emacsvox-eat-review-screen)))
          (with-current-buffer source (fundamental-mode))
          (should-not (buffer-live-p review)))
      (when (buffer-live-p review) (kill-buffer review))
      (when (buffer-live-p source) (kill-buffer source)))))

(ert-deftest emacsvox-eat-frozen-review-mode-has-complete-navigation-map ()
  "The immutable review buffer exposes its row, view, anchor, and quit keys."
  (dolist
      (binding
       '(("n" . emacsvox-eat-review-next-line)
         ("p" . emacsvox-eat-review-previous-line)
         ("SPC" . emacsvox-eat-review-speak-current-line)
         ("RET" . emacsvox-eat-review-speak-current-line)
         ("a" . emacsvox-eat-review-speak-view)
         ("s" . emacsvox-eat-review-show-screen)
         ("c" . emacsvox-eat-review-show-completion)
         ("C" . emacsvox-eat-review-goto-cursor)
         ("h" . emacsvox-eat-review-goto-focus)
         ("]" . emacsvox-eat-review-next-styled-region)
         ("[" . emacsvox-eat-review-previous-styled-region)
         ("t" . emacsvox-eat-speak-retained-status)
         ("i" . emacsvox-eat-speak-retained-metadata)
         ("v" . emacsvox-eat-cycle-verbosity)
         ("m" . emacsvox-eat-toggle-background-monitoring)
         ("q" . emacsvox-eat-review-quit)))
    (should
     (eq (lookup-key emacsvox-eat-review-mode-map (kbd (car binding)))
         (cdr binding)))))

(ert-deftest emacsvox-eat-screen-observer-coalesces-an-update-burst ()
  "Successive chunks produce one aggregate diff after quiescence."
  (with-temp-buffer
    (let ((eat-terminal (eat-term-make (current-buffer) (point-min)))
          delivered
          final-timer)
      (unwind-protect
          (cl-letf (((symbol-function 'emacsvox-eat--selected-buffer-p)
                     (lambda () t))
                    ((symbol-function 'emacsvox-eat--following-live-p)
                     (lambda () t))
                    ((symbol-function 'emacsvox-eat--screen-quiesced)
                     (lambda (diff snapshot)
                       (push (list diff snapshot) delivered))))
            (eat-term-resize eat-terminal 40 6)
            (eat-term-process-output eat-terminal "prompt")
            (eat-term-redisplay eat-terminal)
            (emacsvox-eat--observe-screen)
            (should-not emacsvox-eat--quiescence-timer)
            (eat-term-process-output eat-terminal "\r\nfirst")
            (eat-term-redisplay eat-terminal)
            (emacsvox-eat--observe-screen)
            (should (timerp emacsvox-eat--quiescence-timer))
            (eat-term-process-output eat-terminal "\r\nsecond")
            (eat-term-redisplay eat-terminal)
            (emacsvox-eat--observe-screen)
            (emacsvox-eat--finish-quiescence
             (current-buffer) emacsvox-eat--generation
             (1- emacsvox-eat--update-serial))
            (should-not delivered)
            (should emacsvox-eat--pending-screen-diff)
            (setq final-timer emacsvox-eat--quiescence-timer)
            (emacsvox-eat--finish-quiescence
             (current-buffer) emacsvox-eat--generation
             emacsvox-eat--update-serial)
            (should (= (length delivered) 1))
            (let* ((diff (caar delivered))
                   (rows (plist-get diff :row-change)))
              (should (plist-get diff :text-changed))
              (should (equal (plist-get rows :new-rows)
                             '("first" "second"))))
            (should-not emacsvox-eat--pending-screen-baseline)
            (should-not emacsvox-eat--pending-screen-diff)
            (should-not emacsvox-eat--quiescence-timer))
        (when (timerp final-timer) (cancel-timer final-timer))
        (emacsvox-eat--cancel-quiescence)
        (when (eat-term-live-p eat-terminal)
          (eat-term-delete eat-terminal))))))

(ert-deftest emacsvox-eat-follow-live-uses-the-selected-window-point ()
  "Only the selected window's point determines live-follow state."
  (let ((buffer (generate-new-buffer " *emacsvox-eat-follow*")))
    (unwind-protect
        (save-window-excursion
          (delete-other-windows)
          (switch-to-buffer buffer)
          (with-current-buffer buffer
            (let ((eat-terminal (eat-term-make buffer (point-min))))
              (unwind-protect
                  (progn
                    (eat-term-resize eat-terminal 30 4)
                    (eat-term-process-output
                     eat-terminal "one\r\ntwo\r\n$ ")
                    (eat-term-redisplay eat-terminal)
                    (let* ((review-window (selected-window))
                           (live-window (split-window-below))
                           (cursor
                            (eat-term-display-cursor eat-terminal)))
                      (set-window-buffer live-window buffer)
                      (set-window-point review-window (point-min))
                      (set-window-point live-window cursor)
                      (select-window review-window)
                      (should-not (emacsvox-eat--following-live-p))
                      (select-window live-window)
                      (should (emacsvox-eat--following-live-p))))
                (when (eat-term-live-p eat-terminal)
                  (eat-term-delete eat-terminal))))))
      (when (buffer-live-p buffer) (kill-buffer buffer)))))

(ert-deftest emacsvox-eat-scrollback-suppresses-but-retains-output ()
  "A selected scrollback review retains a change without presenting it."
  (with-temp-buffer
    (let* ((emacsvox-eat--generation 5)
           (emacsvox-eat--update-serial 9)
           (emacsvox-eat--quiescence-timer t)
           (emacsvox-eat--pending-screen-diff
            '(:text-changed t :row-change
              (:start 0 :old-rows nil :new-rows ("private output"))))
           (emacsvox-eat--screen-snapshot
            '(:cursor-row 1 :alternate-screen nil))
           presented)
      (cl-letf (((symbol-function 'emacsvox-eat--selected-buffer-p)
                 (lambda () t))
                ((symbol-function 'emacsvox-eat--following-live-p)
                 (lambda () nil))
                ((symbol-function 'emacsvox-eat--screen-quiesced)
                 (lambda (&rest _) (setq presented t))))
        (emacsvox-eat--finish-quiescence
         (current-buffer) emacsvox-eat--generation
         emacsvox-eat--update-serial))
      (should-not presented)
      (should (equal emacsvox-eat--last-screen-diff
                     '(:text-changed t :row-change
                       (:start 0 :old-rows nil
                        :new-rows ("private output"))
                       :user-input nil)))
      (should (eq emacsvox-eat--last-changed-screen
                  emacsvox-eat--screen-snapshot))
      (should-not emacsvox-eat--pending-screen-diff)
      (should-not emacsvox-eat--quiescence-timer))))

(ert-deftest emacsvox-eat-scrollback-retains-the-latest-status ()
  "A suppressed progress row remains available for later review."
  (with-temp-buffer
    (let ((diff
           '(:text-changed t :user-input nil :size-changed nil
             :alternate-screen-changed nil
             :row-change
             (:start 0 :old-rows ("Progress 10%")
              :new-rows ("Progress 20%"))))
          (snapshot '(:cursor-row 0 :alternate-screen nil)))
      (emacsvox-eat--retain-screen-change diff snapshot)
      (should (equal emacsvox-eat--last-status-text "Progress 20%"))
      (should (eq emacsvox-eat--last-screen-diff diff))
      (should (eq emacsvox-eat--last-changed-screen snapshot)))))

(ert-deftest emacsvox-eat-screen-observer-has-an-absolute-burst-deadline ()
  "Continuous repaint cannot postpone screen classification indefinitely."
  (with-temp-buffer
    (let ((emacsvox-eat--generation 3)
          (emacsvox-eat--update-serial 8)
          (emacsvox-eat--quiescence-started-at 100.0)
          scheduled-delay
          scheduled-arguments)
      (cl-letf (((symbol-function 'float-time)
                 (lambda (&optional _) 100.23))
                ((symbol-function 'run-at-time)
                 (lambda (delay repeat function &rest arguments)
                   (setq scheduled-delay delay
                         scheduled-arguments
                         (cons repeat (cons function arguments)))
                   'test-timer)))
        (emacsvox-eat--schedule-quiescence))
      (should (< (abs (- scheduled-delay 0.02)) 0.000001))
      (should
       (equal
        (cdr scheduled-arguments)
        (list #'emacsvox-eat--finish-quiescence
              (current-buffer) 3 8)))
      (setq emacsvox-eat--quiescence-timer nil))))

(ert-deftest emacsvox-eat-screen-observer-is-chunk-boundary-independent ()
  "Split text and escape sequences converge on the same final screen diff."
  (cl-labels
      ((observe-chunks
        (chunks)
        (with-temp-buffer
          (let ((eat-terminal (eat-term-make (current-buffer) (point-min))))
            (unwind-protect
                (cl-letf (((symbol-function
                            'emacsvox-eat--selected-buffer-p)
                           (lambda () t)))
                  (eat-term-resize eat-terminal 40 6)
                  (eat-term-process-output eat-terminal "prompt\r\n")
                  (eat-term-redisplay eat-terminal)
                  (emacsvox-eat--observe-screen)
                  (dolist (chunk chunks)
                    (eat-term-process-output eat-terminal chunk)
                    (eat-term-redisplay eat-terminal)
                    (emacsvox-eat--observe-screen))
                  (list
                   (plist-get emacsvox-eat--screen-snapshot :text)
                   (plist-get emacsvox-eat--screen-snapshot :rows)
                   (plist-get emacsvox-eat--screen-snapshot :styles)
                   (plist-get emacsvox-eat--pending-screen-diff :text-change)
                   (plist-get emacsvox-eat--pending-screen-diff :row-change)))
              (emacsvox-eat--cancel-quiescence)
              (when (eat-term-live-p eat-terminal)
                (eat-term-delete eat-terminal)))))))
    (should
     (equal
      (observe-chunks '("\e[1mBold\e[0m\r\nsecond"))
      (observe-chunks '("\e[1" "mBo" "ld\e[0" "m\r" "\nsec" "ond"))))))

(ert-deftest emacsvox-eat-screen-observer-discards-focus-lost-delivery ()
  "A selected update that loses focus before quiescence stays silent."
  (with-temp-buffer
    (let ((eat-terminal (eat-term-make (current-buffer) (point-min)))
          (selected-p t)
          delivered
          pending-timer)
      (unwind-protect
          (cl-letf (((symbol-function 'emacsvox-eat--selected-buffer-p)
                     (lambda () selected-p))
                    ((symbol-function 'emacsvox-eat--screen-quiesced)
                     (lambda (&rest event) (push event delivered))))
            (eat-term-process-output eat-terminal "prompt")
            (eat-term-redisplay eat-terminal)
            (emacsvox-eat--observe-screen)
            (eat-term-process-output eat-terminal "\r\nprivate output")
            (eat-term-redisplay eat-terminal)
            (emacsvox-eat--observe-screen)
            (setq selected-p nil
                  pending-timer emacsvox-eat--quiescence-timer)
            (emacsvox-eat--finish-quiescence
             (current-buffer) emacsvox-eat--generation
             emacsvox-eat--update-serial)
            (should-not delivered)
            (should-not emacsvox-eat--pending-screen-diff)
            (eat-term-process-output eat-terminal "\r\nmore private output")
            (eat-term-redisplay eat-terminal)
            (emacsvox-eat--observe-screen)
            (should emacsvox-eat--screen-snapshot)
            (should-not emacsvox-eat--pending-screen-diff)
            (should-not emacsvox-eat--quiescence-timer))
        (when (timerp pending-timer) (cancel-timer pending-timer))
        (emacsvox-eat--cancel-quiescence)
        (when (eat-term-live-p eat-terminal)
          (eat-term-delete eat-terminal))))))

(ert-deftest emacsvox-eat-screen-observer-classifies-repaint-and-resize ()
  "Real unchanged, resize-only, and reflow updates remain distinguishable."
  (with-temp-buffer
    (let ((eat-terminal (eat-term-make (current-buffer) (point-min))))
      (unwind-protect
          (cl-letf (((symbol-function 'emacsvox-eat--selected-buffer-p)
                     (lambda () t)))
            (eat-term-resize eat-terminal 8 4)
            (eat-term-redisplay eat-terminal)
            (emacsvox-eat--observe-screen)
            (eat-term-redisplay eat-terminal)
            (emacsvox-eat--observe-screen)
            (should-not emacsvox-eat--pending-screen-diff)
            (should-not emacsvox-eat--quiescence-timer)
            (eat-term-resize eat-terminal 12 4)
            (eat-term-redisplay eat-terminal)
            (emacsvox-eat--observe-screen)
            (should
             (equal (plist-get emacsvox-eat--pending-screen-diff :changes)
                    '(size)))
            (emacsvox-eat--cancel-quiescence)
            (eat-term-resize eat-terminal 8 4)
            (eat-term-process-output eat-terminal "abcdefghijk")
            (eat-term-redisplay eat-terminal)
            (emacsvox-eat--observe-screen)
            (emacsvox-eat--cancel-quiescence)
            (eat-term-resize eat-terminal 12 4)
            (eat-term-redisplay eat-terminal)
            (emacsvox-eat--observe-screen)
            (should
             (equal (plist-get emacsvox-eat--pending-screen-diff :changes)
                    '(text cursor size))))
        (emacsvox-eat--cancel-quiescence)
        (when (eat-term-live-p eat-terminal)
          (eat-term-delete eat-terminal))))))

(ert-deftest emacsvox-eat-screen-observer-classifies-alternate-transitions ()
  "Real alternate-screen entry and exit retain their semantic boundary."
  (with-temp-buffer
    (let ((eat-terminal (eat-term-make (current-buffer) (point-min))))
      (unwind-protect
          (cl-letf (((symbol-function 'emacsvox-eat--selected-buffer-p)
                     (lambda () t)))
            (eat-term-resize eat-terminal 20 4)
            (eat-term-process-output eat-terminal "Main")
            (eat-term-redisplay eat-terminal)
            (emacsvox-eat--observe-screen)
            (eat-term-process-output eat-terminal "\e[?1049hAlt")
            (eat-term-redisplay eat-terminal)
            (emacsvox-eat--observe-screen)
            (should
             (memq
              'alternate-screen
              (plist-get emacsvox-eat--pending-screen-diff :changes)))
            (should
             (plist-get emacsvox-eat--screen-snapshot :alternate-screen))
            (emacsvox-eat--cancel-quiescence)
            (eat-term-process-output eat-terminal "\e[?1049l")
            (eat-term-redisplay eat-terminal)
            (emacsvox-eat--observe-screen)
            (should
             (memq
              'alternate-screen
              (plist-get emacsvox-eat--pending-screen-diff :changes)))
            (should-not
             (plist-get emacsvox-eat--screen-snapshot :alternate-screen)))
        (emacsvox-eat--cancel-quiescence)
        (when (eat-term-live-p eat-terminal)
          (eat-term-delete eat-terminal))))))

(ert-deftest emacsvox-eat-screen-observer-reset-starts-a-fresh-baseline ()
  "A real EAT reset cancels pending delivery before observing its new screen."
  (with-temp-buffer
    (let ((eat-terminal (eat-term-make (current-buffer) (point-min)))
          (emacsvox-eat--generation 2))
      (unwind-protect
          (cl-letf (((symbol-function 'emacsvox-eat--selected-buffer-p)
                     (lambda () t))
                    ((symbol-function 'emacsvox-speak-line) #'ignore)
                    ((symbol-function 'emacsvox-speak-this-char) #'ignore))
            (eat-term-process-output eat-terminal "prompt")
            (eat-term-redisplay eat-terminal)
            (emacsvox-eat--observe-screen)
            (eat-term-process-output eat-terminal "\r\npending")
            (eat-term-redisplay eat-terminal)
            (emacsvox-eat--observe-screen)
            (should (timerp emacsvox-eat--quiescence-timer))
            (eat-reset)
            (should (= emacsvox-eat--generation 3))
            (should emacsvox-eat--screen-snapshot)
            (should
             (= (plist-get emacsvox-eat--screen-snapshot :generation) 3))
            (should-not emacsvox-eat--pending-screen-baseline)
            (should-not emacsvox-eat--pending-screen-diff)
            (should-not emacsvox-eat--quiescence-timer))
        (emacsvox-eat--cancel-quiescence)
        (when (eat-term-live-p eat-terminal)
          (eat-term-delete eat-terminal))))))

(ert-deftest emacsvox-eat-reset-invalidates-before-terminal-update ()
  "Reset advances its generation before EAT runs the update hook."
  (with-temp-buffer
    (let ((eat-terminal (eat-term-make (current-buffer) (point-min)))
          (emacsvox-eat--generation 3)
          (emacsvox-eat--completion-snapshot '(1 . "~/stale"))
          observed-generation)
      (unwind-protect
          (cl-letf (((symbol-function 'emacsvox-eat--selected-buffer-p)
                     (lambda () t))
                    ((symbol-function 'emacsvox-eat-update-hook)
                     (lambda ()
                       (setq observed-generation
                             emacsvox-eat--generation)))
                    ((symbol-function 'emacsvox-icon) #'ignore)
                    ((symbol-function 'tts-speak) #'ignore))
            (eat-reset)
            (should (= observed-generation 4))
            (should-not emacsvox-eat--completion-snapshot))
        (when (eat-term-live-p eat-terminal)
          (eat-term-delete eat-terminal))))))

(ert-deftest emacsvox-eat-reload-invalidates-every-initialized-buffer ()
  "Reload invalidation advances all initialized EAT speech buffers."
  (let ((first (generate-new-buffer " *emacsvox-eat-first*"))
        (second (generate-new-buffer " *emacsvox-eat-second*"))
        (ordinary (generate-new-buffer " *emacsvox-eat-ordinary*")))
    (unwind-protect
        (progn
          (with-current-buffer first
            (setq-local emacsvox-eat--generation 2
                        emacsvox-eat--completion-snapshot '(1 . "first")))
          (with-current-buffer second
            (setq-local emacsvox-eat--generation 9
                        emacsvox-eat--completion-snapshot '(1 . "second")))
          (emacsvox-eat--invalidate-all-buffer-state)
          (with-current-buffer first
            (should (= emacsvox-eat--generation 3))
            (should-not emacsvox-eat--completion-snapshot))
          (with-current-buffer second
            (should (= emacsvox-eat--generation 10))
            (should-not emacsvox-eat--completion-snapshot))
          (with-current-buffer ordinary
            (should-not
             (local-variable-p 'emacsvox-eat--generation))))
      (dolist (buffer (list first second ordinary))
        (when (buffer-live-p buffer) (kill-buffer buffer))))))

(provide 'emacsvox-eat-tests)
;;; emacsvox-eat-tests.el ends here
