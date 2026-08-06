;;; emacsvox-aural-voice-workbench.el --- Spoken voice routing UI -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; A single accessible workbench presents logical voices, physical inventory,
;; engines, and portable style/effect information. Transactional previews use
;; the same sample text without changing saved palettes or routing profiles.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'tabulated-list)
(require 'tts-speak)
(require 'emacsvox-aural-resources)
(require 'emacsvox-aural-schemes)
(require 'emacsvox-aural-routing-profiles)
(require 'emacsvox-aural-ui)
(require 'emacsvox-aural-inspection)
(require 'emacsvox-aural-preview)

(declare-function emacsvox-aural "emacsvox-aural-home"
                  (&optional source-buffer))
(declare-function emacsvox-speak-help "emacsvox-speak" ())
(declare-function tts-speak "tts-speak" (text))

(defcustom emacsvox-aural-voice-workbench-preview-text
  "The quick brown fox jumps over the lazy dog."
  "Common text used for Voice Workbench preview and A/B comparison."
  :group 'emacsvox-aural
  :type 'string)

(defconst emacsvox-aural-voice-workbench--views
  '((logical . "Logical voices")
    (physical . "Physical voices")
    (engines . "Engines")
    (styles . "Styles and effects"))
  "Workbench view identifiers and spoken titles.")

(defvar-local emacsvox-aural-voice-workbench-view 'logical
  "View displayed by the current Voice Workbench.")

(defvar-local emacsvox-aural-voice-workbench-inventory nil
  "Normalized speech-adapter inventory displayed by this workbench.")

(defvar-local emacsvox-aural-voice-workbench-committed-profile nil
  "Routing-profile snapshot committed when this workbench opened.")

(defvar-local emacsvox-aural-voice-workbench-staged-profile nil
  "Mutable routing-profile snapshot staged in this workbench.")

(defvar-local emacsvox-aural-voice-workbench-selections nil
  "Hash table retaining the selected row in each workbench view.")

(defvar-local emacsvox-aural-voice-workbench-filter nil
  "Physical-voice filter plist for this workbench.")

(defvar-local emacsvox-aural-voice-workbench-last-preview nil
  "Most recent normalized preview result in this workbench.")

(defvar-local emacsvox-aural-voice-workbench-assignment-target nil
  "Logical voice receiving a staged assignment from the physical view.")

(defvar-local emacsvox-aural-voice-workbench-assignment-return-filter nil
  "Physical filter restored after completing or cancelling assignment.")

(defvar-local emacsvox-aural-voice-workbench-undo-stack nil
  "Snapshots preceding staged Voice Workbench routing edits.")

(defvar-local emacsvox-aural-voice-workbench-last-edit nil
  "Description of the most recent staged routing edit.")

(defun emacsvox-aural-voice-workbench--active-palette ()
  "Return the currently effective portable voice palette."
  (or
   emacsvox-aural-voice-palette-override
   (emacsvox-aural-effective-scheme-provider 'voice-palette)
   'acss-default))

(defun emacsvox-aural-voice-workbench--current-profile-data ()
  "Return a safe routing snapshot for a newly opened workbench."
  (if-let* ((entry
             (emacsvox-aural-routing-profile
              emacsvox-aural-active-routing-profile)))
      (copy-tree (emacsvox-aural-routing-profile-entry-data entry))
    (emacsvox-aural-routing-profile-from-omnivox
     'current-runtime "Current unsaved adapter routing")))

(defun emacsvox-aural-voice-workbench--dirty-p ()
  "Return non-nil when staged routing differs from committed routing."
  (not
   (equal emacsvox-aural-voice-workbench-staged-profile
          emacsvox-aural-voice-workbench-committed-profile)))

(defun emacsvox-aural-voice-workbench--inventory-counts ()
  "Return the engine and physical voice counts in the current inventory."
  (let ((engines
         (plist-get emacsvox-aural-voice-workbench-inventory :engines))
        (voices 0))
    (dolist (engine engines)
      (cl-incf voices (length (plist-get engine :voices))))
    (cons (length engines) voices)))

(defun emacsvox-aural-voice-workbench--age-description ()
  "Return concise inventory age text."
  (if-let* ((age
             (plist-get
              emacsvox-aural-voice-workbench-inventory :age-seconds)))
      (cond
       ((< age 1) "now")
       ((< age 60) (format "%d seconds" (floor age)))
       ((< age 3600) (format "%d minutes" (floor (/ age 60))))
       (t (format "%d hours" (floor (/ age 3600)))))
    "not timed"))

(defun emacsvox-aural-voice-workbench--filter-description ()
  "Return concise physical filter text."
  (let (parts)
    (cl-loop
     for (key value) on emacsvox-aural-voice-workbench-filter by #'cddr
     when value
     do (push (format "%s=%s" (substring (symbol-name key) 1) value) parts))
    (if parts (mapconcat #'identity (nreverse parts) ",") "none")))

(defun emacsvox-aural-voice-workbench--header ()
  "Return the non-speaking status header for the current workbench."
  (let* ((inventory emacsvox-aural-voice-workbench-inventory)
         (counts (emacsvox-aural-voice-workbench--inventory-counts))
         (generation (plist-get inventory :generation))
         (profile (or (plist-get
                       emacsvox-aural-voice-workbench-staged-profile :id)
                      "none")))
    (format
     (concat
      " %s | adapter %s | inventory %s%s, generation %s, age %s | "
      "%d engines, %d voices | processes %s | routing %s, %s | filter %s | "
      "assignment %s | preview %s ")
     (alist-get emacsvox-aural-voice-workbench-view
                emacsvox-aural-voice-workbench--views)
     (or (plist-get inventory :adapter) "unknown")
     (or (plist-get inventory :source) "unknown")
     (if (plist-get inventory :stale) " stale" "")
     (or generation "none")
     (emacsvox-aural-voice-workbench--age-description)
     (car counts) (cdr counts)
     (or (plist-get inventory :process-agreement) "unknown")
     profile
     (if (emacsvox-aural-voice-workbench--dirty-p) "staged" "committed")
     (emacsvox-aural-voice-workbench--filter-description)
     (or emacsvox-aural-voice-workbench-assignment-target "none")
     (or (plist-get emacsvox-aural-voice-workbench-last-preview :status)
         "not run"))))

(defun emacsvox-aural-voice-workbench-status ()
  "Return concise Voice Workbench status for Aural Home."
  (let* ((inventory (tts-voice-inventory))
         (engines (plist-get inventory :engines))
         (voices
          (cl-loop for engine in engines
                   sum (length (plist-get engine :voices)))))
    (format
     "%s; %s%s; %d engine%s, %d voice%s; routing %s"
     (or (plist-get inventory :adapter) "unknown adapter")
     (or (plist-get inventory :source) "unknown inventory")
     (if (plist-get inventory :stale) " stale" "")
     (length engines) (if (= (length engines) 1) "" "s")
     voices (if (= voices 1) "" "s")
     (or emacsvox-aural-active-routing-profile "runtime"))))

(defun emacsvox-aural-voice-workbench--profile-binding (logical-voice)
  "Return staged routing binding for LOGICAL-VOICE."
  (let ((name (format "%s" logical-voice)))
    (cl-find-if
     (lambda (binding)
       (equal name (format "%s" (plist-get binding :logical-voice))))
     (plist-get emacsvox-aural-voice-workbench-staged-profile :bindings))))

(defun emacsvox-aural-voice-workbench--selectors (logical-voice)
  "Return staged effective selectors for LOGICAL-VOICE."
  (emacsvox-aural-routing-selectors-from-data
   logical-voice emacsvox-aural-voice-workbench-staged-profile t))

(defun emacsvox-aural-voice-workbench--logical-voices ()
  "Return stable logical voice names visible in the current workbench."
  (let ((table (make-hash-table :test #'equal))
        (palette (emacsvox-aural-voice-workbench--active-palette)))
    (dolist
        (binding
         (plist-get emacsvox-aural-voice-workbench-staged-profile :bindings))
      (puthash (format "%s" (plist-get binding :logical-voice)) t table))
    (dolist (binding emacsvox-aural-session-routing-bindings)
      (puthash (format "%s" (car binding)) t table))
    (when (emacsvox-aural-voice-palette palette)
      (dolist (entry (emacsvox-aural-effective-voice-entries palette))
        (puthash
         (format "%s" (if (symbolp (cdr entry)) (cdr entry) (car entry)))
         t table)))
    (let (names)
      (maphash (lambda (name _) (push name names)) table)
      (sort names #'string-lessp))))

(defun emacsvox-aural-voice-workbench--selector-description (selector)
  "Return concise display text for routing SELECTOR."
  (pcase (plist-get selector :kind)
    ('exact
     (format "%s/%s [%s]"
             (plist-get selector :engine-id)
             (plist-get selector :voice-id)
             (plist-get selector :scope)))
    ('engine-default
     (format "%s default [%s]"
             (plist-get selector :engine-id)
             (plist-get selector :scope)))
    ('properties
     (let (traits)
       (dolist (property '(:engine-id :language :gender))
         (when-let* ((value (plist-get selector property)))
           (push (format "%s" value) traits)))
       (format "%s properties [%s]"
               (if traits (mapconcat #'identity (nreverse traits) "/") "any")
               (plist-get selector :scope))))
    (_ "invalid selector")))

(defun emacsvox-aural-voice-workbench--route-description (logical-voice)
  "Return concise staged route text for LOGICAL-VOICE."
  (if-let* ((selectors
             (emacsvox-aural-voice-workbench--selectors logical-voice)))
      (mapconcat
       #'emacsvox-aural-voice-workbench--selector-description selectors " then ")
    "adapter default"))

(defun emacsvox-aural-voice-workbench--scope-description (logical-voice)
  "Return distinct selector scopes for LOGICAL-VOICE."
  (let ((scopes
         (delete-dups
          (mapcar
           (lambda (selector) (plist-get selector :scope))
           (emacsvox-aural-voice-workbench--selectors logical-voice)))))
    (if scopes (mapconcat #'symbol-name scopes ", ") "inherited")))

(defun emacsvox-aural-voice-workbench--palette-entry (logical-voice)
  "Return palette entry associated with LOGICAL-VOICE."
  (let ((name (format "%s" logical-voice))
        (palette (emacsvox-aural-voice-workbench--active-palette)))
    (and
     (emacsvox-aural-voice-palette palette)
     (cl-find-if
      (lambda (entry)
        (or (equal name (format "%s" (car entry)))
            (and (symbolp (cdr entry))
                 (equal name (symbol-name (cdr entry))))))
      (emacsvox-aural-effective-voice-entries palette)))))

(defun emacsvox-aural-voice-workbench--palette-aliases (logical-voice)
  "Return active palette names resolving to LOGICAL-VOICE."
  (let ((name (format "%s" logical-voice))
        (palette (emacsvox-aural-voice-workbench--active-palette))
        aliases)
    (when (emacsvox-aural-voice-palette palette)
      (dolist (entry (emacsvox-aural-effective-voice-entries palette))
        (let ((definition (cdr entry)))
          (when
              (or (equal name (format "%s" (car entry)))
                  (and (symbolp definition)
                       (equal name (symbol-name definition))))
            (push (symbol-name (car entry)) aliases)))))
    (sort (delete-dups aliases) #'string-lessp)))

(defun emacsvox-aural-voice-workbench--style-description (logical-voice)
  "Return concise portable style text for LOGICAL-VOICE."
  (if-let* ((entry
             (emacsvox-aural-voice-workbench--palette-entry logical-voice)))
      (let* ((definition (cdr entry))
             (realized
              (if (and (symbolp definition) (boundp definition))
                  (symbol-value definition)
                definition)))
        (string-trim
         (replace-regexp-in-string
          "[\n\t ]+" " " (format "%S" realized))))
    "not in active palette"))

(defun emacsvox-aural-voice-workbench--family-diagnostic (logical-voice)
  "Return concise exact-route/family status for LOGICAL-VOICE."
  (let* ((entry (emacsvox-aural-voice-workbench--palette-entry logical-voice))
         (definition
          (if entry
              (let ((value (cdr entry)))
                (if (and (symbolp value) (boundp value))
                    (symbol-value value)
                  value))
            logical-voice))
         (family
          (emacsvox-aural-routing--style-family definition))
         (exact
          (cl-find-if
           (lambda (selector) (eq (plist-get selector :kind) 'exact))
           (emacsvox-aural-voice-workbench--selectors logical-voice))))
    (if (and family exact)
        (format "exact voice; %s family retained for fallback" family)
      "none")))

(defun emacsvox-aural-voice-workbench--logical-row (logical-voice)
  "Return one logical voice row for LOGICAL-VOICE."
  (let* ((binding
          (emacsvox-aural-voice-workbench--profile-binding logical-voice))
         (route
          (emacsvox-aural-voice-workbench--route-description logical-voice))
         (palette (emacsvox-aural-voice-workbench--active-palette)))
    (list
     logical-voice
     (vector
      (format "%s" palette)
      (emacsvox-aural-voice-workbench--join-symbols
       (emacsvox-aural-voice-workbench--palette-aliases logical-voice))
      logical-voice
      (emacsvox-aural-voice-workbench--style-description logical-voice)
      route
      (emacsvox-aural-voice-workbench--realization-description logical-voice)
      (or (plist-get binding :language) "")
      (emacsvox-aural-voice-workbench--scope-description logical-voice)
      (if (equal route "adapter default") "unmapped" "routed")
      (emacsvox-aural-voice-workbench--family-diagnostic logical-voice)))))

(defun emacsvox-aural-voice-workbench--all-engine-voices ()
  "Return (ENGINE VOICE) pairs from the current inventory."
  (cl-loop
   for engine in (plist-get emacsvox-aural-voice-workbench-inventory :engines)
   append (mapcar (lambda (voice) (list engine voice))
                  (plist-get engine :voices))))

(defun emacsvox-aural-voice-workbench--same-value-p (left right)
  "Return non-nil when optional inventory values LEFT and RIGHT match."
  (and left right (string-equal (downcase (format "%s" left))
                                (downcase (format "%s" right)))))

(defun emacsvox-aural-voice-workbench--display (value &optional fallback)
  "Return VALUE as display text, using FALLBACK when it is nil."
  (if (null value) (or fallback "") (format "%s" value)))

(defun emacsvox-aural-voice-workbench--selector-matches-p
    (selector engine voice)
  "Return non-nil when SELECTOR can select VOICE from ENGINE."
  (let ((engine-id (plist-get engine :engine-id))
        (voice-id (plist-get voice :voice-id)))
    (pcase (plist-get selector :kind)
      ('exact
       (and (equal engine-id (plist-get selector :engine-id))
            (equal voice-id (plist-get selector :voice-id))))
      ('engine-default
       (and (equal engine-id (plist-get selector :engine-id))
            (equal voice-id (plist-get engine :default-voice-id))))
      ('properties
       (and
        (or (null (plist-get selector :engine-id))
            (equal engine-id (plist-get selector :engine-id)))
        (or (null (plist-get selector :language))
            (emacsvox-aural-voice-workbench--same-value-p
             (plist-get selector :language) (plist-get voice :language)))
        (or (null (plist-get selector :gender))
            (emacsvox-aural-voice-workbench--same-value-p
             (plist-get selector :gender) (plist-get voice :gender))))))))

(defun emacsvox-aural-voice-workbench--selector-realization (selector)
  "Return the first installed engine/voice pair matching SELECTOR."
  (cl-find-if
   (lambda (pair)
     (let ((engine (car pair)) (voice (cadr pair)))
       (and
        (equal (plist-get engine :availability) "available")
        (equal (plist-get voice :availability) "available")
        (emacsvox-aural-voice-workbench--selector-matches-p
         selector engine voice))))
   (emacsvox-aural-voice-workbench--all-engine-voices)))

(defun emacsvox-aural-voice-workbench--realization-description
    (logical-voice)
  "Return the currently predicted installed route for LOGICAL-VOICE."
  (let ((selectors
         (emacsvox-aural-voice-workbench--selectors logical-voice))
        found)
    (while (and selectors (not found))
      (setq found
            (emacsvox-aural-voice-workbench--selector-realization
             (pop selectors))))
    (if found
        (format "%s/%s"
                (plist-get (car found) :engine-id)
                (plist-get (cadr found) :voice-id))
      (if (emacsvox-aural-voice-workbench--selectors logical-voice)
          "unavailable"
        "adapter default"))))

(defun emacsvox-aural-voice-workbench--voice-users (engine voice)
  "Return logical voices whose staged selectors can match ENGINE and VOICE."
  (let (users)
    (dolist (logical (emacsvox-aural-voice-workbench--logical-voices))
      (when
          (cl-some
           (lambda (selector)
             (emacsvox-aural-voice-workbench--selector-matches-p
              selector engine voice))
           (emacsvox-aural-voice-workbench--selectors logical))
        (push logical users)))
    (sort users #'string-lessp)))

(defun emacsvox-aural-voice-workbench--filter-match-p (key actual)
  "Return non-nil when physical filter KEY accepts ACTUAL."
  (let ((wanted (plist-get emacsvox-aural-voice-workbench-filter key)))
    (or (null wanted)
        (emacsvox-aural-voice-workbench--same-value-p wanted actual))))

(defun emacsvox-aural-voice-workbench--physical-visible-p (engine voice)
  "Return non-nil when ENGINE and VOICE pass the physical filter."
  (and
   (emacsvox-aural-voice-workbench--filter-match-p
    :engine (plist-get engine :engine-id))
   (emacsvox-aural-voice-workbench--filter-match-p
    :language (plist-get voice :language))
   (emacsvox-aural-voice-workbench--filter-match-p
    :gender (plist-get voice :gender))
   (emacsvox-aural-voice-workbench--filter-match-p
    :quality (plist-get voice :quality))
   (emacsvox-aural-voice-workbench--filter-match-p
    :health (plist-get engine :health))
   (emacsvox-aural-voice-workbench--filter-match-p
    :availability (plist-get voice :availability))))

(defun emacsvox-aural-voice-workbench--physical-row (pair)
  "Return one physical voice row from engine/voice PAIR."
  (let* ((engine (car pair))
         (voice (cadr pair))
         (users (emacsvox-aural-voice-workbench--voice-users engine voice)))
    (list
     (list (plist-get engine :engine-id) (plist-get voice :voice-id))
     (vector
      (emacsvox-aural-voice-workbench--display
       (or (plist-get voice :display-name) (plist-get voice :voice-id)))
      (emacsvox-aural-voice-workbench--display
       (plist-get engine :engine-id))
      (emacsvox-aural-voice-workbench--display
       (plist-get voice :language))
      (emacsvox-aural-voice-workbench--display
       (plist-get voice :gender))
      (emacsvox-aural-voice-workbench--display
       (plist-get voice :quality))
      (emacsvox-aural-voice-workbench--display
       (plist-get voice :availability) "unknown")
      (emacsvox-aural-voice-workbench--display
       (plist-get engine :health) "unknown")
      (if users (mapconcat #'identity users ", ") "none")
      (emacsvox-aural-voice-workbench--display
       (plist-get voice :voice-id))))))

(defun emacsvox-aural-voice-workbench--join-symbols (values)
  "Return printable comma-separated VALUES."
  (if values (mapconcat (lambda (value) (format "%s" value)) values ", ") "none"))

(defun emacsvox-aural-voice-workbench--engine-row (engine)
  "Return one speech ENGINE row."
  (let* ((id (plist-get engine :engine-id))
         (order
          (cl-position
           id
           (plist-get emacsvox-aural-voice-workbench-staged-profile
                      :engine-order)
           :test #'equal)))
    (list
     id
     (vector
      id
      (or (plist-get engine :display-name) id)
      (if order (number-to-string (1+ order))
        (if (equal id
                   (plist-get emacsvox-aural-voice-workbench-inventory
                              :preferred-engine-id))
            "preferred" ""))
      (or (plist-get engine :availability) "unknown")
      (or (plist-get engine :health) "unknown")
      (number-to-string (length (plist-get engine :voices)))
      (emacsvox-aural-voice-workbench--join-symbols
       (plist-get engine :acss-dimensions))
      (string-trim
       (replace-regexp-in-string
        "[\n\t ]+" " "
        (format "%S" (plist-get (plist-get engine :capabilities) :markers))))
      (or (plist-get engine :preview-support) "unknown")
      (or (plist-get engine :routing-policy-support) "unknown")))))

(defun emacsvox-aural-voice-workbench--post-effects ()
  "Return union of advertised post-synthesis effect dimensions."
  (let (effects)
    (dolist
        (engine
         (plist-get emacsvox-aural-voice-workbench-inventory :engines))
      (setq effects
            (append (plist-get engine :post-synthesis-dimensions) effects)))
    (delete-dups effects)))

(defun emacsvox-aural-voice-workbench--style-row (entry)
  "Return one active palette style/effect row for ENTRY."
  (let* ((palette-voice (car entry))
         (definition (cdr entry))
         (logical
          (format "%s" (if (symbolp definition) definition palette-voice)))
         (effects (emacsvox-aural-voice-workbench--post-effects))
         (dimensions
          (plist-get (tts-voice-capabilities) :dimensions)))
    (list
     logical
     (vector
      (format "%s" palette-voice)
      logical
      (emacsvox-aural-voice-workbench--style-description logical)
      (emacsvox-aural-voice-workbench--route-description logical)
      (emacsvox-aural-voice-workbench--join-symbols dimensions)
      (if effects
          (emacsvox-aural-voice-workbench--join-symbols effects)
        "not advertised")
      (emacsvox-aural-voice-workbench--family-diagnostic logical)))))

(defun emacsvox-aural-voice-workbench--format ()
  "Return tabulated columns for the active workbench view."
  (pcase emacsvox-aural-voice-workbench-view
    ('logical
     [("Palette" 16 t) ("Aliases" 24 t) ("Logical voice" 28 t)
      ("Requested style" 34 t) ("Selector order" 48 t)
      ("Current realization" 30 t) ("Language" 12 t) ("Scope" 16 t)
      ("Status" 12 t) ("Diagnostic" 0 t)])
    ('physical
     [("Physical voice" 28 t) ("Engine" 14 t) ("Language" 12 t)
      ("Gender" 10 t) ("Quality" 12 t) ("Availability" 14 t)
      ("Health" 12 t) ("Selected by" 28 t) ("Native ID" 0 t)])
    ('engines
     [("Engine ID" 16 t) ("Engine" 20 t) ("Priority" 10 t)
      ("Availability" 14 t) ("Health" 12 t) ("Voices" 8 t)
      ("ACSS" 32 t) ("Markers" 24 t) ("Preview" 14 t)
      ("Routing" 0 t)])
    ('styles
     [("Palette voice" 22 t) ("Logical voice" 26 t)
      ("Portable definition" 38 t) ("Staged route" 42 t)
      ("Adapter ACSS" 30 t) ("Post effects" 24 t)
      ("Diagnostic" 0 t)])))

(defun emacsvox-aural-voice-workbench--entries ()
  "Return rows for the active workbench view."
  (pcase emacsvox-aural-voice-workbench-view
    ('logical
     (mapcar #'emacsvox-aural-voice-workbench--logical-row
             (emacsvox-aural-voice-workbench--logical-voices)))
    ('physical
     (mapcar
      #'emacsvox-aural-voice-workbench--physical-row
      (cl-remove-if-not
       (lambda (pair)
         (emacsvox-aural-voice-workbench--physical-visible-p
          (car pair) (cadr pair)))
       (emacsvox-aural-voice-workbench--all-engine-voices))))
    ('engines
     (mapcar
      #'emacsvox-aural-voice-workbench--engine-row
      (plist-get emacsvox-aural-voice-workbench-inventory :engines)))
    ('styles
     (let ((palette (emacsvox-aural-voice-workbench--active-palette)))
       (if (emacsvox-aural-voice-palette palette)
           (mapcar
            #'emacsvox-aural-voice-workbench--style-row
            (sort
             (copy-sequence (emacsvox-aural-effective-voice-entries palette))
             (lambda (left right)
               (string-lessp (symbol-name (car left))
                             (symbol-name (car right))))))
         nil)))))

(defun emacsvox-aural-voice-workbench--physical-pair (id)
  "Return the physical engine/voice pair identified by ID."
  (cl-find-if
   (lambda (pair)
     (equal id
            (list (plist-get (car pair) :engine-id)
                  (plist-get (cadr pair) :voice-id))))
   (emacsvox-aural-voice-workbench--all-engine-voices)))

(defun emacsvox-aural-voice-workbench--explicit-selectors (logical-voice)
  "Return LOGICAL-VOICE's explicitly staged selectors."
  (copy-tree
   (plist-get
    (emacsvox-aural-voice-workbench--profile-binding logical-voice)
    :selectors)))

(defun emacsvox-aural-voice-workbench--replace-binding
    (logical-voice selectors &optional inferred-language)
  "Stage SELECTORS for LOGICAL-VOICE, retaining or inferring language."
  (let* ((name (format "%s" logical-voice))
         (bindings
          (plist-get emacsvox-aural-voice-workbench-staged-profile :bindings))
         (old (emacsvox-aural-voice-workbench--profile-binding logical-voice))
         (voice (or (plist-get old :logical-voice) (intern name)))
         (language (or (plist-get old :language) inferred-language))
         (replacement
          (append
           (list :logical-voice voice)
           (and language (list :language language))
           (list :selectors selectors))))
    (if old
        (setq bindings
              (mapcar (lambda (binding)
                        (if (eq binding old) replacement binding))
                      bindings))
      (setq bindings (append bindings (list replacement))))
    (setq emacsvox-aural-voice-workbench-staged-profile
          (plist-put emacsvox-aural-voice-workbench-staged-profile
                     :bindings bindings))))

(defun emacsvox-aural-voice-workbench--announce (format-string &rest arguments)
  "Speak or display FORMAT-STRING with ARGUMENTS."
  (let ((text (apply #'format format-string arguments)))
    (if (fboundp 'tts-speak) (tts-speak text) (message "%s" text))
    text))

(defun emacsvox-aural-voice-workbench--stage (description mutation)
  "Apply MUTATION to the staged profile and record DESCRIPTION for undo."
  (let ((before (copy-tree emacsvox-aural-voice-workbench-staged-profile)))
    (condition-case error-data
        (progn
          (funcall mutation)
          (setq emacsvox-aural-voice-workbench-staged-profile
                (emacsvox-aural-validate-routing-profile-data
                 emacsvox-aural-voice-workbench-staged-profile))
          (if (equal before emacsvox-aural-voice-workbench-staged-profile)
              (progn
                (emacsvox-aural-voice-workbench--announce
                 "No routing changes were needed")
                nil)
            (push (list :profile before :description description)
                  emacsvox-aural-voice-workbench-undo-stack)
            (setq emacsvox-aural-voice-workbench-last-edit description)
            (emacsvox-aural-voice-workbench-refresh)
            (emacsvox-aural-voice-workbench--announce
             "%s staged. Save is not yet applied" description)
            t))
      (error
       (setq emacsvox-aural-voice-workbench-staged-profile before)
       (signal (car error-data) (cdr error-data))))))

(defun emacsvox-aural-voice-workbench--current-logical-voice ()
  "Return the logical voice represented by the current row."
  (unless (memq emacsvox-aural-voice-workbench-view '(logical styles))
    (user-error "Switch to a logical voice or style row first"))
  (or (tabulated-list-get-id)
      (user-error "Move to a logical voice row first")))

(defun emacsvox-aural-voice-workbench--assignment-filter (logical-voice)
  "Return a useful physical candidate filter for LOGICAL-VOICE."
  (let* ((binding
          (emacsvox-aural-voice-workbench--profile-binding logical-voice))
         (language (plist-get binding :language))
         (filter (copy-tree emacsvox-aural-voice-workbench-filter)))
    (if language (plist-put filter :language language) filter)))

(defun emacsvox-aural-voice-workbench-begin-assignment ()
  "Open the filtered physical browser for the current logical voice."
  (interactive)
  (let ((logical (emacsvox-aural-voice-workbench--current-logical-voice)))
    (setq emacsvox-aural-voice-workbench-assignment-target logical
          emacsvox-aural-voice-workbench-assignment-return-filter
          (copy-tree emacsvox-aural-voice-workbench-filter)
          emacsvox-aural-voice-workbench-filter
          (emacsvox-aural-voice-workbench--assignment-filter logical)
          emacsvox-aural-voice-workbench-view 'physical)
    (emacsvox-aural-voice-workbench-refresh)
    (emacsvox-aural-voice-workbench--announce
     "Choose and preview a physical voice for %s, then press a to assign"
     logical)))

(defun emacsvox-aural-voice-workbench--assignment-selector (pair)
  "Read and return a staged selector derived from physical voice PAIR."
  (let* ((engine (car pair))
         (voice (cadr pair))
         (engine-id (plist-get engine :engine-id))
         (voice-id (plist-get voice :voice-id))
         (language (plist-get voice :language))
         (gender (plist-get voice :gender))
         (choices
          '(("exact installed voice, local to this machine" . exact)
            ("portable engine default" . engine-default)
            ("portable language and gender" . language-gender)
            ("portable engine, language, and gender" . engine-properties)))
         (kind
          (cdr
           (assoc-string
            (completing-read "Selector kind: " choices nil 'must-match)
            choices))))
    (pcase kind
      ('exact
       (list :kind 'exact :scope 'local
             :engine-id engine-id :voice-id voice-id))
      ('engine-default
       (list :kind 'engine-default :scope 'portable :engine-id engine-id))
      ('language-gender
       (append
        (list :kind 'properties :scope 'portable)
        (and language (list :language language))
        (and gender (list :gender gender))))
      ('engine-properties
       (append
        (list :kind 'properties :scope 'portable :engine-id engine-id)
        (and language (list :language language))
        (and gender (list :gender gender)))))))

(defun emacsvox-aural-voice-workbench--finish-assignment (logical-voice)
  "Return to LOGICAL-VOICE after a physical assignment operation."
  (setq emacsvox-aural-voice-workbench-filter
        emacsvox-aural-voice-workbench-assignment-return-filter
        emacsvox-aural-voice-workbench-assignment-return-filter nil
        emacsvox-aural-voice-workbench-assignment-target nil
        emacsvox-aural-voice-workbench-view 'logical)
  (emacsvox-aural-voice-workbench-refresh logical-voice))

(defun emacsvox-aural-voice-workbench-complete-assignment ()
  "Append a selector from the current physical row to the assignment target."
  (interactive)
  (unless (and (eq emacsvox-aural-voice-workbench-view 'physical)
               emacsvox-aural-voice-workbench-assignment-target)
    (user-error "Begin at a logical voice and press a before assigning"))
  (let* ((logical emacsvox-aural-voice-workbench-assignment-target)
         (pair
          (emacsvox-aural-voice-workbench--physical-pair
           (or (tabulated-list-get-id)
               (user-error "Move to a physical voice first")))))
    (unless pair
      (user-error "The selected physical voice is no longer installed"))
    (let* ((selector
            (emacsvox-aural-voice-workbench--assignment-selector pair))
           (description
            (emacsvox-aural-voice-workbench--selector-description selector)))
      (when (member selector
                    (emacsvox-aural-voice-workbench--explicit-selectors logical))
        (user-error "%s already uses %s" logical description))
      (when
          (y-or-n-p (format "Add %s to %s? " description logical))
        (emacsvox-aural-voice-workbench--stage
         (format "Added %s to %s" description logical)
         (lambda ()
           (emacsvox-aural-voice-workbench--replace-binding
            logical
            (append
             (emacsvox-aural-voice-workbench--explicit-selectors logical)
             (list selector))
            (plist-get (cadr pair) :language))))
        (emacsvox-aural-voice-workbench--finish-assignment logical)))))

(defun emacsvox-aural-voice-workbench-assign ()
  "Begin or complete quick logical-voice assignment for the current view."
  (interactive)
  (if (eq emacsvox-aural-voice-workbench-view 'physical)
      (emacsvox-aural-voice-workbench-complete-assignment)
    (emacsvox-aural-voice-workbench-begin-assignment)))

(defun emacsvox-aural-voice-workbench-cancel-assignment ()
  "Cancel the active physical assignment browser without changing routes."
  (interactive)
  (unless emacsvox-aural-voice-workbench-assignment-target
    (user-error "No voice assignment is active"))
  (let ((logical emacsvox-aural-voice-workbench-assignment-target))
    (emacsvox-aural-voice-workbench--finish-assignment logical)
    (emacsvox-aural-voice-workbench--announce
     "Assignment for %s cancelled" logical)))

(defun emacsvox-aural-voice-workbench--selector-candidates (logical-voice)
  "Return indexed explicit selector candidates for LOGICAL-VOICE."
  (cl-loop
   for selector in
   (emacsvox-aural-voice-workbench--explicit-selectors logical-voice)
   for index from 0
   collect
   (cons
    (format "%d. %s" (1+ index)
            (emacsvox-aural-voice-workbench--selector-description selector))
    index)))

(defun emacsvox-aural-voice-workbench--read-selector-index
    (logical-voice prompt)
  "Read one explicit selector index for LOGICAL-VOICE using PROMPT."
  (let ((candidates
         (emacsvox-aural-voice-workbench--selector-candidates logical-voice)))
    (unless candidates (user-error "%s has no explicit selectors" logical-voice))
    (cdr
     (assoc-string
      (completing-read prompt candidates nil 'must-match) candidates))))

(defun emacsvox-aural-voice-workbench--move-selector (direction)
  "Move a selected explicit selector by DIRECTION positions."
  (let* ((logical (emacsvox-aural-voice-workbench--current-logical-voice))
         (selectors
          (emacsvox-aural-voice-workbench--explicit-selectors logical))
         (index
          (emacsvox-aural-voice-workbench--read-selector-index
           logical "Move selector: "))
         (destination (+ index direction)))
    (unless (<= 0 destination (1- (length selectors)))
      (user-error "That selector is already at the route boundary"))
    (cl-rotatef (nth index selectors) (nth destination selectors))
    (emacsvox-aural-voice-workbench--stage
     (format "Reordered fallback %d for %s" (1+ index) logical)
     (lambda ()
       (emacsvox-aural-voice-workbench--replace-binding logical selectors)))))

(defun emacsvox-aural-voice-workbench-move-selector-up ()
  "Move one explicit selector earlier in the current logical route."
  (interactive)
  (emacsvox-aural-voice-workbench--move-selector -1))

(defun emacsvox-aural-voice-workbench-move-selector-down ()
  "Move one explicit selector later in the current logical route."
  (interactive)
  (emacsvox-aural-voice-workbench--move-selector 1))

(defun emacsvox-aural-voice-workbench-delete-selector ()
  "Delete one explicit selector from the current logical route."
  (interactive)
  (let* ((logical (emacsvox-aural-voice-workbench--current-logical-voice))
         (selectors
          (emacsvox-aural-voice-workbench--explicit-selectors logical))
         (index
          (emacsvox-aural-voice-workbench--read-selector-index
           logical "Delete selector: "))
         (selector (nth index selectors)))
    (when
        (y-or-n-p
         (format "Delete %s from %s? "
                 (emacsvox-aural-voice-workbench--selector-description selector)
                 logical))
      (setq selectors
            (append (cl-subseq selectors 0 index)
                    (nthcdr (1+ index) selectors)))
      (emacsvox-aural-voice-workbench--stage
       (format "Deleted fallback %d from %s" (1+ index) logical)
       (lambda ()
         (emacsvox-aural-voice-workbench--replace-binding
          logical selectors))))))

(defun emacsvox-aural-voice-workbench-copy-route ()
  "Replace the current logical route with a staged copy of another route."
  (interactive)
  (let* ((target (emacsvox-aural-voice-workbench--current-logical-voice))
         (voices (delete target
                         (emacsvox-aural-voice-workbench--logical-voices)))
         (source
          (completing-read "Copy route from: " voices nil 'must-match))
         (selectors
          (emacsvox-aural-voice-workbench--explicit-selectors source)))
    (when (y-or-n-p (format "Replace %s route with %s's route? " target source))
      (emacsvox-aural-voice-workbench--stage
       (format "Copied %s route to %s" source target)
       (lambda ()
         (emacsvox-aural-voice-workbench--replace-binding
          target (copy-tree selectors)))))))

(defun emacsvox-aural-voice-workbench--engine-ids ()
  "Return sorted engine IDs known to inventory or staged routing."
  (let ((ids
         (copy-sequence
          (plist-get emacsvox-aural-voice-workbench-staged-profile
                     :engine-order))))
    (dolist
        (engine
         (plist-get emacsvox-aural-voice-workbench-inventory :engines))
      (push (plist-get engine :engine-id) ids))
    (dolist
        (binding
         (plist-get emacsvox-aural-voice-workbench-staged-profile :bindings))
      (dolist (selector (plist-get binding :selectors))
        (when-let* ((engine (plist-get selector :engine-id)))
          (push engine ids))))
    (let ((fallback
           (plist-get emacsvox-aural-voice-workbench-staged-profile
                      :fallback)))
      (setq ids (append (plist-get fallback :engines) ids))
      (when-let* ((global (plist-get fallback :global-default))
                  (engine (plist-get global :engine-id)))
        (push engine ids)))
    (sort (delete-dups ids) #'string-lessp)))

(defun emacsvox-aural-voice-workbench-bind-unmapped ()
  "Bind every explicitly unmapped logical voice to one engine default."
  (interactive)
  (let* ((engine
          (completing-read
           "Engine default for unmapped voices: "
           (emacsvox-aural-voice-workbench--engine-ids) nil 'must-match))
         (unmapped
          (cl-remove-if
           #'emacsvox-aural-voice-workbench--explicit-selectors
           (emacsvox-aural-voice-workbench--logical-voices)))
         (selector
          (list :kind 'engine-default :scope 'portable :engine-id engine)))
    (unless unmapped (user-error "Every logical voice has an explicit route"))
    (when
        (y-or-n-p
         (format "Bind %d unmapped voices to %s default? "
                 (length unmapped) engine))
      (emacsvox-aural-voice-workbench--stage
       (format "Bound %d unmapped voices to %s" (length unmapped) engine)
       (lambda ()
         (dolist (logical unmapped)
           (emacsvox-aural-voice-workbench--replace-binding
            logical (list (copy-tree selector)))))))))

(defun emacsvox-aural-voice-workbench--replace-selector-engine
    (selector old-engine new-engine exact-strategy)
  "Replace OLD-ENGINE in SELECTOR with NEW-ENGINE using EXACT-STRATEGY."
  (if (not (equal (plist-get selector :engine-id) old-engine))
      selector
    (if (eq (plist-get selector :kind) 'exact)
        (if (eq exact-strategy 'convert)
            (list :kind 'engine-default :scope 'portable
                  :engine-id new-engine)
          selector)
      (plist-put (copy-tree selector) :engine-id new-engine))))

(defun emacsvox-aural-voice-workbench-replace-engine ()
  "Replace one engine in selected staged logical mappings."
  (interactive)
  (let* ((engines (emacsvox-aural-voice-workbench--engine-ids))
         (old (completing-read "Replace engine: " engines nil 'must-match))
         (new
          (completing-read
           "With engine: " (delete old (copy-sequence engines))
           nil 'must-match))
         (logical-voices (emacsvox-aural-voice-workbench--logical-voices))
         (selected
          (completing-read-multiple
           "Logical voices to change (comma separated): "
           logical-voices nil 'must-match))
         (strategy-name
          (completing-read
           "Exact selectors for the old engine: "
           '("leave exact voices unchanged"
             "convert exact voices to destination engine default")
           nil 'must-match))
         (strategy
          (if (string-prefix-p "convert" strategy-name) 'convert 'leave)))
    (unless selected (user-error "Select at least one logical voice"))
    (when
        (y-or-n-p
         (format "Replace %s with %s in %d selected routes? "
                 old new (length selected)))
      (emacsvox-aural-voice-workbench--stage
       (format "Replaced %s with %s in selected routes" old new)
       (lambda ()
         (dolist (logical selected)
           (let* ((selectors
                   (emacsvox-aural-voice-workbench--explicit-selectors logical))
                  (replaced
                   (mapcar
                    (lambda (selector)
                      (emacsvox-aural-voice-workbench--replace-selector-engine
                       selector old new strategy))
                    selectors)))
             (emacsvox-aural-voice-workbench--replace-binding
              logical (cl-remove-duplicates replaced :test #'equal)))))))))

(defun emacsvox-aural-voice-workbench-undo ()
  "Undo the most recent staged routing edit without changing saved state."
  (interactive)
  (let ((snapshot (pop emacsvox-aural-voice-workbench-undo-stack)))
    (unless snapshot (user-error "No staged routing edit to undo"))
    (setq emacsvox-aural-voice-workbench-staged-profile
          (copy-tree (plist-get snapshot :profile))
          emacsvox-aural-voice-workbench-last-edit
          (format "Undid %s" (plist-get snapshot :description)))
    (emacsvox-aural-voice-workbench-refresh)
    (emacsvox-aural-voice-workbench--announce
     "%s" emacsvox-aural-voice-workbench-last-edit)))

(defun emacsvox-aural-voice-workbench-cancel-staged ()
  "Restore the exact profile snapshot from when the workbench opened."
  (interactive)
  (when
      (or (not (emacsvox-aural-voice-workbench--dirty-p))
          (y-or-n-p "Discard every staged routing edit? "))
    (setq emacsvox-aural-voice-workbench-staged-profile
          (copy-tree emacsvox-aural-voice-workbench-committed-profile)
          emacsvox-aural-voice-workbench-undo-stack nil
          emacsvox-aural-voice-workbench-last-edit "Cancelled staged edits")
    (when emacsvox-aural-voice-workbench-assignment-target
      (setq emacsvox-aural-voice-workbench-filter
            emacsvox-aural-voice-workbench-assignment-return-filter
            emacsvox-aural-voice-workbench-assignment-return-filter nil
            emacsvox-aural-voice-workbench-assignment-target nil
            emacsvox-aural-voice-workbench-view 'logical))
    (emacsvox-aural-voice-workbench-refresh)
    (emacsvox-aural-voice-workbench--announce "Staged routing edits cancelled")))

(defun emacsvox-aural-voice-workbench--normalized-acss-value (value)
  "Normalize zero-to-nine ACSS VALUE for transactional preview."
  (and (numberp value) (/ (float (max 0 (min 9 value))) 9.0)))

(defun emacsvox-aural-voice-workbench--preview-acss (logical-voice)
  "Return portable normalized ACSS for LOGICAL-VOICE, when available."
  (when-let* ((entry
               (emacsvox-aural-voice-workbench--palette-entry logical-voice)))
    (let* ((definition (cdr entry))
           (style
            (if (and (symbolp definition) (boundp definition))
                (symbol-value definition)
              definition))
           result)
      (dolist
          (dimension
           '((:average-pitch . acss-average-pitch)
             (:pitch-range . acss-pitch-range)
             (:stress . acss-stress)
             (:richness . acss-richness)))
        (when-let* ((value
                     (and (fboundp (cdr dimension))
                          (ignore-errors (funcall (cdr dimension) style))))
                    (normalized
                     (emacsvox-aural-voice-workbench--normalized-acss-value
                      value)))
          (setq result (plist-put result (car dimension) normalized))))
      result)))

(defun emacsvox-aural-voice-workbench--physical-preview-entry (pair)
  "Return one exact preview entry for physical engine/voice PAIR."
  (let ((engine (car pair)) (voice (cadr pair)))
    (list
     :text emacsvox-aural-voice-workbench-preview-text
     :selector
     (list :kind 'exact
           :engine-id (plist-get engine :engine-id)
           :voice-id (plist-get voice :voice-id)
           :scope 'session)
     :language (plist-get voice :language)
     :acss nil :effects nil)))

(defun emacsvox-aural-voice-workbench--logical-preview-entry (logical-voice)
  "Return one staged preview entry for LOGICAL-VOICE."
  (let* ((binding
          (emacsvox-aural-voice-workbench--profile-binding logical-voice))
         (language (plist-get binding :language))
         (selector
          (or (car (emacsvox-aural-voice-workbench--selectors logical-voice))
              (list :kind 'properties :language language :scope 'portable))))
    (list
     :text emacsvox-aural-voice-workbench-preview-text
     :selector selector :language language
     :acss (emacsvox-aural-voice-workbench--preview-acss logical-voice)
     :effects nil)))

(defun emacsvox-aural-voice-workbench--current-preview-entry ()
  "Return a preview entry for the current Workbench row."
  (let ((id (or (tabulated-list-get-id)
                (user-error "Move to a Voice Workbench row first"))))
    (pcase emacsvox-aural-voice-workbench-view
      ('physical
       (emacsvox-aural-voice-workbench--physical-preview-entry
        (or (emacsvox-aural-voice-workbench--physical-pair id)
            (user-error "The selected physical voice is no longer installed"))))
      ((or 'logical 'styles)
       (emacsvox-aural-voice-workbench--logical-preview-entry id))
      ('engines
       (list
        :text emacsvox-aural-voice-workbench-preview-text
        :selector (list :kind 'engine-default :engine-id id :scope 'session)
        :language nil :acss nil :effects nil)))))

(defun emacsvox-aural-voice-workbench--preview-description (result)
  "Return concise non-speaking status text for preview RESULT."
  (let* ((results (plist-get result :results))
         (last (car (last results)))
         (realized (plist-get last :realized))
         (degraded
          (append (plist-get last :degraded-acss)
                  (plist-get last :degraded-effects))))
    (format
     "Preview %s%s%s"
     (or (plist-get result :status) "unknown")
     (if realized
         (format ", realized %s/%s"
                 (plist-get realized :engine-id)
                 (plist-get realized :voice-id))
       "")
     (if degraded
         (format ", degraded %s"
                 (mapconcat (lambda (item) (format "%s" item))
                            degraded ", "))
       ""))))

(defun emacsvox-aural-voice-workbench--preview-complete (buffer result)
  "Record preview RESULT in live workbench BUFFER without speaking it."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (setq emacsvox-aural-voice-workbench-last-preview result)
      (force-mode-line-update)))
  (emacsvox-aural-preview-message
   "%s" (emacsvox-aural-voice-workbench--preview-description result)))

(defun emacsvox-aural-voice-workbench--preview-entries (entries)
  "Preview ENTRIES with shared sample text and update workbench status."
  (let ((buffer (current-buffer)))
    (setq emacsvox-aural-voice-workbench-last-preview
          (list :status (format "running %d" (length entries))))
    (force-mode-line-update)
    (tts-preview-voices
     entries
     (lambda (result)
       (emacsvox-aural-voice-workbench--preview-complete buffer result)))))

(defun emacsvox-aural-voice-workbench-preview ()
  "Preview the current logical, physical, engine, or style row once."
  (interactive)
  (emacsvox-aural-voice-workbench--preview-entries
   (list (emacsvox-aural-voice-workbench--current-preview-entry))))

(defun emacsvox-aural-voice-workbench-edit-preview-text ()
  "Edit the common Voice Workbench comparison text."
  (interactive)
  (let ((text
         (read-string "Voice preview text: "
                      emacsvox-aural-voice-workbench-preview-text)))
    (when (string-empty-p text)
      (user-error "Voice preview text must not be empty"))
    (setq emacsvox-aural-voice-workbench-preview-text text))
  (emacsvox-aural-preview-message "Voice preview text updated"))

(defun emacsvox-aural-voice-workbench-preview-all ()
  "Preview every currently visible physical voice using identical text."
  (interactive)
  (let ((entries
         (mapcar
          #'emacsvox-aural-voice-workbench--physical-preview-entry
          (cl-remove-if-not
           (lambda (pair)
             (emacsvox-aural-voice-workbench--physical-visible-p
              (car pair) (cadr pair)))
           (emacsvox-aural-voice-workbench--all-engine-voices)))))
    (unless entries (user-error "No physical voices match the current filter"))
    (emacsvox-aural-voice-workbench--preview-entries entries)))

(defun emacsvox-aural-voice-workbench--physical-candidates ()
  "Return completion candidates for installed physical voices."
  (mapcar
   (lambda (pair)
     (let ((engine (car pair)) (voice (cadr pair)))
       (cons
        (format "%s [%s/%s]"
                (or (plist-get voice :display-name)
                    (plist-get voice :voice-id))
                (plist-get engine :engine-id)
                (plist-get voice :voice-id))
        pair)))
   (emacsvox-aural-voice-workbench--all-engine-voices)))

(defun emacsvox-aural-voice-workbench-compare ()
  "A/B two installed physical voices with identical text and settings."
  (interactive)
  (let* ((candidates (emacsvox-aural-voice-workbench--physical-candidates))
         (_ (when (< (length candidates) 2)
              (user-error "A/B comparison requires two installed voices")))
         (first-name
          (completing-read "A voice: " candidates nil 'must-match))
         (remaining (assoc-delete-all first-name (copy-tree candidates)))
         (second-name
          (completing-read "B voice: " remaining nil 'must-match))
         (first (cdr (assoc-string first-name candidates)))
         (second (cdr (assoc-string second-name remaining))))
    (emacsvox-aural-voice-workbench--preview-entries
     (mapcar #'emacsvox-aural-voice-workbench--physical-preview-entry
             (list first second)))))

(defun emacsvox-aural-voice-workbench-stop-preview ()
  "Stop the active preview immediately."
  (interactive)
  (tts-stop)
  (setq emacsvox-aural-voice-workbench-last-preview '(:status cancelled))
  (force-mode-line-update)
  (emacsvox-aural-preview-message "Voice preview stopped"))

(defun emacsvox-aural-voice-workbench-refresh (&optional id)
  "Refresh the Workbench quietly, preserving row ID and column."
  (interactive)
  (when-let* ((current (tabulated-list-get-id)))
    (puthash emacsvox-aural-voice-workbench-view current
             emacsvox-aural-voice-workbench-selections))
  (setq emacsvox-aural-voice-workbench-inventory (tts-voice-inventory)
        tabulated-list-format (emacsvox-aural-voice-workbench--format)
        header-line-format '(:eval (emacsvox-aural-voice-workbench--header)))
  (tabulated-list-init-header)
  (emacsvox-aural-ui-refresh-tabulated
   (lambda ()
     (setq tabulated-list-entries
           (emacsvox-aural-voice-workbench--entries)))
   (or id
       (gethash emacsvox-aural-voice-workbench-view
                emacsvox-aural-voice-workbench-selections))))

(defun emacsvox-aural-voice-workbench-speak-current ()
  "Speak the complete current Workbench row with titled values."
  (interactive)
  (let* ((entry
          (or (tabulated-list-get-entry)
              (user-error "Move to a Voice Workbench row first")))
         parts)
    (dotimes (index (length entry))
      (let ((value (aref entry index)))
        (push
         (format "%s, %s"
                 (car (aref tabulated-list-format index))
                 (if (string-empty-p (format "%s" value)) "blank" value))
         parts)))
    (let ((text (mapconcat #'identity (nreverse parts) ". ")))
      (if (fboundp 'tts-speak) (tts-speak text) (message "%s" text))
      text)))

(defun emacsvox-aural-voice-workbench--switch (view)
  "Switch to Workbench VIEW and announce its selected row."
  (when (and emacsvox-aural-voice-workbench-assignment-target
             (not (eq view 'physical)))
    (setq emacsvox-aural-voice-workbench-filter
          emacsvox-aural-voice-workbench-assignment-return-filter
          emacsvox-aural-voice-workbench-assignment-return-filter nil
          emacsvox-aural-voice-workbench-assignment-target nil))
  (when-let* ((current (tabulated-list-get-id)))
    (puthash emacsvox-aural-voice-workbench-view current
             emacsvox-aural-voice-workbench-selections))
  (setq emacsvox-aural-voice-workbench-view view)
  (emacsvox-aural-voice-workbench-refresh)
  (let ((row
         (and (tabulated-list-get-id)
              (emacsvox-aural-voice-workbench-speak-current))))
    (unless row
      (let ((text
             (format "%s view has no rows"
                     (alist-get view
                                emacsvox-aural-voice-workbench--views))))
        (if (fboundp 'tts-speak) (tts-speak text) (message "%s" text))))))

(defun emacsvox-aural-voice-workbench-logical-view ()
  "Show logical voices."
  (interactive)
  (emacsvox-aural-voice-workbench--switch 'logical))

(defun emacsvox-aural-voice-workbench-physical-view ()
  "Show discovered physical voices."
  (interactive)
  (emacsvox-aural-voice-workbench--switch 'physical))

(defun emacsvox-aural-voice-workbench-engine-view ()
  "Show speech engines and their capabilities."
  (interactive)
  (emacsvox-aural-voice-workbench--switch 'engines))

(defun emacsvox-aural-voice-workbench-style-view ()
  "Show portable styles, routes, and advertised effects."
  (interactive)
  (emacsvox-aural-voice-workbench--switch 'styles))

(defun emacsvox-aural-voice-workbench-refresh-inventory ()
  "Request fresh adapter inventory and quietly rebuild the current view."
  (interactive)
  (setq emacsvox-aural-voice-workbench-inventory
        (tts-refresh-voice-inventory))
  (emacsvox-aural-voice-workbench-refresh)
  (let ((text
         (format "Inventory refresh requested. %s"
                 (emacsvox-aural-voice-workbench--header))))
    (if (fboundp 'tts-speak) (tts-speak text) (message "%s" text))
    text))

(defun emacsvox-aural-voice-workbench--filter-values (field)
  "Return available physical inventory values for filter FIELD."
  (let (values)
    (dolist (pair (emacsvox-aural-voice-workbench--all-engine-voices))
      (let ((engine (car pair)) (voice (cadr pair)))
        (when-let* ((value
                     (pcase field
                       ('engine (plist-get engine :engine-id))
                       ('health (plist-get engine :health))
                       ('language (plist-get voice :language))
                       ('gender (plist-get voice :gender))
                       ('quality (plist-get voice :quality))
                       ('availability (plist-get voice :availability)))))
          (push (format "%s" value) values))))
    (sort (delete-dups values) #'string-lessp)))

(defun emacsvox-aural-voice-workbench-set-filter ()
  "Set or clear one physical-voice inventory filter."
  (interactive)
  (let* ((field
          (intern
           (completing-read
            "Filter field: "
            '("engine" "language" "gender" "quality" "health"
              "availability") nil 'must-match)))
         (key (intern (concat ":" (symbol-name field))))
         (current (plist-get emacsvox-aural-voice-workbench-filter key))
         (value
          (completing-read
           (format "%s value (blank clears): " (capitalize (symbol-name field)))
           (emacsvox-aural-voice-workbench--filter-values field)
           nil nil nil nil current)))
    (setq emacsvox-aural-voice-workbench-filter
          (plist-put emacsvox-aural-voice-workbench-filter key
                     (unless (string-empty-p value) value)))
    (unless (eq emacsvox-aural-voice-workbench-view 'physical)
      (setq emacsvox-aural-voice-workbench-view 'physical))
    (emacsvox-aural-voice-workbench-refresh)
    (let ((text
           (format "Physical voice filter: %s"
                   (emacsvox-aural-voice-workbench--filter-description))))
      (if (fboundp 'tts-speak) (tts-speak text) (message "%s" text))
      text)))

(defun emacsvox-aural-voice-workbench-clear-filters ()
  "Clear all physical-voice filters and refresh."
  (interactive)
  (setq emacsvox-aural-voice-workbench-filter nil)
  (emacsvox-aural-voice-workbench-refresh)
  (if (fboundp 'tts-speak)
      (tts-speak "Physical voice filters cleared")
    (message "Physical voice filters cleared")))

(defun emacsvox-aural-voice-workbench-describe ()
  "Display and speak exact Workbench row and configuration details."
  (interactive)
  (let ((summary (emacsvox-aural-voice-workbench-speak-current)))
    (with-help-window (help-buffer)
      (princ (format "%s\n\n" summary))
      (princ (format "Status: %s\n\n"
                     (emacsvox-aural-voice-workbench--header)))
      (princ
       (format "Inventory:\n%S\n\n"
               emacsvox-aural-voice-workbench-inventory))
      (princ
       (format "Staged routing profile:\n%S\n"
               emacsvox-aural-voice-workbench-staged-profile)))
    summary))

(defun emacsvox-aural-voice-workbench-help ()
  "Display and speak Voice Workbench navigation help."
  (interactive)
  (with-help-window (help-buffer)
    (princ
     (concat
      "Emacsvox Voice Workbench\n\n"
      "The workbench presents portable voice style and machine-local routing\n"
      "together while keeping their saved data separate. Exact native IDs are\n"
      "local; property selectors can be portable; session routes are temporary.\n\n"
      "l logical voices      v physical voices\n"
      "e engines             s styles and effects\n"
      "n/p or up/down rows   left/right columns\n"
      ". speak titled cell   SPC speak complete row\n"
      "RET describe row      F set physical filter\n"
      "C clear filters       R request fresh inventory\n"
      "P preview row         A preview all visible voices\n"
      "B compare two voices  T edit common preview text\n"
      "S stop preview        a assign or choose physical voice\n"
      "c cancel assignment   [/] move selector earlier/later\n"
      "d delete selector     y copy another logical route\n"
      "M map all unmapped    X replace engine in selected routes\n"
      "u undo staged edit    x cancel all staged edits\n"
      "g redraw quietly      h aural home\n"
      "q hide, keep staged   ? help\n")))
  (when (fboundp 'emacsvox-speak-help)
    (emacsvox-speak-help)))

(define-derived-mode
    emacsvox-aural-voice-workbench-mode
    emacsvox-aural-tabulated-mode
  "Aural-Voice-Workbench"
  "Spoken workbench for logical styles and physical voice routing."
  (setq-local emacsvox-aural-voice-workbench-view 'logical)
  (setq-local emacsvox-aural-voice-workbench-inventory (tts-voice-inventory))
  (setq-local emacsvox-aural-voice-workbench-committed-profile
              (emacsvox-aural-voice-workbench--current-profile-data))
  (setq-local emacsvox-aural-voice-workbench-staged-profile
              (copy-tree emacsvox-aural-voice-workbench-committed-profile))
  (setq-local emacsvox-aural-voice-workbench-selections
              (make-hash-table :test #'eq))
  (setq-local emacsvox-aural-voice-workbench-filter nil)
  (setq-local emacsvox-aural-voice-workbench-last-preview nil)
  (setq-local emacsvox-aural-voice-workbench-assignment-target nil)
  (setq-local emacsvox-aural-voice-workbench-assignment-return-filter nil)
  (setq-local emacsvox-aural-voice-workbench-undo-stack nil)
  (setq-local emacsvox-aural-voice-workbench-last-edit nil)
  (emacsvox-aural-ui-configure-tabulated
   "voice workbench"
   #'emacsvox-aural-voice-workbench-speak-current
   #'emacsvox-aural-voice-workbench-refresh)
  (setq tabulated-list-format (emacsvox-aural-voice-workbench--format)
        tabulated-list-padding 2
        header-line-format '(:eval (emacsvox-aural-voice-workbench--header)))
  (add-hook 'tabulated-list-revert-hook
            #'emacsvox-aural-voice-workbench-refresh nil t)
  (tabulated-list-init-header))

(dolist
    (binding
     '(("RET" . emacsvox-aural-voice-workbench-describe)
       ("l" . emacsvox-aural-voice-workbench-logical-view)
       ("v" . emacsvox-aural-voice-workbench-physical-view)
       ("e" . emacsvox-aural-voice-workbench-engine-view)
       ("s" . emacsvox-aural-voice-workbench-style-view)
       ("F" . emacsvox-aural-voice-workbench-set-filter)
       ("C" . emacsvox-aural-voice-workbench-clear-filters)
       ("R" . emacsvox-aural-voice-workbench-refresh-inventory)
       ("P" . emacsvox-aural-voice-workbench-preview)
       ("A" . emacsvox-aural-voice-workbench-preview-all)
       ("B" . emacsvox-aural-voice-workbench-compare)
       ("T" . emacsvox-aural-voice-workbench-edit-preview-text)
       ("S" . emacsvox-aural-voice-workbench-stop-preview)
       ("a" . emacsvox-aural-voice-workbench-assign)
       ("c" . emacsvox-aural-voice-workbench-cancel-assignment)
       ("[" . emacsvox-aural-voice-workbench-move-selector-up)
       ("]" . emacsvox-aural-voice-workbench-move-selector-down)
       ("d" . emacsvox-aural-voice-workbench-delete-selector)
       ("y" . emacsvox-aural-voice-workbench-copy-route)
       ("M" . emacsvox-aural-voice-workbench-bind-unmapped)
       ("X" . emacsvox-aural-voice-workbench-replace-engine)
       ("u" . emacsvox-aural-voice-workbench-undo)
       ("x" . emacsvox-aural-voice-workbench-cancel-staged)
       ("h" . emacsvox-aural)
       ("?" . emacsvox-aural-voice-workbench-help)))
  (define-key emacsvox-aural-voice-workbench-mode-map
              (kbd (car binding)) (cdr binding)))

;;;###autoload
(defun emacsvox-aural-voice-workbench (&optional view)
  "Open the accessible Voice Workbench in VIEW."
  (interactive)
  (let ((source (emacsvox-aural-inspection-remember-source-buffer))
        (buffer (get-buffer-create "*Aural Voice Workbench*")))
    (with-current-buffer buffer
      (unless (derived-mode-p 'emacsvox-aural-voice-workbench-mode)
        (emacsvox-aural-voice-workbench-mode))
      (emacsvox-aural-inspection-attach-source source)
      (when view (setq emacsvox-aural-voice-workbench-view view))
      (emacsvox-aural-voice-workbench-refresh))
    (emacsvox-aural-ui-pop-to-buffer buffer)
    (when (called-interactively-p 'interactive)
      (if (tabulated-list-get-id)
          (emacsvox-aural-voice-workbench-speak-current)
        (tts-speak "Voice Workbench has no rows")))
    buffer))

(defun emacsvox-aural-voice-workbench-refresh-if-live (&rest _ignored)
  "Quietly refresh a live Voice Workbench after configuration changes."
  (when-let* ((buffer (get-buffer "*Aural Voice Workbench*")))
    (with-current-buffer buffer
      (when (derived-mode-p 'emacsvox-aural-voice-workbench-mode)
        (emacsvox-aural-voice-workbench-refresh)))))

(add-hook 'emacsvox-aural-routing-profile-changed-hook
          #'emacsvox-aural-voice-workbench-refresh-if-live)
(add-hook 'emacsvox-aural-voice-palette-changed-hook
          #'emacsvox-aural-voice-workbench-refresh-if-live)

(provide 'emacsvox-aural-voice-workbench)
;;; emacsvox-aural-voice-workbench.el ends here
