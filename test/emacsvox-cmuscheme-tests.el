;;; emacsvox-cmuscheme-tests.el --- CMU Scheme advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated CMU Scheme advice.

;;; Code:

(require 'ert)
(require 'cmuscheme)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-cmuscheme.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--cmuscheme-after-targets
  '(inferior-scheme-mode
    run-scheme
    scheme-send-region
    scheme-send-definition
    scheme-send-last-sexp
    scheme-compile-region
    scheme-compile-definition
    switch-to-scheme
    scheme-send-region-and-go
    scheme-send-definition-and-go
    scheme-load-file
    scheme-compile-file)
  "Current Emacs 31 CMU Scheme targets using direct after advice.")

(ert-deftest emacsvox-cmuscheme-advice-is-directly-registered ()
  "CMU Scheme advice is attached directly to current Emacs 31 targets."
  (dolist (target emacsvox-test--cmuscheme-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-cmuscheme-launch-uses-native-command ()
  "Scheme launch feedback reports the command passed by Emacs."
  (let ((ems--interactive-fn-name 'run-scheme)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push (apply #'format format-string arguments) events))))
      (emacsvox--advice-run-scheme-after "guile --no-auto-compile"))
    (should
     (equal
      (nreverse events)
      '((icon task-done) "Launched scheme guile --no-auto-compile")))))

(ert-deftest emacsvox-cmuscheme-region-feedback-uses-native-bounds ()
  "Scheme region feedback uses explicit start and end positions."
  (with-temp-buffer
    (insert "(one)\n(two)\n(three)\n")
    (let ((ems--interactive-fn-name 'scheme-compile-region)
          events)
      (cl-letf (((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events)))
                ((symbol-function 'message)
                 (lambda (format-string &rest arguments)
                   (push (apply #'format format-string arguments) events))))
        (emacsvox--advice-scheme-send-region-after
         (point-min) (point-max))
        (emacsvox--advice-scheme-compile-region-after
         (point-min) (point-max)))
      (should
       (equal
        (nreverse events)
        '((icon select-object)
          "Compiling  3 lines to scheme. "))))))

(ert-deftest emacsvox-cmuscheme-file-feedback-uses-native-name ()
  "Scheme file feedback reports the file-name argument."
  (let ((ems--interactive-fn-name 'scheme-load-file)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push (apply #'format format-string arguments) events))))
      (emacsvox--advice-scheme-compile-file-after "wrong.scm")
      (emacsvox--advice-scheme-load-file-after "right.scm"))
    (should
     (equal
      (nreverse events)
      '((icon select-object) "loaded scheme file right.scm")))))

(ert-deftest emacsvox-cmuscheme-switch-feedback-is-target-aware ()
  "Only the matching Scheme switch command produces feedback."
  (let ((ems--interactive-fn-name 'scheme-send-definition-and-go)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'mode-line events))))
      (emacsvox--advice-switch-to-scheme-after)
      (emacsvox--advice-scheme-send-definition-and-go-after))
    (should
     (equal
      (nreverse events)
      '((icon select-object) mode-line)))))

(provide 'emacsvox-cmuscheme-tests)
;;; emacsvox-cmuscheme-tests.el ends here
