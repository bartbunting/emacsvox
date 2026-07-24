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
    (wdired-toggle-bit emacsvox--advice-wdired-toggle-bit-after)
    (wdired-abort-changes emacsvox--advice-wdired-abort-changes-after)
    (wdired-finish-edit emacsvox--advice-wdired-finish-edit-after)
    (wdired-change-to-wdired-mode
     emacsvox--advice-wdired-change-to-wdired-mode-after))
  "Native after-advice registrations in the Wdired integration.")

(ert-deftest emacsvox-wdired-advice-is-directly-registered ()
  "Wdired advice uses native advice directly."
  (dolist (entry emacsvox-test--wdired-after-advice)
    (pcase-let ((`(,target ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-wdired-navigation-feedback-is-target-aware ()
  "Only the matching interactive Wdired movement produces feedback."
  (let ((ems--interactive-fn-name 'wdired-previous-line)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-dired-speak-line)
               (lambda () (push 'speak-line events))))
      (emacsvox--advice-wdired-next-line-after)
      (emacsvox--advice-wdired-previous-line-after))
    (should
     (equal
      (nreverse events)
      '((icon select-object) speak-line)))))

(ert-deftest emacsvox-wdired-finish-feedback-preserves-order ()
  "Committing Wdired changes cues before speaking confirmation."
  (let ((ems--interactive-fn-name 'wdired-finish-edit)
        (tts-punctuation-mode 'some)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'tts-speak)
               (lambda (text) (push (list 'speak text) events))))
      (emacsvox--advice-wdired-abort-changes-after)
      (emacsvox--advice-wdired-finish-edit-after))
    (should
     (equal
      (nreverse events)
      '((icon save-object) (speak "Committed changes. "))))))

(ert-deftest emacsvox-wdired-word-feedback-is-target-aware ()
  "Only the matching interactive Wdired case command speaks."
  (let ((ems--interactive-fn-name 'wdired-capitalize-word)
        (tts-punctuation-mode 'some)
        events)
    (cl-letf (((symbol-function 'tts-speak)
               (lambda (text) (push text events))))
      (emacsvox--advice-wdired-upcase-word-after)
      (emacsvox--advice-wdired-capitalize-word-after))
    (should (equal events '("Capitalized file name. ")))))

(provide 'emacsvox-wdired-tests)
;;; emacsvox-wdired-tests.el ends here
