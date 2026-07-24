;;; emacsvox-ruby-tests.el --- Ruby advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Ruby advice.

;;; Code:

(require 'ert)
(require 'ruby-mode)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-ruby.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--ruby-after-targets
  '(ruby-beginning-of-defun
    ruby-end-of-defun
    ruby-beginning-of-block
    ruby-end-of-block
    ruby-forward-sexp
    ruby-backward-sexp
    ruby-indent-line
    ruby-indent-exp)
  "Current Emacs 31 Ruby targets using direct after advice.")

(ert-deftest emacsvox-ruby-advice-is-directly-registered ()
  "Ruby advice is attached directly to callable Emacs 31 targets."
  (dolist (target emacsvox-test--ruby-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (commandp target))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-ruby-does-not-recreate-removed-commands ()
  "Loading the integration does not create obsolete Ruby commands."
  (dolist
      (target
       '(ruby-mark-defun
         ruby-insert-end
         ruby-reindent-then-newline-and-indent
         ruby-electric-brace))
    (should-not (fboundp target))))

(ert-deftest emacsvox-ruby-defers-external-inferior-ruby-advice ()
  "Absent inf-ruby commands are not created as advice placeholders."
  (dolist
      (target
       '(ruby-run
         switch-to-ruby
         ruby-send-region-and-go
         ruby-send-block-and-go
         ruby-send-definition-and-go))
    (should-not (fboundp target))
    (should
     (fboundp
      (intern (format "emacsvox--advice-%s-after" target))))))

(ert-deftest emacsvox-ruby-navigation-feedback-is-target-aware ()
  "Only the matching Ruby movement command produces feedback."
  (let ((ems--interactive-fn-name 'ruby-end-of-block)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-ruby-beginning-of-block-after)
      (emacsvox--advice-ruby-end-of-block-after))
    (should
     (equal
      (nreverse events)
      '(line (icon paragraph))))))

(ert-deftest emacsvox-ruby-indent-feedback-is-target-aware ()
  "Ruby expression indentation retains its distinct auditory icon."
  (let ((ems--interactive-fn-name 'ruby-indent-exp)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-ruby-indent-line-after)
      (emacsvox--advice-ruby-indent-exp-after))
    (should
     (equal
      (nreverse events)
      '(line (icon fill-object))))))

(ert-deftest emacsvox-ruby-programmatic-advice-is-quiet ()
  "Ruby advice emits no feedback outside interactive dispatch."
  (let (events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-ruby-beginning-of-defun-after)
      (emacsvox--advice-ruby-indent-exp-after))
    (should-not events)))

(provide 'emacsvox-ruby-tests)
;;; emacsvox-ruby-tests.el ends here
