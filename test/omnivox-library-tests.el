;;; omnivox-library-tests.el --- Local library transport regressions -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

(require 'ert)
(require 'cl-lib)
(require 'omnivox-library)
(require 'omnivox-voices)

(ert-deftest omnivox-library-confirmation-completes-and-cancels ()
  "Real minibuffer input completes both choices and keeps refusal explicit."
  (dolist (case '(("y TAB RET" . t) ("n TAB RET" . nil)
                  ("YES RET" . t) ("RET" . nil) ("C-g" . cancelled)))
    (let* ((global-map (copy-keymap global-map))
           (completing-read-function #'completing-read-default)
           (completion-styles '(basic))
           (minibuffer-exit-hook nil)
           (outcome 'unanswered) candidates
           (minibuffer-setup-hook
            (list (lambda ()
                    (setq candidates (all-completions "" minibuffer-completion-table))))))
      (cl-letf (((symbol-function 'omnivox-library-tests--confirm-command)
                 (lambda () (interactive)
                   (condition-case nil
                       (setq outcome (omnivox-library--confirm "Install this voice? "))
                     (quit (setq outcome 'cancelled)))))
                ((symbol-function 'tts-speak) #'ignore)
                ((symbol-function 'tts-notify) #'ignore)
                ((symbol-function 'tts-stop) #'ignore)
                ((symbol-function 'emacsvox-icon) #'ignore))
        (define-key global-map (kbd "C-c t") #'omnivox-library-tests--confirm-command)
        (save-window-excursion
          (execute-kbd-macro (vconcat (kbd "C-c t") (kbd (car case))))))
      (should (equal candidates '("no" "yes")))
      (should (eq outcome (cdr case))))))

(ert-deftest omnivox-library-async-inspection-probes-capabilities-without-waiting ()
  (let ((program (make-temp-file "omnivox-library-probe-"))
        (omnivox-library--support-cache nil)
        reply failure cancel)
    (unwind-protect
        (progn
          (with-temp-file program
            (insert "#!/bin/sh\nprintf '%s\\n' --voice-library-owner\n"))
          (set-file-modes program #o700)
          (cl-letf (((symbol-function 'omnivox-library--source-key)
                     (lambda () (list program nil)))
                    ((symbol-function 'omnivox-engine-settings--supported-p) (lambda () t))
                    ((symbol-function 'omnivox-library--service)
                     (lambda () (make-pipe-process :name "probed library fixture" :noquery t)))
                    ((symbol-function 'process-send-string)
                     (lambda (worker line)
                       (let ((id (plist-get (json-parse-string line :object-type 'plist) :request_id)))
                         (omnivox-library--handle-line
                          worker (format "OMNIVOX-LOCAL {\"request_id\":%d,\"type\":\"library\"}" id))))))
            (cl-letf (((symbol-function 'accept-process-output)
                       (lambda (&rest _) (ert-fail "Opening must not wait for a process"))))
              (setq cancel (omnivox-library--inspect-async
                            (lambda (result error-text) (setq reply result failure error-text)))))
            (let ((deadline (+ (float-time) 3)))
              (while (and (not reply) (not failure) (< (float-time) deadline))
                (accept-process-output nil 0.01)))
            (should (equal "library" (plist-get reply :type)))
            (should-not failure)
            (should (cdr (assoc (list program (getenv "OMNIVOX_PROGRAM") nil)
                               omnivox-library--support-cache)))))
      (when cancel (funcall cancel))
      (delete-file program))))

(ert-deftest omnivox-library-async-inspection-correlates-and-cleans-up ()
  (let* ((process (make-pipe-process :name "async library fixture" :noquery t))
         (omnivox-library--support-cache '((("fixture" nil nil) . t)))
         reply failure (calls 0))
    (unwind-protect
        (cl-letf (((symbol-function 'omnivox-library--source-key) (lambda () '("fixture" nil)))
                  ((symbol-function 'getenv) (lambda (_) nil))
                  ((symbol-function 'omnivox-engine-settings--supported-p) (lambda () t))
                  ((symbol-function 'omnivox-library--service) (lambda () process))
                  ((symbol-function 'process-send-string)
                   (lambda (worker line)
                     (let ((id (plist-get (json-parse-string line :object-type 'plist) :request_id)))
                       (omnivox-library--handle-line
                        worker (format "OMNIVOX-LOCAL {\"request_id\":%d,\"type\":\"library\",\"index\":{},\"sha256\":\"test\"}" id))))))
          (let ((cancel (omnivox-library--inspect-async
                         (lambda (result error-text)
                           (cl-incf calls) (setq reply result failure error-text)))))
            (should (equal "test" (plist-get reply :sha256)))
            (should-not failure)
            (should-not (process-live-p process))
            (should-not (process-get process 'omnivox-library-pending))
            (funcall cancel)
            (should (= calls 1))))
      (when (process-live-p process) (delete-process process)))))

(ert-deftest omnivox-library-async-inspection-cancel-and-timeout ()
  (dolist (outcome '(cancel timeout retarget malformed))
    (let* ((process (make-pipe-process :name "pending library fixture" :noquery t))
           (omnivox-library--support-cache '((("fixture" nil nil) . t)))
           (source '("fixture" nil)) expire failure callback-called request-id)
      (unwind-protect
          (cl-letf (((symbol-function 'omnivox-library--source-key) (lambda () source))
                    ((symbol-function 'getenv) (lambda (_) nil))
                    ((symbol-function 'omnivox-engine-settings--supported-p) (lambda () t))
                    ((symbol-function 'omnivox-library--service) (lambda () process))
                    ((symbol-function 'run-at-time)
                     (lambda (_time _repeat callback) (setq expire callback) nil))
                    ((symbol-function 'process-send-string)
                     (lambda (_worker line)
                       (setq request-id (plist-get (json-parse-string line :object-type 'plist) :request_id)))))
            (let ((cancel (omnivox-library--inspect-async
                           (lambda (_reply error-text) (setq callback-called t failure error-text)))))
              (should-not callback-called)
              (pcase outcome
                ('cancel (funcall cancel) (should-not callback-called))
                ('timeout (funcall expire) (should (string-search "timed out" failure)))
                ('retarget
                 (setq source '("different" nil))
                 (omnivox-library--handle-line
                  process (format "OMNIVOX-LOCAL {\"request_id\":%d,\"type\":\"library\"}" request-id))
                 (should (string-search "target changed" failure)))
                ('malformed
                 (funcall (process-filter process) process "OMNIVOX-LOCAL invalid\n")
                 (should failure)))
              (should-not (process-live-p process))
              (should-not (process-get process 'omnivox-library-pending))))
        (when (process-live-p process) (delete-process process))))))

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

(ert-deftest omnivox-library-apply-manages-mbrola-after-first-installation ()
  (should (equal '("piper" "flite") (omnivox-library--managed-providers "both" '(:voices []))))
  (should (equal '("piper" "flite" "mbrola")
                 (omnivox-library--managed-providers
                  "both" '(:voices [(:engine_id "mbrola" :enabled :false)]))))
  (should (equal '("mbrola") (omnivox-library--managed-providers "mbrola" nil))))

(provide 'omnivox-library-tests)
;;; omnivox-library-tests.el ends here
