;;; diagnose-delivery.el --- Reproduce delivery investigation evidence -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:

;; Run from the repository root in a fresh -Q --batch Emacs.  Set
;; EMACSVOX_DELIVERY_LOAD to source (default) or compiled.  Compiled mode
;; requires current in-tree byte-code.  Only isolated pipe processes and the
;; log-null fallback are used; this script never requests audio playback.
;; EMACSVOX_DELIVERY_TESTS=none skips ERT when repeating the measurements.
;; The observer and diagnostic probes report current behaviour, not acceptance
;; assertions that would require retaining the weaknesses they expose.

;;; Code:

(require 'cl-lib)
(require 'cl-macs)
(require 'ert)
(require 'benchmark)
;; Load compressed-source handling before choosing source-only loading.
(require 'jka-compr)

(defconst delivery-investigation--root
  (file-name-directory
   (directory-file-name (file-name-directory (or load-file-name buffer-file-name)))))
(defconst delivery-investigation--mode (or (getenv "EMACSVOX_DELIVERY_LOAD") "source"))
(unless (member delivery-investigation--mode '("source" "compiled"))
  (error "EMACSVOX_DELIVERY_LOAD must be source or compiled"))
(setq ring-bell-function #'ignore)
(fset 'ding #'ignore)
(setq-default emacsvox-play-program nil)
(setenv "TTS_PROGRAM" (expand-file-name "servers/log-null" delivery-investigation--root))
(add-to-list 'load-path (expand-file-name "test" delivery-investigation--root))
(add-to-list 'load-path (expand-file-name "lisp" delivery-investigation--root))

(let ((load-suffixes (if (equal delivery-investigation--mode "source") '(".el") load-suffixes))
      (load-prefer-newer nil))
  (load "emacsvox-preamble.el" nil t)
  (require 'tts-queue-handoff-tests)
  (require 'emacsvox-aural-replay-tests)
  (require 'omnivox-native-runtime-tests)
  (require 'omnivox-rich-tone-tests)
  (require 'emacsvox-aural-recording-tests)
  (require 'omnivox-remote-tests))

(defun delivery-investigation--paths ()
  "Reject another checkout or loading mode for the investigated functions."
  (dolist (function '(emacsvox-aural--build-structured-timeline
                      emacsvox-aural--assembly-span
                      emacsvox-aural--timeline-candidate
                      emacsvox-aural--bind-timeline-candidate
                      emacsvox-aural-reproduce-delivery
                      emacsvox-aural-replay--span-map
                      emacsvox-aural--submit-content
                      emacsvox-aural--frame-structured-timeline
                      tts--dispatch-write-packet tts-queue--send
                      omnivox--prepare-choice-dispatch))
    (let ((path (symbol-file function 'defun)))
      (unless (and (file-in-directory-p path delivery-investigation--root)
                   (string-suffix-p (if (equal delivery-investigation--mode "source")
                                        ".el" ".elc") path))
        (error "Unexpected implementation of %S: %s" function path))
      (princ (format "Loaded %S from %s\n" function path)))))

(defun delivery-investigation--observer-probe (outcome)
  "Report the delivery outcome when a post-write observer has OUTCOME."
  (omnivox-choice-playback-test--with-runtime
   (let* ((run (omnivox-choice-timeline-test--run 'bolden nil))
          writes terminals result caught
          (tts--tracked-completion-function
           (lambda (_id status) (push status terminals)))
          (emacsvox-aural-plan-presented-hook
           (list (lambda (_plan)
                   (pcase outcome
                     ('error (error "Injected presentation observer failure"))
                     ('stop (tts-stop))))))
          (emacsvox-aural-last-delivery-failure nil))
     (setf (emacsvox-aural-concrete-plan-object-end-p (car run)) t)
     (cl-letf (((symbol-function 'tts-voice-reset-code) (lambda () ""))
               ((symbol-function 'process-send-string)
                (lambda (_process command) (push command writes))))
       (condition-case condition
           (setq result
                 (emacsvox-aural-call-with-delivery-transaction
                  speaker (lambda ()
                            (emacsvox-aural-queue-concrete-plan (car run) (cadr run))
                            (tts--protocol-dispatch))))
         (error (setq caught (error-message-string condition))))
       ;; A terminal event after return cannot rescue an abandoned owner.
       (tts--speaker-process-filter speaker "__EMACSVOX_TRACKED__ 1 completed\n")
       (tts--dispatch-drain speaker))
     (list :observer outcome :returned result :error caught
           :timeline-writes (cl-count-if (lambda (wire) (string-prefix-p "emacsvox_timeline " wire)) writes)
           :stop-writes (cl-count "s\n" writes :test #'equal)
           :terminal-callbacks terminals
           :remaining-owners (process-get speaker 'tts--dispatch-owner-count)
           :delivery-failure (plist-get emacsvox-aural-last-delivery-failure :reason)))))

(defun delivery-investigation--readiness-probe ()
  "Report submission diagnostics for a capability-pending process."
  (emacsvox-test--with-transport-scheme
   (let ((original (symbol-function 'emacsvox-aural-call-with-delivery-transaction)) events)
     (cl-letf (((symbol-function 'emacsvox-aural-call-with-delivery-transaction)
                (lambda (owner function &rest arguments)
                  (emacsvox-aural-set-delivery-readiness owner 'pending)
                  (apply original owner function arguments)))
               ((symbol-function 'emacsvox-aural-diagnostic-log-event)
                (lambda (event &rest fields) (push (cons event fields) events))))
       (let ((result (emacsvox-test--capture-native-timeline "Readiness probe")))
         (list :readiness 'pending
               :wire-bytes (string-bytes (plist-get result :wire))
               :submission-returned (emacsvox-aural-submission-p (plist-get result :submission))
               :submission-complete-status (plist-get (cdr (assq 'submission-complete events)) :status)
               :delivery-outcome (cdr (assq 'delivery-outcome events))))))))

(defun delivery-investigation--resource-probe (mode)
  "Record resource mapping during compatibility capture and MODE assembly."
  (omnivox-choice-playback-test--with-runtime
   (let* ((run (omnivox-choice-timeline-test--run 'bolden nil))
          (build (symbol-function 'emacsvox-aural--build-structured-timeline))
          (phase 'capture) calls)
     (setf (emacsvox-aural-concrete-plan-context (car run)) '(:icons-enabled t)
           (emacsvox-aural-concrete-plan-before (car run))
           (list (emacsvox-aural--make-concrete-action
                  :kind 'cue :audio-mode mode :resource "/tmp/resource-order.ogg")))
     (cl-letf (((symbol-function 'tts-voice-reset-code) (lambda () ""))
               ((symbol-function 'process-send-string) #'ignore)
               ((symbol-function 'omnivox-remote-resource)
                (lambda (path) (push phase calls) path))
               ((symbol-function 'emacsvox-aural--build-structured-timeline)
                (lambda (&rest args)
                  (setq phase 'assembly)
                  (apply build args))))
       (emacsvox-aural-call-with-delivery-transaction
        speaker (lambda ()
                  (emacsvox-aural-queue-concrete-plan (car run) (cadr run))
                  (tts--protocol-dispatch))))
     (list :cue-mode mode :resource-phases (nreverse calls)))))

(defun delivery-investigation--measure (name count text coalesce &optional own)
  "Measure COUNT runs of TEXT named NAME with COALESCE and optional OWN copying."
  (let* ((emacsvox-aural-submission-delivery-policy 'ordered)
         (runs (cl-loop for index below count collect
                       (list (emacsvox-aural--make-concrete-plan
                              :object-id (if coalesce 'shared index)
                              :content (emacsvox-aural--make-concrete-content
                                        :text text :speak t
                                        :voice-style (unless coalesce
                                                       (list :gain (if (cl-evenp index) 0 9))))
                              :context '(:icons-enabled nil)) text nil)))
         samples document frames)
    ;; Warm runtime code, then use three independent collections for a baseline.
    (emacsvox-aural--build-structured-timeline 1 1 runs)
    (dotimes (_ 3)
      (garbage-collect)
      (let ((before (memory-use-counts)))
        (let ((timing (benchmark-run
                      1
                      (let ((built (emacsvox-aural--build-structured-timeline 1 1 runs)))
                        (setq document (if own
                                           (emacsvox-aural--candidate-document
                                            (emacsvox-aural--timeline-candidate built))
                                         (car built))
                              frames (emacsvox-aural--frame-structured-timeline document))))))
          (push (list :seconds (car timing) :collections (nth 1 timing)
                      :gc-seconds (nth 2 timing)
                      :allocation-count-deltas (cl-mapcar #'- (memory-use-counts) before)) samples))))
    (list :case name :input-runs count :text-bytes (* count (string-bytes text))
          :spans (length (plist-get document :spans)) :frames (length frames)
          :wire-bytes (apply #'+ (mapcar #'string-bytes frames))
          :samples (nreverse samples))))

(princ (format "Delivery investigation: Emacs %s, %s\n" emacs-version delivery-investigation--mode))
(delivery-investigation--paths)
(unless (equal (getenv "EMACSVOX_DELIVERY_TESTS") "none")
  (let ((stats (ert-run-tests-batch
                '(or "^emacsvox-aural-" "^tts-queue-" "^tts-handoff-" "^tts-preparation-"
                     "^omnivox-choice-" "^omnivox-native-runtime-"
                     "^omnivox-rich-tone-" "^omnivox-extended-tone-" "^omnivox-remote-"))))
    (unless (and (> (ert-stats-total stats) 0)
                 (= (ert-stats-total stats) (ert-stats-completed stats))
                 (= 0 (ert-stats-completed-unexpected stats))
                 (= 0 (ert-stats-skipped stats)))
      (error "Delivery investigation baseline failed"))))
(delivery-investigation--paths)
(dolist (outcome '(normal error stop))
  (princ (format "Observer probe: %S\n" (delivery-investigation--observer-probe outcome))))
(princ (format "Readiness probe: %S\n" (delivery-investigation--readiness-probe)))
(dolist (mode '(overlay insert))
  (princ (format "Resource probe: %S\n" (delivery-investigation--resource-probe mode))))
(princ (format "Measurement environment: %S\n"
               (list :emacs emacs-version :system system-configuration
                     :gc-cons-threshold gc-cons-threshold :gc-cons-percentage gc-cons-percentage
                     :allocation-units '(conses floats vector-cells symbols string-chars intervals strings))))
(dolist (case `((navigation 1 "Next heading" nil)
                (distinct-spans 240 "café 日本 next " nil)
                (coalesced-runs 240 "café 日本 next " t)
                (large-timeline 4096 "café 日本 next " nil)
                (long-span 1 ,(make-string 300000 ?x) nil)))
  (princ (format "Measurement: %S\n" (apply #'delivery-investigation--measure case)))
  (princ (format "Owned candidate measurement: %S\n"
                 (apply #'delivery-investigation--measure (append case '(t))))))

;;; diagnose-delivery.el ends here
