;;; emacsvox-aural-planner.el --- Source aural planner -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Infer presentation objects and formatting runs from captured source text,
;; resolve semantic policy once at the source boundary, and attach frozen
;; concrete plans.  This module performs no queueing or backend process work.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'emacsvox-aural-concrete)
(require 'emacsvox-aural-compiler)
(require 'emacsvox-aural-schemes)
(require 'emacsvox-aural-source)

(declare-function tts-get-voice-for-face "tts-speak" (face))

(defun emacsvox-aural--string-face-value (text position)
  "Return face value and source property for TEXT at POSITION."
  (let ((face
         (emacsvox-aural-source-text-property
          position 'face text)))
    (if face
        (cons face 'face)
      (when-let* ((font-lock-face
                   (emacsvox-aural-source-text-property
                    position 'font-lock-face text)))
        (cons font-lock-face 'font-lock-face)))))

(defun emacsvox-aural--string-style (text position &optional face-snapshot)
  "Return legacy personality or FACE-SNAPSHOT-derived style in TEXT."
  (emacsvox-aural-filter-compatibility-voice
   (or
    (emacsvox-aural-source-text-property
     position 'personality text)
    (when (fboundp 'tts-get-voice-for-face)
      (or
       (cl-loop
        for face in (emacsvox-aural--source-face-names face-snapshot)
        thereis (tts-get-voice-for-face face))
       (tts-get-voice-for-face
        (car (emacsvox-aural--string-face-value text position))))))))

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
          (emacsvox-aural-source-text-property
           position 'personality text))
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

(defun emacsvox-aural--compatibility-action-id
    (icon index action-id)
  "Return a transaction-local ID for ICON action ACTION-ID at INDEX."
  (intern
   (format
    "compatibility-%s-%d-%s"
    icon index action-id)))

(defun emacsvox-aural--compatibility-render-plan
    (action facts context index)
  "Resolve compatibility ACTION under FACTS and CONTEXT at INDEX."
  (let ((phase (plist-get action :phase))
        (kind (plist-get action :kind))
        (icon (plist-get action :value)))
    (unless (and (memq phase '(before after))
                 (eq kind 'legacy-icon)
                 (symbolp icon))
      (emacsvox-aural--transport-error
       "Invalid source compatibility action: %S" action))
    (let* ((render
            (emacsvox-aural-resolve-legacy-icon-adapter
             icon context facts))
           (actions
            (mapcar
             (lambda (source-action)
               (let ((copy (copy-emacsvox-aural-action source-action)))
                 (setf
                  (emacsvox-aural-action-id copy)
                  (emacsvox-aural--compatibility-action-id
                   icon index
                   (emacsvox-aural-action-id source-action)))
                 copy))
             (append
              (emacsvox-aural-render-plan-before render)
              (emacsvox-aural-render-plan-after render)))))
      (emacsvox-aural--make-render-plan
       :before (and (eq phase 'before) actions)
       :content (emacsvox-aural--make-content-style :speak t)
       :after (and (eq phase 'after) actions)
       :matched-rules
       (copy-sequence (emacsvox-aural-render-plan-matched-rules render))
       :rule-scores
       (copy-tree (emacsvox-aural-render-plan-rule-scores render))
       :semantic-matches
       (copy-tree
        (emacsvox-aural-render-plan-semantic-matches render))))))

(defun emacsvox-aural--merge-object-compatibility
    (object-plan actions facts context)
  "Merge ordered compatibility ACTIONS into semantic OBJECT-PLAN."
  (if (null actions)
      object-plan
    (let* ((compatibility-plans
            (cl-loop
             for action in actions
             for index from 1
             collect
             (emacsvox-aural--compatibility-render-plan
              action facts context index)))
           (provenance
            (apply
             #'emacsvox-aural--merge-rule-provenance
             object-plan compatibility-plans)))
      (emacsvox-aural--make-render-plan
       :before
       (append
        (apply
         #'append
         (mapcar
          #'emacsvox-aural-render-plan-before
          compatibility-plans))
        (emacsvox-aural-render-plan-before object-plan))
       :content (emacsvox-aural-render-plan-content object-plan)
       :after
       (append
        (emacsvox-aural-render-plan-after object-plan)
        (apply
         #'append
         (mapcar
          #'emacsvox-aural-render-plan-after
          compatibility-plans)))
       :matched-rules (plist-get provenance :rules)
       :rule-scores (plist-get provenance :scores)
       :semantic-matches (plist-get provenance :semantic-matches)))))

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
    (text start end base-facts base-context object-id
          &optional compatibility-actions)
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
            (emacsvox-aural--merge-object-compatibility
             (emacsvox-aural--resolve-source-object runs 'object)
             compatibility-actions
             (emacsvox-aural-source-run-facts (car runs))
             (emacsvox-aural-source-run-context (car runs))))
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

(defun emacsvox-aural-prepare-text
    (text &optional facts context compatibility-actions)
  "Freeze object and formatting-run decisions in TEXT.

FACTS default to `emacsvox-aural-submission-facts'.  CONTEXT defaults to the
dynamically captured submission context or a fresh source-buffer snapshot.
The returned string retains legacy properties and adds concrete nested plans.
One inferred object spans the submission until semantic context or a queued
icon changes.  `emacsvox-aural-object-property' can group complex runs
explicitly.  COMPATIBILITY-ACTIONS, when non-nil, are normalized source
adapter records applied to the first explicit presentation object."
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
         prepared position end base-facts base-context object-id
         compatibility-actions)
        (setq position end
              compatibility-actions nil)))
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

(provide 'emacsvox-aural-planner)
;;; emacsvox-aural-planner.el ends here
