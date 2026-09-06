;;; emacsvox-eterm-tests.el --- Eterm advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Term advice.

;;; Code:

(require 'ert)
(require 'term)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-eterm.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--eterm-root
  (file-name-as-directory
   (expand-file-name
    "../" (file-name-directory (or load-file-name buffer-file-name))))
  "Repository root used by Term documentation checks.")

(defun emacsvox-test--eterm-file-string (relative-name)
  "Return the literal contents of RELATIVE-NAME below the repository root."
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name relative-name emacsvox-test--eterm-root))
    (buffer-string)))

(defconst emacsvox-test--eterm-targets
  '(term
    ansi-term
    term-mode
    term-emulate-terminal
    term-dynamic-complete
    term-line-mode
    term-char-mode
    term-next-input
    term-next-matching-input
    term-previous-input
    term-previous-matching-input
    term-send-input
    term-previous-prompt
    term-next-prompt
    term-dynamic-list-input-ring
    term-kill-output
    term-quit-subjob
    term-stop-subjob
    term-interrupt-subjob
    term-kill-input
    term-dynamic-list-filename-completions)
  "Term functions advised by the Eterm integration.")

(defconst emacsvox-test--eterm-simple-advice
  '((term :before emacsvox--advice-term-before)
    (ansi-term :before emacsvox--advice-ansi-term-before)
    (term-mode :after emacsvox--advice-term-mode-after)
    (term-line-mode :after emacsvox--advice-term-line-mode-after)
    (term-char-mode :after emacsvox--advice-term-char-mode-after)
    (term-next-input :after emacsvox--advice-term-next-input-after)
    (term-next-matching-input
     :after emacsvox--advice-term-next-matching-input-after)
    (term-previous-input :after emacsvox--advice-term-previous-input-after)
    (term-previous-matching-input
     :after emacsvox--advice-term-previous-matching-input-after)
    (term-send-input :after emacsvox--advice-term-send-input-after)
    (term-previous-prompt :after emacsvox--advice-term-previous-prompt-after)
    (term-next-prompt :after emacsvox--advice-term-next-prompt-after)
    (term-dynamic-list-input-ring
     :after emacsvox--advice-term-dynamic-list-input-ring-after)
    (term-kill-output :after emacsvox--advice-term-kill-output-after)
    (term-quit-subjob :after emacsvox--advice-term-quit-subjob-after)
    (term-stop-subjob :after emacsvox--advice-term-stop-subjob-after)
    (term-interrupt-subjob
     :after emacsvox--advice-term-interrupt-subjob-after)
    (term-kill-input :before emacsvox--advice-term-kill-input-before)
    (term-dynamic-list-filename-completions
     :after
     emacsvox--advice-term-dynamic-list-filename-completions-after))
  "Directly migrated simple Eterm advice.")

