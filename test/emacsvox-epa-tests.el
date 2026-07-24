;;; emacsvox-epa-tests.el --- EPA advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated EasyPG Assistant advice.

;;; Code:

(require 'ert)
(require 'epa)
(require 'epa-dired)
(require 'epa-file)
(require 'epa-mail)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-epa.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--epa-operation-targets
  '(epa-progress-callback-function
    epa-mail-verify
    epa-mail-import-keys
    epa-file-select-keys
    epa-insert-keys
    epa-verify-region
    epa-verify-file
    epa-verify-cleartext-in-region
    epa-sign-region
    epa-sign-file
    epa-mail-sign
    epa-mail-encrypt
    epa-mail-decrypt
    epa-import-keys-region
    epa-import-keys
    epa-import-armor-in-region
    epa-export-keys
    epa-decrypt-region
    epa-decrypt-file
    epa-decrypt-armor-in-region
    epa-encrypt-file
    epa-encrypt-region
    epa-dired-do-verify
    epa-dired-do-sign
    epa-dired-do-encrypt
    epa-dired-do-decrypt)
  "Current Emacs 31 EPA operations using direct around advice.")

(defconst emacsvox-test--epa-after-targets
  '(epa-delete-keys
    epa-exit-buffer
    epa-mail-mode
    epa-global-mail-mode
    epa-file-disable
    epa-file-enable
    epa-list-keys
    epa-list-secret-keys
    epa-mark-key
    epa-unmark-key)
  "Current Emacs 31 EPA commands using direct after advice.")

(ert-deftest emacsvox-epa-advice-is-directly-registered ()
  "EPA advice is attached directly to current Emacs 31 targets."
  (dolist (target emacsvox-test--epa-operation-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-around" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))))
  (dolist (target emacsvox-test--epa-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (commandp target))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-epa-operation-calls-original-once ()
  "An interactive EPA operation runs quietly once before its cue."
  (let ((ems--interactive-fn-name 'epa-verify-region)
        (calls 0)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (should
       (eq
        'result
        (emacsvox--advice-epa-verify-region-around
         (lambda (&rest arguments)
           (setq calls (1+ calls))
           (push
            (list 'original arguments
                  emacsvox-speak-messages inhibit-message)
            events)
           'result)
         4 9))))
    (should (= calls 1))
    (should
     (equal
      (nreverse events)
      '((original (4 9) nil t) (icon task-done))))))

(ert-deftest emacsvox-epa-progress-callback-runs-once-quietly ()
  "The noninteractive EPA progress callback remains message-silenced."
  (let ((calls 0)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (&rest arguments) (push arguments events))))
      (should
       (eq
        'result
        (emacsvox--advice-epa-progress-callback-function-around
         (lambda (&rest arguments)
           (setq calls (1+ calls))
           (should (equal arguments '(context what char 1 2 handback)))
           (should-not emacsvox-speak-messages)
           (should inhibit-message)
           'result)
         'context 'what 'char 1 2 'handback))))
    (should (= calls 1))
    (should-not events)))

(ert-deftest emacsvox-epa-mode-feedback-is-target-aware ()
  "Only the matching EPA mode command announces its resulting state."
  (let ((ems--interactive-fn-name 'epa-file-enable)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-epa-file-disable-after)
      (emacsvox--advice-epa-file-enable-after))
    (should
     (equal
      (nreverse events)
      '(line (icon button))))))

(ert-deftest emacsvox-epa-list-feedback-is-target-aware ()
  "Only the matching EPA key-list command produces feedback."
  (let ((ems--interactive-fn-name 'epa-list-secret-keys)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'mode-line events))))
      (emacsvox--advice-epa-list-keys-after)
      (emacsvox--advice-epa-list-secret-keys-after))
    (should
     (equal
      (nreverse events)
      '((icon open-object) mode-line)))))

(ert-deftest emacsvox-epa-mark-feedback-is-target-aware ()
  "EPA mark and unmark commands retain distinct auditory feedback."
  (let ((ems--interactive-fn-name 'epa-unmark-key)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-epa-mark-key-after)
      (emacsvox--advice-epa-unmark-key-after))
    (should
     (equal
      (nreverse events)
      '(line (icon unmark-object))))))

(provide 'emacsvox-epa-tests)
;;; emacsvox-epa-tests.el ends here
