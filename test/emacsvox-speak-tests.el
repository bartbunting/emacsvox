;;; emacsvox-speak-tests.el --- Core tracked reading tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for interruptible rest-of-buffer reading.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-speak)

(defun emacsvox-speak-tests--with-cycle-buffers (test)
  "Call TEST with four displayed-in-order buffers in a unique major mode."
  (let* ((mode (make-symbol "cycle-test-mode"))
         (buffers
          (mapcar
           (lambda (name)
             (let ((buffer (generate-new-buffer name)))
               (with-current-buffer buffer (setq major-mode mode))
               buffer))
           '("cycle-A" "cycle-B" "cycle-C" "cycle-D"))))
    (unwind-protect
        (save-window-excursion
          (dolist (buffer (reverse buffers)) (switch-to-buffer buffer))
          (cl-letf (((symbol-function 'emacsvox-icon) #'ignore)
                    ((symbol-function 'emacsvox-speak-mode-line) #'ignore)
                    ((symbol-function 'emacsvox-speak-line) #'ignore))
            (funcall test buffers)))
      (dolist (buffer buffers)
        (when (buffer-live-p buffer) (kill-buffer buffer))))))

(ert-deftest emacsvox-buffer-cycle-visits-every-matching-buffer-in-both-directions ()
  "Each direction traverses the entire mode-specific cycle and wraps."
  (dolist (direction '(next previous))
    (emacsvox-speak-tests--with-cycle-buffers
     (lambda (buffers)
       (let ((expected (if (eq direction 'next)
                           (append (cdr buffers) (list (car buffers)))
                         (append (reverse (cdr buffers)) (list (car buffers)))))
             (command (if (eq direction 'next)
                          #'emacsvox-cycle-to-next-buffer
                        #'emacsvox-cycle-to-previous-buffer)))
         (dolist (buffer expected)
           (call-interactively command)
           (should (eq (current-buffer) buffer))))))))

(ert-deftest emacsvox-buffer-cycle-directions-are-inverses ()
  "Changing direction returns to the buffer just left, from every position."
  (emacsvox-speak-tests--with-cycle-buffers
   (lambda (_buffers)
     (dotimes (_ 4)
       (let ((start (current-buffer)))
         (emacsvox-cycle-to-next-buffer)
         (emacsvox-cycle-to-previous-buffer)
         (should (eq (current-buffer) start))
         (emacsvox-cycle-to-previous-buffer)
         (emacsvox-cycle-to-next-buffer)
         (should (eq (current-buffer) start)))
       (emacsvox-cycle-to-next-buffer)))))

(ert-deftest emacsvox-buffer-cycle-skips-other-modes-and-killed-buffers ()
  "The live buffer list remains authoritative when candidates change."
  (emacsvox-speak-tests--with-cycle-buffers
   (lambda (buffers)
     (with-current-buffer (nth 1 buffers) (setq major-mode 'fundamental-mode))
     (kill-buffer (nth 2 buffers))
     (emacsvox-cycle-to-next-buffer)
     (should (eq (current-buffer) (nth 3 buffers)))
     (emacsvox-cycle-to-next-buffer)
     (should (eq (current-buffer) (car buffers)))
     (emacsvox-cycle-to-previous-buffer)
     (should (eq (current-buffer) (nth 3 buffers))))))

(ert-deftest emacsvox-buffer-cycle-single-candidate-does-not-switch ()
  "No matching alternative leaves the current buffer and order unchanged."
  (emacsvox-speak-tests--with-cycle-buffers
   (lambda (buffers)
     (mapc #'kill-buffer (cdr buffers))
     (let ((order (buffer-list (selected-frame))))
       (should-error (emacsvox-cycle-to-next-buffer))
       (should-error (emacsvox-cycle-to-previous-buffer))
       (should (eq (current-buffer) (car buffers)))
       (should (equal order (buffer-list (selected-frame))))))))

(ert-deftest emacsvox-buffer-cycle-repeats-with-bare-keys-and-exits ()
  "Actual prefix and repeat keys cycle in both directions, then yield typing."
  (emacsvox-speak-tests--with-cycle-buffers
   (lambda (buffers)
     (let ((global-map (copy-keymap (current-global-map)))
           (overriding-terminal-local-map nil)
           (pre-command-hook nil)
           (post-command-hook nil))
       (define-key global-map (kbd "C-e") emacsvox-keymap)
       (execute-kbd-macro (kbd "C-e n n"))
       (should (eq (current-buffer) (nth 2 buffers)))
       (execute-kbd-macro (kbd "p"))
       (should (eq (current-buffer) (nth 1 buffers)))
       (execute-kbd-macro (kbd "n n n"))
       (should (eq (current-buffer) (car buffers)))
       (execute-kbd-macro (kbd "x n"))
       (should (eq (current-buffer) (car buffers)))
       (should (equal (buffer-string) "xn"))
       (should-not overriding-terminal-local-map)))))

(ert-deftest emacsvox-show-point-facts-classify-text-boundaries ()
  "Point facts distinguish beginning, interior, end, and empty positions."
  (let ((emacsvox-show-point t)
        (emacsvox-show-point-presentation 'tone))
    (dolist
        (case
         '((10 10 14 beginning before)
           (12 10 14 interior before)
           (14 10 14 end after)
           (10 10 10 empty before)))
      (let ((facts
             (emacsvox-speak--point-facts
              (nth 0 case) (nth 1 case) (nth 2 case))))
        (should (equal (plist-get facts :events) '(point-located)))
        (should (eq (plist-get facts :point-position) (nth 3 case)))
        (should (eq (plist-get facts :point-boundary) (nth 4 case)))
        (should (eq (plist-get facts :point-presentation) 'tone)))))
  (let ((emacsvox-show-point nil))
    (should-not (emacsvox-speak--point-facts 1 1 2)))
  (let ((emacsvox-show-point t)
        (emacsvox-show-point-presentation 'none))
    (should-not (emacsvox-speak--point-facts 1 1 2))))

(ert-deftest emacsvox-show-point-annotation-composes-with-local-facts ()
  "The point marker occupies one character and preserves provider facts."
  (let* ((emacsvox-show-point t)
         (emacsvox-show-point-presentation 'earcon)
         (text (copy-sequence "abc"))
         (facts (emacsvox-speak--point-facts 12 10 13)))
    (add-text-properties
     2 3
     (list emacsvox-aural-facts-property '(:role heading :level 2))
     text)
    (emacsvox-speak--annotate-point text 12 10 13 facts)
    (should-not
     (get-text-property 1 emacsvox-aural-facts-property text))
    (let ((merged
           (get-text-property 2 emacsvox-aural-facts-property text)))
      (should (eq (plist-get merged :role) 'heading))
      (should (= (plist-get merged :level) 2))
      (should (equal (plist-get merged :events) '(point-located)))
      (should (eq (plist-get merged :point-position) 'interior))
      (should (eq (plist-get merged :point-presentation) 'earcon)))))

(ert-deftest emacsvox-set-show-point-presentation-supports-local-and-global ()
  "The selector changes one buffer unless a global default is requested."
  (let ((original (default-value 'emacsvox-show-point-presentation)))
    (unwind-protect
        (with-temp-buffer
          (setq-local emacsvox-show-point-presentation 'voice)
          (should
           (eq (emacsvox-set-show-point-presentation 'tone) 'tone))
          (should (local-variable-p 'emacsvox-show-point-presentation))
          (should (eq emacsvox-show-point-presentation 'tone))
          (emacsvox-set-show-point-presentation 'earcon t)
          (should (eq emacsvox-show-point-presentation 'earcon))
          (should
           (eq
            (default-value 'emacsvox-show-point-presentation)
            'earcon))
          (should-error
           (emacsvox-set-show-point-presentation 'unknown)
           :type 'user-error))
      (set-default 'emacsvox-show-point-presentation original))))

(ert-deftest emacsvox-set-indentation-presentation-supports-local-and-global ()
  "The indentation selector changes one buffer or its global default."
  (let ((original (default-value 'emacsvox-indentation-presentation)))
    (unwind-protect
        (with-temp-buffer
          (setq-local emacsvox-indentation-presentation 'spoken)
          (should
           (eq
            (emacsvox-set-indentation-presentation 'pitch-tone)
            'pitch-tone))
          (should (local-variable-p 'emacsvox-indentation-presentation))
          (should (eq emacsvox-indentation-presentation 'pitch-tone))
          (emacsvox-set-indentation-presentation 'duration-tone t)
          (should (eq emacsvox-indentation-presentation 'duration-tone))
          (should
           (eq
            (default-value 'emacsvox-indentation-presentation)
            'duration-tone))
          (should-error
           (emacsvox-set-indentation-presentation 'unknown)
           :type 'user-error))
      (set-default 'emacsvox-indentation-presentation original))))

(ert-deftest emacsvox-indentation-facts-calibrate-duration-and-pitch-tones ()
  "Indentation modes publish stable duration or rising-pitch tone facts."
  (let ((emacsvox-audio-indentation t)
        (emacsvox-indentation-pitch-tone-base 250.0)
        (emacsvox-indentation-pitch-tone-semitones-per-column 1.0)
        (emacsvox-indentation-pitch-tone-maximum 500.0)
        (emacsvox-indentation-pitch-tone-duration 10))
    (let* ((emacsvox-indentation-presentation 'duration-tone)
           (shallow (emacsvox-speak--indentation-facts 1))
           (deeper (emacsvox-speak--indentation-facts 5)))
      (should (= (plist-get shallow :indentation-tone-pitch) 250.0))
      (should (= (plist-get deeper :indentation-tone-pitch) 250.0))
      (should (= (plist-get shallow :indentation-tone-duration) 70))
      (should (= (plist-get deeper :indentation-tone-duration) 150)))
    (let* ((emacsvox-indentation-presentation 'pitch-tone)
           (shallow (emacsvox-speak--indentation-facts 1))
           (deeper (emacsvox-speak--indentation-facts 5))
           (capped (emacsvox-speak--indentation-facts 100))
           (minimum-duration
            (emacsvox-speak--blank-line-tone-duration)))
      (should (= (plist-get shallow :indentation-tone-pitch) 250.0))
      (should
       (>
        (plist-get deeper :indentation-tone-pitch)
        (plist-get shallow :indentation-tone-pitch)))
      (should (= (plist-get capped :indentation-tone-pitch) 500.0))
      (should
       (=
        (plist-get shallow :indentation-tone-duration)
        minimum-duration)))
    (let ((emacsvox-indentation-presentation 'spoken))
      (let ((facts (emacsvox-speak--indentation-facts 3)))
        (should (= (plist-get facts :indentation-columns) 3))
        (should-not (plist-member facts :indentation-tone-pitch))))
    (let ((emacsvox-indentation-presentation 'custom))
      (should
       (equal
        (emacsvox-speak--indentation-facts 2)
        '(:events (indentation-located)
          :indentation-columns 2
          :indentation-presentation custom))))
    (let ((emacsvox-indentation-presentation 'none))
      (should-not (emacsvox-speak--indentation-facts 2)))
    (let ((emacsvox-audio-indentation nil)
          (emacsvox-indentation-presentation 'pitch-tone))
      (should-not (emacsvox-speak--indentation-facts 2)))))

(ert-deftest emacsvox-indentation-annotation-composes-at-content-boundary ()
  "Indentation facts merge before content without replacing source text."
  (let* ((text (copy-sequence "  value"))
         (facts
          '(:events (indentation-located)
            :indentation-columns 2
            :indentation-presentation spoken)))
    (add-text-properties
     2 3
     (list
      emacsvox-aural-facts-property
      '(:events (point-located) :point-position beginning))
     text)
    (emacsvox-speak--annotate-indentation text facts)
    (should (equal (substring-no-properties text) "  value"))
    (should-not
     (get-text-property 0 emacsvox-aural-facts-property text))
    (let ((merged
           (get-text-property 2 emacsvox-aural-facts-property text)))
      (should (memq 'point-located (plist-get merged :events)))
      (should (memq 'indentation-located (plist-get merged :events)))
      (should (= (plist-get merged :indentation-columns) 2)))
    (let ((following
           (get-text-property 3 emacsvox-aural-facts-property text)))
      (should
       (equal (plist-get following :events) '(indentation-located)))
      (should-not (memq 'point-located (plist-get following :events)))
      (should (= (plist-get following :indentation-columns) 2)))))

(ert-deftest emacsvox-indentation-preview-uses-representative-depth ()
  "The selector audition is useful even on an unindented current line."
  (let ((emacsvox-audio-indentation t)
        (emacsvox-indentation-presentation 'pitch-tone)
        spoken)
    (cl-letf (((symbol-function 'tts-speak)
               (lambda (text) (setq spoken text))))
      (emacsvox-speak--preview-indentation-presentation))
    (should
     (equal
      (substring-no-properties spoken)
      "    indentation preview"))
    (let ((facts
           (get-text-property
            4 emacsvox-aural-facts-property spoken)))
      (should (memq 'indentation-located (plist-get facts :events)))
      (should (= (plist-get facts :indentation-columns) 4))
      (should (eq (plist-get facts :indentation-presentation) 'pitch-tone))
      (should (numberp (plist-get facts :indentation-tone-pitch)))
      (should (integerp (plist-get facts :indentation-tone-duration))))))

(ert-deftest emacsvox-line-indentation-no-longer-injects-spoken-text ()
  "Line extraction leaves source intact and publishes indentation facts."
  (with-temp-buffer
    (insert "  value")
    (goto-char (point-min))
    (let ((emacsvox-audio-indentation t)
          (emacsvox-indentation-presentation 'spoken)
          (emacsvox-show-point nil)
          (tts-punctuation-mode 'all)
          spoken)
      (emacsvox-speak-line-with-speaker
       (lambda (text) (setq spoken text)))
      (should (equal (substring-no-properties spoken) "  value"))
      (let ((facts
             (get-text-property
              2 emacsvox-aural-facts-property spoken)))
        (should (equal (plist-get facts :events) '(indentation-located)))
        (should (= (plist-get facts :indentation-columns) 2))
        (should (eq (plist-get facts :indentation-presentation) 'spoken))))))

(ert-deftest emacsvox-spelling-publishes-capitals-without-spoken-prefixes ()
  "Spelling preserves uppercase source text for the selected aural cue."
  (let (spoken)
    (cl-letf
        (((symbol-function 'tts-speak)
          (lambda (text) (setq spoken text))))
      (emacsvox-speak-spell-word "Ab"))
    (should (equal (substring-no-properties spoken) "A b "))
    (should-not (string-match-p "cap" spoken))
    (should (eq (get-text-property 0 'personality spoken) 'voice-animate))
    (let* ((tts-caps t)
           (emacsvox-capitalization-presentation 'tone)
           (annotated (tts--annotate-capitalization spoken))
           (positioned
            (get-text-property
             0 emacsvox-aural-positioned-facts-property annotated))
           (facts (car positioned)))
      (should (= (length positioned) 1))
      (should (eq (plist-get facts :capitalization-kind) 'capital))
      (should (eq (plist-get facts :capitalization-presentation) 'tone)))))

(ert-deftest emacsvox-phonetic-words-preserve-capitalization-semantically ()
  "Uppercase phonetic words retain a capital boundary instead of saying cap."
  (should (equal (emacsvox-get-phonetic-string ?a) "alpha"))
  (should (equal (emacsvox-get-phonetic-string ?A) "Alpha"))
  (let* ((tts-caps t)
         (emacsvox-capitalization-presentation 'spoken-tone)
         (annotated
          (tts--annotate-capitalization
           (emacsvox-get-phonetic-string ?A)))
         (facts
          (get-text-property
           0 emacsvox-aural-facts-property annotated)))
    (should (eq (plist-get facts :capitalization-kind) 'capital))
    (should
     (eq
      (plist-get facts :capitalization-presentation)
      'spoken-tone))))

(defmacro emacsvox-speak-tests--with-delayed-phonetics (&rest body)
  "Run BODY with captured speech and manually expirable idle timers."
  (declare (indent 0) (debug t))
  `(let ((was-enabled emacsvox-delayed-phonetic-mode))
     (unwind-protect
         (progn
           (emacsvox-delayed-phonetic-mode -1)
           (let ((emacsvox-delayed-phonetic-mode nil)
                 (emacsvox-delayed-phonetic-delay 0.75)
                 (emacsvox--delayed-phonetic-timer nil)
                 (emacsvox--delayed-phonetic-request nil)
                 (emacsvox-aural-submission-occasion nil)
                 (tts-quiet nil)
                 (tts-speaker-process nil)
                 spoken scheduled)
             (save-window-excursion
               (with-temp-buffer
                 (switch-to-buffer (current-buffer))
                 (insert " abA.1")
                 (goto-char 2)
                 (cl-letf
                     (((symbol-function 'tts-letter)
                       (lambda (text) (push (list 'letter text) spoken)))
                      ((symbol-function 'tts-speak)
                       (lambda (text) (push (list 'phonetic text) spoken)))
                      ((symbol-function 'tts-dispatch) #'ignore)
                      ((symbol-function 'tts-stop) #'ignore)
                      ((symbol-function 'emacsvox-icon) #'ignore)
                      ((symbol-function 'input-pending-p) (lambda (&rest _) nil))
                      ((symbol-function 'run-with-idle-timer)
                       (lambda (delay repeat function &rest arguments)
                         (let ((timer (timer-create)))
                           (timer-set-function timer function arguments)
                           (push (list delay repeat timer) scheduled)
                           timer))))
                   (unwind-protect
                       (progn (emacsvox-delayed-phonetic-mode 1) ,@body)
                     (emacsvox-delayed-phonetic-mode -1)))))))
       (emacsvox-delayed-phonetic-mode (if was-enabled 1 -1)))))

(defun emacsvox-speak-tests--expire-phonetics (timer)
  "Invoke captured TIMER, even if cancellation has already made it stale."
  (apply (timer--function timer) (timer--args timer)))

(ert-deftest emacsvox-delayed-phonetics-navigation-is-once-and-configurable ()
  "Navigation speaks normally, then the existing phonetic name once."
  (emacsvox-speak-tests--with-delayed-phonetics
    (let ((emacsvox-aural-submission-occasion 'navigation))
      (emacsvox-speak-char t))
    (should (equal spoken '((letter "a"))))
    (should (equal (seq-take (car scheduled) 2) '(0.75 nil)))
    (let ((timer (nth 2 (car scheduled))))
      (emacsvox-speak-tests--expire-phonetics timer)
      (emacsvox-speak-tests--expire-phonetics timer))
    (should (equal (reverse spoken) '((letter "a") (phonetic "alpha"))))))

(ert-deftest emacsvox-delayed-phonetics-follows-interactive-character-motion ()
  "Actual character motion arms descriptions; deletion does not."
  (require 'emacsvox-advice)
  (emacsvox-speak-tests--with-delayed-phonetics
    (goto-char 1)
    (call-interactively #'forward-char)
    (should (equal spoken '((letter "a"))))
    (emacsvox-speak-tests--expire-phonetics (nth 2 (car scheduled)))
    (should (equal (car spoken) '(phonetic "alpha")))
    (setq scheduled nil)
    (cl-letf (((symbol-function 'emacsvox-speak-edit-operation) #'ignore))
      (call-interactively #'delete-char))
    (should-not scheduled)))

(ert-deftest emacsvox-delayed-phonetics-rapid-navigation-keeps-last-letter ()
  "A stale callback cannot describe the previous character or cancel the new one."
  (emacsvox-speak-tests--with-delayed-phonetics
    (let ((emacsvox-aural-submission-occasion 'navigation))
      (emacsvox-speak-char t)
      (goto-char 4)
      (emacsvox-speak-char t))
    (emacsvox-speak-tests--expire-phonetics (nth 2 (cadr scheduled)))
    (should (equal (reverse spoken) '((letter "a") (letter "A"))))
    (emacsvox-speak-tests--expire-phonetics (nth 2 (car scheduled)))
    (should (equal (car spoken) '(phonetic "Alpha")))))

(ert-deftest emacsvox-delayed-phonetics-cancels-on-input-including-prefix ()
  "Input cancels even before a complete command invokes its pre-command hook."
  (dolist (kind '(command prefix queued))
    (emacsvox-speak-tests--with-delayed-phonetics
      (let ((emacsvox-aural-submission-occasion 'navigation))
        (emacsvox-speak-char t))
      (let ((timer (nth 2 (car scheduled))))
        (pcase kind
          ('command
           (run-hooks 'pre-command-hook)
           (emacsvox-speak-tests--expire-phonetics timer))
          ('prefix
           (let ((num-nonmacro-input-events (1+ num-nonmacro-input-events)))
             (emacsvox-speak-tests--expire-phonetics timer)))
          ('queued
           (cl-letf (((symbol-function 'input-pending-p) (lambda (&rest _) t)))
             (emacsvox-speak-tests--expire-phonetics timer)))))
      (should (equal spoken '((letter "a")))))))

(ert-deftest emacsvox-delayed-phonetics-cancels-on-new-speech-stop-and-disable ()
  "Speech replacement, stop and disable all invalidate the pending callback."
  (dolist (action (list (lambda () (tts-speak "new speech"))
                       (lambda () (tts-letter "b"))
                       (lambda () (tts-dispatch "other text"))
                       #'tts-stop
                       (lambda () (emacsvox-delayed-phonetic-mode -1))))
    (emacsvox-speak-tests--with-delayed-phonetics
      (let ((emacsvox-aural-submission-occasion 'navigation))
        (emacsvox-speak-char t))
      (funcall action)
      (let ((before (copy-tree spoken)))
        (emacsvox-speak-tests--expire-phonetics (nth 2 (car scheduled)))
        (should (equal spoken before)))
      (should-not emacsvox--delayed-phonetic-request))))

(ert-deftest emacsvox-delayed-phonetics-allows-background-fontification ()
  "Changes to highlighting alone do not invalidate the navigated letter."
  (emacsvox-speak-tests--with-delayed-phonetics
    (let ((emacsvox-aural-submission-occasion 'navigation))
      (emacsvox-speak-char t))
    (put-text-property 2 3 'face 'font-lock-keyword-face)
    (emacsvox-speak-tests--expire-phonetics (nth 2 (car scheduled)))
    (should (equal (reverse spoken) '((letter "a") (phonetic "alpha"))))))

(ert-deftest emacsvox-delayed-phonetics-rejects-changed-source-and-context ()
  "Point, text, source window, speech generation and mute changes suppress speech."
  (dolist (kind '(point text display buffer window submission quiet process killed))
    (emacsvox-speak-tests--with-delayed-phonetics
      (let ((emacsvox-aural-submission-occasion 'navigation))
        (emacsvox-speak-char t))
      (let ((source (current-buffer)))
        (pcase kind
          ('point (goto-char 3))
          ('text (save-excursion (insert "z")))
          ('display (put-text-property 2 3 'display "replacement"))
          ('buffer (switch-to-buffer (get-buffer-create " *phonetics-other*")))
          ('window (select-window (split-window)))
          ('submission (cl-incf emacsvox-aural--submission-sequence))
          ('quiet (setq tts-quiet t))
          ('process (setq tts-speaker-process 'different-process))
          ('killed (kill-buffer source)))
        (emacsvox-speak-tests--expire-phonetics (nth 2 (car scheduled)))
        (when (get-buffer " *phonetics-other*")
          (kill-buffer " *phonetics-other*")))
      (should (equal spoken '((letter "a")))))))

(ert-deftest emacsvox-delayed-phonetics-excludes-other-character-speech ()
  "Off, typing/edit feedback, explicit phonetics and nonletters do not arm timers."
  (emacsvox-speak-tests--with-delayed-phonetics
    (emacsvox-speak-this-char ?a)
    (let ((emacsvox-aural-submission-occasion 'edit))
      (emacsvox-speak-char t))
    (emacsvox-speak-char)
    (should (equal (car spoken) '(phonetic "alpha")))
    (let ((emacsvox-aural-submission-occasion 'navigation))
      (dolist (position '(1 5 6 7))
        (goto-char position)
        (emacsvox-speak-char t))
      (goto-char 2)
      (put-text-property 2 3 'display "replacement")
      (emacsvox-speak-char t)
      (remove-text-properties 2 3 '(display nil))
      (emacsvox-delayed-phonetic-mode -1)
      (emacsvox-speak-char t))
    (should-not scheduled)))

(ert-deftest emacsvox-delayed-phonetics-validates-delay-and-cleans-up ()
  "Customize rejects invalid delays; changing delay and disabling release work."
  (emacsvox-speak-tests--with-delayed-phonetics
    (let ((emacsvox-aural-submission-occasion 'navigation))
      (emacsvox-speak-char t))
    (dolist (value '(0 -1 "one" 1.0e+INF 0.0e+NaN))
      (should-error (customize-set-variable 'emacsvox-delayed-phonetic-delay value)))
    (customize-set-variable 'emacsvox-delayed-phonetic-delay 2.0)
    (emacsvox-speak-tests--expire-phonetics (nth 2 (car scheduled)))
    (should (equal spoken '((letter "a"))))
    (emacsvox-delayed-phonetic-mode -1)
    (should-not (memq #'emacsvox--delayed-phonetic-cancel pre-command-hook))
    (dolist (function '(tts-speak tts-letter tts-dispatch tts-stop))
      (should-not (advice-member-p #'emacsvox--delayed-phonetic-cancel function)))))

(ert-deftest emacsvox-speak-rest-of-buffer-advances-after-playback ()
  "Tracked reading advances point and source only after each completion."
  (let ((tts-speaker-process 'speaker)
        (tts-program "windows-outloud")
        (next-identifier 0)
        submissions
        (stops 0))
    (unwind-protect
        (cl-letf
            (((symbol-function 'process-live-p) (lambda (_process) t))
             ((symbol-function 'tts-stop)
              (lambda (&optional _all) (cl-incf stops)))
             ((symbol-function 'emacsvox-icon) #'ignore)
             ((symbol-function 'tts-speak-tracked)
              (lambda (text callback)
                (let ((identifier (cl-incf next-identifier)))
                  (push (list identifier text callback) submissions)
                  identifier))))
          (with-temp-buffer
            (insert "First sentence.  Second sentence.")
            (goto-char (point-min))
            (emacsvox-speak-rest-of-buffer)
            (should (= stops 1))
            (should (= (length submissions) 1))
            (should
             (string-prefix-p "First sentence."
                              (nth 1 (car submissions))))
            (should (= (point) (point-min)))
            (pcase-let ((`(,identifier ,_text ,callback) (car submissions)))
              (funcall callback identifier 'completed))
            (should (= (length submissions) 2))
            (should
             (string-prefix-p "Second sentence."
                              (nth 1 (car submissions))))
            (should
             (= (point)
                (save-excursion
                  (goto-char (point-min))
                  (search-forward "Second")
                  (match-beginning 0))))
            (pcase-let ((`(,identifier ,_text ,callback) (car submissions)))
              (funcall callback identifier 'completed))
            (should-not emacsvox--tracked-reading-session)
            (should (= (point) (point-max)))
            (should-not
             (memq
              #'emacsvox--tracked-reading-pre-command pre-command-hook))))
      (emacsvox--tracked-reading-cancel))))

(ert-deftest emacsvox-speak-rest-of-buffer-interrupts-at-current-chunk ()
  "The next user command stops speech at the current chunk's source start."
  (let ((tts-speaker-process 'speaker)
        (tts-program "windows-outloud")
        (next-identifier 0)
        submissions
        (stops 0))
    (unwind-protect
        (cl-letf
            (((symbol-function 'process-live-p) (lambda (_process) t))
             ((symbol-function 'tts-stop)
              (lambda (&optional _all) (cl-incf stops)))
             ((symbol-function 'emacsvox-icon) #'ignore)
             ((symbol-function 'tts-speak-tracked)
              (lambda (text callback)
                (let ((identifier (cl-incf next-identifier)))
                  (push (list identifier text callback) submissions)
                  identifier))))
          (with-temp-buffer
            (insert "First sentence.  Second sentence.  Third sentence.")
            (goto-char (point-min))
            (emacsvox-speak-rest-of-buffer)
            (pcase-let ((`(,identifier ,_text ,callback) (car submissions)))
              (funcall callback identifier 'completed))
            (let* ((current (car submissions))
                   (stale-identifier (car current))
                   (stale-callback (nth 2 current))
                   (current-start (point))
                   (submission-count (length submissions)))
              (emacsvox--tracked-reading-pre-command)
              (should (= stops 2))
              (should-not emacsvox--tracked-reading-session)
              (should (= (point) current-start))
              (funcall stale-callback stale-identifier 'completed)
              (should (= (length submissions) submission-count))
              (should (= (point) current-start)))))
      (emacsvox--tracked-reading-cancel))))

(ert-deftest emacsvox-speak-rest-of-buffer-cancels-reported-interruption ()
  "A server cancellation never advances or strands tracked reading."
  (let ((tts-speaker-process 'speaker)
        (tts-program "windows-outloud")
        submission)
    (unwind-protect
        (cl-letf
            (((symbol-function 'process-live-p) (lambda (_process) t))
             ((symbol-function 'tts-stop) #'ignore)
             ((symbol-function 'emacsvox-icon) #'ignore)
             ((symbol-function 'tts-speak-tracked)
              (lambda (text callback)
                (setq submission (list text callback))
                1)))
          (with-temp-buffer
            (insert "First sentence. Second sentence.")
            (goto-char (point-min))
            (emacsvox-speak-rest-of-buffer)
            (let ((start (point)))
              (funcall (cadr submission) 1 'cancelled)
              (should-not emacsvox--tracked-reading-session)
              (should (= (point) start)))))
      (emacsvox--tracked-reading-cancel))))

(ert-deftest emacsvox-speak-rest-of-buffer-rejects-unsupported-server ()
  "Rest-of-buffer does not promise tracking on an incapable backend."
  (let ((tts-program "espeak")
        (tts-speaker-process nil))
    (with-temp-buffer
      (insert "Text")
      (should-error
       (emacsvox-speak-rest-of-buffer)
       :type 'user-error)
      (should-not emacsvox--tracked-reading-session))))

(ert-deftest emacsvox-speak-rest-of-buffer-bounds-long-chunks ()
  "Tracked reading caps a sentence without losing forward progress."
  (let ((tts-speaker-process 'speaker)
        (tts-program "windows-outloud")
        (emacsvox-tracked-reading-max-chars 24)
        submission)
    (unwind-protect
        (cl-letf
            (((symbol-function 'process-live-p) (lambda (_process) t))
             ((symbol-function 'tts-stop) #'ignore)
             ((symbol-function 'emacsvox-icon) #'ignore)
             ((symbol-function 'tts-speak-tracked)
              (lambda (text callback)
                (setq submission (list text callback))
                1)))
          (with-temp-buffer
            (insert
             "This sentence contains enough words to exceed the chunk limit.")
            (goto-char (point-min))
            (emacsvox-speak-rest-of-buffer)
            (should submission)
            (should (<= (length (car submission)) 24))
            (should (> (length (car submission)) 0))))
      (emacsvox--tracked-reading-cancel))))

(provide 'emacsvox-speak-tests)
;;; emacsvox-speak-tests.el ends here
