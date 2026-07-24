;;; emacsvox-tar-tests.el --- Tar mode advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Tar mode advice.

;;; Code:

(require 'ert)
(require 'tar-mode)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-tar.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--tar-after-targets
  '(tar-next-line
    tar-previous-line
    tar-flag-deleted
    tar-unflag
    tar-unflag-backwards
    tar-extract
    tar-extract-other-window
    tar-view)
  "Current Emacs 31 Tar mode targets using direct after advice.")

(ert-deftest emacsvox-tar-advice-is-directly-registered ()
  "Tar mode advice is attached directly to current Emacs 31 targets."
  (dolist (target emacsvox-test--tar-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers))))
  (should-not (fboundp 'tar-quit)))

(ert-deftest emacsvox-tar-navigation-feedback-is-target-aware ()
  "Only the matching Tar navigation command speaks."
  (let ((ems--interactive-fn-name 'tar-previous-line)
        events)
    (cl-letf (((symbol-function 'emacsvox-tar-speak-line)
               (lambda () (push 'line events))))
      (emacsvox--advice-tar-next-line-after)
      (emacsvox--advice-tar-previous-line-after))
    (should (equal events '(line)))))

(ert-deftest emacsvox-tar-marking-feedback-is-target-aware ()
  "Tar marking commands retain their distinct auditory icons."
  (let ((ems--interactive-fn-name 'tar-unflag-backwards)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-tar-speak-line)
               (lambda () (push 'line events))))
      (emacsvox--advice-tar-flag-deleted-after)
      (emacsvox--advice-tar-unflag-after)
      (emacsvox--advice-tar-unflag-backwards-after))
    (should
     (equal
      (nreverse events)
      '((icon yank-object) line)))))

(ert-deftest emacsvox-tar-open-feedback-is-target-aware ()
  "Only the matching Tar open command cues and speaks."
  (let ((ems--interactive-fn-name 'tar-view)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'mode-line events))))
      (emacsvox--advice-tar-extract-after)
      (emacsvox--advice-tar-extract-other-window-after)
      (emacsvox--advice-tar-view-after))
    (should
     (equal
      (nreverse events)
      '((icon open-object) mode-line)))))

(provide 'emacsvox-tar-tests)
;;; emacsvox-tar-tests.el ends here
