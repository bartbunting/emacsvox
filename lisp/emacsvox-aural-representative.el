;;; emacsvox-aural-representative.el --- Cross-module aural semantics -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Register the lightweight semantic vocabulary shared by the representative
;; Notmuch, Agent Shell, Python, and Vertico migrations.  This file has no
;; dependency on those packages, so personal schemes can validate at startup
;; before any integration is loaded.

;;; Code:

(require 'emacsvox-aural)
(require 'emacsvox-aural-schemes)

(defconst emacsvox-aural-representative-semantics
  '((message
     :kind role
     :summary "A mail or communication message"
     :owner core
     :occasions
     (navigation continuous state-change inspection notification)
     :phases (before content after))
    (field
     :kind role
     :summary "A named field within a structured object"
     :owner core
     :occasions (navigation continuous state-change inspection)
     :phases (content))
    (field-kind
     :kind attribute
     :summary "The module-defined purpose of a structured field"
     :owner core
     :roles (field)
     :value-type symbol)
    (unread
     :kind state
     :summary "An item has not yet been read"
     :owner core
     :occasions (navigation continuous state-change notification)
     :phases (before content after))
    (flagged
     :kind state
     :summary "An item has been explicitly flagged for attention"
     :owner core
     :occasions (navigation continuous state-change notification)
     :phases (before content after))
    (has-attachments
     :kind state
     :summary "A message contains one or more attachments"
     :owner core
     :occasions (navigation continuous state-change inspection)
     :phases (before content after))
    (refresh-completed
     :kind event
     :summary "A displayed collection finished refreshing"
     :owner core
     :occasions (notification)
     :phases (before content after))
    (refresh-failed
     :kind event
     :summary "A displayed collection failed to refresh"
     :owner core
     :occasions (notification)
     :phases (before content after))
    (message-opened
     :kind event
     :summary "A mail or communication message was opened for reading"
     :owner core
     :occasions (state-change notification)
     :phases (before content after))
    (message-marked
     :kind event
     :summary "A message mark or persistent attention state changed"
     :owner core
     :occasions (state-change)
     :phases (before content after))
    (message-deleted
     :kind event
     :summary "A message was marked or removed as deleted"
     :owner core
     :occasions (state-change)
     :phases (before content after))
    (mail-group
     :kind role
     :summary "A mail or news group containing messages"
     :owner gnus
     :occasions (navigation state-change inspection notification)
     :phases (before content after))
    (mail-view
     :kind role
     :summary "A mail reader group, summary, article, compose, or server view"
     :owner core
     :occasions (navigation state-change inspection notification)
     :phases (before content after))
    (message-thread
     :kind role
     :summary "A conversation thread containing related messages"
     :owner core
     :occasions (navigation state-change inspection)
     :phases (before content after))
    (message-part
     :kind role
     :summary "A body, attachment, link, button, or other part of a message"
     :owner core
     :occasions (navigation state-change inspection notification)
     :phases (before content after))
    (mail-view-kind
     :kind attribute
     :summary "The kind of mail-reader view being presented"
     :owner core
     :roles (mail-view)
     :value-type symbol
     :allowed-values
     (group summary article compose server search thread topic other))
    (message-part-kind
     :kind attribute
     :summary "The kind of content part within a message"
     :owner core
     :roles (message-part)
     :value-type symbol
     :allowed-values
     (body page attachment link button mime-part header other))
    (mail-action-kind
     :kind attribute
     :summary "The mail-reader operation whose feedback is being presented"
     :owner core
     :value-type symbol
     :allowed-values
     (open close compose select unsubscribe catch-up restore list
           customize toggle-topic show hide scroll activate modify save
           archive tag search refresh))
    (mail-view-opened
     :kind event
     :summary "A mail reader view was opened or selected"
     :owner core
     :occasions (navigation state-change)
     :phases (before content after))
    (mail-view-closed
     :kind event
     :summary "A mail reader view was closed, buried, or left"
     :owner core
     :occasions (state-change)
     :phases (before content after))
    (filesystem-entry
     :kind role
     :summary "A file, directory, symbolic link, or other directory entry"
     :owner dired
     :occasions (navigation state-change inspection)
     :phases (before content after))
    (filesystem-listing
     :kind role
     :summary "A directory or search-result listing of filesystem entries"
     :owner dired
     :occasions (navigation state-change inspection)
     :phases (before content after))
    (confirmation-request
     :kind role
     :summary "A prompt asking the user to confirm an action"
     :owner core
     :occasions (notification)
     :phases (before content after))
    (entry-kind
     :kind attribute
     :summary "The filesystem kind of a directory entry"
     :owner dired
     :roles (filesystem-entry)
     :value-type symbol
     :allowed-values (file directory symbolic-link other))
    (entry-inspection-kind
     :kind attribute
     :summary "The requested property of a filesystem entry"
     :owner dired
     :value-type symbol
     :allowed-values
     (size modification-time access-time symbolic-link-target permissions
           file-type))
    (marked
     :kind state
     :summary "An item is marked for a later operation"
     :owner dired
     :occasions (navigation state-change)
     :phases (before content after))
    (deletion-flagged
     :kind state
     :summary "A filesystem entry is flagged for deletion"
     :owner dired
     :occasions (navigation state-change)
     :phases (before content after))
    (entry-marked
     :kind event
     :summary "A filesystem entry was marked"
     :owner dired
     :occasions (state-change)
     :phases (before content after))
    (entry-unmarked
     :kind event
     :summary "A filesystem entry mark was removed"
     :owner dired
     :occasions (state-change)
     :phases (before content after))
    (entry-deletion-flagged
     :kind event
     :summary "A filesystem entry was flagged for deletion"
     :owner dired
     :occasions (state-change)
     :phases (before content after))
    (entry-opened
     :kind event
     :summary "A filesystem entry or directory was opened"
     :owner dired
     :occasions (state-change)
     :phases (before content after))
    (entry-inspected
     :kind event
     :summary "The user requested a property of a filesystem entry"
     :owner dired
     :occasions (inspection)
     :phases (before content after))
    (vcs-section
     :kind role
     :summary "A structural section in a version-control view"
     :owner magit
     :occasions (navigation state-change notification)
     :phases (before content after))
    (vcs-view
     :kind role
     :summary "A version-control status, log, blob, blame, or diff view"
     :owner magit
     :occasions (navigation state-change inspection notification)
     :phases (before content after))
    (vcs-blame-chunk
     :kind role
     :summary "One annotated source chunk in a version-control blame view"
     :owner magit
     :occasions (navigation inspection)
     :phases (before content after))
    (vcs-process
     :kind role
     :summary "An asynchronous version-control operation"
     :owner magit
     :occasions (notification)
     :phases (before content after))
    (section-kind
     :kind attribute
     :summary "The integration-defined kind of a structural section"
     :owner magit
     :roles (vcs-section)
     :value-type symbol)
    (vcs-view-kind
     :kind attribute
     :summary "The kind of version-control view being presented"
     :owner magit
     :roles (vcs-view)
     :value-type symbol
     :allowed-values (status log blob blame diff commit other))
    (staged
     :kind state
     :summary "A version-control change is staged for commit"
     :owner magit
     :occasions (navigation state-change)
     :phases (before content after))
    (unstaged
     :kind state
     :summary "A version-control change is not staged for commit"
     :owner magit
     :occasions (navigation state-change)
     :phases (before content after))
    (entry-staged
     :kind event
     :summary "A version-control entry was staged"
     :owner magit
     :occasions (state-change)
     :phases (before content after))
    (entry-unstaged
     :kind event
     :summary "A version-control entry was unstaged"
     :owner magit
     :occasions (state-change)
     :phases (before content after))
    (vcs-view-opened
     :kind event
     :summary "A version-control view was opened or selected"
     :owner magit
     :occasions (navigation state-change)
     :phases (before content after))
    (vcs-view-closed
     :kind event
     :summary "A version-control view was closed or buried"
     :owner magit
     :occasions (state-change)
     :phases (before content after))
    (vcs-commit-displayed
     :kind event
     :summary "A version-control commit was displayed"
     :owner magit
     :occasions (navigation state-change)
     :phases (before content after))
    (vcs-diff-scrolled
     :kind event
     :summary "Navigation moved within a version-control diff"
     :owner magit
     :occasions (navigation)
     :phases (before content after))
    (visibility-changed
     :kind event
     :summary "The visible descendants of a structural object changed"
     :owner core
     :occasions (state-change)
     :phases (before content after))
    (operation-completed
     :kind event
     :summary "A requested module operation completed successfully"
     :owner core
     :occasions (state-change inspection notification)
     :phases (before content after))
    (operation-failed
     :kind event
     :summary "A requested module operation failed"
     :owner core
     :occasions (navigation state-change inspection notification)
     :phases (before content after))
    (code-construct
     :kind role
     :summary "A structural construct in source code"
     :owner core
     :occasions (navigation continuous inspection)
     :phases (before content after))
    (syntax-role
     :kind attribute
     :summary "The language-defined structural role of source code"
     :owner core
     :value-type symbol)
    (boundary-entered
     :kind event
     :summary "Navigation arrived at a source-code boundary"
     :owner core
     :occasions (navigation)
     :phases (before content after))
    (candidate
     :kind role
     :summary "One available completion candidate"
     :owner core
     :occasions (navigation state-change)
     :phases (before content after))
    (selected
     :kind state
     :summary "An item is the current selection"
     :owner core
     :occasions (navigation state-change)
     :phases (before content after))
    (accepted
     :kind event
     :summary "The current candidate or choice was accepted"
     :owner core
     :occasions (state-change)
     :phases (before content after))
    (completion-index
     :kind attribute
     :summary "Zero-based position of a candidate in a completion list"
     :owner core
     :value-type integer)
    (agent-session
     :kind role
     :summary "One interactive agent conversation"
     :owner agent-shell
     :occasions
     (navigation continuous state-change inspection notification)
     :phases (before content after))
    (agent-response
     :kind role
     :summary "User-facing response content produced by an agent"
     :owner agent-shell
     :occasions (continuous navigation inspection notification)
     :phases (before content after))
    (agent-user-prompt
     :kind role
     :summary "User-authored prompt content in an agent conversation"
     :owner agent-shell
     :occasions (continuous navigation edit inspection)
     :phases (before content after))
    (agent-thought
     :kind role
     :summary "Intermediate reasoning content exposed by an agent"
     :owner agent-shell
     :occasions (continuous navigation inspection)
     :phases (before content after))
    (agent-plan
     :kind role
     :summary "A plan produced by an agent"
     :owner agent-shell
     :occasions (continuous navigation inspection)
     :phases (before content after))
    (agent-tool
     :kind role
     :summary "A tool invocation or its output in an agent session"
     :owner agent-shell
     :occasions (continuous navigation inspection notification)
     :phases (before content after))
    (permission-request
     :kind role
     :summary "An agent action awaiting user permission"
     :owner agent-shell
     :occasions (navigation state-change notification)
     :phases (before content after))
    (agent-block
     :kind role
     :summary "One navigable structural block in an agent transcript"
     :owner agent-shell
     :occasions (navigation state-change inspection)
     :phases (before content after))
    (agent-source-block
     :kind role
     :summary "A rendered source-code block in an agent response"
     :owner agent-shell
     :occasions (navigation inspection state-change)
     :phases (before content after))
    (agent-table
     :kind role
     :summary "A rendered table in an agent response"
     :owner agent-shell
     :occasions (navigation inspection state-change)
     :phases (before content after))
    (agent-table-cell
     :kind role
     :summary "One logical cell in a rendered agent-response table"
     :owner agent-shell
     :occasions (navigation inspection state-change)
     :phases (before content after))
    (agent-viewport
     :kind role
     :summary "An Agent Shell response or prompt viewport"
     :owner agent-shell
     :occasions (navigation state-change notification)
     :phases (before content after))
    (agent-prompt-editor
     :kind role
     :summary "An editor used to compose an Agent Shell prompt"
     :owner agent-shell
     :occasions (navigation edit state-change)
     :phases (before content after))
    (agent-error
     :kind role
     :summary "Error content produced while running an agent session"
     :owner agent-shell
     :occasions (continuous navigation inspection notification)
     :phases (before content after))
    (agent-block-kind
     :kind attribute
     :summary "The structural kind of an Agent Shell transcript block"
     :owner agent-shell
     :value-type symbol
     :allowed-values
     (agent-response user-prompt thought tool-call activity-group plan
                     permission error table source-block other))
    (agent-tool-status
     :kind attribute
     :summary "The current lifecycle status of an Agent Shell tool call"
     :owner agent-shell
     :value-type symbol
     :allowed-values (pending in-progress completed failed))
    (agent-table-row
     :kind attribute
     :summary "The zero-based logical row of an Agent Shell table cell"
     :owner agent-shell
     :value-type integer)
    (agent-table-column
     :kind attribute
     :summary "The zero-based logical column of an Agent Shell table cell"
     :owner agent-shell
     :value-type integer)
    (agent-source-language
     :kind attribute
     :summary "The declared language of an Agent Shell source block"
     :owner agent-shell
     :value-type string)
    (agent-speech-level
     :kind attribute
     :summary "The selected automatic speech level for an agent session"
     :owner agent-shell
     :value-type symbol
     :allowed-values (auto full response notify quiet))
    (agent-viewport-mode
     :kind attribute
     :summary "The interaction mode of an Agent Shell viewport"
     :owner agent-shell
     :value-type symbol
     :allowed-values (view edit))
    (agent-prompt-disposition
     :kind attribute
     :summary "Whether an Agent Shell prompt was submitted, queued, or sent"
     :owner agent-shell
     :value-type symbol
     :allowed-values (submitted queued sent))
    (agent-permission-result
     :kind attribute
     :summary "The result of an Agent Shell permission decision"
     :owner agent-shell
     :value-type symbol
     :allowed-values (allowed denied cancelled sent))
    (processing
     :kind state
     :summary "An agent session is processing a request"
     :owner agent-shell
     :occasions (continuous notification)
     :phases (before content after))
    (processing-started
     :kind event
     :summary "An agent began initialization or request processing"
     :owner agent-shell
     :occasions (notification)
     :phases (before content after))
    (processing-completed
     :kind event
     :summary "An agent completed initialization or a request"
     :owner agent-shell
     :occasions (notification)
     :phases (before content after))
    (processing-failed
     :kind event
     :summary "An agent request ended exceptionally"
     :owner agent-shell
     :occasions (notification)
     :phases (before content after))
    (agent-session-opened
     :kind event
     :summary "An Agent Shell session was opened or selected"
     :owner agent-shell
     :occasions (navigation state-change)
     :phases (before content after))
    (agent-session-interrupted
     :kind event
     :summary "The user interrupted an Agent Shell request"
     :owner agent-shell
     :occasions (state-change notification)
     :phases (before content after))
    (agent-setting-changed
     :kind event
     :summary "An Agent Shell presentation or session setting changed"
     :owner agent-shell
     :occasions (state-change)
     :phases (before content after))
    (agent-content-inspected
     :kind event
     :summary "The user explicitly requested Agent Shell content"
     :owner agent-shell
     :occasions (inspection)
     :phases (before content after))
    (agent-content-copied
     :kind event
     :summary "Agent Shell content was copied for reuse"
     :owner agent-shell
     :occasions (state-change)
     :phases (before content after))
    (agent-table-entered
     :kind event
     :summary "Navigation entered a rendered Agent Shell table"
     :owner agent-shell
     :occasions (navigation)
     :phases (before content after))
    (agent-table-exited
     :kind event
     :summary "Navigation left a rendered Agent Shell table"
     :owner agent-shell
     :occasions (navigation)
     :phases (before content after))
    (agent-viewport-opened
     :kind event
     :summary "An Agent Shell viewport was opened"
     :owner agent-shell
     :occasions (state-change)
     :phases (before content after))
    (agent-viewport-refreshed
     :kind event
     :summary "An Agent Shell viewport finished refreshing"
     :owner agent-shell
     :occasions (state-change notification)
     :phases (before content after))
    (agent-prompt-opened
     :kind event
     :summary "An Agent Shell prompt editor was opened"
     :owner agent-shell
     :occasions (edit state-change)
     :phases (before content after))
    (agent-prompt-submitted
     :kind event
     :summary "A composed Agent Shell prompt was submitted or queued"
     :owner agent-shell
     :occasions (state-change notification)
     :phases (before content after))
    (agent-prompt-cancelled
     :kind event
     :summary "Agent Shell prompt composition was cancelled"
     :owner agent-shell
     :occasions (state-change)
     :phases (before content after))
    (agent-tool-status-changed
     :kind event
     :summary "An Agent Shell tool call changed lifecycle status"
     :owner agent-shell
     :occasions (notification)
     :phases (before content after))
    (agent-permission-requested
     :kind event
     :summary "An Agent Shell action requested user permission"
     :owner agent-shell
     :occasions (notification)
     :phases (before content after))
    (agent-permission-resolved
     :kind event
     :summary "An Agent Shell permission request was resolved"
     :owner agent-shell
     :occasions (state-change notification)
     :phases (before content after)))
  "Semantic definitions used by representative integration slices.")

