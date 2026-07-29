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
         (command-process-signalled event)))
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
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda (&rest _) (push 'line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-shell-backward-command-after)
      (emacsvox--advice-shell-forward-command-after))
    (should
     (equal
      (nreverse events)
      '(line (icon item))))))

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

(ert-deftest emacsvox-comint-completion-list-replaces-stock-display ()
  "The accessible completion list sorts entries without calling the original."
  (let ((calls 0)
        events)
    (unwind-protect
        (with-temp-buffer
          (insert "spoken completion")
          (cl-letf (((symbol-function 'display-completion-list)
                     (lambda (completions)
                       (push (list 'display completions) events)))
                    ((symbol-function 'next-completion)
                     (lambda (count)
                       (push (list 'next count) events)))
                    ((symbol-function 'tts-speak)
                     (lambda (text)
                       (push (list 'speak text) events)
                       'completion-result)))
            (should
             (eq
              (emacsvox--advice-comint-dynamic-list-completions-around
               (lambda (&rest _)
                 (cl-incf calls)
                 'stock-result)
               (list "zeta" "alpha"))
              'completion-result))))
      (when-let* ((buffer (get-buffer "*Completions*")))
        (kill-buffer buffer)))
    (should (= calls 0))
    (should
     (equal
      (nreverse events)
      '((display ("alpha" "zeta"))
        (next 1)
        (speak ""))))))

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
    (let ((ems--interactive-fn-name 'comint-delchar-or-maybe-eof)
          (calls 0)
          events)
      (cl-letf
          (((symbol-function 'message)
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

(provide 'emacsvox-comint-tests)
;;; emacsvox-comint-tests.el ends here
