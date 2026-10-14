;;; emacsvox-settings.el --- Settings discovery -*- lexical-binding: t; -*-

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
;; Search focused settings or existing Home actions with captured source context.
;;; Code:
(require 'emacsvox-aural-menu)
(require 'cus-edit)
(declare-function emacsvox-aural-home-search "emacsvox-aural-home" ())

(defconst emacsvox-settings--destinations
  '(("Edit current and recent feedback" emacsvox-settings-workflows emacsvox-settings-feedback "c")
    ("Speech rate" emacsvox-aural-menu emacsvox-aural-menu-speech "r")
    ("Punctuation levels and profiles" emacsvox-aural-menu emacsvox-aural-menu-punctuation "p")
    ("Punctuation pronunciations" emacsvox-aural-menu emacsvox-aural-menu-punctuation "e")
    ("Indentation presentation" emacsvox-indentation emacsvox-indentation "p")
    ("Indentation pitch and duration" emacsvox-indentation emacsvox-indentation-tone "b")
    ("Capitalization indication and camel case" emacsvox-capitalization emacsvox-capitalization "i")
    ("Capital-letter beep" emacsvox-capitalization emacsvox-capitalization "l")
    ("All-caps beep" emacsvox-capitalization emacsvox-capitalization "a")
    ("Character echo" emacsvox-interaction emacsvox-interaction "c")
    ("Word echo" emacsvox-interaction emacsvox-interaction "w")
    ("Completed-line echo" emacsvox-interaction emacsvox-interaction "l")
    ("Point indication and presentation" emacsvox-interaction emacsvox-interaction "i")
    ("Spoken messages" emacsvox-interaction emacsvox-interaction "m")
    ("Delayed phonetics" emacsvox-interaction emacsvox-interaction "d")
    ("Menu navigation and announcements" emacsvox-aural-menu emacsvox-aural-menu-navigation "m")
    ("Output volumes" emacsvox-aural-menu emacsvox-aural-menu-sounds "t")
    ("Line and boundary cues" emacsvox-aural-menu emacsvox-aural-menu-line-cues "b")
    ("Notification routing and history" emacsvox-output-settings emacsvox-output-settings "r")
    ("Spatial output and separation" emacsvox-output-settings emacsvox-output-settings "d")
    ("Sound packs" emacsvox-aural-menu emacsvox-aural-menu-sounds "p")
    ("Voices and engines" emacsvox-aural-menu emacsvox-aural-menu-voices "b")
    ("Voice palettes" emacsvox-aural-menu emacsvox-aural-menu-voices "p"))
  "Search labels, defining features, destination prefixes, and selected keys.")
(defun emacsvox-settings--open (entry)
  "Open settings ENTRY with the current captured source and scope."
  (let* ((context (emacsvox-aural-menu--context))
         (command (nth 2 entry)))
    (emacsvox-aural-menu--source context)
    (require (nth 1 entry))
    (transient-setup command nil nil :scope
                     (if (memq command '(emacsvox-indentation emacsvox-indentation-tone))
                         (plist-get context :settings) context))
    (transient--show)
    (with-selected-window transient--window
      (transient--goto-button
       (cl-find (nth 3 entry) transient--suffixes
                :key (lambda (suffix) (oref suffix key)) :test #'equal)))))
;;;###autoload
(defun emacsvox-settings-search ()
  "Find a focused setting and select its control without activating it."
  (interactive)
  (emacsvox-settings--open
   (or (assoc (completing-read "Emacsvox setting: " emacsvox-settings--destinations nil t)
              emacsvox-settings--destinations)
       (user-error "Choose a setting"))))
;;;###autoload
(defun emacsvox-settings-search-actions ()
  "Search the existing Home action catalogue; Home q returns to this menu."
  (interactive)
  (emacsvox-aural-menu--open-browser
   (lambda ()
     (emacsvox-aural-menu--call-at-item #'emacsvox-aural)
     (get-buffer "*Emacsvox Aural*"))
   'emacsvox-settings-search-actions)
  (pop-to-buffer "*Emacsvox Aural*")
  (emacsvox-aural-home-search))
(defun emacsvox-settings--speech ()
  "Open speech settings for this buffer." (interactive)
  (emacsvox-settings--open (assoc "Speech rate" emacsvox-settings--destinations)))
(defun emacsvox-settings--indentation ()
  "Open indentation for this buffer." (interactive)
  (emacsvox-settings--open (assoc "Indentation presentation" emacsvox-settings--destinations)))
(defun emacsvox-settings--interaction ()
  "Open typing and interaction for this buffer." (interactive)
  (emacsvox-settings--open (assoc "Character echo" emacsvox-settings--destinations)))
(defun emacsvox-settings--capitalization ()
  "Open capitalization for this buffer." (interactive)
  (emacsvox-settings--open (assoc "Capitalization indication and camel case" emacsvox-settings--destinations)))
(defun emacsvox-settings--mode-group ()
  "Return the captured source mode's actual Customize group, if known."
  (with-current-buffer (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
    (custom-group-of-mode major-mode)))
(defun emacsvox-settings--custom-quit ()
  "Use Customize's normal finish action, then return to the originating menu."
  (interactive)
  (let ((return emacsvox-aural-ui--return-function))
    (Custom-buffer-done)
    (when return (funcall return))))
(defun emacsvox-settings--custom (group command)
  "Open Customize GROUP and return to menu suffix COMMAND with q."
  (emacsvox-aural-menu--open-browser
   (lambda ()
     (customize-group group)
     (let ((buffer (window-buffer (selected-window))))
       (with-current-buffer buffer
         (use-local-map (copy-keymap (current-local-map)))
         (local-set-key (kbd "q") #'emacsvox-settings--custom-quit))
       buffer)) command))
(defun emacsvox-settings--mode ()
  "Open the captured major mode's Customize group."
  (interactive)
  (emacsvox-settings--custom
   (or (emacsvox-settings--mode-group) (user-error "This mode has no known Customize group"))
   'emacsvox-settings--mode))
(defun emacsvox-settings--advanced ()
  "Open the complete Emacsvox Customize group."
  (interactive)
  (emacsvox-settings--custom 'emacsvox 'emacsvox-settings--advanced))
(defun emacsvox-settings--buffer-title ()
  "Describe the captured buffer and its major mode."
  (let ((source (emacsvox-aural-menu--source (emacsvox-aural-menu--context))))
    (format "Settings for %s (%s)" (buffer-name source)
            (buffer-local-value 'major-mode source))))
;;;###autoload
(transient-define-prefix emacsvox-settings-buffer ()
  "Find settings relevant to the captured source buffer."
  [:description emacsvox-settings--buffer-title
   ("s" "Speech rate and punctuation" emacsvox-settings--speech :transient transient--do-stack)
   ("i" "Indentation" emacsvox-settings--indentation :transient transient--do-stack)
   ("t" "Typing, point, and interaction" emacsvox-settings--interaction :transient transient--do-stack)
   ("c" "Capitalization" emacsvox-settings--capitalization :transient transient--do-stack)
   ("m" "Major-mode settings (Customize)" emacsvox-settings--mode :inapt-if-not emacsvox-settings--mode-group :transient transient--do-suspend)]
  ["Discover more"
   ("/" "Find an Emacsvox setting" emacsvox-settings-search :transient transient--do-stack)
   ("a" "Search all Home actions" emacsvox-settings-search-actions :transient transient--do-suspend)
   ("A" "Advanced Emacsvox settings (Customize)" emacsvox-settings--advanced :transient transient--do-suspend)
   ("q" "Back" transient-quit-one)
   ("C-q" "Close all menus" transient-quit-all)]
  (interactive)
  (let ((context (copy-sequence (emacsvox-aural-menu--context))))
    ;; Buffer discovery starts locally without changing the parent's scope flag.
    (setq context (plist-put context :settings
                             (cons (emacsvox-aural-menu--source context) nil)))
    (transient-setup 'emacsvox-settings-buffer nil nil :scope context)))
(provide 'emacsvox-settings)
;;; emacsvox-settings.el ends here
