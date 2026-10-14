;;; emacsvox-aural-menu.el --- Transient menus for aural settings -*- lexical-binding: t; -*-

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

;; Experimental entry and speech menus.  Retain the source item across
;; submenus and delegate settings and feedback to their existing commands.

;;; Code:

(require 'emacsvox-indentation)
(require 'emacsvox-aural-inspection)

(declare-function emacsvox-aural-feedback-outline-mode
                  "emacsvox-aural-feedback-details" (&optional arg))

(autoload 'emacsvox-aural "emacsvox-aural-home" nil t)
(autoload 'emacsvox-capitalization "emacsvox-capitalization" nil t)
(autoload 'emacsvox-settings-integrations "emacsvox-settings-integrations" nil t)
(autoload 'emacsvox-settings-setups "emacsvox-settings-workflows" nil t)
(autoload 'emacsvox-settings-presentation "emacsvox-settings-workflows" nil t)
(autoload 'emacsvox-settings-feedback "emacsvox-settings-workflows" nil t)
(autoload 'emacsvox-settings-search "emacsvox-settings" nil t)
(autoload 'emacsvox-settings-search-actions "emacsvox-settings" nil t)
(autoload 'emacsvox-settings-buffer "emacsvox-settings" nil t)
(autoload 'emacsvox-output-settings "emacsvox-output-settings" nil t)
(autoload 'omnivox-punctuation "omnivox-punctuation" nil t)
(autoload 'emacsvox-line-cues-edit "emacsvox-line-cues" nil t)
(autoload 'emacsvox-interaction "emacsvox-interaction" nil t)
(autoload 'emacsvox-aural-list-sound-packs "emacsvox-aural-sound-packs" nil t)
(autoload 'emacsvox-aural-list-voice-palettes "emacsvox-aural-voice-palettes" nil t)
(autoload 'emacsvox-aural-voice-workbench "emacsvox-aural-voice-workbench" nil t)
(autoload 'emacsvox-aural-prefer-engine "emacsvox-aural-voice-workbench" nil t)
(autoload 'emacsvox-aural-restore-saved-engine-order "emacsvox-aural-voice-workbench" nil t)
(autoload 'emacsvox-explain-aural-presentation "emacsvox-aural-explanation" nil t)

(defun emacsvox-aural-menu--context ()
  "Return the context owned by the current source-aware menu."
  (let ((prefix (or transient--prefix transient-current-prefix)))
    (unless (and prefix
                 (memq (oref prefix command)
                       '(emacsvox-aural-menu emacsvox-aural-menu-speech
                         emacsvox-aural-menu-sounds emacsvox-aural-menu-punctuation
                         emacsvox-aural-menu-voices emacsvox-capitalization
                         emacsvox-interaction emacsvox-aural-menu-line-cues
                         emacsvox-output-settings emacsvox-settings-buffer
                         emacsvox-settings-feedback emacsvox-settings-presentation emacsvox-settings-setups emacsvox-settings-integrations)))
      (user-error "Open the Emacsvox menu first"))
    (oref prefix scope)))

(defun emacsvox-aural-menu--capture (global)
  "Capture the source item and initial GLOBAL settings scope."
  (let* ((source (emacsvox-aural-inspection-source-buffer))
         (interface (emacsvox-aural-ui-interface-buffer-p))
         (position (if interface emacsvox-aural-ui-source-position
                     (and source (with-current-buffer source (point)))))
         (guard (if interface emacsvox-aural-ui-source-guard
                  (and source (emacsvox-aural-inspection-source-guard)))))
    (unless (buffer-live-p source)
      (user-error "No live source buffer is available"))
    (list :source source
          :position (and position
                         (with-current-buffer source (copy-marker position t)))
          :guard guard
          :settings (cons source (and global t)))))

(defun emacsvox-aural-menu--source (context)
  "Return the live source buffer in CONTEXT."
  (let ((source (plist-get context :source)))
    (unless (buffer-live-p source)
      (user-error "The menu's source buffer has been closed"))
    source))

(defun emacsvox-aural-menu--call-at-item (command)
  "Call interactive COMMAND at the captured item, preserving source point."
  (let* ((context (emacsvox-aural-menu--context))
         (source (emacsvox-aural-menu--source context))
         (position (plist-get context :position)))
    (unless (and (markerp position) (eq (marker-buffer position) source))
      (user-error "The captured source location is no longer available"))
    (emacsvox-aural-inspection-check-source-guard (plist-get context :guard))
    (with-current-buffer source
      (save-excursion
        (save-restriction
          (widen)
          (goto-char position)
          (call-interactively command))))))

(defun emacsvox-aural-menu--feedback ()
  "Inspect how the source item was spoken; q returns to this menu."
  (interactive)
  (let ((context (emacsvox-aural-menu--context)))
    (emacsvox-aural-menu--call-at-item #'emacsvox-explain-aural-presentation)
    (with-current-buffer (window-buffer (selected-window))
      (when (derived-mode-p 'emacsvox-aural-feedback-details-mode)
        (emacsvox-aural-feedback-outline-mode 1)
        (setq-local emacsvox-aural-ui--help-return-function
                    (lambda () (emacsvox-aural-menu--return-from-feedback context)))))))

(defun emacsvox-aural-menu--return-from-feedback (context)
  "Restore the menu owning CONTEXT if its source is still available."
  (when (buffer-live-p (plist-get context :source))
    ;; Restore our own context rather than another command's resume stack.
    (pop-to-buffer (plist-get context :source))
    (transient-setup 'emacsvox-aural-menu nil nil :scope context)
    (transient--show)
    t))

(defun emacsvox-aural-menu--home ()
  "Open Aural Home for all voice, sound, rule, and feedback tools."
  (interactive)
  (emacsvox-aural-menu--call-at-item #'emacsvox-aural))

(defun emacsvox-aural-menu--scope-label ()
  "Describe the selected settings scope."
  (if (cdr (plist-get (emacsvox-aural-menu--context) :settings))
      "Global defaults" "Current buffer"))

(defun emacsvox-aural-menu--toggle-scope ()
  "Choose whether subsequent changes affect this buffer or global defaults."
  (interactive)
  (let* ((context (emacsvox-aural-menu--context))
         (source (emacsvox-aural-menu--source context))
         (settings (plist-get context :settings)))
    (setcdr settings (not (cdr settings)))
    (with-current-buffer source
      (emacsvox-transient--submit-text
       (concat "Editing " (downcase (emacsvox-aural-menu--scope-label)))
       (emacsvox-transient--item-facts
        'value 'settings-scope 'command-menu-value-changed '(selected))
       'state-change 'select-object))))

(defun emacsvox-aural-menu--indentation-label ()
  "Describe indentation in the selected settings scope."
  (let* ((context (emacsvox-aural-menu--context))
         (source (emacsvox-aural-menu--source context))
         (global (cdr (plist-get context :settings)))
         (value (lambda (symbol)
                  (if global (default-value symbol)
                    (buffer-local-value symbol source)))))
    (format "Indentation: %s, %s"
            (if (funcall value 'emacsvox-audio-indentation) "on" "off")
            (replace-regexp-in-string
             "-" " "
             (symbol-name (funcall value 'emacsvox-indentation-presentation))))))

(defun emacsvox-aural-menu--indentation ()
  "Choose spoken indentation or tones, their timing, and tone volume."
  (interactive)
  (let* ((context (emacsvox-aural-menu--context))
         (source (emacsvox-aural-menu--source context)))
    (with-current-buffer source
      (emacsvox-indentation--setup (plist-get context :settings)))))

(defun emacsvox-aural-menu--navigation-choice (style label)
  "Describe navigation STYLE with LABEL and its selected state."
  (if (eq emacsvox-transient-navigation-style style)
      (propertize (concat label " (selected)")
                  emacsvox-aural-facts-property '(:states (selected)))
    label))

(defun emacsvox-aural-menu--set-navigation (style label)
  "Activate navigation STYLE and announce LABEL."
  (customize-set-variable 'emacsvox-transient-navigation-style style)
  (emacsvox-transient--submit-text
   label
   (emacsvox-transient--item-facts
    'value 'navigation-style 'command-menu-value-changed '(selected))
   'state-change 'select-object))

(defun emacsvox-aural-menu--save-navigation ()
  "Keep navigation, announcement order, and description preferences across restarts."
  (interactive)
  (customize-save-variable 'emacsvox-transient-navigation-style
                           emacsvox-transient-navigation-style)
  (customize-save-variable 'emacsvox-transient-section-announcement-order
                           emacsvox-transient-section-announcement-order)
  (customize-save-variable 'emacsvox-transient-verbose-descriptions
                           emacsvox-transient-verbose-descriptions)
  (emacsvox-transient--submit-text
   "Saved menu defaults"
   (emacsvox-transient--menu-facts 'save-navigation 'operation-completed)
   'state-change 'save-object))

(defun emacsvox-aural-menu--section-order-choice (order label)
  "Describe section announcement ORDER with LABEL and its selected state."
  (if (eq emacsvox-transient-section-announcement-order order)
      (propertize (concat label " (selected)")
                  emacsvox-aural-facts-property '(:states (selected)))
    label))

(defun emacsvox-aural-menu--set-section-order (order label)
  "Activate section announcement ORDER and announce LABEL."
  (customize-set-variable 'emacsvox-transient-section-announcement-order order)
  (emacsvox-transient--submit-text
   label
   (emacsvox-transient--item-facts
    'value 'section-announcement-order 'command-menu-value-changed '(selected))
   'state-change 'select-object))

(defun emacsvox-aural-menu--toggle-descriptions ()
  "Include command explanations in all Transient menus, including Magit."
  (interactive)
  (customize-set-variable 'emacsvox-transient-verbose-descriptions
                          (not emacsvox-transient-verbose-descriptions))
  (emacsvox-transient--submit-text
   (if emacsvox-transient-verbose-descriptions
       "Detailed descriptions on" "Detailed descriptions off")
   (emacsvox-transient--item-facts
    'value 'verbose-descriptions 'command-menu-value-changed
    (when emacsvox-transient-verbose-descriptions '(selected)))
   'state-change (if emacsvox-transient-verbose-descriptions 'on 'off)))

(transient-define-prefix emacsvox-aural-menu-navigation ()
  "Choose arrow navigation, announcement order, and descriptions for all menus."
  :refresh-suffixes t
  ["Navigation style (global)"
   ("c" (lambda () (emacsvox-aural-menu--navigation-choice 'continuous "Continuous"))
    (lambda () "Move up/down across sections and wrap around the whole menu."
      (interactive) (emacsvox-aural-menu--set-navigation 'continuous "Continuous")) :transient t)
   ("w" (lambda () (emacsvox-aural-menu--navigation-choice 'section-wrap "Wrap within section"))
    (lambda () "Cycle up/down within this section; use left/right to change sections."
      (interactive) (emacsvox-aural-menu--set-navigation 'section-wrap "Wrap within section")) :transient t)
   ("s" (lambda () (emacsvox-aural-menu--navigation-choice 'section-stop "Stop at section edges"))
    (lambda () "Stop up/down at section edges; use left/right to change sections."
      (interactive) (emacsvox-aural-menu--set-navigation 'section-stop "Stop at section edges")) :transient t)]
  ["Presentation (global)"
   ("i" (lambda () (emacsvox-aural-menu--section-order-choice 'item-first "Item first"))
    (lambda () "Speak the item before the section name and position when changing sections."
      (interactive) (emacsvox-aural-menu--set-section-order 'item-first "Item first")) :transient t)
   ("n" (lambda () (emacsvox-aural-menu--section-order-choice 'section-first "Section first"))
    (lambda () "Speak the section name and position before the item when changing sections."
      (interactive) (emacsvox-aural-menu--set-section-order 'section-first "Section first")) :transient t)
   ("m" (lambda () (emacsvox-aural-menu--section-order-choice 'by-movement "By movement: sections or items"))
    (lambda () "Speak sections with section arrows and items with item arrows.
Section arrows still select the first item."
      (interactive) (emacsvox-aural-menu--set-section-order 'by-movement "By movement: sections or items")) :transient t)
   ("v" (lambda ()
          (propertize
           (if emacsvox-transient-verbose-descriptions
               "Detailed descriptions: on" "Detailed descriptions: off")
           'emacsvox-transient-toggle-state
           (if emacsvox-transient-verbose-descriptions 'on 'off)
           emacsvox-aural-facts-property
           (when emacsvox-transient-verbose-descriptions '(:states (selected)))))
    emacsvox-aural-menu--toggle-descriptions :transient t)]
  ["Save and finish"
   ("S" "Save as default" emacsvox-aural-menu--save-navigation :transient t)
   ("q" "Back (keep changes)" transient-quit-one)
   ("C-q" "Close all menus" transient-quit-all)])

(defun emacsvox-aural-menu--rate-value ()
  "Return the rate in the selected settings scope as a number."
  (let* ((context (emacsvox-aural-menu--context))
         (source (emacsvox-aural-menu--source context))
         (value (if (cdr (plist-get context :settings))
                    (default-value 'tts-speech-rate)
                  (buffer-local-value 'tts-speech-rate source))))
    (when (and (stringp value)
               (string-match-p "\\`[0-9]+\\(?:\\.[0-9]+\\)?\\'" value))
      (setq value (string-to-number value)))
    (unless (numberp value)
      (user-error "The current speech rate is not numeric"))
    value))

(defun emacsvox-aural-menu--rate (&optional direction)
  "Set speech rate, or adjust it by DIRECTION times the configured step.
Global scope changes the default and current buffer for this session."
  (interactive)
  (let* ((context (emacsvox-aural-menu--context))
         (source (emacsvox-aural-menu--source context))
         (global (cdr (plist-get context :settings))))
    (with-current-buffer source
      (unless (process-live-p tts-speaker-process)
        (user-error "Start speech before changing its rate"))
      (let* ((omnivox (tts--omnivox-program-p))
             (current (emacsvox-aural-menu--rate-value))
             (value (if direction
                        (max 0 (+ current (* direction tts-speech-rate-step)))
                      (emacsvox-aural-menu--read-number
                       (if omnivox "Speech rate (0 to 100): " "Speech rate: ") current))))
        (when (and direction omnivox) (setq value (min 100 value)))
        (unless (and (numberp value) (>= value 0) (or (not omnivox) (<= value 100)))
          (user-error (if omnivox "Speech rate must be from 0 to 100"
                        "Speech rate must be non-negative")))
        (tts-set-rate value global)
        (emacsvox-transient--submit-text
         (format "%s" value)
         (emacsvox-transient--item-facts
          'value 'speech-rate 'command-menu-value-changed '(selected))
         'state-change 'select-object)))))

(defun emacsvox-aural-menu--adjust-rate (direction)
  "Adjust the focused rate control in DIRECTION."
  (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
  (let ((object
         (with-selected-window (emacsvox-transient--navigation-window)
           (when-let* ((button (button-at (point))))
             (button-get button 'button-data)))))
    (if (and (eieio-object-p object)
             (eq (oref object command) 'emacsvox-aural-menu--rate))
        (emacsvox-aural-menu--rate direction)
      (emacsvox-transient--submit-text
       "Not adjustable. Enter activates; left and right change sections."
       (emacsvox-transient--item-facts 'command 'adjust 'operation-failed)
       'state-change 'warn-user))))

(defun emacsvox-aural-menu--rate-decrease ()
  "Lower the selected speech rate by the configured step."
  (interactive)
  (emacsvox-aural-menu--adjust-rate -1))

(defun emacsvox-aural-menu--rate-increase ()
  "Raise the selected speech rate by the configured step."
  (interactive)
  (emacsvox-aural-menu--adjust-rate 1))

(defun emacsvox-aural-menu--punctuation-value ()
  "Return punctuation in the selected scope, including automatic policy."
  (let* ((context (emacsvox-aural-menu--context))
         (source (emacsvox-aural-menu--source context)))
    (if (cdr (plist-get context :settings))
        (default-value 'tts-punctuation-mode)
      (with-current-buffer source
        (plist-get (tts-punctuation-mode-state) :mode)))))

(defun emacsvox-aural-menu--punctuation-label ()
  "Describe punctuation and its policy in the selected scope."
  (let* ((context (emacsvox-aural-menu--context))
         (source (emacsvox-aural-menu--source context)))
    (with-current-buffer source
      (if (cdr (plist-get context :settings))
          (format "Punctuation: %s, global default"
                  (omnivox-punctuation-profiles--describe (default-value 'tts-punctuation-mode)))
        (tts--punctuation-mode-description)))))

(defun emacsvox-aural-menu--punctuation-choice (mode label)
  "Describe punctuation MODE with LABEL and its selected state."
  (if (equal mode (emacsvox-aural-menu--punctuation-value))
      (propertize (concat label " (selected)")
                  emacsvox-aural-facts-property '(:states (selected)))
    label))

(defun emacsvox-aural-menu--set-punctuation (mode)
  "Apply punctuation MODE through the existing setter in the selected scope."
  (let* ((context (emacsvox-aural-menu--context))
         (source (emacsvox-aural-menu--source context))
         (global (cdr (plist-get context :settings))))
    (with-current-buffer source
      (tts-set-punctuations mode global)
      (emacsvox-transient--submit-text
       (concat (omnivox-punctuation-profiles--describe mode)
               (if global ", global default and current buffer" ", buffer override"))
       (emacsvox-transient--item-facts
        'value 'punctuation 'command-menu-value-changed '(selected))
       'state-change 'select-object))))

(defun emacsvox-aural-menu--choose-punctuation ()
  "Choose a built-in punctuation level or an available named profile."
  (interactive)
  (with-current-buffer (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
    (emacsvox-aural-menu--set-punctuation (omnivox-punctuation-profiles--read))))

(defun emacsvox-aural-menu--local-scope-p ()
  "Return non-nil when settings target the current buffer."
  (not (cdr (plist-get (emacsvox-aural-menu--context) :settings))))

(defun emacsvox-aural-menu--reset-punctuation ()
  "Restore automatic punctuation policy for the source buffer."
  (interactive)
  (unless (emacsvox-aural-menu--local-scope-p)
    (user-error "Choose current buffer scope to restore automatic punctuation"))
  (with-current-buffer (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
    (tts-reset-punctuation-mode)
    (emacsvox-transient--submit-text
     (tts--punctuation-mode-description)
     (emacsvox-transient--item-facts
      'value 'punctuation 'command-menu-value-changed '(selected))
     'state-change 'select-object)))

(defun emacsvox-aural-menu--rate-default-option ()
  "Return the startup rate option for the configured speech backend."
  ;; Match the adapter selection in `voice-setup'.
  (let* ((backend (cond ((string-match "outloud" tts-program) 'outloud)
                        ((string-match "dtk" tts-program) 'dectalk)
                        ((string-match "swiftmac" tts-program) 'swiftmac)
                        ((string-match "mac\\'" tts-program) 'mac)
                        ((string-match "espeak\\'" tts-program) 'espeak)
                        ((tts--omnivox-program-p) 'omnivox)
                        (t 'plain)))
         (option (intern (format "%s-default-speech-rate" backend))))
    (require (intern (format "%s-voices" backend)))
    (unless (custom-variable-p option)
      (user-error "This speech backend has no customizable startup rate"))
    option))

(defun emacsvox-aural-menu--save-speech ()
  "Save the displayed rate and punctuation as defaults across restarts.
Save rate through the backend's startup option.  Punctuation mode policies
and explicit buffer overrides still take precedence over its saved default."
  (interactive)
  (let* ((source (emacsvox-aural-menu--source (emacsvox-aural-menu--context)))
         (rate (emacsvox-aural-menu--rate-value))
         (punctuation (emacsvox-aural-menu--punctuation-value))
         (option (with-current-buffer source (emacsvox-aural-menu--rate-default-option))))
    (customize-save-variable option rate)
    (set-default 'tts-speech-rate rate)
    (customize-save-variable 'tts-punctuation-mode punctuation)
    (with-current-buffer source
      (emacsvox-transient--submit-text
       "Saved rate and punctuation defaults. Punctuation mode policies still apply."
       (emacsvox-transient--menu-facts 'save-speech 'operation-completed)
       'state-change 'save-object))))

(defun emacsvox-aural-menu--save-punctuation ()
  "Save the displayed punctuation as the default across restarts.
Mode policies and explicit buffer overrides still take precedence."
  (interactive)
  (let ((source (emacsvox-aural-menu--source (emacsvox-aural-menu--context)))
        (punctuation (emacsvox-aural-menu--punctuation-value)))
    (customize-save-variable 'tts-punctuation-mode punctuation)
    (with-current-buffer source
      (emacsvox-transient--submit-text
       "Saved punctuation default. Mode policies still apply."
       (emacsvox-transient--menu-facts 'save-punctuation 'operation-completed)
       'state-change 'save-object))))

(defun emacsvox-aural-menu--pronunciations ()
  "Open pronunciation drafts; q returns to the punctuation menu."
  (interactive)
  (emacsvox-aural-menu--open-browser
   (lambda ()
     (omnivox-punctuation)
     (get-buffer "*Omnivox Punctuation*"))
   'emacsvox-aural-menu--pronunciations))

(transient-define-prefix emacsvox-aural-menu-punctuation (&optional global)
  "Choose punctuation for this buffer or the session's global default.
Global changes also apply to the source buffer.  S saves the displayed choice
as the default across restarts; mode policies still take precedence."
  :refresh-suffixes t
  ["Scope"
   ("g" (lambda () (concat "Scope: " (emacsvox-aural-menu--scope-label)))
    emacsvox-aural-menu--toggle-scope :transient t)]
  ["Punctuation"
   ("n" (lambda () (emacsvox-aural-menu--punctuation-choice 'none "None"))
    (lambda () "Speak no punctuation." (interactive)
      (emacsvox-aural-menu--set-punctuation 'none)) :transient t)
   ("s" (lambda () (emacsvox-aural-menu--punctuation-choice 'some "Some"))
    (lambda () "Speak selected punctuation." (interactive)
      (emacsvox-aural-menu--set-punctuation 'some)) :transient t)
   ("a" (lambda () (emacsvox-aural-menu--punctuation-choice 'all "All"))
    (lambda () "Speak all punctuation." (interactive)
      (emacsvox-aural-menu--set-punctuation 'all)) :transient t)
   ("p" (lambda ()
          (let ((mode (emacsvox-aural-menu--punctuation-value)))
            (if (omnivox-punctuation-profiles--mode-p mode)
                (emacsvox-aural-menu--punctuation-choice
                 mode (format "Profile: %s" (cadr mode)))
              "Choose level or named profile")))
    emacsvox-aural-menu--choose-punctuation :transient t)
   ("r" "Restore automatic policy" emacsvox-aural-menu--reset-punctuation
    :if emacsvox-aural-menu--local-scope-p :transient t)]
  ["Save and finish"
   ("e" "Edit pronunciations (separate Save and Restart)" emacsvox-aural-menu--pronunciations :transient transient--do-suspend)
   ("S" "Save punctuation as default" emacsvox-aural-menu--save-punctuation :transient t)
   ("q" "Back (keep changes)" transient-quit-one)
   ("C-q" "Close all menus" transient-quit-all)]
  (interactive "P")
  (let* ((prefix (or transient--prefix transient-current-prefix))
         (context (if (and prefix
                           (memq (oref prefix command)
                                 '(emacsvox-aural-menu-speech emacsvox-aural-menu-punctuation)))
                      (oref prefix scope)
                    (emacsvox-aural-menu--capture global))))
    (emacsvox-aural-menu--source context)
    (transient-setup 'emacsvox-aural-menu-punctuation nil nil :scope context)))

;;;###autoload
(transient-define-prefix emacsvox-aural-menu-speech (&optional global)
  "Choose speech settings for the source buffer or global defaults.
With prefix GLOBAL, start with global defaults when opening directly.
When opened from the Emacsvox menu, share its selected scope."
  :refresh-suffixes t
  ["Speech settings"
   ("g" (lambda () (concat "Scope: " (emacsvox-aural-menu--scope-label)))
    emacsvox-aural-menu--toggle-scope :transient t)
   ("i" (lambda () (emacsvox-aural-menu--indentation-label))
    emacsvox-aural-menu--indentation :transient transient--do-stack)
   ("r" (lambda () (format "Rate: %s" (emacsvox-aural-menu--rate-value)))
    emacsvox-aural-menu--rate :transient t)
   ("p" (lambda () (emacsvox-aural-menu--punctuation-label))
    emacsvox-aural-menu-punctuation :transient transient--do-stack)
   ("c" "Capitalization" emacsvox-capitalization :transient transient--do-stack)
   ("t" "Typing and interaction" emacsvox-interaction :transient transient--do-stack)
   ("n" "Menu navigation (global)" emacsvox-aural-menu-navigation
    :transient transient--do-stack)]
  ["Save and finish"
   ("S" "Save rate and punctuation as defaults" emacsvox-aural-menu--save-speech :transient t)
   ("q" "Back (keep changes)" transient-quit-one)
   ("C-q" "Close all menus" transient-quit-all)]
  (interactive "P")
  (let* ((prefix (or transient--prefix transient-current-prefix))
         (context (if (and prefix
                           (memq (oref prefix command)
                                 '(emacsvox-aural-menu emacsvox-aural-menu-speech)))
                      (oref prefix scope)
                    (emacsvox-aural-menu--capture global))))
    (emacsvox-aural-menu--source context)
    (transient-setup 'emacsvox-aural-menu-speech nil nil :scope context)))

(defconst emacsvox-aural-menu--output-controls
  '((emacsvox-aural-menu--main-tones tts-main-tone-volume "Tones")
    (emacsvox-aural-menu--main-earcons tts-main-earcon-volume "Earcons")
    (emacsvox-aural-menu--notification-speech tts-notification-speech-volume "Speech")
    (emacsvox-aural-menu--notification-tones tts-notification-tone-volume "Tones")
    (emacsvox-aural-menu--notification-earcons tts-notification-earcon-volume "Earcons"))
  "Output commands, global volume options, and labels.")

(defun emacsvox-aural-menu--output-label (command)
  "Describe COMMAND's current output volume."
  (let ((control (assq command emacsvox-aural-menu--output-controls)))
    (format "%s: %d percent" (nth 2 control) (default-value (nth 1 control)))))

(defun emacsvox-aural-menu--output-volume (symbol &optional delta)
  "Set global output option SYMBOL, or adjust it by DELTA percentage points."
  (let* ((source (emacsvox-aural-menu--source (emacsvox-aural-menu--context)))
         (value (if delta
                    (max 0 (min 100 (+ (default-value symbol) delta)))
                  (emacsvox-aural-menu--read-number
                   "Global volume (0 to 100): " (default-value symbol)))))
    (tts--validate-output-volume value)
    (customize-set-variable symbol value)
    (with-current-buffer source
      (emacsvox-transient--submit-text
       (format "%d percent" value)
       (emacsvox-transient--item-facts
        'value symbol 'command-menu-value-changed '(selected))
       'state-change 'select-object))))

(defun emacsvox-aural-menu--read-number (prompt value)
  "Read a number with PROMPT and default VALUE, retaining menu focus."
  (let ((prefix transient--prefix)
        (focus (when (window-live-p transient--window)
                 (with-selected-window transient--window
                   (when-let* ((button (button-at (point))))
                     (button-get button 'button-data))))))
    (unwind-protect
        (read-number prompt value)
      ;; Transient can destroy its popup while the minibuffer is active.
      (when (and focus prefix (eq transient--prefix prefix))
        (transient--show)
        (with-selected-window transient--window
          (transient--goto-button focus))))))

(defun emacsvox-aural-menu--main-tones ()
  "Set the volume of main-stream tones, including indentation tones."
  (interactive)
  (emacsvox-aural-menu--output-volume 'tts-main-tone-volume))

(defun emacsvox-aural-menu--main-earcons ()
  "Set the volume of main-stream earcons played by Omnivox."
  (interactive)
  (emacsvox-aural-menu--output-volume 'tts-main-earcon-volume))

(defun emacsvox-aural-menu--notification-speech ()
  "Set speech volume on the separate Omnivox notification output."
  (interactive)
  (emacsvox-aural-menu--output-volume 'tts-notification-speech-volume))

(defun emacsvox-aural-menu--notification-tones ()
  "Set tone volume on the separate Omnivox notification output."
  (interactive)
  (emacsvox-aural-menu--output-volume 'tts-notification-tone-volume))

(defun emacsvox-aural-menu--notification-earcons ()
  "Set earcon volume on the separate Omnivox notification output."
  (interactive)
  (emacsvox-aural-menu--output-volume 'tts-notification-earcon-volume))

(defun emacsvox-aural-menu--adjust-output (delta)
  "Adjust the selected output control by DELTA percentage points."
  (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
  (let* ((object
          (with-selected-window (emacsvox-transient--navigation-window)
            (when-let* ((button (button-at (point))))
              (button-get button 'button-data))))
         (control (and (eieio-object-p object)
                       (assq (oref object command) emacsvox-aural-menu--output-controls))))
    (if control
        (emacsvox-aural-menu--output-volume (nth 1 control) delta)
      (emacsvox-transient--submit-text
       "Not adjustable. Enter activates; left and right change sections."
       (emacsvox-transient--item-facts 'command 'adjust 'operation-failed)
       'state-change 'warn-user))))

(defun emacsvox-aural-menu--output-decrease ()
  "Lower the selected output volume by five percentage points."
  (interactive)
  (emacsvox-aural-menu--adjust-output -5))

(defun emacsvox-aural-menu--output-increase ()
  "Raise the selected output volume by five percentage points."
  (interactive)
  (emacsvox-aural-menu--adjust-output 5))

(defun emacsvox-aural-menu--output-bindings (map)
  "Add shifted-arrow adjustment to MAP for output volumes or speech rate."
  (when (and transient-enable-menu-navigation transient--prefix)
    (pcase (oref transient--prefix command)
      ('emacsvox-aural-menu-sounds
       (keymap-set map "S-<left>" #'emacsvox-aural-menu--output-decrease)
       (keymap-set map "S-<right>" #'emacsvox-aural-menu--output-increase))
      ('emacsvox-aural-menu-speech
       (keymap-set map "S-<left>" #'emacsvox-aural-menu--rate-decrease)
       (keymap-set map "S-<right>" #'emacsvox-aural-menu--rate-increase))))
  map)

(advice-add 'transient--make-transient-map :filter-return
            #'emacsvox-aural-menu--output-bindings)
(define-key transient-predicate-map [emacsvox-aural-menu--output-decrease]
            #'transient--do-stay)
(define-key transient-predicate-map [emacsvox-aural-menu--output-increase]
            #'transient--do-stay)
(define-key transient-predicate-map [emacsvox-aural-menu--rate-decrease]
            #'transient--do-stay)
(define-key transient-predicate-map [emacsvox-aural-menu--rate-increase]
            #'transient--do-stay)

(defun emacsvox-aural-menu--save-output ()
  "Keep all five output volumes across restarts."
  (interactive)
  (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
  (dolist (control emacsvox-aural-menu--output-controls)
    (customize-save-variable (nth 1 control) (default-value (nth 1 control))))
  (emacsvox-transient--submit-text
   "Saved output volumes"
   (emacsvox-transient--menu-facts 'save-output 'operation-completed)
   'state-change 'save-object))

(defun emacsvox-aural-menu--open-browser (open command)
  "Call OPEN in the source and return from its buffer to menu COMMAND."
  (let* ((context (emacsvox-aural-menu--context))
         (source (emacsvox-aural-menu--source context))
         (stack (copy-sequence transient--stack)))
    (with-current-buffer source
      (with-current-buffer (funcall open)
        (setq-local emacsvox-aural-ui--return-function
                    (lambda ()
                      (when (buffer-live-p source)
                        (pop-to-buffer source)
                        ;; Own the saved stack even if another menu was opened.
                        (setq transient--stack (copy-sequence stack))
                        (transient--stack-pop)
                        (transient--show)
                        (with-selected-window transient--window
                          (transient--goto-button
                           (transient-suffix-object command)))
                        t)))))))

(defun emacsvox-aural-menu--sound-packs ()
  "Open the sound-pack browser; q returns to Sounds and output."
  (interactive)
  (emacsvox-aural-menu--open-browser
   #'emacsvox-aural-list-sound-packs 'emacsvox-aural-menu--sound-packs))

(defun emacsvox-aural-menu--browse-voices ()
  "Browse engines and their voices; q returns through the browser parents."
  (interactive)
  (emacsvox-aural-menu--open-browser
   (lambda () (emacsvox-aural-voice-workbench 'engines))
   'emacsvox-aural-menu--browse-voices))

(defun emacsvox-aural-menu--voice-palettes ()
  "Open voice palettes; q returns to Voices and engines."
  (interactive)
  (emacsvox-aural-menu--open-browser
   #'emacsvox-aural-list-voice-palettes 'emacsvox-aural-menu--voice-palettes))

(defun emacsvox-aural-menu--voice-workbench ()
  "Resume the Voice Workbench; q returns to Voices and engines."
  (interactive)
  (emacsvox-aural-menu--open-browser
   #'emacsvox-aural-voice-workbench 'emacsvox-aural-menu--voice-workbench))

(defun emacsvox-aural-menu--prefer-engine (&optional save)
  "Choose a global engine preference, persisting it only with SAVE."
  (interactive)
  (with-current-buffer (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
    (let ((current-prefix-arg (and save '(4))))
      (call-interactively #'emacsvox-aural-prefer-engine))))

(defun emacsvox-aural-menu--save-preferred-engine ()
  "Choose and explicitly save a global engine preference."
  (interactive)
  (emacsvox-aural-menu--prefer-engine t))

(defun emacsvox-aural-menu--restore-engine-order ()
  "Restore the saved or initial global engine order."
  (interactive)
  (with-current-buffer (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
    (call-interactively #'emacsvox-aural-restore-saved-engine-order)))

(transient-define-prefix emacsvox-aural-menu-voices ()
  "Browse voices and palettes or choose a global engine preference.
Browser quit commands return here after unwinding their own child views.
Engine preferences last for this session unless explicitly saved."
  ["Voices and engines"
   ("b" "Browse voices and engines" emacsvox-aural-menu--browse-voices :transient transient--do-suspend)
   ("p" "Voice palettes" emacsvox-aural-menu--voice-palettes :transient transient--do-suspend)
   ("w" "Resume Voice Workbench" emacsvox-aural-menu--voice-workbench :transient transient--do-suspend)]
  ["Engine preference (global)"
   ("e" "Choose preferred engine for this session" emacsvox-aural-menu--prefer-engine :transient t)
   ("S" "Choose and save preferred engine" emacsvox-aural-menu--save-preferred-engine :transient t)
   ("r" "Restore saved or initial engine order" emacsvox-aural-menu--restore-engine-order :transient t)]
  ["Finish"
   ("q" "Back" transient-quit-one)
   ("C-q" "Close all menus" transient-quit-all)]
  (interactive)
  (let* ((prefix (or transient--prefix transient-current-prefix))
         (context (if (and prefix
                           (memq (oref prefix command)
                                 '(emacsvox-aural-menu emacsvox-aural-menu-voices)))
                      (oref prefix scope)
                    (emacsvox-aural-menu--capture nil))))
    (emacsvox-aural-menu--source context)
    (transient-setup 'emacsvox-aural-menu-voices nil nil :scope context)))

(transient-define-prefix emacsvox-aural-menu-line-cues ()
  "Choose a global line tone or boundary earcon to preview and edit."
  ["Line tones"
   ("b" "Blank line" (lambda () "Edit the blank line cue." (interactive) (emacsvox-line-cues-edit 'empty)) :transient transient--do-stack)
   ("w" "Whitespace-only line" (lambda () "Edit the whitespace-only line cue." (interactive) (emacsvox-line-cues-edit 'whitespace-only)) :transient transient--do-stack)
   ("s" "Separator line" (lambda () "Edit the separator line cue." (interactive) (emacsvox-line-cues-edit 'separator)) :transient transient--do-stack)
   ("d" "Decorated line" (lambda () "Edit the decorated line cue." (interactive) (emacsvox-line-cues-edit 'decorative)) :transient transient--do-stack)
   ("u" "Unspeakable line" (lambda () "Edit the unspeakable line cue." (interactive) (emacsvox-line-cues-edit 'unspeakable)) :transient transient--do-stack)]
  ["Boundary earcons (all uses of these cues)"
   ("e" "Boundary and warning" (lambda () "Edit the warning cue." (interactive) (emacsvox-line-cues-edit 'warn-user)) :transient transient--do-stack)
   ("m" "Large movement" (lambda () "Edit the large movement cue." (interactive) (emacsvox-line-cues-edit 'large-movement)) :transient transient--do-stack)]
  ["Finish"
   ("q" "Back" transient-quit-one)
   ("C-q" "Close all menus" transient-quit-all)]
  (interactive)
  (transient-setup 'emacsvox-aural-menu-line-cues nil nil :scope (emacsvox-aural-menu--context)))

(transient-define-prefix emacsvox-aural-menu-sounds ()
  "Adjust global output volumes or browse sound packs.
Shift left and right adjust the selected volume by five percentage points.
Enter sets an exact value.  Save explicitly to retain volumes across restarts."
  :refresh-suffixes t
  ["Main output (global)"
   ("t" (lambda () (emacsvox-aural-menu--output-label 'emacsvox-aural-menu--main-tones))
    emacsvox-aural-menu--main-tones :transient t)
   ("e" (lambda () (emacsvox-aural-menu--output-label 'emacsvox-aural-menu--main-earcons))
    emacsvox-aural-menu--main-earcons :transient t)]
  ["Separate notifications (global)"
   ("s" (lambda () (emacsvox-aural-menu--output-label 'emacsvox-aural-menu--notification-speech))
    emacsvox-aural-menu--notification-speech :transient t)
   ("T" (lambda () (emacsvox-aural-menu--output-label 'emacsvox-aural-menu--notification-tones))
    emacsvox-aural-menu--notification-tones :transient t)
   ("E" (lambda () (emacsvox-aural-menu--output-label 'emacsvox-aural-menu--notification-earcons))
    emacsvox-aural-menu--notification-earcons :transient t)]
  ["Cues and sound packs"
   ("n" "Notifications and spatial output" emacsvox-output-settings :transient transient--do-stack)
   ("c" "Line and boundary cues" emacsvox-aural-menu-line-cues :transient transient--do-stack)
   ("p" "Browse sound packs" emacsvox-aural-menu--sound-packs :transient transient--do-suspend)]
  ["Save and finish"
   ("S" "Save output volumes" emacsvox-aural-menu--save-output :transient t)
   ("q" "Back (keep changes)" transient-quit-one)
   ("C-q" "Close all menus" transient-quit-all)]
  (interactive)
  (let* ((prefix (or transient--prefix transient-current-prefix))
         (context (if (and prefix
                           (memq (oref prefix command)
                                 '(emacsvox-aural-menu emacsvox-aural-menu-sounds)))
                      (oref prefix scope)
                    (emacsvox-aural-menu--capture nil))))
    (emacsvox-aural-menu--source context)
    (transient-setup 'emacsvox-aural-menu-sounds nil nil :scope context)))

;;;###autoload
(transient-define-prefix emacsvox-aural-menu (&optional global)
  "Choose Emacsvox speech settings or inspect feedback for this item.
With prefix GLOBAL, start speech settings with global defaults.
The source item is captured on entry; Aural Home offers all other actions."
  :refresh-suffixes t
  ["Emacsvox"
   ("s" (lambda () (concat "Speech settings: " (emacsvox-aural-menu--scope-label)))
    emacsvox-aural-menu-speech)
   ("o" "Sounds and output (global)" emacsvox-aural-menu-sounds)
   ("v" "Voices and engines" emacsvox-aural-menu-voices)
   ("j" "Integration settings" emacsvox-settings-integrations :transient transient--do-stack)
   ("p" "Saved setups and drafts" emacsvox-settings-setups :transient transient--do-stack)
   ("r" "Presentation and rules" emacsvox-settings-presentation :transient transient--do-stack)
   ("f" "Edit current or recent feedback" emacsvox-settings-feedback :transient transient--do-stack)
   ("x" "Feedback for this item" emacsvox-aural-menu--feedback)
   ("h" "Aural Home (all actions)" emacsvox-aural-menu--home)
   ("/" "Find an Emacsvox setting" emacsvox-settings-search :transient transient--do-stack)
   ("a" "Search all Home actions" emacsvox-settings-search-actions :transient transient--do-suspend)
   ("." "Settings for this buffer" emacsvox-settings-buffer :transient transient--do-stack)]
  ["Finish"
   ("q" "Close" transient-quit-one)]
  (interactive "P")
  (transient-setup 'emacsvox-aural-menu nil nil
                   :scope (emacsvox-aural-menu--capture global)))

(provide 'emacsvox-aural-menu)
;;; emacsvox-aural-menu.el ends here
