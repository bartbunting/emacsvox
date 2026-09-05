;;; emacsvox-aural-voice-experiment.el --- Temporary physical voice experiments -*- lexical-binding: t; -*-

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

;; Explore exact physical voices in memory.  Keeping an experiment prepares a
;; review, then uses the existing separate palette and routing stores.  Each
;; completed step is retained so a partial save or apply can be retried.

;;; Code:

(require 'emacsvox-aural-voice-workbench)

(defvar-local emacsvox-aural-voice-experiment-opening nil
  "Opening route and parameters, retained for comparison and reset.")
(defvar-local emacsvox-aural-voice-experiment-accepted-route nil
  "Route against which unsaved changes are compared.")
(defvar-local emacsvox-aural-voice-experiment-keep-plan nil
  "Reviewable keep operation and its completed persistence steps.")
(defvar-local emacsvox-aural-voice-experiment-origin nil
  "Experiment buffer owning this Keep result review.")

(defun emacsvox-aural-voice-experiment--snapshot ()
  "Return the requested physical route and working parameters."
  (list :experiment-route (copy-tree emacsvox-aural-voice-tuner-route-selector)
        :engine (copy-tree emacsvox-aural-voice-tuner-route-engine)
        :language emacsvox-aural-voice-tuner-route-language
        :voice emacsvox-aural-voice-tuner-voice
        :style (copy-tree emacsvox-aural-voice-tuner-working-style)))

(defun emacsvox-aural-voice-experiment--restore-snapshot (snapshot)
  "Restore requested state from SNAPSHOT without changing live configuration."
  (setq emacsvox-aural-voice-tuner-route-selector (copy-tree (plist-get snapshot :experiment-route))
        emacsvox-aural-voice-tuner-route-engine (copy-tree (plist-get snapshot :engine))
        emacsvox-aural-voice-tuner-route-language (plist-get snapshot :language)
        emacsvox-aural-voice-tuner-voice (plist-get snapshot :voice)
        emacsvox-aural-voice-tuner-working-style (copy-tree (plist-get snapshot :style))
        emacsvox-aural-voice-tuner-route-realized nil
        emacsvox-aural-voice-tuner-preview-result nil)
  (emacsvox-aural-voice-tuner--update-dirty)
  (emacsvox-aural-voice-tuner-refresh))

(defun emacsvox-aural-voice-experiment--route-dirty-p ()
  "Return whether the working physical route is unsaved."
  (not (equal emacsvox-aural-voice-tuner-route-selector
              emacsvox-aural-voice-experiment-accepted-route)))

(defun emacsvox-aural-voice-experiment-switch-voice ()
  "Try another physical voice while retaining requested parameters."
  (interactive)
  (let* ((emacsvox-aural-voice-workbench-inventory (tts-voice-inventory))
         (candidates (emacsvox-aural-voice-workbench--physical-candidates))
         (pair (cdr (assoc (completing-read "Try physical voice: " candidates nil t) candidates)))
         (entry (emacsvox-aural-voice-workbench--physical-preview-entry pair))
         (before (emacsvox-aural-voice-experiment--snapshot)))
    (push before emacsvox-aural-voice-tuner-history)
    (emacsvox-aural-voice-experiment--restore-snapshot
     (list :experiment-route (plist-get entry :selector)
           :engine (car pair) :language (plist-get entry :language)
           :voice (emacsvox-aural-voice-workbench--pair-name pair)
           :style emacsvox-aural-voice-tuner-working-style))
    (emacsvox-aural-voice-tuner-audition
     (format "Trying %s. Unsupported requested settings: %s."
             emacsvox-aural-voice-tuner-voice
             (or (string-join
                  (cl-loop for dimension in emacsvox-aural-rich-voice-dimensions
                           when (and (emacsvox-aural-voice-tuner--value dimension)
                                     (not (emacsvox-aural-voice-tuner--supported-p dimension)))
                           collect (emacsvox-aural-humanize dimension)) ", ") "none")))))

(defun emacsvox-aural-voice-experiment-copy-style ()
  "Copy an existing logical style into this temporary experiment."
  (interactive)
  (let* ((palette (emacsvox-aural-voice-palettes--active-id))
         (entries (emacsvox-aural-effective-voice-entries palette))
         (name (intern (completing-read "Copy style to experiment: "
                                        (mapcar (lambda (entry) (symbol-name (car entry))) entries)
                                        nil t)))
         (style (emacsvox-aural-voice-tuner--complete-style (cdr (assq name entries)) palette)))
    (push (copy-tree emacsvox-aural-voice-tuner-working-style) emacsvox-aural-voice-tuner-history)
    (setq emacsvox-aural-voice-tuner-working-style style)
    (emacsvox-aural-voice-tuner--update-dirty)
    (emacsvox-aural-voice-tuner-refresh)
    (emacsvox-aural-voice-tuner-audition (format "Copied %s temporarily." name))))

(defun emacsvox-aural-voice-experiment-undo ()
  "Undo a parameter, copied style, or physical voice change."
  (interactive)
  (if (plist-member (car emacsvox-aural-voice-tuner-history) :experiment-route)
      (progn
        (emacsvox-aural-voice-experiment--restore-snapshot (pop emacsvox-aural-voice-tuner-history))
        (emacsvox-aural-voice-tuner-audition "Undid the last voice change."))
    (emacsvox-aural-voice-tuner-undo)))

(defun emacsvox-aural-voice-experiment-reset ()
  "Restore the physical voice and parameters present when the experiment opened."
  (interactive)
  (push (emacsvox-aural-voice-experiment--snapshot) emacsvox-aural-voice-tuner-history)
  (emacsvox-aural-voice-experiment--restore-snapshot emacsvox-aural-voice-experiment-opening)
  (emacsvox-aural-voice-tuner-audition "Restored the opening voice and parameters."))

(defun emacsvox-aural-voice-experiment-compare ()
  "Alternate the exact opening and current working versions."
  (interactive)
  (let ((opening emacsvox-aural-voice-tuner-compare-reference-next-p)
        (snapshot emacsvox-aural-voice-experiment-opening))
    (setq emacsvox-aural-voice-tuner-compare-reference-next-p (not opening))
    (let ((emacsvox-aural-voice-tuner-route-selector
           (if opening (plist-get snapshot :experiment-route) emacsvox-aural-voice-tuner-route-selector))
          (emacsvox-aural-voice-tuner-route-language
           (if opening (plist-get snapshot :language) emacsvox-aural-voice-tuner-route-language)))
      (emacsvox-aural-voice-tuner--play-text
       (concat (if opening "Opening version. " "Working version. ")
               emacsvox-aural-voice-tuner-preview-text)
       (if opening (plist-get snapshot :style) emacsvox-aural-voice-tuner-working-style)))))

(defun emacsvox-aural-voice-experiment-edit-text ()
  "Change the sample text used by this experiment."
  (interactive)
  (let ((text (read-string "Experiment sample text: " emacsvox-aural-voice-tuner-preview-text)))
    (when (string-empty-p (string-trim text)) (user-error "Use a nonempty sample"))
    (setq emacsvox-aural-voice-tuner-preview-text text)
    (emacsvox-aural-voice-tuner-audition)))

(defun emacsvox-aural-voice-experiment-sweep ()
  "Demonstrate the selected parameter at three values without keeping any change."
  (interactive)
  (let* ((dimension (emacsvox-aural-voice-tuner--numeric-dimension))
         (_ (unless (emacsvox-aural-voice-tuner--supported-p dimension)
              (user-error "%s is unsupported by this engine" dimension)))
         (minimum (if (eq dimension 'rate-offset) -20 0))
         (maximum (if (eq dimension 'rate-offset) 20 9))
         (values
          (mapcar (lambda (letter)
                    (read-number (format "%s value %s, %d through %d: "
                                         (emacsvox-aural-humanize dimension) letter minimum maximum)))
                  '(A B C)))
         entries)
    (unless (cl-every (lambda (value) (and (integerp value) (<= minimum value maximum))) values)
      (user-error "Choose three integer values from %d through %d" minimum maximum))
    (dolist (value values)
      (let* ((style (plist-put (copy-tree emacsvox-aural-voice-tuner-working-style)
                               (emacsvox-aural--voice-dimension-key dimension) value))
             (entry (list :text emacsvox-aural-voice-tuner-preview-text
                          :selector (copy-tree emacsvox-aural-voice-tuner-route-selector)
                          :language emacsvox-aural-voice-tuner-route-language
                          :acss (emacsvox-aural-voice-tuner--normalized-acss style)
                          :rate-offset (plist-get style :rate-offset)
                          :effects (emacsvox-aural-voice-tuner--normalized-effects style))))
        ;; Values are essential to this demonstration even when ordinary labels are off.
        (setq entries
              (nconc entries
                     (list (plist-put (copy-tree entry) :text
                                      (format "%s %s." (emacsvox-aural-humanize dimension) value)) entry)))))
    (tts-preview-voices entries
                        (lambda (result)
                          (when (eq (plist-get result :status) 'failed)
                            (tts-speak "Parameter demonstration failed; no settings were changed"))))))

(defun emacsvox-aural-voice-experiment--palette-data (id)
  "Return current palette ID's serialized data, or nil."
  (when-let* ((palette (emacsvox-aural-voice-palette id)))
    (emacsvox-aural-voice-palette-data-form palette)))

(defun emacsvox-aural-voice-experiment--prepare-keep (kind name palette-id)
  "Build a frozen KIND keep proposal for NAME and optional PALETTE-ID.
KIND is `style', `route', or `both'.  This function performs no writes."
  (let* ((active (emacsvox-aural-voice-palettes--active-id))
         (palette-before (and palette-id (emacsvox-aural-voice-experiment--palette-data palette-id)))
         (palette-data (and (memq kind '(style both))
                            (or (copy-tree palette-before)
                                (list :schema-version emacsvox-aural-voice-palette-schema-version
                                      :id palette-id :summary "Kept physical voice experiments"
                                      :parent active :entries nil))))
         (routing-before (emacsvox-aural-voice-workbench--current-profile-data))
         (routing-data (and (memq kind '(route both)) (copy-tree routing-before)))
         (selector (plist-put (copy-tree emacsvox-aural-voice-tuner-route-selector) :scope 'local))
         (snapshot (emacsvox-aural-voice-experiment--snapshot)))
    (when (eq kind 'route)
      (setf (plist-get snapshot :style)
            (emacsvox-aural-voice-tuner--complete-style name active)))
    (when palette-data
      (setq palette-data
            (emacsvox-aural-voice-palettes--put-entry
             palette-data (emacsvox-aural-voice-palettes--entry-data
                           name emacsvox-aural-voice-tuner-working-style)))
      (emacsvox-aural-compile-voice-palette-data palette-data))
    (when routing-data
      (let ((emacsvox-aural-voice-workbench-staged-profile routing-data))
        (emacsvox-aural-voice-workbench--replace-binding name (list selector)
                                                       emacsvox-aural-voice-tuner-route-language)
        (setq routing-data (emacsvox-aural-validate-routing-profile-data
                            emacsvox-aural-voice-workbench-staged-profile))))
    (list :kind kind :name name :snapshot snapshot
          :palette-before palette-before :palette palette-data :palette-id palette-id
          :routing-before routing-before :routing routing-data
          :text emacsvox-aural-voice-tuner-preview-text
          :palette-saved nil :route-saved nil :failure nil :apply-status 'not-started)))

(defun emacsvox-aural-voice-experiment-keep ()
  "Choose what to keep and review the concrete changes before Save and apply."
  (interactive)
  (let* ((kind (cdr (assoc (completing-read "Keep result: "
                                           '("Parameters as a named style" "Physical voice for a logical voice"
                                             "Voice and parameters for a logical voice") nil t)
                          '(("Parameters as a named style" . style)
                            ("Physical voice for a logical voice" . route)
                            ("Voice and parameters for a logical voice" . both)))))
         (active (emacsvox-aural-voice-palettes--active-id))
         (name
          (if (eq kind 'style)
              (emacsvox-aural-voice-palettes--read-entry-name active)
            (let* ((emacsvox-aural-voice-workbench-staged-profile
                    (emacsvox-aural-voice-workbench--current-profile-data))
                   (choices
                    (if (eq kind 'both)
                        (mapcar (lambda (entry) (symbol-name (car entry)))
                                (emacsvox-aural-effective-voice-entries active))
                      (emacsvox-aural-voice-workbench--logical-voices))))
              (intern (completing-read "Logical voice to use the result: " choices nil t)))))
         (palette-id
          (when (memq kind '(style both))
            (if (emacsvox-aural-voice-palette-built-in (emacsvox-aural-voice-palette active))
                (emacsvox-aural-voice-palettes--read-new-id "personal-voices")
              active)))
         (plan (emacsvox-aural-voice-experiment--prepare-keep kind name palette-id))
         (origin (current-buffer))
         (source (emacsvox-aural-inspection-remember-source-buffer))
         (buffer (generate-new-buffer "*Aural Keep Voice Result*")))
    (with-current-buffer buffer
      (emacsvox-aural-voice-experiment-keep-mode)
      (emacsvox-aural-inspection-attach-source source)
      (setq emacsvox-aural-voice-experiment-origin origin
            emacsvox-aural-voice-experiment-keep-plan plan
            emacsvox-aural-ui-speech-function
            (lambda (text)
              (if (buffer-live-p origin)
                  (with-current-buffer origin (emacsvox-aural-voice-tuner--speak-text text))
                (tts-speak text))))
      (emacsvox-aural-voice-experiment--show-keep))
    (emacsvox-aural-ui-pop-to-buffer buffer)
    (emacsvox-aural-ui-speak (buffer-string))
    buffer))

(defun emacsvox-aural-voice-experiment--keep-summary ()
  "Describe the proposed destinations and completed steps in this review."
  (let* ((plan emacsvox-aural-voice-experiment-keep-plan)
         (palette (plist-get plan :palette)) (routing (plist-get plan :routing))
         (snapshot (plist-get plan :snapshot)))
    (concat
     (format "Keep result for %s\n\nPhysical voice: %s\nPreview parameters: %S\n\n"
             (plist-get plan :name) (plist-get snapshot :voice) (plist-get snapshot :style))
     (format "Keep: %s.\n"
             (pcase (plist-get plan :kind)
               ('style "parameters as a named style, using existing routes")
               ('route "physical voice route, retaining the destination's style")
               ('both "physical voice and parameters for this logical voice")))
     (when palette
       (format "Style %s in palette %s: %s. Palette selection applies for this session; a Presentation Profile can retain that choice.\n"
               (plist-get plan :name) (plist-get palette :id)
               (if (plist-get plan :palette-saved) "saved" "will be saved")))
     (when routing
       (format "Exact physical route for %s in routing profile %s: %s. Any session route for this logical voice will also be replaced.\n"
               (plist-get plan :name) (plist-get routing :id)
               (if (plist-get plan :route-saved) "saved" "will be saved")))
     (format "Apply status: %s.\n" (plist-get plan :apply-status))
     (when-let* ((failure (plist-get plan :failure))) (format "Incomplete: %s\n" failure))
     "\nC-c C-c saves and applies this proposal, or retries unfinished steps.\nP previews the frozen voice and parameters above. q returns; h opens Home. ? reads this review.\n")))

(defun emacsvox-aural-voice-experiment--show-keep ()
  "Refresh this review without losing point."
  (let ((inhibit-read-only t) (position (point)))
    (erase-buffer) (insert (emacsvox-aural-voice-experiment--keep-summary))
    (goto-char (min position (point-max)))))

(defun emacsvox-aural-voice-experiment-review ()
  "Speak the complete Keep result proposal and current save/apply status."
  (interactive)
  (emacsvox-aural-ui-speak (emacsvox-aural-voice-experiment--keep-summary)))

(defun emacsvox-aural-voice-experiment-preview-kept ()
  "Audition the frozen proposal without saving or applying it."
  (interactive)
  (let* ((snapshot (plist-get emacsvox-aural-voice-experiment-keep-plan :snapshot))
         (style (plist-get snapshot :style)))
    (tts-preview-voice
     (plist-get emacsvox-aural-voice-experiment-keep-plan :text)
     (plist-get snapshot :experiment-route) :language (plist-get snapshot :language)
     :acss (emacsvox-aural-voice-tuner--normalized-acss style)
     :rate-offset (plist-get style :rate-offset)
     :effects (emacsvox-aural-voice-tuner--normalized-effects style)
     :callback (lambda (result)
                 (when (eq (plist-get result :status) 'failed)
                   (tts-speak (format "Kept-result preview failed: %s"
                                      (plist-get result :message))))))))

(defun emacsvox-aural-voice-experiment--apply-complete (buffer status)
  "Record the adapter's apply STATUS in review BUFFER."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (setf (plist-get emacsvox-aural-voice-experiment-keep-plan :apply-status)
            (plist-get status :status))
      (when (eq (plist-get status :status) 'applied)
        (let* ((origin emacsvox-aural-voice-experiment-origin)
               (snapshot (plist-get emacsvox-aural-voice-experiment-keep-plan :snapshot)))
          (when (buffer-live-p origin)
            (with-current-buffer origin
              (when (equal snapshot (emacsvox-aural-voice-experiment--snapshot))
                (setq emacsvox-aural-voice-tuner-initial-style
                      (copy-tree emacsvox-aural-voice-tuner-working-style)
                      emacsvox-aural-voice-experiment-accepted-route
                      (copy-tree emacsvox-aural-voice-tuner-route-selector))
                (emacsvox-aural-voice-tuner--update-dirty))))))
      (emacsvox-aural-voice-experiment--show-keep)
      (when (eq buffer (window-buffer (selected-window)))
        (emacsvox-aural-ui-speak (format "Keep result: apply %s" (plist-get status :status)))))))

(defun emacsvox-aural-voice-experiment-save-and-apply ()
  "Save reviewed destinations and apply them, retaining completed steps for retry."
  (interactive)
  (let* ((plan emacsvox-aural-voice-experiment-keep-plan)
         (palette (plist-get plan :palette)) (routing (plist-get plan :routing))
         (buffer (current-buffer))
         (callback (lambda (status) (emacsvox-aural-voice-experiment--apply-complete buffer status))))
    (when (eq (plist-get plan :apply-status) 'applying)
      (user-error "The saved result is still being applied"))
    (setf (plist-get plan :failure) nil)
    (condition-case error-data
        (progn
          ;; Recheck both stores before any write, including on partial retries.
          (when (and palette
                     (not (equal (emacsvox-aural-voice-experiment--palette-data (plist-get palette :id))
                                 (if (plist-get plan :palette-saved) palette (plist-get plan :palette-before)))))
            (user-error "The destination palette changed; prepare a new review"))
          (when (and routing
                     (not (equal (emacsvox-aural-voice-workbench--current-profile-data)
                                 (if (plist-get plan :route-saved) routing (plist-get plan :routing-before)))))
            (user-error "Routing changed; prepare a new review"))
          (when (and palette (not (plist-get plan :palette-saved)))
            (emacsvox-aural-voice-palettes--install-data
             palette (and (plist-get plan :palette-before) (plist-get palette :id)))
            (setf (plist-get plan :palette-saved) t))
          (when palette (emacsvox-aural-select-voice-palette (plist-get palette :id)))
          (setf (plist-get plan :apply-status) 'applying)
          (if routing
              (let ((old-session (copy-tree emacsvox-aural-session-routing-bindings)))
                (setq emacsvox-aural-session-routing-bindings
                      (cl-remove (format "%s" (plist-get plan :name)) old-session
                                 :key (lambda (entry) (format "%s" (car entry))) :test #'equal))
                (condition-case write-error
                    (if (plist-get plan :route-saved)
                        (emacsvox-aural-apply-routing-profile (plist-get routing :id) callback)
                      (emacsvox-aural-commit-routing-profile-data routing nil callback)
                      (setf (plist-get plan :route-saved) t))
                  (error
                   (setq emacsvox-aural-session-routing-bindings old-session)
                   (signal (car write-error) (cdr write-error)))))
            (tts-apply-voice-configuration callback)))
      (error
       (setf (plist-get plan :apply-status) 'failed
             (plist-get plan :failure) (error-message-string error-data))))
    (setq emacsvox-aural-voice-experiment-keep-plan plan)
    (emacsvox-aural-voice-experiment--show-keep)
    (emacsvox-aural-voice-experiment-review)))

(define-derived-mode emacsvox-aural-voice-experiment-keep-mode
    emacsvox-aural-interface-mode "Aural-Keep-Voice"
  "Review separate style and route changes before saving and applying them.")

(dolist (binding '(("C-c C-c" . emacsvox-aural-voice-experiment-save-and-apply)
                   ("w" . emacsvox-aural-voice-experiment-save-and-apply)
                   ("P" . emacsvox-aural-voice-experiment-preview-kept)
                   ("?" . emacsvox-aural-voice-experiment-review)
                   ("h" . emacsvox-aural)))
  (define-key emacsvox-aural-voice-experiment-keep-mode-map (kbd (car binding)) (cdr binding)))

(defun emacsvox-aural-voice-experiment-help ()
  "Describe the temporary physical tuner using its working voice."
  (interactive)
  (let ((text (concat "Temporary physical voice experiment. Nothing is saved on opening or adjustment.\n"
                      "n/p or up/down select parameters; left/right adjust; RET enters a value.\n"
                      "P plays; B alternates opening and working versions; S stops.\n"
                      "u undoes; R restores opening voice and parameters; v tries another voice.\n"
                      "c copies an existing style; T changes sample text; D demonstrates three values.\n"
                      "w or C-c C-c chooses what to keep and opens a review. Saving happens in that review.\n"
                      "C-c C-a offers actions. h opens Home; q or C-c C-k cancels, confirming changed experiments.\n"
                      "Requested parameters and advertised support are separate from playback reports.\n"
                      "Exact applied parameter values are not reported by the adapter.\n")))
    (emacsvox-aural-ui-with-help-window (princ text))
    (emacsvox-aural-voice-tuner--speak-text text)))

(define-derived-mode emacsvox-aural-voice-experiment-mode
    emacsvox-aural-voice-tuner-mode "Aural-Voice-Experiment"
  "Temporary physical voice tuner with explicitly reviewed persistence."
  (setq-local emacsvox-aural-ui-action-filter
              (lambda (command)
                (pcase command
                  ('emacsvox-aural-voice-experiment-undo emacsvox-aural-voice-tuner-history)
                  ('emacsvox-aural-voice-experiment-sweep
                   (and (tabulated-list-get-id)
                        (not (eq (tabulated-list-get-id) 'family))
                        (emacsvox-aural-voice-tuner--supported-p (tabulated-list-get-id))))
                  (_ (emacsvox-aural-voice-tuner--action-applicable-p command)))))
  (setq-local emacsvox-aural-voice-tuner-additional-dirty-function
              #'emacsvox-aural-voice-experiment--route-dirty-p))

(dolist (binding '(("v" . emacsvox-aural-voice-experiment-switch-voice)
                   ("c" . emacsvox-aural-voice-experiment-copy-style)
                   ("T" . emacsvox-aural-voice-experiment-edit-text)
                   ("D" . emacsvox-aural-voice-experiment-sweep)
                   ("B" . emacsvox-aural-voice-experiment-compare)
                   ("R" . emacsvox-aural-voice-experiment-reset)
                   ("u" . emacsvox-aural-voice-experiment-undo)
                   ("w" . emacsvox-aural-voice-experiment-keep)
                   ("C-c C-c" . emacsvox-aural-voice-experiment-keep)
                   ("?" . emacsvox-aural-voice-experiment-help)))
  (define-key emacsvox-aural-voice-experiment-mode-map (kbd (car binding)) (cdr binding)))

(defun emacsvox-aural-voice-experiment-open (pair source text)
  "Open an in-memory physical PAIR experiment from SOURCE, using sample TEXT."
  (let* ((entry (emacsvox-aural-voice-workbench--physical-preview-entry pair))
         (selector (plist-get entry :selector))
         (inspection (emacsvox-aural-inspection-remember-source-buffer))
         (existing
          (cl-find-if
           (lambda (buffer)
             (with-current-buffer buffer
               (and (derived-mode-p 'emacsvox-aural-voice-experiment-mode)
                    (equal selector (plist-get emacsvox-aural-voice-experiment-opening :experiment-route)))))
           (buffer-list)))
         (buffer (or existing (generate-new-buffer
                              (format "*Aural Voice Experiment: %s*"
                                      (emacsvox-aural-voice-workbench--pair-name pair))))))
    (unless existing
      (with-current-buffer buffer
        (emacsvox-aural-voice-experiment-mode)
        (emacsvox-aural-inspection-attach-source inspection)
        (setq emacsvox-aural-voice-tuner-source-buffer source
              emacsvox-aural-voice-tuner-preview-text text
              emacsvox-aural-voice-tuner-voice (emacsvox-aural-voice-workbench--pair-name pair)
              emacsvox-aural-voice-tuner-route-selector (copy-tree selector)
              emacsvox-aural-voice-tuner-route-engine (copy-tree (car pair))
              emacsvox-aural-voice-tuner-route-language (plist-get entry :language)
              emacsvox-aural-voice-tuner-working-style
              '(:family nil :average-pitch nil :pitch-range nil :stress nil :richness nil
                :rate-offset 0 :gain 5 :low-pass 9 :high-pass 0 :pan 5 :reverb 0 :echo 0 :chorus 0)
              emacsvox-aural-voice-tuner-initial-style (copy-tree emacsvox-aural-voice-tuner-working-style)
              emacsvox-aural-voice-experiment-opening (emacsvox-aural-voice-experiment--snapshot)
              emacsvox-aural-voice-experiment-accepted-route (copy-tree selector))
        (emacsvox-aural-voice-tuner-refresh)))
    (emacsvox-aural-ui-pop-to-buffer buffer)
    (emacsvox-aural-voice-tuner-speak-current)
    buffer))

(provide 'emacsvox-aural-voice-experiment)
;;; emacsvox-aural-voice-experiment.el ends here
