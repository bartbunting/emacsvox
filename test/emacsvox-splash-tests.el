;;; emacsvox-splash-tests.el --- Splash screen advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated splash screen advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(defconst emacsvox-test--splash-after-targets
  '(about-emacs display-about-screen exit-splash-screen)
  "Splash screen commands using generated native after advice.")

(ert-deftest emacsvox-splash-advice-is-directly-registered ()
  "Migrated splash screen advice bypasses the compatibility bridge."
  (dolist (target emacsvox-test--splash-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-splash-feedback-uses-selected-window-buffer ()
  "Only the matching command speaks, using the selected window's buffer."
  (let ((displayed-buffer (generate-new-buffer " *emacsvox-splash-test*"))
        (calling-buffer (generate-new-buffer " *emacsvox-splash-caller*"))
        (ems--interactive-fn-name 'display-about-screen)
        events)
    (unwind-protect
        (save-window-excursion
          (set-window-buffer (selected-window) displayed-buffer)
          (with-current-buffer calling-buffer
            (cl-letf (((symbol-function 'emacsvox-icon)
                       (lambda (icon) (push (list 'icon icon) events)))
                      ((symbol-function 'emacsvox-speak-buffer)
                       (lambda ()
                         (push (list 'speak-buffer (current-buffer)) events))))
              (emacsvox--advice-about-emacs-after)
              (emacsvox--advice-display-about-screen-after))))
      (kill-buffer displayed-buffer)
      (kill-buffer calling-buffer))
    (should
     (equal
      (nreverse events)
      `((icon open-object) (speak-buffer ,displayed-buffer))))))

(ert-deftest emacsvox-exit-splash-feedback-preserves-order ()
  "Interactive splash exit cues closure before speaking the mode line."
  (let ((ems--interactive-fn-name 'exit-splash-screen)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'speak-mode-line events))))
      (emacsvox--advice-exit-splash-screen-after))
    (should
     (equal
      (nreverse events)
      '((icon close-object) speak-mode-line)))))

(provide 'emacsvox-splash-tests)
;;; emacsvox-splash-tests.el ends here
