;;; voice-benchmark.el --- Isolated voice workbench timing -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Commentary:
;; Launched only by utils/voice_benchmark.py in a fresh Emacs, never emacsclient.
;; Uses real editor, catalogue, preview and transport code; no test fixtures.
;; Preview completion is observable; this protocol does not report live preview
;; onset to Emacs.  The server benchmark separately measures source consumption.
;;; Code:
(require 'cl-lib)
(require 'json)
(defvar voice-benchmark--job)
(defvar voice-benchmark--samples nil)
(defvar voice-benchmark--processes nil)
(defvar voice-benchmark--busy 0)
(defvar voice-benchmark--generation 7000)

(defun voice-benchmark--read-json (file)
  (with-temp-buffer (insert-file-contents file)
    (json-parse-buffer :object-type 'plist :null-object nil :false-object :false)))

(defun voice-benchmark--elapsed (start)
  (let ((elapsed (* 1000.0 (float-time (time-subtract (current-time) start)))))
    (when (< elapsed 0) (error "Clock moved backwards; discard this run")) elapsed))

(defun voice-benchmark--wait (predicate)
  (let ((deadline (+ (float-time) (plist-get voice-benchmark--job :timeout))))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.001))
    (unless (funcall predicate) (error "Benchmark operation timed out"))))

(defun voice-benchmark--control (process request)
  (let (answer)
    (omnivox--send-control-request process request (lambda (_ response) (setq answer response)))
    (voice-benchmark--wait (lambda () answer)) answer))

(defun voice-benchmark--start (name)
  (let* ((route (plist-get voice-benchmark--job :route))
         (process
          (make-process :name name :noquery t :connection-type 'pipe :coding 'utf-8-unix
                        :command (append (list (plist-get voice-benchmark--job :server))
                                         (append (plist-get voice-benchmark--job :server_args) nil)
                                         (list "--engine" (plist-get route :engine) "--audio-output"
                                               (plist-get voice-benchmark--job :audio_output)))
                        :stderr (get-buffer-create " *voice-benchmark-stderr*")
                        :filter #'tts--speaker-process-filter)))
    (push process voice-benchmark--processes)
    (process-put process 'tts--speech-process-generation (cl-incf voice-benchmark--generation))
    process))

(defun voice-benchmark--busy-result (_waiter result)
  (when (eq (plist-get result :status) 'busy) (cl-incf voice-benchmark--busy)))

(defun voice-benchmark--ready ()
  (let* ((state (emacsvox-aural-voice-editor--get :engine-controls))
         (status (plist-get (plist-get state :result) :status))
         (waiter (plist-get state :waiter)))
    ;; A retry clears its timer before the next asynchronous response arrives.
    (and (not (eq status 'checking)) (not (plist-get state :retry))
         (or (null waiter) (omnivox-parameters--waiter-cancelled waiter)))))

(defun voice-benchmark--controls (iteration warmup first)
  (setq voice-benchmark--busy 0)
  (let* ((start (current-time))
         (_ (emacsvox-aural-voice-engine-controls-open))
         (command-ms (voice-benchmark--elapsed start)))
    (when (display-graphic-p) (redisplay t))
    (voice-benchmark--wait #'voice-benchmark--ready)
    (unless (emacsvox-aural-voice-engine-controls--fresh-p)
      (error "Controls unavailable after %.0f ms: %s"
             (voice-benchmark--elapsed start)
             (emacsvox-aural-voice-engine-controls--status-text)))
    (when (or first (not warmup))
      (push (list :case (if first "controls_first_open" "controls_open")
                  :iteration iteration :command_ms command-ms
                  :ready_ms (voice-benchmark--elapsed start) :busy_replies voice-benchmark--busy)
            voice-benchmark--samples))))

(defun voice-benchmark--preview-result (&optional value)
  (voice-benchmark--wait (lambda () (not (emacsvox-aural-voice-editor--get :preview-operation))))
  (let* ((result (emacsvox-aural-voice-editor--get :preview-result))
         (last (plist-get (car (last (plist-get result :results))) :last-started))
         (route (plist-get voice-benchmark--job :route))
         (realized (plist-get last :realized)))
    (unless (and (eq (plist-get result :status) 'completed)
                 (equal (plist-get realized :engine_id) (plist-get route :engine))
                 (equal (plist-get realized :voice_id) (plist-get route :voice)))
      (error "Preview did not complete with the exact requested voice: %S" result))
    (when value
      (let* ((application (plist-get last :native_application))
             (response (voice-benchmark--control tts-speaker-process
                        (list :type "explain_voice_parameters_v1"
                              :source (list :mode "applied" :plan_id (plist-get application :plan_id)))))
             (evidence (plist-get response :result)))
        (unless (and (equal (plist-get application :status) "applied")
                     (equal (plist-get evidence :status) "ready")
                     (seq-some (lambda (parameter)
                                 (and (equal (plist-get parameter :id) (plist-get route :parameter))
                                      (equal (plist-get parameter :value) value)
                                      (eq (plist-get parameter :read_back) t)))
                               (plist-get evidence :parameters)))
          (error "Preview native readback mismatch: %S" response))))))

(defun voice-benchmark--resources ()
  (let* ((attributes (process-attributes (emacs-pid))) (cpu (alist-get 'time attributes)))
    (list :rss_kib (or (alist-get 'rss attributes) :null)
          :cpu_seconds (if cpu (float-time cpu) :null)
          :gc_count gcs-done :gc_seconds gc-elapsed)))

(defun voice-benchmark--run ()
  (setq voice-benchmark--job (voice-benchmark--read-json (getenv "EMACSVOX_BENCHMARK_JOB")))
  (setq user-emacs-directory (file-name-as-directory (plist-get voice-benchmark--job :state_directory)))
  (add-to-list 'load-path (expand-file-name "lisp" (plist-get voice-benchmark--job :emacsvox_root)))
  (setq load-prefer-newer nil native-comp-jit-compilation nil)
  (require 'emacsvox-preamble)
  (require 'emacsvox-aural-provider-workflows)
  (require 'omnivox-voices)
  (require 'omnivox-preview)
  (require 'emacsvox-aural-voice-engine-controls)
  (setq tts-speaker-process nil tts-notify-process nil)
  (omnivox-configure-tts)
  (require 'voice-setup)
  (voice-setup)
  (dolist (fn '(emacsvox-aural-voice-editor-refresh emacsvox-aural-voice-engine-controls-open))
    (unless (string-suffix-p ".elc" (or (symbol-file fn) "")) (error "Current byte-code required: %s" fn)))
  (setq tts-program "omnivox" tts-voice-preview-function #'omnivox-preview-voice-sequence
        emacsvox-speak-messages nil emacsvox-use-icons nil)
  (tts-queue--install)
  (advice-add 'omnivox-parameters--deliver :before #'voice-benchmark--busy-result)
  (setq tts-speaker-process (voice-benchmark--start "benchmark-main")
        tts-notify-process (voice-benchmark--start "benchmark-notification"))
  (omnivox--negotiate-processes)
  (voice-benchmark--wait
   (lambda () (seq-every-p (lambda (process)
                            (process-get process omnivox--control-registration-property))
                          voice-benchmark--processes)))
  (setq tts-speech-rate (plist-get voice-benchmark--job :rate))
  (set-default 'tts-speech-rate (plist-get voice-benchmark--job :rate))
  (dolist (process voice-benchmark--processes)
    (process-send-string process (format "tts_set_speech_rate %d\n" (plist-get voice-benchmark--job :rate))))
  (let* ((route (plist-get voice-benchmark--job :route))
         (source (get-buffer-create " *benchmark-source*"))
         (start (current-time))
         (resources-before (voice-benchmark--resources)))
    (emacsvox-aural-voice-editor-experiment
     (list (list :engine-id (plist-get route :engine)) (list :voice-id (plist-get route :voice)))
     source "The quick brown fox checks interactive speech latency.")
    (when (display-graphic-p) (redisplay t))
    (push (list :case "editor_first_open" :iteration 0 :command_ms (voice-benchmark--elapsed start)) voice-benchmark--samples)
    (emacsvox-aural-voice-editor--put :policy (list :engine-order (list (plist-get route :engine)) :fallback '(:engines nil)))
    (let ((warmups (plist-get voice-benchmark--job :warmups))
          (count (plist-get voice-benchmark--job :iterations)))
      (dotimes (i (+ warmups count))
        (let* ((warmup (< i warmups)) (iteration (- i warmups)) (start (current-time)))
          (emacsvox-aural-voice-editor-refresh)
          (emacsvox-aural-voice-editor-next)
          (when (display-graphic-p) (redisplay t))
          (unless warmup (push (list :case "editor_navigation" :iteration iteration :command_ms (voice-benchmark--elapsed start)) voice-benchmark--samples))
          (setq start (current-time))
          (emacsvox-aural-voice-editor-play)
          (let ((command-ms (voice-benchmark--elapsed start)))
            (voice-benchmark--preview-result)
            (unless warmup (push (list :case "common_preview" :iteration iteration :command_ms command-ms
                                      :preview_complete_ms (voice-benchmark--elapsed start)) voice-benchmark--samples)))
          (when (plist-get route :parameter)
            (voice-benchmark--controls iteration warmup (= i 0))
            (setq start (current-time))
            (emacsvox-aural-voice-engine-controls--apply (plist-get route :parameter) 'set (plist-get route :value))
            (let ((command-ms (voice-benchmark--elapsed start)))
              (voice-benchmark--wait (lambda () (not (emacsvox-aural-voice-editor--get :preview-operation))))
              (let ((complete-ms (voice-benchmark--elapsed start)))
                (voice-benchmark--preview-result (plist-get route :value))
                (unless warmup (push (list :case "native_adjustment" :iteration iteration :command_ms command-ms
                                          :preview_complete_ms complete-ms) voice-benchmark--samples))))
            (emacsvox-aural-voice-editor--put :automatic-sample nil)
            (emacsvox-aural-voice-engine-controls-reset-all)
            (emacsvox-aural-voice-editor--put :automatic-sample t)
            (emacsvox-aural-voice-engine-controls-back)))))
    (list :emacs_version emacs-version :graphical (if (display-graphic-p) t :false)
          :clock "Emacs current-time; negative intervals rejected"
          :measurement "Editor command return and preview completion; preview onset unavailable"
          :resources_before resources-before :resources_after (voice-benchmark--resources)
          :timing_samples (vconcat (nreverse voice-benchmark--samples)))))

(let ((status 1))
  (unwind-protect
      (condition-case err
          (let ((result (voice-benchmark--run)))
            (with-temp-file (getenv "EMACSVOX_BENCHMARK_OUTPUT") (insert (json-serialize result) "\n"))
            (setq status 0))
        (error (let ((standard-output 'external-debugging-output))
                 (princ (format "Voice benchmark failed: %S\n" err)))))
    (advice-remove 'omnivox-parameters--deliver #'voice-benchmark--busy-result)
    (dolist (process voice-benchmark--processes)
      (when (process-live-p process) (delete-process process))))
  (kill-emacs status))
;;; voice-benchmark.el ends here
