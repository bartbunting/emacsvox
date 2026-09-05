;;; emacsvox-aural-ui.el --- Shared accessible aural interfaces -*- lexical-binding: t; -*-

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

;; Common interface identity, spoken tabulated-list navigation, refresh
;; preservation, and dismissal feedback for the aural managers and editors.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'tabulated-list)

(defvar emacsvox-aural-submission-facts)
(defvar emacsvox-aural-submission-context)
(defvar emacsvox-aural-submission-module)
(defvar emacsvox-aural-submission-occasion)
(defvar emacsvox-speak-messages)

(declare-function emacsvox-aural-capture-context
                  "emacsvox-aural-transport"
                  (&optional module occasion))
(declare-function emacsvox-icon "emacsvox-sounds" (icon))
(declare-function emacsvox-speak-mode-line
                  "emacsvox-speak"
                  (&optional buffer-info))
(declare-function emacsvox-aural-home-refresh
                  "emacsvox-aural-home" (&optional id))
(autoload 'emacsvox-aural "emacsvox-aural-home" nil t)
(declare-function tts-speak "tts-speak" (text))
(declare-function emacsvox-aural-preview-stop "emacsvox-aural-preview" ())
(declare-function emacsvox-aural-preview-message "emacsvox-aural-preview"
                  (format-string &rest arguments))

(defvar-local emacsvox-aural-ui-interface-buffer nil
  "Non-nil when the current buffer is an aural interface.")

(defvar-local emacsvox-aural-ui-source-buffer nil
  "Ordinary buffer from which the current aural interface was opened.")

(defvar-local emacsvox-aural-ui-source-position nil
  "Marker for the source item captured on entry to this interface.")

(defvar-local emacsvox-aural-ui-source-guard nil
  "Snapshot detecting replacement of the captured source item.")

(defvar-local emacsvox-aural-ui-list-name "list"
  "Spoken name of the current tabulated interface.")

(defvar-local emacsvox-aural-ui-speech-function nil
  "Optional function used to speak text in the current interface.

The function receives one string.  When nil, interface feedback uses
`tts-speak'.")

(defvar-local emacsvox-aural-ui-row-speaker nil
  "Function that speaks the complete current row.")

(defvar-local emacsvox-aural-ui-move-speaker nil
  "Function called after moving to another row.

When nil, movement speaks the current titled cell.")

(defvar-local emacsvox-aural-ui-after-move-function nil
  "Function called after successful row movement.")

(defvar-local emacsvox-aural-ui-refresh-function nil
  "Interactive function that refreshes the current interface.")

(defvar-local emacsvox-aural-ui-dismiss-warning-function nil
  "Optional function returning a warning to speak after this interface hides.")

(defvar-local emacsvox-aural-ui-action-filter nil
  "Optional predicate deciding whether a command applies to the current row.")

(defvar-local emacsvox-aural-ui-extra-actions nil
  "Additional labelled commands offered by the Actions menu.")

(defvar-local emacsvox-aural-ui-help-origin-buffer nil
  "Aural interface buffer from which the current Help buffer was opened.")

(defvar-local emacsvox-aural-ui-help-origin-window nil
  "Window that displayed the originating aural interface.")

(defvar-local emacsvox-aural-ui-help-origin-position nil
  "Marker recording point in the originating aural interface.")

(defvar emacsvox-aural-ui-help-return-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "q") #'emacsvox-aural-ui-help-quit)
    (define-key map (kbd "h") #'emacsvox-aural)
    (define-key map (kbd "S") #'emacsvox-aural-ui-stop-preview)
    (define-key map (kbd "C-c C-a") #'emacsvox-aural-ui-help-actions)
    map)
  "Keymap that gives aural Help buffers an exact return destination.")

(define-minor-mode emacsvox-aural-ui-help-return-mode
  "Return from Help to the exact aural interface that requested it."
  :lighter nil
  :keymap emacsvox-aural-ui-help-return-mode-map)

(defun emacsvox-aural-ui-help-actions ()
  "Return to the interface that opened Help and choose one of its actions."
  (interactive)
  (unless (buffer-live-p emacsvox-aural-ui-help-origin-buffer)
    (user-error "The interface that opened Help is no longer available"))
  (emacsvox-aural-ui-help-quit)
  (emacsvox-aural-ui-actions))

(defun emacsvox-aural-ui-help-quit ()
  "Quit Help and restore its originating aural interface and position."
  (interactive)
  (let ((origin-buffer emacsvox-aural-ui-help-origin-buffer)
        (origin-window emacsvox-aural-ui-help-origin-window)
        (origin-position emacsvox-aural-ui-help-origin-position))
    (quit-window)
    (cond
     ((and (window-live-p origin-window)
           (buffer-live-p origin-buffer))
      (set-window-buffer origin-window origin-buffer)
      (select-window origin-window)
      (when (and (markerp origin-position)
                 (marker-position origin-position))
        (with-current-buffer origin-buffer
          (goto-char origin-position))
        (set-window-point origin-window origin-position)))
     ((buffer-live-p origin-buffer)
      (pop-to-buffer origin-buffer)
      (when (and (markerp origin-position)
                 (marker-position origin-position))
        (goto-char origin-position))))
    (when (markerp origin-position)
      (set-marker origin-position nil))
    (when (fboundp 'emacsvox-icon)
      (emacsvox-icon 'close-object))
    (when (fboundp 'emacsvox-speak-mode-line)
      (emacsvox-speak-mode-line))))

(defun emacsvox-aural-ui-display-help (producer)
  "Display Help from PRODUCER and remember the exact aural origin.

PRODUCER writes the Help contents to `standard-output', as it would inside
`with-help-window'.  A local `q' binding returns to the invoking buffer,
window, and point even when a reusable Help window has stale restoration
metadata."
  (let ((origin-buffer (current-buffer))
        (origin-window (selected-window))
        (origin-position (copy-marker (point)))
        (source (if emacsvox-aural-ui-interface-buffer
                    emacsvox-aural-ui-source-buffer (current-buffer)))
        (source-position (if emacsvox-aural-ui-interface-buffer
                             emacsvox-aural-ui-source-position (copy-marker (point) t)))
        (source-guard emacsvox-aural-ui-source-guard))
    (with-help-window (help-buffer)
      (funcall producer)
      (princ "\nIn the Aural interface, C-c C-a lists available actions.\n"))
    (when-let* ((buffer (get-buffer (help-buffer))))
      (with-current-buffer buffer
        (when (markerp emacsvox-aural-ui-help-origin-position)
          (set-marker emacsvox-aural-ui-help-origin-position nil))
        (setq-local emacsvox-aural-ui-help-origin-buffer origin-buffer)
        (setq-local emacsvox-aural-ui-help-origin-window origin-window)
        (setq-local emacsvox-aural-ui-help-origin-position origin-position)
        (emacsvox-aural-ui-register-interface source)
        (setq-local emacsvox-aural-ui-source-buffer source)
        (setq-local emacsvox-aural-ui-source-position
                    (and (markerp source-position)
                         (copy-marker source-position t)))
        (setq-local emacsvox-aural-ui-source-guard source-guard)
        (emacsvox-aural-ui-help-return-mode 1)))
    (get-buffer (help-buffer))))

(defmacro emacsvox-aural-ui-with-help-window (&rest body)
  "Display BODY as Help that returns to its exact aural origin with `q'."
  (declare (indent 0) (debug t))
  `(emacsvox-aural-ui-display-help (lambda () ,@body)))

(defun emacsvox-aural-ui-register-interface (&optional source-buffer)
  "Mark the current buffer as an aural interface.

When SOURCE-BUFFER is live and is not itself an aural interface, remember it
as the ordinary buffer from which this interface was opened."
  (setq-local emacsvox-aural-ui-interface-buffer t)
  (when
      (and
       (buffer-live-p source-buffer)
       (not (buffer-local-value
             'emacsvox-aural-ui-interface-buffer source-buffer)))
    (setq-local emacsvox-aural-ui-source-buffer source-buffer))
  t)

(defun emacsvox-aural-ui-interface-buffer-p (&optional buffer)
  "Return non-nil when BUFFER is a registered aural interface."
  (with-current-buffer (or buffer (current-buffer))
    emacsvox-aural-ui-interface-buffer))

(defun emacsvox-aural-ui-pop-to-buffer (buffer)
  "Display aural interface BUFFER and announce that it opened.

Interactive Emacs sessions play the scheme-resolved `open-object' cue with
semantic event `aural-interface-opened'.  Batch sessions remain silent.
Return the window selected by `pop-to-buffer'."
  (let ((window (pop-to-buffer buffer)))
    (when
        (and
         (not noninteractive)
         (fboundp 'emacsvox-icon))
      (let ((emacsvox-aural-submission-facts
             '(:role aural-interface :events (aural-interface-opened)))
            (emacsvox-aural-submission-context
             (emacsvox-aural-capture-context
              'aural-tools 'state-change))
            (emacsvox-aural-submission-module 'aural-tools)
            (emacsvox-aural-submission-occasion 'state-change))
        (emacsvox-icon 'open-object)))
    window))

(defun emacsvox-aural-ui-configure-tabulated
    (list-name row-speaker refresh-function
               &optional move-speaker after-move-function)
  "Configure the current spoken tabulated interface.

LIST-NAME is used in boundary announcements.  ROW-SPEAKER describes a whole
row, while MOVE-SPEAKER optionally provides a shorter movement announcement.
REFRESH-FUNCTION is invoked by the common refresh command.  AFTER-MOVE-FUNCTION
can record selection or perform other non-speaking bookkeeping."
  (emacsvox-aural-ui-register-interface)
  (setq-local emacsvox-aural-ui-list-name list-name)
  (setq-local emacsvox-aural-ui-row-speaker row-speaker)
  (setq-local emacsvox-aural-ui-refresh-function refresh-function)
  (setq-local emacsvox-aural-ui-move-speaker move-speaker)
  (setq-local emacsvox-aural-ui-after-move-function after-move-function))

(defun emacsvox-aural-ui-tabulated-column-index ()
  "Return the current tabulated column index, defaulting to the first."
  (let ((name
         (get-text-property
          (point) 'tabulated-list-column-name)))
    (or
     (and
      name
      (cl-position
       name tabulated-list-format
       :test #'string= :key #'car))
     0)))

(defun emacsvox-aural-ui-goto-tabulated-column (index)
  "Move to column INDEX on the current tabulated row."
  (let* ((last (1- (length tabulated-list-format)))
         (index (max 0 (min index last)))
         (name (and (>= last 0) (car (aref tabulated-list-format index))))
         (position (line-beginning-position))
         (limit (line-end-position))
         found)
    (while (and name (< position limit) (not found))
      (if
          (equal
           name
           (get-text-property
            position 'tabulated-list-column-name))
          (setq found position)
        (setq
         position
         (next-single-property-change
          position 'tabulated-list-column-name nil limit))))
    (when found
      (goto-char found))
    found))

(defun emacsvox-aural-ui-goto-row (id)
  "Move to tabulated row ID and its first column.

Comparison uses `equal' so compound row identifiers are supported."
  (let ((start (point-min))
        found)
    (goto-char start)
    (while (and (not found) (< (point) (point-max)))
      (if (equal id (tabulated-list-get-id))
          (setq found t)
        (forward-line 1)))
    (unless found
      (goto-char start))
    (when found
      (emacsvox-aural-ui-goto-tabulated-column 0))
    found))

(defun emacsvox-aural-ui--goto-first-row ()
  "Move to the first tabulated row, returning its identifier."
  (goto-char (point-min))
  (while
      (and
       (< (point) (point-max))
       (null (tabulated-list-get-id)))
    (forward-line 1))
  (when-let* ((id (tabulated-list-get-id)))
    (emacsvox-aural-ui-goto-tabulated-column 0)
    id))

(defun emacsvox-aural-ui--synchronize-window-points ()
  "Keep visible windows focused on the current interface position."
  (let ((position (point)))
    (dolist (window (get-buffer-window-list (current-buffer) nil t))
      (set-window-point window position))))

(defun emacsvox-aural-ui-refresh-tabulated
    (populate &optional preferred fallback after-print)
  "Refresh a tabulated interface while preserving selection and column.

POPULATE updates `tabulated-list-entries'.  PREFERRED overrides the current
row identifier; FALLBACK is used when neither is available.  AFTER-PRINT is
called after rendering and before restoring the row.  Return the selected row
identifier, or nil when the refreshed interface has no rows."
  (let* ((column (emacsvox-aural-ui-tabulated-column-index))
         (selected
          (or preferred (tabulated-list-get-id) fallback)))
    (funcall populate)
    (tabulated-list-print t)
    (when after-print
      (funcall after-print))
    (unless
        (and
         selected
         (emacsvox-aural-ui-goto-row selected))
      (setq selected (emacsvox-aural-ui--goto-first-row)))
    (when selected
      (emacsvox-aural-ui-goto-tabulated-column column))
    (emacsvox-aural-ui--synchronize-window-points)
    selected))

(defun emacsvox-aural-ui-tabulated-cell-description (&optional value-first)
  "Return the current tabulated cell as titled spoken text.

When VALUE-FIRST is non-nil, put the cell value before its column title."
  (let* ((entry
          (or
           (tabulated-list-get-entry)
           (user-error "Move to a tabulated row first")))
         (index (emacsvox-aural-ui-tabulated-column-index))
         (name (car (aref tabulated-list-format index)))
         (value (aref entry index))
         (value (if (listp value) (car value) value))
         (value (string-trim (format "%s" value))))
    (let ((value (if (string-empty-p value) "blank" value)))
      (if value-first
          (format "%s, %s" value name)
        (format "%s, %s" name value)))))

(defun emacsvox-aural-ui-speak (text)
  "Speak interface feedback TEXT through the current buffer's renderer."
  (cond
   (emacsvox-aural-ui-speech-function
    (funcall emacsvox-aural-ui-speech-function text))
   ((fboundp 'tts-speak)
    (tts-speak text))
   (t
    (message "%s" text)))
  text)

(defun emacsvox-aural-ui-speak-current-cell (&optional value-first)
  "Speak the current tabulated cell.

Speak its column title first by default.  When VALUE-FIRST is non-nil, speak
the cell value first."
  (interactive)
  (let ((description
         (emacsvox-aural-ui-tabulated-cell-description value-first)))
    (when (fboundp 'emacsvox-icon)
      (emacsvox-icon 'select-object))
    (emacsvox-aural-ui-speak description)
    description))

(defun emacsvox-aural-ui-speak-current-row ()
  "Speak the complete current row using its configured callback."
  (interactive)
  (funcall
   (or
    emacsvox-aural-ui-row-speaker
    #'emacsvox-aural-ui-speak-current-cell)))

(defun emacsvox-aural-ui-speak-name-and-state ()
  "Speak the current item's name and status independently of the selected column."
  (let* ((row (or (tabulated-list-get-entry)
                  (user-error "Move to an item first")))
         (name-index
          (or (cl-position "Rule" tabulated-list-format
                           :key #'car :test #'equal) 0))
         (state-index
          (cl-position-if
           (lambda (column) (member (car column) '("Status" "Current status" "State")))
           tabulated-list-format))
         (name (string-trim (format "%s" (aref row name-index))))
         (state (and state-index
                     (string-trim (format "%s" (aref row state-index))))))
    (emacsvox-aural-ui-speak
     (if state (format "%s: %s" name state) (format "%s" name)))))

(defun emacsvox-aural-ui-stop-preview ()
  "Stop the current preview and its remaining samples."
  (interactive)
  (require 'emacsvox-aural-preview)
  (emacsvox-aural-preview-stop)
  (emacsvox-aural-preview-message "Preview stopped"))

(defun emacsvox-aural-ui-action-candidates ()
  "Return labelled, applicable commands from this interface's actual bindings."
  (let ((map (current-local-map))
        (row (or (not (derived-mode-p 'tabulated-list-mode))
                 (tabulated-list-get-id)))
        (excluded '(emacsvox-aural-ui-actions emacsvox-aural-ui-next-row
                    emacsvox-aural-ui-previous-row emacsvox-aural-ui-next-column
                    emacsvox-aural-ui-previous-column emacsvox-aural-ui-speak-current-cell
                    emacsvox-aural-ui-speak-current-row
                    emacsvox-aural-editor-next-rule emacsvox-aural-editor-previous-rule))
        seen result)
    (while map
      (map-keymap
       (lambda (key command)
         (when (and (symbolp command) (commandp command)
                    (string-match-p "aural\\|omnivox" (symbol-name command))
                    (not (memq command excluded))
                    (not (memq key '(?n ?p ?\s ?. up down left right 14 16)))
                    (not (memq command seen))
                    (eq command (key-binding (vector key)))
                    (or emacsvox-aural-ui-action-filter row
                        (memq key '(?N ?g ?h ?q ?? ?S)))
                    (or (null emacsvox-aural-ui-action-filter)
                        (funcall emacsvox-aural-ui-action-filter command)))
           (push command seen)
           (push (cons (format "%s [%s]"
                               (car (split-string (or (documentation command)
                                                      (symbol-name command)) "\n"))
                               (key-description (vector key)))
                       command)
                 result)))
       map)
      (setq map (keymap-parent map)))
    (append emacsvox-aural-ui-extra-actions
            (sort result (lambda (a b) (string-lessp (car a) (car b)))))))

(defun emacsvox-aural-ui-announce-result (format-string &rest arguments)
  "Display and speak the result described by FORMAT-STRING and ARGUMENTS."
  (let ((text (apply #'format format-string arguments))
        (emacsvox-speak-messages nil))
    (message "%s" text)
    (emacsvox-aural-ui-speak text)))

(defun emacsvox-aural-ui-actions ()
  "Choose an available action by name."
  (interactive)
  (let* ((choices (emacsvox-aural-ui-action-candidates))
         (_ (unless choices (user-error "No actions are available here")))
         (answer (completing-read "Action: " choices nil 'require-match)))
    (call-interactively (cdr (assoc answer choices)))))

(defun emacsvox-aural-ui-announce-boundary (message)
  "Announce tabulated-list boundary MESSAGE."
  (when (fboundp 'emacsvox-icon)
    (emacsvox-icon 'warn-user))
  (emacsvox-aural-ui-speak message)
  message)

(defun emacsvox-aural-ui-move-row
    (direction &optional list-name speaker)
  "Move a tabulated row in DIRECTION and announce it.

LIST-NAME and SPEAKER override the current buffer's configured values."
  (let ((origin (point))
        (column (emacsvox-aural-ui-tabulated-column-index)))
    (beginning-of-line)
    (let ((residue (forward-line direction)))
      (if (and (zerop residue) (tabulated-list-get-id))
          (progn
            (emacsvox-aural-ui-goto-tabulated-column column)
            (if-let* ((move-speaker
                       (or speaker emacsvox-aural-ui-move-speaker)))
                (funcall move-speaker)
              (emacsvox-aural-ui-speak-current-cell t))
            (when emacsvox-aural-ui-after-move-function
              (funcall emacsvox-aural-ui-after-move-function))
            (emacsvox-aural-ui--synchronize-window-points)
            (tabulated-list-get-id))
        (goto-char origin)
        (emacsvox-aural-ui-announce-boundary
         (format
          "%s of %s."
          (if (> direction 0) "Bottom" "Top")
          (or list-name emacsvox-aural-ui-list-name "list")))
        nil))))

(defun emacsvox-aural-ui-next-row ()
  "Move to and speak the next row."
  (interactive)
  (emacsvox-aural-ui-move-row 1))

(defun emacsvox-aural-ui-previous-row ()
  "Move to and speak the previous row."
  (interactive)
  (emacsvox-aural-ui-move-row -1))

(defun emacsvox-aural-ui-move-column (direction)
  "Move a tabulated column in DIRECTION and speak its title and value."
  (let* ((index (emacsvox-aural-ui-tabulated-column-index))
         (last (1- (length tabulated-list-format)))
         (target (+ index direction)))
    (cond
     ((< target 0)
      (emacsvox-aural-ui-announce-boundary "First column."))
     ((> target last)
      (emacsvox-aural-ui-announce-boundary "Last column."))
     (t
      (emacsvox-aural-ui-goto-tabulated-column target)
      (emacsvox-aural-ui-speak-current-cell)))))

(defun emacsvox-aural-ui-next-column ()
  "Move right and speak the next column."
  (interactive)
  (emacsvox-aural-ui-move-column 1))

(defun emacsvox-aural-ui-previous-column ()
  "Move left and speak the previous column."
  (interactive)
  (emacsvox-aural-ui-move-column -1))

(defun emacsvox-aural-ui-refresh ()
  "Refresh the current interface using its configured callback."
  (interactive)
  (if emacsvox-aural-ui-refresh-function
      (funcall emacsvox-aural-ui-refresh-function)
    (revert-buffer)))

(defun emacsvox-aural-ui-refresh-home-if-live (&rest _ignored)
  "Refresh the aural home buffer when it is currently available."
  (when-let* ((buffer (get-buffer "*Emacsvox Aural*")))
    (with-current-buffer buffer
      (when (derived-mode-p 'emacsvox-aural-home-mode)
        (emacsvox-aural-home-refresh)))))

(defun emacsvox-aural-quit (&optional kill)
  "Dismiss the current aural interface and report its destination.

When KILL is non-nil, kill the interface buffer as `quit-window' would."
  (interactive)
  (unless (emacsvox-aural-ui-interface-buffer-p)
    (user-error "This is not an aural interface buffer"))
  (let ((warning
         (and emacsvox-aural-ui-dismiss-warning-function
              (funcall emacsvox-aural-ui-dismiss-warning-function)))
        (facts
         '(:role aural-interface :events (aural-interface-closed)))
        (context
         (emacsvox-aural-capture-context 'aural-tools 'state-change)))
    (prog1
        (quit-window kill)
      (let ((emacsvox-aural-submission-facts facts)
            (emacsvox-aural-submission-context context)
            (emacsvox-aural-submission-module 'aural-tools)
            (emacsvox-aural-submission-occasion 'state-change))
        (emacsvox-icon 'close-object)
        (emacsvox-speak-mode-line)
        (when warning
          (if (fboundp 'tts-speak)
              (tts-speak warning)
            (message "%s" warning)))))))

(defvar emacsvox-aural-interface-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    (define-key map (kbd "q") #'emacsvox-aural-quit)
    (define-key map (kbd "C-c C-a") #'emacsvox-aural-ui-actions)
    (define-key map (kbd "S") #'emacsvox-aural-ui-stop-preview)
    map)
  "Keymap inherited by non-tabulated aural interfaces.")

(define-derived-mode emacsvox-aural-interface-mode special-mode
  "Aural-Interface"
  "Base mode for non-tabulated aural interfaces."
  (emacsvox-aural-ui-register-interface))

(defvar emacsvox-aural-tabulated-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map tabulated-list-mode-map)
    (dolist
        (binding
         '(("n" . emacsvox-aural-ui-next-row)
           ("p" . emacsvox-aural-ui-previous-row)
           ("C-n" . emacsvox-aural-ui-next-row)
           ("C-p" . emacsvox-aural-ui-previous-row)
           ("<down>" . emacsvox-aural-ui-next-row)
           ("<up>" . emacsvox-aural-ui-previous-row)
           ("<right>" . emacsvox-aural-ui-next-column)
           ("<left>" . emacsvox-aural-ui-previous-column)
           ("." . emacsvox-aural-ui-speak-current-cell)
           ("SPC" . emacsvox-aural-ui-speak-current-row)
           ("g" . emacsvox-aural-ui-refresh)
           ("C-c C-a" . emacsvox-aural-ui-actions)
           ("S" . emacsvox-aural-ui-stop-preview)
           ("q" . emacsvox-aural-quit)))
      (define-key map (kbd (car binding)) (cdr binding)))
    map)
  "Keymap inherited by spoken tabulated aural interfaces.")

(define-derived-mode emacsvox-aural-tabulated-mode tabulated-list-mode
  "Aural-Tabulated"
  "Base mode for spoken tabulated aural interfaces."
  (emacsvox-aural-ui-register-interface))

(defalias 'emacsvox-aural-ui--announce-boundary
  #'emacsvox-aural-ui-announce-boundary)

(provide 'emacsvox-aural-ui)

;;; emacsvox-aural-ui.el ends here
