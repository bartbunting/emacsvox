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
(autoload 'emacsvox-explain-aural-presentation "emacsvox-aural-explanation" nil t)

(defun emacsvox-aural-menu--context ()
  "Return the context owned by the current entry or speech menu."
  (let ((prefix (or transient--prefix transient-current-prefix)))
    (unless (and prefix
                 (memq (oref prefix command)
                       '(emacsvox-aural-menu emacsvox-aural-menu-speech)))
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
   ("n" "Menu navigation (global)" emacsvox-aural-menu-navigation
    :transient transient--do-stack)]
  ["Finish"
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

;;;###autoload
(transient-define-prefix emacsvox-aural-menu (&optional global)
  "Choose Emacsvox speech settings or inspect feedback for this item.
With prefix GLOBAL, start speech settings with global defaults.
The source item is captured on entry; Aural Home offers all other actions."
  :refresh-suffixes t
  ["Emacsvox"
   ("s" (lambda () (concat "Speech settings: " (emacsvox-aural-menu--scope-label)))
    emacsvox-aural-menu-speech)
   ("x" "Feedback for this item" emacsvox-aural-menu--feedback)
   ("h" "Aural Home (all actions)" emacsvox-aural-menu--home)]
  ["Finish"
   ("q" "Close" transient-quit-one)]
  (interactive "P")
  (transient-setup 'emacsvox-aural-menu nil nil
                   :scope (emacsvox-aural-menu--capture global)))

(provide 'emacsvox-aural-menu)
;;; emacsvox-aural-menu.el ends here
