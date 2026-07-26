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
  "Magit advice uses native advice directly."
  (dolist (target emacsvox-magit--simple-advice-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (advice-member-p function target))))
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

(ert-deftest emacsvox-magit-stage-facts-express-intent ()
  "Staging and section visibility have explicit semantic facts."
  (should
   (equal
    (emacsvox-magit-section-facts
     'magit-stage '(:type file :hidden nil))
    '(:role vcs-section
      :section-kind file
      :events (entry-staged)
      :states (staged)
      :visibility expanded)))
  (should
   (equal
    (emacsvox-magit-section-facts
     'magit-section-toggle
     '(:type hunk :hidden t)
     'visibility-changed)
    '(:role vcs-section
      :section-kind hunk
      :events (visibility-changed)
      :visibility folded))))

(ert-deftest emacsvox-magit-feedback-shares-semantic-context ()
  "The compatibility cue and line speech share one Magit submission."
  (let (events)
    (cl-letf
        (((symbol-function 'emacsvox-icon)
          (lambda (icon)
            (push
             (list icon emacsvox-aural-submission-facts
                   emacsvox-aural-submission-occasion)
             events)))
         ((symbol-function 'emacsvox-speak-line)
          (lambda ()
            (push
             (list 'line emacsvox-aural-submission-facts)
             events))))
      (emacsvox-magit-present-line
       'select-object 'state-change
       'magit-file-unstage '(:type file :hidden nil)))
    (should
     (equal
      (nreverse events)
      '((select-object
         (:role vcs-section :section-kind file
          :events (entry-unstaged) :states (unstaged)
          :visibility expanded)
         state-change)
        (line
         (:role vcs-section :section-kind file
          :events (entry-unstaged) :states (unstaged)
          :visibility expanded)))))))

(ert-deftest emacsvox-magit-view-and-process-facts-express-intent ()
  "Magit view lifecycle and process completion use distinct semantics."
  (should
   (equal
    (emacsvox-magit-view-facts 'diff 'vcs-diff-scrolled)
    '(:role vcs-view :vcs-view-kind diff
      :events (vcs-diff-scrolled))))
  (should
   (equal
    (emacsvox-magit-process-facts t)
    '(:role vcs-process :events (operation-failed)))))

(ert-deftest emacsvox-magit-diff-feedback-has-view-context ()
  "Diff scrolling keeps its compatibility output inside one view submission."
  (with-temp-buffer
    (insert "a\nb")
    (goto-char (point-min))
    (let ((ems--interactive-fn-name 'magit-diff-show-or-scroll-up)
          events)
      (cl-letf
          (((symbol-function 'emacsvox-icon)
            (lambda (icon)
              (push
               (list icon emacsvox-aural-submission-facts
                     emacsvox-aural-submission-occasion)
               events)))
           ((symbol-function 'emacsvox-speak-line)
            (lambda ()
              (push
               (list 'line emacsvox-aural-submission-facts)
               events))))
        (emacsvox--advice-magit-diff-show-or-scroll-up-around
         (lambda () (forward-line 1))))
      (should
       (equal
        (nreverse events)
        '((scroll
           (:role vcs-view :vcs-view-kind diff
            :events (vcs-diff-scrolled))
           navigation)
          (line
           (:role vcs-view :vcs-view-kind diff
            :events (vcs-diff-scrolled)))))))))

(provide 'emacsvox-magit-tests)
;;; emacsvox-magit-tests.el ends here
