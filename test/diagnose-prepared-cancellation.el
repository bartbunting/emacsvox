;;; diagnose-prepared-cancellation.el --- Prepared Stop ordering -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;;; Commentary:
;; Run in a fresh batch Emacs. All writes are substituted; no engine is started.
;; This characterizes ordering without asserting that a defect must persist.
;; See docs/voice-editor-client-handoff-review.org for the XHI design and results.

;;; Code:
(unless noninteractive (error "Run this diagnostic in a fresh batch Emacs"))
(setq load-prefer-newer t)
;; Primitive substitution below must not start a native-compilation subprocess
;; through the pipe fixture's substituted process writer.
(setq native-comp-enable-subr-trampolines nil)
(let ((root (expand-file-name "../" (file-name-directory load-file-name))))
  (add-to-list 'load-path (expand-file-name "lisp/" root))
  (add-to-list 'load-path (expand-file-name "test/" root))
  (dolist (file '("emacsvox-preamble.el" "tts-speak.el" "omnivox-choice-codec.el"
                  "emacsvox-aural-transport.el" "omnivox-voices.el"))
    (load (expand-file-name file (expand-file-name "lisp/" root)) nil t)))
(require 'omnivox-choice-playback-tests)

(dolist (version '(3 4))
  (dolist (second-stop '(nil t))
    (omnivox-choice-playback-test--with-runtime
     (process-put speaker emacsvox-aural--structured-timeline-process-property version)
     (let ((emacsvox-aural-submission-controls-interruption t)
           (emacsvox-aural-submission-delivery-policy 'urgent)
           injected commands result)
       (cl-letf (((symbol-function 'process-send-string)
                  (lambda (_owner command)
                    (push command commands)
                    (when (and second-stop (equal command "s\n") (not injected))
                      (setq injected t)
                      (tts-stop t)))))
         (setq result (omnivox-choice-playback-test--submit)))
       (princ (format "version=%d second-stop=%S returned-id=%S timeline-written=%S observing=%S\n"
                      version injected result
                      (cl-some (lambda (command) (string-prefix-p "emacsvox_timeline " command)) commands)
                      (and result (tts--dispatch-observing-p (tts--dispatch-owner-for speaker result)))))))))

;; Stop before owner allocation and after framing are separate admission edges.
(dolist (version '(3 4))
  (dolist (stage '(projection framing))
    (omnivox-choice-playback-test--with-runtime
     (process-put speaker emacsvox-aural--structured-timeline-process-property version)
     (let* ((target (if (eq stage 'projection)
                        'emacsvox-aural--build-structured-timeline
                      'emacsvox-aural--frame-structured-timeline))
            (original (symbol-function target))
            injected commands result)
       (cl-letf (((symbol-function 'process-send-string)
                  (lambda (_process command) (push command commands)))
                 ((symbol-function target)
                  (lambda (&rest arguments)
                    (unless injected (setq injected t) (tts-stop t))
                    (apply original arguments))))
         (setq result (omnivox-choice-playback-test--submit)))
       (princ (format "version=%d stop-at=%S returned-id=%S timeline-written=%S\n"
                      version stage result
                      (cl-some (lambda (command) (string-prefix-p "emacsvox_timeline " command)) commands)))))))

;; A nested public Stop or newer urgent request must not inherit preservation
;; from the parent policy stop. An ordered hook announcement remains independent.
(dolist (action '(stop ordered urgent))
  (omnivox-choice-playback-test--with-runtime
   (let* ((emacsvox-aural-submission-controls-interruption t)
          (emacsvox-aural-submission-delivery-policy 'urgent)
          entered nested result commands
          (tts-stopped-hook
           (list (lambda (_process)
                   (unless entered
                     (setq entered t)
                     (if (eq action 'stop) (tts-stop t)
                       (let ((emacsvox-aural-submission-controls-interruption (eq action 'urgent))
                             (emacsvox-aural-submission-delivery-policy action))
                         (setq nested (omnivox-choice-playback-test--submit)))))))))
     (cl-letf (((symbol-function 'process-send-string)
                (lambda (_process command) (push command commands))))
       (setq result (omnivox-choice-playback-test--submit)))
     (princ (format "hook=%S parent-id=%S nested-id=%S timeline-writes=%d\n"
                    action result nested
                    (cl-count-if (lambda (command) (string-prefix-p "emacsvox_timeline " command)) commands))))))

;; Legacy tracked and marked calls must have the same preparation lifetime.
(dolist (kind '(tracked marked))
  (dolist (captured '(nil t))
    (omnivox-choice-playback-test--with-runtime
     (let ((original (symbol-function 'tts--dispatch-command)) result commands)
       (cl-letf (((symbol-function 'process-send-string)
                  (lambda (_process command) (push command commands)))
                 ((symbol-function 'tts--dispatch-command)
                  (lambda (owner command)
                    (tts-stop t)
                    (funcall original owner command))))
         (cl-labels ((submit ()
                       (if (eq kind 'tracked)
                           (tts--protocol-dispatch-tracked #'ignore)
                         (tts--protocol-dispatch-marked #'ignore #'ignore))))
           (setq result (if captured
                            (emacsvox-aural-call-with-delivery-transaction speaker #'submit)
                          (submit)))))
       (princ (format "legacy=%S captured=%S returned-id=%S dispatch-written=%S\n"
                      kind captured result
                      (and (cl-some (lambda (command) (string-match-p "emacsvox_\\(?:tracked\\|marker\\)_dispatch" command)) commands) t)))))))

(omnivox-choice-playback-test--with-runtime
 (let ((original (symbol-function 'omnivox--choice-dispatch-admission))
       result commands)
   (cl-letf (((symbol-function 'process-send-string)
              (lambda (_process command) (push command commands)))
             ((symbol-function 'omnivox--choice-dispatch-admission)
              (lambda (owner)
                (funcall original owner)
                (tts-stop t))))
     (setq result (omnivox-choice-playback-test--submit)))
   (princ (format "stop-at=admission returned-id=%S timeline-written=%S\n"
                  result
                  (cl-some (lambda (command) (string-prefix-p "emacsvox_timeline " command)) commands)))))

(omnivox-choice-playback-test--with-runtime
 (let ((original (symbol-function 'tts--dispatch-command)) result commands)
   (cl-letf (((symbol-function 'process-send-string)
              (lambda (_process command) (push command commands)))
             ((symbol-function 'tts--dispatch-command)
              (lambda (owner command)
                (tts-cancel-tracked-dispatch (tts--dispatch-owner-id owner))
                (funcall original owner command))))
     (setq result (tts--protocol-dispatch-tracked #'ignore)))
   (princ (format "forget-prepared returned-id=%S dispatch-written=%S\n"
                  result (and commands t)))))

;; Set the real pending-quit flag after a bookkeeping write. This respects
;; inhibit-quit, unlike unconditionally signalling a synthetic quit condition.
(dolist (stage '(owner-count snapshot-reference metadata-charge))
  (omnivox-choice-playback-test--with-runtime
   (let ((original-put (symbol-function 'process-put))
         (original-hash (symbol-function 'puthash))
         injected quit-seen commands)
     (cl-letf (((symbol-function 'process-send-string)
                (lambda (_process command) (push command commands)))
               ((symbol-function 'process-put)
                (lambda (process property value)
                  (prog1 (funcall original-put process property value)
                    (when (and (not injected) (eq process speaker)
                               (or (and (eq stage 'owner-count)
                                        (eq property 'tts--dispatch-owner-count) (eql value 1))
                                   (and (eq stage 'metadata-charge)
                                        (eq property 'tts--dispatch-metadata-bytes) (> value 100))))
                      (setq injected t quit-flag t)))))
               ((symbol-function 'puthash)
                (lambda (key value table)
                  (prog1 (funcall original-hash key value table)
                    (when (and (not injected) (eq stage 'snapshot-reference)
                               (eq table (process-get speaker 'omnivox--choice-snapshot-references)))
                      (setq injected t quit-flag t))))))
       (condition-case nil
           (omnivox-choice-playback-test--submit)
         (quit (setq quit-seen t))))
     (princ (format "quit-at=%S caught=%S owner-count=%S metadata-bytes=%S snapshot-count=%d writes=%d\n"
                    stage quit-seen
                    (or (process-get speaker 'tts--dispatch-owner-count) 0)
                    (or (process-get speaker 'tts--dispatch-metadata-bytes) 0)
                    (if-let* ((table (process-get speaker 'omnivox--choice-snapshot-references)))
                        (hash-table-count table) 0)
                    (length commands))))))

;;; diagnose-prepared-cancellation.el ends here
