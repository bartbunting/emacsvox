;;; emacsvox-cider-tests.el --- CIDER advice tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'package)
(package-initialize)
(dolist (feature
         '(cider cider-apropos cider-browse-ns cider-classpath cider-connection
           cider-debug cider-doc cider-eval cider-format cider-inspector
           cider-mode cider-popup cider-repl cider-scratch cider-selector
           cider-stacktrace))
  (require feature))
(load (expand-file-name "../lisp/emacsvox-cider.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil)

(ert-deftest emacsvox-cider-advice-is-current-and-direct ()
  "Current CIDER targets use native advice directly."
  (dolist (entry emacsvox-cider--advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp target))
      (should (advice-member-p function target))))
  (dolist (removed '(cider-visit-error-buffer
                     cider-assoc-buffer-with-connection
                     cider-assoc-project-with-connection
                     cider-close-nrepl-session
                     cider-connection-browser
                     cider-connections-goto-connection
                     cider-display-connection-info
                     cider-inspect-read-and-inspect
                     -repl-clear-banners))
    (should-not (fboundp removed))))

(ert-deftest emacsvox-cider-feedback-is-target-aware ()
  "Only the matching interactive CIDER command provides feedback."
  (let ((ems--interactive-fn-name 'cider-format-buffer)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events))))
      (emacsvox--advice-cider-format-region-after)
      (emacsvox--advice-cider-format-buffer-after))
    (should (equal events '(task-done)))))

(ert-deftest emacsvox-cider-pretty-printing-uses-current-state ()
  "Pretty-printing feedback uses the CIDER boolean directly."
  (let ((cider-repl-use-pretty-printing t)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events)))
              ((symbol-function 'message)
               (lambda (&rest _) nil)))
      (emacsvox-cider--pretty-printing-feedback))
    (should (equal events '(on)))))

(provide 'emacsvox-cider-tests)
;;; emacsvox-cider-tests.el ends here
