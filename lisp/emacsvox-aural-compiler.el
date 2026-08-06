;;; emacsvox-aural-compiler.el --- Concrete aural compiler -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Compile resolved render plans to frozen resources, voices, spatial values,
;; and backend-ready ordered actions.  This module performs no queueing or
;; speech-server process control.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'emacsvox-aural-concrete)
(require 'emacsvox-aural-providers)
(require 'emacsvox-aural-schemes)
(require 'emacsvox-aural-spatial)

(declare-function tts-get-voice-command "tts-speak" (voice))
(declare-function tts-voice-capabilities "tts-speak" ())
(declare-function tts-voice-family-id
                  "tts-speak" (family &optional capabilities))
(declare-function voice-from-acss "voice-setup" (style &optional logical-voice))
(declare-function
 emacsvox-aural-routing-static-family
 "emacsvox-aural-routing-profiles" (logical-voice requested-family
                                    &optional capabilities inventory))
(declare-function make-acss "voice-setup" (&rest slots))

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
  (let* ((palette (or palette (emacsvox-aural-effective-voice-palette)))
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

(defun emacsvox-aural--route-palette-voice-definition
    (logical-voice definition)
  "Apply standalone physical routing to portable style DEFINITION.

LOGICAL-VOICE remains the profile identity.  Only `:family' may change; the
portable palette object and every other dimension remain untouched."
  (if (and
       (emacsvox-aural-voice-style-p definition)
       (fboundp 'emacsvox-aural-routing-static-family))
      (let* ((copy (copy-tree definition))
             (requested (plist-get copy :family))
             (family
              (emacsvox-aural-routing-static-family
               logical-voice requested)))
        (plist-put copy :family family))
    definition))

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
    ;; Rate and post-synthesis values are transported independently of the
    ;; legacy inline ACSS command.  Preserve their composed portable state for
    ;; the structured adapter boundary without claiming legacy application.
    (dolist
        (dimension
         (append emacsvox-aural-voice-rate-dimensions
                 emacsvox-aural-post-synthesis-dimensions))
      (let ((key (emacsvox-aural--voice-dimension-key dimension)))
        (when (plist-member style key)
          (setq effective
                (plist-put effective key (plist-get style key))))))
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
  (let* ((palette (or palette (emacsvox-aural-effective-voice-palette)))
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
                    (emacsvox-aural--route-palette-voice-definition
                     voice palette-definition)
                    palette provenance)))
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

(defun emacsvox-aural--resolve-tone (name)
  "Return the registered concrete tone named NAME."
  (or
   (emacsvox-aural-tone name)
   (emacsvox-aural--transport-error
    "Unknown concrete tone: %S" name)))

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
      :anchor (emacsvox-aural-action-anchor action)))
    ('tone
     (let ((tone
            (emacsvox-aural--resolve-tone
             (emacsvox-aural-action-tone action))))
       (emacsvox-aural--make-concrete-action
        :id (emacsvox-aural-action-id action)
        :kind 'tone
        :tone (emacsvox-aural-tone-id tone)
        :pitch (emacsvox-aural-tone-pitch tone)
        :duration (emacsvox-aural-tone-duration tone)
        :force (emacsvox-aural-tone-force tone)
        :source (emacsvox-aural-action-source action)
        :anchor (emacsvox-aural-action-anchor action)))))))

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
         (pack (emacsvox-aural-effective-resource-pack))
         (palette (emacsvox-aural-effective-voice-palette))
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

(provide 'emacsvox-aural-compiler)
;;; emacsvox-aural-compiler.el ends here
