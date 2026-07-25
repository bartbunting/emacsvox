;;; emacsvox-input-tests.el --- Input advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Argument handling and native-registration coverage for input prompt advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(defconst emacsvox-test--input-before-targets
  '(read-key read-key-sequence read-key-sequence-vector
    read-char read-char-exclusive)
  "Input readers migrated with generated native prompt advice.")

(defconst emacsvox-test--input-direct-advice
  '((quoted-insert :after emacsvox--advice-quoted-insert-after)
    (read-event :before emacsvox--advice-read-event-before)
    (read-multiple-choice :before
     emacsvox--advice-read-multiple-choice-before)
    (read-passwd--hide-password :after
     emacsvox--advice-read-passwd--hide-password-after)
    (read-passwd-toggle-visibility :after
     emacsvox--advice-read-passwd-toggle-visibility-after)
    (read-passwd :before emacsvox--advice-read-passwd-before)
    (read-char-choice :before emacsvox--advice-read-char-choice-before)
    (yes-or-no-p :around emacsvox--advice-yes-or-no-p-around)
    (y-or-n-p :around emacsvox--advice-y-or-n-p-around)
    (ask-user-about-lock-help :after
     emacsvox--advice-ask-user-about-lock-help-after))
  "Input readers migrated with individually defined native advice.")

(ert-deftest emacsvox-input-advice-is-directly-registered ()
  "Migrated input advice uses native advice directly."
  (dolist (target emacsvox-test--input-before-targets)
    (let ((function (intern (format "emacsvox--advice-%s-before" target))))
      (should (fboundp function))
      (should (advice-member-p function target))))
  (dolist (entry emacsvox-test--input-direct-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-read-event-advice-uses-explicit-prompt ()
  "Event-reading feedback uses its prompt argument directly."
  (let (notifications)
    (cl-letf (((symbol-function 'tts-notify)
               (lambda (text) (push text notifications))))
      (emacsvox--advice-read-event-before "Press a key")
      (emacsvox--advice-read-event-before nil))
    (should (equal notifications '("Press a key")))))

(ert-deftest emacsvox-read-multiple-choice-preserves-feedback ()
  "Multiple-choice feedback formats short and detailed choices."
  (let (events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'ems--log-message)
               (lambda (text) (push (list 'log text) events)))
              ((symbol-function 'tts-notify)
               (lambda (text) (push (list 'notify text) events)))
              ((symbol-function 'sox-tones)
               (lambda (&rest arguments)
                 (push (list 'tones arguments) events)))
              ((symbol-function 'tts-speak-list)
               (lambda (items) (push (list 'speak-list items) events))))
      (emacsvox--advice-read-multiple-choice-before
       "Continue? "
       '((?y "yes" "accept") (?n "no" "decline"))))
    (should
     (equal
      (nreverse events)
      '((icon open-object)
        (log "Continue? y: yes: accept\n n: no: decline")
        (notify "Continue? ")
        (tones (2 2))
        (speak-list ("y: yes" "n: no")))))))

(ert-deftest emacsvox-read-key-advice-caches-and-speaks-prompt ()
  "Key-reader advice preserves prompt caches and spoken feedback."
  (let ((emacsvox-speak-messages t)
        (emacsvox-last-message nil)
        (emacsvox-read-char-prompt-cache nil)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'tts-notify)
               (lambda (text) (push (list 'notify text) events))))
      (emacsvox--advice-read-key-before "Continue?"))
    (should (equal emacsvox-last-message "Continue?"))
    (should (equal emacsvox-read-char-prompt-cache "Continue?"))
    (should
     (equal
      (nreverse events)
      '((icon char) (notify "Continue?"))))))

(ert-deftest emacsvox-read-key-advice-respects-silenced-messages ()
  "A caller can suppress key-reader speech without losing prompt state."
  (let ((emacsvox-speak-messages nil)
        (emacsvox-last-message nil)
        (emacsvox-read-char-prompt-cache nil)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'tts-notify)
               (lambda (text) (push (list 'notify text) events))))
      (emacsvox--advice-read-key-before "Continue?"))
    (should (equal emacsvox-last-message "Continue?"))
    (should (equal emacsvox-read-char-prompt-cache "Continue?"))
    (should-not events)))

(ert-deftest emacsvox-read-passwd-advice-uses-explicit-prompt ()
  "Password feedback preserves icon and speech order."
  (let (events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'tts-speak)
               (lambda (text) (push (list 'speak text) events))))
      (emacsvox--advice-read-passwd-before "Secret: "))
    (should
     (equal
      (nreverse events)
      '((icon open-object) (speak "Secret: ") (icon pwd))))))

(ert-deftest emacsvox-read-passwd-character-feedback-respects-visibility ()
  "Password characters are masked in speech only while hidden."
  (let ((last-input-event ?s)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'tts-notify)
               (lambda (text) (push (list 'notify text) events))))
      (let ((read-passwd--password-hidden t))
        (emacsvox--advice-read-passwd--hide-password-after))
      (let ((read-passwd--password-hidden nil))
        (emacsvox--advice-read-passwd--hide-password-after)))
    (should
     (equal
      (nreverse events)
      '((notify "dot")
        (icon repeat-active)
        (notify "s")
        (icon repeat-active))))))

(ert-deftest emacsvox-read-passwd-toggle-announces-visibility ()
  "Interactive password visibility changes announce their resulting state."
  (let (events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events))))
      (dolist (hidden '(t nil))
        (let ((ems--interactive-fn-name 'read-passwd-toggle-visibility)
              (read-passwd--password-hidden hidden))
          (emacsvox--advice-read-passwd-toggle-visibility-after))))
    (should (equal (nreverse events) '(off on)))))

(ert-deftest emacsvox-long-question-preserves-call-and-positive-result ()
  "A long question cues a positive answer around exactly one call."
  (let ((calls 0)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (should
       (eq
        (emacsvox--advice-yes-or-no-p-around
         (lambda (&rest arguments)
           (cl-incf calls)
           (push (list 'original arguments) events)
           'accepted)
         "Continue?")
        'accepted)))
    (should (= calls 1))
    (should
     (equal
      (nreverse events)
      '((icon ask-question)
        (original ("Continue?"))
        (icon yes-answer))))))

(ert-deftest emacsvox-short-question-preserves-negative-result ()
  "A short question cues a negative answer around exactly one call."
  (let ((calls 0)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (should-not
       (emacsvox--advice-y-or-n-p-around
        (lambda (&rest arguments)
          (cl-incf calls)
          (push (list 'original arguments) events)
          nil)
        "Continue?")))
    (should (= calls 1))
    (should
     (equal
      (nreverse events)
      '((icon ask-short-question)
        (original ("Continue?"))
        (icon n-answer))))))

(ert-deftest emacsvox-lock-help-cue-remains-unconditional ()
  "Lock-conflict help always plays its help cue."
  (let (events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-ask-user-about-lock-help-after))
    (should (equal events '((icon help))))))

(provide 'emacsvox-input-tests)
;;; emacsvox-input-tests.el ends here
