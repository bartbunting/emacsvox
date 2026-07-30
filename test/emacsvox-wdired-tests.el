;;; emacsvox-wdired-tests.el --- Wdired advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Wdired advice.

;;; Code:

(require 'cl-lib)
(require 'ert)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-wdired.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--wdired-after-advice
  '((wdired-next-line emacsvox--advice-wdired-next-line-after)
    (wdired-previous-line emacsvox--advice-wdired-previous-line-after)
    (wdired-upcase-word emacsvox--advice-wdired-upcase-word-after)
    (wdired-capitalize-word emacsvox--advice-wdired-capitalize-word-after)
    (wdired-downcase-word emacsvox--advice-wdired-downcase-word-after)
    (wdired-set-bit emacsvox--advice-wdired-set-bit-after)
    (wdired-toggle-bit emacsvox--advice-wdired-toggle-bit-after)
    (wdired-mouse-toggle-bit
     emacsvox--advice-wdired-mouse-toggle-bit-after))
  "Native after-advice registrations in the Wdired integration.")

(defconst emacsvox-test--wdired-around-advice
  '((wdired-abort-changes
     emacsvox--advice-wdired-abort-changes-around)
    (wdired-finish-edit
     emacsvox--advice-wdired-finish-edit-around)
    (wdired-exit emacsvox--advice-wdired-exit-around)
    (wdired-change-to-wdired-mode
     emacsvox--advice-wdired-change-to-wdired-mode-around)
    (dired-toggle-read-only
     emacsvox--advice-dired-toggle-read-only-around))
  "Native around-advice registrations in the Wdired integration.")

