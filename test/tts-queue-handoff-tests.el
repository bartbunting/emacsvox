;;; tts-queue-handoff-tests.el --- Captured queue boundaries -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Exercise complete producers and independently specified dispatch sequences.
;;; Code:
(require 'omnivox-choice-consumer-tests)
(require 'tts-preparation-tests)

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

(provide 'tts-queue-handoff-tests)
;;; tts-queue-handoff-tests.el ends here
