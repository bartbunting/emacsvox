;;; Per-fallback storage contract, read as one non-evaluated data form.
;;; Expected promotion and export for the storage read/write contracts.
(:fixture-version 1
 :expected-user-data-envelope-version 9
 :unchanged-parent
 (:schema-version 2 :id reading-parent :summary "Parent" :parent nil
  :routing owned
  :entries ((annotate :personality voice-annotate :choices nil)))
 :source-palette
 (:schema-version 2 :id reading :summary "Reading" :parent reading-parent
  :routing owned
  :entries
  ((bolden :style
    (:family nil :average-pitch 4 :pitch-range nil :stress nil :richness 5
     :rate-offset 2 :gain 5 :low-pass 7 :pan 5)
    :choices
    ((:kind properties :scope portable :engine-id "eloquence" :gender male))
    :language "en-AU" :local-choices "reading-bolden-before")
   (smoothen :personality voice-smoothen :choices
    ((:kind engine-default :scope portable :engine-id "espeak")))))
 :source-routing
 (:schema-version 2 :active-profile nil :profiles nil
  :choice-sets
  ((:id "reading-bolden-before" :palette reading :voice bolden
    :selectors
    ((:kind exact :scope local :engine-id "dectalk" :voice-id "Paul")
     (:kind properties :scope portable :engine-id "eloquence" :gender male)))))
 :expected-palette
 (:schema-version 3 :id reading :summary "Reading" :parent reading-parent
  :routing owned
  :entries
  ((bolden :style
    (:family nil :average-pitch 4 :pitch-range nil :stress nil :richness 5
     :rate-offset 2 :gain 5 :low-pass 7 :pan 5)
    :choices
    ((:id "eloquence-male"
      :selector (:kind properties :scope portable :engine-id "eloquence" :gender male)
      :adjustments (:richness 3 :rate-offset 0 :low-pass nil)))
    :language "en-AU" :local-choices "reading-bolden-after")
   (smoothen :personality voice-smoothen :choices
    ((:id "espeak-default"
      :selector (:kind engine-default :scope portable :engine-id "espeak")
      :adjustments nil)))))
 :expected-routing
 (:schema-version 3 :active-profile nil :profiles nil
  :choice-sets
  ((:id "reading-bolden-before" :palette reading :voice bolden
    :selectors
    ((:kind exact :scope local :engine-id "dectalk" :voice-id "Paul")
     (:kind properties :scope portable :engine-id "eloquence" :gender male)))
   (:schema-version 3 :id "reading-bolden-after" :palette reading :voice bolden
    :choices
    ((:id "dectalk-paul"
      :selector (:kind exact :scope local :engine-id "dectalk" :voice-id "Paul")
      :adjustments (:average-pitch nil :richness 7 :rate-offset 4))
     (:id "eloquence-male"
      :selector (:kind properties :scope portable :engine-id "eloquence" :gender male)
      :adjustments (:richness 3 :rate-offset 0 :low-pass nil))))))
 :expected-portable-bolden-entry
 (bolden :style
  (:family nil :average-pitch 4 :pitch-range nil :stress nil :richness 5
   :rate-offset 2 :gain 5 :low-pass 7 :pan 5)
  :choices
  ((:id "eloquence-male"
    :selector (:kind properties :scope portable :engine-id "eloquence" :gender male)
    :adjustments (:richness 3 :rate-offset 0 :low-pass nil)))
  :language "en-AU")
 :expected-export-omissions ("dectalk-paul")
 :expected-inherited-entry (annotate :personality voice-annotate :choices nil)
 :publication-failure
 (:after local-snapshot-write :before palette-write
  :expected-palette source-palette
  :expected-referenced-snapshot "reading-bolden-before"
  :retry-snapshot-id "reading-bolden-after"
  :retry-choice-ids ("dectalk-paul" "eloquence-male")))
