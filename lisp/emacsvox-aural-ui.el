;;; emacsvox-aural-ui.el --- Shared accessible aural interfaces -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; Author: Emacsvox contributors
;; Keywords: accessibility, multimedia

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

(declare-function emacsvox-aural-capture-context
                  "emacsvox-aural-transport"
                  (&optional module occasion))
(declare-function emacsvox-icon "emacsvox-sounds" (icon))
(declare-function emacsvox-speak-mode-line
                  "emacsvox-speak"
                  (&optional buffer-info))
(declare-function tts-speak "tts-speak" (text))

(defvar-local emacsvox-aural-ui-interface-buffer nil
  "Non-nil when the current buffer is an aural interface.")

(defvar-local emacsvox-aural-ui-source-buffer nil
  "Ordinary buffer from which the current aural interface was opened.")

(defvar-local emacsvox-aural-ui-list-name "list"
  "Spoken name of the current tabulated interface.")

(defvar-local emacsvox-aural-ui-row-speaker nil
  "Function that speaks the complete current row.")

(defvar-local emacsvox-aural-ui-move-speaker nil
  "Function called after moving to another row.

When nil, movement speaks the current titled cell.")

(defvar-local emacsvox-aural-ui-after-move-function nil
  "Function called after successful row movement.")

(defvar-local emacsvox-aural-ui-refresh-function nil
  "Interactive function that refreshes the current interface.")

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

(defun emacsvox-aural-ui-tabulated-cell-description ()
  "Return the current tabulated cell as titled spoken text."
  (let* ((entry
          (or
           (tabulated-list-get-entry)
           (user-error "Move to a tabulated row first")))
         (index (emacsvox-aural-ui-tabulated-column-index))
         (name (car (aref tabulated-list-format index)))
         (value (aref entry index))
         (value (if (listp value) (car value) value))
         (value (string-trim (format "%s" value))))
    (format
     "%s, %s"
     name
     (if (string-empty-p value) "blank" value))))

(defun emacsvox-aural-ui-speak-current-cell ()
  "Speak the current tabulated column title and value."
  (interactive)
  (let ((description
         (emacsvox-aural-ui-tabulated-cell-description)))
    (when (fboundp 'emacsvox-icon)
      (emacsvox-icon 'select-object))
    (if (fboundp 'tts-speak)
        (tts-speak description)
      (message "%s" description))
    description))

(defun emacsvox-aural-ui-speak-current-row ()
  "Speak the complete current row using its configured callback."
  (interactive)
  (funcall
   (or
    emacsvox-aural-ui-row-speaker
    #'emacsvox-aural-ui-speak-current-cell)))

(defun emacsvox-aural-ui--announce-boundary (message)
  "Announce tabulated-list boundary MESSAGE."
  (when (fboundp 'emacsvox-icon)
    (emacsvox-icon 'warn-user))
  (if (fboundp 'tts-speak)
      (tts-speak message)
    (message "%s" message))
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
            (funcall
             (or
              speaker
              emacsvox-aural-ui-move-speaker
              #'emacsvox-aural-ui-speak-current-cell))
            (when emacsvox-aural-ui-after-move-function
              (funcall emacsvox-aural-ui-after-move-function))
            (emacsvox-aural-ui--synchronize-window-points)
            (tabulated-list-get-id))
        (goto-char origin)
        (emacsvox-aural-ui--announce-boundary
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
      (emacsvox-aural-ui--announce-boundary "First column."))
     ((> target last)
      (emacsvox-aural-ui--announce-boundary "Last column."))
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

(defun emacsvox-aural-quit (&optional kill)
  "Dismiss the current aural interface and report its destination.

When KILL is non-nil, kill the interface buffer as `quit-window' would."
  (interactive)
  (unless (emacsvox-aural-ui-interface-buffer-p)
    (user-error "This is not an aural interface buffer"))
  (let ((facts
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
        (emacsvox-speak-mode-line)))))

(defvar emacsvox-aural-interface-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    (define-key map (kbd "q") #'emacsvox-aural-quit)
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
           ("q" . emacsvox-aural-quit)))
      (define-key map (kbd (car binding)) (cdr binding)))
    map)
  "Keymap inherited by spoken tabulated aural interfaces.")

(define-derived-mode emacsvox-aural-tabulated-mode tabulated-list-mode
  "Aural-Tabulated"
  "Base mode for spoken tabulated aural interfaces."
  (emacsvox-aural-ui-register-interface))

(provide 'emacsvox-aural-ui)

;;; emacsvox-aural-ui.el ends here
