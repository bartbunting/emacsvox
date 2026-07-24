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

(ert-deftest emacsvox-comint-output-filter-calls-original-once ()
  "Each Comint process chunk is inserted once before autospeech."
  (with-temp-buffer
    (insert "ordinary output\n")
    (let ((output-buffer (current-buffer))
          (emacsvox-comint-output-monitor t)
          (emacsvox-comint-autospeak t)
          (comint-last-output-start (point-min))
          (shell-prompt-pattern "\\`never-a-prompt\\'")
          (comint-prompt-regexp "\\`never-a-prompt\\'")
          (calls 0)
          events)
      (cl-letf (((symbol-function 'process-buffer)
                 (lambda (process)
                   (should (eq process 'test-process))
                   output-buffer))
                ((symbol-function 'dtk-speak)
                 (lambda (text) (push (list 'speak text) events))))
        (should
         (eq
          (emacsvox--advice-comint-output-filter-around
           (lambda (process output)
             (cl-incf calls)
             (push (list 'original process output) events)
             'filter-result)
           'test-process
           "chunk")
          'filter-result)))
      (should (= calls 1))
      (should
       (equal
        (nreverse events)
        '((original test-process "chunk") (speak "chunk")))))))

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
                    ((symbol-function 'dtk-speak)
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
      (cl-letf (((symbol-function 'dtk-tone-deletion)
                 (lambda () (push 'tone events)))
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
      (should (equal (nreverse events) '(tone character original)))
      (should (equal (buffer-string) "y")))))

(provide 'emacsvox-comint-tests)
;;; emacsvox-comint-tests.el ends here
