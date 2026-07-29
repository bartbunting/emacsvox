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

(ert-deftest emacsvox-bs-buffer-facts-describe-persistent-state ()
  "BS facts distinguish modified and read-only buffer state."
  (should
   (equal
    (emacsvox-bs--buffer-facts t t)
    '(:role buffer-entry :states (modified read-only))))
  (should
   (equal
    (emacsvox-bs--buffer-facts nil nil)
    '(:role buffer-entry))))

(ert-deftest emacsvox-bs-state-policy-resolves-ordered-named-tones ()
  "BS compatibility policy retains modified then read-only tone order."
  (let ((emacsvox-aural-active-scheme 'default)
        (emacsvox-aural-user-rules nil)
        (emacsvox-aural-session-rules nil)
        (emacsvox-aural-buffer-rules nil)
        (emacsvox-aural-enabled-feature-fragments nil)
        (emacsvox-aural--current-rules-cache
         (make-hash-table :test #'equal)))
    (let* ((plan
            (emacsvox-aural-resolve-active
             '(:role buffer-entry :states (modified read-only))
             '(:module bs :mode bs-mode :occasion navigation)))
           (actions (emacsvox-aural-render-plan-before plan)))
      (should
       (equal
        (emacsvox-aural-render-plan-matched-rules plan)
        '(bs-buffer-modified-tone bs-buffer-read-only-tone)))
      (should
       (equal
        (mapcar #'emacsvox-aural-action-tone actions)
        '(buffer-modified buffer-read-only))))))

(ert-deftest emacsvox-bs-buffer-line-submits-one-semantic-object ()
  "BS submits state tones and buffer speech through one aural transaction."
  (let ((target (generate-new-buffer " *emacsvox-bs-target*"))
        submitted)
    (unwind-protect
        (progn
          (with-current-buffer target
            (setq buffer-read-only t)
            (set-buffer-modified-p t))
          (with-temp-buffer
            (setq major-mode 'bs-mode)
            (cl-letf
                (((symbol-function 'bs--current-buffer)
                  (lambda () target))
                 ((symbol-function 'emacsvox-aural-submit)
                  (lambda (content &rest arguments)
                    (setq submitted (cons content arguments)))))
              (emacsvox-bs-speak-buffer-line)))
          (should
           (equal
            (plist-get (cdr submitted) :facts)
            '(:role buffer-entry :states (modified read-only))))
          (should (eq (plist-get (cdr submitted) :module) 'bs))
          (should
           (eq (plist-get (cdr submitted) :occasion) 'navigation))
          (should
           (string-match-p
            (regexp-quote (buffer-name target))
            (substring-no-properties (car submitted)))))
      (kill-buffer target))))

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
