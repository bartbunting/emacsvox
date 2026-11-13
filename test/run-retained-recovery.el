;;; run-retained-recovery.el --- Isolated owner recovery probe -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

(require 'cl-lib)
(defvar recovery-test--root
  (file-name-as-directory
   (or (getenv "OMNIVOX_TEST_SOURCE_ROOT")
       (expand-file-name "../" (file-name-directory load-file-name)))))
(let ((root recovery-test--root))
  (add-to-list 'load-path (expand-file-name "lisp/" root))
  (setq load-prefer-newer (not (getenv "OMNIVOX_TEST_BYTECODE")))
  (require 'emacsvox-preamble)
  (require 'tts-speak)
  (require 'omnivox-library-runtime)
  (require 'omnivox-voices)
  (unless (getenv "OMNIVOX_TEST_BYTECODE")
    (load "tts-speak.el" nil nil)
    (load "tts-lifecycle.el" nil nil)
    (load "omnivox-library-runtime.el" nil nil)
    (load "omnivox-voices.el" nil nil))
  (setq emacsvox-servers-directory (expand-file-name "servers/" root)))
(dolist (function (if (getenv "OMNIVOX_TEST_EXPECT_BUG") '(tts--recover-speaker)
                    '(tts-recover tts--speech-process-sentinel omnivox-library--wait-for-recovered-speech
                      omnivox--register-logical-voices)))
  (let* ((file (symbol-file function 'defun))
         (suffix (if (getenv "OMNIVOX_TEST_BYTECODE") ".elc" ".el")))
    (unless (and file (string-suffix-p suffix file)
                 (string-prefix-p recovery-test--root file))
      (error "Unexpected loaded implementation: %S %S" function file))
    (princ (format "Loaded %s from %s\n" function file))))
(setq tts-program "omnivox" emacsvox-speak-messages nil
      tts-notification-device "both" debug-on-error t)
(unless (and (getenv "OMNIVOX_PROGRAM") (getenv "OMNIVOX_CONFIG_DIR")
             (getenv "OMNIVOX_VOICE_ROOT") (getenv "OMNIVOX_TEST_CONFIG_DIR"))
  (error "Explicit isolated inputs required"))
(defun recovery-test--wait (predicate)
  (let ((deadline (+ (float-time) 10)))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil .005))
    (unless (funcall predicate) (error "Recovery observation timed out"))))
(defun recovery-test--speech (&optional _text)
  (let ((start (float-time)) first terminal actual-engine)
    (recovery-test--wait (lambda () (omnivox--process-supports-p tts-speaker-process "playback_marker_events_v1")))
    (recovery-test--wait
     (lambda () (condition-case nil
                    (and (omnivox--choice-current-registration tts-speaker-process)
                         (cl-every
                          (lambda (process)
                            (let ((pending (process-get process omnivox--control-pending-property)))
                              (or (not pending) (= 0 (hash-table-count pending)))))
                          (list tts-speaker-process tts-notify-process)))
                  (error nil))))
    (tts-speak-marked "Recovery speech works."
                      (lambda (_id record)
                        (when (equal (plist-get record :type) "utterance_started")
                          (unless first
                            (setq first (float-time)
                                  actual-engine (plist-get record :engine_id)))))
                      (lambda (_id status) (setq terminal status)))
    (recovery-test--wait (lambda () terminal))
    (unless (eq terminal 'completed) (error "Speech did not complete: %S" terminal))
    (unless (equal actual-engine (getenv "OMNIVOX_ENGINE"))
      (error "Unexpected actual engine: %S" actual-engine))
    (princ (format "Actual engine %s; speech completion %.3f ms; first source event %S ms\n"
                   actual-engine (* 1000 (- (float-time) start)) (when first (* 1000 (- first start)))))))
(unwind-protect
    (progn
      (tts-initialize)
      (recovery-test--speech)
      (let ((old tts-speaker-process) (notify tts-notify-process)
            (activation (process-get tts-speaker-process 'omnivox-engine-activation))
            (notify-registration (process-get tts-notify-process omnivox--choice-registration-property)))
        (with-temp-file (expand-file-name "config.json" (getenv "OMNIVOX_TEST_CONFIG_DIR"))
          (insert "{broken"))
        (unless (getenv "OMNIVOX_TEST_SKIP_CRASH")
          (with-temp-buffer
            (unless (zerop
                     (call-process
                      "python3" nil t nil
                      (expand-file-name "kill-worker.py" (getenv "OMNIVOX_TEST_FIXTURE_DIR"))
                      (number-to-string (process-id old)) (getenv "OMNIVOX_PROGRAM")))
              (error "Owned crash injection failed: %s" (buffer-string)))
            (princ (buffer-string)))
          (recovery-test--wait (lambda () (process-get old 'omnivox-library-retired)))
          (if (getenv "OMNIVOX_TEST_EXPECT_BUG")
              (progn
                (tts-speak "Speak after the worker failure.")
                (accept-process-output nil .1)
                (unless (and (eq old tts-speaker-process) (process-live-p old))
                  (error "Expected baseline empty-owner bug was not reproduced"))
                (princ "REPRODUCED: confirmed retired native worker still has live client owner; speech does not recover\n")
                (tts--recover-speaker))
            (recovery-test--speech)
            (when (eq old tts-speaker-process) (error "Retired owner suppressed recovery")))
          (recovery-test--speech))
        (unless (getenv "OMNIVOX_TEST_EXPECT_BUG")
          (let ((working tts-speaker-process) failed)
            (condition-case nil (tts-restart) (error (setq failed t)))
            (unless (and failed (eq working tts-speaker-process))
              (error "Broken saved settings did not preserve working speech"))
            (recovery-test--speech)
            (let* ((start (float-time)) submitted completed status notice-error recovered
                   (timer
                    (run-at-time
                     .01 nil
                     (lambda ()
                       (setq submitted (float-time))
                       (condition-case err
                           (tts-notify-apply
                            (lambda (_)
                              (tts-speak-marked
                               "Notification during recovery." #'ignore
                               (lambda (_id outcome)
                                 (setq status outcome completed (float-time))))) nil)
                         (error (setq status 'failed notice-error (error-message-string err))))))))
              (unwind-protect
                  (progn
                    (tts-recover)
                    (setq recovered (float-time))
                    (recovery-test--wait (lambda () status))
                    (unless (and (eq status 'completed) submitted completed
                                 (< start submitted) (< completed recovered))
                      (error "Notification did not complete during recovery: %S %S" status notice-error))
                    (princ (format "Notification submitted/completed %.3f/%.3f ms inside %.3f ms recovery\n"
                                   (* 1000 (- submitted start)) (* 1000 (- completed start))
                                   (* 1000 (- recovered start))))
                    (recovery-test--speech)
                    (princ (format "Retained recovery to completed speech %.3f ms\n"
                                   (* 1000 (- (float-time) start)))))
                (cancel-timer timer)))
            (when (eq working tts-speaker-process) (error "Recovery did not replace foreground"))))
        (when (getenv "OMNIVOX_TEST_LOSE_RETIREMENT_REPLY")
          (let ((working tts-speaker-process)
                (handler (symbol-function 'omnivox-library--handle-line))
                (damage (getenv "OMNIVOX_TEST_DAMAGE_RETIREMENT_RECEIPT"))
                (recovery-start (float-time))
                dropped failed)
            (cl-letf (((symbol-function 'omnivox-library--handle-line)
                       (lambda (process line)
                         (if (and (not dropped) (eq process working)
                                  (string-prefix-p omnivox-library--prefix line)
                                  (equal "retired"
                                         (plist-get
                                          (json-parse-string
                                           (substring line (length omnivox-library--prefix))
                                           :object-type 'plist) :type)))
                             (progn
                               (when damage
                                 (let* ((worker (plist-get (process-get working 'omnivox-library-owner) :worker))
                                        (receipt (expand-file-name
                                                  (concat "voices/sessions/" worker ".retired")
                                                  (getenv "OMNIVOX_TEST_CONFIG_DIR"))))
                                   (copy-file receipt
                                              (expand-file-name "original-retirement-receipt.json"
                                                                (getenv "OMNIVOX_TEST_CONFIG_DIR")))
                                   (with-temp-file receipt (insert "{"))))
                               (setq dropped t))
                           (funcall handler process line)))))
              (condition-case nil (tts-recover) (error (setq failed t))))
            (unless dropped (error "Native retirement reply was not intercepted"))
            (if damage
                (progn
                  (unless (and failed (eq working tts-speaker-process)
                               (not (process-get working 'omnivox-library-retired)))
                    (error "Damaged retirement evidence did not block replacement"))
                  (setq failed nil)
                  (condition-case nil (tts-recover) (error (setq failed t)))
                  (unless (and failed (eq working tts-speaker-process))
                    (error "Retry invented missing retirement evidence"))
                  (let ((receipt (expand-file-name
                                  (concat "voices/sessions/"
                                          (plist-get (process-get working 'omnivox-library-owner) :worker)
                                          ".retired")
                                  (getenv "OMNIVOX_TEST_CONFIG_DIR"))))
                    (unless (equal (with-temp-buffer (insert-file-contents receipt) (buffer-string)) "{")
                      (error "Damaged receipt was rewritten")))
                  (princ "PASS: damaged native receipt blocks replacement and stays damaged\n"))
              (unless (and (not failed) (not (eq working tts-speaker-process))
                           (process-get working 'omnivox-library-retired)
                           (process-live-p tts-speaker-process))
                (error "Lost reply was not reconciled through exact native evidence"))
              (recovery-test--speech)
              (princ (format "Lost reply recovery to completed speech %.3f ms\n"
                             (* 1000 (- (float-time) recovery-start))))
              (princ "PASS: lost retirement reply reconciled from existing native receipt\n"))
            (tts-notify-apply #'recovery-test--speech nil)))
        (unless (and (eq notify tts-notify-process) (process-live-p notify)
                     (equal activation (process-get tts-speaker-process 'omnivox-engine-activation)))
          (error "Recovery changed peer or retained native startup"))
        (unless (or (getenv "OMNIVOX_TEST_EXPECT_BUG")
                    (eq notify-registration
                        (process-get notify omnivox--choice-registration-property)))
          (error "Recovery replaced the healthy notification registration"))
        (tts-notify-apply #'recovery-test--speech nil)
        (princ "PASS: retained recovery with malformed saved settings; notification owner unchanged\n")))
  (dolist (process (list tts-speaker-process tts-notify-process))
    (when (and (processp process) (process-live-p process))
      (omnivox-library--retire process))))
