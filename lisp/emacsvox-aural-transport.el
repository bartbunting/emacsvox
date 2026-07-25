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
(require 'emacsvox-aural-schemes)

(declare-function emacsvox-sounds-play-concrete-cue
                  "emacsvox-sounds" (resource sample-id))
(declare-function emacsvox-queue-resource
                  "emacsvox-sounds" (resource))
(declare-function tts--protocol-dispatch "tts-speak" ())
(declare-function tts--protocol-queue-code "tts-speak" (code))
(declare-function tts--protocol-queue-text "tts-speak" (text))
(declare-function tts--protocol-silence "tts-speak" (duration &optional force))
(declare-function tts-get-voice-command "tts-speak" (voice))
(declare-function tts-get-voice-for-face "tts-speak" (face))
(declare-function tts-initialize "tts-speak" ())
(declare-function tts-voice-reset-code "tts-speak" ())
(declare-function voice-from-acss "voice-setup" (style))

(defvar emacsvox-sounds-current-pack)
(defvar emacsvox-use-icons)
(defvar tts-speaker-process)
(defvar voice-lock-mode)

(define-error
  'emacsvox-aural-transport-error
  "Cannot compile or queue an Emacsvox aural presentation")

(cl-defstruct
    (emacsvox-aural-concrete-action
     (:constructor emacsvox-aural--make-concrete-action))
  "One backend-ready ordered action."
  id kind text cue resource sample-id duration voice-command source)

(cl-defstruct
    (emacsvox-aural-concrete-content
     (:constructor emacsvox-aural--make-concrete-content))
  "Backend-ready styling and speaking state for object content."
  text speak voice-command provenance)

(cl-defstruct
    (emacsvox-aural-concrete-plan
     (:constructor emacsvox-aural--make-concrete-plan))
  "A backend-ready ordered plan frozen at its source boundary."
  before content after facts context resource-pack voice-palette
  source-plan degradations)

(defvar emacsvox-aural-submission-context nil
  "Dynamically bound source context for the current speech submission.")

(defvar emacsvox-aural-submission-facts nil
  "Dynamically bound semantic facts for the current speech submission.")

(defvar emacsvox-aural-submission-module nil
  "Dynamically bound module for the current speech submission.")

(defvar emacsvox-aural-submission-occasion nil
  "Dynamically bound occasion for the current speech submission.")

(defvar emacsvox-aural-plan-presented-hook nil
  "Abnormal hook run after queueing one concrete aural plan.

Each function receives the `emacsvox-aural-concrete-plan' that was queued.
Standalone local cues run this hook after playback has been requested.")

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

(defun emacsvox-aural--transport-error (format-string &rest arguments)
  "Signal a transport error described by FORMAT-STRING and ARGUMENTS."
  (signal
   'emacsvox-aural-transport-error
   (list (apply #'format format-string arguments))))

(defun emacsvox-aural-capture-context (&optional module occasion)
  "Capture immutable source context for MODULE and OCCASION."
  (copy-tree
   (emacsvox-aural-current-context
    (or module emacsvox-aural-submission-module)
    (or occasion emacsvox-aural-submission-occasion 'continuous))))

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
   (emacsvox-aural-effective-scheme-provider 'voice-palette)
   'acss-default))

(defun emacsvox-aural--file-digest (file)
  "Return a SHA-256 digest of the literal contents of FILE."
  (unless (file-readable-p file)
    (emacsvox-aural--transport-error
     "Concrete cue resource is not readable: %s" file))
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally file)
    (secure-hash 'sha256 (current-buffer))))

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

(defun emacsvox-aural--acss-p (value)
  "Return non-nil when VALUE is an ACSS structure."
  (eq (type-of value) 'acss))

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

(defun emacsvox-aural--one-voice-command (voice palette)
  "Compile one VOICE through PALETTE and the selected TTS adapter."
  (let ((resolved (emacsvox-aural--resolve-voice-name voice palette)))
    (when (emacsvox-aural--acss-p resolved)
      (unless (fboundp 'voice-from-acss)
        (emacsvox-aural--transport-error
         "ACSS voice support has not loaded"))
      (setq resolved (voice-from-acss resolved)))
    (unless (symbolp resolved)
      (emacsvox-aural--transport-error
       "Voice did not resolve to a personality: %S" voice))
    (unless (fboundp 'tts-get-voice-command)
      (emacsvox-aural--transport-error
       "The selected TTS adapter has no voice compiler"))
    (tts-get-voice-command resolved)))

(defun emacsvox-aural-compile-voice (voice &optional palette)
  "Compile VOICE through PALETTE to a concrete TTS command.

Return `inaudible' when VOICE suppresses content, nil for the default voice,
or a command string understood by the selected speech server."
  (let ((palette (or palette (emacsvox-aural--voice-palette))))
    (cond
     ((null voice) nil)
     ((or
       (eq voice 'inaudible)
       (and (proper-list-p voice) (memq 'inaudible voice)))
      'inaudible)
     ((and (listp voice) (proper-list-p voice))
      (mapconcat
       (lambda (entry)
         (emacsvox-aural--one-voice-command entry palette))
       voice
       " "))
     (t (emacsvox-aural--one-voice-command voice palette)))))

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

(defun emacsvox-aural--compile-concrete-action (action pack palette)
  "Compile ACTION through PACK and PALETTE."
  (pcase (emacsvox-aural-action-kind action)
    ('cue
     (pcase-let*
         ((`(,resource ,sample-id ,resolved-cue)
           (emacsvox-aural--resolve-cue
            (emacsvox-aural-action-cue action) pack)))
       (emacsvox-aural--make-concrete-action
        :id (emacsvox-aural-action-id action)
        :kind 'cue
        :cue resolved-cue
        :resource resource
        :sample-id sample-id
        :source (emacsvox-aural-action-source action))))
    ('speech
     (let ((voice-command
            (emacsvox-aural-compile-voice
             (emacsvox-aural-action-voice action) palette)))
       (unless (eq voice-command 'inaudible)
         (emacsvox-aural--make-concrete-action
          :id (emacsvox-aural-action-id action)
          :kind 'speech
          :text (emacsvox-aural-action-text action)
          :voice-command voice-command
          :source (emacsvox-aural-action-source action)))))
    ('pause
     (emacsvox-aural--make-concrete-action
      :id (emacsvox-aural-action-id action)
      :kind 'pause
      :duration (emacsvox-aural-action-duration action)
      :source (emacsvox-aural-action-source action)))))

(defun emacsvox-aural--compile-concrete-actions (actions pack palette)
  "Compile ACTIONS through PACK and PALETTE."
  (delq
   nil
   (mapcar
    (lambda (action)
      (emacsvox-aural--compile-concrete-action action pack palette))
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
        (when
            (or
             (emacsvox-aural-action-volume action)
             (emacsvox-aural-action-space action))
          (push
           (list
            :action (emacsvox-aural-action-id action)
            :reason 'backend-property-deferred)
           degradations))
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

(defun emacsvox-aural-compile-plan (plan facts context)
  "Compile render PLAN for FACTS and CONTEXT to a concrete plan."
  (let* ((pack (emacsvox-aural--resource-pack))
         (palette (emacsvox-aural--voice-palette))
         (style (emacsvox-aural-render-plan-content plan))
         (voice-command
          (emacsvox-aural-compile-voice
           (emacsvox-aural-content-style-voice style) palette))
         (speak
          (and
           (emacsvox-aural-content-style-speak style)
           (not (eq voice-command 'inaudible))))
         (degradations nil)
         (before
          (emacsvox-aural--compile-concrete-actions
           (emacsvox-aural-render-plan-before plan)
           pack palette))
         (after
          (emacsvox-aural--compile-concrete-actions
           (emacsvox-aural-render-plan-after plan)
           pack palette)))
    (when (or
           (emacsvox-aural-content-style-volume style)
           (emacsvox-aural-content-style-space style))
      (push
       (list :content t :reason 'backend-property-deferred)
       degradations))
    (setq
     degradations
     (append
      (emacsvox-aural--action-degradations
       (emacsvox-aural-render-plan-before plan) before)
      (emacsvox-aural--action-degradations
       (emacsvox-aural-render-plan-after plan) after)
      degradations))
    (emacsvox-aural--make-concrete-plan
     :before before
     :content
     (emacsvox-aural--make-concrete-content
      :text (plist-get facts :content)
      :speak speak
      :voice-command (unless (eq voice-command 'inaudible) voice-command)
      :provenance
      (copy-tree
       (emacsvox-aural-content-style-provenance style)))
     :after after
     :facts (copy-tree facts)
     :context (copy-tree context)
     :resource-pack pack
     :voice-palette palette
     :source-plan plan
     :degradations (nreverse degradations))))

(defun emacsvox-aural--string-style (text position)
  "Return legacy personality or face-derived style in TEXT at POSITION."
  (or
   (get-text-property position 'personality text)
   (when (fboundp 'tts-get-voice-for-face)
     (tts-get-voice-for-face
      (or
       (get-text-property position 'face text)
       (get-text-property position 'font-lock-face text))))))

(defun emacsvox-aural--run-end (text position)
  "Return the next aural input boundary in TEXT after POSITION."
  (let ((limit (length text))
        boundaries)
    (dolist
        (property
         (list
          'personality 'face 'font-lock-face 'auditory-icon
          'pause
          emacsvox-aural-facts-property
          emacsvox-aural-module-property
          emacsvox-aural-occasion-property))
      (push
       (next-single-property-change position property text limit)
       boundaries))
    (apply #'min boundaries)))

(defun emacsvox-aural--merge-facts (base local)
  "Return semantic facts formed from BASE and run-local LOCAL."
  (unless (or (null local) (listp local))
    (emacsvox-aural--transport-error
     "Run-local semantic facts must be a plist: %S" local))
  (append (copy-tree local) (copy-tree base)))

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

(defun emacsvox-aural-prepare-text (text &optional facts context)
  "Freeze aural decisions for every formatted run in TEXT.

FACTS default to `emacsvox-aural-submission-facts'.  CONTEXT defaults to the
dynamically captured submission context or a fresh source-buffer snapshot.
The returned string retains legacy properties and adds concrete plans."
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
         (length (length prepared)))
    (while (< position length)
      (let* ((end (emacsvox-aural--run-end prepared position))
             (icon (get-text-property position 'auditory-icon prepared))
             (explicit
              (get-text-property position 'personality prepared))
             (legacy
              (and
               (or
                (not (boundp 'voice-lock-mode))
                voice-lock-mode)
               (emacsvox-aural--string-style prepared position)))
             (local-facts
              (get-text-property
               position emacsvox-aural-facts-property prepared))
             (run-facts
              (emacsvox-aural--merge-facts base-facts local-facts))
             (run-context (copy-tree base-context))
             (module
              (get-text-property
               position emacsvox-aural-module-property prepared))
             (occasion
              (get-text-property
               position emacsvox-aural-occasion-property prepared)))
        (when module
          (setq run-context (plist-put run-context :module module)))
        (when occasion
          (setq run-context (plist-put run-context :occasion occasion)))
        (when legacy
          (setq
           run-context
           (plist-put run-context :legacy-personality legacy))
          (setq
           run-context
           (plist-put
            run-context :legacy-source
            (if explicit 'personality-property 'face))))
        (when icon
          (pcase-let
              ((`(,legacy-facts ,legacy-context)
                (emacsvox-aural--legacy-input
                 icon run-facts run-context)))
            (setq
             run-facts legacy-facts
             run-context legacy-context)))
        (let* ((plan
                (if icon
                    (emacsvox-aural-resolve-legacy-icon
                     icon run-context run-facts)
                  (emacsvox-aural-resolve-active
                   run-facts run-context)))
               (concrete
                (emacsvox-aural-compile-plan
                 plan run-facts run-context)))
          (add-text-properties
           position end
           (list emacsvox-aural-concrete-plan-property concrete)
           prepared))
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

(defun emacsvox-aural-queue-concrete-action (action)
  "Queue concrete ACTION without semantic or contextual resolution."
  (pcase (emacsvox-aural-concrete-action-kind action)
    ('cue
     (when
         (or
          (not (boundp 'emacsvox-use-icons))
          emacsvox-use-icons)
       (emacsvox-queue-resource
        (emacsvox-aural-concrete-action-resource action))))
    ('pause
     (tts--protocol-silence
      (emacsvox-aural-concrete-action-duration action)))
    ('speech
     (let ((command
            (emacsvox-aural-concrete-action-voice-command action)))
       (when (and command (not (string-empty-p command)))
         (tts--protocol-queue-code command))
       (tts--protocol-queue-text
        (emacsvox-aural-concrete-action-text action))
       (when command
         (tts--protocol-queue-code (tts-voice-reset-code)))))))

(cl-defun emacsvox-aural-queue-concrete-plan
    (plan &optional (text nil text-supplied-p))
  "Queue concrete PLAN in strict before, content, and after order.

When TEXT is supplied it replaces the plan's source text after normal TTS
cleanup, without rerunning semantic or contextual resolution."
  (dolist (action (emacsvox-aural-concrete-plan-before plan))
    (emacsvox-aural-queue-concrete-action action))
  (let* ((content (emacsvox-aural-concrete-plan-content plan))
         (payload
          (if text-supplied-p
              text
            (emacsvox-aural-concrete-content-text content))))
    (when
        (and
         (emacsvox-aural-concrete-content-speak content)
         payload
         (not (string-empty-p payload)))
      (tts--protocol-queue-code (tts-voice-reset-code))
      (when-let* ((command
                   (emacsvox-aural-concrete-content-voice-command content)))
        (unless (string-empty-p command)
          (tts--protocol-queue-code command)))
      (tts--protocol-queue-text payload)
      (when (emacsvox-aural-concrete-content-voice-command content)
        (tts--protocol-queue-code (tts-voice-reset-code)))))
  (dolist (action (emacsvox-aural-concrete-plan-after plan))
    (emacsvox-aural-queue-concrete-action action))
  (run-hook-with-args 'emacsvox-aural-plan-presented-hook plan)
  plan)

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
  "Present legacy ICON through contextual resolution and concrete transport."
  (pcase-let*
      ((context
        (or
         context
         (emacsvox-aural-capture-context nil 'notification)))
       (`(,facts ,context)
        (emacsvox-aural--legacy-input icon nil context))
       (plan
        (emacsvox-aural-compile-plan
         (emacsvox-aural-resolve-legacy-icon icon context facts)
         facts context))
       (cue (emacsvox-aural--standalone-cue plan)))
    (cond
     (cue
      (emacsvox-sounds-play-concrete-cue
       (emacsvox-aural-concrete-action-resource cue)
       (emacsvox-aural-concrete-action-sample-id cue))
      (when emacsvox-aural-plan-presented-hook
        (emacsvox-aural--ensure-speaker)
        (run-hook-with-args
         'emacsvox-aural-plan-presented-hook plan)
        (tts--protocol-dispatch)))
     ((or
       (emacsvox-aural-concrete-plan-before plan)
       (emacsvox-aural-concrete-plan-after plan))
      (emacsvox-aural--ensure-speaker)
      (emacsvox-aural-queue-concrete-plan plan)
      (tts--protocol-dispatch)))
    plan))

(defun emacsvox-aural-queue-legacy-icon (icon &optional context)
  "Resolve and queue legacy ICON concretely without dispatching."
  (pcase-let*
      ((context
        (or
         context
         emacsvox-aural-submission-context
         (emacsvox-aural-capture-context nil 'continuous)))
       (`(,facts ,context)
        (emacsvox-aural--legacy-input icon nil context))
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
