;;; emacsvox-transpose-tests.el --- Transpose advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated transpose advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(defconst emacsvox-test--transpose-after-targets
  '(transpose-chars transpose-lines transpose-words transpose-sexps)
  "Transpose commands using generated native after advice.")

(ert-deftest emacsvox-transpose-advice-is-directly-registered ()
  "Migrated transpose advice bypasses the compatibility bridge."
  (dolist (target emacsvox-test--transpose-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-transpose-feedback-is-target-aware ()
  "Only the matching transpose command cues and speaks its text unit."
  (let ((ems--interactive-fn-name 'transpose-words)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-char)
               (lambda (&rest _) (push 'speak-char events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events)))
              ((symbol-function 'emacsvox-speak-word)
               (lambda () (push 'speak-word events)))
              ((symbol-function 'emacsvox-speak-sexp)
               (lambda () (push 'speak-sexp events))))
      (emacsvox--advice-transpose-chars-after)
      (emacsvox--advice-transpose-lines-after)
      (emacsvox--advice-transpose-words-after)
      (emacsvox--advice-transpose-sexps-after))
    (should
     (equal
      (nreverse events)
      '((icon yank-object) speak-word)))))

(ert-deftest emacsvox-transpose-char-feedback-includes-preceding-char ()
  "Character transpose retains the original non-nil speech argument."
  (let ((ems--interactive-fn-name 'transpose-chars)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-char)
               (lambda (&optional preceding)
                 (push (list 'speak-char preceding) events))))
      (emacsvox--advice-transpose-chars-after))
    (should
     (equal
      (nreverse events)
      '((icon yank-object) (speak-char t))))))

(provide 'emacsvox-transpose-tests)
;;; emacsvox-transpose-tests.el ends here
