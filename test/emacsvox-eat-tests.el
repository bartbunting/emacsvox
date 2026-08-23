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
    #'emacsvox--advice-eat-self-input-before 'eat-self-input)))

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

(provide 'emacsvox-eat-tests)
;;; emacsvox-eat-tests.el ends here
