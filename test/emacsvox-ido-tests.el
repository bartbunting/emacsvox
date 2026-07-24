;;; emacsvox-ido-tests.el --- IDO advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated IDO advice.

;;; Code:

(require 'cl-lib)
(require 'ert)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-ido.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--ido-after-targets
  '(ido-exhibit
    ido-mode
    ido-everywhere
    ido-toggle-case
    ido-toggle-regexp
    ido-toggle-prefix
    ido-toggle-ignore
    ido-complete
    ido-switch-buffer ido-switch-buffer-other-window
    ido-switch-buffer-other-frame ido-display-buffer
    ido-find-file ido-find-file-other-frame ido-find-file-other-window
    ido-find-alternate-file ido-find-file-read-only
    ido-find-file-read-only-other-window ido-find-file-read-only-other-frame
    ido-bury-buffer-at-head
    ido-kill-buffer
    ido-kill-buffer-at-head)
  "IDO commands using direct native after advice.")

(defconst emacsvox-test--ido-before-targets
  '(ido-set-current-directory ido-fallback-command)
  "IDO commands using direct native before advice.")

(ert-deftest emacsvox-ido-advice-is-directly-registered ()
  "Migrated IDO advice uses native advice directly."
  (dolist (target emacsvox-test--ido-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp function))
      (should (advice-member-p function target))))
  (dolist (target emacsvox-test--ido-before-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-before" target))))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-ido-feedback-is-target-aware ()
  "Only the matching interactive IDO command produces feedback."
  (let ((ems--interactive-fn-name 'ido-find-file-other-window)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'speak-mode-line events))))
      (emacsvox--advice-ido-find-file-after)
      (emacsvox--advice-ido-find-file-other-window-after))
    (should
     (equal
      (nreverse events)
      '((icon open-object) speak-mode-line)))))

(ert-deftest emacsvox-ido-directory-cache-is-unconditional ()
  "Directory setup caches the old directory and produces its cue."
  (let ((ido-current-directory "/old/")
        (emacsvox-ido-cache nil)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events))))
      (emacsvox--advice-ido-set-current-directory-before "/new/"))
    (should (equal emacsvox-ido-cache "/old/"))
    (should (equal events '(item)))))

(ert-deftest emacsvox-ido-exhibit-reports-current-choices ()
  "IDO exhibit feedback reports matches and a changed directory."
  (let ((ido-matches '("one" "two" "three"))
        (ido-max-prospects 2)
        (ido-current-directory "/tmp/work/")
        (emacsvox-ido-cache "/tmp/old/")
        events)
    (cl-letf (((symbol-function 'minibuffer-contents)
               (lambda () "tw"))
              ((symbol-function 'abbreviate-file-name)
               (lambda (directory) directory))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'tts-notify)
               (lambda (text) (push (list 'notify text) events))))
      (emacsvox--advice-ido-exhibit-after))
    (should
     (equal
      (nreverse events)
      '((icon ellipses)
        (notify "tw 3 choices: In /tmp/work/"))))))

(ert-deftest emacsvox-ido-toggle-feedback-is-target-aware ()
  "Only the matching IDO toggle produces feedback."
  (let ((ems--interactive-fn-name 'ido-toggle-regexp)
        (ido-enable-prefix nil)
        (ido-enable-regexp t)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'tts-speak)
               (lambda (text) (push (list 'speech text) events))))
      (emacsvox--advice-ido-toggle-prefix-after)
      (emacsvox--advice-ido-toggle-regexp-after))
    (should
     (equal
      (nreverse events)
      '((icon on) (speech "Regexp on"))))))

(ert-deftest emacsvox-ido-fallback-feedback-is-target-aware ()
  "An interactive IDO fallback produces close and open cues in order."
  (let ((ems--interactive-fn-name 'ido-fallback-command)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events))))
      (emacsvox--advice-ido-fallback-command-before))
    (should (equal (nreverse events) '(close-object open-object)))))

(provide 'emacsvox-ido-tests)
;;; emacsvox-ido-tests.el ends here
