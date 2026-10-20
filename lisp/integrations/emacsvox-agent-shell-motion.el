;;; emacsvox-agent-shell-motion.el --- Agent Shell visual movement and input boundaries  -*- lexical-binding: t; -*-

;; Copyright (C) 2025, T. V. Raman
;; Copyright (C) 2026 Emacsvox contributors
;; All Rights Reserved.
;; SPDX-License-Identifier: GPL-2.0-or-later

;; Author: T. V. Raman <tv.raman.tv@gmail.com>
;; Maintainer: Emacsvox contributors
;; Keywords: Emacsvox,  Audio Desktop agent-shell
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

;; Map rendered chat rows, labels, folds and padding to source positions.
;; Keep visual movement, editable prompt boundaries and line speech together,
;; including their dynamic context and buffer-local command hooks. Semantic
;; block and source navigation remain in `emacsvox-agent-shell-navigation'.
;; The facade retains advice installation and activation order. Load through
;; `emacsvox-agent-shell'; loading definitions does not install command hooks.

;;; Code:

(require 'cl-lib)
(require 'map)
(require 'seq)
(require 'subr-x)
(require 'emacsvox-preamble)
(require 'emacsvox-agent-shell-presentation)
(require 'emacsvox-agent-shell-navigation)

(defvar comint-last-prompt)
(defvar emacsvox-show-point)
(defvar ems--speak-max-length)
(defvar emacsvox-agent-shell-status-speech-labels)
(defvar emacsvox-agent-shell-line-speech-max-characters)
(declare-function agent-shell-status "agent-shell" t)
(declare-function agent-shell-elicitation--pending-p "agent-shell-elicitation" t)
(declare-function emacsvox-speak-region
                  "emacsvox-speak" (start end))
(declare-function emacsvox-agent-shell--presentation-facts
                  "emacsvox-agent-shell-presentation" (role &optional event states attributes))
(declare-function emacsvox-agent-shell--submit-text-feedback
                  "emacsvox-agent-shell-presentation" (text facts occasion &optional icon delivery-policy replacement-key))
(declare-function emacsvox-agent-shell--block-location-facts
                  "emacsvox-agent-shell-navigation" (location &optional event))
(declare-function emacsvox-agent-shell--block-location-at-point
                  "emacsvox-agent-shell-navigation" (&optional position))
(declare-function emacsvox-agent-shell--table-text-motion
                  "emacsvox-agent-shell-tables" (target direction count word-p))
(declare-function emacsvox-agent-shell--speech-copy-without-yank-handler
                  "emacsvox-agent-shell-render" (text))
(declare-function emacsvox-agent-shell--prompt-face-spec-p
                  "emacsvox-agent-shell-render" (spec))
(declare-function emacsvox-agent-shell--chat-label-rendering
                  "emacsvox-agent-shell-render" (rendered))
(declare-function emacsvox-agent-shell--without-leading-chat-prompt
                  "emacsvox-agent-shell-render" (text))
(declare-function emacsvox-agent-shell--status-at
                  "emacsvox-agent-shell-render" (text position))
(declare-function emacsvox-agent-shell--remove-visual-chrome-for-speech
                  "emacsvox-agent-shell-render" (text))

;;;  Helper Functions

(defvar emacsvox-agent-shell-input-activation)
(defvar emacsvox-agent-shell-input-state-feedback)
(defvar emacsvox-agent-shell--viewport-submission)
(defvar emacsvox-agent-shell--speech-control-active)
(declare-function agent-shell--point-in-live-input-p "agent-shell-prompt" ())
(declare-function agent-shell--prompt-input-start "agent-shell-prompt" ())
(declare-function agent-shell--prompt-input "agent-shell-prompt" ())
(declare-function emacsvox-agent-shell--prompt-compose-after "emacsvox-agent-shell" (&rest args))
(declare-function emacsvox-agent-shell--viewport-submit-disposition
                  "emacsvox-agent-shell-interaction" ())
(declare-function emacsvox-agent-shell--viewport-submit-announcement
                  "emacsvox-agent-shell-interaction" (disposition keep-composing dismiss))
(declare-function emacsvox-agent-shell--submit-text-feedback
                  "emacsvox-agent-shell-presentation"
                  (text facts occasion &optional icon delivery-policy replacement-key))

(defvar-local emacsvox-agent-shell--input-active nil
  "Non-nil when explicit inline input activation is enabled in this shell.")
(defvar-local emacsvox-agent-shell--input-editing nil
  "Non-nil when inline input has been explicitly activated.")
(defvar-local emacsvox-agent-shell--input-read-only-saved nil
  "Saved read-only value in a list while browse mode owns buffer protection.")
(defvar emacsvox-agent-shell--input-interactive-submit nil
  "Non-nil during an interactive override submission.")

(defun emacsvox-agent-shell--input-browsing-p ()
  "Whether this shell uses explicit input activation and is browsing."
  (and (derived-mode-p 'agent-shell-mode)
       emacsvox-agent-shell--speech-control-active
       (eq emacsvox-agent-shell-input-activation 'explicit)
       (not emacsvox-agent-shell--input-editing)))

(defun emacsvox-agent-shell--input-unlock ()
  "Restore the buffer protection owned by explicit browsing."
  (when emacsvox-agent-shell--input-read-only-saved
    (setq buffer-read-only (car emacsvox-agent-shell--input-read-only-saved)
          emacsvox-agent-shell--input-read-only-saved nil)))

(defun emacsvox-agent-shell--input-sync ()
  "Synchronize inline input protection with the effective setting."
  (let ((active (and (derived-mode-p 'agent-shell-mode)
                     emacsvox-agent-shell--speech-control-active
                     (eq emacsvox-agent-shell-input-activation 'explicit))))
    (unless (eq (not (null active)) emacsvox-agent-shell--input-active)
      (setq emacsvox-agent-shell--input-editing nil))
    (setq emacsvox-agent-shell--input-active (not (null active)))
    (if (and active (not emacsvox-agent-shell--input-editing))
        (progn
          (unless emacsvox-agent-shell--input-read-only-saved
            (setq emacsvox-agent-shell--input-read-only-saved (list buffer-read-only)))
          (setq buffer-read-only t))
      (emacsvox-agent-shell--input-unlock))
    (force-mode-line-update)))

(defun emacsvox-agent-shell--input-feedback (state)
  "Announce input STATE using the selected speech and earcon preference."
  (let* ((speech (memq emacsvox-agent-shell-input-state-feedback '(speech both)))
         (arguments
          (list
           :facts (emacsvox-agent-shell--presentation-facts
                   'agent-prompt-editor 'agent-input-state-changed nil
                   (list :agent-input-state state))
           :module 'agent-shell :occasion 'state-change
           :lane 'main :delivery-policy 'replaceable
           :replacement-key 'speaker :interruption-policy 'lane
           :compatibility-actions
           (when (memq emacsvox-agent-shell-input-state-feedback '(earcon both))
             (list (emacsvox-aural-compatibility-icon
                    (if (eq state 'editing) 'agent-input-on 'agent-input-off)))))))
    (if speech
        (apply #'emacsvox-aural-submit
               (if (eq state 'editing) "Editing" "Browsing") arguments)
      (apply #'emacsvox-aural-submit-actions arguments))))

(defun emacsvox-agent-shell-edit-input ()
  "Activate inline input, preserving a draft and its current editing position.
From the transcript, move to the end of the live draft.  In Explicit mode,
`C-c e' returns to browsing without sending or discarding text."
  (interactive)
  (unless (and (derived-mode-p 'agent-shell-mode)
               (agent-shell--prompt-input-start))
    (user-error "No live input; use M-x agent-shell-prompt-compose"))
  (emacsvox-agent-shell--input-unlock)
  (when buffer-read-only (user-error "This buffer is read-only"))
  (unless (agent-shell--point-in-live-input-p) (goto-char (point-max)))
  (setq emacsvox-agent-shell--input-editing t)
  (emacsvox-agent-shell--input-sync)
  (emacsvox-agent-shell--input-feedback 'editing))

(defun emacsvox-agent-shell-browse ()
  "Return to Explicit browsing at point, preserving the live draft and undo."
  (interactive)
  (unless (and (derived-mode-p 'agent-shell-mode)
               (eq emacsvox-agent-shell-input-activation 'explicit))
    (user-error "Choose Explicit input activation in Agent Shell settings first"))
  (setq emacsvox-agent-shell--input-editing nil)
  (emacsvox-agent-shell--input-sync)
  (emacsvox-agent-shell--input-feedback 'browsing))

(defun emacsvox-agent-shell--input-post-command ()
  "Return to browsing when editing navigation leaves the live input."
  (let ((left-input
         (and emacsvox-agent-shell--input-active
              emacsvox-agent-shell--input-editing
              (not (agent-shell--point-in-live-input-p)))))
    (when left-input
      (setq emacsvox-agent-shell--input-editing nil))
    (emacsvox-agent-shell--input-sync)
    (when (and left-input
               (memq emacsvox-agent-shell-input-state-feedback '(earcon both)))
      ;; Navigation already speaks the destination on the main lane.
      ;; Signal the boundary separately without replacing or stopping it.
      (emacsvox-aural-submit-actions
       :facts (emacsvox-agent-shell--presentation-facts
               'agent-prompt-editor 'agent-input-state-changed nil
               '(:agent-input-state browsing))
       :module 'agent-shell :occasion 'state-change
       :lane 'notification :delivery-policy 'ordered :interruption-policy 'none
       :compatibility-actions
       (list (emacsvox-aural-compatibility-icon 'agent-input-off))))))

(defun emacsvox-agent-shell--input-typing-p (typing)
  "Keep upstream character TYPING only while input is editable."
  (and typing (not (emacsvox-agent-shell--input-browsing-p))))

(defun emacsvox-agent-shell--input-return-filter (command)
  "Offer COMMAND at the live prompt, its label and adjoining blank rows."
  (when (and (emacsvox-agent-shell--input-browsing-p)
             (agent-shell--prompt-input-start))
    (let ((prompt-start (marker-position (car comint-last-prompt))))
      (when (or (>= (point) prompt-start)
                (and
                 ;; Contextual buttons retain their own Return action.
                 (not (get-char-property (point) 'keymap))
                 (>= (point)
                     (save-excursion
                       (goto-char prompt-start)
                       (skip-chars-backward " \t\n")
                       ;; Keep the preceding content line, including its
                       ;; terminating newline, outside the activation area.
                       (unless (bolp) (forward-line 1))
                       (min prompt-start (point))))))
        command))))

(defvar emacsvox-agent-shell--input-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c i") #'emacsvox-agent-shell-edit-input)
    (define-key map (kbd "C-c e") #'emacsvox-agent-shell-browse)
    (dolist (key '("RET" "<return>"))
      (define-key map (kbd key)
                  '(menu-item "Edit input" emacsvox-agent-shell-edit-input
                              :filter emacsvox-agent-shell--input-return-filter)))
    map)
  "Explicit input keys, active only in inline Agent Shell buffers.")
(add-to-list 'minor-mode-map-alist
             (cons 'emacsvox-agent-shell--input-active emacsvox-agent-shell--input-map))
(add-to-list 'minor-mode-alist
             '(emacsvox-agent-shell--input-active
               (:eval (if emacsvox-agent-shell--input-editing " Agent edit" " Agent browse"))))

(defun emacsvox-agent-shell--input-submit-override-around (original &rest args)
  "Preserve interactive intent while ORIGINAL delegates submission with ARGS."
  (let ((emacsvox-agent-shell--input-interactive-submit
         (called-interactively-p 'any)))
    (apply original args)))

(defun emacsvox-agent-shell--input-submit-around (original &rest args)
  "Run ORIGINAL with ARGS, returning to browsing after a consumed draft.
Rejected submissions retain their edit state.  Explicit interactive submission
requires editing first; programmatic context submission retains upstream policy."
  (when (and (emacsvox-agent-shell--input-browsing-p)
             (or (called-interactively-p 'any)
                 emacsvox-agent-shell--input-interactive-submit))
    (user-error "Browse mode; press RET at the prompt or C-c i to edit input"))
  (let* ((buffer (current-buffer))
         (draft (and emacsvox-agent-shell--input-active
                     (agent-shell--prompt-input)))
         (announce (and draft
                        (not emacsvox-agent-shell--viewport-submission)
                        (or (called-interactively-p 'any)
                            emacsvox-agent-shell--input-interactive-submit)))
         (emacsvox-agent-shell--viewport-submission
          (if announce
              (list (emacsvox-agent-shell--viewport-submit-disposition))
            emacsvox-agent-shell--viewport-submission)))
    (prog1 (emacsvox-agent-shell--input-write-around original args)
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (when (and draft emacsvox-agent-shell--input-active
                     (not (equal draft (agent-shell--prompt-input))))
            (setq emacsvox-agent-shell--input-editing nil)
            (emacsvox-agent-shell--input-sync)
            (when announce
              (emacsvox-agent-shell--submit-text-feedback
               (emacsvox-agent-shell--viewport-submit-announcement
                (car emacsvox-agent-shell--viewport-submission) nil nil)
               (emacsvox-agent-shell--presentation-facts
                'agent-prompt-editor 'agent-prompt-submitted nil
                (list :agent-prompt-disposition
                      (or (car emacsvox-agent-shell--viewport-submission) 'sent)))
               'state-change 'task-done))))))))

(defun emacsvox-agent-shell--input-write-around (original args)
  "Allow upstream ORIGINAL with ARGS to manage a browse-protected draft.
Only relax protection owned by this integration, for the duration of the call."
  (let ((inhibit-read-only (or inhibit-read-only
                               (and emacsvox-agent-shell--input-active
                                    emacsvox-agent-shell--input-read-only-saved
                                    (not (car emacsvox-agent-shell--input-read-only-saved))))))
    (apply original args)))

(defun emacsvox-agent-shell--input-compose-around (original &rest args)
  "Allow ORIGINAL with ARGS to transfer a protected draft to its own editor."
  (let ((shell (current-buffer)))
    (prog1 (emacsvox-agent-shell--input-write-around original args)
      (when (buffer-live-p shell)
        (with-current-buffer shell
          (when emacsvox-agent-shell--input-active
            (setq emacsvox-agent-shell--input-editing nil)
            (emacsvox-agent-shell--input-sync))))
      (emacsvox-agent-shell--prompt-compose-after))))

(defun emacsvox-agent-shell--input-setup ()
  "Install explicit input state tracking in this shell."
  (add-hook 'pre-command-hook #'emacsvox-agent-shell--input-sync nil t)
  (add-hook 'post-command-hook #'emacsvox-agent-shell--input-post-command nil t)
  (emacsvox-agent-shell--input-sync))

(defun emacsvox-agent-shell--input-cleanup ()
  "Release input protection and remove its hooks from this buffer."
  (emacsvox-agent-shell--input-unlock)
  (setq emacsvox-agent-shell--input-active nil
        emacsvox-agent-shell--input-editing nil)
  (remove-hook 'pre-command-hook #'emacsvox-agent-shell--input-sync t)
  (remove-hook 'post-command-hook #'emacsvox-agent-shell--input-post-command t)
  (force-mode-line-update))

(defun emacsvox-agent-shell--input-refresh ()
  "Apply input activation defaults to existing supported shells."
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (and (derived-mode-p 'agent-shell-mode)
                 (bound-and-true-p emacsvox-agent-shell--speech-control-active))
        (emacsvox-agent-shell--input-sync)))))

(defvar emacsvox-agent-shell--chat-label-context nil
  "Dynamically bound visible chat label for the current line speech.")

(defconst emacsvox-agent-shell--end-of-prompt-marker
  "<shell-maker-end-of-prompt>"
  "Text of Shell Maker's property-authenticated prompt delimiter.")

(defun emacsvox-agent-shell--prompt-face-between-p (start end)
  "Return non-nil when prompt face text occurs between START and END."
  (let ((position start)
        found)
    (while (and (< position end) (not found))
      (setq
       found
       (or
        (emacsvox-agent-shell--prompt-face-spec-p
         (get-text-property position 'face))
        (emacsvox-agent-shell--prompt-face-spec-p
         (get-text-property position 'font-lock-face))))
      (unless found
        (setq
         position
         (min
          (or (next-single-property-change position 'face nil end) end)
          (or
           (next-single-property-change position 'font-lock-face nil end)
           end)))))
    found))

(defun emacsvox-agent-shell--chat-overlay-tag (overlay)
  "Return the normalized structural chat tag represented by OVERLAY.
Current Agent Shell uses `agent-shell-chat--tag'.  Releases before
2026-08-29 used overlay `category' values instead."
  (or
   (overlay-get overlay 'agent-shell-chat--tag)
   (pcase (overlay-get overlay 'category)
     ('agent-shell-chat-me 'me)
     ('agent-shell-chat-me-label 'me-label)
     ('agent-shell-chat-me-surplus 'me-surplus)
     ('agent-shell-chat-me-input 'me-input)
     ('agent-shell-chat-agent 'agent))))

(defun emacsvox-agent-shell--chat-overlay-category (overlay)
  "Return the semantic chat category represented by OVERLAY."
  (pcase (emacsvox-agent-shell--chat-overlay-tag overlay)
    ((or 'me 'me-label) 'agent-shell-chat-me)
    ('agent 'agent-shell-chat-agent)))

(defun emacsvox-agent-shell--chat-overlay-rendering (overlay)
  "Return the visible label rendering supplied by chat OVERLAY."
  (seq-find
   (lambda (candidate)
     (and (stringp candidate)
          (not (string-empty-p (string-trim candidate)))))
   (list (overlay-get overlay 'before-string)
         ;; The live `me' overlay displays the input marker, not the name.
         ;; Its name is either in its before-string or a separate label row.
         (unless (eq (emacsvox-agent-shell--chat-overlay-tag overlay) 'me)
           (overlay-get overlay 'display)))))

(defun emacsvox-agent-shell--chat-label-predecessors (overlays)
  "Include adjacent label rows preceding chat OVERLAYS.
Recent Agent Shell draws each label row on a separate source character.
The overlay ending at the response can therefore hide only padding; follow
contiguous overlays of the same role back to the row carrying its name.
Never cross intervening content or inspect unrelated transcript overlays."
  (let ((result (copy-sequence overlays))
        (pending (copy-sequence overlays)))
    (while pending
      (let* ((overlay (pop pending))
             (category (emacsvox-agent-shell--chat-overlay-category overlay))
             (start (overlay-start overlay)))
        (when (and category (> start (point-min)))
          (dolist (previous (overlays-in (1- start) start))
            (when (and (= (overlay-end previous) start)
                       (< (overlay-start previous) start)
                       (eq category
                           (emacsvox-agent-shell--chat-overlay-category previous))
                       (not (memq previous result)))
              (push previous result)
              (push previous pending))))))
    result))

(defun emacsvox-agent-shell--live-chat-prompt-overlay-p (overlay)
  "Return non-nil when OVERLAY carries Agent Shell's live prompt marker."
  (and
   (eq (emacsvox-agent-shell--chat-overlay-tag overlay) 'me)
   (seq-some
    (lambda (candidate)
      (and (stringp candidate)
           (not (string-empty-p (string-trim candidate)))))
    (list (overlay-get overlay 'display)
          (overlay-get overlay 'line-prefix)
          (overlay-get overlay 'wrap-prefix)))))

(defun emacsvox-agent-shell--chat-label-context-between
    (source-start source-end)
  "Return the visible chat label context between SOURCE-START and SOURCE-END.
The optional chat mode renders labels as overlays, so this adapter captures
their semantic text without changing the underlying shell buffer.  An overlay
ending at SOURCE-START labels the content that follows it."
  (let* ((source-start
          (min (point-max) (max (point-min) source-start)))
         (source-end (min (point-max) (max source-start source-end)))
         (overlays
          (delete-dups
           (append
            ;; Chat labels often consume the whitespace before their content,
            ;; so the matching overlay ends exactly where the spoken line
            ;; begins.  Do not include overlays that merely begin at the line
            ;; end: those label the following turn.
            (and (> source-start (point-min))
                 (seq-filter
                  (lambda (candidate)
                    (= (overlay-end candidate) source-start))
                  (overlays-in (1- source-start) source-start)))
            (and (< source-start source-end)
                 (overlays-in source-start source-end)))))
         (chat-overlays
          (emacsvox-agent-shell--chat-label-predecessors
           (seq-filter
            (lambda (candidate)
              (emacsvox-agent-shell--chat-overlay-category candidate))
            overlays)))
         (preferred-category
          (and
           (cdr chat-overlays)
           (cond
            ((emacsvox-agent-shell--prompt-face-between-p
              source-start source-end)
             'agent-shell-chat-me)
            ((save-excursion
               (goto-char source-start)
               (text-property-any
                source-start source-end 'shell-maker--marker t))
             'agent-shell-chat-agent))))
         (overlay
          (or
           (and preferred-category
                (seq-find
                 (lambda (candidate)
                   (eq (emacsvox-agent-shell--chat-overlay-category candidate)
                       preferred-category))
                 (seq-filter
                  #'emacsvox-agent-shell--chat-overlay-rendering
                  chat-overlays)))
           (seq-find
            #'emacsvox-agent-shell--chat-overlay-rendering
            chat-overlays))))
    (when overlay
      (let* ((category
              (emacsvox-agent-shell--chat-overlay-category overlay))
             (rendered
              (emacsvox-agent-shell--chat-overlay-rendering overlay))
             (label-rendering
              (emacsvox-agent-shell--chat-label-rendering rendered))
             (label (car label-rendering)))
        (when label
          (append
           (list :category category :text label)
           (when (and
                  (eq category 'agent-shell-chat-me)
                  (or (cdr label-rendering)
                      (seq-some
                       #'emacsvox-agent-shell--live-chat-prompt-overlay-p
                       chat-overlays)))
             '(:editable t))))))))

(defun emacsvox-agent-shell--chat-label-context-at-point ()
  "Return the visible agent-shell chat label context on the current line."
  ;; Comint's input field starts after the prompt.  Include the whole physical
  ;; line so its preceding Me label wins over the decorative prompt marker.
  (let ((inhibit-field-text-motion t))
    (emacsvox-agent-shell--chat-label-context-between
     (line-beginning-position) (line-end-position))))

(defun emacsvox-agent-shell--visual-line-source-bounds ()
  "Return the current visual line's underlying source bounds."
  (save-excursion
    (let ((inhibit-field-text-motion t))
      (beginning-of-visual-line)
      (let ((start (point)))
        (end-of-visual-line)
        (cons start (point))))))

(defun emacsvox-agent-shell--response-row-source-bounds (bounds)
  "Return visible response bounds when BOUNDS starts in its hidden marker.
The chat indent can make visual motion land in the empty display overlay
before the first response character, including when approaching from below."
  (let ((start (car bounds)) (end (cdr bounds)))
    (when (get-text-property start 'shell-maker--marker)
      (cl-loop for overlay in (overlays-at start)
               when (and (eq (emacsvox-agent-shell--chat-overlay-tag overlay)
                             'agent)
                         (equal (overlay-get overlay 'display) "")
                         (< start (overlay-end overlay))
                         (< (overlay-end overlay) end))
               return (cons (overlay-end overlay) end)))))

(defun emacsvox-agent-shell--live-prompt-state-speech ()
  "Briefly describe a non-idle prompt's state, or return nil."
  (let ((status (condition-case nil
                    (agent-shell-status :shell-buffer (current-buffer))
                  (error 'unknown))))
    (pcase status
      ('ready nil)
      ('busy "Agent busy.")
      ('blocked (if (agent-shell-elicitation--pending-p)
                    "Waiting for an answer."
                  "Waiting for permission."))
      (_ "Input state unavailable."))))

(defun emacsvox-agent-shell--add-chat-label-for-speech (text)
  "Return TEXT prefixed by the visible chat label captured for speech."
  (if-let* ((context emacsvox-agent-shell--chat-label-context)
            (label (plist-get context :text)))
      (let* ((category (plist-get context :category))
             (explicit-input (and (plist-get context :editable)
                                  emacsvox-agent-shell--input-active))
             (label (if explicit-input "Input" label))
             (prompt-state
              (when (plist-get context :editable)
                (emacsvox-agent-shell--live-prompt-state-speech)))
             (content
              (if (eq category 'agent-shell-chat-me)
                  (emacsvox-agent-shell--without-leading-chat-prompt text)
                text))
             (plain (substring-no-properties content))
             (marker-start
              (and
               (eq category 'agent-shell-chat-agent)
               (string-match "\\`[ \t\n\r]*" plain)
               (match-end 0)))
             (marker-end
              (and
               marker-start
               (< marker-start (length content))
               (get-text-property
                marker-start 'shell-maker--marker content)
               (string-prefix-p
                emacsvox-agent-shell--end-of-prompt-marker
                plain marker-start)
               (+ marker-start
                  (length emacsvox-agent-shell--end-of-prompt-marker)))))
        (when marker-end
          (setq content (substring content marker-end)))
        (setq content (string-trim-left content))
        (if (string-empty-p (string-trim (substring-no-properties content)))
            (if (plist-get context :editable)
                (if (and explicit-input (not prompt-state))
                    (concat label ".")
                  (concat label ". " (or prompt-state "Ready for input.")))
              label)
          (concat label ". "
                  (when prompt-state (concat prompt-state " ")) content)))
    text))

(defun emacsvox-agent-shell--replace-status-icons-for-speech (text)
  "Return TEXT with faced agent-shell status icons replaced semantically.
Only the returned speech string is changed.  Replacement words retain the
icon's text properties so its status voice remains available to Emacsvox."
  (let (replacements)
    (dotimes (position (length text))
      (when-let* ((status (emacsvox-agent-shell--status-at text position))
                  (label
                   (map-elt emacsvox-agent-shell-status-speech-labels
                            status)))
        (let ((replacement (format " %s " label)))
          (set-text-properties
           0 (length replacement) (text-properties-at position text)
           replacement)
          ;; Positions are visited in ascending order, so pushing makes this
          ;; list safe to apply from the end of the string toward its start.
          (push (cons position replacement) replacements))))
    (if (null replacements)
        text
      (let ((result text))
        (dolist (replacement replacements result)
          (let ((position (car replacement)))
            (setq result
                  (concat (substring result 0 position)
                          (cdr replacement)
                          (substring result (1+ position))))))))))

(defvar emacsvox-agent-shell--line-navigation-speech-p nil
  "Non-nil while Agent Shell is preparing line-navigation speech.")

(defvar emacsvox-agent-shell--visual-line-kill-p nil
  "Non-nil while an interactive Agent Shell visual-line kill is running.")

(defun emacsvox-agent-shell--limit-line-navigation-speech (text)
  "Return bounded line-navigation speech TEXT for Agent Shell."
  (let ((limit emacsvox-agent-shell-line-speech-max-characters))
    (if (and emacsvox-agent-shell--line-navigation-speech-p
             (integerp limit)
             (> limit 0)
             (> (length text) limit))
        (concat
         (substring text 0 limit)
         (format " [line truncated; %d characters omitted]"
                 (- (length text) limit)))
      text)))

(defun emacsvox-agent-shell--prepare-speech-text (text)
  "Prepare TEXT for speech in agent-shell, leaving other modes unchanged."
  (if (and (stringp text)
           (derived-mode-p 'agent-shell-mode
                           'agent-shell-viewport-view-mode
                           'agent-shell-viewport-edit-mode))
      (let ((text
             (emacsvox-agent-shell--limit-line-navigation-speech text)))
        (emacsvox-agent-shell--add-chat-label-for-speech
         (emacsvox-agent-shell--replace-status-icons-for-speech
          (emacsvox-agent-shell--remove-visual-chrome-for-speech
           (emacsvox-agent-shell--speech-copy-without-yank-handler text)))))
    text))

(defconst emacsvox-agent-shell--vertical-toggle-hint-regexp
  "\\`Press RET to toggle\\'"
  "Exact message pattern for agent-shell's collapsible-label cursor sensor.")

(defconst emacsvox-agent-shell--item-action-hint-regexp
  "\\`Press RET to \\(?:copy\\|open\\)"
  "Message pattern for Agent Shell item actions spoken semantically.")

(defvar-local emacsvox-agent-shell--saved-message-filter nil
  "Saved local-state flag and value for `ems--message-filter'.")

(defvar-local emacsvox-agent-shell--vertical-navigation-active-p nil
  "Non-nil while an interactive vertical movement command is running.")

(defvar-local emacsvox-agent-shell--vertical-navigation-origin nil
  "Semantic block identity captured before vertical movement.")

(defun emacsvox-agent-shell--synthetic-agent-row-p (start end)
  "Return non-nil when START through END repeats an agent chat display row.

Agent Shell's multiline `before-string' can make upward visual motion visit
the hidden response marker and the first response row as one source interval
after that response row was already visited directly."
  (and
   emacsvox-agent-shell--vertical-navigation-active-p
   (< start end)
   (save-excursion
     (goto-char start)
     (search-forward "<shell-maker-end-of-prompt>" end t))
   (seq-some
    (lambda (overlay)
      (and
       (eq (emacsvox-agent-shell--chat-overlay-tag overlay) 'agent)
       (< (overlay-end overlay) end)))
    (overlays-in start end))))

(defun emacsvox-agent-shell--block-location-identity (location)
  "Return a stable identity for semantic block LOCATION."
  (when location
    (list
     (plist-get location :type)
     (plist-get location :position)
     (plist-get location :end))))

(defun emacsvox-agent-shell--vertical-navigation-pre-command ()
  "Remember the semantic block before interactive vertical movement."
  (setq emacsvox-agent-shell--vertical-navigation-active-p
        (memq this-command '(next-line previous-line)))
  (setq emacsvox-aural-command-start-time
        (and emacsvox-agent-shell--vertical-navigation-active-p
             (float-time)))
  (when emacsvox-agent-shell--vertical-navigation-active-p
    (setq emacsvox-agent-shell--vertical-navigation-origin
          (emacsvox-agent-shell--block-location-identity
           (emacsvox-agent-shell--block-location-at-point)))))

(defun emacsvox-agent-shell--vertical-navigation-post-command ()
  "Clear transient vertical block-entry state."
  (setq emacsvox-agent-shell--vertical-navigation-active-p nil
        emacsvox-agent-shell--vertical-navigation-origin nil
        emacsvox-aural-command-start-time nil))

(defun emacsvox-agent-shell--vertical-block-entry-facts ()
  "Return destination facts when vertical movement entered another block."
  (when emacsvox-agent-shell--vertical-navigation-active-p
    (when-let* ((location
                 (emacsvox-agent-shell--block-location-at-point))
                ((not
                  (equal
                   emacsvox-agent-shell--vertical-navigation-origin
                   (emacsvox-agent-shell--block-location-identity
                    location)))))
      (emacsvox-agent-shell--block-location-facts
       location 'focus-entered))))

(defun emacsvox-agent-shell--end-of-prompt-marker-line-p ()
  "Return non-nil when the current line is only a hidden prompt marker."
  (let ((inhibit-field-text-motion t))
    (let ((start (line-beginning-position))
          (end (line-end-position)))
      (and
       (< start end)
       (text-property-any start end 'shell-maker--marker t)
       (string-match-p
        "\\`[ \t]*<shell-maker-end-of-prompt>[ \t]*\\'"
        (buffer-substring-no-properties start end))))))

(defun emacsvox-agent-shell--chat-navigation-source-bounds ()
  "Return the current visual source bounds when they carry a chat label."
  (when (or line-move-visual visual-line-mode)
    (let ((bounds (emacsvox-agent-shell--visual-line-source-bounds)))
      (when (emacsvox-agent-shell--chat-label-context-between
             (car bounds) (cdr bounds))
        bounds))))

(defun emacsvox-agent-shell--chat-padding-source-bounds ()
  "Return inclusive source bounds of chat label padding at point."
  (when-let* ((overlay
               (seq-find
                (lambda (candidate)
                  (memq (emacsvox-agent-shell--chat-overlay-tag candidate)
                        '(me-label me-surplus)))
                (overlays-at (point)))))
    (cons (max (point-min) (overlay-start overlay))
          (min (1- (point-max)) (1- (overlay-end overlay))))))

(defun emacsvox-agent-shell--adjacent-chat-padding-source-bounds (direction)
  "Return chat padding immediately beyond this visual row in DIRECTION."
  (when (or line-move-visual visual-line-mode)
    (save-excursion
      (let* ((bounds (emacsvox-agent-shell--visual-line-source-bounds))
             (position (pcase direction
                         ('forward (1+ (cdr bounds)))
                         ('backward (1- (car bounds))))))
        (when (<= (point-min) position (1- (point-max)))
          (goto-char position)
          (emacsvox-agent-shell--chat-padding-source-bounds))))))

(defun emacsvox-agent-shell--move-beyond-visual-source-row
    (direction bounds)
  "Move in DIRECTION beyond visual source BOUNDS.
Use source positions rather than `line-move', whose retained goal column can
skip a short wrapped continuation after Agent Shell's displayed Me label."
  (goto-char
   (pcase direction
     ('forward
      (min (point-max) (1+ (cdr bounds))))
     ('backward
      (max (point-min) (1- (car bounds)))))))

(defun emacsvox-agent-shell--move-through-prompt-marker (direction)
  "Move in DIRECTION through the current hidden prompt-marker line.
Forward movement uses the next logical line.  Backward movement lands on the
last source position of the preceding line, which preserves its final wrapped
visual row instead of inheriting a goal column that can skip it."
  (pcase direction
    ('forward
     (forward-line 1))
    ('backward
     (goto-char (max (point-min) (1- (line-beginning-position)))))))

(defun emacsvox-agent-shell--present-current-navigation-line ()
  "Present the current line after Agent Shell normalizes vertical motion."
  (let* ((facts (copy-tree emacsvox-aural-submission-facts))
         (events
          (append
           (copy-sequence (plist-get facts :events))
           '(focus-entered)))
         (emacsvox-aural-submission-facts
          (plist-put facts :events (delete-dups events)))
         (emacsvox-aural-submission-occasion 'navigation))
    (if (or line-move-visual visual-line-mode)
        (emacsvox-speak-visual-line)
      (emacsvox-speak-line))))

(defun emacsvox-agent-shell--normalize-folded-heading-position ()
  "Keep a collapsed heading's visual end inside its actionable text.

Visual motion can retain a goal column past the heading and land after its
invisible body.  That padding newline shares the heading's display row but
has neither its fragment state nor its RET binding."
  (when (and (or line-move-visual visual-line-mode)
             (> (point) (point-min))
             (or (eobp) (eq (char-after) ?\n))
             (not (get-text-property (point) 'agent-shell-ui-state))
             (not (invisible-p (point)))
             (get-text-property (1- (point)) 'invisible)
             (invisible-p (1- (point))))
    (let* ((hidden-start
            (previous-single-property-change
             (point) 'invisible nil (point-min)))
           (heading-position (1- hidden-start)))
      (when (and (>= heading-position (point-min))
                 (not (invisible-p heading-position))
                 (map-elt (get-text-property
                           heading-position 'agent-shell-ui-state)
                          :collapsed)
                 (memq (get-text-property
                        heading-position 'agent-shell-ui-section)
                       '(indicator label-left label-right)))
        ;; Retain the last display row when the heading itself wraps.
        (goto-char heading-position)))))

(defun emacsvox-agent-shell--vertical-motion-around
    (original-function nominal-direction arguments)
  "Normalize presentational chat rows during interactive vertical motion.

ORIGINAL-FUNCTION receives ARGUMENTS.  NOMINAL-DIRECTION is the direction of
a positive argument to the advised command."
  (let* ((target ems--interactive-fn-name)
         (interactive-p (memq target '(next-line previous-line)))
         (count (prefix-numeric-value (car arguments)))
         (normalize-p
          (and interactive-p
               (/= count 0)
               (derived-mode-p 'agent-shell-mode)))
         (direction
          (if (< count 0)
              (if (eq nominal-direction 'forward) 'backward 'forward)
            nominal-direction))
         (origin-point (point))
         (origin-source-bounds
          (and normalize-p
               (emacsvox-agent-shell--chat-navigation-source-bounds)))
         result)
    ;; Agent Shell may need to move again after the command reaches a display
    ;; alias.  Defer core line speech until that final destination is known.
    (setq result
          (if normalize-p
              (let ((ems--interactive-fn-name nil))
                (condition-case error-data
                    (apply original-function arguments)
                  ((beginning-of-buffer end-of-buffer)
                   ;; A multiline Me label can trap core visual motion at
                   ;; its newline anchor, far from either buffer boundary.
                   (let ((padding
                          (emacsvox-agent-shell--chat-padding-source-bounds)))
                     (unless
                         (and padding
                              (pcase direction
                                ('backward
                                 (and (eq (car error-data) 'beginning-of-buffer)
                                      (> (car padding) (point-min))))
                                ('forward
                                 (and (eq (car error-data) 'end-of-buffer)
                                      (< (cdr padding) (1- (point-max)))))))
                       (signal (car error-data) (cdr error-data)))))))
            (apply original-function arguments)))
    (when normalize-p
      ;; A multiline chat label can also stall motion on the preceding
      ;; ordinary row (for example, Cancelled), outside the label overlay.
      ;; Cross only the adjacent chat padding, and only if motion stalled.
      (when-let* (((= origin-point (point)))
                  (adjacent-padding
                   (emacsvox-agent-shell--adjacent-chat-padding-source-bounds
                    direction)))
        (emacsvox-agent-shell--move-beyond-visual-source-row
         direction adjacent-padding))
      ;; A retained goal column can land in the first response row's hidden
      ;; marker.  Recover its content before skipping marker-only rows.  Do
      ;; not repeat this row when motion started within it.
      (when-let* (((eq direction 'backward))
                  (response-bounds
                   (emacsvox-agent-shell--response-row-source-bounds
                    (emacsvox-agent-shell--visual-line-source-bounds)))
                  ((> origin-point (cdr response-bounds)))
                  ((< (point) (car response-bounds))))
        (goto-char (car response-bounds)))
      (let (previous padding)
        ;; A folded or transient row can make core visual motion return while
        ;; point remains at the row anchor.  Escape when source remains in the
        ;; requested direction instead of presenting that anchor indefinitely.
        (while (and (or
                     (setq padding
                           (emacsvox-agent-shell--chat-padding-source-bounds))
                     (emacsvox-agent-shell--end-of-prompt-marker-line-p)
                     (emacsvox-agent-shell--diff-border-line-p)
                     (and
                      origin-source-bounds
                      (or
                       (/= origin-point (point))
                       (pcase direction
                         ('forward
                          (< (cdr origin-source-bounds) (point-max)))
                         ('backward
                          (> (car origin-source-bounds) (point-min)))))
                      (equal
                       origin-source-bounds
                       (emacsvox-agent-shell--chat-navigation-source-bounds))))
                    (not (eq previous (point))))
          (setq previous (point))
          (cond
           (padding
            (emacsvox-agent-shell--move-beyond-visual-source-row
             direction padding))
           ((or (emacsvox-agent-shell--end-of-prompt-marker-line-p)
                (emacsvox-agent-shell--diff-border-line-p))
            (emacsvox-agent-shell--move-through-prompt-marker direction))
           (t
            (emacsvox-agent-shell--move-beyond-visual-source-row
             direction origin-source-bounds)))))
      (emacsvox-agent-shell--normalize-folded-heading-position)
      ;; Core advice may wrap this adapter when loaded later.  We own the
      ;; final presentation, so do not let that outer advice repeat it.
      (ems-interactive-p target)
      (emacsvox-agent-shell--present-current-navigation-line))
    result))

(defun emacsvox-agent-shell--diff-border-line-p ()
  "Return non-nil on a purely decorative generated diff-heading line."
  (let ((start (line-beginning-position))
        (end (line-end-position)))
    (and (< start end)
         (not (text-property-not-all
               start end 'emacsvox-agent-shell-diff-heading 'border)))))

(defun emacsvox-agent-shell--next-line-around
    (original-function &rest arguments)
  "Normalize Agent Shell presentational rows during downward motion."
  (emacsvox-agent-shell--vertical-motion-around
   original-function 'forward arguments))

(defun emacsvox-agent-shell--previous-line-around
    (original-function &rest arguments)
  "Normalize Agent Shell presentational rows during upward motion."
  (emacsvox-agent-shell--vertical-motion-around
   original-function 'backward arguments))

(defun emacsvox-agent-shell--call-with-vertical-block-entry
    (original-function arguments)
  "Call ORIGINAL-FUNCTION with ARGUMENTS and authoritative entry facts."
  (if-let* ((facts (emacsvox-agent-shell--vertical-block-entry-facts))
            (module 'agent-shell)
            (occasion 'navigation)
            (context
             (emacsvox-aural-capture-context module occasion)))
      (let ((emacsvox-aural-submission-facts facts)
            (emacsvox-aural-submission-context context)
            (emacsvox-aural-submission-module module)
            (emacsvox-aural-submission-occasion occasion))
        (apply original-function arguments))
    (apply original-function arguments)))

(defun emacsvox-agent-shell--restore-message-filter ()
  "Restore the message filter saved before navigation feedback."
  (when emacsvox-agent-shell--saved-message-filter
    (let ((was-local
           (car emacsvox-agent-shell--saved-message-filter))
          (value
           (cdr emacsvox-agent-shell--saved-message-filter)))
      (setq emacsvox-agent-shell--saved-message-filter nil)
      (if was-local
          (setq-local ems--message-filter value)
        (kill-local-variable 'ems--message-filter)))))

(defun emacsvox-agent-shell--filter-message-through-post-command (regexp)
  "Filter messages matching REGEXP until navigation sensors have run."
  (emacsvox-agent-shell--restore-message-filter)
  (setq emacsvox-agent-shell--saved-message-filter
        (cons (local-variable-p 'ems--message-filter)
              ems--message-filter))
  (setq-local
   ems--message-filter
   (if (stringp ems--message-filter)
       (concat "\\(?:" ems--message-filter "\\|" regexp "\\)")
     regexp)))

(defun emacsvox-agent-shell--filter-vertical-toggle-hint ()
  "Temporarily filter the redundant action hint before vertical motion.
Normal Emacsvox line speech describes the collapsible label.  Keep
agent-shell's cursor-sensor message visible, but filter its exact text from
speech until the cursor sensor has run from `post-command-hook'."
  (when (memq this-command '(next-line previous-line))
    (emacsvox-agent-shell--filter-message-through-post-command
     emacsvox-agent-shell--vertical-toggle-hint-regexp)))

(defun emacsvox-agent-shell--vertical-toggle-hint-setup ()
  "Install buffer-local filtering for vertical collapsible-label entry."
  (add-hook 'pre-command-hook
            #'emacsvox-agent-shell--vertical-navigation-pre-command nil t)
  (add-hook 'pre-command-hook
            #'emacsvox-agent-shell--filter-vertical-toggle-hint nil t)
  ;; Cursor sensors run from `post-command-hook'.  Restore afterward so
  ;; non-arrow entry still speaks the action hint.
  (add-hook 'post-command-hook
            #'emacsvox-agent-shell--restore-message-filter t t)
  (add-hook 'post-command-hook
            #'emacsvox-agent-shell--vertical-navigation-post-command t t))

(defun emacsvox-agent-shell--vertical-toggle-hint-cleanup ()
  "Remove vertical collapsible-label filtering from the current buffer."
  (emacsvox-agent-shell--restore-message-filter)
  (emacsvox-agent-shell--vertical-navigation-post-command)
  (remove-hook 'pre-command-hook
               #'emacsvox-agent-shell--vertical-navigation-pre-command t)
  (remove-hook 'pre-command-hook
               #'emacsvox-agent-shell--filter-vertical-toggle-hint t)
  (remove-hook 'post-command-hook
               #'emacsvox-agent-shell--restore-message-filter t)
  (remove-hook 'post-command-hook
               #'emacsvox-agent-shell--vertical-navigation-post-command t))

(defun emacsvox-agent-shell--live-input-bounds ()
  "Return the current live Agent Shell input bounds, or nil.

The chat-mode prompt overlay confirms that `comint-last-prompt' names the
visible live prompt rather than historical output.  User input begins at the
prompt's end and extends to `point-max'."
  (when (and (derived-mode-p 'agent-shell-mode)
             (consp comint-last-prompt))
    (let* ((end-marker (cdr comint-last-prompt))
           (start (and (markerp end-marker)
                       (eq (marker-buffer end-marker) (current-buffer))
                       (marker-position end-marker)))
           (end (point-max)))
      (when (and start
                 (< (point-min) start)
                 (<= start end)
                 (not (text-property-any start end 'field 'output))
                 (seq-some
                  (lambda (overlay)
                    (and (= (overlay-end overlay) start)
                         (emacsvox-agent-shell--live-chat-prompt-overlay-p
                          overlay)))
                  (overlays-in (1- start) start)))
        (cons start end)))))

(defun emacsvox-agent-shell--input-boundary-feedback (boundary)
  "Speak the live prompt input BOUNDARY without a decorative cue."
  (emacsvox-agent-shell--submit-text-feedback
   (if (eq boundary 'beginning)
       "Beginning of input"
     "End of input")
   (emacsvox-agent-shell--presentation-facts
    'agent-user-prompt 'boundary-entered)
   'navigation))

(defun emacsvox-agent-shell--hidden-chat-overlay-at (position direction)
  "Return the hidden chat overlay to cross at POSITION in DIRECTION."
  (let (best)
    (dolist (overlay (overlays-at position))
      (when (and
             (memq (emacsvox-agent-shell--chat-overlay-tag overlay)
                   '(me me-label me-surplus agent))
             ;; Split label rows replace source characters with a nonempty
             ;; display string.  Their underlying prompt/marker is still UI
             ;; source and must not be read one character at a time.
             (stringp (overlay-get overlay 'display))
             (< (overlay-start overlay) (overlay-end overlay))
             (or
              (null best)
              (if (eq direction 'forward)
                  (> (overlay-end overlay) (overlay-end best))
                (< (overlay-start overlay) (overlay-start best)))))
        (setq best overlay)))
    best))

(defun emacsvox-agent-shell--horizontal-chat-destination (direction steps)
  "Return a DIRECTION destination STEPS away across hidden chat source.

Return nil when ordinary character motion would not cross a hidden chat
overlay.  Each hidden overlay counts as no source characters, so a step into
one lands on the next real character in DIRECTION."
  (when (derived-mode-p 'agent-shell-mode)
    (let ((position (point))
          (delta (if (eq direction 'forward) 1 -1))
          crossed
          valid)
      (setq valid t)
      (dotimes (_ steps)
        (let ((next (+ position delta)))
          (if (not (<= (point-min) next (point-max)))
              (setq valid nil)
            (setq position next)
            (let (overlay)
              (while (and valid
                          (setq overlay
                                (emacsvox-agent-shell--hidden-chat-overlay-at
                                 position direction)))
                (setq crossed t
                      position
                      (if (eq direction 'forward)
                          (overlay-end overlay)
                        (1- (overlay-start overlay))))
                (unless (<= (point-min) position (point-max))
                  (setq valid nil)))))))
      (and valid crossed position))))

(defun emacsvox-agent-shell--horizontal-motion-around
    (original-function nominal-direction arguments)
  "Normalize interactive horizontal motion through Agent Shell chat UI.

ORIGINAL-FUNCTION receives ARGUMENTS when motion does not cross a prompt
boundary.  NOMINAL-DIRECTION is the positive-argument direction of the
advised command.  Input boundaries apply only while editing; browsing can
cross them.  Display-only chat source is crossed as one unit before core
character speech runs."
  (let* ((target ems--interactive-fn-name)
         (interactive-p
          (memq target '(left-char right-char backward-char forward-char)))
         (count (prefix-numeric-value (car arguments)))
         (direction
          (if (< count 0)
              (if (eq nominal-direction 'forward) 'backward 'forward)
            nominal-direction))
         (steps (abs count))
         (bounds (and interactive-p
                      (> steps 0)
                      (not (emacsvox-agent-shell--input-browsing-p))
                      (emacsvox-agent-shell--live-input-bounds)))
         (start (car-safe bounds))
         (end (cdr-safe bounds))
         boundary
         chat-destination)
    (when (and bounds (<= start (point)) (<= (point) end))
      (setq boundary
            (pcase direction
              ('backward
               (and (> steps (- (point) start)) 'beginning))
              ('forward
               (and (>= steps (- end (point))) 'end)))))
    (unless boundary
      (setq chat-destination
            (and interactive-p
                 (> steps 0)
                 (emacsvox-agent-shell--horizontal-chat-destination
                  direction steps))))
    (cond
     ((and interactive-p
           (emacsvox-agent-shell--table-text-motion
            target nominal-direction count nil)) nil)
     (boundary
      ;; Consume the interactive marker so core character advice cannot add
      ;; ellipses, "control at", or an end-of-buffer warning if its advice is
      ;; outside this adapter in the current advice order.
      (ems-interactive-p target)
      (goto-char (if (eq boundary 'beginning) start end))
      (emacsvox-agent-shell--input-boundary-feedback boundary)
      nil)
     (chat-destination
      ;; Chat overlays replace the underlying prompt/marker source.  Bypass it so
      ;; core character presentation cannot emit one ellipses icon per hidden
      ;; prompt character, then provide the same destination feedback here.
      (ems-interactive-p target)
      (goto-char chat-destination)
      (and tts-stop-immediately (tts-stop))
      (let ((emacsvox-aural-submission-occasion 'navigation))
        (emacsvox-speak-char t))
      nil)
     (t
      (apply original-function arguments)))))

(defun emacsvox-agent-shell--backward-char-around
    (original-function &rest arguments)
  "Normalize backward character motion, protecting input edges while editing."
  (emacsvox-agent-shell--horizontal-motion-around
   original-function 'backward arguments))

(defun emacsvox-agent-shell--forward-char-around
    (original-function &rest arguments)
  "Normalize forward character motion, protecting input edges while editing."
  (emacsvox-agent-shell--horizontal-motion-around
   original-function 'forward arguments))

(defun emacsvox-agent-shell--speak-live-input-visual-line
    (input-bounds boundary)
  "Speak the editable visual line within INPUT-BOUNDS.
BOUNDARY is `beginning' or `end' and supplies feedback for empty input."
  (pcase-let ((`(,visual-start . ,visual-end)
               (emacsvox-agent-shell--visual-line-source-bounds)))
    (let ((start (max (car input-bounds) visual-start))
          (end (min (cdr input-bounds) visual-end)))
      (if (< start end)
          (let ((emacsvox-agent-shell--chat-label-context nil)
                (emacsvox-agent-shell--line-navigation-speech-p t)
                (emacsvox-show-point nil))
            (emacsvox-speak-region start end))
        (emacsvox-agent-shell--input-boundary-feedback boundary)))))

(defun emacsvox-agent-shell--visual-line-input-around
    (original-function target boundary arguments)
  "Present an interactive live-input visual-line TARGET concisely.
ORIGINAL-FUNCTION receives ARGUMENTS unchanged.  BOUNDARY names the endpoint
selected by TARGET."
  (let* ((interactive-p (eq ems--interactive-fn-name target))
         (ordinary-motion-p
          (= 1 (prefix-numeric-value (car arguments))))
         (bounds (and interactive-p
                      ordinary-motion-p
                      (emacsvox-agent-shell--live-input-bounds)))
         (in-input-p
          (and bounds
               (<= (car bounds) (point))
               (<= (point) (cdr bounds)))))
    (if (not in-input-p)
        (apply original-function arguments)
      ;; Consume the marker before core after-advice runs; this adapter speaks
      ;; the editable visual line without the prompt label or point highlight.
      (ems-interactive-p target)
      (let ((result (apply original-function arguments)))
        (emacsvox-agent-shell--speak-live-input-visual-line bounds boundary)
        result))))

(defun emacsvox-agent-shell--beginning-of-visual-line-around
    (original-function &rest arguments)
  "Read live prompt input after interactive visual-line beginning motion."
  (emacsvox-agent-shell--visual-line-input-around
   original-function 'beginning-of-visual-line 'beginning arguments))

(defun emacsvox-agent-shell--end-of-visual-line-around
    (original-function &rest arguments)
  "Read live prompt input after interactive visual-line end motion."
  (emacsvox-agent-shell--visual-line-input-around
   original-function 'end-of-visual-line 'end arguments))

;;;  Advice Agent-Shell Functions

(defun emacsvox-agent-shell--kill-visual-line-around
    (original-function &rest arguments)
  "Mark an interactive Agent Shell visual-line kill.
Call ORIGINAL-FUNCTION with ARGUMENTS unchanged.  The marker lets the nested
`kill-region' announce its exact bounds instead of repeating the whole prompt
line."
  (let ((emacsvox-agent-shell--visual-line-kill-p
         (and (derived-mode-p 'agent-shell-mode)
              (eq ems--interactive-fn-name 'kill-visual-line))))
    (apply original-function arguments)))

(defun emacsvox-agent-shell--kill-region-around
    (original-function beginning end &rest arguments)
  "Speak an Agent Shell visual-line kill, then call ORIGINAL-FUNCTION.
BEGINNING and END are the exact bounds selected by `kill-visual-line'.
ARGUMENTS are passed to ORIGINAL-FUNCTION unchanged."
  (when emacsvox-agent-shell--visual-line-kill-p
    (let ((emacsvox-agent-shell--chat-label-context nil)
          (emacsvox-agent-shell--line-navigation-speech-p nil))
      (emacsvox-speak-region (min beginning end) (max beginning end))))
  (apply original-function beginning end arguments))

(defun emacsvox-agent-shell--live-input-source-bounds (visual-bounds)
  "Recover an empty or reversed VISUAL-BOUNDS interval in the live prompt.
Prompt display strings can confuse `end-of-visual-line'.  Moving forward
one display row from the draft still locates its end, including wrapped
input.  Keep the prompt source on the first row so speech can name Me."
  (when (<= (cdr visual-bounds) (car visual-bounds))
    (when-let* ((input (emacsvox-agent-shell--live-input-bounds))
                (prompt-start (marker-position (car comint-last-prompt)))
                ((<= prompt-start (point))))
      (save-excursion
        (let ((inhibit-field-text-motion t))
          (goto-char (max (point) (car input)))
          (let* ((physical-end (line-end-position))
                 (start (save-excursion (vertical-motion 0) (point)))
                 (end (progn (vertical-motion 1)
                             (min (point) physical-end))))
            (setq start (if (<= start (car input)) prompt-start start))
            (when (< start end)
              (cons start end))))))))

(defun emacsvox-agent-shell--call-with-folded-heading-cue
    (function arguments)
  "Call FUNCTION with ARGUMENTS, adding a folded cue to its speech submission.
Keep the cue in the same presentation as the heading so aural rules can
replace it and navigation interruption cannot cancel it separately."
  (let ((submit (symbol-function 'emacsvox-aural-submit)))
    (cl-letf
        (((symbol-function 'emacsvox-aural-submit)
          (lambda (text &rest options)
            (apply submit text
                   (plist-put
                    options :compatibility-actions
                    (append (plist-get options :compatibility-actions)
                            (list (emacsvox-aural-compatibility-icon
                                   'ellipses))))))))
      (apply function arguments))))

(defun emacsvox-agent-shell--speak-visual-line-around
    (original-function &rest arguments)
  "Add semantic block-entry context to Agent Shell visual-line speech.

Core visual-line presentation owns blank-line semantics and interruption."
  (unless emacsvox-agent-shell--visual-line-kill-p
    (let* ((state (get-text-property (point) 'agent-shell-ui-state))
           (section (get-text-property (point) 'agent-shell-ui-section))
           (folded-heading-bounds
            (when (and state
                       (map-elt state :collapsed)
                       (memq section '(indicator label-left label-right)))
              (cons (line-beginning-position) (line-end-position))))
           (folded-heading-entry-p
            (and folded-heading-bounds
                 (emacsvox-agent-shell--vertical-block-entry-facts)))
           (source-bounds
            (if folded-heading-bounds
                ;; Invisible bodies can make the display engine treat a complete
                ;; folded fragment as one source span.  Narrowing to its visible
                ;; physical heading retains visual wrapping without copying the
                ;; hidden body or repeating the complete heading on every row.
                (save-restriction
                  (narrow-to-region
                   (car folded-heading-bounds)
                   (cdr folded-heading-bounds))
                  (emacsvox-agent-shell--visual-line-source-bounds))
              (emacsvox-agent-shell--visual-line-source-bounds)))
           (input-source-bounds
            (emacsvox-agent-shell--live-input-source-bounds source-bounds))
           (raw-source-bounds source-bounds)
           (response-source-bounds
            (emacsvox-agent-shell--response-row-source-bounds source-bounds))
           (source-bounds
            (or input-source-bounds response-source-bounds source-bounds))
           (source-start (car source-bounds))
           (source-end (cdr source-bounds))
           (emacsvox-agent-shell--chat-label-context
            (emacsvox-agent-shell--chat-label-context-between
             source-start source-end))
           (emacsvox-agent-shell--line-navigation-speech-p t)
           (ems--speak-max-length
            (if (and
                 (integerp emacsvox-agent-shell-line-speech-max-characters)
                 (> emacsvox-agent-shell-line-speech-max-characters 0))
                most-positive-fixnum
              ems--speak-max-length)))
      (unless
          (emacsvox-agent-shell--synthetic-agent-row-p
           (car raw-source-bounds) (cdr raw-source-bounds))
        (emacsvox-agent-shell--call-with-vertical-block-entry
         (cond
          ((or input-source-bounds response-source-bounds)
           (lambda (&rest _)
             (emacsvox-agent-shell--submit-text-feedback
              (emacsvox-aural-source-substring source-start source-end)
              emacsvox-aural-submission-facts 'navigation)))
          (folded-heading-bounds
           (lambda (&rest call-arguments)
             (save-restriction
               (narrow-to-region
                (car folded-heading-bounds)
                (cdr folded-heading-bounds))
               (if folded-heading-entry-p
                   (emacsvox-agent-shell--call-with-folded-heading-cue
                    original-function call-arguments)
                 (apply original-function call-arguments)))))
          (t original-function))
         arguments)))))

(defun emacsvox-agent-shell--speak-line-around
    (original-function &rest arguments)
  "Add semantic block-entry facts to vertical line speech."
  (let* ((start (line-beginning-position))
         (end (line-end-position))
         (observed-at (float-time)))
    (emacsvox-aural-diagnostic-log-event
     'line-presentation-start
     :command this-command
     :buffer (buffer-name)
     :mode major-mode
     :point (point)
     :line (line-number-at-pos)
     :command-elapsed-ms
     (emacsvox-aural--diagnostic-elapsed-ms
      emacsvox-aural-command-start-time observed-at)
     :content-characters (- end start)
     :content (buffer-substring-no-properties start end))
    (let ((emacsvox-agent-shell--chat-label-context
           (emacsvox-agent-shell--chat-label-context-at-point))
          (emacsvox-agent-shell--line-navigation-speech-p t)
          (ems--speak-max-length
           (if (and
                (integerp emacsvox-agent-shell-line-speech-max-characters)
                (> emacsvox-agent-shell-line-speech-max-characters 0))
               most-positive-fixnum
             ems--speak-max-length)))
      (emacsvox-agent-shell--call-with-vertical-block-entry
       original-function arguments))))

(defun emacsvox-agent-shell--tts-speak-around
    (original-function text &rest arguments)
  "Preserve rendered Markdown properties while speaking agent-shell content.
Native submissions have already transformed and prepared their immutable text,
so this adapter leaves them untouched.  Bare legacy TTS calls are transformed
once without changing agent-shell's clipboard handler or source buffer."
  (apply original-function
         (if (emacsvox-aural-prepared-text-p text)
             text
           (emacsvox-agent-shell--prepare-speech-text text))
         arguments))

(provide 'emacsvox-agent-shell-motion)

;;; emacsvox-agent-shell-motion.el ends here
