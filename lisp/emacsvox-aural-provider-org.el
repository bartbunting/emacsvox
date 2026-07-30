;;; emacsvox-aural-provider-org.el --- Data-only Org aural provider -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Register the lightweight Org compatibility fragment, selectable example
;; schemes, and optional feature fragments before personal aural data is
;; loaded.  This file deliberately does not load Org itself; live semantic
;; fact capture remains in emacsvox-org.el.

;;; Code:

(require 'emacsvox-aural-schemes)

(defconst emacsvox-org-aural-semantic-definitions
  '((org-content
     :kind role
     :summary "Ordinary content in an Org document"
     :owner org)
    (org-item
     :kind role
     :summary "One list item in an Org document"
     :owner org)
    (org-paragraph
     :kind role
     :summary "One prose paragraph in an Org document"
     :owner org)
    (org-agenda-entry
     :kind role
     :summary "One entry in an Org agenda"
     :owner org)
    (org-table
     :kind role
     :summary "An Org table or table cell"
     :owner org)
    (org-capture
     :kind role
     :summary "An Org capture target or capture lifecycle operation"
     :owner org)
    (org-edit-buffer
     :kind role
     :summary "A temporary Org source-editing buffer"
     :owner org)
    (org-export
     :kind role
     :summary "An Org export or publishing operation"
     :owner org)
    (org-action
     :kind attribute
     :summary "The user-visible Org operation being presented"
     :owner org
     :roles
     (heading org-content org-item org-paragraph org-agenda-entry org-table
              org-capture org-edit-buffer org-export)
     :value-type symbol
     :allowed-values
     (item-navigation structure-navigation paragraph-navigation
                      list-style-changed heading-edited subtree-changed
                      option-toggled timestamp-changed agenda-navigation
                      agenda-opened agenda-closed table-mode-toggled
                      table-navigation table-inspection
                      line-inserted checkbox-toggled item-boundary line-start
                      line-end capture-target capture-saved capture-cancelled
                      edit-opened edit-closed paragraph-filled todo-changed
                      list-item-created calendar-evaluated overview-shown
                      contents-shown indirect-buffer-opened export-menu-opened
                      priority-changed tags-changed planning-changed
                      effort-changed property-changed statistics-updated
                      radio-button-toggled display-changed context-action
                      agenda-entry-reordered agenda-entry-archived
                      agenda-entry-deleted agenda-entry-refiled
                      agenda-clock-changed agenda-mark-changed
                      agenda-bulk-action agenda-filter-changed
                      agenda-view-changed agenda-display-changed
                      agenda-refreshed
                      export-completed publish-completed))
    (org-table-row
     :kind attribute
     :summary "The one-based logical row of an Org table cell"
     :owner org
     :roles (org-table)
     :value-type integer)
    (org-table-column
     :kind attribute
     :summary "The one-based logical column of an Org table cell"
     :owner org
     :roles (org-table)
     :value-type integer)
    (org-table-presentation
     :kind attribute
     :summary "The cell and header information spoken for an Org table"
     :owner org
     :roles (org-table)
     :value-type symbol
     :allowed-values
     (cell column-header row-header coordinates cell-with-column-header
           cell-with-row-header cell-with-both-headers)))
  "Semantic definitions owned by the Org integration.")

(defconst emacsvox-org-aural-semantics
  '(heading level visibility folded focus-entered state-changed object-changed
            org-content org-item org-paragraph org-agenda-entry org-table
            org-capture org-edit-buffer org-export org-action org-table-row
            org-table-column org-table-presentation)
  "Semantic identifiers interpreted by the Org integration.")

(defconst emacsvox-org-aural-level-voices
  '((1 . bolden)
    (2 . brighten)
    (3 . animate)
    (4 . lighten)
    (5 . smoothen)
    (6 . monotone)
    (7 . lighten-medium)
    (8 . lighten-extra))
  "Voice-palette entries used by the Org voice-only example scheme.")

