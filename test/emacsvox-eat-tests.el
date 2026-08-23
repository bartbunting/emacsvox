;;; emacsvox-eat-tests.el --- Eat advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'eat)
(load (expand-file-name "../lisp/emacsvox-eat.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

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
  (should (memq #'emacsvox-eat--process-started eat-exec-hook))
  (should (memq #'emacsvox-eat--process-exited eat-exit-hook)))

(ert-deftest emacsvox-eat-yank-feedback-is-target-aware ()
  "Only the matching interactive Eat yank command plays an icon."
  (let ((ems--interactive-fn-name 'eat-yank)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events))))
      (emacsvox--advice-eat-yank-from-kill-ring-after)
      (emacsvox--advice-eat-yank-after))
    (should (equal events '(yank-object)))))

(ert-deftest emacsvox-eat-mode-feedback-names-the-command ()
  "Eat mode feedback identifies the command that ran."
  (let ((ems--interactive-fn-name 'eat-line-mode)
        messages)
    (cl-letf (((symbol-function 'emacsvox-icon) #'ignore)
              ((symbol-function 'message)
               (lambda (format-string &rest args)
                 (push (apply #'format format-string args) messages))))
      (emacsvox--advice-eat-line-mode-after))
    (should (equal messages '("eat-line-mode ")))))

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

(ert-deftest emacsvox-eat-process-generations-clear-transient-state ()
  "Process start and matching exit invalidate asynchronous EAT state."
  (with-temp-buffer
    (let ((emacsvox-eat--generation 7)
          (emacsvox-eat--completion-snapshot '(12 . "stale"))
          (emacsvox-eat--completion-timer
           (run-at-time 60 nil #'ignore))
          (emacsvox-eat--screen-snapshot '(:generation 7 :text "stale"))
          (emacsvox-eat--pending-screen-baseline
           '(:generation 7 :text "older"))
          (emacsvox-eat--pending-screen-diff '(:changes (text)))
          (emacsvox-eat--pending-user-input-p t)
          (emacsvox-eat--quiescence-started-at 10.0)
          (emacsvox-eat--last-status-text "Progress 40%")
          (emacsvox-eat--last-status-spoken-at 20.0)
          (emacsvox-eat--last-completion-output
           '(:rows ("stale candidate")))
          (emacsvox-eat--quiescence-timer
           (run-at-time 60 nil #'ignore))
          process-a process-b)
      (setq process-a (make-symbol "process-a")
            process-b (make-symbol "process-b"))
      (emacsvox-eat--process-started process-a)
      (should (= emacsvox-eat--generation 8))
      (should (eq emacsvox-eat--active-process process-a))
      (should-not emacsvox-eat--completion-snapshot)
      (should-not emacsvox-eat--completion-timer)
      (should-not emacsvox-eat--screen-snapshot)
      (should-not emacsvox-eat--pending-screen-baseline)
      (should-not emacsvox-eat--pending-screen-diff)
      (should-not emacsvox-eat--pending-user-input-p)
      (should-not emacsvox-eat--quiescence-started-at)
      (should-not emacsvox-eat--quiescence-timer)
      (should-not emacsvox-eat--last-status-text)
      (should (= emacsvox-eat--last-status-spoken-at 0.0))
      (should-not emacsvox-eat--last-completion-output)
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
                style-data))))
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
