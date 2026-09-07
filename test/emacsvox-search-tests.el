;;; emacsvox-search-tests.el --- Search and replacement advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated search and replace advice.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(defconst emacsvox-test--replace-after-targets
  '(query-replace query-replace-regexp)
  "Replacement commands using generated native after advice.")

(defconst emacsvox-test--search-after-targets
  '(search-forward search-backward
    word-search-forward word-search-backward
    occur-prev occur-next occur-mode-goto-occurrence)
  "Non-incremental search commands using generated native after advice.")

(defconst emacsvox-test--isearch-after-targets
  '(isearch-yank-word isearch-yank-kill isearch-yank-line
    isearch-ring-advance isearch-ring-retreat
    isearch-ring-advance-edit isearch-ring-retreat-edit)
  "Incremental search commands using generated native after advice.")

(defconst emacsvox-test--replace-direct-advice
  '((perform-replace :around emacsvox--advice-perform-replace-around)
    (replace-highlight :after emacsvox--advice-replace-highlight-after)
    (isearch-search :after emacsvox--advice-isearch-search-after)
    (isearch-delete-char :after emacsvox--advice-isearch-delete-char-after)
    (isearch-toggle-case-fold :after
     emacsvox--advice-isearch-toggle-case-fold-after)
    (isearch-toggle-regexp :after
     emacsvox--advice-isearch-toggle-regexp-after)
    (isearch-occur :after emacsvox--advice-isearch-occur-after)
    (occur-mode-display-occurrence :after
     emacsvox--advice-occur-mode-display-occurrence-after))
  "Search and replacement functions using individually defined native advice.")

(ert-deftest emacsvox-replace-advice-is-directly-registered ()
  "Migrated replacement advice uses native advice directly."
  (dolist (target emacsvox-test--replace-after-targets)
    (let ((function (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp function))
      (should (advice-member-p function target))))
  (dolist (target emacsvox-test--search-after-targets)
    (let ((function (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp function))
      (should (advice-member-p function target))))
  (dolist (target emacsvox-test--isearch-after-targets)
    (let ((function (intern (format "emacsvox--advice-%s-after" target))))
      (should (fboundp function))
      (should (advice-member-p function target))))
  (dolist (entry emacsvox-test--replace-direct-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target)))))

