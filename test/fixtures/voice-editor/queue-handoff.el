;;; Selected A: independent expected capture/flush outcomes, not executable code.
;;; N = ordinary producer, Q = owned named queue, D = explicit dispatch.
(:fixture-version 1
 :scope complete-captures
 :cases
 ((:id queue-only :initial empty :events (Q)
   :output legacy :sequence (Q) :reason queue-only)
  (:id named-normal :initial empty :events (Q N)
   :output layered :sequence ((timeline Q N)))
  (:id named-explicit :initial empty :events (Q D)
   :output layered :sequence ((timeline Q)) :closes D)
  (:id adjacent-normal :initial empty :events (N N)
   :output structured :sequence ((timeline N N)))
  (:id unsealed-tail :initial empty :events (N Q)
   :output legacy :sequence (N ordinary-dispatch Q) :reason unsealed-tail)
  (:id sealed-tail :initial empty :events (N Q D)
   :output legacy :sequence (N ordinary-dispatch Q D) :reason multiple-flushes)
  (:id explicit-prefix :initial empty :events (Q D N)
   :output legacy :sequence (Q D N ordinary-dispatch) :reason multiple-flushes)
  (:id opaque-tail :initial empty :events (N opaque-code)
   :output legacy :sequence (N ordinary-dispatch opaque-code) :reason opaque-command)
  (:id different-rates :initial empty :events ((N :rate 100) (N :rate 200))
   :output legacy :sequence ((sync 100) N ordinary-dispatch (sync 200) N ordinary-dispatch)
   :reason state-transition)
  (:id earlier-pending :initial pending :events (Q N)
   :output legacy :sequence (Q N ordinary-dispatch) :reason cross-call-queue)
  (:id unknown-pending :initial unknown :events (Q N)
   :output legacy :sequence (Q N ordinary-dispatch) :reason unknown-queue)
  (:id stop-does-not-justify-promotion :initial pending :planned-stop t :events (Q N)
   :output legacy :sequence (Stop Q N ordinary-dispatch) :reason cross-call-queue)
  (:id tracked-explicit :initial empty :events (Q (D :callback completion :id 17))
   :output layered :sequence ((timeline Q :id 17)) :returned-id 17)
  (:id marked-explicit :initial empty :events (Q (D :callback markers :id 18))
   :output layered :sequence ((timeline Q :id 18)) :returned-id 18)
  (:id nested-tracked-normal :initial empty :events ((N :callback completion :id 19))
   :output structured :sequence ((timeline N :id 19)) :returned-id 19)
  (:id distinct-owners :initial empty
   :events ((N :callback completion :id 20) (N :callback completion :id 21))
   :output legacy :sequence (N (dispatch 20) N (dispatch 21))
   :reason multiple-owners)
  (:id separate-character :initial empty :events (N letter)
   :output legacy :sequence (N ordinary-dispatch letter) :reason opaque-command)
  (:id old-server :initial empty :bundle nil :events (Q N)
   :output legacy :sequence (Q N ordinary-dispatch) :reason old-server))
 :proof-cases
 ((:id successful-flush :before pending :effect dispatch :after empty)
  (:id successful-stop :before unknown :effect stop :after empty)
  (:id letter-keeps-queue :before pending :effect letter :after pending :serial changed)
  (:id say-keeps-queue :before pending :effect immediate-say :after pending :serial changed)
  (:id timeline-keeps-queue :before pending :effect timeline :after pending :serial unchanged)
  (:id unclassified-write :before empty :effect unknown-write :after unknown)
  (:id failed-clear :before pending :effect stop :write error :after unknown)
  (:id frame-may-be-skipped :before pending :effect (replaceable-frame dispatch)
   :after unknown)
  (:id closed-frame-from-empty :before empty :effect (replaceable-frame queue dispatch)
   :after empty)
  (:id unknown-not-cleared-by-queue :before unknown :effect queue :after unknown)
  (:id heartbeat-neutral :before empty :effect heartbeat :after empty :serial unchanged))
 :admission-cases
 ((:id queue-changed-before-stop :prepared layered :now pending
   :result abort :writes nil)
  (:id queue-changed-in-own-stop-hook :prepared layered :now pending :stop-sent t
   :result abort :writes (Stop))
  (:id neutral-nested-timeline :prepared layered :now empty :stop-sent t
   :result send :writes (Stop nested-timeline timeline))
  (:id intervening-flush-restores-empty :prepared layered :now empty :serial-changed t
   :result abort :writes nil)
  (:id intervening-letter-keeps-empty :prepared layered :now empty :serial-changed t
   :result abort :writes nil)
  (:id registration-changed :prepared layered :now empty :registry-changed t
   :result abort :writes nil)
  (:id proof-lost-during-write :prepared layered :reentrant unknown-write
   :result ambiguous-failure :queue unknown :replay nil)))
