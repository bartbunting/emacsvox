;;; omnivox-punctuation.el --- Review and edit host punctuation -*- lexical-binding: t; -*-

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

;; Omnivox supplies defaults and validates edits on the selected local speech
;; host.  This interface edits a draft of saved overrides; it neither owns
;; pronunciation tables nor changes active speech as a side effect of saving.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'subr-x)
(require 'emacsvox-aural-ui)
(require 'omnivox-library)
(declare-function tts-restart "tts" ())
(declare-function emacsvox-speak-help "emacsvox-speak" ())

(defconst omnivox-punctuation--levels '("none" "some" "all"))
(defvar-local omnivox-punctuation--review nil)
(defvar-local omnivox-punctuation--defaults nil)
(defvar-local omnivox-punctuation--draft nil)
(defvar-local omnivox-punctuation--saved nil)
(defvar-local omnivox-punctuation--level "some")
(defvar-local omnivox-punctuation--status "Saved settings; active speech may differ")
(defvar-local omnivox-punctuation--parent nil)

(defun omnivox-punctuation--request (command)
  "Send punctuation COMMAND to the selected local speech host."
  (let ((service (omnivox-library--service)))
    (unwind-protect
        (progn
          (unless (eql 1 (plist-get (omnivox-library--request service '(:command "host"))
                                   :punctuation_configuration_version))
            (user-error "Update the local Omnivox speech host to use the punctuation editor"))
          (let ((reply (omnivox-library--request service command)))
            (unless (equal (plist-get reply :type) "punctuation_configuration")
              (error "Unexpected punctuation configuration response"))
            (plist-get reply :review)))
      (when (process-live-p service) (delete-process service)))))

(defun omnivox-punctuation--tables (data)
  "Decode the three punctuation tables in host plist DATA."
  (mapcar
   (lambda (level)
     (let ((table (make-hash-table :test #'equal))
           (entries (plist-get data (intern (concat ":" level)))))
       (while entries
         (let ((key (substring (symbol-name (pop entries)) 1))
               (value (pop entries)))
           (unless (and (= (length key) 1) (or (stringp value) (eq value :null)))
             (error "Invalid host punctuation entry"))
           (puthash key value table)))
       (cons level table)))
   omnivox-punctuation--levels))

(defun omnivox-punctuation--accept (review)
  "Replace this buffer's saved baseline and draft with host REVIEW."
  (unless (and (stringp (plist-get review :path))
               (string-match-p "\\`[a-f0-9]\\{64\\}\\'" (or (plist-get review :sha256) "")))
    (error "Missing punctuation file identity"))
  (let ((defaults (omnivox-punctuation--tables (plist-get review :defaults)))
        (draft (omnivox-punctuation--tables (plist-get review :overrides))))
    (setq omnivox-punctuation--review review
          omnivox-punctuation--defaults defaults
          omnivox-punctuation--draft draft
          omnivox-punctuation--saved
          (mapcar (lambda (entry) (cons (car entry) (copy-hash-table (cdr entry)))) draft))))

(defun omnivox-punctuation--dirty-p ()
  "Whether the draft differs from the last successful read or save."
  (not
   (cl-every
    (lambda (entry)
      (let ((table (cdr entry))
            (saved (cdr (assoc (car entry) omnivox-punctuation--saved))))
        (and saved (= (hash-table-count table) (hash-table-count saved))
             (cl-loop for key being the hash-keys of table using (hash-values value)
                      always (equal value (gethash key saved :absent))))))
    omnivox-punctuation--draft)))

(defun omnivox-punctuation--table (tables)
  "Return the selected level in TABLES."
  (cdr (assoc omnivox-punctuation--level tables)))

(defun omnivox-punctuation--value (character)
  "Return CHARACTER's effective value in the selected draft level."
  (let ((override (gethash character (omnivox-punctuation--table omnivox-punctuation--draft) :absent)))
    (if (eq override :absent)
        (gethash character (omnivox-punctuation--table omnivox-punctuation--defaults) :null)
      override)))

(defun omnivox-punctuation--description (value)
  "Describe VALUE without calling preservation silence."
  (if (eq value :null) "Preserve character" (concat "Speak: " value)))

(defun omnivox-punctuation--character-name (character)
  "Return an explicit Unicode name for CHARACTER."
  (format "U+%04X %s" (string-to-char character)
          (or (get-char-code-property (string-to-char character) 'name) "Unnamed character")))

(defun omnivox-punctuation--render (&optional selected)
  "Refresh the draft view, retaining SELECTED character and column."
  (let ((keys (make-hash-table :test #'equal))
        (table (omnivox-punctuation--table omnivox-punctuation--draft))
        (saved (omnivox-punctuation--table omnivox-punctuation--saved)))
    (dolist (tables (list omnivox-punctuation--defaults omnivox-punctuation--draft
                         omnivox-punctuation--saved))
      (dolist (entry tables)
        (maphash (lambda (key _value) (puthash key t keys)) (cdr entry))))
    (setq header-line-format
          (format " %s | %s | RET edit, l level, a add, d default, s save, r restart, ? help"
                  omnivox-punctuation--level
                  (if (omnivox-punctuation--dirty-p) "Unsaved edits" omnivox-punctuation--status)))
    (emacsvox-aural-ui-refresh-tabulated
     (lambda ()
       (setq tabulated-list-entries
             (mapcar
              (lambda (key)
                (let ((override (gethash key table :absent)))
                  (list key
                        (vector (omnivox-punctuation--character-name key)
                                (omnivox-punctuation--description (omnivox-punctuation--value key))
                                (concat
                                 (if (eq override :absent) "Default" "Override")
                                 (unless (equal override (gethash key saved :absent)) "; unsaved"))))))
              (sort (hash-table-keys keys) #'string<))))
     selected)))

(defun omnivox-punctuation-speak-row ()
  "Speak the current character's name, level, pronunciation and source."
  (interactive)
  (let ((row (or (tabulated-list-get-entry) (user-error "Choose a character first"))))
    (emacsvox-aural-ui-speak
     (format "%s. %s level. %s. %s."
             (aref row 0) omnivox-punctuation--level (aref row 1) (aref row 2)))))

(defun omnivox-punctuation--change (character action &optional name)
  "Set CHARACTER to ACTION, using NAME for speak; retain other levels."
  (let ((code (and (= (length character) 1) (string-to-char character))))
    (unless (and code (<= code #x10ffff) (not (<= #xd800 code #xdfff))
                 (not (memq (get-char-code-property code 'general-category) '(Cc Zs Zl Zp))))
      (user-error "Enter one Unicode character, excluding whitespace and controls")))
  (when (equal action "Speak a name")
    (unless (and (stringp name) (<= 1 (string-bytes name) 64)
                 (equal name (string-trim name))
                 (not (string-match-p "[[:cntrl:]]" name)))
      (user-error "Use a spoken name of 1 to 64 UTF-8 bytes without controls or edge spaces")))
  (let ((table (omnivox-punctuation--table omnivox-punctuation--draft)))
    (pcase action
      ("Speak a name" (puthash character name table))
      ("Preserve character" (puthash character :null table))
      ("Restore default" (remhash character table))
      (_ (user-error "Unknown punctuation action"))))
  (omnivox-punctuation--render character)
  (emacsvox-aural-ui-speak
   (format "%s. %s level. %s. %s."
           (omnivox-punctuation--character-name character) omnivox-punctuation--level
           (omnivox-punctuation--description (omnivox-punctuation--value character)) action)))

(defun omnivox-punctuation-edit (&optional character)
  "Edit CHARACTER, or the selected character, in the current level."
  (interactive)
  (let* ((character (or character (tabulated-list-get-id) (user-error "Choose a character first")))
         (action (completing-read
                  (format "%s, %s: " (omnivox-punctuation--character-name character) omnivox-punctuation--level)
                  '("Speak a name" "Preserve character" "Restore default") nil t))
         (name (when (equal action "Speak a name")
                 (read-string "Spoken name: " (let ((value (omnivox-punctuation--value character)))
                                               (and (stringp value) value))))))
    (omnivox-punctuation--change character action name)))

(defun omnivox-punctuation-add ()
  "Add or edit a Unicode character in the current level."
  (interactive)
  (let ((character (read-string "Character to add: ")))
    (unless (= (length character) 1) (user-error "Enter exactly one character"))
    (omnivox-punctuation-edit character)))

(defun omnivox-punctuation-default ()
  "Restore the current character's shipped default in this level."
  (interactive)
  (omnivox-punctuation--change
   (or (tabulated-list-get-id) (user-error "Choose a character first")) "Restore default"))

(defun omnivox-punctuation-level (level)
  "Review and edit punctuation LEVEL without discarding drafts."
  (interactive (list (completing-read "Punctuation level: " omnivox-punctuation--levels nil t)))
  (unless (member level omnivox-punctuation--levels) (user-error "Unknown punctuation level"))
  (setq omnivox-punctuation--level level)
  (omnivox-punctuation--render)
  (omnivox-punctuation-speak-row))

(defun omnivox-punctuation-save ()
  "Save all draft levels on the speech host, without restarting speech."
  (interactive)
  (unless (omnivox-punctuation--dirty-p) (user-error "No punctuation changes to save"))
  (let ((tables (make-hash-table :test #'equal)))
    (dolist (entry omnivox-punctuation--draft) (puthash (car entry) (cdr entry) tables))
    ;; Errors deliberately leave the draft and original revision intact.
    (omnivox-punctuation--accept
     (omnivox-punctuation--request
      (list :command "punctuation-save"
            :expected_sha256 (plist-get omnivox-punctuation--review :sha256)
            :punctuation_json (decode-coding-string
                               (json-serialize tables :null-object :null) 'utf-8 t)))))
  (setq omnivox-punctuation--status "Saved; restart speech to apply")
  (omnivox-punctuation--render)
  (emacsvox-aural-ui-speak omnivox-punctuation--status))

(defun omnivox-punctuation-refresh ()
  "Read saved settings again, asking before discarding draft edits."
  (interactive)
  (when (or (not (omnivox-punctuation--dirty-p))
            (yes-or-no-p "Discard unsaved punctuation edits and read the saved file? "))
    (omnivox-punctuation--accept
     (omnivox-punctuation--request '(:command "punctuation-review")))
    (setq omnivox-punctuation--status "Saved settings; active speech may differ")
    (omnivox-punctuation--render)
    (omnivox-punctuation-speak-row)))

(defun omnivox-punctuation-restart ()
  "Explicitly restart this session's speech workers with saved settings."
  (interactive)
  (when (omnivox-punctuation--dirty-p) (user-error "Save or discard punctuation edits before restarting"))
  ;; Reject a changed target/file before interrupting working speech.
  (let ((current (omnivox-punctuation--request '(:command "punctuation-review"))))
    (unless (equal (plist-get current :sha256) (plist-get omnivox-punctuation--review :sha256))
      (user-error "Saved settings or speech host changed; refresh before restarting")))
  (when (yes-or-no-p "Restart this session's main and notification speech with saved settings? ")
    (tts-restart)
    (setq omnivox-punctuation--status "Restart requested; refresh speech status to verify")
    (omnivox-punctuation--render)
    (emacsvox-aural-ui-speak omnivox-punctuation--status)))

(defun omnivox-punctuation--kill-query ()
  "Protect unsaved edits when this buffer is killed."
  (or (not (omnivox-punctuation--dirty-p))
      (yes-or-no-p "Discard unsaved punctuation edits? ")))

(defun omnivox-punctuation-quit ()
  "Return to the originating view; retain this buffer and its draft."
  (interactive)
  (let ((parent omnivox-punctuation--parent))
    (quit-window)
    (when (buffer-live-p parent) (pop-to-buffer parent))))

(defun omnivox-punctuation-help ()
  "Explain punctuation editing and its save/restart boundary."
  (interactive)
  (let ((path (plist-get omnivox-punctuation--review :path)))
   (emacsvox-aural-ui-with-help-window
    (princ (format "Punctuation on the speech host\n\nFile: %s\n\n"
                   path))
    (princ "This view shows saved settings and your draft, not verified live settings.\n\n")
    (princ "l chooses none, some or all. Up/down reads rows; left/right reads columns.\n")
    (princ "RET edits: speak a name, preserve the character, or restore its default.\n")
    (princ "a adds a character; d restores the selected default in this level.\n")
    (princ "s saves all edited levels. Saving never restarts speech.\n")
    (princ "r explicitly restarts both speech workers after confirmation.\n")
    (princ "g refreshes from the file and asks before discarding edits.\n")
    (princ "q returns to the previous view and retains your unfinished draft.\n\n")
    (princ "Preserve leaves the character for the engine's pronunciation and pauses.\n")
    (princ "Org normally selects some. Configure both straight and curly apostrophes\n")
    (princ "there to name them in prose. Each level is independent.\n")))
  (when (fboundp 'emacsvox-speak-help) (emacsvox-speak-help)))

(define-derived-mode omnivox-punctuation-mode emacsvox-aural-tabulated-mode "Punctuation"
  "Review saved host punctuation and edit a separate draft."
  (emacsvox-aural-ui-configure-tabulated
   "Punctuation characters" #'omnivox-punctuation-speak-row #'omnivox-punctuation-refresh)
  (setq tabulated-list-format [("Character" 48 t) ("Pronunciation" 32 t) ("Source" 18 t)]
        tabulated-list-padding 2)
  (add-hook 'kill-buffer-query-functions #'omnivox-punctuation--kill-query nil t)
  (tabulated-list-init-header))

(dolist (binding '(("RET" . omnivox-punctuation-edit) ("e" . omnivox-punctuation-edit)
                   ("a" . omnivox-punctuation-add) ("d" . omnivox-punctuation-default)
                   ("l" . omnivox-punctuation-level) ("s" . omnivox-punctuation-save)
                   ("r" . omnivox-punctuation-restart) ("g" . omnivox-punctuation-refresh)
                   ("q" . omnivox-punctuation-quit) ("?" . omnivox-punctuation-help)))
  (define-key omnivox-punctuation-mode-map (kbd (car binding)) (cdr binding)))

;;;###autoload
(defun omnivox-punctuation ()
  "Review and edit punctuation on the selected local Omnivox speech host.
The host supplies defaults and validates saved overrides.  Saving does not
restart speech.  Reopening retains any unfinished draft in this buffer."
  (interactive)
  (let ((parent (current-buffer))
        (existing (get-buffer "*Omnivox Punctuation*")))
    (if (and existing (buffer-local-value 'omnivox-punctuation--review existing))
        (emacsvox-aural-ui-pop-to-buffer existing)
      (let ((review (omnivox-punctuation--request '(:command "punctuation-review")))
            (buffer (get-buffer-create "*Omnivox Punctuation*")))
        (with-current-buffer buffer
          (omnivox-punctuation-mode)
          (setq omnivox-punctuation--parent parent)
          (omnivox-punctuation--accept review)
          (omnivox-punctuation--render "’"))
        (emacsvox-aural-ui-pop-to-buffer buffer)))))

(provide 'omnivox-punctuation)
;;; omnivox-punctuation.el ends here
