;;; emacsvox-table-settings.el --- Scoped table reading settings -*- lexical-binding: t; -*-

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
;; Capture a source buffer, browse pending choices and save only explicitly.
;;; Code:

(require 'emacsvox-table-reader)
(require 'emacsvox-aural-menu)
(require 'emacsvox-aural-preview)
(require 'cus-edit)

(defconst emacsvox-table-settings--specs
  '((titles "Titles" "Choose titles spoken with a cell. Row titles use the first column; column titles use the header row when available."
     ((column) "Column titles" "Read the header above the cell, when available.")
     ((row) "Row titles" "Read the first cell in the row as its heading.")
     ((column row) "Both titles" "Read both the column heading and the row heading.")
     (nil "No titles" "Read the cell data without row or column headings.")
     (inherit "Inherit wider scope"))
    (data-position "Order" "Read the cell data before or after its titles."
     (first "Data first" "Read the cell value before its selected headings.")
     (last "Titles first" "Read the selected headings before the cell value.")
     (inherit "Inherit wider scope"))
    (movement-speech "Plain Up and Down" "Choose cell or whole-row speech for plain vertical arrows. Control-Meta arrows always read a cell. Public row-reading commands still read rows."
     (row "Read the row" "Plain Up and Down speak every cell in the destination row.")
     (cell "Read the cell" "Plain Up and Down speak only the destination cell.")
     (inherit "Inherit wider scope"))
    (activation "Activation" "Automatic reading starts when navigation enters a table. On demand starts with Control-Meta arrows or the table reading command. Quitting suspends automatic entry until you leave and return or explicitly enter again."
     (automatic "Automatic" "Start table reading when navigation enters a supported table.")
     (on-demand "On demand" "Start reading with Control-Meta arrows or the table reading command.")
     (nil "Mode defaults: Agent Shell automatic; others on demand"
          "Use the built-in activation policy, even if a broader setting differs.")
     (inherit "Inherit wider scope"))
    (coordinates "Coordinates during movement" "Add row and column numbers to movement feedback. The coordinate inspection command always remains available."
     (t "Announce coordinates" "Include row and column numbers when moving between cells.")
     (nil "Omit coordinates" "Leave numbers out of movement speech; coordinate inspection remains available.")
     (inherit "Inherit wider scope"))
    (entry-detail "Entry detail" "Full entry announces table dimensions and the cell. Brief entry announces the table and cell; dimensions remain available on equals."
     (full "Dimensions and cell" "Announce the table size and current cell when reading starts.")
     (brief "Brief: table and cell" "Announce the table and current cell; equals still reads its size.")
     (inherit "Inherit wider scope"))
    (repeat-titles "Repeated titles" "When off, omit unchanged headings on consecutive cell moves. Explicit inspection always reads the selected titles."
     (t "Repeat titles" "Include the selected headings on each cell move, even when unchanged.")
     (nil "Omit unchanged titles" "Skip headings repeated from the previous cell; explicit inspection keeps them.")
     (inherit "Inherit wider scope"))
    (edge-action "Vertical edges" "Leave moves to adjacent prose at the first or last row. Stop retains the cell. Application lists always stop. Explicit exit commands remain available."
     (leave "Leave for adjacent prose" "Moving past the first or last row leaves the table; application lists still stop.")
     (stop "Stop at the edge" "Keep the current cell at the first or last row; q still exits reading.")
     (inherit "Inherit wider scope")))
  "Settings, labels, explanations and ordered choices.")

(defun emacsvox-table-settings--context ()
  "Return the captured context, initializing its pending choices once."
  (let* ((prefix (or transient--prefix transient-current-prefix))
         (context (emacsvox-aural-menu--context))
         (source (emacsvox-aural-menu--source context)))
    (unless (plist-get context :table-draft)
      (setq context
            (plist-put (copy-sequence context) :table-draft
                       (with-current-buffer source
                         (list :mode (emacsvox-table-reader--mode)
                               :values (mapcar
                                        (lambda (entry)
                                          (cons (car entry) (emacsvox-table-reader--preference (car entry))))
                                        emacsvox-table-reader--options)
                               :changed nil :applied nil))))
      (oset prefix scope context))
    (unless (eq (plist-get (plist-get context :table-draft) :mode)
                (with-current-buffer source (emacsvox-table-reader--mode)))
      (user-error "Source mode changed; reopen Tables settings"))
    context))

(defun emacsvox-table-settings--draft ()
  "Return the shared pending choices for this menu visit."
  (plist-get (emacsvox-table-settings--context) :table-draft))

(defun emacsvox-table-settings--value-label (key value)
  "Describe VALUE for table setting KEY."
  (or (cadr (assoc value (nthcdr 3 (assq key emacsvox-table-settings--specs))))
      (format "%S" value)))

(defun emacsvox-table-settings--label (key)
  "Describe KEY, retaining an exit route if the source is no longer usable."
  (condition-case nil (emacsvox-table-settings--live-label key)
    (user-error (concat (cadr (assq key emacsvox-table-settings--specs))
                        ": source unavailable; reopen Tables"))))

(defun emacsvox-table-settings--live-label (key)
  "Describe KEY with pending value, effective value and scope."
  (let* ((context (emacsvox-table-settings--context))
         (draft (plist-get context :table-draft))
         (value (alist-get key (plist-get draft :values)))
         (resolved (with-current-buffer (plist-get context :source)
                     (emacsvox-table-reader--resolve key)))
         (effective (emacsvox-table-settings--value-label key (plist-get resolved :value)))
         (scope (pcase (plist-get resolved :source)
                  ('legacy-ambiguous "older Agent Shell value; origin uncertain")
                  ('legacy-mode "older Agent Shell setting")
                  ('legacy-buffer "older Agent Shell buffer setting")
                  ('built-in "mode default")
                  (other (symbol-name other)))))
    (format "%s: %s%s; effective %s, %s"
            (cadr (assq key emacsvox-table-settings--specs))
            (emacsvox-table-settings--value-label key value)
            (cond ((memq key (plist-get draft :applied)) ", applied here, not saved")
                  ((memq key (plist-get draft :changed)) ", pending")
                  (t "")) effective scope)))

(defun emacsvox-table-settings--say (text &optional intent)
  "Speak TEXT as INTENT, replacing obsolete menu speech."
  (emacsvox-transient--submit-text
   text (emacsvox-transient--menu-facts
         'tables (when (memq intent '(nil state-change))
                   'command-menu-value-changed))
   (or intent 'state-change) 'button))

(defun emacsvox-table-settings--focus (command)
  "Restore the menu item for COMMAND."
  (when (window-live-p transient--window)
    (when-let* ((object (cl-find command transient--suffixes
                                :key (lambda (item) (oref item command)))))
      (with-selected-window transient--window (transient--goto-button object)))))

(defun emacsvox-table-settings--return (command)
  "Restore the parent menu at COMMAND."
  (when (transient--stack-pop)
    (transient--show)
    (emacsvox-table-settings--focus command)))

(defun emacsvox-table-settings--choose (key)
  "Browse choices for KEY without changing the pending value."
  (let* ((context (emacsvox-table-settings--context))
         (value (alist-get key (plist-get (plist-get context :table-draft) :values)))
         (index (or (seq-position (nthcdr 3 (assq key emacsvox-table-settings--specs))
                                  value (lambda (choice selected) (equal (car choice) selected))) 0)))
    (transient-setup 'emacsvox-table-settings--choices nil nil
                     :scope (plist-put (copy-sequence context) :table-choice key))
    (transient--show)
    (emacsvox-table-settings--focus
     (intern (format "emacsvox-table-settings--choice-%d" index)))
    (emacsvox-transient--speak-button)))

(defun emacsvox-table-settings--choice (index)
  "Return choice INDEX for the browsed setting."
  (nth index (nthcdr 3 (assq (plist-get (emacsvox-table-settings--context) :table-choice)
                            emacsvox-table-settings--specs))))

(defun emacsvox-table-settings--choice-label (index)
  "Describe choice INDEX and identify the pending selection."
  (let* ((key (plist-get (emacsvox-table-settings--context) :table-choice))
         (choice (emacsvox-table-settings--choice index)))
    (concat (cadr choice)
            (when (equal (car choice) (alist-get key (plist-get (emacsvox-table-settings--draft) :values)))
              ", selected"))))

(defun emacsvox-table-settings--choice-documentation (index)
  "Explain the effect of choice INDEX in the active choice menu."
  (if (and transient--prefix
           (eq (oref transient--prefix command) 'emacsvox-table-settings--choices))
      (let ((choice (emacsvox-table-settings--choice index)))
        (if (eq (car choice) 'inherit)
            (concat
             "Apply follows the mode setting; Save mode follows common defaults.\n\n"
             "This removes the override at the scope you apply or save. "
             "A buffer follows its mode setting, or common defaults if that mode has no override. "
             "A mode follows the common default; existing buffer overrides still win. "
             "For example, if common titles are Column titles, saving inheritance for Org makes Org follow that choice. "
             "Common defaults cannot inherit. No titles and Off are explicit values, not inheritance.")
          (nth 2 choice)))
    "Stage this choice; Apply or Save in the parent menu makes it effective."))

(defun emacsvox-table-settings--stage (key value)
  "Stage VALUE for KEY without changing runtime preferences."
  (let ((draft (emacsvox-table-settings--draft)))
    (setf (alist-get key (plist-get draft :values)) (copy-tree value))
    (cl-pushnew key (plist-get draft :changed))
    (setf (plist-get draft :applied) (remq key (plist-get draft :applied)))))

(defun emacsvox-table-settings--choice-apply (index)
  "Stage choice INDEX and return focus to the originating control."
  (let* ((key (plist-get (emacsvox-table-settings--context) :table-choice))
         (choice (emacsvox-table-settings--choice index)))
    (emacsvox-table-settings--stage key (car choice))
    (emacsvox-table-settings--return (intern (format "emacsvox-table-settings--%s" key)))
    (emacsvox-table-settings--say (concat (cadr choice) ", pending. Apply or Save to use it."))))

(defun emacsvox-table-settings--choice-cancel ()
  "Return without selecting a value."
  (interactive)
  (emacsvox-table-settings--return
   (intern (format "emacsvox-table-settings--%s"
                   (plist-get (emacsvox-table-settings--context) :table-choice)))))

(defun emacsvox-table-settings--commit (scope)
  "Apply changed choices at SCOPE: buffer, mode or common.
Other scopes and unchanged settings remain intact."
  (let* ((context (emacsvox-table-settings--context))
         (draft (plist-get context :table-draft))
         (changed (plist-get draft :changed))
         (values (plist-get draft :values))
         (mode (plist-get draft :mode)))
    (unless changed (user-error "No pending table choices"))
    (when (and (eq scope 'common)
               (seq-some (lambda (key) (eq (alist-get key values) 'inherit)) changed))
      (user-error "Common defaults cannot inherit; select values or save inheritance for the buffer or mode"))
    (pcase scope
      ('buffer
       (with-current-buffer (plist-get context :source)
         (dolist (key changed)
           (setf (alist-get key emacsvox-table-reader--buffer-preferences)
                 (copy-tree (alist-get key values))))
         (setq emacsvox-table-reader--last-titles nil)))
      ('mode
       (let ((preferences (copy-tree emacsvox-table-reader-mode-preferences)))
         (dolist (key changed)
           (setf (alist-get key (alist-get mode preferences)) (copy-tree (alist-get key values))))
         (customize-save-variable 'emacsvox-table-reader-mode-preferences preferences)))
      ('common
       (dolist (key changed)
         (customize-save-variable (alist-get key emacsvox-table-reader--options)
                                  (copy-tree (alist-get key values))))))
    (if (eq scope 'buffer)
        (setf (plist-get draft :applied) (copy-sequence changed))
      (setf (plist-get draft :changed) nil
            (plist-get draft :applied) nil))
    ;; Keep applied values available to Save, even after a local trial.
    ;; Re-read effective values: a narrower override may still win.
    (unless (eq scope 'buffer)
      (with-current-buffer (plist-get context :source)
        (setf (plist-get draft :values)
              (mapcar (lambda (entry) (cons (car entry) (emacsvox-table-reader--preference (car entry))))
                      emacsvox-table-reader--options))))
    (emacsvox-table-settings--say
     (pcase scope
       ('buffer "Applied to the captured buffer. Not saved.")
       ('mode (format "Saved table settings for %s. Buffer overrides still apply." mode))
       ('common "Saved common table defaults. Mode and buffer overrides still apply.")))))

(defun emacsvox-table-settings--apply ()
  "Apply only pending choices to the captured buffer, without saving."
  (interactive) (emacsvox-table-settings--commit 'buffer))
(defun emacsvox-table-settings--save-common ()
  "Save changed choices as common Customize defaults.
Narrower overrides remain."
  (interactive) (emacsvox-table-settings--commit 'common))
(defun emacsvox-table-settings--save-mode ()
  "Save only pending choices for the captured mode through Customize."
  (interactive) (emacsvox-table-settings--commit 'mode))
(defun emacsvox-table-settings--inherit ()
  "Stage inheritance for every setting. Apply to this buffer or Save for its mode."
  (interactive)
  (dolist (entry emacsvox-table-reader--options)
    (emacsvox-table-settings--stage (car entry) 'inherit))
  (emacsvox-table-settings--say "Inherit wider scope, pending for all table settings."))
(defun emacsvox-table-settings--discard ()
  "Discard pending choices and reread the captured buffer's effective settings."
  (interactive)
  (let* ((context (emacsvox-table-settings--context))
         (draft (plist-get context :table-draft)))
    (setf (plist-get draft :changed) nil (plist-get draft :applied) nil)
    (with-current-buffer (plist-get context :source)
      (setf (plist-get draft :values)
            (mapcar (lambda (entry) (cons (car entry) (emacsvox-table-reader--preference (car entry))))
                    emacsvox-table-reader--options))))
  (emacsvox-table-settings--say "Pending choices discarded."))

(defun emacsvox-table-settings--preview ()
  "Preview a representative table with pending choices.
Preserve the source buffer and runtime settings."
  (interactive)
  (let* ((context (emacsvox-table-settings--context))
         (draft (plist-get context :table-draft)))
    (with-current-buffer (plist-get context :source)
      (let* ((emacsvox-table-reader--buffer-preferences (copy-tree (plist-get draft :values)))
             (emacsvox-table-reader--last-titles nil)
             (cell '(:data "Engineer" :row-title "Alice" :column-title "Role"
                           :row-index 1 :column-index 1 :row-count 3 :column-count 2
                           :column-titles-p t :rows (("Name" "Role") ("Alice" "Engineer") ("Bob" ""))))
             (text (concat "Table. "
                           (when (eq (emacsvox-table-reader--preference 'entry-detail) 'full)
                             (concat (emacsvox-table-reader--dimensions-speech cell) " "))
                           (emacsvox-table-reader--format cell 'cell t) " ")))
        (setq cell (copy-sequence cell))
        (setq cell (plist-put cell :data ""))
        (setq cell (plist-put cell :row-title "Bob"))
        (setq cell (plist-put cell :row-index 2))
        (emacsvox-table-settings--say
         (concat text (emacsvox-table-reader--format
                       cell (emacsvox-table-reader--preference 'movement-speech) t))
         'inspection)))))

(defun emacsvox-table-settings--stop ()
  "Stop the current preview without changing pending choices."
  (interactive) (emacsvox-aural-preview-stop))

(defun emacsvox-table-settings--legacy-details (context)
  "Describe retained Agent Shell choices in CONTEXT, including overridden ones."
  (with-current-buffer (plist-get context :source)
    (when (eq (emacsvox-table-reader--mode) 'agent-shell-mode)
      (concat
       "\n\nRetained older Agent Shell values:\n"
       (mapconcat
        (lambda (entry)
          (let ((symbol (cdr entry)))
            (if (not (boundp symbol))
                (format "%s: not loaded." (car entry))
              (format "%s: %S%s; global %S%s."
                      (car entry) (symbol-value symbol)
                      (if (local-variable-p symbol) " in this buffer" "")
                      (default-value symbol)
                      (cond ((get symbol 'saved-value) " (saved)")
                            ((get symbol 'customized-value) " (customized for this session)")
                            ((memq symbol emacsvox-table-reader--legacy-assigned) " (assigned this session)")
                            ((memq symbol emacsvox-table-reader--legacy-preexisting) " (origin uncertain)")
                            (t " (package value)"))))))
        '((Titles . emacsvox-agent-shell-table-titles)
          (Order . emacsvox-agent-shell-table-data-position)) "\n")))))

(defun emacsvox-table-settings--help (&optional object)
  "Explain table settings or the choice at OBJECT without changing it."
  (interactive)
  (let* ((context (emacsvox-table-settings--context))
         (key (plist-get context :table-choice)))
    (when (window-live-p transient--window)
      (with-selected-window transient--window
        (when-let* ((button (button-at (point))) (suffix (button-get button 'button-data)))
          (oset transient--prefix scope
                (plist-put context :table-help-focus (oref suffix command))))))
    (with-help-window (help-buffer)
      (princ "Table reading settings\n\n")
      (when key
        (princ (nth 2 (assq key emacsvox-table-settings--specs)))
        (when object
          (princ "\n\n")
          (let ((index (1- (string-to-number (oref object key)))))
            (princ (cadr (emacsvox-table-settings--choice index)))
            (princ ". ")
            (princ (emacsvox-table-settings--choice-documentation index))))
        (princ "\n\n"))
      (princ "Browsing changes nothing. Selecting stages a pending choice. Space previews it. Apply affects only the captured buffer; Save common and Save mode persist only pending choices through Customize. Applied choices remain available to Save during this visit and are labelled not saved. Closing discards unapplied choices and keeps buffer applications.\n\nBuffer settings override mode settings, which override common defaults. Inherit skips older choices at the scope you apply or save. No titles is an explicit value. Mode defaults means automatic in Agent Shell and on demand elsewhere.\n\nOlder Agent Shell title and order settings remain effective, including saved values equal to their defaults. The effective label identifies them. A value set before loading may have uncertain origin; it is preserved until you explicitly select inheritance or a replacement. No old configuration is rewritten.\n\nUp and Down read rows by default. Control-Meta arrows enter reading and read cells. q leaves reading in place until explicit entry or leaving and returning. Agent Shell retains native Tab, Shift-Tab and Return actions. In its viewport, a second q can bury the buffer. Application lists retain their action keys. Org's native table editing and its movement feedback option remain independent.\n\nActivation and edge behavior are tried in the source table; the preview demonstrates speech only. Preview treats pending choices as buffer overrides, so inheritance follows current mode settings. Mode Save can resolve inheritance differently; the effective labels refresh after saving.")
      (princ (or (emacsvox-table-settings--legacy-details context) "")))
    (pop-to-buffer (help-buffer))
    (emacsvox-table-settings--say (buffer-string) 'inspection)))

(defun emacsvox-table-settings--restore-help-focus (&rest _)
  "Restore the browsed item once after its Help closes."
  (when (and transient--prefix
             (memq (oref transient--prefix command)
                   '(emacsvox-table-settings emacsvox-table-settings--choices)))
    (when-let* ((command (plist-get (oref transient--prefix scope) :table-help-focus)))
      (oset transient--prefix scope (plist-put (oref transient--prefix scope) :table-help-focus nil))
      (emacsvox-table-settings--focus command))))
(advice-add 'transient--show :after #'emacsvox-table-settings--restore-help-focus)

(defun emacsvox-table-settings--titles ()
  "Titles spoken with cells; select without applying."
  (interactive) (emacsvox-table-settings--choose 'titles))
(defun emacsvox-table-settings--data-position ()
  "Choose data before or after titles; select without applying."
  (interactive) (emacsvox-table-settings--choose 'data-position))
(defun emacsvox-table-settings--movement-speech ()
  "Choose row or cell speech for plain Up and Down; Control-Meta arrows read cells."
  (interactive) (emacsvox-table-settings--choose 'movement-speech))
(defun emacsvox-table-settings--activation ()
  "Choose automatic or explicit entry; quitting suspends this visit."
  (interactive) (emacsvox-table-settings--choose 'activation))
(defun emacsvox-table-settings--coordinates ()
  "Choose whether movement includes coordinates.
Explicit inspection remains available."
  (interactive) (emacsvox-table-settings--choose 'coordinates))
(defun emacsvox-table-settings--entry-detail ()
  "Choose full dimensions or brief table entry."
  (interactive) (emacsvox-table-settings--choose 'entry-detail))
(defun emacsvox-table-settings--repeat-titles ()
  "Choose whether consecutive cell moves repeat unchanged titles."
  (interactive) (emacsvox-table-settings--choose 'repeat-titles))
(defun emacsvox-table-settings--edge-action ()
  "Choose whether vertical edges stop or leave for prose; lists always stop."
  (interactive) (emacsvox-table-settings--choose 'edge-action))
(defun emacsvox-table-settings--choice-0 ()
  "Stage this choice; Apply or Save in the parent menu makes it effective."
  (interactive) (emacsvox-table-settings--choice-apply 0))
(defun emacsvox-table-settings--choice-1 ()
  "Stage this choice; Apply or Save in the parent menu makes it effective."
  (interactive) (emacsvox-table-settings--choice-apply 1))
(defun emacsvox-table-settings--choice-2 ()
  "Stage this choice; Apply or Save in the parent menu makes it effective."
  (interactive) (emacsvox-table-settings--choice-apply 2))
(defun emacsvox-table-settings--choice-3 ()
  "Stage this choice; Apply or Save in the parent menu makes it effective."
  (interactive) (emacsvox-table-settings--choice-apply 3))
(defun emacsvox-table-settings--choice-4 ()
  "Stage this choice; Apply or Save in the parent menu makes it effective."
  (interactive) (emacsvox-table-settings--choice-apply 4))

;; Transient uses the first documentation line for its optional short
;; descriptions.  Resolve it from the current setting, since these commands
;; serve different values in each choice list.
(dotimes (index 5)
  (put (intern (format "emacsvox-table-settings--choice-%d" index))
       'function-documentation
       `(emacsvox-table-settings--choice-documentation ,index)))

(transient-define-prefix emacsvox-table-settings--choices ()
  "Browse table choices; selecting stages a value without applying it."
  ["Choose a pending value"
   ("1" (lambda () (emacsvox-table-settings--choice-label 0))
    emacsvox-table-settings--choice-0
    :if (lambda () (emacsvox-table-settings--choice 0))
    :show-help emacsvox-table-settings--help :transient transient--do-replace)
   ("2" (lambda () (emacsvox-table-settings--choice-label 1))
    emacsvox-table-settings--choice-1
    :if (lambda () (emacsvox-table-settings--choice 1))
    :show-help emacsvox-table-settings--help :transient transient--do-replace)
   ("3" (lambda () (emacsvox-table-settings--choice-label 2))
    emacsvox-table-settings--choice-2
    :if (lambda () (emacsvox-table-settings--choice 2))
    :show-help emacsvox-table-settings--help :transient transient--do-replace)
   ("4" (lambda () (emacsvox-table-settings--choice-label 3))
    emacsvox-table-settings--choice-3
    :if (lambda () (emacsvox-table-settings--choice 3))
    :show-help emacsvox-table-settings--help :transient transient--do-replace)
   ("5" (lambda () (emacsvox-table-settings--choice-label 4))
    emacsvox-table-settings--choice-4
    :if (lambda () (emacsvox-table-settings--choice 4))
    :show-help emacsvox-table-settings--help :transient transient--do-replace)
  ]
  ["Finish"
   ("q" "Cancel selection" emacsvox-table-settings--choice-cancel :transient transient--do-replace)])

;;;###autoload
(transient-define-prefix emacsvox-table-settings ()
  "Browse pending table choices for a captured source buffer.
Apply temporarily to that buffer, or explicitly save common or mode defaults."
  :refresh-suffixes t
  [:description (lambda ()
                  (let ((source (plist-get (emacsvox-aural-menu--context) :source)))
                    (if (buffer-live-p source)
                        (format "Tables for %s (%s): reading preferences"
                                (buffer-name source)
                                (with-current-buffer source (emacsvox-table-reader--mode)))
                      "Tables: source closed")))
   ("t" (lambda () (emacsvox-table-settings--label 'titles))
    emacsvox-table-settings--titles :transient transient--do-suspend)
   ("o" (lambda () (emacsvox-table-settings--label 'data-position))
    emacsvox-table-settings--data-position :transient transient--do-suspend)
   ("m" (lambda () (emacsvox-table-settings--label 'movement-speech))
    emacsvox-table-settings--movement-speech :transient transient--do-suspend)
   ("a" (lambda () (emacsvox-table-settings--label 'activation))
    emacsvox-table-settings--activation :transient transient--do-suspend)
   ("c" (lambda () (emacsvox-table-settings--label 'coordinates))
    emacsvox-table-settings--coordinates :transient transient--do-suspend)
   ("e" (lambda () (emacsvox-table-settings--label 'entry-detail))
    emacsvox-table-settings--entry-detail :transient transient--do-suspend)
   ("r" (lambda () (emacsvox-table-settings--label 'repeat-titles))
    emacsvox-table-settings--repeat-titles :transient transient--do-suspend)
   ("v" (lambda () (emacsvox-table-settings--label 'edge-action))
    emacsvox-table-settings--edge-action :transient transient--do-suspend)
  ]
  ["Try and apply"
   ("SPC" "Preview pending speech" emacsvox-table-settings--preview :transient t)
   ("s" "Stop preview" emacsvox-table-settings--stop :transient t)
   ("A" "Apply pending choices to captured buffer" emacsvox-table-settings--apply :transient t)
   ("W" "Save changed choices as common defaults" emacsvox-table-settings--save-common :transient t)
   ("M" "Save changed choices for captured mode" emacsvox-table-settings--save-mode :transient t)]
  ["Inheritance and finish"
   ("I" "Stage inheritance for all settings" emacsvox-table-settings--inherit :transient t)
   ("D" "Discard pending choices" emacsvox-table-settings--discard :transient t)
   ("h" "Help: scopes, migration and navigation" emacsvox-table-settings--help :transient transient--do-suspend)
   ("q" "Back; discard pending choices" transient-quit-one)
   ("C-q" "Close menus; discard pending choices" transient-quit-all)]
  (interactive)
  (let* ((context (condition-case nil (copy-sequence (emacsvox-aural-menu--context))
                    (user-error (emacsvox-aural-menu--capture nil)))))
    (setq context (plist-put context :table-draft nil))
    (transient-setup 'emacsvox-table-settings nil nil :scope context)))

(provide 'emacsvox-table-settings)
;;; emacsvox-table-settings.el ends here
