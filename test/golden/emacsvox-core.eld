;; Emacsvox compatibility-bridge baseline: 69e71b0b2.
;; Captured with Emacs 31 from test/scenarios/emacsvox-core-scenarios.el.
((:name forward-char :events ((stop nil) (letter "l")) :value nil
	:state
	(:text "alpha beta\n" :point 2 :mark nil :mark-active nil
	       :modified nil :kill-ring nil))
 (:name backward-char :events ((stop nil) (letter "a")) :value nil
	:state
	(:text "alpha beta\n" :point 1 :mark nil :mark-active nil
	       :modified nil :kill-ring nil))
 (:name next-line :events ((stop all) (speak (:text "second"))) :value
	nil :state
	(:text "first\nsecond\n" :point 7 :mark nil :mark-active nil
	       :modified nil :kill-ring nil))
 (:name previous-line :events ((stop all) (speak (:text "first")))
	:value nil :state
	(:text "first\nsecond\n" :point 1 :mark nil :mark-active nil
	       :modified nil :kill-ring nil))
 (:name beginning-of-buffer :events
	((message "Mark set") (icon large-movement) (stop all)
	 (speak (:text "first"))
	 (notify (:text " top " :personalities ((0 5 acss-p0-s0))) nil))
	:value nil :state
	(:text "first\nsecond\n" :point 1 :mark 9 :mark-active t
	       :modified nil :kill-ring nil))
 (:name end-of-buffer :events
	((message "Mark set") (icon large-movement) (stop all)
	 (tone 130.8 150 force)
	 (notify (:text " bottom " :personalities ((0 8 acss-p0-s0)))
		 nil))
	:value nil :state
	(:text "first\nsecond\n" :point 14 :mark 1 :mark-active t
	       :modified nil :kill-ring nil))
 (:name delete-forward-char :events ((tone 500 75 force) (letter "a"))
	:value nil :state
	(:text "bc" :point 1 :mark nil :mark-active nil :modified t
	       :kill-ring nil))
 (:name kill-word :events
	((tone 500 75 force) (speak (:text "alpha"))) :value nil
	:state
	(:text " beta" :point 1 :mark nil :mark-active nil :modified t
	       :kill-ring ("alpha")))
 (:name kill-ring-save :events
	((icon mark-object)
	 (message "region containing 1 lines copied to kill ring "))
	:value nil :state
	(:text "alpha beta" :point 1 :mark 6 :mark-active t :modified
	       nil :kill-ring ("alpha")))
 (:name newline :events ((tone 225 75 force)) :value nil :state
	(:text "alpha\n beta" :point 7 :mark nil :mark-active nil
	       :modified t :kill-ring nil))
 (:name beginning-of-visual-line :events ((icon left)) :value 1 :state
	(:text "alpha beta\n" :point 1 :mark nil :mark-active nil
	       :modified nil :kill-ring nil))
 (:name next-logical-line :events
	((stop all) (icon left)
	 (speak (:text "second" :personalities ((0 1 acss-p6-s6-r6)))))
	:value nil :state
	(:text "first\nsecond\n" :point 7 :mark nil :mark-active nil
	       :modified nil :kill-ring nil))
 (:name forward-word :events ((speak (:text "beta"))) :value t :state
	(:text "alpha beta" :point 7 :mark nil :mark-active nil
	       :modified nil :kill-ring nil))
 (:name backward-word :events ((speak (:text "beta"))) :value t :state
	(:text "alpha beta" :point 7 :mark nil :mark-active nil
	       :modified nil :kill-ring nil))
 (:name back-to-indentation :events
	((stop all) (icon tick-tick)
	 (speak (:text "  alpha" :personalities ((2 3 acss-p6-s6-r6)))))
	:value nil :state
	(:text "  alpha\n" :point 3 :mark nil :mark-active nil
	       :modified nil :kill-ring nil))
 (:name forward-sentence :events ((speak (:text "Second sentence.")))
	:value 16 :state
	(:text "First sentence.  Second sentence.  Third sentence."
	       :point 16 :mark nil :mark-active nil :modified nil
	       :kill-ring nil))
 (:name forward-paragraph :events
	((icon paragraph) (speak (:text "\nSecond paragraph.\n")))
	:value 0 :state
	(:text
	 "First paragraph.\n\nSecond paragraph.\n\nThird paragraph.\n"
	 :point 18 :mark nil :mark-active nil :modified nil :kill-ring
	 nil))
 (:name forward-list :events
	((icon large-movement) (stop all) (icon tick-tick)
	 (speak
	  (:text "(one) (two)" :personalities ((5 6 acss-p6-s6-r6)))))
	:value 6 :state
	(:text "(one) (two)" :point 6 :mark nil :mark-active nil
	       :modified nil :kill-ring nil))
 (:name forward-page :events
	((icon scroll) (speak (:text "second page\n\f"))) :value nil
	:state
	(:text "first page\n\fsecond page\n\fthird page\n" :point 13
	       :mark 26 :mark-active t :modified nil :kill-ring nil)))
