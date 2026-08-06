;;; emacsvox-comint-tests.el --- Comint advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Comint advice.

;;; Code:

(require 'ert)
(require 'comint)
(require 'shell)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-comint.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--comint-removed-targets
  '(comint-dynamic-complete comint-kill-output)
  "Comint commands absent from Emacs 31.")

(ert-deftest emacsvox-comint-obsolete-targets-remain-absent ()
  "The integration must not recreate commands removed before Emacs 31."
  (dolist (target emacsvox-test--comint-removed-targets)
    (should-not (fboundp target))))

(ert-deftest emacsvox-comint-emacs31-replacement-targets-exist ()
  "Current completion and output-deletion facilities are available."
  (dolist (target
           '(completion-at-point
             comint-completion-at-point
             comint-delete-output))
    (should (fboundp target)))
  (with-temp-buffer
    (comint-mode)
    (should
     (equal completion-at-point-functions
            '(comint-completion-at-point t)))
    (should (eq (key-binding (kbd "TAB")) 'indent-for-tab-command))
    (should (eq (key-binding (kbd "C-c C-o")) 'comint-delete-output))))

(ert-deftest emacsvox-comint-registers-command-semantic-vocabulary ()
  "Shell migration facts are registered before integrations submit them."
  (dolist
      (entry
       '((command-interaction role)
         (command-input role)
         (command-output role)
         (command-prompt role)
         (command-interaction-kind attribute)
         (command-operation attribute)
         (command-input-origin attribute)
         (command-submitted event)
         (command-output-received event)
         (command-prompt-ready event)
         (command-process-signalled event)
         (command-process-exited event)
         (command-exit-status attribute)))
    (pcase-let ((`(,id ,kind) entry))
      (let ((semantic (emacsvox-aural-semantic id)))
        (should semantic)
        (should (eq (emacsvox-aural-semantic-kind semantic) kind))))))

(ert-deftest emacsvox-comint-context-distinguishes-shell-from-shared-comint ()
  "Shell buffers and generic Comint buffers expose distinct module context."
  (with-temp-buffer
    (comint-mode)
    (should (eq emacsvox-aural-module 'comint))
    (should
     (equal
      (emacsvox-comint-facts
       'command-input 'focus-entered 'history-navigation
       '(:command-input-origin history))
      '(:role command-input
        :command-interaction-kind repl
        :events (focus-entered)
        :command-operation history-navigation
        :command-input-origin history))))
  (with-temp-buffer
    (shell-mode)
    (should (eq emacsvox-aural-module 'shell))
    (should
     (equal
      (emacsvox-comint-facts 'command-prompt 'command-prompt-ready)
      '(:role command-prompt
        :command-interaction-kind shell
        :events (command-prompt-ready))))))

(defconst emacsvox-test--comint-navigation-history-after-targets
  '(comint-history-isearch-backward
    comint-history-isearch-backward-regexp
    comint-next-matching-input-from-input
    comint-previous-matching-input-from-input
    shell-forward-command
    shell-backward-command
    comint-show-output
    comint-show-maximum-output
    comint-bol-or-process-mark
    comint-copy-old-input
    comint-next-input
    comint-next-matching-input
    comint-previous-input
    comint-previous-matching-input
    comint-previous-prompt
    comint-next-prompt
    comint-get-next-from-history)
  "Comint navigation and history commands with direct after advice.")

(ert-deftest emacsvox-comint-navigation-history-advice-is-directly-registered ()
  "Comint navigation and history advice uses native advice directly."
  (dolist (target emacsvox-test--comint-navigation-history-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-comint-navigation-feedback-is-target-aware ()
  "Only matching interactive Comint navigation speaks and cues."
  (let ((ems--interactive-fn-name 'shell-forward-command)
        events)
    (cl-letf
        (((symbol-function 'emacsvox-comint--present-line-feedback)
          (lambda (_facts _occasion icon phase &optional _argument)
            (push (list 'line icon phase) events))))
      (emacsvox--advice-shell-backward-command-after)
      (emacsvox--advice-shell-forward-command-after))
    (should
     (equal
      (nreverse events)
      '((line item after))))))

(ert-deftest emacsvox-comint-navigation-has-one-semantic-boundary ()
  "Shell command navigation preserves speech-first order in one transaction."
  (with-temp-buffer
    (shell-mode)
    (let ((ems--interactive-fn-name 'shell-forward-command)
          boundaries
          events)
      (cl-letf
          (((symbol-function 'emacsvox-aural-call-with-submission)
            (lambda (function &rest arguments)
              (push
               (list
                (plist-get arguments :facts)
                (plist-get arguments :module)
                (plist-get arguments :occasion))
               boundaries)
              (apply function (plist-get arguments :arguments))))
           ((symbol-function 'emacsvox-speak--present-physical-line)
            (lambda (argument actions)
              (push
               (list
                'line argument
                (mapcar
                 (lambda (action)
                   (list
                    (emacsvox-aural-compatibility-action-value action)
                    (emacsvox-aural-compatibility-action-phase action)))
                 actions))
               events)))
           ((symbol-function 'emacsvox-icon)
            (lambda (icon)
              (ert-fail (format "Escaped Comint icon: %S" icon)))))
        (emacsvox--advice-shell-forward-command-after))
      (should
       (equal
        boundaries
        '(((:role command-input
            :command-interaction-kind shell
            :events (focus-entered)
            :command-operation command-navigation
            :command-input-origin current)
           shell navigation))))
      (should
       (equal
        (nreverse events)
        '((line nil ((item after)))))))))

(ert-deftest emacsvox-comint-history-navigation-keeps-line-cue-phases ()
  "History line cues enter the same physical-line submission in order."
  (dolist
      (case
       '((comint-history-isearch-backward select-object before)
         (comint-next-matching-input-from-input select-object after)
         (comint-next-input item after)
         (comint-get-next-from-history item before)))
    (pcase-let ((`(,target ,icon ,phase) case))
      (let ((ems--interactive-fn-name target)
            observed)
        (cl-letf
            (((symbol-function 'comint-bol-or-process-mark) #'ignore)
             ((symbol-function 'comint-line-beginning-position)
              (lambda () (point)))
             ((symbol-function 'comint-bol) #'ignore)
             ((symbol-function 'emacsvox-comint--present-line-feedback)
              (lambda (facts occasion value action-phase &optional argument)
                (setq
                 observed
                 (list facts occasion value action-phase argument)))))
          (funcall
           (intern (format "emacsvox--advice-%s-after" target))))
        (should (eq (nth 1 observed) 'navigation))
        (should (eq (nth 2 observed) icon))
        (should (eq (nth 3 observed) phase))
        (should (= (nth 4 observed) 1))
        (should
         (eq
          (plist-get (car observed) :command-operation)
          'history-navigation))))))

(ert-deftest emacsvox-comint-output-process-advice-is-directly-registered ()
  "Comint output and subprocess advice uses native advice directly."
  (dolist
      (entry
       '((comint-delete-output
          :after emacsvox--advice-comint-delete-output-after)
         (comint-clear-buffer
          :after emacsvox--advice-comint-clear-buffer-after)
         (shell-dirstack-message
          :around emacsvox--advice-shell-dirstack-message-around)
         (comint-output-filter
          :around emacsvox--advice-comint-output-filter-around)
         (comint-quit-subjob
          :after emacsvox--advice-comint-quit-subjob-after)
         (comint-stop-subjob
          :after emacsvox--advice-comint-stop-subjob-after)
         (comint-interrupt-subjob
          :after emacsvox--advice-comint-interrupt-subjob-after)))
    (pcase-let ((`(,target ,where ,function) entry))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-comint-dirstack-message-calls-original-once ()
  "Shell directory-stack reporting preserves one silenced call."
  (let ((calls 0))
    (should
     (eq
      (emacsvox--advice-shell-dirstack-message-around
       (lambda ()
         (cl-incf calls)
         'dirstack-result))
      'dirstack-result))
    (should (= calls 1))))

(defun emacsvox-test--comint-output-chunk
    (buffer process-marker raw-output &optional inserted-output)
  "Run one advised process output chunk in BUFFER.
PROCESS-MARKER is advanced past INSERTED-OUTPUT, which defaults to RAW-OUTPUT."
  (cl-letf (((symbol-function 'process-buffer)
             (lambda (process)
               (should (eq process 'test-process))
               buffer))
            ((symbol-function 'process-mark)
             (lambda (process)
               (should (eq process 'test-process))
               process-marker)))
    (emacsvox--advice-comint-output-filter-around
     (lambda (process output)
       (should (eq process 'test-process))
       (should (equal output raw-output))
       (with-current-buffer buffer
         (goto-char process-marker)
         (insert (or inserted-output raw-output))
         (set-marker process-marker (point)))
       'filter-result)
     'test-process raw-output)))

(ert-deftest emacsvox-comint-output-filter-calls-original-once ()
  "Each process chunk is inserted once before normalized aural submission."
  (with-temp-buffer
    (let ((output-buffer (current-buffer))
          (process-marker (copy-marker (point-min)))
          (emacsvox-comint-output-monitor t)
          (emacsvox-comint-autospeak t)
          (comint-prompt-regexp "\\`never-a-prompt\\'")
          events)
      (cl-letf (((symbol-function 'emacsvox-comint--submit)
                 (lambda (content facts occasion &rest _)
                   (push (list 'submit content facts occasion) events))))
        (should
         (eq
          (emacsvox-test--comint-output-chunk
           output-buffer process-marker "ordinary output\n")
          'filter-result)))
      (should
       (equal
        (nreverse events)
        '((submit
           "ordinary output\n"
           (:role command-output
            :command-interaction-kind repl
            :events (command-output-received))
           continuous)))))))

(ert-deftest emacsvox-comint-output-waits-for-logical-line-boundaries ()
  "Partial process chunks produce one logical output presentation."
  (with-temp-buffer
    (let ((buffer (current-buffer))
          (process-marker (copy-marker (point-min)))
          (emacsvox-comint-output-monitor t)
          (emacsvox-comint-autospeak t)
          (comint-prompt-regexp "\\`never-a-prompt\\'")
          events)
      (cl-letf (((symbol-function 'emacsvox-comint--submit)
                 (lambda (content &rest _)
                   (push content events))))
        (emacsvox-test--comint-output-chunk buffer process-marker "par")
        (should-not events)
        (should (equal emacsvox-comint--pending-output "par"))
        (emacsvox-test--comint-output-chunk
         buffer process-marker "tial\nsecond")
        (should (equal events '("partial\n")))
        (should (equal emacsvox-comint--pending-output "second"))))))

(ert-deftest emacsvox-comint-output-separates-trailing-prompt ()
  "Output and a prompt in one process chunk become separate ordered events."
  (with-temp-buffer
    (let ((buffer (current-buffer))
          (process-marker (copy-marker (point-min)))
          (emacsvox-comint-output-monitor t)
          (emacsvox-comint-autospeak t)
          (comint-prompt-regexp "[$] ")
          events)
      (cl-letf
          (((symbol-function 'emacsvox-comint--submit)
            (lambda (content &rest _)
              (push (list 'output content) events)))
           ((symbol-function 'emacsvox-comint--present-feedback)
            (lambda (facts occasion icon function &rest arguments)
              (push (list 'prompt facts occasion icon) events)
              (apply function arguments))))
        (emacsvox-test--comint-output-chunk
         buffer process-marker "result\n$ "))
      (should
       (equal
        (nreverse events)
        '((output "result\n")
          (prompt
           (:role command-prompt
            :command-interaction-kind repl
            :events (command-prompt-ready))
           notification item))))
      (should (equal emacsvox-comint--last-prompt "$ "))
      (should (equal emacsvox-comint--pending-output "")))))

(ert-deftest emacsvox-comint-output-reassembles-a-split-prompt ()
  "A prompt split across process chunks produces one prompt event."
  (with-temp-buffer
    (let ((buffer (current-buffer))
          (process-marker (copy-marker (point-min)))
          (emacsvox-comint-output-monitor t)
          (emacsvox-comint-autospeak t)
          (comint-prompt-regexp "[$] ")
          events)
      (cl-letf
          (((symbol-function 'emacsvox-comint--submit)
            (lambda (&rest _) (push 'output events)))
           ((symbol-function 'emacsvox-comint--present-feedback)
            (lambda (_facts _occasion icon function &rest arguments)
              (push icon events)
              (apply function arguments))))
        (emacsvox-test--comint-output-chunk buffer process-marker "$")
        (should-not events)
        (emacsvox-test--comint-output-chunk buffer process-marker " "))
      (should (equal events '(item)))
      (should (equal emacsvox-comint--pending-output "")))))

(ert-deftest emacsvox-comint-known-prompt-delimits-non-newline-output ()
  "A known prompt preserves preceding output that has no final newline."
  (with-temp-buffer
    (let ((buffer (current-buffer))
          (process-marker (copy-marker (point-min)))
          (emacsvox-comint-output-monitor t)
          (emacsvox-comint-autospeak t)
          (emacsvox-comint--last-prompt "$ ")
          (comint-prompt-regexp "[$] ")
          events)
      (cl-letf
          (((symbol-function 'emacsvox-comint--submit)
            (lambda (content &rest _)
              (push (list 'output content) events)))
           ((symbol-function 'emacsvox-comint--present-feedback)
            (lambda (_facts _occasion icon function &rest arguments)
              (push (list 'prompt icon) events)
              (apply function arguments))))
        (emacsvox-test--comint-output-chunk
         buffer process-marker "value")
        (should-not events)
        (emacsvox-test--comint-output-chunk
         buffer process-marker "$ "))
      (should
       (equal
        (nreverse events)
        '((output "value") (prompt item)))))))

(ert-deftest emacsvox-comint-carriage-return-replaces-pending-progress ()
  "Carriage-motion output does not speak every overwritten progress value."
  (with-temp-buffer
    (let ((buffer (current-buffer))
          (process-marker (copy-marker (point-min)))
          (emacsvox-comint-output-monitor t)
          (emacsvox-comint-autospeak t)
          (emacsvox-comint--last-prompt "$ ")
          (comint-prompt-regexp "[$] ")
          events)
      (cl-letf
          (((symbol-function 'emacsvox-comint--submit)
            (lambda (content &rest _) (push content events)))
           ((symbol-function 'emacsvox-comint--present-feedback)
            (lambda (_facts _occasion _icon function &rest arguments)
              (apply function arguments))))
        (emacsvox-test--comint-output-chunk
         buffer process-marker "10 percent")
        ;; Model the normalized text left by Comint carriage motion.
        (emacsvox-test--comint-output-chunk
         buffer process-marker "\r20 percent" "20 percent")
        (emacsvox-test--comint-output-chunk
         buffer process-marker "$ "))
      (should (equal events '("20 percent"))))))

(ert-deftest emacsvox-comint-output-submits-normalized-buffer-text ()
  "Autospeech uses post-filter buffer text rather than raw terminal escapes."
  (with-temp-buffer
    (let ((buffer (current-buffer))
          (process-marker (copy-marker (point-min)))
          (emacsvox-comint-output-monitor t)
          (emacsvox-comint-autospeak t)
          (comint-prompt-regexp "\\`never-a-prompt\\'")
          events)
      (cl-letf (((symbol-function 'emacsvox-comint--submit)
                 (lambda (content &rest _) (push content events))))
        (emacsvox-test--comint-output-chunk
         buffer process-marker "\e[31merror\e[0m\n" "error\n"))
      (should (equal events '("error\n"))))))

(ert-deftest emacsvox-comint-output-does-not-backlog-ineligible-speech ()
  "Disabled or unmonitored output is discarded instead of spoken later."
  (with-temp-buffer
    (let ((buffer (current-buffer))
          (process-marker (copy-marker (point-min)))
          (emacsvox-comint-output-monitor nil)
          (emacsvox-comint-autospeak t)
          (comint-prompt-regexp "\\`never-a-prompt\\'")
          events)
      (cl-letf
          (((symbol-function 'window-buffer)
            (lambda (&optional _window) (get-buffer-create " *elsewhere*")))
           ((symbol-function 'emacsvox-comint--submit)
            (lambda (&rest _) (push 'submit events))))
        (emacsvox-test--comint-output-chunk
         buffer process-marker "hidden partial")
        (should-not events)
        (should (equal emacsvox-comint--pending-output ""))
        (setq emacsvox-comint-output-monitor t)
        (emacsvox-test--comint-output-chunk
         buffer process-marker "visible\n"))
      (should (equal events '(submit))))))

(ert-deftest emacsvox-comint-output-survives-a-killed-process-buffer ()
  "A process buffer killed by the original filter does not cause feedback errors."
  (let ((buffer (generate-new-buffer " *emacsvox-dead-comint*"))
        process-marker)
    (unwind-protect
        (progn
          (with-current-buffer buffer
            (setq process-marker (copy-marker (point-min))))
          (cl-letf (((symbol-function 'process-buffer)
                     (lambda (_process) buffer))
                    ((symbol-function 'process-mark)
                     (lambda (_process) process-marker)))
            (should
             (eq
              (emacsvox--advice-comint-output-filter-around
               (lambda (&rest _)
                 (kill-buffer buffer)
                 'filter-result)
               'test-process "final")
              'filter-result))))
      (when (buffer-live-p buffer) (kill-buffer buffer)))))

(ert-deftest emacsvox-comint-process-exit-flushes-output-and-announces-once ()
  "Terminal process state flushes partial output before one close event."
  (let ((buffer (generate-new-buffer " *emacsvox-comint-exit*"))
        process
        (original-calls 0)
        events)
    (unwind-protect
        (progn
          (setq process
                (make-pipe-process
                 :name "emacsvox-comint-exit"
                 :buffer buffer
                 :noquery t))
          (with-current-buffer buffer
            (comint-mode)
            (setq-local emacsvox-comint-autospeak t)
            (setq-local emacsvox-comint-output-monitor t)
            (setq-local emacsvox-comint--pending-output "final partial")
            (set-process-sentinel
             process
             (lambda (_process _event) (cl-incf original-calls)))
            (emacsvox-comint-install-process-sentinel))
          (let ((wrapper (process-sentinel process)))
            (cl-letf
                (((symbol-function 'process-status)
                  (lambda (candidate)
                    (should (eq candidate process))
                    'exit))
                 ((symbol-function 'process-exit-status)
                  (lambda (candidate)
                    (should (eq candidate process))
                    0))
                 ((symbol-function 'emacsvox-comint--submit)
                  (lambda (content facts occasion &rest _)
                    (setq
                     events
                     (append
                      events
                      (list (list 'output content facts occasion))))))
                 ((symbol-function 'emacsvox-comint--present-feedback)
                  (lambda (facts occasion icon function &rest arguments)
                    (setq
                     events
                     (append
                      events
                      (list (list 'exit facts occasion icon))))
                    (apply function arguments))))
              (funcall wrapper process "finished\n")
              (funcall wrapper process "finished\n"))))
          (with-current-buffer buffer
            (should (equal emacsvox-comint--pending-output "")))
          (should (= original-calls 2))
          (should
           (equal
            events
            '((output
               "final partial"
               (:role command-output
                :command-interaction-kind repl
                :events (command-output-received))
               continuous)
              (exit
               (:role command-interaction
                :command-interaction-kind repl
                :events (command-process-exited)
                :command-operation process-exit
                :command-exit-status 0)
               notification close-object))))
      (when (processp process)
        (set-process-sentinel process nil)
        (ignore-errors (delete-process process)))
      (when (buffer-live-p buffer) (kill-buffer buffer)))))

(ert-deftest emacsvox-comint-process-sentinel-wraps-a-nil-sentinel-once ()
  "Lifecycle installation handles processes without an existing sentinel."
  (let ((buffer (generate-new-buffer " *emacsvox-comint-sentinel*"))
        process)
    (unwind-protect
        (progn
          (setq process
                (make-pipe-process
                 :name "emacsvox-comint-sentinel"
                 :buffer buffer
                 :noquery t))
          (set-process-sentinel process nil)
          (with-current-buffer buffer
            (comint-mode)
            (emacsvox-comint-install-process-sentinel)
            (let ((installed (process-sentinel process)))
              (should (functionp installed))
              (emacsvox-comint-install-process-sentinel)
              (should (eq (process-sentinel process) installed)))))
      (when (processp process)
        (set-process-sentinel process nil)
        (ignore-errors (delete-process process)))
      (when (buffer-live-p buffer) (kill-buffer buffer)))))

(ert-deftest emacsvox-comint-failed-process-uses-warning-cue ()
  "A signalled command process is distinct from a normal session close."
  (let ((buffer (generate-new-buffer " *emacsvox-comint-failure*"))
        process
        icons)
    (unwind-protect
        (progn
          (setq process
                (make-pipe-process
                 :name "emacsvox-comint-failure"
                 :buffer buffer
                 :noquery t))
          (with-current-buffer buffer
            (comint-mode)
            (setq-local emacsvox-comint-autospeak t)
            (setq-local emacsvox-comint-output-monitor t))
          (cl-letf
              (((symbol-function 'process-status)
                (lambda (_process) 'signal))
               ((symbol-function 'process-exit-status)
                (lambda (_process) 9))
               ((symbol-function 'emacsvox-comint--present-feedback)
                (lambda (_facts _occasion icon function &rest arguments)
                  (push icon icons)
                  (apply function arguments))))
            (emacsvox-comint--handle-process-exit process "killed\n"))
          (should (equal icons '(warn-user))))
      (when (processp process)
        (set-process-sentinel process nil)
        (ignore-errors (delete-process process)))
      (when (buffer-live-p buffer) (kill-buffer buffer)))))

(ert-deftest emacsvox-comint-split-prompt-drives-procfs-tracking-once ()
  "Directory tracking follows the logical prompt, even with autospeak off."
  (with-temp-buffer
    (shell-mode)
    (let ((emacsvox-comint-autospeak nil)
          (comint-prompt-regexp "[$] ")
          (dirtrack-procfs-mode t)
          (calls 0))
      (cl-letf (((symbol-function 'emacsvox-shell-dirtrack-procfs)
                 (lambda (&optional output)
                   (cl-incf calls)
                   output)))
        (emacsvox-comint--present-process-output "$" "$")
        (should (= calls 1))
        (emacsvox-comint--present-process-output " " " "))
      (should (= calls 1))
      (should (equal emacsvox-comint--last-prompt "$ "))
      (should (equal emacsvox-comint--pending-output "")))))

(ert-deftest emacsvox-shell-procfs-tracking-updates-only-at-a-new-directory ()
  "Procfs tracking changes directory once and preserves its filter argument."
  (with-temp-buffer
    (shell-mode)
    (let ((default-directory "/old/")
          changed-to)
      (cl-letf
          (((symbol-function 'emacsvox-shell--procfs-directory)
            (lambda () "/new/"))
           ((symbol-function 'file-equal-p)
            (lambda (left right)
              (equal left right)))
           ((symbol-function 'cd)
            (lambda (directory)
              (setq changed-to directory
                    default-directory directory))))
        (should
         (equal
          (emacsvox-shell-dirtrack-procfs "unchanged output")
          "unchanged output"))
        (should (equal changed-to "/new/"))
        (setq changed-to nil)
        (emacsvox-shell-dirtrack-procfs)
        (should-not changed-to)))))

(ert-deftest emacsvox-shell-remote-buffers-retain-stock-directory-tracking ()
  "A remote Shell buffer does not replace Shell's own directory tracker."
  (with-temp-buffer
    (cl-letf (((symbol-function 'file-remote-p)
               (lambda (&rest _) "/mock:")))
      (shell-mode))
    (should shell-dirtrack-mode)
    (should-not dirtrack-procfs-mode)
    (should-not
     (memq
      #'emacsvox-shell-dirtrack-procfs
      comint-preoutput-filter-functions))))

(ert-deftest emacsvox-shell-procfs-mode-refuses-an-ineligible-shell ()
  "Manually enabling procfs tracking cannot disable a safe fallback."
  (with-temp-buffer
    (shell-mode)
    (shell-dirtrack-mode 1)
    (cl-letf (((symbol-function
                'emacsvox-shell--procfs-dirtrack-available-p)
               (lambda () nil)))
      (dirtrack-procfs-mode 1))
    (should-not dirtrack-procfs-mode)
    (should shell-dirtrack-mode)))

(ert-deftest emacsvox-comint-completion-history-advice-is-directly-registered ()
  "Comint completion and history-display advice uses native advice directly."
  (dolist
      (entry
       '((comint-dynamic-list-completions
          :around
          emacsvox--advice-comint-dynamic-list-completions-around)
         (comint-dynamic-list-input-ring
          :around
          emacsvox--advice-comint-dynamic-list-input-ring-around)
         (comint-dynamic-list-filename-completions
          :after
          emacsvox--advice-comint-dynamic-list-filename-completions-after)))
    (pcase-let ((`(,target ,where ,function) entry))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-comint-completion-list-layers-on-stock-display ()
  "The accessible list preserves the stock UI without blocking for a key."
  (let ((calls 0)
        events)
    (unwind-protect
        (with-temp-buffer
          (cl-letf (((symbol-function 'display-completion-list)
                     (lambda (completions)
                       (push (list 'display completions) events)))
                    ((symbol-function 'emacsvox-comint--submit)
                     (lambda (text facts occasion &optional icon &rest _)
                       (push
                        (list 'submit text facts occasion icon)
                        events)
                       'completion-result)))
            (should
             (eq
              (emacsvox--advice-comint-dynamic-list-completions-around
               (lambda (completions common-substring)
                 (cl-incf calls)
                 (should (equal common-substring "a"))
                 (with-output-to-temp-buffer "*Completions*"
                   (display-completion-list
                    (sort completions #'string-lessp)))
                 'stock-result)
               (list "zeta" "alpha") "a")
              'stock-result))))
      (when-let* ((buffer (get-buffer "*Completions*")))
        (kill-buffer buffer)))
    (should (= calls 1))
    (should
     (equal
      (nreverse events)
      '((display ("alpha" "zeta"))
        (submit
         "alpha"
         (:role command-interaction
          :command-interaction-kind repl
          :events (focus-entered)
         :command-operation completion)
         navigation help))))))

(ert-deftest emacsvox-comint-input-ring-layers-on-stock-history-ui ()
  "Interactive history uses the stock completion buffer and speaks one entry."
  (let ((comint-input-ring (make-ring 3))
        (ems--interactive-fn-name 'comint-dynamic-list-input-ring)
        (origin (current-buffer))
        (calls 0)
        events)
    (ring-insert comint-input-ring "older")
    (ring-insert comint-input-ring "newer\ncontinued")
    (unwind-protect
        (cl-letf
            (((symbol-function 'emacsvox-comint--submit)
              (lambda (content facts occasion &optional icon &rest _)
                (push (list content facts occasion icon) events))))
          (should
           (eq
            (emacsvox--advice-comint-dynamic-list-input-ring-around
             (lambda ()
               (cl-incf calls)
               (with-output-to-temp-buffer " *Input History*"
                 (display-completion-list
                  (list "newer\ncontinued" "older")))
               ;; The Emacs 31 implementation changes the Lisp current buffer
               ;; while constructing its history UI.
               (set-buffer " *Input History*")
               ;; The advice supplies this event without waiting for input.
               (should
                (eq (read-event) 'emacsvox-comint-nonblocking))
               'stock-history))
            'stock-history)))
      (when-let* ((buffer (get-buffer " *Input History*")))
        (kill-buffer buffer)))
    (should (= calls 1))
    (should (eq (current-buffer) origin))
    (should
     (equal
      events
      '(("newer\ncontinued"
         (:role command-input
          :command-interaction-kind repl
          :events (focus-entered)
          :command-operation history-navigation
          :command-input-origin history)
         navigation help))))))

(ert-deftest emacsvox-comint-input-ring-selects-one-display-path ()
  "Input history replaces the stock UI only for interactive calls."
  (let ((comint-input-ring (make-ring 1))
        (calls 0)
        messages)
    (should
     (eq
      (emacsvox--advice-comint-dynamic-list-input-ring-around
       (lambda ()
         (cl-incf calls)
         'stock-history))
      'stock-history))
    (let ((ems--interactive-fn-name 'comint-dynamic-list-input-ring))
      (cl-letf (((symbol-function 'message)
                 (lambda (format-string &rest arguments)
                   (let ((text (apply #'format format-string arguments)))
                     (push text messages)
                     text))))
        (should
         (equal
          (emacsvox--advice-comint-dynamic-list-input-ring-around
           (lambda ()
             (cl-incf calls)
             'unexpected-stock-history))
          "No history"))))
    (should (= calls 1))
    (should (equal messages '("No history")))))

(ert-deftest emacsvox-comint-input-advice-is-directly-registered ()
  "Comint input advice uses native advice directly."
  (dolist
      (entry
       '((comint-magic-space
          :around emacsvox--advice-comint-magic-space-around)
         (comint-insert-previous-argument
          :around emacsvox--advice-comint-insert-previous-argument-around)
         (comint-delchar-or-maybe-eof
          :around emacsvox--advice-comint-delchar-or-maybe-eof-around)
         (comint-send-eof
          :before emacsvox--advice-comint-send-eof-before)
         (comint-accumulate
          :before emacsvox--advice-comint-accumulate-before)
         (comint-send-input
          :after emacsvox--advice-comint-send-input-after)
         (comint-kill-input
          :before emacsvox--advice-comint-kill-input-before)))
    (pcase-let ((`(,target ,where ,function) entry))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-comint-send-input-announces-one-semantic-lifecycle-event ()
  "Submitting input stops stale speech and cues one frozen command event."
  (with-temp-buffer
    (comint-mode)
    (let ((ems--interactive-fn-name 'comint-send-input)
          (emacsvox-comint--prompt-awaiting-padding t)
          boundaries
          events)
      (cl-letf
          (((symbol-function 'emacsvox-aural-call-with-submission)
            (lambda (function &rest arguments)
              (push
               (list
                (plist-get arguments :facts)
                (plist-get arguments :module)
                (plist-get arguments :occasion))
               boundaries)
              (apply function (plist-get arguments :arguments))))
           ((symbol-function 'tts-stop)
            (lambda (&rest arguments)
              (push (cons 'stop arguments) events)))
           ((symbol-function 'emacsvox-icon)
            (lambda (icon) (push (list 'icon icon) events))))
        (emacsvox--advice-comint-send-input-after))
      (should-not emacsvox-comint--prompt-awaiting-padding)
      (should
       (equal
        boundaries
        '(((:role command-input
            :command-interaction-kind repl
            :events (command-submitted)
            :command-operation submit
            :command-input-origin current)
           comint state-change))))
      (should
       (equal
        (nreverse events)
        '((stop all) (icon more)))))))

(ert-deftest emacsvox-comint-command-lifecycle-is-ordered-and-singular ()
  "One command produces one submit, output, and prompt presentation in order."
  (with-temp-buffer
    (shell-mode)
    (let ((ems--interactive-fn-name 'comint-send-input)
          (emacsvox-comint-autospeak t)
          (emacsvox-comint-output-monitor t)
          (comint-prompt-regexp "[$] ")
          events)
      (cl-letf
          (((symbol-function 'tts-stop)
            (lambda (&rest arguments)
              (push (cons 'stop arguments) events)))
           ((symbol-function 'emacsvox-aural-call-with-submission)
            (lambda (function &rest arguments)
              (push
               (list
                'boundary
                (plist-get arguments :facts)
                (plist-get arguments :module)
                (plist-get arguments :occasion))
               events)
              (apply function (plist-get arguments :arguments))))
           ((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (push
               (list
                'submission
                content
                (plist-get arguments :facts)
                (plist-get arguments :module)
                (plist-get arguments :occasion))
               events)))
           ((symbol-function 'emacsvox-icon)
            (lambda (icon)
              (push (list 'icon icon) events))))
        (emacsvox--advice-comint-send-input-after)
        (emacsvox-comint--present-process-output
         "result\n$ " "result\n$ "))
      (should
       (equal
        (nreverse events)
        '((stop all)
          (boundary
           (:role command-input
            :command-interaction-kind shell
            :events (command-submitted)
            :command-operation submit
            :command-input-origin current)
           shell state-change)
          (icon more)
          (submission
           "result\n"
           (:role command-output
            :command-interaction-kind shell
            :events (command-output-received))
           shell continuous)
          (boundary
           (:role command-prompt
            :command-interaction-kind shell
            :events (command-prompt-ready))
           shell notification)
          (icon item)))))))

(ert-deftest emacsvox-comint-magic-space-calls-original-once ()
  "Interactive magic space preserves one original call and its result."
  (with-temp-buffer
    (insert "word")
    (let ((ems--interactive-fn-name 'comint-magic-space)
          (calls 0)
          events)
      (cl-letf (((symbol-function 'emacsvox-speak-word)
                 (lambda () (push 'word events))))
        (should
         (eq
          (emacsvox--advice-comint-magic-space-around
           (lambda (argument)
             (cl-incf calls)
             (insert (make-string argument ?\s))
             'magic-result)
           1)
          'magic-result)))
      (should (= calls 1))
      (should (equal events '(word))))))

(ert-deftest emacsvox-comint-magic-space-programmatic-call-runs-once ()
  "Programmatic magic space remains quiet and calls the original once."
  (with-temp-buffer
    (let ((ems--interactive-fn-name nil)
          (calls 0)
          events)
      (cl-letf (((symbol-function 'emacsvox-speak-word)
                 (lambda () (push 'word events)))
                ((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push icon events))))
        (should
         (eq
          (emacsvox--advice-comint-magic-space-around
           (lambda (_argument)
             (cl-incf calls)
             'programmatic-result)
           1)
          'programmatic-result)))
      (should (= calls 1))
      (should-not events))))

(ert-deftest emacsvox-comint-previous-argument-calls-original-once ()
  "Previous-argument insertion speaks one insertion from one call."
  (with-temp-buffer
    (insert "prompt ")
    (let ((ems--interactive-fn-name 'comint-insert-previous-argument)
          (origin (point))
          (calls 0)
          events)
      (cl-letf (((symbol-function 'emacsvox-speak-region)
                 (lambda (start end)
                   (push (list 'region start end) events)))
                ((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events))))
        (should
         (eq
          (emacsvox--advice-comint-insert-previous-argument-around
           (lambda (index)
             (cl-incf calls)
             (should (= index 2))
             (insert "prior")
             'argument-result)
           2)
          'argument-result)))
      (should (= calls 1))
      (should
       (equal
        (nreverse events)
        `((region ,origin ,(point)) (icon yank-object)))))))

(ert-deftest emacsvox-comint-kill-input-is-safe-without-a-live-process ()
  "A dead Shell buffer does not fail while preparing kill-input feedback."
  (with-temp-buffer
    (comint-mode)
    (let ((ems--interactive-fn-name 'comint-kill-input)
          presented)
      (cl-letf (((symbol-function 'get-buffer-process)
                 (lambda (&rest _) nil))
                ((symbol-function 'emacsvox-comint--present-feedback)
                 (lambda (&rest _) (setq presented t))))
        (should-not (emacsvox--advice-comint-kill-input-before)))
      (should-not presented))))

(ert-deftest emacsvox-comint-output-policy-is-independent-of-voice-controls ()
  "Voice Lock and face policy do not suppress native Shell output events."
  (dolist
      (settings
       '((nil nil nil)
         (nil t t)
         (t nil t)
         (t t nil)))
    (pcase-let ((`(,voice-lock ,face-presentation ,icons) settings))
      (with-temp-buffer
        (let ((voice-lock-mode voice-lock)
              (emacsvox-aural-face-presentation-enabled face-presentation)
              (emacsvox-use-icons icons)
              (emacsvox-comint-output-monitor t)
              (emacsvox-comint-autospeak t)
              (comint-prompt-regexp "[$] ")
              output-events prompt-events)
          (cl-letf
              (((symbol-function 'emacsvox-comint--submit)
                (lambda (content &rest _)
                  (push content output-events)))
               ((symbol-function 'emacsvox-comint--present-feedback)
                (lambda (facts _occasion icon function &rest arguments)
                  (push (list facts icon) prompt-events)
                  (apply function arguments))))
            (emacsvox-comint--present-process-output
             "result\n$ " "result\n$ "))
          (should (equal output-events '("result\n")))
          (should (= (length prompt-events) 1)))))))

(ert-deftest emacsvox-toggle-comint-output-monitor-preserves-local-and-global-use ()
  "The semantic replacement for the generated switcher keeps its API."
  (let ((original-default
         (default-value 'emacsvox-comint-output-monitor)))
    (unwind-protect
        (with-temp-buffer
          (setq-local emacsvox-comint-output-monitor nil)
          (emacsvox-toggle-comint-output-monitor)
          (should emacsvox-comint-output-monitor)
          (emacsvox-toggle-comint-output-monitor)
          (should-not emacsvox-comint-output-monitor)
          (let ((expected (not original-default)))
            (emacsvox-toggle-comint-output-monitor t)
            (should
             (eq
              (default-value 'emacsvox-comint-output-monitor)
              expected))
            (should (eq emacsvox-comint-output-monitor expected))))
      (setq-default emacsvox-comint-output-monitor original-default))))

(ert-deftest emacsvox-comint-delete-or-eof-calls-original-once-after-feedback ()
  "Delete-or-EOF gives feedback before one original call."
  (with-temp-buffer
    (insert "xy")
    (goto-char (point-min))
    (let ((ems--interactive-fn-name 'comint-delchar-or-maybe-eof)
          (calls 0)
          events)
      (cl-letf (((symbol-function 'emacsvox-speak-edit-operation)
                 (lambda (operation)
                   (push (list 'edit operation) events)))
                ((symbol-function 'emacsvox-speak-char)
                 (lambda (&rest _) (push 'character events))))
        (should
         (eq
          (emacsvox--advice-comint-delchar-or-maybe-eof-around
           (lambda (argument)
             (cl-incf calls)
             (push 'original events)
             (delete-char argument)
             'delete-result)
           1)
          'delete-result)))
      (should (= calls 1))
      (should
       (equal
        (nreverse events)
        '((edit deletion) character original)))
      (should (equal (buffer-string) "y")))))

(ert-deftest emacsvox-comint-delete-or-eof-keeps-eof-free-of-edit-feedback ()
  "The EOF branch reports EOF and does not present a deletion."
  (with-temp-buffer
    (insert "xy")
    (goto-char (point-max))
    (let ((process-marker (copy-marker (point-max)))
          (ems--interactive-fn-name 'comint-delchar-or-maybe-eof)
          (calls 0)
          events)
      (cl-letf
          (((symbol-function 'get-buffer-process)
            (lambda (&rest _) 'test-process))
           ((symbol-function 'process-mark)
            (lambda (process)
              (should (eq process 'test-process))
              process-marker))
           ((symbol-function 'message)
            (lambda (format-string &rest arguments)
              (push
               (list 'message
                     (apply #'format format-string arguments))
               events)))
           ((symbol-function 'emacsvox-speak-edit-operation)
            (lambda (operation)
              (push (list 'edit operation) events)))
           ((symbol-function 'emacsvox-speak-char)
            (lambda (&rest _) (push 'character events))))
        (should
         (eq
          (emacsvox--advice-comint-delchar-or-maybe-eof-around
           (lambda (argument)
             (cl-incf calls)
             (push (list 'original argument) events)
             'eof-result)
           nil)
          'eof-result)))
      (should (= calls 1))
      (should
       (equal
        (nreverse events)
        '((message "Sending EOF to comint process")
          (original nil)))))))

(ert-deftest emacsvox-comint-delete-at-eob-with-input-is-not-misreported-as-eof ()
  "End of buffer is deletion when unsent input follows the process mark."
  (with-temp-buffer
    (insert "xy")
    (goto-char (point-max))
    (let ((process-marker (copy-marker (point-min)))
          (ems--interactive-fn-name 'comint-delchar-or-maybe-eof)
          events)
      (cl-letf
          (((symbol-function 'get-buffer-process)
            (lambda (&rest _) 'test-process))
           ((symbol-function 'process-mark)
            (lambda (_process) process-marker))
           ((symbol-function 'emacsvox-speak-edit-operation)
            (lambda (operation) (push (list 'edit operation) events)))
           ((symbol-function 'emacsvox-speak-char)
            (lambda (&rest _) (push 'character events)))
           ((symbol-function 'message)
            (lambda (&rest _) (push 'message events))))
        (emacsvox--advice-comint-delchar-or-maybe-eof-around
         (lambda (&rest _) 'delete-result)
         nil))
      (should (equal (nreverse events) '((edit deletion) character))))))

(ert-deftest emacsvox-comint-setup-leaves-undo-policy-to-comint ()
  "Speech setup does not override a derived mode's undo policy."
  (with-temp-buffer
    (comint-mode)
    (setq buffer-undo-list nil)
    (emacsvox-comint-speech-setup)
    (should-not buffer-undo-list)
    (should
     (eq
      (lookup-key comint-mode-map (kbd "C-o"))
      #'switch-to-completions))))

(ert-deftest emacsvox-comint-header-line-separates-spoken-fields ()
  "The Shell header does not concatenate time, buffer, directory, and state."
  (with-temp-buffer
    (comint-mode)
    (rename-buffer "shell-header-test" t)
    (let ((emacsvox-use-header-line t)
          (emacsvox-comint-autospeak t)
          (default-directory "/tmp/"))
      (cl-letf (((symbol-function 'format-time-string)
                 (lambda (&rest _) "12 34"))
                ((symbol-function 'window-list)
                 (lambda (&rest _) '(window-one))))
        (emacsvox-comint-speech-setup)
        (let ((rendered (eval (cadr (car header-line-format)))))
          (should
           (equal
            (substring-no-properties rendered)
            "12 34 shell-header-test /tmp/ Autospeak")))))))

(provide 'emacsvox-comint-tests)
;;; emacsvox-comint-tests.el ends here
