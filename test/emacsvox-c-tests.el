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

(provide 'emacsvox-c-tests)
;;; emacsvox-c-tests.el ends here
