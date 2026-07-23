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

(provide 'emacsvox-gnus-tests)
;;; emacsvox-gnus-tests.el ends here