(defun emacsvox-org--require-aural-semantics ()
  "Verify that every semantic interpreted by Org is registered."
  (dolist (semantic emacsvox-org-aural-semantics)
    (unless (emacsvox-aural-semantic semantic)
      (error "Org requires unregistered aural semantic %S" semantic))))

(defun emacsvox-org--voice-only-rules ()
  "Return declarative level rules for the voice-only Org example."
  (mapcar
   (lambda (entry)
     (let ((level (car entry))
           (voice (cdr entry)))
       (list
        :id (intern (format "org-voice-heading-level-%d" level))
        :match (list :role 'heading :module 'org :level level)
        :render (list :content (list :voice voice)))))
   emacsvox-org-aural-level-voices))

(defun emacsvox-org--spoken-label-rules ()
  "Return declarative level rules for the spoken-label Org example."
  (mapcar
   (lambda (entry)
     (let ((level (car entry)))
       (list
        :id (intern (format "org-spoken-heading-level-%d" level))
        :match
        (list
         :role 'heading :module 'org :level level
         :occasion 'navigation)
        :render
        (list
         :before
         (list
          (list
           :id (intern (format "org-heading-level-%d-label" level))
           :kind 'speech
           :text (format "Heading %d" level)))
         :after
         '(:remove (org-heading-navigation-movement))))))
   emacsvox-org-aural-level-voices))

(defun emacsvox-org-aural-example-scheme-data ()
  "Return the built-in data-only Org example schemes."
  (list
   (list
    :schema-version 1
    :id 'org-voice-only
    :summary "Org heading levels presented only through distinct voices"
    :parent 'default
    :rules
    (append
     (emacsvox-org--voice-only-rules)
     '((:id org-voice-only-remove-navigation-cue
        :match (:role heading :module org :occasion navigation)
        :render
        (:after (:remove (org-heading-navigation-movement)))))))
   (list
    :schema-version 1
    :id 'org-spoken-label
    :summary "Org heading levels spoken before heading contents"
    :parent 'default
    :rules (emacsvox-org--spoken-label-rules))
   '(:schema-version 1
     :id org-cue-only
     :summary "Org headings introduced by one semantic section cue"
     :parent default
     :rules
     ((:id org-cue-only-heading
       :match (:role heading :module org :occasion navigation)
       :render
       (:before
        ((:id org-heading-section-cue :kind cue :cue section))
        :after (:remove (org-heading-navigation-movement))))))
   '(:schema-version 1
     :id org-combined
     :summary "Org headings combine a label, cue, and content voice"
     :parent default
     :rules
     ((:id org-combined-heading
       :match (:role heading :module org :occasion navigation)
       :render
       (:before
        ((:id org-combined-label :kind speech :text "Heading")
         (:id org-combined-cue :kind cue :cue section))
        :content (:voice bolden)
        :after (:remove (org-heading-navigation-movement))))))
   '(:schema-version 1
     :id org-before-after
     :summary "Org headings use explicit speech before and after contents"
     :parent default
     :rules
     ((:id org-before-after-heading
       :match (:role heading :module org :occasion navigation)
       :render
       (:before
        ((:id org-before-label :kind speech :text "Heading"))
        :after
        (:replace
         ((:id org-after-label :kind speech :text "end heading")))))))
   '(:schema-version 1
     :id org-folded-state
     :summary "Folded Org headings announce their state after contents"
     :parent default
     :rules
     ((:id org-folded-heading-state
       :match (:role heading :module org :state folded)
       :render
       (:after
        ((:id org-folded-label :kind speech :text "folded"))))))))

