;;; emacsvox-gnus-tests.el --- Gnus advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Gnus advice.

;;; Code:

(require 'cl-lib)
(require 'ert)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-gnus.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

;; Verify that advice survives definition of lazily loaded Gnus commands.
(require 'gnus-cus)
(require 'gnus-msg)
(require 'gnus-srvr)
(require 'gnus-topic)

(defconst emacsvox-test--gnus-startup-group-after-targets
  '(gnus-group-suspend gnus-group-quit gnus-group-exit gnus-server-exit
    gnus-group-post-news
    gnus-group-select-group gnus-group-first-unread-group
    gnus-group-read-group
    gnus-group-prev-group gnus-group-next-group
    gnus-group-prev-unread-group gnus-group-next-unread-group
    gnus-group-get-new-news-this-group
    gnus-group-unsubscribe-current-group gnus-group-catchup-current
    gnus-group-yank-group gnus-group-list-groups gnus-topic-mode
    gnus-group-list-all-groups gnus-group-list-all-matching
    gnus-group-list-killed gnus-group-list-matching
    gnus-group-list-zombies)
  "Gnus startup and group commands with direct after advice.")

(defconst emacsvox-test--gnus-startup-group-around-advice
  '((gnus emacsvox--advice-gnus-around)
    (gnus-group-get-new-news
     emacsvox--advice-gnus-group-get-new-news-around)
    (nnheader-message-maybe
     emacsvox--advice-nnheader-message-maybe-around))
  "Gnus startup commands with direct around advice.")

(ert-deftest emacsvox-gnus-startup-group-advice-is-directly-registered ()
  "Gnus startup and group advice uses native advice directly."
  (dolist (target emacsvox-test--gnus-startup-group-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))))
  (dolist (entry emacsvox-test--gnus-startup-group-around-advice)
    (pcase-let ((`(,target ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target))))
  (should
   (advice-member-p
    #'emacsvox--advice-gnus-group-customize-before
    'gnus-group-customize)))

(ert-deftest emacsvox-gnus-startup-calls-original-once ()
  "Gnus startup silences one original call and preserves its result."
  (let ((emacsvox-speak-messages t)
        (inhibit-message nil)
        (calls 0)
        events)
    (cl-letf (((symbol-function 'dtk-speak)
               (lambda (text) (push (list 'speak text) events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push
                  (list 'message
                        (apply #'format format-string arguments))
                  events))))
      (should
       (eq
        (emacsvox--advice-gnus-around
         (lambda (&rest arguments)
           (cl-incf calls)
           (push
            (list 'original arguments
                  emacsvox-speak-messages inhibit-message)
            events)
           'started)
         1 t 'child)
        'started)))
    (should (= calls 1))
    (should
     (equal
      (nreverse events)
      '((speak "Starting gnus")
        (original (1 t child) nil t)
        (icon news)
        (message "Gnus is ready "))))))

(ert-deftest emacsvox-gnus-refresh-calls-original-once ()
  "Refreshing Gnus silences one call and preserves its result."
  (let ((emacsvox-speak-messages t)
        (inhibit-message nil)
        (calls 0)
        events)
    (cl-letf (((symbol-function 'dtk-speak)
               (lambda (text) (push (list 'speak text) events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push
                  (list 'message
                        (apply #'format format-string arguments))
                  events))))
      (should
       (eq
        (emacsvox--advice-gnus-group-get-new-news-around
         (lambda (&rest arguments)
           (cl-incf calls)
           (push
            (list 'original arguments
                  emacsvox-speak-messages inhibit-message)
            events)
           'refreshed)
         2 t)
        'refreshed)))
    (should (= calls 1))
    (should
     (equal
      (nreverse events)
      '((speak "Getting new  gnus")
        (original (2 t) nil t)
        (message "Gnus is ready ")
        (icon news))))))

(ert-deftest emacsvox-gnus-group-movement-is-target-aware ()
  "Only matching interactive group movement cues and speaks."
  (let ((ems--interactive-fn-name 'gnus-group-next-group)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events))))
      (emacsvox--advice-gnus-group-prev-group-after)
      (emacsvox--advice-gnus-group-next-group-after))
    (should
     (equal
      (nreverse events)
      '((icon select-object) speak-line)))))

(ert-deftest emacsvox-gnus-close-feedback-is-target-aware ()
  "Only the matching interactive Gnus exit emits close feedback."
  (let ((ems--interactive-fn-name 'gnus-group-exit)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'dtk-stop)
               (lambda (&rest _) (push 'stop events)))
              ((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'speak-mode-line events))))
      (emacsvox--advice-gnus-group-quit-after)
      (emacsvox--advice-gnus-group-exit-after))
    (should
     (equal
      (nreverse events)
      '((icon close-object) stop speak-mode-line)))))

(defconst emacsvox-test--gnus-summary-marking-around-targets
  '(gnus-summary-clear-mark-backward gnus-summary-clear-mark-forward
    gnus-summary-mark-as-dormant gnus-summary-mark-as-expirable
    gnus-summary-mark-as-processable
    gnus-summary-tick-article-backward
    gnus-summary-tick-article-forward)
  "Gnus summary marking commands with direct around advice.")

(defconst emacsvox-test--gnus-summary-navigation-around-targets
  '(gnus-summary-exit-no-update gnus-summary-exit
    gnus-summary-prev-subject gnus-summary-next-subject
    gnus-summary-prev-unread-subject
    gnus-summary-next-unread-subject
    gnus-summary-goto-subject)
  "Gnus summary navigation commands with direct around advice.")

(defconst emacsvox-test--gnus-summary-navigation-after-targets
  '(gnus-summary-unmark-as-processable gnus-summary-delete-article
    gnus-summary-catchup-to-here gnus-summary-catchup-from-here
    gnus-summary-select-article-buffer
    gnus-summary-catchup-and-exit
    gnus-summary-mark-as-read-forward
    gnus-summary-mark-as-read-backward
    gnus-summary-kill-same-subject-and-select
    gnus-summary-kill-same-subject
    gnus-summary-next-thread gnus-summary-prev-thread
    gnus-summary-up-thread gnus-summary-down-thread
    gnus-summary-kill-thread gnus-summary-hide-all-threads)
  "Gnus summary marking and navigation commands with direct after advice.")

(ert-deftest emacsvox-gnus-summary-navigation-advice-is-directly-registered ()
  "Gnus summary marking and navigation use native advice directly."
  (dolist
      (target
       (append
        emacsvox-test--gnus-summary-marking-around-targets
        emacsvox-test--gnus-summary-navigation-around-targets))
    (let ((function
           (intern (format "emacsvox--advice-%s-around" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))))
  (dolist (target emacsvox-test--gnus-summary-navigation-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-gnus-does-not-create-removed-unread-commands ()
  "Loading the integration does not recreate removed Gnus mark commands."
  (should-not (fboundp 'gnus-summary-mark-as-unread-forward))
  (should-not (fboundp 'gnus-summary-mark-as-unread-backward)))

(ert-deftest emacsvox-gnus-summary-marking-calls-original-once ()
  "Summary marking preserves one original call, result, and feedback."
  (with-temp-buffer
    (insert "first\nsecond\n")
    (goto-char (point-min))
    (let ((ems--interactive-fn-name 'gnus-summary-clear-mark-forward)
          (calls 0)
          events)
      (cl-letf (((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events)))
                ((symbol-function 'emacsvox-gnus-summary-speak-subject)
                 (lambda () (push 'speak-subject events))))
        (should
         (eq
          (emacsvox--advice-gnus-summary-clear-mark-forward-around
           (lambda (count)
             (cl-incf calls)
             (push (list 'original count (point)) events)
             (forward-line count)
             'marked)
           1)
          'marked)))
      (should (= calls 1))
      (should
       (equal
        (nreverse events)
        '((original 1 1) (icon mark-object) speak-subject))))))

(ert-deftest emacsvox-gnus-summary-subject-calls-original-once ()
  "Subject movement preserves one original call and its result."
  (with-temp-buffer
    (insert "first\nsecond\n")
    (goto-char (point-min))
    (let ((ems--interactive-fn-name 'gnus-summary-next-subject)
          (calls 0)
          events)
      (cl-letf (((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events)))
                ((symbol-function 'gnus-summary-article-subject)
                 (lambda () "Second subject"))
                ((symbol-function 'dtk-speak)
                 (lambda (text) (push (list 'speak text) events))))
        (should
         (eq
          (emacsvox--advice-gnus-summary-next-subject-around
           (lambda (count &optional unread)
             (cl-incf calls)
             (push (list 'original count unread (point)) events)
             (forward-line count)
             'moved)
           1 t)
          'moved)))
      (should (= calls 1))
      (should
       (equal
        (nreverse events)
        '((original 1 t 1)
          (icon select-object)
          (speak "Second subject")))))))

(ert-deftest emacsvox-gnus-summary-exit-calls-original-once ()
  "Summary exit captures the old group and preserves one original result."
  (let ((ems--interactive-fn-name 'gnus-summary-exit)
        (gnus-newsgroup-name "old.group")
        (calls 0)
        events)
    (cl-letf (((symbol-function 'gnus-group-group-name)
               (lambda () "next.group"))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'dtk-stop)
               (lambda (&rest _) (push 'stop events)))
              ((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events))))
      (should
       (eq
        (emacsvox--advice-gnus-summary-exit-around
         (lambda (&rest arguments)
           (cl-incf calls)
           (push
            (list 'original arguments gnus-newsgroup-name)
            events)
           (setq gnus-newsgroup-name "new.group")
           'exited)
         t nil)
        'exited)))
    (should (= calls 1))
    (should
     (equal
      (nreverse events)
      '((original (t nil) "old.group")
        (icon close-object) stop speak-line)))))

(ert-deftest emacsvox-gnus-summary-thread-feedback-is-target-aware ()
  "Only matching interactive thread movement cues and speaks."
  (let ((ems--interactive-fn-name 'gnus-summary-down-thread)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'emacsvox-gnus-summary-speak-subject)
               (lambda () (push 'speak-subject events))))
      (emacsvox--advice-gnus-summary-up-thread-after)
      (emacsvox--advice-gnus-summary-down-thread-after))
    (should
     (equal
      (nreverse events)
      '((icon select-object) speak-subject)))))

(defconst emacsvox-test--gnus-summary-article-after-targets
  '(gnus-summary-show-article
    gnus-summary-next-page gnus-summary-prev-page
    gnus-summary-beginning-of-article
    gnus-summary-end-of-article
    gnus-summary-prev-article gnus-summary-next-article
    gnus-summary-next-unread-article
    gnus-summary-prev-unread-article
    gnus-summary-prev-same-subject
    gnus-summary-next-same-subject
    gnus-summary-first-unread-article
    gnus-summary-goto-last-article)
  "Gnus summary article-display commands with direct after advice.")

(ert-deftest emacsvox-gnus-summary-article-advice-is-directly-registered ()
  "Gnus summary article-display advice uses native advice directly."
  (dolist (target '(gnus-summary-read-group gnus-summary-show-article))
    (let ((function
           (intern (format "emacsvox--advice-%s-around" target))))
      (should (fboundp function))
      (should (advice-member-p function target))))
  (dolist (target emacsvox-test--gnus-summary-article-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))))
  ;; Both differently named advice must coexist on this target.
  (should
   (advice-member-p
    #'emacsvox--advice-gnus-summary-show-article-around
    'gnus-summary-show-article))
  (should
   (advice-member-p
    #'emacsvox--advice-gnus-summary-show-article-after
    'gnus-summary-show-article)))

(ert-deftest emacsvox-gnus-summary-render-calls-original-once ()
  "Summary rendering disables external SHR renderers for one call."
  (let ((shr-external-rendering-functions '(external-renderer))
        (calls 0))
    (should
     (eq
      (emacsvox--advice-gnus-summary-show-article-around
       (lambda (&rest arguments)
         (cl-incf calls)
         (should-not shr-external-rendering-functions)
         (should (equal arguments '(4)))
         'rendered)
       4)
      'rendered))
    (should (= calls 1))
    (should
     (equal
      shr-external-rendering-functions
      '(external-renderer)))))

(ert-deftest emacsvox-gnus-summary-article-movement-is-target-aware ()
  "Only matching interactive article movement speaks the article."
  (let ((ems--interactive-fn-name 'gnus-summary-next-unread-article)
        events)
    (cl-letf (((symbol-function 'emacsvox-gnus-speak-article-body)
               (lambda () (push 'speak-article events))))
      (emacsvox--advice-gnus-summary-prev-unread-article-after)
      (emacsvox--advice-gnus-summary-next-unread-article-after))
    (should (equal events '(speak-article)))))

(ert-deftest emacsvox-gnus-summary-boundary-speech-is-unconditional ()
  "Article boundary commands speak even when invoked internally."
  (with-temp-buffer
    (let ((gnus-article-buffer (current-buffer))
          events)
      (cl-letf (((symbol-function 'emacsvox-speak-line)
                 (lambda () (push (current-buffer) events))))
        (emacsvox--advice-gnus-summary-beginning-of-article-after)
        (emacsvox--advice-gnus-summary-end-of-article-after))
      (should
       (equal events
              (list (current-buffer) (current-buffer)))))))

(ert-deftest emacsvox-gnus-summary-show-article-is-target-aware ()
  "Article rendering feedback is limited to interactive display."
  (with-temp-buffer
    (let ((gnus-article-buffer (current-buffer))
          (ems--interactive-fn-name 'gnus-summary-show-article)
          events)
      (cl-letf (((symbol-function 'visual-line-mode)
                 (lambda (&rest _) (push 'visual-lines events)))
                ((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events)))
                ((symbol-function 'emacsvox-hide-all-blocks-in-buffer)
                 (lambda () (push 'hide-blocks events)))
                ((symbol-function 'emacsvox-gnus-speak-article-body)
                 (lambda () (push 'speak-article events))))
        (emacsvox--advice-gnus-summary-show-article-after))
      (should
       (equal
        (nreverse events)
        '(visual-lines (icon open-object)
          hide-blocks speak-article))))))

(defconst emacsvox-test--gnus-article-after-targets
  '(gnus-article-show-summary
    gnus-article-next-page gnus-article-prev-page
    gnus-summary-button-forward
    gnus-article-goto-prev-page gnus-article-goto-next-page)
  "Current Gnus article commands with direct after advice.")

(defconst emacsvox-test--gnus-server-after-targets
  '(gnus-server-edit-server
    gnus-group-enter-server-mode gnus-browse-exit)
  "Current Gnus server commands with direct after advice.")

(ert-deftest emacsvox-gnus-article-server-advice-is-directly-registered ()
  "Gnus article and server advice uses native advice directly."
  (dolist
      (target
       (append
        emacsvox-test--gnus-article-after-targets
        emacsvox-test--gnus-server-after-targets))
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))))
  (should
   (advice-member-p
    #'emacsvox--advice-gnus-article-press-button-before
    'gnus-article-press-button))
  (should
   (advice-member-p
    #'emacsvox--advice-auth-source-do-debug-around
    'auth-source-do-debug)))

(ert-deftest emacsvox-gnus-does-not-create-obsolete-article-server-targets ()
  "Loading the integration does not recreate removed Gnus commands."
  (should-not (fboundp 'gnus-article-next-button))
  (should-not (fboundp 'gnus-server-edit-buffer)))

(ert-deftest emacsvox-gnus-button-navigation-uses-current-command ()
  "Current Gnus button navigation cues and identifies its button."
  (with-temp-buffer
    (insert-text-button "Open link" 'action #'ignore)
    (goto-char (point-min))
    (let ((ems--interactive-fn-name 'gnus-summary-button-forward)
          events)
      (cl-letf (((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events)))
                ((symbol-function 'message)
                 (lambda (format-string &rest arguments)
                   (push
                    (list
                     'message
                     (apply #'format format-string arguments))
                    events))))
        (emacsvox--advice-gnus-summary-button-forward-after))
      (should
       (equal
        (nreverse events)
        '((icon large-movement) (message "Open link")))))))

(ert-deftest emacsvox-gnus-article-page-feedback-is-target-aware ()
  "Only matching article page movement speaks the current window."
  (let ((ems--interactive-fn-name 'gnus-article-prev-page)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-current-window)
               (lambda () (push 'speak-window events))))
      (emacsvox--advice-gnus-article-next-page-after)
      (emacsvox--advice-gnus-article-prev-page-after))
    (should (equal events '(speak-window)))))

(ert-deftest emacsvox-gnus-server-feedback-is-target-aware ()
  "Only matching interactive server navigation speaks the mode line."
  (let ((ems--interactive-fn-name 'gnus-server-edit-server)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-mode-line)
               (lambda () (push 'speak-mode-line events))))
      (emacsvox--advice-gnus-browse-exit-after)
      (emacsvox--advice-gnus-server-edit-server-after))
    (should (equal events '(speak-mode-line)))))

(ert-deftest emacsvox-gnus-auth-debug-calls-original-once ()
  "Auth-source debugging preserves one silenced call and its result."
  (let ((emacsvox-speak-messages t)
        (inhibit-message nil)
        (calls 0))
    (should
     (eq
      (emacsvox--advice-auth-source-do-debug-around
       (lambda (&rest arguments)
         (cl-incf calls)
         (should-not emacsvox-speak-messages)
         (should inhibit-message)
         (should (equal arguments '("debug")))
         'debugged)
       "debug")
      'debugged))
    (should (= calls 1))))

(ert-deftest emacsvox-gnus-xoauth-calls-original-once ()
  "XOAuth credential lookup preserves one quiet call and its result."
  (let ((emacsvox-speak-messages t)
        (calls 0))
    (should
     (eq
      (emacsvox--advice-auth-source-xoauth2--file-creds-around
       (lambda (&rest arguments)
         (cl-incf calls)
         (should-not emacsvox-speak-messages)
         (should (equal arguments '("host" "user")))
         'credentials)
       "host" "user")
      'credentials))
    (should (= calls 1))))

(ert-deftest emacsvox-gnus-xoauth-advice-is-deferred ()
  "Optional XOAuth advice is installed only after its package loads."
  (should-not (fboundp 'auth-source-xoauth2--file-creds))
  (unwind-protect
      (progn
        (fset 'auth-source-xoauth2--file-creds #'ignore)
        (emacsvox-gnus--setup-xoauth2-advice)
        (should
         (advice-member-p
          #'emacsvox--advice-auth-source-xoauth2--file-creds-around
          'auth-source-xoauth2--file-creds)))
    (advice-remove
     'auth-source-xoauth2--file-creds
     #'emacsvox--advice-auth-source-xoauth2--file-creds-around)
    (fmakunbound 'auth-source-xoauth2--file-creds)))

(provide 'emacsvox-gnus-tests)
;;; emacsvox-gnus-tests.el ends here
