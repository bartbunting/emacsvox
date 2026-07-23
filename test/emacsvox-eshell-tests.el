;;; emacsvox-eshell-tests.el --- Eshell advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Eshell advice.

;;; Code:

(require 'ert)
(require 'eshell)
(require 'esh-mode)
(require 'em-hist)
(require 'em-prompt)
(require 'esh-arg)
(require 'em-cmpl)
(require 'em-rebind)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-eshell.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--eshell-selection-after-targets
  '(eshell
    eshell-next-input
    eshell-previous-input
    eshell-next-matching-input
    eshell-previous-matching-input
    eshell-next-matching-input-from-input
    eshell-previous-matching-input-from-input
    eshell-next-prompt
    eshell-previous-prompt
    eshell-forward-matching-input
    eshell-backward-matching-input
    eshell-insert-buffer-name
    eshell-insert-process
    eshell-insert-envvar
    eshell-forward-argument
    eshell-backward-argument
    eshell-copy-old-input
    eshell-get-next-from-history)
  "Eshell selection and movement commands with direct after advice.")

(defconst emacsvox-test--eshell-editing-advice
  '((eshell-delchar-or-maybe-eof
     :before emacsvox--advice-eshell-delchar-or-maybe-eof-before)
    (eshell-delete-backward-char
     :before emacsvox--advice-eshell-delete-backward-char-before)
    (eshell-show-output
     :after emacsvox--advice-eshell-show-output-after)
    (eshell-mark-output
     :after emacsvox--advice-eshell-mark-output-after)
    (eshell-delete-output
     :after emacsvox--advice-eshell-delete-output-after)
    (eshell-kill-input
     :before emacsvox--advice-eshell-kill-input-before)
    (eshell-complete-lisp-symbol
     :around emacsvox--advice-eshell-complete-lisp-symbol-around))
  "Current Eshell editing commands and their direct advice.")

(ert-deftest emacsvox-eshell-selection-advice-is-directly-registered ()
  "Eshell selection advice bypasses the compatibility bridge."
  (dolist (target emacsvox-test--eshell-selection-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-eshell-history-feedback-is-target-aware ()
  "Only matching interactive Eshell history movement gives feedback."
  (let ((ems--interactive-fn-name 'eshell-next-input)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'eshell-skip-prompt)
               (lambda () (push 'skip-prompt events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda (&rest arguments)
                 (push (cons 'line arguments) events))))
      (emacsvox--advice-eshell-previous-input-after)
      (emacsvox--advice-eshell-next-input-after))
    (should
     (equal
      (nreverse events)
      '((icon select-object) skip-prompt (line 1))))))

(ert-deftest emacsvox-eshell-insert-process-has-one-feedback-path ()
  "Process insertion produces one selection cue and one spoken line."
  (let ((ems--interactive-fn-name 'eshell-insert-process)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda (&rest _) (push 'line events))))
      (emacsvox--advice-eshell-insert-process-after))
    (should
     (equal
      (nreverse events)
      '((icon select-object) line)))))

(ert-deftest emacsvox-eshell-editing-advice-is-directly-registered ()
  "Eshell editing advice is attached directly to current targets."
  (dolist (entry emacsvox-test--eshell-editing-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target where function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-eshell-emacs31-replacement-targets-and-bindings-exist ()
  "Emacs 31 Eshell uses the current line, completion, and output commands."
  (should (fboundp 'eshell-delete-output))
  (should (eq (symbol-function 'eshell-kill-output) 'eshell-delete-output))
  (should (eq (symbol-function 'eshell-bol) 'beginning-of-line))
  (should (eq (symbol-function 'eshell-pcomplete) 'completion-at-point))
  (should-not (fboundp 'emacsvox--advice-eshell-kill-output-after))
  (with-temp-buffer
    (eshell-mode)
    (should (eq (key-binding (kbd "C-a")) 'move-beginning-of-line))
    (should (eq (key-binding (kbd "TAB")) 'completion-at-point))
    (should (eq (key-binding (kbd "C-c C-o")) 'eshell-delete-output))))

(ert-deftest emacsvox-eshell-optional-toggle-targets-remain-absent ()
  "Loading Eshell support does not create optional toggle commands."
  (should-not (featurep 'eshell-toggle))
  (should-not (fboundp 'eshell-toggle))
  (should-not (fboundp 'eshell-toggle-cd)))

(ert-deftest emacsvox-eshell-deletion-feedback-is-target-aware ()
  "Only the matching interactive deletion command gives feedback."
  (with-temp-buffer
    (insert "ab")
    (let ((ems--interactive-fn-name 'eshell-delete-backward-char)
          events)
      (cl-letf (((symbol-function 'dtk-tone)
                 (lambda (&rest arguments)
                   (push (cons 'tone arguments) events)))
                ((symbol-function 'emacsvox-speak-this-char)
                 (lambda (character)
                   (push (list 'char character) events)))
                ((symbol-function 'emacsvox-speak-char)
                 (lambda (&rest arguments)
                   (push (cons 'speak-char arguments) events))))
        (emacsvox--advice-eshell-delchar-or-maybe-eof-before)
        (emacsvox--advice-eshell-delete-backward-char-before))
      (should
       (equal
        (nreverse events)
        '((tone 500 100 force) (char 98)))))))

(ert-deftest emacsvox-eshell-output-feedback-is-target-aware ()
  "Only matching interactive output deletion produces its feedback."
  (let ((ems--interactive-fn-name 'eshell-delete-output)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push
                  (list 'message (apply #'format format-string arguments))
                  events))))
      (emacsvox--advice-eshell-show-output-after)
      (emacsvox--advice-eshell-delete-output-after))
    (should
     (equal
      (nreverse events)
      '((icon delete-object) (message "Flushed output"))))))

(ert-deftest emacsvox-eshell-completion-calls-original-once ()
  "Eshell Lisp completion preserves the result and speaks inserted text."
  (with-temp-buffer
    (insert "ec")
    (let ((ems--interactive-fn-name 'eshell-complete-lisp-symbol)
          (calls 0)
          events)
      (cl-letf (((symbol-function 'dtk-speak)
                 (lambda (text) (push (list 'speak text) events)))
                ((symbol-function 'emacsvox-speak-completions-if-available)
                 (lambda () (push 'completions events))))
        (should
         (eq
          (emacsvox--advice-eshell-complete-lisp-symbol-around
           (lambda (&rest _)
             (cl-incf calls)
             (insert "ho")
             'completed))
          'completed)))
      (should (= calls 1))
      (should (equal (nreverse events) '((speak "echo")))))))

(provide 'emacsvox-eshell-tests)
;;; emacsvox-eshell-tests.el ends here
