;;; emacsvox-aural-transport.el --- Concrete aural transport -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Freeze semantic and contextual decisions while the source buffer is
;; current, compile render plans to concrete resources and TTS commands, and
;; queue only backend-ready ordered actions.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'emacsvox-aural-concrete)
(require 'emacsvox-aural-history)
(require 'emacsvox-aural-schemes)
(require 'emacsvox-aural-spatial)

(declare-function emacsvox-sounds-play-concrete-cue
                  "emacsvox-sounds" (resource sample-id &optional balance))
(declare-function emacsvox-queue-resource
                  "emacsvox-sounds" (resource))
(declare-function tts--protocol-dispatch "tts-speak" ())
(declare-function tts--protocol-queue-code "tts-speak" (code))
(declare-function tts--protocol-queue-text "tts-speak" (text))
(declare-function tts--protocol-silence "tts-speak" (duration &optional force))
(declare-function tts-get-voice-command "tts-speak" (voice))
(declare-function tts-get-voice-for-face "tts-speak" (face))
(declare-function tts-initialize "tts-speak" ())
(declare-function tts-voice-capabilities "tts-speak" ())
(declare-function tts-voice-family-id
                  "tts-speak" (family &optional capabilities))
(declare-function tts-voice-reset-code "tts-speak" ())
(declare-function voice-from-acss "voice-setup" (style))
(declare-function make-acss "voice-setup" (&rest slots))

(defvar emacsvox-sounds-current-pack)
(defvar emacsvox-aural-voice-palette-override)
(defvar emacsvox-use-icons)
(defvar tts-speaker-process)
(defvar voice-lock-mode)

(cl-defstruct
    (emacsvox-aural-source-run
     (:constructor emacsvox-aural--make-source-run))
  "One source formatting run captured inside an aural object."
  start end facts context icon)

(defvar emacsvox-aural-submission-context nil
  "Dynamically bound source context for the current speech submission.")

(defvar emacsvox-aural-submission-facts nil
  "Dynamically bound semantic facts for the current speech submission.")

(defvar emacsvox-aural-submission-module nil
  "Dynamically bound module for the current speech submission.")

(defvar emacsvox-aural-submission-occasion nil
  "Dynamically bound occasion for the current speech submission.")

(defvar emacsvox-aural-ui-interface-buffer)

(defcustom emacsvox-aural-unsupported-volume-policy 'degrade
  "Policy for explicit volume when the active transport cannot apply it.

`degrade' queues the presentation without volume and records the exact
capability degradation.  `reject' signals an error before anything is queued."
  :type '(choice
          (const :tag "Queue without volume and report degradation" degrade)
          (const :tag "Reject presentations requesting volume" reject))
  :group 'emacsvox-aural)

(defvar emacsvox-aural--file-digest-cache
  (make-hash-table :test #'equal)
  "Content digests keyed by canonical file identity and metadata.")

(defconst emacsvox-aural-concrete-plan-property
  'emacsvox-aural-concrete-plan
  "Text property holding a source-resolved concrete plan.")

(defconst emacsvox-aural-facts-property
  'emacsvox-aural-facts
  "Text property holding semantic facts for one formatted text run.")

(defconst emacsvox-aural-module-property
  'emacsvox-aural-module
  "Text property overriding the semantic module for one text run.")

(defconst emacsvox-aural-occasion-property
  'emacsvox-aural-occasion
  "Text property overriding presentation occasion for one text run.")

(defconst emacsvox-aural-object-property
  'emacsvox-aural-object
  "Text property explicitly identifying one aural object.

Adjacent text with the same non-nil value belongs to one object even when
run-local semantic or presentation properties change.  Without this property,
the complete submission is one inferred object until semantic facts, module,
occasion, or a new queued icon changes.")

(defconst emacsvox-aural-source-faces-property
  'emacsvox-aural-source-faces
  "Text property holding an authoritative named source-face snapshot.")

(defun emacsvox-aural--transport-error (format-string &rest arguments)
  "Signal a transport error described by FORMAT-STRING and ARGUMENTS."
  (signal
   'emacsvox-aural-transport-error
   (list (apply #'format format-string arguments))))

(defun emacsvox-aural-capture-context (&optional module occasion)
  "Capture immutable source context for MODULE and OCCASION."
  (let ((context
         (copy-tree
          (emacsvox-aural-current-context
           (or module emacsvox-aural-submission-module)
           (or
            occasion
            emacsvox-aural-submission-occasion
            'continuous)))))
    (when
        (and
         (boundp 'emacsvox-aural-ui-interface-buffer)
         emacsvox-aural-ui-interface-buffer
         (not emacsvox-aural-history-record-interface-presentations))
      (setq
       context
       (plist-put context :history-recording-inhibited t)))
    context))

(defun emacsvox-aural--resource-pack ()
  "Return the effective sound pack at the current submission boundary."
  (or
   (and
    (boundp 'emacsvox-sounds-current-pack)
    emacsvox-sounds-current-pack
    (emacsvox-aural-resource-pack emacsvox-sounds-current-pack)
    emacsvox-sounds-current-pack)
   (emacsvox-aural-effective-scheme-provider 'resource-pack)
   'chimes))

(defun emacsvox-aural--voice-palette ()
  "Return the effective voice palette at the current submission boundary."
  (or
   (and
    emacsvox-aural-voice-palette-override
    (emacsvox-aural-voice-palette
     emacsvox-aural-voice-palette-override)
    emacsvox-aural-voice-palette-override)
   (emacsvox-aural-effective-scheme-provider 'voice-palette)
   'acss-default))

(defun emacsvox-aural-clear-file-digest-cache (&optional _pack)
  "Clear cached sound digests after a resource-pack change.

The optional PACK argument makes this function suitable for
`emacsvox-aural-resource-packs-changed-hook'."
  (clrhash emacsvox-aural--file-digest-cache))

(add-hook
 'emacsvox-aural-resource-packs-changed-hook
 #'emacsvox-aural-clear-file-digest-cache)

(add-hook
 'emacsvox-aural-resource-overlays-changed-hook
 #'emacsvox-aural-clear-file-digest-cache)

(defun emacsvox-aural--file-digest (file)
  "Return a cached SHA-256 digest of the literal contents of FILE."
  (let* ((canonical (file-truename file))
         (attributes (file-attributes canonical 'string)))
    (unless (and attributes (file-readable-p canonical))
      (emacsvox-aural--transport-error
       "Concrete cue resource is not readable: %s" file))
    (let* ((metadata
            (list
             (nth 5 attributes)
             (nth 6 attributes)
             (nth 7 attributes)
             (nth 10 attributes)
             (nth 11 attributes)))
           (cached
            (gethash canonical emacsvox-aural--file-digest-cache)))
      (if (and cached (equal (car cached) metadata))
          (cdr cached)
        (let ((digest
               (with-temp-buffer
                 (set-buffer-multibyte nil)
                 (insert-file-contents-literally canonical)
                 (secure-hash 'sha256 (current-buffer)))))
          (puthash
           canonical
           (cons metadata digest)
           emacsvox-aural--file-digest-cache)
          digest)))))

(defun emacsvox-aural--sample-component (value)
  "Return VALUE as a Pulse/PipeWire-safe identifier component."
  (replace-regexp-in-string
   "[^[:alnum:]_-]+" "-"
   (if (symbolp value) (symbol-name value) (format "%s" value))))

(defun emacsvox-aural-sample-id (pack cue resource)
  "Return an owned content-addressed sample identifier.

PACK and CUE remain readable while RESOURCE contents distinguish generations."
  (format
   "emacsvox-%s-%s-%s"
   (emacsvox-aural--sample-component pack)
   (emacsvox-aural--sample-component cue)
   (substring (emacsvox-aural--file-digest resource) 0 16)))

(defun emacsvox-aural--resolve-voice-name (voice palette)
  "Resolve named VOICE through PALETTE and existing personality variables."
  (let ((resolved
         (or
          (and
           (symbolp voice)
           (emacsvox-aural-voice voice palette))
          voice)))
    (if
        (and
         (symbolp resolved)
         (boundp resolved)
         (not (eq (symbol-value resolved) resolved)))
        (symbol-value resolved)
      resolved)))

(defun emacsvox-aural--legacy-voice-adapter ()
  "Identify the active legacy ACSS adapter from its compiler function."
  (let ((implementation
         (and
          (fboundp 'tts-define-voice-from-acss)
          (symbol-function 'tts-define-voice-from-acss))))
    (or
     (cdr
     (assq
       implementation
       '((dectalk-define-voice-from-acss . dectalk)
         (outloud-define-voice-from-acss . outloud)
         (espeak-define-voice-from-acss . espeak)
         (mac-define-voice-from-acss . mac)
         (swiftmac-define-voice-from-acss . swiftmac)
         (plain-define-voice-from-acss . plain))))
     'unknown)))

(defun emacsvox-aural--legacy-voice-capabilities (adapter)
  "Return compatibility voice capabilities for legacy ADAPTER."
  (let ((dimensions
         (pcase adapter
           ('dectalk emacsvox-aural-voice-dimensions)
           ('outloud '(average-pitch pitch-range stress richness))
           ('espeak '(family average-pitch pitch-range richness))
           ((or 'mac 'swiftmac) '(family average-pitch pitch-range))
           (_ nil))))
    (list
     :adapter adapter
     :source 'compatibility
     :family-selection
     (cond
      ((not (memq 'family dimensions)) 'unsupported)
      ((memq adapter '(mac swiftmac)) 'free-form)
      (t 'free-form))
     :families nil
     :generic-families nil
     :dimensions (copy-sequence dimensions)
     :parameters nil)))

(defun emacsvox-aural-active-voice-capabilities ()
  "Return adapter-owned ACSS capabilities for the active speech adapter."
  (let* ((reported
          (and
           (fboundp 'tts-voice-capabilities)
           (tts-voice-capabilities)))
         (adapter (emacsvox-aural--legacy-voice-adapter)))
    (copy-tree
     (if
         (and
          reported
          (not (eq (plist-get reported :adapter) 'unknown)))
         reported
       (emacsvox-aural--legacy-voice-capabilities adapter)))))

(defun emacsvox-aural--voice-family-selection (capability)
  "Return the family-selection policy declared by CAPABILITY."
  (or
   (plist-get capability :family-selection)
   (cond
    ((plist-get capability :families) 'enumerated)
    ((memq 'family (plist-get capability :dimensions)) 'free-form)
    (t 'unsupported))))

(defun emacsvox-aural--resolve-voice-family (family capability)
  "Resolve requested FAMILY through active CAPABILITY.

Return nil when an enumerated adapter cannot provide the requested family."
  (pcase (emacsvox-aural--voice-family-selection capability)
    ('enumerated
     (and
      (fboundp 'tts-voice-family-id)
      (tts-voice-family-id family capability)))
    ('free-form family)
    (_ nil)))

(defun emacsvox-aural--unavailable-family-degradation
    (family capability &optional voice)
  "Describe unavailable FAMILY under CAPABILITY for optional palette VOICE."
  (append
   (list
    :reason 'unavailable-voice-family
    :adapter (plist-get capability :adapter))
   (when voice (list :voice voice))
   (list
    :dimension 'family
    :requested family
    :available
    (mapcar #'car (plist-get capability :families)))))

(defun emacsvox-aural-voice-palette-capability-degradations
    (&optional palette)
  "Return unsupported explicit dimensions in PALETTE for the active adapter.

Existing personality-backed presets are adapter-owned compatibility values
and are not reconstructed or rejected here."
  (let* ((palette (or palette (emacsvox-aural--voice-palette)))
         (capability (emacsvox-aural-active-voice-capabilities))
         (supported (plist-get capability :dimensions))
         degradations)
    (dolist (entry (emacsvox-aural-effective-voice-entries palette))
      (when (emacsvox-aural-voice-style-p (cdr entry))
        (dolist (dimension emacsvox-aural-voice-dimensions)
          (let* ((key (emacsvox-aural--voice-dimension-key dimension))
                 (value (plist-get (cdr entry) key)))
            (when value
              (cond
               ((not (memq dimension supported))
                (push
                 (list
                  :reason 'unsupported-voice-dimension
                  :adapter (plist-get capability :adapter)
                  :voice (car entry)
                  :dimension dimension
                  :requested value)
                 degradations))
               ((and
                 (eq dimension 'family)
                 (eq
                  (emacsvox-aural--voice-family-selection capability)
                  'enumerated)
                 (not
                  (emacsvox-aural--resolve-voice-family
                   value capability)))
                (push
                 (emacsvox-aural--unavailable-family-degradation
                  value capability (car entry))
                 degradations))))))))
    (nreverse degradations)))
(defun emacsvox-aural--empty-voice-style ()
  "Return a complete device-independent default voice style."
  (let (style)
    (dolist (dimension emacsvox-aural-voice-dimensions)
      (setq
       style
       (plist-put
        style (emacsvox-aural--voice-dimension-key dimension) nil)))
    style))

(defun emacsvox-aural--personality-style (personality)
  "Return complete ACSS settings declared for PERSONALITY, or nil."
  (let ((settings-variable
         (intern-soft (format "%s-settings" personality))))
    (when
        (and
         settings-variable
         (boundp settings-variable)
         (proper-list-p (symbol-value settings-variable)))
      (let ((settings (symbol-value settings-variable))
            (style (emacsvox-aural--empty-voice-style)))
        (cl-loop
         for dimension in emacsvox-aural-voice-dimensions
         for index from 0
         do
         (setq
          style
          (plist-put
           style
           (emacsvox-aural--voice-dimension-key dimension)
           (nth index settings))))
        style))))

(defun emacsvox-aural--join-voice-commands (&rest commands)
  "Join nonempty adapter COMMANDS, returning nil when none remain."
  (let ((commands
         (cl-remove-if
          (lambda (command)
            (or (null command)
                (and (stringp command) (string-empty-p command))))
          commands)))
    (when commands
      (mapconcat #'identity commands " "))))

(defun emacsvox-aural--style-acss (style)
  "Return an ACSS record containing non-nil values from STYLE."
  (unless (fboundp 'make-acss)
    (emacsvox-aural--transport-error "ACSS voice support has not loaded"))
  (make-acss
   :family (plist-get style :family)
   :average-pitch (plist-get style :average-pitch)
   :pitch-range (plist-get style :pitch-range)
   :stress (plist-get style :stress)
   :richness (plist-get style :richness)))

(defun emacsvox-aural--compile-personality-command (personality)
  "Compile PERSONALITY with the selected speech adapter."
  (unless (symbolp personality)
    (emacsvox-aural--transport-error
     "Voice did not resolve to a personality: %S" personality))
  (unless (fboundp 'tts-get-voice-command)
    (emacsvox-aural--transport-error
     "The selected TTS adapter has no voice compiler"))
  (tts-get-voice-command personality))

(defun emacsvox-aural--compile-explicit-voice-style
    (style palette provenance)
  "Compile explicit STYLE through PALETTE with PROVENANCE."
  (let* ((capability (emacsvox-aural-active-voice-capabilities))
         (supported (plist-get capability :dimensions))
         (preset-present (plist-member style :preset))
         (preset (and preset-present (plist-get style :preset)))
         (base
          (when preset-present
            (emacsvox-aural-compile-voice-style
             preset palette provenance)))
         (effective
          (or
           (and base
                (copy-tree (emacsvox-aural-compiled-voice-style base)))
           (emacsvox-aural--empty-voice-style)))
         command-style
         degradations)
    (when
        (and
         base
         (eq (emacsvox-aural-compiled-voice-command base) 'inaudible))
      (emacsvox-aural--transport-error
       "Inaudible cannot be used as the base of an explicit voice style"))
    (dolist (dimension emacsvox-aural-voice-dimensions)
      (let ((key (emacsvox-aural--voice-dimension-key dimension)))
        (when (plist-member style key)
          (let ((value (plist-get style key)))
            (setq effective (plist-put effective key nil))
            (cond
             ((null value))
             ((and
               (eq dimension 'family)
               (memq dimension supported))
              (let ((family
                     (emacsvox-aural--resolve-voice-family
                      value capability)))
                (if family
                    (progn
                      (setq command-style
                            (plist-put command-style key family))
                      (setq effective (plist-put effective key family)))
                  (push
                   (emacsvox-aural--unavailable-family-degradation
                    value capability)
                   degradations))))
             ((memq dimension supported)
              (setq command-style (plist-put command-style key value))
              (setq effective (plist-put effective key value)))
             (t
              (push
               (list
                :reason 'unsupported-voice-dimension
                :adapter (plist-get capability :adapter)
                :dimension dimension
                :requested value)
               degradations)))))))
    (let ((style-command
           (when command-style
             (unless (fboundp 'voice-from-acss)
               (emacsvox-aural--transport-error
                "ACSS voice support has not loaded"))
             (emacsvox-aural--compile-personality-command
              (voice-from-acss
               (emacsvox-aural--style-acss command-style))))))
      (emacsvox-aural--make-compiled-voice
       :command
       (emacsvox-aural--join-voice-commands
        (and base (emacsvox-aural-compiled-voice-command base))
        style-command)
       :request (copy-tree style)
       :style effective
       :provenance (copy-tree provenance)
       :capability capability
       :degradations
       (append
        (and
         base
         (copy-tree (emacsvox-aural-compiled-voice-degradations base)))
        (nreverse degradations))
       :preset
       (or
        preset
        (and base (emacsvox-aural-compiled-voice-preset base)))))))

(defun emacsvox-aural-compile-voice-style
    (voice &optional palette provenance)
  "Compile VOICE once and return a concrete voice result.

PALETTE defaults to the active palette.  PROVENANCE maps the winning preset
and ACSS dimensions to the rules that supplied them."
  (let* ((palette (or palette (emacsvox-aural--voice-palette)))
         (capability (emacsvox-aural-active-voice-capabilities)))
    (cond
     ((null voice)
      (emacsvox-aural--make-compiled-voice
       :command nil
       :request nil
       :style (emacsvox-aural--empty-voice-style)
       :provenance (copy-tree provenance)
       :capability capability))
     ((or
       (eq voice 'inaudible)
       (and (proper-list-p voice) (memq 'inaudible voice)))
      (emacsvox-aural--make-compiled-voice
       :command 'inaudible
       :request (copy-tree voice)
       :provenance (copy-tree provenance)
       :capability capability
       :preset 'inaudible))
     ((or
       (emacsvox-aural-voice-style-p voice)
       (emacsvox-aural--acss-p voice))
      (emacsvox-aural--compile-explicit-voice-style
       (if (emacsvox-aural--acss-p voice)
           (emacsvox-aural--acss-to-voice-style voice)
         voice)
       palette provenance))
     ((and (proper-list-p voice) voice)
      (let ((parts
             (mapcar
              (lambda (entry)
                (emacsvox-aural-compile-voice-style
                 entry palette provenance))
              voice)))
        (emacsvox-aural--make-compiled-voice
         :command
         (apply
          #'emacsvox-aural--join-voice-commands
          (mapcar #'emacsvox-aural-compiled-voice-command parts))
         :request (copy-tree voice)
         :provenance (copy-tree provenance)
         :capability capability
         :degradations
         (apply
          #'append
         (mapcar
           #'emacsvox-aural-compiled-voice-degradations parts))
         :preset (copy-tree voice))))
     ((symbolp voice)
      (let ((palette-definition
             (emacsvox-aural-voice voice palette)))
        (if palette-definition
            (let ((compiled
                   (emacsvox-aural-compile-voice-style
                    palette-definition palette provenance)))
              (setf
               (emacsvox-aural-compiled-voice-request compiled) voice
               (emacsvox-aural-compiled-voice-preset compiled) voice)
              compiled)
          (let* ((resolved (emacsvox-aural--resolve-voice-name voice palette))
                 (style (emacsvox-aural--personality-style voice)))
            (emacsvox-aural--make-compiled-voice
             :command
             (emacsvox-aural--compile-personality-command resolved)
             :request voice
             :style style
             :provenance (copy-tree provenance)
             :capability capability
             :preset voice)))))
     (t
      (emacsvox-aural--transport-error
       "Cannot compile voice value: %S" voice)))))

(defun emacsvox-aural-compile-voice (voice &optional palette)
  "Compile VOICE through PALETTE to a concrete TTS command.

Return `inaudible' when VOICE suppresses content, nil for the default voice,
or a command string understood by the selected speech server."
  (emacsvox-aural-compiled-voice-command
   (emacsvox-aural-compile-voice-style voice palette)))

(defun emacsvox-aural--resolve-cue (cue pack)
  "Return concrete resource and sample identifier for CUE in PACK."
  (let* ((resource (emacsvox-aural-resolve-cue cue pack t))
         (resolved-cue cue))
    (unless resource
      (setq
       resolved-cue 'button
       resource (emacsvox-aural-resolve-cue 'button pack t)))
    (unless resource
      (emacsvox-aural--transport-error
       "Cue %S has no concrete resource in pack %S" cue pack))
    (list
     resource
     (emacsvox-aural-sample-id pack resolved-cue resource)
     resolved-cue)))

(defun emacsvox-aural--spatial-degradation
    (reason requested balance capability &optional extra)
  "Return one spatial degradation record.

REASON describes the reduction from REQUESTED to BALANCE for CAPABILITY.
EXTRA supplies identifying properties such as `:action' or `:content'."
  (append
   extra
   (list
    :reason reason
    :requested-space (copy-tree requested)
    :balance balance
    :capability capability)))

(defun emacsvox-aural--compile-space
    (space kind target &optional resource-spatialization identity)
  "Compile SPACE for KIND and transport TARGET.

RESOURCE-SPATIALIZATION describes a cue asset.  IDENTITY is a plist used in
degradation records.  Return balance, capability, and degradation records."
  (let* ((capability (emacsvox-aural-spatial-capability target))
         (requested
          (and space
               (emacsvox-aural-spatial-requested-balance space)))
         (balance requested)
         degradations)
    (when space
      (when (plist-member space :azimuth)
        (push
         (emacsvox-aural--spatial-degradation
          'azimuth-reduced-to-stereo
          space balance capability identity)
         degradations))
      (let ((policy
             (emacsvox-aural-spatial-apply-user-policy balance kind)))
        (setq balance (plist-get policy :balance))
        (dolist (reason (plist-get policy :reasons))
          (push
           (emacsvox-aural--spatial-degradation
            reason space balance capability identity)
           degradations)))
      (cond
       ((and
         (eq kind 'cue)
         (eq resource-spatialization 'pre-spatialized)
         (not (zerop balance)))
        (setq balance 0.0)
        (push
         (emacsvox-aural--spatial-degradation
          'pre-spatialized-resource
          space balance capability identity)
         degradations))
       ((and (not (eq capability 'stereo))
             (not (zerop balance)))
        (setq balance 0.0)
        (push
         (emacsvox-aural--spatial-degradation
          (if (eq capability 'mono) 'mono-output 'backend-centered)
          space balance capability identity)
         degradations))))
    (list
     :balance balance
     :capability capability
     :degradations (nreverse degradations))))

(defun emacsvox-aural--template-value (facts field action-id)
  "Return spoken FACTS value for template FIELD in ACTION-ID."
  (let* ((key (intern (format ":%s" field)))
         (missing (make-symbol "missing"))
         (value (if (plist-member facts key)
                    (plist-get facts key)
                  missing)))
    (when (eq value missing)
      (emacsvox-aural--transport-error
       "Action %S template field {%s} is missing from semantic facts"
       action-id field))
    (cond
     ((null value) "false")
     ((eq value t) "true")
     ((symbolp value)
      (replace-regexp-in-string "-" " " (symbol-name value)))
     ((listp value)
      (mapconcat
       (lambda (item)
         (emacsvox-aural--template-value
          (list key item) field action-id))
       value ", "))
     (t (format "%s" value)))))

(defun emacsvox-aural--render-text-template (action facts)
  "Render the safe semantic text template from ACTION using FACTS."
  (let ((template (emacsvox-aural-action-text-template action))
        (position 0)
        parts)
    (while (string-match "{\\([^{}]+\\)}" template position)
      (push (substring template position (match-beginning 0)) parts)
      (push
       (emacsvox-aural--template-value
        facts
        (intern (match-string 1 template))
        (emacsvox-aural-action-id action))
       parts)
      (setq position (match-end 0)))
    (push (substring template position) parts)
    (apply #'concat (nreverse parts))))

(defun emacsvox-aural--compile-volume (volume identity)
  "Freeze unsupported VOLUME handling for presentation IDENTITY.

The current queue protocol has no portable per-action or per-content volume
operation.  Return an explicit capability record, or reject the presentation
according to `emacsvox-aural-unsupported-volume-policy'."
  (when volume
    (when (eq emacsvox-aural-unsupported-volume-policy 'reject)
      (emacsvox-aural--transport-error
       "Volume %S requested for %S, but this transport cannot apply volume"
       volume identity))
    (list
     :requested volume
     :capability 'unsupported
     :degradation
     (append
      identity
      (list
       :property 'volume
       :requested volume
       :capability 'unsupported
       :policy 'degrade
       :reason 'unsupported-volume)))))

(defun emacsvox-aural--compile-concrete-action
    (action facts pack palette cue-target)
  "Compile ACTION with FACTS through PACK and PALETTE for CUE-TARGET."
  (let* ((identity (list :action (emacsvox-aural-action-id action)))
         (volume
          (emacsvox-aural--compile-volume
           (emacsvox-aural-action-volume action) identity)))
    (pcase (emacsvox-aural-action-kind action)
    ('cue
     (pcase-let*
         ((`(,resource ,sample-id ,resolved-cue)
           (emacsvox-aural--resolve-cue
            (emacsvox-aural-action-cue action) pack))
          (spatialization
           (emacsvox-aural-resource-spatialization
            resource pack t))
          (space
           (emacsvox-aural--compile-space
            (emacsvox-aural-action-space action)
            'cue cue-target spatialization
            (list :action (emacsvox-aural-action-id action)))))
       (emacsvox-aural--make-concrete-action
        :id (emacsvox-aural-action-id action)
        :kind 'cue
        :cue resolved-cue
        :resource resource
        :sample-id sample-id
        :source (emacsvox-aural-action-source action)
        :anchor (emacsvox-aural-action-anchor action)
        :requested-space
        (copy-tree (emacsvox-aural-action-space action))
        :balance (plist-get space :balance)
        :spatial-capability (plist-get space :capability)
        :spatial-degradations (plist-get space :degradations)
        :requested-volume (plist-get volume :requested)
        :volume-capability (plist-get volume :capability)
        :volume-degradation (plist-get volume :degradation))))
    ('speech
     (let* ((voice
             (emacsvox-aural-compile-voice-style
              (emacsvox-aural-action-voice action)
              palette
              (mapcar
               (lambda (property)
                 (cons property (emacsvox-aural-action-source action)))
               (cons 'preset emacsvox-aural-voice-dimensions))))
            (voice-command
             (emacsvox-aural-compiled-voice-command voice))
            (space
             (emacsvox-aural--compile-space
              (emacsvox-aural-action-space action)
              'speech 'speech nil
              (list :action (emacsvox-aural-action-id action)))))
       (unless (eq voice-command 'inaudible)
         (emacsvox-aural--make-concrete-action
          :id (emacsvox-aural-action-id action)
          :kind 'speech
          :text
          (if (emacsvox-aural-action-text-template action)
              (emacsvox-aural--render-text-template action facts)
            (emacsvox-aural-action-text action))
          :voice-command voice-command
          :voice-request
          (copy-tree (emacsvox-aural-compiled-voice-request voice))
          :voice-style
          (copy-tree (emacsvox-aural-compiled-voice-style voice))
          :voice-provenance
          (copy-tree (emacsvox-aural-compiled-voice-provenance voice))
          :voice-capability
          (copy-tree (emacsvox-aural-compiled-voice-capability voice))
          :voice-degradations
          (copy-tree (emacsvox-aural-compiled-voice-degradations voice))
          :source (emacsvox-aural-action-source action)
          :anchor (emacsvox-aural-action-anchor action)
          :requested-space
          (copy-tree (emacsvox-aural-action-space action))
          :balance (plist-get space :balance)
          :spatial-capability (plist-get space :capability)
          :spatial-degradations (plist-get space :degradations)
          :requested-volume (plist-get volume :requested)
          :volume-capability (plist-get volume :capability)
          :volume-degradation (plist-get volume :degradation)))))
    ('pause
     (emacsvox-aural--make-concrete-action
      :id (emacsvox-aural-action-id action)
      :kind 'pause
      :duration (emacsvox-aural-action-duration action)
      :source (emacsvox-aural-action-source action)
      :anchor (emacsvox-aural-action-anchor action))))))

(defun emacsvox-aural--compile-concrete-actions
    (actions facts pack palette cue-target)
  "Compile ACTIONS with FACTS through PACK and PALETTE for CUE-TARGET."
  (delq
   nil
   (mapcar
    (lambda (action)
      (emacsvox-aural--compile-concrete-action
       action facts pack palette cue-target))
    actions)))

(defun emacsvox-aural--action-degradations (source concrete)
  "Return backend degradation records from SOURCE and CONCRETE actions."
  (let (degradations)
    (dolist (action source)
      (let ((compiled
             (cl-find
              (emacsvox-aural-action-id action)
              concrete
              :key #'emacsvox-aural-concrete-action-id
              :test #'eq)))
        (when compiled
          (setq
           degradations
           (append
            (when-let* ((volume
                         (emacsvox-aural-concrete-action-volume-degradation
                          compiled)))
              (list (copy-tree volume)))
            (reverse
             (emacsvox-aural-concrete-action-voice-degradations compiled))
            (reverse
             (emacsvox-aural-concrete-action-spatial-degradations compiled))
            degradations)))
        (when
            (and
             compiled
             (eq (emacsvox-aural-action-kind action) 'cue)
             (not
              (eq
               (emacsvox-aural-action-cue action)
               (emacsvox-aural-concrete-action-cue compiled))))
          (push
           (list
            :action (emacsvox-aural-action-id action)
            :requested (emacsvox-aural-action-cue action)
            :fallback (emacsvox-aural-concrete-action-cue compiled))
           degradations))))
    (nreverse degradations)))

(defun emacsvox-aural--frozen-rule-provenance (plan facts context)
  "Return data-only matching-rule provenance for resolved PLAN."
  (let* ((input (emacsvox-aural-normalize-input facts context))
         (rules (emacsvox-aural-current-rules context))
         (aliases (emacsvox-aural-input-semantic-aliases input)))
    (mapcar
     (lambda (id)
       (let* ((rule
               (cl-find
                id rules :key #'emacsvox-aural-rule-id :test #'eq))
              (rule-aliases
               (and
                rule
                (emacsvox-aural-selector-semantic-aliases
                 (emacsvox-aural-rule-selector rule)))))
         (list
          :id id
          :origin
          (and rule (emacsvox-aural-rule-origin rule))
          :source
          (and rule (emacsvox-aural-rule-source rule))
          :score
          (cdr (assq id (emacsvox-aural-render-plan-rule-scores plan)))
          :semantic-matches
          (copy-tree
           (cdr
            (assq
             id
             (emacsvox-aural-render-plan-semantic-matches plan))))
          :semantic-aliases
          (mapcar
           (lambda (alias)
             (emacsvox-aural-semantic-alias-diagnostic
              (emacsvox-aural-semantic-alias-id alias)))
           (append aliases rule-aliases)))))
     (emacsvox-aural-render-plan-matched-rules plan))))

(defun emacsvox-aural-compile-plan
    (plan facts context &optional cue-target)
  "Compile render PLAN for FACTS and CONTEXT to a concrete plan.

CUE-TARGET defaults to `queued-cue'; immediate local cue callers use
`local-cue' so capabilities are frozen before playback."
  (let* ((context (copy-tree context))
         (context
          (if (plist-member context :icons-enabled)
              context
            (plist-put
             context :icons-enabled
             (emacsvox-aural-icons-enabled-p context))))
         (facts (emacsvox-aural-canonical-facts facts))
         (pack (emacsvox-aural--resource-pack))
         (palette (emacsvox-aural--voice-palette))
         (cue-target (or cue-target 'queued-cue))
         (style (emacsvox-aural-render-plan-content plan))
         (voice
          (emacsvox-aural-compile-voice-style
           (emacsvox-aural-content-style-voice style)
           palette
           (emacsvox-aural-content-style-voice-provenance style)))
         (voice-command
          (emacsvox-aural-compiled-voice-command voice))
         (speak
          (and
           (emacsvox-aural-content-style-speak style)
           (not (eq voice-command 'inaudible))))
         (degradations nil)
         (content-volume
          (emacsvox-aural--compile-volume
           (emacsvox-aural-content-style-volume style)
           '(:content t)))
         (content-space
          (emacsvox-aural--compile-space
           (emacsvox-aural-content-style-space style)
           'speech 'speech nil '(:content t)))
         (before
          (emacsvox-aural--compile-concrete-actions
           (emacsvox-aural-render-plan-before plan)
           facts pack palette cue-target))
         (after
          (emacsvox-aural--compile-concrete-actions
           (emacsvox-aural-render-plan-after plan)
           facts pack palette cue-target)))
    (when-let* ((volume (plist-get content-volume :degradation)))
      (push volume degradations))
    (setq
     degradations
     (append
      (emacsvox-aural--action-degradations
       (emacsvox-aural-render-plan-before plan) before)
      (plist-get content-space :degradations)
      (copy-tree (emacsvox-aural-compiled-voice-degradations voice))
      (nreverse degradations)
      (emacsvox-aural--action-degradations
       (emacsvox-aural-render-plan-after plan) after)))
    (emacsvox-aural--make-concrete-plan
     :before before
     :content
     (emacsvox-aural--make-concrete-content
      :text (plist-get facts :content)
      :speak speak
      :voice-command (unless (eq voice-command 'inaudible) voice-command)
      :voice-request
      (copy-tree (emacsvox-aural-compiled-voice-request voice))
      :voice-style
      (copy-tree (emacsvox-aural-compiled-voice-style voice))
      :voice-provenance
      (copy-tree (emacsvox-aural-compiled-voice-provenance voice))
      :voice-capability
      (copy-tree (emacsvox-aural-compiled-voice-capability voice))
      :voice-degradations
      (copy-tree (emacsvox-aural-compiled-voice-degradations voice))
      :requested-space
      (copy-tree (emacsvox-aural-content-style-space style))
      :balance (plist-get content-space :balance)
      :spatial-capability (plist-get content-space :capability)
      :spatial-degradations (plist-get content-space :degradations)
      :requested-volume (plist-get content-volume :requested)
      :volume-capability (plist-get content-volume :capability)
      :volume-degradation (plist-get content-volume :degradation)
      :provenance
      (copy-tree
       (emacsvox-aural-content-style-provenance style)))
     :after after
     :facts (copy-tree facts)
     :context (copy-tree context)
     :resource-pack pack
     :voice-palette palette
     :source-plan plan
     :degradations degradations
     :scheme emacsvox-aural-active-scheme
     :configuration-generation
     emacsvox-aural-configuration-generation
     :rule-provenance
     (emacsvox-aural--frozen-rule-provenance plan facts context))))

(defun emacsvox-aural-face-names (value)
  "Return ordered named faces explicitly represented by face VALUE.

Anonymous attribute plists contribute only named faces reached through
`:inherit'.  Duplicate names retain their first, strongest position."
  (cl-labels
      ((collect
        (item)
        (cond
         ((and (symbolp item) (facep item)) (list item))
         ((and (stringp item) (facep item))
          (when-let* ((name (intern-soft item)))
            (list name)))
         ((and (proper-list-p item) (keywordp (car item)))
          (collect (plist-get item :inherit)))
         ((proper-list-p item)
          (apply #'append (mapcar #'collect item)))
         (t nil))))
    (delete-dups (collect value))))

(defun emacsvox-aural--source-face-records
    (value source property &optional overlay)
  "Return provenance records for named faces in VALUE.

SOURCE is `overlay' or `text-property', PROPERTY is `face' or
`font-lock-face', and OVERLAY supplies source range and priority metadata."
  (mapcar
   (lambda (face)
     (append
      (list
       :face face
       :source source
       :property property)
      (when overlay
        (list
         :priority (copy-tree (overlay-get overlay 'priority))
         :overlay-start (overlay-start overlay)
         :overlay-end (overlay-end overlay)))))
   (emacsvox-aural-face-names value)))

(defun emacsvox-aural--normalize-source-face-records (records)
  "Deduplicate ordered source-face RECORDS and assign stable order."
  (let (seen result)
    (dolist (record records)
      (let ((face (plist-get record :face)))
        (unless (memq face seen)
          (push face seen)
          (setq
           result
           (append
            result
            (list
             (plist-put
              (copy-tree record) :order (length result))))))))
    result))

(defun emacsvox-aural-capture-source-faces (&optional position buffer)
  "Capture ordered named source faces at POSITION in BUFFER.

Overlay faces are ordered by decreasing Emacs overlay priority, followed by
the explicit `face' and `font-lock-face' text properties.  Within each source,
`face' precedes `font-lock-face'.  Returned provenance is data-only and never
retains an overlay object.  POSITION and BUFFER default to point and the
current buffer."
  (with-current-buffer (or buffer (current-buffer))
    (let ((position (or position (point)))
          records)
      (dolist (overlay (overlays-at position t))
        (dolist (property '(face font-lock-face))
          (when-let* ((value (overlay-get overlay property)))
            (setq
             records
             (append
              records
              (emacsvox-aural--source-face-records
               value 'overlay property overlay))))))
      (dolist (property '(face font-lock-face))
        (when-let* ((value (get-text-property position property)))
          (setq
           records
           (append
            records
            (emacsvox-aural--source-face-records
             value 'text-property property)))))
      (emacsvox-aural--normalize-source-face-records records))))

(defun emacsvox-aural-source-substring (start end &optional buffer)
  "Copy START through END from BUFFER with source-face snapshots.

This is the source-boundary counterpart of `buffer-substring'.  It preserves
ordinary text properties and annotates the returned string with ordered,
data-only overlay and text-property face provenance without changing BUFFER."
  (with-current-buffer (or buffer (current-buffer))
    (let ((text (buffer-substring start end))
          (position start))
      (while (< position end)
        (let* ((next (next-char-property-change position end))
               (snapshot
                (emacsvox-aural-capture-source-faces position)))
          (when snapshot
            (add-text-properties
             (- position start) (- next start)
             (list
              emacsvox-aural-source-faces-property
              (copy-tree snapshot))
             text))
          (setq position next)))
      text)))

(defun emacsvox-aural--string-face-snapshot (text position)
  "Return authoritative source-face records for TEXT at POSITION."
  (or
   (copy-tree
    (get-text-property
     position emacsvox-aural-source-faces-property text))
   (let (records)
     (dolist (property '(face font-lock-face))
       (when-let* ((value (get-text-property position property text)))
         (setq
          records
          (append
           records
           (emacsvox-aural--source-face-records
            value 'text-property property)))))
     (emacsvox-aural--normalize-source-face-records records))))

(defun emacsvox-aural--source-face-names (snapshot)
  "Return ordered names from source-face SNAPSHOT."
  (mapcar
   (lambda (record) (plist-get record :face))
   snapshot))

(defun emacsvox-aural--source-face-summary (snapshot)
  "Return the strongest source identifier represented by SNAPSHOT."
  (when-let* ((record (car snapshot))
              (source (plist-get record :source))
              (property (plist-get record :property)))
    (if (eq source 'overlay)
        (intern (format "overlay-%s" property))
      property)))

(defun emacsvox-aural--string-face-value (text position)
  "Return face value and source property for TEXT at POSITION."
  (let ((face (get-text-property position 'face text)))
    (if face
        (cons face 'face)
      (when-let* ((font-lock-face
                   (get-text-property position 'font-lock-face text)))
        (cons font-lock-face 'font-lock-face)))))

(defun emacsvox-aural--string-style (text position &optional face-snapshot)
  "Return legacy personality or FACE-SNAPSHOT-derived style in TEXT."
  (or
   (get-text-property position 'personality text)
   (when (fboundp 'tts-get-voice-for-face)
     (or
      (cl-loop
       for face in (emacsvox-aural--source-face-names face-snapshot)
       thereis (tts-get-voice-for-face face))
      (tts-get-voice-for-face
       (car (emacsvox-aural--string-face-value text position)))))))

(defun emacsvox-aural--next-non-nil-property
    (text position property limit)
  "Return next position after POSITION where PROPERTY becomes non-nil.

Return LIMIT when PROPERTY has no later non-nil value in TEXT."
  (let ((next position)
        found)
    (while (and (< next limit) (not found))
      (setq
       next
       (next-single-property-change next property text limit))
      (when
          (and
           (< next limit)
           (get-text-property next property text))
        (setq found next)))
    (or found limit)))

(defun emacsvox-aural--object-end (text position)
  "Return the inferred aural-object boundary in TEXT after POSITION."
  (let* ((limit (length text))
         (explicit
          (get-text-property
           position emacsvox-aural-object-property text))
         (icon-boundary
          (emacsvox-aural--next-non-nil-property
           text position 'auditory-icon limit))
         (object-boundary
          (next-single-property-change
           position emacsvox-aural-object-property text limit)))
    (if explicit
        (min object-boundary icon-boundary)
      (min
       object-boundary
       icon-boundary
       (next-single-property-change
        position emacsvox-aural-facts-property text limit)
       (next-single-property-change
        position emacsvox-aural-module-property text limit)
       (next-single-property-change
        position emacsvox-aural-occasion-property text limit)))))

(defun emacsvox-aural--run-end (text position limit)
  "Return the next formatting-run boundary in TEXT before LIMIT."
  (let (
        boundaries)
    (dolist
        (property
         (list
          'personality 'face 'font-lock-face
          emacsvox-aural-source-faces-property
          'pause
          emacsvox-aural-facts-property
          emacsvox-aural-module-property
          emacsvox-aural-occasion-property
          emacsvox-aural-object-property))
      (push
       (next-single-property-change position property text limit)
       boundaries))
    (apply #'min boundaries)))

(defun emacsvox-aural--merge-facts (base local)
  "Return semantic facts formed from BASE and run-local LOCAL."
  (unless
      (or
       (null local)
       (and
        (listp local)
        (proper-list-p local)
        (zerop (% (length local) 2))))
    (emacsvox-aural--transport-error
     "Run-local semantic facts must be a plist: %S" local))
  (emacsvox-aural-merge-facts base local))

(defun emacsvox-aural--legacy-input (icon facts context)
  "Return concrete source FACTS and CONTEXT for legacy ICON."
  (let* ((semantic
          (alist-get icon emacsvox-aural-legacy-icon-semantics))
         (facts (copy-tree facts))
         (events
          (append
           (when-let* ((event (plist-get facts :event))) (list event))
           (copy-sequence (plist-get facts :events))
           (when semantic (list semantic)))))
    (list
     (if events
         (plist-put facts :events (delete-dups events))
       facts)
     (plist-put (copy-tree context) :legacy-cue icon))))

(defun emacsvox-aural--capture-source-run
    (text position end base-facts base-context object-icon)
  "Capture one source formatting run from POSITION to END in TEXT."
  (let* ((explicit
          (get-text-property position 'personality text))
         (face-snapshot
          (emacsvox-aural--string-face-snapshot text position))
         (legacy-faces
          (emacsvox-aural--source-face-names face-snapshot))
         (run-context (copy-tree base-context))
         (legacy
          (and
           (if (plist-member run-context :voice-lock-enabled)
               (plist-get run-context :voice-lock-enabled)
             (emacsvox-aural-voice-lock-enabled-p))
           (emacsvox-aural--string-style
            text position face-snapshot)))
         (local-facts
          (get-text-property
           position emacsvox-aural-facts-property text))
         (run-facts
          (emacsvox-aural--merge-facts base-facts local-facts))
         (module
          (get-text-property
           position emacsvox-aural-module-property text))
         (occasion
          (get-text-property
           position emacsvox-aural-occasion-property text)))
    (when module
      (setq run-context (plist-put run-context :module module)))
    (when occasion
      (setq run-context (plist-put run-context :occasion occasion)))
    (when legacy-faces
      (setq
       run-context
       (plist-put
        run-context :legacy-faces (copy-sequence legacy-faces)))
      (setq
       run-context
       (plist-put
        run-context :legacy-face-source
        (emacsvox-aural--source-face-summary face-snapshot)))
      (setq
       run-context
       (plist-put
        run-context :legacy-face-provenance
        (copy-tree face-snapshot))))
    (when legacy
      (setq
       run-context
       (plist-put run-context :legacy-personality legacy))
      (setq
       run-context
       (plist-put
        run-context :legacy-source
        (if explicit 'personality-property 'face))))
    (when object-icon
      (pcase-let
          ((`(,legacy-facts ,legacy-context)
            (emacsvox-aural--legacy-input
             object-icon run-facts run-context)))
        (setq
         run-facts legacy-facts
         run-context legacy-context)))
    (emacsvox-aural--make-source-run
     :start position
     :end end
     :facts run-facts
     :context run-context
     :icon object-icon)))

(defun emacsvox-aural--resolve-source-run (run anchor)
  "Resolve source RUN's presentation for ANCHOR."
  (let ((facts (emacsvox-aural-source-run-facts run))
        (context (emacsvox-aural-source-run-context run))
        (icon (emacsvox-aural-source-run-icon run)))
    (if icon
        (emacsvox-aural-resolve-legacy-icon
         icon context facts anchor)
      (emacsvox-aural-resolve-active facts context anchor))))

(defun emacsvox-aural--resolve-source-object (runs anchor)
  "Resolve RUNS as one aural object for ANCHOR."
  (let* ((icon (emacsvox-aural-source-run-icon (car runs)))
         (inputs
          (mapcar
           (lambda (run)
             (cons
              (emacsvox-aural-source-run-facts run)
              (emacsvox-aural-source-run-context run)))
           runs)))
    (if icon
        (emacsvox-aural-resolve-legacy-icon-inputs
         icon inputs anchor)
      (emacsvox-aural-resolve-active-inputs inputs anchor))))

(defun emacsvox-aural--actions-not-in
    (actions other id-function)
  "Return ACTIONS whose IDs do not occur in OTHER using ID-FUNCTION."
  (let ((other-ids (mapcar id-function other)))
    (cl-remove-if
     (lambda (action)
       (memq (funcall id-function action) other-ids))
     actions)))

(defun emacsvox-aural--merge-rule-provenance (&rest plans)
  "Return matching rules, scores, and semantic matches from render PLANS."
  (let (rules scores semantic-matches)
    (dolist (plan plans)
      (when plan
        (dolist (rule (emacsvox-aural-render-plan-matched-rules plan))
          (unless (memq rule rules)
            (setq rules (append rules (list rule)))))
        (dolist (score (emacsvox-aural-render-plan-rule-scores plan))
          (setq scores (assq-delete-all (car score) scores))
          (setq scores (append scores (list score))))
        (dolist
            (match (emacsvox-aural-render-plan-semantic-matches plan))
          (setq semantic-matches (assq-delete-all (car match) semantic-matches))
          (setq semantic-matches (append semantic-matches (list match))))))
    (list
     :rules rules
     :scores scores
     :semantic-matches semantic-matches)))

(defun emacsvox-aural--combine-run-plan
    (object-plan run-plan transition-plan previous-transition next-transition
     first-p last-p)
  "Return one render plan combining object, run, and transition lifetimes."
  (let* ((transition-before
          (emacsvox-aural--actions-not-in
           (emacsvox-aural-render-plan-before transition-plan)
           (and
            previous-transition
            (emacsvox-aural-render-plan-before previous-transition))
           #'emacsvox-aural-action-id))
         (transition-after
          (emacsvox-aural--actions-not-in
           (emacsvox-aural-render-plan-after transition-plan)
           (and
            next-transition
            (emacsvox-aural-render-plan-after next-transition))
           #'emacsvox-aural-action-id))
         (provenance
          (emacsvox-aural--merge-rule-provenance
           object-plan run-plan transition-plan)))
    (emacsvox-aural--make-render-plan
     :before
     (append
      (and first-p (emacsvox-aural-render-plan-before object-plan))
      transition-before
      (emacsvox-aural-render-plan-before run-plan))
     :content (emacsvox-aural-render-plan-content run-plan)
     :after
     (append
      (emacsvox-aural-render-plan-after run-plan)
      transition-after
      (and last-p (emacsvox-aural-render-plan-after object-plan)))
     :matched-rules (plist-get provenance :rules)
     :rule-scores (plist-get provenance :scores)
     :semantic-matches (plist-get provenance :semantic-matches))))

(defun emacsvox-aural--combine-concrete-run
    (source-plan object-plan run-plan transition-plan previous-transition
     next-transition object-id run-id first-p last-p)
  "Return one concrete run nested in OBJECT-ID."
  (let ((transition-before
         (emacsvox-aural--actions-not-in
          (emacsvox-aural-concrete-plan-before transition-plan)
          (and
           previous-transition
           (emacsvox-aural-concrete-plan-before previous-transition))
          #'emacsvox-aural-concrete-action-id))
        (transition-after
         (emacsvox-aural--actions-not-in
          (emacsvox-aural-concrete-plan-after transition-plan)
          (and
           next-transition
           (emacsvox-aural-concrete-plan-after next-transition))
          #'emacsvox-aural-concrete-action-id)))
    (emacsvox-aural--make-concrete-plan
     :before
     (append
      (and first-p (emacsvox-aural-concrete-plan-before object-plan))
      transition-before
      (emacsvox-aural-concrete-plan-before run-plan))
     :content (emacsvox-aural-concrete-plan-content run-plan)
     :after
     (append
      (emacsvox-aural-concrete-plan-after run-plan)
      transition-after
      (and last-p (emacsvox-aural-concrete-plan-after object-plan)))
     :facts (copy-tree (emacsvox-aural-concrete-plan-facts run-plan))
     :context (copy-tree (emacsvox-aural-concrete-plan-context run-plan))
     :resource-pack (emacsvox-aural-concrete-plan-resource-pack run-plan)
     :voice-palette (emacsvox-aural-concrete-plan-voice-palette run-plan)
     :scheme (emacsvox-aural-concrete-plan-scheme run-plan)
     :configuration-generation
     (emacsvox-aural-concrete-plan-configuration-generation run-plan)
     :rule-provenance
     (mapcar
      (lambda (id)
        (cl-find
         id
         (append
          (emacsvox-aural-concrete-plan-rule-provenance object-plan)
          (emacsvox-aural-concrete-plan-rule-provenance transition-plan)
          (emacsvox-aural-concrete-plan-rule-provenance run-plan))
         :key (lambda (entry) (plist-get entry :id))
         :test #'eq))
      (emacsvox-aural-render-plan-matched-rules source-plan))
     :source-plan source-plan
     :degradations
     (append
      (and first-p (emacsvox-aural-concrete-plan-degradations object-plan))
      (emacsvox-aural-concrete-plan-degradations transition-plan)
      (emacsvox-aural-concrete-plan-degradations run-plan))
     :object-id object-id
     :run-id run-id
     :object-start-p first-p
     :object-end-p last-p)))

(defun emacsvox-aural--prepare-object
    (text start end base-facts base-context object-id)
  "Attach frozen nested plans to one object from START to END in TEXT."
  (let ((object-icon (get-text-property start 'auditory-icon text))
        (position start)
        runs)
    (while (< position end)
      (let ((run-end (emacsvox-aural--run-end text position end)))
        (push
         (emacsvox-aural--capture-source-run
          text position run-end base-facts base-context object-icon)
         runs)
        (setq position run-end)))
    (setq runs (nreverse runs))
    (let* ((object-render
            (emacsvox-aural--resolve-source-object runs 'object))
           (object-concrete
            (emacsvox-aural-compile-plan
             object-render
             (emacsvox-aural-source-run-facts (car runs))
             (emacsvox-aural-source-run-context (car runs))))
           (run-renders
            (mapcar
             (lambda (run)
               (emacsvox-aural--resolve-source-run run 'run))
             runs))
           (transition-renders
            (mapcar
             (lambda (run)
               (emacsvox-aural--resolve-source-run run 'transition))
             runs))
           (run-concretes
            (cl-mapcar
             (lambda (render run)
               (emacsvox-aural-compile-plan
                render
                (emacsvox-aural-source-run-facts run)
                (emacsvox-aural-source-run-context run)))
             run-renders runs))
           (transition-concretes
            (cl-mapcar
             (lambda (render run)
               (emacsvox-aural-compile-plan
                render
                (emacsvox-aural-source-run-facts run)
                (emacsvox-aural-source-run-context run)))
             transition-renders runs))
           (count (length runs)))
      (cl-loop
       for run in runs
       for run-render in run-renders
       for transition-render in transition-renders
       for run-concrete in run-concretes
       for transition-concrete in transition-concretes
       for index from 0
       for previous-render = nil then transition-render
       for previous-concrete = nil then transition-concrete
       for next-render = (nth (1+ index) transition-renders)
       for next-concrete = (nth (1+ index) transition-concretes)
       for first-p = (zerop index)
       for last-p = (= index (1- count))
       do
       (let* ((source-plan
               (emacsvox-aural--combine-run-plan
                object-render run-render transition-render
                previous-render next-render first-p last-p))
              (concrete
               (emacsvox-aural--combine-concrete-run
                source-plan object-concrete run-concrete transition-concrete
                previous-concrete next-concrete object-id index
                first-p last-p)))
         (add-text-properties
          (emacsvox-aural-source-run-start run)
          (emacsvox-aural-source-run-end run)
          (list emacsvox-aural-concrete-plan-property concrete)
          text))))))

(defun emacsvox-aural-prepare-text (text &optional facts context)
  "Freeze object and formatting-run decisions in TEXT.

FACTS default to `emacsvox-aural-submission-facts'.  CONTEXT defaults to the
dynamically captured submission context or a fresh source-buffer snapshot.
The returned string retains legacy properties and adds concrete nested plans.
One inferred object spans the submission until semantic context or a queued
icon changes.  `emacsvox-aural-object-property' can group complex runs
explicitly."
  (unless (stringp text)
    (emacsvox-aural--transport-error
     "Aural text preparation requires a string: %S" text))
  (let* ((prepared (copy-sequence text))
         (base-facts (or facts emacsvox-aural-submission-facts))
         (base-context
          (copy-tree
           (or
            context
            emacsvox-aural-submission-context
            (emacsvox-aural-capture-context))))
         (position 0)
         (length (length prepared))
         (sequence 0))
    (while (< position length)
      (let* ((end (emacsvox-aural--object-end prepared position))
             (explicit
              (get-text-property
               position emacsvox-aural-object-property prepared))
             (object-id
              (or explicit
                  (list 'inferred-object (cl-incf sequence)))))
        (emacsvox-aural--prepare-object
         prepared position end base-facts base-context object-id)
        (setq position end)))
    prepared))

(defun emacsvox-aural-prepared-text-p (text)
  "Return non-nil when every character of nonempty TEXT has a concrete plan."
  (and
   (stringp text)
   (> (length text) 0)
   (not
    (text-property-any
     0 (length text) emacsvox-aural-concrete-plan-property nil text))))

(defun emacsvox-aural-concrete-plan-at (position &optional object)
  "Return the concrete aural plan at POSITION in OBJECT."
  (get-text-property
   position emacsvox-aural-concrete-plan-property object))

(defun emacsvox-aural-queue-concrete-action (action &optional context)
  "Queue concrete ACTION under frozen CONTEXT without resolving again."
  (pcase (emacsvox-aural-concrete-action-kind action)
    ('cue
     (when (emacsvox-aural-icons-enabled-p context)
       (let ((resource
              (emacsvox-aural-concrete-action-resource action))
             (balance
              (emacsvox-aural-concrete-action-balance action)))
         (if
             (and
              (numberp balance)
              (not (zerop balance))
              (functionp emacsvox-aural-queued-cue-balance-function))
             (funcall
              emacsvox-aural-queued-cue-balance-function
              resource balance)
           (emacsvox-queue-resource resource)))))
    ('pause
     (tts--protocol-silence
      (emacsvox-aural-concrete-action-duration action)))
    ('speech
     (let ((command
            (emacsvox-aural-concrete-action-voice-command action))
           (balance
            (emacsvox-aural-concrete-action-balance action)))
       (when
           (and
            (numberp balance)
            (not (zerop balance))
            (functionp emacsvox-aural-speech-balance-function))
         (funcall emacsvox-aural-speech-balance-function balance))
       (when (and command (not (string-empty-p command)))
         (tts--protocol-queue-code command))
       (tts--protocol-queue-text
        (emacsvox-aural-concrete-action-text action))
       (when command
         (tts--protocol-queue-code (tts-voice-reset-code)))
       (when
           (and
            (numberp balance)
            (not (zerop balance))
            (functionp emacsvox-aural-speech-balance-function))
         (funcall emacsvox-aural-speech-balance-function 0.0))))))

(defun emacsvox-aural--queue-concrete-content (content payload)
  "Queue concrete CONTENT using final text PAYLOAD."
  (when
      (and
       (emacsvox-aural-concrete-content-speak content)
       payload
       (not (string-empty-p payload)))
    (tts--protocol-queue-code (tts-voice-reset-code))
    (let ((balance
           (emacsvox-aural-concrete-content-balance content)))
      (when
          (and
           (numberp balance)
           (not (zerop balance))
           (functionp emacsvox-aural-speech-balance-function))
        (funcall emacsvox-aural-speech-balance-function balance))
      (when-let* ((command
                   (emacsvox-aural-concrete-content-voice-command content)))
        (unless (string-empty-p command)
          (tts--protocol-queue-code command)))
      (tts--protocol-queue-text payload)
      (when (emacsvox-aural-concrete-content-voice-command content)
        (tts--protocol-queue-code (tts-voice-reset-code)))
      (when
          (and
           (numberp balance)
           (not (zerop balance))
           (functionp emacsvox-aural-speech-balance-function))
        (funcall emacsvox-aural-speech-balance-function 0.0)))))

(defun emacsvox-aural--finish-concrete-plan
    (plan text text-supplied-p)
  "Record and finish concrete PLAN after queueing.

TEXT is the final payload when TEXT-SUPPLIED-P is non-nil."
  (let ((emacsvox-aural--history-respect-icon-policy t))
    (if text-supplied-p
        (emacsvox-aural-record-presentation plan text)
      (emacsvox-aural-record-presentation plan)))
  (when
      (or
       (null (emacsvox-aural-concrete-plan-object-id plan))
       (emacsvox-aural-concrete-plan-object-end-p plan))
    (run-hook-with-args 'emacsvox-aural-plan-presented-hook plan))
  plan)

(defun emacsvox-aural--concrete-content-transport-key (content)
  "Return the speech-transport settings that distinguish CONTENT."
  (list
   (emacsvox-aural-concrete-content-speak content)
   (emacsvox-aural-concrete-content-voice-command content)
   (emacsvox-aural-concrete-content-balance content)))

(defun emacsvox-aural--coalescible-concrete-runs-p (left right)
  "Return non-nil when adjacent concrete runs LEFT and RIGHT can be joined.

Each run is a list of PLAN, final text, and an optional leading pause."
  (pcase-let
      ((`(,left-plan ,left-text ,_) left)
       (`(,right-plan ,right-text ,right-pause) right))
    (let ((left-content
           (emacsvox-aural-concrete-plan-content left-plan))
          (right-content
           (emacsvox-aural-concrete-plan-content right-plan)))
      (and
       (not right-pause)
       (stringp left-text)
       (not (string-empty-p left-text))
       (stringp right-text)
       (not (string-empty-p right-text))
       (emacsvox-aural-concrete-content-speak left-content)
       (emacsvox-aural-concrete-content-speak right-content)
       (emacsvox-aural-concrete-plan-object-id left-plan)
       (equal
        (emacsvox-aural-concrete-plan-object-id left-plan)
        (emacsvox-aural-concrete-plan-object-id right-plan))
       (null (emacsvox-aural-concrete-plan-after left-plan))
       (null (emacsvox-aural-concrete-plan-before right-plan))
       (equal
        (emacsvox-aural--concrete-content-transport-key left-content)
        (emacsvox-aural--concrete-content-transport-key right-content))))))

(defun emacsvox-aural--queue-concrete-run-group (runs)
  "Queue forward-ordered, transport-equivalent concrete RUNS together."
  (let* ((first (car runs))
         (last (car (last runs)))
         (first-plan (car first))
         (last-plan (car last))
         (payload
          (mapconcat
           (lambda (run) (nth 1 run))
           runs
           "")))
    (when-let* ((pause (nth 2 first)))
      (tts--protocol-silence pause))
    (dolist (action (emacsvox-aural-concrete-plan-before first-plan))
      (emacsvox-aural-queue-concrete-action
       action (emacsvox-aural-concrete-plan-context first-plan)))
    (emacsvox-aural--queue-concrete-content
     (emacsvox-aural-concrete-plan-content first-plan)
     payload)
    (dolist (action (emacsvox-aural-concrete-plan-after last-plan))
      (emacsvox-aural-queue-concrete-action
       action (emacsvox-aural-concrete-plan-context last-plan)))
    (dolist (run runs)
      (emacsvox-aural--finish-concrete-plan
       (car run) (nth 1 run) t))
    last-plan))

(defun emacsvox-aural-queue-concrete-runs (runs)
  "Queue adjacent concrete RUNS without artificial speech boundaries.

Each entry in RUNS is a list of PLAN, final text, and an optional leading
pause.  Adjacent runs are coalesced only within one aural object when their
effective speech transport settings match and no action or pause separates
them."
  (let (group previous)
    (cl-labels
        ((flush
          ()
          (when group
            (setq group (nreverse group))
            (if (cdr group)
                (emacsvox-aural--queue-concrete-run-group group)
              (pcase-let ((`(,plan ,text ,pause) (car group)))
                (when pause
                  (tts--protocol-silence pause))
                (emacsvox-aural-queue-concrete-plan plan text)))
            (setq group nil
                  previous nil))))
      (dolist (run runs)
        (unless
            (and
             previous
             (emacsvox-aural--coalescible-concrete-runs-p previous run))
          (flush))
        (push run group)
        (setq previous run))
      (flush))))

(cl-defun emacsvox-aural-queue-concrete-plan
    (plan &optional (text nil text-supplied-p))
  "Queue concrete PLAN in strict before, content, and after order.

When TEXT is supplied it replaces the plan's source text after normal TTS
cleanup, without rerunning semantic or contextual resolution."
  (let ((context (emacsvox-aural-concrete-plan-context plan)))
    (dolist (action (emacsvox-aural-concrete-plan-before plan))
      (emacsvox-aural-queue-concrete-action action context)))
  (let* ((content (emacsvox-aural-concrete-plan-content plan))
         (payload
         (if text-supplied-p
              text
            (emacsvox-aural-concrete-content-text content))))
    (emacsvox-aural--queue-concrete-content content payload)
    (dolist (action (emacsvox-aural-concrete-plan-after plan))
      (emacsvox-aural-queue-concrete-action
       action (emacsvox-aural-concrete-plan-context plan)))
    (emacsvox-aural--finish-concrete-plan
     plan payload text-supplied-p)))

(defun emacsvox-aural--standalone-cue (plan)
  "Return PLAN's one standalone cue action, or nil."
  (let* ((actions
          (append
           (emacsvox-aural-concrete-plan-before plan)
           (emacsvox-aural-concrete-plan-after plan)))
         (content (emacsvox-aural-concrete-plan-content plan)))
    (when
        (and
         (= (length actions) 1)
         (eq
          (emacsvox-aural-concrete-action-kind (car actions))
          'cue)
         (not (emacsvox-aural-concrete-content-text content)))
      (car actions))))

(defun emacsvox-aural--ensure-speaker ()
  "Ensure the TTS process needed for ordered plans is available."
  (unless
      (and
       (boundp 'tts-speaker-process)
       (process-live-p tts-speaker-process))
    (tts-initialize)))

(defun emacsvox-aural-present-legacy-icon (icon &optional context)
  "Present legacy ICON through concrete transport.
Resolve it using CONTEXT or the dynamically captured submission context."
  (pcase-let*
      ((context
        (or
         context
         (emacsvox-aural-capture-context
          nil
          (or emacsvox-aural-submission-occasion 'notification))))
       (`(,facts ,context)
        (emacsvox-aural--legacy-input
         icon emacsvox-aural-submission-facts context))
       (render
        (emacsvox-aural-resolve-legacy-icon icon context facts))
       (local-cue-p
        (let ((actions
               (append
                (emacsvox-aural-render-plan-before render)
                (emacsvox-aural-render-plan-after render))))
          (and
           (= (length actions) 1)
           (eq (emacsvox-aural-action-kind (car actions)) 'cue)
           (not (plist-get facts :content)))))
       (plan
        (emacsvox-aural-compile-plan
         render facts context
         (if local-cue-p 'local-cue 'queued-cue)))
       (cue (emacsvox-aural--standalone-cue plan))
       (icons-enabled
        (emacsvox-aural-icons-enabled-p
         (emacsvox-aural-concrete-plan-context plan))))
    (cond
     ((and cue icons-enabled)
      (let ((balance
             (emacsvox-aural-concrete-action-balance cue)))
        (if (and (numberp balance) (not (zerop balance)))
            (emacsvox-sounds-play-concrete-cue
             (emacsvox-aural-concrete-action-resource cue)
             (emacsvox-aural-concrete-action-sample-id cue)
             balance)
          (emacsvox-sounds-play-concrete-cue
           (emacsvox-aural-concrete-action-resource cue)
           (emacsvox-aural-concrete-action-sample-id cue))))
      (emacsvox-aural-record-presentation plan)
      (when emacsvox-aural-plan-presented-hook
        (emacsvox-aural--ensure-speaker)
        (run-hook-with-args
         'emacsvox-aural-plan-presented-hook plan)
        (tts--protocol-dispatch)))
     (cue nil)
     ((or
       (emacsvox-aural-concrete-plan-before plan)
       (emacsvox-aural-concrete-plan-after plan))
      (emacsvox-aural--ensure-speaker)
      (emacsvox-aural-queue-concrete-plan plan)
      (tts--protocol-dispatch)))
    plan))

(defun emacsvox-aural-queue-legacy-icon (icon &optional context)
  "Resolve and queue legacy ICON concretely without dispatching.
Use CONTEXT when supplied, otherwise capture the submission context."
  (pcase-let*
      ((context
        (or
         context
         emacsvox-aural-submission-context
         (emacsvox-aural-capture-context nil 'continuous)))
       (`(,facts ,context)
        (emacsvox-aural--legacy-input
         icon emacsvox-aural-submission-facts context))
       (plan
        (emacsvox-aural-compile-plan
         (emacsvox-aural-resolve-legacy-icon icon context facts)
         facts context)))
    (emacsvox-aural-queue-concrete-plan plan)))

(defun emacsvox-aural-present (facts &optional context)
  "Resolve, compile, queue, and dispatch semantic FACTS in CONTEXT."
  (let* ((context
          (or
           context
           (emacsvox-aural-capture-context nil 'notification)))
         (plan
          (emacsvox-aural-compile-plan
           (emacsvox-aural-resolve-active facts context)
           facts context)))
    (emacsvox-aural--ensure-speaker)
    (emacsvox-aural-queue-concrete-plan plan)
    (tts--protocol-dispatch)
    plan))

(provide 'emacsvox-aural-transport)
;;; emacsvox-aural-transport.el ends here
