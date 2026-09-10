;;; Voice editor contract examples, read as one non-evaluated data form.
;;; Independent expected outputs for the owned voice storage tests.
(:fixture-version 1 :source-palettes
		  ((:routing owned :schema-version 3 :id source-base
			     :summary "Source base" :parent
			     acss-default :entries
			     ((bolden :style
				      (:family nil :average-pitch 0
					       :pitch-range 3 :stress
					       6 :richness 9
					       :rate-offset -4 :gain 5
					       :low-pass 7 :high-pass
					       nil :pan 5 :reverb 0
					       :echo 2 :chorus 3)
				      :choices nil)
			      (annotate :personality voice-annotate
					:choices nil)))
		   (:routing owned :schema-version 3 :id source-child
			     :summary "Source child" :parent
			     source-base :entries nil))
		  :source-routing-profiles
		  ((:schema-version 2 :id dectalk-source :summary
				    "DECtalk source" :engine-order
				    ("dectalk" "eloquence")
				    :disabled-engines nil :fallback
				    (:allow-same-language t
							  :global-default
							  nil :engines
							  ("espeak")))
		   (:schema-version 2 :id eloquence-source :summary
				    "Eloquence source" :engine-order
				    ("eloquence" "dectalk")
				    :disabled-engines nil :fallback
				    (:allow-same-language t
							  :global-default
							  nil :engines
							  ("espeak"))))
		  :conversions
		  ((:source-palette source-child
				    :source-routing-profile
				    dectalk-source :expected-palette
				    (:schema-version 3 :id
						     reading-owned
						     :summary
						     "Reading" :parent
						     acss-default
						     :routing owned
						     :entries
						     ((bolden :style
							      (:family
							       nil
							       :average-pitch
							       0
							       :pitch-range
							       3
							       :stress
							       6
							       :richness
							       9
							       :rate-offset
							       -4
							       :gain 5
							       :low-pass
							       7
							       :high-pass
							       nil
							       :pan 5
							       :reverb
							       0 :echo
							       2
							       :chorus
							       3)
							      :choices
							      ((:id
								"choice-152abc69"
								:selector
								(:kind
								 properties
								 :scope
								 portable
								 :engine-id
								 "eloquence"
								 :gender
								 male)
								:adjustments
								nil))
							      :language
							      "en-AU"
							      :local-choices
							      "fixture-reading-bolden-1")
						      (annotate
						       :personality
						       voice-annotate
						       :choices nil)))
				    :expected-local-choice-sets
				    ((:choices
				      ((:id "choice-0af474d0"
					    :selector
					    (:kind exact :scope local
						   :engine-id
						   "dectalk" :voice-id
						   "Paul")
					    :adjustments nil)
				       (:id "choice-152abc69"
					    :selector
					    (:kind properties :scope
						   portable :engine-id
						   "eloquence" :gender
						   male)
					    :adjustments nil))
				      :id "fixture-reading-bolden-1"
				      :palette reading-owned :voice
				      bolden :schema-version 3)))
		   (:source-palette source-child
				    :source-routing-profile
				    eloquence-source :expected-palette
				    (:schema-version 3 :id
						     alternative-owned
						     :summary
						     "Alternative"
						     :parent
						     acss-default
						     :routing owned
						     :entries
						     ((bolden :style
							      (:family
							       nil
							       :average-pitch
							       0
							       :pitch-range
							       3
							       :stress
							       6
							       :richness
							       9
							       :rate-offset
							       -4
							       :gain 5
							       :low-pass
							       7
							       :high-pass
							       nil
							       :pan 5
							       :reverb
							       0 :echo
							       2
							       :chorus
							       3)
							      :choices
							      nil
							      :language
							      "en-AU"
							      :local-choices
							      "fixture-alternative-bolden-1")
						      (annotate
						       :personality
						       voice-annotate
						       :choices nil)))
				    :expected-local-choice-sets
				    ((:choices
				      ((:id "choice-683f9012"
					    :selector
					    (:kind exact :scope local
						   :engine-id
						   "eloquence"
						   :voice-id "Reed")
					    :adjustments nil))
				      :id
				      "fixture-alternative-bolden-1"
				      :palette alternative-owned
				      :voice bolden :schema-version 3)))))
