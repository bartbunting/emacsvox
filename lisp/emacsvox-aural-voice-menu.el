;;; emacsvox-aural-voice-menu.el --- Focused named voice tuning -*- lexical-binding: t; -*-

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
;; A focused view of the common editor's authoritative named-voice draft.
;; Preview and saving use the editor's existing ownership and recovery paths.

;;; Code:

(require 'emacsvox-aural-menu)
(require 'emacsvox-aural-voice-editor)

(defconst emacsvox-aural-voice-menu--controls
  '((emacsvox-aural-voice-menu--rate . rate-offset)
    (emacsvox-aural-voice-menu--pitch . average-pitch)
    (emacsvox-aural-voice-menu--range . pitch-range)
    (emacsvox-aural-voice-menu--gain . gain))
  "Numeric commands and their draft dimensions.")

(defun emacsvox-aural-voice-menu--call (function &optional inspect)
  "Call FUNCTION in the captured editor, retaining its field and menu focus.
With INSPECT, only read editor state; do not disturb menu rendering."
  (let* ((prefix (or transient--prefix transient-current-prefix))
         (scope (and prefix (eq (oref prefix command) 'emacsvox-aural-voice-menu)
                     (oref prefix scope)))
         (buffer (car scope))
         (context (nth 1 scope))
         (choice (nth 2 scope))
         (focus (when (and (not inspect) (window-live-p transient--window))
                  (with-selected-window transient--window
                    (when-let* ((button (button-at (point))))
                      (button-get button 'button-data))))))
    (unless (buffer-live-p buffer) (user-error "The voice editor has closed"))
    (with-current-buffer buffer
      (unless (and (eq context emacsvox-aural-voice-editor--context)
                   (emacsvox-aural-voice-editor--get :voice)
                   (equal choice (emacsvox-aural-voice-editor--get :tuning-choice))
                   (or (null choice) (emacsvox-aural-voice-editor--tuning-row))
                   (not (emacsvox-aural-voice-editor--get :engine-controls)))
        (user-error "Voice editing scope changed; reopen the tuning menu"))
      (let ((field (get-text-property (point) 'voice-field)))
        (unwind-protect (funcall function)
          (unless inspect (emacsvox-aural-voice-editor--locate field))
          ;; A minibuffer prompt may have destroyed the popup.
          (when (and focus (eq transient--prefix prefix)
                     (not (window-live-p transient--window)))
            (transient--show)
            (with-selected-window transient--window
              (transient--goto-button focus))))))))

(defun emacsvox-aural-voice-menu--label (dimension)
  "Describe DIMENSION in the selected scope, with changes and support."
  (emacsvox-aural-voice-menu--call
   (lambda ()
     (let ((snapshot (emacsvox-aural-voice-editor--working)))
       (emacsvox-aural-voice-editor--adjustment-text
        dimension (emacsvox-aural-voice-editor--tuning-style
                   snapshot (emacsvox-aural-voice-editor--get :palette))
        (if (emacsvox-aural-voice-editor--get :tuning-choice)
            (list (plist-get (emacsvox-aural-voice-editor--tuning-row) :selector))
          (plist-get snapshot :selectors))))) t))

(defun emacsvox-aural-voice-menu--title ()
  "Name the draft, owning palette, scope, and save state."
  (emacsvox-aural-voice-menu--call
   (lambda ()
     (format "%s in %s: %s; %s"
             (emacsvox-aural-voice-editor--get :voice)
             (emacsvox-aural-voice-editor--get :palette)
             (if-let* ((row (emacsvox-aural-voice-editor--tuning-row)))
                 (format "choice %s, %s"
                         (1+ (cl-position (plist-get row :id)
                                          (emacsvox-aural-voice-editing--rows
                                           (emacsvox-aural-voice-editor--working))
                                          :key (lambda (item) (plist-get item :id))
                                          :test #'equal))
                         (emacsvox-aural-voice-workbench--selector-description (plist-get row :selector)))
               "shared tuning")
             (plist-get (emacsvox-aural-voice-drafts--status
                         (emacsvox-aural-voice-editor--draft)) :label))) t))

(defun emacsvox-aural-voice-menu--edit (dimension &optional delta reset)
  "Edit DIMENSION, step by DELTA, or RESET it to the adapter default."
  (emacsvox-aural-voice-menu--call
   (lambda ()
     (let ((automatic (emacsvox-aural-voice-editor--get :automatic-sample)) bound)
       (emacsvox-aural-voice-editor-stop)
       (unwind-protect
           (progn
             (emacsvox-aural-voice-editor--put :automatic-sample nil)
             ;; The menu owns concise adjustment feedback; previews are explicit.
             (cl-letf (((symbol-function 'emacsvox-aural-voice-editor-speak) #'ignore))
               (cond
                (reset (emacsvox-aural-voice-editor--set dimension nil))
                (delta
                 (let* ((style (emacsvox-aural-voice-editor--tuning-style
                                (emacsvox-aural-voice-editor--working)
                                (emacsvox-aural-voice-editor--get :palette)))
                        (value (plist-get style (emacsvox-aural--voice-dimension-key dimension)))
                        (metadata (emacsvox-aural--voice-style-field dimension))
                        (current (emacsvox-aural-voice-tuner--control-value dimension value))
                        (next (max (plist-get metadata :minimum)
                                   (min (plist-get metadata :maximum)
                                        (+ delta (or current (if (eq dimension 'gain) 5 0)))))))
                   (if (equal current next)
                       (setq bound (if (> delta 0) "Maximum. " "Minimum. "))
                     (emacsvox-aural-voice-editor--set dimension next))))
                (t (emacsvox-aural-voice-editor-edit dimension)))))
         (emacsvox-aural-voice-editor--put :automatic-sample automatic))
       (let* ((style (emacsvox-aural-voice-editor--tuning-style
                      (emacsvox-aural-voice-editor--working)
                      (emacsvox-aural-voice-editor--get :palette)))
              (value (plist-get style (emacsvox-aural--voice-dimension-key dimension))))
         (emacsvox-transient--submit-text
          (concat bound (emacsvox-aural-voice-tuner--value-description dimension value))
          (emacsvox-transient--item-facts 'value dimension 'command-menu-value-changed '(selected))
          'state-change 'select-object))))))

(defun emacsvox-aural-voice-menu--rate ()
  "Edit the selected scope's relative rate." (interactive)
  (emacsvox-aural-voice-menu--edit 'rate-offset))
(defun emacsvox-aural-voice-menu--pitch ()
  "Edit the selected scope's pitch." (interactive)
  (emacsvox-aural-voice-menu--edit 'average-pitch))
(defun emacsvox-aural-voice-menu--range ()
  "Edit the selected scope's pitch range." (interactive)
  (emacsvox-aural-voice-menu--edit 'pitch-range))
(defun emacsvox-aural-voice-menu--gain ()
  "Edit the selected scope's output gain." (interactive)
  (emacsvox-aural-voice-menu--edit 'gain))

(defun emacsvox-aural-voice-menu--selected-dimension (&optional noerror)
  "Return the focused numeric control's dimension, or nil with NOERROR."
  (let ((object (with-selected-window (emacsvox-transient--navigation-window)
                  (when-let* ((button (button-at (point))))
                    (button-get button 'button-data)))))
    (or (and (eieio-object-p object)
             (alist-get (oref object command) emacsvox-aural-voice-menu--controls))
        (unless noerror (user-error "Choose a numeric adjustment first")))))

(defun emacsvox-aural-voice-menu--decrease ()
  "Decrease the selected shared adjustment." (interactive)
  (emacsvox-aural-voice-menu--edit (emacsvox-aural-voice-menu--selected-dimension) -1))
(defun emacsvox-aural-voice-menu--increase ()
  "Increase the selected shared adjustment." (interactive)
  (emacsvox-aural-voice-menu--edit (emacsvox-aural-voice-menu--selected-dimension) 1))
(defun emacsvox-aural-voice-menu--default ()
  "Restore the selected or chosen adjustment to its adapter default." (interactive)
  (let ((dimension
         (or (emacsvox-aural-voice-menu--selected-dimension t)
             (emacsvox-aural-voice-menu--call
              (lambda ()
                (let ((choices (mapcar (lambda (entry)
                                         (cons (emacsvox-aural-voice-tuner--dimension-label (cdr entry))
                                               (cdr entry)))
                                       emacsvox-aural-voice-menu--controls)))
                  (cdr (assoc (completing-read "Restore adapter default for: " choices nil t)
                              choices))))))))
    (emacsvox-aural-voice-menu--edit dimension nil t)))
(defun emacsvox-aural-voice-menu--play ()
  "Preview the selected voice scope privately." (interactive)
  (emacsvox-aural-voice-menu--call #'emacsvox-aural-voice-editor-play))
(defun emacsvox-aural-voice-menu--compare ()
  "Compare the selected scope before and after editing with the same text." (interactive)
  (emacsvox-aural-voice-menu--call #'emacsvox-aural-voice-editor-compare))
(defun emacsvox-aural-voice-menu--stop ()
  "Stop this editor's sample." (interactive)
  (emacsvox-aural-voice-menu--call #'emacsvox-aural-voice-editor-stop))
(defun emacsvox-aural-voice-menu--text ()
  "Edit the shared comparison text." (interactive)
  (emacsvox-aural-voice-menu--call #'emacsvox-aural-voice-editor-text))
(defun emacsvox-aural-voice-menu--undo ()
  "Undo the last draft change." (interactive)
  (emacsvox-aural-voice-menu--call
   (lambda ()
     (cl-letf (((symbol-function 'emacsvox-aural-voice-editor-speak) #'ignore))
       (emacsvox-aural-voice-editor-undo))
     (emacsvox-transient--submit-text
      (concat "Undo. " (plist-get (emacsvox-aural-voice-drafts--status
                                  (emacsvox-aural-voice-editor--draft)) :label))
      (emacsvox-transient--menu-facts 'undo 'operation-completed)
      'state-change 'select-object))))
(defun emacsvox-aural-voice-menu--save ()
  "Save and apply through the common editor." (interactive)
  (emacsvox-aural-voice-menu--call #'emacsvox-aural-voice-editor-save))
(defun emacsvox-aural-voice-menu--collection ()
  "Save without selecting the palette." (interactive)
  (emacsvox-aural-voice-menu--call #'emacsvox-aural-voice-editor-save-to-collection))

(defun emacsvox-aural-voice-menu--scope (choice)
  "Switch the same draft to CHOICE, or shared settings for nil."
  (emacsvox-aural-voice-editor--customize choice)
  (oset (or transient--prefix transient-current-prefix) scope
        (list (current-buffer) emacsvox-aural-voice-editor--context choice)))
(defun emacsvox-aural-voice-menu--fallback ()
  "Choose one stable fallback row without changing its voice or order."
  (interactive)
  (emacsvox-aural-voice-menu--call
   (lambda ()
     (emacsvox-aural-voice-menu--scope
      (emacsvox-aural-voice-editor--read-choice
       (emacsvox-aural-voice-editor--working) "Customize fallback: "
       (emacsvox-aural-voice-editor--get :tuning-choice))))))
(defun emacsvox-aural-voice-menu--shared ()
  "Return to shared tuning without losing individual fallback adjustments."
  (interactive)
  (emacsvox-aural-voice-menu--call (lambda () (emacsvox-aural-voice-menu--scope nil))))
(defun emacsvox-aural-voice-menu--fallback-p ()
  "Whether this menu is editing one fallback row."
  (emacsvox-aural-voice-menu--call
   (lambda () (emacsvox-aural-voice-editor--get :tuning-choice)) t))
(defun emacsvox-aural-voice-menu--inherit ()
  "Restore the selected fallback adjustment's shared value."
  (interactive)
  (let ((dimension (emacsvox-aural-voice-menu--selected-dimension)))
    (emacsvox-aural-voice-menu--call
     (lambda ()
       (let ((automatic (emacsvox-aural-voice-editor--get :automatic-sample)))
         (emacsvox-aural-voice-editor-stop)
         (unwind-protect
             (progn
               (emacsvox-aural-voice-editor--put :automatic-sample nil)
               (cl-letf (((symbol-function 'emacsvox-aural-voice-editor-speak) #'ignore))
                 (emacsvox-aural-voice-editor--set-choice dimension 'inherit nil)))
           (emacsvox-aural-voice-editor--put :automatic-sample automatic))
         (emacsvox-transient--submit-text
          (concat "Use shared value. " (emacsvox-aural-voice-menu--label dimension))
          (emacsvox-transient--menu-facts 'voice-inherit 'command-menu-value-changed)
          'state-change 'select-object))))))
(defun emacsvox-aural-voice-menu--native ()
  "Open qualified engine controls in the same editor, retaining its draft."
  (interactive)
  (require 'emacsvox-aural-voice-engine-controls)
  (emacsvox-aural-voice-menu--call #'emacsvox-aural-voice-engine-controls-open t))

(defun emacsvox-aural-voice-menu--bindings (map)
  "Add shifted-arrow adjustments to this voice menu's MAP."
  (when (and transient--prefix
             (eq (oref transient--prefix command) 'emacsvox-aural-voice-menu))
    (keymap-set map "S-<left>" #'emacsvox-aural-voice-menu--decrease)
    (keymap-set map "S-<right>" #'emacsvox-aural-voice-menu--increase))
  map)
(advice-add 'transient--make-transient-map :filter-return #'emacsvox-aural-voice-menu--bindings)
(define-key transient-predicate-map [emacsvox-aural-voice-menu--decrease] #'transient--do-stay)
(define-key transient-predicate-map [emacsvox-aural-voice-menu--increase] #'transient--do-stay)

;;;###autoload
(transient-define-prefix emacsvox-aural-voice-menu ()
  "Tune shared or individual fallback values; preview and save explicitly."
  :refresh-suffixes t
  [:description emacsvox-aural-voice-menu--title
   ("f" "Choose a fallback to customize" emacsvox-aural-voice-menu--fallback :transient t)
   ("h" "Shared settings" emacsvox-aural-voice-menu--shared :transient t)
   ("e" "Qualified engine controls (full editor)" emacsvox-aural-voice-menu--native)]
  ["Adjust the selected voice scope"
   ("r" (lambda () (emacsvox-aural-voice-menu--label 'rate-offset)) emacsvox-aural-voice-menu--rate :transient t)
   ("p" (lambda () (emacsvox-aural-voice-menu--label 'average-pitch)) emacsvox-aural-voice-menu--pitch :transient t)
   ("g" (lambda () (emacsvox-aural-voice-menu--label 'pitch-range)) emacsvox-aural-voice-menu--range :transient t)
   ("v" (lambda () (emacsvox-aural-voice-menu--label 'gain)) emacsvox-aural-voice-menu--gain :transient t)
   ("d" "Adapter default for selected adjustment" emacsvox-aural-voice-menu--default :transient t)
   ("i" "Use shared value for selected adjustment" emacsvox-aural-voice-menu--inherit :inapt-if-not emacsvox-aural-voice-menu--fallback-p :transient t)
   ("u" "Undo last change" emacsvox-aural-voice-menu--undo :transient t)]
  ["Preview the selected voice scope"
   ("P" "Preview edited voice" emacsvox-aural-voice-menu--play :transient t)
   ("B" "Compare original and edited" emacsvox-aural-voice-menu--compare :transient t)
   ("S" "Stop preview" emacsvox-aural-voice-menu--stop :transient t)
   ("T" "Preview text" emacsvox-aural-voice-menu--text :transient t)]
  ["Save"
   ("w" "Save and apply" emacsvox-aural-voice-menu--save :transient t)
   ("c" "Save to collection without selecting" emacsvox-aural-voice-menu--collection :transient t)]
  ["Finish"
   ("q" "Back to editor (keep draft)" transient-quit-one)]
  (interactive)
  (unless (and (derived-mode-p 'emacsvox-aural-voice-editor-mode)
               (emacsvox-aural-voice-editor--get :voice)
               (or (not (emacsvox-aural-voice-editor--get :tuning-choice))
                   (emacsvox-aural-voice-editor--tuning-row))
               (not (emacsvox-aural-voice-editor--get :engine-controls)))
    (user-error "Open a named voice's shared or fallback editor first"))
  (let ((buffer (current-buffer)) (context emacsvox-aural-voice-editor--context) cleanup)
    (emacsvox-aural-voice-editor-stop)
    (transient-setup 'emacsvox-aural-voice-menu nil nil :scope (list buffer context (emacsvox-aural-voice-editor--get :tuning-choice)))
    (setq cleanup
          (lambda ()
            (remove-hook 'transient-exit-hook cleanup)
            (when (buffer-live-p buffer)
              (with-current-buffer buffer
                (when (eq context emacsvox-aural-voice-editor--context)
                  (emacsvox-aural-voice-editor-stop))))))
    (add-hook 'transient-exit-hook cleanup)))

(provide 'emacsvox-aural-voice-menu)
;;; emacsvox-aural-voice-menu.el ends here
