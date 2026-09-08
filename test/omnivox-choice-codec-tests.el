;;; omnivox-choice-codec-tests.el --- Choice wire boundaries -*- lexical-binding: t; -*-
;;; Commentary:
;; Independent values exercise presence, neutral points and row identity.
;;; Code:
(require 'ert)
(require 'omnivox-voices)
(require 'omnivox-choice-codec)

(ert-deftest omnivox-choice-codec-keeps-inheritance-zero-and-default-distinct ()
  (let* ((raw '(:richness 0 :rate-offset 0 :low-pass nil :pan 5))
         (before (copy-tree raw))
         (wire (omnivox--choice-patch-json raw)))
    (should (equal wire '(:richness (:op "set" :value 0.0)
                         :rate_offset (:op "set" :value 0)
                         :low_pass (:op "default")
                         :pan (:op "set" :value 0.5))))
    (should-not (plist-member wire :stress))
    (should (equal raw before))
    (should (hash-table-p (omnivox--choice-patch-json nil)))))

(ert-deftest omnivox-choice-codec-context-nil-retains-old-acss-meaning ()
  (let ((patch '(:richness nil :rate-offset nil :echo nil :stress 0)))
    (should (equal (omnivox--choice-patch-json patch t)
                   '(:stress (:op "set" :value 0.0)
                     :rate_offset (:op "default") :echo (:op "default"))))
    (should (equal (plist-get (omnivox--choice-patch-json patch) :richness)
                   '(:op "default")))))

(ert-deftest omnivox-choice-codec-uses-the-same-contrast-and-neutral-points ()
  (let* ((omnivox-average-pitch-contrast 0.0)
         (raw '(:average-pitch 9 :gain 5 :pan 9 :low-pass 0 :high-pass 9))
         (shared (omnivox--choice-style-json raw))
         (patch (omnivox--choice-patch-json raw)))
    (should (= (plist-get (plist-get shared :acss) :average_pitch) (/ 5.0 9.0)))
    (should (= (plist-get (plist-get patch :average_pitch) :value) (/ 5.0 9.0)))
    (should (equal (plist-get shared :effects)
                   '(:gain 0.5 :low_pass 0.0 :high_pass 1.0 :pan 1.0
                     :reverb :null :echo :null :chorus :null)))))

(ert-deftest omnivox-choice-codec-completes-shared-nulls-and-rejects-ambiguity ()
  (let ((shared (omnivox--choice-shared-json '(:rate 0.0 :volume 1.0) nil nil)))
    (should (equal (plist-get shared :acss)
                   '(:rate 0.0 :average_pitch :null :pitch_range :null
                     :stress :null :richness :null :volume 1.0)))
    (should (eq (plist-get shared :rate_offset) :null)))
  (should-error (omnivox--choice-shared-json '(:rate 0) 0 nil))
  (dolist (invalid '(21 -21 1.0 t))
    (should-error (omnivox--choice-shared-json nil invalid nil)))
  (dolist (invalid '(1.01 -0.01 t "1"))
    (should-error (omnivox--choice-shared-json (list :stress invalid) nil nil))))

(ert-deftest omnivox-choice-codec-preserves-duplicate-physical-occurrences ()
  (let* ((selector '(:kind exact :scope local :engine-id "eloquence" :voice-id "Reed"))
         (rows (list (list :id "normal" :selector selector :adjustments '(:richness 0))
                     (list :id "soft" :selector selector :adjustments '(:richness nil))))
         (wire (omnivox--choice-records-json rows)))
    (should (equal (mapcar (lambda (row) (plist-get row :id)) wire) '("normal" "soft")))
    (should (equal (plist-get (aref wire 0) :selector) (plist-get (aref wire 1) :selector)))
    (should-not (equal (plist-get (aref wire 0) :adjustments)
                       (plist-get (aref wire 1) :adjustments)))
    (should-error (omnivox--choice-records-json (list (car rows) (car rows))))))

(ert-deftest omnivox-choice-codec-does-not-clamp-malformed-saved-patches ()
  (dolist (patch '((:richness 10) (:richness 0.5) (:low-pass -1)
                   (:gain 5 :gain 0) (:unknown 1) (:rate 3)))
    (should-error (omnivox--choice-patch-json patch))))

(provide 'omnivox-choice-codec-tests)
;;; omnivox-choice-codec-tests.el ends here
