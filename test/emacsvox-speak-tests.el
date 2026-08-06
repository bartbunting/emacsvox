;;; emacsvox-speak-tests.el --- Core tracked reading tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for interruptible rest-of-buffer reading.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'emacsvox-speak)

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
