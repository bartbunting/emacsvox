;; Read as data with read-eval nil. Timings do not measure audible latency.
(:schema 1
 :baseline "89acd0601ba768a0ac767ebb021959be81cf0f1d"
 :emacs-executable "/home/bart/opt/emacs-31/bin/emacs"
 :input-sha256 (
  ("test/diagnose-delivery.el" . "e2e7afb28c6647f0ab721b822277e63877a9aaf326946d465c3221477fdbdda7")
  ("test/emacsvox-aural-transport-tests.el" . "8dd02a722d5f560e670ff2a7084eb962355e3bdefae67562a3887646bf3ba58b")
  ("test/tts-preparation-tests.el" . "c7185b4bf5075143dd2c64abb4bad5c5ff4f18763cc641d2f881c5a95d2541ad")
 )
 :source
 ( :test-summary "Ran 446 tests, 446 results as expected, 0 unexpected (2026-11-13 04:09:30+1100, 16.853857 sec)"
   :loaded-paths (
    "Loaded emacsvox-aural--build-structured-timeline from /home/bart/src/.worktrees/emacsvox/speech-delivery/lisp/aural/emacsvox-aural-transport.el"
    "Loaded emacsvox-aural--submit-content from /home/bart/src/.worktrees/emacsvox/speech-delivery/lisp/aural/emacsvox-aural-submission.el"
    "Loaded emacsvox-aural--frame-structured-timeline from /home/bart/src/.worktrees/emacsvox/speech-delivery/lisp/aural/emacsvox-aural-timeline-codec.el"
    "Loaded tts--dispatch-write-packet from /home/bart/src/.worktrees/emacsvox/speech-delivery/lisp/speech/tts-lifecycle.el"
    "Loaded tts-queue--send from /home/bart/src/.worktrees/emacsvox/speech-delivery/lisp/speech/tts-queue-state.el"
    "Loaded omnivox--prepare-choice-dispatch from /home/bart/src/.worktrees/emacsvox/speech-delivery/lisp/speech/omnivox-voices.el"
   )
   :environment (:emacs "31.0.90" :system "x86_64-pc-linux-gnu" :gc-cons-threshold 800000 :gc-cons-percentage 1.0 :allocation-units (conses floats vector-cells symbols string-chars intervals strings))
   :observations (
    (:observer normal :returned 1 :error nil :timeline-writes 1 :stop-writes 0 :terminal-callbacks (completed) :remaining-owners 0 :delivery-failure nil)
    (:observer error :returned nil :error "Injected presentation observer failure" :timeline-writes 1 :stop-writes 0 :terminal-callbacks nil :remaining-owners 0 :delivery-failure nil)
    (:observer stop :returned nil :error nil :timeline-writes 1 :stop-writes 1 :terminal-callbacks nil :remaining-owners 0 :delivery-failure nil)
    (:readiness pending :wire-bytes 0 :submission-returned t :submission-complete-status completed)
    (:cue-mode overlay :resource-phases (capture assembly))
    (:cue-mode insert :resource-phases (assembly))
   )
   :measurements (
    (:case navigation :input-runs 1 :text-bytes 12 :spans 1 :frames 1 :wire-bytes 357 :samples ((:seconds 0.0005331089999999999 :collections 0 :gc-seconds 0.0 :allocation-count-deltas (5467 6 233 0 962 0 4)) (:seconds 0.000370382 :collections 0 :gc-seconds 0.0 :allocation-count-deltas (5467 6 233 0 962 0 4)) (:seconds 0.00039754 :collections 0 :gc-seconds 0.0 :allocation-count-deltas (5467 6 233 0 962 0 4))))
    (:case distinct-spans :input-runs 240 :text-bytes 4320 :spans 240 :frames 1 :wire-bytes 50113 :samples ((:seconds 0.0065427110000000005 :collections 0 :gc-seconds 0.0 :allocation-count-deltas (81709 724 2384 0 180033 0 244)) (:seconds 0.007852828 :collections 0 :gc-seconds 0.0 :allocation-count-deltas (81709 724 2384 0 180033 0 244)) (:seconds 0.006773995 :collections 0 :gc-seconds 0.0 :allocation-count-deltas (81709 724 2384 0 180033 0 244))))
    (:case coalesced-runs :input-runs 240 :text-bytes 4320 :spans 1 :frames 1 :wire-bytes 6029 :samples ((:seconds 0.002518564 :collections 0 :gc-seconds 0.0 :allocation-count-deltas (26848 4 248 0 25367 0 5)) (:seconds 0.002206012 :collections 0 :gc-seconds 0.0 :allocation-count-deltas (26848 4 248 0 25367 0 5)) (:seconds 0.002113226 :collections 0 :gc-seconds 0.0 :allocation-count-deltas (26848 4 248 0 25367 0 5))))
    (:case large-timeline :input-runs 4096 :text-bytes 73728 :spans 4096 :frames 3 :wire-bytes 865663 :samples ((:seconds 0.122282697 :collections 0 :gc-seconds 0.0 :allocation-count-deltas (1311791 12292 37088 0 3979960 0 4105)) (:seconds 0.133031479 :collections 0 :gc-seconds 0.0 :allocation-count-deltas (1311791 12292 37088 0 3979960 0 4105)) (:seconds 0.136625383 :collections 0 :gc-seconds 0.0 :allocation-count-deltas (1311791 12292 37088 0 3979960 0 4105))))
    (:case long-span :input-runs 1 :text-bytes 300000 :spans 1 :frames 2 :wire-bytes 400402 :samples ((:seconds 0.0072460960000000005 :collections 0 :gc-seconds 0.0 :allocation-count-deltas (5484 6 233 0 1501299 0 7)) (:seconds 0.0073182690000000005 :collections 0 :gc-seconds 0.0 :allocation-count-deltas (5484 6 233 0 1501299 0 7)) (:seconds 0.007302017 :collections 0 :gc-seconds 0.0 :allocation-count-deltas (5484 6 233 0 1501299 0 7))))
   ))
 :compiled
 ( :test-summary "Ran 446 tests, 446 results as expected, 0 unexpected (2026-11-13 04:10:15+1100, 4.275851 sec)"
   :loaded-paths (
    "Loaded emacsvox-aural--build-structured-timeline from /home/bart/src/.worktrees/emacsvox/speech-delivery/lisp/aural/emacsvox-aural-transport.elc"
    "Loaded emacsvox-aural--submit-content from /home/bart/src/.worktrees/emacsvox/speech-delivery/lisp/aural/emacsvox-aural-submission.elc"
    "Loaded emacsvox-aural--frame-structured-timeline from /home/bart/src/.worktrees/emacsvox/speech-delivery/lisp/aural/emacsvox-aural-timeline-codec.elc"
    "Loaded tts--dispatch-write-packet from /home/bart/src/.worktrees/emacsvox/speech-delivery/lisp/speech/tts-lifecycle.elc"
    "Loaded tts-queue--send from /home/bart/src/.worktrees/emacsvox/speech-delivery/lisp/speech/tts-queue-state.elc"
    "Loaded omnivox--prepare-choice-dispatch from /home/bart/src/.worktrees/emacsvox/speech-delivery/lisp/speech/omnivox-voices.elc"
   )
   :environment (:emacs "31.0.90" :system "x86_64-pc-linux-gnu" :gc-cons-threshold 800000 :gc-cons-percentage 1.0 :allocation-units (conses floats vector-cells symbols string-chars intervals strings))
   :observations (
    (:observer normal :returned 1 :error nil :timeline-writes 1 :stop-writes 0 :terminal-callbacks (completed) :remaining-owners 0 :delivery-failure nil)
    (:observer error :returned nil :error "Injected presentation observer failure" :timeline-writes 1 :stop-writes 0 :terminal-callbacks nil :remaining-owners 0 :delivery-failure nil)
    (:observer stop :returned nil :error nil :timeline-writes 1 :stop-writes 1 :terminal-callbacks nil :remaining-owners 0 :delivery-failure nil)
    (:readiness pending :wire-bytes 0 :submission-returned t :submission-complete-status completed)
    (:cue-mode overlay :resource-phases (capture assembly))
    (:cue-mode insert :resource-phases (assembly))
   )
   :measurements (
    (:case navigation :input-runs 1 :text-bytes 12 :spans 1 :frames 1 :wire-bytes 357 :samples ((:seconds 0.00020521500000000002 :collections 0 :gc-seconds 0.0 :allocation-count-deltas (326 6 243 0 962 0 4)) (:seconds 9.3411e-05 :collections 0 :gc-seconds 0.0 :allocation-count-deltas (326 6 243 0 962 0 4)) (:seconds 0.000136546 :collections 0 :gc-seconds 0.0 :allocation-count-deltas (326 6 243 0 962 0 4))))
    (:case distinct-spans :input-runs 240 :text-bytes 4320 :spans 240 :frames 1 :wire-bytes 50113 :samples ((:seconds 0.002122998 :collections 0 :gc-seconds 0.0 :allocation-count-deltas (8692 724 2394 0 180033 0 244)) (:seconds 0.001952287 :collections 0 :gc-seconds 0.0 :allocation-count-deltas (8692 724 2394 0 180033 0 244)) (:seconds 0.002214116 :collections 0 :gc-seconds 0.0 :allocation-count-deltas (8692 724 2394 0 180033 0 244))))
    (:case coalesced-runs :input-runs 240 :text-bytes 4320 :spans 1 :frames 1 :wire-bytes 6029 :samples ((:seconds 0.000560657 :collections 0 :gc-seconds 0.0 :allocation-count-deltas (3429 4 243 0 25367 0 5)) (:seconds 0.00036954 :collections 0 :gc-seconds 0.0 :allocation-count-deltas (3429 4 243 0 25367 0 5)) (:seconds 0.000349432 :collections 0 :gc-seconds 0.0 :allocation-count-deltas (3429 4 243 0 25367 0 5))))
    (:case large-timeline :input-runs 4096 :text-bytes 73728 :spans 4096 :frames 3 :wire-bytes 865663 :samples ((:seconds 0.026225085999999998 :collections 0 :gc-seconds 0.0 :allocation-count-deltas (143654 12292 37098 0 3979960 0 4105)) (:seconds 0.035522898000000004 :collections 0 :gc-seconds 0.0 :allocation-count-deltas (143654 12292 37098 0 3979960 0 4105)) (:seconds 0.027294330999999998 :collections 0 :gc-seconds 0.0 :allocation-count-deltas (143654 12292 37098 0 3979960 0 4105))))
    (:case long-span :input-runs 1 :text-bytes 300000 :spans 1 :frames 2 :wire-bytes 400402 :samples ((:seconds 0.006143382 :collections 0 :gc-seconds 0.0 :allocation-count-deltas (327 6 243 0 1501299 0 7)) (:seconds 0.006827274 :collections 0 :gc-seconds 0.0 :allocation-count-deltas (327 6 243 0 1501299 0 7)) (:seconds 0.005136711 :collections 0 :gc-seconds 0.0 :allocation-count-deltas (327 6 243 0 1501299 0 7))))
   ))
)
