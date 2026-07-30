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
  "Entering BS mode retains legacy voices and records native context."
  (with-temp-buffer
    (let ((voice-lock-mode nil))
      (emacsvox--advice-bs-mode-after)
      (should voice-lock-mode)
      (should (eq emacsvox-aural-module 'bs))
      (should (local-variable-p 'emacsvox-aural-module)))))

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
  "BS state tones apply to navigation and state-change transactions."
  (let ((emacsvox-aural-active-scheme 'default)
        (emacsvox-aural-user-rules nil)
        (emacsvox-aural-session-rules nil)
        (emacsvox-aural-buffer-rules nil)
        (emacsvox-aural-enabled-feature-fragments nil)
        (emacsvox-aural--current-rules-cache
         (make-hash-table :test #'equal)))
    (dolist (occasion '(navigation state-change))
      (let* ((plan
              (emacsvox-aural-resolve-active
               '(:role buffer-entry :states (modified read-only))
               (list
                :module 'bs :mode 'bs-mode :occasion occasion)))
             (actions (emacsvox-aural-render-plan-before plan)))
        (should
         (equal
          (emacsvox-aural-render-plan-matched-rules plan)
          '(bs-buffer-modified-tone bs-buffer-read-only-tone)))
        (should
         (equal
          (mapcar #'emacsvox-aural-action-tone actions)
          '(buffer-modified buffer-read-only)))))))

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
              (emacsvox-bs-speak-buffer-line 'select-object)))
          (should
           (equal
            (plist-get (cdr submitted) :facts)
            '(:role buffer-entry :states (modified read-only))))
          (should (eq (plist-get (cdr submitted) :module) 'bs))
          (should
           (eq (plist-get (cdr submitted) :occasion) 'navigation))
          (should
           (equal
            (mapcar
             #'emacsvox-aural-compatibility-action-value
             (plist-get
              (cdr submitted) :compatibility-actions))
            '(select-object)))
          (should
           (string-match-p
            (regexp-quote (buffer-name target))
            (substring-no-properties (car submitted)))))
      (kill-buffer target))))

(ert-deftest emacsvox-bs-selected-buffer-is-one-native-submission ()
  "Leaving BS combines the transition cue and selected-buffer summary."
  (with-temp-buffer
    (rename-buffer " *emacsvox-bs-selected*" t)
    (setq buffer-read-only t)
    (set-buffer-modified-p t)
    (let (submitted)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (setq submitted (cons content arguments)))))
        (emacsvox-bs--submit-current-buffer 'open-object))
      (should
       (string-match-p
        (regexp-quote (buffer-name))
        (substring-no-properties (car submitted))))
      (should
       (equal
        (plist-get (cdr submitted) :facts)
        '(:role buffer-entry :states (modified read-only))))
      (should (eq (plist-get (cdr submitted) :occasion) 'state-change))
      (should
       (equal
        (mapcar
         #'emacsvox-aural-compatibility-action-value
         (plist-get (cdr submitted) :compatibility-actions))
        '(open-object))))))

(ert-deftest emacsvox-bs-selection-feedback-is-target-aware ()
  "Only the matching BS selection command produces feedback."
  (let ((ems--interactive-fn-name 'bs-select-other-window)
        events)
    (cl-letf
        (((symbol-function 'emacsvox-bs--submit-current-buffer)
          (lambda (icon) (push icon events))))
      (emacsvox--advice-bs-select-after)
      (emacsvox--advice-bs-select-other-window-after))
    (should (equal events '(open-object)))))

(ert-deftest emacsvox-bs-row-feedback-is-target-aware ()
  "Only the matching BS row command speaks the selected buffer."
  (let ((ems--interactive-fn-name 'bs-mark-current)
        events)
    (cl-letf
        (((symbol-function 'emacsvox-bs-speak-buffer-line)
          (lambda (&optional icon)
            (push (list 'buffer-line icon) events))))
      (emacsvox--advice-bs-unmark-current-after)
      (emacsvox--advice-bs-mark-current-after))
    (should
     (equal
      (nreverse events)
      '((buffer-line mark-object))))))

(ert-deftest emacsvox-bs-cycle-silences-message-speech ()
  "BS cycling speaks the mode line with message speech disabled."
  (let ((ems--interactive-fn-name 'bs-cycle-next)
        (emacsvox-speak-messages t)
        events)
    (cl-letf
        (((symbol-function 'emacsvox-bs--submit-current-buffer)
          (lambda (icon)
            (push
             (list icon emacsvox-speak-messages)
             events))))
      (emacsvox--advice-bs-cycle-previous-after)
      (emacsvox--advice-bs-cycle-next-after))
    (should
     (equal
      (nreverse events)
      '((select-object nil))))))

(provide 'emacsvox-bs-tests)
;;; emacsvox-bs-tests.el ends here
