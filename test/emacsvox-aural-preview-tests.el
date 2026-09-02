;;; emacsvox-aural-preview-tests.el --- Aural preview runtime tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Focused lifecycle checks for explicit speech and cue previews.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-aural-preview)

(ert-deftest emacsvox-aural-preview-plan-has-one-ordered-lifecycle ()
  "A concrete speech preview prepares, queues, and dispatches exactly once."
  (let ((plan 'concrete-plan)
        events)
    (cl-letf
        (((symbol-function 'emacsvox-aural--ensure-speaker)
          (lambda () (setq events (append events '(ensure)))))
         ((symbol-function 'tts-stop)
          (lambda () (setq events (append events '(stop)))))
         ((symbol-function 'emacsvox-aural-queue-concrete-plan)
          (lambda (queued)
            (should (eq queued plan))
            (setq events (append events '(queue)))))
         ((symbol-function 'tts--protocol-dispatch)
          (lambda () (setq events (append events '(dispatch))))))
      (should (eq (emacsvox-aural-preview-play-plan plan) plan)))
    (should (equal events '(stop ensure queue dispatch)))))

(ert-deftest emacsvox-aural-preview-plan-uses-one-delivery-transaction ()
  "A speech preview exposes its concrete style to structured delivery."
  (let ((plan 'concrete-plan)
        (tts-speaker-process 'preview-speaker)
        transaction-owner)
    (cl-letf
        (((symbol-function 'emacsvox-aural--ensure-speaker) #'ignore)
         ((symbol-function 'tts-stop) #'ignore)
         ((symbol-function 'emacsvox-aural-call-with-delivery-transaction)
          (lambda (owner function &rest arguments)
            (setq transaction-owner owner)
            (apply function arguments)))
         ((symbol-function 'emacsvox-aural-queue-concrete-plan) #'ignore)
         ((symbol-function 'tts--protocol-dispatch) #'ignore))
      (emacsvox-aural-preview-play-plan plan))
    (should (eq transaction-owner tts-speaker-process))))

(ert-deftest emacsvox-aural-preview-compiled-voice-retains-effects ()
  "A compiled palette voice becomes a concrete effect-bearing preview plan."
  (let* ((compiled
          (emacsvox-aural--make-compiled-voice
           :command "[[logical_voice lighten-extra]]"
           :request 'lighten-extra
           :style '(:average-pitch 6 :high-pass 5 :reverb 7 :echo 5 :chorus 4)
           :capability '(:adapter omnivox)
           :degradations nil))
         (plan
          (emacsvox-aural-preview-compiled-voice-plan
           compiled "Lighten extra voice."))
         (content (emacsvox-aural-concrete-plan-content plan))
         (built
          (emacsvox-aural--build-structured-timeline
           1 1 (list (list plan "Lighten extra voice." nil))))
         (span (aref (plist-get (car built) :spans) 0))
         (effects (plist-get (plist-get span :effects) :style)))
    (should (equal (emacsvox-aural-concrete-content-text content)
                   "Lighten extra voice."))
    (should (equal (emacsvox-aural-concrete-content-voice-style content)
                   '(:average-pitch 6 :high-pass 5 :reverb 7 :echo 5
                     :chorus 4)))
    (should (= (plist-get effects :high_pass) (/ 5.0 9.0)))
    (should (= (plist-get effects :reverb) (/ 7.0 9.0)))
    (should (= (plist-get effects :echo) (/ 5.0 9.0)))
    (should (= (plist-get effects :chorus) (/ 4.0 9.0)))))

(ert-deftest emacsvox-aural-preview-runs-retain-one-transaction ()
  "A multi-run preview queues and dispatches within one history transaction."
  (let ((runs '((first "First" nil) (second "Second" 0.1)))
        events)
    (cl-letf
        (((symbol-function 'emacsvox-aural--ensure-speaker)
          (lambda () (push 'ensure events)))
         ((symbol-function 'tts-stop)
          (lambda () (push 'stop events)))
         ((symbol-function 'emacsvox-aural-call-with-presentation-transaction)
          (lambda (id function &rest arguments)
            (push (list 'transaction id) events)
            (apply function arguments)))
         ((symbol-function 'emacsvox-aural-queue-concrete-runs)
          (lambda (queued)
            (should (equal queued runs))
            (push 'queue events)))
         ((symbol-function 'tts--protocol-dispatch)
          (lambda () (push 'dispatch events))))
      (should
       (equal
        (emacsvox-aural-preview-play-runs runs 7)
        runs)))
    (should
     (equal
      (nreverse events)
      '(stop ensure (transaction 7) queue dispatch)))))

(ert-deftest emacsvox-aural-preview-cues-bypass-speech-transport ()
  "Cue-only previews stop old speech and play concrete resources directly."
  (let ((cues
         (list
          (emacsvox-aural--make-concrete-action
           :kind 'cue :resource "/sounds/left.ogg"
           :sample-id "left" :balance -0.5)
          (emacsvox-aural--make-concrete-action
           :kind 'cue :resource "/sounds/centre.ogg"
           :sample-id "centre" :balance 0)))
        events)
    (cl-letf
        (((symbol-function 'tts-stop)
          (lambda () (push 'stop events)))
         ((symbol-function 'emacsvox-aural--ensure-speaker)
          (lambda () (ert-fail "Cue preview must not start speech")))
         ((symbol-function 'emacsvox-aural-queue-concrete-plan)
          (lambda (&rest _) (ert-fail "Cue preview must not queue speech")))
         ((symbol-function 'tts--protocol-dispatch)
          (lambda () (ert-fail "Cue preview must not dispatch speech")))
         ((symbol-function 'emacsvox-sounds-play-concrete-cue)
          (lambda (resource sample-id &optional balance)
            (push (list resource sample-id balance) events))))
      (should (eq (emacsvox-aural-preview-play-cues cues) cues)))
    (should
     (equal
      (nreverse events)
      '(stop
        ("/sounds/left.ogg" "left" -0.5)
        ("/sounds/centre.ogg" "centre" nil))))))

(ert-deftest emacsvox-aural-preview-status-message-is-silent ()
  "Preview status remains visible without entering message speech."
  (let ((emacsvox-speak-messages t)
        observed)
    (cl-letf
        (((symbol-function 'message)
          (lambda (&rest _)
            (setq
             observed
             (symbol-value 'emacsvox-speak-messages)))))
      (emacsvox-aural-preview-message "Preview status"))
    (should-not observed)))

(provide 'emacsvox-aural-preview-tests)
;;; emacsvox-aural-preview-tests.el ends here
