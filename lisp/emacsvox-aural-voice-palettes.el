;;; emacsvox-aural-voice-palettes.el --- Spoken voice-palette manager -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Accessible management for inherited, data-safe ACSS voice palettes.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'tabulated-list)
(require 'emacsvox-aural-schemes)
(require 'emacsvox-aural-ui)
(require 'emacsvox-aural-inspection)
(require 'emacsvox-aural-description)
(require 'emacsvox-aural-preview)

(declare-function emacsvox-speak-help "emacsvox-speak" ())
(declare-function tts-speak "tts-speak" (text))
(declare-function tts-voice-reset-code "tts-speak" ())
(declare-function tts--protocol-queue-code "tts-speak" (code))
(declare-function tts--protocol-queue-text "tts-speak" (text))
(declare-function tts-preview-voice "tts-speak"
                  (text selector &rest arguments))
(declare-function tts-voice-family-capability
                  "tts-speak" (family &optional capabilities))
(declare-function tts-voice-family-id
                  "tts-speak" (family &optional capabilities))

(defcustom emacsvox-aural-voice-palettes-preview-text
  "The quick brown fox jumps over the lazy dog. Numbers one, two, three."
  "Comparison text used when auditioning voices from a palette."
  :type 'string
  :group 'emacsvox-aural)

(defvar emacsvox-aural-voice-palettes--last-preview-voices
  (make-hash-table :test #'eq)
  "Most recently selected preview voice for each palette.")

(defvar-local emacsvox-aural-voice-palette-previews-palette nil
  "Voice palette shown in the current preview buffer.")

(defvar-local emacsvox-aural-voice-palette-previews-entries nil
  "Effective voice entries shown in the current preview buffer.")

(defvar-local emacsvox-aural-voice-palette-previews-text nil
  "Comparison text used by the current preview buffer.")

(defconst emacsvox-aural-voice-tuner--dimension-descriptions
  '((family . "Portable or synth-specific ACSS family; a physical route takes precedence")
    (average-pitch . "Overall pitch from zero through nine")
    (pitch-range . "Pitch variation from zero through nine")
    (stress . "Word emphasis from zero through nine")
    (richness . "Spectral richness from zero through nine")
    (rate . "Speech rate from zero through nine")
    (gain . "Post-synthesis gain; five is neutral")
    (low-pass . "Low-pass cutoff; higher values retain more high frequencies")
    (high-pass . "High-pass cutoff; higher values remove more low frequencies")
    (pan . "Stereo position; zero is left, five centre, and nine right")
    (reverb . "Post-synthesis reverberation from zero through nine")
    (echo . "Post-synthesis echo from zero through nine"))
  "Spoken descriptions of tunable voice dimensions.")

(defvar-local emacsvox-aural-voice-tuner-palette nil
  "Personal palette containing the voice being tuned.")

(defvar-local emacsvox-aural-voice-tuner-voice nil
  "Voice name represented by the current tuner.")

(defvar-local emacsvox-aural-voice-tuner-original-definition nil
  "Persisted voice definition from which the tuner started.")

(defvar-local emacsvox-aural-voice-tuner-initial-style nil
  "Complete ACSS working style from which tuning started.")

(defvar-local emacsvox-aural-voice-tuner-working-style nil
  "Complete unsaved ACSS style currently being auditioned.")

(defvar-local emacsvox-aural-voice-tuner-history nil
  "Earlier tuner working styles, newest first.")

(defvar-local emacsvox-aural-voice-tuner-dirty nil
  "Whether the tuner working style differs from its initial style.")

(defvar-local emacsvox-aural-voice-tuner-preview-text nil
  "Comparison text spoken by the current tuner.")

(defvar-local emacsvox-aural-voice-tuner-source-buffer nil
  "Voice-palette preview buffer that opened the current tuner.")

(defvar-local emacsvox-aural-voice-tuner-route-selector nil
  "Unsaved physical route selector used by this tuner.")

(defvar-local emacsvox-aural-voice-tuner-route-language nil
  "Language constraint used by the tuner route preview.")

(defvar-local emacsvox-aural-voice-tuner-route-engine nil
  "Discovered engine descriptor used by the tuner route preview.")

(defvar-local emacsvox-aural-voice-tuner-route-realized nil
  "Most recently realized engine and voice reported by preview.")

(defvar-local emacsvox-aural-voice-tuner-preview-result nil
  "Most recent normalized route-preview completion result.")

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
  (emacsvox-aural-ui-goto-row id))

(defun emacsvox-aural-voice-palettes-refresh (&optional id)
  "Refresh palettes while preserving ID and the current column."
  (interactive)
  (emacsvox-aural-ui-refresh-tabulated
   #'emacsvox-aural-voice-palettes--set-entries
   id
   (emacsvox-aural-voice-palettes--active-id)))

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

(defun emacsvox-aural-voice-palettes--persist-mutation (mutation)
  "Persist MUTATION against a staged palette registry, then publish it.

MUTATION is called with a copy of the voice-palette registry dynamically
installed.  The complete candidate registry is validated and saved before it
replaces live state.  Return the value of MUTATION."
  (let ((registry
         (copy-hash-table emacsvox-aural-voice-palette-registry))
        result)
    (let ((emacsvox-aural-voice-palette-registry registry))
      (setq result (funcall mutation))
      (maphash
       (lambda (palette-id _)
         (emacsvox-aural-effective-voice-entries palette-id))
       registry)
      (emacsvox-aural-save-user-data))
    (setq emacsvox-aural-voice-palette-registry registry)
    result))

(defun emacsvox-aural-voice-palettes--install-data (data &optional old-id)
  "Atomically install personal palette DATA, replacing OLD-ID when non-nil."
  (let ((record
         (emacsvox-aural-voice-palettes--persist-mutation
          (lambda ()
            (when old-id
              (remhash old-id emacsvox-aural-voice-palette-registry))
            (let* ((record
                    (emacsvox-aural-compile-voice-palette-data
                     data nil emacsvox-aural-schemes-file))
                   (id (emacsvox-aural-voice-palette-id record)))
              (when
                  (gethash id emacsvox-aural-voice-palette-registry)
                (user-error "Voice palette already exists: %s" id))
              (puthash
               id record emacsvox-aural-voice-palette-registry)
              record)))))
    (emacsvox-aural-ui-refresh-home-if-live)
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

(defun emacsvox-aural-voice-palettes--read-new-entry-name
    (id &optional initial)
  "Read a new voice entry name for palette ID, offering INITIAL."
  (let* ((text
          (string-trim
           (read-string "New voice name: " initial)))
         (name (intern text)))
    (when
        (or (string-empty-p text) (keywordp name) (memq name '(nil t)))
      (user-error "Use a non-keyword voice name"))
    (when (assq name (emacsvox-aural-effective-voice-entries id))
      (user-error "Voice already exists in palette %s: %s" id name))
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
           (emacsvox-aural-humanize dimension)
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
  (let* ((default
          (if (and current (symbolp current))
              "personality"
            "custom ACSS"))
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
           (emacsvox-aural-humanize id)
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
  (emacsvox-aural-ui-speak-current-cell))

(defun emacsvox-aural-voice-palettes-next ()
  "Move to and speak the next voice palette."
  (interactive)
  (emacsvox-aural-ui-move-row 1 "voice palettes"))

(defun emacsvox-aural-voice-palettes-previous ()
  "Move to and speak the previous voice palette."
  (interactive)
  (emacsvox-aural-ui-move-row -1 "voice palettes"))

(defun emacsvox-aural-voice-palettes-next-column ()
  "Move right and speak the next palette column."
  (interactive)
  (emacsvox-aural-ui-move-column 1))

(defun emacsvox-aural-voice-palettes-previous-column ()
  "Move left and speak the previous palette column."
  (interactive)
  (emacsvox-aural-ui-move-column -1))

(defun emacsvox-aural-voice-palettes-describe (&optional id)
  "Display and speak the effective voices in palette ID."
  (interactive)
  (let* ((id (or id (emacsvox-aural-voice-palettes--at-point-or-read)))
         (palette (emacsvox-aural-voice-palette id))
         (direct (emacsvox-aural-voice-palette-entries palette))
         (report (emacsvox-aural-voice-palettes--validation id)))
    (emacsvox-aural-ui-with-help-window
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

(defun emacsvox-aural-voice-palettes--copy (source)
  "Copy voice palette SOURCE to a prompted personal palette."
  (let* ((source-palette (emacsvox-aural-voice-palette source))
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
    id))

(defun emacsvox-aural-voice-palettes-copy ()
  "Copy the voice palette at point to a personal palette."
  (interactive)
  (let ((id
         (emacsvox-aural-voice-palettes--copy
          (emacsvox-aural-voice-palettes--at-point-or-read))))
    (emacsvox-aural-voice-palettes-refresh id)
    (emacsvox-aural-voice-palettes-speak-current)
    id))

(defun emacsvox-aural-voice-palettes--install-entry-definition
    (id name definition)
  "Install complete voice DEFINITION as NAME in personal palette ID."
  (let* ((palette (emacsvox-aural-voice-palette id))
         (data (emacsvox-aural-voice-palette-data-form palette))
         (updated
          (emacsvox-aural-voice-palettes--put-entry
           data
           (emacsvox-aural-voice-palettes--entry-data name definition))))
    (when (emacsvox-aural-voice-palette-built-in palette)
      (user-error "Copy the built-in palette first, then edit the copy"))
    (emacsvox-aural-voice-palettes--install-data updated id)
    (message "Saved voice %s in palette %s" name id)
    name))

(defun emacsvox-aural-voice-palettes--edit-entry (id name)
  "Create or replace voice NAME in personal palette ID."
  (let* ((palette (emacsvox-aural-voice-palette id))
         (data (emacsvox-aural-voice-palette-data-form palette)))
    (when (emacsvox-aural-voice-palette-built-in palette)
      (user-error "Copy the built-in palette first, then edit the copy"))
    (let* ((direct (emacsvox-aural-voice-palettes--direct-entry data name))
           (current
            (if direct
                (or
                 (plist-get (cdr direct) :personality)
                 (plist-get (cdr direct) :style))
              (emacsvox-aural-voice name id)))
           (definition
            (emacsvox-aural-voice-palettes--read-definition current)))
      (emacsvox-aural-voice-palettes--install-entry-definition
       id name definition))))

(defun emacsvox-aural-voice-palettes-edit-entry ()
  "Create or replace one direct voice entry in the personal palette at point."
  (interactive)
  (let* ((id (emacsvox-aural-voice-palettes--at-point-or-read))
         (name (emacsvox-aural-voice-palettes--read-entry-name id)))
    (prog1
        (emacsvox-aural-voice-palettes--edit-entry id name)
      (emacsvox-aural-voice-palettes-refresh id))))

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
    (emacsvox-aural-voice-palettes--persist-mutation
     (lambda ()
       (remhash id emacsvox-aural-voice-palette-registry)
       id))
    (when (eq id emacsvox-aural-voice-palette-override)
      (emacsvox-aural-select-voice-palette nil))
    (emacsvox-aural-voice-palettes-refresh)
    (emacsvox-aural-ui-refresh-home-if-live)
    id))

(defun emacsvox-aural-voice-palettes-activate ()
  "Activate the voice palette at point as an override."
  (interactive)
  (let ((id (emacsvox-aural-voice-palettes--at-point-or-read)))
    (emacsvox-aural-select-voice-palette id)
    (emacsvox-aural-voice-palettes-refresh id)
    (emacsvox-aural-ui-refresh-home-if-live)
    (emacsvox-aural-voice-palettes-speak-current)
    id))

(defun emacsvox-aural-voice-palettes-follow-scheme ()
  "Clear the palette override and follow the active scheme."
  (interactive)
  (emacsvox-aural-select-voice-palette nil)
  (emacsvox-aural-voice-palettes-refresh
   (emacsvox-aural-voice-palettes--active-id))
  (emacsvox-aural-ui-refresh-home-if-live)
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

(defun emacsvox-aural-voice-palettes--entry-provider (name palette-id)
  "Return the palette that directly provides voice NAME to PALETTE-ID."
  (let ((current palette-id)
        provider)
    (while (and current (not provider))
      (let ((palette (emacsvox-aural-voice-palette current)))
        (when (assq name (emacsvox-aural-voice-palette-entries palette))
          (setq provider current))
        (setq current (emacsvox-aural-voice-palette-parent palette))))
    provider))

(defun emacsvox-aural-voice-palettes--preview-entries (palette)
  "Return effective entries for PALETTE in predictable voice-name order."
  (sort
   (copy-sequence (emacsvox-aural-effective-voice-entries palette))
   (lambda (left right)
     (string-lessp
      (symbol-name (car left))
      (symbol-name (car right))))))

(defun emacsvox-aural-voice-palettes--definition-summary (definition)
  "Return a concise display description of voice DEFINITION."
  (if (symbolp definition)
      (format "personality %s" definition)
    (string-trim
     (replace-regexp-in-string
      "[\n\t ]+" " " (prin1-to-string definition)))))

(defun emacsvox-aural-voice-palettes--effective-summary (compiled)
  "Return a concise effective-style description for COMPILED voice data."
  (string-trim
   (replace-regexp-in-string
    "[\n\t ]+" " "
    (prin1-to-string
     (emacsvox-aural-compiled-voice-style compiled)))))

(defun emacsvox-aural-voice-palettes--preview-status (compiled)
  "Return concise audition status for COMPILED voice data."
  (let ((command (emacsvox-aural-compiled-voice-command compiled))
        (degradations
         (emacsvox-aural-compiled-voice-degradations compiled)))
    (cond
     ((eq command 'inaudible) "inaudible")
     (degradations
      (format
       "%d fallback%s"
       (length degradations)
       (if (= (length degradations) 1) "" "s")))
     (t "ready"))))

(defun emacsvox-aural-voice-palette-previews--row (entry)
  "Return one tabulated preview row for effective voice ENTRY."
  (let* ((name (car entry))
         (definition (cdr entry))
         (palette emacsvox-aural-voice-palette-previews-palette)
         (provider
          (emacsvox-aural-voice-palettes--entry-provider name palette)))
    (condition-case error
        (let ((compiled
               (emacsvox-aural-compile-voice-style name palette)))
          (list
           name
           (vector
            (symbol-name name)
            (if (eq provider palette)
                "direct"
              (format "from %s" provider))
            (emacsvox-aural-voice-palettes--definition-summary definition)
            (emacsvox-aural-voice-palettes--effective-summary compiled)
            (emacsvox-aural-voice-palettes--preview-status compiled))))
      (error
       (list
        name
        (vector
         (symbol-name name)
         (if (eq provider palette)
             "direct"
           (format "from %s" provider))
         (emacsvox-aural-voice-palettes--definition-summary definition)
         "unavailable"
         (error-message-string error)))))))

(defun emacsvox-aural-voice-palette-previews--set-entries ()
  "Populate the current voice-palette preview buffer."
  (setq
   tabulated-list-entries
   (mapcar
    #'emacsvox-aural-voice-palette-previews--row
    emacsvox-aural-voice-palette-previews-entries)))

(defun emacsvox-aural-voice-palette-previews--goto (voice)
  "Move to VOICE and its first preview column."
  (emacsvox-aural-ui-goto-row voice))

(defun emacsvox-aural-voice-palette-previews--update-header ()
  "Update the current preview buffer's palette and sample heading."
  (setq
   header-line-format
   (format
    " Palette: %s    Comparison text: %s"
    emacsvox-aural-voice-palette-previews-palette
    emacsvox-aural-voice-palette-previews-text)))

(defun emacsvox-aural-voice-palette-previews-refresh (&optional voice)
  "Refresh palette voices, preserving VOICE and the current column."
  (interactive)
  (let ((selected
         (or
          voice
          (tabulated-list-get-id)
          (gethash
           emacsvox-aural-voice-palette-previews-palette
           emacsvox-aural-voice-palettes--last-preview-voices)
          (caar emacsvox-aural-voice-palette-previews-entries))))
    (setq
     emacsvox-aural-voice-palette-previews-entries
     (emacsvox-aural-voice-palettes--preview-entries
      emacsvox-aural-voice-palette-previews-palette))
    (unless emacsvox-aural-voice-palette-previews-entries
      (user-error
       "Voice palette %s has no effective voices"
       emacsvox-aural-voice-palette-previews-palette))
    (unless (assq selected emacsvox-aural-voice-palette-previews-entries)
      (setq selected (caar emacsvox-aural-voice-palette-previews-entries)))
    (emacsvox-aural-ui-refresh-tabulated
     #'emacsvox-aural-voice-palette-previews--set-entries
     selected nil
     #'emacsvox-aural-voice-palette-previews--update-header)))

(defun emacsvox-aural-voice-palette-previews--current-voice ()
  "Return the effective voice represented by the current preview row."
  (or
   (tabulated-list-get-id)
   (user-error "Move to a voice first")))

(defun emacsvox-aural-voice-palette-previews--remember-current ()
  "Remember the voice selected by the current preview row."
  (when-let* ((voice (tabulated-list-get-id)))
    (puthash
     emacsvox-aural-voice-palette-previews-palette
     voice
     emacsvox-aural-voice-palettes--last-preview-voices))
  (tabulated-list-get-id))

(defun emacsvox-aural-voice-palette-previews-speak-current ()
  "Speak the complete palette voice row at point."
  (interactive)
  (let* ((voice
          (emacsvox-aural-voice-palette-previews--current-voice))
         (row
          (or
           (cadr (assq voice tabulated-list-entries))
           (user-error "Unknown voice: %s" voice)))
         (summary
          (format
           "%s. Source %s. Requested %s. Effective %s. Status %s."
           (aref row 0)
           (aref row 1)
           (aref row 2)
           (aref row 3)
           (aref row 4))))
    (emacsvox-aural-voice-palette-previews--remember-current)
    (if (fboundp 'tts-speak)
        (tts-speak summary)
      (message "%s" summary))
    summary))

(defun emacsvox-aural-voice-palette-previews-speak-current-cell ()
  "Speak the current preview column title and value."
  (interactive)
  (emacsvox-aural-ui-speak-current-cell))

(defun emacsvox-aural-voice-palette-previews-next ()
  "Move to and speak the next effective voice."
  (interactive)
  (emacsvox-aural-ui-move-row 1 "palette voices")
  (emacsvox-aural-voice-palette-previews--remember-current))

(defun emacsvox-aural-voice-palette-previews-previous ()
  "Move to and speak the previous effective voice."
  (interactive)
  (emacsvox-aural-ui-move-row -1 "palette voices")
  (emacsvox-aural-voice-palette-previews--remember-current))

(defun emacsvox-aural-voice-palette-previews-next-column ()
  "Move right and speak the next voice column."
  (interactive)
  (emacsvox-aural-ui-move-column 1))

(defun emacsvox-aural-voice-palette-previews-previous-column ()
  "Move left and speak the previous voice column."
  (interactive)
  (emacsvox-aural-ui-move-column -1))

(defun emacsvox-aural-voice-palettes--preview-sample (voice text)
  "Return comparison TEXT labelled with VOICE."
  (format
   "%s voice. %s"
   (capitalize (emacsvox-aural-humanize voice))
   text))

(defun emacsvox-aural-voice-palettes--compiled-preview-plan
    (compiled label text)
  "Return a preview plan for COMPILED voice and comparison TEXT under LABEL."
  (let ((command (emacsvox-aural-compiled-voice-command compiled)))
    (when (eq command 'inaudible)
      (user-error "Voice %s suppresses speech" label))
    (emacsvox-aural-preview-compiled-voice-plan
     compiled
     (emacsvox-aural-voice-palettes--preview-sample label text))))

(defun emacsvox-aural-voice-palettes--preview-plan
    (palette voice text)
  "Return a preview plan for VOICE from PALETTE speaking comparison TEXT."
  (emacsvox-aural-voice-palettes--compiled-preview-plan
   (emacsvox-aural-compile-voice-style voice palette)
   voice text))

(defun emacsvox-aural-voice-palette-previews-play ()
  "Audition the effective voice at point with the comparison text."
  (interactive)
  (let ((voice
         (emacsvox-aural-voice-palette-previews--current-voice)))
    (emacsvox-aural-voice-palette-previews--remember-current)
    (let ((plan
           (emacsvox-aural-voice-palettes--preview-plan
            emacsvox-aural-voice-palette-previews-palette
            voice
            emacsvox-aural-voice-palette-previews-text)))
      (emacsvox-aural-preview-play-plan plan))))

(defun emacsvox-aural-voice-palette-previews-play-all ()
  "Audition every effective voice using the same comparison text."
  (interactive)
  (let ((count 0)
        unavailable
        runs)
    (dolist (entry emacsvox-aural-voice-palette-previews-entries)
      (condition-case error
          (let* ((plan
                  (emacsvox-aural-voice-palettes--preview-plan
                   emacsvox-aural-voice-palette-previews-palette
                   (car entry)
                   emacsvox-aural-voice-palette-previews-text))
                 (text
                  (emacsvox-aural-concrete-content-text
                   (emacsvox-aural-concrete-plan-content plan))))
            (push (list plan text nil) runs)
            (cl-incf count))
        (error
         (push
          (format "%s: %s" (car entry) (error-message-string error))
          unavailable))))
    (unless (> count 0)
      (user-error "No voices in this palette can be previewed"))
    (emacsvox-aural-preview-play-runs (nreverse runs))
    (emacsvox-aural-preview-message
     "Previewing %d voice%s%s; press s to stop"
     count
     (if (= count 1) "" "s")
     (if unavailable
         (format ", skipped %d unavailable" (length unavailable))
       ""))
    (list :queued count :unavailable (nreverse unavailable))))

(defun emacsvox-aural-voice-palette-previews-stop ()
  "Stop the current voice audition."
  (interactive)
  (emacsvox-aural-preview-stop)
  (emacsvox-aural-preview-message "Voice preview stopped"))

(defun emacsvox-aural-voice-palette-previews-set-text ()
  "Set the comparison text used by this preview buffer."
  (interactive)
  (let ((text
         (string-trim
          (read-string
           "Voice comparison text: "
           emacsvox-aural-voice-palette-previews-text))))
    (when (string-empty-p text)
      (user-error "Comparison text cannot be empty"))
    (setq emacsvox-aural-voice-palette-previews-text text)
    (emacsvox-aural-voice-palette-previews--update-header)
    (if (fboundp 'tts-speak)
        (tts-speak "Voice comparison text updated")
      (message "Voice comparison text updated"))
    text))

(defun emacsvox-aural-voice-palette-previews-open-manager ()
  "Return to the palette manager for the current preview palette."
  (interactive)
  (emacsvox-aural-list-voice-palettes
   emacsvox-aural-voice-palette-previews-palette))

(defun emacsvox-aural-voice-palette-previews-explain ()
  "Explain the effective voice at point."
  (interactive)
  (emacsvox-aural-voice-palettes-explain
   emacsvox-aural-voice-palette-previews-palette
   (emacsvox-aural-voice-palette-previews--current-voice)))

(defun emacsvox-aural-voice-palette-previews--editable-palette ()
  "Return an editable palette for the current voice preview.

When the preview shows a built-in palette, offer to create and activate an
empty personal overlay that inherits from it.  Continue the current preview
in that overlay so subsequent edits do not create more palettes."
  (let* ((source emacsvox-aural-voice-palette-previews-palette)
         (palette (emacsvox-aural-voice-palette source)))
    (if (not (emacsvox-aural-voice-palette-built-in palette))
        source
      (unless
          (y-or-n-p
           (format
            "Palette %s is built in; create and activate a personal overlay? "
            source))
        (user-error "Voice editing cancelled"))
      (let* ((id
              (emacsvox-aural-voice-palettes--read-new-id
               (format "%s-personal" source)))
             (data
              (list
               :schema-version emacsvox-aural-voice-palette-schema-version
               :id id
               :summary (format "Personal additions to %s" source)
               :parent source
               :entries nil)))
        (emacsvox-aural-voice-palettes--install-data data)
        (emacsvox-aural-select-voice-palette id)
        (setq emacsvox-aural-voice-palette-previews-palette id)
        (message "Created and activated personal voice palette %s" id)
        id))))

(defun emacsvox-aural-voice-palette-previews-edit ()
  "Replace the effective voice at point using the guided definition editor."
  (interactive)
  (let* ((voice
          (emacsvox-aural-voice-palette-previews--current-voice)))
    (let ((palette-id
           (emacsvox-aural-voice-palette-previews--editable-palette)))
      (emacsvox-aural-voice-palettes--edit-entry palette-id voice)
      (emacsvox-aural-voice-palette-previews-refresh voice)
      voice)))

(defun emacsvox-aural-voice-tuner--complete-style
    (definition palette)
  "Return a complete ACSS style for DEFINITION resolved through PALETTE."
  (let* ((requested
          (and
           (emacsvox-aural-voice-style-p definition)
           (copy-tree definition)))
         (compiled
          (unless requested
            (emacsvox-aural-compile-voice-style definition palette)))
         (source
          (or
           requested
           (and
            compiled
            (copy-tree
             (emacsvox-aural-compiled-voice-style compiled)))))
         style)
    (dolist (dimension emacsvox-aural-rich-voice-dimensions)
      (let ((key (emacsvox-aural--voice-dimension-key dimension)))
        (setq
         style
         (plist-put
          style key
          (and source (plist-get source key))))))
    style))

(defun emacsvox-aural-voice-tuner--adapter ()
  "Return the active tuner adapter identifier."
  (or (plist-get emacsvox-aural-voice-tuner-route-engine :engine-id)
      (plist-get (emacsvox-aural-active-voice-capabilities) :adapter)))

(defun emacsvox-aural-voice-tuner--capability-dimensions ()
  "Return dimensions supported by the selected tuner route."
  (if emacsvox-aural-voice-tuner-route-engine
      (plist-get emacsvox-aural-voice-tuner-route-engine :acss-dimensions)
    (plist-get (emacsvox-aural-active-voice-capabilities) :dimensions)))

(defun emacsvox-aural-voice-tuner--effect-dimension-p (dimension)
  "Return non-nil when DIMENSION is a post-synthesis effect."
  (memq dimension emacsvox-aural-post-synthesis-dimensions))

(defun emacsvox-aural-voice-tuner--normalized-dimensions (values)
  "Normalize adapter dimension VALUES to Lisp symbols."
  (mapcar
   (lambda (value)
     (intern
      (replace-regexp-in-string
       "_" "-" (if (symbolp value) (symbol-name value) value))))
   values))

(defun emacsvox-aural-voice-tuner--supported-p (dimension)
  "Return non-nil when the selected route supports DIMENSION."
  (and
   (not (and emacsvox-aural-voice-tuner-route-selector
             (eq dimension 'family)))
   (if (emacsvox-aural-voice-tuner--effect-dimension-p dimension)
       (memq
        dimension
        (emacsvox-aural-voice-tuner--normalized-dimensions
         (if emacsvox-aural-voice-tuner-route-engine
             (plist-get emacsvox-aural-voice-tuner-route-engine
                        :post-synthesis-dimensions)
           (plist-get (emacsvox-aural-active-voice-capabilities)
                      :post-synthesis-dimensions))))
     (memq dimension
           (emacsvox-aural-voice-tuner--capability-dimensions)))))

(defun emacsvox-aural-voice-tuner--value (dimension)
  "Return the current requested value for DIMENSION."
  (plist-get
   emacsvox-aural-voice-tuner-working-style
   (emacsvox-aural--voice-dimension-key dimension)))

(defun emacsvox-aural-voice-tuner--display-value (value)
  "Return a user-facing description of voice VALUE."
  (if (null value) "adapter default" (format "%s" value)))

(defun emacsvox-aural-voice-tuner--dimension-label (dimension)
  "Return the user-facing tuner label for DIMENSION."
  (if (eq dimension 'family)
      (if (eq (plist-get (emacsvox-aural-active-voice-capabilities)
                         :family-selection)
              'routed)
          "Portable Fallback Family"
        "Base Voice (ACSS Family)")
    (capitalize (emacsvox-aural-humanize dimension))))

(defun emacsvox-aural-voice-tuner--family-description
    (family &optional effective)
  "Describe requested FAMILY, or its EFFECTIVE adapter realization."
  (if (null family)
      "adapter default"
    (let* ((capability (emacsvox-aural-active-voice-capabilities))
           (resolved
            (and
             effective
             (fboundp 'tts-voice-family-id)
             (tts-voice-family-id family capability)))
           (display-id (or resolved family))
           (entry
            (and
             (fboundp 'tts-voice-family-capability)
             (tts-voice-family-capability display-id capability)))
           (label (plist-get (cdr entry) :label)))
      (if label
          (format "%s — %s" display-id label)
        (format "%s" display-id)))))

(defun emacsvox-aural-voice-tuner--requested-value (dimension)
  "Describe the requested tuner value for DIMENSION."
  (let ((value (emacsvox-aural-voice-tuner--value dimension)))
    (if (eq dimension 'family)
        (emacsvox-aural-voice-tuner--family-description value)
      (emacsvox-aural-voice-tuner--display-value value))))

(defun emacsvox-aural-voice-tuner--support-description (dimension)
  "Describe active adapter support for DIMENSION."
  (if (not emacsvox-aural-voice-tuner-route-selector)
      (format
       "%s by %s"
       (if (emacsvox-aural-voice-tuner--supported-p dimension)
           "supported"
         "unsupported")
       (emacsvox-aural-humanize
        (emacsvox-aural-voice-tuner--adapter)))
    (cond
     ((and emacsvox-aural-voice-tuner-route-selector
           (eq dimension 'family))
      "portable fallback; physical route owns the base voice")
     ((memq
       dimension
       (plist-get
        emacsvox-aural-voice-tuner-preview-result
        (if (emacsvox-aural-voice-tuner--effect-dimension-p dimension)
            :degraded-effects
          :degraded-acss)))
      (format "omitted by %s" (emacsvox-aural-voice-tuner--adapter)))
     ((emacsvox-aural-voice-tuner--supported-p dimension)
      (format "%s by %s"
              (if (emacsvox-aural-voice-tuner--effect-dimension-p dimension)
                  "Omnivox-rendered"
                "engine-rendered")
              (emacsvox-aural-voice-tuner--adapter)))
     (t
      (format "omitted by %s" (emacsvox-aural-voice-tuner--adapter))))))

(defun emacsvox-aural-voice-tuner--effective-value (dimension)
  "Describe the auditioned value for DIMENSION."
  (if (and emacsvox-aural-voice-tuner-route-selector
           (eq dimension 'family))
      "retained for fallback; not applied to the selected physical voice"
    (if (emacsvox-aural-voice-tuner--supported-p dimension)
        (if (eq dimension 'family)
            (let* ((value (emacsvox-aural-voice-tuner--value dimension))
                   (capability (emacsvox-aural-active-voice-capabilities))
                   (selection (plist-get capability :family-selection))
                   (resolved
                    (and
                     value
                     (fboundp 'tts-voice-family-id)
                     (tts-voice-family-id value capability))))
              (cond
               ((null value) "adapter default")
               ((and (eq selection 'enumerated) (null resolved))
                "adapter default; requested family unavailable")
               (t
                (emacsvox-aural-voice-tuner--family-description value t))))
          (emacsvox-aural-voice-tuner--display-value
           (emacsvox-aural-voice-tuner--value dimension)))
      "not applied")))

(defun emacsvox-aural-voice-tuner--route-description ()
  "Return the currently requested and realized tuner route."
  (if (not emacsvox-aural-voice-tuner-route-selector)
      (format "adapter %s" (emacsvox-aural-voice-tuner--adapter))
    (let ((realized emacsvox-aural-voice-tuner-route-realized))
      (format
       "route %S; realized %s"
       emacsvox-aural-voice-tuner-route-selector
       (if realized
           (format "%s/%s"
                   (plist-get realized :engine-id)
                   (plist-get realized :voice-id))
         "pending")))))

(defun emacsvox-aural-voice-tuner--row (dimension)
  "Return one tabulated tuner row for DIMENSION."
  (list
   dimension
   (vector
    (emacsvox-aural-voice-tuner--dimension-label dimension)
    (emacsvox-aural-voice-tuner--requested-value dimension)
    (emacsvox-aural-voice-tuner--effective-value dimension)
    (emacsvox-aural-voice-tuner--support-description dimension)
    (or
     (alist-get
      dimension
      emacsvox-aural-voice-tuner--dimension-descriptions)
     ""))))

(defun emacsvox-aural-voice-tuner--set-entries ()
  "Populate the current voice tuner."
  (setq
   tabulated-list-entries
   (mapcar
    #'emacsvox-aural-voice-tuner--row
    emacsvox-aural-rich-voice-dimensions)))

(defun emacsvox-aural-voice-tuner--goto (dimension)
  "Move to tuner DIMENSION and its first column."
  (emacsvox-aural-ui-goto-row dimension))

(defun emacsvox-aural-voice-tuner--update-header ()
  "Update tuner identity, adapter, and transaction state."
  (setq
   header-line-format
   (format
    " Voice: %s    Palette: %s    %s    %s"
    emacsvox-aural-voice-tuner-voice
    emacsvox-aural-voice-tuner-palette
    (emacsvox-aural-voice-tuner--route-description)
    (if emacsvox-aural-voice-tuner-dirty "modified" "unchanged")))
  (force-mode-line-update))

(defun emacsvox-aural-voice-tuner-refresh (&optional dimension)
  "Refresh the tuner while preserving DIMENSION and the current column."
  (interactive)
  (emacsvox-aural-ui-refresh-tabulated
   #'emacsvox-aural-voice-tuner--set-entries
   dimension
   (car emacsvox-aural-rich-voice-dimensions)
   #'emacsvox-aural-voice-tuner--update-header))

(defun emacsvox-aural-voice-tuner--current-dimension ()
  "Return the voice dimension represented by the current tuner row."
  (or
   (tabulated-list-get-id)
   (user-error "Move to a voice setting first")))

(defun emacsvox-aural-voice-tuner-speak-current ()
  "Speak the complete tuner row at point."
  (interactive)
  (let* ((dimension (emacsvox-aural-voice-tuner--current-dimension))
         (row
          (or
           (cadr (assq dimension tabulated-list-entries))
           (user-error "Unknown voice setting: %s" dimension)))
         (summary
          (format
           "%s. Requested %s. Auditioned %s. %s. %s."
           (aref row 0)
           (aref row 1)
           (aref row 2)
           (aref row 3)
           (aref row 4))))
    (if (fboundp 'tts-speak)
        (tts-speak summary)
      (message "%s" summary))
    summary))

(defun emacsvox-aural-voice-tuner-next ()
  "Move to and speak the next tunable dimension."
  (interactive)
  (emacsvox-aural-ui-move-row
   1 "voice settings"
   #'emacsvox-aural-voice-tuner--speak-setting))

(defun emacsvox-aural-voice-tuner-previous ()
  "Move to and speak the previous tunable dimension."
  (interactive)
  (emacsvox-aural-ui-move-row
   -1 "voice settings"
   #'emacsvox-aural-voice-tuner--speak-setting))

(defun emacsvox-aural-voice-tuner--setting-announcement (dimension)
  "Describe the current DIMENSION value and adapter support."
  (format
   "%s %s. %s%s"
   (emacsvox-aural-voice-tuner--dimension-label dimension)
   (emacsvox-aural-voice-tuner--requested-value dimension)
   (capitalize
    (emacsvox-aural-voice-tuner--support-description dimension))
   (if (emacsvox-aural-voice-tuner--supported-p dimension)
       "."
     "; this setting is saved but is not applied in this audition.")))

(defun emacsvox-aural-voice-tuner--speak-setting ()
  "Speak the current setting name, value, and adapter support."
  (let ((summary
         (emacsvox-aural-voice-tuner--setting-announcement
          (emacsvox-aural-voice-tuner--current-dimension))))
    (when (fboundp 'emacsvox-icon)
      (emacsvox-icon 'select-object))
    (if (fboundp 'tts-speak)
        (tts-speak summary)
      (message "%s" summary))
    summary))

(defun emacsvox-aural-voice-tuner-audition (&optional announcement)
  "Audition the unsaved working style after optional ANNOUNCEMENT."
  (interactive)
  (if emacsvox-aural-voice-tuner-route-selector
      (let ((buffer (current-buffer))
            (text
             (concat
              (and announcement (concat announcement " "))
              (emacsvox-aural-voice-palettes--preview-sample
               emacsvox-aural-voice-tuner-voice
               emacsvox-aural-voice-tuner-preview-text)))
            acss effects)
        (dolist (dimension '(rate average-pitch pitch-range stress richness))
          (let* ((key (emacsvox-aural--voice-dimension-key dimension))
                 (value
                  (plist-get emacsvox-aural-voice-tuner-working-style key)))
            (when (numberp value)
              (setq acss
                    (plist-put
                     acss key (/ (float (max 0 (min 9 value))) 9.0))))))
        (dolist (dimension emacsvox-aural-post-synthesis-dimensions)
          (let* ((key (emacsvox-aural--voice-dimension-key dimension))
                 (value
                  (plist-get emacsvox-aural-voice-tuner-working-style key)))
            (when (numberp value)
              (setq effects
                    (plist-put
                     effects key (/ (float (max 0 (min 9 value))) 9.0))))))
        (setq emacsvox-aural-voice-tuner-preview-result '(:status running))
        (tts-preview-voice
         text emacsvox-aural-voice-tuner-route-selector
         :acss acss :effects effects
         :language emacsvox-aural-voice-tuner-route-language
         :callback
         (lambda (result)
           (when (buffer-live-p buffer)
             (with-current-buffer buffer
               (setq emacsvox-aural-voice-tuner-preview-result result)
               (when-let* ((realized (plist-get result :realized)))
                 (setq emacsvox-aural-voice-tuner-route-realized realized))
               (when (derived-mode-p 'emacsvox-aural-voice-tuner-mode)
                 (emacsvox-aural-voice-tuner-refresh
                  (tabulated-list-get-id)))))))
        emacsvox-aural-voice-tuner-preview-result)
    (let* ((compiled
            (emacsvox-aural-compile-voice-style
             emacsvox-aural-voice-tuner-working-style
             emacsvox-aural-voice-tuner-palette))
           (text
            (concat
             (and announcement (concat announcement " "))
             (emacsvox-aural-voice-palettes--preview-sample
              emacsvox-aural-voice-tuner-voice
              emacsvox-aural-voice-tuner-preview-text)))
           (plan
            (emacsvox-aural-preview-compiled-voice-plan compiled text)))
      (emacsvox-aural-preview-play-plan plan)
      (when announcement
        (emacsvox-aural-preview-message "%s" announcement))
      compiled)))

(defun emacsvox-aural-voice-tuner--update-dirty ()
  "Update and return the tuner dirty state."
  (setq
   emacsvox-aural-voice-tuner-dirty
   (not
    (equal
     emacsvox-aural-voice-tuner-working-style
     emacsvox-aural-voice-tuner-initial-style))))

(defun emacsvox-aural-voice-tuner--set-value
    (dimension value &optional announcement)
  "Set DIMENSION to VALUE, refresh, and audition the working style.

ANNOUNCEMENT overrides the normal setting description."
  (let* ((key (emacsvox-aural--voice-dimension-key dimension))
         (current (plist-get emacsvox-aural-voice-tuner-working-style key)))
    (unless (equal current value)
      (push
       (copy-tree emacsvox-aural-voice-tuner-working-style)
       emacsvox-aural-voice-tuner-history)
      (setq
       emacsvox-aural-voice-tuner-working-style
       (plist-put
        (copy-tree emacsvox-aural-voice-tuner-working-style)
        key value))
      (emacsvox-aural-voice-tuner--update-dirty)
      (emacsvox-aural-voice-tuner-refresh dimension)
      (emacsvox-aural-voice-tuner-audition
       (or
        announcement
        (emacsvox-aural-voice-tuner--setting-announcement dimension))))
    value))

(defun emacsvox-aural-voice-tuner--numeric-dimension ()
  "Return the current numeric dimension, or report a family-row error."
  (let ((dimension (emacsvox-aural-voice-tuner--current-dimension)))
    (when (eq dimension 'family)
      (user-error "Press RET to edit the voice family"))
    dimension))

(defun emacsvox-aural-voice-tuner-increase ()
  "Increase the current numeric dimension and audition it."
  (interactive)
  (let* ((dimension (emacsvox-aural-voice-tuner--numeric-dimension))
         (current (emacsvox-aural-voice-tuner--value dimension))
         (value (if (numberp current) (1+ current) 5)))
    (when (> value 9)
      (user-error "%s is already at nine" dimension))
    (emacsvox-aural-voice-tuner--set-value dimension value)))

(defun emacsvox-aural-voice-tuner-decrease ()
  "Decrease the current numeric dimension and audition it."
  (interactive)
  (let* ((dimension (emacsvox-aural-voice-tuner--numeric-dimension))
         (current (emacsvox-aural-voice-tuner--value dimension))
         (value (if (numberp current) (1- current) 5)))
    (when (< value 0)
      (user-error "%s is already at zero" dimension))
    (emacsvox-aural-voice-tuner--set-value dimension value)))

(defun emacsvox-aural-voice-tuner-set-digit ()
  "Set the current numeric dimension from the typed digit and audition it."
  (interactive)
  (emacsvox-aural-voice-tuner--set-value
   (emacsvox-aural-voice-tuner--numeric-dimension)
   (- last-command-event ?0)))

(defun emacsvox-aural-voice-tuner-use-default ()
  "Use the adapter default for the current dimension and audition it."
  (interactive)
  (emacsvox-aural-voice-tuner--set-value
   (emacsvox-aural-voice-tuner--current-dimension)
   nil))

(defun emacsvox-aural-voice-tuner--family-candidates (capability)
  "Return accessible completion choices from family CAPABILITY."
  (let (choices)
    (dolist (generic (plist-get capability :generic-families))
      (let* ((entry
              (and
               (fboundp 'tts-voice-family-capability)
               (tts-voice-family-capability generic capability)))
             (label (plist-get (cdr entry) :label)))
        (push
         (cons
          (format
           "%s — portable%s"
           generic
           (if label (format "; currently %s" label) ""))
          generic)
         choices)))
    (dolist (entry (plist-get capability :families))
      (let ((id (car entry))
            (label (plist-get (cdr entry) :label)))
        (push
         (cons
          (if label (format "%s — %s" id label) (format "%s" id))
          id)
         choices)))
    (nreverse choices)))

(defun emacsvox-aural-voice-tuner--read-family (current)
  "Read a base voice or ACSS family, initially CURRENT."
  (let* ((capability (emacsvox-aural-active-voice-capabilities))
         (selection
          (or
           (plist-get capability :family-selection)
           (cond
            ((plist-get capability :families) 'enumerated)
            ((emacsvox-aural-voice-tuner--supported-p 'family) 'free-form)
            (t 'unsupported)))))
    (pcase selection
      ('unsupported
       (user-error
        "The %s adapter does not support inline base-voice changes"
        (plist-get capability :adapter)))
      ('enumerated
       (let* ((choices
               (cons
                '("adapter default" . nil)
                (emacsvox-aural-voice-tuner--family-candidates capability)))
              (initial-entry
               (cl-find current choices :key #'cdr :test #'equal))
              (answer
               (completing-read
                "Base voice; choose a portable family or exact voice: "
                choices nil t nil nil (car-safe initial-entry))))
         (cdr (assoc-string answer choices))))
      ('routed
       (let* ((choices
               (cons
                '("adapter default" . nil)
                (emacsvox-aural-voice-tuner--family-candidates capability)))
              (initial-entry
               (cl-find current choices :key #'cdr :test #'equal))
              (answer
               (string-trim
                (completing-read
                 "Portable fallback family (not the Omnivox route): "
                 choices nil nil nil nil
                 (or (car-safe initial-entry)
                     (and current (format "%s" current))))))
              (entry (assoc-string answer choices)))
         (if entry
             (cdr entry)
           (unless (string-empty-p answer) answer))))
      (_
       (let ((answer
              (string-trim
               (read-string
                "Installed base voice; blank means adapter default: "
                (and current (format "%s" current))))))
         (unless (string-empty-p answer) answer))))))

(defun emacsvox-aural-voice-tuner-edit ()
  "Edit the current dimension and audition the new value."
  (interactive)
  (let* ((dimension (emacsvox-aural-voice-tuner--current-dimension))
         (current (emacsvox-aural-voice-tuner--value dimension))
         (value
          (if (eq dimension 'family)
              (emacsvox-aural-voice-tuner--read-family current)
            (emacsvox-aural-voice-palettes--read-style-number
             dimension current))))
    (emacsvox-aural-voice-tuner--set-value dimension value)))

(defun emacsvox-aural-voice-tuner-undo ()
  "Undo the most recent unsaved tuner change and audition it."
  (interactive)
  (unless emacsvox-aural-voice-tuner-history
    (user-error "No tuner change to undo"))
  (let ((dimension (emacsvox-aural-voice-tuner--current-dimension)))
    (setq
     emacsvox-aural-voice-tuner-working-style
     (pop emacsvox-aural-voice-tuner-history))
    (emacsvox-aural-voice-tuner--update-dirty)
    (emacsvox-aural-voice-tuner-refresh dimension)
    (emacsvox-aural-voice-tuner-audition "Undid the last voice change.")))

(defun emacsvox-aural-voice-tuner-restore ()
  "Restore and audition the style present when the tuner opened."
  (interactive)
  (when
      (equal
       emacsvox-aural-voice-tuner-working-style
       emacsvox-aural-voice-tuner-initial-style)
    (user-error "The starting voice style is already restored"))
  (let ((dimension (emacsvox-aural-voice-tuner--current-dimension)))
    (push
     (copy-tree emacsvox-aural-voice-tuner-working-style)
     emacsvox-aural-voice-tuner-history)
    (setq
     emacsvox-aural-voice-tuner-working-style
     (copy-tree emacsvox-aural-voice-tuner-initial-style))
    (emacsvox-aural-voice-tuner--update-dirty)
    (emacsvox-aural-voice-tuner-refresh dimension)
    (emacsvox-aural-voice-tuner-audition
     "Restored the voice style from when the tuner opened.")))

(defun emacsvox-aural-voice-tuner--refresh-source
    (source palette voice)
  "Refresh SOURCE after saving VOICE in PALETTE and keep VOICE selected."
  (when (buffer-live-p source)
    (with-current-buffer source
      (when
          (and
           (derived-mode-p
            'emacsvox-aural-voice-palette-previews-mode)
           (eq
            emacsvox-aural-voice-palette-previews-palette
            palette))
        (emacsvox-aural-voice-palette-previews-refresh voice)
        (let ((position (point)))
          (dolist (window (get-buffer-window-list source nil t))
            (set-window-point window position))))
      (when (derived-mode-p 'emacsvox-aural-voice-workbench-mode)
        (when (fboundp 'emacsvox-aural-voice-workbench-refresh)
          (funcall 'emacsvox-aural-voice-workbench-refresh
                   (format "%s" voice)))))))

(defun emacsvox-aural-voice-tuner--source-route-staged-p (source)
  "Return non-nil when SOURCE is a Workbench with unsaved routing edits."
  (and
   (buffer-live-p source)
   (with-current-buffer source
     (and
      (derived-mode-p 'emacsvox-aural-voice-workbench-mode)
      (boundp 'emacsvox-aural-voice-workbench-staged-profile)
      (boundp 'emacsvox-aural-voice-workbench-committed-profile)
      (not
       (equal emacsvox-aural-voice-workbench-staged-profile
              emacsvox-aural-voice-workbench-committed-profile))))))

(defun emacsvox-aural-voice-tuner--announce-save
    (source voice style-saved)
  "Announce what was saved for VOICE and whether SOURCE has a staged route."
  (let ((text
         (concat
          (if style-saved
              (format "Portable style for %s saved. " voice)
            (format "No portable style changes for %s. " voice))
          (if (emacsvox-aural-voice-tuner--source-route-staged-p source)
              (concat
               "Its physical route is still staged, not saved. "
               "In Voice Workbench press w to save and apply the route.")
            "No physical route was changed."))))
    (if (fboundp 'tts-speak)
        (tts-speak text)
      (message "%s" text))
    text))

(defun emacsvox-aural-voice-tuner-save ()
  "Atomically save the portable style and return to the voice preview."
  (interactive)
  (let ((source emacsvox-aural-voice-tuner-source-buffer)
        (palette emacsvox-aural-voice-tuner-palette)
        (voice emacsvox-aural-voice-tuner-voice)
        saved)
    (when emacsvox-aural-voice-tuner-dirty
      (emacsvox-aural-voice-palettes--install-entry-definition
       palette voice emacsvox-aural-voice-tuner-working-style)
      (setq
       emacsvox-aural-voice-tuner-original-definition
       (copy-tree emacsvox-aural-voice-tuner-working-style)
       emacsvox-aural-voice-tuner-initial-style
       (copy-tree emacsvox-aural-voice-tuner-working-style)
       emacsvox-aural-voice-tuner-history nil
       emacsvox-aural-voice-tuner-dirty nil
       saved t))
    (emacsvox-aural-quit t)
    (when saved
      (emacsvox-aural-voice-tuner--refresh-source
       source palette voice))
    (emacsvox-aural-voice-tuner--announce-save source voice saved)))

(defun emacsvox-aural-voice-tuner-quit ()
  "Cancel tuning, asking before discarding unsaved changes."
  (interactive)
  (when
      (or
       (not emacsvox-aural-voice-tuner-dirty)
       (yes-or-no-p "Discard unsaved voice tuning changes? "))
    (emacsvox-aural-quit t)))

(defun emacsvox-aural-voice-tuner-help ()
  "Display and speak voice tuner help."
  (interactive)
  (emacsvox-aural-ui-with-help-window
    (princ
     (concat
      "Aural Voice Tuner\n\n"
      "Changes are temporary until saved.  Every adjustment announces the\n"
      "new value and adapter support, then auditions the same comparison text.\n"
      "Unsupported dimensions remain portable but do not affect this adapter.\n"
      "For a routed adapter, Portable Fallback Family is retained for other\n"
      "adapters but does not replace the physical voice chosen in Workbench.\n"
      "Saving a changed personality converts this palette entry to a complete\n"
      "custom ACSS style; cancelling preserves its original definition.\n\n"
      "Tuner w saves only this portable style.  If its physical route is\n"
      "staged in Voice Workbench, return there and press w to save and apply\n"
      "that separate machine-local route.\n\n"
      "n or down next       p or up previous\n"
      "left/right decrease/increase numeric value\n"
      "0 through 9 set numeric value directly\n"
      "RET or e edit        d use adapter default\n"
      "P audition           u undo last change\n"
      "R restore opening style\n"
      "w save style, return C-c C-c save style, return\n"
      "q or C-c C-k cancel and return\n"
      "h aural home         ? help\n")))
  (when (fboundp 'emacsvox-speak-help)
    (emacsvox-speak-help)))

(define-derived-mode
    emacsvox-aural-voice-tuner-mode
    emacsvox-aural-tabulated-mode
  "Aural-Voice-Tuner"
  "Transactional spoken tuner for one personal-palette voice."
  (emacsvox-aural-ui-configure-tabulated
   "voice settings"
   #'emacsvox-aural-voice-tuner-speak-current
   #'emacsvox-aural-voice-tuner-refresh
   #'emacsvox-aural-voice-tuner--speak-setting)
  (setq
   tabulated-list-format
   [("Setting" 22 nil)
    ("Requested" 18 nil)
    ("Auditioned" 18 nil)
    ("Adapter" 28 nil)
    ("Meaning" 0 nil)])
  (setq tabulated-list-padding 2)
  (setq-local
   mode-line-process
   '(:eval (when emacsvox-aural-voice-tuner-dirty " [modified]")))
  (add-hook
   'tabulated-list-revert-hook
   #'emacsvox-aural-voice-tuner--set-entries nil t)
  (tabulated-list-init-header))

(define-key emacsvox-aural-voice-tuner-mode-map (kbd "s") nil)

(dolist
    (binding
     '(("RET" . emacsvox-aural-voice-tuner-edit)
       ("e" . emacsvox-aural-voice-tuner-edit)
       ("d" . emacsvox-aural-voice-tuner-use-default)
       ("P" . emacsvox-aural-voice-tuner-audition)
       ("u" . emacsvox-aural-voice-tuner-undo)
       ("R" . emacsvox-aural-voice-tuner-restore)
       ("w" . emacsvox-aural-voice-tuner-save)
       ("C-c C-c" . emacsvox-aural-voice-tuner-save)
       ("C-c C-k" . emacsvox-aural-voice-tuner-quit)
       ("<right>" . emacsvox-aural-voice-tuner-increase)
       ("<left>" . emacsvox-aural-voice-tuner-decrease)
       ("+" . emacsvox-aural-voice-tuner-increase)
       ("-" . emacsvox-aural-voice-tuner-decrease)
       ("h" . emacsvox-aural)
       ("q" . emacsvox-aural-voice-tuner-quit)
       ("?" . emacsvox-aural-voice-tuner-help)))
  (define-key
   emacsvox-aural-voice-tuner-mode-map
   (kbd (car binding))
   (cdr binding)))

(dotimes (digit 10)
  (define-key
   emacsvox-aural-voice-tuner-mode-map
   (char-to-string (+ ?0 digit))
   #'emacsvox-aural-voice-tuner-set-digit))

(cl-defun emacsvox-aural-voice-tuner-open
    (palette-id voice source text
                &key selector language engine realized)
  "Open a transactional tuner for VOICE in PALETTE-ID.

SOURCE is the manager to return to and TEXT is the comparison text.  When
SELECTOR is non-nil, audition the unsaved style against that staged physical
route using LANGUAGE, discovered ENGINE capabilities, and initial REALIZED
identity."
  (let ((palette (emacsvox-aural-voice-palette palette-id)))
    (when (emacsvox-aural-voice-palette-built-in palette)
      (user-error
       "Built-in palette; press o, then c to make an editable copy"))
    (let* ((inspection-source
            (emacsvox-aural-inspection-remember-source-buffer))
           (definition (emacsvox-aural-voice voice palette-id))
           (style
            (emacsvox-aural-voice-tuner--complete-style
             definition palette-id))
           (buffer (get-buffer-create "*Aural Voice Tuner*")))
      (when
          (with-current-buffer buffer
            (and
             (derived-mode-p 'emacsvox-aural-voice-tuner-mode)
             emacsvox-aural-voice-tuner-dirty))
        (unless
            (yes-or-no-p
             "Discard the unsaved voice tuner before opening another voice? ")
          (user-error "Kept the existing unsaved voice tuner")))
      (with-current-buffer buffer
        (emacsvox-aural-voice-tuner-mode)
        (emacsvox-aural-inspection-attach-source inspection-source)
        (setq
         emacsvox-aural-voice-tuner-palette palette-id
         emacsvox-aural-voice-tuner-voice voice
         emacsvox-aural-voice-tuner-original-definition
         (copy-tree definition)
         emacsvox-aural-voice-tuner-initial-style (copy-tree style)
         emacsvox-aural-voice-tuner-working-style (copy-tree style)
         emacsvox-aural-voice-tuner-history nil
         emacsvox-aural-voice-tuner-dirty nil
         emacsvox-aural-voice-tuner-preview-text text
         emacsvox-aural-voice-tuner-source-buffer source
         emacsvox-aural-voice-tuner-route-selector (copy-tree selector)
         emacsvox-aural-voice-tuner-route-language language
         emacsvox-aural-voice-tuner-route-engine (copy-tree engine)
         emacsvox-aural-voice-tuner-route-realized (copy-tree realized)
         emacsvox-aural-voice-tuner-preview-result nil)
        (emacsvox-aural-voice-tuner-refresh))
      (emacsvox-aural-ui-pop-to-buffer buffer)
      (emacsvox-aural-voice-tuner-speak-current)
      buffer)))

(defun emacsvox-aural-voice-palette-previews-tune ()
  "Open a transactional tuner for the effective voice at point."
  (interactive)
  (let* ((voice
          (emacsvox-aural-voice-palette-previews--current-voice))
         (palette
          (emacsvox-aural-voice-palette-previews--editable-palette)))
    (emacsvox-aural-voice-palette-previews-refresh voice)
    (emacsvox-aural-voice-tuner-open
     palette voice (current-buffer)
     emacsvox-aural-voice-palette-previews-text)))

(defun emacsvox-aural-voice-palette-previews-new ()
  "Create a new voice in the palette shown by the current preview."
  (interactive)
  (let* ((palette
          (emacsvox-aural-voice-palette-previews--editable-palette))
         (voice
          (emacsvox-aural-voice-palettes--read-new-entry-name palette))
         (definition
          (emacsvox-aural-voice-palettes--read-definition)))
    (emacsvox-aural-voice-palettes--install-entry-definition
     palette voice definition)
    (emacsvox-aural-voice-palette-previews-refresh voice)
    voice))

(defun emacsvox-aural-voice-palette-previews-copy ()
  "Copy the current voice to a new, independently routable voice."
  (interactive)
  (let* ((source-palette
          emacsvox-aural-voice-palette-previews-palette)
         (source-voice
          (emacsvox-aural-voice-palette-previews--current-voice))
         (definition
          (or
           (emacsvox-aural-voice source-voice source-palette)
           (user-error "Unknown voice: %s" source-voice)))
         (style
          (emacsvox-aural-voice-tuner--complete-style
           definition source-palette))
         (palette
          (emacsvox-aural-voice-palette-previews--editable-palette))
         (voice
          (emacsvox-aural-voice-palettes--read-new-entry-name
           palette (format "%s-copy" source-voice))))
    (emacsvox-aural-voice-palettes--install-entry-definition
     palette voice style)
    (emacsvox-aural-voice-palette-previews-refresh voice)
    voice))

(defun emacsvox-aural-voice-palette-previews-help ()
  "Display and speak voice-palette preview help."
  (interactive)
  (emacsvox-aural-ui-with-help-window
    (princ
     (concat
      "Aural Voice Palette Preview\n\n"
      "Each row is one effective voice, including inherited voices.  Every\n"
      "audition uses the same comparison text so differences are easier to\n"
      "hear.  The voice name is spoken in the voice being auditioned.\n\n"
      "n or down next       p or up previous\n"
      "left/right column    . speak titled cell\n"
      "RET or P preview     A preview every voice\n"
      "T comparison text    S stop preview\n"
      "SPC speak voice      t tune voice\n"
      "e also tunes; s also stops for compatibility\n"
      "c copy voice         N new voice\n"
      "E replace definition\n"
      "Editing a built-in creates one active personal overlay\n"
      "x explain voice\n"
      "g refresh            o palette manager\n"
      "h aural home         q quit\n")))
  (when (fboundp 'emacsvox-speak-help)
    (emacsvox-speak-help)))

(define-derived-mode
    emacsvox-aural-voice-palette-previews-mode
    emacsvox-aural-tabulated-mode
  "Aural-Voice-Preview"
  "Spoken browser for effective voices in one palette."
  (emacsvox-aural-ui-configure-tabulated
   "palette voices"
   #'emacsvox-aural-voice-palette-previews-speak-current
   #'emacsvox-aural-voice-palette-previews-refresh
   nil
   #'emacsvox-aural-voice-palette-previews--remember-current)
  (setq
   tabulated-list-format
   [("Voice" 24 t)
    ("Source" 22 t)
    ("Requested" 42 t)
    ("Effective" 48 t)
    ("Status" 0 t)])
  (setq tabulated-list-padding 2)
  (add-hook
   'tabulated-list-revert-hook
   #'emacsvox-aural-voice-palette-previews--set-entries nil t)
  (tabulated-list-init-header))

(dolist
    (binding
     '(("RET" . emacsvox-aural-voice-palette-previews-play)
       ("P" . emacsvox-aural-voice-palette-previews-play)
       ("A" . emacsvox-aural-voice-palette-previews-play-all)
       ("t" . emacsvox-aural-voice-palette-previews-tune)
       ("T" . emacsvox-aural-voice-palette-previews-set-text)
       ("s" . emacsvox-aural-voice-palette-previews-stop)
       ("S" . emacsvox-aural-voice-palette-previews-stop)
       ("e" . emacsvox-aural-voice-palette-previews-tune)
       ("E" . emacsvox-aural-voice-palette-previews-edit)
       ("c" . emacsvox-aural-voice-palette-previews-copy)
       ("N" . emacsvox-aural-voice-palette-previews-new)
       ("x" . emacsvox-aural-voice-palette-previews-explain)
       ("o" . emacsvox-aural-voice-palette-previews-open-manager)
       ("h" . emacsvox-aural)
       ("?" . emacsvox-aural-voice-palette-previews-help)))
  (define-key
   emacsvox-aural-voice-palette-previews-mode-map
   (kbd (car binding))
   (cdr binding)))

(defun emacsvox-aural-list-voice-palette-previews
    (palette &optional voice speak)
  "Open the spoken effective-voice browser for PALETTE.

VOICE selects the initial row.  When SPEAK is non-nil, announce that row
after displaying the preview buffer."
  (let ((source
         (emacsvox-aural-inspection-remember-source-buffer))
        (entries (emacsvox-aural-voice-palettes--preview-entries palette))
        (buffer (get-buffer-create "*Aural Voice Palette Preview*")))
    (unless entries
      (user-error "Voice palette %s has no effective voices" palette))
    (with-current-buffer buffer
      (emacsvox-aural-voice-palette-previews-mode)
      (emacsvox-aural-inspection-attach-source source)
      (setq
       emacsvox-aural-voice-palette-previews-palette palette
       emacsvox-aural-voice-palette-previews-entries entries
       emacsvox-aural-voice-palette-previews-text
       emacsvox-aural-voice-palettes-preview-text)
      (emacsvox-aural-voice-palette-previews-refresh voice))
    (emacsvox-aural-ui-pop-to-buffer buffer)
    (when (and speak (tabulated-list-get-id))
      (emacsvox-aural-voice-palette-previews-speak-current))
    buffer))

(defun emacsvox-aural-voice-palettes-preview (&optional id)
  "Browse and audition all effective voices in palette ID or at point."
  (interactive)
  (let ((id (or id (emacsvox-aural-voice-palettes--at-point-or-read))))
    (emacsvox-aural-list-voice-palette-previews
     id nil (called-interactively-p 'interactive))))

(defun emacsvox-aural-voice-palettes-explain (&optional id voice)
  "Explain one effective voice and its adapter fallback."
  (interactive)
  (let* ((id (or id (emacsvox-aural-voice-palettes--at-point-or-read)))
         (voice
          (or
           voice
           (emacsvox-aural-voice-palettes--read-voice
            id "Voice to explain: ")))
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
    (emacsvox-aural-ui-with-help-window
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
  (emacsvox-aural-ui-with-help-window
    (princ
     (concat
      "Aural Voice Palettes\n\n"
      "A named voice is a complete preset. A rule may layer explicit ACSS\n"
      "dimensions over that preset. Custom named presets therefore ask for\n"
      "all five dimensions; blank values mean the adapter default.\n\n"
      "n or down next       p or up previous\n"
      "left/right column    . speak titled cell\n"
      "RET browse voices    SPC speak palette\n"
      "a activate override  f follow active scheme\n"
      "N create palette     c copy palette\n"
      "e edit voice         E edit summary and parent\n"
      "D delete voice       d delete palette\n"
      "B or P browse voices x explain voice\n"
      "In the voice list, N creates and c copies a voice\n"
      "v view and validate  g refresh\n"
      "h aural home         q quit\n")))
  (when (fboundp 'emacsvox-speak-help)
    (emacsvox-speak-help)))

(define-derived-mode
    emacsvox-aural-voice-palettes-mode
    emacsvox-aural-tabulated-mode
  "Aural-Voice-Palettes"
  "Spoken manager for inherited ACSS voice palettes."
  (emacsvox-aural-ui-configure-tabulated
   "voice palettes"
   #'emacsvox-aural-voice-palettes-speak-current
   #'emacsvox-aural-voice-palettes-refresh)
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
     '(("RET" . emacsvox-aural-voice-palettes-preview)
       ("B" . emacsvox-aural-voice-palettes-preview)
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
       ("h" . emacsvox-aural)
       ("?" . emacsvox-aural-voice-palettes-help)))
  (define-key
   emacsvox-aural-voice-palettes-mode-map
   (kbd (car binding))
   (cdr binding)))

;;;###autoload
(defun emacsvox-aural-list-voice-palettes (&optional palette)
  "Open the spoken manager for voice PALETTE providers."
  (interactive)
  (let ((source
         (emacsvox-aural-inspection-remember-source-buffer))
        (buffer (get-buffer-create "*Aural Voice Palettes*")))
    (with-current-buffer buffer
      (emacsvox-aural-voice-palettes-mode)
      (emacsvox-aural-inspection-attach-source source)
      (emacsvox-aural-voice-palettes-refresh
       (or palette (emacsvox-aural-voice-palettes--active-id))))
    (emacsvox-aural-ui-pop-to-buffer buffer)
    (when (called-interactively-p 'interactive)
      (emacsvox-aural-voice-palettes-speak-current))
    buffer))

(provide 'emacsvox-aural-voice-palettes)
;;; emacsvox-aural-voice-palettes.el ends here
