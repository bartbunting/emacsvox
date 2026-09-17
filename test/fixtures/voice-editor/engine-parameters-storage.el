(:fixture-version 1
 :status contract-only-readers-not-yet-implemented
 :expected-user-data-envelope-version 10
 :source-palette
 (:schema-version 3 :id reading :summary "Reading" :parent acss-default
  :routing owned
  :entries
  ((bolden :personality voice-bolden :language "en-US"
    :choices
    ((:id "eci-default"
      :selector (:kind engine-default :scope portable :engine-id "eloquence")
      :adjustments nil))
    :local-choices "reading-bolden-before")))
 :source-routing
 (:schema-version 3 :active-profile nil :profiles nil
  :choice-sets
  ((:schema-version 3 :id "reading-bolden-before" :palette reading :voice bolden
    :choices
    ((:id "paul-main"
      :selector (:kind exact :scope local :engine-id "dectalk" :voice-id "paul")
      :adjustments nil)
     (:id "paul-soft"
      :selector (:kind exact :scope local :engine-id "dectalk" :voice-id "paul")
      :adjustments nil)
     (:id "eci-default"
      :selector (:kind engine-default :scope portable :engine-id "eloquence")
      :adjustments nil)))))
 :expected-palette
 (:schema-version 4 :id reading :summary "Reading" :parent acss-default
  :routing owned
  :entries
  ((bolden :personality voice-bolden :language "en-US"
    :choices
    ((:id "eci-default"
      :selector (:kind engine-default :scope portable :engine-id "eloquence")
      :adjustments nil
      :native
      (:engine-id "eloquence" :schema-id "eloquence.eci-units.v1"
       :parameters (("breathiness" :op set :value 42)))))
    :local-choices "reading-bolden-after")))
 :expected-routing
 (:schema-version 4 :active-profile nil :profiles nil
  :choice-sets
  ((:schema-version 3 :id "reading-bolden-before" :palette reading :voice bolden
    :choices
    ((:id "paul-main"
      :selector (:kind exact :scope local :engine-id "dectalk" :voice-id "paul")
      :adjustments nil)
     (:id "paul-soft"
      :selector (:kind exact :scope local :engine-id "dectalk" :voice-id "paul")
      :adjustments nil)
     (:id "eci-default"
      :selector (:kind engine-default :scope portable :engine-id "eloquence")
      :adjustments nil)))
   (:schema-version 4 :id "reading-bolden-after" :palette reading :voice bolden
    :choices
    ((:id "paul-main"
      :selector (:kind exact :scope local :engine-id "dectalk" :voice-id "paul")
      :adjustments nil
      :native
      (:engine-id "dectalk" :schema-id "dectalk.design-voice.v1"
       :parameters (("sm" :op set :value 55) ("br" :op default))))
     (:id "paul-soft"
      :selector (:kind exact :scope local :engine-id "dectalk" :voice-id "paul")
      :adjustments nil
      :native
      (:engine-id "dectalk" :schema-id "dectalk.design-voice.v1"
       :parameters (("sm" :op set :value 80))))
     (:id "eci-default"
      :selector (:kind engine-default :scope portable :engine-id "eloquence")
      :adjustments nil
      :native
      (:engine-id "eloquence" :schema-id "eloquence.eci-units.v1"
       :parameters (("breathiness" :op set :value 42))))))))
 :expected-portable-palette
 (:schema-version 4 :id reading :summary "Reading" :parent acss-default
  :routing owned
  :entries
  ((bolden :personality voice-bolden :language "en-US"
    :choices
    ((:id "eci-default"
      :selector (:kind engine-default :scope portable :engine-id "eloquence")
      :adjustments nil
      :native
      (:engine-id "eloquence" :schema-id "eloquence.eci-units.v1"
       :parameters (("breathiness" :op set :value 42))))))))
 :expected-omitted-choice-ids ("paul-main" "paul-soft")
 :native-value-cases
 ((:name zero :operation (:op set :value 0) :expected-json "{\"op\":\"set\",\"value\":0}")
  (:name false :operation (:op set :value nil) :expected-json "{\"op\":\"set\",\"value\":false}")
  (:name default :operation (:op default) :expected-json "{\"op\":\"default\"}")))
