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

(defun emacsvox-frame-test--await (workers ticket count)
  (let ((deadline (+ (float-time) 10)))
    (while (and (< (float-time) deadline)
                (< (cl-count-if (lambda (p) (assoc ticket (process-get p 'heard))) workers) count))
      (accept-process-output nil 0.02)))
  (should (equal count (cl-count-if
                        (lambda (p) (member (cons ticket "completed") (process-get p 'heard)))
                        workers))))

(ert-deftest emacsvox-frame-speech-four-workers-one-conversation ()
  (should (display-graphic-p))
  (dolist (name '("compat" "acp" "shell-maker" "agent-shell" "markdown-mode"))
    (add-to-list 'load-path (expand-file-name name (getenv "EMACSVOX_TEST_DEPS_DIR"))))
  (require 'agent-shell)
  (require 'emacsvox-agent-shell)
  (require 'emacsvox-agent-shell-frames)
  (let* ((a (selected-frame)) (b (make-frame))
         (buffer (generate-new-buffer "Frame subscription test"))
         (workers (mapcar #'emacsvox-frame-test--worker
                          '("Alice main" "Alice notification" "Bob main" "Bob notification")))
         (actor (emacsvox-frame-speech-attach a (nth 0 workers) (nth 1 workers) "omnivox"))
         (other (emacsvox-frame-speech-attach b (nth 2 workers) (nth 3 workers) "omnivox"))
         (event-count 0) steering)
    (unwind-protect
        (with-current-buffer buffer
          (setq major-mode 'agent-shell-mode)
          (setq-local agent-shell--state (make-hash-table :test #'eq))
          (puthash :buffer buffer agent-shell--state)
          (setq-local emacsvox-agent-shell-speech-level 'response)
          (setq-local emacsvox-comint-autospeak t)
          (setq-local emacsvox-agent-shell-signal-processing nil)
          (setq-local emacsvox-agent-shell-speak-permissions t)
          (set-window-buffer (frame-selected-window a) buffer)
          (set-window-buffer (frame-selected-window b) buffer)
          (emacsvox-agent-shell-subscribe-frame buffer a)
          (emacsvox-agent-shell-subscribe-frame buffer b)
          (emacsvox-agent-shell-subscribe-frame buffer b)
          (emacsvox-agent-shell--lifecycle-event-setup)
          (emacsvox-agent-shell--permission-event-setup)
          (agent-shell-subscribe-to :shell-buffer buffer
                                    :on-event (lambda (_event) (cl-incf event-count)))
          ;; Keep the public Agent Shell events, its caches and both frame
          ;; workers real. Use short tracked submissions at the final audio
          ;; boundary so playback and cancellation can be checked per worker.
          (cl-letf (((symbol-function 'emacsvox-agent-shell--submit-automatic-text-feedback)
                     (lambda (words &rest _)
                       (when (equal words "Shared reply") (emacsvox-frame-test--speak 301))))
                    ((symbol-function 'emacsvox-agent-shell--notify-background)
                     (lambda (facts &rest _)
                       (when (memq 'agent-permission-requested (plist-get facts :events))
                         (tts-notify-apply #'emacsvox-frame-test--speak 302)))))
            (emacsvox-frame-speech-call actor #'agent-shell--emit-event :event 'input-submitted)
            (setq-local emacsvox-agent-shell--pending-bodies (make-hash-table :test #'equal))
            (puthash "s-agent_message_chunk" "Shared reply" emacsvox-agent-shell--pending-bodies)
            (setq-local emacsvox-agent-shell--pending-speech-qualified-ids '("s-agent_message_chunk"))
            (agent-shell--emit-event :event 'turn-complete :data '((:stop-reason . "end_turn")))
            (should (equal emacsvox-agent-shell--last-completed-answer "Shared reply"))
            (emacsvox-frame-test--await workers 301 2)
            (should (and (assoc 301 (process-get (nth 0 workers) 'heard))
                         (assoc 301 (process-get (nth 2 workers) 'heard))))
            (agent-shell--emit-event :event 'permission-request :data '((:request-id . 8)))
            (emacsvox-frame-test--await workers 302 2)
            (dolist (notify (list (nth 1 workers) (nth 3 workers)))
              (should (assoc 302 (process-get notify 'heard)))
              (should (equal 8 (nth 1 (process-get notify 'emacsvox-frame-permission)))))
            (emacsvox-frame-speech-call other #'tts-stop 'all)
            (should (process-get (nth 3 workers) 'emacsvox-frame-permission))
            (emacsvox-frame-speech-call actor #'agent-shell--emit-event
                                       :event 'permission-response :data '((:request-id . 8)))
            (should-not (process-get (nth 1 workers) 'emacsvox-frame-permission))
            (should-not (process-get (nth 3 workers) 'emacsvox-frame-permission))
            (should (= event-count 4))
            ;; Both the callback and the application state belong to the
            ;; person who submitted the steering request.
            (emacsvox-frame-speech-call
             actor #'emacsvox-agent-shell--frame-steering
             (lambda (&rest req) (setq steering (plist-get req :on-success)))
             :request '((:method . "_session/steering"))
             :on-success (lambda () (cl-incf event-count) (tts-dispatch "q {Steering accepted}")
                           (emacsvox-frame-test--speak 303)))
            (emacsvox-frame-speech-call other steering)
            (emacsvox-frame-test--await workers 303 1)
            (should (assoc 303 (process-get (car workers) 'heard)))
            ;; Both frames still follow this conversation, but only Alice
            ;; is reading it now. Bob's notification must omit its content.
            (set-window-buffer (frame-selected-window b) (get-buffer-create " *Other work*"))
            (setq-local emacsvox-agent-shell-speech-level 'auto)
            (let ((emacsvox-agent-shell-foreground-speech-level 'response)
                  (emacsvox-agent-shell-background-speech-level 'notify)
                  (emacsvox-agent-shell-signal-processing t))
              (cl-letf (((symbol-function 'emacsvox-agent-shell--submit-automatic-text-feedback)
                         (lambda (words &rest _)
                           (when (equal words "Private body") (emacsvox-frame-test--speak 304))))
                        ((symbol-function 'emacsvox-agent-shell--submit-icon-feedback) #'ignore)
                        ((symbol-function 'emacsvox-agent-shell--notify-background)
                         (lambda (_facts _occasion _icon words &rest _)
                           (should (equal words "finished."))
                           (tts-notify-apply #'emacsvox-frame-test--speak 305))))
                (setq-local emacsvox-agent-shell--pending-bodies (make-hash-table :test #'equal))
                (puthash "next-agent_message_chunk" "Private body" emacsvox-agent-shell--pending-bodies)
                (setq-local emacsvox-agent-shell--pending-speech-qualified-ids '("next-agent_message_chunk"))
                (agent-shell--emit-event :event 'turn-complete :data '((:stop-reason . "end_turn")))
                (emacsvox-frame-test--await workers 304 1)
                (emacsvox-frame-test--await workers 305 1)
                (should (assoc 304 (process-get (nth 0 workers) 'heard)))
                (should (assoc 305 (process-get (nth 3 workers) 'heard)))))
            (emacsvox-frame-speech-detach b)
            (should (equal (emacsvox-agent-shell--subscribers) (list (cons a actor))))
            (agent-shell--emit-event :event 'permission-request :data '((:request-id . 9)))
            (should (equal 9 (nth 1 (process-get (nth 1 workers) 'emacsvox-frame-permission))))
            (should-not (process-get (nth 3 workers) 'emacsvox-frame-permission))
            (emacsvox-frame-speech-call actor #'tts-stop t)
            (should-not (process-get (nth 1 workers) 'emacsvox-frame-permission))
            (kill-buffer buffer)
            (should-not emacsvox-agent-shell--frame-hooks-installed)))
      (when (buffer-live-p buffer) (kill-buffer buffer))
      (emacsvox-frame-speech-detach a)
      (emacsvox-frame-speech-detach b)
      (delete-frame b)
      (dolist (p workers) (delete-process p)))))

(let ((report (getenv "EMACSVOX_TEST_FRAME_REPORT")))
  (let ((stats (ert-run-tests-batch "^emacsvox-frame-speech-four-")))
    (when report
      (with-temp-file report
        (insert (if (zerop (ert-stats-completed-unexpected stats))
                    "Two Emacs frames reached their four desktop Omnivox workers. Shared Agent Shell events passed.\n"
                  "Desktop frame routing failed.\n"))
        (unless (zerop (ert-stats-completed-unexpected stats))
          (when-let* ((messages (get-buffer "*Messages*")))
            (insert-buffer-substring messages)))))
    (kill-emacs (if (zerop (ert-stats-completed-unexpected stats)) 0 1))))
;;; frame-speech-workers.el ends here
