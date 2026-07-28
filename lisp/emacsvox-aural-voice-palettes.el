;;; emacsvox-aural-voice-palettes.el --- Spoken voice-palette manager -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Accessible management for inherited, data-safe ACSS voice palettes.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'tabulated-list)
(require 'emacsvox-aural-tools)

(declare-function emacsvox-speak-help "emacsvox-speak" ())
(declare-function tts-speak "tts-speak" (text))
(declare-function tts-voice-reset-code "tts-speak" ())
(declare-function tts--protocol-queue-code "tts-speak" (code))
(declare-function tts--protocol-queue-text "tts-speak" (text))
(declare-function tts--protocol-dispatch "tts-speak" ())

(defun emacsvox-aural-voice-palettes--active-id ()
  "Return the currently effective voice palette."
  (or
   emacsvox-aural-voice-palette-override
   (emacsvox-aural-effective-scheme-provider 'voice-palette)
   'acss-default))

(defun emacsvox-aural-voice-palettes-status ()
  "Return concise voice-palette status for Aural Home."
  (let ((active (emacsvox-aural-voice-palettes--active-id))
        (count (hash-table-count emacsvox-aural-voice-palette-registry)))
    (format
     "%s active; %d available%s"
     active count
     (if emacsvox-aural-voice-palette-override
         " (override)"
       " (from scheme)"))))

(defun emacsvox-aural-voice-palettes--ids ()
  "Return registered palette identifiers in display order."
  (mapcar #'intern (emacsvox-aural-voice-palette-candidates)))

(defun emacsvox-aural-voice-palettes--kind (palette)
  "Return a display kind for PALETTE."
  (if (emacsvox-aural-voice-palette-built-in palette)
      "built-in"
    "personal"))

(defun emacsvox-aural-voice-palettes--validation (id)
  "Return validation details for palette ID."
  (condition-case error
      (let ((missing (emacsvox-aural-validate-voice-palette id))
            (degradations
             (emacsvox-aural-voice-palette-capability-degradations id)))
        (list
         :valid (null missing)
         :missing missing
         :degradations degradations))
    (error
     (list :valid nil :errors (list (error-message-string error))))))

(defun emacsvox-aural-voice-palettes--validation-status (report)
  "Return concise status for palette validation REPORT."
  (cond
   ((plist-get report :errors) "invalid")
   ((plist-get report :missing)
    (format "%d unavailable" (length (plist-get report :missing))))
   ((plist-get report :degradations)
    (format "%d fallbacks" (length (plist-get report :degradations))))
   (t "valid")))

(defun emacsvox-aural-voice-palettes--row (id)
  "Return one tabulated manager row for palette ID."
  (let* ((palette (emacsvox-aural-voice-palette id))
         (direct (length (emacsvox-aural-voice-palette-entries palette)))
         (effective (length (emacsvox-aural-effective-voice-entries id)))
         (report (emacsvox-aural-voice-palettes--validation id)))
    (list
     id
     (vector
      (symbol-name id)
      (if (eq id (emacsvox-aural-voice-palettes--active-id))
          "active"
        "")
      (emacsvox-aural-voice-palettes--kind palette)
      (if-let* ((parent (emacsvox-aural-voice-palette-parent palette)))
          (symbol-name parent)
        "")
      (format "%d" direct)
      (format "%d" effective)
      (symbol-name
       (plist-get
        (emacsvox-aural-active-voice-capabilities) :adapter))
      (emacsvox-aural-voice-palettes--validation-status report)
      (emacsvox-aural-voice-palette-summary palette)))))

(defun emacsvox-aural-voice-palettes--set-entries ()
  "Populate the voice-palette manager."
  (setq
   tabulated-list-entries
   (mapcar
    #'emacsvox-aural-voice-palettes--row
    (emacsvox-aural-voice-palettes--ids))))

(defun emacsvox-aural-voice-palettes--goto (id)
  "Move to palette ID and its first column."
  (goto-char (point-min))
  (while (and (< (point) (point-max))
              (not (eq id (tabulated-list-get-id))))
    (forward-line 1))
  (when (eq id (tabulated-list-get-id))
    (emacsvox-aural-tools--goto-tabulated-column 0)
    t))

(defun emacsvox-aural-voice-palettes-refresh (&optional id)
  "Refresh palettes while preserving ID and the current column."
  (interactive)
  (let ((column (emacsvox-aural-tools--tabulated-column-index))
        (selected
         (or id
             (tabulated-list-get-id)
             (emacsvox-aural-voice-palettes--active-id))))
    (emacsvox-aural-voice-palettes--set-entries)
    (tabulated-list-print t)
    (if selected
        (emacsvox-aural-voice-palettes--goto selected)
      (goto-char (point-min)))
    (emacsvox-aural-tools--goto-tabulated-column column)))

(defun emacsvox-aural-voice-palettes--at-point-or-read (&optional prompt)
  "Return the palette at point, or read one using PROMPT."
  (or
   (tabulated-list-get-id)
   (intern
    (completing-read
     (or prompt "Voice palette: ")
     (emacsvox-aural-voice-palette-candidates)
     nil 'must-match))))

(defun emacsvox-aural-voice-palettes--read-new-id (&optional initial)
  "Read a new personal palette identifier, offering INITIAL."
  (let* ((text
          (string-trim
           (read-string "New voice palette name: " initial)))
         (id (intern text)))
    (when
        (or
         (string-empty-p text)
         (keywordp id)
         (memq id '(nil t)))
      (user-error "Use a non-keyword voice palette name"))
    (when (emacsvox-aural-voice-palette id)
      (user-error "Voice palette already exists: %s" id))
    id))

(defun emacsvox-aural-voice-palettes--parent-candidates (&optional exclude)
  "Return palette candidates, omitting EXCLUDE."
  (cons
   "none"
   (cl-remove
    (and exclude (symbol-name exclude))
    (emacsvox-aural-voice-palette-candidates)
    :test #'equal)))

(defun emacsvox-aural-voice-palettes--read-parent (&optional current exclude)
  "Read a parent palette, offering CURRENT and omitting EXCLUDE."
  (let ((answer
         (completing-read
          "Parent palette: "
          (emacsvox-aural-voice-palettes--parent-candidates exclude)
          nil 'must-match nil nil
          (if current (symbol-name current) "acss-default"))))
    (unless (equal answer "none") (intern answer))))

(defun emacsvox-aural-voice-palettes--install-data (data &optional old-id)
  "Atomically install personal palette DATA, replacing OLD-ID when non-nil."
  (let ((registry
         (copy-hash-table emacsvox-aural-voice-palette-registry))
        record)
    (when old-id
      (remhash old-id registry))
    (let ((emacsvox-aural-voice-palette-registry registry))
      (setq
       record
       (emacsvox-aural-compile-voice-palette-data
        data nil emacsvox-aural-schemes-file))
      (let ((id (emacsvox-aural-voice-palette-id record)))
        (when (gethash id registry)
          (user-error "Voice palette already exists: %s" id))
        (puthash id record registry)
        (maphash
         (lambda (palette-id _)
           (emacsvox-aural-effective-voice-entries palette-id))
         registry)
        (emacsvox-aural-save-user-data)))
    (setq emacsvox-aural-voice-palette-registry registry)
    (emacsvox-aural-home-refresh-if-live)
    record))

(defun emacsvox-aural-voice-palettes--replace-entries (data entries)
  "Return palette DATA with direct ENTRIES."
  (plist-put (copy-tree data) :entries (copy-tree entries)))

(defun emacsvox-aural-voice-palettes--entry-data
    (name definition)
  "Return safe entry data for NAME and DEFINITION."
  (if (symbolp definition)
      (list name :personality definition)
    (list name :style (copy-tree definition))))

(defun emacsvox-aural-voice-palettes--direct-entry (data name)
  "Return direct entry named NAME in palette DATA."
  (cl-find name (plist-get data :entries) :key #'car :test #'eq))

(defun emacsvox-aural-voice-palettes--put-entry (data entry)
  "Return palette DATA with direct ENTRY inserted or replaced."
  (let* ((name (car entry))
         (entries
          (cl-remove name (plist-get data :entries)
                     :key #'car :test #'eq)))
    (emacsvox-aural-voice-palettes--replace-entries
     data (append entries (list entry)))))

(defun emacsvox-aural-voice-palettes--read-entry-name (id)
  "Read a voice entry name for palette ID, permitting a new name."
  (let* ((entries (emacsvox-aural-effective-voice-entries id))
         (answer
          (string-trim
           (completing-read
            "Voice name to edit or create: "
            (mapcar (lambda (entry) (symbol-name (car entry))) entries))))
         (name (intern answer)))
    (when
        (or (string-empty-p answer) (keywordp name) (memq name '(nil t)))
      (user-error "Use a non-keyword voice name"))
    name))

(defun emacsvox-aural-voice-palettes--personality-candidates ()
  "Return known compatibility personality names."
  (let ((names
         (mapcar
          (lambda (entry) (symbol-name (cdr entry)))
          emacsvox-aural-default-voice-entries)))
    (dolist
        (symbol
         (apropos-internal "\\`voice-" #'boundp))
      (unless (string-suffix-p "-settings" (symbol-name symbol))
        (push (symbol-name symbol) names)))
    (sort (delete-dups names) #'string-lessp)))

(defun emacsvox-aural-voice-palettes--read-style-number
    (dimension current)
  "Read optional ACSS DIMENSION, offering CURRENT."
  (let* ((prompt
          (format
           "%s, 0 through 9; blank means default%s: "
           (emacsvox-aural-tools--humanize dimension)
           (if current (format " [%s]" current) "")))
         (answer (string-trim (read-string prompt))))
    (cond
     ((and (string-empty-p answer) current) current)
     ((string-empty-p answer) nil)
     ((not (string-match-p "\\`[0-9]\\'" answer))
      (user-error "%s must be 0 through 9 or blank" dimension))
     (t (string-to-number answer)))))

(defun emacsvox-aural-voice-palettes--read-style (&optional current)
  "Read a complete ACSS style, offering CURRENT values."
  (let* ((old-family (plist-get current :family))
         (family-text
          (string-trim
           (read-string
            (format
             "Voice family; blank means default%s: "
             (if old-family (format " [%s]" old-family) ""))
            nil nil
            (and old-family (format "%s" old-family)))))
         (style
          (list
           :family
           (unless (string-empty-p family-text)
             (intern family-text)))))
    (dolist (dimension '(average-pitch pitch-range stress richness))
      (setq
       style
       (plist-put
        style
        (emacsvox-aural--voice-dimension-key dimension)
        (emacsvox-aural-voice-palettes--read-style-number
         dimension
         (plist-get
          current
          (emacsvox-aural--voice-dimension-key dimension))))))
    style))

(defun emacsvox-aural-voice-palettes--read-definition (&optional current)
  "Read a complete voice definition, offering CURRENT."
  (let* ((default (if (symbolp current) "personality" "custom ACSS"))
         (kind
          (completing-read
           "Voice definition kind: "
           '("personality" "custom ACSS")
           nil 'must-match nil nil default)))
    (if (equal kind "personality")
        (intern
         (completing-read
          "Existing personality: "
          (emacsvox-aural-voice-palettes--personality-candidates)
          nil 'must-match nil nil
          (and (symbolp current) (symbol-name current))))
      (emacsvox-aural-voice-palettes--read-style
       (and (listp current) current)))))

(defun emacsvox-aural-voice-palettes-speak-current ()
  "Speak the complete voice-palette row at point."
  (interactive)
  (let* ((id (emacsvox-aural-voice-palettes--at-point-or-read))
         (palette (emacsvox-aural-voice-palette id))
         (report (emacsvox-aural-voice-palettes--validation id))
         (summary
          (format
           "%s. %s. %s. Parent %s. %d direct voices, %d effective. %s. %s"
           (emacsvox-aural-tools--humanize id)
           (if (eq id (emacsvox-aural-voice-palettes--active-id))
               "active"
             "inactive")
           (emacsvox-aural-voice-palettes--kind palette)
           (or (emacsvox-aural-voice-palette-parent palette) "none")
           (length (emacsvox-aural-voice-palette-entries palette))
           (length (emacsvox-aural-effective-voice-entries id))
           (emacsvox-aural-voice-palettes--validation-status report)
           (emacsvox-aural-voice-palette-summary palette))))
    (if (fboundp 'tts-speak)
        (tts-speak summary)
      (message "%s" summary))
    summary))

(defun emacsvox-aural-voice-palettes-speak-current-cell ()
  "Speak the current palette column title and value."
  (interactive)
  (emacsvox-aural-tools--speak-tabulated-cell))

(defun emacsvox-aural-voice-palettes-next ()
  "Move to and speak the next voice palette."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-row 1 "voice palettes"))

(defun emacsvox-aural-voice-palettes-previous ()
  "Move to and speak the previous voice palette."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-row -1 "voice palettes"))

(defun emacsvox-aural-voice-palettes-next-column ()
  "Move right and speak the next palette column."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-column 1))

(defun emacsvox-aural-voice-palettes-previous-column ()
  "Move left and speak the previous palette column."
  (interactive)
  (emacsvox-aural-tools--move-tabulated-column -1))

(defun emacsvox-aural-voice-palettes-describe (&optional id)
  "Display and speak the effective voices in palette ID."
  (interactive)
  (let* ((id (or id (emacsvox-aural-voice-palettes--at-point-or-read)))
         (palette (emacsvox-aural-voice-palette id))
         (direct (emacsvox-aural-voice-palette-entries palette))
         (report (emacsvox-aural-voice-palettes--validation id)))
    (with-help-window (help-buffer)
      (princ (format "Voice palette: %s\n\n" id))
      (princ (format "Summary: %s\n"
                     (emacsvox-aural-voice-palette-summary palette)))
      (princ (format "Kind: %s\n"
                     (emacsvox-aural-voice-palettes--kind palette)))
      (princ (format "Parent: %s\n"
                     (or (emacsvox-aural-voice-palette-parent palette)
                         "none")))
      (princ
       (format
        "Active adapter: %s\n"
        (plist-get (emacsvox-aural-active-voice-capabilities) :adapter)))
      (princ
       (format
        "Validation: %s\n\n"
        (emacsvox-aural-voice-palettes--validation-status report)))
      (princ "Effective voices\n\n")
      (dolist (entry (emacsvox-aural-effective-voice-entries id))
        (princ
         (format
          "%s%s: %S\n"
          (car entry)
          (if (assq (car entry) direct) "" " (inherited)")
          (cdr entry))))
      (when-let* ((missing (plist-get report :missing)))
        (princ (format "\nUnavailable personalities: %S\n" missing)))
      (when-let* ((fallbacks (plist-get report :degradations)))
        (princ "\nAdapter fallbacks\n\n")
        (dolist (fallback fallbacks)
          (princ
           (format
            "%s: %s %S is unsupported by %s\n"
            (plist-get fallback :voice)
            (plist-get fallback :dimension)
            (plist-get fallback :requested)
            (plist-get fallback :adapter))))))
    (when (called-interactively-p 'interactive)
      (emacsvox-aural-voice-palettes-speak-current))
    report))

(defun emacsvox-aural-voice-palettes-create ()
  "Create an empty personal voice palette."
  (interactive)
  (let* ((id (emacsvox-aural-voice-palettes--read-new-id))
         (summary
          (read-string
           "Palette purpose: "
           (format "Personal voice palette %s" id)))
         (parent (emacsvox-aural-voice-palettes--read-parent))
         (data
          (list
           :schema-version emacsvox-aural-voice-palette-schema-version
           :id id
           :summary summary
           :parent parent
           :entries nil)))
    (emacsvox-aural-voice-palettes--install-data data)
    (emacsvox-aural-voice-palettes-refresh id)
    (emacsvox-aural-voice-palettes-speak-current)
    id))

(defun emacsvox-aural-voice-palettes-copy ()
  "Copy the voice palette at point to a personal palette."
  (interactive)
  (let* ((source (emacsvox-aural-voice-palettes--at-point-or-read))
         (source-palette (emacsvox-aural-voice-palette source))
         (id
          (emacsvox-aural-voice-palettes--read-new-id
           (format "%s-copy" source)))
         (data
          (emacsvox-aural-voice-palette-data-form source-palette)))
    (setq data (plist-put data :id id))
    (setq
     data
     (plist-put
      data :summary
      (read-string
       "Copied palette purpose: "
       (format "Editable copy of %s" source))))
    (emacsvox-aural-voice-palettes--install-data data)
    (emacsvox-aural-voice-palettes-refresh id)
    (emacsvox-aural-voice-palettes-speak-current)
    id))

(defun emacsvox-aural-voice-palettes-edit-entry ()
  "Create or replace one direct voice entry in the personal palette at point."
  (interactive)
  (let* ((id (emacsvox-aural-voice-palettes--at-point-or-read))
         (palette (emacsvox-aural-voice-palette id)))
    (when (emacsvox-aural-voice-palette-built-in palette)
      (user-error "Copy the built-in palette first, then edit the copy"))
    (let* ((data (emacsvox-aural-voice-palette-data-form palette))
           (name (emacsvox-aural-voice-palettes--read-entry-name id))
           (direct (emacsvox-aural-voice-palettes--direct-entry data name))
           (current
            (if direct
                (or
                 (plist-get (cdr direct) :personality)
                 (plist-get (cdr direct) :style))
              (emacsvox-aural-voice name id)))
           (definition
            (emacsvox-aural-voice-palettes--read-definition current))
           (updated
            (emacsvox-aural-voice-palettes--put-entry
             data
             (emacsvox-aural-voice-palettes--entry-data
              name definition))))
      (emacsvox-aural-voice-palettes--install-data updated id)
      (emacsvox-aural-voice-palettes-refresh id)
      (message "Saved voice %s in palette %s" name id)
      name)))

(defun emacsvox-aural-voice-palettes-edit-metadata ()
  "Edit summary and parent of the personal palette at point."
  (interactive)
  (let* ((id (emacsvox-aural-voice-palettes--at-point-or-read))
         (palette (emacsvox-aural-voice-palette id)))
    (when (emacsvox-aural-voice-palette-built-in palette)
      (user-error "Copy the built-in palette first, then edit the copy"))
    (let* ((data (emacsvox-aural-voice-palette-data-form palette))
           (summary
            (read-string
             "Palette purpose: "
             (emacsvox-aural-voice-palette-summary palette)))
           (parent
            (emacsvox-aural-voice-palettes--read-parent
             (emacsvox-aural-voice-palette-parent palette) id)))
      (setq data (plist-put data :summary summary))
      (setq data (plist-put data :parent parent))
      (emacsvox-aural-voice-palettes--install-data data id)
      (emacsvox-aural-voice-palettes-refresh id)
      (emacsvox-aural-voice-palettes-speak-current)
      id)))

(defun emacsvox-aural-voice-palettes-delete-entry ()
  "Delete one direct entry from the personal palette at point."
  (interactive)
  (let* ((id (emacsvox-aural-voice-palettes--at-point-or-read))
         (palette (emacsvox-aural-voice-palette id)))
    (when (emacsvox-aural-voice-palette-built-in palette)
      (user-error "Built-in voice entries cannot be deleted"))
    (let* ((data (emacsvox-aural-voice-palette-data-form palette))
           (entries (plist-get data :entries))
           (_ (unless entries (user-error "This palette has no direct voices")))
           (name
            (intern
             (completing-read
              "Delete direct voice: "
              (mapcar
               (lambda (entry) (symbol-name (car entry)))
               entries)
              nil 'must-match)))
           (updated
            (emacsvox-aural-voice-palettes--replace-entries
             data
             (cl-remove name entries :key #'car :test #'eq))))
      (unless (yes-or-no-p
               (format "Delete voice %s from palette %s? " name id))
        (user-error "Deletion cancelled"))
      (emacsvox-aural-voice-palettes--install-data updated id)
      (emacsvox-aural-voice-palettes-refresh id)
      name)))

(defun emacsvox-aural-voice-palettes--dependents (id)
  "Return direct palette children of ID."
  (let (children)
    (maphash
     (lambda (candidate palette)
       (when (eq id (emacsvox-aural-voice-palette-parent palette))
         (push candidate children)))
     emacsvox-aural-voice-palette-registry)
    children))

(defun emacsvox-aural-voice-palettes--references (id)
  "Return scheme and profile references to palette ID."
  (let (references)
    (maphash
     (lambda (scheme entry)
       (when
           (eq
            id
            (plist-get
             (emacsvox-aural-scheme-entry-data entry) :voice-palette))
         (push (format "scheme %s" scheme) references)))
     emacsvox-aural-scheme-registry)
    (maphash
     (lambda (profile entry)
       (when
           (eq
            id
            (plist-get
             (emacsvox-aural-profile-entry-data entry) :voice-palette))
         (push (format "profile %s" profile) references)))
     emacsvox-aural-profile-registry)
    references))

(defun emacsvox-aural-voice-palettes-delete ()
  "Delete the personal voice palette at point when it is unreferenced."
  (interactive)
  (let* ((id (emacsvox-aural-voice-palettes--at-point-or-read))
         (palette (emacsvox-aural-voice-palette id))
         (children (emacsvox-aural-voice-palettes--dependents id))
         (references (emacsvox-aural-voice-palettes--references id)))
    (when (emacsvox-aural-voice-palette-built-in palette)
      (user-error "Built-in voice palettes cannot be deleted"))
    (when children
      (user-error
       "Cannot delete %s; inherited by %s"
       id (mapconcat #'symbol-name children ", ")))
    (when references
      (user-error
       "Cannot delete %s; used by %s"
       id (string-join references ", ")))
    (unless (yes-or-no-p (format "Delete voice palette %s? " id))
      (user-error "Deletion cancelled"))
    (let ((registry
           (copy-hash-table emacsvox-aural-voice-palette-registry)))
      (remhash id registry)
      (let ((emacsvox-aural-voice-palette-registry registry))
        (emacsvox-aural-save-user-data))
      (setq emacsvox-aural-voice-palette-registry registry))
    (when (eq id emacsvox-aural-voice-palette-override)
      (emacsvox-aural-select-voice-palette nil))
    (emacsvox-aural-voice-palettes-refresh)
    (emacsvox-aural-home-refresh-if-live)
    id))

(defun emacsvox-aural-voice-palettes-activate ()
  "Activate the voice palette at point as an override."
  (interactive)
  (let ((id (emacsvox-aural-voice-palettes--at-point-or-read)))
    (emacsvox-aural-select-voice-palette id)
    (emacsvox-aural-voice-palettes-refresh id)
    (emacsvox-aural-home-refresh-if-live)
    (emacsvox-aural-voice-palettes-speak-current)
    id))

(defun emacsvox-aural-voice-palettes-follow-scheme ()
  "Clear the palette override and follow the active scheme."
  (interactive)
  (emacsvox-aural-select-voice-palette nil)
  (emacsvox-aural-voice-palettes-refresh
   (emacsvox-aural-voice-palettes--active-id))
  (emacsvox-aural-home-refresh-if-live)
  (emacsvox-aural-voice-palettes-speak-current))

(defun emacsvox-aural-voice-palettes--read-voice (id &optional prompt)
  "Read an effective voice from palette ID using PROMPT."
  (intern
   (completing-read
    (or prompt "Voice to preview: ")
    (mapcar
     (lambda (entry) (symbol-name (car entry)))
     (emacsvox-aural-effective-voice-entries id))
    nil 'must-match)))

(defun emacsvox-aural-voice-palettes-preview ()
  "Preview one named voice from the palette at point."
  (interactive)
  (let* ((id (emacsvox-aural-voice-palettes--at-point-or-read))
         (voice (emacsvox-aural-voice-palettes--read-voice id))
         (text (read-string "Preview text: " "This is a voice preview."))
         (compiled (emacsvox-aural-compile-voice-style voice id))
         (command (emacsvox-aural-compiled-voice-command compiled)))
    (when (eq command 'inaudible)
      (user-error "The selected voice suppresses speech"))
    (emacsvox-aural--ensure-speaker)
    (tts--protocol-queue-code (tts-voice-reset-code))
    (when command
      (tts--protocol-queue-code command))
    (tts--protocol-queue-text text)
    (tts--protocol-queue-code (tts-voice-reset-code))
    (tts--protocol-dispatch)
    compiled))

(defun emacsvox-aural-voice-palettes-explain ()
  "Explain one effective voice and its adapter fallback."
  (interactive)
  (let* ((id (emacsvox-aural-voice-palettes--at-point-or-read))
         (voice (emacsvox-aural-voice-palettes--read-voice
                 id "Voice to explain: "))
         (definition (emacsvox-aural-voice voice id))
         (compiled (emacsvox-aural-compile-voice-style voice id))
         (capability (emacsvox-aural-compiled-voice-capability compiled))
         (degradations
          (emacsvox-aural-compiled-voice-degradations compiled))
         (summary
          (format
           "%s in %s. Requested %S. Effective style %S. Adapter %s. %s"
           voice id definition
           (emacsvox-aural-compiled-voice-style compiled)
           (plist-get capability :adapter)
           (if degradations
               (format "%d fallback%s"
                       (length degradations)
                       (if (= (length degradations) 1) "" "s"))
             "No fallback"))))
    (with-help-window (help-buffer)
      (princ (format "Voice: %s\nPalette: %s\n\n" voice id))
      (princ (format "Requested preset: %S\n" definition))
      (princ
       (format
        "Effective ACSS: %S\n"
        (emacsvox-aural-compiled-voice-style compiled)))
      (princ
       (format
        "Adapter capability: %S\n"
        capability))
      (princ
       (format
        "Dimension provenance: %S\n"
        (emacsvox-aural-compiled-voice-provenance compiled)))
      (if degradations
          (progn
            (princ "\nFallbacks\n\n")
            (dolist (degradation degradations)
              (princ (format "%S\n" degradation))))
        (princ "\nNo adapter fallback was required.\n")))
    (if (fboundp 'tts-speak)
        (tts-speak summary)
      (message "%s" summary))
    compiled))

(defun emacsvox-aural-voice-palettes-help ()
  "Display and speak voice-palette manager help."
  (interactive)
  (with-help-window (help-buffer)
    (princ
     (concat
      "Aural Voice Palettes\n\n"
      "A named voice is a complete preset. A rule may layer explicit ACSS\n"
      "dimensions over that preset. Custom named presets therefore ask for\n"
      "all five dimensions; blank values mean the adapter default.\n\n"
      "n or down next       p or up previous\n"
      "left/right column    . speak titled cell\n"
      "RET view voices      SPC speak palette\n"
      "a activate override  f follow active scheme\n"
      "N create             c copy\n"
      "e edit voice         E edit summary and parent\n"
      "D delete voice       d delete palette\n"
      "P preview voice      x explain voice\n"
      "v view and validate  g refresh\n"
      "h aural home         q quit\n")))
  (when (fboundp 'emacsvox-speak-help)
    (emacsvox-speak-help)))

(define-derived-mode
    emacsvox-aural-voice-palettes-mode tabulated-list-mode
  "Aural-Voice-Palettes"
  "Spoken manager for inherited ACSS voice palettes."
  (setq
   tabulated-list-format
   [("Palette" 24 t)
    ("Status" 10 t)
    ("Kind" 10 t)
    ("Parent" 20 t)
    ("Direct" 8 t)
    ("Effective" 10 t)
    ("Adapter" 12 t)
    ("Validation" 16 t)
    ("Purpose" 0 t)])
  (setq tabulated-list-padding 2)
  (add-hook
   'tabulated-list-revert-hook
   #'emacsvox-aural-voice-palettes--set-entries nil t)
  (tabulated-list-init-header))

(dolist
    (binding
     '(("RET" . emacsvox-aural-voice-palettes-describe)
       ("SPC" . emacsvox-aural-voice-palettes-speak-current)
       ("." . emacsvox-aural-voice-palettes-speak-current-cell)
       ("n" . emacsvox-aural-voice-palettes-next)
       ("p" . emacsvox-aural-voice-palettes-previous)
       ("<down>" . emacsvox-aural-voice-palettes-next)
       ("<up>" . emacsvox-aural-voice-palettes-previous)
       ("<right>" . emacsvox-aural-voice-palettes-next-column)
       ("<left>" . emacsvox-aural-voice-palettes-previous-column)
       ("a" . emacsvox-aural-voice-palettes-activate)
       ("f" . emacsvox-aural-voice-palettes-follow-scheme)
       ("N" . emacsvox-aural-voice-palettes-create)
       ("c" . emacsvox-aural-voice-palettes-copy)
       ("e" . emacsvox-aural-voice-palettes-edit-entry)
       ("E" . emacsvox-aural-voice-palettes-edit-metadata)
       ("D" . emacsvox-aural-voice-palettes-delete-entry)
       ("d" . emacsvox-aural-voice-palettes-delete)
       ("P" . emacsvox-aural-voice-palettes-preview)
       ("x" . emacsvox-aural-voice-palettes-explain)
       ("v" . emacsvox-aural-voice-palettes-describe)
       ("g" . emacsvox-aural-voice-palettes-refresh)
       ("h" . emacsvox-aural)
       ("q" . emacsvox-aural-quit)
       ("?" . emacsvox-aural-voice-palettes-help)))
  (define-key
   emacsvox-aural-voice-palettes-mode-map
   (kbd (car binding))
   (cdr binding)))

;;;###autoload
(defun emacsvox-aural-list-voice-palettes (&optional palette)
  "Open the spoken manager for voice PALETTE providers."
  (interactive)
  (emacsvox-aural-tools--remember-source-buffer)
  (let ((buffer (get-buffer-create "*Aural Voice Palettes*")))
    (with-current-buffer buffer
      (emacsvox-aural-voice-palettes-mode)
      (emacsvox-aural-voice-palettes-refresh
       (or palette (emacsvox-aural-voice-palettes--active-id))))
    (pop-to-buffer buffer)
    (when (called-interactively-p 'interactive)
      (emacsvox-aural-voice-palettes-speak-current))
    buffer))

(provide 'emacsvox-aural-voice-palettes)
;;; emacsvox-aural-voice-palettes.el ends here
