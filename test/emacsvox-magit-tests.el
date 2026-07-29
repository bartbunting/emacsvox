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

(ert-deftest emacsvox-magit-face-mapping-conflict-is-visible ()
  "The duplicate Magit face declaration is reported with provenance."
  (let* ((diagnostic
          (voice-setup-face-mapping-diagnostic
           'magit-diff-added-highlight))
         (declarations (plist-get diagnostic :declarations)))
    (should (plist-get diagnostic :conflict))
    (should
     (equal
      (mapcar
       (lambda (record) (plist-get record :voice))
       declarations)
      '(voice-animate voice-animate-extra)))
    (should
     (equal
      (delete-dups
       (mapcar
        (lambda (record) (plist-get record :origin))
        declarations))
      '(emacsvox-magit)))))

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

(ert-deftest emacsvox-magit-blame-navigation-uses-one-native-submission ()
  "Blame content and its before/after cues are submitted together."
  (with-temp-buffer
    (insert
     (propertize
      "deadbeef" 'personality 'voice-lighten
      'after-string " Author"))
    (goto-char (point-min))
    (let (calls)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (content &rest arguments)
              (push (cons content arguments) calls)
              'submission)))
        (should
         (eq
          (emacsvox-magit-blame-speak 'large-movement)
          'submission)))
      (should (= (length calls) 1))
      (pcase-let* ((`(,content . ,arguments) (car calls))
                   (actions
                    (plist-get arguments :compatibility-actions)))
        (should (equal content "deadbeef Author"))
        (should
         (eq
          (get-text-property 0 'personality content)
          'voice-lighten))
        (should
         (equal
          (plist-get arguments :facts)
          '(:role vcs-blame-chunk :events (focus-entered))))
        (should (eq (plist-get arguments :module) 'magit))
        (should (eq (plist-get arguments :occasion) 'navigation))
        (should
         (equal
          (mapcar
           #'emacsvox-aural-compatibility-action-value actions)
          '(left large-movement)))
        (should
         (equal
          (mapcar
           #'emacsvox-aural-compatibility-action-phase actions)
          '(before after)))))))

(ert-deftest emacsvox-magit-blame-advice-adds-movement-after-content ()
  "Interactive blame navigation requests one trailing movement cue."
  (let ((ems--interactive-fn-name
         'magit-blame-next-chunk-same-commit)
        calls)
    (cl-letf
        (((symbol-function 'emacsvox-magit-blame-speak)
          (lambda (&optional icon) (push icon calls))))
      (emacsvox--advice-magit-blame-next-chunk-after)
      (emacsvox--advice-magit-blame-next-chunk-same-commit-after))
    (should (equal calls '(large-movement)))))

(ert-deftest emacsvox-magit-empty-blame-keeps-legacy-fallback ()
  "An empty blame line retains its cue and speech ordering."
  (with-temp-buffer
    (let (events)
      (cl-letf
          (((symbol-function 'emacsvox-aural-submit)
            (lambda (&rest _)
              (ert-fail "Empty blame content used native submission")))
           ((symbol-function 'emacsvox-icon)
            (lambda (icon) (push (list 'icon icon) events)))
           ((symbol-function 'tts-speak)
            (lambda (content) (push (list 'text content) events))))
        (emacsvox-magit-blame-speak 'large-movement))
      (should
       (equal
        (nreverse events)
        '((icon left) (text "") (icon large-movement)))))))

(ert-deftest emacsvox-magit-native-blame-presents-one-transaction ()
  "Blame navigation preserves voice, order, and icon policy."
  (dolist (icons-enabled '(t nil))
    (with-temp-buffer
      (insert (propertize "deadbeef" 'personality 'voice-lighten))
      (goto-char (point-min))
      (let ((emacsvox-aural-active-scheme 'default)
            (emacsvox-aural-enabled-feature-fragments nil)
            (emacsvox-aural-user-rules nil)
            (emacsvox-aural-session-rules nil)
            (emacsvox-aural-buffer-rules nil)
            (emacsvox-aural-presentation-history nil)
            (emacsvox-aural-presentation-history-limit 20)
            (emacsvox-aural--presentation-sequence 0)
            (emacsvox-aural--submission-sequence 0)
            (emacsvox-aural-plan-presented-hook nil)
            (emacsvox-use-icons icons-enabled)
            (emacsvox-aural-face-presentation-enabled t)
            (voice-lock-mode t)
            events
            submission)
        (cl-letf
            (((symbol-function 'tts-speak)
              (lambda (prepared)
                (with-temp-buffer
                  (insert prepared)
                  (tts-audio-format (point-min) (point-max)))))
             ((symbol-function 'emacsvox-queue-resource)
              (lambda (_resource) (push 'cue events)))
             ((symbol-function 'tts-voice-reset-code)
              (lambda () "RESET"))
             ((symbol-function 'tts--protocol-queue-code) #'ignore)
             ((symbol-function 'tts--protocol-queue-text)
              (lambda (text) (push (list 'text text) events)))
             ((symbol-function 'tts--protocol-silence) #'ignore))
          (setq
           submission
           (emacsvox-magit-blame-speak 'large-movement)))
        (should (emacsvox-aural-submission-p submission))
        (should
         (equal
          (nreverse events)
          (if icons-enabled
              '(cue (text "deadbeef") cue)
            '((text "deadbeef")))))
        (should (= (length emacsvox-aural-presentation-history) 1))
        (should
         (= (emacsvox-aural-presentation-record-transaction-id
             (emacsvox-aural-last-presentation))
            1))
        (let* ((plans (emacsvox-aural-submission-plans submission))
               (plan (car plans))
               (content
                (emacsvox-aural-concrete-plan-content plan)))
          (should (= (length plans) 1))
          (should
           (equal
            (mapcar
             #'emacsvox-aural-concrete-action-cue
             (emacsvox-aural-concrete-plan-before plan))
            (and icons-enabled '(left))))
          (should
           (equal
            (mapcar
             #'emacsvox-aural-concrete-action-cue
             (emacsvox-aural-concrete-plan-after plan))
            (and icons-enabled '(large-movement))))
          (should
           (eq
            (emacsvox-aural-concrete-content-voice-request content)
            'voice-lighten)))))))

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
