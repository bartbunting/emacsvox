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
(require 'emacsvox-aural-voice-palettes)

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

(defconst emacsvox-aural-voice-workbench--known-engine-aliases
  '(("eloquence"
     ("v1" paul outloud-v1 v1 male)
     ("v2" outloud-v2 v2 female)
     ("v3" outloud-v3 v3 child)
     ("v4" outloud-v4 v4 male)
     ("v5" outloud-v5 v5 male)
     ("v6" outloud-v6 v6 female)
     ("v7" outloud-v7 v7 female)
     ("v8" outloud-v8 v8 male))
    ("outloud"
     ("paul" paul outloud-v1 v1 male)
     ("outloud-v2" outloud-v2 v2 female)
     ("outloud-v3" outloud-v3 v3 child)
     ("outloud-v4" outloud-v4 v4 male)
     ("outloud-v5" outloud-v5 v5 male)
     ("outloud-v6" outloud-v6 v6 female)
     ("outloud-v7" outloud-v7 v7 female)
     ("outloud-v8" outloud-v8 v8 male))
    ("dectalk"
     ("paul" paul male) ("betty" betty female)
     ("harry" harry male) ("frank" frank male)
     ("kit" kit child) ("rita" rita female)
     ("ursula" ursula female) ("dennis" dennis male)
     ("wendy" wendy female)))
  "Compatibility aliases used only to explain reviewable route suggestions.")

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

(defvar-local emacsvox-aural-voice-workbench-applied-undo nil
  "Previous known-good profile available after one successful save.")

(defvar-local emacsvox-aural-voice-workbench-diagnostics nil
  "Current inventory and apply diagnostics for the staged profile.")

(defvar-local emacsvox-aural-voice-workbench-provenance nil
  "Ephemeral explanations for imported, preset, and suggested staged edits.")

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

