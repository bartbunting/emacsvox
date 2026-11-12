;; Data only. Read with evaluation disabled.
(:date "2026-11-13" :source-commit "8156ee3ea" :baseline
       "2026-11-13-speech-delivery.eld" :method
       "Three samples after assembly warmup; GC before each sample. Framing and benchmark harness are not separately warmed. Sequential runs after all test jobs. No live binding, synthesis or audio."
       :checks
       (:focused
	(:emacs31-source 459 :emacs31-compiled 459 :emacs30-source 459
			 :emacs30-compiled 459 :unexpected 0 :skipped
			 0)
	:core
	(:each-toolchain
	 (:total 1067 :passed 1049 :unexpected 0 :skipped 18))
	:bytecode (:emacs31 passed :emacs30 passed) :compiled-aural
	passed :semantic-traces 27)
       :input-sha256
       (("lisp/aural/emacsvox-aural-transport.el"
	 . "e684d19aefa9ef60d5bffa82d1c6a9ba3e41d46bfe5c4ed0cac8ad050b75b8a2")
	("lisp/aural/emacsvox-aural-replay.el"
	 . "21a843011faab5cbc0f730ba6c22f541392b250ff846948788c8169053a0c040")
	("lisp/speech/tts-lifecycle.el"
	 . "56b197edc1edd66bf014aa0899e9b14271be35cf7450aa344b067b5e898c4aad")
	("lisp/speech/tts-queue-state.el"
	 . "4a5d1703d0261223b37dcd1a98e9e8a5906897cc12f359937a31325bc3db267d")
	("lisp/speech/omnivox-parameters.el"
	 . "7fb8819f776ff609fd52893abe2b5bf8e2240b7df7cebaa0040c955518895b25")
	("test/diagnose-delivery.el"
	 . "165c5f1feb03a03b890bed22f425e7d9c52612182031273ea8c984cd249c8c95")
	("test/tts-preparation-tests.el"
	 . "084a9d9f843fdb4312df9f100eff83524b6c49066bab7c7e0c9594a3b10e32eb")
	("test/omnivox-choice-timeline-tests.el"
	 . "d5ac7f6bae27c53183315bdf9e6dd8ca4d6b3562426449bc10df21b21632dee4")
	("test/emacsvox-aural-transport-tests.el"
	 . "69b9c00861adc9b001fa0a96fff73a4331bd2a91e5234bf78b637a5fe3841884")
	("test/emacsvox-aural-replay-tests.el"
	 . "3b9ea56c06251f7d698be0b64a3d4fd8dbf35c48becde5eb5278cdb2650c2547")
	("test/omnivox-rich-tone-tests.el"
	 . "02aab948157ee4d2c2c667396c4528014c33924ef4befede740399ee7f63c398")
	("test/fixtures/delivery-assembly.eld"
	 . "db278e578cbdccb646d22205b9ce65b6d51f0208f74ca8ef94328c64f3654fc6"))
       :runs
       ((:emacs "31.0.90" :mode source :loaded-paths
		(("emacsvox-aural--build-structured-timeline"
		  . "/home/bart/src/.worktrees/emacsvox/speech-delivery/lisp/aural/emacsvox-aural-transport.el")
		 ("emacsvox-aural--assembly-span"
		  . "/home/bart/src/.worktrees/emacsvox/speech-delivery/lisp/aural/emacsvox-aural-transport.el")
		 ("emacsvox-aural--timeline-candidate"
		  . "/home/bart/src/.worktrees/emacsvox/speech-delivery/lisp/aural/emacsvox-aural-transport.el")
		 ("emacsvox-aural--bind-timeline-candidate"
		  . "/home/bart/src/.worktrees/emacsvox/speech-delivery/lisp/aural/emacsvox-aural-transport.el")
		 ("emacsvox-aural-replay--span-map"
		  . "/home/bart/src/.worktrees/emacsvox/speech-delivery/lisp/aural/emacsvox-aural-replay.el")
		 ("emacsvox-aural--submit-content"
		  . "/home/bart/src/.worktrees/emacsvox/speech-delivery/lisp/aural/emacsvox-aural-submission.el")
		 ("emacsvox-aural--frame-structured-timeline"
		  . "/home/bart/src/.worktrees/emacsvox/speech-delivery/lisp/aural/emacsvox-aural-timeline-codec.el")
		 ("tts--dispatch-write-packet"
		  . "/home/bart/src/.worktrees/emacsvox/speech-delivery/lisp/speech/tts-lifecycle.el")
		 ("tts-queue--send"
		  . "/home/bart/src/.worktrees/emacsvox/speech-delivery/lisp/speech/tts-queue-state.el")
		 ("omnivox--prepare-choice-dispatch"
		  . "/home/bart/src/.worktrees/emacsvox/speech-delivery/lisp/speech/omnivox-voices.el"))
		:observers
		((:observer normal :returned 1 :error nil
			    :timeline-writes 1 :stop-writes 0
			    :terminal-callbacks (completed)
			    :remaining-owners 0 :delivery-failure nil)
		 (:observer error :returned 1 :error nil
			    :timeline-writes 1 :stop-writes 0
			    :terminal-callbacks (completed)
			    :remaining-owners 0 :delivery-failure nil)
		 (:observer stop :returned nil :error nil
			    :timeline-writes 1 :stop-writes 1
			    :terminal-callbacks nil :remaining-owners
			    0 :delivery-failure nil))
		:readiness
		(:readiness pending :wire-bytes 0 :submission-returned
			    t :submission-complete-status completed
			    :delivery-outcome
			    (:submission-id 1 :process-name
					    "aural-native-wire-test"
					    :process-generation nil
					    :delivery-sequence nil
					    :selection no-output
					    :reason readiness-pending
					    :version nil :stage
					    capture :disposition
					    suppressed :write-status
					    not-attempted
					    :failure-reason nil))
		:resources
		((:cue-mode overlay :resource-phases
			    (capture assembly))
		 (:cue-mode insert :resource-phases (assembly)))
		:environment
		(:emacs "31.0.90" :system "x86_64-pc-linux-gnu"
			:gc-cons-threshold 800000 :gc-cons-percentage
			1.0 :allocation-units
			(conses floats vector-cells symbols
				string-chars intervals strings))
		:assembly
		((:case navigation :input-runs 1 :text-bytes 12 :spans
			1 :frames 1 :wire-bytes 357 :samples
			((:seconds 0.000232681 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (4282 6 226 0 962 0 4))
			 (:seconds 0.000319699 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (4282 6 226 0 962 0 4))
			 (:seconds 0.000228388 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (4282 6 226 0 962 0 4))))
		 (:case distinct-spans :input-runs 240 :text-bytes
			4320 :spans 240 :frames 1 :wire-bytes 50113
			:samples
			((:seconds 0.006134537 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (86260 724 2377 0 180033 0 244))
			 (:seconds 0.006702337 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (86260 724 2377 0 180033 0 244))
			 (:seconds 0.00665762 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (86260 724 2377 0 180033 0 244))))
		 (:case coalesced-runs :input-runs 240 :text-bytes
			4320 :spans 1 :frames 1 :wire-bytes 6029
			:samples
			((:seconds 0.002146304 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (27097 4 241 0 25367 0 5))
			 (:seconds 0.002404762 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (27097 4 241 0 25367 0 5))
			 (:seconds 0.002216045 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (27097 4 241 0 25367 0 5))))
		 (:case large-timeline :input-runs 4096 :text-bytes
			73728 :spans 4096 :frames 3 :wire-bytes 865663
			:samples
			((:seconds 0.12051858300000001 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (1408886 12292 37081 0 3979960 0
					    4105))
			 (:seconds 0.120848839 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (1408886 12292 37081 0 3979960 0
					    4105))
			 (:seconds 0.115601253 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (1408886 12292 37081 0 3979960 0
					    4105))))
		 (:case long-span :input-runs 1 :text-bytes 300000
			:spans 1 :frames 2 :wire-bytes 400402 :samples
			((:seconds 0.0055228410000000006 :collections
				   0 :gc-seconds 0.0
				   :allocation-count-deltas
				   (4299 6 226 0 1501299 0 7))
			 (:seconds 0.00738865 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (4299 6 226 0 1501299 0 7))
			 (:seconds 0.005403271 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (4299 6 226 0 1501299 0 7)))))
		:owned
		((:case navigation :input-runs 1 :text-bytes 12 :spans
			1 :frames 1 :wire-bytes 357 :samples
			((:seconds 0.00037362 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (5541 6 296 0 1006 0 8))
			 (:seconds 0.000597285 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (5541 6 296 0 1006 0 8))
			 (:seconds 0.000375806 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (5541 6 296 0 1006 0 8))))
		 (:case distinct-spans :input-runs 240 :text-bytes
			4320 :spans 240 :frames 1 :wire-bytes 50113
			:samples
			((:seconds 0.019179338 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (218013 724 8183 0 184757 0 487))
			 (:seconds 0.017547434 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (218013 724 8183 0 184757 0 487))
			 (:seconds 0.0147402 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (218013 724 8183 0 184757 0 487))))
		 (:case coalesced-runs :input-runs 240 :text-bytes
			4320 :spans 1 :frames 1 :wire-bytes 6029
			:samples
			((:seconds 0.0024416060000000002 :collections
				   0 :gc-seconds 0.0
				   :allocation-count-deltas
				   (28252 4 311 0 29700 0 8))
			 (:seconds 0.003199125 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (28252 4 311 0 29700 0 8))
			 (:seconds 0.002319463 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (28252 4 311 0 29700 0 8))))
		 (:case large-timeline :input-runs 4096 :text-bytes
			73728 :spans 4096 :frames 3 :wire-bytes 865663
			:samples
			((:seconds 0.240311352 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (3646015 12292 135431 0 4064901 0
					    8204))
			 (:seconds 0.239740964 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (3646015 12292 135431 0 4064901 0
					    8204))
			 (:seconds 0.241272832 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (3646015 12292 135431 0 4064901 0
					    8204))))
		 (:case long-span :input-runs 1 :text-bytes 300000
			:spans 1 :frames 2 :wire-bytes 400402 :samples
			((:seconds 0.005794827 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (5558 6 296 0 1801331 0 11))
			 (:seconds 0.005476081999999999 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (5558 6 296 0 1801331 0 11))
			 (:seconds 0.006089239 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (5558 6 296 0 1801331 0 11))))))
	(:emacs "31.0.90" :mode compiled :loaded-paths
		(("emacsvox-aural--build-structured-timeline"
		  . "/home/bart/src/.worktrees/emacsvox/speech-delivery/lisp/aural/emacsvox-aural-transport.elc")
		 ("emacsvox-aural--assembly-span"
		  . "/home/bart/src/.worktrees/emacsvox/speech-delivery/lisp/aural/emacsvox-aural-transport.elc")
		 ("emacsvox-aural--timeline-candidate"
		  . "/home/bart/src/.worktrees/emacsvox/speech-delivery/lisp/aural/emacsvox-aural-transport.elc")
		 ("emacsvox-aural--bind-timeline-candidate"
		  . "/home/bart/src/.worktrees/emacsvox/speech-delivery/lisp/aural/emacsvox-aural-transport.elc")
		 ("emacsvox-aural-replay--span-map"
		  . "/home/bart/src/.worktrees/emacsvox/speech-delivery/lisp/aural/emacsvox-aural-replay.elc")
		 ("emacsvox-aural--submit-content"
		  . "/home/bart/src/.worktrees/emacsvox/speech-delivery/lisp/aural/emacsvox-aural-submission.elc")
		 ("emacsvox-aural--frame-structured-timeline"
		  . "/home/bart/src/.worktrees/emacsvox/speech-delivery/lisp/aural/emacsvox-aural-timeline-codec.elc")
		 ("tts--dispatch-write-packet"
		  . "/home/bart/src/.worktrees/emacsvox/speech-delivery/lisp/speech/tts-lifecycle.elc")
		 ("tts-queue--send"
		  . "/home/bart/src/.worktrees/emacsvox/speech-delivery/lisp/speech/tts-queue-state.elc")
		 ("omnivox--prepare-choice-dispatch"
		  . "/home/bart/src/.worktrees/emacsvox/speech-delivery/lisp/speech/omnivox-voices.elc"))
		:observers
		((:observer normal :returned 1 :error nil
			    :timeline-writes 1 :stop-writes 0
			    :terminal-callbacks (completed)
			    :remaining-owners 0 :delivery-failure nil)
		 (:observer error :returned 1 :error nil
			    :timeline-writes 1 :stop-writes 0
			    :terminal-callbacks (completed)
			    :remaining-owners 0 :delivery-failure nil)
		 (:observer stop :returned nil :error nil
			    :timeline-writes 1 :stop-writes 1
			    :terminal-callbacks nil :remaining-owners
			    0 :delivery-failure nil))
		:readiness
		(:readiness pending :wire-bytes 0 :submission-returned
			    t :submission-complete-status completed
			    :delivery-outcome
			    (:submission-id 1 :process-name
					    "aural-native-wire-test"
					    :process-generation nil
					    :delivery-sequence nil
					    :selection no-output
					    :reason readiness-pending
					    :version nil :stage
					    capture :disposition
					    suppressed :write-status
					    not-attempted
					    :failure-reason nil))
		:resources
		((:cue-mode overlay :resource-phases
			    (capture assembly))
		 (:cue-mode insert :resource-phases (assembly)))
		:environment
		(:emacs "31.0.90" :system "x86_64-pc-linux-gnu"
			:gc-cons-threshold 800000 :gc-cons-percentage
			1.0 :allocation-units
			(conses floats vector-cells symbols
				string-chars intervals strings))
		:assembly
		((:case navigation :input-runs 1 :text-bytes 12 :spans
			1 :frames 1 :wire-bytes 357 :samples
			((:seconds 0.0017269739999999998 :collections
				   0 :gc-seconds 0.0
				   :allocation-count-deltas
				   (1536 11 935 28 27249 0 414))
			 (:seconds 0.000129763 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (409 6 215 0 962 0 4))
			 (:seconds 7.104e-05 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (409 6 215 0 962 0 4))))
		 (:case distinct-spans :input-runs 240 :text-bytes
			4320 :spans 240 :frames 1 :wire-bytes 50113
			:samples
			((:seconds 0.003149729 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (8775 724 2366 0 180033 0 244))
			 (:seconds 0.003100616 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (8775 724 2366 0 180033 0 244))
			 (:seconds 0.001568684 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (8775 724 2366 0 180033 0 244))))
		 (:case coalesced-runs :input-runs 240 :text-bytes
			4320 :spans 1 :frames 1 :wire-bytes 6029
			:samples
			((:seconds 0.000398645 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (3512 4 215 0 25367 0 5))
			 (:seconds 0.00038526299999999995 :collections
				   0 :gc-seconds 0.0
				   :allocation-count-deltas
				   (3512 4 215 0 25367 0 5))
			 (:seconds 0.000395099 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (3512 4 215 0 25367 0 5))))
		 (:case large-timeline :input-runs 4096 :text-bytes
			73728 :spans 4096 :frames 3 :wire-bytes 865663
			:samples
			((:seconds 0.029458067 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (143737 12292 37070 0 3979960 0
					   4105))
			 (:seconds 0.028042239 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (143737 12292 37070 0 3979960 0
					   4105))
			 (:seconds 0.02684707 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (143737 12292 37070 0 3979960 0
					   4105))))
		 (:case long-span :input-runs 1 :text-bytes 300000
			:spans 1 :frames 2 :wire-bytes 400402 :samples
			((:seconds 0.004978619 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (410 6 215 0 1501299 0 7))
			 (:seconds 0.004774795 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (410 6 215 0 1501299 0 7))
			 (:seconds 0.005137509 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (410 6 215 0 1501299 0 7)))))
		:owned
		((:case navigation :input-runs 1 :text-bytes 12 :spans
			1 :frames 1 :wire-bytes 357 :samples
			((:seconds 0.000100255 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (527 6 263 0 1006 0 8))
			 (:seconds 9.4169e-05 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (527 6 263 0 1006 0 8))
			 (:seconds 9.4805e-05 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (527 6 263 0 1006 0 8))))
		 (:case distinct-spans :input-runs 240 :text-bytes
			4320 :spans 240 :frames 1 :wire-bytes 50113
			:samples
			((:seconds 0.003818538 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (22277 724 6477 0 184757 0 487))
			 (:seconds 0.0027127279999999998 :collections
				   0 :gc-seconds 0.0
				   :allocation-count-deltas
				   (22277 724 6477 0 184757 0 487))
			 (:seconds 0.003668926 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (22277 724 6477 0 184757 0 487))))
		 (:case coalesced-runs :input-runs 240 :text-bytes
			4320 :spans 1 :frames 1 :wire-bytes 6029
			:samples
			((:seconds 0.00033463199999999996 :collections
				   0 :gc-seconds 0.0
				   :allocation-count-deltas
				   (3612 4 263 0 29700 0 8))
			 (:seconds 0.00031367 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (3612 4 263 0 29700 0 8))
			 (:seconds 0.000415044 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (3612 4 263 0 29700 0 8))))
		 (:case large-timeline :input-runs 4096 :text-bytes
			73728 :spans 4096 :frames 3 :wire-bytes 865663
			:samples
			((:seconds 0.046877133 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (373175 12292 106733 0 4064901 0
					   8204))
			 (:seconds 0.047239252 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (373175 12292 106733 0 4064901 0
					   8204))
			 (:seconds 0.049476561 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (373175 12292 106733 0 4064901 0
					   8204))))
		 (:case long-span :input-runs 1 :text-bytes 300000
			:spans 1 :frames 2 :wire-bytes 400402 :samples
			((:seconds 0.0059168829999999995 :collections
				   0 :gc-seconds 0.0
				   :allocation-count-deltas
				   (528 6 263 0 1801331 0 11))
			 (:seconds 0.0060647290000000005 :collections
				   0 :gc-seconds 0.0
				   :allocation-count-deltas
				   (528 6 263 0 1801331 0 11))
			 (:seconds 0.005365392 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (528 6 263 0 1801331 0 11))))))
	(:emacs "30.2" :mode source :loaded-paths
		(("emacsvox-aural--build-structured-timeline"
		  . "/home/bart/src/.worktrees/emacsvox/speech-delivery-emacs30/lisp/aural/emacsvox-aural-transport.el")
		 ("emacsvox-aural--assembly-span"
		  . "/home/bart/src/.worktrees/emacsvox/speech-delivery-emacs30/lisp/aural/emacsvox-aural-transport.el")
		 ("emacsvox-aural--timeline-candidate"
		  . "/home/bart/src/.worktrees/emacsvox/speech-delivery-emacs30/lisp/aural/emacsvox-aural-transport.el")
		 ("emacsvox-aural--bind-timeline-candidate"
		  . "/home/bart/src/.worktrees/emacsvox/speech-delivery-emacs30/lisp/aural/emacsvox-aural-transport.el")
		 ("emacsvox-aural-replay--span-map"
		  . "/home/bart/src/.worktrees/emacsvox/speech-delivery-emacs30/lisp/aural/emacsvox-aural-replay.el")
		 ("emacsvox-aural--submit-content"
		  . "/home/bart/src/.worktrees/emacsvox/speech-delivery-emacs30/lisp/aural/emacsvox-aural-submission.el")
		 ("emacsvox-aural--frame-structured-timeline"
		  . "/home/bart/src/.worktrees/emacsvox/speech-delivery-emacs30/lisp/aural/emacsvox-aural-timeline-codec.el")
		 ("tts--dispatch-write-packet"
		  . "/home/bart/src/.worktrees/emacsvox/speech-delivery-emacs30/lisp/speech/tts-lifecycle.el")
		 ("tts-queue--send"
		  . "/home/bart/src/.worktrees/emacsvox/speech-delivery-emacs30/lisp/speech/tts-queue-state.el")
		 ("omnivox--prepare-choice-dispatch"
		  . "/home/bart/src/.worktrees/emacsvox/speech-delivery-emacs30/lisp/speech/omnivox-voices.el"))
		:observers
		((:observer normal :returned 1 :error nil
			    :timeline-writes 1 :stop-writes 0
			    :terminal-callbacks (completed)
			    :remaining-owners 0 :delivery-failure nil)
		 (:observer error :returned 1 :error nil
			    :timeline-writes 1 :stop-writes 0
			    :terminal-callbacks (completed)
			    :remaining-owners 0 :delivery-failure nil)
		 (:observer stop :returned nil :error nil
			    :timeline-writes 1 :stop-writes 1
			    :terminal-callbacks nil :remaining-owners
			    0 :delivery-failure nil))
		:readiness
		(:readiness pending :wire-bytes 0 :submission-returned
			    t :submission-complete-status completed
			    :delivery-outcome
			    (:submission-id 1 :process-name
					    "aural-native-wire-test"
					    :process-generation nil
					    :delivery-sequence nil
					    :selection no-output
					    :reason readiness-pending
					    :version nil :stage
					    capture :disposition
					    suppressed :write-status
					    not-attempted
					    :failure-reason nil))
		:resources
		((:cue-mode overlay :resource-phases
			    (capture assembly))
		 (:cue-mode insert :resource-phases (assembly)))
		:environment
		(:emacs "30.2" :system "x86_64-pc-linux-gnu"
			:gc-cons-threshold 800000 :gc-cons-percentage
			1.0 :allocation-units
			(conses floats vector-cells symbols
				string-chars intervals strings))
		:assembly
		((:case navigation :input-runs 1 :text-bytes 12 :spans
			1 :frames 1 :wire-bytes 357 :samples
			((:seconds 0.000374052 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (5516 6 226 0 962 0 4))
			 (:seconds 0.00035594 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (5516 6 226 0 962 0 4))
			 (:seconds 0.000361473 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (5516 6 226 0 962 0 4))))
		 (:case distinct-spans :input-runs 240 :text-bytes
			4320 :spans 240 :frames 1 :wire-bytes 50113
			:samples
			((:seconds 0.008483518 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (110438 724 2377 0 180033 0 244))
			 (:seconds 0.010065492 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (110438 724 2377 0 180033 0 244))
			 (:seconds 0.008886862 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (110438 724 2377 0 180033 0 244))))
		 (:case coalesced-runs :input-runs 240 :text-bytes
			4320 :spans 1 :frames 1 :wire-bytes 6029
			:samples
			((:seconds 0.003638836 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (48412 4 241 0 25367 0 5))
			 (:seconds 0.0036700960000000003 :collections
				   0 :gc-seconds 0.0
				   :allocation-count-deltas
				   (48412 4 241 0 25367 0 5))
			 (:seconds 0.0029613770000000003 :collections
				   0 :gc-seconds 0.0
				   :allocation-count-deltas
				   (48412 4 241 0 25367 0 5))))
		 (:case large-timeline :input-runs 4096 :text-bytes
			73728 :spans 4096 :frames 3 :wire-bytes 865663
			:samples
			((:seconds 0.159299461 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (1803240 12292 37081 0 3979960 0
					    4105))
			 (:seconds 0.154812062 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (1803240 12292 37081 0 3979960 0
					    4105))
			 (:seconds 0.147136511 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (1803240 12292 37081 0 3979960 0
					    4105))))
		 (:case long-span :input-runs 1 :text-bytes 300000
			:spans 1 :frames 2 :wire-bytes 400402 :samples
			((:seconds 0.00600567 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (5533 6 226 0 1501299 0 7))
			 (:seconds 0.0054103350000000005 :collections
				   0 :gc-seconds 0.0
				   :allocation-count-deltas
				   (5533 6 226 0 1501299 0 7))
			 (:seconds 0.006322953 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (5533 6 226 0 1501299 0 7)))))
		:owned
		((:case navigation :input-runs 1 :text-bytes 12 :spans
			1 :frames 1 :wire-bytes 357 :samples
			((:seconds 0.00046691299999999995 :collections
				   0 :gc-seconds 0.0
				   :allocation-count-deltas
				   (6862 6 296 0 1006 0 8))
			 (:seconds 0.000490909 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (6862 6 296 0 1006 0 8))
			 (:seconds 0.000410207 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (6862 6 296 0 1006 0 8))))
		 (:case distinct-spans :input-runs 240 :text-bytes
			4320 :spans 240 :frames 1 :wire-bytes 50113
			:samples
			((:seconds 0.020574729 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (244668 724 8183 0 184757 0 487))
			 (:seconds 0.025403101 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (244668 724 8183 0 184757 0 487))
			 (:seconds 0.01647271 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (244668 724 8183 0 184757 0 487))))
		 (:case coalesced-runs :input-runs 240 :text-bytes
			4320 :spans 1 :frames 1 :wire-bytes 6029
			:samples
			((:seconds 0.004845347000000001 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (49654 4 311 0 29700 0 8))
			 (:seconds 0.00327378 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (49654 4 311 0 29700 0 8))
			 (:seconds 0.003488094 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (49654 4 311 0 29700 0 8))))
		 (:case large-timeline :input-runs 4096 :text-bytes
			73728 :spans 4096 :frames 3 :wire-bytes 865663
			:samples
			((:seconds 0.337571176 :collections 1
				   :gc-seconds 0.0694117540000001
				   :allocation-count-deltas
				   (4081407 12293 135431 0 4064901 0
					    8204))
			 (:seconds 0.28084168200000004 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (4081406 12292 135431 0 4064901 0
					    8204))
			 (:seconds 0.271200083 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (4081406 12292 135431 0 4064901 0
					    8204))))
		 (:case long-span :input-runs 1 :text-bytes 300000
			:spans 1 :frames 2 :wire-bytes 400402 :samples
			((:seconds 0.005472195 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (6879 6 296 0 1801331 0 11))
			 (:seconds 0.006770096 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (6879 6 296 0 1801331 0 11))
			 (:seconds 0.0067813 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (6879 6 296 0 1801331 0 11))))))
	(:emacs "30.2" :mode compiled :loaded-paths
		(("emacsvox-aural--build-structured-timeline"
		  . "/home/bart/src/.worktrees/emacsvox/speech-delivery-emacs30/lisp/aural/emacsvox-aural-transport.elc")
		 ("emacsvox-aural--assembly-span"
		  . "/home/bart/src/.worktrees/emacsvox/speech-delivery-emacs30/lisp/aural/emacsvox-aural-transport.elc")
		 ("emacsvox-aural--timeline-candidate"
		  . "/home/bart/src/.worktrees/emacsvox/speech-delivery-emacs30/lisp/aural/emacsvox-aural-transport.elc")
		 ("emacsvox-aural--bind-timeline-candidate"
		  . "/home/bart/src/.worktrees/emacsvox/speech-delivery-emacs30/lisp/aural/emacsvox-aural-transport.elc")
		 ("emacsvox-aural-replay--span-map"
		  . "/home/bart/src/.worktrees/emacsvox/speech-delivery-emacs30/lisp/aural/emacsvox-aural-replay.elc")
		 ("emacsvox-aural--submit-content"
		  . "/home/bart/src/.worktrees/emacsvox/speech-delivery-emacs30/lisp/aural/emacsvox-aural-submission.elc")
		 ("emacsvox-aural--frame-structured-timeline"
		  . "/home/bart/src/.worktrees/emacsvox/speech-delivery-emacs30/lisp/aural/emacsvox-aural-timeline-codec.elc")
		 ("tts--dispatch-write-packet"
		  . "/home/bart/src/.worktrees/emacsvox/speech-delivery-emacs30/lisp/speech/tts-lifecycle.elc")
		 ("tts-queue--send"
		  . "/home/bart/src/.worktrees/emacsvox/speech-delivery-emacs30/lisp/speech/tts-queue-state.elc")
		 ("omnivox--prepare-choice-dispatch"
		  . "/home/bart/src/.worktrees/emacsvox/speech-delivery-emacs30/lisp/speech/omnivox-voices.elc"))
		:observers
		((:observer normal :returned 1 :error nil
			    :timeline-writes 1 :stop-writes 0
			    :terminal-callbacks (completed)
			    :remaining-owners 0 :delivery-failure nil)
		 (:observer error :returned 1 :error nil
			    :timeline-writes 1 :stop-writes 0
			    :terminal-callbacks (completed)
			    :remaining-owners 0 :delivery-failure nil)
		 (:observer stop :returned nil :error nil
			    :timeline-writes 1 :stop-writes 1
			    :terminal-callbacks nil :remaining-owners
			    0 :delivery-failure nil))
		:readiness
		(:readiness pending :wire-bytes 0 :submission-returned
			    t :submission-complete-status completed
			    :delivery-outcome
			    (:submission-id 1 :process-name
					    "aural-native-wire-test"
					    :process-generation nil
					    :delivery-sequence nil
					    :selection no-output
					    :reason readiness-pending
					    :version nil :stage
					    capture :disposition
					    suppressed :write-status
					    not-attempted
					    :failure-reason nil))
		:resources
		((:cue-mode overlay :resource-phases
			    (capture assembly))
		 (:cue-mode insert :resource-phases (assembly)))
		:environment
		(:emacs "30.2" :system "x86_64-pc-linux-gnu"
			:gc-cons-threshold 800000 :gc-cons-percentage
			1.0 :allocation-units
			(conses floats vector-cells symbols
				string-chars intervals strings))
		:assembly
		((:case navigation :input-runs 1 :text-bytes 12 :spans
			1 :frames 1 :wire-bytes 357 :samples
			((:seconds 0.001723784 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (1576 11 876 27 26934 0 443))
			 (:seconds 5.5623e-05 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (461 6 215 0 962 0 4))
			 (:seconds 5.6256000000000005e-05 :collections
				   0 :gc-seconds 0.0
				   :allocation-count-deltas
				   (461 6 215 0 962 0 4))))
		 (:case distinct-spans :input-runs 240 :text-bytes
			4320 :spans 240 :frames 1 :wire-bytes 50113
			:samples
			((:seconds 0.0022515200000000003 :collections
				   0 :gc-seconds 0.0
				   :allocation-count-deltas
				   (8827 724 2366 0 180033 0 244))
			 (:seconds 0.001358559 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (8827 724 2366 0 180033 0 244))
			 (:seconds 0.001865565 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (8827 724 2366 0 180033 0 244))))
		 (:case coalesced-runs :input-runs 240 :text-bytes
			4320 :spans 1 :frames 1 :wire-bytes 6029
			:samples
			((:seconds 0.000623629 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (3564 4 215 0 25367 0 5))
			 (:seconds 0.000334706 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (3564 4 215 0 25367 0 5))
			 (:seconds 0.00029453199999999996 :collections
				   0 :gc-seconds 0.0
				   :allocation-count-deltas
				   (3564 4 215 0 25367 0 5))))
		 (:case large-timeline :input-runs 4096 :text-bytes
			73728 :spans 4096 :frames 3 :wire-bytes 865663
			:samples
			((:seconds 0.028883344999999998 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (143789 12292 37070 0 3979960 0
					   4105))
			 (:seconds 0.031383689 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (143789 12292 37070 0 3979960 0
					   4105))
			 (:seconds 0.030892672 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (143789 12292 37070 0 3979960 0
					   4105))))
		 (:case long-span :input-runs 1 :text-bytes 300000
			:spans 1 :frames 2 :wire-bytes 400402 :samples
			((:seconds 0.005866685 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (462 6 215 0 1501299 0 7))
			 (:seconds 0.006791287 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (462 6 215 0 1501299 0 7))
			 (:seconds 0.005040429 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (462 6 215 0 1501299 0 7)))))
		:owned
		((:case navigation :input-runs 1 :text-bytes 12 :spans
			1 :frames 1 :wire-bytes 357 :samples
			((:seconds 7.6901e-05 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (581 6 263 0 1006 0 8))
			 (:seconds 7.1686e-05 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (581 6 263 0 1006 0 8))
			 (:seconds 8.1083e-05 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (581 6 263 0 1006 0 8))))
		 (:case distinct-spans :input-runs 240 :text-bytes
			4320 :spans 240 :frames 1 :wire-bytes 50113
			:samples
			((:seconds 0.002642252 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (22331 724 6477 0 184757 0 487))
			 (:seconds 0.003077284 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (22331 724 6477 0 184757 0 487))
			 (:seconds 0.003774886 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (22331 724 6477 0 184757 0 487))))
		 (:case coalesced-runs :input-runs 240 :text-bytes
			4320 :spans 1 :frames 1 :wire-bytes 6029
			:samples
			((:seconds 0.000284732 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (3666 4 263 0 29700 0 8))
			 (:seconds 0.000336752 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (3666 4 263 0 29700 0 8))
			 (:seconds 0.000350764 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (3666 4 263 0 29700 0 8))))
		 (:case large-timeline :input-runs 4096 :text-bytes
			73728 :spans 4096 :frames 3 :wire-bytes 865663
			:samples
			((:seconds 0.048409588999999996 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (373229 12292 106733 0 4064901 0
					   8204))
			 (:seconds 0.049357977 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (373229 12292 106733 0 4064901 0
					   8204))
			 (:seconds 0.047452041 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (373229 12292 106733 0 4064901 0
					   8204))))
		 (:case long-span :input-runs 1 :text-bytes 300000
			:spans 1 :frames 2 :wire-bytes 400402 :samples
			((:seconds 0.005863607 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (582 6 263 0 1801331 0 11))
			 (:seconds 0.006444323 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (582 6 263 0 1801331 0 11))
			 (:seconds 0.006452675 :collections 0
				   :gc-seconds 0.0
				   :allocation-count-deltas
				   (582 6 263 0 1801331 0 11))))))))
