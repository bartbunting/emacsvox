;;; emacsvox-sh-script-tests.el --- Sh Script advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Sh Script advice.

;;; Code:

(require 'ert)
(require 'sh-script)
(require 'shell)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-sh-script.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--sh-script-advice
  '((sh-mode :after emacsvox--advice-sh-mode-after)
    (sh--maybe-here-document
     :around emacsvox--advice-sh--maybe-here-document-around)
    (sh-beginning-of-command
     :after emacsvox--advice-sh-beginning-of-command-after)
    (sh-end-of-command
     :after emacsvox--advice-sh-end-of-command-after))
  "Current Emacs 31 Sh Script targets and their direct native advice.")

(ert-deftest emacsvox-sh-script-advice-is-directly-registered ()
  "Sh Script advice is attached directly to current Emacs 31 targets."
  (dolist (entry emacsvox-test--sh-script-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))))
  (dolist (removed
           '(sh-indent-line sh-maybe-here-document sh-newline-and-indent))
    (should-not (fboundp removed))))

(ert-deftest emacsvox-sh-script-mode-setup-retains-feedback ()
  "Entering Sh mode configures speech and announces the mode."
  (save-window-excursion
    (set-window-buffer (selected-window) (current-buffer))
    (let ((emacsvox-audio-indentation nil)
          events)
      (cl-letf (((symbol-function 'tts-apply-punctuation-mode-policy)
                 (lambda () (push 'punctuation-policy events)))
                ((symbol-function 'emacsvox-toggle-audio-indentation)
                 (lambda ()
                   (setq emacsvox-audio-indentation t)
                   (push 'indentation events)))
                ((symbol-function 'emacsvox-speak-mode-line)
                 (lambda () (push 'mode-line events))))
        (emacsvox--advice-sh-mode-after))
      (should emacsvox-audio-indentation)
      (should
       (equal
        (nreverse events)
        '(punctuation-policy indentation mode-line))))))

(ert-deftest emacsvox-sh-script-navigation-is-target-aware ()
  "Only the matching Sh command-navigation advice produces feedback."
  (let ((ems--interactive-fn-name 'sh-end-of-command)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events))))
      (emacsvox--advice-sh-beginning-of-command-after)
      (emacsvox--advice-sh-end-of-command-after))
    (should
     (equal
      (nreverse events)
      '((icon large-movement) line)))))

(ert-deftest emacsvox-sh-script-comint-fontification-is-quiet ()
  "Preparing a hidden Shell fontification buffer must not announce its parent."
  (save-window-excursion
    (with-temp-buffer
      (shell-mode)
      ;; Exercise Comint's real indirect buffer without needing a shell process
      ;; solely for Shell's choice of syntax-highlighting major mode.
      (setq-local comint-indirect-setup-function #'sh-mode)
      (set-window-buffer (selected-window) (current-buffer))
      (let (announcements)
        (cl-letf (((symbol-function 'tts-apply-punctuation-mode-policy) #'ignore)
                  ((symbol-function 'tts--protocol-sync) #'ignore)
                  ((symbol-function 'emacsvox-speak-mode-line)
                   (lambda () (push (buffer-name) announcements))))
          (let ((indirect (comint-indirect-buffer)))
            (should (buffer-live-p indirect))
            (with-current-buffer indirect
              (should (derived-mode-p 'sh-mode))
              (should emacsvox-audio-indentation))))
        (should-not announcements)))))

(ert-deftest emacsvox-sh-script-graphical-shell-startup-speaks-once ()
  "Starting and redisplaying a real shell announces its header only once."
  (skip-unless (display-graphic-p))
  (require 'emacsvox-advice)
  (require 'emacsvox-comint)
  (let ((buffer (generate-new-buffer "*shell-announcement-test*"))
        (explicit-shell-file-name "/bin/sh")
        (explicit-sh-args '("-i"))
        (emacsvox-comint-autospeak nil)
        (emacsvox-use-icons nil)
        announcements)
    (unwind-protect
        (save-window-excursion
          (cl-letf (((symbol-function 'tts-stop) #'ignore)
                    ((symbol-function 'tts--protocol-sync) #'ignore)
                    ((symbol-function 'tts-speak) #'ignore)
                    ((symbol-function 'emacsvox-icon) #'ignore)
                    ((symbol-function 'emacsvox-speak-mode-line)
                     (lambda () (push (current-buffer) announcements))))
            (funcall-interactively #'shell buffer)
            (accept-process-output (get-buffer-process buffer) 1)
            (font-lock-ensure)
            (redisplay t)
            (should (buffer-live-p comint--indirect-buffer))
            (should (equal announcements (list buffer)))))
      (when-let* ((process (get-buffer-process buffer)))
        (set-process-query-on-exit-flag process nil)
        (delete-process process))
      (when (buffer-live-p buffer) (kill-buffer buffer)))))

(ert-deftest emacsvox-sh-script-here-document-calls-original-once ()
  "Interactive here-document expansion is run once and announced."
  (with-temp-buffer
    (let ((ems--interactive-fn-name 'self-insert-command)
          (calls 0)
          events)
      (cl-letf (((symbol-function 'message)
                 (lambda (format-string &rest arguments)
                   (push (apply #'format format-string arguments) events))))
        (should
         (eq
          'result
          (emacsvox--advice-sh--maybe-here-document-around
           (lambda ()
             (setq calls (1+ calls))
             (insert "EOF\n\nEOF")
             'result)))))
      (should (= calls 1))
      (should (equal events '("Started a shell here document."))))))

(ert-deftest emacsvox-sh-script-current-here-document-is-announced ()
  "The current Emacs 31 here-document helper remains speech-enabled."
  (with-temp-buffer
    (insert "x << ")
    (let ((sh-here-document-word "EOF")
          (ems--interactive-fn-name 'self-insert-command)
          events)
      (cl-letf (((symbol-function 'message)
                 (lambda (format-string &rest arguments)
                   (push (apply #'format format-string arguments) events))))
        (emacsvox--advice-sh--maybe-here-document-around
         (symbol-function 'sh--maybe-here-document)))
      (should (equal (buffer-string) "x <<EOF\n\nEOF"))
      (should (equal events '("Started a shell here document."))))))

(ert-deftest emacsvox-sh-script-ordinary-insertion-is-not-duplicated ()
  "An unexpanded interactive insertion stays quiet and runs once."
  (with-temp-buffer
    (let ((ems--interactive-fn-name 'self-insert-command)
          (calls 0)
          events)
      (cl-letf (((symbol-function 'message)
                 (lambda (&rest arguments) (push arguments events))))
        (should
         (eq
          'result
          (emacsvox--advice-sh--maybe-here-document-around
           (lambda ()
             (setq calls (1+ calls))
             'result)))))
      (should (= calls 1))
      (should-not events))))

(ert-deftest emacsvox-sh-script-programmatic-here-document-is-quiet ()
  "Programmatic here-document expansion runs once without feedback."
  (with-temp-buffer
    (let ((calls 0)
          events)
      (cl-letf (((symbol-function 'message)
                 (lambda (&rest arguments) (push arguments events))))
        (should
         (eq
          'result
          (emacsvox--advice-sh--maybe-here-document-around
           (lambda ()
             (setq calls (1+ calls))
             (insert "EOF\n\nEOF")
             'result)))))
      (should (= calls 1))
      (should-not events))))

(provide 'emacsvox-sh-script-tests)
;;; emacsvox-sh-script-tests.el ends here