(defun emacsvox-aural-voice-workbench--apply-status-description ()
  "Return concise apply status for the staged profile."
  (let* ((status emacsvox-aural-routing-apply-status)
         (profile-id
          (plist-get emacsvox-aural-voice-workbench-staged-profile :id)))
    (if (not (eq profile-id (plist-get status :profile-id)))
        "not applied here"
      (let* ((state (or (plist-get status :status) 'unknown))
             (processes (plist-get status :processes))
             (applied
              (cl-count
               'applied processes
               :key (lambda (process) (plist-get process :status)))))
        (if processes
            (format "%s %d/%d" state applied (length processes))
          (format "%s" state))))))

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
      "%d engines, %d voices | processes %s | routing %s, %s, apply %s | filter %s | "
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
     (emacsvox-aural-voice-workbench--apply-status-description)
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

(defun emacsvox-aural-voice-workbench--provenance-description
    (logical-voice)
  "Return routing provenance visible for LOGICAL-VOICE."
  (let* ((name (format "%s" logical-voice))
         (session
          (cl-find-if
           (lambda (entry) (equal name (format "%s" (car entry))))
           emacsvox-aural-session-routing-bindings))
         (record
          (cl-find-if
           (lambda (entry)
             (let ((voice (plist-get entry :logical-voice)))
               (or (null voice) (equal name (format "%s" voice)))))
           emacsvox-aural-voice-workbench-provenance))
         (scopes
          (delete-dups
           (mapcar
            (lambda (selector) (plist-get selector :scope))
            (emacsvox-aural-voice-workbench--explicit-selectors name)))))
    (cond
     (session "session override")
     (record
      (format "%s: %s"
              (plist-get record :kind) (plist-get record :detail)))
     (scopes
      (format "saved %s"
              (mapconcat #'symbol-name scopes "/")))
     ((plist-get emacsvox-aural-voice-workbench-staged-profile :engine-order)
      "inherited engine order")
     (t "adapter default"))))

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
      (emacsvox-aural-voice-workbench--last-played-description logical-voice)
      (emacsvox-aural-voice-workbench--registration-description logical-voice)
      (or (plist-get binding :language) "")
      (emacsvox-aural-voice-workbench--scope-description logical-voice)
      (if (equal route "adapter default") "unmapped" "routed")
      (emacsvox-aural-voice-workbench--provenance-description logical-voice)
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

(defun emacsvox-aural-voice-workbench--default-tuning-selector ()
  "Return a session selector for the first usable preferred engine.

This selector auditions an otherwise unrouted logical voice without staging
or persisting a routing choice."
  (let* ((inventory emacsvox-aural-voice-workbench-inventory)
         (disabled
          (plist-get emacsvox-aural-voice-workbench-staged-profile
                     :disabled-engines))
         (candidates
          (delete-dups
           (append
            (copy-sequence
             (plist-get emacsvox-aural-voice-workbench-staged-profile
                        :engine-order))
            (copy-sequence (plist-get inventory :preferred-engine-order))
            (list (plist-get inventory :preferred-engine-id))
            (mapcar
             (lambda (engine) (plist-get engine :engine-id))
             (plist-get inventory :engines)))))
         engine-id)
    (while (and candidates (not engine-id))
      (let* ((candidate (pop candidates))
             (engine
              (and
               candidate
               (cl-find candidate (plist-get inventory :engines)
                        :key (lambda (item) (plist-get item :engine-id))
                        :test #'equal))))
        (when
            (and engine
                 (equal (plist-get engine :availability) "available")
                 (not (member candidate disabled)))
          (setq engine-id candidate))))
    (and engine-id
         (list :kind 'engine-default :scope 'session
               :engine-id engine-id))))

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

(defun emacsvox-aural-voice-workbench--last-played-description
    (logical-voice)
  "Return the last route observed during playback for LOGICAL-VOICE."
  (if-let* ((route (tts-last-realized-voice logical-voice)))
      (let ((base
             (format "%s/%s"
                     (or (plist-get route :engine-id) "unknown")
                     (or (plist-get route :voice-id) "default")))
            (acss (plist-get route :degraded-acss))
            (effects (plist-get route :degraded-effects)))
        (concat
         base
         (when (or acss effects)
           (format " omitted %s"
                   (mapconcat
                    (lambda (value) (format "%s" value))
                    (append acss effects) ",")))))
    "not observed"))

(defun emacsvox-aural-voice-workbench--registration-binding-name (binding)
  "Return logical voice name carried by registration BINDING."
  (let ((status (plist-get binding :status)))
    (cond
     ((equal status "resolved")
      (plist-get (plist-get binding :resolution) :logical_voice_id))
     ((equal status "unresolved")
      (plist-get (plist-get binding :error) :logical_voice_id)))))

(defun emacsvox-aural-voice-workbench--registration-description
    (logical-voice)
  "Return per-process registration result for LOGICAL-VOICE."
  (let ((name (format "%s" logical-voice)) parts)
    (dolist (process (plist-get emacsvox-aural-routing-apply-status :processes))
      (let ((role (or (plist-get process :role) 'speech)))
        (if (not (eq (plist-get process :status) 'applied))
            (push
             (format "%s failed %s"
                     role (or (plist-get process :phase) "apply"))
             parts)
          (let* ((registration (plist-get process :registration))
                 (binding
                  (cl-find-if
                   (lambda (entry)
                     (equal name
                            (emacsvox-aural-voice-workbench--registration-binding-name
                             entry)))
                   (append (plist-get registration :bindings) nil))))
            (cond
             ((null binding)
              (push (format "%s adapter default" role) parts))
             ((equal (plist-get binding :status) "resolved")
              (let* ((resolution (plist-get binding :resolution))
                     (realized (plist-get resolution :realized)))
                (push
                 (format "%s %s/%s"
                         role
                         (plist-get realized :engine_id)
                         (plist-get realized :voice_id))
                 parts)))
             (t (push (format "%s unresolved" role) parts)))))))
    (if parts (mapconcat #'identity (nreverse parts) "; ")
      (pcase (plist-get emacsvox-aural-routing-apply-status :status)
        ('applying "applying")
        ('failed "apply failed")
        (_ "not registered")))))

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
         (preferred-order
          (cl-position
           id
           (plist-get emacsvox-aural-voice-workbench-staged-profile
                      :engine-order)
           :test #'equal))
         (fallback-order
          (cl-position
           id
           (plist-get
            (plist-get emacsvox-aural-voice-workbench-staged-profile
                       :fallback)
            :engines)
           :test #'equal))
         (disabled
          (member
           id
           (plist-get emacsvox-aural-voice-workbench-staged-profile
                      :disabled-engines)))
         (live-disabled (plist-get engine :disabled-by-policy)))
    (list
     id
     (vector
      id
      (or (plist-get engine :display-name) id)
      (if preferred-order (number-to-string (1+ preferred-order))
        (if (equal id
                   (plist-get emacsvox-aural-voice-workbench-inventory
                              :preferred-engine-id))
            "server default" "unlisted"))
      (if fallback-order (number-to-string (1+ fallback-order)) "unlisted")
      (cond (disabled "disabled staged")
            (live-disabled "disabled live")
            (t "enabled"))
      (or (plist-get engine :availability) "unknown")
      (format "%s/%s"
              (or (plist-get engine :health) "unknown")
              (or (plist-get engine :circuit) "unknown"))
      (or (plist-get engine :last-failure)
          (plist-get engine :health-reason) "none")
      (if-let* ((milliseconds
                 (plist-get engine :cooldown-remaining-ms)))
          (format "%d ms" milliseconds)
        "none")
      (or (plist-get engine :audio-output) "unknown")
      (number-to-string (length (plist-get engine :voices)))
      (emacsvox-aural-voice-workbench--join-symbols
       (plist-get engine :marker-support))
      (or (plist-get engine :anchor-support) "none")
      (emacsvox-aural-voice-workbench--join-symbols
       (plist-get engine :post-synthesis-dimensions))))))

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
      (emacsvox-aural-voice-workbench--last-played-description logical)
      (emacsvox-aural-voice-workbench--join-symbols dimensions)
      (if effects
          (emacsvox-aural-voice-workbench--join-symbols effects)
        "not advertised")
      (emacsvox-aural-voice-workbench--provenance-description logical)
      (emacsvox-aural-voice-workbench--family-diagnostic logical)))))

(defun emacsvox-aural-voice-workbench--format ()
  "Return tabulated columns for the active workbench view."
  (pcase emacsvox-aural-voice-workbench-view
    ('logical
     [("Palette" 16 t) ("Aliases" 24 t) ("Logical voice" 28 t)
      ("Requested style" 34 t) ("Selector order" 48 t)
      ("Predicted route" 24 t) ("Last played" 30 t)
      ("Registration" 36 t) ("Language" 12 t) ("Scope" 16 t)
      ("Status" 12 t) ("Provenance" 28 t) ("Diagnostic" 0 t)])
    ('physical
     [("Physical voice" 28 t) ("Engine" 14 t) ("Language" 12 t)
      ("Gender" 10 t) ("Quality" 12 t) ("Availability" 14 t)
      ("Health" 12 t) ("Selected by" 28 t) ("Native ID" 0 t)])
    ('engines
     [("Engine ID" 16 t) ("Engine" 20 t) ("Preferred" 12 t)
      ("Fallback" 10 t) ("Policy" 10 t) ("Availability" 14 t)
      ("Health/circuit" 18 t) ("Last failure" 28 t) ("Cooldown" 12 t)
      ("Audio" 18 t) ("Voices" 8 t) ("Markers" 24 t)
      ("Anchors" 18 t) ("Effects" 0 t)])
    ('styles
     [("Palette voice" 22 t) ("Logical voice" 26 t)
      ("Portable definition" 38 t) ("Staged route" 42 t)
      ("Last played" 30 t)
      ("Adapter ACSS" 30 t) ("Supported post effects" 30 t)
      ("Provenance" 28 t)
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

(defun emacsvox-aural-voice-workbench--stage
    (description mutation &optional provenance)
  "Apply MUTATION and record DESCRIPTION and optional PROVENANCE for undo."
  (let ((before (copy-tree emacsvox-aural-voice-workbench-staged-profile))
        (before-provenance
         (copy-tree emacsvox-aural-voice-workbench-provenance)))
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
            (when provenance
              (push (copy-tree provenance)
                    emacsvox-aural-voice-workbench-provenance))
            (push (list :profile before :description description
                        :provenance before-provenance)
                  emacsvox-aural-voice-workbench-undo-stack)
            (setq emacsvox-aural-voice-workbench-last-edit description)
            (emacsvox-aural-voice-workbench-refresh)
            (emacsvox-aural-voice-workbench--announce
             "%s staged. Save is not yet applied" description)
            t))
      (error
       (setq emacsvox-aural-voice-workbench-staged-profile before
             emacsvox-aural-voice-workbench-provenance before-provenance)
       (signal (car error-data) (cdr error-data))))))

(defun emacsvox-aural-voice-workbench--comparison-name (value)
  "Return normalized comparison text for voice metadata VALUE."
  (and value
       (downcase
        (string-trim
         (if (symbolp value) (symbol-name value) (format "%s" value))))))

(defun emacsvox-aural-voice-workbench--definition-family (definition)
  "Return requested family carried by portable voice DEFINITION."
  (or
   (emacsvox-aural-routing--style-family definition)
   (when (symbolp definition)
     (let ((settings
            (intern-soft (format "%s-settings" definition))))
       (and settings (boundp settings)
            (car-safe (symbol-value settings)))))))

(defun emacsvox-aural-voice-workbench--requested-family (logical-voice)
  "Return active-palette family requested by LOGICAL-VOICE."
  (when-let* ((entry
               (emacsvox-aural-voice-workbench--palette-entry logical-voice)))
    (emacsvox-aural-voice-workbench--definition-family (cdr entry))))

(defun emacsvox-aural-voice-workbench--known-voice-aliases
    (engine-id voice-id)
  "Return compatibility aliases for ENGINE-ID and VOICE-ID."
  (let ((engine
         (assoc-string
          engine-id emacsvox-aural-voice-workbench--known-engine-aliases t)))
    (copy-sequence
     (cdr
      (cl-find-if
       (lambda (entry)
         (equal
          (emacsvox-aural-voice-workbench--comparison-name voice-id)
          (emacsvox-aural-voice-workbench--comparison-name (car entry))))
       (cdr engine))))))

(defun emacsvox-aural-voice-workbench--voice-aliases (engine voice)
  "Return normalized discoverable names for VOICE from ENGINE."
  (delete-dups
   (delq
    nil
    (mapcar
     #'emacsvox-aural-voice-workbench--comparison-name
     (append
      (list (plist-get voice :voice-id)
            (plist-get voice :display-name)
            (plist-get voice :native-id))
      (plist-get voice :aliases)
      (emacsvox-aural-voice-workbench--known-voice-aliases
       (plist-get engine :engine-id) (plist-get voice :voice-id)))))))

(defun emacsvox-aural-voice-workbench--family-gender (family)
  "Return portable gender implied by FAMILY, or nil."
  (let ((name (emacsvox-aural-voice-workbench--comparison-name family))
        found)
    (cond
     ((member name '("male" "female" "neutral")) (intern name))
     (t
      (dolist (engine emacsvox-aural-voice-workbench--known-engine-aliases)
        (dolist (entry (cdr engine))
          (when
              (member
               name
               (mapcar
                #'emacsvox-aural-voice-workbench--comparison-name
                (cdr entry)))
            (cond
             ((memq 'female (cdr entry)) (setq found 'female))
             ((memq 'male (cdr entry)) (setq found 'male))
             ((memq 'neutral (cdr entry)) (setq found 'neutral))))))
      found))))

(defun emacsvox-aural-voice-workbench--ordered-engines ()
  "Return inventory engines in staged policy order, then discovery order."
  (let ((engines
         (copy-sequence
          (plist-get emacsvox-aural-voice-workbench-inventory :engines)))
        result)
    (dolist
        (id
         (plist-get emacsvox-aural-voice-workbench-staged-profile
                    :engine-order))
      (when-let* ((engine
                   (cl-find
                    id engines
                    :key (lambda (entry) (plist-get entry :engine-id))
                    :test #'equal)))
        (push engine result)
        (setq engines (delq engine engines))))
    (append (nreverse result) engines)))

(defun emacsvox-aural-voice-workbench--usable-voice-p (voice)
  "Return non-nil when inventory VOICE can currently be suggested."
  (not (member (format "%s" (plist-get voice :availability))
               '("unavailable" "failed"))))

(defun emacsvox-aural-voice-workbench--suggestion
    (logical selector reason &optional realized)
  "Construct a suggestion for LOGICAL using SELECTOR because REASON."
  (append
   (list :logical-voice logical :selector selector :reason reason
         :provenance 'suggested)
   (and realized (list :realized realized))))

(defun emacsvox-aural-voice-workbench--suggestions (logical-voice)
  "Return ordered, reviewable route suggestions for LOGICAL-VOICE."
  (let* ((binding
          (emacsvox-aural-voice-workbench--profile-binding logical-voice))
         (language (plist-get binding :language))
         (family
          (emacsvox-aural-voice-workbench--requested-family logical-voice))
         (family-name
          (emacsvox-aural-voice-workbench--comparison-name family))
         (gender (emacsvox-aural-voice-workbench--family-gender family))
         suggestions seen)
    (cl-labels
        ((add
          (selector reason &optional realized)
          (unless (member selector seen)
            (push selector seen)
            (push
             (emacsvox-aural-voice-workbench--suggestion
              logical-voice selector reason realized)
             suggestions)))
         (matching-voice
          (voices wanted-language wanted-gender)
          (cl-find-if
           (lambda (voice)
             (and
              (emacsvox-aural-voice-workbench--usable-voice-p voice)
              (or (null wanted-language)
                  (emacsvox-aural-voice-workbench--same-value-p
                   wanted-language (plist-get voice :language)))
              (or (null wanted-gender)
                  (emacsvox-aural-voice-workbench--same-value-p
                   wanted-gender (plist-get voice :gender)))))
           voices)))
      (dolist (engine (emacsvox-aural-voice-workbench--ordered-engines))
        (let* ((engine-id (plist-get engine :engine-id))
               (voices (plist-get engine :voices))
               (alias
                (and
                 family-name
                 (cl-find-if
                  (lambda (voice)
                    (and
                     (emacsvox-aural-voice-workbench--usable-voice-p voice)
                     (member
                      family-name
                      (emacsvox-aural-voice-workbench--voice-aliases
                       engine voice))))
                  voices)))
               (both (and language gender
                          (matching-voice voices language gender)))
               (by-language
                (and language (matching-voice voices language nil)))
               (by-gender
                (and gender (matching-voice voices nil gender))))
          (when alias
            (add
             (list :kind 'exact :scope 'local :engine-id engine-id
                   :voice-id (plist-get alias :voice-id))
             'exact-alias (plist-get alias :voice-id)))
          (when both
            (add
             (list :kind 'properties :scope 'portable
                   :engine-id engine-id :language language :gender gender)
             'language-and-gender (plist-get both :voice-id)))
          (when by-language
            (add
             (list :kind 'properties :scope 'portable
                   :engine-id engine-id :language language)
             'language (plist-get by-language :voice-id)))
          (when by-gender
            (add
             (list :kind 'properties :scope 'portable
                   :engine-id engine-id :gender gender)
             'gender (plist-get by-gender :voice-id)))
          (when voices
            (add
             (list :kind 'engine-default :scope 'portable
                   :engine-id engine-id)
             'engine-default (plist-get engine :default-voice-id)))))
      (nreverse suggestions))))

(defun emacsvox-aural-voice-workbench--suggestion-description (suggestion)
  "Return a review label for SUGGESTION."
  (format
   "%s: %s%s"
   (plist-get suggestion :reason)
   (emacsvox-aural-voice-workbench--selector-description
    (plist-get suggestion :selector))
   (if-let* ((realized (plist-get suggestion :realized)))
       (format " currently resolves to %s" realized)
     "")))

(defun emacsvox-aural-voice-workbench-suggest-route ()
  "Review and stage one inferred route for the current logical voice."
  (interactive)
  (let* ((logical (emacsvox-aural-voice-workbench--current-logical-voice))
         (existing
          (emacsvox-aural-voice-workbench--explicit-selectors logical))
         (suggestions
          (cl-remove-if
           (lambda (entry)
             (member (plist-get entry :selector) existing))
           (emacsvox-aural-voice-workbench--suggestions logical)))
         (candidates
          (mapcar
           (lambda (entry)
             (cons
              (emacsvox-aural-voice-workbench--suggestion-description entry)
              entry))
           suggestions)))
    (unless candidates
      (user-error "No new route suggestion is available for %s" logical))
    (let* ((choice
            (completing-read "Review route suggestion: " candidates
                             nil 'must-match))
           (suggestion (cdr (assoc-string choice candidates)))
           (selector (plist-get suggestion :selector))
           (reason (plist-get suggestion :reason)))
      (when (y-or-n-p (format "Stage %s for %s? " choice logical))
        (emacsvox-aural-voice-workbench--stage
         (format "Accepted %s suggestion for %s" reason logical)
         (lambda ()
           (emacsvox-aural-voice-workbench--replace-binding
            logical (append existing (list selector))))
         (list :logical-voice logical :kind 'suggested
               :detail (format "%s, %s" reason
                               (emacsvox-aural-voice-workbench--selector-description
                                selector))))))))

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

(defun emacsvox-aural-voice-workbench--current-engine-id ()
  "Return the engine ID on the current engine row."
  (unless (eq emacsvox-aural-voice-workbench-view 'engines)
    (user-error "Switch to the engine view first"))
  (or (tabulated-list-get-id)
      (user-error "Move to an engine row first")))

(defun emacsvox-aural-voice-workbench--policy-engine-list (field)
  "Return a copy of staged routing-policy engine FIELD."
  (copy-sequence
   (pcase field
     ('preferred
      (plist-get emacsvox-aural-voice-workbench-staged-profile
                 :engine-order))
     ('fallback
      (plist-get
       (plist-get emacsvox-aural-voice-workbench-staged-profile :fallback)
       :engines))
     ('disabled
      (plist-get emacsvox-aural-voice-workbench-staged-profile
                 :disabled-engines))
     (_ (error "Unknown routing-policy list: %S" field)))))

(defun emacsvox-aural-voice-workbench--set-policy-engine-list (field engines)
  "Set staged routing-policy FIELD to ordered ENGINES."
  (pcase field
    ('preferred
     (setf (plist-get emacsvox-aural-voice-workbench-staged-profile
                      :engine-order)
           engines))
    ('fallback
     (let ((fallback
            (copy-tree
             (plist-get emacsvox-aural-voice-workbench-staged-profile
                        :fallback))))
       (setf (plist-get fallback :engines) engines)
       (setf (plist-get emacsvox-aural-voice-workbench-staged-profile
                        :fallback)
             fallback)))
    ('disabled
     (setf (plist-get emacsvox-aural-voice-workbench-staged-profile
                      :disabled-engines)
           engines))))

(defun emacsvox-aural-voice-workbench--move-policy-engine
    (field direction label)
  "Move current engine in policy FIELD by DIRECTION, described by LABEL."
  (let* ((engine-id
          (emacsvox-aural-voice-workbench--current-engine-id))
         (engines
          (emacsvox-aural-voice-workbench--policy-engine-list field))
         (index (cl-position engine-id engines :test #'equal)))
    (unless index
      (user-error "%s is not in the %s; use its toggle command first"
                  engine-id label))
    (let ((destination (+ index direction)))
      (unless (<= 0 destination (1- (length engines)))
        (user-error "%s is already at the %s boundary" engine-id label))
      (cl-rotatef (nth index engines) (nth destination engines))
      (emacsvox-aural-voice-workbench--stage
       (format "Moved %s in global %s" engine-id label)
       (lambda ()
         (emacsvox-aural-voice-workbench--set-policy-engine-list
          field engines))))))

(defun emacsvox-aural-voice-workbench--toggle-policy-engine
    (field label)
  "Toggle current engine membership in policy FIELD described by LABEL."
  (let* ((engine-id
          (emacsvox-aural-voice-workbench--current-engine-id))
         (engines
          (emacsvox-aural-voice-workbench--policy-engine-list field))
         (present (member engine-id engines)))
    (emacsvox-aural-voice-workbench--stage
     (format "%s %s in %s"
             (if present "Removed" "Added") engine-id label)
     (lambda ()
       (emacsvox-aural-voice-workbench--set-policy-engine-list
        field
        (if present
            (delete engine-id engines)
          (append engines (list engine-id))))))))

(defun emacsvox-aural-voice-workbench-move-selector-up ()
  "Move the current selector or preferred engine earlier."
  (interactive)
  (if (eq emacsvox-aural-voice-workbench-view 'engines)
      (emacsvox-aural-voice-workbench--move-policy-engine
       'preferred -1 "preferred order")
    (emacsvox-aural-voice-workbench--move-selector -1)))

(defun emacsvox-aural-voice-workbench-move-selector-down ()
  "Move the current selector or preferred engine later."
  (interactive)
  (if (eq emacsvox-aural-voice-workbench-view 'engines)
      (emacsvox-aural-voice-workbench--move-policy-engine
       'preferred 1 "preferred order")
    (emacsvox-aural-voice-workbench--move-selector 1)))

(defun emacsvox-aural-voice-workbench-toggle-preferred-engine ()
  "Add or remove the current engine from global preferred order."
  (interactive)
  (emacsvox-aural-voice-workbench--toggle-policy-engine
   'preferred "global preferred order"))

(defun emacsvox-aural-voice-workbench-toggle-fallback-engine ()
  "Add or remove the current engine from global fallback order."
  (interactive)
  (emacsvox-aural-voice-workbench--toggle-policy-engine
   'fallback "global fallback order"))

(defun emacsvox-aural-voice-workbench-move-fallback-engine-up ()
  "Move the current engine earlier in global fallback order."
  (interactive)
  (emacsvox-aural-voice-workbench--move-policy-engine
   'fallback -1 "fallback order"))

(defun emacsvox-aural-voice-workbench-move-fallback-engine-down ()
  "Move the current engine later in global fallback order."
  (interactive)
  (emacsvox-aural-voice-workbench--move-policy-engine
   'fallback 1 "fallback order"))

(defun emacsvox-aural-voice-workbench-toggle-disabled-engine ()
  "Disable or restore the current engine in the staged policy."
  (interactive)
  (emacsvox-aural-voice-workbench--toggle-policy-engine
   'disabled "disabled engine list"))

(defun emacsvox-aural-voice-workbench-request-recovery-probe ()
  "Request a live recovery probe for the current failed engine."
  (interactive)
  (let ((engine-id
         (emacsvox-aural-voice-workbench--current-engine-id))
        (buffer (current-buffer)))
    (tts-request-engine-recovery-probe
     engine-id
     (lambda (result)
       (when (buffer-live-p buffer)
         (with-current-buffer buffer
           (emacsvox-aural-voice-workbench-refresh engine-id)
           (emacsvox-aural-voice-workbench--announce
            "%s recovery probe for %s"
            (if (equal (plist-get result :type)
                       "engine_recovery_probe_requested")
                "Armed" "Could not arm")
            engine-id)))))
    (emacsvox-aural-voice-workbench--announce
     "Requested recovery probe for %s" engine-id)))

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

(defun emacsvox-aural-voice-workbench--migrate-active-palette ()
  "Stage best current-adapter suggestions for every unmapped palette voice."
  (let (mappings)
    (dolist (logical (emacsvox-aural-voice-workbench--logical-voices))
      (unless (emacsvox-aural-voice-workbench--explicit-selectors logical)
        (when-let* ((suggestion
                     (car
                      (emacsvox-aural-voice-workbench--suggestions logical))))
          (push
           (cons logical (copy-tree (plist-get suggestion :selector)))
           mappings))))
    (unless mappings
      (user-error "No unmapped palette voices have current adapter suggestions"))
    (when
        (y-or-n-p
         (format
          "Stage %d active-palette mappings for review? " (length mappings)))
      (emacsvox-aural-voice-workbench--stage
       (format "Imported %d active palette mappings" (length mappings))
       (lambda ()
         (dolist (mapping mappings)
           (emacsvox-aural-voice-workbench--replace-binding
            (car mapping) (list (cdr mapping)))))
       (list :kind 'imported
             :detail (format "active palette, %d suggested mappings"
                             (length mappings)))))))

(defun emacsvox-aural-voice-workbench--migrate-omnivox-customize ()
  "Replace staged data with current legacy Omnivox Customize settings."
  (let* ((id (plist-get emacsvox-aural-voice-workbench-staged-profile :id))
         (profile
          (emacsvox-aural-routing-profile-from-omnivox
           id "Imported current Omnivox Customize routing")))
    (when
        (y-or-n-p
         "Replace every staged route with current Omnivox Customize values? ")
      (emacsvox-aural-voice-workbench--stage
       "Imported Omnivox Customize routing"
       (lambda ()
         (setq emacsvox-aural-voice-workbench-staged-profile
               (copy-tree profile)))
       '(:kind imported :detail "Omnivox Customize values")))))

(defun emacsvox-aural-voice-workbench-migrate ()
  "Stage an explicit migration from a legacy voice configuration source."
  (interactive)
  (let ((source
         (completing-read
          "Migration source: "
          '("active palette and current adapter families"
            "current Omnivox Customize values")
          nil 'must-match)))
    (if (string-prefix-p "current Omnivox" source)
        (emacsvox-aural-voice-workbench--migrate-omnivox-customize)
      (emacsvox-aural-voice-workbench--migrate-active-palette))))

(defun emacsvox-aural-voice-workbench-apply-preset ()
  "Review and stage one routing-policy or portability preset."
  (interactive)
  (let* ((candidates
          (append
           (mapcar
            (lambda (entry)
              (cons (plist-get (cdr entry) :label) (car entry)))
            emacsvox-aural-routing-engine-order-presets)
           '(("Prefer each logical voice's language" . native-language)
             ("Remove exact native IDs, keep portable traits" . fully-portable))))
         (choice
          (completing-read "Routing preset: " candidates nil 'must-match))
         (preset (cdr (assoc-string choice candidates)))
         (profile
          (emacsvox-aural-routing-apply-preset-to-data
           emacsvox-aural-voice-workbench-staged-profile preset
           emacsvox-aural-voice-workbench-inventory)))
    (when (y-or-n-p (format "Stage preset %s for review? " choice))
      (emacsvox-aural-voice-workbench--stage
       (format "Applied %s preset" preset)
       (lambda ()
         (setq emacsvox-aural-voice-workbench-staged-profile
               (copy-tree profile)))
       (list :kind 'preset :detail choice)))))

(defun emacsvox-aural-voice-workbench-export-profile ()
  "Export the staged routing profile without activating it."
  (interactive)
  (let* ((kind
          (completing-read
           "Export routing: "
           '("portable copy without exact native IDs"
             "complete machine-local profile")
           nil 'must-match))
         (portable (string-prefix-p "portable" kind))
         (file
          (read-file-name
           "Export routing profile to: " emacsvox-user-directory nil nil
           (format "%s-routing.el"
                   (plist-get emacsvox-aural-voice-workbench-staged-profile
                              :id)))))
    (emacsvox-aural-export-routing-profile
     emacsvox-aural-voice-workbench-staged-profile file portable
     emacsvox-aural-voice-workbench-inventory)
    (emacsvox-aural-voice-workbench--announce
     "%s routing profile exported to %s"
     (if portable "Portable" "Complete") file)))

(defun emacsvox-aural-voice-workbench-import-profile ()
  "Read one data-only routing profile into the staged workbench copy."
  (interactive)
  (let* ((file
          (read-file-name
           "Import routing profile: " emacsvox-user-directory nil 'must-match))
         (profile (emacsvox-aural-read-routing-profile file)))
    (when
        (y-or-n-p
         (format "Replace staged routing with profile %s from %s? "
                 (plist-get profile :id) file))
      (emacsvox-aural-voice-workbench--stage
       (format "Imported routing profile %s" (plist-get profile :id))
       (lambda ()
         (setq emacsvox-aural-voice-workbench-staged-profile
               (copy-tree profile)))
       (list :kind 'imported :detail (abbreviate-file-name file))))))

(defun emacsvox-aural-voice-workbench-undo ()
  "Undo the most recent staged routing edit without changing saved state."
  (interactive)
  (let ((snapshot (pop emacsvox-aural-voice-workbench-undo-stack)))
    (unless snapshot (user-error "No staged routing edit to undo"))
    (setq emacsvox-aural-voice-workbench-staged-profile
          (copy-tree (plist-get snapshot :profile))
          emacsvox-aural-voice-workbench-provenance
          (copy-tree (plist-get snapshot :provenance))
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
          emacsvox-aural-voice-workbench-provenance nil
          emacsvox-aural-voice-workbench-last-edit "Cancelled staged edits")
    (when emacsvox-aural-voice-workbench-assignment-target
      (setq emacsvox-aural-voice-workbench-filter
            emacsvox-aural-voice-workbench-assignment-return-filter
            emacsvox-aural-voice-workbench-assignment-return-filter nil
            emacsvox-aural-voice-workbench-assignment-target nil
            emacsvox-aural-voice-workbench-view 'logical))
    (emacsvox-aural-voice-workbench-refresh)
    (emacsvox-aural-voice-workbench--announce "Staged routing edits cancelled")))

(defun emacsvox-aural-voice-workbench--inventory-engine (engine-id)
  "Return staged inventory engine ENGINE-ID, or nil."
  (cl-find
   engine-id
   (plist-get emacsvox-aural-voice-workbench-inventory :engines)
   :key (lambda (engine) (plist-get engine :engine-id))
   :test #'equal))

(defun emacsvox-aural-voice-workbench--profile-diagnostics (profile)
  "Return non-blocking current-inventory diagnostics for PROFILE."
  (let (diagnostics checked-engines)
    (when (plist-get emacsvox-aural-voice-workbench-inventory :stale)
      (push
       '(:kind stale-inventory
         :message "Inventory is stale; routes will re-resolve when refreshed")
       diagnostics))
    (cl-labels
        ((check-engine
          (engine-id context)
          (when (and engine-id (not (member engine-id checked-engines)))
            (push engine-id checked-engines)
            (if-let* ((engine
                       (emacsvox-aural-voice-workbench--inventory-engine
                        engine-id)))
                (when
                    (member (format "%s" (plist-get engine :health))
                            '("failed" "unavailable"))
                  (push
                   (list :kind 'engine-unhealthy :engine-id engine-id
                         :context context
                         :message
                         (format "Engine %s is currently %s"
                                 engine-id (plist-get engine :health)))
                   diagnostics))
              (push
               (list :kind 'engine-missing :engine-id engine-id
                     :context context
                     :message
                     (format "Engine %s is not in current inventory" engine-id))
               diagnostics))))
         (check-selector
          (selector logical)
          (let* ((engine-id (plist-get selector :engine-id))
                 (engine (and engine-id
                              (emacsvox-aural-voice-workbench--inventory-engine
                               engine-id))))
            (check-engine engine-id logical)
            (when (and engine
                       (eq (plist-get selector :kind) 'exact)
                       (not
                        (cl-find
                         (plist-get selector :voice-id)
                         (plist-get engine :voices)
                         :key (lambda (voice) (plist-get voice :voice-id))
                         :test #'equal)))
              (push
               (list
                :kind 'voice-missing :logical-voice logical
                :engine-id engine-id
                :voice-id (plist-get selector :voice-id)
                :message
                (format "Exact voice %s/%s for %s is not installed"
                        engine-id (plist-get selector :voice-id) logical))
               diagnostics)))))
      (dolist (engine-id (append (plist-get profile :engine-order)
                                 (plist-get profile :disabled-engines)
                                 (plist-get (plist-get profile :fallback)
                                            :engines)))
        (check-engine engine-id 'global-policy))
      (when-let* ((global
                   (plist-get (plist-get profile :fallback) :global-default)))
        (check-selector global 'global-default))
      (dolist (binding (plist-get profile :bindings))
        (dolist (selector (plist-get binding :selectors))
          (check-selector selector (plist-get binding :logical-voice))))
      (nreverse diagnostics))))

(defun emacsvox-aural-voice-workbench--apply-complete (buffer status)
  "Update live workbench BUFFER with terminal apply STATUS."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when (derived-mode-p 'emacsvox-aural-voice-workbench-mode)
        (setq emacsvox-aural-voice-workbench-diagnostics
              (emacsvox-aural-voice-workbench--profile-diagnostics
               emacsvox-aural-voice-workbench-staged-profile))
        (emacsvox-aural-voice-workbench-refresh)
        (emacsvox-aural-voice-workbench--announce
         "Voice configuration apply %s"
         (plist-get status :status))))))

(defun emacsvox-aural-voice-workbench--apply-callback ()
  "Return a callback targeting the current workbench buffer."
  (let ((buffer (current-buffer)))
    (lambda (status)
      (emacsvox-aural-voice-workbench--apply-complete buffer status))))

(defun emacsvox-aural-voice-workbench-save-and-apply ()
  "Atomically save the staged profile and apply it to every speech stream."
  (interactive)
  (let* ((validated
          (emacsvox-aural-validate-routing-profile-data
           emacsvox-aural-voice-workbench-staged-profile))
         (previous
          (copy-tree emacsvox-aural-voice-workbench-committed-profile))
         (diagnostics
          (emacsvox-aural-voice-workbench--profile-diagnostics validated))
         (callback (emacsvox-aural-voice-workbench--apply-callback)))
    (setq emacsvox-aural-voice-workbench-diagnostics diagnostics)
    (if (not (emacsvox-aural-voice-workbench--dirty-p))
        (progn
          (emacsvox-aural-apply-routing-profile
           (plist-get validated :id) callback)
          (emacsvox-aural-voice-workbench--announce
           "Committed routing is being reapplied"))
      (emacsvox-aural-commit-routing-profile-data
       validated emacsvox-aural-routing-profiles-file callback)
      (setq emacsvox-aural-voice-workbench-applied-undo previous
            emacsvox-aural-voice-workbench-committed-profile
            (copy-tree validated)
            emacsvox-aural-voice-workbench-staged-profile
            (copy-tree validated)
            emacsvox-aural-voice-workbench-undo-stack nil
            emacsvox-aural-voice-workbench-last-edit
            "Saved and submitted complete routing profile")
      (emacsvox-aural-voice-workbench-refresh)
      (emacsvox-aural-voice-workbench--announce
       "Routing profile saved atomically; apply pending%s"
       (if diagnostics
           (format ", %d current inventory warning%s"
                   (length diagnostics)
                   (if (= (length diagnostics) 1) "" "s"))
         "")))))

(defun emacsvox-aural-voice-workbench-retry-apply ()
  "Idempotently retry the committed profile on all live speech streams."
  (interactive)
  (when (emacsvox-aural-voice-workbench--dirty-p)
    (user-error "Save or cancel staged edits before retrying live apply"))
  (emacsvox-aural-apply-routing-profile
   (plist-get emacsvox-aural-voice-workbench-committed-profile :id)
   (emacsvox-aural-voice-workbench--apply-callback))
  (emacsvox-aural-voice-workbench--announce
   "Committed voice configuration apply retried"))

(defun emacsvox-aural-voice-workbench-undo-applied ()
  "Restore and apply the previous known-good profile revision."
  (interactive)
  (unless emacsvox-aural-voice-workbench-applied-undo
    (user-error "No saved Voice Workbench revision is available to restore"))
  (when (y-or-n-p "Restore the previous saved routing revision? ")
    (let ((restored (copy-tree emacsvox-aural-voice-workbench-applied-undo)))
      (emacsvox-aural-commit-routing-profile-data
       restored emacsvox-aural-routing-profiles-file
       (emacsvox-aural-voice-workbench--apply-callback))
      (setq emacsvox-aural-voice-workbench-committed-profile
            (copy-tree restored)
            emacsvox-aural-voice-workbench-staged-profile
            (copy-tree restored)
            emacsvox-aural-voice-workbench-applied-undo nil
            emacsvox-aural-voice-workbench-undo-stack nil
            emacsvox-aural-voice-workbench-last-edit
            "Restored previous saved routing revision")
      (emacsvox-aural-voice-workbench-refresh)
      (emacsvox-aural-voice-workbench--announce
       "Previous routing revision restored and apply pending"))))

(defun emacsvox-aural-voice-workbench--normalized-acss-value (value)
  "Normalize zero-to-nine ACSS VALUE for transactional preview."
  (and (numberp value) (/ (float (max 0 (min 9 value))) 9.0)))

(defun emacsvox-aural-voice-workbench--preview-acss (logical-voice)
  "Return portable normalized ACSS for LOGICAL-VOICE, when available."
  (when-let* ((entry
               (emacsvox-aural-voice-workbench--palette-entry logical-voice)))
    (let* ((definition (cdr entry))
           (style
            (emacsvox-aural-voice-tuner--complete-style
             definition (emacsvox-aural-voice-workbench--active-palette)))
           result)
      (dolist
          (dimension
           '(rate average-pitch pitch-range stress richness))
        (when-let* ((value
                     (plist-get
                      style
                      (emacsvox-aural--voice-dimension-key dimension)))
                    (normalized
                     (emacsvox-aural-voice-workbench--normalized-acss-value
                      value)))
          (setq
           result
           (plist-put
            result
            (emacsvox-aural--voice-dimension-key dimension)
            normalized))))
      result)))

(defun emacsvox-aural-voice-workbench--preview-effects (logical-voice)
  "Return normalized post-synthesis effects for LOGICAL-VOICE."
  (when-let* ((entry
               (emacsvox-aural-voice-workbench--palette-entry logical-voice)))
    (let ((style
           (emacsvox-aural-voice-tuner--complete-style
            (cdr entry) (emacsvox-aural-voice-workbench--active-palette)))
          result)
      (dolist (dimension emacsvox-aural-post-synthesis-dimensions)
        (when-let* ((value
                     (plist-get
                      style
                      (emacsvox-aural--voice-dimension-key dimension)))
                    (normalized
                     (emacsvox-aural-voice-workbench--normalized-acss-value
                      value)))
          (setq
           result
           (plist-put
            result
            (emacsvox-aural--voice-dimension-key dimension)
            normalized))))
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
          (or
           (car (emacsvox-aural-voice-workbench--selectors logical-voice))
           (emacsvox-aural-voice-workbench--default-tuning-selector)
           (list :kind 'properties :language language :scope 'portable))))
    (list
     :text emacsvox-aural-voice-workbench-preview-text
     :selector selector :language language
     :acss (emacsvox-aural-voice-workbench--preview-acss logical-voice)
     :effects (emacsvox-aural-voice-workbench--preview-effects logical-voice))))

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

(defun emacsvox-aural-voice-workbench--editable-palette
    (palette logical-voice)
  "Return an editable PALETTE for tuning LOGICAL-VOICE.

When PALETTE is built in, offer to create and activate a personal copy before
refreshing the Workbench at LOGICAL-VOICE."
  (if (not
       (emacsvox-aural-voice-palette-built-in
        (emacsvox-aural-voice-palette palette)))
      palette
    (unless
        (y-or-n-p
         (format
          "Palette %s is built in; create and activate an editable copy? "
          palette))
      (user-error "Voice tuning cancelled"))
    (let ((copy (emacsvox-aural-voice-palettes--copy palette)))
      (emacsvox-aural-select-voice-palette copy)
      (emacsvox-aural-voice-workbench-refresh
       (format "%s" logical-voice))
      copy)))

(defun emacsvox-aural-voice-workbench-tune ()
  "Tune the current logical voice against its effective preview route."
  (interactive)
  (unless (memq emacsvox-aural-voice-workbench-view '(logical styles))
    (user-error "Tune a logical voice from the logical or styles view"))
  (let* ((logical
          (or (tabulated-list-get-id)
              (user-error "Move to a logical voice first")))
         (entry
          (or (emacsvox-aural-voice-workbench--palette-entry logical)
              (user-error "%s is not defined by the active palette" logical)))
         (selector
          (or
           (car (emacsvox-aural-voice-workbench--selectors logical))
           (emacsvox-aural-voice-workbench--default-tuning-selector)
           (user-error "No available speech engine can tune %s" logical)))
         (pair
          (emacsvox-aural-voice-workbench--selector-realization selector))
         (engine
          (or (car pair)
              (cl-find
               (plist-get selector :engine-id)
               (plist-get emacsvox-aural-voice-workbench-inventory :engines)
               :key (lambda (item) (plist-get item :engine-id))
               :test #'equal)))
         (binding
          (emacsvox-aural-voice-workbench--profile-binding logical))
         (palette
          (emacsvox-aural-voice-workbench--editable-palette
           (emacsvox-aural-voice-workbench--active-palette) logical)))
    (emacsvox-aural-voice-tuner-open
     palette
     (car entry) (current-buffer)
     emacsvox-aural-voice-workbench-preview-text
     :selector selector
     :language (plist-get binding :language)
     :engine engine
     :realized
     (and pair
          (list :engine-id (plist-get (car pair) :engine-id)
                :voice-id (plist-get (cadr pair) :voice-id))))))

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
    (emacsvox-aural-ui-with-help-window
      (princ (format "%s\n\n" summary))
      (princ (format "Status: %s\n\n"
                     (emacsvox-aural-voice-workbench--header)))
      (princ
       (format "Inventory:\n%S\n\n"
               emacsvox-aural-voice-workbench-inventory))
      (princ
       (format "Staged routing profile:\n%S\n"
               emacsvox-aural-voice-workbench-staged-profile))
      (princ
       (format "\nApply status:\n%S\n"
               emacsvox-aural-routing-apply-status))
      (princ
       (format "\nCurrent diagnostics:\n%S\n"
               emacsvox-aural-voice-workbench-diagnostics))
      (princ
       (format "\nStaged provenance:\n%S\n"
               emacsvox-aural-voice-workbench-provenance)))
    summary))

(defun emacsvox-aural-voice-workbench-help ()
  "Display and speak Voice Workbench navigation help."
  (interactive)
  (emacsvox-aural-ui-with-help-window
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
      "S stop preview        t tune logical voice on effective route\n"
      "a assign or choose physical voice\n"
      "j review one route suggestion\n"
      "c cancel assignment   [/] move selector earlier/later\n"
      "d delete selector     y copy another logical route\n"
      "M map all unmapped    X replace engine in selected routes\n"
      "Engine view: O toggle preferred; [/] reorder preferred\n"
      "f toggle fallback     {/} reorder fallback\n"
      "D disable/restore     K request failed-engine recovery probe\n"
      "u undo staged edit    C-c C-k cancel all staged edits\n"
      "x explain row\n"
      "m migrate legacy setup  N stage routing preset\n"
      "E export profile        I import profile\n"
      "w or C-c C-c save and apply\n"
      "r retry committed apply\n"
      "U restore previous saved revision\n"
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
  (setq-local emacsvox-aural-voice-workbench-applied-undo nil)
  (setq-local emacsvox-aural-voice-workbench-diagnostics
              (emacsvox-aural-voice-workbench--profile-diagnostics
               emacsvox-aural-voice-workbench-staged-profile))
  (setq-local emacsvox-aural-voice-workbench-provenance nil)
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
       ("t" . emacsvox-aural-voice-workbench-tune)
       ("a" . emacsvox-aural-voice-workbench-assign)
       ("j" . emacsvox-aural-voice-workbench-suggest-route)
       ("c" . emacsvox-aural-voice-workbench-cancel-assignment)
       ("[" . emacsvox-aural-voice-workbench-move-selector-up)
       ("]" . emacsvox-aural-voice-workbench-move-selector-down)
       ("O" . emacsvox-aural-voice-workbench-toggle-preferred-engine)
       ("f" . emacsvox-aural-voice-workbench-toggle-fallback-engine)
       ("{" . emacsvox-aural-voice-workbench-move-fallback-engine-up)
       ("}" . emacsvox-aural-voice-workbench-move-fallback-engine-down)
       ("D" . emacsvox-aural-voice-workbench-toggle-disabled-engine)
       ("K" . emacsvox-aural-voice-workbench-request-recovery-probe)
       ("d" . emacsvox-aural-voice-workbench-delete-selector)
       ("y" . emacsvox-aural-voice-workbench-copy-route)
       ("M" . emacsvox-aural-voice-workbench-bind-unmapped)
       ("X" . emacsvox-aural-voice-workbench-replace-engine)
       ("m" . emacsvox-aural-voice-workbench-migrate)
       ("N" . emacsvox-aural-voice-workbench-apply-preset)
       ("E" . emacsvox-aural-voice-workbench-export-profile)
       ("I" . emacsvox-aural-voice-workbench-import-profile)
       ("u" . emacsvox-aural-voice-workbench-undo)
       ("x" . emacsvox-aural-voice-workbench-describe)
       ("w" . emacsvox-aural-voice-workbench-save-and-apply)
       ("C-c C-c" . emacsvox-aural-voice-workbench-save-and-apply)
       ("C-c C-k" . emacsvox-aural-voice-workbench-cancel-staged)
       ("r" . emacsvox-aural-voice-workbench-retry-apply)
       ("U" . emacsvox-aural-voice-workbench-undo-applied)
       ("q" . emacsvox-aural-quit)
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
(add-hook 'emacsvox-aural-routing-apply-status-hook
          #'emacsvox-aural-voice-workbench-refresh-if-live)
(add-hook 'tts-realized-voice-changed-hook
          #'emacsvox-aural-voice-workbench-refresh-if-live)

(provide 'emacsvox-aural-voice-workbench)
;;; emacsvox-aural-voice-workbench.el ends here
