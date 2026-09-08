;;; emacsvox-aural-voice-editing-tests.el --- Voice editor proposal contracts -*- lexical-binding: t; -*-
;;; Commentary:
;; Named and physical entry paths must propose the same complete saved voice.
;;; Code:
(require 'ert)
(require 'emacsvox-aural-voice-runtime-tests)
(require 'emacsvox-aural-voice-editing)

(ert-deftest emacsvox-aural-voice-editing-legacy-alias-and-independent-conversion ()
  (emacsvox-test--with-owned-runtime
   (let* ((profile (car (plist-get emacsvox-test--voice-data-fixture :source-routing-profiles)))
          (opened (emacsvox-aural-voice-editing--snapshot 'source-child 'voice-bolden profile))
          (snapshot (plist-get opened :snapshot))
          (copy (emacsvox-aural-voice-editing--proposal
                 'source-child 'bolden snapshot 'new-editor "Editor" profile)))
     (should (eq (plist-get opened :name) 'bolden))
     (should (equal (plist-get snapshot :selectors) (plist-get (car emacsvox-aural-routing--choice-sets) :selectors)))
     (should-not (gethash 'new-editor emacsvox-aural-voice-palette-registry))
     (should-not (plist-get (plist-get copy :palette) :parent))
     (should (equal (plist-get (cdr (assq 'bolden (plist-get (plist-get copy :palette) :entries))) :style)
                    (plist-get snapshot :definition)))
     (should (equal (plist-get (car (plist-get copy :choice-sets)) :selectors)
                    (plist-get snapshot :selectors))))))

(ert-deftest emacsvox-aural-voice-editing-experiment-keeps-are-explicit-and-preserve-chain ()
  (emacsvox-test--with-owned-runtime
   (let* ((snapshot (plist-get (emacsvox-aural-voice-editing--snapshot 'reading-owned 'bolden nil) :snapshot))
          (experiment '(:definition (:family nil :average-pitch 8 :pitch-range 2 :stress 4 :richness 5)
                                    :selectors ((:kind exact :scope local :engine-id "new" :voice-id "new"))))
          (physical (emacsvox-aural-voice-editing--keep snapshot experiment 'physical 'replace))
          (adjustments (emacsvox-aural-voice-editing--keep snapshot experiment 'adjustments 'replace))
          (both (emacsvox-aural-voice-editing--keep snapshot experiment 'both 'fallback)))
     (should (equal (plist-get physical :definition) (plist-get snapshot :definition)))
     (should (equal (cdr (plist-get physical :selectors)) (cdr (plist-get snapshot :selectors))))
     (should (equal (plist-get adjustments :selectors) (plist-get snapshot :selectors)))
     (should (equal (plist-get adjustments :definition) (plist-get experiment :definition)))
     (should (equal (butlast (plist-get both :selectors)) (plist-get snapshot :selectors)))
     (should (equal (car (last (plist-get both :selectors))) (car (plist-get experiment :selectors)))))))

(ert-deftest emacsvox-aural-voice-editing-style-only-preserves-local-reference-and-raw-values ()
  (emacsvox-test--with-owned-runtime
   (let* ((snapshot (plist-get (emacsvox-aural-voice-editing--snapshot 'reading-owned 'bolden nil) :snapshot))
          (edited (emacsvox-aural-voice-editing--adjust snapshot 'reading-owned 'echo nil))
          (proposal (emacsvox-aural-voice-editing--proposal 'reading-owned 'bolden edited 'reading-owned "" nil))
          (properties (cdr (assq 'bolden (plist-get (plist-get proposal :palette) :entries)))))
     (should (= (plist-get (plist-get properties :style) :low-pass) 7))
     (should (= (plist-get (plist-get properties :style) :average-pitch) 0))
     (should (plist-member (plist-get properties :style) :echo))
     (should-not (plist-get (plist-get properties :style) :echo))
     (should (equal (plist-get properties :local-choices) "fixture-reading-bolden-1"))
     (should-not (plist-get proposal :choice-sets)))))

(ert-deftest emacsvox-aural-voice-editing-inherited-change-copies-owner-and-automatic-clears-reference ()
  (emacsvox-test--with-owned-runtime
   (puthash 'child-owned
            (emacsvox-aural-compile-voice-palette-data
             '(:schema-version 2 :id child-owned :summary "Child" :parent reading-owned :routing owned :entries nil))
            emacsvox-aural-voice-palette-registry)
   (let* ((snapshot (plist-get (emacsvox-aural-voice-editing--snapshot 'child-owned 'bolden nil) :snapshot))
          (copy (emacsvox-aural-voice-editing--proposal 'child-owned 'bolden snapshot 'child-owned "" nil))
          (set (car (plist-get copy :choice-sets))))
     (should (eq (plist-get set :palette) 'child-owned))
     (should (equal (plist-get set :selectors) (plist-get snapshot :selectors)))
     (setq snapshot (plist-put snapshot :selectors nil))
     (let* ((auto (emacsvox-aural-voice-editing--proposal 'reading-owned 'bolden snapshot 'reading-owned "" nil))
            (properties (cdr (assq 'bolden (plist-get (plist-get auto :palette) :entries)))))
       (should-not (plist-get properties :local-choices))
       (should-not (plist-get properties :choices))))))

(ert-deftest emacsvox-aural-voice-editing-preview-keeps-chain-and-neutral-effects ()
  (emacsvox-test--with-owned-runtime
   (let* ((snapshot (plist-get (emacsvox-aural-voice-editing--snapshot 'reading-owned 'bolden nil) :snapshot))
          (preview (emacsvox-aural-voice-editing--preview snapshot 'reading-owned
                                                          '(:engine-order ("dectalk") :disabled-engines ("disabled") :fallback (:engines ("eloquence"))) "Test")))
     (should (equal (plist-get preview :selectors) (plist-get snapshot :selectors)))
     (should (= (plist-get (plist-get preview :effects) :gain) 0.5))
     (should (= (plist-get (plist-get preview :effects) :pan) 0.5))
     (should (= (plist-get (plist-get preview :effects) :low-pass) (/ 7.0 9)))
     (should (= (plist-get (plist-get preview :acss) :average-pitch) 0))
     (should (= (plist-get preview :rate-offset) -4)))))

(ert-deftest emacsvox-aural-voice-editing-freezes-personality-without-registration ()
  (let ((symbol (make-symbol "test-personality")))
    (set symbol (make-acss :average-pitch 2 :richness 4))
    (cl-letf (((symbol-function 'voice-from-acss) (lambda (&rest _) (ert-fail "Inspection must not register a voice"))))
      (let* ((snapshot (emacsvox-aural-voice-editing--freeze (list :definition symbol :selectors nil) nil))
             (before (emacsvox-aural-voice-editing--style snapshot nil)))
        (set symbol (make-acss :average-pitch 9 :richness 9))
        (should (= (plist-get before :average-pitch) 2))
        (should (equal before (emacsvox-aural-voice-editing--style snapshot nil)))
        (should (eq (plist-get snapshot :definition) symbol))
        (let ((combined (emacsvox-aural-voice-editing--keep snapshot '(:definition nil) 'adjustments 'replace)))
          (should-not (plist-get (emacsvox-aural-voice-editing--style combined nil) :average-pitch)))))))

(provide 'emacsvox-aural-voice-editing-tests)
;;; emacsvox-aural-voice-editing-tests.el ends here
