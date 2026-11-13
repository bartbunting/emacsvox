;;; omnivox-audio-devices-tests.el --- Physical output regressions -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Code:
(require 'ert)
(require 'cl-lib)
(require 'omnivox-output-devices)
(require 'omnivox-voices)
(require 'emacsvox-advice-messages)

(defmacro omnivox-devices-tests--worker (&rest body)
  (declare (indent 0))
  `(let ((tts-program "omnivox") (omnivox-audio-devices--lanes nil)
         (omnivox-audio-device-preferences nil)
         (tts-speaker-process (make-pipe-process :name "device-main" :noquery t))
         (tts-notify-process nil))
     (unwind-protect
         (progn
           (process-put tts-speaker-process 'omnivox--control-capabilities
                        '(:features ("audio_device_selection_v1")))
           ,@body)
       (when (process-live-p tts-speaker-process) (delete-process tts-speaker-process)))))

(defun omnivox-devices-tests--status (&optional change outcome)
  "Build a coherent test status for CHANGE and OUTCOME."
  (list :type "audio_device_status_v1" :incarnation "worker" :host_scope "windows:wasapi:desk"
        :state (list :revision (if (equal outcome "applied") 1 0)
                     :selection (if (equal outcome "applied") (plist-get change :selection) '(:mode "system_default"))
                     :connected "wasapi:headset"
                     :last_operation (when change (list :change change :outcome outcome :reason nil)))))

(ert-deftest omnivox-devices-command-errors-with-missing-notifier-never-spawn-main ()
  "Quit feedback must not create an owner in a temporary main binding."
  (omnivox-devices-tests--worker
    (let ((tts-notification-device nil) (emacsvox-speak-messages nil) attempted)
      (omnivox-audio-devices--put 'speaker (list :status (omnivox-devices-tests--status)))
      (omnivox-audio-devices--put
       'notification (list :status (omnivox-devices-tests--status
                                    '(:sequence 1 :expected_revision 0
                                      :selection (:mode "device" :id "wasapi:private")) "applied")))
      (cl-letf (((symbol-function 'emacsvox-aural-submit)
                 (lambda (_text &rest arguments)
                   (let ((emacsvox-aural-submission-lane (plist-get arguments :lane)))
                     (emacsvox-aural--call-on-submission-lane
                      (lambda ()
                        (unless (tts--speech-process-usable-p tts-speaker-process)
                          (tts--recover-speaker)))))))
                ((symbol-function 'tts--recover-speaker) (lambda () (setq attempted t))))
        (dotimes (_ 5) (emacsvox--present-command-error '(quit))))
      (should-not attempted))))

(ert-deftest omnivox-devices-submission-lane-death-cannot-create-a-replacement ()
  "A notifier dying inside a submission cannot recover onto another output."
  (omnivox-devices-tests--worker
    (let ((tts-notification-device nil)
          (tts-notify-process (make-pipe-process :name "device-notify" :noquery t))
          (emacsvox-aural-submission-lane 'notification)
          (main tts-speaker-process))
      (omnivox-audio-devices--put 'speaker (list :status (omnivox-devices-tests--status)))
      (omnivox-audio-devices--put 'notification (list :override '(:mode "device" :id "wasapi:private")))
      (unwind-protect
          (cl-letf (((symbol-function 'tts-make-process)
                     (lambda (_) (ert-fail "Submission started an abandoned worker"))))
            (emacsvox-aural--call-on-submission-lane
             (lambda ()
               (should (eq tts-speaker-process tts-notify-process))
               (delete-process tts-notify-process)
               (tts--recover-speaker)
               (should-not tts-speaker-process)))
            (should (eq main tts-speaker-process))
            (should (process-live-p main)))
        (when (process-live-p tts-notify-process) (delete-process tts-notify-process))))))

(ert-deftest omnivox-devices-saved-lanes-are-projected-without-starting-a-process ()
  (omnivox-devices-tests--worker
    (let ((omnivox-audio-device-preferences
           '(("windows:wasapi:desk" speaker "wasapi:headset" "Headset")
             ("windows:wasapi:desk" notification "default" "Default")
             ("windows:wasapi:other" speaker "wasapi:other" "Other"))))
      (cl-letf (((symbol-function 'make-process) (lambda (&rest _) (ert-fail "Startup spawned discovery"))))
        (let* ((process-environment (omnivox-audio-devices--startup-environment nil 'notification))
               (rows (json-parse-string (getenv "OMNIVOX_AUDIO_DEVICE_PREFERENCES") :object-type 'plist :array-type 'list)))
          (should (= 1 (length rows)))
          (should (equal '(:mode "system_default") (plist-get (car rows) :selection)))
          (should-not (getenv "OMNIVOX_OWNED_AUDIO_DEVICE")))))))

(ert-deftest omnivox-devices-lost-reply-queries-one-operation-and-retains-confirmed-recovery ()
  (omnivox-devices-tests--worker
    (let (change outcome requests)
      (cl-letf (((symbol-function 'omnivox--send-control-request)
                 (lambda (process request callback &optional _)
                   (push request requests)
                   (pcase (plist-get request :type)
                     ("audio_device_status_v1"
                      (funcall callback process (omnivox-devices-tests--status change (when change "applied"))))
                     ("apply_audio_device_v1"
                      (setq change (plist-get request :change))
                      (should (plist-get (omnivox-audio-devices--record 'speaker) :pending))
                      (funcall callback process '(:type "error" :code "timeout")))))))
        (omnivox-audio-devices--apply tts-speaker-process 'speaker '(:mode "device" :id "wasapi:headset")
                                     (lambda (value _) (setq outcome value)))
        (let ((deadline (+ (float-time) 1)))
          (while (and (not outcome) (< (float-time) deadline)) (sleep-for 0.01))))
      (should (equal "applied" outcome))
      (should (= 1 (cl-count "apply_audio_device_v1" requests :key (lambda (r) (plist-get r :type)) :test #'equal)))
      (should-not (plist-get (omnivox-audio-devices--record 'speaker) :pending))
      (should-not omnivox-audio-device-preferences)
      (let ((process-environment (omnivox-audio-devices--startup-environment nil 'speaker)))
        (should (equal "wasapi:headset" (getenv "OMNIVOX_OWNED_AUDIO_DEVICE")))))))

(ert-deftest omnivox-devices-death-during-apply-blocks-assumed-recovery ()
  (omnivox-devices-tests--worker
    (let (outcome)
      (cl-letf (((symbol-function 'omnivox--send-control-request)
                 (lambda (process request callback &optional _)
                   (if (equal (plist-get request :type) "audio_device_status_v1")
                       (funcall callback process (omnivox-devices-tests--status))
                     (delete-process process)
                     (funcall callback process '(:type "error" :code "process-exited"))))))
        (omnivox-audio-devices--apply tts-speaker-process 'speaker '(:mode "device" :id "wasapi:headset")
                                     (lambda (value _) (setq outcome value)))
        (let ((deadline (+ (float-time) 1)))
          (while (and (not outcome) (< (float-time) deadline)) (sleep-for 0.01))))
      (should (equal outcome "unknown"))
      (should (plist-get (omnivox-audio-devices--record 'speaker) :pending))
      (should-error (omnivox-audio-devices--startup-environment nil 'speaker) :type 'user-error))))

(ert-deftest omnivox-devices-refreshed-cancellation-preserves-confirmed-route ()
  (omnivox-devices-tests--worker
    (let* ((change '(:sequence 1 :expected_revision 0 :selection (:mode "device" :id "wasapi:new")))
           (pending (list :incarnation "worker" :change change)))
      (omnivox-audio-devices--put 'speaker (list :process tts-speaker-process :pending pending))
      (cl-letf (((symbol-function 'omnivox--send-control-request)
                 (lambda (process request callback &optional _)
                   (should (equal "cancel_audio_device_v1" (plist-get request :type)))
                   (should (= 1 (plist-get request :sequence)))
                   (funcall callback process
                            (list :type "audio_device_result_v1" :sequence 1 :outcome "cancelled"
                                  :status (omnivox-devices-tests--status change "cancelled"))))))
        (omnivox-audio-devices--refresh-status tts-speaker-process 'speaker #'ignore t))
      (should-not (plist-get (omnivox-audio-devices--record 'speaker) :pending))
      (let ((process-environment (omnivox-audio-devices--startup-environment nil 'speaker)))
        (should (equal "default" (getenv "OMNIVOX_OWNED_AUDIO_DEVICE")))))))

(ert-deftest omnivox-devices-stale-observation-cannot-replace-a-later-confirmed-choice ()
  (omnivox-devices-tests--worker
    (let* ((change '(:sequence 1 :expected_revision 0 :selection (:mode "device" :id "wasapi:new")))
           (status (omnivox-devices-tests--status change "applied")))
      (should (omnivox-audio-devices--observe tts-speaker-process 'speaker status))
      (should-not (omnivox-audio-devices--observe tts-speaker-process 'speaker (omnivox-devices-tests--status)))
      (should (equal status (plist-get (omnivox-audio-devices--record 'speaker) :status))))))

(ert-deftest omnivox-devices-rejects-a-catalogue-from-a-different-host ()
  (omnivox-devices-tests--worker
    (let (outcome)
      (cl-letf (((symbol-function 'omnivox--send-control-request)
                 (lambda (process request callback &optional _)
                   (should (equal "audio_device_status_v1" (plist-get request :type)))
                   (funcall callback process (omnivox-devices-tests--status)))))
        (omnivox-audio-devices--apply tts-speaker-process 'speaker '(:mode "system_default")
                                     (lambda (value _) (setq outcome value)) "windows:wasapi:elsewhere"))
      (should (equal outcome "rejected"))
      (should-not (plist-get (omnivox-audio-devices--record 'speaker) :pending)))))

(ert-deftest omnivox-devices-notifications-never-fall-back-to-a-different-output ()
  (omnivox-devices-tests--worker
    (let ((main (omnivox-devices-tests--status))
          (notify (omnivox-devices-tests--status '(:sequence 1 :expected_revision 0 :selection (:mode "device" :id "wasapi:private")) "applied"))
          spoken)
      (omnivox-audio-devices--put 'speaker (list :status main))
      (omnivox-audio-devices--put 'notification (list :status notify))
      (should-not (tts-notify-process))
      (cl-letf (((symbol-function 'tts-speak) (lambda (&rest _) (setq spoken t))))
        (tts-notify "Must not reach main output" t)
        (should-not spoken))
      (omnivox-audio-devices--put 'notification (list :status main))
      (should (eq tts-speaker-process (tts-notify-process)))
      (omnivox-audio-devices--put 'notification (list :status main :pending t))
      (should-not (tts-notify-process)))))

(ert-deftest omnivox-devices-save-persists-only-confirmed-lane-and-keeps-missing-identity ()
  (omnivox-devices-tests--worker
    (let ((state '(:role speaker :candidate "wasapi:b" :catalogue
                   (:supported t :host_scope "windows:wasapi:desk"
                    :devices ((:id "wasapi:a" :name "Same") (:id "wasapi:b" :name "Same")))))
          (omnivox-audio-device-preferences '(("windows:wasapi:desk" notification "wasapi:notify" "Private")))
          saved)
      (omnivox-audio-devices--put
       'speaker (list :process tts-speaker-process :status
                      (omnivox-devices-tests--status '(:sequence 1 :expected_revision 0 :selection (:mode "device" :id "wasapi:missing")) "applied")))
      (cl-letf (((symbol-function 'omnivox-output-devices--state) (lambda () state))
                ((symbol-function 'omnivox-output-devices--render) #'ignore)
                ((symbol-function 'omnivox-output-devices--say) #'ignore)
                ((symbol-function 'customize-save-variable)
                 (lambda (symbol value &rest _) (should (eq symbol 'omnivox-audio-device-preferences)) (setq saved value))))
        (should (equal '("default" "wasapi:a" "wasapi:b" "wasapi:missing") (omnivox-output-devices--ids state)))
        (should (string-match-p "device 1" (omnivox-output-devices--description "wasapi:a" state)))
        (should (string-match-p "device 2" (omnivox-output-devices--description "wasapi:b" state)))
        (omnivox-output-devices-save))
      (should (equal '(("windows:wasapi:desk" speaker "wasapi:missing" "Unavailable saved or applied device")
                       ("windows:wasapi:desk" notification "wasapi:notify" "Private")) saved)))))

(ert-deftest omnivox-devices-death-during-notification-delivery-does-not-cross-devices ()
  (omnivox-devices-tests--worker
    (let ((tts-notify-process (make-pipe-process :name "device-notify" :noquery t)))
      (omnivox-audio-devices--put 'speaker (list :status (omnivox-devices-tests--status)))
      (omnivox-audio-devices--put
       'notification (list :status (omnivox-devices-tests--status
                                    '(:sequence 1 :expected_revision 0 :selection (:mode "device" :id "wasapi:private")) "applied")))
      (unwind-protect
          (tts-notify-apply
           (lambda (_)
             (delete-process tts-notify-process)
             (tts--recover-speaker)
             (should-not tts-speaker-process)) "Notification")
        (when (process-live-p tts-notify-process) (delete-process tts-notify-process))))))

(ert-deftest omnivox-devices-unknown-apply-blocks-retirement-before-recovery ()
  (omnivox-devices-tests--worker
    (omnivox-audio-devices--put 'speaker (list :process tts-speaker-process :pending t))
    (cl-letf (((symbol-function 'tts--confirm-owned-retirement)
               (lambda (_) (ert-fail "Unknown Apply retired a working owner"))))
      (should-error (tts-recover) :type 'user-error))))

(ert-deftest omnivox-devices-concurrent-apply-does-not-reuse-a-sequence ()
  (omnivox-devices-tests--worker
    (let (receive requests)
      (cl-letf (((symbol-function 'omnivox--send-control-request)
                 (lambda (_process request callback &optional _)
                   (push request requests) (setq receive callback))))
        (omnivox-audio-devices--apply tts-speaker-process 'speaker '(:mode "system_default") #'ignore)
        (should-error (omnivox-audio-devices--apply tts-speaker-process 'speaker '(:mode "system_default") #'ignore)
                      :type 'user-error)
        (should (= 1 (length requests)))
        (funcall receive tts-speaker-process '(:type "error" :code "timeout"))
        (should-not (plist-get (omnivox-audio-devices--record 'speaker) :query-operation))))))

(ert-deftest omnivox-devices-unsupported-workers-never-receive-new-requests ()
  (omnivox-devices-tests--worker
    (process-put tts-speaker-process 'omnivox--control-capabilities '(:features ()))
    (cl-letf (((symbol-function 'omnivox--send-control-request)
               (lambda (&rest _) (ert-fail "Sent output command to unsupported worker"))))
      (omnivox-audio-devices--negotiate tts-speaker-process)
      (should-error (omnivox-audio-devices--apply tts-speaker-process 'speaker '(:mode "system_default") #'ignore)
                    :type 'user-error))))

(ert-deftest omnivox-devices-replacement-during-preliminary-query-cannot-send-old-apply ()
  (omnivox-devices-tests--worker
    (let (receive outcome)
      (cl-letf (((symbol-function 'omnivox--send-control-request)
                 (lambda (_ request callback &optional _)
                   (should (equal "audio_device_status_v1" (plist-get request :type)))
                   (setq receive callback))))
        (omnivox-audio-devices--apply tts-speaker-process 'speaker '(:mode "system_default")
                                     (lambda (value _) (setq outcome value)))
        (omnivox-audio-devices--put 'speaker '(:replacement t))
        (funcall receive tts-speaker-process (omnivox-devices-tests--status))
        (should (equal "stale" outcome))
        (should (equal '(:replacement t) (omnivox-audio-devices--record 'speaker)))))))

(ert-deftest omnivox-devices-retired-owner-is-unavailable-and-apply-establishes-recovery ()
  (omnivox-devices-tests--worker
    (process-put tts-speaker-process 'omnivox-library-retired t)
    (should (process-live-p tts-speaker-process))
    (should-not (omnivox-audio-devices--supported-p tts-speaker-process))
    (omnivox-audio-devices--put
     'speaker (list :process tts-speaker-process :status (omnivox-devices-tests--status) :pending t))
    (let ((state '(:role speaker :candidate "wasapi:headset" :catalogue
                   (:supported t :host_scope "windows:wasapi:desk" :devices ((:id "wasapi:headset" :name "Headset"))))))
      (should (string-match-p "Last confirmed" (omnivox-output-devices--description "default" state)))
      (should-not (string-match-p "Connected" (omnivox-output-devices--description "wasapi:headset" state)))
      (let (retired recovered)
        (cl-letf (((symbol-function 'omnivox-output-devices--state) (lambda () state))
                  ((symbol-function 'omnivox-output-devices--render) #'ignore)
                  ((symbol-function 'yes-or-no-p) (lambda (_) t))
                  ((symbol-function 'omnivox-audio-devices--apply)
                   (lambda (&rest _) (ert-fail "Sent Apply to a retired worker")))
                  ((symbol-function 'tts--confirm-owned-retirement)
                   (lambda (process)
                     (should (eq process tts-speaker-process))
                     (should-not (omnivox-audio-devices--observe process 'speaker (omnivox-devices-tests--status)))
                     (setq retired t)))
                  ((symbol-function 'tts--recover-speaker)
                   (lambda ()
                     (should retired)
                     (should-not (plist-get (omnivox-audio-devices--record 'speaker) :pending))
                     (let ((process-environment (omnivox-audio-devices--startup-environment nil 'speaker)))
                       (should (equal "wasapi:headset" (getenv "OMNIVOX_OWNED_AUDIO_DEVICE")))
                       (should (equal "windows:wasapi:desk" (getenv "OMNIVOX_OWNED_AUDIO_DEVICE_HOST"))))
                     (setq recovered t)))
                  ((symbol-function 'omnivox-output-devices--refresh) #'ignore))
          (should-error (omnivox-output-devices-save) :type 'user-error)
          (omnivox-output-devices-apply))
        (should recovered)))))

(ert-deftest omnivox-devices-unresolved-ordinary-apply-does-not-block-emergency-recovery ()
  (omnivox-devices-tests--worker
    (omnivox-audio-devices--put 'speaker (list :pending t))
    (process-put tts-speaker-process 'omnivox-emergency-output "device")
    (let ((recoveries 0) retired)
      (cl-letf (((symbol-function 'tts-emergency-start)
                 (lambda (output) (should (equal "device" output)) (cl-incf recoveries)))
                ((symbol-function 'tts--confirm-owned-retirement) (lambda (_) (setq retired t)))
                ((symbol-function 'tts--protocol-sync) #'ignore))
        (tts--recover-speaker)
        (tts-recover)
        (should retired)
        (should (= 2 recoveries))
        (should (plist-get (omnivox-audio-devices--record 'speaker) :pending))
        (should-error (tts-initialize) :type 'user-error)))))

(provide 'omnivox-audio-devices-tests)
;;; omnivox-audio-devices-tests.el ends here
