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
     :occasions (navigation continuous notification)
     :phases (before content after))
    (field
     :kind role
     :summary "A named field within a structured object"
     :owner core
     :occasions (navigation continuous inspection)
     :phases (content))
    (field-kind
     :kind attribute
     :summary "The module-defined purpose of a structured field"
     :owner core
     :value-type symbol)
    (unread
     :kind state
     :summary "An item has not yet been read"
     :owner core
     :occasions (navigation continuous notification)
     :phases (before content after))
    (flagged
     :kind state
     :summary "An item has been explicitly flagged for attention"
     :owner core
     :occasions (navigation continuous notification)
     :phases (before content after))
    (has-attachments
     :kind state
     :summary "A message contains one or more attachments"
     :owner core
     :occasions (navigation continuous inspection)
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
     :occasions (navigation state-change notification)
     :phases (before content after))
    (filesystem-entry
     :kind role
     :summary "A file, directory, symbolic link, or other directory entry"
     :owner dired
     :occasions (navigation state-change inspection)
     :phases (before content after))
    (entry-kind
     :kind attribute
     :summary "The filesystem kind of a directory entry"
     :owner dired
     :value-type symbol
     :allowed-values (file directory symbolic-link other))
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
    (vcs-section
     :kind role
     :summary "A structural section in a version-control view"
     :owner magit
     :occasions (navigation state-change notification)
     :phases (before content after))
    (section-kind
     :kind attribute
     :summary "The integration-defined kind of a structural section"
     :owner magit
     :value-type symbol)
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
     :occasions (notification state-change)
     :phases (before content after))
    (operation-failed
     :kind event
     :summary "A requested module operation failed"
     :owner core
     :occasions (notification state-change)
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
     :occasions (continuous notification)
     :phases (before content after))
    (agent-response
     :kind role
     :summary "User-facing response content produced by an agent"
     :owner agent-shell
     :occasions (continuous notification)
     :phases (before content after))
    (agent-thought
     :kind role
     :summary "Intermediate reasoning content exposed by an agent"
     :owner agent-shell
     :occasions (continuous)
     :phases (before content after))
    (agent-tool
     :kind role
     :summary "A tool invocation or its output in an agent session"
     :owner agent-shell
     :occasions (continuous notification)
     :phases (before content after))
    (permission-request
     :kind role
     :summary "An agent action awaiting user permission"
     :owner agent-shell
     :occasions (notification)
     :phases (before content after))
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
       data :built-in t :source "emacsvox-aural-representative"))))

(emacsvox-aural-register-representative-semantics)

(provide 'emacsvox-aural-representative)
;;; emacsvox-aural-representative.el ends here
