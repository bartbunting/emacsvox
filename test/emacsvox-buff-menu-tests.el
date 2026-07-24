;;; emacsvox-buff-menu-tests.el --- Buffer Menu advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Buffer Menu advice.

;;; Code:

(require 'ert)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-buff-menu.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--buff-menu-after-targets
  '(buffer-menu
    Buffer-menu-bury
    Buffer-menu-delete-backwards
    Buffer-menu-delete
    Buffer-menu-mark
    Buffer-menu-save
    Buffer-menu-select
    Buffer-menu-unmark
    Buffer-menu-backup-unmark
    Buffer-menu-execute
    Buffer-menu-toggle-read-only
    Buffer-menu-not-modified
    Buffer-menu-1-window
    Buffer-menu-2-window
    Buffer-menu-this-window
    Buffer-menu-other-window)
  "Current Emacs 31 Buffer Menu targets using direct after advice.")

(ert-deftest emacsvox-buff-menu-advice-is-directly-registered ()
  "Buffer Menu advice is attached directly to current Emacs 31 targets."
  (dolist (target emacsvox-test--buff-menu-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))))
  (should
   (advice-member-p
    #'emacsvox--advice-list-buffers-filter-return
    'list-buffers))
  (should
   (advice-member-p
    #'emacsvox--advice-Buffer-menu-visit-tags-table-before
    'Buffer-menu-visit-tags-table))
  (should
   (advice-member-p
    #'emacsvox--advice-buffer-menu-quit-window-around
    'quit-window)))

(ert-deftest emacsvox-buff-menu-obsolete-quit-remains-absent ()
  "Buffer Menu support does not recreate its removed quit command."
  (should-not (fboundp 'Buffer-menu-quit))
  (should-not
   (fboundp 'emacsvox--advice-Buffer-menu-quit-after)))

(ert-deftest emacsvox-buff-menu-list-uses-returned-window ()
  "List feedback selects and returns the window produced by Emacs."
  (let ((ems--interactive-fn-name 'list-buffers)
        (window 'window)
        events)
    (cl-letf (((symbol-function 'select-window)
               (lambda (selected &rest _)
                 (push (list 'window selected) events)))
              ((symbol-function 'tabulated-list-next-column)
               (lambda (count) (push (list 'column count) events)))
              ((symbol-function 'define-key)
               (lambda (&rest _)))
              ((symbol-function 'emacsvox-list-buffers-speak-buffer-line)
               (lambda () (push 'line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (should
       (eq
        window
        (emacsvox--advice-list-buffers-filter-return window))))
    (should
     (equal
      (nreverse events)
      '((window window) (column 3) line (icon open-object))))))

(ert-deftest emacsvox-buff-menu-modified-feedback-uses-native-argument ()
  "Modified feedback reflects the native optional argument."
  (let ((ems--interactive-fn-name 'Buffer-menu-not-modified)
        events)
    (cl-letf (((symbol-function 'emacsvox-list-buffers-speak-buffer-line)
               (lambda () (push 'line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-Buffer-menu-not-modified-after t)
      (setq ems--interactive-fn-name 'Buffer-menu-not-modified)
      (emacsvox--advice-Buffer-menu-not-modified-after nil))
    (should
     (equal
      (nreverse events)
      '(line
        (icon modified-object)
        line
        (icon unmodified-object))))))

(ert-deftest emacsvox-buff-menu-row-feedback-is-target-aware ()
  "Only the matching Buffer Menu row command produces feedback."
  (let ((ems--interactive-fn-name 'Buffer-menu-mark)
        events)
    (cl-letf (((symbol-function 'emacsvox-list-buffers-speak-buffer-line)
               (lambda () (push 'line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-Buffer-menu-delete-after)
      (emacsvox--advice-Buffer-menu-mark-after))
    (should
     (equal
      (nreverse events)
      '((icon mark-object) line)))))

(ert-deftest emacsvox-buff-menu-quit-feedback-is-mode-scoped ()
  "Interactive quit feedback is limited to Buffer Menu origins."
  (let ((ems--interactive-fn-name 'quit-window)
        (calls 0)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'mode-line events))))
      (with-temp-buffer
        (setq major-mode 'Buffer-menu-mode)
        (should
         (eq
          'quit
          (emacsvox--advice-buffer-menu-quit-window-around
           (lambda ()
             (setq calls (1+ calls))
             'quit)))))
      (with-temp-buffer
        (should
         (eq
          'quit
          (emacsvox--advice-buffer-menu-quit-window-around
           (lambda ()
             (setq calls (1+ calls))
             'quit))))))
    (should (= calls 2))
    (should
     (equal
      (nreverse events)
      '((icon close-object) mode-line)))))

(provide 'emacsvox-buff-menu-tests)
;;; emacsvox-buff-menu-tests.el ends here
