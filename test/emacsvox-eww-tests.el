;;; emacsvox-eww-tests.el --- EWW advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated EWW advice.

;;; Code:

(require 'cl-lib)
(require 'ert)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-eww.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--eww-ui-after-targets
  '(eww-up-url eww-top-url eww-next-url eww-previous-url
    eww-back-url eww-forward-url
    eww eww-open-in-new-buffer eww-reload eww-open-file
    eww-add-bookmark eww-beginning-of-text eww-end-of-text
    eww-bookmark-browse eww-bookmark-kill eww-bookmark-yank
    eww-list-bookmarks eww-next-bookmark eww-previous-bookmark
    eww-change-select eww-toggle-checkbox eww-submit
    shr-next-link shr-previous-link
    eww-list-buffers eww-buffer-kill eww-buffer-select
    eww-buffer-show-next eww-buffer-show-previous
    eww-restore-history)
  "EWW navigation and UI targets expected to use direct native advice.")

(ert-deftest emacsvox-eww-ui-advice-is-directly-registered ()
  "EWW navigation and UI advice bypasses the compatibility bridge."
  (dolist (target emacsvox-test--eww-ui-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-eww-does-not-create-obsolete-quit-command ()
  "Loading the integration does not recreate removed `eww-quit'."
  (should-not (fboundp 'eww-quit)))

(ert-deftest emacsvox-eww-url-navigation-feedback-is-target-aware ()
  "Only matching EWW URL navigation cues and speaks the header."
  (let ((ems--interactive-fn-name 'eww-forward-url)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-header-line)
               (lambda () (push 'speak-header events))))
      (emacsvox--advice-eww-back-url-after)
      (emacsvox--advice-eww-forward-url-after))
    (should
     (equal
      (nreverse events)
      '((icon open-object) speak-header)))))

(ert-deftest emacsvox-eww-open-feedback-is-target-aware ()
  "Only the matching EWW open command emits its cue."
  (let ((ems--interactive-fn-name 'eww-open-file)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events))))
      (emacsvox--advice-eww-after "https://example.test")
      (emacsvox--advice-eww-open-file-after "page.html"))
    (should (equal events '(open-object)))))

(ert-deftest emacsvox-eww-bookmark-movement-keeps-unconditional-speech ()
  "Bookmark movement always speaks, but only interactive movement cues."
  (let ((ems--interactive-fn-name 'eww-next-bookmark)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events))))
      (emacsvox--advice-eww-previous-bookmark-after)
      (emacsvox--advice-eww-next-bookmark-after))
    (should
     (equal
      (nreverse events)
      '(speak-line (icon select-object) speak-line)))))

(ert-deftest emacsvox-eww-link-navigation-preserves-feedback ()
  "Interactive link movement selects an icon and speaks the link."
  (with-temp-buffer
    (insert (propertize "link" 'help-echo "Link"))
    (goto-char (point-min))
    (let ((ems--interactive-fn-name 'shr-next-link)
          (emacsvox-we-url-executor nil)
          (emacsvox-eww-url-at-point
           (lambda () "https://reddit.com/r/emacs"))
          events)
      (cl-letf (((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events)))
                ((symbol-function 'emacsvox-speak-region)
                 (lambda (start end)
                   (push (list 'speak-region start end) events))))
        (emacsvox--advice-shr-next-link-after))
      (should
       (equal
        (nreverse events)
        '((icon item) (speak-region 1 5)))))))

(ert-deftest emacsvox-eww-buffer-select-feedback-preserves-order ()
  "Selecting an EWW buffer cues, speaks the mode line, then opens."
  (let ((ems--interactive-fn-name 'eww-buffer-select)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'speak-mode-line events))))
      (emacsvox--advice-eww-buffer-select-after))
    (should
     (equal
      (nreverse events)
      '((icon select-object) speak-mode-line (icon open-object))))))

(ert-deftest emacsvox-eww-restore-history-refreshes-caches ()
  "Restoring EWW history always invalidates and rebuilds DOM caches."
  (let ((emacsvox-eww-cache-updated t)
        prepared)
    (cl-letf (((symbol-function 'emacsvox-eww-prepare-eww)
               (lambda () (setq prepared t))))
      (emacsvox--advice-eww-restore-history-after nil))
    (should-not emacsvox-eww-cache-updated)
    (should prepared)))

(provide 'emacsvox-eww-tests)
;;; emacsvox-eww-tests.el ends here
