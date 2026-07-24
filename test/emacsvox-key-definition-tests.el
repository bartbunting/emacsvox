;;; emacsvox-key-definition-tests.el --- Key definition advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated interactive prompt advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(defconst emacsvox-test--key-definition-before-targets
  '(local-set-key global-set-key modify-syntax-entry)
  "Definition commands using native before advice with interactive specs.")

(ert-deftest emacsvox-key-definition-advice-is-directly-registered ()
  "Migrated definition advice uses native advice directly."
  (dolist (target emacsvox-test--key-definition-before-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-before" target))))
      (should (fboundp function))
      (should (commandp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-local-set-key-uses-spoken-prompts ()
  "Interactive local binding uses the Emacsvox key and command prompts."
  (with-temp-buffer
    (use-local-map (make-sparse-keymap))
    (let ((key (kbd "C-c t"))
          prompts)
      (cl-letf (((symbol-function 'read-key-sequence)
                 (lambda (prompt &rest _)
                   (push prompt prompts)
                   key))
                ((symbol-function 'read-command)
                 (lambda (prompt &rest _)
                   (push prompt prompts)
                   'ignore)))
        (call-interactively #'local-set-key))
      (should (eq (lookup-key (current-local-map) key) 'ignore))
      (should
       (equal
        (nreverse prompts)
        '("Locally bind key:" "To command:"))))))

(ert-deftest emacsvox-global-set-key-uses-spoken-prompts ()
  "Interactive global binding uses the Emacsvox key and command prompts."
  (let ((map (make-sparse-keymap))
        (key (kbd "C-c g"))
        prompts)
    (cl-letf (((symbol-function 'current-global-map)
               (lambda () map))
              ((symbol-function 'read-key-sequence)
               (lambda (prompt &rest _)
                 (push prompt prompts)
                 key))
              ((symbol-function 'read-command)
               (lambda (prompt &rest _)
                 (push prompt prompts)
                 'ignore)))
      (call-interactively #'global-set-key))
    (should (eq (lookup-key map key) 'ignore))
    (should
     (equal
      (nreverse prompts)
      '("Globally bind key:" "To command:")))))

(ert-deftest emacsvox-modify-syntax-entry-uses-spoken-prompts ()
  "Interactive syntax modification uses the Emacsvox character prompts."
  (with-temp-buffer
    (set-syntax-table (make-syntax-table))
    (let (prompts)
      (cl-letf (((symbol-function 'read-char)
                 (lambda (prompt &rest _)
                   (push prompt prompts)
                   ?x))
                ((symbol-function 'read-string)
                 (lambda (prompt &rest _)
                   (push prompt prompts)
                   ".")))
        (call-interactively #'modify-syntax-entry))
      (should (eq (char-syntax ?x) ?.))
      (should
       (equal
        (nreverse prompts)
        '("Modify syntax for: " "Syntax Entry: "))))))

(provide 'emacsvox-key-definition-tests)
;;; emacsvox-key-definition-tests.el ends here
