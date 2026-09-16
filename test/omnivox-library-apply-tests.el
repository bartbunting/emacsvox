;;; omnivox-library-apply-tests.el --- Apply sequencing contracts -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later
;;; Commentary:
;; Exercise the real coordinator with a simulated native owner.  These tests
;; establish client sequencing and evidence checks, not native process cleanup.
;;; Code:
(require 'ert)
(require 'omnivox-library-apply)

(defun omnivox-library-apply-test--id (number)
  (format "%08x-0000-0000-0000-000000000000" number))

(defun omnivox-library-apply-test--config (number)
  (list :target_id (omnivox-library-apply-test--id 1)
        :profile_id (omnivox-library-apply-test--id 2)
        :generation_id (omnivox-library-apply-test--id number)
        :sha256 (make-string 64 (+ ?a (% number 6)))))

(defun omnivox-library-apply-test--workers (number)
  (vector (list :role 'speaker :worker (omnivox-library-apply-test--id number))
          (list :role 'notification :worker (omnivox-library-apply-test--id (1+ number)))))

(defun omnivox-library-apply-test--plan (&optional legacy)
  (list
   :operation-id (omnivox-library-apply-test--id 10)
   :candidate (omnivox-library-apply-test--config 30)
   ;; Another session has advanced this pointer since our actual workers started.
   :previous-active (if legacy :null (omnivox-library-apply-test--config 29))
   :index-sha256 (make-string 64 ?f) :overridden-engines []
   :eligible-voices [(:engine_id "flite" :voice_id "cmu_us_slt")]
   :previous-lanes
   (vconcat
    (cl-loop for role in '(speaker notification) for number from 20 collect
             (list :role role :worker (omnivox-library-apply-test--id number)
                   :startup (list :program "/native/omnivox" :environment
                                  (vector (if (eq role 'speaker) "OUTPUT=both" "OUTPUT=left")))
                   :configuration (if legacy :null (omnivox-library-apply-test--config number))
                   :overridden-engines ["piper"]
                   :eligible-voices [(:engine_id "piper" :voice_id "piper:old")])))
   :candidate-startup [(:role speaker :startup (:program "/native/omnivox" :environment ["OUTPUT=both"]))
                       (:role notification :startup (:program "/native/omnivox" :environment ["OUTPUT=left"]))]
   :impact "Restart both speech streams; retain saved palette references"))

(defun omnivox-library-apply-test--proofs (plan workers previous)
  (vconcat
   (cl-loop for lane across workers for index from 0 collect
            (let* ((expected (if previous (aref (plist-get plan :previous-lanes) index) plan))
                   (config (plist-get expected (if previous :configuration :candidate)))
                   (legacy (eq config :null)))
              (list :role (plist-get lane :role) :worker (plist-get lane :worker)
                    :ready t :negotiated (not legacy) :inventory-generation (+ 5 index)
                    :request-id (if legacy :null (+ 50 index))
                    :status
                    (if legacy :legacy
                      (list :protocol_version 1 :request_id (+ 50 index) :type "voice_library_status_v1"
                            :configuration config :overridden_engines (plist-get expected :overridden-engines)
                            :eligible_voices (plist-get expected :eligible-voices)
                            :inventory_generation (+ 5 index))))))))

(defun omnivox-library-apply-test--receipt (action)
  (let ((plan (plist-get action :plan)))
    (pcase (plist-get action :phase)
      ('preflight
       (let ((workers (omnivox-library-apply-test--workers 40)))
         (list :ok t :workers workers :proofs (omnivox-library-apply-test--proofs plan workers nil)
               :quiescent t)))
      ('activating (list :ok t :previous-active (plist-get plan :previous-active)
                         :index-sha256 (plist-get plan :index-sha256) :previous-lanes (plist-get plan :previous-lanes)))
      ((or 'retire-old 'retire-candidate) '(:ok t :quiescent t))
      ('start-candidate (list :ok t :workers (omnivox-library-apply-test--workers 60)))
      ('start-previous (list :ok t :workers (omnivox-library-apply-test--workers 80)))
      ((or 'verify-candidate 'verify-previous)
       (list :ok t :proofs (omnivox-library-apply-test--proofs
                            plan (plist-get action :workers) (eq (plist-get action :phase) 'verify-previous))))
      ('commit (list :ok t :commit 'committed :active (plist-get plan :candidate)))
      ('rolling-back (list :ok t :previous-active (plist-get plan :previous-active)))
      ('finish (list :ok t :state (plist-get action :final))))))

(defun omnivox-library-apply-test--complete (operation action receipt)
  (omnivox-library-apply--complete operation (plist-get action :operation-id)
                                 (plist-get action :ticket) (plist-get action :phase) receipt))

(defun omnivox-library-apply-test--step (operation &optional alter)
  (let* ((action (omnivox-library-apply--action operation))
         (receipt (omnivox-library-apply-test--receipt action)))
    (should action)
    (when alter (setq receipt (funcall alter receipt action)))
    (should (omnivox-library-apply-test--complete operation action receipt))
    action))

(defun omnivox-library-apply-test--reach (operation phase)
  (let ((remaining 20))
    (while (not (eq (omnivox-library-apply--operation-phase operation) phase))
      (should (> (cl-decf remaining) 0))
      (omnivox-library-apply-test--step operation))))

(ert-deftest omnivox-library-apply-commits-only-after-both-pairs-and-evidence ()
  (let ((operation (omnivox-library-apply--begin (omnivox-library-apply-test--plan))) trace)
    (while (not (omnivox-library-apply--operation-result operation))
      (let ((action (omnivox-library-apply-test--step operation)))
        (push (plist-get action :phase) trace)
        (when (eq (plist-get action :phase) 'commit)
          (should (= (length (plist-get action :evidence)) 2)))))
    (should (equal (nreverse trace) '(preflight activating retire-old start-candidate verify-candidate commit)))
    (should (eq (plist-get (omnivox-library-apply--operation-result operation) :status) 'succeeded))
    (should-not (omnivox-library-apply--action operation))))

(ert-deftest omnivox-library-apply-rollback-restores-actual-lanes-not-active-pointer ()
  (dolist (legacy '(nil t))
    (let ((operation (omnivox-library-apply--begin (omnivox-library-apply-test--plan legacy))) trace)
      (omnivox-library-apply-test--reach operation 'start-candidate)
      ;; Notification startup failed after the provider started the speaker.
      (omnivox-library-apply-test--step operation (lambda (_receipt _action) '(:ok nil :message "Notification startup failed")))
      (while (not (omnivox-library-apply--operation-result operation))
        (push (plist-get (omnivox-library-apply-test--step operation) :phase) trace))
      (should (equal (nreverse trace) '(rolling-back retire-candidate start-previous verify-previous finish)))
      (should (eq (plist-get (omnivox-library-apply--operation-result operation) :status) 'rolled-back))
      (let ((proofs (omnivox-library-apply--operation-evidence operation)))
        (if legacy (should (eq (plist-get (aref proofs 0) :status) :legacy))
          (should (equal (plist-get (plist-get (aref proofs 0) :status) :configuration)
                         (omnivox-library-apply-test--config 20)))
          (should (equal (plist-get (plist-get (aref proofs 1) :status) :configuration)
                         (omnivox-library-apply-test--config 21))))))))

(ert-deftest omnivox-library-apply-rejects-one-wrong-lane-without-commit ()
  (dolist (change '(owner generation digest eligible overrides inventory request readiness negotiation missing duplicate))
    (let ((operation (omnivox-library-apply--begin (omnivox-library-apply-test--plan))))
      (omnivox-library-apply-test--reach operation 'verify-candidate)
      (omnivox-library-apply-test--step
       operation
       (lambda (receipt _action)
         (let* ((proofs (plist-get receipt :proofs)) (proof (aref proofs 1)) (status (plist-get proof :status)))
           (pcase change
             ('owner (setf (plist-get proof :worker) (omnivox-library-apply-test--id 20)))
             ('generation (setf (plist-get status :configuration) (omnivox-library-apply-test--config 29)))
             ('digest (setf (plist-get (plist-get status :configuration) :sha256) (make-string 64 ?0)))
             ('eligible (setf (plist-get status :eligible_voices) []))
             ('overrides (setf (plist-get status :overridden_engines) ["piper"]))
             ('inventory (setf (plist-get status :inventory_generation) 900))
             ('request (setf (plist-get status :request_id) 999))
             ('readiness (setf (plist-get proof :ready) nil))
             ('negotiation (setf (plist-get proof :negotiated) nil))
             ('missing (setf (plist-get receipt :proofs) (vector (aref proofs 0))))
             ('duplicate (setf (plist-get proof :status) (append status '(:configuration :null)))))
           receipt)))
      (should (eq (omnivox-library-apply--operation-phase operation) 'rolling-back)))))

(ert-deftest omnivox-library-apply-stale-plan-never-retires-old-pair ()
  (dolist (field '(:previous-active :index-sha256 :previous-lanes))
    (let ((operation (omnivox-library-apply--begin (omnivox-library-apply-test--plan))))
      (omnivox-library-apply-test--reach operation 'activating)
      (omnivox-library-apply-test--step operation (lambda (receipt _action) (plist-put receipt field :changed)))
      (should (eq (omnivox-library-apply--operation-phase operation) 'finish))
      (should (eq (omnivox-library-apply--operation-final operation) 'failed)))))

(ert-deftest omnivox-library-apply-cleanup-failure-blocks-any-replacement ()
  (dolist (phase '(retire-old retire-candidate))
    (let ((operation (omnivox-library-apply--begin (omnivox-library-apply-test--plan))))
      (omnivox-library-apply-test--reach operation 'retire-old)
      (when (eq phase 'retire-candidate)
        (omnivox-library-apply-test--reach operation 'start-candidate)
        (omnivox-library-apply-test--step operation (lambda (_receipt _action) '(:ok nil :message "Timed out")))
        (omnivox-library-apply-test--reach operation 'retire-candidate))
      (omnivox-library-apply-test--step operation (lambda (_receipt _action) '(:ok t :quiescent nil)))
      (should (eq (omnivox-library-apply--operation-phase operation) 'finish))
      (omnivox-library-apply-test--step operation)
      (should (eq (plist-get (omnivox-library-apply--operation-result operation) :status) 'recovery-failed)))))

(ert-deftest omnivox-library-apply-commit-ambiguity-does-not-rollback ()
  (dolist (receipt '((:ok nil :message "Manager connection lost")
                     (:ok t :commit unknown :active :null)
                     (:ok t :commit committed :active :null)))
    (let ((operation (omnivox-library-apply--begin (omnivox-library-apply-test--plan))))
      (omnivox-library-apply-test--reach operation 'commit)
      (omnivox-library-apply-test--step operation (lambda (_receipt _action) receipt))
      (should (eq (plist-get (omnivox-library-apply--operation-result operation) :status) 'interrupted))
      (should-not (omnivox-library-apply--action operation)))))

(ert-deftest omnivox-library-apply-confirmed-uncommitted-result-rolls-back ()
  (let ((operation (omnivox-library-apply--begin (omnivox-library-apply-test--plan))))
    (omnivox-library-apply-test--reach operation 'commit)
    (omnivox-library-apply-test--step operation
     (lambda (_receipt action)
       (list :ok t :commit 'not-committed :active (plist-get (plist-get action :plan) :previous-active))))
    (should (eq (omnivox-library-apply--operation-phase operation) 'rolling-back))))

(ert-deftest omnivox-library-apply-cancellation-before-retirement-preserves-pair ()
  (dolist (phase '(preflight activating retire-old))
    (let ((operation (omnivox-library-apply--begin (omnivox-library-apply-test--plan))))
      (omnivox-library-apply-test--reach operation phase)
      (omnivox-library-apply--cancel operation)
      (let ((action (omnivox-library-apply-test--step operation)))
        (should (eq (plist-get action :phase) 'finish)))
      (should (eq (plist-get (omnivox-library-apply--operation-result operation) :status) 'cancelled)))))

(ert-deftest omnivox-library-apply-cancellation-after-retirement-restores-both ()
  (dolist (phase '(retire-old start-candidate verify-candidate))
    (let ((operation (omnivox-library-apply--begin (omnivox-library-apply-test--plan))))
      (omnivox-library-apply-test--reach operation phase)
      (let ((action (omnivox-library-apply--action operation)))
        (omnivox-library-apply--cancel operation)
        (omnivox-library-apply-test--complete operation action (omnivox-library-apply-test--receipt action)))
      (should (eq (omnivox-library-apply--operation-phase operation) 'rolling-back))
      (omnivox-library-apply-test--reach operation 'done)
      (should (eq (plist-get (omnivox-library-apply--operation-result operation) :status) 'rolled-back)))))

(ert-deftest omnivox-library-apply-cancellation-with-issued-commit-observes-result ()
  (let ((operation (omnivox-library-apply--begin (omnivox-library-apply-test--plan))))
    (omnivox-library-apply-test--reach operation 'commit)
    (let ((action (omnivox-library-apply--action operation)))
      (omnivox-library-apply--cancel operation)
      (should (eq (omnivox-library-apply--operation-phase operation) 'commit))
      (omnivox-library-apply-test--complete operation action (omnivox-library-apply-test--receipt action)))
    (should (eq (plist-get (omnivox-library-apply--operation-result operation) :status) 'succeeded))))

(ert-deftest omnivox-library-apply-issues-once-and-ignores-stale-replies ()
  (let* ((operation (omnivox-library-apply--begin (omnivox-library-apply-test--plan)))
         (action (omnivox-library-apply--action operation))
         (receipt (omnivox-library-apply-test--receipt action)))
    (should-not (omnivox-library-apply--action operation))
    (should-not (omnivox-library-apply--complete operation (omnivox-library-apply-test--id 11) 1 'preflight receipt))
    (should-not (omnivox-library-apply--complete operation (plist-get action :operation-id) 2 'preflight receipt))
    (should-not (omnivox-library-apply--complete operation (plist-get action :operation-id) 1 'commit receipt))
    (should (omnivox-library-apply-test--complete operation action receipt))
    (should-not (omnivox-library-apply-test--complete operation action receipt))
    (should (eq (omnivox-library-apply--operation-phase operation) 'activating))))

(ert-deftest omnivox-library-apply-freezes-caller-and-provider-data ()
  (let* ((plan (omnivox-library-apply-test--plan))
         (operation (omnivox-library-apply--begin plan))
         (action (omnivox-library-apply--action operation))
         (receipt (omnivox-library-apply-test--receipt action)))
    (aset (plist-get (plist-get plan :candidate) :sha256) 0 ?0)
    (should (omnivox-library-apply-test--complete operation action receipt))
    (aset (plist-get (plist-get (plist-get action :plan) :candidate) :sha256) 0 ?1)
    (aset (plist-get (aref (plist-get receipt :workers) 0) :worker) 0 ?f)
    (let ((next (omnivox-library-apply--action operation)))
      (should (equal (plist-get (plist-get next :plan) :candidate) (omnivox-library-apply-test--config 30))))))

(ert-deftest omnivox-library-apply-rejects-reused-probe-or-old-worker ()
  (dolist (number '(20 40))
    (let ((operation (omnivox-library-apply--begin (omnivox-library-apply-test--plan))))
      (omnivox-library-apply-test--reach operation 'start-candidate)
      (omnivox-library-apply-test--step operation
       (lambda (_receipt _action) (list :ok t :workers (omnivox-library-apply-test--workers number))))
      (should (eq (omnivox-library-apply--operation-phase operation) 'rolling-back)))))

(ert-deftest omnivox-library-apply-rollback-failure-is-visible ()
  (dolist (phase '(start-previous verify-previous))
    (let ((operation (omnivox-library-apply--begin (omnivox-library-apply-test--plan))))
      (omnivox-library-apply-test--reach operation 'start-candidate)
      (omnivox-library-apply--cancel operation)
      (omnivox-library-apply-test--reach operation phase)
      (omnivox-library-apply-test--step operation (lambda (_receipt _action) '(:ok nil :message "Rollback failed")))
      (omnivox-library-apply-test--step operation)
      (should (eq (plist-get (omnivox-library-apply--operation-result operation) :status) 'recovery-failed)))))

(ert-deftest omnivox-library-apply-journal-failure-cannot-claim-rollback-success ()
  (let ((operation (omnivox-library-apply--begin (omnivox-library-apply-test--plan))))
    (omnivox-library-apply-test--reach operation 'start-candidate)
    (omnivox-library-apply--cancel operation)
    (omnivox-library-apply-test--reach operation 'finish)
    (omnivox-library-apply-test--step operation (lambda (_receipt _action) '(:ok nil :message "Disk write failed")))
    (should (eq (plist-get (omnivox-library-apply--operation-result operation) :status) 'interrupted))))

(ert-deftest omnivox-library-apply-rollback-journal-failure-still-retires-candidates ()
  (let ((operation (omnivox-library-apply--begin (omnivox-library-apply-test--plan))))
    (omnivox-library-apply-test--reach operation 'start-candidate)
    (omnivox-library-apply-test--step operation (lambda (_receipt _action) '(:ok nil :message "Second lane failed")))
    (omnivox-library-apply-test--step operation (lambda (_receipt _action) '(:ok nil :message "Journal failed")))
    (should (eq (omnivox-library-apply--operation-phase operation) 'retire-candidate))
    (omnivox-library-apply-test--step operation)
    (should (eq (omnivox-library-apply--operation-phase operation) 'finish))
    (omnivox-library-apply-test--step operation)
    (let ((result (omnivox-library-apply--operation-result operation)))
      (should (eq (plist-get result :status) 'recovery-failed))
      (should (equal (mapcar (lambda (failure) (plist-get failure :phase)) (plist-get result :failures))
                     '(start-candidate rolling-back))))))

(ert-deftest omnivox-library-apply-failed-action-preparation-does-not-consume-ticket ()
  (let ((operation (omnivox-library-apply--begin (omnivox-library-apply-test--plan))))
    (cl-letf (((symbol-function 'omnivox-library-apply--copy) (lambda (_value) (error "Copy failed"))))
      (should-error (omnivox-library-apply--action operation)))
    (should (omnivox-library-apply--action operation))))

(ert-deftest omnivox-library-apply-validates-before-issuing-actions ()
  (dolist (alter (list
                  (lambda (plan) (plist-put plan :candidate :null))
                  (lambda (plan) (plist-put plan :previous-lanes []))
                  (lambda (plan) (plist-put plan :index-sha256 "bad"))
                  (lambda (plan) (plist-put plan :eligible-voices [(:engine_id "x" :voice_id "a") (:engine_id "x" :voice_id "a")]))
                  (lambda (plan) (append plan '(:candidate :null)))))
    (should-error (omnivox-library-apply--begin (funcall alter (omnivox-library-apply-test--plan)))))
  (let ((cycle (list :cycle)))
    (setcdr cycle cycle)
    (should-error (omnivox-library-apply--copy cycle))))

(ert-deftest omnivox-library-apply-freezes-json-objects-through-completion ()
  "Empty adjustment objects survive Apply; caller mutations cannot change it."
  (require 'omnivox-library)
  (let* ((empty (make-hash-table :test #'equal))
         (objects (make-hash-table :test #'equal))
         (key (copy-sequence "adjustments"))
         (value (vector (copy-sequence "saved") empty))
         (plan (omnivox-library-apply-test--plan)))
    (puthash key value objects)
    (setf (plist-get (plist-get (aref (plist-get plan :candidate-startup) 0) :startup)
                     :registration) objects)
    (setf (plist-get (plist-get (aref (plist-get plan :previous-lanes) 0) :startup)
                     :registration) objects)
    (let ((operation (omnivox-library-apply--begin plan)))
      (aset key 0 ?X)
      (aset (aref value 0) 0 ?X)
      (puthash "changed" t empty)
      (while (not (omnivox-library-apply--operation-result operation))
        (let* ((action (omnivox-library-apply--action operation))
               (registration
                (plist-get (plist-get (aref (plist-get (plist-get action :plan)
                                                      :candidate-startup) 0) :startup)
                           :registration)))
          (should (equal (omnivox-library--json registration)
                         "{\"adjustments\":[\"saved\",{}]}"))
          (clrhash registration)
          (omnivox-library-apply-test--complete
           operation action (omnivox-library-apply-test--receipt action))))
      (should (eq (plist-get (omnivox-library-apply--operation-result operation) :status)
                  'succeeded)))))

(ert-deftest omnivox-library-apply-detects-changes-inside-json-objects ()
  "Object content equality must still reject a changed native startup receipt."
  (let* ((plan (omnivox-library-apply-test--plan))
         (objects (make-hash-table :test #'equal)))
    (puthash "voice" "AWB" objects)
    (setf (plist-get (plist-get (aref (plist-get plan :previous-lanes) 0) :startup)
                     :registration) objects)
    (let ((operation (omnivox-library-apply--begin plan)))
      (omnivox-library-apply-test--reach operation 'activating)
      (omnivox-library-apply-test--step
       operation
       (lambda (receipt _action)
         (puthash "voice" "awb"
                  (plist-get (plist-get (aref (plist-get receipt :previous-lanes) 0) :startup)
                             :registration))
         receipt))
      (should-not (eq (omnivox-library-apply--operation-phase operation) 'retire-old))
      (should (omnivox-library-apply--operation-failure operation)))))

(ert-deftest omnivox-library-apply-rejects-cycles-and-handles-inside-json-objects ()
  (let ((table (make-hash-table :test #'equal)))
    (puthash "cycle" (vector table) table)
    (should-error (omnivox-library-apply--copy table))
    (clrhash table)
    (with-temp-buffer
      (puthash "buffer" (current-buffer) table)
      (should-error (omnivox-library-apply--copy table)))))

(provide 'omnivox-library-apply-tests)
;;; omnivox-library-apply-tests.el ends here
