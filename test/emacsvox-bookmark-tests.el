;;; emacsvox-bookmark-tests.el --- Bookmark advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Bookmark advice.

;;; Code:

(require 'ert)
(require 'bookmark)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-bookmark.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--bookmark-after-targets
  '(bookmark-set
    bookmark-yank-word
    bookmark-jump
    bookmark-bmenu-list
    bookmark-bmenu-this-window
    bookmark-bmenu-select
    bookmark-bmenu-delete-backwards
    bookmark-bmenu-1-window
    bookmark-bmenu-2-window
    bookmark-bmenu-switch-other-window
    bookmark-bmenu-edit-annotation
    bookmark-bmenu-delete
    bookmark-bmenu-unmark
    bookmark-edit-annotation-confirm
    bookmark-bmenu-show-annotation
    bookmark-bmenu-show-all-annotations
    bookmark-bmenu-mark
    bookmark-bmenu-backup-unmark)
  "Current Emacs 31 Bookmark targets using direct after advice.")

(ert-deftest emacsvox-bookmark-advice-is-directly-registered ()
  "Bookmark advice is attached once to each current Emacs 31 target."
  (dolist (target emacsvox-test--bookmark-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target)))
          (registrations 0))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))
      (advice-mapc
       (lambda (advice _properties)
         (when (eq advice function)
           (setq registrations (1+ registrations))))
       target)
      (should (= registrations 1))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-bookmark-obsolete-targets-are-not-advised ()
  "Bookmark support does not recreate or advise superseded commands."
  (dolist
      (target
       '(bookmark-insert-current-bookmark
         bookmark-insert-current-file-name
         bookmark-bmenu-quit))
    (should-not (fboundp target))
    (should-not
     (fboundp
      (intern (format "emacsvox--advice-%s-after" target)))))
  (should (fboundp 'bookmark-send-edited-annotation))
  (should-not
   (fboundp 'emacsvox--advice-bookmark-send-edited-annotation-after)))

(ert-deftest emacsvox-bookmark-list-feedback-preserves-order ()
  "Listing bookmarks selects the list before speaking its first line."
  (let ((ems--interactive-fn-name 'bookmark-bmenu-list)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'switch-to-buffer)
               (lambda (buffer &rest _)
                 (push (list 'switch buffer) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda (&rest _) (push 'line events))))
      (emacsvox--advice-bookmark-bmenu-list-after))
    (should
     (equal
      (nreverse events)
      '((icon open-object) (switch "*Bookmark List*") line)))))

(ert-deftest emacsvox-bookmark-selection-feedback-is-target-aware ()
  "Only the matching Bookmark selection command produces feedback."
  (let ((ems--interactive-fn-name 'bookmark-bmenu-this-window)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda (&rest _) (push 'line events))))
      (emacsvox--advice-bookmark-bmenu-select-after)
      (emacsvox--advice-bookmark-bmenu-this-window-after))
    (should
     (equal
      (nreverse events)
      '(line (icon open-object))))))

(ert-deftest emacsvox-bookmark-annotation-feedback-uses-current-command ()
  "Annotation confirmation feedback follows its current Emacs command."
  (let ((ems--interactive-fn-name 'bookmark-edit-annotation-confirm)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda (&rest _) (push 'line events))))
      (emacsvox--advice-bookmark-bmenu-edit-annotation-after)
      (emacsvox--advice-bookmark-edit-annotation-confirm-after))
    (should
     (equal
      (nreverse events)
      '((icon task-done) line)))))

(provide 'emacsvox-bookmark-tests)
;;; emacsvox-bookmark-tests.el ends here
