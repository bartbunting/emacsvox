;;; emacsvox-magit-tests.el --- Magit advice tests -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'package)
(package-initialize)
(require 'magit)
(require 'magit-blame)
(require 'magit-files)
(require 'git-rebase)

(load
 (expand-file-name
  "../lisp/emacsvox-magit.el"
  (file-name-directory (or load-file-name buffer-file-name)))
 nil nil)

(ert-deftest emacsvox-magit-current-targets-exist ()
  "Every retained Magit advice target exists."
  (dolist (target emacsvox-magit--simple-advice-targets)
    (should (fboundp target)))
  (should (fboundp 'magit-diff-show-or-scroll-up))
  (should (fboundp 'git-rebase-squash)))

(ert-deftest emacsvox-magit-removed-targets-are-not-recreated ()
  "Do not install phantom advice for removed Magit commands."
  (dolist
      (target
       '(magit-mark-item
         magit-ignore-file
         magit-ignore-item
         magit-ignore-item-locally
         magit-stage-file
         magit-unstage-file
         magit-blame-toggle-headings))
    (should-not (fboundp target))))

(ert-deftest emacsvox-magit-advice-is-directly-registered ()
  "Magit advice bypasses the compatibility bridge."
  (dolist (target emacsvox-magit--simple-advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (advice-member-p function target))
      (should-not
       (gethash (list target :after function)
                ems--modern-advice-wrappers))))
  (should
   (advice-member-p
    #'emacsvox--advice-magit-diff-show-or-scroll-up-around
    'magit-diff-show-or-scroll-up))
  (should
   (advice-member-p
    #'emacsvox--advice-git-rebase-squash-after
    'git-rebase-squash)))

(ert-deftest emacsvox-magit-diff-scroll-calls-original-once ()
  "Diff scrolling calls once, preserves its result, and announces motion."
  (with-temp-buffer
    (insert "a\nb")
    (goto-char (point-min))
    (let ((ems--interactive-fn-name 'magit-diff-show-or-scroll-up)
          (calls 0)
          events)
      (cl-letf (((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push icon events)))
                ((symbol-function 'emacsvox-speak-line)
                 (lambda () (push 'line events))))
        (should
         (eq
          'scrolled
          (emacsvox--advice-magit-diff-show-or-scroll-up-around
           (lambda ()
             (cl-incf calls)
             (forward-line 1)
             'scrolled)))))
      (should (= calls 1))
      (should (equal (nreverse events) '(scroll line))))))

(ert-deftest emacsvox-magit-diff-scroll-noninteractive-calls-once ()
  "A noninteractive diff call has no duplicate invocation."
  (let ((calls 0)
        (ems--interactive-fn-name nil))
    (should
     (eq
      'result
      (emacsvox--advice-magit-diff-show-or-scroll-up-around
       (lambda () (cl-incf calls) 'result))))
    (should (= calls 1))))

(provide 'emacsvox-magit-tests)
;;; emacsvox-magit-tests.el ends here
