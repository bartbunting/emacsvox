;;; emacsvox-re-builder-tests.el --- Re Builder advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Re Builder advice.

;;; Code:

(require 'ert)
(require 're-builder)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-re-builder.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--re-builder-after-targets
  '(re-builder
    reb-quit
    reb-next-match
    reb-prev-match
    reb-toggle-case
    reb-copy
    reb-enter-subexp-mode
    reb-quit-subexp-mode
    reb-auto-update)
  "Current Emacs 31 Re Builder targets using direct after advice.")

(ert-deftest emacsvox-re-builder-advice-is-directly-registered ()
  "Re Builder advice is attached directly to current Emacs 31 targets."
  (dolist (target emacsvox-test--re-builder-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-re-builder-lifecycle-feedback-is-target-aware ()
  "Only the matching Re Builder lifecycle command produces feedback."
  (let ((ems--interactive-fn-name 'reb-enter-subexp-mode)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-reb-quit-after)
      (emacsvox--advice-reb-enter-subexp-mode-after)
      (emacsvox--advice-reb-quit-subexp-mode-after))
    (should (equal events '((icon open-object))))))

(ert-deftest emacsvox-re-builder-match-feedback-uses-target-buffer ()
  "Match navigation speaks the target buffer with point highlighted."
  (let ((target (generate-new-buffer " *emacsvox-re-builder-target*"))
        (ems--interactive-fn-name 'reb-next-match)
        events)
    (unwind-protect
        (progn
          (with-current-buffer target
            (insert "matching line"))
          (let ((reb-target-buffer target))
            (cl-letf (((symbol-function 'emacsvox-speak-line)
                       (lambda ()
                         (push
                          (list 'line (current-buffer) emacsvox-show-point)
                          events)))
                      ((symbol-function 'emacsvox-icon)
                       (lambda (icon) (push (list 'icon icon) events))))
              (emacsvox--advice-reb-next-match-after)
              (emacsvox--advice-reb-prev-match-after)))
          (should
           (equal
            (nreverse events)
            `((line ,target t) (icon large-movement)))))
      (kill-buffer target))))

(ert-deftest emacsvox-re-builder-toggle-reports-target-case-state ()
  "Case toggling reports the target buffer's resulting state."
  (let ((target (generate-new-buffer " *emacsvox-re-builder-case*"))
        (ems--interactive-fn-name 'reb-toggle-case)
        events)
    (unwind-protect
        (progn
          (with-current-buffer target
            (setq-local case-fold-search nil))
          (let ((reb-target-buffer target))
            (cl-letf (((symbol-function 'emacsvox-icon)
                       (lambda (icon) (push icon events))))
              (emacsvox--advice-reb-toggle-case-after)))
          (should (equal events '(off))))
      (kill-buffer target))))

(ert-deftest emacsvox-re-builder-auto-update-remains-unconditional ()
  "Automatic updates mark overlays and repeat their status message."
  (let ((target (generate-new-buffer " *emacsvox-re-builder-update*"))
        events
        overlay)
    (unwind-protect
        (progn
          (with-current-buffer target
            (insert "match")
            (setq overlay (make-overlay (point-min) (point-max)))
            (setq-local reb-overlays (list overlay)))
          (let ((reb-target-buffer target))
            (cl-letf (((symbol-function 'emacsvox-speak-message-again)
                       (lambda () (push 'message events))))
              (emacsvox--advice-reb-auto-update-after)))
          (should (eq (overlay-get overlay 'auditory-icon) 'item))
          (should (equal events '(message))))
      (kill-buffer target))))

(provide 'emacsvox-re-builder-tests)
;;; emacsvox-re-builder-tests.el ends here
