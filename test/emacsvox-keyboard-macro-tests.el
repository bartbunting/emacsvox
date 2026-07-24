;;; emacsvox-keyboard-macro-tests.el --- Keyboard macro advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for keyboard macro lifecycle advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(defconst emacsvox-test--keyboard-macro-direct-advice
  '((kbd-macro-query :after emacsvox--advice-kbd-macro-query-after)
    (start-kbd-macro :before emacsvox--advice-start-kbd-macro-before)
    (end-kbd-macro :after emacsvox--advice-end-kbd-macro-after))
  "Keyboard macro commands using individually named native advice.")

(ert-deftest emacsvox-keyboard-macro-lifecycle-advice-is-directly-registered ()
  "Migrated keyboard macro advice uses native advice directly."
  (dolist (entry emacsvox-test--keyboard-macro-direct-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-keyboard-macro-start-feedback-preserves-order ()
  "Starting a macro cues opening before speaking its announcement."
  (let ((ems--interactive-fn-name 'start-kbd-macro)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'tts-speak)
               (lambda (text) (push (list 'speak text) events))))
      (emacsvox--advice-kbd-macro-query-after)
      (emacsvox--advice-start-kbd-macro-before)
      (emacsvox--advice-end-kbd-macro-after))
    (should
     (equal
      (nreverse events)
      '((icon open-object)
        (speak "Started defining a keyboard macro "))))))

(ert-deftest emacsvox-keyboard-macro-end-feedback-preserves-order ()
  "Ending a macro cues closure before speaking its announcement."
  (let ((ems--interactive-fn-name 'end-kbd-macro)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'tts-speak)
               (lambda (text) (push (list 'speak text) events))))
      (emacsvox--advice-end-kbd-macro-after))
    (should
     (equal
      (nreverse events)
      '((icon close-object)
        (speak "Finished defining keyboard macro "))))))

(ert-deftest emacsvox-keyboard-macro-query-announces-prompt ()
  "An interactive macro query announces its future prompt."
  (let ((ems--interactive-fn-name 'kbd-macro-query)
        events)
    (cl-letf (((symbol-function 'message)
               (lambda (text) (push (list 'message text) events))))
      (emacsvox--advice-kbd-macro-query-after))
    (should
     (equal events
            '((message "Will prompt at this point in macro"))))))

(provide 'emacsvox-keyboard-macro-tests)
;;; emacsvox-keyboard-macro-tests.el ends here
