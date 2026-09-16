;;; omnivox-library-tests.el --- Local library transport regressions -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

(require 'ert)
(require 'cl-lib)
(require 'omnivox-library)
(require 'omnivox-voices)

(ert-deftest omnivox-library-empty-state-explains-actions-and-clears-on-install ()
  "An empty library is readable, and adding a voice replaces its explanation."
  (with-temp-buffer
    (omnivox-library-mode)
    (let (voices spoken)
      (cl-letf (((symbol-function 'omnivox-library--service)
                 (lambda () (make-pipe-process :name "empty library fixture" :noquery t)))
                ((symbol-function 'omnivox-library--request)
                 (lambda (&rest _) (list :index (list :voices voices) :sha256 "fixture")))
                ((symbol-function 'emacsvox-aural-ui-speak)
                 (lambda (text) (setq spoken text))))
        (omnivox-library-refresh)
        (should (string-search "Press b to add the bundled Flite SLT voice" (buffer-string)))
        (should-not (tabulated-list-get-id))
        (should-error (omnivox-library-toggle) :type 'user-error)
        (omnivox-library--speak-row)
        (should (string-search "No voices added" spoken))
        (setq voices '((:engine_id "flite" :physical_id "cmu_us_slt"
                                  :display_name "SLT" :enabled t)))
        (omnivox-library-refresh)
        (should-not (string-search "No voices have been added" (buffer-string)))
        (goto-char (point-min))
        (should (equal (tabulated-list-get-id) '("flite" . "cmu_us_slt")))
        (omnivox-library--speak-row)
        (should (equal spoken "flite. SLT. Enabled"))))))

(ert-deftest omnivox-library-retains-an-attempt-that-exits-before-initialization ()
  (require 'tts-speak)
  (let* ((process (make-pipe-process :name "library exited startup" :noquery t))
         (tts-program "fixture") retained
         (omnivox-library--birth-collector (lambda (attempt) (setq retained attempt))))
    (delete-process process)
    (cl-letf (((symbol-function 'omnivox-remote-enabled-p) (lambda () nil))
              ((symbol-function 'tts--resolve-program) (lambda (_) "fixture"))
              ((symbol-function 'tts-queue--create) (lambda (&rest _) process)))
      (should-error (tts-make-process "Notify"))
      (should (eq retained process)))))

(ert-deftest omnivox-library-rollback-policy-preserves-wire-arrays ()
  ;; Discovery decodes arrays as lists. Reusing that record directly broke
  ;; json-serialize during rollback, after the working pair had exited.
  (cl-letf (((symbol-function 'omnivox--process-routing-registration)
             (lambda (_) '(:policy (:preferred_engine_ids ("espeak")
                                    :fallback_engine_ids nil :disabled_engine_ids ("piper"))))))
    (let* ((policy (omnivox-library--policy-snapshot nil))
           (decoded (json-parse-string (json-serialize policy) :object-type 'plist :array-type 'array)))
      (should (equal (plist-get decoded :preferred_engine_ids) ["espeak"]))
      (should (equal (plist-get decoded :fallback_engine_ids) []))
      (should (equal (plist-get decoded :disabled_engine_ids) ["piper"])))))

(ert-deftest omnivox-library-reply-may-arrive-before-send-returns ()
  (let ((process (make-pipe-process :name "library synchronous receipt" :noquery t)))
    (unwind-protect
        (cl-letf (((symbol-function 'process-send-string)
                   (lambda (source line)
                     (let ((id (plist-get (json-parse-string line :object-type 'plist) :request_id)))
                       (omnivox-library--handle-line source
                         (format "OMNIVOX-LOCAL {\"request_id\":%d,\"type\":\"state\",\"state\":\"pending\"}" id))))))
          (should (equal (plist-get (omnivox-library--request process '(:command "inspect")) :state) "pending"))
          (should (zerop (hash-table-count (process-get process 'omnivox-library-pending)))))
      (delete-process process))))

(ert-deftest omnivox-library-retirement-is-bound-to-native-owner ()
  (let ((process (make-pipe-process :name "library owner correlation" :noquery t)))
    (unwind-protect
        (progn
          (process-put process 'omnivox-library-owner '(:worker "actual-owner"))
          (omnivox-library--handle-line process "OMNIVOX-LOCAL {\"request_id\":0,\"type\":\"retired\",\"worker\":\"old-owner\"}")
          (should-not (process-get process 'omnivox-library-retired))
          (omnivox-library--handle-line process "OMNIVOX-LOCAL {\"request_id\":0,\"type\":\"retired\",\"worker\":\"actual-owner\"}")
          (should (process-get process 'omnivox-library-retired)))
      (delete-process process))))

(ert-deftest omnivox-library-eligibility-preserves-unmanaged-and-engine-exclusions ()
  (let ((index '(:voices [(:engine_id "piper" :physical_id "new" :enabled t)
                          (:engine_id "flite" :physical_id "disabled" :enabled :false)]
                        :disabled_physical_ids [(:engine_id "espeak" :voice_id "excluded")]))
        (previous '((:engine_id "espeak" :voice_id "en")
                    (:engine_id "espeak" :voice_id "excluded")
                    (:engine_id "piper" :voice_id "old"))))
    (should (equal (omnivox-library--eligible index previous '("piper" "flite") '(:disabled_engine_ids []))
                   [(:engine_id "espeak" :voice_id "en") (:engine_id "piper" :voice_id "new")]))
    (should (equal (omnivox-library--eligible index previous '("piper" "flite") '(:disabled_engine_ids ["piper"]))
                   [(:engine_id "espeak" :voice_id "en")]))))

(ert-deftest omnivox-library-review-exposes-installed-but-disabled-provider ()
  "A successful Apply must not imply that a disabled downloaded voice is active."
  (let ((index '(:voices [(:engine_id "flite" :display_name "AWB" :enabled t)
                          (:engine_id "flite" :display_name "RMS" :enabled t)
                          (:engine_id "piper" :display_name "Kristin" :enabled :false)])))
    (should (equal "2 Flite voices enabled; No Piper voices enabled"
                   (omnivox-library--enabled-summary index '("flite" "piper"))))
    (setf (plist-get (aref (plist-get index :voices) 2) :enabled) t)
    (should (equal "2 Flite voices enabled; 1 Piper voice enabled"
                   (omnivox-library--enabled-summary index '("flite" "piper"))))))

(provide 'omnivox-library-tests)
;;; omnivox-library-tests.el ends here
