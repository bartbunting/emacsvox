;;; omnivox-choice-timeline-tests.el --- Layered timeline projection -*- lexical-binding: t; -*-
;;; Commentary:
;; Explicit frozen snapshots exercise projection without enabling live negotiation.
;;; Code:
(require 'ert)
(require 'omnivox-choice-registration-tests)
(require 'emacsvox-aural-transport)

(defun omnivox-choice-timeline-test--registration (process)
  "Return an explicit frozen test registration for PROCESS."
  (list :registry-generation 17 :content (omnivox--process-logical-registry-content process)))

(defun omnivox-choice-timeline-test--run (request style &optional provenance text)
  "Build an independent concrete run with raw REQUEST and effective STYLE."
  (let ((text (or text "The quick brown fox.")))
    (list (emacsvox-aural--make-concrete-plan
           :object-id "one-object"
           :content (emacsvox-aural--make-concrete-content
                     :speak t :text text :voice-request request :voice-style style
                     :voice-provenance provenance)
           :context '(:icons-enabled nil)) text nil)))

(ert-deftest omnivox-choice-timeline-preserves-raw-context-through-real-compilation ()
  (omnivox-test--with-choice-registration
   (cl-letf (((symbol-function 'emacsvox-aural-active-voice-capabilities)
              (lambda () '(:adapter omnivox :dimensions (average-pitch pitch-range stress richness rate-offset echo))))
             ((symbol-function 'voice-from-acss) (lambda (_) 'generated))
             ((symbol-function 'tts-get-voice-command) (lambda (_) "[[logical_voice generated]]")))
     (let* ((request '(:preset bolden :richness 0 :average-pitch nil :rate-offset 0 :echo nil))
            (compiled (emacsvox-aural-compile-voice-style request 'reading))
            (run (omnivox-choice-timeline-test--run
                  (emacsvox-aural-compiled-voice-request compiled)
                  (emacsvox-aural-compiled-voice-style compiled)))
            (built (emacsvox-aural--build-structured-timeline
                    2 41 (list run) (omnivox-choice-timeline-test--registration speaker)))
            (span (plist-get (aref (plist-get (car built) :spans) 0) :span))
            (patch (plist-get span :context)))
       (should (equal patch '(:richness (:op "set" :value 0.0)
                              :rate_offset (:op "set" :value 0) :echo (:op "default"))))
       (should-not (plist-member patch :average_pitch))
       (should-not (plist-member span :acss))
       (should-not (plist-member span :effects))
       (should (equal (plist-get (gethash 1 (nth 2 built)) :raw-context)
                      '(:average-pitch nil :richness 0 :rate-offset 0 :echo nil)))
       (should (= (plist-get (car built) :registry_generation) 17))
       (should (emacsvox-aural--frame-structured-timeline (car built)))))))

(ert-deftest omnivox-choice-timeline-ends-legacy-effects-at-layered-boundaries ()
  (omnivox-test--with-choice-registration
   (let* ((runs (list (omnivox-choice-timeline-test--run 'unrelated '(:echo 3))
                      (omnivox-choice-timeline-test--run 'bolden '(:echo 8))
                      (omnivox-choice-timeline-test--run 'unrelated '(:echo 3))))
          (built (emacsvox-aural--build-structured-timeline
                  2 41 runs (omnivox-choice-timeline-test--registration speaker)))
          (spans (plist-get (car built) :spans)))
     (should (equal (mapcar (lambda (wrapper) (plist-get wrapper :mode)) spans)
                    '("legacy" "layered" "legacy")))
     (dolist (index '(0 2))
       (should (equal (plist-get (plist-get (plist-get (aref spans index) :span) :effects) :mode) "replace")))
     (should (hash-table-p (plist-get (plist-get (aref spans 1) :span) :context)))
     (should-not (plist-member (plist-get (aref spans 1) :span) :effects)))))

(ert-deftest omnivox-choice-timeline-speech-actions-preserve-placement-and-span-context ()
  (omnivox-test--with-choice-registration
   (let* ((run (omnivox-choice-timeline-test--run 'bolden nil))
          (plan (car run)))
     (setf (emacsvox-aural-concrete-plan-before plan)
           (list (emacsvox-aural--make-concrete-action
                  :id 'announcement :kind 'speech :text "Before"
                  :voice-request '(:preset bolden :stress 0) :balance -1
                  :voice-provenance '((stress . announcement-rule)))))
     (let* ((built (emacsvox-aural--build-structured-timeline
                    2 41 (list run) (omnivox-choice-timeline-test--registration speaker)))
            (spans (plist-get (car built) :spans))
            (context (gethash 1 (nth 2 built))))
       (should (= (length spans) 2))
       (should (= (plist-get (plist-get (plist-get (aref spans 0) :span) :placement) :pan) 0.0))
       (should (eq (plist-get (plist-get (plist-get (aref spans 1) :span) :placement) :pan) :null))
       (should (equal (plist-get context :voice-provenance) '((stress . announcement-rule))))
       (should-not (plist-member context :text))
       (should (emacsvox-aural--frame-structured-timeline (car built)))))))

(ert-deftest omnivox-choice-timeline-multipart-is-the-same-version-four-document ()
  (omnivox-test--with-choice-registration
   (let* ((text (make-string 500 ?é))
          (built (emacsvox-aural--build-structured-timeline
                  2 41 (list (omnivox-choice-timeline-test--run 'bolden nil nil text))
                  (omnivox-choice-timeline-test--registration speaker)))
          (envelope (car built))
          (single (car (emacsvox-aural--frame-structured-timeline envelope)))
          (emacsvox-aural--timeline-frame-max-bytes 128)
          (emacsvox-aural--timeline-encoded-fragment-max-bytes 172)
          (parts (emacsvox-aural--frame-structured-timeline envelope)))
     (should (> (length parts) 1))
     (cl-loop for part in parts for index from 0 do
              (let ((fields (split-string (string-trim part))))
                (should (equal (seq-take fields 4) '("emacsvox_timeline_part" "4" "2" "41")))
                (should (= (string-to-number (nth 4 fields)) index))
                (should (= (string-to-number (nth 5 fields)) (length parts)))))
     (should (equal single (format "emacsvox_timeline {%s}\n"
                                  (mapconcat (lambda (part) (nth 7 (split-string (string-trim part)))) parts "")))))))

(ert-deftest omnivox-choice-timeline-rejects-malformed-layered-fields-before-framing ()
  (omnivox-test--with-choice-registration
   (dolist (patch '(nil (:richness 0) (:richness (:op "set" :value 2))
                    (:richness (:op "default" :value 0)) (:unexpected (:op "default"))
                    (:echo (:op "default") :echo (:op "default"))))
     (let* ((built (emacsvox-aural--build-structured-timeline
                    2 41 (list (omnivox-choice-timeline-test--run 'bolden nil))
                    (omnivox-choice-timeline-test--registration speaker)))
            (span (plist-get (aref (plist-get (car built) :spans) 0) :span)))
       (setf (plist-get span :context) patch)
       (should-error (emacsvox-aural--frame-structured-timeline (car built)))))))

(ert-deftest omnivox-choice-timeline-keeps-rule-provenance-when-equal-values-cannot-be-merged ()
  (omnivox-test--with-choice-registration
   (let* ((runs (list (omnivox-choice-timeline-test--run '(:preset bolden :richness 0) '(:richness 0) '((richness . first)))
                      (omnivox-choice-timeline-test--run '(:preset bolden :richness 0) '(:richness 0) '((richness . second)))))
          (old (emacsvox-aural--build-structured-timeline 2 41 runs))
          (new (emacsvox-aural--build-structured-timeline 2 41 runs (omnivox-choice-timeline-test--registration speaker))))
     (should (= (length (plist-get (car old) :spans)) 1))
     (should (= (length (plist-get (car new) :spans)) 2))
     (should (equal (plist-get (gethash 2 (nth 2 new)) :voice-provenance) '((richness . second)))))))

(provide 'omnivox-choice-timeline-tests)
;;; omnivox-choice-timeline-tests.el ends here
