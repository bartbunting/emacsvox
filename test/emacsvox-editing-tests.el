;;; emacsvox-editing-tests.el --- Editing advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated editing advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(defconst emacsvox-test--editing-after-targets
  '(blink-matching-open zap-to-char exchange-point-and-mark
    abort-recursive-edit insert-parentheses)
  "Editing functions using native after advice.")

(ert-deftest emacsvox-editing-advice-is-directly-registered ()
  "Migrated editing advice bypasses the compatibility bridge."
  (dolist (target emacsvox-test--editing-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-matching-delimiter-feedback-is-unconditional ()
  "The internal matching-delimiter callback always speaks its match."
  (let ((ems--interactive-fn-name nil)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-matching-paren)
               (lambda () (push 'speak-match events))))
      (emacsvox--advice-blink-matching-open-after))
    (should (equal events '(speak-match)))))

(ert-deftest emacsvox-zap-feedback-is-target-aware ()
  "Interactive character zapping cues deletion before speaking the line."
  (let ((ems--interactive-fn-name 'zap-to-char)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda (&optional argument)
                 (push (list 'speak-line argument) events))))
      (emacsvox--advice-zap-to-char-after))
    (should
     (equal
      (nreverse events)
      '((icon delete-object) (speak-line 1))))))

(ert-deftest emacsvox-exchange-point-and-mark-highlights-point ()
  "Interactive point/mark exchange temporarily enables point highlighting."
  (let ((ems--interactive-fn-name 'exchange-point-and-mark)
        (emacsvox-show-point nil)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda ()
                 (push (list 'speak-line emacsvox-show-point) events))))
      (emacsvox--advice-exchange-point-and-mark-after))
    (should-not emacsvox-show-point)
    (should
     (equal
      (nreverse events)
      '((icon large-movement) (speak-line t))))))

(ert-deftest emacsvox-abort-recursive-edit-feedback-is-target-aware ()
  "Only an interactive recursive-edit abort announces itself."
  (let ((ems--interactive-fn-name 'abort-recursive-edit)
        messages)
    (cl-letf (((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push (apply #'format format-string arguments) messages))))
      (emacsvox--advice-abort-recursive-edit-after))
    (should (equal messages '("Aborting recursive edit")))))

(ert-deftest emacsvox-insert-parentheses-feedback-preserves-order ()
  "Interactive parenthesis insertion speaks before its open-object cue."
  (let ((ems--interactive-fn-name 'insert-parentheses)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-insert-parentheses-after))
    (should
     (equal
      (nreverse events)
      '(speak-line (icon open-object))))))

(provide 'emacsvox-editing-tests)
;;; emacsvox-editing-tests.el ends here
