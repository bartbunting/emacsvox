;;; emacsvox-speak-tests.el --- Core tracked reading tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for interruptible rest-of-buffer reading.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-speak)

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
      (should (= (plist-get merged :indentation-columns) 2)))))

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
    (should (eq (get-text-property 0 'personality spoken) voice-animate))
    (let* ((tts-caps t)
           (emacsvox-capitalization-presentation 'tone)
           (annotated (tts--annotate-capitalization spoken))
           (facts
            (get-text-property
             0 emacsvox-aural-facts-property annotated)))
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
