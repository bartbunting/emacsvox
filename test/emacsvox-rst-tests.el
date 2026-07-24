;;; emacsvox-rst-tests.el --- RST advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated RST advice.

;;; Code:

(require 'ert)
(require 'rst)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-rst.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--rst-after-targets
  '(rst-shift-region
    rst-goto-section
    rst-forward-section
    rst-backward-section
    rst-forward-indented-block
    rst-compile
    rst-compile-alt-toolset
    rst-adjust
    rst-adjust-section-title
    rst-compile-find-conf
    rst-compile-pdf-preview
    rst-compile-pseudo-region
    rst-compile-slides-preview
    rst-display-adornments-hierarchy
    rst-toc
    rst-toc-mode-goto-section
    rst-toc-quit-window
    rst-force-fill-paragraph
    rst-mark-section
    rst-bullet-list-region
    rst-convert-bullets-to-enumeration
    rst-enumerate-region
    rst-insert-list
    rst-insert-list-new-item
    rst-toc-insert
    rst-join-paragraph
    rst-line-block-region
    rst-straighten-adornments
    rst-straighten-bullets-region)
  "Current Emacs 31 RST targets using direct after advice.")

(ert-deftest emacsvox-rst-advice-is-directly-registered ()
  "RST advice is attached directly to current Emacs 31 targets."
  (dolist (target emacsvox-test--rst-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-rst-obsolete-target-remains-absent ()
  "Loading RST support does not recreate removed commands."
  (should-not (fboundp 'rst-promote-region))
  (should-not (fboundp 'emacsvox--advice-rst-promote-region-after)))

(ert-deftest emacsvox-rst-movement-feedback-is-target-aware ()
  "Only the matching RST movement target produces feedback."
  (let ((ems--interactive-fn-name 'rst-shift-region)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda (&rest _) (push 'line events))))
      (emacsvox--advice-rst-forward-section-after)
      (emacsvox--advice-rst-shift-region-after))
    (should
     (equal
      (nreverse events)
      '((icon large-movement) line)))))

(ert-deftest emacsvox-rst-task-and-list-feedback-is-target-aware ()
  "RST task and list operations retain distinct feedback."
  (let ((ems--interactive-fn-name 'rst-adjust)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda (&rest _) (push 'line events)))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push
                  (list 'message (apply #'format format-string arguments))
                  events))))
      (emacsvox--advice-rst-bullet-list-region-after)
      (emacsvox--advice-rst-adjust-after))
    (should
     (equal
      (nreverse events)
      '((icon task-done) line)))
    (setq ems--interactive-fn-name 'rst-bullet-list-region
          events nil)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push
                  (list 'message (apply #'format format-string arguments))
                  events))))
      (emacsvox--advice-rst-bullet-list-region-after))
    (should
     (equal
      (nreverse events)
      '((icon item) (message "Bulletized. "))))))

(ert-deftest emacsvox-rst-toc-and-mark-feedback-is-target-aware ()
  "RST TOC and mark commands retain their distinct spoken context."
  (let ((ems--interactive-fn-name 'rst-toc)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'mode-line events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda (&rest _) (push 'line events))))
      (emacsvox--advice-rst-mark-section-after)
      (emacsvox--advice-rst-toc-after))
    (should
     (equal
      (nreverse events)
      '((icon open-object) mode-line)))))

(provide 'emacsvox-rst-tests)
;;; emacsvox-rst-tests.el ends here
