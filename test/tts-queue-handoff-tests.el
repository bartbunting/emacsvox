;;; tts-queue-handoff-tests.el --- Captured queue boundaries -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Exercise complete producers and independently specified dispatch sequences.
;;; Code:
(require 'omnivox-choice-consumer-tests)
(require 'tts-preparation-tests)
(require 'tts-queue-state-tests)

(defconst tts-queue-test--fixture
  (expand-file-name "fixtures/voice-editor/queue-handoff.el"
                    (file-name-directory (or load-file-name buffer-file-name))))

(defun tts-queue-test--normal ()
  "Speak the ordinary named test contribution."
  (tts-speak (propertize "NORMAL" 'personality 'voice-bolden)))

(defun tts-queue-test--event (event)
  "Run a fixture EVENT through the actual producer."
  (pcase event
    ('Q (tts-speak-using-voice 'voice-bolden "RAW"))
    ('N (tts-queue-test--normal))
    ('D (tts--protocol-dispatch))
    ('opaque-code (tts--protocol-queue-code "[[pitch 1.1]]"))
    ('letter (tts-letter "B"))
    (`(N :rate ,rate) (let ((tts-speech-rate rate)) (tts-queue-test--normal))))
  nil)

(defun tts-queue-test--legacy-sequence (wire &optional rates)
  "Decode observable speech/flush order from WIRE, retaining RATES if requested."
  (let (sequence)
    (dolist (line (split-string wire "\n" t))
      (cond
       ((string-match-p "emacsvox_timeline" line) (ert-fail "Unexpected timeline"))
       ((string-prefix-p "q {NORMAL" line) (push 'N sequence))
       ((string-prefix-p "q {RAW" line) (push 'Q sequence))
       ((equal line "d") (push 'dispatch sequence))
       ((string-prefix-p "l " line) (push 'letter sequence))
       ((string-match-p "pitch 1.1" line) (push 'opaque-code sequence))
       ((and rates (string-match "tts_sync_state .* \\([0-9]+\\)\\'" line))
        (push (list 'sync (string-to-number (match-string 1 line))) sequence))))
    (nreverse sequence)))

(ert-deftest tts-queue-fixture-preserves-flushes-tails-and-state ()
  (let* ((read-eval nil)
         (data (emacsvox-aural-routing--read-one-form tts-queue-test--fixture "queue fixture")))
    (dolist (id '(queue-only unsealed-tail sealed-tail explicit-prefix opaque-tail
                 different-rates separate-character))
      (let ((case (cl-find id (plist-get data :cases) :key (lambda (row) (plist-get row :id)))))
        (dolist (version '(nil 3 4))
          (omnivox-choice-consumer-test--with-speech
           (process-put speaker emacsvox-aural--structured-timeline-process-property version)
           (emacsvox-aural-call-with-delivery-transaction
            speaker (lambda () (mapc #'tts-queue-test--event (plist-get case :events))))
           (should (equal
                    (tts-queue-test--legacy-sequence
                     (mapconcat #'cdr (reverse writes) "") (eq id 'different-rates))
                    (cl-subst 'dispatch 'D
                              (cl-subst 'dispatch 'ordinary-dispatch (plist-get case :sequence)))))))))))

(ert-deftest tts-queue-adjacent-ordinary-keeps-one-timeline ()
  (omnivox-choice-consumer-test--with-speech
   (emacsvox-aural-call-with-delivery-transaction
    speaker (lambda () (tts-queue-test--normal) (tts-queue-test--normal)))
   (let ((doc (omnivox-choice-consumer-test--timeline (car writes))))
     (should (= 1 (length writes)))
     (should (equal "NORMALNORMAL"
                    (mapconcat (lambda (row) (plist-get (plist-get row :span) :text))
                               (plist-get doc :spans) ""))))))

(ert-deftest tts-queue-untyped-sync-and-changing-capitalization-stay-legacy ()
  (dolist (kind '(untyped changed))
    (omnivox-choice-consumer-test--with-speech
     (process-put speaker tts--capitalization-presentation-property t)
     (emacsvox-aural-call-with-delivery-transaction
      speaker
      (lambda ()
        (let ((tts-caps t) (emacsvox-capitalization-presentation 'none))
          (tts-queue-test--normal))
        (if (eq kind 'untyped)
            (emacsvox-aural-delivery-send speaker "tts_sync_state all 1 0 100\n")
          (let ((tts-caps t) (emacsvox-capitalization-presentation 'spoken))
            (tts-queue-test--normal)))))
     (should-not (string-match-p "emacsvox_timeline" (cdar writes)))
     (should (= (if (eq kind 'untyped) 1 2)
                (cl-count 'dispatch (tts-queue-test--legacy-sequence (cdar writes))))))))

(ert-deftest tts-queue-bare-concrete-fallback-does-not-invent-dispatch ()
  (omnivox-choice-consumer-test--with-speech
   (let ((run (omnivox-choice-timeline-test--run '(:preset bolden) nil)))
     (emacsvox-aural-call-with-delivery-transaction
      speaker (lambda ()
                (emacsvox-aural-queue-concrete-plan (car run) (cadr run))
                (tts--protocol-queue-code "[[pitch 1.1]]"))))
   (should-not (member "d" (split-string (cdar writes) "\n" t)))
   (should-not (string-match-p "emacsvox_timeline" (cdar writes)))))

(ert-deftest tts-queue-nested-callback-id-survives-structured-and-legacy-selection ()
  (dolist (marked '(nil t))
    (dolist (legacy '(nil t))
      (omnivox-choice-consumer-test--with-speech
       (let (returned callbacks outer)
         (cl-letf (((symbol-function 'process-send-string)
                    (lambda (process wire)
                      (push (cons process wire) writes)
                      (should (= returned 1))
                      (tts--complete-tracked-dispatch process "__EMACSVOX_TRACKED__ 1 completed")
                      (tts--dispatch-drain process)
                      (should-not callbacks))))
           (setq outer
                 (emacsvox-aural-call-with-delivery-transaction
                  speaker
                  (lambda ()
                    (let ((callback (lambda (id status) (push (list id status) callbacks))))
                      (setq returned
                            (if marked
                                (tts-speak-marked "NORMAL" #'ignore callback)
                              (tts-speak-tracked "NORMAL" callback))))
                    (when legacy (tts-queue-test--event 'Q))
                    returned))))
         (should (= returned outer 1))
         (should (= tts--tracked-dispatch-sequence 1))
         (if legacy
             (let ((wire (cdar writes)))
               (should (< (string-match (if marked "emacsvox_marker_dispatch 1"
                                         "emacsvox_tracked_dispatch 1") wire)
                          (string-match "q {RAW" wire))))
           (should (= 1 (plist-get (omnivox-choice-consumer-test--timeline (car writes)) :dispatch_id))))
         (tts--dispatch-drain speaker)
         (should (equal callbacks '((1 completed))))
         (tts-preparation-test--empty speaker))))))

(ert-deftest tts-queue-explicit-callback-owner-reused-by-concrete-timeline ()
  (dolist (marked '(nil t))
    (omnivox-choice-consumer-test--with-speech
     (let ((run (omnivox-choice-timeline-test--run '(:preset bolden) nil)) id)
       (emacsvox-aural-call-with-delivery-transaction
        speaker (lambda ()
                  (emacsvox-aural-queue-concrete-plan (car run) (cadr run))
                  (setq id (if marked (tts--protocol-dispatch-marked #'ignore #'ignore)
                             (tts--protocol-dispatch-tracked #'ignore)))))
       (should (= id 1 tts--tracked-dispatch-sequence))
       (should (= id (plist-get (omnivox-choice-consumer-test--timeline (car writes)) :dispatch_id)))
       (should (tts--dispatch-owner-semantics-bound (tts--dispatch-owner-for speaker id)))))))

(ert-deftest tts-queue-distinct-callbacks-keep-dispatches-and-immediate-delivery ()
  (omnivox-choice-consumer-test--with-speech
   (let ((emacsvox-aural-submission-delivery-policy 'replaceable)
         (emacsvox-aural--pending-deliveries (make-hash-table :test #'equal))
         ids callbacks)
     (emacsvox-aural-call-with-delivery-transaction
      speaker (lambda ()
                (dotimes (_ 2)
                  (push (tts-speak-tracked "NORMAL"
                                          (lambda (id status) (push (list id status) callbacks))) ids))))
     (should (equal ids '(2 1)))
     (should (zerop (hash-table-count emacsvox-aural--pending-deliveries)))
     (should (equal
              (cl-remove-if-not
               (lambda (line) (or (string-prefix-p "q " line)
                                 (string-prefix-p "emacsvox_tracked_dispatch " line)))
               (split-string (cdar writes) "\n" t))
              '("q {NORMAL }" "emacsvox_tracked_dispatch 1"
                "q {NORMAL }" "emacsvox_tracked_dispatch 2")))
     (dolist (id '(1 2))
       (tts--complete-tracked-dispatch speaker (format "__EMACSVOX_TRACKED__ %d completed" id)))
     (tts--dispatch-drain speaker)
     (should (equal (reverse callbacks) '((1 completed) (2 completed))))
     (tts-preparation-test--empty speaker))))

(ert-deftest tts-queue-deferred-binding-is-one-shot-and-charges-only-the-delta ()
  (tts-handoff-test--with-process
   (tts--call-with-preparation
    process
    (lambda ()
      (let* ((owner (tts--dispatch-new-owner #'ignore #'ignore nil t))
             (map (list (cons "action" (vector "semantic"))))
             (expected (string-bytes (prin1-to-string map))))
        (should-error (tts--dispatch-arm owner))
        (tts--dispatch-bind-semantics owner map)
        (should (= expected (process-get process 'tts--dispatch-metadata-bytes)))
        (aset (cdar map) 0 "changed")
        (should (equal (tts--dispatch-owner-semantics owner) '(("action" . ["semantic"]))))
        (should-error (tts--dispatch-bind-semantics owner nil)))))
   (tts-preparation-test--empty process)))

(ert-deftest tts-queue-binding-faults-and-bounds-release-reservations ()
  (dolist (fault '(error quit throw pending-quit bounds))
    (tts-handoff-test--with-process
     (let ((original (symbol-function 'process-put)) injected)
       (condition-case nil
           (catch 'binding-fault
             (tts--call-with-preparation
              process
              (lambda ()
                (let ((owner (tts--dispatch-new-owner nil #'ignore nil t))
                      (tts--dispatch-metadata-limit (if (eq fault 'bounds) 4 tts--dispatch-metadata-limit)))
                  (cl-letf (((symbol-function 'process-put)
                             (lambda (target property value)
                               (prog1 (funcall original target property value)
                                 (when (and (not injected) (eq property 'tts--dispatch-metadata-bytes)
                                            (> value 3))
                                   (setq injected t)
                                   (pcase fault
                                     ('error (error "Injected binding failure"))
                                     ('quit (signal 'quit nil))
                                     ('throw (throw 'binding-fault t))
                                     ('pending-quit (setq quit-flag t))))))))
                    (tts--dispatch-bind-semantics owner '("semantic action")))))))
         ((error quit) nil))
       (should (or injected (eq fault 'bounds)))
       (tts-preparation-test--empty process)))))

(ert-deftest tts-queue-invalid-frame-fails-before-stop-and-effects ()
  (dolist (events '((N Q D) (Q) (N letter) (N opaque-code) (N tracked)))
    (omnivox-choice-consumer-test--with-speech
     (process-put speaker emacsvox-aural--framed-delivery-process-property t)
     (let ((emacsvox-aural-submission-delivery-policy 'replaceable)
           (emacsvox-aural-submission-controls-interruption t)
           (emacsvox-aural-last-delivery-failure nil) effect)
       (emacsvox-aural-call-with-delivery-transaction
        speaker (lambda ()
                  (emacsvox-aural--defer-delivery-effect (lambda () (setq effect t)))
                  (dolist (event events)
                    (if (eq event 'tracked) (tts--protocol-dispatch-tracked #'ignore)
                      (tts-queue-test--event event)))))
       (should-not writes)
       (should-not effect)
       (should (eq (plist-get emacsvox-aural-last-delivery-failure :reason) 'dispatch-admission-failed))
       (tts-preparation-test--empty speaker)))))

(ert-deftest tts-queue-frame-validator-checks-grammar-and-bounds ()
  (tts-queue-state-test--with-process
   (process-put process emacsvox-aural--framed-delivery-process-property t)
   (let* ((command (copy-sequence "q {hello}\nd\n"))
          (entry (emacsvox-aural--make-delivery-entry
                  :process process :command command
                  :queue-description (tts-queue--describe command '(queue clear)))))
     (aset command 3 ?X)
     (should-error (emacsvox-aural--framed-delivery-entries process 1 (list entry)))))
  (dolist (payload '("q {hello}\nd\n" "c {}\ntts_sync_state all 1 0 100\nd\n"
                     "a \"/tmp/cue space.ogg\"\nt 440 25\nemacsvox_tone 1 insert 440 25\nsh 0\nd\n"
                     "a \"/tmp/\\uD000\\u0024\\n.ogg\"\nd\n"))
    (emacsvox-aural--validate-legacy-frame payload))
  (dolist (payload '("q {hi}\nd\nd\n" "d\nq {tail}\n" "s\nd\n"
                     "tts_sync_state all 1 0 NaN\nd\n" "t 0 20\nd\n"
                     "sh -1\nd\n" "emacsvox_marker_dispatch 1\n"
                     "a \"/tmp/\\u0000.ogg\"\nd\n" "a \"/tmp/\\uD800.ogg\"\nd\n"))
    (should-error (emacsvox-aural--validate-legacy-frame payload)))
  (let ((emacsvox-aural--timeline-frame-max-bytes 3))
    (should-error (emacsvox-aural--validate-legacy-frame "q {hi}\nd\n"))))

(ert-deftest tts-queue-capture-bound-failure-does-not-fall-back-or-write ()
  (omnivox-choice-consumer-test--with-speech
   (let ((emacsvox-aural--timeline-aggregate-max-bytes 8))
     (should-error
      (emacsvox-aural-call-with-delivery-transaction speaker #'tts-queue-test--normal)))
   (should-not writes)
   (tts-preparation-test--empty speaker)))

(ert-deftest tts-queue-caught-capacity-error-still-cancels-the-capture ()
  (omnivox-choice-consumer-test--with-speech
   (should-not
    (emacsvox-aural-call-with-delivery-transaction
     speaker (lambda ()
               (tts-queue-test--normal)
               (condition-case nil
                   (let ((emacsvox-aural--timeline-aggregate-max-bytes 1))
                     (tts-queue-test--event 'Q))
                 (error nil)))))
   (should-not writes)
   (tts-preparation-test--empty speaker)))

(ert-deftest tts-queue-late-capture-during-finalization-aborts-without-dropping-speech ()
  (dolist (stage '(tts--dispatch-bind-semantics emacsvox-aural--frame-structured-timeline))
    (omnivox-choice-consumer-test--with-speech
     (let ((original (symbol-function stage)) injected)
       (cl-letf (((symbol-function stage)
                  (lambda (&rest arguments)
                    (unless injected
                      (setq injected t)
                      (condition-case nil (tts-queue-test--normal)
                        (tts--preparation-cancelled nil)))
                    (apply original arguments))))
         (should-not
          (emacsvox-aural-call-with-delivery-transaction
           speaker (lambda () (tts-speak-tracked "NORMAL" #'ignore)))))
       (should injected)
       (should-not writes)
       (tts-preparation-test--empty speaker)))))

(ert-deftest tts-queue-presented-hook-speech-uses-an-independent-capture ()
  (omnivox-choice-consumer-test--with-speech
   (let* (entered nested
          (emacsvox-aural-plan-presented-hook
           (list (lambda (_plan)
                   (unless entered
                     (setq entered t nested (tts-queue-test--normal)))))))
     (should (= 1 (tts-queue-test--normal)))
     (should (= 2 nested))
     (should (= 2 (length writes)))
     (should (equal '(1 2)
                    (mapcar (lambda (write)
                              (plist-get (omnivox-choice-consumer-test--timeline write) :dispatch_id))
                            (reverse writes)))))))

(ert-deftest tts-queue-observed-producers-and-packets-preserve-queue-knowledge ()
  (omnivox-choice-consumer-test--with-speech
   (tts-queue--install)
   (set-process-coding-system speaker 'utf-8-unix 'utf-8-unix)
   (tts-queue-state-test--set speaker '(empty boundary usable))
   (tts--protocol-queue-text "QUEUED")
   (should (equal '(pending boundary usable) (tts-queue-state-test--get speaker)))
   (tts-queue-test--normal)
   (should (equal '(pending boundary usable) (tts-queue-state-test--get speaker)))
   (tts--protocol-dispatch)
   (should (tts-queue--known-empty-p speaker))
   (emacsvox-aural-call-with-delivery-transaction
    speaker (lambda () (emacsvox-aural-delivery-send speaker "q {")
              (tts--protocol-stop)))
   (should-not (tts-queue--known-empty-p speaker))
   ;; Observe actual adjacent entry concatenation with a typed clear afterwards.
   (emacsvox-aural-call-with-delivery-transaction
    speaker (lambda () (emacsvox-aural-delivery-send speaker "fragment")
              (tts--protocol-dispatch)))
   (should (equal '(unknown boundary usable) (tts-queue-state-test--get speaker)))
   (tts--protocol-dispatch)
   (should (tts-queue--known-empty-p speaker))))

(ert-deftest tts-queue-own-stop-guard-advances-before-independent-hooks ()
  (dolist (nested '(nil neutral queue dispatch letter))
    (omnivox-choice-consumer-test--with-speech
     (tts-queue--install)
     (set-process-coding-system speaker 'utf-8-unix 'utf-8-unix)
     (tts-queue-state-test--set speaker '(empty boundary usable))
     (let ((tts-stopped-hook
            (list (lambda (_process)
                    (pcase nested
                      ('neutral (tts-queue--send-typed speaker "OMNIVOX-REMOTE ping\n" 'neutral))
                      ('queue (tts--protocol-queue-text "OTHER"))
                      ('dispatch (tts--protocol-dispatch))
                      ('letter (tts--protocol-letter "A")))))))
       (tts--call-with-preparation
        speaker
        (lambda ()
          (let ((guard (tts-queue--guard speaker omnivox--choice-registration-property)))
            (setf (tts--preparation-queue-guard tts--current-preparation) guard)
            (tts--preparation-before-delivery speaker)
            (if (memq nested '(nil neutral))
                (progn (tts--preparation-interrupt speaker)
                       (should (tts-queue--guard-valid-p guard)))
              (should-error (tts--preparation-interrupt speaker)
                            :type 'tts--preparation-cancelled)))))))))

(ert-deftest tts-queue-named-fixture-promotes-only-complete-empty-captures ()
  (let ((read-eval nil))
    (dolist (case (plist-get (emacsvox-aural-routing--read-one-form
                             tts-queue-test--fixture "queue fixture") :cases))
      (when (memq (plist-get case :id)
                  '(queue-only named-normal named-explicit unsealed-tail sealed-tail
                    explicit-prefix earlier-pending unknown-pending old-server))
        (ert-info ((format "Fixture %S" (plist-get case :id)))
          (omnivox-choice-consumer-test--with-speech
           (tts-queue-state-test--set speaker (list (plist-get case :initial) 'boundary 'usable))
           (when (eq (plist-get case :id) 'old-server)
             (process-put speaker emacsvox-aural--structured-timeline-process-property 3))
           (emacsvox-aural-call-with-delivery-transaction
            speaker (lambda () (mapc #'tts-queue-test--event (plist-get case :events))))
           (if (eq (plist-get case :output) 'layered)
               (let ((doc (omnivox-choice-consumer-test--timeline (car writes))))
                 (should (equal (mapconcat (lambda (row) (plist-get (plist-get row :span) :text))
                                           (plist-get doc :spans) "")
                                (if (eq (plist-get case :id) 'named-normal) "RAWNORMAL" "RAW"))))
             (should (equal (tts-queue-test--legacy-sequence (cdar writes))
                            (cl-subst 'dispatch 'D
                                      (cl-subst 'dispatch 'ordinary-dispatch (plist-get case :sequence))))))
           (should (eq (plist-get case :reason)
                       (plist-get (process-get speaker emacsvox-aural--queue-limitation-property) :reason)))))))))

(ert-deftest tts-queue-named-closing-callback-reuses-owner-on-both-lanes ()
  (dolist (marked '(nil t))
    (omnivox-choice-consumer-test--with-speech
     (dolist (lane (list speaker notification))
       (let ((tts-speaker-process lane) returned outer)
         (setq outer
               (emacsvox-aural-call-with-delivery-transaction
                lane (lambda ()
                       (tts-speak-using-voice 'voice-bolden "Exact named text")
                       (setq returned (if marked
                                          (tts--protocol-dispatch-marked #'ignore #'ignore)
                                        (tts--protocol-dispatch-tracked #'ignore))))))
         (let* ((doc (omnivox-choice-consumer-test--timeline (car writes)))
                (span (car (plist-get doc :spans))))
           (should (= returned outer (plist-get doc :dispatch_id)))
           (should (equal "layered" (plist-get span :mode)))
           (should (equal "Exact named text" (plist-get (plist-get span :span) :text)))
           (should-not (plist-get (plist-get span :span) :context)))
         (should (tts-queue--known-empty-p lane)))))))

(ert-deftest tts-queue-named-limits-preserve-original-helper-behavior ()
  (dolist (case '((voice-bolden " " opaque-command)
                  (voice-bolden "first\nsecond" opaque-command)
                  ((voice-bolden voice-monotone) "compound" opaque-definition)))
    (omnivox-choice-consumer-test--with-speech
     (emacsvox-aural-call-with-delivery-transaction
      speaker (lambda () (tts-speak-using-voice (car case) (cadr case)) (tts--protocol-dispatch)))
     (should-not (string-match-p "emacsvox_timeline" (cdar writes)))
     (should (eq (nth 2 case) (plist-get (process-get speaker emacsvox-aural--queue-limitation-property) :reason)))))
  (omnivox-choice-consumer-test--with-speech
   (dolist (voice '(inaudible (voice-bolden inaudible)))
     (emacsvox-aural-call-with-delivery-transaction
      speaker (lambda () (tts-speak-using-voice voice "quiet"))))
   (should-not writes)))

(ert-deftest tts-queue-named-registration-mismatch-fails-before-stop ()
  (dolist (fault '(pending changed-palette changed-definition))
    (omnivox-choice-consumer-test--with-speech
     (let ((emacsvox-aural-submission-controls-interruption t)
           (emacsvox-aural-submission-delivery-policy 'urgent))
       (should-error
        (emacsvox-aural-call-with-delivery-transaction
         speaker
         (lambda ()
           (tts-speak-using-voice 'voice-bolden "named")
           (tts--protocol-dispatch)
           (if (eq fault 'pending)
               (process-put speaker omnivox--choice-registration-property nil)
             (let* ((snapshot (tts--dispatch-copy-data (process-get speaker omnivox--choice-registration-property)))
                    (source (omnivox--choice-provenance snapshot "bolden")))
               (setf (plist-get source (if (eq fault 'changed-palette) :palette :definition)) 'changed)
               (process-put speaker omnivox--choice-registration-property snapshot))))))
       (should-not writes)
       (tts-preparation-test--empty speaker)))))

(ert-deftest tts-queue-named-own-stop-hooks-recheck-prepared-projection ()
  (dolist (nested '(nil neutral queue dispatch letter))
    (omnivox-choice-consumer-test--with-speech
     (let ((emacsvox-aural-submission-controls-interruption t)
           (emacsvox-aural-submission-delivery-policy 'urgent)
           (tts-stopped-hook
            (list (lambda (_)
                    (pcase nested
                      ('neutral (tts-queue--send-typed speaker "OMNIVOX-REMOTE ping\n" 'neutral))
                      ('queue (tts--protocol-queue-text "OTHER"))
                      ('dispatch (tts--protocol-dispatch))
                      ('letter (tts--protocol-letter "A")))))))
       (emacsvox-aural-call-with-delivery-transaction
        speaker (lambda () (tts-speak-using-voice 'voice-bolden "named") (tts--protocol-dispatch)))
       (should (equal "s\n" (cdr (car (last writes)))))
       (if (memq nested '(nil neutral))
           (should (string-match-p "emacsvox_timeline" (cdar writes)))
         (should-not (cl-some (lambda (write) (string-match-p "emacsvox_timeline" (cdr write))) writes))
         (should-not (process-get speaker emacsvox-aural--queue-limitation-property))
         (tts-preparation-test--empty speaker))))))

(ert-deftest tts-queue-named-diagnostic-is-bounded-and-published-only-after-send ()
  (omnivox-choice-consumer-test--with-speech
   (let ((named (cl-loop for index below 40 collect (list :name (intern (format "name-%d" index))))))
     (let ((old (emacsvox-aural--queue-limitation-effect speaker 10 named 'unknown-queue))
           (new (emacsvox-aural--queue-limitation-effect speaker 11 nil nil)))
       (should-not (process-get speaker emacsvox-aural--queue-limitation-property))
       (funcall old)
       (let ((diagnostic (process-get speaker emacsvox-aural--queue-limitation-property)))
         (should (= 32 (length (plist-get diagnostic :logical-ids))))
         (should (plist-get diagnostic :truncated)))
       (funcall new)
       (funcall old)
       (should (= 11 (plist-get (process-get speaker emacsvox-aural--queue-limitation-property) :submission)))
       (should-not (plist-get (process-get speaker emacsvox-aural--queue-limitation-property) :reason))))))

(ert-deftest tts-queue-named-intervening-output-aborts-without-legacy-replay ()
  (dolist (phase '(binding framing))
    (omnivox-choice-consumer-test--with-speech
     (let* ((function (if (eq phase 'binding) 'tts--dispatch-bind-semantics
                        'emacsvox-aural--frame-structured-timeline))
            (original (symbol-function function)) injected)
       (cl-letf (((symbol-function function)
                  (lambda (&rest arguments)
                    (prog1 (apply original arguments)
                      (unless injected
                        (setq injected t)
                        ;; This restores empty, but must still invalidate the serial.
                        (tts-queue--send-typed speaker "q {OTHER}\nd\n" '(queue clear)))))))
         (should-not
          (emacsvox-aural-call-with-delivery-transaction
           speaker (lambda () (tts-speak-using-voice 'voice-bolden "named")
                     (tts--protocol-dispatch-tracked #'ignore)))))
       (should injected)
       (should (equal (mapcar #'cdr writes) '("q {OTHER}\nd\n")))
       (should-not (process-get speaker emacsvox-aural--queue-limitation-property))
       (tts-preparation-test--empty speaker)))))

(ert-deftest tts-queue-named-overlap-at-primitive-is-ambiguous-without-replay ()
  (omnivox-choice-consumer-test--with-speech
   (let (injected)
     (cl-letf (((symbol-function 'process-send-string)
                (lambda (process command)
                  (push (cons process command) writes)
                  (when (and (not injected) (string-match-p "emacsvox_timeline" command))
                    (setq injected t)
                    (tts-queue--send-typed process "OMNIVOX-REMOTE ping\n" 'neutral)))))
       (tts-queue--install)
       (should-not
        (emacsvox-aural-call-with-delivery-transaction
         speaker (lambda () (tts-speak-using-voice 'voice-bolden "named")
                   (tts--protocol-dispatch-tracked #'ignore)))))
     (should injected)
     (should (= 2 (length writes)))
     (should (= 1 (cl-count-if (lambda (write) (string-match-p "emacsvox_timeline" (cdr write))) writes)))
     (should-not (tts-queue--known-empty-p speaker))
     (should-not (process-get speaker emacsvox-aural--queue-limitation-property))
     (tts-preparation-test--empty speaker))))

(ert-deftest tts-queue-named-future-stop-cannot-justify-promotion ()
  (dolist (case '(((pending boundary usable) nil cross-call-queue)
                  ((empty unproven usable) nil input-boundary-unproven)
                  ((unknown unproven unusable) t remote-proof-unusable)))
    (omnivox-choice-consumer-test--with-speech
     (tts-queue-state-test--set speaker (car case) (cadr case))
     (let ((emacsvox-aural-submission-controls-interruption t)
           (emacsvox-aural-submission-delivery-policy 'urgent))
       (emacsvox-aural-call-with-delivery-transaction
        speaker (lambda () (tts-speak-using-voice 'voice-bolden "named") (tts--protocol-dispatch))))
     (should (equal "s\n" (cdr (car (last writes)))))
     (should-not (cl-some (lambda (write) (string-match-p "emacsvox_timeline" (cdr write))) writes))
     (should (eq (nth 2 case) (plist-get (process-get speaker emacsvox-aural--queue-limitation-property) :reason))))))

(ert-deftest tts-queue-named-command-mutation-fails-before-policy-stop ()
  (omnivox-choice-consumer-test--with-speech
   (let ((emacsvox-aural-submission-controls-interruption t)
         (emacsvox-aural-submission-delivery-policy 'urgent)
         (emacsvox-aural-last-delivery-failure nil))
     (emacsvox-aural-call-with-delivery-transaction
      speaker (lambda ()
                (tts--protocol-sync)
                (aset (emacsvox-aural--delivery-entry-command
                       (car emacsvox-aural--delivery-transaction-entries)) 0 ?X)
                (tts-speak-using-voice 'voice-bolden "named")
                (tts--protocol-dispatch)))
     (should-not writes)
     (should (eq 'dispatch-admission-failed (plist-get emacsvox-aural-last-delivery-failure :reason)))
     (tts-preparation-test--empty speaker)))
  (omnivox-choice-consumer-test--with-speech
   (let ((emacsvox-aural-submission-controls-interruption t)
         (emacsvox-aural-submission-delivery-policy 'urgent))
     (should-error
      (emacsvox-aural-call-with-delivery-transaction
       speaker (lambda ()
                 (tts-speak-using-voice 'voice-bolden "named")
                 (let* ((data (car (emacsvox-aural--named-queue-records)))
                        (entry (cadr (plist-get data :entries))))
                   (aset (emacsvox-aural--delivery-entry-command entry) 3 ?X))
                 (tts--protocol-dispatch))))
     (should-not writes)
     (tts-preparation-test--empty speaker))))

(provide 'tts-queue-handoff-tests)
;;; tts-queue-handoff-tests.el ends here
