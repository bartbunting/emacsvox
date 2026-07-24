;;; emacsvox-bs-tests.el --- BS advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated BS advice.

;;; Code:

(require 'ert)
(require 'bs)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-bs.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--bs-after-targets
  '(bs-mode
    bs-kill
    bs-abort
    bs-set-configuration-and-refresh
    bs-refresh
    bs-view
    bs-select
    bs-select-other-window
    bs-tmp-select-other-window
    bs-select-other-frame
    bs-select-in-one-window
    bs-bury-buffer
    bs-save
    bs-toggle-current-to-show
    bs-set-current-buffer-to-show-never
    bs-mark-current
    bs-unmark-current
    bs-delete
    bs-delete-backward
    bs-up
    bs-down
    bs-cycle-next
    bs-cycle-previous)
  "Current Emacs 31 BS targets using direct after advice.")

(ert-deftest emacsvox-bs-advice-is-directly-registered ()
  "BS advice is attached directly to current Emacs 31 targets."
  (dolist (target emacsvox-test--bs-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-bs-mode-always-enables-voice-lock ()
  "Entering BS mode enables voice locking even when called internally."
  (let ((voice-lock-mode nil))
    (emacsvox--advice-bs-mode-after)
    (should voice-lock-mode)))

(ert-deftest emacsvox-bs-selection-feedback-is-target-aware ()
  "Only the matching BS selection command produces feedback."
  (let ((ems--interactive-fn-name 'bs-select-other-window)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'mode-line events))))
      (emacsvox--advice-bs-select-after)
      (emacsvox--advice-bs-select-other-window-after))
    (should
     (equal
      (nreverse events)
      '((icon open-object) mode-line)))))

(ert-deftest emacsvox-bs-row-feedback-is-target-aware ()
  "Only the matching BS row command speaks the selected buffer."
  (let ((ems--interactive-fn-name 'bs-mark-current)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-bs-speak-buffer-line)
               (lambda () (push 'buffer-line events))))
      (emacsvox--advice-bs-unmark-current-after)
      (emacsvox--advice-bs-mark-current-after))
    (should
     (equal
      (nreverse events)
      '((icon mark-object) buffer-line)))))

(ert-deftest emacsvox-bs-cycle-silences-message-speech ()
  "BS cycling speaks the mode line with message speech disabled."
  (let ((ems--interactive-fn-name 'bs-cycle-next)
        (emacsvox-speak-messages t)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda ()
                 (push
                  (list 'mode-line emacsvox-speak-messages)
                  events))))
      (emacsvox--advice-bs-cycle-previous-after)
      (emacsvox--advice-bs-cycle-next-after))
    (should
     (equal
      (nreverse events)
      '((icon select-object) (mode-line nil))))))

(provide 'emacsvox-bs-tests)
;;; emacsvox-bs-tests.el ends here
