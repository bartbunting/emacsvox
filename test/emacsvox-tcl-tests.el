;;; emacsvox-tcl-tests.el --- Tcl advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Tcl advice.

;;; Code:

(require 'ert)
(require 'tcl)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-tcl.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--tcl-advice
  '((tcl-electric-hash :after emacsvox--advice-tcl-electric-hash-after)
    (tcl-electric-char :after emacsvox--advice-tcl-electric-char-after)
    (tcl-electric-brace :after emacsvox--advice-tcl-electric-brace-after)
    (switch-to-tcl :before emacsvox--advice-switch-to-tcl-before)
    (tcl-eval-region :after emacsvox--advice-tcl-eval-region-after)
    (tcl-eval-defun :after emacsvox--advice-tcl-eval-defun-after)
    (tcl-help-on-word :after emacsvox--advice-tcl-help-on-word-after)
    (tcl-indent-exp :after emacsvox--advice-tcl-indent-exp-after)
    (tcl-indent-line :after emacsvox--advice-tcl-indent-line-after))
  "Current Emacs 31 Tcl targets and their direct native advice.")

(ert-deftest emacsvox-tcl-advice-is-directly-registered ()
  "Tcl advice is attached directly to current Emacs 31 targets."
  (dolist (entry emacsvox-test--tcl-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-tcl-electric-feedback-is-target-aware ()
  "Only the matching Tcl electric command speaks the input event."
  (let ((ems--interactive-fn-name 'tcl-electric-brace)
        (last-input-event ?})
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-this-char)
               (lambda (character) (push character events))))
      (emacsvox--advice-tcl-electric-hash-after)
      (emacsvox--advice-tcl-electric-char-after)
      (emacsvox--advice-tcl-electric-brace-after))
    (should (equal events '(?})))))

(ert-deftest emacsvox-tcl-eval-defun-uses-current-navigation-api ()
  "Defun feedback uses `beginning-of-defun', not Tcl's obsolete alias."
  (with-temp-buffer
    (insert "proc example {} {\n  return 1\n}\n")
    (goto-char (point-max))
    (let ((ems--interactive-fn-name 'tcl-eval-defun)
          (navigation-calls 0)
          events)
      (cl-letf (((symbol-function 'beginning-of-defun)
                 (lambda (&optional _arg)
                   (setq navigation-calls (1+ navigation-calls))
                   (goto-char (point-min))))
                ((symbol-function 'message)
                 (lambda (format-string &rest arguments)
                   (push (apply #'format format-string arguments) events))))
        (emacsvox--advice-tcl-eval-defun-after))
      (should (= navigation-calls 1))
      (should
       (equal events '("Evaluated  proc example {} {"))))))

(ert-deftest emacsvox-tcl-help-speaks-current-help-buffer ()
  "Interactive Tcl help cues and speaks the help buffer."
  (let ((ems--interactive-fn-name 'tcl-help-on-word)
        events)
    (with-current-buffer (get-buffer-create "*Tcl help*")
      (erase-buffer)
      (insert "Tcl help"))
    (unwind-protect
        (cl-letf (((symbol-function 'emacsvox-icon)
                   (lambda (icon) (push (list 'icon icon) events)))
                  ((symbol-function 'emacsvox-speak-buffer)
                   (lambda ()
                     (push (list 'buffer (buffer-name)) events))))
          (emacsvox--advice-tcl-help-on-word-after))
      (kill-buffer "*Tcl help*"))
    (should
     (equal
      (nreverse events)
      '((icon help) (buffer "*Tcl help*"))))))

(ert-deftest emacsvox-tcl-structure-feedback-uses-current-targets ()
  "Current Tcl indentation commands provide distinct feedback."
  (let ((ems--interactive-fn-name 'tcl-indent-exp)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events))))
      (emacsvox--advice-tcl-indent-line-after)
      (emacsvox--advice-tcl-indent-exp-after))
    (should (equal events '((icon fill-object))))))

(ert-deftest emacsvox-tcl-switch-feedback-is-not-triggered-internally ()
  "An internal switch from evaluation does not announce a direct switch."
  (let ((ems--interactive-fn-name 'tcl-eval-region)
        events)
    (cl-letf (((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push (apply #'format format-string arguments) events))))
      (emacsvox--advice-switch-to-tcl-before t)
      (emacsvox--advice-tcl-eval-region-after 1 2 t))
    (should (equal events '("Evaluating contents of region")))))

(provide 'emacsvox-tcl-tests)
;;; emacsvox-tcl-tests.el ends here
