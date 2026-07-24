;;; emacsvox-python-tests.el --- Python advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Python advice.

;;; Code:

(require 'ert)
(require 'python)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-python.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--python-after-targets
  '(python-check
    python-shell-send-region
    python-shell-send-defun
    python-shell-send-file
    python-shell-send-buffer
    python-shell-send-string
    python-indent-dedent-line
    python-fill-paragraph
    python-indent-shift-left
    python-indent-shift-right
    python-indent-region
    python-mark-defun
    python-nav-up-list
    python-nav-if-name-main
    python-nav-forward-statement
    python-nav-forward-sexp-safe
    python-nav-forward-sexp
    python-nav-forward-defun
    python-nav-forward-block
    python-nav-end-of-statement
    python-nav-end-of-defun
    python-nav-end-of-block
    python-nav-beginning-of-statement
    python-nav-beginning-of-block
    python-nav-backward-up-list
    python-nav-backward-statement
    python-nav-backward-sexp-safe
    python-nav-backward-sexp
    python-nav-backward-defun
    python-nav-backward-block)
  "Current Emacs 31 Python targets using direct after advice.")

(ert-deftest emacsvox-python-advice-is-directly-registered ()
  "Python advice is attached directly to current Emacs 31 targets."
  (dolist (target emacsvox-test--python-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))))
  (should
   (advice-member-p
    #'emacsvox--advice-python-indent-dedent-line-backspace-around
    'python-indent-dedent-line-backspace))
  (should-not (commandp 'python-shell-send-string-no-output)))

(ert-deftest emacsvox-python-backspace-calls-original-once ()
  "Python backspace speaks before exactly one original deletion."
  (with-temp-buffer
    (insert "x")
    (let ((ems--interactive-fn-name
           'python-indent-dedent-line-backspace)
          (calls 0)
          events)
      (cl-letf (((symbol-function 'tts-tone)
                 (lambda (&rest _) (push 'tone events)))
                ((symbol-function 'emacsvox-speak-this-char)
                 (lambda (character)
                   (push (list 'character character) events))))
        (should
         (eq
          'result
          (emacsvox--advice-python-indent-dedent-line-backspace-around
           (lambda (arg)
             (setq calls (1+ calls))
             (should (= arg 1))
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

(ert-deftest emacsvox-python-whitespace-backspace-reports-indent ()
  "Whitespace backspace reports indentation after one original call."
  (with-temp-buffer
    (insert "    ")
    (let ((ems--interactive-fn-name
           'python-indent-dedent-line-backspace)
          (calls 0)
          events)
      (cl-letf (((symbol-function 'tts-tone)
                 (lambda (&rest _) (push 'tone events)))
                ((symbol-function 'tts-notify)
                 (lambda (text) (push (list 'notify text) events))))
        (should
         (eq
          'result
          (emacsvox--advice-python-indent-dedent-line-backspace-around
           (lambda (_arg)
             (setq calls (1+ calls))
             (push 'original events)
             (delete-char -1)
             'result)
           1))))
      (should (= calls 1))
      (should
       (equal
        (nreverse events)
        '(tone original (notify "Indent 3 ")))))))

(ert-deftest emacsvox-python-shell-feedback-cues-only-outer-command ()
  "Nested send operations produce one cue for the interactive command."
  (let ((ems--interactive-fn-name 'python-shell-send-buffer)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-python-shell-send-string-after "code")
      (emacsvox--advice-python-shell-send-region-after 1 2)
      (emacsvox--advice-python-shell-send-buffer-after))
    (should (equal events '((icon task-done))))))

(ert-deftest emacsvox-python-indentation-uses-native-bounds ()
  "Python indentation feedback counts explicit START and END bounds."
  (with-temp-buffer
    (insert "one\ntwo\nthree\n")
    (let ((ems--interactive-fn-name 'indent-region)
          events)
      (cl-letf (((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events)))
                ((symbol-function 'tts-speak)
                 (lambda (text) (push (list 'speech text) events))))
        (emacsvox--advice-python-indent-region-after
         (point-min) (point-max)))
      (should
       (equal
        (nreverse events)
        '((icon right)
          (speech "Indented region   containing 3 lines")))))))

(ert-deftest emacsvox-python-navigation-feedback-is-target-aware ()
  "Only the matching Python navigation command produces feedback."
  (let ((ems--interactive-fn-name 'python-nav-backward-block)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-python-nav-forward-block-after)
      (emacsvox--advice-python-nav-backward-block-after))
    (should
     (equal
      (nreverse events)
      '(line (icon paragraph))))))

(provide 'emacsvox-python-tests)
;;; emacsvox-python-tests.el ends here