(ert-deftest emacsvox-query-replace-feedback-is-interactive-only ()
  "Query replacement completion is announced once only when interactive."
  (let ((ems--interactive-fn-name 'query-replace)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push icon events))))
      (emacsvox--advice-query-replace-regexp-after)
      (emacsvox--advice-query-replace-after)
      (emacsvox--advice-query-replace-after))
    (should (equal events '(task-done)))))

(ert-deftest emacsvox-perform-replace-preserves-silenced-call ()
  "Replacement execution is silenced and preserves arguments and result."
  (let ((emacsvox-speak-messages t)
        (inhibit-message nil)
        observed)
    (should
     (eq
      (emacsvox--advice-perform-replace-around
       (lambda (&rest arguments)
         (setq observed
               (list arguments emacsvox-speak-messages inhibit-message))
         'replace-result)
       'first 'second)
      'replace-result))
    (should (equal observed '((first second) nil t)))
    (should emacsvox-speak-messages)
    (should-not inhibit-message)))

(ert-deftest emacsvox-replace-highlight-always-speaks-line ()
  "Replacement highlighting speaks its line for every invocation."
  (let (events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda (&rest _) (push 'speak-line events))))
      (emacsvox--advice-replace-highlight-after))
    (should (equal events '(speak-line)))))

(ert-deftest emacsvox-nonincremental-search-preserves-feedback-order ()
  "Interactive search speaks its destination before the hit icon."
  (let ((ems--interactive-fn-name 'search-forward)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda (&rest _) (push 'speak-line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-search-backward-after)
      (emacsvox--advice-search-forward-after)
      (emacsvox--advice-search-forward-after))
    (should
     (equal
      (nreverse events)
      '(speak-line (icon search-hit))))))

(ert-deftest emacsvox-isearch-search-distinguishes-hit-and-miss ()
  "Incremental search emits miss or highlighted-hit feedback from its state."
  (with-temp-buffer
    (insert "alpha beta")
    (goto-char 1)
    (let ((isearch-success nil)
          (isearch-other-end 6)
          events)
      (cl-letf (((symbol-function 'emacsvox-icon)
                 (lambda (icon) (push (list 'icon icon) events)))
                ((symbol-function 'sit-for) (lambda (&rest _) t))
                ((symbol-function 'tts-speak)
                 (lambda (text)
                   (push
                    (list 'speak
                          (substring-no-properties text)
                          (get-text-property 0 'personality text))
                    events))))
        (emacsvox--advice-isearch-search-after)
        (setq isearch-success t)
        (emacsvox--advice-isearch-search-after))
      (should
       (equal
        (nreverse events)
        `((icon search-miss)
          (icon search-hit)
          (speak "alpha beta" ,voice-bolden))))
      (should-not (get-text-property 1 'personality)))))

(ert-deftest emacsvox-isearch-exit-and-quit-restore-message-preference ()
  "Real Isearch exit and abort preserve both preference value and locality."
  (let ((original-default (default-value 'emacsvox-speak-messages))
        (emacsvox-isearch--message-states nil)
        (isearch-lazy-highlight nil))
    (unwind-protect
        (cl-letf (((symbol-function 'emacsvox-icon) #'ignore)
                  ((symbol-function 'tts-speak) #'ignore)
                  ((symbol-function 'tts-notify) #'ignore))
          (dolist (value '(nil t))
            (set-default 'emacsvox-speak-messages value)
            (dolist (local '(nil t))
              (dolist (lazy-count '(nil t))
                (dolist (abort '(nil t))
                  (save-window-excursion
                    (with-temp-buffer
                      (switch-to-buffer (current-buffer))
                      (insert "alpha beta")
                      (goto-char (point-min))
                      (when local (setq-local emacsvox-speak-messages value))
                      (let ((isearch-lazy-count lazy-count))
                        (unwind-protect
                            (progn
                              (isearch-mode t)
                              (isearch-yank-string "alpha")
                              (should (eq emacsvox-speak-messages lazy-count))
                              (should (eq (default-value 'emacsvox-speak-messages) value))
                              (if abort
                                  (condition-case nil (isearch-abort) (quit nil))
                                (isearch-exit))
                              (should (eq emacsvox-speak-messages value))
                              (should (eq (local-variable-p 'emacsvox-speak-messages) local))
                              (should-not emacsvox-isearch--message-states))
                          (when isearch-mode (isearch-done t)))))))))))
      (set-default 'emacsvox-speak-messages original-default))))

(ert-deftest emacsvox-isearch-suspension-and-nested-search-restore-state ()
  "Suspending Isearch restores the preference until the outer search resumes."
  (let ((emacsvox-isearch--message-states nil)
        (isearch-lazy-highlight nil)
        (isearch-lazy-count t))
    (cl-letf (((symbol-function 'emacsvox-icon) #'ignore)
              ((symbol-function 'tts-speak) #'ignore)
              ((symbol-function 'tts-notify) #'ignore))
      (save-window-excursion
        (with-temp-buffer
          (switch-to-buffer (current-buffer))
          (setq-local emacsvox-speak-messages nil)
          (unwind-protect
              (progn
                (isearch-mode t)
                (should emacsvox-speak-messages)
                (with-isearch-suspended
                 (should-not emacsvox-speak-messages)
                 (should-not emacsvox-isearch--message-states)
                 (isearch-mode t)
                 (should emacsvox-speak-messages)
                 (isearch-done)
                 (should-not emacsvox-speak-messages))
                (should isearch-mode)
                (should emacsvox-speak-messages)
                (isearch-done)
                (should-not emacsvox-speak-messages)
                (should (local-variable-p 'emacsvox-speak-messages))
                (should-not emacsvox-isearch--message-states))
            (when isearch-mode (isearch-done t))))))))

(ert-deftest emacsvox-isearch-restores-owner-after-buffer-switch-or-death ()
  "Ending in another buffer restores only the owner and tolerates its death."
  (let ((emacsvox-isearch--message-states nil)
        (isearch-lazy-count t)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon) (lambda (icon) (push icon events)))
              ((symbol-function 'tts-speak) #'ignore))
      (with-temp-buffer
        (setq-local emacsvox-speak-messages nil)
        (let ((owner (current-buffer)))
          (emacsvox-isearch-setup)
          (with-temp-buffer
            (setq-local emacsvox-speak-messages 'other)
            (emacsvox-isearch-teardown)
            (should (eq emacsvox-speak-messages 'other)))
          (should-not emacsvox-speak-messages)
          (emacsvox-isearch-setup)
          (kill-buffer owner)
          (emacsvox-isearch-teardown)
          (emacsvox-isearch-teardown)
          (should-not emacsvox-isearch--message-states)))
      (should (equal (nreverse events)
                     '(open-object close-object open-object close-object))))))

(ert-deftest emacsvox-isearch-feedback-errors-preserve-preference ()
  "Opening and closing speech failures do not strand temporary preferences."
  (let ((emacsvox-isearch--message-states nil)
        (isearch-lazy-count t))
    (with-temp-buffer
      (setq-local emacsvox-speak-messages nil)
      (cl-letf (((symbol-function 'emacsvox-icon) #'ignore)
                ((symbol-function 'tts-speak) (lambda (&rest _) (error "speech failed"))))
        (should-error (emacsvox-isearch-setup)))
      (should-not emacsvox-speak-messages)
      (should-not emacsvox-isearch--message-states)
      (cl-letf (((symbol-function 'emacsvox-icon) #'ignore)
                ((symbol-function 'tts-speak) #'ignore))
        (emacsvox-isearch-setup))
      (cl-letf (((symbol-function 'emacsvox-icon) (lambda (&rest _) (error "icon failed"))))
        (should-error (emacsvox-isearch-teardown)))
      (should-not emacsvox-speak-messages)
      (should-not emacsvox-isearch--message-states))))

(ert-deftest emacsvox-isearch-yank-feedback-is-target-aware ()
  "Only the matching interactive isearch yank command emits feedback."
  (let ((ems--interactive-fn-name 'isearch-yank-word)
        (isearch-string "search text")
        events)
    (cl-letf (((symbol-function 'tts-speak)
               (lambda (text)
                 (push
                  (list 'speak
                        (substring-no-properties text)
                        (get-text-property 0 'personality text))
                  events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-isearch-yank-line-after)
      (emacsvox--advice-isearch-yank-word-after))
    (should
     (equal
      (nreverse events)
      `((speak "search text" ,voice-bolden)
        (icon yank-object))))))

(ert-deftest emacsvox-isearch-toggle-feedback-reflects-state ()
  "Isearch toggle advice preserves icon and spoken state announcements."
  (let ((isearch-case-fold-search t)
        (isearch-regexp t)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'tts-speak)
               (lambda (text) (push (list 'speak text) events))))
      (emacsvox--advice-isearch-toggle-case-fold-after)
      (emacsvox--advice-isearch-toggle-regexp-after))
    (should
     (equal
      (nreverse events)
      '((icon off)
        (speak " Case is  not significant in search")
        (icon on)
        (speak "Regexp search"))))))

(ert-deftest emacsvox-occur-navigation-feedback-is-target-aware ()
  "Only the matching Occur navigation command speaks and cues its line."
  (let ((ems--interactive-fn-name 'occur-next)
        events)
    (cl-letf (((symbol-function 'emacsvox-speak-line)
               (lambda () (push 'speak-line events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-occur-prev-after)
      (emacsvox--advice-occur-next-after))
    (should
     (equal
      (nreverse events)
      '(speak-line (icon large-movement))))))

(ert-deftest emacsvox-occur-display-feedback-preserves-order ()
  "Displaying an occurrence cues its window before the status message."
  (let ((ems--interactive-fn-name 'occur-mode-display-occurrence)
        events)
    (cl-letf (((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events)))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push
                  (list 'message
                        (apply #'format format-string arguments))
                  events))))
      (emacsvox--advice-occur-mode-display-occurrence-after))
    (should
     (equal
      (nreverse events)
      '((icon open-object)
        (message "Displayed occurrence in other window"))))))

(provide 'emacsvox-search-tests)
;;; emacsvox-search-tests.el ends here
