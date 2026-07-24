;;; emacsvox-finder-tests.el --- Finder advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Finder advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)
(require 'finder)

(defconst emacsvox-test--finder-direct-advice
  '((finder-commentary :after
     emacsvox--advice-finder-commentary-after)
    (finder-mode :after emacsvox--advice-finder-mode-after)
    (finder-exit :after emacsvox--advice-finder-exit-after))
  "Finder commands using individually named native advice.")

(ert-deftest emacsvox-finder-advice-is-directly-registered ()
  "Migrated Finder advice uses native advice directly."
  (dolist (entry emacsvox-test--finder-direct-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-finder-commentary-feedback-preserves-order ()
  "Interactive Finder commentary speaks before its opening cue."
  (let ((ems--interactive-fn-name 'finder-commentary)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-buffer)
               (lambda () (push 'speak-buffer events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-finder-commentary-after))
    (should
     (equal
      (nreverse events)
      '(speak-buffer (icon open-object))))))

(ert-deftest emacsvox-finder-mode-feedback-remains-unconditional ()
  "Finder mode setup registers Emacsvox and speaks without interactivity."
  (let ((ems--interactive-fn-name nil)
        (finder-known-keywords '((libraries . "Libraries")))
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'speak-mode-line events))))
      (emacsvox--advice-finder-mode-after))
    (should (equal (car finder-known-keywords)
                   '(emacsvox . "Audio Desktop")))
    (should
     (equal
      (nreverse events)
      '((icon open-object) speak-mode-line)))))

(ert-deftest emacsvox-finder-exit-speaks-selected-window-buffer ()
  "Interactive Finder exit speaks in the selected window's buffer."
  (let ((displayed-buffer (generate-new-buffer " *emacsvox-finder-test*"))
        (calling-buffer (generate-new-buffer " *emacsvox-finder-caller*"))
        (ems--interactive-fn-name 'finder-exit)
        events)
    (unwind-protect
        (save-window-excursion
          (set-window-buffer (selected-window) displayed-buffer)
          (with-current-buffer calling-buffer
            (cl-letf (((symbol-function 'emacsvox-icon)
                       (lambda (icon) (push (list 'icon icon) events)))
                      ((symbol-function 'emacsvox-speak-mode-line)
                       (lambda ()
                         (push (list 'mode-line (current-buffer)) events))))
              (emacsvox--advice-finder-exit-after))))
      (kill-buffer displayed-buffer)
      (kill-buffer calling-buffer))
    (should
     (equal
      (nreverse events)
      `((icon close-object) (mode-line ,displayed-buffer))))))

(provide 'emacsvox-finder-tests)
;;; emacsvox-finder-tests.el ends here
