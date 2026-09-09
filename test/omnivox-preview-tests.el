;;; omnivox-preview-tests.el --- Private preview ownership contracts -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Commentary:
;; Exercise real coordinator, Stop and stream observation with muted primitives.
;;; Code:
(require 'ert)
(require 'emacsvox-tts-tests)
(require 'tts-queue-state-tests)

(defun omnivox-preview-test--entry (individual)
  (if individual (emacsvox-test--individual-preview-entry)
    (emacsvox-test--complete-preview-entry)))

(defun omnivox-preview-test--start (individual &optional count callback)
  (omnivox-preview-voice-sequence
   (make-list (or count 1) (omnivox-preview-test--entry individual)) (or callback #'ignore)))

(defun omnivox-preview-test--reply (speaker id individual)
  (omnivox--dispatch-control-response
   speaker (if individual (emacsvox-test--individual-preview-response id)
             ;; Match normal legacy decoding, which maps arrays/null to lists/nil.
             (omnivox--decode-control-response
              (base64-encode-string
               (json-serialize (emacsvox-test--complete-preview-response id)) t)))))

(defun omnivox-preview-test--clean (speaker)
  (should-not (process-get speaker 'omnivox--preview-operation))
  (should-not (process-get speaker 'tts--interrupt-listener))
  (should-not tts-stopped-hook)
  (should (zerop (hash-table-count (omnivox--pending-requests speaker)))))

(ert-deftest omnivox-preview-startup-clears-framed-pending-queue ()
  (dolist (individual '(nil t))
    (emacsvox-test--with-complete-preview
     (tts-queue--send-typed speaker "q {earlier}\n" 'queue)
     (setq writes nil)
     (omnivox-preview-test--start individual)
     (should (= stops 1))
     (should (= (length writes) 1))
     (should (tts-queue--known-empty-p speaker))
     (omnivox-preview-test--reply speaker 41 individual)
     (omnivox-preview-test--clean speaker))))

(ert-deftest omnivox-preview-startup-grant-cannot-send-speech-or-clear-twice ()
  (tts-queue-state-test--with-process
   (tts-queue--send-typed process "q {earlier}\n" 'queue)
   (let ((guard (tts-queue--startup-guard process)))
     (should guard)
     (should-error (tts-queue--send process "q {new}\n" (tts-queue--describe "q {new}\n" 'queue) nil guard))
     (should (= (length writes) 1))))
  (tts-queue-state-test--with-process
   (let* ((guard (tts-queue--startup-guard process))
          (receipt (tts-queue--send process "s\n" (tts-queue--describe "s\n" 'clear) nil guard t)))
     (tts-queue--advance-stop guard receipt)
     (should (tts-queue--guard-valid-p guard))
     (should-not (tts-queue--guard-startup guard))
     (should-error (tts-queue--advance-stop guard receipt))
     (should-error (tts-queue--send process "s\n" (tts-queue--describe "s\n" 'clear) nil guard t))
     (should (= (length writes) 1)))))

(ert-deftest omnivox-preview-unproven-boundary-rejects-before-stop ()
  (emacsvox-test--with-complete-preview
   (process-send-string speaker "q {")
   (setq writes nil)
   (should-error (omnivox-preview-test--start nil))
   (should-not writes)
   (should (= stops 0))
   (omnivox-preview-test--clean speaker)))

(ert-deftest omnivox-preview-stop-during-preflight-cancels-startup ()
  (emacsvox-test--with-complete-preview
   (let ((prepare (symbol-function 'omnivox--preview-complete-request)))
     (cl-letf (((symbol-function 'omnivox--preview-complete-request)
                (lambda (&rest args) (prog1 (apply prepare args) (tts-stop)))))
       (should-error (omnivox-preview-test--start nil))))
   (should-not writes)
   (should (= stops 1))
   (omnivox-preview-test--clean speaker)))

(ert-deftest omnivox-preview-public-stop-in-own-stop-hook-cancels ()
  (emacsvox-test--with-complete-preview
   (let (observed)
     (let ((hook (lambda (_owner) (unless observed (setq observed t) (tts-stop)))))
       (add-hook 'tts-stopped-hook hook)
       (omnivox-preview-test--start nil 1 (lambda (value) (push value results)))
       (remove-hook 'tts-stopped-hook hook)))
   (should-not writes)
   (should (= stops 2))
   (should (= (length results) 1))
   (should (eq (plist-get (car results) :status) 'cancelled))
   (omnivox-preview-test--clean speaker)))

(ert-deftest omnivox-preview-either-mode-can-supersede-startup ()
  (dolist (individual '(nil t))
    (emacsvox-test--with-complete-preview
     (let (replacement)
       (let ((hook (lambda (_owner)
                     (unless replacement
                       (setq replacement t)
                       (omnivox-preview-test--start (not individual))))))
         (add-hook 'tts-stopped-hook hook)
         (omnivox-preview-test--start individual 1 (lambda (value) (push value results)))
         (remove-hook 'tts-stopped-hook hook)))
     (should (= (length writes) 1))
     (should (= (length results) 1))
     (should (eq (plist-get (car results) :status) 'cancelled))
     (omnivox-preview-test--reply speaker 41 (not individual))
     (omnivox-preview-test--clean speaker))))

(ert-deftest omnivox-preview-early-response-advances-after-write-only ()
  (dolist (individual '(nil t))
    (emacsvox-test--with-complete-preview
     (let ((depth 0) (maximum 0))
       (setq preview-write-hook
             (lambda (_owner command)
               (unless (equal command "s\n")
                 (cl-incf depth) (setq maximum (max maximum depth))
                 (unwind-protect
                     (let* ((request (emacsvox-test--omnivox-decode-command command))
                            (id (plist-get request :request_id)))
                       (omnivox-preview-test--reply speaker id individual))
                   (cl-decf depth)))))
       (omnivox-preview-test--start individual 64 (lambda (value) (push value results)))
       (should (= maximum 1))
       (should (= (length writes) 64))
       (should (= (length (plist-get (car results) :results)) 64))
       (should (eq (plist-get (car results) :status) 'completed))
       (omnivox-preview-test--clean speaker)))))

(ert-deftest omnivox-preview-early-response-then-failure-never-starts-next ()
  (dolist (individual '(nil t))
    (emacsvox-test--with-complete-preview
     (setq preview-write-hook
           (lambda (_owner command)
             (unless (equal command "s\n")
               (omnivox-preview-test--reply speaker 41 individual)
               (error "write failed after response"))))
     (if individual
         (should-error (omnivox-preview-test--start t 2 (lambda (value) (push value results))))
       (omnivox-preview-test--start nil 2 (lambda (value) (push value results))))
     (should (= omnivox--control-request-sequence 41))
     (should (eq (plist-get (car results) :status) 'failed))
     (should-not (plist-get (car results) :results))
     (omnivox-preview-test--clean speaker))))

(ert-deftest omnivox-preview-nonlocal-exits-release-every-reservation ()
  (dolist (individual '(nil t))
    (dolist (stage '(stop send))
      (dolist (exit-kind '(quit throw))
        (emacsvox-test--with-complete-preview
         (setq preview-write-hook
               (lambda (_owner command)
                 (when (eq (equal command "s\n") (eq stage 'stop))
                   (if (eq exit-kind 'quit) (signal 'quit nil) (throw 'preview-exit 'escaped)))))
         (catch 'preview-exit
           (condition-case nil (omnivox-preview-test--start individual 2) (quit nil)))
         (omnivox-preview-test--clean speaker))))))

(ert-deftest omnivox-preview-public-stop-nonlocal-exits-retire-waiting-sample ()
  (dolist (exit-kind '(error quit throw))
    (emacsvox-test--with-complete-preview
     (omnivox-preview-test--start t)
     (setq preview-write-hook
           (lambda (_owner command)
             (when (equal command "s\n")
               (pcase exit-kind
                 ('error (error "Stop write failed"))
                 ('quit (signal 'quit nil))
                 ('throw (throw 'preview-exit 'escaped))))))
     (catch 'preview-exit (condition-case nil (tts-stop) ((error quit) nil)))
     (omnivox-preview-test--clean speaker))))

(ert-deftest omnivox-preview-stop-callback-runs-after-interrupt-in-independent-capture ()
  (emacsvox-test--with-complete-preview
   (let (observed)
     (omnivox-preview-test--start
      t 1 (lambda (_result)
            (should-not emacsvox-aural--delivery-transaction-active-p)
            (setq observed stops)
            (omnivox-preview-test--start nil)))
     (let ((emacsvox-aural--delivery-transaction-active-p t)) (tts-stop))
     (should (= observed 2))
     (should (= stops 3))
     (omnivox-preview-test--reply speaker 42 nil)
     (omnivox-preview-test--clean speaker))))

(ert-deftest omnivox-preview-timeout-before-reentrant-exact-replacement ()
  (emacsvox-test--with-complete-preview
   (let (timeout before)
     (cl-letf (((symbol-function 'run-at-time)
                (lambda (_time _repeat callback) (setq timeout callback) nil)))
       (omnivox-preview-test--start nil 1
                                    (lambda (_result) (setq before stops) (omnivox-preview-test--start t)))
       (funcall timeout)
       (should (= before 2))
       (should (= stops 3))
       (should (gethash 42 (omnivox--pending-requests speaker)))
       (omnivox-preview-test--reply speaker 42 t)
       (omnivox-preview-test--clean speaker)))))

(ert-deftest omnivox-preview-overlapping-heartbeat-prevents-advancement ()
  (emacsvox-test--with-complete-preview
   (setq preview-write-hook
         (lambda (_owner command)
           (unless (equal command "s\n")
             (let (preview-write-hook) (tts-queue--send-typed speaker "OMNIVOX-REMOTE ping\n" 'neutral))
             (omnivox-preview-test--reply speaker 41 nil))))
   (omnivox-preview-test--start nil 2 (lambda (value) (push value results)))
   (should (= omnivox--control-request-sequence 41))
   (should (eq (plist-get (car results) :status) 'failed))
   (should-not (plist-get (car results) :results))
   (omnivox-preview-test--clean speaker)))

(ert-deftest omnivox-preview-input-strings-are-frozen ()
  (emacsvox-test--with-complete-preview
   (let ((entry (copy-tree (emacsvox-test--complete-preview-entry))))
     (setf (plist-get entry :text) (copy-sequence (plist-get entry :text)))
     (let ((selector (car (plist-get entry :selectors))))
       (setf (plist-get selector :voice-id) (copy-sequence (plist-get selector :voice-id))))
     (tts-preview-voices (list entry entry) #'ignore)
     (aset (plist-get entry :text) 0 ?X)
     (aset (plist-get (car (plist-get entry :selectors)) :voice-id) 0 ?X)
     (omnivox-preview-test--reply speaker 41 nil)
     (let ((request (emacsvox-test--omnivox-decode-command (car writes))))
       (should (string-prefix-p "The quick" (plist-get request :text)))
       (should (equal "Paul" (plist-get (car (plist-get request :preferences)) :voice_id)))))))

(ert-deftest omnivox-preview-invalid-later-exact-entry-does-not-interrupt ()
  (emacsvox-test--with-complete-preview
   (should-error (omnivox-preview-voice-sequence
                  (list (emacsvox-test--individual-preview-entry)
                        '(:text "bad" :selector (:kind exact :engine-id "test"))) #'ignore))
   (should-not writes)
   (should (= stops 0))
   (omnivox-preview-test--clean speaker)))

(ert-deftest omnivox-preview-rejects-cycle-and-capacity-before-stop ()
  (emacsvox-test--with-complete-preview
   (let ((cyclic (list (emacsvox-test--individual-preview-entry))))
     (setcdr cyclic cyclic)
     (should-error (omnivox--preview-individual-sequence cyclic #'ignore)))
   (should-error (omnivox-preview-test--start t 65))
   (let ((omnivox--control-request-sequence omnivox--choice-u64-max))
     (should-error (omnivox-preview-test--start nil)))
   (should (= stops 0))
   (omnivox-preview-test--clean speaker)))

(provide 'omnivox-preview-tests)
;;; omnivox-preview-tests.el ends here
