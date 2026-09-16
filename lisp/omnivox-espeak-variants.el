;;; omnivox-espeak-variants.el --- Bundled eSpeak variant selection -*- lexical-binding: t; -*-

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

;; Discover bundled variants on the selected local speech host, retain explicit
;; combinations, and reuse ordinary exact previews and the palette editor.
;; Discovery is asynchronous and never restarts or speaks through live workers.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'tabulated-list)
(require 'omnivox-engine-settings)
(require 'tts-speak)
(require 'emacsvox-aural-ui)
(declare-function emacsvox-aural-voice-workbench--open-engine "emacsvox-aural-voice-workbench" (id parent))

(defvar-local omnivox-espeak-variants--catalogue nil)
(defvar-local omnivox-espeak-variants--base nil)
(defvar-local omnivox-espeak-variants--parent nil)
(defvar-local omnivox-espeak-variants--process nil)
(defvar-local omnivox-espeak-variants--timer nil)
(defvar-local omnivox-espeak-variants--status "Not discovered")
(defvar-local omnivox-espeak-variants--source nil)
(defvar-local omnivox-espeak-variants--preview-token nil)

(defun omnivox-espeak-variants--source-key ()
  "Identify the next local speech target without inspecting a live process."
  (list (expand-file-name "omnivox" emacsvox-servers-directory)
        (getenv "OMNIVOX_PROGRAM") (getenv "ESPEAK_NG_DATA")
        (getenv "OMNIVOX_ESPEAK_VARIANTS")))

(defun omnivox-espeak-variants--editable ()
  "Reject edits for a changed target, unavailable provider or explicit override."
  (unless (omnivox-engine-settings--supported-p)
    (user-error "Variant settings require the bundled local Omnivox launcher"))
  (unless (string-empty-p (or (getenv "OMNIVOX_ESPEAK_VARIANTS") ""))
    (user-error "OMNIVOX_ESPEAK_VARIANTS overrides this profile; edit it on the speech host"))
  (unless (equal omnivox-espeak-variants--source (omnivox-espeak-variants--source-key))
    (user-error "Speech target changed; refresh variants first")))

(defun omnivox-espeak-variants--entry (variant)
  "Return the desired entry for VARIANT and the selected base."
  (cl-find-if (lambda (entry) (equal (cdr entry) (list omnivox-espeak-variants--base variant)))
              omnivox-espeak-variants))

(defun omnivox-espeak-variants--render ()
  "Update rows without moving focus or losing the selected variant."
  (let ((id (tabulated-list-get-id))
        (variants (copy-tree (plist-get omnivox-espeak-variants--catalogue :variants))))
    (dolist (entry omnivox-espeak-variants)
      (when (and (equal (nth 1 entry) omnivox-espeak-variants--base)
                 (not (cl-find (nth 2 entry) variants :key (lambda (v) (plist-get v :id)) :test #'equal)))
        (push (list :id (nth 2 entry) :display_name (concat (nth 2 entry) " (missing)")) variants)))
    (setq header-line-format
          (format "%s | %s | RET toggle, b base, s save, a restart, p sample, v voices, q back"
                  (or omnivox-espeak-variants--base "eSpeak variants") omnivox-espeak-variants--status))
    (setq tabulated-list-entries
          (mapcar (lambda (v)
                    (let* ((variant (plist-get v :id)) (entry (omnivox-espeak-variants--entry variant)))
                      (list variant (vector (plist-get v :display_name)
                                            (if (car entry) "Enabled at next start" "Disabled") variant))))
                  variants))
    (tabulated-list-print t)
    (when id
      (goto-char (point-min))
      (while (and (not (eobp)) (not (equal id (tabulated-list-get-id)))) (forward-line 1)))))

(defun omnivox-espeak-variants--stop ()
  "Retire only this buffer's private discovery request."
  (when (timerp omnivox-espeak-variants--timer) (cancel-timer omnivox-espeak-variants--timer))
  (when (process-live-p omnivox-espeak-variants--process)
    (set-process-sentinel omnivox-espeak-variants--process #'ignore)
    (delete-process omnivox-espeak-variants--process))
  (setq omnivox-espeak-variants--process nil omnivox-espeak-variants--timer nil))

(defun omnivox-espeak-variants--accept (text)
  "Validate and retain a native catalogue encoded in TEXT."
  (let* ((catalogue (json-parse-string text :object-type 'plist :array-type 'list))
         (bases (plist-get catalogue :bases)) (variants (plist-get catalogue :variants)))
    (unless (and (= (or (plist-get catalogue :schema_version) 0) 1)
                 bases (<= (length bases) 4096) (<= (length variants) 512)
                 (cl-every (lambda (v) (and (stringp (plist-get v :display_name))
                                            (stringp (plist-get (plist-get v :id) :voice_id)))) bases)
                 (cl-every (lambda (v) (and (stringp (plist-get v :id))
                                            (stringp (plist-get v :display_name)))) variants))
      (error "Unsupported eSpeak variant catalogue"))
    (setq omnivox-espeak-variants--catalogue catalogue)
    (unless (cl-find omnivox-espeak-variants--base bases
                     :key (lambda (v) (plist-get (plist-get v :id) :voice_id)) :test #'equal)
      (setq omnivox-espeak-variants--base
            (plist-get (plist-get (or (cl-find "en-us" bases :key (lambda (v) (plist-get v :language)) :test #'equal)
                                     (car bases)) :id) :voice_id)))))

(defun omnivox-espeak-variants-refresh ()
  "Discover bundled variants silently on the selected speech host."
  (interactive)
  (unless (omnivox-engine-settings--supported-p)
    (user-error "Variant discovery requires the bundled local Omnivox launcher"))
  (omnivox-espeak-variants--stop)
  (setq omnivox-espeak-variants--source (omnivox-espeak-variants--source-key)
        omnivox-espeak-variants--catalogue nil omnivox-espeak-variants--status "Discovering")
  (omnivox-espeak-variants--render)
  (let ((buffer (current-buffer)) (output "")
        (source omnivox-espeak-variants--source)
        (process-environment (copy-sequence process-environment)))
    (setenv "EMACSVOX_OMNIVOX_DIAGNOSTIC" "1")
    (condition-case err
        (setq omnivox-espeak-variants--process
              (make-process
               :name "eSpeak variant discovery" :noquery t :connection-type 'pipe :coding 'utf-8-unix
               :command (list (car source) "--list-espeak-variants")
               :stderr (get-buffer-create "*eSpeak variant discovery diagnostics*")
               :filter (lambda (worker text)
                         (setq output (concat output text))
                         (when (> (string-bytes output) (* 1024 1024))
                           (process-put worker 'variant-failure "Variant catalogue exceeds 1 MiB")
                           (delete-process worker)))
               :sentinel
               (lambda (worker _event)
                 (when (and (not (process-live-p worker)) (buffer-live-p buffer))
                   (with-current-buffer buffer
                     (when (eq worker omnivox-espeak-variants--process)
                       (when omnivox-espeak-variants--timer (cancel-timer omnivox-espeak-variants--timer))
                       (setq omnivox-espeak-variants--process nil)
                       (condition-case failure
                           (progn
                             (unless (equal source (omnivox-espeak-variants--source-key)) (error "Speech target changed; refresh again"))
                             (unless (zerop (process-exit-status worker))
                               (error "%s" (or (process-get worker 'variant-failure)
                                                "Discovery failed; this server may not support eSpeak variants")))
                             (omnivox-espeak-variants--accept output)
                             (setq omnivox-espeak-variants--status "Bundled choices; changes need explicit restart"))
                         (error (setq omnivox-espeak-variants--status (error-message-string failure))))
                       (omnivox-espeak-variants--render)))))))
      (error (setq omnivox-espeak-variants--status (error-message-string err))
             (omnivox-espeak-variants--render)))
    (when omnivox-espeak-variants--process
      (let ((worker omnivox-espeak-variants--process))
        (setq omnivox-espeak-variants--timer
              (run-at-time 30 nil (lambda ()
                                    (when (process-live-p worker)
                                      (process-put worker 'variant-failure "Variant discovery timed out")
                                      (delete-process worker)))))))))

(defun omnivox-espeak-variants-base ()
  "Choose the base language or voice without materializing every combination."
  (interactive)
  (let ((candidates (mapcar (lambda (base)
                              (cons (format "%s — %s" (plist-get base :display_name)
                                            (plist-get (plist-get base :id) :voice_id))
                                    (plist-get (plist-get base :id) :voice_id)))
                            (plist-get omnivox-espeak-variants--catalogue :bases))))
    (unless candidates (user-error "Wait for discovery or refresh variants"))
    (setq omnivox-espeak-variants--base (cdr (assoc (completing-read "Base voice: " candidates nil t) candidates)))
    (omnivox-espeak-variants--render)))

(defun omnivox-espeak-variants-toggle ()
  "Toggle the desired combination, retaining saved palette references."
  (interactive)
  (omnivox-espeak-variants--editable)
  (let* ((variant (or (tabulated-list-get-id) (user-error "Choose a variant row")))
         (old (omnivox-espeak-variants--entry variant))
         (entry (list (not (car old)) omnivox-espeak-variants--base variant))
         (choices (append (cl-remove old omnivox-espeak-variants :test #'equal) (list entry))))
    (omnivox-engine-settings--variants-json choices)
    (setq omnivox-espeak-variants choices
          omnivox-espeak-variants--status "Edited; s saves, a restarts both speech lanes")
    (omnivox-espeak-variants--render)
    (emacsvox-aural-ui-announce-result "%s for next speech start" (if (car entry) "Enabled" "Disabled"))))

(defun omnivox-espeak-variants-save ()
  "Save desired combinations in this Emacs profile without restarting speech."
  (interactive)
  (omnivox-espeak-variants--editable)
  (omnivox-engine-settings--variants-json omnivox-espeak-variants)
  (customize-save-variable 'omnivox-espeak-variants omnivox-espeak-variants)
  (setq omnivox-espeak-variants--status "Saved; restart speech to apply")
  (omnivox-espeak-variants--render)
  (emacsvox-aural-ui-announce-result "Variant choices saved. Restart speech to apply."))

(defun omnivox-espeak-variants-apply ()
  "Restart this session's speech lanes with the current desired choices."
  (interactive)
  (omnivox-espeak-variants--editable)
  (omnivox-engine-settings--variants-json omnivox-espeak-variants)
  (tts-restart)
  (setq omnivox-espeak-variants--status "Restart requested; browse voices to check live availability")
  (omnivox-espeak-variants--render))

(defun omnivox-espeak-variants-preview ()
  "Audition the exact selected combination through the live main lane."
  (interactive)
  (let ((variant (or (tabulated-list-get-id) (user-error "Choose a variant row")))
        (buffer (current-buffer)) (token (list t)))
    (unless (car (omnivox-espeak-variants--entry variant)) (user-error "Enable this combination and restart speech first"))
    (setq omnivox-espeak-variants--preview-token token)
    (tts-preview-voices
     (list (list :text "This is the selected eSpeak voice variant."
                 :selector (list :kind 'exact :engine-id "espeak"
                                 :voice-id (concat omnivox-espeak-variants--base "+" variant) :scope 'session)
                 :acss nil :effects nil))
     (lambda (result)
       (when (buffer-live-p buffer)
         (with-current-buffer buffer
           (when (eq token omnivox-espeak-variants--preview-token)
             (setq omnivox-espeak-variants--status
                   (format "Exact sample: %s. Newly enabled choices need restart." (plist-get result :status)))
             (omnivox-espeak-variants--render)
             (emacsvox-aural-ui-announce-result "%s" omnivox-espeak-variants--status))))))))

(defun omnivox-espeak-variants-voices ()
  "Browse live eSpeak voices and use the existing palette editor."
  (interactive)
  (require 'emacsvox-aural-voice-workbench)
  (emacsvox-aural-voice-workbench--open-engine "espeak" (current-buffer)))

(defun omnivox-espeak-variants-back ()
  "Return to engine details without discarding desired settings."
  (interactive)
  (omnivox-espeak-variants--stop)
  (if (buffer-live-p omnivox-espeak-variants--parent)
      (pop-to-buffer omnivox-espeak-variants--parent)
    (quit-window)))

(defvar omnivox-espeak-variants-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map tabulated-list-mode-map)
    (dolist (binding '(("RET" . omnivox-espeak-variants-toggle)
                       ("b" . omnivox-espeak-variants-base) ("s" . omnivox-espeak-variants-save)
                       ("a" . omnivox-espeak-variants-apply) ("p" . omnivox-espeak-variants-preview)
                       ("v" . omnivox-espeak-variants-voices) ("g" . omnivox-espeak-variants-refresh)
                       ("q" . omnivox-espeak-variants-back)))
      (define-key map (kbd (car binding)) (cdr binding)))
    map))

(define-derived-mode omnivox-espeak-variants-mode tabulated-list-mode "eSpeak variants"
  "Select bundled variants one base voice at a time.
RET toggles desired availability; s saves; a restarts both speech lanes.
Use p for exact samples after restart and v to save a voice in a palette."
  (setq tabulated-list-format [("Variant" 28 t) ("Desired availability" 23 t) ("ID" 20 t)])
  (tabulated-list-init-header)
  (add-hook 'kill-buffer-hook #'omnivox-espeak-variants--stop nil t))

;;;###autoload
(defun omnivox-espeak-variants ()
  "Browse bundled eSpeak variants on the selected local speech host."
  (interactive)
  (let ((parent (current-buffer)) (buffer (get-buffer-create "*eSpeak Variants*")))
    (with-current-buffer buffer
      (unless (derived-mode-p 'omnivox-espeak-variants-mode) (omnivox-espeak-variants-mode))
      (unless (eq parent buffer) (setq omnivox-espeak-variants--parent parent)))
    (pop-to-buffer buffer)
    (omnivox-espeak-variants-refresh)))

(provide 'omnivox-espeak-variants)
;;; omnivox-espeak-variants.el ends here
