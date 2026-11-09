;;; omnivox-preferences-tests.el --- Independent reload regressions -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Code:
(require 'ert)
(require 'cl-lib)
(require 'omnivox-preferences)
(require 'omnivox-punctuation-profiles-tests)

(defun omnivox-preferences-tests--state (&optional operation)
  "Return a coherent live test state with OPERATION."
  (list :type "host_preferences_status_v1" :incarnation "worker"
        :configuration_file "/speech/config.json" :revision (if operation 1 0)
        :punctuation_sha256 (make-string 64 ?a) :last_operation operation))

(ert-deftest omnivox-preferences-main-applies-while-notifications-are-unavailable ()
  (omnivox-profiles-tests--workers
    (process-put tts-speaker-process 'omnivox--control-capabilities
                 '(:features ("host_preferences_v1")))
    (delete-process tts-notify-process)
    (let (results requests)
      (cl-letf (((symbol-function 'omnivox--send-control-request)
                 (lambda (process request callback &optional _timeout)
                   (push request requests)
                   (pcase (plist-get request :type)
                     ("host_preferences_status_v1"
                      (funcall callback process (omnivox-preferences-tests--state)))
                     ("reload_punctuation_v1"
                      (funcall callback process
                               (list :type "reload_punctuation_v1" :state
                                     (omnivox-preferences-tests--state
                                      '(:sequence 1 :outcome "applied")))))))))
        (omnivox-reload-punctuation (lambda (value) (setq results value)) "/speech/config.json"))
      (should (equal (mapcar (lambda (r) (plist-get r :outcome)) results)
                     '("applied" "unavailable")))
      (should (= 1 (cl-count "reload_punctuation_v1" requests :key (lambda (r) (plist-get r :type)) :test #'equal)))
      (should-not (process-get tts-speaker-process 'omnivox-preference-operation)))))

(ert-deftest omnivox-preferences-does-not-reload-a-different-editor-target ()
  (omnivox-profiles-tests--workers
    (process-put tts-speaker-process 'omnivox--control-capabilities '(:features ("host_preferences_v1")))
    (let (result requests)
      (cl-letf (((symbol-function 'omnivox--send-control-request)
                 (lambda (process request callback &optional _)
                   (push request requests)
                   (funcall callback process (omnivox-preferences-tests--state)))))
        (omnivox-preferences--reload-worker tts-speaker-process "Main" "/other/config.json"
                                            (lambda (value) (setq result value))))
      (should (equal "rejected" (plist-get result :outcome)))
      (should (= 1 (length requests))))))

(ert-deftest omnivox-preferences-lost-reply-observes-completion-without-replaying ()
  (omnivox-profiles-tests--workers
    (process-put tts-speaker-process 'omnivox--control-capabilities '(:features ("host_preferences_v1")))
    (let (result applied requests)
      (cl-letf (((symbol-function 'omnivox--send-control-request)
                 (lambda (process request callback &optional _)
                   (push request requests)
                   (pcase (plist-get request :type)
                     ("host_preferences_status_v1"
                      (funcall callback process (omnivox-preferences-tests--state
                                                 (when applied '(:sequence 1 :outcome "applied")))))
                     ("reload_punctuation_v1"
                      (setq applied t)
                      (funcall callback process '(:type "error" :code "timeout")))))))
        (omnivox-preferences--reload-worker tts-speaker-process "Main" nil (lambda (r) (setq result r)))
        (let ((deadline (+ (float-time) 1)))
          (while (and (not result) (< (float-time) deadline)) (sleep-for 0.01))))
      (should (equal "applied" (plist-get result :outcome)))
      (should (= 1 (cl-count "reload_punctuation_v1" requests :key (lambda (r) (plist-get r :type)) :test #'equal))))))

(ert-deftest omnivox-preferences-stale-worker-is-not-replayed ()
  (omnivox-profiles-tests--workers
    (process-put tts-speaker-process 'omnivox--control-capabilities '(:features ("host_preferences_v1")))
    (let (result)
      (cl-letf (((symbol-function 'omnivox--send-control-request)
                 (lambda (process request callback &optional _)
                   (let ((state (omnivox-preferences-tests--state)))
                     (when (equal (plist-get request :type) "reload_punctuation_v1")
                       (setq state (plist-put state :incarnation "replacement")))
                     (funcall callback process state)))))
        (omnivox-preferences--reload-worker tts-speaker-process "Main" nil (lambda (r) (setq result r))))
      (should (equal "stale" (plist-get result :outcome))))))

(ert-deftest omnivox-preferences-independent-profiles-ignore-secondary-divergence ()
  (omnivox-profiles-tests--workers
    (process-put tts-speaker-process 'omnivox--control-capabilities '(:features ("host_preferences_v1")))
    (process-put tts-notify-process 'omnivox-punctuation-profiles nil)
    (should (omnivox-punctuation-profiles--command '(profile "prose" some) tts-speaker-process))
    (should-not (omnivox-punctuation-profiles--command '(profile "prose" some) tts-notify-process))
    (delete-process tts-notify-process)
    (should (omnivox-punctuation-profiles--command '(profile "prose" some) tts-speaker-process))))

(ert-deftest omnivox-preferences-updated-profile-base-preserves-selected-id ()
  (omnivox-profiles-tests--workers
    (process-put tts-speaker-process 'omnivox--control-capabilities '(:features ("host_preferences_v1")))
    (process-put tts-speaker-process 'omnivox-punctuation-profiles
                 (list (list :id "prose" :fallback "all" :sha256 (make-string 64 ?b))))
    (should (omnivox-punctuation-profiles--command '(profile "prose" some) tts-speaker-process))
    (process-put tts-speaker-process 'omnivox-punctuation-profiles nil)
    (should-not (omnivox-punctuation-profiles--command '(profile "prose" some) tts-speaker-process))))

(provide 'omnivox-preferences-tests)
;;; omnivox-preferences-tests.el ends here
