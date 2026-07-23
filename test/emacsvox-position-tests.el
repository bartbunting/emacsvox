;;; emacsvox-position-tests.el --- Point and display advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for point and display advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(defconst emacsvox-test--position-before-targets
  '(recenter-top-bottom recenter)
  "Display commands using generated native before advice.")

(defconst emacsvox-test--position-after-targets
  '(beginning-of-line move-beginning-of-line
    end-of-line move-end-of-line
    yank yank-pop
    line-number-mode column-number-mode)
  "Point-editing commands using generated native after advice.")

(ert-deftest emacsvox-position-advice-is-directly-registered ()
  "Migrated point and display advice bypasses the compatibility bridge."
  (dolist (target emacsvox-test--position-before-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-before" target))))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :before function) ems--modern-advice-wrappers))))
  (dolist (target emacsvox-test--position-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-recenter-feedback-is-target-aware ()
  "Only the matching interactive recenter command speaks before movement."
  (let ((ems--interactive-fn-name 'recenter)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events))))
      (emacsvox--advice-recenter-top-bottom-before)
      (emacsvox--advice-recenter-before))
    (should (equal events '(speak-line)))))

(ert-deftest emacsvox-line-endpoint-feedback-preserves-order ()
  "Line endpoint movement retains its speech-before-icon ordering."
  (let ((ems--interactive-fn-name 'move-end-of-line)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events)))
              ((symbol-function 'emacsvox-speak-current-column)
               (lambda () (push 'speak-column events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-move-beginning-of-line-after 1)
      (emacsvox--advice-move-end-of-line-after 1))
    (should
     (equal
      (nreverse events)
      '(speak-column (icon right))))))

(ert-deftest emacsvox-yank-feedback-speaks-post-command-range ()
  "Interactive yank feedback cues and speaks the mark-to-point range."
  (with-temp-buffer
    (insert "abcdef")
    (goto-char 5)
    (set-mark 2)
    (let ((ems--interactive-fn-name 'yank-pop)
          events)
      (cl-letf (((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events)))
                ((symbol-function 'emacsvox-speak-region)
                 (lambda (beginning end)
                   (push (list 'speak-region beginning end) events))))
        (emacsvox--advice-yank-after)
        (emacsvox--advice-yank-pop-after))
      (should
       (equal
        (nreverse events)
        '((icon yank-object) (speak-region 2 5)))))))

(ert-deftest emacsvox-position-indicator-feedback-is-target-aware ()
  "Only the toggled position indicator cues and speaks the mode line."
  (let ((ems--interactive-fn-name 'column-number-mode)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'speak-mode-line events))))
      (emacsvox--advice-line-number-mode-after)
      (emacsvox--advice-column-number-mode-after))
    (should
     (equal
      (nreverse events)
      '((icon button) speak-mode-line)))))

(provide 'emacsvox-position-tests)
;;; emacsvox-position-tests.el ends here