(defun emacsvox-org-aural-feature-fragment-data ()
  "Return optional built-in Org presentation feature fragments."
  '((:schema-version 1
     :id org-heading-level-labels
     :summary "Speak an Org heading's level before inherited presentation"
     :rules
     ((:id org-fragment-heading-level-label
       :match
       (:role heading :module org :occasion navigation :requires (level))
       :render
       (:before
        (:prepend
         ((:id org-fragment-heading-level-label-action
           :kind speech
           :text-template "Heading {level}")))))))
    (:schema-version 1
     :id org-heading-section-cues
     :summary "Add a section cue before navigated Org headings"
     :rules
     ((:id org-fragment-heading-section-cue
       :match (:role heading :module org :occasion navigation)
       :render
       (:before
        (:append
         ((:id org-fragment-heading-section-cue-action
           :kind cue
           :cue section)))))))
    (:schema-version 1
     :id org-heading-visibility-changes
     :summary "Speak an Org heading's level and new visibility after cycling"
     :rules
     ((:id org-fragment-heading-folded
       :match
       (:role heading :module org :event state-changed
        :visibility folded :requires (level) :occasion state-change)
       :render
       (:after
        (:append
         ((:id org-fragment-heading-folded-action
           :kind speech
           :text-template "Heading {level} is now folded")))))
      (:id org-fragment-heading-expanded
       :match
       (:role heading :module org :event state-changed
        :visibility expanded :requires (level) :occasion state-change)
       :render
       (:after
        (:append
         ((:id org-fragment-heading-expanded-action
           :kind speech
           :text-template "Heading {level} is now opened")))))))))

(defconst emacsvox-org-aural-feature-fragment-examples
  '((org-heading-level-labels org-level-three
     :rule org-fragment-heading-level-label
     :summary "Level three Org heading"
     :facts
     (:role heading :level 3 :visibility expanded
      :content "Project milestones")
     :context (:module org :mode org-mode :occasion navigation))
    (org-heading-visibility-changes org-level-two-folded
     :rule org-fragment-heading-folded
     :summary "Level two Org heading folded"
     :facts
     (:role heading :events (state-changed) :level 2 :visibility folded
      :content "Implementation details")
     :context (:module org :mode org-mode :occasion state-change)))
  "Curated data-only previews for optional Org presentation features.")

(defun emacsvox-org-register-aural-presentation ()
  "Register Org compatibility rules, examples, and optional fragments."
  (dolist (definition emacsvox-org-aural-semantic-definitions)
    (let ((id (car definition))
          (metadata (cdr definition)))
      (unless (emacsvox-aural-semantic id)
        (apply #'emacsvox-aural-register-semantic id metadata))))
  (emacsvox-org--require-aural-semantics)
  (unless (gethash 'org-compatibility
                   emacsvox-aural-module-fragment-registry)
    (emacsvox-aural-register-module-fragment
     'org
     '(:schema-version 1
       :id org-compatibility
       :summary "Compatibility presentation for semantic Org headings"
       :rules
       ((:id org-heading-navigation-compatibility
         :match (:role heading :module org :occasion navigation)
         :render
         (:after
          ((:id org-heading-navigation-movement
            :kind cue
            :cue large-movement))))
        (:id org-heading-edit-compatibility
         :match (:role heading :module org :occasion edit)
         :render
         (:after
          ((:id org-heading-edit-open
            :kind cue
            :cue open-object))))))
     :source "emacsvox-aural-provider-org"))
  (dolist (data (emacsvox-org-aural-example-scheme-data))
    (unless (emacsvox-aural-scheme-entry (plist-get data :id))
      (emacsvox-aural-register-scheme
       data :built-in t :source "emacsvox-aural-provider-org")))
  (dolist (data (emacsvox-org-aural-feature-fragment-data))
    (unless (emacsvox-aural-feature-fragment-entry (plist-get data :id))
      (emacsvox-aural-register-feature-fragment
       data :built-in t :source "emacsvox-aural-provider-org"
       :collection 'org)))
  (dolist (definition emacsvox-org-aural-feature-fragment-examples)
    (apply
     #'emacsvox-aural-register-feature-fragment-example
     (car definition)
     (cadr definition)
     :source "emacsvox-aural-provider-org"
     (cddr definition))))

(emacsvox-org-register-aural-presentation)

(provide 'emacsvox-aural-provider-org)
;;; emacsvox-aural-provider-org.el ends here
