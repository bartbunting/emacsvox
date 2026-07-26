;;; emacsvox-aural-markdown.el --- Data-only Markdown presentation -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Register Markdown structure and its compatibility presentation without
;; loading markdown-mode.  Live fact capture remains in emacsvox-markdown.el.

;;; Code:

(require 'emacsvox-aural-schemes)
(require 'emacsvox-aural-representative)

(defconst emacsvox-markdown-aural-semantics
  '((markdown-content
     :kind role
     :summary "Ordinary prose content in a Markdown document"
     :owner markdown
     :occasions (navigation continuous inspection)
     :phases (before content after))
    (markdown-list-item
     :kind role
     :summary "One ordered or unordered Markdown list item"
     :owner markdown
     :occasions (navigation continuous inspection edit)
     :phases (before content after))
    (markdown-task
     :kind role
     :summary "A Markdown task-list item"
     :owner markdown
     :occasions (navigation continuous state-change inspection edit)
     :phases (before content after))
    (markdown-link
     :kind role
     :summary "A Markdown link, image, or reference"
     :owner markdown
     :occasions (navigation continuous inspection edit)
     :phases (before content after))
    (markdown-code-block
     :kind role
     :summary "A fenced Markdown source-code block"
     :owner markdown
     :occasions (navigation continuous inspection edit)
     :phases (before content after))
    (markdown-table-row
     :kind role
     :summary "One logical row of a Markdown table"
     :owner markdown
     :occasions (navigation continuous inspection edit)
     :phases (before content after))
    (markdown-footnote
     :kind role
     :summary "A Markdown footnote definition or reference"
     :owner markdown
     :occasions (navigation continuous inspection edit)
     :phases (before content after))
    (markdown-separator
     :kind role
     :summary "A thematic or structural separator in Markdown"
     :owner markdown
     :occasions (navigation continuous)
     :phases (before content after))
    (markdown-language
     :kind attribute
     :summary "The declared language of a Markdown fenced code block"
     :owner markdown
     :value-type string)
    (markdown-list-kind
     :kind attribute
     :summary "Whether a Markdown list item is ordered or unordered"
     :owner markdown
     :value-type symbol
     :allowed-values (ordered unordered))
    (markdown-task-state
     :kind attribute
     :summary "Whether a Markdown task is checked or unchecked"
     :owner markdown
     :value-type symbol
     :allowed-values (checked unchecked))
    (markdown-navigation-kind
     :kind attribute
     :summary "Whether Markdown navigation was by line or structure"
     :owner markdown
     :value-type symbol
     :allowed-values (line structural))
    (checked
     :kind state
     :summary "A checkable item is complete"
     :owner markdown
     :occasions (navigation continuous state-change inspection)
     :phases (before content after))
    (unchecked
     :kind state
     :summary "A checkable item is incomplete"
     :owner markdown
     :occasions (navigation continuous state-change inspection)
     :phases (before content after))
    (markdown-heading-navigated
     :kind event
     :summary "Structural navigation arrived at a Markdown heading"
     :owner markdown
     :occasions (navigation)
     :phases (before content after))
    (markdown-link-navigated
     :kind event
     :summary "Navigation arrived at a Markdown link"
     :owner markdown
     :occasions (navigation)
     :phases (before content after))
    (markdown-structure-navigated
     :kind event
     :summary "A Markdown structural navigation command moved point"
     :owner markdown
     :occasions (navigation)
     :phases (before content after))
    (markdown-operation-completed
     :kind event
     :summary "A Markdown validation or export operation completed"
     :owner markdown
     :occasions (notification state-change)
     :phases (before content after))
    (markdown-completion-completed
     :kind event
     :summary "A Markdown completion command updated document content"
     :owner markdown
     :occasions (edit)
     :phases (before content after)))
  "Semantic definitions owned by the Markdown integration.")

