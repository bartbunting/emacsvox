;;; emacsvox-eat-tests.el --- Eat advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(require 'eat)
(load (expand-file-name "../lisp/emacsvox-eat.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

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
  "A terminal completion on the current line speaks its final component."
  (with-temp-buffer
    (insert "$ ~/sr")
    (let ((eat-terminal 'terminal)
          (eat--semi-char-mode t)
          events)
      (cl-letf (((symbol-function 'eat-term-display-cursor)
                 (lambda (_terminal) (point-marker)))
                ((symbol-function 'emacsvox-eat--selected-buffer-p)
                 (lambda () t))
                ((symbol-function 'tts-speak)
                 (lambda (text) (push (list 'speak text) events)))
                ((symbol-function 'emacsvox-speak-line)
                 (lambda () (push '(line) events)))
                ((symbol-function 'emacsvox-speak-this-char)
                 (lambda (char) (push (list 'char char) events))))
        (emacsvox--advice-eat-self-input-before 1 'tab)
        (erase-buffer)
        (insert "$ ~/src/")
        (emacsvox-eat-update-hook))
      (should-not emacsvox-eat--completion-snapshot)
      (should (equal (nreverse events) '((speak "src/")))))))

(ert-deftest emacsvox-eat-multiline-completion-uses-ordinary-feedback ()
  "A candidate listing on another line remains outside the narrow fix."
  (with-temp-buffer
    (insert "$ ~/sr")
    (let ((eat-terminal 'terminal)
          (eat--semi-char-mode t)
          events)
      (cl-letf (((symbol-function 'eat-term-display-cursor)
                 (lambda (_terminal) (point-marker)))
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
      (should-not emacsvox-eat--completion-snapshot)
      (should (equal (nreverse events) '((char 47)))))))

(ert-deftest emacsvox-eat-background-update-is-silent ()
  "An EAT resize while another buffer is selected produces no speech."
  (with-temp-buffer
    (insert "shell-prompt$ ")
    (let ((eat-terminal 'terminal)
          (emacsvox-eat--completion-snapshot '(1 . "~/sr"))
          events)
      (cl-letf (((symbol-function 'emacsvox-eat--selected-buffer-p)
                 (lambda () nil))
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
          process-a process-b)
      (setq process-a (make-symbol "process-a")
            process-b (make-symbol "process-b"))
      (emacsvox-eat--process-started process-a)
      (should (= emacsvox-eat--generation 8))
      (should (eq emacsvox-eat--active-process process-a))
      (should-not emacsvox-eat--completion-snapshot)
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