(ert-deftest emacsvox-wdired-advice-is-directly-registered ()
  "Every migrated Wdired command has native advice."
  (dolist (entry
           (append
            emacsvox-test--wdired-after-advice
            emacsvox-test--wdired-around-advice))
    (pcase-let ((`(,target ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-wdired-navigation-feedback-is-target-aware ()
  "Only the matching interactive Wdired movement presents its entry."
  (let ((ems--interactive-fn-name 'wdired-previous-line)
        events)
    (cl-letf
        (((symbol-function 'emacsvox-dired-present-current)
          (lambda (&rest arguments)
            (push arguments events))))
      (emacsvox--advice-wdired-next-line-after)
      (emacsvox--advice-wdired-previous-line-after))
    (should
     (equal
      events
      '((select-object navigation focus-entered))))))

(ert-deftest emacsvox-wdired-edit-feedback-is-target-aware-and-semantic ()
  "Only the matching edit command submits its edit kind and current entry."
  (let ((ems--interactive-fn-name 'wdired-capitalize-word)
        submission)
    (cl-letf
        (((symbol-function 'emacsvox-dired-entry-facts)
          (lambda (&rest _)
            '(:role filesystem-entry :entry-kind file
              :events (object-changed))))
         ((symbol-function 'emacsvox-dired--submit-text)
          (lambda (&rest arguments)
            (setq submission arguments))))
      (emacsvox--advice-wdired-upcase-word-after)
      (emacsvox--advice-wdired-capitalize-word-after))
    (should
     (equal
      submission
      '("Capitalized file name"
        (:role filesystem-entry :entry-kind file
         :events (object-changed)
         :filesystem-edit-kind filename-capitalize)
        edit nil)))))

(ert-deftest emacsvox-wdired-operation-result-runs-once-and-is-semantic ()
  "Committing Wdired changes submits one native operation result."
  (let ((ems--interactive-fn-name 'wdired-finish-edit)
        (visible-message "Earlier message")
        (calls 0)
        submission)
    (cl-letf
        (((symbol-function 'current-message)
          (lambda () visible-message))
         ((symbol-function 'emacsvox-dired--submit-message)
          (lambda (&rest arguments)
            (setq submission arguments))))
      (should
       (eq
        'committed
        (emacsvox--advice-wdired-finish-edit-around
         (lambda (&rest arguments)
           (should-not emacsvox-speak-messages)
           (should (equal arguments '(confirm)))
           (setq
            calls (1+ calls)
            visible-message "Changes committed")
           'committed)
         'confirm))))
    (should (= calls 1))
    (should
     (equal
      submission
      '("Changes committed"
        (:role filesystem-operation
         :filesystem-operation-kind wdired-commit
         :events (operation-completed))
        state-change save-object)))))

(ert-deftest emacsvox-wdired-enter-is-one-context-preserving-submission ()
  "Entering Wdired owns its message and preserves source context."
  (let ((ems--interactive-fn-name 'dired-toggle-read-only)
        (calls 0)
        submission)
    (cl-letf
        (((symbol-function 'emacsvox-aural-capture-context)
          (lambda (&rest arguments)
            (should (equal arguments '(dired state-change)))
            '(:module dired :occasion state-change :captured t)))
         ((symbol-function 'emacsvox-dired--submit-message)
          (lambda (&rest arguments)
            (setq
             submission
             (cons emacsvox-aural-submission-context arguments)))))
      (should
       (eq
        'entered
        (emacsvox--advice-dired-toggle-read-only-around
         (lambda ()
           (should-not emacsvox-speak-messages)
           (setq calls (1+ calls))
           'entered)))))
    (should (= calls 1))
    (should
     (equal
      submission
      '((:module dired :occasion state-change :captured t)
        "Entering writable Dired mode"
        (:role filesystem-operation
         :filesystem-operation-kind wdired-edit
         :events (operation-started))
        state-change open-object)))))

(ert-deftest emacsvox-wdired-nested-entry-does-not-duplicate-feedback ()
  "The public Dired toggle owns feedback when it calls the Wdired entry point."
  (let ((ems--interactive-fn-name 'dired-toggle-read-only)
        (calls 0)
        submissions)
    (cl-letf
        (((symbol-function 'emacsvox-dired--submit-message)
          (lambda (&rest arguments)
            (push arguments submissions))))
      (emacsvox--advice-dired-toggle-read-only-around
       (lambda ()
         (emacsvox--advice-wdired-change-to-wdired-mode-around
          (lambda ()
            (setq calls (1+ calls))
            'entered)))))
    (should (= calls 1))
    (should (= (length submissions) 1))
    (should
     (eq
      (plist-get (cadar submissions) :filesystem-operation-kind)
      'wdired-edit))))

(ert-deftest emacsvox-wdired-real-enter-and-abort-have-native-feedback ()
  "A real Wdired cycle enters and aborts with one native result per command."
  (let* ((directory (make-temp-file "emacsvox-wdired-" t))
         (file (expand-file-name "entry.txt" directory))
         buffer
         submissions)
    (unwind-protect
        (progn
          (write-region "entry" nil file nil 'silent)
          (setq buffer (dired-noselect directory))
          (with-current-buffer buffer
            (cl-letf
                (((symbol-function 'emacsvox-aural-submit)
                  (lambda (content &rest arguments)
                    (push (cons content arguments) submissions))))
              (funcall-interactively #'dired-toggle-read-only)
              (should (derived-mode-p 'wdired-mode))
              (funcall-interactively #'wdired-abort-changes)
              (should (derived-mode-p 'dired-mode)))))
      (when (buffer-live-p buffer)
        (kill-buffer buffer))
      (delete-directory directory t))
    (should (= (length submissions) 2))
    (should
     (equal
      (mapcar
       (lambda (submission)
         (let ((facts (plist-get (cdr submission) :facts)))
           (list
            (plist-get facts :filesystem-operation-kind)
            (car (plist-get facts :events)))))
       (nreverse submissions))
      '((wdired-edit operation-started)
        (wdired-abort operation-failed))))))

(ert-deftest emacsvox-wdired-edit-kind-is-registered ()
  "The Wdired edit discriminator is part of the aural vocabulary."
  (should (emacsvox-aural-semantic 'filesystem-edit-kind))
  (should
   (memq
    'filename-capitalize
    (emacsvox-aural-semantic-allowed-values
     (emacsvox-aural-semantic 'filesystem-edit-kind)))))

(provide 'emacsvox-wdired-tests)
;;; emacsvox-wdired-tests.el ends here
