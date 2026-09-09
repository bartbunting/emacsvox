;;; emacsvox-aural-voice-context.el --- Contextual voice inspection and editing -*- lexical-binding: t; -*-

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

;; Inspect the existing cascade without flattening it into palette data.
;; Contextual edits use the ordinary scoped rule editor and its save services.

;;; Code:

(require 'emacsvox-aural-voice-editor)
(declare-function omnivox-preview-voice-sequence "omnivox-voices" (entries callback))
(declare-function omnivox--preview-cancel "omnivox-preview" (operation))
(declare-function omnivox--preview-token-operation "omnivox-preview" (token))
(require 'emacsvox-aural-editor)
(require 'emacsvox-aural-tools)

(defvar-local emacsvox-aural-voice-context--base nil)
(defvar-local emacsvox-aural-voice-context--input nil)
(defvar-local emacsvox-aural-voice-context--origin nil)
(defvar-local emacsvox-aural-voice-context--origin-field nil)
(defvar-local emacsvox-aural-voice-context--playback nil)
(defvar-local emacsvox-aural-voice-context--generation 0)
(defvar-local emacsvox-aural-voice-context--operation nil)
(defvar-local emacsvox-aural-voice-context--startup nil)

(defun emacsvox-aural-voice-context--patch-field (rule dimension action value)
  "Return RULE with DIMENSION set to VALUE, or removed for ACTION inherit.
Preserve all other fields, including existing explicit nil and preset resets."
  (let* ((rule (copy-tree rule))
         (render (copy-tree (plist-get rule :render)))
         (content (copy-tree (plist-get render :content)))
         (voice (plist-get content :voice))
         (style (cond ((emacsvox-aural-voice-style-p voice) (copy-tree voice))
                      ((emacsvox-aural--acss-p voice) (emacsvox-aural--acss-to-voice-style voice))
                      ((plist-member content :voice) (list :preset voice))))
         (key (emacsvox-aural--voice-dimension-key dimension)))
    (unless (memq dimension emacsvox-aural-rich-voice-dimensions)
      (user-error "Unknown voice dimension: %s" dimension))
    (setq style (if (eq action 'inherit) (map-delete style key)
                  (plist-put style key value)))
    (when style (emacsvox-aural--validate-voice-style style "Context adjustment"))
    (setq content (if style (plist-put content :voice style) (map-delete content :voice)))
    (setq render (if content (plist-put render :content content) (map-delete render :content)))
    (setq rule (plist-put rule :render render))
    (emacsvox-aural-compile-rule rule 'user)
    rule))

(defun emacsvox-aural-voice-context--read-field (rule)
  "Read one scoped adjustment to RULE, with explicit Inherit semantics."
  (let* ((dimension (intern (completing-read
                             "Context adjustment: "
                             '("average-pitch" "pitch-range" "stress" "richness" "rate-offset"
                               "gain" "low-pass" "high-pass" "pan" "reverb" "echo" "chorus" "family") nil t)))
         (style (plist-get (plist-get (plist-get rule :render) :content) :voice))
         (key (emacsvox-aural--voice-dimension-key dimension))
         (present (and (emacsvox-aural-voice-style-p style) (plist-member style key)))
         (value (and present (plist-get style key)))
         (action (completing-read
                  (format "%s, currently %s: " dimension
                          (if present (if value (format "%s" (emacsvox-aural-voice-tuner--control-value dimension value))
                                        "explicit nil (legacy behavior)") "Inherit"))
                  '("Set value" "Inherit — remove this field") nil t)))
    (if (equal action "Inherit — remove this field")
        (emacsvox-aural-voice-context--patch-field rule dimension 'inherit nil)
      (let* ((answer (read-string (format "%s value (cancel to retain existing nil): " dimension)))
             (value (if (eq dimension 'family)
                        (progn (when (string-empty-p answer) (user-error "Enter a family")) (intern answer))
                      (unless (string-match-p "\\`[+-]?[0-9]+\\'" answer) (user-error "Enter a whole number"))
                      (string-to-number answer))))
        (emacsvox-aural-voice-context--patch-field
         rule dimension 'set (emacsvox-aural-voice-tuner--stored-value dimension value))))))

(defun emacsvox-aural-voice-context-adjust-rule ()
  "Adjust one voice field in the selected rule; Inherit removes that field."
  (interactive)
  (unless (derived-mode-p 'emacsvox-aural-scheme-editor-mode)
    (user-error "Open a scoped rule editor first"))
  (let* ((index (emacsvox-aural-editor--index-at-point))
         (rule (emacsvox-aural-voice-context--read-field (emacsvox-aural-editor--rule-at-point))))
    (setf (nth index emacsvox-aural-editor-rules) rule)
    (emacsvox-aural-editor-mark-dirty)
    (emacsvox-aural-editor-refresh)
    (goto-char (or (text-property-any (point-min) (point-max)
                                      emacsvox-aural-editor-rule-index-property index) (point-min)))
    (emacsvox-aural-ui-speak "Context adjustment prepared; palette definitions unchanged. Save this rule scope to apply.")))

(defun emacsvox-aural-voice-context--resolve (base snapshot input)
  "Resolve BASE's SNAPSHOT against frozen INPUT without compilation.
Keep requested nil distinct from the ACSS transport's no-reset behavior."
  (let* ((palette (plist-get base :palette))
         (context (plist-get input :context))
         (render (emacsvox-aural--apply-legacy-content-style
                  (emacsvox-aural-resolve (plist-get input :facts) context (plist-get input :rules)) context))
         (content (emacsvox-aural-render-plan-content render))
         (request (emacsvox-aural-content-style-voice content))
         (partial (and (emacsvox-aural-voice-style-p request) request))
         (preset (if partial (plist-get partial :preset) request))
         (resolved (and (symbolp preset) preset
                        (emacsvox-aural-voice-runtime--resolve preset palette)))
         (name (plist-get resolved :name))
         (used (and name (eq name (plist-get base :voice))))
         (chosen
          (cond ((eq preset 'inaudible) (list :definition nil :selectors nil))
                (used (copy-tree snapshot))
                (name (emacsvox-aural-voice-editing--freeze
                       (plist-get (emacsvox-aural-voice-editing--snapshot palette name (plist-get base :routing)) :snapshot) palette))
                ((or (null preset) (symbolp preset))
                 (list :definition preset :selectors nil))
                (t (user-error "This compound legacy voice cannot be represented by a complete preview"))))
         (base-style (emacsvox-aural-voice-editing--style chosen palette))
         (requested (copy-tree base-style))
         (audible (copy-tree base-style)) sparse masked nil-acss)
    (dolist (dimension emacsvox-aural-rich-voice-dimensions)
      (let ((key (emacsvox-aural--voice-dimension-key dimension)))
        (when (plist-member partial key)
          (let ((value (plist-get partial key)))
            (setq requested (plist-put requested key value))
            (when (memq key emacsvox-aural-routing--choice-dimensions)
              (setq sparse (plist-put sparse key value)))
            ;; Existing inline ACSS nil reports nil but sends no reset over a
            ;; preset. Rate/effect nil clears its separately transported value.
            (if (and (null value) (memq dimension emacsvox-aural-voice-dimensions))
                (push dimension nil-acss)
              (setq audible (plist-put audible key value))
              (when used (push dimension masked)))))))
    (list :base-snapshot (copy-tree chosen) :context sparse
          :snapshot (plist-put chosen :definition audible)
          :requested requested :preset preset :uses-base used :masked (nreverse masked)
          :nil-acss nil-acss :explicit (cl-loop for (key _) on partial by #'cddr collect key)
          :origins (copy-tree (emacsvox-aural-content-style-voice-provenance content))
          :matched (copy-sequence (emacsvox-aural-render-plan-matched-rules render))
          :speaks (and (emacsvox-aural-content-style-speak content) (not (eq preset 'inaudible))))))

(defun emacsvox-aural-voice-context--check ()
  "Reject a dead or changed captured context before inspecting or previewing it."
  (unless (buffer-live-p (plist-get emacsvox-aural-voice-context--input :source))
    (user-error "Source buffer unavailable; choose a new context"))
  (emacsvox-aural-inspection-check-source-guard
   (plist-get emacsvox-aural-voice-context--input :source-guard)))

(defun emacsvox-aural-voice-context--current (&optional original)
  "Resolve the edited base, or ORIGINAL, in the captured context."
  (emacsvox-aural-voice-context--check)
  (let ((draft (plist-get emacsvox-aural-voice-context--base :draft)))
    (emacsvox-aural-voice-context--resolve
     emacsvox-aural-voice-context--base
     (if original (emacsvox-aural-voice-draft-original draft) (emacsvox-aural-voice-draft-working draft))
     emacsvox-aural-voice-context--input)))

(defun emacsvox-aural-voice-context-refresh ()
  "Explain requested values and their origins for the captured item."
  (interactive)
  (let* ((result (emacsvox-aural-voice-context--current))
         (style (plist-get result :requested))
         (field (get-text-property (point) 'voice-field))
         (inhibit-read-only t))
    (erase-buffer)
    (insert (format "Voice in captured context — %s\n" (buffer-name (plist-get emacsvox-aural-voice-context--input :source))))
    (insert "Simulation using captured facts and rules; not a report of current playback.\nVoice only: cues and spatial placement are omitted. Temporary routes are excluded.\n")
    (insert (format "Base preset: %s. Matching rules: %s.\n"
                    (or (plist-get result :preset) "adapter default") (plist-get result :matched)))
    (insert (if (plist-get result :uses-base)
                (format "Context overrides these base dimensions: %s.\n" (or (plist-get result :masked) "none"))
              "This context selects a different base; edits to the open named voice do not affect it.\n"))
    (unless (plist-get result :speaks) (insert "Content speech is suppressed in this context.\n"))
    (when (plist-get result :nil-acss)
      (insert (format "Explicit nil for %s reports nil but does not clear the underlying voice setting.\n"
                      (plist-get result :nil-acss))))
    (insert "\nShared and context requests and sources\nA customized fallback may supply other values; playback identifies the row used.\n")
    (dolist (dimension (append '(average-pitch pitch-range stress richness rate-offset)
                               emacsvox-aural-post-synthesis-dimensions))
      (let* ((value (plist-get style (emacsvox-aural--voice-dimension-key dimension)))
             (origin (alist-get dimension (plist-get result :origins)))
             (label (format "%s: %s; source %s" dimension
                            (if (null value)
                                (if (memq (emacsvox-aural--voice-dimension-key dimension) (plist-get result :explicit))
                                    "explicit nil (legacy behavior)" "adapter default")
                              (emacsvox-aural-voice-tuner--value-description dimension value))
                            (or origin (format "base %s" (plist-get result :preset))))))
        (emacsvox-aural-voice-editor--button dimension label
                                             (lambda () (emacsvox-aural-ui-speak label)))))
    (insert "\nRequested settings can be unsupported by the engine that plays them.\nPlayback evidence below reports actual omissions; numeric values are requests.\n\n")
    (emacsvox-aural-voice-editor--button 'play "Play edited voice in context" #'emacsvox-aural-voice-context-play)
    (emacsvox-aural-voice-editor--button 'compare "Compare original and edited in context" #'emacsvox-aural-voice-context-compare)
    (emacsvox-aural-voice-editor--button 'adjust "Adjust for this context — choose rule scope" #'emacsvox-aural-voice-context-adjust)
    (emacsvox-aural-voice-editor--button 'capture "Refresh facts and rules from this source item" #'emacsvox-aural-voice-context-recapture)
    (emacsvox-aural-voice-editor--button 'choose "Choose another source context" #'emacsvox-aural-voice-context-choose)
    (emacsvox-aural-voice-editor--button 'return "Return to base voice editor" #'emacsvox-aural-voice-context-return)
    (when emacsvox-aural-voice-context--playback
      (let ((label (emacsvox-aural-voice-editor--preview-status emacsvox-aural-voice-context--playback)))
        (emacsvox-aural-voice-editor--button 'playback label (lambda () (emacsvox-aural-ui-speak label))))
      (emacsvox-aural-voice-editor--button
       'playback-details "Where the last sample's settings came from"
       (lambda ()
         (let ((explanation (emacsvox-aural-voice-editor--explain-playback emacsvox-aural-voice-context--playback)))
           (with-help-window "*Voice context playback details*" (princ explanation))))))
    (emacsvox-aural-voice-editor--locate field)))

(defun emacsvox-aural-voice-context--preview (compare)
  "Preview the captured context, with original comparison when COMPARE."
  (let* ((base emacsvox-aural-voice-context--base)
         (buffer (current-buffer))
         (input emacsvox-aural-voice-context--input)
         (adapter tts-voice-preview-function)
         (process tts-speaker-process)
         (revision (emacsvox-aural-voice-draft-revision (plist-get base :draft)))
         (base-generation (plist-get base :preview-generation))
         (generation (cl-incf emacsvox-aural-voice-context--generation))
         (current
          (lambda ()
            (and (buffer-live-p buffer) (eq adapter tts-voice-preview-function) (eq process tts-speaker-process)
                 (with-current-buffer buffer
                   (and (eq base emacsvox-aural-voice-context--base)
                        (eq input emacsvox-aural-voice-context--input)
                        (= generation emacsvox-aural-voice-context--generation)
                        (equal base-generation (plist-get base :preview-generation))
                        (= revision (emacsvox-aural-voice-draft-revision (plist-get base :draft))))))))
         (startup (when (and (processp process) (eq adapter #'omnivox-preview-voice-sequence))
                    (cons process current)))
         entries operation returned)
    (dolist (original (if compare '(t nil) '(nil)))
      (let* ((result (emacsvox-aural-voice-context--current original))
             (entry (emacsvox-aural-voice-editing--cascade
                     (plist-get result :base-snapshot) (plist-get base :palette)
                     (plist-get base :policy) (plist-get base :text) (plist-get result :context))))
        (unless (plist-get result :speaks) (user-error "Content speech is suppressed in this context"))
        (setq entry (plist-put entry :variant (if original 'original 'edited)))
        (setq entries (append entries
                              (list (plist-put (plist-put (copy-tree entry) :text
                                                          (if original "Original in context." "Edited in context."))
                                               :role 'label) entry)))))
    (when startup
      (when-let* ((admitted (omnivox--preview-token-operation emacsvox-aural-voice-context--startup)))
        (setq emacsvox-aural-voice-context--operation admitted))
      (setq emacsvox-aural-voice-context--startup startup))
    (setq emacsvox-aural-voice-editor--preview-owner buffer)
    (unwind-protect
        (progn
          (setq operation
                (emacsvox-aural-voice-editor--submit-preview
                 entries
                 (lambda (result)
                   (when (funcall current)
                     (with-current-buffer buffer
                       (setq result (plist-put result :draft-revision revision))
                       (setq result (plist-put result :context-generation generation))
                       (when (eq emacsvox-aural-voice-editor--preview-owner buffer)
                         (setq emacsvox-aural-voice-editor--preview-owner nil))
                       (setq emacsvox-aural-voice-context--operation nil
                             emacsvox-aural-voice-context--playback (copy-tree result))
                       ;; Preserve captured evidence if its source changed during playback.
                       (condition-case nil (emacsvox-aural-voice-context-refresh) (user-error nil))
                       (when (funcall current)
                         (tts-notify (emacsvox-aural-voice-editor--preview-status result)))))) current))
          (when (and (funcall current) (eq emacsvox-aural-voice-editor--preview-owner buffer))
            (setq emacsvox-aural-voice-context--operation operation))
          (setq returned t))
      (when (and (not returned) (funcall current)
                 (eq emacsvox-aural-voice-editor--preview-owner buffer))
        (setq emacsvox-aural-voice-editor--preview-owner nil))
      (when (eq startup emacsvox-aural-voice-context--startup)
        (setq emacsvox-aural-voice-context--startup nil)))))

(defun emacsvox-aural-voice-context-play ()
  "Play the edited voice against captured context without saving."
  (interactive) (emacsvox-aural-voice-context--preview nil))
(defun emacsvox-aural-voice-context-compare ()
  "Compare original and edited voices against the same captured context."
  (interactive) (emacsvox-aural-voice-context--preview t))

(defun emacsvox-aural-voice-context-adjust ()
  "Prepare a dimension-only rule with an explicit match and lifetime."
  (interactive)
  (emacsvox-aural-voice-context--check)
  (let* ((input emacsvox-aural-voice-context--input)
         (source (plist-get input :source))
         (selector (emacsvox-aural-tools--voice-remap-selector
                    (plist-get input :facts) (plist-get input :context)))
         (description (emacsvox-aural-describe-selector
                       (emacsvox-aural-rule-selector
                        (emacsvox-aural-compile-rule (list :id 'context-review :match selector :render nil) 'user))))
         (scope (emacsvox-aural-tools--voice-remap-scope source (format "adjustment for %s" description)))
         (id (emacsvox-aural-tools--remap-rule-id scope selector '(voice-dimensions)))
         (buffer (emacsvox-aural-editor--open-remap-target scope source)))
    (with-current-buffer buffer
      (let* ((existing (cl-find id emacsvox-aural-editor-rules :key (lambda (rule) (plist-get rule :id))))
             (rule (emacsvox-aural-voice-context--read-field
                    (or existing (list :id id :match selector :render nil)))))
        (let ((emacsvox-aural-editor-prepared-source-guard (plist-get input :source-guard)))
          (emacsvox-aural-editor-open-prefilled-rule scope rule source))
        (emacsvox-aural-ui-speak
         (format "Prepared %s context rule for %s. V adjusts another field; RET reviews the match; w saves this scope. Palette definitions unchanged."
                 scope description))))))

(defun emacsvox-aural-voice-context--capture ()
  "Capture inspected input and the rules currently applicable to its source."
  (let* ((input (emacsvox-aural-tools--remap-source-input nil 'voice))
         (rules (emacsvox-aural-inspection-call-in-source
                 (lambda () (emacsvox-aural-current-rules (plist-get input :context))))))
    (plist-put input :rules (copy-tree rules t))))

(defun emacsvox-aural-voice-context-recapture ()
  "Refresh the captured rules and facts after validating the source identity."
  (interactive)
  (emacsvox-aural-voice-context--check)
  (emacsvox-aural-voice-context-stop)
  (setq emacsvox-aural-voice-context--input (emacsvox-aural-voice-context--capture))
  (emacsvox-aural-voice-context-refresh))

(defun emacsvox-aural-voice-context-stop ()
  "Stop this context preview without cancelling a newer editor's playback."
  (interactive)
  (cl-incf emacsvox-aural-voice-context--generation)
  (when emacsvox-aural-voice-context--playback
    (setq emacsvox-aural-voice-context--playback (plist-put emacsvox-aural-voice-context--playback :earlier t)))
  (let ((operation emacsvox-aural-voice-context--operation)
        (startup emacsvox-aural-voice-context--startup)
        (owned (eq emacsvox-aural-voice-editor--preview-owner (current-buffer))))
    (setq emacsvox-aural-voice-context--operation nil emacsvox-aural-voice-context--startup nil)
    (when owned (setq emacsvox-aural-voice-editor--preview-owner nil))
    (cond (operation (omnivox--preview-cancel operation))
          ((and owned (not startup)) (tts-stop)))
    (when startup (omnivox--preview-cancel startup))))

(defun emacsvox-aural-voice-context-return ()
  "Return to the same field in the base editor."
  (interactive)
  (emacsvox-aural-voice-context-stop)
  (let ((origin emacsvox-aural-voice-context--origin)
        (field emacsvox-aural-voice-context--origin-field))
    (if (and (markerp origin) (marker-buffer origin))
        (progn (pop-to-buffer (marker-buffer origin))
               (if field (emacsvox-aural-voice-editor--locate field) (goto-char origin)))
      (quit-window))))

(defun emacsvox-aural-voice-context-choose ()
  "Choose a new current source item from the originating base voice editor."
  (interactive)
  (let ((origin emacsvox-aural-voice-context--origin))
    (unless (and (markerp origin) (marker-buffer origin))
      (user-error "Reopen the base voice editor first"))
    (emacsvox-aural-voice-context-stop)
    (with-current-buffer (marker-buffer origin)
      (emacsvox-aural-voice-context-open t))))

(defun emacsvox-aural-voice-context-next ()
  "Move to and read the next context field."
  (interactive) (emacsvox-aural-voice-context--move 1))
(defun emacsvox-aural-voice-context-previous ()
  "Move to and read the previous context field."
  (interactive) (emacsvox-aural-voice-context--move -1))

(defun emacsvox-aural-voice-context--move (direction)
  "Move in DIRECTION without wrapping, reading the field or boundary."
  (emacsvox-aural-voice-context-stop)
  (let* ((current (button-at (point)))
         (next (if (> direction 0) (next-button (if current (button-end current) (point)))
                 (previous-button (if current (button-start current) (point))))))
    (when next (goto-char (button-start next)))
    (emacsvox-aural-ui-speak
     (concat (unless next (if (> direction 0) "Last field. " "First field. "))
             (if (or next current) (button-label (or next current)) "No fields")))))

(defvar emacsvox-aural-voice-context-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map emacsvox-aural-interface-mode-map)
    (dolist (key '("n" "<down>" "TAB")) (define-key map (kbd key) #'emacsvox-aural-voice-context-next))
    (dolist (key '("p" "<up>" "<backtab>")) (define-key map (kbd key) #'emacsvox-aural-voice-context-previous))
    (define-key map [remap forward-button] #'emacsvox-aural-voice-context-next)
    (define-key map [remap backward-button] #'emacsvox-aural-voice-context-previous)
    (define-key map (kbd "P") #'emacsvox-aural-voice-context-play)
    (define-key map (kbd "B") #'emacsvox-aural-voice-context-compare)
    (define-key map (kbd "S") #'emacsvox-aural-voice-context-stop)
    (define-key map (kbd "a") #'emacsvox-aural-voice-context-adjust)
    (define-key map (kbd "g") #'emacsvox-aural-voice-context-recapture)
    (define-key map (kbd "q") #'emacsvox-aural-voice-context-return)
    map))
(define-derived-mode emacsvox-aural-voice-context-mode emacsvox-aural-interface-mode "Voice-Context"
  "Inspect contextual voice requests independently of the named base draft."
  (add-hook 'kill-buffer-hook #'emacsvox-aural-voice-context-stop nil t))

(defun emacsvox-aural-voice-context-open (&optional choose-source)
  "Inspect the base draft against a captured source item, without saving.
With CHOOSE-SOURCE, explicitly select a buffer and use its current point."
  (interactive "P")
  (unless (emacsvox-aural-voice-editor--get :voice)
    (user-error "Choose a named-voice destination before inspecting context"))
  (let* ((base emacsvox-aural-voice-editor--context)
         (origin (copy-marker (point)))
         (field (get-text-property (point) 'voice-field))
         (captured (unless choose-source (emacsvox-aural-inspection-source-buffer)))
         (source (or captured
                     (get-buffer (read-buffer "Context source buffer (at its point): " nil t
                                              (lambda (entry) (not (emacsvox-aural-ui-interface-buffer-p (cdr entry))))))))
         (ordinary (if captured (emacsvox-aural-inspection-remember-source-buffer source)
                     (with-current-buffer source
                       (emacsvox-aural-inspection-remember-source-buffer source))))
         (input (if captured (emacsvox-aural-voice-context--capture)
                  (with-current-buffer ordinary (emacsvox-aural-voice-context--capture))))
         (buffer (generate-new-buffer "*Voice in context*")))
    (with-current-buffer buffer
      (emacsvox-aural-voice-context-mode)
      (emacsvox-aural-inspection-attach-source ordinary)
      (setq emacsvox-aural-voice-context--base base emacsvox-aural-voice-context--origin origin
            emacsvox-aural-voice-context--origin-field field
            emacsvox-aural-voice-context--input input)
      (emacsvox-aural-voice-context-refresh))
    (emacsvox-aural-ui-pop-to-buffer buffer)
    (emacsvox-aural-ui-speak "Voice in captured context. Values are requests; playback reports actual support.")
    buffer))

(provide 'emacsvox-aural-voice-context)
;;; emacsvox-aural-voice-context.el ends here
