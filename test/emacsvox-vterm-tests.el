;;; emacsvox-vterm-tests.el --- Vterm advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)

;; Loading the Elisp interface does not need to compile the optional native
;; module.  Supply only the module entry point advised by Emacsvox.
(unless (featurep 'vterm-module)
  (defun vterm--redraw (&rest _))
  (provide 'vterm-module))
(require 'vterm)
(load (expand-file-name "../lisp/emacsvox-vterm.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-vterm-advice-is-current-and-direct ()
  "Current Vterm targets use native advice directly."
  (dolist (entry emacsvox-vterm--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-vterm-snapshot-captures-buffer-state ()
  "VTerm snapshots cache the current buffer position and character."
  (with-temp-buffer
    (insert "first\nsecond")
    (goto-char (point-max))
    (let ((expected-row (1+ (count-lines (point-min) (point))))
          (expected-column (current-column))
          (expected-point (point))
          (expected-char (preceding-char)))
      (emacsvox-vterm-snapshot)
      (should (= ems--vterm-row expected-row))
      (should (= ems--vterm-column expected-column))
      (should (= ems--vterm-opoint expected-point))
      (should (= ems--vterm-char expected-char)))))

(ert-deftest emacsvox-vterm-redraw-presents-detected-deletion-in-order ()
  "A one-column backspace redraw presents deletion before its character."
  (with-temp-buffer
    (insert "ab")
    (goto-char (point-max))
    (emacsvox-vterm-snapshot)
    (delete-char -1)
    (let ((last-command-event 127)
          events)
      (cl-letf
          (((symbol-function 'emacsvox-speak-edit-operation)
            (lambda (operation)
              (push (list 'edit operation) events)))
           ((symbol-function 'emacsvox-speak-this-char)
            (lambda (character)
              (push (list 'character character) events))))
        (emacsvox--advice-vterm--redraw-after))
      (should
       (equal
        (nreverse events)
        '((edit deletion) (character 98)))))))

(provide 'emacsvox-vterm-tests)
;;; emacsvox-vterm-tests.el ends here
