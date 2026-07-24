;;; emacsvox-trace-tests.el --- Tests for semantic traces -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for deterministic speech event recording and editor scenarios.

;;; Code:

(require 'ert)
(require 'emacsvox-trace)

(ert-deftest emacsvox-trace-records-semantic-output-in-order ()
  "Trace capture records output operations without a speech server."
  (let* ((spoken (propertize "Hello" 'personality 'voice-bolden))
         (result
          (let ((inhibit-message t))
            (emacsvox-trace-capture
             (lambda ()
               (funcall (symbol-function 'tts-speak) spoken)
               (funcall (symbol-function 'tts-letter) "h")
               (funcall (symbol-function 'tts-dispatch) "punctuation")
               (funcall (symbol-function 'emacsvox-icon) 'select-object)
               (funcall (symbol-function 'tts-tone) 440 100 t)
               (funcall (symbol-function 'tts-silence) 50 nil)
               (funcall (symbol-function 'tts-set-rate) 120 t)
               (funcall (symbol-function 'tts-stop) t)
               (funcall (symbol-function 'tts-notify) "notice" 'dont-log)
               (funcall (symbol-function 'tts-notify-icon) 'progress)
               (funcall (symbol-function 'tts-notify-stop))
               (funcall (symbol-function 'message) "At %s" "point")
               'finished)))))
    (should (eq (plist-get result :value) 'finished))
    (should
     (equal
      (plist-get result :events)
      '((speak
         (:text "Hello" :personalities ((0 5 voice-bolden))))
        (letter "h")
        (dispatch "punctuation")
        (icon select-object)
        (tone 440 100 t)
        (silence 50 nil)
        (rate 120 t)
        (stop t)
        (notify (:text "notice") dont-log)
        (notify-icon progress)
        (notify-stop)
        (message "At point"))))))

(ert-deftest emacsvox-trace-restores-output-functions ()
  "Trace capture restores every function definition it replaces."
  (let ((original (symbol-function 'message)))
    (let ((inhibit-message t))
      (emacsvox-trace-capture (lambda () (message "captured"))))
    (should (eq (symbol-function 'message) original))))

(ert-deftest emacsvox-trace-scenario-captures-result-and-buffer-state ()
  "A scenario records command output, return value, and final editor state."
  (let ((command 'emacsvox-test--trace-command))
    (fset command
          (lambda ()
            (interactive)
            (forward-char 1)
            (funcall (symbol-function 'tts-speak) "moved")
            (funcall (symbol-function 'emacsvox-icon) 'select-object)
            'done))
    (unwind-protect
        (should
         (equal
          (emacsvox-trace-run-scenario
           :name 'move-forward
           :command command
           :interactive t
           :text "ab"
           :point 1)
          '(:name move-forward
            :events
            ((speak (:text "moved")) (icon select-object))
            :value done
            :state
            (:text "ab" :point 2 :mark nil :mark-active nil
                   :modified nil :kill-ring nil))))
      (fmakunbound command))))

(provide 'emacsvox-trace-tests)
;;; emacsvox-trace-tests.el ends here
