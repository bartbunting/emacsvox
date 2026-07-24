;;; emacsvox-kmacro-tests.el --- Kmacro advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Kmacro advice.

;;; Code:

(require 'ert)
(require 'kmacro)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-kmacro.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--kmacro-advice
  '((kmacro-start-macro :before
                        emacsvox--advice-kmacro-start-macro-before)
    (kmacro-start-macro-or-insert-counter
     :before emacsvox--advice-kmacro-start-macro-or-insert-counter-before)
    (kmacro-end-or-call-macro
     :before emacsvox--advice-kmacro-end-or-call-macro-before)
    (kmacro-end-or-call-macro-repeat
     :before emacsvox--advice-kmacro-end-or-call-macro-repeat-before)
    (kmacro-edit-macro-repeat
     :after emacsvox--advice-kmacro-edit-macro-repeat-after)
    (kmacro-call-ring-2nd-repeat
     :before emacsvox--advice-kmacro-call-ring-2nd-repeat-before)
    (kmacro-call-macro :around
                       emacsvox--advice-kmacro-call-macro-around)
    (call-last-kbd-macro :around
                         emacsvox--advice-kmacro-call-last-kbd-macro-around))
  "Current Emacs 31 Kmacro targets and their direct native advice.")

(ert-deftest emacsvox-kmacro-advice-is-directly-registered ()
  "Kmacro advice is attached directly to current Emacs 31 targets."
  (dolist (entry emacsvox-test--kmacro-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target where function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-kmacro-start-feedback-is-target-aware ()
  "Only the matching Kmacro start command announces recording."
  (let ((ems--interactive-fn-name 'kmacro-start-macro)
        (defining-kbd-macro nil)
        (executing-kbd-macro nil)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push (apply #'format format-string arguments) events))))
      (emacsvox--advice-kmacro-start-macro-or-insert-counter-before)
      (emacsvox--advice-kmacro-start-macro-before))
    (should
     (equal
      (nreverse events)
      '((icon open-object) "Defining new kbd macro.")))))

(ert-deftest emacsvox-kmacro-counter-start-respects-recording-state ()
  "Counter insertion does not announce a new macro while one is active."
  (let ((ems--interactive-fn-name
         'kmacro-start-macro-or-insert-counter)
        (defining-kbd-macro t)
        (executing-kbd-macro nil)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'message)
               (lambda (&rest arguments) (push arguments events))))
      (emacsvox--advice-kmacro-start-macro-or-insert-counter-before))
    (should-not events)))

(ert-deftest emacsvox-kmacro-end-feedback-reports-recording-state ()
  "Ending an active macro retains close feedback."
  (let ((ems--interactive-fn-name 'kmacro-end-or-call-macro)
        (defining-kbd-macro t)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push (apply #'format format-string arguments) events))))
      (emacsvox--advice-kmacro-end-or-call-macro-before))
    (should
     (equal
      (nreverse events)
      '((icon close-object) "Finished defining kbd macro.")))))

(ert-deftest emacsvox-kmacro-call-fallback-retains-reference-feedback ()
  "The reference-defined macro-call fallback remains unconditional."
  (let ((defining-kbd-macro nil)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push (apply #'format format-string arguments) events))))
      (emacsvox--advice-kmacro-end-or-call-macro-repeat-before))
    (should
     (equal
      (nreverse events)
      '((icon select-object) "Calling macro.")))))

(ert-deftest emacsvox-kmacro-call-macro-runs-once-with-silenced-messages ()
  "Calling a Kmacro invokes the original once with message speech off."
  (let ((calls 0)
        events)
    (should
     (eq
      'result
      (emacsvox--advice-kmacro-call-macro-around
       (lambda (&rest arguments)
         (setq calls (1+ calls))
         (push (list arguments emacsvox-speak-messages) events)
         'result)
       3 t nil "macro")))
    (should (= calls 1))
    (should
     (equal events '(((3 t nil "macro") nil))))))

(ert-deftest emacsvox-kmacro-last-macro-runs-once-with-spoken-messages ()
  "Calling the last macro invokes the original once with message speech on."
  (let ((calls 0)
        events)
    (should
     (eq
      'result
      (emacsvox--advice-kmacro-call-last-kbd-macro-around
       (lambda (&rest arguments)
         (setq calls (1+ calls))
         (push (list arguments emacsvox-speak-messages) events)
         'result)
       2 #'ignore)))
    (should (= calls 1))
    (should
     (equal events `(((2 ,#'ignore) t))))))

(provide 'emacsvox-kmacro-tests)
;;; emacsvox-kmacro-tests.el ends here
