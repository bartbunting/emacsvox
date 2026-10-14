;;; emacsvox-interaction.el --- Typing and interaction settings -*- lexical-binding: t; -*-

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
;; Scoped typing echo, point and message feedback, and global phonetic controls.
;; Changes apply immediately; saving startup defaults is explicit.

;;; Code:
(require 'emacsvox-aural-menu)

(defconst emacsvox-interaction--scoped-options
  '(emacsvox-character-echo emacsvox-word-echo emacsvox-line-echo
    emacsvox-show-point emacsvox-show-point-presentation emacsvox-speak-messages)
  "Options displayed in the selected buffer/global scope.")

(defun emacsvox-interaction--value (symbol)
  "Read SYMBOL in the displayed settings scope."
  (let* ((context (emacsvox-aural-menu--context))
         (source (emacsvox-aural-menu--source context)))
    (if (cdr (plist-get context :settings)) (default-value symbol)
      (buffer-local-value symbol source))))

(defun emacsvox-interaction--set (symbol value)
  "Apply scoped SYMBOL VALUE to the source and, when selected, its default."
  (let* ((context (emacsvox-aural-menu--context))
         (source (emacsvox-aural-menu--source context))
         (global (cdr (plist-get context :settings))))
    (with-current-buffer source
      (if (eq symbol 'emacsvox-show-point-presentation)
          (emacsvox-set-show-point-presentation value global)
        (when global (set-default symbol value))
        (set (make-local-variable symbol) value)))))

(defun emacsvox-interaction--say (text)
  "Announce TEXT as replaceable menu feedback, even with messages disabled."
  (emacsvox-transient--submit-text
   text (emacsvox-transient--menu-facts 'interaction 'command-menu-value-changed)
   'state-change 'select-object))

(defun emacsvox-interaction--label (symbol label)
  "Describe scoped boolean SYMBOL with LABEL."
  (format "%s: %s" label (if (emacsvox-interaction--value symbol) "on" "off")))

(defun emacsvox-interaction--toggle (symbol label)
  "Toggle scoped SYMBOL and announce LABEL with its new value."
  (emacsvox-interaction--set symbol (not (emacsvox-interaction--value symbol)))
  (emacsvox-interaction--say (emacsvox-interaction--label symbol label)))

(defun emacsvox-interaction--character ()
  "Toggle character echo." (interactive)
  (emacsvox-interaction--toggle 'emacsvox-character-echo "Character echo"))
(defun emacsvox-interaction--word ()
  "Toggle word echo." (interactive)
  (emacsvox-interaction--toggle 'emacsvox-word-echo "Word echo"))
(defun emacsvox-interaction--line ()
  "Toggle completed-line echo." (interactive)
  (emacsvox-interaction--toggle 'emacsvox-line-echo "Line echo"))
(defun emacsvox-interaction--point ()
  "Toggle point indication during line reading." (interactive)
  (emacsvox-interaction--toggle 'emacsvox-show-point "Point indication"))
(defun emacsvox-interaction--messages ()
  "Toggle spoken messages." (interactive)
  (emacsvox-interaction--toggle 'emacsvox-speak-messages "Spoken messages"))

(defun emacsvox-interaction--presentation ()
  "Choose how line reading indicates point without enabling indication."
  (interactive)
  (let* ((choices '(("Animated voice" . voice) ("Tone" . tone) ("Earcon" . earcon)
                    ("Voice and tone" . voice-tone) ("Voice and earcon" . voice-earcon)
                    ("Spoken point" . spoken) ("Personal rules" . custom) ("None" . none)))
         (choice (completing-read "Point presentation: " choices nil t)))
    (emacsvox-interaction--set 'emacsvox-show-point-presentation (cdr (assoc choice choices)))
    (emacsvox-interaction--say choice)))

(defun emacsvox-interaction--phonetics ()
  "Toggle global delayed phonetics through the mode's cancellation lifecycle."
  (interactive)
  (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
  (emacsvox-delayed-phonetic-mode (if emacsvox-delayed-phonetic-mode -1 1))
  (emacsvox-interaction--say
   (if emacsvox-delayed-phonetic-mode "Delayed phonetics on" "Delayed phonetics off")))

(defun emacsvox-interaction--delay (&optional delta)
  "Set phonetic delay exactly, or adjust by DELTA seconds without saving."
  (interactive)
  (emacsvox-aural-menu--source (emacsvox-aural-menu--context))
  ;; Direct shortcut entry should leave the edited control ready for arrows.
  (when (and (not delta) (window-live-p transient--window))
    (when-let* ((suffix (cl-find 'emacsvox-interaction--delay transient--suffixes
                                :key (lambda (item) (oref item command)))))
      (with-selected-window transient--window
        (transient--goto-button suffix))))
  (let* ((current emacsvox-delayed-phonetic-delay)
         (value (if delta
                    (max 0.1 (/ (round (* 10 (+ current delta))) 10.0))
                  (emacsvox-aural-menu--read-number "Phonetic delay in seconds (minimum 0.1): " current))))
    (unless (and (numberp value) (>= value 0.1) (= (- value value) 0))
      (user-error "Delay must be finite and at least 0.1 seconds"))
    (customize-set-variable 'emacsvox-delayed-phonetic-delay value)
    (emacsvox-interaction--say
     (format "%s%s seconds" (if (and delta (= current value)) "Minimum. " "") value))))

(defun emacsvox-interaction--adjust (direction)
  "Adjust the focused numeric option in DIRECTION."
  (let ((command (with-selected-window (emacsvox-transient--navigation-window)
                   (when-let* ((button (button-at (point))))
                     (oref (button-get button 'button-data) command)))))
    (unless (eq command 'emacsvox-interaction--delay)
      (user-error "Choose Phonetic delay first"))
    (emacsvox-interaction--delay (* 0.1 direction))))
(defun emacsvox-interaction--decrease ()
  "Decrease phonetic delay." (interactive) (emacsvox-interaction--adjust -1))
(defun emacsvox-interaction--increase ()
  "Increase phonetic delay." (interactive) (emacsvox-interaction--adjust 1))

(defun emacsvox-interaction--preview ()
  "Read the captured source line using the displayed point settings."
  (interactive)
  (let ((enabled (emacsvox-interaction--value 'emacsvox-show-point))
        (presentation (emacsvox-interaction--value 'emacsvox-show-point-presentation)))
    (emacsvox-aural-menu--call-at-item
     (lambda ()
       (interactive)
       (let ((emacsvox-show-point enabled)
             (emacsvox-show-point-presentation presentation))
         (emacsvox-speak-line))))))

(defun emacsvox-interaction--phonetic-preview ()
  "Speak the phonetic name at the source immediately, preserving its point."
  (interactive)
  (emacsvox-aural-menu--call-at-item
   (lambda () (interactive) (emacsvox-speak-char))))

(defun emacsvox-interaction--stop ()
  "Stop preview speech and pending phonetic feedback."
  (interactive)
  (tts-stop))

(defun emacsvox-interaction--save ()
  "Save displayed scoped settings and global phonetic settings as defaults."
  (interactive)
  (let ((values (append
                 (mapcar (lambda (symbol) (cons symbol (emacsvox-interaction--value symbol)))
                         emacsvox-interaction--scoped-options)
                 (list (cons 'emacsvox-delayed-phonetic-mode emacsvox-delayed-phonetic-mode)
                       (cons 'emacsvox-delayed-phonetic-delay emacsvox-delayed-phonetic-delay)))))
    (dolist (entry values) (customize-save-variable (car entry) (cdr entry)))
    (emacsvox-interaction--say "Saved interaction defaults. Buffer overrides still apply.")))

(defun emacsvox-interaction--bindings (map)
  "Add shifted-arrow delay adjustment only to the interaction menu MAP."
  (when (and transient--prefix (eq (oref transient--prefix command) 'emacsvox-interaction))
    (keymap-set map "S-<left>" #'emacsvox-interaction--decrease)
    (keymap-set map "S-<right>" #'emacsvox-interaction--increase))
  map)
(advice-add 'transient--make-transient-map :filter-return #'emacsvox-interaction--bindings)
(define-key transient-predicate-map [emacsvox-interaction--decrease] #'transient--do-stay)
(define-key transient-predicate-map [emacsvox-interaction--increase] #'transient--do-stay)

;;;###autoload
(transient-define-prefix emacsvox-interaction (&optional global)
  "Adjust typing, point, message, and phonetic feedback."
  :refresh-suffixes t
  ["Typing and interaction"
   ("g" (lambda () (concat "Scope: " (emacsvox-aural-menu--scope-label))) emacsvox-aural-menu--toggle-scope :transient t)
   ("c" (lambda () (emacsvox-interaction--label 'emacsvox-character-echo "Character echo")) emacsvox-interaction--character :transient t)
   ("w" (lambda () (emacsvox-interaction--label 'emacsvox-word-echo "Word echo")) emacsvox-interaction--word :transient t)
   ("l" (lambda () (emacsvox-interaction--label 'emacsvox-line-echo "Line echo")) emacsvox-interaction--line :transient t)
   ("i" (lambda () (emacsvox-interaction--label 'emacsvox-show-point "Point indication")) emacsvox-interaction--point :transient t)
   ("p" (lambda () (format "Point presentation: %s" (emacsvox-interaction--value 'emacsvox-show-point-presentation))) emacsvox-interaction--presentation :transient t)
   ("m" (lambda () (emacsvox-interaction--label 'emacsvox-speak-messages "Spoken messages")) emacsvox-interaction--messages :transient t)]
  ["Phonetics after character navigation (global)"
   ("f" (lambda () (format "Delayed phonetics: %s" (if emacsvox-delayed-phonetic-mode "on" "off"))) emacsvox-interaction--phonetics :transient t)
   ("d" (lambda () (format "Phonetic delay: %s seconds" emacsvox-delayed-phonetic-delay)) emacsvox-interaction--delay :transient t)]
  ["Preview and finish"
   ("SPC" "Preview source line and point" emacsvox-interaction--preview :transient t)
   ("P" "Speak phonetic name at source" emacsvox-interaction--phonetic-preview :transient t)
   ("s" "Stop preview" emacsvox-interaction--stop :transient t)
   ("S" "Save displayed settings as defaults" emacsvox-interaction--save :transient t)
   ("q" "Back (keep changes)" transient-quit-one)
   ("C-q" "Close all menus" transient-quit-all)]
  (interactive "P")
  (let* ((prefix (or transient--prefix transient-current-prefix))
         (context (if (and prefix (memq (oref prefix command)
                                       '(emacsvox-aural-menu-speech emacsvox-interaction)))
                      (oref prefix scope) (emacsvox-aural-menu--capture global))))
    (emacsvox-aural-menu--source context)
    (transient-setup 'emacsvox-interaction nil nil :scope context)))

(provide 'emacsvox-interaction)
;;; emacsvox-interaction.el ends here
