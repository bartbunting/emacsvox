;;; emacsvox-ediff-tests.el --- Ediff advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Ediff advice.

;;; Code:

(require 'ert)
(require 'ediff)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-ediff.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--ediff-after-targets
  '(ediff-setup-control-buffer
    ediff-toggle-help
    ediff-next-difference
    ediff-previous-difference
    ediff-jump-to-difference
    ediff-jump-to-difference-at-point
    ediff-status-info
    ediff-scroll-vertically
    ediff-toggle-split
    ediff-recenter
    ediff-previous-meta-item
    ediff-next-meta-item
    ediff-registry-action
    ediff-show-registry
    ediff-toggle-filename-truncation)
  "Current Emacs 31 Ediff targets using direct after advice.")

(ert-deftest emacsvox-ediff-advice-is-directly-registered ()
  "Ediff advice is attached directly to current Emacs 31 targets."
  (dolist (target emacsvox-test--ediff-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-ediff-obsolete-scroll-targets-remain-absent ()
  "Ediff support uses the combined Emacs 31 vertical scroll command."
  (should-not (fboundp 'ediff-scroll-up))
  (should-not (fboundp 'ediff-scroll-down))
  (should-not (fboundp 'emacsvox--advice-ediff-scroll-up-after))
  (should-not (fboundp 'emacsvox--advice-ediff-scroll-down-after)))

(ert-deftest emacsvox-ediff-control-buffer-uses-native-argument ()
  "Control-panel tracking records the argument passed by Emacs."
  (let ((emacsvox-ediff-control-buffer 'old))
    (emacsvox--advice-ediff-setup-control-buffer-after 'new)
    (should (eq emacsvox-ediff-control-buffer 'new))))

(ert-deftest emacsvox-ediff-navigation-feedback-is-target-aware ()
  "Only the matching Ediff navigation command produces feedback."
  (let ((ems--interactive-fn-name 'ediff-jump-to-difference)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-ediff-speak-current-difference)
               (lambda () (push 'difference events))))
      (emacsvox--advice-ediff-next-difference-after)
      (emacsvox--advice-ediff-jump-to-difference-after))
    (should
     (equal
      (nreverse events)
      '((icon large-movement) difference)))))

(ert-deftest emacsvox-ediff-scroll-feedback-uses-current-command-event ()
  "Combined vertical scrolling reports the direction selected by Ediff."
  (let ((ems--interactive-fn-name 'ediff-scroll-vertically)
        (last-command-event ?v)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push (apply #'format format-string arguments) events))))
      (emacsvox--advice-ediff-scroll-vertically-after)
      (setq ems--interactive-fn-name 'ediff-scroll-vertically
            last-command-event ?V)
      (emacsvox--advice-ediff-scroll-vertically-after))
    (should
     (equal
      (nreverse events)
      '((icon scroll)
        "Scrolled up buffers A and B"
        (icon scroll)
        "Scrolled down buffers A and B")))))

(provide 'emacsvox-ediff-tests)
;;; emacsvox-ediff-tests.el ends here
