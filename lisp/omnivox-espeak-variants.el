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

;; Browse the running speech worker's bundled variants and resolve combinations
;; on demand for exact preview and palette editing.  No enablement or restart.

;;; Code:

(require 'cl-lib)
(require 'tabulated-list)
(require 'tts-speak)
(require 'emacsvox-aural-ui)
(declare-function emacsvox-aural-voice-editor-experiment "emacsvox-aural-voice-editor" (pair source text))
(declare-function emacsvox-aural-voice-editor-keep-experiment "emacsvox-aural-voice-editor" (&optional part placement source))
(declare-function emacsvox-aural-voice-workbench--open-engine "emacsvox-aural-voice-workbench" (id parent))

(defvar-local omnivox-espeak-variants--base nil)
(defvar-local omnivox-espeak-variants--parent nil)
(defvar-local omnivox-espeak-variants--status nil)
(defvar-local omnivox-espeak-variants--preview-token nil)

(defun omnivox-espeak-variants--engine (&optional inventory)
  "Return eSpeak from the live speech INVENTORY."
  (cl-find "espeak" (plist-get (or inventory (tts-voice-inventory)) :engines)
           :key (lambda (engine) (plist-get engine :engine-id)) :test #'equal))

(defun omnivox-espeak-variants--bases (engine)
  "Return base voices from ENGINE without expanding variant combinations."
  (cl-remove-if (lambda (voice) (string-match-p "[+]" (plist-get voice :voice-id)))
                (plist-get engine :voices)))

(defun omnivox-espeak-variants--selector (variant)
  "Return the exact local selector for VARIANT and the chosen base."
  (list :kind 'exact :engine-id "espeak"
        :voice-id (concat omnivox-espeak-variants--base "+" variant) :scope 'local))

(defun omnivox-espeak-variants--preview-state (variant inventory)
  "Describe whether VARIANT can be auditioned through live INVENTORY."
  (cond
   ((or (plist-get inventory :stale)
        (not (equal (plist-get inventory :status) "available"))) "Waiting for speech")
   ((not (plist-get (omnivox-espeak-variants--engine inventory) :espeak-variants))
    "Update Omnivox for variants")
   (t (condition-case nil
          (progn (tts--resolve-voice-preview-selector
                  (omnivox-espeak-variants--selector variant) inventory)
                 "Ready")
        (error "Unavailable")))))

(defun omnivox-espeak-variants--render ()
  "Refresh variants without moving focus or losing the selected row."
  (let* ((inventory (tts-voice-inventory))
         (engine (omnivox-espeak-variants--engine inventory))
         (bases (omnivox-espeak-variants--bases engine))
         (variants (plist-get engine :espeak-variants)))
    (unless (cl-find omnivox-espeak-variants--base bases
                     :key (lambda (voice) (plist-get voice :voice-id)) :test #'equal)
      (setq omnivox-espeak-variants--base
            (plist-get (or (cl-find "en-us" bases :key (lambda (voice) (plist-get voice :language)) :test #'equal)
                           (car bases)) :voice-id)))
    (setq header-line-format
          (format "%s | %s | p preview, u use in palette, b base, v voices, g refresh, q back"
                  (or omnivox-espeak-variants--base "eSpeak variants")
                  (or omnivox-espeak-variants--status
                      (if variants "Bundled variants; no restart needed"
                        "Waiting for live variant support; update Omnivox if needed"))))
    (emacsvox-aural-ui-refresh-tabulated
     (lambda ()
       (setq tabulated-list-entries
             (mapcar (lambda (variant)
                       (let ((id (plist-get variant :id)))
                         (list id (vector (plist-get variant :display-name)
                                          (omnivox-espeak-variants--preview-state id inventory)
                                          id))))
                     variants))))))

(defun omnivox-espeak-variants--speak-row ()
  "Speak the variant name and preview availability."
  (let ((row (or (tabulated-list-get-entry) (user-error "No variants reported; press g to refresh"))))
    (emacsvox-aural-ui-speak (format "%s, %s." (aref row 0) (aref row 1)))))

(defun omnivox-espeak-variants--inventory-changed ()
  "Refresh open variant browsers silently after live inventory changes."
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (derived-mode-p 'omnivox-espeak-variants-mode)
        (omnivox-espeak-variants--render)))))
(add-hook 'tts-voice-inventory-changed-hook #'omnivox-espeak-variants--inventory-changed)

(defun omnivox-espeak-variants-refresh ()
  "Refresh variants from the running speech worker without restarting it."
  (interactive)
  (setq omnivox-espeak-variants--status nil)
  (tts-refresh-voice-inventory)
  (omnivox-espeak-variants--render))

(defun omnivox-espeak-variants-base ()
  "Choose a base voice for immediate variant previews."
  (interactive)
  (let ((candidates (mapcar (lambda (voice)
                              (cons (format "%s — %s" (plist-get voice :display-name)
                                            (plist-get voice :voice-id))
                                    (plist-get voice :voice-id)))
                            (omnivox-espeak-variants--bases (omnivox-espeak-variants--engine)))))
    (unless candidates (user-error "Wait for speech inventory or press g to refresh"))
    (setq omnivox-espeak-variants--base
          (cdr (assoc (completing-read "Base voice: " candidates nil t) candidates))
          omnivox-espeak-variants--status nil
          omnivox-espeak-variants--preview-token nil)
    (omnivox-espeak-variants--render)))

(defun omnivox-espeak-variants--pair ()
  "Return the selected live engine/variant pair, or explain why it is unavailable."
  (let* ((variant (or (tabulated-list-get-id) (user-error "Choose a variant row")))
         (inventory (tts-voice-inventory))
         (state (omnivox-espeak-variants--preview-state variant inventory)))
    (unless (equal state "Ready") (user-error "%s; press g to refresh" state))
    (list (omnivox-espeak-variants--engine inventory)
          (plist-get (tts--resolve-voice-preview-selector
                      (omnivox-espeak-variants--selector variant) inventory) :voice))))

(defun omnivox-espeak-variants-preview ()
  "Audition the selected variant without saving settings or restarting speech."
  (interactive)
  (let* ((pair (omnivox-espeak-variants--pair))
         (voice (cadr pair))
         (name (plist-get voice :display-name))
         (buffer (current-buffer)) (token (list t)))
    (setq omnivox-espeak-variants--preview-token token)
    (tts-preview-voices
     (list (list :text "This is the selected eSpeak voice variant."
                 :selector (list :kind 'exact :engine-id "espeak"
                                 :voice-id (plist-get voice :voice-id) :scope 'session)
                 :acss nil :effects nil))
     (lambda (result)
       (when (buffer-live-p buffer)
         (with-current-buffer buffer
           (when (eq token omnivox-espeak-variants--preview-token)
             (setq omnivox-espeak-variants--status
                   (format "%s sample: %s" name (plist-get result :status)))
             (omnivox-espeak-variants--render)
             (when (eq (plist-get result :status) 'failed)
               (emacsvox-aural-ui-announce-result "%s" omnivox-espeak-variants--status)))))))))

(defun omnivox-espeak-variants-use ()
  "Choose a palette destination for this variant, retaining existing fallbacks.
The destination editor previews its tuning and offers Save and apply or
Save to collection.  Opening it changes no saved data or startup settings."
  (interactive)
  (let ((pair (omnivox-espeak-variants--pair)) (source (current-buffer)))
    (require 'emacsvox-aural-voice-editor)
    (emacsvox-aural-voice-editor-experiment
     pair source "This is the selected eSpeak voice variant.")
    (emacsvox-aural-voice-editor-keep-experiment 'physical 'preferred source)))

(defun omnivox-espeak-variants-voices ()
  "Browse eSpeak base voices."
  (interactive)
  (require 'emacsvox-aural-voice-workbench)
  (emacsvox-aural-voice-workbench--open-engine "espeak" (current-buffer)))

(defun omnivox-espeak-variants-back ()
  "Return to the parent view with its selection preserved."
  (interactive)
  (setq omnivox-espeak-variants--preview-token nil)
  (if (buffer-live-p omnivox-espeak-variants--parent)
      (pop-to-buffer omnivox-espeak-variants--parent)
    (quit-window)))

(defvar omnivox-espeak-variants-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map emacsvox-aural-tabulated-mode-map)
    (dolist (binding '(("RET" . omnivox-espeak-variants-preview)
                       ("p" . omnivox-espeak-variants-preview)
                       ("u" . omnivox-espeak-variants-use)
                       ("b" . omnivox-espeak-variants-base)
                       ("v" . omnivox-espeak-variants-voices)
                       ("g" . omnivox-espeak-variants-refresh)
                       ("q" . omnivox-espeak-variants-back)))
      (define-key map (kbd (car binding)) (cdr binding)))
    map))

(define-derived-mode omnivox-espeak-variants-mode emacsvox-aural-tabulated-mode "eSpeak variants"
  "Preview bundled variants with p or RET; use u to choose a palette destination.
Choose a base with b.  No variant enablement, setting save or restart is needed."
  (emacsvox-aural-ui-configure-tabulated "eSpeak variants"
                                        #'omnivox-espeak-variants--speak-row
                                        #'omnivox-espeak-variants-refresh
                                        #'omnivox-espeak-variants--speak-row)
  (setq-local emacsvox-aural-ui-extra-actions
              '(("Preview variant" . omnivox-espeak-variants-preview)
                ("Use in palette" . omnivox-espeak-variants-use)
                ("Choose base voice" . omnivox-espeak-variants-base)))
  (setq tabulated-list-format [("Variant" 28 t) ("Preview" 23 t) ("ID" 20 t)])
  (tabulated-list-init-header))

;;;###autoload
(defun omnivox-espeak-variants ()
  "Preview bundled eSpeak variants and use them directly in a palette."
  (interactive)
  (let ((parent (current-buffer)) (buffer (get-buffer-create "*eSpeak Variants*")))
    (with-current-buffer buffer
      (unless (derived-mode-p 'omnivox-espeak-variants-mode) (omnivox-espeak-variants-mode))
      (unless (eq parent buffer) (setq omnivox-espeak-variants--parent parent))
      (omnivox-espeak-variants--render))
    (pop-to-buffer buffer)
    (omnivox-espeak-variants-refresh)))

(provide 'omnivox-espeak-variants)
;;; omnivox-espeak-variants.el ends here
