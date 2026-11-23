;;; frame-speech-workers.el --- Exercise independent Omnivox frames -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Run in a fresh graphical Emacs with EMACSVOX_TEST_OMNIVOX pointing to
;; a desktop Omnivox executable. Each real worker uses eSpeak and null output.
(require 'ert)
(require 'tts-speak)
(require 'emacsvox-frame-speech)

(defvar emacsvox-frame-test--ticket 0)

(defun emacsvox-frame-test--speak (ticket)
  (process-send-string tts-speaker-process
                       (format "q {frame speech check}\nemacsvox_tracked_dispatch %d\n" ticket)))

(defun emacsvox-frame-test--key ()
  (interactive)
  (emacsvox-frame-test--speak emacsvox-frame-test--ticket)
  (tts-notify-apply #'emacsvox-frame-test--speak (1+ emacsvox-frame-test--ticket)))

(defun emacsvox-frame-test--worker (name)
  (make-process
   :name name :command (list (getenv "EMACSVOX_TEST_OMNIVOX") "--engine" "espeak" "--audio-output" "null")
   :noquery t :connection-type 'pipe :coding 'utf-8-unix
   :stderr (get-buffer-create " *Frame worker diagnostics*")
   :filter (lambda (process bytes)
             (let* ((text (concat (process-get process 'partial) bytes))
                    (lines (split-string text "\n")))
               (process-put process 'partial (car (last lines)))
               (dolist (line (butlast lines))
                 (when (string-match "\\`__EMACSVOX_TRACKED__ \\([0-9]+\\) \\([a-z]+\\)\\'" line)
                   (push (cons (string-to-number (match-string 1 line)) (match-string 2 line))
                         (process-get process 'heard))))))))

(ert-deftest emacsvox-frame-speech-four-desktop-workers ()
  (should (display-graphic-p))
  (let ((a (selected-frame)) (b (make-frame)) workers)
    (unwind-protect
        (progn
          (dolist (name '("Frame A main" "Frame A notifications" "Frame B main" "Frame B notifications"))
            (push (emacsvox-frame-test--worker name) workers))
          (setq workers (nreverse workers))
          (let ((left (emacsvox-frame-speech-attach a (nth 0 workers) (nth 1 workers) "omnivox"))
                (right (emacsvox-frame-speech-attach b (nth 2 workers) (nth 3 workers) "omnivox")))
            (with-selected-frame a
              (let ((emacsvox-frame-test--ticket 100)) (command-execute #'emacsvox-frame-test--key)))
            (with-selected-frame b
              (let ((emacsvox-frame-test--ticket 200)) (command-execute #'emacsvox-frame-test--key))
              (emacsvox-frame-speech-call left #'emacsvox-frame-test--speak 102))
            (let ((deadline (+ (float-time) 12)))
              (while (and (< (float-time) deadline)
                          (< (apply #'+ (mapcar (lambda (p) (length (process-get p 'heard))) workers)) 5))
                (accept-process-output nil 0.02)))
            (should (equal (mapcar (lambda (p) (reverse (process-get p 'heard))) workers)
                           '(((100 . "completed") (102 . "completed")) ((101 . "completed"))
                             ((200 . "completed")) ((201 . "completed")))))
            (emacsvox-frame-speech-detach a)
            (should-not (emacsvox-frame-speech-call left #'error "Stale frame callback"))
            (should (eq (emacsvox-frame-speech-call right (lambda () tts-speaker-process)) (nth 2 workers)))))
      (emacsvox-frame-speech-detach a)
      (emacsvox-frame-speech-detach b)
      (delete-frame b)
      (dolist (p workers) (delete-process p)))))

(let ((report (getenv "EMACSVOX_TEST_FRAME_REPORT")))
  (let ((stats (ert-run-tests-batch "^emacsvox-frame-speech-four-")))
    (when report
      (with-temp-file report
        (insert (if (zerop (ert-stats-completed-unexpected stats))
                    "Two Emacs frames reached their four desktop Omnivox workers.\n"
                  "Desktop frame routing failed.\n"))
        (unless (zerop (ert-stats-completed-unexpected stats))
          (when-let* ((messages (get-buffer "*Messages*")))
            (insert-buffer-substring messages)))))
    (kill-emacs (if (zerop (ert-stats-completed-unexpected stats)) 0 1))))
;;; frame-speech-workers.el ends here
