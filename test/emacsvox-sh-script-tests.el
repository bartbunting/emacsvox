;;; emacsvox-sh-script-tests.el --- Sh Script advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Sh Script advice.

;;; Code:

(require 'ert)
(require 'sh-script)

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
  (let ((emacsvox-audio-indentation nil)
        events)
    (cl-letf (((symbol-function 'tts-set-punctuations)
               (lambda (value) (push (list 'punctuation value) events)))
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
      '((punctuation all) indentation mode-line)))))

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
