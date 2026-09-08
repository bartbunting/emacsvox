;;; Voice editor contract examples, read as one non-evaluated data form.
;;; Independent expected outputs for the owned voice storage tests.
(:fixture-version 1
 :source-palettes
 ((:schema-version 1 :id source-base :summary "Source base" :parent nil
   :entries
   ((bolden :style
     (:family nil :average-pitch 0 :pitch-range 3 :stress 6 :richness 9
      :rate-offset -4 :gain 5 :low-pass 7 :high-pass nil :pan 5
      :reverb 0 :echo 2 :chorus 3))
    (annotate :personality voice-annotate)))
  (:schema-version 1 :id source-child :summary "Source child"
   :parent source-base :entries nil))
 :source-routing-profiles
 ((:schema-version 2 :id dectalk-source :summary "DECtalk source"
   :engine-order ("dectalk" "eloquence") :disabled-engines nil
   :fallback (:allow-same-language t :global-default nil :engines ("espeak"))
   :bindings
   ((:logical-voice voice-bolden :language "en-AU"
     :selectors
     ((:kind exact :scope local :engine-id "dectalk" :voice-id "Paul")
      (:kind properties :scope portable :engine-id "eloquence" :gender male)))))
  (:schema-version 2 :id eloquence-source :summary "Eloquence source"
   :engine-order ("eloquence" "dectalk") :disabled-engines nil
   :fallback (:allow-same-language t :global-default nil :engines ("espeak"))
   :bindings
   ((:logical-voice voice-bolden :language "en-AU"
     :selectors
     ((:kind exact :scope local :engine-id "eloquence" :voice-id "Reed"))))))
 :conversions
 ((:source-palette source-child :source-routing-profile dectalk-source
   :expected-palette
   (:schema-version 2 :id reading-owned :summary "Reading" :parent nil
    :routing owned
    :entries
    ((bolden :style
      (:family nil :average-pitch 0 :pitch-range 3 :stress 6 :richness 9
       :rate-offset -4 :gain 5 :low-pass 7 :high-pass nil :pan 5
       :reverb 0 :echo 2 :chorus 3)
      :choices
      ((:kind properties :scope portable :engine-id "eloquence" :gender male))
      :language "en-AU" :local-choices "fixture-reading-bolden-1")
     (annotate :personality voice-annotate :choices nil)))
   :expected-local-choice-sets
   ((:id "fixture-reading-bolden-1" :palette reading-owned :voice bolden
     :selectors
     ((:kind exact :scope local :engine-id "dectalk" :voice-id "Paul")
      (:kind properties :scope portable :engine-id "eloquence" :gender male)))))
  (:source-palette source-child :source-routing-profile eloquence-source
   :expected-palette
   (:schema-version 2 :id alternative-owned :summary "Alternative" :parent nil
    :routing owned
    :entries
    ((bolden :style
      (:family nil :average-pitch 0 :pitch-range 3 :stress 6 :richness 9
       :rate-offset -4 :gain 5 :low-pass 7 :high-pass nil :pan 5
       :reverb 0 :echo 2 :chorus 3)
      :choices nil :language "en-AU"
      :local-choices "fixture-alternative-bolden-1")
     (annotate :personality voice-annotate :choices nil)))
   :expected-local-choice-sets
   ((:id "fixture-alternative-bolden-1" :palette alternative-owned :voice bolden
     :selectors
     ((:kind exact :scope local :engine-id "eloquence" :voice-id "Reed")))))))