(defconst emacsvox-aural-workflow-feature-fragments
  '((:schema-version 1
     :id mail-message-status-cues
     :summary "Add semantic cues for unread, flagged, and attached messages"
     :rules
     ((:id workflow-mail-unread
       :match (:role message :state unread :occasion navigation)
       :render
       (:before
        (:append
         ((:id workflow-mail-unread-cue :kind cue :cue new-mail)))))
      (:id workflow-mail-flagged
       :match (:role message :state flagged :occasion navigation)
       :render
       (:before
        (:append
         ((:id workflow-mail-flagged-cue :kind cue :cue mark-object)))))
      (:id workflow-mail-attachments
       :match (:role message :state has-attachments :occasion navigation)
       :render
       (:after
        (:append
         ((:id workflow-mail-attachments-label
           :kind speech :text "has attachments")))))))
    (:schema-version 1
     :id dired-entry-state-labels
     :summary "Speak Dired mark and deletion-flag changes after the entry"
     :rules
     ((:id workflow-dired-marked
       :match
       (:role filesystem-entry :module dired
        :event entry-marked :occasion state-change)
       :render
       (:after
        (:append
         ((:id workflow-dired-marked-label :kind speech :text "marked")))))
      (:id workflow-dired-unmarked
       :match
       (:role filesystem-entry :module dired
        :event entry-unmarked :occasion state-change)
       :render
       (:after
        (:append
         ((:id workflow-dired-unmarked-label :kind speech :text "unmarked")))))
      (:id workflow-dired-deletion
       :match
       (:role filesystem-entry :module dired
        :event entry-deletion-flagged :occasion state-change)
       :render
       (:after
        (:append
         ((:id workflow-dired-deletion-label
           :kind speech :text "flagged for deletion")))))))
    (:schema-version 1
     :id magit-section-visibility-cues
     :summary "Add semantic open and close cues when Magit section visibility changes"
     :rules
     ((:id workflow-magit-section-folded
       :match
       (:role vcs-section :module magit :event visibility-changed
        :visibility folded :occasion state-change)
       :render
       (:after
        (:append
         ((:id workflow-magit-section-folded-cue
           :kind cue :cue close-object)))))
      (:id workflow-magit-section-expanded
       :match
       (:role vcs-section :module magit :event visibility-changed
        :visibility expanded :occasion state-change)
       :render
       (:after
        (:append
         ((:id workflow-magit-section-expanded-cue
           :kind cue :cue open-object))))))))
  "Disabled built-in feature layers for migrated user workflows.")

