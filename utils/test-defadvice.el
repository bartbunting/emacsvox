;;; test-defadvice.el --- Test file for conversion -*- lexical-binding: t; -*-

;; Test case 1: Simple :after advice

(defun ems--calendar-forward-day-after (&rest _) "Speak the date." (when (ems-interactive-p) (emacspeak-calendar-speak-date) (emacspeak-icon 'select-object)))

(advice-add 'calendar-forward-day :after #'ems--calendar-forward-day-after)



;; Test case 2: Simple :before advice

(defun ems--some-function-before (&rest _) "Icon before action." (when (ems-interactive-p) (emacspeak-icon 'open-object)))

(advice-add 'some-function :before #'ems--some-function-before)



;; Test case 3: Simple :around with ad-do-it

(defun ems--perform-replace-around (orig-fun &rest args) "Silence help." (ems-with-messages-silenced (apply orig-fun args)))

(advice-add 'perform-replace :around #'ems--perform-replace-around)



;; Test case 4: :after with ad-get-arg

(defun ems--mark-visible-calendar-date-after (&rest _) "Use voice locking to mark date." (let ((date (ad-get-arg 0))) (when (calendar-date-is-valid-p date) (message "Marked: %s" date))))

(advice-add 'mark-visible-calendar-date :after #'ems--mark-visible-calendar-date-after)



(provide 'test-defadvice)
;;; test-defadvice.el ends here
