;;; diagnose-client-handoff.el --- Isolated submission probes -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Run in a fresh batch Emacs to print observations of submission ordering.
;; These are diagnostic probes, not assertions that the current bugs must stay.
;; They replace process writes and send no speech.  See
;; docs/voice-editor-client-handoff-review.org for the reviewed target behavior.

;;; Code:

(unless noninteractive
  (error "Run the handoff diagnostic in a fresh batch Emacs"))
(setq load-prefer-newer t)
(let* ((root (expand-file-name "../" (file-name-directory load-file-name)))
       (directory (expand-file-name "lisp/" root)))
  (add-to-list 'load-path directory)
  (dolist (file '("emacsvox-preamble.el" "emacsvox-aural-transport.el"
                  "tts-speak.el" "omnivox-voices.el" "emacsvox-speak.el"))
    (load (expand-file-name file directory) nil t)))
(require 'cl-lib)
(require 'emacsvox-aural-submission)
(require 'emacsvox-speak)
(require 'omnivox-voices)

(defun emacsvox-handoff-review--probe (scenario)
  "Return observations of SCENARIO using an isolated pipe process."
  (let* ((process (make-pipe-process :name "handoff-review" :noquery t))
         (tts-speaker-process process)
         (tts-notify-process nil)
         (tts-program "omnivox")
         (tts--tracked-dispatch-sequence 0)
         (tts--tracked-dispatches (make-hash-table :test #'eql))
         (tts--marker-dispatches (make-hash-table :test #'eql))
         (tts--dispatch-lifecycles (make-hash-table :test #'eql))
         (tts-stopped-hook nil)
         (omnivox-last-realized-routes (make-hash-table :test #'equal))
         (omnivox--utterance-logical-voices (make-hash-table :test #'equal))
         (omnivox-realized-route-changed-hook nil)
         (tts-realized-voice-changed-hook nil)
         (emacsvox-aural-delivery-failed-hook nil)
         (emacsvox-aural-presentation-history nil)
         (emacsvox-aural--pending-deliveries (make-hash-table :test #'equal))
         (emacsvox-aural-submission-delivery-policy 'ordered)
         (emacsvox-aural-submission-controls-interruption nil)
         (emacsvox-speak-messages nil)
         callbacks writes injected nested-captured result
         (tts--marker-event-function
          (unless (eq scenario 'ordinary)
            (lambda (&rest _) (push 'marker callbacks))))
         (tts--tracked-completion-function
          (unless (eq scenario 'ordinary)
            (lambda (_id status) (push status callbacks))))
         (event '(:protocol_version 2 :dispatch_id 1 :sequence 1
                  :type "utterance_started" :utterance_id 1
                  :logical_voice_id "bolden" :engine_id "espeak"
                  :actual_voice (:engine_id "espeak" :voice_id "en")))
         (plan (emacsvox-aural--make-concrete-plan
                :content (emacsvox-aural--make-concrete-content
                          :text "probe" :speak t)
                :context '(:icons-enabled nil))))
    (unwind-protect
        (progn
          (process-put process tts--tracked-playback-completion-property t)
          (process-put process tts--marker-playback-events-property t)
          (process-put process emacsvox-aural--structured-timeline-process-property 3)
          (cl-letf (((symbol-function 'tts-voice-reset-code) (lambda () ""))
                    ((symbol-function 'message) #'ignore)
                    ((symbol-function 'process-send-string)
                     (lambda (owner command)
                       (push command writes)
                       (unless injected
                         (setq injected t)
                         (pcase scenario
                           ((or 'early-marker 'ordinary)
                            (tts--dispatch-playback-marker-event owner event))
                           ('early-terminal
                            (tts--complete-tracked-dispatch
                             owner "__EMACSVOX_TRACKED__ 1 completed"))
                           ('stop (tts--interrupt-process owner))
                           ('exit (delete-process owner)
                                  (tts--cancel-process-tracked-dispatches owner 'failed))
                           ('failed-after-start
                            (omnivox--handle-marker-line
                             owner
                             (concat omnivox-marker-event-prefix
                                     (base64-encode-string (json-serialize event) t)))
                            (error "failure after simulated consumption"))
                           ('nested-effect nil))))))
            (setq result
                  (emacsvox-aural-call-with-delivery-transaction
                   process
                   (lambda ()
                     (emacsvox-aural-queue-concrete-plan plan "probe")
                     (when (eq scenario 'nested-effect)
                       (emacsvox-aural--defer-delivery-effect
                        (lambda ()
                          (emacsvox-aural-call-with-delivery-transaction
                           process
                           (lambda ()
                             (emacsvox-aural-delivery-send process "q {nested}\nd\n")))
                          (setq nested-captured
                                (cl-some
                                 (lambda (entry)
                                   (equal (emacsvox-aural--delivery-entry-command entry)
                                          "q {nested}\nd\n"))
                                 emacsvox-aural--delivery-transaction-entries)))))
                     (tts--protocol-dispatch)))))
          (list scenario :returned result :callbacks (reverse callbacks)
                :writes (length writes)
                :owner-after (and (gethash 1 tts--dispatch-lifecycles) t)
                :source-observed (and (gethash 1 tts--dispatch-lifecycles)
                                      (tts--dispatch-lifecycle-source-observed-at
                                       (gethash 1 tts--dispatch-lifecycles)) t)
                :actual-route (and (gethash "bolden" omnivox-last-realized-routes) t)
                :nested-captured nested-captured))
      (delete-process process))))

(dolist (scenario '(early-marker ordinary early-terminal stop exit
                   failed-after-start nested-effect))
  (prin1 (emacsvox-handoff-review--probe scenario))
  (terpri))

;; Test the actual tracked-reader consumer with a completion before ID return.
(with-temp-buffer
  (insert "First sentence. Second sentence.")
  (goto-char (point-min))
  (let* ((session (emacsvox--make-tracked-reading-session
                   :buffer (current-buffer) :window nil
                   :limit (copy-marker (point-max)) :next (copy-marker 1)
                   :current-start (make-marker) :current-end (make-marker)
                   :generation 7))
         (emacsvox--tracked-reading-session session)
         (emacsvox-tracked-reading-max-chars 100)
         (emacsvox--tracked-reading-generation 7))
    (unwind-protect
        (cl-letf (((symbol-function 'tts-speak-tracked)
                   (lambda (_text callback) (funcall callback 99 'completed) 99)))
          (emacsvox--tracked-reading-next 7)
          (prin1 (list 'reader-early-terminal
                       :id (emacsvox--tracked-reading-session-identifier session)
                       :next (marker-position (emacsvox--tracked-reading-session-next session))
                       :chunk-end (marker-position (emacsvox--tracked-reading-session-current-end session))))
          (terpri))
      (emacsvox--tracked-reading-release-markers session))))

;;; diagnose-client-handoff.el ends here
