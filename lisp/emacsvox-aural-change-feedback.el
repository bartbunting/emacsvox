;;; emacsvox-aural-change-feedback.el --- Guided feedback changes -*- lexical-binding: t; -*-

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

;; Guide a narrowly scoped change using existing semantic facts and rule data.
;; Preview, match, and lifetime are independent choices.  No live rule layer
;; changes until Apply; the advanced editor remains available for full control.

;;; Code:

(require 'emacsvox-aural-editor)
(require 'emacsvox-aural-tools)
(require 'emacsvox-aural-ui)
(require 'emacsvox-aural-preview)
(require 'emacsvox-aural-recent-feedback)
(declare-function emacsvox-aural-voice-runtime--resolve
                  "emacsvox-aural-voice-runtime" (voice &optional palette profile))
(declare-function emacsvox-aural-voice-editor-open
                  "emacsvox-aural-voice-editor" (palette voice &optional source text))

(defvar-local emacsvox-aural-change-feedback-input nil
  "Frozen current-item or explicit history input for this draft.")
(defvar-local emacsvox-aural-change-feedback-record nil
  "Explicitly selected history record, or nil for Current item.")
(defvar-local emacsvox-aural-change-feedback-render nil
  "Unapplied declarative render contribution for this draft.")
(defvar-local emacsvox-aural-change-feedback-component nil
  "Stable component identity used to replace a previous generated rule.")
(defvar-local emacsvox-aural-change-feedback-part nil
  "Description of the selected part of a multi-part feedback record.")
(defvar-local emacsvox-aural-change-feedback-description nil
  "Plain description of the proposed component change.")
(defvar-local emacsvox-aural-change-feedback-selector nil
  "Matching criteria explicitly selected for this draft.")
(defvar-local emacsvox-aural-change-feedback-scope nil
  "Explicitly selected lifetime: buffer, session, or personal.")
(defvar-local emacsvox-aural-change-feedback-applied nil
  "Non-nil after this draft has been successfully saved or applied.")
(defvar-local emacsvox-aural-change-feedback--voice-remap nil
  "Non-nil for the simple named-voice mapping view.")
(defvar-local emacsvox-aural-change-feedback--expanded nil
  "Currently expanded choices: parts, operations, voices, or match.")
(defvar-local emacsvox-aural-change-feedback--match-options nil
  "Individual matching criteria, including those excluded from this draft.")
(defvar-local emacsvox-aural-change-feedback--part-number nil
  "One-based selected part number, or nil before selecting a part.")
(defvar-local emacsvox-aural-change-feedback--part-drafts nil
  "Draft fields retained separately for each selected part.")
(defvar-local emacsvox-aural-change-feedback--record-input nil
  "Original input from which each part's source context is selected.")

(defun emacsvox-aural-change-feedback--pending-p ()
  "Return non-nil if this buffer retains an unapplied change for any part."
  (or (and emacsvox-aural-change-feedback-render
           (not emacsvox-aural-change-feedback-applied))
      (cl-some (lambda (entry)
                 (and (not (eql (car entry) emacsvox-aural-change-feedback--part-number))
                      (cadr entry) (not (nth 6 entry))))
               emacsvox-aural-change-feedback--part-drafts)))

(defun emacsvox-aural-change-feedback--part-rows ()
  "Return parts in playback order, retaining their captured content voices."
  (cl-loop
   for plan in (emacsvox-aural-presentation-record-effective-plans
                emacsvox-aural-change-feedback-record)
   for n from 1
   for content = (emacsvox-aural-concrete-plan-content plan)
   collect
   (list (list 'part n)
         (vector (format "  Part %d%s" n
                         (if (eql n emacsvox-aural-change-feedback--part-number)
                             " [selected]" ""))
                 (concat
                  (emacsvox-aural-recent-feedback--voice
                   (emacsvox-aural--make-presentation-record :plan plan))
                  ": "
                  (propertize
                   (emacsvox-aural-recent-feedback--clean-text
                    (or (emacsvox-aural-concrete-content-text content)
                        "feedback without content"))
                   'emacsvox-aural-recent-feedback-voice content))))))

(defun emacsvox-aural-change-feedback--select-part (number)
  "Select part NUMBER, retaining any draft for the previously selected part."
  (let* ((fields '(emacsvox-aural-change-feedback-render
                   emacsvox-aural-change-feedback-component
                   emacsvox-aural-change-feedback-description
                   emacsvox-aural-change-feedback-selector
                   emacsvox-aural-change-feedback-scope
                   emacsvox-aural-change-feedback-applied
                   emacsvox-aural-change-feedback--match-options))
         (plan (nth (1- number)
                    (emacsvox-aural-presentation-record-effective-plans
                     emacsvox-aural-change-feedback-record)))
         (input (copy-sequence emacsvox-aural-change-feedback--record-input)))
    (when emacsvox-aural-change-feedback--part-number
      (setf (alist-get emacsvox-aural-change-feedback--part-number
                       emacsvox-aural-change-feedback--part-drafts)
            (mapcar #'symbol-value fields)))
    (cl-mapc #'set fields
             (or (alist-get number emacsvox-aural-change-feedback--part-drafts)
                 (make-list (length fields) nil)))
    (setq input (plist-put input :concrete plan)
          input (plist-put input :facts (copy-tree (emacsvox-aural-concrete-plan-facts plan)))
          input (plist-put input :context (copy-tree (emacsvox-aural-concrete-plan-context plan)))
          input (plist-put input :render (emacsvox-aural-concrete-plan-source-plan plan)))
    (when (and (plist-get input :source)
               (not (emacsvox-aural-tools--source-matches-context-p
                     (plist-get input :source) (plist-get input :context))))
      (setq input (plist-put input :source nil)))
    (setq emacsvox-aural-change-feedback-input input
          emacsvox-aural-change-feedback--part-number number
          emacsvox-aural-change-feedback-part (format ", Part %d: %s" number
                                                    (or (emacsvox-aural-concrete-content-text
                                                         (emacsvox-aural-concrete-plan-content plan)) "feedback without content"))
          emacsvox-aural-change-feedback--expanded nil)
    (emacsvox-aural-change-feedback-refresh 'change)
    (emacsvox-aural-ui-speak-name-and-state)))

(defun emacsvox-aural-change-feedback--voice-description ()
  "Describe the frozen content voice and the proposed replacement."
  (concat
   "Original voice: "
   (emacsvox-aural-recent-feedback--voice
    (emacsvox-aural--make-presentation-record
     :plan (plist-get emacsvox-aural-change-feedback-input :concrete)))
   (when emacsvox-aural-change-feedback-description
     (concat "; proposed: " emacsvox-aural-change-feedback-description))))

(defun emacsvox-aural-change-feedback--voice-rows ()
  "Return the original voice first, followed by alphabetical alternatives."
  (let* ((request (emacsvox-aural-concrete-content-voice-request
                   (emacsvox-aural-concrete-plan-content
                    (plist-get emacsvox-aural-change-feedback-input :concrete))))
         (current (cond ((null request) "default")
                        ((symbolp request)
                         (symbol-name
                          (or (cadr (emacsvox-aural-change-feedback--named-voice
                                     emacsvox-aural-change-feedback-input))
                              request)))))
         (names (sort (copy-sequence (emacsvox-aural-tools--voice-remap-candidates))
                      #'string-lessp))
         (selected (plist-get emacsvox-aural-change-feedback-render :content)))
    (when (member current names)
      (setq names (cons current (delete current names))))
    (mapcar
     (lambda (name)
       (list (list 'voice (intern name))
             (vector (concat "    " name)
                     (concat (if (equal name current) "Original voice. " "")
                             (if (and (plist-member selected :voice)
                                      (equal name (symbol-name (or (plist-get selected :voice) 'default))))
                                 "Selected for draft; P previews" "RET selects; P previews after selection")))))
     names)))

(defun emacsvox-aural-change-feedback--toggle (panel row)
  "Expand or collapse PANEL and retain focus on ROW."
  (setq emacsvox-aural-change-feedback--expanded
        (unless (eq emacsvox-aural-change-feedback--expanded panel) panel))
  (emacsvox-aural-change-feedback-refresh row)
  (emacsvox-aural-ui--announce-expansion
   (pcase row
     ('change (memq emacsvox-aural-change-feedback--expanded '(operations voices)))
     ('target (memq emacsvox-aural-change-feedback--expanded '(parts match)))
     ('match (eq emacsvox-aural-change-feedback--expanded 'match))
     (_ (eq emacsvox-aural-change-feedback--expanded 'voices)))))

(defun emacsvox-aural-change-feedback--require-part ()
  "Require an explicit part selection for a multi-part record."
  (when (and emacsvox-aural-change-feedback--record-input
             (null emacsvox-aural-change-feedback--part-number))
    (user-error "Select a part first; RET on a Part row chooses it")))

(defun emacsvox-aural-change-feedback--expand-rows (rows)
  "Insert expanded choices into the ordinary task ROWS."
  (cl-loop
   for row in rows
   for id = (car row)
   append
   (append
    (list
     (pcase id
       ('target
        (cond
         (emacsvox-aural-change-feedback--voice-remap
          (list id (vector "Applies to"
                           (concat (aref (cadr row) 1)
                                   (if (eq emacsvox-aural-change-feedback--expanded 'match)
                                       "; expanded" "; collapsed")))))
         (emacsvox-aural-change-feedback--record-input
            (list id (vector "Parts"
                             (format "%s; %s"
                                     (or emacsvox-aural-change-feedback-part "Choose a part")
                                     (if (eq emacsvox-aural-change-feedback--expanded 'parts)
                                         "expanded" "collapsed")))))
         (t row)))
       ('change
        (list id (vector (if emacsvox-aural-change-feedback--voice-remap "Voice" "Change")
                         (concat (emacsvox-aural-change-feedback--voice-description)
                                 (if (memq emacsvox-aural-change-feedback--expanded '(operations voices))
                                     "; expanded"
                                   "; collapsed")))))
       ('match
        (list id (vector "What should match"
                         (concat (aref (cadr row) 1)
                                 (if (eq emacsvox-aural-change-feedback--expanded 'match)
                                     "; expanded"
                                   "; collapsed")))))
       (_ row)))
    (pcase id
      ('match
       (when (eq emacsvox-aural-change-feedback--expanded 'match)
         (emacsvox-aural-change-feedback--match-rows)))
      ('target
       (cond
        ((eq emacsvox-aural-change-feedback--expanded 'parts)
         (emacsvox-aural-change-feedback--part-rows))
        ((and emacsvox-aural-change-feedback--voice-remap
              (eq emacsvox-aural-change-feedback--expanded 'match))
         (emacsvox-aural-change-feedback--match-rows))))
      ('change
       (if emacsvox-aural-change-feedback--voice-remap
           (when (eq emacsvox-aural-change-feedback--expanded 'voices)
             (emacsvox-aural-change-feedback--voice-rows))
         (when (memq emacsvox-aural-change-feedback--expanded '(operations voices))
           (cl-loop
            for operation in (emacsvox-aural-change-feedback--operations)
            for voicep = (equal operation "Change the content voice")
            append
            (append
             (list (list (list 'operation operation)
                         (vector (concat "  " (if voicep "Content voice" operation))
                                 (if voicep
                                     (concat (emacsvox-aural-change-feedback--voice-description)
                                             (if (eq emacsvox-aural-change-feedback--expanded 'voices)
                                                 "; expanded"
                                               "; collapsed"))
                                   "RET chooses this change"))))
             (when (and voicep (eq emacsvox-aural-change-feedback--expanded 'voices))
               (emacsvox-aural-change-feedback--voice-rows)))))))))))

(defun emacsvox-aural-change-feedback--named-voice (input)
  "Return (PALETTE NAME) for INPUT's base voice, without copying its tuning."
  (require 'emacsvox-aural-voice-runtime)
  (let* ((plan (plist-get input :concrete))
         (palette (or (and plan (emacsvox-aural-concrete-plan-voice-palette plan))
                      (emacsvox-aural-effective-voice-palette)))
         (content (emacsvox-aural-render-plan-content (plist-get input :render)))
         (voice (if (assq 'voice (emacsvox-aural-content-style-provenance content))
                    (emacsvox-aural-content-style-voice content)
                  (emacsvox-aural-tools--voice-remap-current-voice
                   (plist-get input :render) (plist-get input :context))))
         (preset (if (emacsvox-aural-voice-style-p voice)
                     (plist-get voice :preset) voice))
         (name (and preset (symbolp preset)
                    (plist-get (emacsvox-aural-voice-runtime--resolve preset palette) :name))))
    (when name (list palette name))))

(defun emacsvox-aural-change-feedback--tune-at-point ()
  "Open the current named voice's base tuner from the captured source."
  (interactive)
  (let* ((input (emacsvox-aural-tools--remap-source-input nil 'voice))
         (identity (emacsvox-aural-change-feedback--named-voice input)))
    (unless identity
      (user-error "This item has no named voice to tune; remap it to a named voice first"))
    (require 'emacsvox-aural-voice-editor)
    (emacsvox-aural-voice-editor-open
     (car identity) (cadr identity) (plist-get input :source)
     (or (plist-get (plist-get input :facts) :content)
         (emacsvox-aural-concrete-content-text
          (emacsvox-aural-concrete-plan-content (plist-get input :concrete)))))
    (emacsvox-aural-ui-announce-result
     "Tuning %s in palette %s; changes affect every use of this named voice"
     (cadr identity) (car identity))))

(defun emacsvox-aural-change-feedback--remap-at-point ()
  "Open a simple voice mapping draft for the current source item."
  (interactive)
  (let* ((input (emacsvox-aural-tools--remap-source-input nil 'voice))
         (context (plist-get input :context))
         (face (car (plist-get context :legacy-faces)))
         (selector
          (if face
              (append (if (plist-get context :module)
                          (list :module (plist-get context :module))
                        (list :mode (plist-get context :mode)))
                      (list :legacy-face face))
            (emacsvox-aural-tools--voice-remap-selector (plist-get input :facts) context)))
         (source (emacsvox-aural-inspection-remember-source-buffer))
         (buffer (generate-new-buffer "*Remap Voice*")))
    (with-current-buffer buffer
      (emacsvox-aural-change-feedback-mode)
      (emacsvox-aural-inspection-attach-source source)
      (setq emacsvox-aural-change-feedback-input input
            emacsvox-aural-change-feedback--voice-remap t
            emacsvox-aural-change-feedback-selector selector
            emacsvox-aural-change-feedback-component '(content))
      (emacsvox-aural-change-feedback-refresh))
    (emacsvox-aural-ui-pop-to-buffer buffer)
    (emacsvox-aural-ui-speak
     (concat (emacsvox-aural-change-feedback--summary)
             " Choose Voice, How long, then Save. P previews; O plays the original."))
    buffer))

(defun emacsvox-aural-change-feedback--remap-rows ()
  "Return the simple voice mapping fields and actions."
  (let ((identity (emacsvox-aural-change-feedback--named-voice emacsvox-aural-change-feedback-input)))
    (list
     (list 'target (vector "Applies to"
                           (emacsvox-aural-change-feedback--selector-description
                            emacsvox-aural-change-feedback-selector)))
     (list 'change (vector "Voice"
                           (or emacsvox-aural-change-feedback-description
                               (format "Currently %s; RET chooses another voice"
                                       (or (cadr identity) "default or custom voice")))))
     (list 'original (vector "Preview original" "Hear the captured item"))
     (list 'proposed (vector "Preview change" "Hear this item with the chosen voice"))
     (list 'lifetime (vector "How long" (emacsvox-aural-change-feedback--lifetime-description)))
     (list 'apply (vector "Save"
                          (cond (emacsvox-aural-change-feedback-applied "Saved or applied")
                                ((emacsvox-aural-change-feedback--ready-p) "Ready; RET or w saves")
                                (t "Choose a voice and how long to keep it"))))
     (list 'advanced (vector "Advanced" "Review the detailed rule")))))

(defun emacsvox-aural-change-feedback--source ()
  "Return this draft's still-live source buffer, if any."
  (let ((source (plist-get emacsvox-aural-change-feedback-input :source)))
    (and (buffer-live-p source) source)))

(defun emacsvox-aural-change-feedback--suggested-selector (&optional object-only)
  "Return existing fact-based matching criteria; OBJECT-ONLY omits events."
  (funcall (if object-only #'emacsvox-aural-tools--voice-remap-selector
             #'emacsvox-aural-tools--earcon-remap-selector)
           (plist-get emacsvox-aural-change-feedback-input :facts)
           (plist-get emacsvox-aural-change-feedback-input :context)))

(defun emacsvox-aural-change-feedback--selector-description (selector)
  "Describe the breadth of SELECTOR using the established rule vocabulary."
  (emacsvox-aural-describe-selector
   (emacsvox-aural-rule-selector
    (emacsvox-aural-compile-rule
     (list :id 'guided-match-description :match selector :render '(:content (:voice default))) 'user))))

(defun emacsvox-aural-change-feedback-match ()
  "Choose which facts should match, independently of the change's lifetime."
  (interactive)
  (emacsvox-aural-change-feedback--require-part)
  (unless emacsvox-aural-change-feedback-selector
    (setq emacsvox-aural-change-feedback-selector
          (copy-tree (emacsvox-aural-change-feedback--suggested-selector))))
  (setq emacsvox-aural-change-feedback--match-options
        (delete-dups
         (append emacsvox-aural-change-feedback--match-options
                 (emacsvox-aural-change-feedback--criteria
                  emacsvox-aural-change-feedback-selector))))
  (emacsvox-aural-change-feedback--toggle
   'match (if emacsvox-aural-change-feedback--voice-remap 'target 'match)))

(defun emacsvox-aural-change-feedback--criteria (selector)
  "Split SELECTOR into criteria, treating each state and event separately."
  (cl-loop for (key value) on selector by #'cddr
           append (if (memq key '(:states :events :requires))
                      (mapcar (lambda (item) (list key (list item))) value)
                    (list (list key value)))))

(defun emacsvox-aural-change-feedback--criterion-description (criterion)
  "Describe CRITERION without requiring its accompanying role or other facts."
  (let ((key (car criterion)) (value (cadr criterion)))
    (pcase key
      (:requires (format "%s present" (emacsvox-aural-humanize (car value))))
      ((or :states :events)
       (format "%s %s" (if (eq key :states) "state" "event")
               (emacsvox-aural-humanize (car value))))
      (_ (format "%s %s" (emacsvox-aural-humanize (substring (symbol-name key) 1))
                 (emacsvox-aural-humanize value))))))

(defun emacsvox-aural-change-feedback--match-rows ()
  "Return matching criteria with their included or excluded state."
  (let ((selected (emacsvox-aural-change-feedback--criteria
                   emacsvox-aural-change-feedback-selector)))
    (mapcar
     (lambda (criterion)
       (list (list 'criterion criterion)
             (vector (concat "  " (emacsvox-aural-change-feedback--criterion-description criterion))
                     (if (member criterion selected)
                         "Included; RET excludes this criterion"
                       "Excluded; RET includes this criterion"))))
     emacsvox-aural-change-feedback--match-options)))

(defun emacsvox-aural-change-feedback--toggle-criterion (criterion)
  "Include or exclude CRITERION in the draft, without changing live rules."
  (let* ((selected (emacsvox-aural-change-feedback--criteria
                    emacsvox-aural-change-feedback-selector))
         (included (member criterion selected))
         (wanted (if included (remove criterion selected) (cons criterion selected)))
         selector)
    (unless wanted (user-error "Keep at least one matching criterion"))
    (dolist (option emacsvox-aural-change-feedback--match-options)
      (when (member option wanted)
        (let ((key (car option)) (value (cadr option)))
          (setq selector
                (plist-put selector key
                           (if (memq key '(:states :events :requires))
                               (append (plist-get selector key) (copy-sequence value))
                             (copy-tree value)))))))
    ;; Validate before replacing the previous draft's matching criteria.
    (let ((description (emacsvox-aural-change-feedback--selector-description selector)))
      (setq emacsvox-aural-change-feedback-selector selector
            emacsvox-aural-change-feedback-applied nil)
      (emacsvox-aural-change-feedback-refresh (list 'criterion criterion))
      (emacsvox-aural-ui-announce-result
       "%s %s. Matches %s"
       (if included "Excluded" "Included")
       (emacsvox-aural-change-feedback--criterion-description criterion) description))))

(defun emacsvox-aural-change-feedback-lifetime ()
  "Choose current buffer, this session, or a saved personal rule."
  (interactive)
  (emacsvox-aural-change-feedback--require-part)
  (let ((choices (append (when (emacsvox-aural-change-feedback--source)
                           '(("Current buffer, until it is killed" . buffer)))
                         '(("This Emacs session" . session) ("Saved personal rule" . personal)))))
    (setq emacsvox-aural-change-feedback-scope
          (cdr (assoc (completing-read "How long: " choices nil t) choices))
          emacsvox-aural-change-feedback-applied nil)
    (emacsvox-aural-change-feedback-refresh 'lifetime)
    (emacsvox-aural-ui-speak (emacsvox-aural-change-feedback--summary))))

(defun emacsvox-aural-change-feedback--components (&optional kind)
  "Return individually removable component choices, optionally limited to KIND."
  (let ((plan (plist-get emacsvox-aural-change-feedback-input :concrete)) choices)
    (dolist (phase '(before after))
      (let ((actions (if (eq phase 'before) (emacsvox-aural-concrete-plan-before plan)
                       (emacsvox-aural-concrete-plan-after plan))))
        (cl-loop for action in actions for index from 0
                 for id = (emacsvox-aural-concrete-action-id action)
                 when (and id (or (null kind) (eq kind (emacsvox-aural-concrete-action-kind action)))
                           (memq (emacsvox-aural-concrete-action-anchor action) emacsvox-aural-action-anchors)
                           (= 1 (cl-count id actions :key #'emacsvox-aural-concrete-action-id)))
                 do (push (cons (format "%s %s: %s"
                                        (capitalize (symbol-name phase))
                                        (emacsvox-aural-concrete-action-kind action)
                                        (or (emacsvox-aural-concrete-action-cue action)
                                            (emacsvox-aural-concrete-action-tone action)
                                            (emacsvox-aural-concrete-action-text action) id))
                                (list :phase phase :action action :index index :count (length actions))) choices))))
    (nreverse choices)))

(defun emacsvox-aural-change-feedback--content-p ()
  "Return whether this example has spoken content that can be changed."
  (when-let* ((content (emacsvox-aural-concrete-plan-content
			(plist-get emacsvox-aural-change-feedback-input :concrete))))
    (emacsvox-aural-concrete-content-speak content)))

(defun emacsvox-aural-change-feedback--operations ()
  "Return component changes supported by this example's existing presentation."
  (append (when (emacsvox-aural-change-feedback--content-p) '("Change the content voice"))
          '("Add a sound" "Add a tone" "Add a spoken label")
          (when (emacsvox-aural-change-feedback--components 'cue) '("Replace a sound"))
          (when (emacsvox-aural-change-feedback--components 'tone) '("Change a tone"))
          (when (or (emacsvox-aural-change-feedback--content-p)
                    (emacsvox-aural-change-feedback--components)) '("Suppress one component"))))

(defun emacsvox-aural-change-feedback--choose-component (&optional kind content)
  "Choose a removable component of KIND; CONTENT also offers spoken content."
  (let ((choices (append (when content '(("Spoken content" . content)))
                         (emacsvox-aural-change-feedback--components kind))))
    (unless choices (user-error "No individually removable component; use Advanced"))
    (cdr (assoc (completing-read "Component: " choices nil t) choices))))

(defun emacsvox-aural-change-feedback--tone-data (&optional original)
  "Read a named tone or explicit pitch/duration, offering ORIGINAL values."
  (if (equal (completing-read "Tone settings: " '("Named tone" "Pitch and duration") nil t) "Named tone")
      (list :tone (intern (completing-read "Tone: " (emacsvox-aural-tone-candidates) nil t)))
    (list :pitch (read-number "Pitch in Hertz: " (and original (emacsvox-aural-concrete-action-pitch original)))
          :duration (read-number "Duration in milliseconds: "
                                 (or (and original (emacsvox-aural-concrete-action-duration original)) 100)))))

(defun emacsvox-aural-change-feedback--placement ()
  "Choose whether added feedback precedes or follows content."
  (if (equal (completing-read "Place added feedback: " '("Before content" "After content") nil t)
             "Before content") :before :after))

(defun emacsvox-aural-change-feedback--replace-action (choice data)
  "Build an isolated replacement for CHOICE using DATA and its original identity."
  (let* ((action (plist-get choice :action))
         (phase (intern (format ":%s" (plist-get choice :phase))))
         (anchor (emacsvox-aural-concrete-action-anchor action))
         (id (emacsvox-aural-concrete-action-id action))
         (insertion (emacsvox-aural-tools--earcon-remap-insertion choice)))
    (when (and (> (plist-get choice :index) 0)
               (< (plist-get choice :index) (1- (plist-get choice :count))))
      ;; Existing rule data can insert only at an edge; make a moved action explicit.
      (setq insertion
            (if (equal (completing-read "Replacement is between other feedback. Place it: "
                                        '("Before the other feedback" "After the other feedback") nil t)
                       "Before the other feedback") :prepend :append)))
    (list phase (list :anchor anchor :remove (list id)
                      insertion (list (append (list :id id :anchor anchor) data))))))

(defun emacsvox-aural-change-feedback-change ()
  "Choose a component change without applying or saving any partial choice."
  (interactive)
  (emacsvox-aural-change-feedback--require-part)
  (emacsvox-aural-change-feedback--toggle
   (if emacsvox-aural-change-feedback--voice-remap 'voices
     (if (eq emacsvox-aural-change-feedback--expanded 'voices) 'voices 'operations))
   'change))

(defun emacsvox-aural-change-feedback--change (operation &optional voice)
  "Prepare OPERATION, using VOICE for a content voice change."
  (emacsvox-aural-change-feedback--require-part)
  (let* ((selector (or emacsvox-aural-change-feedback-selector
                       (emacsvox-aural-change-feedback--suggested-selector)))
         (id (emacsvox-aural-tools--remap-rule-id 'guided selector (list (intern operation))))
         render description (component (list (intern operation))))
    (pcase operation
      ("Change the content voice"
       (setq component '(content) render (list :content (list :voice (unless (eq voice 'default) voice)))
             description (format "Content voice %s" voice)))
      ((or "Add a sound" "Add a tone" "Add a spoken label")
       (let* ((phase (emacsvox-aural-change-feedback--placement))
              (data
               (pcase operation
                 ("Add a sound" (list :kind 'cue :cue (intern (completing-read "Sound: "
									       (emacsvox-aural-tools--earcon-remap-candidates) nil t))))
                 ("Add a tone" (append '(:kind tone) (emacsvox-aural-change-feedback--tone-data)))
                 (_ (list :kind 'speech :text (read-string "Spoken label: "))))))
         (setq render (list phase (list :append (list (append (list :id id :anchor 'object) data))))
               description (format "%s %s content: %s" operation (substring (symbol-name phase) 1)
                                   (or (plist-get data :cue) (plist-get data :tone) (plist-get data :text)
                                       (format "%s Hertz, %s milliseconds" (plist-get data :pitch) (plist-get data :duration)))))))
      ((or "Replace a sound" "Change a tone")
       (let* ((choice (emacsvox-aural-change-feedback--choose-component
                       (if (equal operation "Replace a sound") 'cue 'tone)))
              (action (plist-get choice :action))
              (data
               (if (equal operation "Replace a sound")
                   (emacsvox-aural-tools--earcon-action-data
                    action (intern (completing-read "Replacement sound: "
						    (emacsvox-aural-tools--earcon-remap-candidates) nil t)))
                 (append (list :kind 'tone :audio-mode (or (emacsvox-aural-concrete-action-audio-mode action) 'overlay))
                         (emacsvox-aural-change-feedback--tone-data action)))))
         ;; Build cue data directly; retain cue volume/space without duplicating IDs.
         (when (equal operation "Replace a sound")
           (setq data (cl-loop for (key value) on data by #'cddr
                               unless (memq key '(:id :anchor)) append (list key value))))
         (setq component (list (plist-get choice :phase) (emacsvox-aural-concrete-action-id action))
               render (emacsvox-aural-change-feedback--replace-action choice data)
               description (format "%s: %s; %s other feedback in the %s-content phase"
                                   operation (or (plist-get data :cue) (plist-get data :tone)
                                                 (format "%s Hertz, %s milliseconds" (plist-get data :pitch) (plist-get data :duration)))
                                   (if (plist-member (cadr render) :prepend) "before" "after")
                                   (plist-get choice :phase)))))
      ("Suppress one component"
       (let ((choice (emacsvox-aural-change-feedback--choose-component nil (emacsvox-aural-change-feedback--content-p))))
         (if (eq choice 'content)
             (setq component '(content) render '(:content (:speak nil)) description "Suppress spoken content; retain surrounding feedback")
           (let ((action (plist-get choice :action)))
             (setq component (list (plist-get choice :phase) (emacsvox-aural-concrete-action-id action))
                   render (list (intern (format ":%s" (plist-get choice :phase)))
                                (list :anchor (emacsvox-aural-concrete-action-anchor action)
                                      :remove (list (emacsvox-aural-concrete-action-id action))))
                   description (format "Suppress the selected %s component %s"
                                       (emacsvox-aural-concrete-action-kind action)
                                       (emacsvox-aural-concrete-action-id action))))))))
    (emacsvox-aural-compile-rule (list :id id :match selector :render render) 'user)
    (setq emacsvox-aural-change-feedback-component component
          emacsvox-aural-change-feedback-render render
          emacsvox-aural-change-feedback-description description
          emacsvox-aural-change-feedback-applied nil)
    (emacsvox-aural-change-feedback-refresh
     (if voice (list 'voice voice) 'change))
    (emacsvox-aural-ui-announce-result
     "%s" (if (emacsvox-aural-change-feedback--ready-p)
              (emacsvox-aural-change-feedback--summary)
            (format "Unsaved: %s. P previews before choosing a lifetime." description)))))

(defun emacsvox-aural-change-feedback--rule ()
  "Return the draft as existing declarative rule data."
  (let ((selector (or emacsvox-aural-change-feedback-selector
                      (emacsvox-aural-change-feedback--suggested-selector))))
    (list :id (emacsvox-aural-tools--remap-rule-id
               (or emacsvox-aural-change-feedback-scope 'preview) selector
               (if emacsvox-aural-change-feedback--voice-remap '(voice)
                 (cons 'guided emacsvox-aural-change-feedback-component)))
          :match selector :render (copy-tree emacsvox-aural-change-feedback-render))))

(defun emacsvox-aural-change-feedback--layer-rules (scope)
  "Return the present declarative rules for SCOPE."
  (pcase scope
    ('personal (copy-tree emacsvox-aural-user-rules))
    ('session (copy-tree emacsvox-aural-session-rules))
    ('buffer (when-let* ((source (emacsvox-aural-change-feedback--source)))
               (copy-tree (buffer-local-value 'emacsvox-aural-buffer-rules source))))))

(defun emacsvox-aural-change-feedback--rules-with-draft (scope)
  "Return SCOPE rules with the candidate draft appended or updated by ID."
  (let* ((rule (emacsvox-aural-change-feedback--rule))
         (id (plist-get rule :id))
         (rules (emacsvox-aural-change-feedback--layer-rules scope)))
    (let ((order (1+ (cl-loop for entry in rules
                             maximize (or (plist-get entry :order) 0) into maximum
                             finally return (or maximum 0)))))
      (append (cl-remove id rules :key (lambda (entry) (plist-get entry :id)))
              (list (plist-put rule :order order))))))

(defun emacsvox-aural-change-feedback-proposed ()
  "Preview this draft with current rules, without applying it."
  (interactive)
  (unless emacsvox-aural-change-feedback-render (user-error "Choose a change first"))
  (let* ((facts (copy-tree (plist-get emacsvox-aural-change-feedback-input :facts)))
         (context (copy-tree (plist-get emacsvox-aural-change-feedback-input :context)))
         (scope (or emacsvox-aural-change-feedback-scope 'buffer))
         (rules (emacsvox-aural-change-feedback--rules-with-draft scope))
         (emacsvox-aural-user-rules (if (eq scope 'personal) rules emacsvox-aural-user-rules))
         (emacsvox-aural-session-rules (if (eq scope 'session) rules emacsvox-aural-session-rules))
         (emacsvox-aural--current-rules-cache (make-hash-table :test #'equal)))
    (when (eq scope 'buffer) (setq context (plist-put context :buffer-rules rules)))
    (emacsvox-aural-preview-play-plan
     (emacsvox-aural-compile-plan
      (emacsvox-aural-resolve-active facts context) facts context))))

(defun emacsvox-aural-change-feedback-original ()
  "Replay the frozen selected feedback or the captured Current item example."
  (interactive)
  (let ((record emacsvox-aural-change-feedback-record))
    (when (and record (emacsvox-aural-presentation-record-effective-payload-truncated-p record))
      (user-error "The retained feedback is truncated and cannot be replayed completely"))
    (emacsvox-aural-preview-play-plan
     (if (eq (car-safe (tabulated-list-get-id)) 'part)
         (nth (1- (cadr (tabulated-list-get-id)))
              (emacsvox-aural-presentation-record-effective-plans record))
       (emacsvox-aural-change-feedback--require-part)
       (plist-get emacsvox-aural-change-feedback-input :concrete)))))

(defun emacsvox-aural-change-feedback--ready-p ()
  "Return whether matching criteria, change, and lifetime have all been chosen."
  (and emacsvox-aural-change-feedback-render emacsvox-aural-change-feedback-selector
       emacsvox-aural-change-feedback-scope))

(defun emacsvox-aural-change-feedback-advanced ()
  "Open this prepared change in the full rule editor without applying it."
  (interactive)
  (unless (emacsvox-aural-change-feedback--ready-p)
    (user-error "Choose a change, matching criteria, and lifetime first"))
  (let ((emacsvox-aural-editor-prepared-source-guard
         (plist-get emacsvox-aural-change-feedback-input :source-guard)))
    (emacsvox-aural-editor-open-prefilled-rule
     emacsvox-aural-change-feedback-scope (emacsvox-aural-change-feedback--rule)
     (emacsvox-aural-change-feedback--source))))

(defun emacsvox-aural-change-feedback-apply ()
  "Save or apply the reviewed rule using its explicitly selected lifetime."
  (interactive)
  (unless (emacsvox-aural-change-feedback--ready-p)
    (user-error "Choose a change, matching criteria, and lifetime before Apply"))
  (emacsvox-aural-inspection-check-source-guard (plist-get emacsvox-aural-change-feedback-input :source-guard))
  (let* ((scope emacsvox-aural-change-feedback-scope)
         (source (emacsvox-aural-change-feedback--source))
         (editor (emacsvox-aural-editor--find-buffer scope source))
         (rules (emacsvox-aural-change-feedback--rules-with-draft scope))
         (emacsvox-aural-editor-scope scope)
         (emacsvox-aural-editor-target source))
    (when (and editor (buffer-local-value 'emacsvox-aural-editor-dirty editor))
      (user-error "An unfinished %s rule editor exists; finish it before applying this change" scope))
    (emacsvox-aural--compile-rule-list rules (if (eq scope 'personal) 'user scope) "guided change" t)
    (condition-case error-data
        (progn
          (emacsvox-aural-editor--commit-layer rules)
          (setq emacsvox-aural-change-feedback-applied t)
          (emacsvox-aural-change-feedback-refresh 'apply)
          (emacsvox-aural-ui-announce-result "%s: %s"
                                             (if (eq scope 'personal) "Saved" "Applied temporarily")
                                             emacsvox-aural-change-feedback-description))
      (error
       (emacsvox-aural-ui-announce-result "Failed; draft retained: %s" (error-message-string error-data))))))

(defun emacsvox-aural-change-feedback--lifetime-description ()
  "Describe persistence separately from the breadth of matching criteria."
  (pcase emacsvox-aural-change-feedback-scope
    ('personal "saved personal rule, across sessions")
    ('session "this Emacs session, across matching buffers")
    ('buffer (format "all matching items in buffer %s, until it is killed"
                     (if-let* ((source (emacsvox-aural-change-feedback--source)))
                         (buffer-name source) "that has been killed")))
    (_ "not chosen")))

(defun emacsvox-aural-change-feedback--summary ()
  "Describe the target, proposed change, matching breadth, and lifetime."
  (if emacsvox-aural-change-feedback--voice-remap
      (format "Voice mapping for %s. %s. How long: %s. %s"
              (emacsvox-aural-change-feedback--selector-description emacsvox-aural-change-feedback-selector)
              (or emacsvox-aural-change-feedback-description
                  (aref (cadr (assq 'change (emacsvox-aural-change-feedback--remap-rows))) 1))
              (emacsvox-aural-change-feedback--lifetime-description)
              (if emacsvox-aural-change-feedback-applied "Saved or applied." "Unsaved."))
    (format "%s. Change: %s. Matching criteria: %s. Lifetime: %s. %s"
          (if emacsvox-aural-change-feedback-record
              (format "Recent Feedback record %s%s" (emacsvox-aural-presentation-record-id emacsvox-aural-change-feedback-record)
                      (or emacsvox-aural-change-feedback-part ""))
            (concat "Current item: " (emacsvox-aural-inspection-source-description)))
          (or emacsvox-aural-change-feedback-description "not chosen")
          (if emacsvox-aural-change-feedback-selector
              (concat "all items with " (emacsvox-aural-change-feedback--selector-description emacsvox-aural-change-feedback-selector))
            "not yet chosen")
          (emacsvox-aural-change-feedback--lifetime-description)
          (if emacsvox-aural-change-feedback-applied
              (if (eq emacsvox-aural-change-feedback-scope 'personal) "Saved." "Applied temporarily.")
            "Unsaved draft."))))

(defun emacsvox-aural-change-feedback-refresh (&optional id)
  "Refresh the guided draft while retaining selected row ID."
  (interactive)
  (emacsvox-aural-ui-refresh-tabulated
   (lambda ()
     (setq tabulated-list-entries
           (if emacsvox-aural-change-feedback--voice-remap
               (emacsvox-aural-change-feedback--remap-rows)
             (list
            (list 'target (vector "Target" (if emacsvox-aural-change-feedback-record (concat "Recent Feedback" (or emacsvox-aural-change-feedback-part "")) "Current item")))
            (list 'change (vector "Change" (or emacsvox-aural-change-feedback-description "Choose a component change")))
            (list 'match (vector "What should match"
                                 (if emacsvox-aural-change-feedback-selector
                                     (emacsvox-aural-change-feedback--selector-description emacsvox-aural-change-feedback-selector)
                                   "Not chosen; this may match many items")))
            (list 'lifetime (vector "How long" (emacsvox-aural-change-feedback--lifetime-description)))
            (list 'apply (vector "Apply or save" (cond (emacsvox-aural-change-feedback-applied
							(if (eq emacsvox-aural-change-feedback-scope 'personal) "Saved" "Applied temporarily"))
                                                       ((emacsvox-aural-change-feedback--ready-p) "Ready; a or C-c C-c applies the reviewed change")
                                                       (t "Choose change, match, and lifetime first")))))))
     (setq tabulated-list-entries
           (emacsvox-aural-change-feedback--expand-rows tabulated-list-entries))) id 'change))

(defun emacsvox-aural-change-feedback-details ()
  "Show the full reviewed summary without applying it."
  (interactive)
  (emacsvox-aural-ui-with-help-window (princ (emacsvox-aural-change-feedback--summary)))
  (emacsvox-aural-ui-speak (emacsvox-aural-change-feedback--summary)))

(defun emacsvox-aural-change-feedback-open-row ()
  "Open matching or lifetime choices, or show details of the selected row."
  (interactive)
  (pcase (tabulated-list-get-id)
    (`(criterion ,criterion)
     (emacsvox-aural-change-feedback--toggle-criterion criterion))
    (`(part ,number) (emacsvox-aural-change-feedback--select-part number))
    (`(operation ,operation)
     (if (equal operation "Change the content voice")
         (emacsvox-aural-change-feedback--toggle
          (if (eq emacsvox-aural-change-feedback--expanded 'voices) 'operations 'voices)
          (list 'operation operation))
       (emacsvox-aural-change-feedback--change operation)))
    (`(voice ,voice)
     (emacsvox-aural-change-feedback--change "Change the content voice" voice))
    ('target
     (cond
      (emacsvox-aural-change-feedback--voice-remap (emacsvox-aural-change-feedback-match))
      (emacsvox-aural-change-feedback--record-input
       (emacsvox-aural-change-feedback--toggle 'parts 'target))
      (t (emacsvox-aural-change-feedback-details))))
    ('change (emacsvox-aural-change-feedback-change))
    ('match (emacsvox-aural-change-feedback-match))
    ('lifetime (emacsvox-aural-change-feedback-lifetime))
    ('original (emacsvox-aural-change-feedback-original))
    ('proposed (emacsvox-aural-change-feedback-proposed))
    ('apply (emacsvox-aural-change-feedback-apply))
    ('advanced (emacsvox-aural-change-feedback-advanced))
    (_ (emacsvox-aural-change-feedback-details))))

(defun emacsvox-aural-change-feedback-help ()
  "Explain guided changes, previews, matching criteria, and lifetimes."
  (interactive)
  (let ((text (if emacsvox-aural-change-feedback--voice-remap
                  (concat (emacsvox-aural-change-feedback--summary)
                          "\n\nChoose Voice to use another named voice for this face or item. The named voice itself is not retuned.\n"
                          "RET opens the selected row. n/p or arrows move. P previews the change; O plays the original; S stops.\n"
                          "Choose How long, then Save or w. q hides and preserves the draft. e opens Advanced.\n"
                          "To retune the named voice everywhere it is used, return to Home and choose Tune voice used here (T).\n")
                (concat (emacsvox-aural-change-feedback--summary)
                      "\n\nRET on Parts expands parts in playback order. Moving reads their text in the captured voice; O replays a part.\n"
                      "c expands component changes. RET on Content voice expands voices: original first, then alphabetical.\n"
                      "RET selects a voice for the draft. P previews before choosing a lifetime. O plays the original. S stops.\n"
                      "m expands matching facts; RET on a criterion includes or excludes it. l chooses lifetime.\n"
                      "Exclude a state such as unread to match regardless of that state. A buffer rule affects every matching item in that buffer.\n"
                      "Preview uses the selected example with current rules and its captured buffer context.\n"
                      "a or C-c C-c applies only after all choices are made; e opens the full Advanced rule editor.\n"
                      "RET opens choices or details. n/p and arrows navigate. Space reads the row.\n"
                      "C-c C-a lists applicable actions. h opens Home. q hides and preserves the unfinished draft.\n"))))
    (emacsvox-aural-ui-with-help-window (princ text))
    (emacsvox-aural-ui-speak text)))

(define-derived-mode emacsvox-aural-change-feedback-mode emacsvox-aural-tabulated-mode
  "Aural-Change-Feedback" "Guide an unapplied change to selected feedback."
  (emacsvox-aural-ui-configure-tabulated "feedback changes" #'emacsvox-aural-ui-speak-name-and-state
					 #'emacsvox-aural-change-feedback-refresh #'emacsvox-aural-ui-speak-name-and-state)
  (setq tabulated-list-format [("Task" 26 nil) ("Status" 0 nil)] tabulated-list-padding 2)
  (setq-local emacsvox-aural-ui-speech-function #'emacsvox-aural-recent-feedback--speak)
  (setq-local emacsvox-aural-ui-action-filter
              (lambda (command)
                (pcase command
                  ((or 'emacsvox-aural-change-feedback-apply 'emacsvox-aural-change-feedback-advanced)
                   (emacsvox-aural-change-feedback--ready-p))
                  ('emacsvox-aural-change-feedback-proposed emacsvox-aural-change-feedback-render)
                  (_ t))))
  (tabulated-list-init-header))

(dolist (binding '(("RET" . emacsvox-aural-change-feedback-open-row)
                   ("c" . emacsvox-aural-change-feedback-change)
                   ("m" . emacsvox-aural-change-feedback-match)
                   ("l" . emacsvox-aural-change-feedback-lifetime)
                   ("P" . emacsvox-aural-change-feedback-proposed)
                   ("O" . emacsvox-aural-change-feedback-original)
                   ("a" . emacsvox-aural-change-feedback-apply)
                   ("w" . emacsvox-aural-change-feedback-apply)
                   ("C-c C-c" . emacsvox-aural-change-feedback-apply)
                   ("e" . emacsvox-aural-change-feedback-advanced)
                   ("h" . emacsvox-aural)
                   ("?" . emacsvox-aural-change-feedback-help)))
  (define-key emacsvox-aural-change-feedback-mode-map (kbd (car binding)) (cdr binding)))

;;;###autoload
(defun emacsvox-aural-change-feedback (&optional record)
  "Guide a feedback change for the captured Current item or explicit RECORD."
  (interactive)
  (when (and record (emacsvox-aural-presentation-record-effective-payload-truncated-p record))
    (user-error "This record is truncated; choose complete feedback for a comparable preview"))
  (let* ((input (emacsvox-aural-tools--remap-source-input record))
         (plans (and record (emacsvox-aural-presentation-record-effective-plans record)))
         (record-input (and (cdr plans) (copy-sequence input)))
         (source (emacsvox-aural-inspection-remember-source-buffer))
         (buffer (generate-new-buffer "*Aural Change Feedback*")))
    ;; Frozen history can identify a buffer only when its original identity survives.
    (when (and record (plist-get input :source)
               (not (emacsvox-aural-tools--source-matches-context-p
                     (plist-get input :source) (plist-get input :context))))
      (setq input (plist-put input :source nil)))
    (with-current-buffer buffer
      (emacsvox-aural-change-feedback-mode)
      (emacsvox-aural-inspection-attach-source source)
      (setq emacsvox-aural-change-feedback-input input
            emacsvox-aural-change-feedback-record record
            emacsvox-aural-change-feedback--record-input record-input
            emacsvox-aural-change-feedback--expanded (and (cdr plans) 'parts))
      (emacsvox-aural-change-feedback-refresh (and (cdr plans) '(part 1))))
    (emacsvox-aural-ui-pop-to-buffer buffer)
    (emacsvox-aural-ui-speak (emacsvox-aural-change-feedback--summary))
    (when (cdr plans) (emacsvox-aural-ui-speak-name-and-state))
    buffer))

(provide 'emacsvox-aural-change-feedback)
;;; emacsvox-aural-change-feedback.el ends here
