;;; verify-omnivox-native-runtime.el --- Real native editor acceptance -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Commentary:
;; Opt-in fresh Emacs check using a fully staged Windows server and installed
;; DECtalk/Eloquence runtimes. Set OMNIVOX_PROGRAM and ESPEAK_NG_DATA for that
;; package, and EMACSVOX_NATIVE_TEST_SERVER to the launcher. Uses null audio,
;; private processes and temporary palette stores; no personal settings change.
;; Inherit the deployment launcher's runtime selection unchanged: substituting
;; a different DLL only for this check does not verify the deployed controls.
;;; Code:
(unless noninteractive (error "Run in a fresh batch Emacs"))
(setq load-prefer-newer t)
(princ (format "Native acceptance selection: server=%s DECtalk=%s Eloquence=%s\n"
               (getenv "OMNIVOX_PROGRAM")
               (or (getenv "OMNIVOX_DECTALK_DLL") "automatic discovery")
               (or (getenv "OMNIVOX_ECI_DLL") "automatic discovery")))
(require 'emacsvox-preamble)
(require 'emacsvox-aural-provider-workflows)
(require 'emacsvox-aural-voice-engine-controls-tests)
(require 'omnivox-native-runtime-tests)
(dolist (fn '(emacsvox-aural-voice-engine-controls-open omnivox--preview-layered-sequence
              omnivox-register-logical-voices emacsvox-aural-voice-editor-refresh))
  (unless (string-suffix-p ".elc" (or (symbol-file fn) ""))
    (error "Compile before native acceptance: %s" fn)))

(defvar native-accept--processes nil)
(add-hook 'kill-emacs-hook
          (lambda ()
            (dolist (process native-accept--processes)
              (when (process-live-p process) (tts--retire-process process)))))

(defun native-accept--wait (predicate)
  (let ((deadline (+ (float-time) 30)))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.02))
    (unless (funcall predicate)
      (error "Native acceptance timed out; query=%S marker=%S"
             omnivox-parameters--last-error omnivox-marker-last-error))))

(defun native-accept--control (process type)
  (let (answer)
    (omnivox--send-control-request process (list :type type)
                                   (lambda (_ response) (setq answer response)))
    (native-accept--wait (lambda () answer)) answer))

(defun native-accept--process (name generation)
  (let ((process (make-process
                  :name name :noquery t :connection-type 'pipe :coding 'utf-8-unix
                  :command (list (or (getenv "EMACSVOX_NATIVE_TEST_SERVER")
                                     (error "Set EMACSVOX_NATIVE_TEST_SERVER"))
                                 "--engine" "eloquence" "--audio-output" "null")
                  :stderr (get-buffer-create " *native-accept-errors*")
                  :filter #'tts--speaker-process-filter)))
    (push process native-accept--processes)
    (process-put process 'tts--speech-process-generation generation)
    (omnivox--install-control-filter process)
    (process-put process omnivox--control-capabilities-property
                 (native-accept--control process "capabilities"))
    (unless (omnivox--native-tuning-supported-p process)
      (delete-process process) (error "Staged worker lacks native bundle"))
    (process-put process omnivox--control-inventory-property
                 (native-accept--control process "inventory"))
    (process-put process tts--tracked-playback-completion-property t)
    (process-put process tts--marker-playback-events-property t)
    process))

(defun native-accept--catalogue (process engine &optional voice)
  (let ((deadline (+ (float-time) 10)) answer)
    ;; Startup recovery can briefly own the engine. Only this opt-in harness
    ;; retries busy; the interactive view keeps its explicit Refresh action.
    (while (progn
             (setq answer nil)
             (omnivox-parameters--request process engine voice (lambda (r) (setq answer r)))
             (native-accept--wait (lambda () answer))
             (and (eq (plist-get answer :status) 'busy) (< (float-time) deadline)))
      (accept-process-output nil 0.1))
    (unless (eq (plist-get answer :status) 'ready) (error "Catalogue: %S" answer))
    answer))

(defun native-accept--applied (process application key expected)
  (let (answer)
    (omnivox-parameters--explain-applied
     process (list (process-name process) (process-get process 'tts--speech-process-generation))
     application (lambda (r) (setq answer r)))
    (native-accept--wait (lambda () answer))
    (unless (eq (plist-get answer :status) 'ready) (error "Explanation: %S" answer))
    (let ((parameter (cl-find key (append (plist-get (plist-get answer :explanation) :parameters) nil)
                              :test #'equal :key (lambda (p) (plist-get p :id)))))
      (unless (and (equal (plist-get parameter :value) expected)
                   (eq (plist-get parameter :read_back) t))
        (error "Native readback mismatch: %S, expected %S" parameter expected)))))

(let* ((tts-program "omnivox")
       (tts-speaker-process (native-accept--process "native-main" 3001))
       (tts-notify-process (native-accept--process "native-notify" 3002))
       (original tts-speaker-process)
       (tts-voice-preview-function #'omnivox-preview-voice-sequence)
       (omnivox--logical-registry-generation 0) (omnivox--logical-registry-signature nil)
       (omnivox-average-pitch-contrast 1.0)
       (omnivox-logical-voice-preferences nil) (omnivox-logical-voice-languages nil)
       (omnivox-engine-priority-ids nil) (omnivox-fallback-engine-ids nil)
       (omnivox-disabled-engine-ids nil) (omnivox-global-default-selector nil)
       (omnivox-last-realized-routes (make-hash-table :test #'equal))
       (omnivox-realized-route-changed-hook nil) (tts-realized-voice-changed-hook nil)
       (omnivox-initial-routing-ready-hook nil) (tts-stopped-hook nil)
       (emacsvox-speak-messages nil) (omnivox-marker-last-error nil)
       (emacsvox-aural-submission-controls-interruption nil)
       (emacsvox-aural-submission-delivery-policy 'ordered)
       (after-change-major-mode-hook nil)
       (voice (plist-get (omnivox-native-test--entry) :voice))
       (owned (list :mode 'owned :name 'bolden :palette 'isolated-acceptance
                    :names '(bolden voice-bolden) :definition (plist-get voice :shared)
                    :choices (plist-get voice :choices) :choice-source 'local :language "en-US")))
  (unwind-protect
      (progn
        (tts-queue--install)
        (dolist (process (list tts-speaker-process tts-notify-process))
          (dolist (engine '("dectalk" "eloquence")) (native-accept--catalogue process engine)))
        ;; Use the actual editor and preview transport with isolated palette files.
        (emacsvox-test--with-voice-editor
         (emacsvox-aural-voice-editor-open 'reading-owned 'bolden)
         (let* ((draft (emacsvox-aural-voice-editor--draft))
                (snapshot (list :definition (append '(:family nil :average-pitch nil :pitch-range nil :stress nil)
                                                    (plist-get voice :shared))
                                :language "en-US" :choices (copy-tree (plist-get voice :choices))
                                :selectors (emacsvox-aural-voice-data--selectors (plist-get voice :choices)))))
           (setf (emacsvox-aural-voice-draft-working draft) (copy-tree snapshot)
                 (emacsvox-aural-voice-draft-baseline draft) (copy-tree snapshot)
                 (emacsvox-aural-voice-draft-original draft) (copy-tree snapshot))
           (emacsvox-aural-voice-editor--put :policy '(:engine-order ("dectalk" "eloquence") :fallback (:engines ("espeak"))))
           (dolist (case '(("paul-main" "sm" 61) ("eci-default" "breathiness" 35)))
             (emacsvox-aural-voice-editor--put :tuning-choice (car case))
             (emacsvox-aural-voice-engine-controls-open)
             (native-accept--wait (lambda () (not (eq (plist-get (plist-get (emacsvox-aural-voice-engine-controls--state) :result) :status) 'checking))))
             (emacsvox-aural-voice-engine-controls--apply (nth 1 case) 'set (nth 2 case))
             (native-accept--wait (lambda () (not (emacsvox-aural-voice-editor--get :preview-operation))))
             (let* ((result (emacsvox-aural-voice-editor--get :preview-result))
                    (sample (car (last (plist-get result :results)))))
               (unless (eq (plist-get result :status) 'completed)
                 (error "Automatic sample failed: %S" result))
               (native-accept--applied tts-speaker-process (plist-get sample :last-started)
                                       (nth 1 case) (nth 2 case)))
             (emacsvox-aural-voice-editor-compare)
             (native-accept--wait (lambda () (not (emacsvox-aural-voice-editor--get :preview-operation))))
             (let* ((result (emacsvox-aural-voice-editor--get :preview-result))
                    (samples (cl-remove-if-not (lambda (r) (eq (plist-get (plist-get r :request-snapshot) :role) 'sample))
                                               (plist-get result :results)))
                    (last (plist-get (car (last samples)) :last-started)))
               (unless (and (eq (plist-get result :status) 'completed) (= 2 (length samples)))
                 (error "Editor comparison failed: %S" result))
               (native-accept--applied tts-speaker-process last (nth 1 case) (nth 2 case)))
             (princ (format "editor comparison and readback: %s passed\n" (car case)))
             (emacsvox-aural-voice-engine-controls-back))
           (emacsvox-aural-voice-editor-save-to-collection)
           (let ((saved (plist-get (emacsvox-aural-voice-editing--snapshot 'reading-owned 'bolden) :snapshot)))
             (should (equal (plist-get saved :choices) (plist-get (emacsvox-aural-voice-editor--working) :choices)))
             (setq owned (plist-put owned :choices (plist-get saved :choices))))
           (princ "native palette save and reload passed\n")))
        ;; Exercise acknowledged publication and consumed ordinary speech on both lanes.
        (cl-letf (((symbol-function 'omnivox--logical-voice-ids) (lambda () '("bolden" "voice-bolden")))
                  ((symbol-function 'emacsvox-aural-voice-runtime--owned) (lambda (&rest _) owned)))
          (dotimes (round 2)
            (when (= round 1)
              (let ((choices (copy-tree (plist-get owned :choices))))
                (setq owned (plist-put owned :choices
                                       (cons (nth 2 choices)
                                             (append (seq-take choices 2) (nthcdr 3 choices)))))))
            (dolist (engine '("dectalk" "eloquence")) (native-accept--catalogue tts-speaker-process engine))
            (let (applied)
              (omnivox-apply-voice-configuration (lambda (r) (setq applied r)))
              (native-accept--wait (lambda () applied))
              (unless (eq (plist-get applied :status) 'applied) (error "Apply: %S" applied)))
            (dolist (lane (list tts-speaker-process tts-notify-process))
              (let ((tts-speaker-process lane) terminal)
                (omnivox-choice-playback-test--submit nil (lambda (_ status) (setq terminal status)))
                (native-accept--wait (lambda () terminal))
                (unless (eq terminal 'completed) (error "Speech: %S" terminal))
                (let ((route (omnivox-last-realized-voice 'bolden)))
                  (should (eq (plist-get route :choice-status) 'verified))
                  (should (equal (plist-get route :choice-id) (if (= round 0) "paul-main" "eci-default")))
                  (native-accept--applied lane
                    (list :realized (list :engine_id (plist-get route :engine-id) :voice_id (plist-get route :voice-id))
                          :choice_id (plist-get route :choice-id)
                          :native_application (plist-get route :native-application))
                    (if (= round 0) "sm" "breathiness") (if (= round 0) 61 35)))
                (princ (format "round=%d lane=%s native ordinary speech verified\n" round (process-name lane)))))
            (when (= round 0)
              (tts--retire-process tts-speaker-process)
              (setq tts-speaker-process (native-accept--process "native-reconnected" 3003)))))
        (unless (null omnivox-marker-last-error) (error "Marker: %S" omnivox-marker-last-error))
        (princ "Real-server native client acceptance passed (null audio).\n"))
    (dolist (process (delete-dups (list original tts-speaker-process tts-notify-process)))
      (when (process-live-p process) (tts--retire-process process)))))
;;; verify-omnivox-native-runtime.el ends here
