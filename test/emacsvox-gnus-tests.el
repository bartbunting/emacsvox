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
  "Gnus startup and group advice bypasses the compatibility bridge."
  (dolist (target emacsvox-test--gnus-startup-group-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers))))
  (dolist (entry emacsvox-test--gnus-startup-group-around-advice)
    (pcase-let ((`(,target ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :around function) ems--modern-advice-wrappers))))
  (should
   (advice-member-p
    #'emacsvox--advice-gnus-group-customize-before
    'gnus-group-customize))
  (should-not
   (gethash
    '(gnus-group-customize :before
      emacsvox--advice-gnus-group-customize-before)
    ems--modern-advice-wrappers)))

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
  "Gnus summary marking and navigation bypass the compatibility bridge."
  (dolist
      (target
       (append
        emacsvox-test--gnus-summary-marking-around-targets
        emacsvox-test--gnus-summary-navigation-around-targets))
    (let ((function
           (intern (format "emacsvox--advice-%s-around" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :around function) ems--modern-advice-wrappers))))
  (dolist (target emacsvox-test--gnus-summary-navigation-after-targets)
    (let ((function
           (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp target))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target :after function) ems--modern-advice-wrappers)))))

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

(provide 'emacsvox-gnus-tests)
;;; emacsvox-gnus-tests.el ends here
