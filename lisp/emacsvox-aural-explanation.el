;;; emacsvox-aural-explanation.el --- Explain aural presentation -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox contributors
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: Emacsvox contributors
;; Maintainer: Emacsvox contributors
;; Keywords: accessibility, multimedia
;; URL: https://github.com/bartbunting/emacsvox

;; This file is part of Emacsvox.
;;
;; Emacsvox is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; Emacsvox is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with Emacsvox.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Retained and simulated presentation explanations, spoken and visual reports,
;; spatial capability inspection, concise descriptions, and training mode.

;;; Code:

(require 'cl-lib)
(require 'help-mode)
(require 'pp)
(require 'subr-x)
(require 'emacsvox-aural-ui)
(require 'emacsvox-aural-history)
(require 'emacsvox-aural-transport)
(require 'emacsvox-aural-description)
(require 'emacsvox-aural-validation)
(require 'emacsvox-aural-inspection)
(require 'emacsvox-aural-semantics)

(declare-function emacsvox-icon "emacsvox-sounds" (icon))
(declare-function emacsvox-speak-mode-line "emacsvox-speak" ())
(declare-function tts-speak "tts-speak" (text))
(declare-function tts-voice-reset-code "tts-speak" ())
(declare-function tts--protocol-queue-code "tts-speak" (code))
(declare-function tts--protocol-queue-text "tts-speak" (text))
(declare-function tts--protocol-dispatch "tts-speak" ())

(cl-defstruct
    (emacsvox-aural-explanation
     (:constructor emacsvox-aural--make-explanation))
  "Reproducible explanation of one resolved aural presentation."
  scheme facts context matching-rules render-plan concrete-plan
  suppressed-actions basis presentation-id queued-at source-location)

(defvar emacsvox-aural-explanation--last-explanation nil
  "Most recently displayed aural presentation explanation.")

(defvar emacsvox-sounds-current-pack)
(defvar emacsvox-speak-messages)
(defvar emacsvox-aural-training-mode nil
  "Non-nil when semantic training explanations are enabled.")

(defcustom emacsvox-aural-training-voice 'annotate
  "Palette-aware voice used for semantic training explanations."
  :type 'symbol
  :group 'emacsvox-aural)

(defvar emacsvox-aural-explanation--pending-training-explanations nil
  "Training explanations waiting for the current command to finish.")

(declare-function emacsvox-icon "emacsvox-sounds" (icon))
(declare-function emacsvox-speak-help "emacsvox-speak" ())
(declare-function voice-setup-get-voice-for-face "voice-setup" (face))
(declare-function emacsvox-speak-mode-line "emacsvox-speak" ())
(declare-function tts-speak "tts-speak" (text))
(declare-function tts-voice-reset-code "tts-speak" ())
(declare-function tts--protocol-queue-code "tts-speak" (code))
(declare-function tts--protocol-queue-text "tts-speak" (text))
(declare-function tts--protocol-dispatch "tts-speak" ())

(autoload 'emacsvox-aural "emacsvox-aural-home"
  "Open the spoken aural presentation home." t)

(defun emacsvox-aural-explanation--matching-rules-for-occasion
    (facts context occasion)
  "Return rules matching FACTS in CONTEXT for OCCASION."
  (let* ((context
          (emacsvox-aural-inspection-context-for-occasion
           context occasion))
         (rules (emacsvox-aural-current-rules context))
         (input (emacsvox-aural-normalize-input facts context)))
    (emacsvox-aural-matching-rules rules input)))

(defun emacsvox-aural-explanation--occasion-match-counts (facts context)
  "Return registered occasions and matching-rule counts for FACTS and CONTEXT."
  (mapcar
   (lambda (candidate)
     (let ((occasion (intern candidate)))
       (cons
        occasion
        (length
         (emacsvox-aural-explanation--matching-rules-for-occasion
          facts context occasion)))))
   (emacsvox-aural-occasion-candidates)))

(defun emacsvox-aural-explanation--best-explanation-occasion (facts context)
  "Choose the most informative presentation occasion for FACTS in CONTEXT.

Prefer the current occasion when it ties for the most matching rules."
  (let* ((current (or (plist-get context :occasion) 'continuous))
         (counts
          (emacsvox-aural-explanation--occasion-match-counts facts context))
         (best current)
         (best-count (or (alist-get current counts) 0)))
    (dolist (entry counts)
      (when (> (cdr entry) best-count)
        (setq best (car entry)
              best-count (cdr entry))))
    best))

(defun emacsvox-aural-explanation--read-explanation-input (choose-occasion)
  "Read interactive explanation input.

Infer an informative occasion unless CHOOSE-OCCASION is non-nil, in which
case prompt with the inferred occasion as the default.  A frozen concrete
plan at point always supplies its actual occasion as the initial default."
  (let* ((plan (emacsvox-aural-inspection-plan-at-point))
         (facts
          (if plan
              (copy-tree (emacsvox-aural-concrete-plan-facts plan))
            (emacsvox-aural-semantics-facts-or-read)))
         (context (emacsvox-aural-context-at-point))
         (inferred
          (if plan
              (or (plist-get context :occasion) 'continuous)
            (emacsvox-aural-explanation--best-explanation-occasion
             facts context)))
         (occasion
          (if choose-occasion
              (intern
               (completing-read
                "Explain aural occasion: "
                (emacsvox-aural-occasion-candidates)
                nil 'must-match nil nil (symbol-name inferred)))
            inferred)))
    (list
     facts
     (emacsvox-aural-inspection-context-for-occasion
      context occasion))))

(defun emacsvox-aural-explanation--interactive-explanation-input
    (choose-occasion)
  "Return exact queued input, or simulated input when CHOOSE-OCCASION."
  (let* ((interface
          (emacsvox-aural-ui-interface-buffer-p))
         (source
          (emacsvox-aural-inspection-source-buffer))
         (record
          (and
           (not choose-occasion)
           source
           (emacsvox-aural-last-presentation source))))
    (if record
        (list nil nil record)
      (when (and interface (null source))
        (user-error "No live source buffer is available"))
      (let ((input
             (if (eq source (current-buffer))
                 (emacsvox-aural-explanation--read-explanation-input
                  choose-occasion)
               (with-current-buffer source
                 (emacsvox-aural-explanation--read-explanation-input
                  choose-occasion)))))
        (append input (list nil))))))

(defun emacsvox-aural-explanation--suppressed-action-ids (rules plan)
  "Return action identifiers introduced by RULES but absent from PLAN."
  (let ((introduced
         (mapcar
          #'emacsvox-aural-action-id
          (cl-mapcan
           (lambda (rule)
             (copy-sequence (emacsvox-aural-rule-actions rule)))
           rules)))
        (retained
         (mapcar
          #'emacsvox-aural-action-id
          (append
           (emacsvox-aural-render-plan-before plan)
           (emacsvox-aural-render-plan-after plan)))))
    (cl-set-difference introduced retained :test #'eq)))

(defun emacsvox-aural-explain (facts &optional context)
  "Return a reproducible explanation for FACTS in CONTEXT."
  (let* ((context
          (copy-tree
           (or context (emacsvox-aural-capture-context))))
         (rules (emacsvox-aural-current-rules context))
         (input (emacsvox-aural-normalize-input facts context))
         (facts (emacsvox-aural-input-facts input))
         (matching (emacsvox-aural-matching-rules rules input))
         (render (emacsvox-aural-resolve-active facts context))
         (concrete (emacsvox-aural-compile-plan render facts context)))
    (emacsvox-aural--make-explanation
     :scheme emacsvox-aural-active-scheme
     :facts (copy-tree facts)
     :context context
     :matching-rules
     (mapcar
      (lambda (rule)
        (let ((aliases
               (append
                (emacsvox-aural-input-semantic-aliases input)
                (emacsvox-aural-selector-semantic-aliases
                 (emacsvox-aural-rule-selector rule)))))
          (list
           :id (emacsvox-aural-rule-id rule)
           :origin (emacsvox-aural-rule-origin rule)
           :source (emacsvox-aural-rule-source rule)
           :score (emacsvox-aural-rule-score rule input)
           :semantic-matches
           (emacsvox-aural-rule-semantic-matches rule input)
           :semantic-aliases
           (mapcar
            (lambda (alias)
              (emacsvox-aural-semantic-alias-diagnostic
               (emacsvox-aural-semantic-alias-id alias)))
            aliases))))
      matching)
     :render-plan render
     :concrete-plan concrete
     :suppressed-actions
     (emacsvox-aural-explanation--suppressed-action-ids matching render)
     :basis 'simulation)))

(defun emacsvox-aural-explain-record (record)
  "Return an explanation of retained frozen presentation RECORD."
  (unless (emacsvox-aural-presentation-record-p record)
    (user-error "Not an aural presentation record: %S" record))
  (let* ((concrete (emacsvox-aural-presentation-record-plan record))
         (render (emacsvox-aural-concrete-plan-source-plan concrete)))
    (emacsvox-aural--make-explanation
     :scheme (emacsvox-aural-concrete-plan-scheme concrete)
     :facts (copy-tree (emacsvox-aural-concrete-plan-facts concrete))
     :context (copy-tree (emacsvox-aural-concrete-plan-context concrete))
     :matching-rules
     (copy-tree (emacsvox-aural-concrete-plan-rule-provenance concrete))
     :render-plan render
     :concrete-plan concrete
     :suppressed-actions nil
     :basis
     (if
         (emacsvox-aural-presentation-record-effective-payload-truncated-p
          record)
         'retained-preview
       'exact-queued)
     :presentation-id (emacsvox-aural-presentation-record-id record)
     :queued-at (copy-tree
                 (emacsvox-aural-presentation-record-queued-at record))
     :source-location
     (list
      :buffer
      (emacsvox-aural-presentation-record-source-buffer-name record)
      :position
      (emacsvox-aural-presentation-record-source-position record)))))

(defun emacsvox-describe-aural-spatial-capabilities ()
  "Describe current spatial backends and user policy."
  (interactive)
  (with-help-window (help-buffer)
    (princ "Aural spatial capabilities\n\n")
    (princ
     (format "Backends: %S\n" (emacsvox-aural-spatial-capabilities)))
    (princ
     (format
      "Enabled: %s; speech: %s; cues: %s\n"
      emacsvox-aural-spatial-enabled
      emacsvox-aural-spatial-speech-enabled
      emacsvox-aural-spatial-cue-enabled))
    (princ (format "Final output: %s\n" emacsvox-aural-spatial-output))
    (princ
     (format
      "Maximum separation: %.3f; remapping: %S\n"
      emacsvox-aural-spatial-maximum-separation
      emacsvox-aural-spatial-remapping))
    (princ
     "\nUnsupported spatial requests remain audible at the center.\n")))

(defun emacsvox-aural-explanation-facts-description (facts context)
  "Return a concise natural-language description of FACTS in CONTEXT."
  (let* ((input (emacsvox-aural-normalize-input facts context))
         (parts
          (when-let* ((role (emacsvox-aural-input-role input)))
            (list (emacsvox-aural-humanize role)))))
    (dolist (attribute (emacsvox-aural-input-attributes input))
      (setq
       parts
       (append
        parts
        (list
         (format
          "%s %s"
          (emacsvox-aural-humanize (car attribute))
          (emacsvox-aural-humanize (cdr attribute)))))))
    (dolist (state (emacsvox-aural-input-states input))
      (setq
       parts
       (append
        parts
        (list (emacsvox-aural-humanize state)))))
    (dolist (event (emacsvox-aural-input-events input))
      (setq
       parts
       (append
        parts
        (list
         (format
          "event %s"
          (emacsvox-aural-humanize event))))))
    (dolist (face (emacsvox-aural-input-legacy-faces input))
      (setq
       parts
       (append
        parts
        (list
         (format
          "visual face %s"
          (emacsvox-aural-humanize face))))))
    (if parts
        (string-join parts ", ")
      "unclassified content")))

(defun emacsvox-aural-explanation--spoken-action (action)
  "Return a concise spoken description of concrete ACTION."
  (concat
   (pcase (emacsvox-aural-concrete-action-kind action)
     ('speech
      (format "say %s" (emacsvox-aural-concrete-action-text action)))
     ('cue
      (format
       "play the %s cue"
       (emacsvox-aural-humanize
        (emacsvox-aural-concrete-action-cue action))))
     ('pause
      (format
       "pause for %s seconds"
       (emacsvox-aural-concrete-action-duration action)))
     ('tone
      (format
       "play the %s tone %s"
       (emacsvox-aural-humanize
        (emacsvox-aural-concrete-action-tone action))
       (if
           (eq
            (emacsvox-aural-concrete-action-audio-mode action)
            'insert)
           "before speech"
         "over speech"))))
   (pcase (emacsvox-aural-concrete-action-anchor action)
     ('object " once for the object")
     ('run " for this formatting run")
     ('transition " at the presentation transition")
     (_ ""))))

(defun emacsvox-aural-explanation--spoken-content (render concrete)
  "Describe resolved content from RENDER and CONCRETE for speech."
  (let* ((style (emacsvox-aural-render-plan-content render))
         (content (emacsvox-aural-concrete-plan-content concrete))
         (voice (emacsvox-aural-content-style-voice style))
         (voice-description
          (cond
           ((emacsvox-aural-voice-style-p voice)
            (let ((preset (plist-get voice :preset))
                  dimensions)
              (dolist (dimension emacsvox-aural-voice-dimensions)
                (let ((key
                       (emacsvox-aural--voice-dimension-key dimension)))
                  (when (plist-member voice key)
                    (push
                     (format
                      "%s %s"
                      (emacsvox-aural-humanize dimension)
                      (or (plist-get voice key) "default"))
                     dimensions))))
              (string-join
               (append
                (when preset
                  (list
                   (format
                    "the %s preset"
                    (emacsvox-aural-humanize preset))))
                (nreverse dimensions))
               ", with ")))
           (voice
            (format
             "the %s voice"
             (emacsvox-aural-humanize voice)))
           (t "its existing voice")))
         (balance (emacsvox-aural-concrete-content-balance content)))
    (if (not (emacsvox-aural-concrete-content-speak content))
        "The content is suppressed"
      (concat
       "The content is spoken"
       (format " using %s" voice-description)
       (cond
        ((and (numberp balance) (< balance 0)) " on the left")
        ((and (numberp balance) (> balance 0)) " on the right")
        (t " in the center"))))))

(defun emacsvox-aural-explanation--matching-occasion-description (counts)
  "Describe nonzero occasion match COUNTS, or return nil."
  (when-let* ((matching
               (cl-remove-if-not
                (lambda (entry) (> (cdr entry) 0))
                counts)))
    (mapconcat
     (lambda (entry)
       (format
        "%s, %d %s"
        (emacsvox-aural-humanize (car entry))
        (cdr entry)
        (if (= (cdr entry) 1) "rule" "rules")))
     matching
     "; ")))

(defun emacsvox-aural-explanation--context-control
    (context key fallback)
  "Return boolean control KEY from CONTEXT, or FALLBACK when absent."
  (if (plist-member context key)
      (plist-get context key)
    fallback))

(defun emacsvox-aural-explanation--face-policy-description (context)
  "Describe frozen visual-face and compatibility controls in CONTEXT."
  (format
   (concat
    "Visual face presentation is %s. "
    "Legacy compatibility voices are %s and control only face and "
    "personality voice mapping; Voice Lock is the compatibility adapter")
   (if
       (emacsvox-aural-explanation--context-control
        context :face-presentation-enabled
        emacsvox-aural-face-presentation-enabled)
       "enabled"
     "disabled")
   (if
       (emacsvox-aural-explanation--context-control
        context :voice-lock-enabled
        (emacsvox-aural-compatibility-voice-enabled-p))
       "enabled"
     "disabled")))

(defun emacsvox-aural-explanation--spoken-explanation
    (explanation &optional occasion-counts)
  "Return a concise spoken summary of EXPLANATION.

OCCASION-COUNTS, when supplied, identifies other useful contexts when the
selected occasion has no matching rule."
  (let* ((scheme
          (or
           (emacsvox-aural-explanation-scheme explanation)
           emacsvox-aural-active-scheme))
         (facts (emacsvox-aural-explanation-facts explanation))
         (context (emacsvox-aural-explanation-context explanation))
         (rules (emacsvox-aural-explanation-matching-rules explanation))
         (render (emacsvox-aural-explanation-render-plan explanation))
         (concrete (emacsvox-aural-explanation-concrete-plan explanation))
         (voice-source
          (cdr
           (assq
            'voice
            (emacsvox-aural-content-style-provenance
             (emacsvox-aural-render-plan-content render)))))
         (before (emacsvox-aural-concrete-plan-before concrete))
         (after (emacsvox-aural-concrete-plan-after concrete))
         (faces (plist-get context :legacy-faces))
         (face-source (plist-get context :legacy-face-source))
         (occasion (plist-get context :occasion))
         (fallback-count
          (cl-loop
           for rule in rules
           sum
           (cl-count-if
            (lambda (detail)
              (> (plist-get detail :distance) 0))
            (plist-get rule :semantic-matches))))
         (alias-diagnostics
          (delete-dups
           (cl-mapcan
            (lambda (rule)
              (copy-sequence (plist-get rule :semantic-aliases)))
            rules)))
         (matching-occasions
          (emacsvox-aural-explanation--matching-occasion-description
           occasion-counts)))
    (string-join
     (delq
      nil
      (list
       "Aural explanation."
       (pcase (emacsvox-aural-explanation-basis explanation)
         ('exact-queued
          (format
           "Exact queued presentation %s."
           (emacsvox-aural-explanation-presentation-id explanation)))
         ('retained-preview
          (format
           "Bounded queued preview %s; the complete payload was not retained."
           (emacsvox-aural-explanation-presentation-id explanation)))
         (_ "Simulation using the current configuration."))
       (format
        "Compatibility baseline %s."
        (emacsvox-aural-humanize scheme))
       (format
        "%s."
        (capitalize
         (emacsvox-aural-explanation-facts-description facts context)))
       (format
        "Occasion %s."
        (emacsvox-aural-humanize occasion))
       (concat
        (emacsvox-aural-explanation--face-policy-description context)
        ".")
       (when faces
         (format
          "Captured visual %s %s, strongest first, from %s."
          (if (= (length faces) 1) "face" "faces")
          (mapconcat
           #'emacsvox-aural-humanize faces ", ")
          (emacsvox-aural-humanize
           (or face-source 'unspecified-source))))
       (if rules
           (format
            "%d %s matched. Strongest rule %s."
            (length rules)
            (if (= (length rules) 1) "rule" "rules")
             (emacsvox-aural-humanize
              (plist-get (car (last rules)) :id)))
         (concat
          "No rule matched."
          (when matching-occasions
            (format
             " Matching rules are available for %s. Use a prefix argument to choose an occasion."
             matching-occasions))))
       (when (> fallback-count 0)
         (format
          "%d semantic fallback %s used; technical details give each path."
          fallback-count
          (if (= fallback-count 1) "match was" "matches were")))
       (when alias-diagnostics
         (format
          "%d deprecated semantic %s used."
          (length alias-diagnostics)
          (if (= (length alias-diagnostics) 1) "alias was" "aliases were")))
       (when before
         (format
          "Before the content, %s."
          (mapconcat
           #'emacsvox-aural-explanation--spoken-action before ", then ")))
       (concat
        (emacsvox-aural-explanation--spoken-content render concrete)
        ".")
       (when voice-source
         (format
          "The content voice comes from %s."
          (emacsvox-aural-humanize voice-source)))
       (when after
         (format
          "After the content, %s."
          (mapconcat
           #'emacsvox-aural-explanation--spoken-action after ", then ")))
       "To change this object's voice or one of its earcons, use the remap rows in Aural Home."))
      " ")))

(defun emacsvox-aural-explanation-display
    (explanation &optional speak occasion-counts)
  "Display EXPLANATION in a help buffer.

When SPEAK is non-nil, speak a concise natural-language summary rather than
the raw diagnostic buffer.  OCCASION-COUNTS describes contexts with matches."
  (let* ((render (emacsvox-aural-explanation-render-plan explanation))
         (concrete (emacsvox-aural-explanation-concrete-plan explanation))
         (content (emacsvox-aural-concrete-plan-content concrete))
         (context (emacsvox-aural-explanation-context explanation))
         (rules (emacsvox-aural-explanation-matching-rules explanation))
         (before (emacsvox-aural-concrete-plan-before concrete))
         (after (emacsvox-aural-concrete-plan-after concrete))
         (summary
          (emacsvox-aural-explanation--spoken-explanation
           explanation occasion-counts))
         (matching-occasions
          (emacsvox-aural-explanation--matching-occasion-description
           occasion-counts)))
    (setq emacsvox-aural-explanation--last-explanation explanation)
    (with-help-window (help-buffer)
      (princ "Aural presentation explanation\n\n")
      (if
          (memq
           (emacsvox-aural-explanation-basis explanation)
           '(exact-queued retained-preview))
          (let ((location
                 (emacsvox-aural-explanation-source-location explanation)))
            (princ
             (format
              (if
                  (eq
                   (emacsvox-aural-explanation-basis explanation)
                   'exact-queued)
                  "Basis: exact queued presentation %s, submitted at %s\n"
                "Basis: bounded queued preview %s, submitted at %s; complete payload not retained\n")
              (emacsvox-aural-explanation-presentation-id explanation)
              (format-time-string
               "%Y-%m-%d %H:%M:%S"
               (emacsvox-aural-explanation-queued-at explanation))))
            (princ
             (format
              "Source: %s at position %s\n"
              (or (plist-get location :buffer) "unknown")
              (or (plist-get location :position) "unknown"))))
        (princ
         "Basis: simulation using the current configuration; this may differ from previously heard output\n"))
      (princ
       (format
        "Compatibility baseline: %s\n"
        (or
         (emacsvox-aural-explanation-scheme explanation)
         emacsvox-aural-active-scheme)))
      (princ
       (format
        "Object: %s\n"
        (emacsvox-aural-explanation-facts-description
         (emacsvox-aural-explanation-facts explanation)
         context)))
      (princ
       (format "Occasion: %s\n" (plist-get context :occasion)))
      (when-let* ((object-id
                   (emacsvox-aural-concrete-plan-object-id concrete)))
        (princ
         (format
          "Frozen object: %S; formatting run: %S; object start: %s; object end: %s\n"
          object-id
          (emacsvox-aural-concrete-plan-run-id concrete)
          (if
              (emacsvox-aural-concrete-plan-object-start-p concrete)
              "yes"
            "no")
          (if
              (emacsvox-aural-concrete-plan-object-end-p concrete)
              "yes"
            "no"))))
      (princ
       (format
        "Module: %s; mode: %s\n"
        (or (plist-get context :module) "none")
        (or (plist-get context :mode) "none")))
      (princ
       (concat
        (emacsvox-aural-explanation--face-policy-description context)
        ".\n"))
      (when-let* ((faces (plist-get context :legacy-faces)))
        (princ
         (format
          "Visual faces, strongest first: %s\n"
          (mapconcat #'symbol-name faces ", "))))
      (when-let*
          ((provenance (plist-get context :legacy-face-provenance)))
        (princ "Visual face source provenance:\n")
        (dolist (entry provenance)
          (princ
           (format
            "  %s: %s %s%s%s\n"
            (plist-get entry :face)
            (plist-get entry :source)
            (plist-get entry :property)
            (if (plist-member entry :priority)
                (format ", priority %S" (plist-get entry :priority))
              "")
            (if (plist-member entry :overlay-start)
                (format
                 ", source range %s to %s"
                 (plist-get entry :overlay-start)
                 (plist-get entry :overlay-end))
              "")))))
      (when matching-occasions
        (princ
         (format
          "Occasions with matching rules: %s\n"
          matching-occasions)))
      (princ
       "Use a prefix argument with this command to choose another occasion.\n")
      (princ "\nResolved presentation order\n\n")
      (princ "Before content:\n")
      (if before
          (dolist (action before)
            (princ
             (format
              "  %s\n"
              (emacsvox-aural-describe-concrete-action action))))
        (princ "  Nothing.\n"))
      (princ
       (format
        "\nContent: %s.\n"
        (emacsvox-aural-explanation--spoken-content render concrete)))
      (princ "After content:\n")
      (if after
          (dolist (action after)
            (princ
             (format
              "  %s\n"
              (emacsvox-aural-describe-concrete-action action))))
        (princ "  Nothing.\n"))
      (princ "\nMatching rules, weakest to strongest\n\n")
      (if rules
          (dolist (rule rules)
            (princ
             (format
              "%s, origin %s, score %S, source %S\n"
              (plist-get rule :id)
              (plist-get rule :origin)
              (plist-get rule :score)
              (plist-get rule :source)))
            (dolist (detail (plist-get rule :semantic-matches))
              (princ
               (format
                "  %s: selected %s, actual %s, fallback path %S, distance %d\n"
                (plist-get detail :kind)
                (plist-get detail :selected)
                (plist-get detail :actual)
                (plist-get detail :path)
                (plist-get detail :distance))))
            (dolist
                (diagnostic
                 (delete-dups
                  (copy-sequence
                   (plist-get rule :semantic-aliases))))
              (when diagnostic
                (princ (format "  Deprecation: %s\n" diagnostic)))))
        (princ "No presentation rule matched for this occasion.\n"))
      (princ "\nTechnical details\n\n")
      (princ
       (format "Facts: %S\n" (emacsvox-aural-explanation-facts explanation)))
      (princ
       (format
        "Context: %S\n\n"
        context))
      (princ
       (format
        (concat
         "Content: speak %s, voice command %S, balance %S (%s), "
         "volume %S (%s), "
         "provenance %S\n")
        (emacsvox-aural-concrete-content-speak content)
        (emacsvox-aural-concrete-content-voice-command content)
        (emacsvox-aural-concrete-content-balance content)
        (emacsvox-aural-concrete-content-spatial-capability content)
        (emacsvox-aural-concrete-content-requested-volume content)
        (or
         (emacsvox-aural-concrete-content-volume-capability content)
         'not-requested)
        (emacsvox-aural-content-style-provenance
         (emacsvox-aural-render-plan-content render))))
      (princ
       (format
        "Voice: requested %S, effective ACSS %S, capability %S, dimension provenance %S\n"
        (emacsvox-aural-concrete-content-voice-request content)
        (emacsvox-aural-concrete-content-voice-style content)
        (emacsvox-aural-concrete-content-voice-capability content)
        (emacsvox-aural-concrete-content-voice-provenance content)))
      (when-let* ((voice-source
                   (cdr
                    (assq
                     'voice
                     (emacsvox-aural-content-style-provenance
                      (emacsvox-aural-render-plan-content render))))))
        (princ (format "Voice source: %S\n" voice-source)))
      (when-let* ((suppressed
                   (emacsvox-aural-explanation-suppressed-actions
                    explanation)))
        (princ (format "\nSuppressed or removed actions: %S\n" suppressed)))
      (when-let* ((degradations
                   (emacsvox-aural-concrete-plan-degradations concrete)))
        (princ (format "\nBackend degradation: %S\n" degradations)))
      (princ
       (concat
        "\nTo change this object's voice, choose Remap at point from "
        "Aural Home, or run M-x emacsvox-aural-remap-voice-at-point.\n")))
    (when speak
      (when (fboundp 'emacsvox-icon)
        (emacsvox-icon 'help))
      (when (fboundp 'tts-speak)
        (tts-speak summary)))
    summary))

(defun emacsvox-explain-aural-presentation
    (&optional facts context record)
  "Explain exact queued RECORD or simulate FACTS in CONTEXT.

Interactively, use the last queued presentation for the source buffer when
available.  With a prefix argument, deliberately simulate an occasion chosen
by the user.  When no queued record is available, infer the occasion that
produces the most useful simulation.  The visual and spoken explanations
always identify whether they describe queued output or a simulation."
  (interactive
   (emacsvox-aural-explanation--interactive-explanation-input
    current-prefix-arg))
  (when (called-interactively-p 'interactive)
    (emacsvox-aural-inspection-remember-source-buffer))
  (let* ((facts
          (and
           (null record)
           (or facts (emacsvox-aural-semantics-facts-or-read))))
         (context
          (and
           (null record)
           (or context (emacsvox-aural-context-at-point))))
         (explanation
          (if record
              (emacsvox-aural-explain-record record)
            (emacsvox-aural-explain facts context)))
         (occasion-counts
          (and
           (null record)
           (called-interactively-p 'interactive)
           (emacsvox-aural-explanation--occasion-match-counts facts context))))
    (when (called-interactively-p 'interactive)
      (emacsvox-aural-explanation-display
       explanation t occasion-counts))
    explanation))


(defun emacsvox-aural-explanation--concise-explanation
    (facts context concrete-cues concrete-p)
  "Return a concise explanation of FACTS and CONTEXT.

When CONCRETE-P is non-nil, describe CONCRETE-CUES that actually survived
resolution instead of the legacy cue that initiated resolution."
  (let (parts)
    (when-let* ((role (plist-get facts :role)))
      (push (emacsvox-aural-humanize role) parts))
    (dolist
        (event
         (append
          (when-let* ((one (plist-get facts :event))) (list one))
          (copy-sequence (plist-get facts :events))))
      (push (emacsvox-aural-humanize event) parts))
    (dolist
        (state
         (append
          (when-let* ((one (plist-get facts :state))) (list one))
          (copy-sequence (plist-get facts :states))))
      (push (emacsvox-aural-humanize state) parts))
    (dolist (record (emacsvox-aural-semantics))
      (when (eq (emacsvox-aural-semantic-kind record) 'attribute)
        (let* ((id (emacsvox-aural-semantic-id record))
               (keyword (intern (format ":%s" id))))
          (when (plist-member facts keyword)
            (push
             (format
              "%s %s"
              (emacsvox-aural-humanize id)
              (emacsvox-aural-humanize
               (plist-get facts keyword)))
             parts)))))
    (if concrete-p
        (dolist (cue concrete-cues)
          (push
           (format "earcon %s" (emacsvox-aural-humanize cue))
           parts))
      (when-let* ((cue (plist-get context :legacy-cue)))
        (push
         (format "legacy cue %s" (emacsvox-aural-humanize cue))
         parts)))
    (dolist (face (plist-get context :legacy-faces))
      (push
       (format "visual face %s" (emacsvox-aural-humanize face))
       parts))
    (when-let* ((occasion (plist-get context :occasion)))
      (push
       (format "%s occasion"
               (emacsvox-aural-humanize occasion))
       parts))
    (if parts
        (concat (string-join (nreverse (delete-dups parts)) ", ") ".")
      "Unannotated content.")))

(defun emacsvox-aural-concise-explanation (facts context)
  "Return a concise spoken explanation of FACTS in CONTEXT."
  (emacsvox-aural-explanation--concise-explanation facts context nil nil))

(defun emacsvox-aural-concise-plan-explanation (plan)
  "Return a concise explanation of the presentation actually in PLAN."
  (let ((cues
         (delete-dups
          (delq
           nil
           (mapcar
            #'emacsvox-aural-concrete-action-cue
            (append
             (emacsvox-aural-concrete-plan-before plan)
             (emacsvox-aural-concrete-plan-after plan)))))))
    (emacsvox-aural-explanation--concise-explanation
     (emacsvox-aural-concrete-plan-facts plan)
     (emacsvox-aural-concrete-plan-context plan)
     cues t)))

(defun emacsvox-aural-explanation--queue-training-explanation (text)
  "Queue training explanation TEXT in the configured training voice."
  (let ((voice-command
         (emacsvox-aural-compile-voice emacsvox-aural-training-voice)))
    (unless (eq voice-command 'inaudible)
      (tts--protocol-queue-code (tts-voice-reset-code))
      (when voice-command
        (tts--protocol-queue-code voice-command))
      (tts--protocol-queue-text text)
      (tts--protocol-queue-code (tts-voice-reset-code)))))

(defun emacsvox-aural-explanation--training-command-active-p ()
  "Return non-nil while an interactive command is being presented."
  (or this-command
      (and (boundp 'real-this-command) real-this-command)))

(defun emacsvox-aural-explanation--training-presented (plan)
  "Retain a concise semantic explanation after concrete PLAN."
  (let ((text (emacsvox-aural-concise-plan-explanation plan)))
    (if (emacsvox-aural-explanation--training-command-active-p)
        (push text emacsvox-aural-explanation--pending-training-explanations)
      (emacsvox-aural-explanation--queue-training-explanation text))))

(defun emacsvox-aural-explanation--flush-training-explanations ()
  "Queue deferred training explanations after normal command feedback."
  (when emacsvox-aural-explanation--pending-training-explanations
    (let ((explanations
           (nreverse emacsvox-aural-explanation--pending-training-explanations)))
      (setq emacsvox-aural-explanation--pending-training-explanations nil)
      (dolist (text explanations)
        (emacsvox-aural-explanation--queue-training-explanation text))
      (tts--protocol-dispatch))))

(define-minor-mode emacsvox-aural-training-mode
  "Speak concise semantics after each normal aural presentation."
  :global t
  :group 'emacsvox-aural
  (if emacsvox-aural-training-mode
      (progn
        (setq emacsvox-aural-explanation--pending-training-explanations nil)
        (add-hook
         'emacsvox-aural-plan-presented-hook
         #'emacsvox-aural-explanation--training-presented)
        (add-hook
         'post-command-hook
         #'emacsvox-aural-explanation--flush-training-explanations t))
    (remove-hook
     'emacsvox-aural-plan-presented-hook
     #'emacsvox-aural-explanation--training-presented)
    (remove-hook
     'post-command-hook
     #'emacsvox-aural-explanation--flush-training-explanations)
    (setq emacsvox-aural-explanation--pending-training-explanations nil)))

;; Keep the established verb-first commands while exposing one discoverable
;; `emacsvox-aural-' command namespace.
(defalias 'emacsvox-aural-describe-spatial-capabilities
  #'emacsvox-describe-aural-spatial-capabilities)
(defalias 'emacsvox-aural-explain-presentation
  #'emacsvox-explain-aural-presentation)

(provide 'emacsvox-aural-explanation)

;;; emacsvox-aural-explanation.el ends here
