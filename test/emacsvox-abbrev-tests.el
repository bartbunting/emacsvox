;;; emacsvox-abbrev-tests.el --- Abbrev advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Abbrev advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(defconst emacsvox-test--abbrev-after-targets
  '(abbrev-edit-save-buffer edit-abbrevs-redefine
    list-abbrevs edit-abbrevs abbrev-mode)
  "Abbrev commands using generated native after advice.")

(ert-deftest emacsvox-abbrev-advice-is-directly-registered ()
  "Migrated Abbrev advice uses native advice directly."
  (dolist (target emacsvox-test--abbrev-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-abbrev-save-feedback-is-target-aware ()
  "Only an interactive abbrev save cues and speaks completion."
  (let ((ems--interactive-fn-name 'abbrev-edit-save-buffer)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'tts-speak)
               (lambda (text) (push (list 'speak text) events))))
      (emacsvox--advice-edit-abbrevs-redefine-after)
      (emacsvox--advice-abbrev-edit-save-buffer-after))
    (should
     (equal
      (nreverse events)
      '((icon save-object) (speak "Saved Abbrevs"))))))

(ert-deftest emacsvox-abbrev-display-feedback-preserves-contracts ()
  "Listing and editing abbrevs retain their distinct announcements."
  (let (events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'message)
               (lambda (text) (push (list 'message text) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'speak-mode-line events))))
      (let ((ems--interactive-fn-name 'list-abbrevs))
        (emacsvox--advice-list-abbrevs-after))
      (let ((ems--interactive-fn-name 'edit-abbrevs))
        (emacsvox--advice-edit-abbrevs-after)))
    (should
     (equal
      (nreverse events)
      '((icon open-object)
        (message "Displayed abbrevs in other window.")
        (icon open-object)
        speak-mode-line)))))

(ert-deftest emacsvox-abbrev-mode-feedback-reports-state ()
  "Interactive abbrev mode toggles cue and report the new state."
  (let ((ems--interactive-fn-name 'abbrev-mode)
        (abbrev-mode nil)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push
                  (list 'message
                        (apply #'format format-string arguments))
                  events))))
      (emacsvox--advice-abbrev-mode-after))
    (should
     (equal
      (nreverse events)
      '((icon button) (message "Turned off abbrev mode"))))))

(provide 'emacsvox-abbrev-tests)
;;; emacsvox-abbrev-tests.el ends here
