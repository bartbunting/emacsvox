;;; emacsvox-display-tests.el --- Display command advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated display command advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(defconst emacsvox-test--display-after-targets
  '(shell world-clock)
  "Display commands using native after advice.")

(ert-deftest emacsvox-display-advice-is-directly-registered ()
  "Migrated display advice bypasses the compatibility bridge."
  (dolist (target emacsvox-test--display-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-shell-feedback-is-target-aware ()
  "Interactive shell startup cues before speaking its mode line."
  (let ((ems--interactive-fn-name 'shell)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'speak-mode-line events))))
      (emacsvox--advice-world-clock-after)
      (emacsvox--advice-shell-after))
    (should
     (equal
      (nreverse events)
      '((icon open-object) speak-mode-line)))))

(ert-deftest emacsvox-world-clock-speaks-clock-buffer ()
  "Interactive world-clock display speaks in its buffer and restores context."
  (let ((clock-buffer (get-buffer-create "*wclock*"))
        (caller-buffer (current-buffer))
        (ems--interactive-fn-name 'world-clock)
        events)
    (unwind-protect
        (progn
          (cl-letf (((symbol-function 'emacsvox-icon)
                     (lambda (icon) (push (list 'icon icon) events)))
                    ((symbol-function 'emacsvox-speak-buffer)
                     (lambda ()
                       (push (list 'speak-buffer (current-buffer)) events))))
            (emacsvox--advice-world-clock-after))
          (should (eq (current-buffer) caller-buffer))
          (should
           (equal
            (nreverse events)
            (list
             '(icon open-object)
             (list 'speak-buffer clock-buffer)))))
      (kill-buffer clock-buffer))))

(provide 'emacsvox-display-tests)
;;; emacsvox-display-tests.el ends here
