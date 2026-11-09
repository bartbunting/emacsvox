;;; emacsvox-tree-settings.el --- Tree feedback settings -*- lexical-binding: t; -*-

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
;; Browse and preview tree feedback presets, then commit ordinary aural rules.
;; The shared tree parser and integrations do not depend on this interface.
;;; Code:
(require 'emacsvox-text-tree)
(require 'emacsvox-tone-editor)
(require 'emacsvox-aural-menu)
(require 'emacsvox-aural-editor)
(require 'emacsvox-aural-preview)
(require 'emacsvox-aural-provider-workflows)

(defconst emacsvox-tree-settings--events
  '((tree-entered "Entering a tree" "Tree. " open-object 660)
    (tree-exited "Leaving a tree" "End of tree. " close-object 330)
    (tree-level-changed "Changing level" "Level 1. " item 440))
  "Event, label, sample speech, preset earcon and preset tone pitch.")

(defconst emacsvox-tree-settings--choices
  '((speech "Speech" "Speak the tree boundary or the new level. Item labels keep their own feedback.")
    (earcon "Earcon" "Play the event's preset sound instead of its spoken indication. Requires enabled auditory icons; item labels remain spoken.")
    (both "Speech and earcon" "Play the preset sound and speak the boundary or new level. Auditory icons must be enabled for the sound.")
    (tone "Tone" "Play a short preset tone instead of the spoken indication. The level-change tone signals movement but does not encode the depth.")
    (none "No indication" "Omit this tree indication while retaining item labels and tree navigation.")
    (inherit "Use existing rules" "Remove only this page's rule at the applied or saved scope. Other feedback rules and narrower overrides remain; without overrides the indication uses speech."))
  "Ordered presets, with explanations for browsing and Help.")

(defun emacsvox-tree-settings--context ()
  "Return the captured source context and initialise its pending changes."
  (let* ((prefix (or transient--prefix transient-current-prefix))
         (context (emacsvox-aural-menu--context)))
    (emacsvox-aural-menu--source context)
    (unless (plist-get context :tree-draft)
      (setq context (plist-put (copy-sequence context) :tree-draft
                               (list :pending nil :applied nil)))
      (oset prefix scope context))
    context))

(defun emacsvox-tree-settings--draft ()
  "Return pending tree choices for this menu visit."
  (plist-get (emacsvox-tree-settings--context) :tree-draft))

(defun emacsvox-tree-settings--render (event choice)
  "Return the ordinary aural render contribution for EVENT and CHOICE."
  (if (and (eq event 'tree-level-changed) (listp choice))
      (emacsvox-tree-settings--level-render choice)
    (unless (assq choice emacsvox-tree-settings--choices)
      (user-error "Unknown tree feedback choice: %s" choice))
    (let* ((spec (assq event emacsvox-tree-settings--events))
           (actions (pcase choice
                      ((or 'earcon 'both)
                       (list (list :id 'tree-cue :kind 'cue :cue (nth 3 spec))))
                      ('tone (list (list :id 'tree-tone :kind 'tone
                                         :pitch (nth 4 spec) :duration 70))))))
      (list :content (list :speak (not (null (memq choice '(speech both)))))
            :before (list :replace actions) :after '(:replace nil)))))

(defun emacsvox-tree-settings--rule-id (event scope)
  "Return this page's stable rule identifier for EVENT at SCOPE."
  (intern (format "tree-settings-%s-%s" scope event)))

(defun emacsvox-tree-settings--rules (rules pending &optional scope)
  "Copy RULES and replace this page's PENDING entries at SCOPE.
SCOPE defaults to buffer for previews."
  (let ((result (copy-tree rules))
        (order (1+ (cl-loop for rule in rules maximize (or (plist-get rule :order) 0)
                            into maximum finally return (or maximum 0)))))
    (dolist (entry pending)
      (let ((id (emacsvox-tree-settings--rule-id (car entry) (or scope 'buffer))))
        (setq result (cl-remove id result :key (lambda (rule) (plist-get rule :id))))
        (unless (eq (cdr entry) 'inherit)
          (setq result
                (append result
                        (list (list :id id :order order
                                    :match (append (list :role 'tree-indicator :event (car entry))
                                                   (when (and (eq (car entry) 'tree-level-changed)
                                                              (listp (cdr entry))
                                                              (eq (plist-get (cdr entry) :tone) t))
                                                     '(:requires (tree-depth))))
                                    :render (emacsvox-tree-settings--render (car entry) (cdr entry)))))))))
    result))

(defun emacsvox-tree-settings--sample (event)
  "Return representative facts for EVENT, with depth on entry and level changes."
  (append (get-text-property
           0 'emacsvox-aural-facts
           (emacsvox-text-tree--indicator event " " (pcase event
                                                      ('tree-entered 0)
                                                      ('tree-level-changed 1))))
          (list :content (nth 2 (assq event emacsvox-tree-settings--events)))))

(defun emacsvox-tree-settings--effective (event)
  "Describe EVENT's effective output in the captured source buffer."
  (with-current-buffer (emacsvox-aural-menu--source (emacsvox-tree-settings--context))
    (let* ((facts (emacsvox-tree-settings--sample event))
           (context (emacsvox-aural-capture-context nil 'navigation))
           (plan (emacsvox-aural-compile-plan
                  (emacsvox-aural-resolve-active facts context) facts context))
           (speech (emacsvox-aural-concrete-content-speak
                    (emacsvox-aural-concrete-plan-content plan)))
           (actions (append (emacsvox-aural-concrete-plan-before plan)
                            (emacsvox-aural-concrete-plan-after plan))))
      (cond ((null actions) (if speech 'speech 'none))
            ((and (= (length actions) 1)
                  (eq (emacsvox-aural-concrete-action-kind (car actions)) 'cue))
             (if speech 'both 'earcon))
            ((and (not speech) (= (length actions) 1)
                  (eq (emacsvox-aural-concrete-action-kind (car actions)) 'tone)) 'tone)
            (t 'custom)))))

(defun emacsvox-tree-settings--name (choice)
  "Return the accessible label for CHOICE."
  (if (listp choice)
      (string-join
       (delq nil (list (when (plist-get choice :speech)
                         (format "spoken level, %s voice" (or (plist-get choice :voice) 'default)))
                       (pcase (plist-get choice :tone)
                         ('fixed "existing fixed tone") ('t "depth tone"))
                       (when (plist-get choice :earcon)
                         (format "%s earcon" (plist-get choice :earcon)))
                       (unless (or (plist-get choice :speech) (plist-get choice :tone)
                                   (plist-get choice :earcon)) "No indication"))) "; ")
    (or (cadr (assq choice emacsvox-tree-settings--choices)) "Custom feedback")))

(defun emacsvox-tree-settings--label (event)
  "Describe EVENT's pending choice and current effective feedback."
  (condition-case nil
      (let* ((draft (emacsvox-tree-settings--draft))
             (pending (assq event (plist-get draft :pending)))
             (effective (emacsvox-tree-settings--name
                         (if (eq event 'tree-level-changed)
                             (emacsvox-tree-settings--level-value t)
                           (emacsvox-tree-settings--effective event)))))
        (format "%s: %s"
                (cadr (assq event emacsvox-tree-settings--events))
                (if pending
                    (format "%s, %s; effective %s"
                            (emacsvox-tree-settings--name (cdr pending))
                            (if (memq event (plist-get draft :applied)) "applied here, not saved" "pending")
                            effective)
                  effective)))
    (user-error "Source closed; reopen Trees")))

(defun emacsvox-tree-settings--say (text)
  "Speak TEXT promptly as menu feedback."
  (emacsvox-transient--submit-text
   text (emacsvox-transient--menu-facts 'trees 'command-menu-value-changed)
   'state-change 'button))

(defun emacsvox-tree-settings--focus (command)
  "Focus COMMAND in the current menu."
  (when (window-live-p transient--window)
    (when-let* ((object (cl-find command transient--suffixes
                                 :key (lambda (item) (oref item command)))))
      (with-selected-window transient--window (transient--goto-button object)))))

(defun emacsvox-tree-settings--event-command (event)
  "Return the settings command for EVENT."
  (intern (format "emacsvox-tree-settings--%s" event)))

(defun emacsvox-tree-settings--choose (event)
  "Browse EVENT's choices without applying anything."
  (let* ((context (emacsvox-tree-settings--context))
         (choice (or (alist-get event (plist-get (plist-get context :tree-draft) :pending))
                     (emacsvox-tree-settings--effective event)))
         (index (or (seq-position emacsvox-tree-settings--choices choice
                                  (lambda (entry value) (eq (car entry) value))) 0)))
    (transient-setup 'emacsvox-tree-settings--choice-menu nil nil
                     :scope (plist-put (copy-sequence context) :tree-event event))
    (transient--show)
    (emacsvox-tree-settings--focus (intern (format "emacsvox-tree-settings--choice-%d" index)))
    (emacsvox-transient--speak-button)))

(defun emacsvox-tree-settings--return ()
  "Return to the event control in the parent menu."
  (let ((event (plist-get (emacsvox-tree-settings--context) :tree-event)))
    (when (transient--stack-pop)
      (transient--show)
      (emacsvox-tree-settings--focus (emacsvox-tree-settings--event-command event)))))

(defun emacsvox-tree-settings--stage (index)
  "Stage choice INDEX, then return to its event control."
  (let* ((event (plist-get (emacsvox-tree-settings--context) :tree-event))
         (draft (emacsvox-tree-settings--draft))
         (choice (car (nth index emacsvox-tree-settings--choices))))
    (setf (alist-get event (plist-get draft :pending)) choice
          (plist-get draft :applied) (remq event (plist-get draft :applied)))
    (emacsvox-tree-settings--return)
    (emacsvox-tree-settings--say
     (concat (emacsvox-tree-settings--name choice) ", pending. Apply or Save to use it."))))

(defun emacsvox-tree-settings--choice-label (index)
  "Describe choice INDEX, marking the selected value."
  (let* ((event (plist-get (emacsvox-tree-settings--context) :tree-event))
         (choice (car (nth index emacsvox-tree-settings--choices)))
         (selected (or (alist-get event (plist-get (emacsvox-tree-settings--draft) :pending))
                       (emacsvox-tree-settings--effective event))))
    (concat (emacsvox-tree-settings--name choice) (when (eq choice selected) ", selected"))))

(defun emacsvox-tree-settings--commit (scope)
  "Commit pending choices as ordinary aural rules at SCOPE."
  (let* ((context (emacsvox-tree-settings--context))
         (source (emacsvox-aural-menu--source context))
         (draft (plist-get context :tree-draft))
         (pending (plist-get draft :pending))
         (editor (emacsvox-aural-editor--find-buffer scope source))
         (emacsvox-aural-editor-scope scope)
         (emacsvox-aural-editor-target source))
    (unless pending (user-error "No pending tree choices"))
    (when (and editor (buffer-local-value 'emacsvox-aural-editor-dirty editor))
      (user-error "Finish the open %s rule editor before applying tree settings" scope))
    (with-current-buffer source
      (let ((rules (emacsvox-tree-settings--rules
                    (pcase scope ('buffer emacsvox-aural-buffer-rules)
                           ('session emacsvox-aural-session-rules)
                           ('personal emacsvox-aural-user-rules)) pending scope)))
        (emacsvox-aural--compile-rule-list rules (if (eq scope 'personal) 'user scope) "tree settings" t)
        (emacsvox-aural-editor--commit-layer rules)))
    (if (eq scope 'buffer)
        (setf (plist-get draft :applied) (mapcar #'car pending))
      (setf (plist-get draft :pending) nil (plist-get draft :applied) nil))
    (emacsvox-tree-settings--say
     (pcase scope
       ('buffer "Applied to this buffer. Not saved.")
       ('session "Applied for this Emacs session. Buffer rules still apply.")
       ('personal "Saved tree feedback. Session and buffer rules still apply.")))))

(defun emacsvox-tree-settings--preview-runs ()
  "Resolve a small tree example with pending choices, without changing rules."
  (let* ((context (emacsvox-tree-settings--context))
         (pending (plist-get (plist-get context :tree-draft) :pending)))
    (with-current-buffer (emacsvox-aural-menu--source context)
      (let* ((emacsvox-aural-buffer-rules
              (emacsvox-tree-settings--rules emacsvox-aural-buffer-rules pending))
             (emacsvox-aural--current-rules-cache (make-hash-table :test #'equal))
             (text (concat (emacsvox-text-tree--indicator 'tree-entered "Tree. " 0)
                           "Finance. "
                           (emacsvox-text-tree--indicator 'tree-level-changed "Level 1. " 1)
                           "Cash forecast. "
                           (emacsvox-text-tree--indicator 'tree-level-changed "Level 2. " 2)
                           "Expected receipts. "
                           (emacsvox-text-tree--indicator 'tree-level-changed "Level 1. " 1)
                           "Planning. "
                           (emacsvox-text-tree--indicator 'tree-exited "End of tree. ")
                           "Outside the tree."))
             (prepared (emacsvox-aural-prepare-text
                        text nil (emacsvox-aural-capture-context nil 'navigation))))
        (emacsvox-tree-settings--prepared-runs prepared)))))

(defun emacsvox-tree-settings--prepared-runs (prepared)
  "Pair each plan in PREPARED with its actual text span."
  (let ((start 0) runs)
    (while (< start (length prepared))
      (let ((end (next-single-property-change start emacsvox-aural-concrete-plan-property
                                              prepared (length prepared))))
        (push (list (emacsvox-aural-concrete-plan-at start prepared)
                    (substring prepared start end)) runs)
        (setq start end)))
    (nreverse runs)))

(defun emacsvox-tree-settings--preview ()
  "Browse a sample tree with pending feedback; q returns without applying it."
  (interactive)
  (emacsvox-tree-settings--browse (emacsvox-tree-settings--context)))

(defun emacsvox-tree-settings--stop ()
  "Stop the current preview without changing pending tree choices."
  (interactive) (emacsvox-aural-preview-stop))
(defun emacsvox-tree-settings--apply ()
  "Apply pending choices to this buffer only; save nothing."
  (interactive) (emacsvox-tree-settings--commit 'buffer))
(defun emacsvox-tree-settings--session ()
  "Apply pending choices across this session; buffer rules still take precedence."
  (interactive) (emacsvox-tree-settings--commit 'session))
(defun emacsvox-tree-settings--save ()
  "Save pending choices as shared personal rules; narrower rules remain."
  (interactive) (emacsvox-tree-settings--commit 'personal))
(defun emacsvox-tree-settings--discard ()
  "Discard pending choices; previously applied or saved rules stay in effect."
  (interactive)
  (let ((draft (emacsvox-tree-settings--draft)))
    (setf (plist-get draft :pending) nil (plist-get draft :applied) nil))
  (emacsvox-tree-settings--say "Pending choices discarded."))
(defun emacsvox-tree-settings--cancel ()
  "Return to the tree event without selecting a different choice."
  (interactive) (emacsvox-tree-settings--return))
(defun emacsvox-tree-settings--open-help ()
  "Read the Trees guide, then return to this menu with q."
  (interactive)
  (transient--display-help #'emacsvox-tree-settings--help nil))

(defun emacsvox-tree-settings--help (&optional object)
  "Explain tree presets, scope, previews and finer feedback changes."
  (interactive)
  (let ((context (emacsvox-tree-settings--context)))
    (when (window-live-p transient--window)
      (with-selected-window transient--window
        (when-let* ((button (button-at (point))) (suffix (button-get button 'button-data)))
          (oset transient--prefix scope
                (plist-put context :tree-help-focus (oref suffix command))))))
    (with-help-window (help-buffer)
      (when object
        (let* ((index (1- (string-to-number (oref object key))))
               (choice (nth index emacsvox-tree-settings--choices)))
          (princ (format "%s. %s\n\n" (cadr choice) (nth 2 choice)))))
      (princ "Trees\n\nEntering, leaving and changing level have independent feedback. Item labels remain separate. The shared settings apply wherever an integration supplies these tree events; currently Agent Shell's recognised text trees do so. Ordinary outlines and file-tree packages are unaffected.\n\nBrowse an event's choices with arrows. Return selects a pending value; q cancels the selection. Space opens a sample tree. Up and Down move through entry, levels one and two, siblings, shallower levels and exit. Space or Return repeats the current line; s stops speech; q returns to this menu. The sample uses pending choices without changing source text or live settings. A applies to this buffer, E applies across this Emacs session, and W saves personal rules for future sessions. Only changed events are written. Session and buffer rules can override saved choices; more specific feedback rules may also win. Saving after a buffer trial keeps that local override.\n\nPresets replace the selected indication's speech and before/after actions. Entry uses open-object and exit uses close-object. Their fixed tones are 70 milliseconds at 660 and 330 Hz. Level changes have separate controls for spoken level, its named voice, a depth tone and an optional earcon. These components can be combined. The factory depth tone rises three semitones per level from 220 Hz at the root, capped at 1760 Hz. Returning to a shallower level lowers the pitch. Its duration is 50 milliseconds. T opens the shared tone editor. Pitch is the root frequency; Rise per level sets semitones and Maximum pitch caps deeper levels. Duration, volume, waveform, sweep and envelope describe the sound. Shift arrows adjust numbers; Return enters an exact value. Space plays the root tone; P opens the sample with this draft tone enabled privately. A or W keeps the tone in the Trees draft; q returns. Apply or Save in Trees makes it effective. Keeping the edited tone enables it in the pending Trees draft; live settings change only when you apply or save in Trees. Choose a voice or earcon from the completion list; selecting only stages a change. Earcons require auditory icons to be enabled. No indication suppresses only the cue; tree labels and navigation remain.\n\nUse existing rules removes only this page's rule from the scope you apply or save. It leaves unrelated and more specific rules intact. With no overrides, all three indications use speech. Discard clears the draft, not already applied settings.\n\nFor another recording, a different tone, a voice or custom spoken label, use Change this feedback on the indicator in Recent feedback, C-e H f h. Choose its tree event as a matching condition. The same feedback-rule system stores these presets and finer changes.\n"))
    (pop-to-buffer (help-buffer))))

(defun emacsvox-tree-settings--restore-help-focus (&rest _)
  "Restore the browsed tree control once after Help closes."
  (when (and transient--prefix
             (memq (oref transient--prefix command)
                   '(emacsvox-tree-settings emacsvox-tree-settings--choice-menu
                                            emacsvox-tree-settings--level-menu)))
    (when-let* ((command (plist-get (oref transient--prefix scope) :tree-help-focus)))
      (oset transient--prefix scope
            (plist-put (oref transient--prefix scope) :tree-help-focus nil))
      (emacsvox-tree-settings--focus command))))
(advice-add 'transient--show :after #'emacsvox-tree-settings--restore-help-focus)

(defun emacsvox-tree-settings--tone-defaults ()
  "Return the factory tree tone, including its depth mapping."
  (append (emacsvox-tone-editor--data 220 50 100 nil) '(:semitones 3 :maximum 1760)))

(defun emacsvox-tree-settings--level-render (choice)
  "Return the combined level-feedback contribution described by CHOICE."
  (let* ((tone (plist-get choice :tone))
         (data (or (plist-get choice :tone-data) (emacsvox-tree-settings--tone-defaults))) actions)
    (when tone
      (push (append
             (list :id 'tree-depth-tone :kind 'tone
                   :pitch (if (eq tone 'fixed) (plist-get choice :pitch)
                            (list :pitch-from-depth 'tree-depth (plist-get data :pitch)
                                  (plist-get data :semitones) (plist-get data :maximum)))
                   :duration (if (eq tone 'fixed) (or (plist-get choice :duration) 70)
                               (plist-get data :duration)))
             (when (or (eq tone t) (plist-get choice :tone-data))
               (list :volume (/ (plist-get data :volume) 100.0)
                     :shape (emacsvox-tone-editor--shape data)))) actions))
    (when (plist-get choice :earcon)
      (push (list :id 'tree-level-cue :kind 'cue :cue (plist-get choice :earcon)) actions))
    (list :content (list :speak (plist-get choice :speech)
                         :voice (or (plist-get choice :voice) 'default))
          :before (list :replace (nreverse actions)) :after '(:replace nil))))

(defun emacsvox-tree-settings--level-value (&optional effective-only)
  "Return pending level components, or a snapshot of the effective example.
With EFFECTIVE-ONLY, ignore pending choices."
  (let ((pending (alist-get 'tree-level-changed
                            (plist-get (emacsvox-tree-settings--draft) :pending))))
    (if (and (not effective-only) pending (listp pending)) (copy-tree pending)
      (with-current-buffer (emacsvox-aural-menu--source (emacsvox-tree-settings--context))
        (let* ((facts (emacsvox-tree-settings--sample 'tree-level-changed))
               (context (emacsvox-aural-capture-context nil 'navigation))
               (render (emacsvox-aural-resolve-active facts context))
               (plan (emacsvox-aural-compile-plan render facts context))
               (tone (seq-find (lambda (action) (eq (emacsvox-aural-concrete-action-kind action) 'tone))
                               (emacsvox-aural-concrete-plan-before plan)))
               (cue (seq-find (lambda (action) (eq (emacsvox-aural-concrete-action-kind action) 'cue))
                              (emacsvox-aural-concrete-plan-before plan)))
               (raw-tone (seq-find (lambda (action) (eq (emacsvox-aural-action-kind action) 'tone))
                                   (emacsvox-aural-render-plan-before render)))
               (pitch (and raw-tone (emacsvox-aural-action-pitch raw-tone)))
               (mapped (eq (car-safe pitch) :pitch-from-depth))
               (depth-tone (or mapped (equal pitch '(:fact tree-tone-pitch))))
               (data (when tone
                       (append
                        (emacsvox-tone-editor--data
                         (cond (mapped (nth 2 pitch)) (depth-tone 220)
                               (t (emacsvox-aural-concrete-action-pitch tone)))
                         (round (emacsvox-aural-concrete-action-duration tone))
                         (* 100 (or (emacsvox-aural-concrete-action-requested-volume tone) 1))
                         (emacsvox-aural-concrete-action-shape tone))
                        (list :semitones (if mapped (nth 3 pitch) 3)
                              :maximum (if mapped (nth 4 pitch)
                                         (max 1760 (emacsvox-aural-concrete-action-pitch tone))))))))
          (list :speech (emacsvox-aural-concrete-content-speak
                         (emacsvox-aural-concrete-plan-content plan))
                :voice (or (emacsvox-aural-content-style-voice
                            (emacsvox-aural-render-plan-content render)) 'default)
                :tone (and tone (if depth-tone t 'fixed))
                :tone-data data
                :pitch (and tone (emacsvox-aural-concrete-action-pitch tone))
                :duration (and tone (emacsvox-aural-concrete-action-duration tone))
                :earcon (and cue (emacsvox-aural-concrete-action-cue cue))))))))

(defun emacsvox-tree-settings--level-set (key value)
  "Stage a level component KEY with VALUE, preserving the other components."
  (let ((choice (emacsvox-tree-settings--level-value))
        (draft (emacsvox-tree-settings--draft)))
    (setq choice (plist-put choice key value))
    (setf (alist-get 'tree-level-changed (plist-get draft :pending)) choice
          (plist-get draft :applied) (remq 'tree-level-changed (plist-get draft :applied)))
    (emacsvox-tree-settings--say
     (concat (emacsvox-tree-settings--name choice) ", pending."))))

(defun emacsvox-tree-settings--level-speech ()
  "Toggle the spoken level in the draft; item labels retain their own voices."
  (interactive)
  (emacsvox-tree-settings--level-set :speech
                                     (not (plist-get (emacsvox-tree-settings--level-value) :speech))))

(defun emacsvox-tree-settings--level-tone ()
  "Toggle a tone that rises with depth and falls on return.
An existing fixed tone is replaced by a depth tone on the first activation."
  (interactive)
  (emacsvox-tree-settings--level-set :tone
                                     (not (eq (plist-get (emacsvox-tree-settings--level-value) :tone) t))))

(defun emacsvox-tree-settings--level-voice ()
  "Stage a named voice for level numbers; speech must be enabled to hear it."
  (interactive)
  (let* ((current (plist-get (emacsvox-tree-settings--level-value) :voice))
         (names (emacsvox-aural-editor-voice-candidates current))
         (voice (completing-read "Spoken level voice: " names nil t nil nil
                                 (if (symbolp current) (symbol-name (or current 'default)) current))))
    (emacsvox-tree-settings--level-set :voice (intern voice))))

(defun emacsvox-tree-settings--level-earcon ()
  "Stage a level-change earcon, or None. Enabled auditory icons are required."
  (interactive)
  (let* ((cue (plist-get (emacsvox-tree-settings--level-value) :earcon))
         (name (completing-read "Level-change earcon: "
                                (cons "None" (emacsvox-aural-editor-cue-candidates))
                                nil t nil nil (if cue (symbol-name cue) "None"))))
    (emacsvox-tree-settings--level-set :earcon (unless (equal name "None") (intern name)))))

(defun emacsvox-tree-settings--level-inherit ()
  "Stage removal of this page's level override at the chosen scope."
  (interactive)
  (let ((draft (emacsvox-tree-settings--draft)))
    (setf (alist-get 'tree-level-changed (plist-get draft :pending)) 'inherit
          (plist-get draft :applied) (remq 'tree-level-changed (plist-get draft :applied))))
  (emacsvox-tree-settings--return)
  (emacsvox-tree-settings--say "Use existing level rules, pending."))

(defun emacsvox-tree-settings--level-back ()
  "Return to Trees with pending level choices; Apply or Save makes them effective."
  (interactive) (emacsvox-tree-settings--return))

(transient-define-prefix emacsvox-tree-settings--level-menu ()
                         "Combine spoken depth, a chosen voice, depth tones and an earcon."
                         :refresh-suffixes t
                         ["Level changes: combine components"
                          ("s" (lambda () (format "Spoken level: %s" (if (plist-get (emacsvox-tree-settings--level-value) :speech) "on" "off")))
                           emacsvox-tree-settings--level-speech :transient t)
                          ("v" (lambda () (format "Level voice: %s" (plist-get (emacsvox-tree-settings--level-value) :voice)))
                           emacsvox-tree-settings--level-voice :transient t)
                          ("t" (lambda () (format "Depth tone: %s" (pcase (plist-get (emacsvox-tree-settings--level-value) :tone)
                                                                     ('fixed "existing fixed tone; activate to replace")
                                                                     ('t "on") (_ "off"))))
                           emacsvox-tree-settings--level-tone :transient t)
                          ("T" "Edit depth tone" emacsvox-tree-settings--edit-tone :transient transient--do-suspend)
                          ("e" (lambda () (format "Level earcon: %s" (or (plist-get (emacsvox-tree-settings--level-value) :earcon) "none")))
                           emacsvox-tree-settings--level-earcon :transient t)]
                         ["Try and finish"
                          ("SPC" "Browse sample tree" emacsvox-tree-settings--preview :transient transient--do-suspend)
                          ("S" "Stop preview" emacsvox-tree-settings--stop :transient t)
                          ("I" "Use existing level rules" emacsvox-tree-settings--level-inherit :transient transient--do-replace)
                          ("h" "Help" emacsvox-tree-settings--open-help :transient transient--do-suspend)
                          ("q" "Back; keep pending choices" emacsvox-tree-settings--level-back :transient transient--do-replace)])

(defun emacsvox-tree-settings--tone-read (&optional factory)
  "Read the pending root tone and depth mapping, or FACTORY defaults."
  (if factory (emacsvox-tree-settings--tone-defaults)
    (copy-tree (or (plist-get (emacsvox-tree-settings--level-value) :tone-data)
                   (emacsvox-tree-settings--tone-defaults)))))

(defun emacsvox-tree-settings--tone-check (data)
  "Validate tone DATA and the relation between root and maximum pitch."
  (emacsvox-tone-editor--validate data)
  (unless (and (numberp (plist-get data :semitones)) (<= 0 (plist-get data :semitones) 12)
               (numberp (plist-get data :maximum))
               (<= (plist-get data :pitch) (plist-get data :maximum) 20000))
    (user-error "Rise must be 0–12 semitones; maximum pitch must be at least the root pitch and at most 20000 Hz"))
  data)

(defun emacsvox-tree-settings--tone-keep (data _save)
  "Keep DATA and enable its depth tone in the Trees draft; apply or save there."
  (let ((choice (emacsvox-tree-settings--level-value))
        (draft (emacsvox-tree-settings--draft)))
    (setq choice (plist-put choice :tone-data
                            (copy-tree (emacsvox-tree-settings--tone-check data)))
          choice (plist-put choice :tone t))
    (setf (alist-get 'tree-level-changed (plist-get draft :pending)) choice
          (plist-get draft :applied) (remq 'tree-level-changed (plist-get draft :applied)))))

(defun emacsvox-tree-settings--tone-step ()
  "Set pitch rise per tree level, from 0 to 12 semitones.
Zero gives a fixed pitch. Shift arrows adjust by a quarter semitone."
  (interactive) (emacsvox-tone-editor--number :semitones))
(put 'emacsvox-tree-settings--tone-step 'emacsvox-tone-field :semitones)

(defun emacsvox-tree-settings--tone-maximum ()
  "Set the pitch ceiling in Hz; deeper levels retain this pitch once reached.
The ceiling must be at least the root pitch. Shift arrows adjust by 100 Hz."
  (interactive) (emacsvox-tone-editor--number :maximum))
(put 'emacsvox-tree-settings--tone-maximum 'emacsvox-tone-field :maximum)

(defun emacsvox-tree-settings--tone-preview (data sample)
  "Preview private tone DATA, with a browsable SAMPLE when non-nil."
  (emacsvox-tree-settings--tone-check data)
  (let* ((context (copy-tree (emacsvox-tree-settings--context)))
         (draft (plist-get context :tree-draft))
         (choice (copy-tree (emacsvox-tree-settings--level-value))))
    (setq choice (plist-put choice :tone t)
          choice (plist-put choice :tone-data (copy-tree data)))
    (setf (alist-get 'tree-level-changed (plist-get draft :pending)) choice)
    (if sample (emacsvox-tree-settings--browse context)
      (setq choice (plist-put choice :speech nil)
            choice (plist-put choice :earcon nil))
      (with-current-buffer (emacsvox-aural-menu--source context)
        (let* ((emacsvox-aural-buffer-rules
                (emacsvox-tree-settings--rules emacsvox-aural-buffer-rules
                                               (list (cons 'tree-level-changed choice))))
               (emacsvox-aural--current-rules-cache (make-hash-table :test #'equal))
               (prepared (emacsvox-aural-prepare-text
                          (emacsvox-text-tree--indicator 'tree-level-changed "Root. " 0)
                          nil (emacsvox-aural-capture-context nil 'navigation))))
          (emacsvox-aural-preview-play-runs (emacsvox-tree-settings--prepared-runs prepared)))))))

(defun emacsvox-tree-settings--edit-tone ()
  "Edit the root tone and its depth mapping in a private draft.
Pitch is the root frequency. Rise per level and maximum pitch control deeper
levels. Space plays the root tone; P opens a browsable sample with the draft
tone enabled privately. A or W keeps edits in Trees; apply or save there.
Keeping enables the depth tone in the draft and preserves spoken level, voice
and earcon."
  (interactive)
  (emacsvox-tone-editor--open
   (emacsvox-tree-settings--context)
   (list :label "Tree root tone; pending until applied in Trees"
         :read #'emacsvox-tree-settings--tone-read
         :apply #'emacsvox-tree-settings--tone-keep
         :preview #'emacsvox-tree-settings--tone-preview
         :apply-label "Use tone in Trees draft" :save-label "Use tone in Trees draft"
         :apply-message "Depth tone enabled in Trees draft; apply or save in Trees"
         :save-message "Depth tone enabled in Trees draft; apply or save in Trees"
         :current-label "Play pending root tone" :sample-label "Browse sample tree"
         :sample-suspends t
         :keep-preset-fields '(:semitones :maximum)
         :numbers '((:semitones "Rise per level" "semitones" 0 12 0.25)
                    (:maximum "Maximum pitch" "Hz" 50 20000 100))
         :extra-controls
         '(("j" (lambda () (emacsvox-tone-editor--number-label :semitones))
            emacsvox-tree-settings--tone-step :transient t)
           ("m" (lambda () (emacsvox-tone-editor--number-label :maximum))
            emacsvox-tree-settings--tone-maximum :transient t)))))

(defvar-local emacsvox-tree-settings--preview-context nil)
(defvar-local emacsvox-tree-settings--preview-rules nil)
(defvar-local emacsvox-tree-settings--preview-position nil)

(defvar emacsvox-tree-settings-preview-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    (dolist (key '("<down>" "C-n" "n")) (keymap-set map key #'emacsvox-tree-settings--preview-next))
    (dolist (key '("<up>" "C-p" "p")) (keymap-set map key #'emacsvox-tree-settings--preview-previous))
    (dolist (key '("SPC" "RET")) (keymap-set map key #'emacsvox-tree-settings--preview-read))
    (keymap-set map "s" #'emacsvox-tree-settings--stop)
    (keymap-set map "q" #'transient-resume)
    map))

(define-derived-mode emacsvox-tree-settings-preview-mode special-mode "Tree preview"
  "Browse draft tree feedback with Up and Down; Space repeats and q returns.
The sample uses captured source settings. It changes no source or preferences.")

(defun emacsvox-tree-settings--preview-read ()
  "Read this sample line with tree feedback relative to the last sample line."
  (interactive)
  (let* ((context emacsvox-tree-settings--preview-context)
         (rules emacsvox-tree-settings--preview-rules)
         (description (emacsvox-text-tree--describe
                       (buffer-substring (line-beginning-position) (line-end-position))
                       emacsvox-tree-settings--preview-position)))
    (setq emacsvox-tree-settings--preview-position (cdr description))
    (with-current-buffer (emacsvox-aural-menu--source context)
      (let* ((emacsvox-aural-buffer-rules rules)
             (emacsvox-aural--current-rules-cache (make-hash-table :test #'equal))
             (prepared (emacsvox-aural-prepare-text
                        (car description) nil (emacsvox-aural-capture-context nil 'navigation))))
        (emacsvox-aural-preview-play-runs (emacsvox-tree-settings--prepared-runs prepared))))))

(defun emacsvox-tree-settings--preview-move (direction)
  "Move DIRECTION lines in the sample and read the resulting tree feedback."
  (let ((origin (point)))
    (forward-line direction)
    (when (or (eobp) (= origin (point)))
      (goto-char origin) (user-error "End of sample")))
  (emacsvox-tree-settings--preview-read))
(defun emacsvox-tree-settings--preview-next ()
  "Read the next sample line and its entry, level or exit indication."
  (interactive) (emacsvox-tree-settings--preview-move 1))
(defun emacsvox-tree-settings--preview-previous ()
  "Read the previous sample line, including movement to shallower levels."
  (interactive) (emacsvox-tree-settings--preview-move -1))

(defun emacsvox-tree-settings--browse (context)
  "Browse a private sample with pending choices from CONTEXT."
  (let* ((captured (copy-tree context))
         (rules (with-current-buffer (emacsvox-aural-menu--source captured)
                  (emacsvox-tree-settings--rules
                   emacsvox-aural-buffer-rules
                   (plist-get (plist-get captured :tree-draft) :pending)))))
    (let ((emacsvox-speak-messages nil))
      (transient--display-help
       (lambda (_)
         (pop-to-buffer (get-buffer-create "*Tree feedback preview*"))
         (let ((inhibit-read-only t))
           (erase-buffer)
           (insert "Outside the tree.\n")
           (let ((start (point)))
             (insert "Finance\n├─ Cash forecast\n│  ├─ Overview\n│  └─ Expected receipts\n└─ Planning\n")
             (emacsvox-text-tree--mark-region start (point)))
           (insert "Outside the tree.\n"))
         (emacsvox-tree-settings-preview-mode)
         (setq emacsvox-tree-settings--preview-context captured
               emacsvox-tree-settings--preview-rules rules
               emacsvox-tree-settings--preview-position nil)
         (goto-char (point-min))) nil))
    (emacsvox-tree-settings--say "Tree sample. Up and Down browse; Space repeats; q returns. Outside the tree.")))

(defun emacsvox-tree-settings--tree-entered ()
  "Choose feedback on entry; item labels remain separate."
  (interactive) (emacsvox-tree-settings--choose 'tree-entered))
(defun emacsvox-tree-settings--tree-exited ()
  "Choose feedback when reading leaves a tree, including onto a blank line."
  (interactive) (emacsvox-tree-settings--choose 'tree-exited))
(defun emacsvox-tree-settings--tree-level-changed ()
  "Choose feedback when depth changes; siblings do not repeat it."
  (interactive)
  (transient-setup 'emacsvox-tree-settings--level-menu nil nil
                   :scope (plist-put (copy-sequence (emacsvox-tree-settings--context))
                                     :tree-event 'tree-level-changed)))
(defun emacsvox-tree-settings--choice-0 ()
  "Stage this preset; Apply or Save makes it effective."
  (interactive) (emacsvox-tree-settings--stage 0))
(defun emacsvox-tree-settings--choice-1 ()
  "Stage this preset; Apply or Save makes it effective."
  (interactive) (emacsvox-tree-settings--stage 1))
(defun emacsvox-tree-settings--choice-2 ()
  "Stage this preset; Apply or Save makes it effective."
  (interactive) (emacsvox-tree-settings--stage 2))
(defun emacsvox-tree-settings--choice-3 ()
  "Stage this preset; Apply or Save makes it effective."
  (interactive) (emacsvox-tree-settings--stage 3))
(defun emacsvox-tree-settings--choice-4 ()
  "Stage this preset; Apply or Save makes it effective."
  (interactive) (emacsvox-tree-settings--stage 4))
(defun emacsvox-tree-settings--choice-5 ()
  "Stage this preset; Apply or Save makes it effective."
  (interactive) (emacsvox-tree-settings--stage 5))

(dotimes (index 6)
  (put (intern (format "emacsvox-tree-settings--choice-%d" index))
       'function-documentation `(nth 2 (nth ,index emacsvox-tree-settings--choices))))

(transient-define-prefix emacsvox-tree-settings--choice-menu ()
                         "Browse tree feedback presets; selecting only changes the pending draft."
                         [:description (lambda () (cadr (assq (plist-get (emacsvox-tree-settings--context) :tree-event)
                                                              emacsvox-tree-settings--events)))
                                       ("1" (lambda () (emacsvox-tree-settings--choice-label 0))
                                        emacsvox-tree-settings--choice-0 :show-help emacsvox-tree-settings--help :transient transient--do-replace)
                                       ("2" (lambda () (emacsvox-tree-settings--choice-label 1))
                                        emacsvox-tree-settings--choice-1 :show-help emacsvox-tree-settings--help :transient transient--do-replace)
                                       ("3" (lambda () (emacsvox-tree-settings--choice-label 2))
                                        emacsvox-tree-settings--choice-2 :show-help emacsvox-tree-settings--help :transient transient--do-replace)
                                       ("4" (lambda () (emacsvox-tree-settings--choice-label 3))
                                        emacsvox-tree-settings--choice-3 :show-help emacsvox-tree-settings--help :transient transient--do-replace)
                                       ("5" (lambda () (emacsvox-tree-settings--choice-label 4))
                                        emacsvox-tree-settings--choice-4 :show-help emacsvox-tree-settings--help :transient transient--do-replace)
                                       ("6" (lambda () (emacsvox-tree-settings--choice-label 5))
                                        emacsvox-tree-settings--choice-5 :show-help emacsvox-tree-settings--help :transient transient--do-replace)
                                       ]
                         ["Finish"
                          ("q" "Cancel selection" emacsvox-tree-settings--cancel :transient transient--do-replace)])

;;;###autoload
(transient-define-prefix emacsvox-tree-settings ()
                         "Browse and preview shared tree feedback for a captured source buffer.
Apply to that buffer or this session, or save personal rules explicitly."
                         :refresh-suffixes t
                         ["Trees: indications, separate from item labels"
                          ("e" (lambda () (emacsvox-tree-settings--label 'tree-entered))
                           emacsvox-tree-settings--tree-entered :transient transient--do-suspend)
                          ("x" (lambda () (emacsvox-tree-settings--label 'tree-exited))
                           emacsvox-tree-settings--tree-exited :transient transient--do-suspend)
                          ("l" (lambda () (emacsvox-tree-settings--label 'tree-level-changed))
                           emacsvox-tree-settings--tree-level-changed :transient transient--do-suspend)]
                         ["Try and apply"
                          ("SPC" "Browse sample tree" emacsvox-tree-settings--preview :transient transient--do-suspend)
                          ("s" "Stop preview" emacsvox-tree-settings--stop :transient t)
                          ("A" "Apply to captured buffer" emacsvox-tree-settings--apply :transient t)
                          ("E" "Apply across this Emacs session" emacsvox-tree-settings--session :transient t)
                          ("W" "Save shared personal rules" emacsvox-tree-settings--save :transient t)]
                         ["Finish"
                          ("D" "Discard pending choices" emacsvox-tree-settings--discard :transient t)
                          ("h" "Help: presets, scope and finer changes" emacsvox-tree-settings--open-help :transient transient--do-suspend)
                          ("q" "Back; discard pending choices" transient-quit-one)
                          ("C-q" "Close menus; discard pending choices" transient-quit-all)]
                         (interactive)
                         (let ((context (condition-case nil (copy-sequence (emacsvox-aural-menu--context))
                                          (user-error (emacsvox-aural-menu--capture nil)))))
                           (transient-setup 'emacsvox-tree-settings nil nil
                                            :scope (plist-put context :tree-draft nil))))

(provide 'emacsvox-tree-settings)
;;; emacsvox-tree-settings.el ends here
