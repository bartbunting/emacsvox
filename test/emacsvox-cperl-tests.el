;;; emacsvox-cperl-tests.el --- CPerl advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated CPerl advice.

;;; Code:

(require 'ert)
(require 'cperl-mode)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-cperl.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--cperl-after-targets
  '(cperl-indent-exp
    cperl-info-on-current-command
    cperl-info-on-command
    cperl-invert-if-unless
    cperl-comment-region
    cperl-uncomment-region
    cperl-indent-command
    cperl-indent-region
    cperl-fill-paragraph
    cperl-switch-to-doc-buffer
    cperl-find-bad-style)
  "Current Emacs 31 CPerl targets using direct after advice.")

(ert-deftest emacsvox-cperl-advice-is-directly-registered ()
  "CPerl advice is attached directly to current Emacs 31 targets."
  (dolist (target emacsvox-test--cperl-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))))
  (dolist
      (target '(cperl-electric-backspace cperl-linefeed))
    (let ((function
           (intern (format "emacsvox--advice-%s-around" target))))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-cperl-backspace-calls-original-once ()
  "CPerl backspace speaks before one original call and preserves result."
  (with-temp-buffer
    (insert "x")
    (let ((ems--interactive-fn-name 'cperl-electric-backspace)
          (calls 0)
          events)
      (cl-letf (((symbol-function 'dtk-tone)
                 (lambda (&rest _) (push 'tone events)))
                ((symbol-function 'emacsvox-speak-this-char)
                 (lambda (character)
                   (push (list 'character character) events))))
        (should
         (eq
          'result
          (emacsvox--advice-cperl-electric-backspace-around
           (lambda (&rest arguments)
             (setq calls (1+ calls))
             (should (equal arguments '(1)))
             (push 'original events)
             (delete-char -1)
             'result)
           1))))
      (should (= calls 1))
      (should (equal (buffer-string) ""))
      (should
       (equal
        (nreverse events)
        '(tone (character 120) original))))))

(ert-deftest emacsvox-cperl-linefeed-calls-original-once ()
  "CPerl linefeed cues indentation before one original call."
  (with-temp-buffer
    (insert "  code")
    (let ((ems--interactive-fn-name 'cperl-linefeed)
          (emacsvox-line-echo nil)
          (voice-annotate 'annotation)
          (calls 0)
          events)
      (cl-letf (((symbol-function 'dtk-speak-using-voice)
                 (lambda (voice text)
                   (push (list 'speech voice text) events)))
                ((symbol-function 'tts--protocol-dispatch)
                 (lambda () (push 'speak events))))
        (should
         (eq
          'result
          (emacsvox--advice-cperl-linefeed-around
           (lambda ()
             (setq calls (1+ calls))
             (push 'original events)
             (insert "\n")
             'result)))))
      (should (= calls 1))
      (should
       (equal
        (nreverse events)
        '((speech annotation "indent 6") speak original))))))

(ert-deftest emacsvox-cperl-comment-feedback-uses-native-region ()
  "CPerl comment feedback uses Emacs's explicit bounds and prefix."
  (with-temp-buffer
    (insert "one\ntwo\nthree\n")
    (let ((ems--interactive-fn-name 'cperl-comment-region)
          events)
      (cl-letf (((symbol-function 'message)
                 (lambda (format-string &rest arguments)
                   (push (apply #'format format-string arguments) events))))
        (emacsvox--advice-cperl-uncomment-region-after
         (point-min) (point-max) -1)
        (emacsvox--advice-cperl-comment-region-after
         (point-min) (point-max) -1))
      (should
       (equal
        events
        '("Uncommented region containing 3 lines"))))))

(ert-deftest emacsvox-cperl-feedback-is-target-aware ()
  "Only the matching CPerl command produces feedback."
  (let ((ems--interactive-fn-name 'cperl-find-bad-style)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'mode-line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-cperl-switch-to-doc-buffer-after)
      (emacsvox--advice-cperl-find-bad-style-after))
    (should
     (equal
      (nreverse events)
      '(mode-line (icon task-done))))))

(provide 'emacsvox-cperl-tests)
;;; emacsvox-cperl-tests.el ends here
