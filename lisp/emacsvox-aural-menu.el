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
  "Open Feedback Details for the captured item."
  (interactive)
  (let ((context (emacsvox-aural-menu--context)))
    (emacsvox-aural-menu--call-at-item #'emacsvox-explain-aural-presentation)
    (with-current-buffer (window-buffer (selected-window))
      (when (derived-mode-p 'emacsvox-aural-feedback-details-mode)
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
  "Open all Aural Home actions at the captured item."
  (interactive)
  (emacsvox-aural-menu--call-at-item #'emacsvox-aural))

(defun emacsvox-aural-menu--scope-label ()
  "Describe the selected settings scope."
  (if (cdr (plist-get (emacsvox-aural-menu--context) :settings))
      "Global defaults" "Current buffer"))

(defun emacsvox-aural-menu--toggle-scope ()
  "Switch settings scope without changing any settings."
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
  "Open Indentation with the source and scope shared by its parent."
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
  "Save the current global menu navigation style through Customize."
  (interactive)
  (customize-save-variable 'emacsvox-transient-navigation-style
                           emacsvox-transient-navigation-style)
  (emacsvox-transient--submit-text
   "Saved navigation default"
   (emacsvox-transient--menu-facts 'save-navigation 'operation-completed)
   'state-change 'save-object))

(transient-define-prefix emacsvox-aural-menu-navigation ()
  "Choose navigation for all Transient menus; Left and Right change sections."
  :refresh-suffixes t
  ["Navigation style (global)"
   ("c" (lambda () (emacsvox-aural-menu--navigation-choice 'continuous "Continuous"))
    (lambda () (interactive) (emacsvox-aural-menu--set-navigation 'continuous "Continuous")) :transient t)
   ("w" (lambda () (emacsvox-aural-menu--navigation-choice 'section-wrap "Wrap within section"))
    (lambda () (interactive) (emacsvox-aural-menu--set-navigation 'section-wrap "Wrap within section")) :transient t)
   ("s" (lambda () (emacsvox-aural-menu--navigation-choice 'section-stop "Stop at section edges"))
    (lambda () (interactive) (emacsvox-aural-menu--set-navigation 'section-stop "Stop at section edges")) :transient t)]
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
