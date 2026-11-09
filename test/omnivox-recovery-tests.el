;;; omnivox-recovery-tests.el --- Owned speech recovery regressions -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Code:
(require 'ert)
(require 'cl-lib)
(require 'tts-speak)
(require 'omnivox-library-runtime)

(defmacro omnivox-recovery-tests--workers (&rest body)
  (declare (indent 0))
  `(let ((main (make-pipe-process :name "recovery main" :noquery t))
         (notify (make-pipe-process :name "recovery notify" :noquery t))
         (replacement (make-pipe-process :name "recovery replacement" :noquery t)))
     (unwind-protect
         (let ((tts-speaker-process main) (tts-notify-process notify) (tts-quiet nil)) ,@body)
       (dolist (p (list main notify replacement)) (when (process-live-p p) (delete-process p))))))

(ert-deftest omnivox-recovery-retired-native-owner-does-not-mask-worker-failure ()
  (omnivox-recovery-tests--workers
    (should (tts--speech-process-usable-p main))
    (process-put main 'omnivox-library-retired t)
    (process-put notify 'omnivox-library-retired t)
    (should (process-live-p main))
    (should-not (tts--speech-process-usable-p main))
    (should (eq (tts-notify-process) main))
    (let (letters recovered)
      (cl-letf (((symbol-function 'tts--recover-speaker)
                 (lambda () (setq recovered t tts-speaker-process replacement)))
                ((symbol-function 'tts--protocol-sync-capitalization-presentation) #'ignore)
                ((symbol-function 'tts--protocol-set-character-scale) #'ignore)
                ((symbol-function 'tts--protocol-letter)
                 (lambda (letter) (push (cons tts-speaker-process letter) letters))))
        (tts-letter "A"))
      (should recovered)
      (should (equal letters (list (cons replacement "A")))))))

(ert-deftest omnivox-recovery-explicit-repair-requires-native-retirement ()
  (omnivox-recovery-tests--workers
    (let (events)
      (cl-letf (((symbol-function 'process-command) (lambda (_) '("omnivox" "--voice-library-owner")))
                ((symbol-function 'omnivox-library--retire)
                 (lambda (p) (should (eq p main))
                   (should (= omnivox-library--timeout 6)) (push 'retired events)
                   (process-put p 'omnivox-library-retired t) (delete-process p)))
                ((symbol-function 'tts--recover-speaker)
                 (lambda () (should-not (process-live-p main))
                   (push 'recovered events) (setq tts-speaker-process replacement)))
                ((symbol-function 'tts--protocol-sync) (lambda () (push 'synchronized events))))
        (tts-recover))
      (should (equal (reverse events) '(retired recovered synchronized)))
      (should (eq tts-notify-process notify))
      (should (process-live-p notify)))))

(ert-deftest omnivox-recovery-unconfirmed-cleanup-never-starts-replacement ()
  (omnivox-recovery-tests--workers
    (cl-letf (((symbol-function 'process-command) (lambda (_) '("omnivox" "--voice-library-owner")))
              ((symbol-function 'omnivox-library--retire) (lambda (_) (error "cleanup unconfirmed")))
              ((symbol-function 'tts--recover-speaker) (lambda () (ert-fail "Unsafe replacement"))))
      (should-error (tts-recover))
      (should (process-live-p main))
      (delete-process main)
      (should-error (tts-recover) :type 'user-error))))

(ert-deftest omnivox-recovery-startup-registration-does-not-reconfigure-its-peer ()
  (omnivox-recovery-tests--workers
    (process-put notify omnivox--control-capabilities-property
                 '(:features ("logical_voice_registration")))
    (let (targets)
      (cl-letf (((symbol-function 'omnivox--register-logical-voices)
                 (lambda (processes) (setq targets processes)))
                ((symbol-function 'omnivox-register-logical-voices)
                 (lambda () (ert-fail "Startup reconfigured the healthy peer")))
                ((symbol-function 'run-hooks) #'ignore))
        (omnivox--handle-inventory-response notify '(:type "inventory" :engines [])))
      (should (equal targets (list notify))))))

(ert-deftest omnivox-recovery-readiness-waits-only-for-own-speech-initialization ()
  (omnivox-recovery-tests--workers
    (process-put main omnivox--control-capabilities-property '(:features ()))
    (let ((own (omnivox--pending-requests main)) (peer (omnivox--pending-requests notify)))
      (puthash 1 (omnivox--make-control-request :type "register_logical_voices_v3") own)
      (puthash 2 (omnivox--make-control-request :type "get_engine_parameters_v1") own)
      (puthash 3 (omnivox--make-control-request :type "register_logical_voices_v3") peer)
      (cl-letf (((symbol-function 'omnivox-library--wait)
                 (lambda (predicate process _description seconds)
                   (should (eq process main)) (should (= seconds 2))
                   (should-not (funcall predicate))
                   (remhash 1 own)
                   (should (funcall predicate)))))
        (omnivox-library--wait-for-recovered-speech main)))))

(ert-deftest omnivox-recovery-notification-fallback-retains-the-real-foreground-owner ()
  (omnivox-recovery-tests--workers
    (process-put notify 'omnivox-library-retired t)
    (tts-notify-apply (lambda (_) (setq tts-speaker-process replacement)) "notice")
    (should (eq tts-speaker-process replacement))))

(ert-deftest omnivox-recovery-notification-race-does-not-create-an-unreachable-owner ()
  (omnivox-recovery-tests--workers
    (let (selected)
      (cl-letf (((symbol-function 'tts-make-process)
                 (lambda (&rest _) (ert-fail "Notification created an unretained owner"))))
        (tts-notify-apply
         (lambda (_)
           (process-put notify 'omnivox-library-retired t)
           (tts--recover-speaker)
           (setq selected tts-speaker-process)) "notice"))
      (should (eq selected main))
      (should (eq tts-speaker-process main)))))

(ert-deftest omnivox-recovery-automatic-path-cannot-bypass-missing-native-cleanup ()
  (omnivox-recovery-tests--workers
    (delete-process main)
    (cl-letf (((symbol-function 'process-command)
               (lambda (_) '("omnivox" "--voice-library-owner")))
              ((symbol-function 'omnivox-remote-enabled-p) (lambda () nil))
              ((symbol-function 'tts-make-process)
               (lambda (&rest _) (ert-fail "Unconfirmed native owner was replaced"))))
      (should-error (tts--recover-speaker) :type 'user-error))))

(ert-deftest omnivox-recovery-sentinel-retains-unconfirmed-native-owner ()
  (omnivox-recovery-tests--workers
    (delete-process main)
    (cl-letf (((symbol-function 'process-command)
               (lambda (_) '("omnivox" "--voice-library-owner")))
              ((symbol-function 'tts--speech-process-terminal-p) (lambda (_) t))
              ((symbol-function 'omnivox-library--prepare-engines)
               (lambda () (ert-fail "Fresh restart bypassed missing cleanup"))))
      (tts--speech-process-sentinel main "finished")
      (should (eq tts-speaker-process main))
      (should-error (tts-recover) :type 'user-error)
      (should-error (tts-initialize) :type 'user-error)
      (should (eq (tts-notify-process) notify)))))

(provide 'omnivox-recovery-tests)
;;; omnivox-recovery-tests.el ends here
