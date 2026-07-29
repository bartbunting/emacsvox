;;; emacsvox-aural-tools.el --- Contextual aural remapping -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Contextual voice and earcon remapping plus override reset commands.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'emacsvox-aural-schemes)
(require 'emacsvox-aural-transport)
(require 'emacsvox-aural-description)
(require 'emacsvox-aural-preview)
(require 'emacsvox-aural-inspection)
(require 'emacsvox-aural-semantics)
(require 'emacsvox-aural-explanation)

(declare-function emacsvox-aural-editor--open-prefilled-rule
                  "emacsvox-aural-editor" (scope rule source-buffer))
(declare-function emacsvox-aural-editor--open-without-rule
                  "emacsvox-aural-editor" (scope rule-id source-buffer))
(declare-function voice-setup-get-voice-for-face "voice-setup" (face))

(defun emacsvox-aural-tools--remap-source-input (&optional record)
  "Return presentation input for optional frozen RECORD or the current source.

For RECORD, use its exact frozen voice and semantic context.  Associate it
with the current inspection source only when the buffer name still matches;
history deliberately does not retain source buffers.  Without RECORD, prefer
the latest exact presentation from the current source and fall back to
inspectable facts at point."
  (if record
      (progn
        (unless (emacsvox-aural-presentation-record-p record)
          (user-error "Not an aural presentation record: %S" record))
        (let* ((concrete
                (emacsvox-aural-presentation-record-plan record))
               (source
                (emacsvox-aural-inspection-source-buffer))
               (source
                (and
                 source
                 (equal
                  (buffer-name source)
                  (emacsvox-aural-presentation-record-source-buffer-name
                   record))
                 source)))
          (list
           :source source
           :facts (copy-tree (emacsvox-aural-concrete-plan-facts concrete))
           :context
           (copy-tree (emacsvox-aural-concrete-plan-context concrete))
           :render (emacsvox-aural-concrete-plan-source-plan concrete)
           :concrete concrete)))
    (let ((source (emacsvox-aural-inspection-source-buffer)))
      (unless source
        (user-error "No live source buffer is available"))
      (with-current-buffer source
        (if-let* ((record (emacsvox-aural-last-presentation source)))
            (let* ((concrete
                    (emacsvox-aural-presentation-record-plan record))
                   (render
                    (emacsvox-aural-concrete-plan-source-plan concrete)))
              (list
               :source source
               :facts
               (copy-tree (emacsvox-aural-concrete-plan-facts concrete))
               :context
               (copy-tree (emacsvox-aural-concrete-plan-context concrete))
               :render render
               :concrete concrete))
          (let* ((facts (emacsvox-aural-facts-at-point))
                 (_
                  (unless facts
                    (user-error
                     "No presentation is recorded here; move away and back, then retry")))
                 (context (emacsvox-aural-context-at-point))
                 (explanation (emacsvox-aural-explain facts context)))
            (list
             :source source
             :facts (copy-tree facts)
             :context (copy-tree context)
             :render
             (emacsvox-aural-explanation-render-plan explanation)
             :concrete
             (emacsvox-aural-explanation-concrete-plan explanation))))))))

(defun emacsvox-aural-tools--voice-remap-selector (facts context)
  "Derive a stable object selector from FACTS and CONTEXT.

Transient events and the current occasion are deliberately omitted.  Object
states remain specific, while MODULE (or MODE when there is no module) keeps
the override local to its provider.  A visual face is used only when semantic
facts do not distinguish the object."
  (let ((role (plist-get facts :role))
        (states (copy-sequence (plist-get facts :states)))
        selector
        attributes)
    (when role
      (setq selector (plist-put selector :role role)))
    (dolist (semantic (emacsvox-aural-semantics))
      (when (eq (emacsvox-aural-semantic-kind semantic) 'attribute)
        (let* ((id (emacsvox-aural-semantic-id semantic))
               (key (intern (format ":%s" id))))
          (when (plist-member facts key)
            (push id attributes)
            (setq
             selector
             (plist-put selector key (copy-tree (plist-get facts key))))))))
    (when states
      (setq selector (plist-put selector :states states)))
    (if-let* ((module (plist-get context :module)))
        (setq selector (plist-put selector :module module))
      (when-let* ((mode (plist-get context :mode)))
        (setq selector (plist-put selector :mode mode))))
    (when
        (and
         (null role)
         (null attributes)
         (null states)
         (plist-get context :legacy-faces))
      (setq
       selector
       (plist-put
        selector :legacy-face (car (plist-get context :legacy-faces)))))
    (unless selector
      (user-error
       "This presentation has no stable semantic, mode, or face identity"))
    selector))

(defun emacsvox-aural-tools--voice-remap-current-voice (render context)
  "Return the requested voice represented by RENDER and CONTEXT."
  (or
   (emacsvox-aural-content-style-voice
    (emacsvox-aural-render-plan-content render))
   (cl-loop
    for face in (plist-get context :legacy-faces)
    thereis
    (and
     (fboundp 'voice-setup-get-voice-for-face)
     (voice-setup-get-voice-for-face face)))))

(defun emacsvox-aural-tools--voice-remap-default-name (voice)
  "Return the active palette name corresponding to VOICE."
  (let* ((palette
          (or
           (emacsvox-aural-effective-scheme-provider 'voice-palette)
           'acss-default))
         (entries (emacsvox-aural-effective-voice-entries palette)))
    (cond
     ((null voice) "default")
     ((assq voice entries) (symbol-name voice))
     ((cl-find voice entries :key #'cdr :test #'equal)
      (symbol-name
       (car (cl-find voice entries :key #'cdr :test #'equal))))
     ((and
       (symbolp voice)
       (string-prefix-p "voice-" (symbol-name voice))
       (assq
        (intern (string-remove-prefix "voice-" (symbol-name voice)))
        entries))
      (string-remove-prefix "voice-" (symbol-name voice)))
     (t "default"))))

(defun emacsvox-aural-tools--voice-remap-candidates ()
  "Return named voices available from the active palette."
  (let ((palette
         (or
          (emacsvox-aural-effective-scheme-provider 'voice-palette)
          'acss-default)))
    (sort
     (delete-dups
      (append
       '("default" "inaudible")
       (mapcar
        (lambda (entry) (symbol-name (car entry)))
        (emacsvox-aural-effective-voice-entries palette))))
     #'string-lessp)))

(defun emacsvox-aural-tools--voice-remap-scope
    (source-available &optional kind)
  "Read a remap scope for KIND.

KIND defaults to voice.  Offer buffer-local persistence only when
SOURCE-AVAILABLE is non-nil."
  (pcase
      (completing-read
       (format "Keep this %s change: " (or kind "voice"))
       (append
        '("always (personal)" "this Emacs session")
        (when source-available '("this buffer")))
       nil 'must-match nil nil "always (personal)")
    ("always (personal)" 'personal)
    ("this Emacs session" 'session)
    ("this buffer" 'buffer)))

(defun emacsvox-aural-tools--remap-rule-id (scope selector suffix)
  "Return a stable rule identifier for SCOPE, SELECTOR, and SUFFIX."
  (let ((parts
         (delq
          nil
          (list
           scope 'remap
           (plist-get selector :module)
           (plist-get selector :mode)
           (plist-get selector :role)))))
    (setq parts (append parts (plist-get selector :states)))
    (dolist (event (plist-get selector :events))
      (setq parts (append parts (list 'event event))))
    (when-let* ((occasion (plist-get selector :occasion)))
      (setq parts (append parts (list 'occasion occasion))))
    (dolist (semantic (emacsvox-aural-semantics))
      (when (eq (emacsvox-aural-semantic-kind semantic) 'attribute)
        (let* ((id (emacsvox-aural-semantic-id semantic))
               (key (intern (format ":%s" id))))
          (when (plist-member selector key)
            (setq parts
                  (append parts (list id (plist-get selector key))))))))
    (setq
     parts
     (append
      parts
      (list (plist-get selector :legacy-face))
      suffix))
    (intern
     (mapconcat
      (lambda (part)
        (string-trim
         (replace-regexp-in-string
          "[^[:alnum:]-]+" "-"
          (downcase (format "%s" part)))
         "-" "-"))
      (delq nil parts)
      "-"))))

(defun emacsvox-aural-tools--voice-remap-rule-id (scope selector)
  "Return a stable voice-remap identifier for SCOPE and SELECTOR."
  (emacsvox-aural-tools--remap-rule-id scope selector '(voice)))

(defun emacsvox-aural-remap-voice-at-point (&optional record)
  "Prepare a scoped named-voice override for RECORD or presentation at point.

When RECORD is non-nil, use that frozen presentation from recent feedback.
Otherwise the latest presentation heard in the source buffer supplies exact
facts and context.  The generated rule ignores transient events and
occasions, but retains object kind, state, and provider identity.  It opens
unsaved in the advanced rule editor so the selector can be reviewed or
  refined before `s' saves it."
  (interactive)
  (let* ((input
          (if record
              (emacsvox-aural-tools--remap-source-input record)
            (emacsvox-aural-tools--remap-source-input)))
         (facts (plist-get input :facts))
         (context (plist-get input :context))
         (render (plist-get input :render))
         (source (plist-get input :source))
         (selector
          (emacsvox-aural-tools--voice-remap-selector facts context))
         (compiled-selector
          (emacsvox-aural-rule-selector
           (emacsvox-aural-compile-rule
            (list
             :id 'point-voice-remap-preview
             :match selector
             :render '(:content (:voice default)))
            'user)))
         (description
          (emacsvox-aural-describe-selector compiled-selector))
         (current
          (emacsvox-aural-tools--voice-remap-current-voice render context))
         (default
          (emacsvox-aural-tools--voice-remap-default-name current))
         (answer
          (completing-read
           (format
            "Voice for %s (currently %s): "
            description
            (emacsvox-aural-humanize default))
           (emacsvox-aural-tools--voice-remap-candidates)
           nil 'must-match nil nil default))
         (voice
          (unless (or (string-empty-p answer) (string= answer "default"))
            (intern answer)))
         (scope (emacsvox-aural-tools--voice-remap-scope source))
         (rule
          (list
           :id (emacsvox-aural-tools--voice-remap-rule-id scope selector)
           :match selector
           :render (list :content (list :voice voice)))))
    (require 'emacsvox-aural-editor)
    (emacsvox-aural-editor--open-prefilled-rule scope rule source)
    (message
     "Prepared %s voice override for %s; review it and press s to save"
     scope description)))

(defun emacsvox-aural-tools--earcon-remap-selector (facts context)
  "Derive a precise earcon selector from FACTS and CONTEXT.

Retain the stable semantic identity used by voice remapping, plus events and
occasion because earcons commonly announce a particular transition rather
than every presentation of an object."
  (let ((selector
         (emacsvox-aural-tools--voice-remap-selector facts context)))
    (when-let* ((events (copy-sequence (plist-get facts :events))))
      (setq selector (plist-put selector :events events)))
    (when-let* ((occasion (plist-get context :occasion)))
      (setq selector (plist-put selector :occasion occasion)))
    selector))

(defun emacsvox-aural-tools--earcon-remap-candidates ()
  "Return registered non-prompt cue identifiers for completion."
  (let (cues)
    (maphash
     (lambda (id cue)
       (unless (eq (emacsvox-aural-cue-kind cue) 'prompt)
         (push (symbol-name id) cues)))
     emacsvox-aural-cue-registry)
    (sort cues #'string-lessp)))

(defun emacsvox-aural-tools--earcon-remap-choices (concrete)
  "Return labeled concrete earcon choices from CONCRETE."
  (let (choices)
    (dolist
        (phase-actions
         (list
          (cons 'before
                (emacsvox-aural-concrete-plan-before concrete))
          (cons 'after
                (emacsvox-aural-concrete-plan-after concrete))))
      (let ((phase (car phase-actions))
            (actions (cdr phase-actions)))
        (cl-loop
         for action in actions
         for index from 0
         when
         (eq (emacsvox-aural-concrete-action-kind action) 'cue)
         do
         (let* ((cue (emacsvox-aural-concrete-action-cue action))
                (id (emacsvox-aural-concrete-action-id action))
                (source (emacsvox-aural-concrete-action-source action))
                (label
                 (format
                  "%s position %d: %s; action %s; source %s"
                  (capitalize (symbol-name phase))
                  (1+ index)
                  (emacsvox-aural-humanize cue)
                  (emacsvox-aural-humanize id)
                  (if source
                      (emacsvox-aural-humanize source)
                    "unknown"))))
           (push
            (cons
             label
             (list
              :phase phase
              :action action
              :index index
              :count (length actions)))
            choices)))))
    (nreverse choices)))

(defun emacsvox-aural-tools--earcon-remap-choice (concrete)
  "Read and return one concrete earcon choice from CONCRETE."
  (let ((choices (emacsvox-aural-tools--earcon-remap-choices concrete)))
    (unless choices
      (user-error "This presentation contains no earcon to remap"))
    (if (= (length choices) 1)
        (cdar choices)
      (let ((answer
             (completing-read
              "Earcon to remap: "
              (mapcar #'car choices)
              nil 'must-match)))
        (cdr (assoc answer choices))))))

(defun emacsvox-aural-tools--validate-earcon-remap-choice
    (choice concrete)
  "Return CHOICE when it identifies one removable action in CONCRETE."
  (let* ((phase (plist-get choice :phase))
         (selected (plist-get choice :action))
         (id (emacsvox-aural-concrete-action-id selected))
         (anchor (emacsvox-aural-concrete-action-anchor selected))
         (actions
          (if (eq phase 'before)
              (emacsvox-aural-concrete-plan-before concrete)
            (emacsvox-aural-concrete-plan-after concrete)))
         (matches
          (cl-remove-if-not
           (lambda (action)
             (and
              (eq (emacsvox-aural-concrete-action-id action) id)
              (eq
               (emacsvox-aural-concrete-action-anchor action)
               anchor)))
           actions)))
    (when (> (length matches) 1)
      (user-error
       "Action ID %s is duplicated in this %s phase and anchor; use the advanced rule editor"
       id phase))
    choice))

(defun emacsvox-aural-tools--earcon-action-data (action cue)
  "Return declarative replacement data for concrete ACTION using CUE."
  (let ((anchor (emacsvox-aural-concrete-action-anchor action))
        (volume
         (emacsvox-aural-concrete-action-requested-volume action))
        (space
         (emacsvox-aural-concrete-action-requested-space action))
        (data
         (list
          :id (emacsvox-aural-concrete-action-id action)
          :kind 'cue
          :cue cue)))
    (unless (memq anchor emacsvox-aural-action-anchors)
      (user-error
       "The selected earcon has no precise lifecycle anchor: %S"
       anchor))
    (setq data (plist-put data :anchor anchor))
    (when (numberp volume)
      (setq data (plist-put data :volume volume)))
    (when space
      (setq data (plist-put data :space (copy-tree space))))
    data))

(defun emacsvox-aural-tools--preview-replacement-earcon
    (data facts context)
  "Audition replacement earcon DATA using FACTS and CONTEXT."
  (let* ((anchor (plist-get data :anchor))
         (action
          (emacsvox-aural--compile-action
           data 'earcon-remap-preview 'before 0 anchor))
         (render
          (emacsvox-aural--make-render-plan
           :before (list action)
           :content
           (emacsvox-aural--make-content-style :speak nil)))
         (concrete
          (emacsvox-aural-compile-plan
           render facts context 'local-cue))
         (cue (car (emacsvox-aural-concrete-plan-before concrete))))
    (emacsvox-aural-preview-play-cues (list cue))
    cue))

(defun emacsvox-aural-tools--earcon-remap-insertion (choice)
  "Return the least-disruptive insertion operation for earcon CHOICE."
  (let ((phase (plist-get choice :phase))
        (index (plist-get choice :index))
        (count (plist-get choice :count)))
    (cond
     ((zerop index) :prepend)
     ((= index (1- count)) :append)
     ((eq phase 'before) :prepend)
     (t :append))))

(defun emacsvox-aural-remap-earcon-at-point (&optional record)
  "Prepare a scoped override for one earcon in RECORD or at point.

Audition the exact selected earcon before asking whether to replace, suppress,
or restore it.  Replacement also auditions the newly resolved cue.  The
generated change opens unsaved in the advanced editor for review."
  (interactive)
  (let* ((input
          (if record
              (emacsvox-aural-tools--remap-source-input record)
            (emacsvox-aural-tools--remap-source-input)))
         (facts (plist-get input :facts))
         (context (plist-get input :context))
         (concrete (plist-get input :concrete))
         (source (plist-get input :source))
         (selector
          (emacsvox-aural-tools--earcon-remap-selector facts context))
         (compiled-selector
          (emacsvox-aural-rule-selector
           (emacsvox-aural-compile-rule
            (list
             :id 'point-earcon-remap-preview
             :match selector
             :render '(:content (:voice default)))
            'user)))
         (description
          (emacsvox-aural-describe-selector compiled-selector))
         (choice
          (emacsvox-aural-tools--validate-earcon-remap-choice
           (emacsvox-aural-tools--earcon-remap-choice concrete)
           concrete))
         (phase (plist-get choice :phase))
         (action (plist-get choice :action))
         (action-id (emacsvox-aural-concrete-action-id action))
         (current-cue (emacsvox-aural-concrete-action-cue action)))
    (emacsvox-aural-preview-play-cues (list action))
    (let* ((operation
            (pcase
                (completing-read
                 (format
                  "Change %s earcon for %s: "
                  (emacsvox-aural-humanize current-cue)
                  description)
                 '("replace it" "suppress it" "restore inherited behavior")
                 nil 'must-match nil nil "replace it")
              ("replace it" 'replace)
              ("suppress it" 'suppress)
              ("restore inherited behavior" 'restore)))
           (scope
            (emacsvox-aural-tools--voice-remap-scope source "earcon"))
           (rule-id
            (emacsvox-aural-tools--remap-rule-id
             scope selector (list 'earcon phase action-id))))
      (require 'emacsvox-aural-editor)
      (if (eq operation 'restore)
          (progn
            (emacsvox-aural-editor--open-without-rule
             scope rule-id source)
            (message
             "Prepared removal of %s earcon override; press s to restore inherited behavior"
             scope))
        (let* ((phase-key (intern (format ":%s" phase)))
               (anchor
                (emacsvox-aural-concrete-action-anchor action))
               (phase-data
                (list :anchor anchor :remove (list action-id))))
          (when (eq operation 'replace)
            (let* ((answer
                    (completing-read
                     (format
                      "Replacement for %s: "
                      (emacsvox-aural-humanize current-cue))
                     (emacsvox-aural-tools--earcon-remap-candidates)
                     nil 'must-match nil nil
                     (symbol-name current-cue)))
                   (replacement (intern answer))
                   (action-data
                    (emacsvox-aural-tools--earcon-action-data
                     action replacement)))
              (setq
               phase-data
               (plist-put
                phase-data
                (emacsvox-aural-tools--earcon-remap-insertion choice)
                (list action-data)))
              (emacsvox-aural-tools--preview-replacement-earcon
               action-data facts context)))
          (let ((rule
                 (list
                  :id rule-id
                  :match selector
                  :render (list phase-key phase-data))))
            (emacsvox-aural-editor--open-prefilled-rule
             scope rule source)
            (message
             "Prepared %s %s-earcon override for %s; review it and press s to save"
             scope phase description)))))))


(defun emacsvox-reset-aural-overrides (scope)
  "Remove aural override rules from SCOPE.

SCOPE is `personal', `session', or `buffer'."
  (interactive
   (list
    (intern
     (completing-read
      "Reset aural overrides in scope: "
      '("personal" "session" "buffer")
      nil 'must-match))))
  (unless (memq scope '(personal session buffer))
    (user-error "Unknown aural override scope: %S" scope))
  (when
      (or
       (not (called-interactively-p 'interactive))
       (yes-or-no-p (format "Remove all %s aural overrides? " scope)))
    (pcase scope
      ('personal
       (setq emacsvox-aural-user-rules nil)
       (emacsvox-aural-save-user-data))
      ('session (setq emacsvox-aural-session-rules nil))
      ('buffer (setq emacsvox-aural-buffer-rules nil)))
    (emacsvox-aural-configuration-changed 'override-reset)
    (when (called-interactively-p 'interactive)
      (message "Reset %s aural overrides" scope))
    t))


(defalias 'emacsvox-aural-reset-overrides
  #'emacsvox-reset-aural-overrides)

(provide 'emacsvox-aural-tools)
;;; emacsvox-aural-tools.el ends here
