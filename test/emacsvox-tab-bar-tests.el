;;; emacsvox-tab-bar-tests.el --- Tab Bar advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Tab Bar advice.

;;; Code:

(require 'ert)
(require 'tab-bar)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-tab-bar.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--tab-bar-removed-list-targets
  '(tab-bar-list
    tab-bar-list-execute
    tab-bar-list-prev-line
    tab-bar-list-next-line
    tab-bar-list-unmark
    tab-bar-list-delete
    tab-bar-list-delete-backwards
    tab-bar-list-select)
  "Tab-list commands absent from Emacs 31.")

(ert-deftest emacsvox-tab-bar-obsolete-list-targets-remain-absent ()
  "The integration must not recreate commands removed before Emacs 31."
  (dolist (target emacsvox-test--tab-bar-removed-list-targets)
    (should-not (fboundp target))))

(ert-deftest emacsvox-tab-bar-emacs31-switcher-targets-exist ()
  "Current Tab Switcher commands and bindings are available."
  (dolist
      (target
       '(tab-list
         tab-switcher
         tab-switcher-execute
         tab-switcher-prev-line
         tab-switcher-next-line
         tab-switcher-unmark
         tab-switcher-delete
         tab-switcher-delete-backwards
         tab-switcher-select))
    (should (fboundp target)))
  (with-temp-buffer
    (tab-switcher-mode)
    (should (eq (key-binding (kbd "RET")) 'tab-switcher-select))
    (should (eq (key-binding (kbd "d")) 'tab-switcher-delete))
    (should (eq (key-binding (kbd "x")) 'tab-switcher-execute))
    (should (eq (key-binding (kbd "n")) 'tab-switcher-next-line))
    (should (eq (key-binding (kbd "p")) 'tab-switcher-prev-line))))

(defconst emacsvox-test--tab-bar-lifecycle-after-targets
  '(tab-bar-switch-to-tab
    tab-next
    tab-previous
    tab-select
    tab-bar-select-tab
    tab-bar-select-tab-by-name
    tab-bar-switch-to-next-tab
    tab-bar-switch-to-prev-tab
    tab-bar-switch-to-recent-tab
    tab-bar-close-other-tabs
    tab-bar-close-tab
    tab-close
    tab-close-other
    tab-new
    tab-bar-new-tab
    tab-bar-close-tab-by-name)
  "Tab selection, creation, and closing commands with direct advice.")

(ert-deftest emacsvox-tab-bar-lifecycle-advice-is-directly-registered ()
  "Tab lifecycle advice uses native advice directly."
  (dolist (target emacsvox-test--tab-bar-lifecycle-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-tab-bar-alias-feedback-is-target-aware ()
  "Only the interactively invoked tab-selection alias gives feedback."
  (let ((ems--interactive-fn-name 'tab-next)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-tab-bar-speak-tab-name)
               (lambda () (push 'tab-name events))))
      (emacsvox--advice-tab-bar-switch-to-next-tab-after)
      (emacsvox--advice-tab-next-after))
    (should
     (equal
      (nreverse events)
      '((icon select-object) tab-name)))))

(ert-deftest emacsvox-tab-bar-close-by-name-uses-native-argument ()
  "Closing by name reports the explicit native NAME argument."
  (let ((ems--interactive-fn-name 'tab-bar-close-tab-by-name)
        events)
    (cl-letf (((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (let ((text (apply #'format format-string arguments)))
                   (push (list 'message text) events)
                   text)))
              ((symbol-function 'dtk-speak)
               (lambda (text) (push (list 'speak text) events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-tab-bar-close-tab-by-name-after "Research"))
    (should
     (equal
      (nreverse events)
      '((message "Closed tab Research")
        (speak "Closed tab Research")
        (icon close-object))))))

(defconst emacsvox-test--tab-switcher-after-targets
  '(tab-list
    tab-switcher
    tab-switcher-execute
    tab-switcher-prev-line
    tab-switcher-next-line
    tab-switcher-unmark
    tab-switcher-backup-unmark
    tab-switcher-delete
    tab-switcher-delete-backwards
    tab-switcher-select)
  "Emacs 31 Tab Switcher commands with direct advice.")

(ert-deftest emacsvox-tab-switcher-advice-is-directly-registered ()
  "Current Tab Switcher advice uses native advice directly."
  (dolist (target emacsvox-test--tab-switcher-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-tab-switcher-movement-is-target-aware ()
  "Only matching interactive Tab Switcher movement speaks and cues."
  (let ((ems--interactive-fn-name 'tab-switcher-next-line)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda (&rest _) (push 'line events))))
      (emacsvox--advice-tab-switcher-prev-line-after)
      (emacsvox--advice-tab-switcher-next-line-after))
    (should
     (equal
      (nreverse events)
      '((icon large-movement) line)))))

(ert-deftest emacsvox-tab-switcher-alias-feedback-is-not-duplicated ()
  "Opening the switcher through `tab-list' produces one cue."
  (let ((ems--interactive-fn-name 'tab-list)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events))))
      (emacsvox--advice-tab-switcher-after)
      (emacsvox--advice-tab-list-after))
    (should (equal events '(open-object)))))

(provide 'emacsvox-tab-bar-tests)
;;; emacsvox-tab-bar-tests.el ends here
