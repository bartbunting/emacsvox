;;; emacsvox-reading-settings.el --- Scoped line reading controls -*- lexical-binding: t; -*-

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
;; Browse explained choices, preview drafts and apply or save explicitly.
;;; Code:
(require 'emacsvox-reading-lines)
(require 'emacsvox-aural-menu)
(require 'emacsvox-aural-preview)
(require 'emacsvox-tone-editor)
(require 'emacsvox-aural-tools)
(require 'cus-edit)
(autoload 'emacsvox-sound-library "emacsvox-sound-library" nil t)
(declare-function emacsvox-speak-row-position "emacsvox-speak" ())

(defun emacsvox-reading-settings--context ()
  "Return the source context, initializing an isolated draft once."
  (let* ((context (emacsvox-aural-menu--context))
         (source (emacsvox-aural-menu--source context))
         (prefix (or transient--prefix transient-current-prefix)))
    (unless (plist-get context :reading-draft)
      (setq context
            (plist-put (copy-sequence context) :reading-draft
                       (with-current-buffer source
                         (list :scope 'buffer :mode major-mode
                               :values (copy-tree emacsvox-reading-lines-overrides)
                               :initial (copy-tree emacsvox-reading-lines-overrides)))))
      (oset prefix scope context))
    (unless (eq (plist-get (plist-get context :reading-draft) :mode)
                (buffer-local-value 'major-mode source))
      (user-error "Source mode changed; reopen line reading settings"))
    context))
(defun emacsvox-reading-settings--state ()
  "Return the shared draft state."
  (plist-get (emacsvox-reading-settings--context) :reading-draft))
(defun emacsvox-reading-settings--source ()
  "Return the captured source buffer."
  (emacsvox-aural-menu--source (emacsvox-reading-settings--context)))
(defun emacsvox-reading-settings--values ()
  "Resolve draft values against the wider scopes they follow."
  (let ((state (emacsvox-reading-settings--state)))
    (with-current-buffer (emacsvox-reading-settings--source)
      (emacsvox-reading-lines--merge
       (plist-get state :values)
       (when (eq (plist-get state :scope) 'buffer)
         (alist-get major-mode emacsvox-reading-lines-modes))
       (unless (eq (plist-get state :scope) 'global) emacsvox-reading-lines-defaults)))))
(defun emacsvox-reading-settings--stage (key value)
  "Stage KEY as VALUE without applying it."
  (let ((state (emacsvox-reading-settings--state)))
    (setf (plist-get state :values)
          (plist-put (copy-tree (plist-get state :values)) key (copy-tree value)))))
(defun emacsvox-reading-settings--say (text)
  "Speak replaceable menu feedback TEXT."
  (emacsvox-transient--submit-text
   text (emacsvox-transient--menu-facts 'line-reading 'command-menu-value-changed)
   'state-change 'button))
(defun emacsvox-reading-settings--label (key label)
  "Describe KEY's draft value and inheritance using LABEL."
  (let* ((state (emacsvox-reading-settings--state))
         (value (plist-get (emacsvox-reading-settings--values) key)))
    (format "%s: %s%s" label value
            (if (plist-member (plist-get state :values) key) "" ", inherited"))))
(defun emacsvox-reading-settings--title ()
  "Describe scope and unapplied edits concisely."
  (let ((state (emacsvox-reading-settings--state)))
    (format "Line reading, %s%s; active %s" (plist-get state :scope)
            (if (equal (plist-get state :values) (plist-get state :initial)) "" ", draft")
            (with-current-buffer (emacsvox-reading-settings--source)
              (if (or visual-line-mode line-move-visual) "screen rows" "source lines")))))
(defun emacsvox-reading-settings--applied ()
  "Return runtime settings at the draft's selected scope."
  (let ((state (emacsvox-reading-settings--state)))
    (with-current-buffer (emacsvox-reading-settings--source)
      (copy-tree (pcase (plist-get state :scope)
                   ('buffer emacsvox-reading-lines-overrides)
                   ('mode (alist-get major-mode emacsvox-reading-lines-modes))
                   ('global emacsvox-reading-lines-defaults))))))
(defun emacsvox-reading-settings--discard ()
  "Discard unapplied edits and reread the selected scope; applied changes remain."
  (interactive)
  (let ((state (emacsvox-reading-settings--state)) (applied (emacsvox-reading-settings--applied)))
    (setf (plist-get state :values) (copy-tree applied)
          (plist-get state :initial) applied))
  (emacsvox-reading-settings--say "Unapplied edits discarded"))
(defun emacsvox-reading-settings--inherit ()
  "Stage inheritance for every preference at this scope; Apply makes it effective."
  (interactive)
  (let ((state (emacsvox-reading-settings--state)))
    (setf (plist-get state :values) nil))
  (emacsvox-reading-settings--say "Draft follows wider settings; global follows factory values"))
(defun emacsvox-reading-settings--factory ()
  "Stage all factory values, including preserving native major-mode navigation."
  (interactive)
  (let ((state (emacsvox-reading-settings--state)))
    (setf (plist-get state :values) (copy-tree emacsvox-reading-lines--factory)))
  (emacsvox-reading-settings--say "Factory values in draft"))
(defun emacsvox-reading-settings--commit (save)
  "Apply this scope's draft; SAVE also persists mode or global preferences."
  (let* ((state (emacsvox-reading-settings--state))
         (scope (plist-get state :scope)) (values (copy-tree (plist-get state :values))))
    (when (and save (eq scope 'buffer))
      (user-error "Buffer settings are temporary; choose mode or global scope to save"))
    (pcase scope
      ('buffer (with-current-buffer (emacsvox-reading-settings--source)
                 (setq emacsvox-reading-lines-overrides values)
                 (emacsvox-reading-lines--apply-mode)))
      ('mode (let ((modes (copy-tree emacsvox-reading-lines-modes)))
               (setf (alist-get (plist-get state :mode) modes) values)
               (if save (customize-save-variable 'emacsvox-reading-lines-modes modes)
                 (setq emacsvox-reading-lines-modes modes))))
      ('global (if save (customize-save-variable 'emacsvox-reading-lines-defaults values)
                 (setq emacsvox-reading-lines-defaults values))))
    (unless (eq scope 'buffer) (emacsvox-reading-lines--refresh))
    (setf (plist-get state :initial) (copy-tree values))
    (setq emacsvox-reading-lines--last-visit nil)
    (emacsvox-reading-settings--say (if save "Saved and applied" "Applied for this session"))))
(defun emacsvox-reading-settings--apply ()
  "Apply the draft for this session; no startup file is written."
  (interactive) (emacsvox-reading-settings--commit nil))
(defun emacsvox-reading-settings--save ()
  "Save and apply mode or global preferences through Customize."
  (interactive) (emacsvox-reading-settings--commit t))

(defun emacsvox-reading-settings--choose (key title choices)
  "Browse explained CHOICES for KEY under TITLE, without selecting on movement."
  (let ((current (if (eq key :scope) (plist-get (emacsvox-reading-settings--state) :scope)
                   (plist-get (emacsvox-reading-settings--values) key))))
    (transient-setup
     'emacsvox-reading-settings--choices nil nil
     :scope (append (list :reading-choice (list key title choices))
                    (emacsvox-reading-settings--context)))
    (transient--show)
    (when (window-live-p transient--window)
      (let* ((index (or (cl-position current choices :key #'car :test #'eq) 0))
             (command (nth index '(emacsvox-reading-settings--select-first
                                   emacsvox-reading-settings--select-second
                                   emacsvox-reading-settings--select-third)))
             (suffix (cl-find command transient--suffixes :key (lambda (item) (oref item command)))))
        (when suffix
          (with-selected-window transient--window (transient--goto-button suffix)))))))
(defun emacsvox-reading-settings--choice-label (index)
  "Describe choice INDEX and mark the current draft choice."
  (let* ((spec (plist-get (emacsvox-reading-settings--context) :reading-choice))
         (choice (nth index (nth 2 spec)))
         (current (if (eq (car spec) :scope) (plist-get (emacsvox-reading-settings--state) :scope)
                    (plist-get (emacsvox-reading-settings--values) (car spec)))))
    (concat (cadr choice) (when (eq current (car choice)) ", selected"))))
(defun emacsvox-reading-settings--choice-doc (index)
  "Return the effect of choice INDEX for spoken Help."
  (condition-case nil
      (nth 2 (nth index (nth 2 (plist-get (emacsvox-reading-settings--context) :reading-choice))))
    (user-error "Stage this choice; Apply or Save in line reading settings makes it effective.")))
(defun emacsvox-reading-settings--select (index)
  "Stage choice INDEX and return to its parent."
  (let* ((spec (plist-get (emacsvox-reading-settings--context) :reading-choice))
         (choice (nth index (nth 2 spec))) (key (car spec)))
    (if (eq key :scope)
        (let ((state (emacsvox-reading-settings--state)))
          (unless (equal (plist-get state :values) (plist-get state :initial))
            (user-error "Apply or discard the draft before changing scope"))
          (setf (plist-get state :scope) (car choice))
          (emacsvox-reading-settings--discard))
      (if (eq key :all-placement)
          (dolist (type '(first middle last))
            (emacsvox-reading-settings--stage (emacsvox-reading-lines--key type 'placement) (car choice)))
        (emacsvox-reading-settings--stage key (car choice))))
    (transient--stack-pop)
    (emacsvox-reading-settings--say (concat (cadr choice) ", draft"))))
(defun emacsvox-reading-settings--select-first ()
  "Stage the first choice." (interactive) (emacsvox-reading-settings--select 0))
(defun emacsvox-reading-settings--select-second ()
  "Stage the second choice." (interactive) (emacsvox-reading-settings--select 1))
(defun emacsvox-reading-settings--select-third ()
  "Stage the third choice." (interactive) (emacsvox-reading-settings--select 2))
(defun emacsvox-reading-settings--choice-inherit ()
  "Remove this preference from the draft so it follows wider settings."
  (interactive)
  (let* ((key (car (plist-get (emacsvox-reading-settings--context) :reading-choice)))
         (state (emacsvox-reading-settings--state)) (values (copy-tree (plist-get state :values))))
    (when (eq key :scope) (user-error "Scope cannot inherit"))
    (if (eq key :all-placement)
        (dolist (type '(first middle last))
          (cl-remf values (emacsvox-reading-lines--key type 'placement)))
      (cl-remf values key))
    (setf (plist-get state :values) values)
    (transient--stack-pop)
    (emacsvox-reading-settings--say "Following wider settings in draft")))
(cl-loop for command in '(emacsvox-reading-settings--select-first
                          emacsvox-reading-settings--select-second
                          emacsvox-reading-settings--select-third)
         for index from 0
         do (put command 'function-documentation
                 `(emacsvox-reading-settings--choice-doc ,index)))
(transient-define-prefix emacsvox-reading-settings--choices ()
  "Browse without changing settings; Enter stages the selected choice."
  [:description (lambda () (cadr (plist-get (emacsvox-reading-settings--context) :reading-choice)))
   ("1" (lambda () (emacsvox-reading-settings--choice-label 0)) emacsvox-reading-settings--select-first
    :transient transient--do-replace)
   ("2" (lambda () (emacsvox-reading-settings--choice-label 1)) emacsvox-reading-settings--select-second :transient transient--do-replace)
   ("3" (lambda () (emacsvox-reading-settings--choice-label 2)) emacsvox-reading-settings--select-third
    :if (lambda () (nth 2 (nth 2 (plist-get (emacsvox-reading-settings--context) :reading-choice)))) :transient transient--do-replace)]
  ["Inheritance and return"
   ("i" "Follow wider settings for this preference" emacsvox-reading-settings--choice-inherit :transient transient--do-replace)
   ("q" "Back without selecting" transient-quit-one)])

(defun emacsvox-reading-settings--mode ()
  "Choose arrow movement and speech amount.
Integration-owned navigation may take priority."
  (interactive)
  (emacsvox-reading-settings--choose
   :mode "Reading unit"
   '((source "Whole source lines" "Up and Down move and read one newline-delimited source line.")
     (visual "Wrapped screen rows" "Up and Down move and read one displayed row; enable Visual Line mode.")
     (inherit "Native mode behaviour" "Preserve the major mode's existing reading and wrapping defaults."))))
(defun emacsvox-reading-settings--speech ()
  "Choose spoken continuation descriptions independently of sound."
  (interactive)
  (emacsvox-reading-settings--choose
   :speech "Spoken continuation"
   '((off "Off" "Read the row without a spoken continuation prefix; sounds remain independent.")
     (brief "Brief: start, continued, end" "Speak a short row-type label before the text.")
     (explicit "Explicit: continuation above or below" "Describe which parts of this source line lie outside the row."))))
(defun emacsvox-reading-settings--frequency ()
  "Choose whether feedback repeats on each row or only when entering a source line."
  (interactive)
  (emacsvox-reading-settings--choose
   :frequency "Feedback frequency"
   '((every "Every wrapped row" "Repeat sound and description on every wrapped-row visit.")
     (entry "Only on entering a source line" "Identify the first row visited, including middle-row jumps; suppress subsequent rows of that line."))))
(defun emacsvox-reading-settings--scope ()
  "Choose temporary buffer, remembered major-mode, or global-default scope."
  (interactive)
  (emacsvox-reading-settings--choose
   :scope "Editing scope"
   '((buffer "This buffer, temporary" "Overrides mode and global choices here; cannot be saved per file.")
     (mode "This major mode" "Follows global defaults except for chosen keys; Save persists for this exact major mode.")
     (global "Global defaults" "Used where buffer and mode choices do not override them; Save persists across restarts."))))

(defun emacsvox-reading-settings--row-type ()
  "Return the row type being edited."
  (plist-get (emacsvox-reading-settings--context) :reading-row))
(defun emacsvox-reading-settings--row-key (field)
  "Return FIELD's preference key for the row being edited."
  (emacsvox-reading-lines--key (emacsvox-reading-settings--row-type) field))
(defun emacsvox-reading-settings--open-row (type)
  "Edit TYPE's independent draft."
  (transient-setup 'emacsvox-reading-settings--row nil nil
                   :scope (append (list :reading-row type) (emacsvox-reading-settings--context))))
(defun emacsvox-reading-settings--first ()
  "Edit feedback for a first row, where the source line continues below."
  (interactive) (emacsvox-reading-settings--open-row 'first))
(defun emacsvox-reading-settings--middle ()
  "Edit feedback for a middle row, where the source line continues above and below."
  (interactive) (emacsvox-reading-settings--open-row 'middle))
(defun emacsvox-reading-settings--last ()
  "Edit feedback for a last row, where the source line continues above."
  (interactive) (emacsvox-reading-settings--open-row 'last))
(defun emacsvox-reading-settings--sound ()
  "Choose Off, a generated tone or a recorded earcon for this row alone."
  (interactive)
  (emacsvox-reading-settings--choose
   (emacsvox-reading-settings--row-key 'sound) "Row sound"
   '((off "Off" "Suppress this row's sound; spoken descriptions remain independent.")
     (tone "Tone" "Use this row's independent pitch, duration, shape and volume.")
     (earcon "Recorded earcon" "Play the selected cue's recording from the active sound pack."))))
(defun emacsvox-reading-settings--placement ()
  "Choose when this row's sound plays relative to its description and text."
  (interactive)
  (emacsvox-reading-settings--choose
   (emacsvox-reading-settings--row-key 'placement) "Sound placement"
   '((before "Before speech" "Finish the sound before the spoken description and row text.")
     (alongside "Alongside speech" "Start sound with the spoken item, using supported playback timing.")
     (after "After speech" "Play only after this item finishes; navigation and Stop cancel it."))))
(defun emacsvox-reading-settings--all-placement ()
  "Stage one placement for all three sounds, preserving their identities."
  (interactive)
  (emacsvox-reading-settings--choose
   :all-placement "Placement for all three row sounds"
   '((before "Before speech" "Finish each row's own sound before its spoken item.")
     (alongside "Alongside speech" "Start each row's own sound with its speech.")
     (after "After speech" "Play each row's own sound only after its speech finishes."))))
(defun emacsvox-reading-settings--all-volume ()
  "Stage a common volume while preserving each row's sound and placement."
  (interactive)
  (let ((value (emacsvox-aural-menu--read-number "All row sounds, percent: " 60)))
    (unless (and (numberp value) (<= 0 value 100)) (user-error "Enter 0 to 100"))
    (dolist (type '(first middle last))
      (emacsvox-reading-settings--stage (emacsvox-reading-lines--key type 'volume) (/ value 100.0)))
    (emacsvox-reading-settings--say (format "%s percent for all row sounds in draft" value))))
(defun emacsvox-reading-settings--volume ()
  "Set this row's sound gain from 0 to 100 percent, subject to output controls."
  (interactive)
  (let* ((key (emacsvox-reading-settings--row-key 'volume))
         (value (emacsvox-aural-menu--read-number "Row sound volume, percent: "
                                                (* 100 (plist-get (emacsvox-reading-settings--values) key)))))
    (unless (and (numberp value) (<= 0 value 100)) (user-error "Enter 0 to 100"))
    (emacsvox-reading-settings--stage key (/ value 100.0))
    (emacsvox-reading-settings--say (format "%s percent in draft" value))))
(defun emacsvox-reading-settings--earcon ()
  "Select this row's cue identity without remapping generic boundary sounds."
  (interactive)
  (let ((cue (intern (emacsvox-transient--read
                      #'completing-read "Recorded cue: "
                      (emacsvox-aural-tools--earcon-remap-candidates) nil t))))
    (emacsvox-reading-settings--stage (emacsvox-reading-settings--row-key 'cue) cue)
    (emacsvox-reading-settings--stage (emacsvox-reading-settings--row-key 'sound) 'earcon))
  (emacsvox-reading-settings--say "Recorded cue selected in draft"))
(defun emacsvox-reading-settings--library ()
  "Browse and audition recordings; assignment and saving belong to the sound pack.
The dedicated wrapped-line cues avoid changing generic left and right sounds.
Library W saves pack assignments globally; it does not apply this reading draft."
  (interactive)
  (let* ((context (emacsvox-reading-settings--context))
         (buffer (emacsvox-sound-library)))
    (with-current-buffer buffer
      (let ((return emacsvox-aural-ui--return-function))
        (setq emacsvox-aural-ui--return-function
              (lambda ()
                (when return (funcall return))
                (when (buffer-live-p (plist-get context :source))
                  (transient-setup 'emacsvox-reading-settings nil nil :scope context))
                t))))))

(defun emacsvox-reading-settings--preview-values (values &optional type)
  "Preview VALUES for TYPE or a complete four-item sequence, without applying them."
  (unless (process-live-p tts-speaker-process) (user-error "Start speech before previewing"))
  (let* ((context (with-current-buffer (emacsvox-reading-settings--source)
                    (emacsvox-aural-capture-context nil 'navigation)))
         (types (if type (list type) '(complete first middle last)))
         (rules (delq nil (mapcar (lambda (row) (emacsvox-reading-lines--rule row values))
                                 (remq 'complete (copy-sequence types)))))
         (text (mapconcat
                (lambda (row)
                  (propertize
                   (pcase row ('complete "A complete source line. ")
                          ('first "A long source line begins here, ")
                          ('middle "continues through this middle row, ")
                          ('last "and finishes here. "))
                   emacsvox-aural-object-property row
                   emacsvox-aural-facts-property
                   (unless (eq row 'complete) (list :wrapped-row row))))
                types ""))
         (tts-quiet nil))
    (dolist (row (remq 'complete (copy-sequence types)))
      (when-let* ((reason (emacsvox-reading-lines--sound-unavailable values row)))
        (user-error "%s: %s" row reason)))
    (emacsvox-aural-preview-stop)
    (emacsvox-aural-submit text :context (plist-put context :buffer-rules rules)
                          :occasion 'navigation :lane 'main :delivery-policy 'urgent)))
(defun emacsvox-reading-settings--stop ()
  "Stop main speech and its pending preview cues."
  (interactive) (emacsvox-aural-preview-stop))
(defun emacsvox-reading-settings--preview ()
  "Preview complete, first, middle and last examples using only draft settings."
  (interactive) (emacsvox-reading-settings--preview-values (emacsvox-reading-settings--values)))
(defun emacsvox-reading-settings--preview-row ()
  "Preview this row alone using draft sound, description, placement and volume."
  (interactive) (emacsvox-reading-settings--preview-values
                 (emacsvox-reading-settings--values) (emacsvox-reading-settings--row-type)))
(defun emacsvox-reading-settings--compare ()
  "Preview the source buffer's currently applied feedback without changing drafts."
  (interactive)
  (emacsvox-reading-settings--preview-values
   (with-current-buffer (emacsvox-reading-settings--source) (emacsvox-reading-lines--values))))
(defun emacsvox-reading-settings--tone-data (values type)
  "Convert VALUES for TYPE into the common tone editor's units."
  (let ((tone (plist-get values (emacsvox-reading-lines--key type 'tone))))
    (emacsvox-tone-editor--data
     (plist-get tone :pitch) (plist-get tone :duration)
     (* 100 (plist-get values (emacsvox-reading-lines--key type 'volume)))
     (plist-get tone :shape))))
(defun emacsvox-reading-settings--put-tone (values type data)
  "Return a copy of VALUES with TYPE's editor DATA staged in runtime units."
  (let ((prefs (copy-tree values)))
    (setq prefs (plist-put prefs (emacsvox-reading-lines--key type 'tone)
                           (list :pitch (plist-get data :pitch) :duration (plist-get data :duration)
                                 :shape (emacsvox-tone-editor--shape data)))
          prefs (plist-put prefs (emacsvox-reading-lines--key type 'volume)
                           (/ (plist-get data :volume) 100.0)))
    prefs))
(defun emacsvox-reading-settings--tone ()
  "Stage this row's tone in the shared editor, keeping its sound choice.
Apply and Save here update the parent draft; the parent applies or saves it."
  (interactive)
  (let* ((context (emacsvox-reading-settings--context))
         (state (emacsvox-reading-settings--state))
         (type (emacsvox-reading-settings--row-type))
         (values (emacsvox-reading-settings--values)))
    (emacsvox-tone-editor--open
     context
     (list :label (format "%s wrapped row tone" type)
           :read (lambda (&optional factory)
                   (emacsvox-reading-settings--tone-data
                    (if factory emacsvox-reading-lines--factory values) type))
           :current (lambda ()
                      (emacsvox-reading-settings--tone-data
                       (with-current-buffer (plist-get context :source)
                         (emacsvox-reading-lines--values)) type))
           :apply (lambda (data _save)
                    (setf (plist-get state :values)
                          (emacsvox-reading-settings--put-tone (plist-get state :values) type data)))
           :preview (lambda (data sample)
                      (let* ((prefs (plist-put (emacsvox-reading-settings--put-tone values type data)
                                             (emacsvox-reading-lines--key type 'sound) 'tone))
                             (reason (emacsvox-reading-lines--sound-unavailable prefs type)))
                        (when reason (user-error "%s" reason))
                        (if sample (emacsvox-reading-settings--preview-values prefs type)
                          (let* ((action (emacsvox-aural--compile-action
                                          (append '(:id wrapped-tone-preview :kind tone)
                                                  (plist-get prefs (emacsvox-reading-lines--key type 'tone))
                                                  (list :volume (/ (plist-get data :volume) 100.0)))
                                          'wrapped-tone-preview 'before 0 'object))
                                 (render (emacsvox-aural--make-render-plan
                                          :before (list action)
                                          :content (emacsvox-aural--make-content-style :speak nil))))
                            (with-current-buffer (plist-get context :source)
                              (emacsvox-aural-preview-play-plan
                               (emacsvox-aural-compile-plan render nil (emacsvox-aural-context-at-point) 'local-cue)))))))
           :apply-label "Use in row draft" :save-label "Use in row draft (save in parent)"
           :apply-message "Tone in row draft; Apply or Save in line reading settings"
           :save-message "Tone in row draft; Save in line reading settings"))))
(defun emacsvox-reading-settings--tones ()
  "Stage three distinct short sine tones, preserving each placement and volume."
  (interactive)
  (dolist (type '(first middle last))
    (emacsvox-reading-settings--stage (emacsvox-reading-lines--key type 'sound) 'tone)
    (emacsvox-reading-settings--stage
     (emacsvox-reading-lines--key type 'tone)
     (plist-get emacsvox-reading-lines--factory (emacsvox-reading-lines--key type 'tone))))
  (emacsvox-reading-settings--say "Three distinct tones in draft"))
(defun emacsvox-reading-settings--off ()
  "Stage silence for all continuation sounds and spoken descriptions."
  (interactive)
  (dolist (type '(first middle last))
    (emacsvox-reading-settings--stage (emacsvox-reading-lines--key type 'sound) 'off))
  (emacsvox-reading-settings--stage :speech 'off)
  (emacsvox-reading-settings--say "Continuation feedback off in draft"))
(defun emacsvox-reading-settings--status ()
  "Read Help and effective settings, then q returns to the same draft."
  (interactive)
  (transient--display-help (lambda (_) (emacsvox-reading-settings--status-content)) nil))
(defun emacsvox-reading-settings--status-content ()
  "Show applied values, inheritance and any unavailable sound capabilities."
  (interactive)
  (let ((source (emacsvox-reading-settings--source)) (draft (emacsvox-reading-settings--values)))
    (with-help-window (help-buffer)
      (princ "Line reading and wrapping\n\n")
      (princ "Choices edit a draft. Apply affects this session; Save persists mode or global choices through Customize. Buffer scope is temporary. Follow wider settings removes this scope's overrides. Factory values explicitly restore the defaults. Discard leaves applied changes intact.\n\n")
      (princ "Whole source lines controls ordinary Up/Down and speech. Wrapped rows enables Visual Line mode. Tables, terminal navigation and other integration-owned commands keep their own behaviour. C-e l always reads the whole source line.\n\n")
      (princ "First means more text below; middle means text above and below; last means text above. A complete line has no continuation cue. Before, Alongside and After apply to the complete spoken item. Moving away or Stop cancels its remaining sound. No sound is silently moved to another placement.\n\n")
      (princ "Each row has an independent sound, volume and timing. Choose a cue, or use the recording library to audition and explicitly assign a recording to wrapped-line-first, wrapped-line-middle or wrapped-line-last in a personal sound pack. Library W saves pack-wide assignments independently of this draft.\n\nApplied source preferences:\n")
      (with-current-buffer source
        (let ((values (emacsvox-reading-lines--values)))
          (while values
            (let ((key (pop values)) (value (pop values)))
              (princ (format "%s: %S (%s)\n" key value (emacsvox-reading-lines--origin key))))))
        (princ (format "Actual navigation: %s\n" (if (or visual-line-mode line-move-visual) "screen rows" "source lines"))))
      (dolist (type '(first middle last))
        (when-let* ((reason (emacsvox-reading-lines--sound-unavailable draft type)))
          (princ (format "\n%s: %s. Saved placement remains %s.\n" type reason
                         (plist-get draft (emacsvox-reading-lines--key type 'placement))))))))
    (pop-to-buffer (help-buffer)))
(defun emacsvox-reading-settings--inspect ()
  "Speak the captured source line and its rendered row position without moving it."
  (interactive)
  (emacsvox-aural-menu--call-at-item #'emacsvox-speak-row-position))
(defun emacsvox-reading-settings--row-title ()
  "Describe the selected row and any unavailable draft sound."
  (let* ((type (emacsvox-reading-settings--row-type))
         (reason (emacsvox-reading-lines--sound-unavailable (emacsvox-reading-settings--values) type)))
    (format "%s row%s" type (if reason (concat "; " reason) ""))))
(transient-define-prefix emacsvox-reading-settings--row ()
  "Edit one row's sound without changing other row identities or applying drafts."
  :refresh-suffixes t
  [:description emacsvox-reading-settings--row-title
   ("s" (lambda () (emacsvox-reading-settings--label (emacsvox-reading-settings--row-key 'sound) "Sound")) emacsvox-reading-settings--sound :transient transient--do-stack)
   ("e" (lambda () (emacsvox-reading-settings--label (emacsvox-reading-settings--row-key 'cue) "Recorded cue")) emacsvox-reading-settings--earcon :transient t)
   ("l" "Recording library (separate pack assignments)" emacsvox-reading-settings--library)
   ("t" "Tone pitch, duration and shape" emacsvox-reading-settings--tone :transient transient--do-stack)
   ("p" (lambda () (emacsvox-reading-settings--label (emacsvox-reading-settings--row-key 'placement) "Placement")) emacsvox-reading-settings--placement :transient transient--do-stack)
   ("v" (lambda () (emacsvox-reading-settings--label (emacsvox-reading-settings--row-key 'volume) "Volume")) emacsvox-reading-settings--volume :transient t)]
  ["Listen and return"
   ("SPC" "Preview this row's draft" emacsvox-reading-settings--preview-row :transient t)
   ("x" "Stop preview and speech" emacsvox-reading-settings--stop :transient t)
   ("q" "Back with draft" transient-quit-one)])

;;;###autoload
(transient-define-prefix emacsvox-reading-settings ()
  "Configure source-line reading and independent wrapped-row feedback.
Entry and browsing preserve current behaviour. Apply changes the selected
scope for this session; Save and apply persists mode or global choices.
Integration-owned navigation may take priority; Help shows effective values."
  :refresh-suffixes t
  [:description emacsvox-reading-settings--title
   ("m" (lambda () (emacsvox-reading-settings--label :mode "Reading unit")) emacsvox-reading-settings--mode :transient transient--do-stack)
   ("s" (lambda () (emacsvox-reading-settings--label :speech "Spoken continuation")) emacsvox-reading-settings--speech :transient transient--do-stack)
   ("f" (lambda () (emacsvox-reading-settings--label :frequency "Feedback frequency")) emacsvox-reading-settings--frequency :transient transient--do-stack)
   ("g" "Choose buffer, mode or global scope" emacsvox-reading-settings--scope :transient transient--do-stack)]
  ["Independent row feedback"
   ("1" "First row: source line continues below" emacsvox-reading-settings--first :transient transient--do-stack)
   ("2" "Middle row: continues above and below" emacsvox-reading-settings--middle :transient transient--do-stack)
   ("3" "Last row: source line continues above" emacsvox-reading-settings--last :transient transient--do-stack)
   ("t" "Stage three distinct tones" emacsvox-reading-settings--tones :transient t)
   ("o" "Stage all continuation feedback off" emacsvox-reading-settings--off :transient t)
   ("P" "Stage one placement for all three sounds" emacsvox-reading-settings--all-placement :transient transient--do-stack)
   ("V" "Stage one volume for all three sounds" emacsvox-reading-settings--all-volume :transient t)]
  ["Preview and inspect"
   ("p" "Preview draft sequence" emacsvox-reading-settings--preview :transient t)
   ("c" "Compare applied sequence" emacsvox-reading-settings--compare :transient t)
   ("x" "Stop preview and speech" emacsvox-reading-settings--stop :transient t)
   ("=" "Inspect source line and screen row" emacsvox-reading-settings--inspect :transient t)
   ("h" "Help, applied values and worker support" emacsvox-reading-settings--status :transient transient--do-suspend)]
  ["Apply, save and restore"
   ("a" "Apply at selected scope for this session" emacsvox-reading-settings--apply :transient t)
   ("S" "Save and apply mode or global choices" emacsvox-reading-settings--save :transient t)
   ("i" "Stage following wider settings" emacsvox-reading-settings--inherit :transient t)
   ("r" "Stage factory defaults" emacsvox-reading-settings--factory :transient t)
   ("d" "Discard unapplied edits" emacsvox-reading-settings--discard :transient t)
   ("q" "Back; discard unapplied edits" transient-quit-one)
   ("C-q" "Close menus; discard unapplied edits" transient-quit-all)]
  (interactive)
  (let ((context (condition-case nil (emacsvox-aural-menu--context)
                   (user-error (emacsvox-aural-menu--capture nil)))))
    (transient-setup 'emacsvox-reading-settings nil nil :scope context)))

(provide 'emacsvox-reading-settings)
;;; emacsvox-reading-settings.el ends here
