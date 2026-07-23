;;; emacsvox-c-tests.el --- C mode advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated CC Mode advice.

;;; Code:

(require 'ert)
(require 'cc-mode)
(require 'cc-awk)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-c.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(ert-deftest emacsvox-c-obsolete-targets-remain-absent ()
  "The integration must not recreate commands absent from Emacs 31."
  (dolist (target '(c-awk-end-of-defunm c-toggle-auto-state))
    (should-not (fboundp target))))

(ert-deftest emacsvox-c-emacs31-awk-targets-and-bindings-exist ()
  "Current AWK navigation commands and bindings are available."
  (dolist (target '(c-awk-beginning-of-defun c-awk-end-of-defun))
    (should (fboundp target)))
  (with-temp-buffer
    (awk-mode)
    (should
     (eq (key-binding (kbd "C-M-a")) 'c-awk-beginning-of-defun))
    (should (eq (key-binding (kbd "C-M-e")) 'c-awk-end-of-defun))))

(ert-deftest emacsvox-c-custom-navigation-bindings-are-installed ()
  "Emacsvox C statement navigation retains its established bindings."
  (with-temp-buffer
    (c-mode)
    (should
     (eq (key-binding (kbd "C-c s")) 'emacsvox-c-speak-semantics))
    (should (eq (key-binding (kbd "M-n")) 'c-next-statement))
    (should (eq (key-binding (kbd "M-p")) 'c-previous-statement))))

(defconst emacsvox-test--c-deletion-advice
  '((c-electric-delete-forward
     :before emacsvox--advice-c-electric-delete-forward-before)
    (c-hungry-delete-forward
     :before emacsvox--advice-c-hungry-delete-forward-before)
    (c-hungry-delete-backwards
     :before emacsvox--advice-c-hungry-delete-backwards-before)
    (c-electric-backspace
     :before emacsvox--advice-c-electric-backspace-before)
    (c-electric-delete
     :before emacsvox--advice-c-electric-delete-before)
    (c-electric-semi&comma
     :after emacsvox--advice-c-electric-semi&comma-after))
  "CC Mode deletion and electric advice registrations.")

(ert-deftest emacsvox-c-deletion-advice-is-directly-registered ()
  "CC Mode deletion advice bypasses the compatibility bridge."
  (dolist (entry emacsvox-test--c-deletion-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target where function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-c-forward-delete-runs-once-after-feedback ()
  "Interactive forward deletion speaks first and invokes CC Mode once."
  (with-temp-buffer
    (c-mode)
    (insert "ab")
    (goto-char 2)
    (let ((c-hungry-delete-key nil)
          (ems--interactive-fn-name 'c-electric-delete-forward)
          (calls 0)
          events)
      (cl-letf (((symbol-function 'dtk-tone-deletion)
                 (lambda () (push 'tone events)))
                ((symbol-function 'emacsvox-speak-this-char)
                 (lambda (character)
                   (push (list 'char character) events)))
                (c-delete-function
                 (lambda (count)
                   (cl-incf calls)
                   (push (list 'original count) events)
                   'delete-result)))
        (should (eq (c-electric-delete-forward nil) 'delete-result)))
      (should (= calls 1))
      (should
       (equal
        (nreverse events)
        '(tone (char 98) (original 1)))))))

(ert-deftest emacsvox-c-deletion-feedback-is-target-aware ()
  "Only the matching interactive deletion command gives feedback."
  (with-temp-buffer
    (insert "ab")
    (goto-char 2)
    (let ((ems--interactive-fn-name 'c-hungry-delete-backwards)
          events)
      (cl-letf (((symbol-function 'dtk-tone-deletion)
                 (lambda () (push 'tone events)))
                ((symbol-function 'emacsvox-speak-this-char)
                 (lambda (character)
                   (push (list 'char character) events))))
        (emacsvox--advice-c-hungry-delete-forward-before)
        (emacsvox--advice-c-hungry-delete-backwards-before))
      (should (equal (nreverse events) '(tone (char 97)))))))

(defconst emacsvox-test--c-navigation-after-targets
  '(c-up-conditional
    c-forward-conditional
    c-backward-conditional
    c-beginning-of-statement
    c-end-of-statement
    c-mark-function
    c-beginning-of-defun
    c-end-of-defun
    c-scope-operator
    c-previous-statement
    c-next-statement
    c-awk-beginning-of-defun
    c-awk-end-of-defun
    c-up-conditional-with-else
    c-down-conditional-with-else
    c-down-conditional)
  "CC Mode navigation commands with direct after advice.")

(ert-deftest emacsvox-c-navigation-advice-is-directly-registered ()
  "CC Mode navigation advice bypasses the compatibility bridge."
  (dolist (target emacsvox-test--c-navigation-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-c-navigation-feedback-is-target-aware ()
  "Only matching interactive C navigation speaks and cues."
  (let ((ems--interactive-fn-name 'c-forward-conditional)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda (&rest _) (push 'line events))))
      (emacsvox--advice-c-backward-conditional-after)
      (emacsvox--advice-c-forward-conditional-after))
    (should
     (equal
      (nreverse events)
      '((icon large-movement) line)))))

(ert-deftest emacsvox-c-conditional-feedback-preserves-reference-order ()
  "Conditional descent speaks the destination before its cue."
  (let ((ems--interactive-fn-name 'c-down-conditional-with-else)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda (&rest _) (push 'line events))))
      (emacsvox--advice-c-down-conditional-with-else-after))
    (should
     (equal
      (nreverse events)
      '(line (icon large-movement))))))

(defconst emacsvox-test--c-formatting-after-targets
  '(c-indent-defun
    c-indent-command
    c-backslash-region
    c-context-line-break
    c-context-open-line
    c-indent-new-comment-line
    c-indent-line-or-region
    c-indent-exp
    c-fill-paragraph
    c-toggle-auto-hungry-state
    c-toggle-auto-newline
    c-toggle-electric-state
    c-toggle-hungry-state
    c-toggle-parse-state-debug
    c-toggle-syntactic-indentation)
  "CC Mode formatting and toggle commands with direct after advice.")

(ert-deftest emacsvox-c-formatting-advice-is-directly-registered ()
  "CC Mode formatting advice bypasses the compatibility bridge."
  (dolist (target emacsvox-test--c-formatting-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-c-context-line-feedback-preserves-reference-order ()
  "Contextual line insertion speaks before its opening cue."
  (let ((ems--interactive-fn-name 'c-context-open-line)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda (&rest _) (push 'line events))))
      (emacsvox--advice-c-context-line-break-after)
      (emacsvox--advice-c-context-open-line-after))
    (should
     (equal
      (nreverse events)
      '(line (icon open-object))))))

(ert-deftest emacsvox-c-toggle-feedback-is-target-aware ()
  "Only the matching interactive CC Mode toggle is announced."
  (let ((ems--interactive-fn-name 'c-toggle-electric-state)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push
                  (list 'message
                        (apply #'format format-string arguments))
                  events))))
      (emacsvox--advice-c-toggle-auto-newline-after)
      (emacsvox--advice-c-toggle-electric-state-after))
    (should
     (equal
      (nreverse events)
      '((icon button) (message "Toggled c-toggle-electric-state"))))))

(ert-deftest emacsvox-c-backslash-region-speaks-post-command-region ()
  "Backslash feedback uses the current point and mark after the command."
  (with-temp-buffer
    (insert "alpha")
    (goto-char 2)
    (set-mark 5)
    (let ((ems--interactive-fn-name 'c-backslash-region)
          events)
      (cl-letf (((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events)))
                ((symbol-function 'emacsvox-speak-region)
                 (lambda (start end)
                   (push (list 'region start end) events))))
        (emacsvox--advice-c-backslash-region-after))
      (should
       (equal
        (nreverse events)
        '((icon task-done) (region 2 5)))))))

(provide 'emacsvox-c-tests)
;;; emacsvox-c-tests.el ends here
