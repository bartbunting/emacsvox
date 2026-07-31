;;; emacsvox-message-tests.el --- Message advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated message advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(defconst emacsvox-test--message-direct-advice
  '((momentary-string-display :around
     emacsvox--advice-momentary-string-display-around)
    (minibuffer-message :around
     emacsvox--advice-minibuffer-message-around)
    (set-minibuffer-message :around
     emacsvox--advice-set-minibuffer-message-around)
    (message :around emacsvox--advice-message-around)
    (display-message-or-buffer :around
     emacsvox--advice-display-message-or-buffer-around))
  "Message functions using individually defined native advice.")

(ert-deftest emacsvox-message-advice-is-directly-registered ()
  "Migrated message advice uses native advice directly."
  (dolist (entry emacsvox-test--message-direct-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-message-advice-calls-original-once ()
  "A new message calls once, preserves its result, and emits ordered feedback."
  (let ((emacsvox-last-message nil)
        (emacsvox-speak-messages t)
        (ems--message-filter "\\`never-match\\'")
        (minibuffer-message-overlay nil)
        (inhibit-message nil)
        (tts-punctuation-mode 'all)
        (calls 0)
        events)
    (cl-letf (((symbol-function 'current-message)
               (lambda () "  Hello world  "))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'tts-notify)
               (lambda (text &optional mode)
                 (push (list 'notify text mode) events))))
      (should
       (eq
        (emacsvox--advice-message-around
         (lambda (&rest arguments)
           (cl-incf calls)
           (push (list 'original arguments) events)
           'message-result)
         "Hello %s" "world")
        'message-result)))
    (should (= calls 1))
    (should
     (equal
      (nreverse events)
      '((original ("Hello %s" "world"))
        (icon key)
        (notify "Hello world" dont-log))))
    (should (equal emacsvox-last-message "Hello world"))))

(ert-deftest emacsvox-message-advice-throttles-duplicates ()
  "A duplicate message preserves the original call without repeated feedback."
  (let ((emacsvox-last-message "Repeated")
        (emacsvox-speak-messages t)
        (ems--message-filter "\\`never-match\\'")
        (minibuffer-message-overlay nil)
        (inhibit-message nil)
        (calls 0)
        feedback)
    (cl-letf (((symbol-function 'current-message)
               (lambda () "Repeated"))
              ((symbol-function 'emacsvox-icon)
               (lambda (&rest _) (setq feedback t)))
              ((symbol-function 'tts-notify)
               (lambda (&rest _) (setq feedback t))))
      (should
       (eq
        (emacsvox--advice-minibuffer-message-around
         (lambda (&rest _)
           (cl-incf calls)
           'message-result)
         "Repeated")
        'message-result)))
    (should (= calls 1))
    (should-not feedback)))

(ert-deftest emacsvox-message-advice-honors-suppression ()
  "Inhibited message speech calls the original without inspecting output."
  (let ((emacsvox-speak-messages t)
        (minibuffer-message-overlay nil)
        (inhibit-message t)
        (calls 0)
        inspected)
    (cl-letf (((symbol-function 'current-message)
               (lambda () (setq inspected t)))
              ((symbol-function 'tts-notify)
               (lambda (&rest _) (setq inspected t))))
      (should
       (eq
        (emacsvox--advice-set-minibuffer-message-around
         (lambda (&rest _)
           (cl-incf calls)
           'message-result)
         "Quiet")
        'message-result)))
    (should (= calls 1))
    (should-not inspected)))

(ert-deftest emacsvox-command-quit-submits-one-replaceable-presentation ()
  "A command quit displays quietly and presents one bounded cue and message."
  (let ((emacsvox-last-message nil)
        (emacsvox-speak-messages t)
        (tts-speaker-process 'main-speaker)
        events
        submission)
    (cl-letf
        (((symbol-function 'message)
          (lambda (&rest arguments)
            (push
             (list 'message arguments emacsvox-speak-messages)
             events)))
         ((symbol-function 'tts-notify-process)
          (lambda () 'notification-speaker))
         ((symbol-function 'emacsvox-icon)
          (lambda (icon) (push (list 'standalone-icon icon) events)))
         ((symbol-function 'tts-notify)
          (lambda (text &rest _)
            (push (list 'standalone-notify text) events)))
         ((symbol-function 'emacsvox-aural-submit)
          (lambda (content &rest arguments)
            (setq
             submission
             (list content arguments tts-speaker-process))
            (push 'submission events))))
      (emacsvox-error-handler '(quit) nil nil))
    (should
     (equal
      (nreverse events)
      '((message ("Quit") nil) submission)))
    (pcase-let ((`(,content ,arguments ,speaker) submission))
      (should (equal content "Quit"))
      (should-not (plist-get arguments :facts))
      (should (eq (plist-get arguments :module) 'core))
      (should (eq (plist-get arguments :occasion) 'notification))
      (should (eq (plist-get arguments :delivery-policy) 'replaceable))
      (should (eq (plist-get arguments :replacement-key) 'command-quit))
      (should (eq speaker 'notification-speaker))
      (let ((actions (plist-get arguments :compatibility-actions)))
        (should (= (length actions) 1))
        (should
         (eq
          (emacsvox-aural-compatibility-action-phase (car actions))
          'before))
        (should
         (eq
          (emacsvox-aural-compatibility-action-kind (car actions))
          'legacy-icon))
        (should
         (eq
          (emacsvox-aural-compatibility-action-value (car actions))
          'warn-user))))
    (should (equal emacsvox-last-message "Quit"))))

(ert-deftest emacsvox-command-error-submits-operation-failure ()
  "A genuine command error carries failure semantics in one presentation."
  (let ((emacsvox-speak-messages t)
        (tts-speaker-process 'main-speaker)
        submission)
    (cl-letf
        (((symbol-function 'message) #'ignore)
         ((symbol-function 'tts-notify-process)
          (lambda () 'notification-speaker))
         ((symbol-function 'emacsvox-aural-submit)
          (lambda (content &rest arguments)
            (setq
             submission
             (list content arguments tts-speaker-process)))))
      (emacsvox-error-handler '(user-error "Broken") nil nil))
    (pcase-let ((`(,content ,arguments ,speaker) submission))
      (should (equal content "Broken"))
      (should
       (equal
        (plist-get arguments :facts)
        '(:events (operation-failed))))
      (should (eq speaker 'notification-speaker)))))

(ert-deftest emacsvox-repeated-command-quits-share-replacement-boundary ()
  "Repeated quits use one stable boundary that delivery can coalesce."
  (let ((emacsvox-speak-messages t)
        submissions)
    (cl-letf
        (((symbol-function 'message) #'ignore)
         ((symbol-function 'tts-notify-process)
          (lambda () 'notification-speaker))
         ((symbol-function 'emacsvox-aural-submit)
          (lambda (_content &rest arguments)
            (push
             (list
              (plist-get arguments :delivery-policy)
              (plist-get arguments :replacement-key))
             submissions))))
      (dotimes (_ 20)
        (emacsvox-error-handler '(quit) nil nil)))
    (should
     (equal
      submissions
      (make-list 20 '(replaceable command-quit))))))

(ert-deftest emacsvox-command-error-falls-back-to-plain-notification ()
  "A presentation failure retains spoken error feedback without another cue."
  (let ((emacsvox-speak-messages t)
        notifications)
    (cl-letf
        (((symbol-function 'message) #'ignore)
         ((symbol-function 'emacsvox-aural-submit)
          (lambda (&rest _) (error "Presentation failed")))
         ((symbol-function 'tts-notify)
          (lambda (text &optional mode)
            (push (list text mode) notifications))))
      (emacsvox-error-handler '(quit) nil nil))
    (should
     (equal notifications '(("Quit" dont-log))))))

(ert-deftest emacsvox-display-message-or-buffer-announces-buffer-result ()
  "A displayed buffer is announced after one call and returned unchanged."
  (let ((buffer (generate-new-buffer " *emacsvox-message-result*"))
        (emacsvox-speak-messages t)
        (minibuffer-message-overlay nil)
        (inhibit-message t)
        (calls 0)
        events)
    (unwind-protect
        (cl-letf (((symbol-function 'tts-notify)
                   (lambda (text &rest _)
                     (push (list 'notify text) events))))
          (should
           (eq
            (emacsvox--advice-display-message-or-buffer-around
             (lambda (&rest arguments)
               (cl-incf calls)
               (push (list 'original arguments) events)
               buffer)
             "Long message" "*Long Message*")
            buffer))
          (should (= calls 1))
          (should
           (equal
            (nreverse events)
            '((original ("Long message" "*Long Message*"))
              (notify
               "Displayed message in buffer  *Long Message*")))))
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))))

(ert-deftest emacsvox-momentary-display-preserves-silenced-call ()
  "Momentary text is announced before one silenced original call."
  (let ((emacsvox-speak-messages t)
        (inhibit-message nil)
        (calls 0)
        events)
    (cl-letf (((symbol-function 'tts-notify)
               (lambda (text &rest _)
                 (push
                  (list 'notify text emacsvox-speak-messages
                        inhibit-message)
                  events))))
      (should
       (eq
        (emacsvox--advice-momentary-string-display-around
         (lambda (&rest arguments)
           (cl-incf calls)
           (push
            (list 'original arguments
                  emacsvox-speak-messages inhibit-message)
            events)
           'momentary-result)
         "Help" 4 ?q "Exit")
        'momentary-result)))
    (should (= calls 1))
    (should
     (equal
      (nreverse events)
      '((notify "Help Press q to exit" nil t)
        (original ("Help" 4 113 "Exit") nil t))))
    (should emacsvox-speak-messages)
    (should-not inhibit-message)))

(provide 'emacsvox-message-tests)
;;; emacsvox-message-tests.el ends here