(defconst emacsvox-markdown-aural-compatibility-fragment
  '(:schema-version 1
    :id markdown-compatibility
    :summary "Compatibility cues for semantic Markdown presentation"
    :rules
    ((:id markdown-line-separator-compatibility
      :match
      (:role markdown-separator :module markdown :occasion navigation
       :markdown-navigation-kind line)
      :render
      (:before
       ((:id markdown-line-separator-cue :kind cue :cue item))))
     (:id markdown-line-code-block-compatibility
      :match
      (:role markdown-code-block :module markdown :occasion navigation
       :markdown-navigation-kind line)
      :render
      (:before
       ((:id markdown-line-code-block-cue :kind cue :cue open-object))))
     (:id markdown-line-heading-compatibility
      :match
      (:role heading :module markdown :occasion navigation
       :markdown-navigation-kind line)
      :render
      (:before
       ((:id markdown-line-heading-cue :kind cue :cue section))))
     (:id markdown-line-task-compatibility
      :match
      (:role markdown-task :module markdown :occasion navigation
       :markdown-navigation-kind line)
      :render
      (:before
       ((:id markdown-line-task-cue :kind cue :cue mark-object))))
     (:id markdown-heading-navigation-compatibility
      :match
      (:role heading :module markdown :event markdown-heading-navigated
       :occasion navigation)
      :render
      (:before
       ((:id markdown-heading-navigation-cue
         :kind cue :cue large-movement))))
     (:id markdown-link-navigation-compatibility
      :match
      (:role markdown-link :module markdown :event markdown-link-navigated
       :occasion navigation)
      :render
      (:before
       ((:id markdown-link-navigation-cue :kind cue :cue button))))
     (:id markdown-structure-navigation-compatibility
      :match
      (:module markdown :event markdown-structure-navigated
       :occasion navigation)
      :render
      (:before
       ((:id markdown-structure-navigation-cue
         :kind cue :cue large-movement))))
     (:id markdown-visibility-compatibility
      :match
      (:module markdown :event visibility-changed :occasion state-change)
      :render
      (:before
       ((:id markdown-visibility-cue :kind cue :cue large-movement))))
     (:id markdown-edit-compatibility
      :match (:module markdown :event object-changed :occasion edit)
      :render
      (:before
       ((:id markdown-edit-cue :kind cue :cue large-movement))))
     (:id markdown-operation-compatibility
      :match
      (:module markdown :event markdown-operation-completed
       :occasion notification)
      :render
      (:before
       ((:id markdown-operation-cue :kind cue :cue task-done))))
     (:id markdown-completion-compatibility
      :match
      (:module markdown :event markdown-completion-completed
       :occasion edit)
      :render
      (:before
       ((:id markdown-completion-cue :kind cue :cue complete))))))
  "Default Markdown presentation that preserves established feedback.")

(defconst emacsvox-markdown-aural-feature-fragments
  '((:schema-version 1
     :id markdown-heading-level-labels
     :summary "Speak Markdown heading levels before heading contents"
     :rules
     ((:id markdown-heading-level-label
       :match
       (:role heading :module markdown :requires (level)
        :occasion navigation)
       :render
       (:before
        (:prepend
         ((:id markdown-heading-level-label-action
           :kind speech :text-template "Heading {level}")))))))
    (:schema-version 1
     :id markdown-task-state-labels
     :summary "Speak checked and unchecked state after Markdown tasks"
     :rules
     ((:id markdown-task-checked-label
       :match
       (:role markdown-task :module markdown :state checked)
       :render
       (:after
        (:append
         ((:id markdown-task-checked-label-action
           :kind speech :text "checked")))))
      (:id markdown-task-unchecked-label
       :match
       (:role markdown-task :module markdown :state unchecked)
       :render
       (:after
        (:append
         ((:id markdown-task-unchecked-label-action
           :kind speech :text "unchecked"))))))))
  "Optional built-in Markdown presentation layers.")

(defun emacsvox-markdown-register-aural-presentation ()
  "Register Markdown semantics, compatibility rules, and feature fragments."
  (dolist (definition emacsvox-markdown-aural-semantics)
    (let ((id (car definition))
          (metadata (cdr definition)))
      (unless (emacsvox-aural-semantic id)
        (apply #'emacsvox-aural-register-semantic id metadata))))
  (emacsvox-aural-validate-registry)
  (unless
      (gethash
       'markdown-compatibility emacsvox-aural-module-fragment-registry)
    (emacsvox-aural-register-module-fragment
     'markdown emacsvox-markdown-aural-compatibility-fragment
     :source "emacsvox-aural-markdown"))
  (dolist (data emacsvox-markdown-aural-feature-fragments)
    (unless (emacsvox-aural-feature-fragment-entry (plist-get data :id))
      (emacsvox-aural-register-feature-fragment
       data :built-in t :source "emacsvox-aural-markdown"))))

(emacsvox-markdown-register-aural-presentation)

(provide 'emacsvox-aural-markdown)
;;; emacsvox-aural-markdown.el ends here
