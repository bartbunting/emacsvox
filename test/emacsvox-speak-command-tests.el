;;; emacsvox-speak-command-tests.el --- Core reading command contracts -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Behavior coverage for commands extracted from the core reading library.

;;; Code:
(require 'cl-lib)
(require 'ert)
(require 'emacsvox-advice)

(ert-deftest emacsvox-speak-completion-graphical-candidates-and-return ()
  "Read real completion candidates, navigate with Space and return with C-o."
  (skip-unless (display-graphic-p))
  (save-window-excursion
    (let ((reference (generate-new-buffer " *reading completion reference*"))
          (previous-completions (get-buffer "*Completions*"))
          spoken)
      (unwind-protect
          (cl-letf (((symbol-function 'tts-speak)
                     (lambda (text) (push (substring-no-properties text) spoken)))
                    ((symbol-function 'emacsvox-icon) #'ignore)
                    ((symbol-function 'emacsvox-speak-line) #'ignore))
            (switch-to-buffer reference)
            (insert "draft")
            (with-output-to-temp-buffer "*Completions*"
              (display-completion-list '("alpha" "beta")))
            (let ((window (get-buffer-window "*Completions*")))
              (should (window-live-p window))
              (with-selected-window window
                (setq-local completion-reference-buffer nil)
                (goto-char (point-min))
                (next-completion 1)
                (should (equal (emacsvox-get-current-completion) "alpha"))
                (call-interactively (key-binding " "))
                (should (equal (emacsvox-get-current-completion) "beta"))
                (should (equal (car spoken) "beta"))
                (setq-local completion-reference-buffer reference)
                (should (eq (key-binding (kbd "C-o"))
                            #'emacsvox-switch-to-reference-buffer))
                (call-interactively (key-binding (kbd "C-o")))
                (should (eq (current-buffer) reference))
                (should (equal (buffer-string) "draft")))))
        (unless previous-completions
          (when (get-buffer "*Completions*") (kill-buffer "*Completions*")))
        (kill-buffer reference)))))

(ert-deftest emacsvox-speak-notification-history-retains-newest-lines ()
  "Keep the newest history entries and recreate a killed history buffer."
  (let ((emacsvox-notifications-buffer (generate-new-buffer " *history test*")))
    (unwind-protect
        (progn
          (dotimes (index (+ emacsvox-notifications-max 3))
            (emacsvox-log-notification (number-to-string index)))
          (emacsvox-notifications-truncate)
          (with-current-buffer emacsvox-notifications-buffer
            (should (= (count-lines (point-min) (point-max))
                       emacsvox-notifications-max))
            (should (string-prefix-p "3\n" (buffer-string))))
          (kill-buffer emacsvox-notifications-buffer)
          (cl-letf (((symbol-function 'emacsvox--notifications-init)
                     (lambda () (generate-new-buffer " *history replacement*"))))
            (emacsvox-log-notification "new history"))
          (with-current-buffer emacsvox-notifications-buffer
            (should (equal (buffer-string) "new history\n"))))
      (when (buffer-live-p emacsvox-notifications-buffer)
        (kill-buffer emacsvox-notifications-buffer)))))

(ert-deftest emacsvox-speak-message-cache-replay-preserves-text ()
  "Interactive cached replay also makes the text available for yanking."
  (let ((emacsvox-last-message "cached message")
        (current-prefix-arg '(4))
        (kill-ring nil)
        spoken)
    (cl-letf (((symbol-function 'tts-speak) (lambda (text) (setq spoken text)))
              ((symbol-function 'called-interactively-p) (lambda (&rest _) t)))
      (funcall-interactively #'emacsvox-speak-message-again t)
      (should (equal spoken "cached message"))
      (should (equal (car kill-ring) "cached message")))))

(ert-deftest emacsvox-speak-pip-uses-available-notification-service ()
  "Use Piper when loaded and the notification stream otherwise."
  (let ((original-featurep (symbol-function 'featurep))
        available spoken)
    (cl-letf (((symbol-function 'pip-speak)
               (lambda (text) (push (cons 'piper text) spoken)))
              ((symbol-function 'tts-notify)
               (lambda (text) (push (cons 'notification text) spoken)))
              ((symbol-function 'featurep)
               (lambda (feature &optional subfeature)
                 (if (eq feature 'pip) available
                   (funcall original-featurep feature subfeature)))))
      (emacsvox-pip "fallback")
      (setq available t)
      (emacsvox-pip "piper")
      (should (equal spoken '((piper . "piper") (notification . "fallback")))))))

(ert-deftest emacsvox-speak-date-collector-uses-calendar-date ()
  "Calendar date collection offers the selected date in each requested format."
  (with-temp-buffer
    (setq major-mode 'calendar-mode)
    (cl-letf (((symbol-function 'calendar-cursor-to-nearest-date)
               (lambda () '(2 29 2024)))
              ((symbol-function 'read-from-minibuffer)
               (lambda (_prompt initial &rest _) initial)))
      (should (equal (emacsvox-speak-read-date-year/month/date) "2024/02/29"))
      (should (equal (emacsvox-speak-date-YearMonthDate) "20240229"))
      (should (equal (emacsvox-speak-date-month/date) "02/29"))
      (should (equal (emacsvox-speak-year-month-date) "2024-02-29")))))

(ert-deftest emacsvox-speak-scheduled-message-delivers-at-callback ()
  "Scheduling defers delivery and preserves the message and alarm cues."
  (let ((emacsvox-use-icons t) scheduled spoken cues tones)
    (cl-letf (((symbol-function 'run-at-time)
               (lambda (&rest arguments) (setq scheduled arguments)))
              ((symbol-function 'tts-notify) (lambda (text) (push text spoken)))
              ((symbol-function 'emacsvox-icon) (lambda (cue) (push cue cues)))
              ((symbol-function 'sox-tones) (lambda (&rest _) (setq tones t)))
              ((symbol-function 'message) #'ignore))
      (emacsvox-speak-message-at-time "5 min" "Take a break")
      (should (equal (seq-take scheduled 2) '("5 min" nil)))
      (should-not spoken)
      (apply (nth 2 scheduled) (nthcdr 3 scheduled))
      (should (equal spoken '("Take a break")))
      (should (equal cues '(alarm button)))
      (should tones))))

(ert-deftest emacsvox-speak-time-conversions-preserve-units ()
  "Duration parsing and epoch helpers retain their time units."
  (should (= (ems--duration-to-seconds "-01:02:03") -3723))
  (should (equal (ems--seconds-to-duration "3723") "01:02:03"))
  (should (equal (ems--format-clock 125) "02:05"))
  (let (seconds)
    (cl-letf (((symbol-function 'emacsvox-speak-seconds-since-epoch)
               (lambda (value) (push value seconds))))
      (emacsvox-speak-milliseconds-since-epoch 2000)
      (emacsvox-speak-microseconds-since-epoch 3000000)
      (should (equal seconds '(3 2))))))

(ert-deftest emacsvox-speak-windows-graphical-reading-preserves-focus ()
  "Read actual visible window bounds and preserve focus when reading elsewhere."
  (skip-unless (display-graphic-p))
  (save-window-excursion
    (let ((first (generate-new-buffer " *reading first window*"))
          (second (generate-new-buffer " *reading second window*"))
          ranges spoken)
      (unwind-protect
          (cl-letf (((symbol-function 'emacsvox-speak-region)
                     (lambda (start end)
                       (push (list (current-buffer) start end) ranges)))
                    ((symbol-function 'tts-speak) (lambda (text) (setq spoken text)))
                    ((symbol-function 'sox-multiwindow) #'ignore)
                    ((symbol-function 'emacsvox-icon) #'ignore))
            (delete-other-windows)
            (switch-to-buffer first)
            (insert "first draft\n")
            (let* ((origin (selected-window))
                   (destination (split-window-below))
                   (saved-point (point)))
              (with-current-buffer second
                (dotimes (index 100) (insert (format "line %d\n" index)))
                (goto-char (point-min)))
              (set-window-buffer destination second)
              (redisplay t)
              (emacsvox-speak-current-window)
              (should (equal (car ranges)
                             (list first (window-start origin) (window-end origin t))))
              (emacsvox-speak-other-window)
              (should (equal (car ranges)
                             (list second (window-start destination)
                                   (window-end destination t))))
              (should (eq (selected-window) origin))
              (should (= (point) saved-point))
              (emacsvox-describe-tapestry t)
              (should (string-match-p "Displaying 2 windows" spoken))
              (should (string-match-p (regexp-quote (buffer-name second)) spoken))
              (should (string-match-p "with top left" spoken))))
        (kill-buffer first)
        (kill-buffer second)))))

(ert-deftest emacsvox-speak-status-graphical-header-and-mode-line ()
  "Format real status lines and preserve header routing and modification cues."
  (skip-unless (display-graphic-p))
  (save-window-excursion
    (let ((buffer (generate-new-buffer " *reading status*")) spoken notified cues)
      (unwind-protect
          (cl-letf (((symbol-function 'tts-stop) #'ignore)
                    ((symbol-function 'tts-speak) (lambda (text) (setq spoken text)))
                    ((symbol-function 'tts-notify) (lambda (text) (setq notified text)))
                    ((symbol-function 'emacsvox-icon) (lambda (cue) (push cue cues))))
            (delete-other-windows)
            (switch-to-buffer buffer)
            (insert "status sample\n")
            (setq-local emacsvox-mail-alert nil)
            (setq-local emacsvox-comint-autospeak nil)
            (setq-local header-line-format '("Header ready"))
            (emacsvox-speak-mode-line)
            (should (equal notified "Header ready"))
            (should-not spoken)
            (setq-local header-line-format nil)
            (setq-local global-mode-string '("Build READY"))
            (setq-local mode-line-format '("Status"))
            (setq-local buffer-file-name "/tmp/emacsvox-status-fixture")
            (setq-local vc-mode nil)
            (emacsvox-speak-mode-line)
            (should (string-match-p (regexp-quote (buffer-name buffer)) spoken))
            (should (string-match-p "build ready" spoken))
            (should (memq 'modified-object cues))
            (set-buffer-modified-p nil)
            (setq buffer-read-only t cues nil)
            (emacsvox-speak-mode-line)
            (should (memq 'unmodified-object cues)))
        (with-current-buffer buffer (set-buffer-modified-p nil))
        (kill-buffer buffer)))))

(ert-deftest emacsvox-speak-status-battery-crossing-alerts-once ()
  "A fall below ten percent off-line emits one low-battery cue."
  (let ((emacsvox-battery-prev '((?L . "off-line") (?p . "12"))) cues)
    (cl-letf (((symbol-function 'emacsvox-icon) (lambda (cue) (push cue cues))))
      (emacsvox-battery-alarm '((?L . "on-line") (?p . "8")))
      (should-not cues)
      (emacsvox-battery-alarm '((?L . "off-line") (?p . "8")))
      (emacsvox-battery-alarm '((?L . "off-line") (?p . "7")))
      (should (equal cues '(battery-low))))))

(ert-deftest emacsvox-speak-status-network-report-can-be-yanked ()
  "Report the first non-loopback interface and retain its identity for yanking."
  (let ((kill-ring nil))
    (cl-letf (((symbol-function 'network-interface-list)
               (lambda () '(("lo" . [127 0 0 1 0]) ("wlan0" . [192 0 2 1 0]))))
              ((symbol-function 'network-interface-info)
               (lambda (device)
                 (should (equal device "wlan0"))
                 '([192 0 2 1 0])))
              ((symbol-function 'shell-command-to-string)
               (lambda (command)
                 (should (equal command "iwgetid --raw")) "Test network\n")))
      (emacsvox-speak-net-id)
      (should (equal (car kill-ring) "Test network: 192.0.2.1")))))

(provide 'emacsvox-speak-command-tests)
;;; emacsvox-speak-command-tests.el ends here
