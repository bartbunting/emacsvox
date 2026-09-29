;;; emacsvox-aural-replay.el --- Playback-observed aural replay -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: Emacsvox contributors
;; Maintainer: Emacsvox contributors
;; Keywords: accessibility, multimedia
;; URL: https://github.com/bartbunting/emacsvox

;; This file is part of Emacsvox.
;;
;; Emacsvox is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; Emacsvox is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with Emacsvox.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Retain bounded, process-free evidence from owned playback callbacks.  Replay
;; uses exact private voice auditions, never the current named-voice registry.

;;; Code:

(require 'cl-lib)
(require 'emacsvox-aural-preview)
(require 'tts-speak)
(require 'omnivox-voices)

(defconst emacsvox-aural-replay--byte-limit (* 64 1024)
  "Maximum playback evidence retained by one presentation transaction.")
(defconst emacsvox-aural-replay--span-limit 128
  "Maximum recorded spans per dispatch, and dispatches per transaction.")

(defun emacsvox-aural-replay--size (data)
  "Return the retained printed byte size of acyclic DATA."
  (let ((print-length nil) (print-level nil) (print-circle t))
    (string-bytes (prin1-to-string data))))

(defun emacsvox-aural-replay--speech-p (action)
  "Whether ACTION contributes a nonempty speech span."
  (and (eq (emacsvox-aural-concrete-action-kind action) 'speech)
       (stringp (emacsvox-aural-concrete-action-text action))
       (not (string-empty-p (emacsvox-aural-concrete-action-text action)))))

(defun emacsvox-aural-replay--span-map (runs associations)
  "Map wire spans in RUNS to retained run IDs in ASSOCIATIONS.
Use the same coalescing predicate as transport, preserving byte-independent
character ranges for fields sharing one wire span."
  (let (groups group previous mapped)
    (dolist (run runs)
      (unless (and previous
                   (emacsvox-aural--coalescible-structured-runs-p previous run))
        (when group (push (nreverse group) groups))
        (setq group nil))
      (let ((association (assq (car run) associations)))
        (push (cons (cdr association) run) group)
        (setq associations (delq association associations)))
      (setq previous run))
    (when group (push (nreverse group) groups))
    (cl-labels
        ((actions (entry phase)
           (let* ((id (car entry)) (plan (cadr entry))
                  (actions (if (eq phase 'before)
                               (emacsvox-aural-concrete-plan-before plan)
                             (emacsvox-aural-concrete-plan-after plan))))
             (cl-loop for action in actions for index from 0
                      when (emacsvox-aural-replay--speech-p action) do
                      (push (list :text (emacsvox-aural-concrete-action-text action)
                                  :targets (when id (list (list :run id :part phase :index index
                                                                :start 0 :end (length (emacsvox-aural-concrete-action-text action))))))
                            mapped)))))
      (dolist (entries (nreverse groups))
        (actions (car entries) 'before)
        (let ((offset 0) targets texts positioned)
          (dolist (entry entries)
            (pcase-let* ((`(,id ,plan ,text ,_pause . ,extra) entry)
                         (content (emacsvox-aural-concrete-plan-content plan)))
              (when (and (emacsvox-aural-concrete-content-speak content)
                         (stringp text) (not (string-empty-p text)))
                (push text texts)
                (when id
                  (push (list :run id :part 'content :start offset :end (+ offset (length text))) targets))
                (cl-incf offset (length text))
                (when (car extra) (setq positioned t)))))
          (when texts
            (push (list :text (apply #'concat (nreverse texts)) :targets (nreverse targets)
                        :positioned positioned) mapped)))
        (actions (car (last entries)) 'after)))
    (mapcar (lambda (span) (append (list :id nil :projection nil :items nil) span))
            (nreverse mapped))))

(defun emacsvox-aural-replay--projection (snapshot span)
  "Freeze the requested layers for SPAN from acknowledged SNAPSHOT."
  (let* ((logical (plist-get span :logical-id))
         (provenance (omnivox--choice-provenance snapshot logical))
         (definition (cl-find logical (plist-get (plist-get snapshot :content) :definitions)
                              :test #'equal :key (lambda (item) (plist-get (plist-get item :definition) :id)))))
    (when (and provenance (memq (plist-get span :mode) '(layered engine-layered)))
      (tts--dispatch-copy-data
       (list :shared (plist-get provenance :shared)
             :choices (mapcar (lambda (choice)
                                (let ((copy (copy-tree choice)))
                                  (unless (eq (plist-get span :mode) 'engine-layered)
                                    (cl-remf copy :native))
                                  copy))
                              (plist-get provenance :choices))
             :language (let ((language (plist-get (plist-get definition :definition) :language)))
                         (unless (eq language :null) language))
             :context (plist-get span :raw-context)
             :placement (list :pan (let ((pan (plist-get (plist-get span :placement) :pan)))
                                     (unless (eq pan :null) pan))))))))

(defun emacsvox-aural-replay--invalidate (dispatch reason)
  "Make DISPATCH unavailable for replay with a bounded REASON."
  (setf (plist-get dispatch :status) 'unavailable
        (plist-get dispatch :reason) reason
        (plist-get dispatch :start) nil
        (plist-get dispatch :span-index) nil
        (plist-get dispatch :spans) nil))

(defun emacsvox-aural-replay--exhausted (capture)
  "Discard CAPTURE's speech evidence when its shared budget is exhausted."
  (setf (emacsvox-aural--playback-unavailable capture) t)
  (dolist (dispatch (emacsvox-aural--playback-dispatches capture))
    (emacsvox-aural-replay--invalidate dispatch "Playback evidence exceeds the history limit")))

(defun emacsvox-aural-replay--marker (dispatch event capture)
  "Retain owned EVENT for DISPATCH within the shared CAPTURE budget."
  (when (eq (plist-get dispatch :status) 'pending)
    (condition-case nil
        (progn
          (unless (= (plist-get event :sequence) (1+ (plist-get dispatch :sequence)))
            (error "Missing playback evidence"))
          (setf (plist-get dispatch :sequence) (plist-get event :sequence))
          (pcase (plist-get event :type)
            ("utterance_started"
             (when (plist-get dispatch :start) (error "Uncorrelated speech"))
             (unless (<= (string-bytes (plist-get event :text)) emacsvox-aural--history-preview-max-bytes)
               (error "Speech evidence exceeds history budget"))
             (setf (plist-get dispatch :start)
                   (tts--dispatch-copy-data
                    (list :text (plist-get event :text) :utterance (plist-get event :utterance_id)
                          :actual (plist-get event :actual_voice)))))
            ("voice_choice_applied"
             (let* ((span (assq (plist-get event :span_id) (plist-get dispatch :span-index)))
                    (span (cdr span))
                    (start (plist-get dispatch :start))
                    (choice (plist-get event :choice))
                    (projection (plist-get span :projection))
                    (row (cl-find (plist-get choice :choice_id) (plist-get projection :choices)
                                  :test #'equal :key (lambda (item) (plist-get item :id))))
                    (actual (plist-get choice :realized)))
               (unless (and span start
                            (eql (plist-get event :utterance_id) (plist-get start :utterance))
                            (equal actual (plist-get start :actual)))
                 (error "Uncorrelated voice receipt"))
               (setf (plist-get dispatch :start) nil)
               (when (plist-get span :targets)
                 (unless projection (error "Voice settings were not retained"))
                 (let* ((row (copy-tree (or row '(:id "recorded" :adjustments nil))))
                        (_ (when (equal (plist-get (plist-get event :native_application) :status)
                                        "common_only")
                             (cl-remf row :native)))
                        (selector (list :kind 'exact :scope 'local :engine-id (plist-get actual :engine_id)
                                        :voice-id (plist-get actual :voice_id)))
                        (entry
                         (list :text (plist-get start :text)
                               :voice (list :language (plist-get projection :language)
                                            :shared (plist-get projection :shared)
                                            :choices (list (plist-put row :selector selector)))
                               :context (plist-get projection :context)
                               :placement (plist-get projection :placement)
                               :selection (list :mode 'choice :choice-id (plist-get row :id))
                               :fallback-policy '(:preferred-engines nil :allow-same-language-on-requested-engine nil
                                                                     :global-default nil :fallback-engines nil)
                               :disabled-engine-ids nil)))
                   (push (tts--dispatch-copy-data entry) (plist-get span :items)))))))
          (when (> (emacsvox-aural-replay--size capture) emacsvox-aural-replay--byte-limit)
            (emacsvox-aural-replay--exhausted capture)))
      (error (emacsvox-aural-replay--invalidate dispatch "Playback evidence is incomplete or exceeds the history limit")))))

(defun emacsvox-aural-replay--terminal (dispatch status)
  "Close DISPATCH with observed terminal STATUS, validating complete coverage."
  (when (eq (plist-get dispatch :status) 'pending)
    (setf (plist-get dispatch :status) status)
    (dolist (span (plist-get dispatch :spans))
      (setf (plist-get span :items) (nreverse (plist-get span :items)))
      (when (and (eq status 'completed) (plist-get span :targets))
        (let* ((items (plist-get span :items))
               (first (car items))
               ;; Omnivox reports text after punctuation and capitalization
               ;; processing.  A uniform actual voice covers the original
               ;; span and all of its fields without aligning transformed text.
               (uniform (and first (cl-every (lambda (entry) (equal (cddr entry) (cddr first))) items))))
          (cond
           ((or (plist-get dispatch :start) (plist-get span :positioned) (null items))
            (emacsvox-aural-replay--invalidate dispatch "Complete voice evidence or inline cue timing was not retained"))
           (uniform
            (setf (plist-get first :text) (plist-get span :text)
                  (plist-get span :items) (list first)))
           ((not (equal (plist-get span :text)
                        (mapconcat (lambda (entry) (plist-get entry :text)) items "")))
            (emacsvox-aural-replay--invalidate dispatch "Changed voices could not be aligned with the retained text")))))
      ;; Only the actually used choices survive the terminal notification.
      (setf (plist-get span :projection) nil))
    (setf (plist-get dispatch :start) nil (plist-get dispatch :span-index) nil)))

(cl-defun emacsvox-aural-replay--attach (owner snapshot built runs capture associations)
  "Attach bounded CAPTURE observations to inactive OWNER for BUILT RUNS.
ASSOCIATIONS links source plan occurrences to retained history run IDs."
  (when (>= (length (emacsvox-aural--playback-dispatches capture))
            emacsvox-aural-replay--span-limit)
    (emacsvox-aural-replay--exhausted capture))
  (when (emacsvox-aural--playback-unavailable capture)
    (cl-return-from emacsvox-aural-replay--attach nil))
  (let* ((envelope (car built))
         (mapping (emacsvox-aural-replay--span-map runs associations))
         (wire (append (plist-get envelope :spans) nil))
         (process (tts--dispatch-owner-process owner))
         (dispatch (list :id (tts--dispatch-owner-id owner)
                         :generation (tts--dispatch-owner-generation owner)
                         :lane (if (eq process tts-notify-process) 'notification 'main)
                         :status 'pending :sequence 0 :spans mapping
                         :span-index nil :start nil :reason nil))
         (marker (tts--dispatch-owner-marker owner))
         (completion (tts--dispatch-owner-completion owner)))
    (push dispatch (emacsvox-aural--playback-dispatches capture))
    (condition-case nil
        (progn
          (unless (and snapshot (= (length wire) (length mapping))
                       (<= (length mapping) emacsvox-aural-replay--span-limit)
                       (<= (cl-loop for span in mapping sum (string-bytes (plist-get span :text)))
                           emacsvox-aural--history-preview-max-bytes))
            (error "Unsupported voice evidence"))
          (setq mapping (emacsvox-aural--history-value mapping))
          (setf (plist-get dispatch :spans) mapping)
          (cl-loop for span in mapping for wrapper in wire do
                   (let* ((value (plist-get wrapper :span)) (id (plist-get value :id)))
                     (unless (equal (plist-get span :text) (plist-get value :text))
                       (error "Speech span mapping changed"))
                     (setf (plist-get span :id) id
                           (plist-get span :projection)
                           (when (plist-get span :targets)
                             (emacsvox-aural-replay--projection snapshot (gethash id (nth 2 built)))))))
          (setf (plist-get dispatch :span-index)
                (mapcar (lambda (span) (cons (plist-get span :id) span)) mapping))
          (when (or (> (emacsvox-aural-replay--size capture) emacsvox-aural-replay--byte-limit)
                    (> (+ (process-get process 'tts--dispatch-metadata-bytes)
                          emacsvox-aural-replay--byte-limit) tts--dispatch-metadata-limit))
            (error "History evidence capacity exhausted"))
          ;; Reserve the entire bounded evidence budget before the first write.
          (let ((inhibit-quit t))
            (tts--dispatch-set-accounting
             process (process-get process 'tts--dispatch-owner-count)
             (+ (process-get process 'tts--dispatch-metadata-bytes) emacsvox-aural-replay--byte-limit))
            (cl-incf (tts--dispatch-owner-metadata-bytes owner) emacsvox-aural-replay--byte-limit)
            (setf (tts--dispatch-owner-marker owner)
                  (lambda (id event)
                    (emacsvox-aural-replay--marker dispatch event capture)
                    (when marker (funcall marker id event)))
                  (tts--dispatch-owner-completion owner)
                  (lambda (id status)
                    (emacsvox-aural-replay--terminal dispatch status)
                    (when completion (funcall completion id status))))))
      (error (emacsvox-aural-replay--invalidate dispatch "Actual voice recording is unavailable for this presentation")))
    (when (> (emacsvox-aural-replay--size capture) emacsvox-aural-replay--byte-limit)
      (emacsvox-aural-replay--exhausted capture))))

(defun emacsvox-aural-replay--capture (record)
  "Return RECORD's playback evidence, allowing records from older sessions."
  (condition-case nil (emacsvox-aural-presentation-record-playback record)
    (args-out-of-range nil)))

(defun emacsvox-aural-replay--entries (record run part &optional index)
  "Return exact speech entries recorded for RUN, PART and action INDEX."
  (let (found)
    (dolist (dispatch (and (emacsvox-aural-replay--capture record)
                           (emacsvox-aural--playback-dispatches (emacsvox-aural-replay--capture record))))
      (dolist (span (plist-get dispatch :spans))
        (when-let* ((target (cl-find-if
                             (lambda (target)
                               (and (eql run (plist-get target :run))
                                    (eq part (plist-get target :part))
                                    (equal index (plist-get target :index))))
                             (plist-get span :targets))))
          (unless (eq (plist-get dispatch :status) 'completed)
            (user-error "Original playback was %s; a complete replay is unavailable"
                        (plist-get dispatch :status)))
          (let ((offset 0))
            (dolist (entry (plist-get span :items))
              (let* ((text (plist-get entry :text))
                     (start (max offset (plist-get target :start)))
                     (end (min (+ offset (length text)) (plist-get target :end))))
                (when (< start end)
                  (push (plist-put (tts--dispatch-copy-data entry) :text
                                   (substring text (- start offset) (- end offset))) found))
                (cl-incf offset (length text))))))))
    (or (nreverse found)
        (user-error "The actual voice was not recorded; original playback is unavailable"))))

(defun emacsvox-aural-replay--steps (record &optional indices speech-action)
  "Prepare RECORD's complete playback, optional INDICES or SPEECH-ACTION.
SPEECH-ACTION is the report's (PLAN ACTION PHASE) target.  Missing evidence
fails before stopping or sending any audio."
  (when (emacsvox-aural-presentation-record-effective-payload-truncated-p record)
    (user-error "Only a truncated preview was retained; complete playback is unavailable"))
  (let ((runs (emacsvox-aural-presentation-record-runs record)) steps)
    (cl-labels
        ((speech (id part &optional index)
           (dolist (entry (emacsvox-aural-replay--entries record id part index))
             (push (list 'speech entry) steps)))
         (actions (id plan phase)
           (cl-loop for action in (if (eq phase 'before) (emacsvox-aural-concrete-plan-before plan)
                                    (emacsvox-aural-concrete-plan-after plan))
                    for index from 0 do
                    (when (or (not speech-action)
                              (and (eq plan (car speech-action))
                                   (eq action (cadr speech-action))
                                   (eq phase (caddr speech-action))))
                      (cond
                       ((emacsvox-aural-replay--speech-p action) (speech id phase index))
                       ((not (eq (emacsvox-aural-concrete-action-kind action) 'speech))
                        (push (list 'action action (emacsvox-aural-concrete-plan-context plan)) steps)))))))
      (cl-loop for (plan text pause) in runs for index from 0 do
               (when (and (or (not indices) (memq index indices))
                          (or (not speech-action) (eq plan (car speech-action))))
                 (let* ((id (condition-case nil
                                (nth index (emacsvox-aural-presentation-record-playback-runs record))
                              (args-out-of-range nil)))
                        (content (emacsvox-aural-concrete-plan-content plan)))
                   (when (and pause (not speech-action)) (push (list 'pause pause) steps))
                   (actions id plan 'before)
                   (when (and (not speech-action) (emacsvox-aural-concrete-content-speak content)
                              (stringp text) (not (string-empty-p text)))
                     (speech id 'content))
                   (actions id plan 'after)))))
    (tts--dispatch-copy-data (nreverse steps))))

(cl-defstruct (emacsvox-aural-replay--operation (:constructor emacsvox-aural-replay--operation-create))
  process generation steps pending response busy finished observer timer token
  dispatch guard)

(defun emacsvox-aural-replay--current-p (operation)
  "Whether OPERATION still owns its original foreground connection."
  (let ((process (emacsvox-aural-replay--operation-process operation)))
    (and (not (emacsvox-aural-replay--operation-finished operation))
         (eq process tts-speaker-process) (process-live-p process)
         (eq operation (process-get process 'emacsvox-aural-replay))
         (or (null (emacsvox-aural-replay--operation-guard operation))
             (tts-queue--guard-valid-p (emacsvox-aural-replay--operation-guard operation)))
         (equal (emacsvox-aural-replay--operation-generation operation)
                (process-get process 'tts--speech-process-generation)))))

(defun emacsvox-aural-replay--clear-stage (operation)
  "Remove OPERATION's temporary stage observer and timer."
  (when-let* ((observer (emacsvox-aural-replay--operation-observer operation)))
    (remove-hook 'tts-stopped-hook observer))
  (when-let* ((timer (emacsvox-aural-replay--operation-timer operation)))
    (cancel-timer timer))
  (setf (emacsvox-aural-replay--operation-observer operation) nil
        (emacsvox-aural-replay--operation-timer operation) nil))

(defun emacsvox-aural-replay--finish (operation status &optional message superseded)
  "Finish OPERATION exactly once with STATUS and optional MESSAGE.
When SUPERSEDED, the replacement's guarded stop retires the private preview."
  (unless (emacsvox-aural-replay--operation-finished operation)
    (setf (emacsvox-aural-replay--operation-finished operation) status
          (emacsvox-aural-replay--operation-steps operation) nil
          (emacsvox-aural-replay--operation-pending operation) nil)
    (emacsvox-aural-replay--clear-stage operation)
    (let ((process (emacsvox-aural-replay--operation-process operation)))
      (when (eq operation (process-get process 'emacsvox-aural-replay))
        (process-put process 'emacsvox-aural-replay nil)))
    (when-let* ((token (and (not superseded) (emacsvox-aural-replay--operation-token operation))))
      (omnivox--preview-cancel token))
    (when-let* ((id (emacsvox-aural-replay--operation-dispatch operation)))
      (tts-cancel-tracked-dispatch id))
    (emacsvox-aural-preview-message "Original playback %s%s" status
                                    (if message (concat ": " message) ""))))

(defun emacsvox-aural-replay--receive (operation ticket result)
  "Latch RESULT once for OPERATION's current stage TICKET."
  (when (and (not (emacsvox-aural-replay--operation-finished operation))
             (eq ticket (emacsvox-aural-replay--operation-pending operation))
             (not (emacsvox-aural-replay--operation-response operation)))
    (setf (emacsvox-aural-replay--operation-response operation) result)
    (unless (emacsvox-aural-replay--operation-busy operation)
      (emacsvox-aural-replay--drive operation))))

(defun emacsvox-aural-replay--actions (operation steps ticket)
  "Play non-speech STEPS with owned completion for OPERATION and TICKET."
  (let* ((process (emacsvox-aural-replay--operation-process operation))
         (observer (lambda (owner)
                     (when (eq owner process)
                       (emacsvox-aural-replay--receive operation ticket '(:status cancelled)))))
         (emacsvox-aural--history-recording-inhibited t)
         (emacsvox-aural-submission-delivery-policy 'ordered)
         (emacsvox-aural-submission-controls-interruption nil)
         (identifier
          (emacsvox-aural-call-with-delivery-transaction
           process
           (lambda ()
             (dolist (step steps)
               (pcase (car step)
                 ('pause (tts--protocol-silence (cadr step)))
                 ('action (emacsvox-aural-queue-concrete-action (cadr step) (caddr step)))))
             (tts--protocol-dispatch-tracked
              (lambda (_id status)
                (emacsvox-aural-replay--receive operation ticket (list :status status))))))))
    (unless identifier (error "Recorded cues could not be submitted"))
    (setf (emacsvox-aural-replay--operation-observer operation) observer
          (emacsvox-aural-replay--operation-dispatch operation) identifier
          (emacsvox-aural-replay--operation-guard operation)
          (tts-queue--startup-guard process))
    (add-hook 'tts-stopped-hook observer)
    (setf (emacsvox-aural-replay--operation-timer operation)
          (run-at-time
           60 nil
           (lambda ()
             (when (eq ticket (emacsvox-aural-replay--operation-pending operation))
               (let ((current (emacsvox-aural-replay--current-p operation))
                     (guard (emacsvox-aural-replay--operation-guard operation)))
                 (emacsvox-aural-replay--receive operation ticket
                                                 '(:status failed :message "Recorded cue playback timed out"))
                 (when (and current guard (tts-queue--guard-valid-p guard))
                   (tts--interrupt-process process)))))))))

(defun emacsvox-aural-replay--drive (operation)
  "Advance OPERATION with one owned speech or cue stage outstanding."
  (setf (emacsvox-aural-replay--operation-busy operation) t)
  (unwind-protect
      (condition-case err
          (let (waiting)
            (while (and (not waiting) (not (emacsvox-aural-replay--operation-finished operation)))
              (cond
               ((not (emacsvox-aural-replay--current-p operation))
                (emacsvox-aural-replay--finish operation 'cancelled))
               ((emacsvox-aural-replay--operation-response operation)
                (let ((result (emacsvox-aural-replay--operation-response operation)))
                  (setf (emacsvox-aural-replay--operation-response operation) nil
                        (emacsvox-aural-replay--operation-pending operation) nil
                        (emacsvox-aural-replay--operation-guard operation) nil
                        (emacsvox-aural-replay--operation-token operation) nil)
                  (emacsvox-aural-replay--clear-stage operation)
                  (unless (eq (plist-get result :status) 'completed)
                    (emacsvox-aural-replay--finish operation (plist-get result :status) (plist-get result :message)))))
               ((emacsvox-aural-replay--operation-pending operation) (setq waiting t))
               ((not (emacsvox-aural-replay--operation-steps operation))
                (emacsvox-aural-replay--finish operation 'completed))
               (t
                (let* ((speech (eq (caar (emacsvox-aural-replay--operation-steps operation)) 'speech))
                       (ticket (list 'stage)) (count 0) steps)
                  (while (and (emacsvox-aural-replay--operation-steps operation)
                              (< count 64)
                              (eq speech (eq (caar (emacsvox-aural-replay--operation-steps operation)) 'speech)))
                    (cl-incf count)
                    (push (pop (emacsvox-aural-replay--operation-steps operation)) steps))
                  (setf (emacsvox-aural-replay--operation-pending operation) ticket)
                  (if speech
                      (setf (emacsvox-aural-replay--operation-token operation)
                            (omnivox--preview-layered-sequence
                             (mapcar #'cadr (nreverse steps))
                             (lambda (result) (emacsvox-aural-replay--receive operation ticket result))
                             (lambda () (emacsvox-aural-replay--current-p operation))))
                    (emacsvox-aural-replay--actions operation (nreverse steps) ticket)))))))
        (error (emacsvox-aural-replay--finish operation 'failed (error-message-string err)))
        (quit (emacsvox-aural-replay--finish operation 'cancelled)
              (signal (car err) (cdr err))))
    (setf (emacsvox-aural-replay--operation-busy operation) nil)))

(defun emacsvox-aural-replay--play (record &optional indices speech-action)
  "Replay RECORD with actual voices, optionally selecting INDICES or SPEECH-ACTION."
  (let* ((process tts-speaker-process)
         (guard (and (processp process) (tts-queue--startup-guard process)))
         (steps (emacsvox-aural-replay--steps record indices speech-action)))
    (unless (and (processp process) (process-live-p process))
      (user-error "A live speech server is required for original playback"))
    ;; Validate every captured speech entry before any cue or interruption.
    (dolist (step steps)
      (when (eq (car step) 'speech)
        (omnivox--preview-layered-request (cadr step) process)))
    (unless (and guard (eq process tts-speaker-process) (tts-queue--guard-valid-p guard))
      (user-error "Original playback needs an unchanged speech connection"))
    (let* ((previous (process-get process 'emacsvox-aural-replay))
           (operation (emacsvox-aural-replay--operation-create
                       :process process :generation (process-get process 'tts--speech-process-generation)
                       :steps steps))
           (observer (lambda (owner)
                       (when (eq process owner)
                         (emacsvox-aural-replay--finish operation 'cancelled))))
           started)
      (process-put process 'emacsvox-aural-replay operation)
      (setf (emacsvox-aural-replay--operation-observer operation) observer)
      (add-hook 'tts-stopped-hook observer)
      (unwind-protect
          (progn
            (when previous (emacsvox-aural-replay--finish previous 'cancelled nil t))
            (emacsvox-aural-cancel-pending-deliveries process)
            (when (emacsvox-aural-replay--current-p operation)
              (tts--interrupt-process process nil nil (list guard observer operation)))
            (unless (tts-queue--guard-valid-p guard)
              (emacsvox-aural-replay--finish operation 'cancelled))
            (emacsvox-aural-replay--clear-stage operation)
            (emacsvox-aural-replay--drive operation)
            (setq started t))
        (unless started (emacsvox-aural-replay--finish operation 'cancelled)))
      operation)))

(provide 'emacsvox-aural-replay)
;;; emacsvox-aural-replay.el ends here
