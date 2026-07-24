;;; emacsvox-arc-tests.el --- Archive mode advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Archive mode advice.

;;; Code:

(require 'ert)
(require 'arc-mode)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-arc.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--arc-after-targets
  '(archive-mark
    archive-next-line
    archive-previous-line
    archive-flag-deleted
    archive-unflag
    archive-unflag-backwards
    archive-extract
    archive-extract-other-window
    archive-view)
  "Current Emacs 31 Archive mode targets using direct after advice.")

(ert-deftest emacsvox-arc-advice-is-directly-registered ()
  "Archive mode advice is attached directly to current Emacs 31 targets."
  (dolist (target emacsvox-test--arc-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-arc-navigation-feedback-is-target-aware ()
  "Only the matching Archive navigation command speaks."
  (let ((ems--interactive-fn-name 'archive-previous-line)
        events)
    (cl-letf (((symbol-function 'emacsvox-archive-speak-line)
               (lambda () (push 'line events))))
      (emacsvox--advice-archive-next-line-after)
      (emacsvox--advice-archive-previous-line-after))
    (should (equal events '(line)))))

(ert-deftest emacsvox-arc-marking-feedback-is-target-aware ()
  "Archive marking commands retain their distinct auditory icons."
  (let ((ems--interactive-fn-name 'archive-flag-deleted)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-archive-speak-line)
               (lambda () (push 'line events))))
      (emacsvox--advice-archive-mark-after)
      (emacsvox--advice-archive-flag-deleted-after)
      (emacsvox--advice-archive-unflag-after))
    (should
     (equal
      (nreverse events)
      '((icon delete-object) line)))))

(ert-deftest emacsvox-arc-open-feedback-is-target-aware ()
  "Only the matching Archive open command cues and speaks."
  (let ((ems--interactive-fn-name 'archive-extract-other-window)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'mode-line events))))
      (emacsvox--advice-archive-extract-after)
      (emacsvox--advice-archive-extract-other-window-after)
      (emacsvox--advice-archive-view-after))
    (should
     (equal
      (nreverse events)
      '((icon open-object) mode-line)))))

(provide 'emacsvox-arc-tests)
;;; emacsvox-arc-tests.el ends here
