;;; emacsvox-frame-speech-tests.el --- Frame-owned speech tests -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

(require 'ert)
(require 'cl-lib)
(require 'tts-speak)
(require 'emacsvox-frame-speech)

(ert-deftest emacsvox-frame-speech-replacement-expires-captured-work ()
  (let* ((main (make-pipe-process :name "Frame speech A" :noquery t))
         (other (make-pipe-process :name "Frame speech B" :noquery t))
         (frame (selected-frame)) (tts-speaker-process main))
    (unwind-protect
        (let ((first (emacsvox-frame-speech-attach frame main))
              (fresh (emacsvox-frame-speech-attach frame other)))
          (should-not (emacsvox-frame-speech-call first #'error "Expired speech callback ran"))
          (should (eq 'edited (emacsvox-frame-speech--with-origin
                               first (lambda ()
                                       (should-not tts-speaker-process)
                                       (should tts-quiet)
                                       'edited))))
          (should (eq other (emacsvox-frame-speech-call fresh (lambda () tts-speaker-process))))
          (should (eq main (emacsvox-frame-speech-call
                            fresh (lambda () (emacsvox-frame-speech-call nil (lambda () tts-speaker-process))))))
          (emacsvox-frame-speech-detach frame)
          (should-not (emacsvox-frame-speech-call fresh #'error "Detached callback ran"))
          (should (and (process-live-p main) (process-live-p other)))
          (should-not (advice-member-p #'emacsvox-frame-speech--route 'tts-dispatch)))
      (emacsvox-frame-speech-detach frame)
      (delete-process main)
      (delete-process other))))

(ert-deftest emacsvox-frame-speech-auditions-use-the-workers-voice-adapter ()
  (require 'omnivox-voices)
  (let* ((main (make-pipe-process :name "Frame audition" :noquery t))
         (frame (selected-frame))
         (endpoint (emacsvox-frame-speech-attach frame main))
         (tts-voice-inventory-function #'tts-default-voice-inventory)
         (tts-voice-preview-function #'tts-default-voice-preview-sequence)
         (adapter (lambda () (list tts-voice-inventory-function tts-voice-preview-function)))
         (desktop (funcall adapter)))
    (unwind-protect
        (progn
          (should (equal desktop (emacsvox-frame-speech-call endpoint adapter)))
          (process-put main omnivox--control-capabilities-property '(:features ("engine_inventory")))
          (emacsvox-frame-speech-call
           endpoint (lambda ()
                      (should (equal (funcall adapter)
                                     '(omnivox-voice-inventory omnivox-preview-voice-sequence)))
                      (should (equal desktop (emacsvox-frame-speech-call nil adapter)))))
          (should (equal desktop (funcall adapter))))
      (emacsvox-frame-speech-detach frame)
      (delete-process main))))

(ert-deftest emacsvox-frame-speech-unicode-follows-both-attached-workers ()
  (require 'omnivox-voices)
  (let* ((main (make-pipe-process :name "Unicode main" :noquery t))
         (notify (make-pipe-process :name "Unicode notify" :noquery t))
         (frame (selected-frame))
         (endpoint (emacsvox-frame-speech-attach frame main notify "omnivox"))
         (feature '(:features ("text_repertoire_routing_v1")))
         (names (lambda () tts-handle-unicode))
         (tts-handle-unicode nil))
    (unwind-protect
        (progn
          (process-put main omnivox--control-capabilities-property feature)
          (should (emacsvox-frame-speech-call endpoint names))
          (process-put notify omnivox--control-capabilities-property '(:features ("control_v1")))
          (should (emacsvox-frame-speech-call endpoint names))
          (setq tts-handle-unicode t)
          (process-put notify omnivox--control-capabilities-property feature)
          (emacsvox-frame-speech-call
           endpoint (lambda ()
                      (should-not (funcall names))
                      (should (emacsvox-frame-speech-call nil names))))
          (delete-process notify)
          (should-not (emacsvox-frame-speech-call endpoint names))
          (should tts-handle-unicode))
      (emacsvox-frame-speech-detach frame)
      (delete-process main)
      (when (process-live-p notify) (delete-process notify)))))

(ert-deftest emacsvox-frame-speech-local-worker-on-a-remote-desktop ()
  (let* ((frame (selected-frame)) (main (make-pipe-process :name "Local frame" :noquery t))
         (tts-program "omnivox") (omnivox-remote-host "127.0.0.1")
         (omnivox-available-voices '("desktop voice"))
         (local (emacsvox-frame-speech-attach frame main nil "omnivox")))
    (unwind-protect
        (progn
          (should (omnivox-remote-enabled-p))
          (emacsvox-frame-speech-call
           local (lambda ()
                   (should-not (omnivox-remote-enabled-p))
                   (should-not omnivox-available-voices)
                   (should (equal "/local/cue.wav" (omnivox-remote-resource "/local/cue.wav")))))
          (should (equal omnivox-available-voices '("desktop voice"))))
      (emacsvox-frame-speech-detach frame)
      (delete-process main))))

(provide 'emacsvox-frame-speech-tests)
;;; emacsvox-frame-speech-tests.el ends here
