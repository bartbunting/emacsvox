;;; emacsvox-browse-kill-ring-tests.el --- Browse Kill Ring advice tests -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'package)
(package-initialize)
(require 'browse-kill-ring)

(load
 (expand-file-name
  "../lisp/emacsvox-browse-kill-ring.el"
  (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(ert-deftest emacsvox-browse-kill-ring-current-targets-exist ()
  "Every advised target exists in the installed package."
  (dolist (entry emacsvox-browse-kill-ring--advice)
    (should (fboundp (car entry)))))

(ert-deftest emacsvox-browse-kill-ring-advice-is-directly-registered ()
  "Browse Kill Ring advice uses native advice directly."
  (dolist (entry emacsvox-browse-kill-ring--advice)
    (pcase-let ((`(,target ,function) entry))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-browse-kill-ring-feedback-is-target-aware ()
  "Only the matching interactive command produces feedback."
  (let ((ems--interactive-fn-name 'browse-kill-ring-forward)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events))))
      (emacsvox--advice-browse-kill-ring-previous-after)
      (emacsvox--advice-browse-kill-ring-forward-after))
    (should (equal (nreverse events) '(line select-object)))))

(provide 'emacsvox-browse-kill-ring-tests)
;;; emacsvox-browse-kill-ring-tests.el ends here
