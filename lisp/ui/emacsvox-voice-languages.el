;;; emacsvox-voice-languages.el --- Languages shown in voice browsers -*- lexical-binding: t; -*-

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

;; Choose which languages to show when browsing physical voices. Speech
;; workers use their full inventories to resolve saved and active voices.

;;; Code:

(require 'emacsvox-aural-ui)
(require 'tts-voice-api)

(declare-function tts-speak "tts-speak" (text))
(declare-function custom-file "cus-edit" (&optional no-error))
(declare-function emacsvox-aural-voice-workbench--language-label "emacsvox-aural-voice-workbench-views" (tag))
(defvar emacsvox-aural-voice-workbench--language-names)

(defvar-local emacsvox-voice-browser--redraw nil
  "Function to redraw this open voice list after its language filter changes.")

(defun emacsvox-voice-browser--language (tag)
  "Return the primary language of TAG, or \"und\" for an unspecified language."
  (or (and (stringp tag) (car (split-string (downcase (string-trim tag)) "[-_]" t)))
      "und"))

(defcustom emacsvox-voice-browser-languages nil
  "Languages to show when browsing physical voices on any connected speech server.
An empty list shows all voices.  Use primary language codes, such as
\"en\" for all English voices or \"fr\" for all French voices.  Use \"und\"
for voices with an unspecified language.  This preference affects the
lists and their searches.  Speech uses the complete inventory."
  :type '(repeat (string :tag "Language code")) :group 'tts
  :set (lambda (symbol value)
         (set-default symbol (delete-dups (mapcar #'emacsvox-voice-browser--language value)))
         (dolist (buffer (buffer-list))
           (with-current-buffer buffer
             (when emacsvox-voice-browser--redraw
               (funcall emacsvox-voice-browser--redraw))))))

(defun emacsvox-voice-browser--visible-p (tag)
  "Return non-nil when a voice with language TAG belongs in the browser."
  (or (null emacsvox-voice-browser-languages)
      (member (emacsvox-voice-browser--language tag) emacsvox-voice-browser-languages)))

(defvar-local emacsvox-voice-languages--available nil)
(defvar-local emacsvox-voice-languages--original nil)
(defvar-local emacsvox-voice-languages--selected nil)

(defun emacsvox-voice-languages--name (code)
  (if (equal code "und") "Unspecified language"
    (emacsvox-aural-voice-workbench--language-label code)))

(defun emacsvox-voice-languages--draw ()
  (emacsvox-aural-ui-refresh-tabulated
   (lambda ()
     (setq tabulated-list-entries
           (cons (list 'all (vector "All languages" (if emacsvox-voice-languages--selected "" "Selected")))
                 (mapcar (lambda (code)
                           (list code (vector (emacsvox-voice-languages--name code)
                                              (if (member code emacsvox-voice-languages--selected) "Selected" ""))))
                         emacsvox-voice-languages--available))))))

(defun emacsvox-voice-languages--speak ()
  (when-let* ((row (tabulated-list-get-entry)))
    (tts-speak (format "%s, %s" (aref row 0) (if (string-empty-p (aref row 1)) "unselected" "selected")))))

(defun emacsvox-voice-languages--toggle ()
  "Toggle this language. The All languages row clears the pending filter."
  (interactive)
  (let ((code (or (tabulated-list-get-id) (user-error "Move to a language first"))))
    (setq emacsvox-voice-languages--selected
          (cond ((eq code 'all) nil)
                ((member code emacsvox-voice-languages--selected)
                 (remove code emacsvox-voice-languages--selected))
                (t (cons code emacsvox-voice-languages--selected))))
    (emacsvox-voice-languages--draw)
    (emacsvox-voice-languages--speak)))

(defun emacsvox-voice-languages--quit ()
  "Return to the previous view and discard pending language changes."
  (interactive)
  (emacsvox-aural-quit t))

(defun emacsvox-voice-languages--save ()
  "Save the selected browsing languages for all connections and return."
  (interactive)
  (let ((selection (sort (copy-sequence emacsvox-voice-languages--selected) #'string-lessp)))
    (unless (or (equal emacsvox-voice-languages--original emacsvox-voice-browser-languages)
                (equal selection emacsvox-voice-browser-languages))
      (user-error "Voice languages changed in another view. Reopen the list to edit the saved selection"))
    (customize-save-variable 'emacsvox-voice-browser-languages selection)
    (emacsvox-voice-languages--quit)
    (tts-speak (concat (if (custom-file t) "Saved. " "For this Emacs session. ")
                       (if selection (mapconcat #'emacsvox-voice-languages--name selection ", ")
                         "Showing all voice languages")))))

(define-derived-mode emacsvox-voice-languages-mode emacsvox-aural-tabulated-mode "Voice Languages"
  "Choose browsing languages. Return toggles a language, s saves and q cancels."
  (setq tabulated-list-format [("Language" 30 nil) ("Selection" 12 nil)])
  (emacsvox-aural-ui-configure-tabulated "Voice languages" #'emacsvox-voice-languages--speak
                                         #'emacsvox-voice-languages--draw #'emacsvox-voice-languages--speak)
  (tabulated-list-init-header))

(keymap-set emacsvox-voice-languages-mode-map "RET" #'emacsvox-voice-languages--toggle)
(keymap-set emacsvox-voice-languages-mode-map "s" #'emacsvox-voice-languages--save)
(keymap-set emacsvox-voice-languages-mode-map "q" #'emacsvox-voice-languages--quit)

;;;###autoload
(defun emacsvox-choose-voice-languages ()
  "Choose which languages appear in physical voice browsers and voice pickers.
Return toggles a language and s saves the list across sessions. Select All
languages to include every voice. Each language includes its regional voices."
  (interactive)
  (require 'emacsvox-aural-voice-workbench)
  (let* ((source (current-buffer))
         (observed (cl-loop for engine in (plist-get (tts-voice-inventory) :engines) append
                            (mapcar (lambda (v) (emacsvox-voice-browser--language (plist-get v :language)))
                                    (plist-get engine :voices))))
         (buffer (generate-new-buffer "*Voice browser languages*")))
    (with-current-buffer buffer
      (emacsvox-voice-languages-mode)
      (emacsvox-aural-ui-register-interface source)
      (setq emacsvox-voice-languages--original (copy-sequence emacsvox-voice-browser-languages)
            emacsvox-voice-languages--selected (copy-sequence emacsvox-voice-browser-languages)
            emacsvox-voice-languages--available
            (seq-sort-by #'emacsvox-voice-languages--name #'string-lessp
                         (delete-dups (append '("und") observed emacsvox-voice-browser-languages
                                              (mapcar #'car emacsvox-aural-voice-workbench--language-names)))))
      (emacsvox-voice-languages--draw)
      (emacsvox-aural-ui-goto-row (or (car emacsvox-voice-languages--selected) 'all)))
    (let ((display-buffer-overriding-action '((display-buffer-same-window))))
      (emacsvox-aural-ui--pop-to-buffer
       buffer (lambda ()
                (tts-speak (format "Voice languages. %s. Return selects or clears, s saves, q cancels."
                                   (if emacsvox-voice-languages--selected
                                       (mapconcat #'emacsvox-voice-languages--name emacsvox-voice-languages--selected ", ")
                                     "All languages"))))))
    buffer))

(provide 'emacsvox-voice-languages)
;;; emacsvox-voice-languages.el ends here
