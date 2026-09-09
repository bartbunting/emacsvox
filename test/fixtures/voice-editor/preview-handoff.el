;;; Independent preview expectations. Read as data; never load or evaluate.
;;; Raw editor units. Expected operations are wire-shaped fragments, not requests.
(:fixture-version 1
 :voice
 (:definition (:average-pitch 3 :rate-offset 4 :echo 6)
  :choices
  ((:id "primary" :selector (:kind exact :scope local :engine-id "test" :voice-id "same")
    :adjustments (:average-pitch 9))
   (:id "soft" :selector (:kind exact :scope local :engine-id "test" :voice-id "same")
    :adjustments (:average-pitch nil :rate-offset 0 :echo 0))))
 :projection-cases
 ((:id automatic :selection automatic :context nil
   :expected-ids ("primary" "soft") :expected-context nil)
  (:id original-second-row :selection "soft" :context nil
   :expected-ids ("primary" "soft") :expected-index 1
   :expected-row-patch (:average_pitch (:op "default")
                        :rate_offset (:op "set" :value 0)
                        :echo (:op "set" :value 0.0)))
  (:id equal-to-shared-still-overrides :selection "soft" :context (:rate-offset 4)
   :expected-context (:rate_offset (:op "set" :value 4)))
  (:id contextual-acss-nil :selection "soft" :context (:average-pitch nil)
   :expected-context nil)
  (:id contextual-effect-nil :selection "soft" :context (:echo nil)
   :expected-context (:echo (:op "default")))
  (:id reordered :selection "soft" :edited-order ("soft" "primary")
   :expected-original-index 1 :expected-edited-index 0)
  (:id new-row-has-no-original :selection "new" :edited-add "new"
   :expected-compare unavailable :expected-edited-audition available))
 :lifecycle-cases
 ((:id invalid-second-half :event preflight-error :expected-writes nil)
  (:id startup-quit :event quit-before-stop :expected-owned-resources 0)
  (:id startup-stop :event public-stop-before-first-write :expected-preview-writes 0)
  (:id own-stop :event successful-private-startup-stop :expected-preview-writes 1)
  (:id stop-in-own-stop-hook :event reentrant-public-stop :expected-preview-writes 0)
  (:id supersede-in-own-stop :event newer-exact :expected-old-preview-writes 0)
  (:id supersede-in-exact-stop :event newer-complete :expected-old-preview-writes 0)
  (:id early-response :event terminal-during-write :expected-next after-write)
  (:id early-response-then-error :event write-fails-after-terminal
   :expected-next never :expected-status failed :expected-replay nil)
  (:id throw-during-send :event throw :expected-owned-resources 0 :expected-replay nil)
  (:id timeout-reentrant-callback :event callback-starts-new-preview
   :expected-order (retire-old interrupt-old notify-old start-new))
  (:id reconnect :event replacement-process :expected-next never :expected-replay nil)
  (:id notify-lane-stop :event notification-stop :expected-foreground-cancel nil)
  (:id malformed-terminal :event correlated-invalid-response :expected-status failed)
  (:id uncorrelatable-terminal :event duplicate-request-id :expected-consume-ticket nil)
  (:id changed-capture :event recapture-text-edit-undo-or-save
   :expected-current-result-update nil :expected-retain-draft t)
  (:id abandoned-view :event leave-kill-or-picker-cancel :expected-late-announcement nil)
  (:id partial-input :event unproven-boundary :expected-startup-writes nil)
  (:id queued-input :event framed-pending-queue :expected-order (own-stop preview))
  (:id overlapping-send :event heartbeat-during-preview-write
   :expected-status failed :expected-next never :expected-replay nil))
 :evidence-cases
 ((:id accepted-unconsumed :status cancelled :accepted-count 1 :last-started nil
   :expected-label accepted-start-unconfirmed)
  (:id started-then-failed :status failed :accepted-count 1 :last-started "soft"
   :expected-label partial-playback)
  (:id empty-completed :status completed :accepted-count 0 :last-started nil
   :expected-label completed-no-started-evidence)
  (:id truncated-started :status completed :accepted-count 0 :truncated t :last-started "soft"
   :expected-valid t :expected-label last-sample-started)
  (:id missing-untruncated-start :status completed :accepted-count 0 :truncated nil :last-started "soft"
   :expected-valid nil)
  (:id label-only-started :label-started "primary" :sample-started nil
   :expected-sample-label start-unconfirmed)
  (:id timeout-without-terminal :status failed :terminal nil
   :expected-label playback-unconfirmed)
  (:id duplicate-physical-rows :requested "soft" :reported "primary"
   :expected-valid nil :physical-identity-alone-sufficient nil))
 :compatibility-cases
 ((:id negotiated :bundle complete :customized t :expected-mode v2)
  (:id old-shared :bundle absent :customized nil :expected-mode v1)
  (:id old-customized-chain :bundle absent :customized t :expected-mode unavailable
   :expected-save available)
  (:id old-faithful-exact :bundle absent :selection exact :faithful t
   :expected-mode legacy-exact :expected-row-receipt nil)
  (:id old-unproved-default :bundle absent :selection exact :faithful nil
   :expected-mode unavailable :expected-save available)))
