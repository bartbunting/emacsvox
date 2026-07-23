;;; emacsvox-calendar-tests.el --- Calendar advice tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Behaviour and registration coverage for migrated Calendar advice.

;;; Code:

(require 'cl-lib)
(require 'ert)

(let ((module
       (expand-file-name
        "../lisp/emacsvox-calendar.el"
        (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise source even when a compiled integration module exists.
  (load module nil nil))

(defconst emacsvox-test--calendar-advice
  '((calendar-exchange-point-and-mark :after
     emacsvox--advice-calendar-exchange-point-and-mark-after)
    (calendar-set-mark :after emacsvox--advice-calendar-set-mark-after)
    (diary-fancy-display :around
     emacsvox--advice-diary-fancy-display-around)
    (diary-simple-display :around
     emacsvox--advice-diary-simple-display-around)
    (diary-list-entries :around
     emacsvox--advice-diary-list-entries-around)
    (diary-view-entries :after
     emacsvox--advice-diary-view-entries-after)
    (calendar-mark-visible-date :after
     emacsvox--advice-calendar-mark-visible-date-after)
    (calendar :after emacsvox--advice-calendar-after)
    (calendar-goto-date :after emacsvox--advice-calendar-goto-date-after)
    (calendar-goto-today :after emacsvox--advice-calendar-goto-today-after)
    (calendar-backward-day :after
     emacsvox--advice-calendar-backward-day-after)
    (calendar-forward-day :after
     emacsvox--advice-calendar-forward-day-after)
    (calendar-backward-week :after
     emacsvox--advice-calendar-backward-week-after)
    (calendar-forward-week :after
     emacsvox--advice-calendar-forward-week-after)
    (calendar-backward-month :after
     emacsvox--advice-calendar-backward-month-after)
    (calendar-forward-month :after
     emacsvox--advice-calendar-forward-month-after)
    (calendar-backward-year :after
     emacsvox--advice-calendar-backward-year-after)
    (calendar-forward-year :after
     emacsvox--advice-calendar-forward-year-after)
    (calendar-beginning-of-week :after
     emacsvox--advice-calendar-beginning-of-week-after)
    (calendar-beginning-of-month :after
     emacsvox--advice-calendar-beginning-of-month-after)
    (calendar-beginning-of-year :after
     emacsvox--advice-calendar-beginning-of-year-after)
    (calendar-end-of-week :after
     emacsvox--advice-calendar-end-of-week-after)
    (calendar-end-of-month :after
     emacsvox--advice-calendar-end-of-month-after)
    (calendar-end-of-year :after
     emacsvox--advice-calendar-end-of-year-after)
    (calendar-exit :after emacsvox--advice-calendar-exit-after)
    (diary-insert-block-entry :before
     emacsvox--advice-diary-insert-block-entry-before)
    (calendar-read :around emacsvox--advice-calendar-read-around)
    (diary-insert-anniversary-entry :before
     emacsvox--advice-diary-insert-anniversary-entry-before)
    (diary-insert-cyclic-entry :after
     emacsvox--advice-diary-insert-cyclic-entry-after)
    (diary-insert-entry :after
     emacsvox--advice-diary-insert-entry-after)
    (diary-insert-weekly-entry :before
     emacsvox--advice-diary-insert-weekly-entry-before)
    (diary-insert-yearly-entry :before
     emacsvox--advice-diary-insert-yearly-entry-before)
    (diary-insert-monthly-entry :before
     emacsvox--advice-diary-insert-monthly-entry-before)
    (calendar-cursor-holidays :after
     emacsvox--advice-calendar-cursor-holidays-after)
    (diary-mark-entries :around
     emacsvox--advice-diary-mark-entries-around)
    (appt-add :after emacsvox--advice-appt-add-after)
    (calendar-sunrise-sunset :around
     emacsvox--advice-calendar-sunrise-sunset-around)
    (calendar-lunar-phases :after
     emacsvox--advice-calendar-lunar-phases-after)
    (lunar-phases :after emacsvox--advice-lunar-phases-after)
    (holidays :after emacsvox--advice-holidays-after)
    (calendar-list-holidays :after
     emacsvox--advice-calendar-list-holidays-after))
  "Native advice registrations in the Calendar integration.")

(ert-deftest emacsvox-calendar-advice-is-directly-registered ()
  "Calendar advice uses current Emacs APIs and bypasses the bridge."
  (dolist (entry emacsvox-test--calendar-advice)
    (pcase-let ((`(,target ,where ,function) entry))
      (should (fboundp function))
      (should (advice-member-p function target))
      (should-not
       (gethash
        (list target where function) ems--modern-advice-wrappers)))))

(ert-deftest emacsvox-calendar-movement-feedback-is-target-aware ()
  "Only the matching interactive Calendar movement produces feedback."
  (let ((ems--interactive-fn-name 'calendar-forward-month)
        events)
    (cl-letf (((symbol-function 'emacsvox-calendar-speak-date)
               (lambda () (push 'speak-date events)))
              ((symbol-function 'emacsvox-icon)
               (lambda (icon) (push (list 'icon icon) events))))
      (emacsvox--advice-calendar-backward-month-after)
      (emacsvox--advice-calendar-forward-month-after))
    (should
     (equal
      (nreverse events)
      '(speak-date (icon section))))))

(ert-deftest emacsvox-calendar-read-calls-original-once-and-records-result ()
  "Calendar input is read once, cached, and returned unchanged."
  (let ((calls 0)
        (emacsvox-calendar-user-input nil))
    (should
     (eq
      'read-result
      (emacsvox--advice-calendar-read-around
       (lambda (&rest args)
         (cl-incf calls)
         (should (equal args '("Prompt: " acceptable "initial")))
         'read-result)
       "Prompt: " 'acceptable "initial")))
    (should (= calls 1))
    (should (eq emacsvox-calendar-user-input 'read-result))))

(ert-deftest emacsvox-calendar-diary-marking-calls-original-once-silenced ()
  "Diary marking runs once with speech messages inhibited."
  (let ((calls 0)
        observed-speech-state)
    (should
     (eq
      'mark-result
      (emacsvox--advice-diary-mark-entries-around
       (lambda (&rest args)
         (cl-incf calls)
         (setq observed-speech-state emacsvox-speak-messages)
         (should (equal args '(redraw)))
         'mark-result)
       'redraw)))
    (should (= calls 1))
    (should-not observed-speech-state)))

(ert-deftest emacsvox-calendar-diary-display-preserves-result-and-message-state ()
  "Diary display runs once with the intended interactive message state."
  (let ((calls 0)
        observed)
    (let ((ems--interactive-fn-name 'diary-fancy-display))
      (should
       (eq
        'display-result
        (emacsvox--advice-diary-fancy-display-around
         (lambda (&rest args)
           (cl-incf calls)
           (setq observed (list emacsvox-speak-messages args))
           'display-result)
         'entry))))
    (should (= calls 1))
    (should (equal observed '(nil (entry)))))
  (let (observed)
    (emacsvox--advice-diary-fancy-display-around
     (lambda (&rest _)
       (setq observed emacsvox-speak-messages))
     'entry)
    (should observed)))

(ert-deftest emacsvox-calendar-mark-visible-date-uses-explicit-date ()
  "Calendar marking receives DATE directly rather than through the bridge."
  (let (seen)
    (cl-letf (((symbol-function 'calendar-date-is-valid-p)
               (lambda (date)
                 (setq seen date)
                 nil)))
      (emacsvox--advice-calendar-mark-visible-date-after '(7 23 2026)))
    (should (equal seen '(7 23 2026)))))

(ert-deftest emacsvox-calendar-appt-add-uses-explicit-arguments ()
  "Appointment confirmation uses the native TIME and MESSAGE arguments."
  (let ((ems--interactive-fn-name 'appt-add)
        spoken)
    (cl-letf (((symbol-function 'message)
               (lambda (format-string &rest args)
                 (setq spoken (apply #'format format-string args)))))
      (emacsvox--advice-appt-add-after "09:00" "Standup"))
    (should (equal spoken "Set alarm Standup at 09:00"))))

(ert-deftest emacsvox-calendar-sunrise-programmatic-call-runs-original-once ()
  "Programmatic sunrise lookup preserves one original call and its result."
  (let ((calls 0)
        (gmaps-my-address "Sydney"))
    (should
     (eq
      'sun-result
      (emacsvox--advice-calendar-sunrise-sunset-around
       (lambda (&rest args)
         (cl-incf calls)
         (should (equal args '(argument)))
         'sun-result)
       'argument)))
    (should (= calls 1))))

(provide 'emacsvox-calendar-tests)
;;; emacsvox-calendar-tests.el ends here
