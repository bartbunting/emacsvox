;;; emacsvox-aural-recording-tests.el --- Delivery recording contracts -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Commentary:
;; Capture real muted deliveries, then reconstruct without live access.
;;; Code:
(require 'ert)
(require 'omnivox-rich-tone-tests)
(require 'emacsvox-aural-recording)

(defconst emacsvox-recording-test--directory
  (file-name-directory (or load-file-name buffer-file-name)))

(defmacro emacsvox-recording-test--isolated (&rest body)
  (declare (indent 0) (debug t))
  `(let ((emacsvox-aural-recording--state nil) (emacsvox-aural-recording--timer nil)
         (emacsvox-aural--recording-observer nil) (emacsvox-aural--recording-error nil)
         (this-command nil))
     (unwind-protect (progn ,@body) (emacsvox-aural-recording--clear))))

(defun emacsvox-recording-test--roundtrip ()
  (emacsvox-aural-recording--reconstruct
   (emacsvox-aural-recording--parse
    (emacsvox-aural-recording--json (emacsvox-aural-recording--bundle)))))

(defun emacsvox-recording-test--capture ()
  (emacsvox-aural-record-next-delivery 'main)
  (tts-speak (propertize "café 日本" 'personality 'voice-bolden))
  (emacsvox-aural-recording--bundle))

(ert-deftest emacsvox-aural-recording-native-versions-roundtrip-without-live-access ()
  (dolist (version '(3 4 5 6 7))
    (emacsvox-recording-test--isolated
      (omnivox-native-runtime-test--with-speech
        (pcase version
          (3 (process-put speaker emacsvox-aural--structured-timeline-process-property 3))
          (4 (process-put speaker omnivox--control-capabilities-property (list :features omnivox-test--choice-features))
             (process-put speaker omnivox--choice-registration-property nil)
             (let (requests)
               (cl-letf (((symbol-function 'process-send-string)
                          (lambda (process command)
                            (push (cons process (omnivox-test--choice-decode-command command)) requests))))
                 (omnivox-register-logical-voices))
               (dolist (write requests)
                 (omnivox--dispatch-control-response (car write) (omnivox-test--choice-registration-ack write)))))
          (6 (omnivox-rich-tone-test--enable speaker)
             (process-put speaker omnivox--choice-registration-property nil)
             (omnivox-native-runtime-test--register))
          (7 (omnivox-extended-tone-test--enable speaker)
             (process-put speaker omnivox--choice-registration-property nil)
             (omnivox-native-runtime-test--register)))
        (setq writes nil)
        (emacsvox-recording-test--capture)
        (let ((expected (mapcar #'cdr (reverse writes))) result)
          (cl-letf (((symbol-function 'process-get) (lambda (&rest _) (error "Live process read")))
                    ((symbol-function 'process-send-string) (lambda (&rest _) (error "Speech write")))
                    ((symbol-function 'omnivox-remote-resource) (lambda (&rest _) (error "Resource access")))
                    ((symbol-function 'emacsvox-aural--timeline-delivery-fields) (lambda () (error "Policy read")))
                    ((symbol-function 'make-network-process) (lambda (&rest _) (error "Network access"))))
            (setq result (emacsvox-recording-test--roundtrip)))
          (should (eq (plist-get result :status) 'matching))
          (should (= version (plist-get (plist-get result :document) :protocol_version)))
          (should (equal (apply #'concat expected) (apply #'concat (plist-get result :wire)))))))))

(ert-deftest emacsvox-aural-recording-preserves-wire-and-only-captures-one-lane ()
  (emacsvox-recording-test--isolated
    (omnivox-choice-consumer-test--with-speech
      (emacsvox-aural-record-next-delivery 'notification)
      (tts-speak "main speech")
      (should (eq (emacsvox-aural-recording--capture-phase emacsvox-aural-recording--state) 'armed))
      (tts-notify "chosen notification" t)
      (let* ((first (emacsvox-aural-recording--json (emacsvox-aural-recording--bundle)))
             (result (emacsvox-recording-test--roundtrip)))
        (should (eq (plist-get result :status) 'matching))
        (should (equal (apply #'concat (plist-get result :wire)) (cdar writes)))
        (tts-notify "later notification" t)
        (should (equal first (emacsvox-aural-recording--json (emacsvox-aural-recording--bundle))))))))

(ert-deftest emacsvox-aural-recording-independently-submitted-observer-speech-is-excluded ()
  (emacsvox-recording-test--isolated
    (omnivox-choice-consumer-test--with-speech
      (let ((emacsvox-aural-plan-presented-hook
             (list (lambda (_plan)
                     (let ((emacsvox-aural-plan-presented-hook nil))
                       (emacsvox-aural--call-independent-callback (lambda () (tts-speak "independent callback"))))))))
        (emacsvox-recording-test--capture))
      (let ((json (emacsvox-aural-recording--json (emacsvox-aural-recording--bundle))))
        (should-not (string-match-p "independent callback" json))
        (should (eq (plist-get (emacsvox-recording-test--roundtrip) :status) 'matching))))))

(ert-deftest emacsvox-aural-recording-owns-input-and-strips-editor-properties ()
  (emacsvox-recording-test--isolated
    (omnivox-choice-consumer-test--with-speech
      (let ((text (propertize "original text" 'personality 'voice-bolden 'private-buffer (current-buffer))))
        (emacsvox-aural-record-next-delivery 'main)
        (tts-speak text)
        (aset text 0 ?X)
        (let ((json (emacsvox-aural-recording--json (emacsvox-aural-recording--bundle))))
          (should (string-match-p "original text" json))
          (should-not (string-match-p "private-buffer" json))
          (should (eq (plist-get (emacsvox-recording-test--roundtrip) :status) 'matching)))))))

(ert-deftest emacsvox-aural-recording-readiness-suppression-is-complete-no-output ()
  (emacsvox-recording-test--isolated
    (omnivox-choice-consumer-test--with-speech
      (emacsvox-aural-set-delivery-readiness speaker 'pending)
      (emacsvox-recording-test--capture)
      (let ((result (emacsvox-recording-test--roundtrip)))
        (should (eq (plist-get result :status) 'matching))
        (should (eq (plist-get result :coverage) 'no-output))
        (should (eq (plist-get (plist-get result :outcome) :disposition) 'suppressed))))))

(ert-deftest emacsvox-aural-recording-limits-discard-text-without-changing-speech ()
  (emacsvox-recording-test--isolated
    (omnivox-choice-consumer-test--with-speech
      (emacsvox-aural-record-next-delivery 'main)
      (tts-speak (make-string (1+ emacsvox-aural-recording--limit) ?x))
      (should writes)
      (let* ((bundle (emacsvox-aural-recording--bundle))
             (json (emacsvox-aural-recording--json bundle)))
        (should (< (length json) 4096))
        (should (eq (gethash "complete" bundle) :false))
        (should (= (length (gethash "operations" bundle)) 0))
        (should-not (string-match-p "xxxxxxxx" json))
        (should (eq (plist-get (emacsvox-recording-test--roundtrip) :status) 'incomplete))))))

(ert-deftest emacsvox-aural-recording-large-styled-captures-export-and-reconstruct ()
  "Ordinary styled selections exceeding the old cap remain reproducible."
  (let ((table (mapconcat (lambda (index)
                           (concat (propertize (format "Item %d " index) 'personality 'voice-bolden)
                                   "status ready; modified today; owner local.\n"))
                         (number-sequence 1 40) ""))
        (code (with-temp-buffer
                (insert-file-contents (expand-file-name "fixtures/delivery-code.el.txt"
                                                       emacsvox-recording-test--directory))
                (emacs-lisp-mode)
                (font-lock-ensure)
                (let ((position (point-min)))
                  (while (< position (point-max))
                    (let ((end (next-single-property-change position 'face nil (point-max))))
                      (when (get-text-property position 'face)
                        (put-text-property position end 'personality 'voice-bolden))
                      (setq position end))))
                (buffer-string))))
    (dolist (case (list (cons 65536 table) (cons 131072 code)))
      (emacsvox-recording-test--isolated
        (omnivox-choice-consumer-test--with-speech
          (emacsvox-aural-record-next-delivery 'main)
          (emacsvox-aural-submit (cdr case) :delivery-policy 'ordered :interruption-policy 'none)
          (let* ((bundle (emacsvox-aural-recording--bundle))
                 (bytes (emacsvox-aural-recording--json bundle))
                 (wire (apply #'concat (mapcar #'cdr (reverse writes))))
                 (directory (make-temp-file "emacsvox-large-recording-" t))
                 (file (expand-file-name "capture.json" directory)))
            (unwind-protect
                (progn
                  (should (eq (gethash "complete" bundle) t))
                  (should (> (length bytes) (car case)))
                  (should (<= (length bytes) 262144))
                  (emacsvox-aural-export-recording file)
                  (should-not emacsvox-aural-recording--state)
                  (cl-letf (((symbol-function 'process-get) (lambda (&rest _) (error "Live process read")))
                            ((symbol-function 'process-send-string) (lambda (&rest _) (error "Speech write")))
                            ((symbol-function 'make-network-process) (lambda (&rest _) (error "Network access"))))
                    (let ((result (emacsvox-aural-reproduce-delivery file)))
                      (should (eq (plist-get result :status) 'matching))
                      (should (equal wire (apply #'concat (plist-get result :wire)))))))
              (delete-directory directory t))))))))

(ert-deftest emacsvox-aural-recording-import-byte-boundary ()
  "Accept valid 256 KiB JSON and reject one extra byte before construction."
  (emacsvox-recording-test--isolated
    (omnivox-choice-consumer-test--with-speech
      (let* ((json (emacsvox-aural-recording--json (emacsvox-recording-test--capture)))
             (directory (make-temp-file "emacsvox-recording-boundary-" t))
             (file (expand-file-name "capture.json" directory)))
        (unwind-protect
            (progn
              (with-temp-file file
                (set-buffer-multibyte nil)
                (insert json (make-string (- 262144 (length json)) ?\s)))
              (should (eq (plist-get (emacsvox-aural-reproduce-delivery file) :status) 'matching))
              (write-region " " nil file t 'silent)
              (let (constructed)
                (cl-letf (((symbol-function 'emacsvox-aural-recording--reconstruct)
                           (lambda (&rest _) (setq constructed t))))
                  (should-error (emacsvox-aural-reproduce-delivery file)))
                (should-not constructed)))
          (delete-directory directory t))))))

(ert-deftest emacsvox-aural-recording-operation-limit-and-recorder-fault-preserve-delivery ()
  (dolist (fault '(limit observer construction))
    (emacsvox-recording-test--isolated
      (omnivox-choice-consumer-test--with-speech
        (let ((emacsvox-aural-recording--operation-limit (if (eq fault 'limit) 1 4096)))
          (emacsvox-aural-record-next-delivery 'main)
          (when (eq fault 'observer)
            (setq emacsvox-aural--recording-observer (lambda (&rest _) (error "Injected recorder failure"))))
          (if (eq fault 'construction)
              (cl-letf (((symbol-function 'emacsvox-aural-recording--snapshot)
                         (lambda (&rest _) (error "Injected snapshot failure"))))
                (tts-speak "speech survives")
                ;; Cleanup is immediate, without needing Status or Export.
                (should-not (emacsvox-aural-recording--capture-assembly emacsvox-aural-recording--state))
                (should-not (emacsvox-aural-recording--capture-operations emacsvox-aural-recording--state))
                (should-not emacsvox-aural--recording-observer))
            (tts-speak "speech survives")))
        (should writes)
        (should (eq (plist-get (emacsvox-recording-test--roundtrip) :status) 'incomplete))))))

(ert-deftest emacsvox-aural-recording-stop-and-uncertain-send-do-not-claim-success ()
  (dolist (fault '(stop send))
    (emacsvox-recording-test--isolated
      (omnivox-choice-consumer-test--with-speech
        (emacsvox-aural-record-next-delivery 'main)
        (if (eq fault 'stop)
            (let ((emacsvox-aural-plan-presented-hook (list (lambda (_plan) (tts-stop)))))
              (tts-speak "stop during publication"))
          (cl-letf (((symbol-function 'process-send-string) (lambda (&rest _) (error "Uncertain send"))))
            (condition-case nil (tts-speak "ambiguous") (error nil))))
        (let* ((result (emacsvox-recording-test--roundtrip)) (outcome (plist-get result :outcome)))
          (should (memq (plist-get result :status) '(matching incomplete)))
          (should (memq (plist-get outcome :disposition) '(cancelled ambiguous rejected))))))))

(ert-deftest emacsvox-aural-recording-multipart-uses-actual-id-and-recorded-frame-limits ()
  (emacsvox-recording-test--isolated
    (omnivox-choice-consumer-test--with-speech
      (let ((tts--tracked-dispatch-sequence 1000000000)
            (emacsvox-aural--timeline-frame-max-bytes 128)
            (emacsvox-aural--timeline-encoded-fragment-max-bytes 172))
        (emacsvox-recording-test--capture))
      (let ((result (emacsvox-recording-test--roundtrip)))
        (should (eq (plist-get result :status) 'matching))
        (should (> (length (plist-get result :wire)) 1))
        (should (= (plist-get (plist-get result :document) :dispatch_id) 1000000001))))))

(ert-deftest emacsvox-aural-recording-compatibility-bytes-remain-inert ()
  (emacsvox-recording-test--isolated
    (omnivox-choice-consumer-test--with-speech
      (process-put speaker emacsvox-aural--structured-timeline-process-property nil)
      (emacsvox-recording-test--capture)
      (let ((result (emacsvox-recording-test--roundtrip)))
        (should (eq (plist-get result :status) 'matching))
        (should (eq (plist-get result :coverage) 'compatibility-bytes))
        (should (equal (apply #'concat (plist-get result :wire))
                       (apply #'concat (mapcar #'cdr (reverse writes)))))))))

(ert-deftest emacsvox-aural-recording-cancel-expiry-and-command-feedback ()
  (emacsvox-recording-test--isolated
    (omnivox-choice-consumer-test--with-speech
      (let (expire)
        (cl-letf (((symbol-function 'run-at-time) (lambda (seconds repeat function)
                                                  (should (= seconds 60)) (should-not repeat)
                                                  (setq expire function))))
          (emacsvox-aural-record-next-delivery 'main))
        (let ((this-command 'emacsvox-aural-record-next-delivery)) (tts-speak "arming feedback"))
        (should (eq (emacsvox-aural-recording--capture-phase emacsvox-aural-recording--state) 'armed))
        (funcall expire)
        (should-not emacsvox-aural-recording--state)
        (emacsvox-aural-record-next-delivery 'main)
        ;; An obsolete timer cannot clear a later armed recording.
        (funcall expire)
        (should emacsvox-aural-recording--state)
        (emacsvox-aural-cancel-recording)
        (should-not emacsvox-aural--recording-observer)
        (should-not emacsvox-aural-recording--timer)))))

(ert-deftest emacsvox-aural-recording-export-is-private-atomic-and-explicit ()
  (emacsvox-recording-test--isolated
    (omnivox-choice-consumer-test--with-speech
      (emacsvox-recording-test--capture)
      (let* ((directory (make-temp-file "emacsvox-recording-" t))
             (file (expand-file-name "capture.json" directory)))
        (unwind-protect
            (progn
              (should-error (emacsvox-aural-export-recording (expand-file-name "missing/capture.json" directory)))
              (should emacsvox-aural-recording--state)
              (with-temp-file file (insert "old data"))
              (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) nil)))
                (should-error (emacsvox-aural-export-recording file)))
              (should emacsvox-aural-recording--state)
              (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
                (emacsvox-aural-export-recording file))
              (should (= (logand (file-modes file) #o777) #o600))
              (should-not emacsvox-aural-recording--state)
              (let ((file-name-handler-alist
                     (list (cons (regexp-quote file)
                                 (lambda (operation &rest _)
                                   (unless (eq operation 'file-remote-p)
                                     (ert-fail "Import invoked a file handler")))))))
                (should (eq (plist-get (emacsvox-aural-reproduce-delivery file) :status) 'matching)))
              (should (equal (directory-files directory nil "^[^.]") '("capture.json"))))
          (delete-directory directory t))))))

(ert-deftest emacsvox-aural-recording-rejects-schema-and-late-unknown-operation-before-assembly ()
  (emacsvox-recording-test--isolated
    (omnivox-choice-consumer-test--with-speech
      (let* ((bundle (emacsvox-recording-test--capture))
             (bytes (emacsvox-aural-recording--json bundle)))
        (dolist (mutation '(format construction unknown-field unknown-operation wrong-argument wrong-order))
          (let ((object (emacsvox-aural-recording--parse bytes)))
            (pcase mutation
              ('format (puthash "format" 99 object))
              ('construction (puthash "construction" 99 object))
              ('unknown-field (puthash "eval" "(delete-file ...)" object))
              ('unknown-operation (puthash "operations" (vconcat (gethash "operations" object)
                                                                 (vector (vector "load-file" ["symbol" "nil"]))) object))
              ('wrong-argument (puthash "operations" (vector (vector "span" (emacsvox-aural-recording--snapshot '(1 nil nil nil nil nil nil)))) object))
              ('wrong-order (puthash "operations" (vconcat (reverse (append (gethash "operations" object) nil))) object)))
            (cl-letf (((symbol-function 'emacsvox-aural--make-assembly) (lambda (&rest _) (ert-fail "Reconstructed before validation"))))
              (should-error (emacsvox-aural-recording--reconstruct object)))))))))

(ert-deftest emacsvox-aural-recording-parser-rejects-oversize-deep-duplicate-and-invalid-utf8 ()
  (dolist (bytes (list (make-string (1+ emacsvox-aural-recording--limit) ?\s)
                      (concat (make-string 300 ?\[) "0" (make-string 300 ?\]))
                      "{\"format\":1,\"format\":1}" "{\"format\":1,\"for\\u006dat\":1}"
                      (unibyte-string 255)))
    (should-error (emacsvox-aural-recording--parse bytes)))
  (let ((emacsvox-aural-recording--budget 1000) (emacsvox-aural-recording--nodes 0))
    (should-error
     (emacsvox-aural-recording--decode
      ["hash" "equal" [[["string" "key"] ["symbol" "absent"]]
                       [["string" "key"] ["integer" 1]]]]))))

(ert-deftest emacsvox-aural-recording-mismatch-does-not-claim-original-reproduction ()
  (emacsvox-recording-test--isolated
    (omnivox-choice-consumer-test--with-speech
      (let ((bundle (emacsvox-recording-test--capture)))
        (puthash "wire_hash" (make-string 64 ?0) bundle)
        (should (eq (plist-get (emacsvox-aural-recording--reconstruct bundle) :status) 'mismatch))
        (puthash "complete" :false bundle)
        (puthash "reason" "redacted" bundle)
        (should (eq (plist-get (emacsvox-aural-recording--reconstruct bundle) :status) 'incomplete))))))

(ert-deftest emacsvox-aural-recording-actions-coalescing-and-utf8-positions-roundtrip ()
  (emacsvox-recording-test--isolated
    (omnivox-choice-consumer-test--with-speech
      (let* ((run (omnivox-choice-timeline-test--run 'bolden nil nil "café 日本"))
             (plan (car run))
             (tone (emacsvox-aural--make-concrete-action :id 'tone :kind 'tone :pitch 880 :duration 20))
             (pause (emacsvox-aural--make-concrete-action :id 'pause :kind 'pause :duration 25)))
        (setf (emacsvox-aural-concrete-plan-before plan)
              (list (emacsvox-aural--make-concrete-action :id 'ignored :kind 'cue :resource "/not-opened.ogg"))
              (emacsvox-aural-concrete-plan-after plan) (list pause))
        (emacsvox-aural-record-next-delivery 'main)
        (emacsvox-aural-call-with-delivery-transaction
         speaker (lambda ()
                   (emacsvox-aural-queue-concrete-plan
                    plan (cadr run)
                    (list (list :utf8-offset 6 :actions
                                (list (emacsvox-aural--make-concrete-positioned-action
                                       :action tone :context '(:icons-enabled nil))))))
                   (tts--protocol-dispatch)))
        (let ((result (emacsvox-recording-test--roundtrip)))
          (should (eq (plist-get result :status) 'matching))
          (should (plist-get result :bindings))
          (should (cl-find 6 (plist-get (plist-get result :document) :actions)
                           :key (lambda (action) (plist-get (plist-get action :position) :utf8_offset))))
          (should (equal (apply #'concat (plist-get result :wire)) (cdar writes)))
          (should (string-match-p "omitted-action"
                                  (emacsvox-aural-recording--json (emacsvox-aural-recording--bundle)))))))))

(ert-deftest emacsvox-aural-recording-real-rule-actions-retain-semantics ()
  (emacsvox-recording-test--isolated
    (omnivox-choice-consumer-test--with-speech
      (emacsvox-test--transport-scheme
       '((:id heading :match (:role heading)
          :render (:before ((:id label :kind speech :text "Heading" :voice bolden))
                   :after ((:id pause :kind pause :duration 20 :anchor run))))))
      (emacsvox-aural-record-next-delivery 'main)
      (emacsvox-aural-submit "Body" :facts '(:role heading))
      (let ((result (emacsvox-recording-test--roundtrip)))
        (should (eq (plist-get result :status) 'matching))
        (should (= (length (plist-get (plist-get result :document) :spans)) 2))
        (should (plist-get result :bindings))))))

(ert-deftest emacsvox-aural-recording-harmless-splits-preserve-one-span ()
  (emacsvox-recording-test--isolated
    (omnivox-choice-consumer-test--with-speech
      (emacsvox-aural-record-next-delivery 'main)
      (emacsvox-aural-call-with-delivery-transaction
       speaker (lambda ()
                 (dolist (text '("café " "日本"))
                   (let ((run (omnivox-choice-timeline-test--run 'bolden nil nil text)))
                     (emacsvox-aural-queue-concrete-plan (car run) text)))
                 (tts--protocol-dispatch)))
      (let ((result (emacsvox-recording-test--roundtrip)))
        (should (eq (plist-get result :status) 'matching))
        (should (= (length (plist-get (plist-get result :document) :spans)) 1))))))

(ert-deftest emacsvox-aural-recording-scheduled-outcome-follows-only-its-delivery ()
  (dolist (finish '(flush cancel))
    (emacsvox-recording-test--isolated
      (omnivox-choice-playback-test--with-runtime
        (let ((emacsvox-aural-submission-delivery-policy 'replaceable)
              (emacsvox-aural-submission-replacement-key 'recording-test)
              (emacsvox-aural--pending-deliveries (make-hash-table :test #'equal)))
          (cl-letf (((symbol-function 'process-send-string) #'ignore))
            (unwind-protect
                (progn
                  (emacsvox-aural-record-next-delivery 'main)
                  (emacsvox-aural-call-with-delivery-transaction
                   speaker (lambda () (tts--protocol-queue-text "pending") (tts--protocol-dispatch)))
                  (should (eq (emacsvox-aural-recording--disposition (emacsvox-aural-recording--bundle)) 'scheduled))
                  (let ((emacsvox-aural--delivery-result '(:disposition untouched)))
                    (if (eq finish 'flush) (emacsvox-aural-flush-pending-deliveries speaker)
                      (emacsvox-aural-cancel-pending-deliveries speaker)))
                  (should (eq (emacsvox-aural-recording--disposition (emacsvox-aural-recording--bundle))
                              (if (eq finish 'flush) 'written 'cancelled)))
                  (should (eq (plist-get (emacsvox-recording-test--roundtrip) :status) 'matching)))
              (emacsvox-aural-cancel-pending-deliveries speaker))))))))

(ert-deftest emacsvox-aural-recording-failed-rename-preserves-file-and-capture ()
  (emacsvox-recording-test--isolated
    (omnivox-choice-consumer-test--with-speech
      (emacsvox-recording-test--capture)
      (let* ((directory (make-temp-file "emacsvox-recording-" t))
             (file (expand-file-name "capture.json" directory)))
        (unwind-protect
            (progn
              (with-temp-file file (insert "original"))
              (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t))
                        ((symbol-function 'rename-file) (lambda (&rest _) (error "Injected rename failure"))))
                (should-error (emacsvox-aural-export-recording file)))
              (should emacsvox-aural-recording--state)
              (should (equal (with-temp-buffer (insert-file-contents file) (buffer-string)) "original"))
              (should (equal (directory-files directory nil directory-files-no-dot-files-regexp) '("capture.json"))))
          (delete-directory directory t))))))

(ert-deftest emacsvox-aural-recording-rejects-live-and-cyclic-data-without-interning-input ()
  (dolist (value (list (current-buffer) (point-marker) (lambda () nil)
                      (let ((cycle (list 'x))) (setcdr cycle cycle) cycle)))
    (should-error (emacsvox-aural-recording--snapshot value)))
  (let* ((name (concat "recording-uninterned-" (make-temp-name "")))
         (emacsvox-aural-recording--budget 1000) (emacsvox-aural-recording--nodes 0)
         (decoded (emacsvox-aural-recording--decode (vector "symbol" name))))
    (should (symbolp decoded))
    (should-not (intern-soft name))))

(ert-deftest emacsvox-aural-recording-owned-process-death-keeps-notification-independent ()
  "Retained recovery ownership cannot publish cancelled recorded speech."
  (emacsvox-recording-test--isolated
    (omnivox-choice-consumer-test--with-speech
      (let ((command (symbol-function 'process-command))
            (copier (symbol-function 'emacsvox-aural--own-candidate-data))
            (emacsvox-speak-messages nil))
        (cl-letf (((symbol-function 'process-command)
                   (lambda (process)
                     (if (eq process speaker) '("omnivox" "--voice-library-owner")
                       (funcall command process)))))
          (set-process-sentinel speaker #'tts--speech-process-sentinel)
          (emacsvox-aural-record-next-delivery 'main)
          (setq writes nil)
          (cl-letf (((symbol-function 'emacsvox-aural--own-candidate-data)
                     (lambda (data)
                       (prog1 (funcall copier data) (delete-process speaker)))))
            (condition-case nil (tts-speak "cancelled during preparation") (error nil)))
          (should-not (process-live-p speaker))
          (should (eq tts-speaker-process speaker))
          (should (process-live-p notification))
          (should-not writes)
          (should (zerop (or (process-get speaker 'tts--dispatch-owner-count) 0)))
          (should (zerop (or (process-get speaker 'tts--dispatch-metadata-bytes) 0)))
          (should-not emacsvox-aural--recording-observer)
          (let* ((result (emacsvox-recording-test--roundtrip))
                 (capture (emacsvox-aural-recording--json (emacsvox-aural-recording--bundle))))
            (should (memq (plist-get result :status) '(matching incomplete)))
            (should (memq (plist-get (plist-get result :outcome) :disposition) '(cancelled rejected)))
            (tts-notify "notification survives" t)
            (should writes)
            (should (cl-every (lambda (write) (eq (car write) notification)) writes))
            (should (equal capture (emacsvox-aural-recording--json
                                    (emacsvox-aural-recording--bundle))))))))))

(provide 'emacsvox-aural-recording-tests)
;;; emacsvox-aural-recording-tests.el ends here
