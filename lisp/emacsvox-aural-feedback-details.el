;;; emacsvox-aural-feedback-details.el --- Review recorded feedback -*- lexical-binding: t; -*-

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

;; A stable, readable report of one retained presentation.  Semantic fields
;; group their formatting runs, and linked editors keep independent drafts.
;; Original replay uses frozen output; proposed playback uses the normal
;; planner with private rule layers and captured source context.

;;; Code:

(require 'button)
(require 'pp)
(require 'emacsvox-aural-recent-feedback)
(require 'emacsvox-aural-planner)

(declare-function emacsvox-aural-change-feedback "emacsvox-aural-change-feedback" (&optional record))
(declare-function emacsvox-aural-change-feedback--select-part "emacsvox-aural-change-feedback" (number))
(declare-function emacsvox-aural-change-feedback--rule "emacsvox-aural-change-feedback" ())
(declare-function emacsvox-aural-change-feedback-refresh "emacsvox-aural-change-feedback" (&optional id))
(defvar emacsvox-aural-change-feedback-render)
(defvar emacsvox-aural-change-feedback-scope)
(defvar emacsvox-aural-change-feedback-input)
(defvar emacsvox-aural-change-feedback-selector)
(defvar emacsvox-aural-change-feedback-part)
(defvar emacsvox-aural-change-feedback--record-input)
(defvar emacsvox-aural-change-feedback--review-buffer)
(defvar emacsvox-aural-change-feedback--review-indices)
(defvar emacsvox-aural-change-feedback--simulation)

(defvar-local emacsvox-aural-feedback-details--record nil
  "Frozen presentation retained by this report.")
(defvar-local emacsvox-aural-feedback-details--simulation nil
  "Non-nil when this report describes a simulation, not submitted speech.")
(defvar-local emacsvox-aural-feedback-details--expanded nil
  "Field indices whose content, explanation, and formatting runs are visible.")
(defvar-local emacsvox-aural-feedback-details--debug-buffer nil
  "Separate debug buffer for this report's frozen snapshot.")
(defvar-local emacsvox-aural-feedback-details--drafts nil
  "Alist from lists of run indices to live guided editor buffers.")

(defun emacsvox-aural-feedback-details--groups (record)
  "Group RECORD's consecutive runs by semantic field within each object.
Return lists of zero-based run indices in playback order."
  (let (groups key group previous)
    (cl-loop
     for plan in (emacsvox-aural-presentation-record-effective-plans record)
     for index from 0
     for facts = (emacsvox-aural-concrete-plan-facts plan)
     for context = (emacsvox-aural-concrete-plan-context plan)
     for identity = (list (emacsvox-aural-concrete-plan-object-id plan)
                          (plist-get facts :role) (plist-get facts :field-kind)
                          (plist-get context :module) (plist-get context :occasion))
     do
     (when (and group
                (or (not (equal identity key))
                    (null (car identity))
                    (emacsvox-aural-concrete-plan-object-start-p plan)
                    (emacsvox-aural-concrete-plan-object-end-p previous)))
       (push (nreverse group) groups)
       (setq group nil))
     (push index group)
     (setq key identity previous plan))
    (when group (push (nreverse group) groups))
    (nreverse groups)))

(defun emacsvox-aural-feedback-details--plan (index)
  "Return the frozen plan at INDEX in this report."
  (nth index (emacsvox-aural-presentation-record-effective-plans
              emacsvox-aural-feedback-details--record)))

(defun emacsvox-aural-feedback-details--label (indices)
  "Describe the semantic field or object containing INDICES."
  (let* ((plan (emacsvox-aural-feedback-details--plan (car indices)))
         (facts (emacsvox-aural-concrete-plan-facts plan)))
    (pcase (plist-get facts :field-kind)
      ('count "Message count")
      ((and kind (pred identity)) (capitalize (emacsvox-aural-humanize kind)))
      (_ (if (string-match-p
              "\\`[[:space:],;:]*\\'"
              (mapconcat
               (lambda (index)
                 (or (emacsvox-aural-concrete-content-text
                      (emacsvox-aural-concrete-plan-content
                       (emacsvox-aural-feedback-details--plan index))) "")) indices ""))
             "Separator"
           (capitalize (emacsvox-aural-explanation-facts-description
                        facts (emacsvox-aural-concrete-plan-context plan))))))))

(defun emacsvox-aural-feedback-details--target ()
  "Return the field or span at point, or signal a navigation error."
  (or (get-text-property (point) 'emacsvox-aural-feedback-target)
      (get-text-property (line-beginning-position) 'emacsvox-aural-feedback-target)
      (user-error "Move to a field or voice span first")))

(defun emacsvox-aural-feedback-details--complete ()
  "Require a complete retained presentation for original or proposed playback."
  (when (emacsvox-aural-presentation-record-effective-payload-truncated-p
         emacsvox-aural-feedback-details--record)
    (user-error "Only a truncated preview was retained; record a complete example first")))

(defun emacsvox-aural-feedback-details-play (&optional indices)
  "Play the recorded or simulated baseline, or only the supplied INDICES."
  (interactive)
  (emacsvox-aural-feedback-details--complete)
  (let* ((emacsvox-aural--history-recording-inhibited t)
         (runs (emacsvox-aural-presentation-record-runs emacsvox-aural-feedback-details--record)))
    (emacsvox-aural-preview-play-runs
     (if indices (mapcar (lambda (i) (nth i runs)) indices) runs))))

(defun emacsvox-aural-feedback-details-play-field ()
  "Replay the field or span at point, with its recorded voices and actions."
  (interactive)
  (emacsvox-aural-feedback-details-play (emacsvox-aural-feedback-details--target)))

(defun emacsvox-aural-feedback-details--merge-rules (rules additions)
  "Return a private RULES layer incorporating ordered ADDITIONS by identity."
  (setq rules (copy-tree rules))
  (dolist (rule additions rules)
    (let ((order (1+ (cl-loop for old in rules maximize (or (plist-get old :order) 0)
                              into maximum finally return (or maximum 0)))))
      (setq rules
            (append (cl-remove (plist-get rule :id) rules
                               :key (lambda (old) (plist-get old :id)))
                    (list (plist-put (copy-tree rule) :order order)))))))

(defun emacsvox-aural-feedback-details--proposal-runs ()
  "Compile this report with current rules and all of its linked drafts."
  (emacsvox-aural-feedback-details--complete)
  (let (personal session buffer-rules)
    (dolist (entry (reverse emacsvox-aural-feedback-details--drafts))
      (when (buffer-live-p (cdr entry))
        (with-current-buffer (cdr entry)
          (when emacsvox-aural-change-feedback-render
            (let ((rule (emacsvox-aural-change-feedback--rule)))
              (pcase emacsvox-aural-change-feedback-scope
                ('personal (push rule personal))
                ('session (push rule session))
                (_ (push (cons (plist-get emacsvox-aural-change-feedback-input :context) rule)
                         buffer-rules))))))))
    (unless (or personal session buffer-rules)
      (user-error "Choose a field change before previewing the proposal"))
    (let ((emacsvox-aural-user-rules
           (emacsvox-aural-feedback-details--merge-rules emacsvox-aural-user-rules (nreverse personal)))
          (emacsvox-aural-session-rules
           (emacsvox-aural-feedback-details--merge-rules emacsvox-aural-session-rules (nreverse session)))
          (emacsvox-aural--current-rules-cache (make-hash-table :test #'equal)))
      (emacsvox-aural-replan-runs
       (emacsvox-aural-presentation-record-runs emacsvox-aural-feedback-details--record)
       (lambda (context)
         (let ((applicable
                (cl-loop for (origin . rule) in (reverse buffer-rules)
                         when (and (equal (plist-get origin :source-buffer-id)
                                          (plist-get context :source-buffer-id))
                                   (equal (plist-get origin :source-buffer-name)
                                          (plist-get context :source-buffer-name)))
                         collect rule)))
           (plist-put context :buffer-rules
                      (emacsvox-aural-feedback-details--merge-rules
                       (plist-get context :buffer-rules) applicable))))))))

(defun emacsvox-aural-feedback-details-preview (&optional indices)
  "Preview all linked changes in the whole presentation, or only INDICES."
  (interactive)
  (let ((runs (emacsvox-aural-feedback-details--proposal-runs))
        (emacsvox-aural--history-recording-inhibited t))
    (emacsvox-aural-preview-play-runs
     (if indices (mapcar (lambda (i) (nth i runs)) indices) runs))
    (emacsvox-aural-preview-message "Proposed feedback: current rules plus draft changes")))

(defun emacsvox-aural-feedback-details-change ()
  "Open or resume a guided change to the field or span at point."
  (interactive)
  (emacsvox-aural-feedback-details--complete)
  (require 'emacsvox-aural-change-feedback)
  (let* ((indices (emacsvox-aural-feedback-details--target))
         (origin (current-buffer))
         (window (selected-window))
         (position (copy-marker (point)))
         (record emacsvox-aural-feedback-details--record)
         (simulation emacsvox-aural-feedback-details--simulation)
         (label (emacsvox-aural-feedback-details--label indices))
         (plan (emacsvox-aural-feedback-details--plan (car indices)))
         (facts (emacsvox-aural-concrete-plan-facts plan))
         (context (emacsvox-aural-concrete-plan-context plan))
         (group (cl-find-if (lambda (g) (memq (car indices) g))
                            (emacsvox-aural-feedback-details--groups record)))
         (spanp (not (equal indices group)))
         (face (cl-find-if
                (lambda (candidate)
                  (equal indices
                         (cl-remove-if-not
                          (lambda (index)
                            (memq candidate
                                  (plist-get (emacsvox-aural-concrete-plan-context
                                              (emacsvox-aural-feedback-details--plan index))
                                             :legacy-faces))) group)))
                (plist-get context :legacy-faces)))
         (personality (plist-get context :legacy-personality))
         (distinct-personality
          (and personality (symbolp personality)
               (equal indices
                      (cl-remove-if-not
                       (lambda (index)
                         (eq personality
                             (plist-get (emacsvox-aural-concrete-plan-context
                                         (emacsvox-aural-feedback-details--plan index))
                                        :legacy-personality))) group))))
         (editor (cdr (assoc indices emacsvox-aural-feedback-details--drafts))))
    (when (and spanp (not (or face distinct-personality)))
      (user-error "No face or explicit voice distinguishes just this span; change its semantic field instead"))
    (when spanp (setq label (format "%s, span %d" label (1+ (car indices)))))
    (unless (buffer-live-p editor)
      (let ((emacsvox-aural-ui--inhibit-opening-feedback t))
        (setq editor (emacsvox-aural-change-feedback record)))
      (with-current-buffer editor
        (let ((emacsvox-aural-ui--inhibit-opening-feedback t))
          (emacsvox-aural-change-feedback--select-part (1+ (car indices))))
        ;; Component choices describe the outer field boundaries.  Its final
        ;; action may live on a later formatting run than its opening voice.
        (let* ((plans (emacsvox-aural-presentation-record-effective-plans record))
               (field (copy-emacsvox-aural-concrete-plan plan)))
          (setf (emacsvox-aural-concrete-plan-after field)
                (emacsvox-aural-concrete-plan-after (nth (car (last indices)) plans)))
          (setq emacsvox-aural-change-feedback-input
                (plist-put emacsvox-aural-change-feedback-input :concrete field)))
        (setq emacsvox-aural-change-feedback--record-input nil
              emacsvox-aural-change-feedback-part (concat ", " label)
              emacsvox-aural-change-feedback--review-buffer origin
              emacsvox-aural-change-feedback--simulation simulation
              emacsvox-aural-change-feedback--review-indices indices
              emacsvox-aural-change-feedback-selector
              (append (when-let* ((role (plist-get facts :role))) (list :role role))
                      (when-let* ((field (plist-get facts :field-kind))) (list :field-kind field))
                      (when-let* ((module (plist-get context :module))) (list :module module))
                      (when-let* ((mode (plist-get context :mode))) (list :mode mode))
                      (when-let* ((occasion (plist-get context :occasion))) (list :occasion occasion))
                      (when (and (not spanp) (not (plist-get facts :role))
                                 (not (plist-get facts :field-kind))
                                 (plist-get context :legacy-faces))
                        (list :legacy-face (car (plist-get context :legacy-faces))))
                      (when spanp
                        (if face (list :legacy-face face)
                          (list :legacy-personality personality)))))
        (emacsvox-aural-change-feedback-refresh 'change))
      (with-current-buffer origin
        (push (cons indices editor) emacsvox-aural-feedback-details--drafts)))
    (with-current-buffer editor
      (when (markerp emacsvox-aural-ui-help-origin-position)
        (set-marker emacsvox-aural-ui-help-origin-position nil))
      (setq emacsvox-aural-ui-help-origin-buffer origin
            emacsvox-aural-ui-help-origin-window window
            emacsvox-aural-ui-help-origin-position position))
    (emacsvox-aural-ui--pop-to-buffer
     editor (lambda () (emacsvox-aural-ui-speak
                        (concat "Change " label ". P previews this field; V previews the whole presentation."))))))

(defun emacsvox-aural-feedback-details--button (label command)
  "Insert a LABEL button invoking COMMAND without a mouse dependency."
  (insert-text-button label 'follow-link t
                      'action (lambda (_) (call-interactively command))))

(defun emacsvox-aural-feedback-details--heading (text)
  "Insert a navigable heading containing TEXT."
  (insert (propertize (concat text "\n") 'face 'bold
                      'emacsvox-aural-feedback-heading t)))

(defun emacsvox-aural-feedback-details--insert-content (indices)
  "Insert the recorded content at INDICES with its frozen voices."
  (dolist (index indices)
    (let* ((plan (emacsvox-aural-feedback-details--plan index))
           (content (emacsvox-aural-concrete-plan-content plan)))
      (insert (propertize (or (emacsvox-aural-concrete-content-text content) "")
                          'emacsvox-aural-recent-feedback-voice content)))))

(defun emacsvox-aural-feedback-details-toggle ()
  "Expand or collapse the selected field, including its voice spans."
  (interactive)
  (let* ((target (emacsvox-aural-feedback-details--target))
         (indices (cl-find-if
                   (lambda (group) (memq (car target) group))
                   (emacsvox-aural-feedback-details--groups emacsvox-aural-feedback-details--record))))
    (if (member indices emacsvox-aural-feedback-details--expanded)
        (setq emacsvox-aural-feedback-details--expanded
              (delete indices emacsvox-aural-feedback-details--expanded))
      (push indices emacsvox-aural-feedback-details--expanded))
    ;; Collapsing from a child span returns to the containing field.
    (emacsvox-aural-feedback-details--render indices)
    (emacsvox-aural-ui--announce-expansion
     (member indices emacsvox-aural-feedback-details--expanded)
     (buffer-substring (line-beginning-position) (line-end-position)))))

(defun emacsvox-aural-feedback-details--source-description (source plan)
  "Describe a winning SOURCE in frozen PLAN without consulting current rules."
  (pcase source
    ('face "the visual face")
    ((or 'personality 'personality-property 'legacy-personality) "the text's voice annotation")
    ('nil "the default presentation")
    (_ (pcase (plist-get (cl-find source (emacsvox-aural-concrete-plan-rule-provenance plan)
                                 :key (lambda (entry) (plist-get entry :id))) :origin)
         ('user "your personal override")
         ('session "your session override")
         ('buffer "your buffer override")
         ('scheme "the presentation scheme")
         ('fragment "a presentation fragment")
         ('module "the integration's presentation rule")
         ('core "the default presentation rule")
         (_ "a recorded presentation rule")))))

(defun emacsvox-aural-feedback-details--action-description (action)
  "Describe ACTION for ordinary review, keeping raw identifiers in debug output."
  (pcase (emacsvox-aural-concrete-action-kind action)
    ('cue (format "earcon %s" (emacsvox-aural-humanize (emacsvox-aural-concrete-action-cue action))))
    ('speech (format "say %S%s" (emacsvox-aural-concrete-action-text action)
                     (if-let* ((voice (emacsvox-aural-concrete-action-voice-request action)))
                         (format " using %s" (emacsvox-aural-humanize voice)) "")))
    ('pause (format "pause %s ms" (emacsvox-aural-concrete-action-duration action)))
    ('tone (format "tone at %s Hz for %s ms" (emacsvox-aural-concrete-action-pitch action)
                   (emacsvox-aural-concrete-action-duration action)))
    (_ "recorded action")))

(defun emacsvox-aural-feedback-details--limitation (diagnostic)
  "Describe a captured DIAGNOSTIC briefly without dumping backend metadata."
  (pcase (plist-get diagnostic :reason)
    ((or 'unsupported-voice-dimension 'unavailable-voice-family)
     (format "%s could not use the requested %s %s."
             (emacsvox-aural-humanize (or (plist-get diagnostic :adapter) 'backend))
             (emacsvox-aural-humanize (plist-get diagnostic :dimension))
             (plist-get diagnostic :requested)))
    ('unknown-voice (format "Voice %s was unavailable." (plist-get diagnostic :requested)))
    (_ (concat (capitalize (emacsvox-aural-humanize (plist-get diagnostic :reason)))
               ". See Debug details for the captured values."))))

(defun emacsvox-aural-feedback-details--insert-explanation (indices)
  "Insert only the voice sources, actions, and limitations belonging to INDICES."
  (let (voices adjustments limitations)
    (dolist (index indices)
      (let* ((plan (emacsvox-aural-feedback-details--plan index))
             (content (emacsvox-aural-concrete-plan-content plan))
             (provenance (emacsvox-aural-concrete-content-provenance content))
             (source (alist-get 'voice provenance)))
        (cl-pushnew
         (format "%s, from %s%s"
                 (emacsvox-aural-recent-feedback--voice (emacsvox-aural--make-presentation-record :plan plan))
                 (emacsvox-aural-feedback-details--source-description source plan)
                 (if (emacsvox-aural-concrete-content-speak content) "" "; content is silent"))
         voices :test #'equal)
        (dolist (entry (emacsvox-aural-concrete-content-voice-provenance content))
          (unless (or (eq (car entry) 'preset) (eq (cdr entry) source))
            (cl-pushnew (format "%s from %s" (emacsvox-aural-humanize (car entry))
                                (emacsvox-aural-feedback-details--source-description (cdr entry) plan))
                        adjustments :test #'equal)))
        (dolist (diagnostic (emacsvox-aural-concrete-plan-degradations plan))
          (cl-pushnew (emacsvox-aural-feedback-details--limitation diagnostic) limitations :test #'equal))))
    (insert "Voice: " (string-join (nreverse voices) "; ") ".\n")
    (when adjustments (insert "Voice adjustments: " (string-join (nreverse adjustments) "; ") ".\n"))
    (dolist (phase '(before after))
      (let (descriptions)
        (dolist (index indices)
          (let* ((plan (emacsvox-aural-feedback-details--plan index))
                 (actions (if (eq phase 'before) (emacsvox-aural-concrete-plan-before plan)
                            (emacsvox-aural-concrete-plan-after plan))))
            (dolist (action actions)
              (push (format "%s, from %s"
                            (emacsvox-aural-feedback-details--action-description action)
                            (emacsvox-aural-feedback-details--source-description
                             (emacsvox-aural-concrete-action-source action) plan)) descriptions))))
        (insert (capitalize (symbol-name phase)) ": "
                (if descriptions (string-join (nreverse descriptions) "; ") "Nothing") ".\n")))
    (dolist (limitation (nreverse limitations)) (insert "Limitation: " limitation "\n"))))

(defun emacsvox-aural-feedback-details-debug ()
  "Open the frozen raw snapshot separately; q returns to this report."
  (interactive)
  (let ((origin (current-buffer)) (window (selected-window)) (position (copy-marker (point)))
        (record emacsvox-aural-feedback-details--record)
        (simulation emacsvox-aural-feedback-details--simulation)
        (source (emacsvox-aural-inspection-remember-source-buffer)))
    (unless (buffer-live-p emacsvox-aural-feedback-details--debug-buffer)
      (setq emacsvox-aural-feedback-details--debug-buffer
            (generate-new-buffer "*Aural Debug Details*")))
    (with-current-buffer emacsvox-aural-feedback-details--debug-buffer
      (when (markerp emacsvox-aural-ui-help-origin-position)
        (set-marker emacsvox-aural-ui-help-origin-position nil))
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "Aural Debug Details\n"
                (if simulation "Simulation; not recorded speech.\n" "Recorded presentation snapshot.\n")
                "Raw data for troubleshooting. q returns to Feedback Details.\n\n"
                (pp-to-string record)))
      (emacsvox-aural-interface-mode)
      (use-local-map (copy-keymap (current-local-map)))
      (local-set-key (kbd "q") #'emacsvox-aural-ui-help-quit)
      (emacsvox-aural-inspection-attach-source source)
      (setq-local emacsvox-aural-ui-help-origin-buffer origin)
      (setq-local emacsvox-aural-ui-help-origin-window window)
      (setq-local emacsvox-aural-ui-help-origin-position position)
      (goto-char (point-min))
      (set-buffer-modified-p nil))
    (let ((emacsvox-aural--history-recording-inhibited t))
      (emacsvox-aural-ui--pop-to-buffer
       emacsvox-aural-feedback-details--debug-buffer
       (lambda () (emacsvox-aural-ui-speak "Debug details. Raw troubleshooting data; q returns."))))))

(defun emacsvox-aural-feedback-details--render (&optional selected-target)
  "Render the report, preserving SELECTED-TARGET or the field at point."
  (let ((inhibit-read-only t)
        (target (or selected-target (get-text-property (point) 'emacsvox-aural-feedback-target)))
        (record emacsvox-aural-feedback-details--record))
    (erase-buffer)
    (emacsvox-aural-feedback-details--heading "Aural Feedback Details")
    (if emacsvox-aural-feedback-details--simulation
        (insert (format "Simulation using captured current rules; not recorded speech.\nSource: %s\n\n"
                        (or (emacsvox-aural-presentation-record-source-buffer-name record) "Unknown")))
      (insert (format "Record %s. %s\nSource: %s\n\n"
                    (emacsvox-aural-presentation-record-id record)
                    (if (emacsvox-aural-presentation-record-effective-payload-truncated-p record)
                        "Truncated preview; complete playback unavailable."
                      "Exact retained presentation.")
                    (or (emacsvox-aural-presentation-record-source-buffer-name record) "Unknown"))))
    (insert (format "%s: %s\nOccasion: %s\n\n"
                    (if emacsvox-aural-feedback-details--simulation "Simulated" "Submitted")
                    (format-time-string "%Y-%m-%d %H:%M:%S"
                                        (emacsvox-aural-presentation-record-queued-at record))
                    (emacsvox-aural-humanize
                     (plist-get (emacsvox-aural-concrete-plan-context
                                 (emacsvox-aural-presentation-record-plan record)) :occasion))))
    (emacsvox-aural-feedback-details--button
     (if emacsvox-aural-feedback-details--simulation "Play simulation" "Play original whole presentation")
     #'emacsvox-aural-feedback-details-play)
    (insert "\n")
    (emacsvox-aural-feedback-details--button "Preview whole presentation with changes" #'emacsvox-aural-feedback-details-preview)
    (insert (if emacsvox-aural-feedback-details--simulation
                "\nProposals use current rules plus linked drafts; the simulated baseline stays frozen.\n\n"
              "\nProposals use current rules plus linked drafts; originals stay frozen.\n\n"))
    (emacsvox-aural-feedback-details--heading "Fields in playback order")
    (dolist (indices (emacsvox-aural-feedback-details--groups record))
      (let ((start (point))
            (expanded (member indices emacsvox-aural-feedback-details--expanded)))
        (emacsvox-aural-feedback-details--heading
         (emacsvox-aural-ui--expansion-text
          (format "%s (%s; %d voice %s)"
                  (emacsvox-aural-feedback-details--label indices)
                  (emacsvox-aural-recent-feedback--voice
                   (emacsvox-aural--make-presentation-record
                    :plan (emacsvox-aural-feedback-details--plan (car indices))
                    :plans (mapcar #'emacsvox-aural-feedback-details--plan indices)))
                  (length indices)
                  (if (= 1 (length indices)) "span" "spans"))
          expanded))
        (make-text-button start (1- (point)) 'follow-link t
                          'action (lambda (_) (emacsvox-aural-feedback-details-toggle)))
        ;; Visibility owns the heading's cue; generic button marking would duplicate it.
        (remove-text-properties start (point) '(auditory-icon nil))
        (put-text-property start (point) 'emacsvox-aural-feedback-target indices)
        (when expanded
          (emacsvox-aural-feedback-details--insert-content indices)
          (insert "\n")
          (emacsvox-aural-feedback-details--button "Play field" #'emacsvox-aural-feedback-details-play-field)
          (insert "  ")
          (emacsvox-aural-feedback-details--button "Change field" #'emacsvox-aural-feedback-details-change)
          (insert "\n")
          (emacsvox-aural-feedback-details--insert-explanation indices)
          (put-text-property start (point) 'emacsvox-aural-feedback-target indices)
          (when (cdr indices)
            (cl-loop for index in indices for number from 1 do
                     (let ((span-start (point)))
                       (emacsvox-aural-feedback-details--heading
                        (format "  Span %d. Voice: %s" number
                                (emacsvox-aural-recent-feedback--voice
                                 (emacsvox-aural--make-presentation-record
                                  :plan (emacsvox-aural-feedback-details--plan index)))))
                       (emacsvox-aural-feedback-details--insert-content (list index))
                       (insert "\n")
                       (emacsvox-aural-feedback-details--insert-explanation (list index))
                       (emacsvox-aural-feedback-details--button "Play span" #'emacsvox-aural-feedback-details-play-field)
                       (insert "  ")
                       (emacsvox-aural-feedback-details--button "Change span" #'emacsvox-aural-feedback-details-change)
                       (insert "\n")
                       (put-text-property span-start (point) 'emacsvox-aural-feedback-target (list index))))))))
    (insert "\n")
    (let ((start (point)))
      (emacsvox-aural-feedback-details--heading "Debug details")
      (make-text-button start (1- (point)) 'follow-link t
                        'action (lambda (_) (emacsvox-aural-feedback-details-debug))))
    (emacsvox-aural-feedback-details--button "Open raw snapshot in a separate buffer" #'emacsvox-aural-feedback-details-debug)
    (insert "\nFor troubleshooting: recorded facts, rules, and backend settings.\n")
    (insert "\nRET expands or collapses a field. n/p headings; arrows read lines; TAB actions; O play field; P play all.\nC change field; V preview all changes; S stop; q return.\n")
    (goto-char (point-min))
    (when-let* ((position
                 (when target (cl-loop for pos = (point-min) then (next-single-property-change
                                                                    pos 'emacsvox-aural-feedback-target nil (point-max))
                                        while (< pos (point-max))
                                        when (equal target (get-text-property pos 'emacsvox-aural-feedback-target))
                                        return pos))))
      (goto-char position))
    (set-buffer-modified-p nil)))

(defun emacsvox-aural-feedback-details-speak-line ()
  "Read the current report line, retaining recorded content voices."
  (interactive)
  (emacsvox-aural-ui--speak-control (buffer-substring (line-beginning-position) (line-end-position))))

(defun emacsvox-aural-feedback-details-next-line (&optional previous)
  "Move one line and read it; PREVIOUS reverses direction."
  (interactive)
  (forward-line (if previous -1 1))
  (emacsvox-aural-feedback-details-speak-line))

(defun emacsvox-aural-feedback-details-previous-line ()
  "Move to and read the previous report line."
  (interactive)
  (emacsvox-aural-feedback-details-next-line t))

(defun emacsvox-aural-feedback-details-next-heading (&optional previous)
  "Move to the next heading; PREVIOUS selects the previous heading."
  (interactive)
  (let ((start (point)) found)
    (while (and (not found) (zerop (forward-line (if previous -1 1))))
      (setq found (get-text-property (point) 'emacsvox-aural-feedback-heading)))
    (unless found (goto-char start))
    (if-let* ((indices (get-text-property (point) 'emacsvox-aural-feedback-target))
              (expanded (cl-some (lambda (group) (memq (car indices) group))
                                 emacsvox-aural-feedback-details--expanded)))
        (let ((label (buffer-substring (line-beginning-position) (line-end-position)))
              (text (apply #'concat
                           (mapcar
                            (lambda (index)
                              (let ((content (emacsvox-aural-concrete-plan-content
                                              (emacsvox-aural-feedback-details--plan index))))
                                (propertize (or (emacsvox-aural-concrete-content-text content) "")
                                            'emacsvox-aural-recent-feedback-voice content))) indices))))
          (emacsvox-aural-ui--speak-control (concat label ". " text)))
      (emacsvox-aural-feedback-details-speak-line))))

(defun emacsvox-aural-feedback-details-previous-heading ()
  "Move to and read the previous heading."
  (interactive)
  (emacsvox-aural-feedback-details-next-heading t))

(defun emacsvox-aural-feedback-details-next-button (&optional previous)
  "Move to and speak the next action; PREVIOUS reverses direction."
  (interactive)
  (forward-button (if previous -1 1) t)
  (emacsvox-aural-ui--speak-control (button-label (button-at (point)))))

(defun emacsvox-aural-feedback-details-previous-button ()
  "Move to and speak the previous action."
  (interactive)
  (emacsvox-aural-feedback-details-next-button t))

(defun emacsvox-aural-feedback-details-open ()
  "Activate an action or expand the field at point."
  (interactive)
  (if-let* ((button (button-at (point))))
      (button-activate button)
    (emacsvox-aural-feedback-details-toggle)))

(define-derived-mode emacsvox-aural-feedback-details-mode emacsvox-aural-interface-mode
  "Aural-Details" "Read and change a pinned presentation at your own pace."
  (setq-local emacsvox-aural-ui-speech-function #'emacsvox-aural-recent-feedback--speak))

;; Text buttons bind RET to `push-button', overriding the mode's RET binding.
;; Use our activation path so generic button advice cannot append a cue to replay.
(define-key emacsvox-aural-feedback-details-mode-map [remap push-button]
            #'emacsvox-aural-feedback-details-open)

(dolist (binding '(("n" . emacsvox-aural-feedback-details-next-heading)
                   ("p" . emacsvox-aural-feedback-details-previous-heading)
                   ("<down>" . emacsvox-aural-feedback-details-next-line)
                   ("<up>" . emacsvox-aural-feedback-details-previous-line)
                   ("C-n" . emacsvox-aural-feedback-details-next-line)
                   ("C-p" . emacsvox-aural-feedback-details-previous-line)
                   ("TAB" . emacsvox-aural-feedback-details-next-button)
                   ("<backtab>" . emacsvox-aural-feedback-details-previous-button)
                   ("RET" . emacsvox-aural-feedback-details-open)
                   ("SPC" . emacsvox-aural-feedback-details-speak-line)
                   ("O" . emacsvox-aural-feedback-details-play-field)
                   ("P" . emacsvox-aural-feedback-details-play)
                   ("C" . emacsvox-aural-feedback-details-change)
                   ("V" . emacsvox-aural-feedback-details-preview)
                   ("h" . emacsvox-aural)
                   ("q" . emacsvox-aural-ui-help-quit)))
  (define-key emacsvox-aural-feedback-details-mode-map (kbd (car binding)) (cdr binding)))

(defun emacsvox-aural-feedback-details--open (record &optional simulation)
  "Open RECORD's report, marking a private SIMULATION explicitly."
  (let ((origin (current-buffer)) (window (selected-window)) (position (copy-marker (point)))
        (source (emacsvox-aural-inspection-remember-source-buffer))
        (buffer (or (cl-find-if
                     (lambda (candidate)
                       (eq record (buffer-local-value 'emacsvox-aural-feedback-details--record candidate)))
                     (buffer-list))
                    (generate-new-buffer "*Aural Feedback Details*"))))
    (with-current-buffer buffer
      (unless (eq record emacsvox-aural-feedback-details--record)
        (emacsvox-aural-feedback-details-mode)
        (setq emacsvox-aural-feedback-details--record record
              emacsvox-aural-feedback-details--simulation simulation))
      (emacsvox-aural-inspection-attach-source source)
      (when (markerp emacsvox-aural-ui-help-origin-position)
        (set-marker emacsvox-aural-ui-help-origin-position nil))
      (setq emacsvox-aural-ui-help-origin-buffer origin
            emacsvox-aural-ui-help-origin-window window
            emacsvox-aural-ui-help-origin-position position)
      (emacsvox-aural-feedback-details--render))
    (let ((emacsvox-aural--history-recording-inhibited t))
      (emacsvox-aural-ui--pop-to-buffer
       buffer (lambda () (emacsvox-aural-ui-speak
                          (if simulation
                              "Simulated feedback details; not recorded speech. n and p move by heading; q returns."
                            "Feedback details. n and p move by heading; q returns.")))))
    buffer))

(defun emacsvox-aural-feedback-details (record)
  "Select a stable review buffer for RECORD and speak only a brief introduction."
  (emacsvox-aural-feedback-details--open record))

(defun emacsvox-aural-feedback-details-explain (explanation &optional record)
  "Review EXPLANATION, using RECORD or an explicitly simulated baseline.
Simulations are private snapshots and are never added to presentation history."
  (if record
      (emacsvox-aural-feedback-details record)
    (let* ((plan (emacsvox-aural--freeze-presentation-plan
                  (emacsvox-aural-explanation-concrete-plan explanation)))
           (context (emacsvox-aural-concrete-plan-context plan)))
      (emacsvox-aural-feedback-details--open
       (emacsvox-aural--make-presentation-record
        :plan plan :plans (list plan) :queued-at (current-time)
        :source-buffer-name (plist-get context :source-buffer-name)
        :source-position (plist-get context :source-position))
       t))))

(provide 'emacsvox-aural-feedback-details)
;;; emacsvox-aural-feedback-details.el ends here
