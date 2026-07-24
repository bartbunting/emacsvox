;;; emacsvox-ffap-tests.el --- FFAP advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated FFAP advice.

;;; Code:

(require 'cl-lib)
(require 'ert)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-ffap.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--ffap-after-targets
  '(ffap ffap-alternate-file ffap-alternate-file-other-window ffap-at-mouse
    ffap-dired-other-frame ffap-dired-other-window
    ffap-list-directory ffap-literally
    ffap-next ffap-next-url
    ffap-other-frame ffap-other-tab ffap-other-window
    ffap-read-only ffap-read-only-other-frame
    ffap-read-only-other-tab ffap-read-only-other-window)
  "FFAP commands using generated native after advice.")

(ert-deftest emacsvox-ffap-advice-is-directly-registered ()
  "Migrated FFAP advice uses native advice directly."
  (dolist (target emacsvox-test--ffap-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-ffap-feedback-is-target-aware ()
  "Only the matching interactive FFAP command produces feedback."
  (let ((ems--interactive-fn-name 'ffap-other-window)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'speak-mode-line events))))
      (emacsvox--advice-ffap-other-frame-after)
      (emacsvox--advice-ffap-other-window-after))
    (should
     (equal
      (nreverse events)
      '((icon open-object) speak-mode-line)))))

(provide 'emacsvox-ffap-tests)
;;; emacsvox-ffap-tests.el ends here