(defconst emacsvox-aural-agent-shell-feature-fragments
  '((:schema-version 1
     :id agent-shell-block-type-labels
     :summary "Speak the semantic type when entering an Agent Shell block"
     :rules
     ((:id agent-shell-block-type-label
       :match
       (:module agent-shell :event focus-entered :occasion navigation
        :requires (agent-block-kind))
       :render
       (:before
        (:prepend
         ((:id agent-shell-block-type-label-action
           :kind speech
           :text-template "{agent-block-kind}")))))))
    (:schema-version 1
     :id agent-shell-block-type-cues
     :summary "Use distinct semantic cues for Agent Shell block types"
     :rules
     ((:id agent-shell-agent-response-cue
       :match
       (:module agent-shell :event focus-entered :occasion navigation
        :agent-block-kind agent-response)
       :render
       (:before
        (:append
         ((:id agent-shell-agent-response-cue-action
           :kind cue :cue section)))))
      (:id agent-shell-user-prompt-cue
       :match
       (:module agent-shell :event focus-entered :occasion navigation
        :agent-block-kind user-prompt)
       :render
       (:before
        (:append
         ((:id agent-shell-user-prompt-cue-action
           :kind cue :cue ask-question)))))
      (:id agent-shell-thought-cue
       :match
       (:module agent-shell :event focus-entered :occasion navigation
        :agent-block-kind thought)
       :render
       (:before
        (:append
         ((:id agent-shell-thought-cue-action
           :kind cue :cue progress)))))
      (:id agent-shell-tool-call-cue
       :match
       (:module agent-shell :event focus-entered :occasion navigation
        :agent-block-kind tool-call)
       :render
       (:before
        (:append
         ((:id agent-shell-tool-call-cue-action
           :kind cue :cue button)))))
      (:id agent-shell-activity-group-cue
       :match
       (:module agent-shell :event focus-entered :occasion navigation
        :agent-block-kind activity-group)
       :render
       (:before
        (:append
         ((:id agent-shell-activity-group-cue-action
           :kind cue :cue repeat-active)))))
      (:id agent-shell-plan-cue
       :match
       (:module agent-shell :event focus-entered :occasion navigation
        :agent-block-kind plan)
       :render
       (:before
        (:append
         ((:id agent-shell-plan-cue-action
           :kind cue :cue item)))))
      (:id agent-shell-permission-cue
       :match
       (:module agent-shell :event focus-entered :occasion navigation
        :agent-block-kind permission)
       :render
       (:before
        (:append
         ((:id agent-shell-permission-cue-action
           :kind cue :cue alert-user)))))
      (:id agent-shell-error-cue
       :match
       (:module agent-shell :event focus-entered :occasion navigation
        :agent-block-kind error)
       :render
       (:before
        (:append
         ((:id agent-shell-error-cue-action
           :kind cue :cue warn-user)))))
      (:id agent-shell-table-cue
       :match
       (:module agent-shell :event focus-entered :occasion navigation
        :agent-block-kind table)
       :render
       (:before
        (:append
         ((:id agent-shell-table-cue-action
           :kind cue :cue select-object)))))
      (:id agent-shell-source-block-cue
       :match
       (:module agent-shell :event focus-entered :occasion navigation
        :agent-block-kind source-block)
       :render
       (:before
        (:append
         ((:id agent-shell-source-block-cue-action
           :kind cue :cue doc)))))
      (:id agent-shell-other-block-cue
       :match
       (:module agent-shell :event focus-entered :occasion navigation
        :agent-block-kind other)
       :render
       (:before
        (:append
         ((:id agent-shell-other-block-cue-action
           :kind cue :cue large-movement)))))))
    (:schema-version 1
     :id agent-shell-block-visibility-cues
     :summary "Cue folded and expanded Agent Shell blocks on entry and toggle"
     :rules
     ((:id agent-shell-navigated-folded-cue
       :match
       (:module agent-shell :event focus-entered
        :occasion navigation :visibility folded)
       :render
       (:before
        (:append
         ((:id agent-shell-navigated-folded-cue-action
           :kind cue :cue close-object)))))
      (:id agent-shell-navigated-expanded-cue
       :match
       (:module agent-shell :event focus-entered
        :occasion navigation :visibility expanded)
       :render
       (:before
        (:append
         ((:id agent-shell-navigated-expanded-cue-action
           :kind cue :cue open-object)))))
      (:id agent-shell-toggled-folded-cue
       :match
       (:module agent-shell :event visibility-changed
        :occasion state-change :visibility folded)
       :render
       (:before
        (:remove (legacy-cue)
         :append
         ((:id agent-shell-toggled-folded-cue-action
           :kind cue :cue close-object)))))
      (:id agent-shell-toggled-expanded-cue
       :match
       (:module agent-shell :event visibility-changed
        :occasion state-change :visibility expanded)
       :render
       (:before
        (:remove (legacy-cue)
         :append
         ((:id agent-shell-toggled-expanded-cue-action
           :kind cue :cue open-object))))))))
  "Optional built-in presentation layers for Agent Shell transcript blocks.")

(defun emacsvox-aural-register-representative-semantics ()
  "Register the representative cross-module semantic vocabulary."
  (dolist (definition emacsvox-aural-representative-semantics)
    (let ((id (car definition))
          (metadata (cdr definition)))
      (unless (emacsvox-aural-semantic id)
        (apply #'emacsvox-aural-register-semantic id metadata))))
  (emacsvox-aural-validate-registry)
  (dolist (data emacsvox-aural-workflow-feature-fragments)
    (unless (emacsvox-aural-feature-fragment-entry (plist-get data :id))
      (emacsvox-aural-register-feature-fragment
       data :built-in t :source "emacsvox-aural-representative")))
  (dolist (data emacsvox-aural-agent-shell-feature-fragments)
    (unless (emacsvox-aural-feature-fragment-entry (plist-get data :id))
      (emacsvox-aural-register-feature-fragment
       data :built-in t :source "emacsvox-aural-representative"))))

(emacsvox-aural-register-representative-semantics)

(provide 'emacsvox-aural-representative)
;;; emacsvox-aural-representative.el ends here
