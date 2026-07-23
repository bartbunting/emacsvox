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

(provide 'emacsvox-eshell-tests)
;;; emacsvox-eshell-tests.el ends here
