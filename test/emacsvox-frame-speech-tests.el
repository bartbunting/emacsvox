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