(ert-deftest emacsvox-eterm-emacs31-targets-exist ()
  "Every Eterm advice target exists in Emacs 31."
  (dolist (target emacsvox-test--eterm-targets)
    (should (fboundp target)))
  (should
   (equal
    (help-function-arglist 'term-emulate-terminal t)
    '(proc str))))

(ert-deftest emacsvox-eterm-simple-advice-is-directly-registered ()
  "Simple Eterm advice uses native advice directly."
  (dolist (entry emacsvox-test--eterm-simple-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-eterm-completion-advice-is-directly-registered ()
  "Term completion advice uses native advice directly."
  (should
   (advice-member-p
    #'emacsvox--advice-term-dynamic-complete-around
    'term-dynamic-complete)))

(ert-deftest emacsvox-eterm-completion-calls-original-once ()
  "Term completion calls once, returns its result, and speaks inserted text."
  (with-temp-buffer
    (insert "ec")
    (let ((calls 0)
          events)
      (cl-letf (((symbol-function 'emacsvox-speak-region)
                 (lambda (start end)
                   (push
                    (buffer-substring-no-properties start end)
                    events))))
        (should
         (eq
          'completed
          (emacsvox--advice-term-dynamic-complete-around
           (lambda ()
             (cl-incf calls)
             (insert "ho")
             'completed)))))
      (should (= calls 1))
      (should (equal events '("ho"))))))

(ert-deftest emacsvox-eterm-output-advice-is-directly-registered ()
  "Term output advice uses native advice directly."
  (should
   (advice-member-p
    #'emacsvox--advice-term-emulate-terminal-around
    'term-emulate-terminal)))

(ert-deftest emacsvox-eterm-output-skips-a-dead-process ()
  "Term output preserves the reference behavior for a dead process."
  (let ((calls 0))
    (cl-letf (((symbol-function 'process-live-p)
               (lambda (_proc) nil)))
      (should-not
       (emacsvox--advice-term-emulate-terminal-around
        (lambda (&rest _)
          (cl-incf calls))
        'dead-process
        "ignored")))
    (should (= calls 0))))

(ert-deftest emacsvox-eterm-output-uses-explicit-arguments-once ()
  "Term output passes PROC and STR once and preserves the result."
  (with-temp-buffer
    (insert ">")
    (let ((buffer (current-buffer))
          (calls 0)
          received)
      (cl-letf (((symbol-function 'process-live-p)
                 (lambda (_proc) t))
                ((symbol-function 'process-buffer)
                 (lambda (_proc) buffer))
                ((symbol-function 'get-buffer-window)
                 (lambda (&rest _) nil))
                ((symbol-function 'term-current-row)
                 (lambda () 0))
                ((symbol-function 'term-current-column)
                 (lambda () 1)))
        (should
         (eq
          'emulated
          (emacsvox--advice-term-emulate-terminal-around
           (lambda (proc str)
             (cl-incf calls)
             (setq received (list proc str))
             'emulated)
           'fake-process
           "payload"))))
      (should (= calls 1))
      (should (equal received '(fake-process "payload"))))))

(ert-deftest emacsvox-eterm-line-output-speaks-after-one-call ()
  "Line-mode output speaks its changed range after one original call."
  (with-temp-buffer
    (insert ">")
    (let ((buffer (current-buffer))
          (calls 0)
          events
          (emacsvox-eterm-autospeak t)
          (emacsvox-eterm-focus-window nil)
          (emacsvox-eterm-filter-window nil)
          (emacsvox-eterm-pointer-mode t)
          (eterm-line-mode t)
          (eterm-char-mode nil))
      (cl-letf (((symbol-function 'process-live-p)
                 (lambda (_proc) t))
                ((symbol-function 'process-buffer)
                 (lambda (_proc) buffer))
                ((symbol-function 'get-buffer-window)
                 (lambda (&rest _) 'term-window))
                ((symbol-function 'window-live-p)
                 (lambda (window) (eq window 'term-window)))
                ((symbol-function 'term-current-row)
                 (lambda () 0))
                ((symbol-function 'term-current-column)
                 (lambda () 1))
                ((symbol-function 'emacsvox-speak-region)
                 (lambda (start end)
                   (push (list start end) events))))
        (should
         (eq
          'emulated
          (emacsvox--advice-term-emulate-terminal-around
           (lambda (_proc _str)
             (cl-incf calls)
             (insert "ok")
             'emulated)
           'fake-process
           "ok"))))
      (should (= calls 1))
      (should (equal events '((1 3)))))))

(ert-deftest emacsvox-eterm-backspace-preserves-state-and-feedback-order ()
  "Character-mode backspace preserves emulation and feedback ordering."
  (with-temp-buffer
    (insert "ab")
    (goto-char (point-max))
    (let ((buffer (current-buffer))
          (calls 0)
          (current-row 0)
          (current-column 2)
          (emacsvox-eterm-autospeak t)
          (emacsvox-eterm-focus-window nil)
          (emacsvox-eterm-filter-window nil)
          (emacsvox-eterm-pointer-mode t)
          (eterm-line-mode nil)
          (eterm-char-mode t)
          (last-command-event 'backspace)
          (original-delete-char (symbol-function 'delete-char))
          (original-window-live-p (symbol-function 'window-live-p))
          events)
      (cl-letf
          (((symbol-function 'process-live-p)
            (lambda (_proc) t))
           ((symbol-function 'process-buffer)
            (lambda (_proc) buffer))
           ((symbol-function 'get-buffer-window)
            (lambda (&rest _) 'term-window))
           ((symbol-function 'window-live-p)
            (lambda (window)
              (or (eq window 'term-window)
                  (funcall original-window-live-p window))))
           ((symbol-function 'term-current-row)
            (lambda () current-row))
           ((symbol-function 'term-current-column)
            (lambda () current-column))
           ((symbol-function 'emacsvox-speak-this-char)
            (lambda (character)
              (push (list 'character character) events)))
           ((symbol-function 'delete-char)
            (lambda (count)
              (push (list 'delete count) events)
              (funcall original-delete-char count)))
           ((symbol-function 'emacsvox-speak-edit-operation)
            (lambda (operation)
              (push (list 'edit operation) events))))
        (should
         (eq
          (emacsvox--advice-term-emulate-terminal-around
           (lambda (proc str)
             (cl-incf calls)
             (push (list 'original proc str) events)
             (setq current-column 1)
             (backward-char)
             'emulated)
           'fake-process
           "backspace")
          'emulated)))
      (should (= calls 1))
      (should (equal (buffer-string) "a"))
      (should
       (equal
        (nreverse events)
        '((original fake-process "backspace")
          (character 98)
          (delete 1)
          (edit deletion)))))))

(ert-deftest emacsvox-eterm-launch-feedback-remains-unconditional ()
  "Programmatic terminal launch still requests a single window."
  (let (events)
    (cl-letf (((symbol-function 'delete-other-windows)
               (lambda (&rest _) (push 'delete-other-windows events))))
      (emacsvox--advice-term-before)
      (emacsvox--advice-ansi-term-before))
    (should
     (equal
      (nreverse events)
      '(delete-other-windows delete-other-windows)))))

(ert-deftest emacsvox-eterm-history-feedback-is-target-aware ()
  "Only matching interactive input-history movement speaks."
  (let ((ems--interactive-fn-name 'term-next-input)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda (&rest arguments)
                 (push (cons 'line arguments) events))))
      (emacsvox--advice-term-previous-input-after)
      (emacsvox--advice-term-next-input-after))
    (should (equal events '((line))))))

(ert-deftest emacsvox-eterm-mode-state-and-feedback-preserve-contract ()
  "Mode state always updates while speech remains target-aware."
  (with-temp-buffer
    (let ((ems--interactive-fn-name 'term-line-mode)
          events)
      (cl-letf (((symbol-function 'emacsvox-eterm-setup-raw-keys)
                 (lambda () (push 'raw-keys events)))
                ((symbol-function 'tts-speak)
                 (lambda (text) (push (list 'speak text) events))))
        (emacsvox--advice-term-char-mode-after)
        (emacsvox--advice-term-line-mode-after))
      (should eterm-line-mode)
      (should-not eterm-char-mode)
      (should (equal mode-line-process '("line")))
      (should
       (equal
        (nreverse events)
        '(raw-keys (speak "Terminal line mode ")))))))

(ert-deftest emacsvox-eterm-input-ring-notice-remains-unconditional ()
  "The input-ring browsing notice is emitted for internal calls."
  (let ((ems--interactive-fn-name nil)
        events)
    (cl-letf (((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push (apply #'format format-string arguments) events))))
      (emacsvox--advice-term-dynamic-list-input-ring-after))
    (should
     (equal
      events
      '("Switch to the other window to browse the input history ")))))

(ert-deftest emacsvox-eterm-current-guide-owns-the-supported-workflow ()
  "Current Term guidance should be separate from the inherited survey."
  (let ((guide (emacsvox-test--eterm-file-string "info/emacsvox-body.texi"))
        (survey (emacsvox-test--eterm-file-string "info/eterm.texi"))
        (master (emacsvox-test--eterm-file-string "docs/manual/emacsvox.org"))
        (heritage
         (emacsvox-test--eterm-file-string "info/emacsvox-heritage.texi"))
        (menu (emacsvox-test--eterm-file-string "info/preamble.texi"))
        (applications
         (emacsvox-test--eterm-file-string "info/emacsvox-body.texi")))
    (should
     (string-match-p
      (regexp-quote "#+include: \"chapters/term.org\"") master))
    (should-not (string-match-p "@include eterm\\.texi" master))
    (should (string-match-p "@include eterm\\.texi" heritage))
    (should
     (string-match-p
      "\\* Historical Term Survey: Running Terminal Based Applications\\."
      heritage))
    (should
     (string-match-p
      "\\* Term Terminal Access: Running Terminal Based Applications\\."
      menu))
    (dolist
        (required
         '("@chapter Term Terminal Access"
           "prefer @ref{EAT Terminal Access}"
           "@kbd{M-x term @key{RET}}"
           "fill the frame"
           "@kbd{C-c C-j}"
           "@kbd{C-c C-k}"
           "@kbd{C-c C-h m}"
           "@kbd{C-t C-t}"
           "@code{emacsvox-eterm-autospeak}"
           "@kbd{C-t C-q}"
           "The older spelling\n@code{eterm-autospeak} is not an Emacsvox variable"
           "hidden Term buffer can continue running without speaking"
           "@kbd{C-t q}"
           "@ref{emacsvox-eterm,,,emacsvox-reference"))
      (should (string-match-p (regexp-quote required) guide)))
    (should-not
     (string-match-p
      (regexp-quote
       "program output is spoken if user option\n@code{eterm-autospeak}")
      guide))
    (should
     (string-match-p "@chapter Historical Term And Eterm Survey" survey))
    (should
     (string-match-p (regexp-quote "@code{eterm-autospeak}") survey))
    (dolist
        (reference
         '("@ref{EAT Terminal Access}"
           "@ref{Running Terminal Based Applications}"))
      (should (string-match-p (regexp-quote reference) applications)))))

(ert-deftest emacsvox-eterm-current-guide-keys-match-live-maps ()
  "The documented starter keys should resolve to the current commands."
  (emacsvox-eterm-setup-keys)
  (emacsvox-eterm-setup-raw-keys)
  (dolist
      (entry
       '(("C-q" . emacsvox-toggle-eterm-autospeak)
         ("." . emacsvox-eterm-pointer-to-cursor)
         ("p" . emacsvox-eterm-pointer-up)
         ("n" . emacsvox-eterm-pointer-down)
         ("<left>" . emacsvox-eterm-pointer-left)
         ("<right>" . emacsvox-eterm-pointer-right)
         ("M-b" . emacsvox-eterm-pointer-backward-word)
         ("M-f" . emacsvox-eterm-pointer-forward-word)
         ("l" . emacsvox-eterm-speak-pointer-line)
         ("w" . emacsvox-eterm-speak-pointer-word)
         ("c" . emacsvox-eterm-speak-pointer-char)
         ("SPC" . emacsvox-eterm-speak-screen)
         ("s" . emacsvox-eterm-search-forward)
         ("q" . emacsvox-eterm-toggle-review)
         ("m" . emacsvox-eterm-set-marker)
         ("y" . emacsvox-eterm-kill-ring-save-region)))
    (should
     (eq (lookup-key emacsvox-eterm-keymap (kbd (car entry)))
         (cdr entry))))
  (dolist
      (entry
       '(("C-c C-j" . term-line-mode)
         ("C-c C-k" . term-char-mode)
         ("C-c C-h m" . describe-mode)
         ("C-c M-x" . execute-extended-command)
         ("C-t C-t" . emacsvox-eterm-maybe-send-raw)))
    (should
     (eq (lookup-key term-raw-map (kbd (car entry)))
         (cdr entry))))
  (should (default-value 'emacsvox-eterm-autospeak))
  (should-not (boundp 'eterm-autospeak)))

(provide 'emacsvox-eterm-tests)
;;; emacsvox-eterm-tests.el ends here
