;;; emacsvox-aural-provider-workflows.el --- Shared workflow aural provider -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Emacsvox Contributors

;; This file is not part of GNU Emacs, but the same permissions apply.

;;; Commentary:

;; Register the lightweight semantic vocabulary shared by the Notmuch, Gnus,
;; Dired, Magit, Shell/Comint, Agent Shell, Python, Vertico, BS, Corfu,
;; Tabulated List, and Solitaire integrations.  This file has no dependency on
;; those packages, so personal schemes can validate at startup before any
;; integration is loaded.

;;; Code:

(require 'emacsvox-aural)
(require 'emacsvox-aural-schemes)

(defconst emacsvox-aural-workflow-semantics
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
     :phases (before content after))
    (field-kind
     :kind attribute
     :summary "The module-defined purpose of a structured field"
     :owner core
     :roles (field)
     :value-type symbol)
    (empty
     :kind state
     :summary "A structured field contains no text"
     :owner core
     :roles (field)
     :occasions (navigation continuous inspection)
     :phases (before content after))
    (aural-interface
     :kind role
     :summary "An Emacsvox aural manager, browser, or editor"
     :owner core
     :occasions (navigation state-change inspection)
     :phases (before content after))
    (aural-interface-opened
     :kind event
     :summary "An Emacsvox aural interface was displayed"
     :owner core
     :occasions (state-change)
     :phases (before content after))
    (aural-interface-closed
     :kind event
     :summary "An Emacsvox aural interface was dismissed"
     :owner core
     :occasions (state-change)
     :phases (before content after))
    (buffer-entry
     :kind role
     :summary "A buffer represented in a buffer list or selector"
     :owner core
     :occasions (navigation state-change inspection)
     :phases (before content after))
    (modified
     :kind state
     :summary "A buffer has unsaved modifications"
     :owner core
     :roles (buffer-entry)
     :occasions (navigation state-change inspection)
     :phases (before content after))
    (read-only
     :kind state
     :summary "A buffer does not permit ordinary editing"
     :owner core
     :roles (buffer-entry)
     :occasions (navigation state-change inspection)
     :phases (before content after))
    (unread
     :kind state
     :summary "An item has not yet been read"
     :owner core
     :occasions (navigation continuous state-change inspection notification)
     :phases (before content after))
    (flagged
     :kind state
     :summary "An item has been explicitly flagged for attention"
     :owner core
     :occasions (navigation continuous state-change inspection notification)
     :phases (before content after))
    (forwarded
     :kind state
     :summary "A mail message has been forwarded"
     :owner mail
     :occasions (navigation continuous state-change inspection)
     :phases (before content after))
    (has-attachments
     :kind state
     :summary "A message contains one or more attachments"
     :owner core
     :occasions (navigation continuous state-change inspection)
     :phases (before content after))
    (replied
     :kind state
     :summary "A mail message has been replied to"
     :owner mail
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
     :occasions (navigation edit state-change inspection)
     :phases (before content after))
    (filesystem-listing
     :kind role
     :summary "A directory or search-result listing of filesystem entries"
     :owner dired
     :occasions (navigation state-change inspection)
     :phases (before content after))
    (filesystem-operation
     :kind role
     :summary "The result of a filesystem operation requested from Dired"
     :owner dired
     :occasions (state-change notification)
     :phases (before content after))
    (filesystem-listing-closed
     :kind event
     :summary "A filesystem listing was dismissed"
     :owner dired
     :occasions (state-change)
     :phases (before content after))
    (filesystem-listing-opened
     :kind event
     :summary "A filesystem listing was opened or selected"
     :owner dired
     :occasions (navigation state-change)
     :phases (before content after))
    (confirmation-request
     :kind role
     :summary "A prompt asking the user to confirm an action"
     :owner core
     :occasions (notification)
     :phases (before content after))
    (game-cell
     :kind role
     :summary "One position on a game board"
     :owner core
     :occasions (navigation continuous state-change inspection)
     :phases (before content after))
    (game-cell-kind
     :kind attribute
     :summary "The module-defined contents of a game-board cell"
     :owner core
     :roles (game-cell)
     :value-type symbol)
    (entry-kind
     :kind attribute
     :summary "The filesystem kind of a directory entry"
     :owner dired
     :roles (filesystem-entry)
     :value-type symbol
     :allowed-values (file directory symbolic-link other))
    (filesystem-operation-kind
     :kind attribute
     :summary "The filesystem operation whose result is being presented"
     :owner dired
     :roles (filesystem-operation)
     :value-type symbol)
    (filesystem-listing-aspect
     :kind attribute
     :summary "The part of a filesystem listing whose visibility changed"
     :owner dired
     :roles (filesystem-listing)
     :value-type symbol
     :allowed-values (details subdirectory all-subdirectories))
    (filesystem-edit-kind
     :kind attribute
     :summary "The pending Wdired edit made to a filesystem entry"
     :owner dired
     :roles (filesystem-entry)
     :value-type symbol
     :allowed-values
     (filename-upcase filename-capitalize filename-downcase
                      permission-set permission-toggled))
    (entry-inspection-kind
     :kind attribute
     :summary "The requested property of a filesystem entry"
     :owner dired
     :value-type symbol
     :allowed-values
     (size modification-time access-time symbolic-link-target permissions
           file-type header duration marked-summary package))
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
    (vcs-rebase-entry
     :kind role
     :summary "One editable instruction in an interactive version-control rebase"
     :owner magit
     :occasions (navigation state-change inspection)
     :phases (before content after))
    (vcs-commit-message
     :kind role
     :summary "A version-control commit message being edited"
     :owner magit
     :occasions (navigation edit state-change inspection)
     :phases (before content after))
    (vcs-repository
     :kind role
     :summary "One repository in a version-control repository list"
     :owner magit
     :occasions (navigation state-change notification)
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
     :allowed-values
     (status log blob blame diff commit process repositories rebase refs other))
    (vcs-operation
     :kind attribute
     :summary "The version-control operation being performed"
     :owner magit
     :roles
     (vcs-section vcs-view vcs-blame-chunk vcs-process vcs-rebase-entry
                  vcs-commit-message vcs-repository)
     :value-type symbol)
    (vcs-rebase-action
     :kind attribute
     :summary "The action assigned to an interactive rebase entry"
     :owner magit
     :roles (vcs-rebase-entry)
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
    (operation-started
     :kind event
     :summary "A requested module operation started and may still be running"
     :owner core
     :occasions (state-change notification)
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
     :occasions (navigation continuous edit state-change inspection)
     :phases (before content after))
    (code-operation
     :kind role
     :summary "An operation requested from a programming-language interface"
     :owner core
     :occasions (edit state-change notification)
     :phases (before content after))
    (syntax-role
     :kind attribute
     :summary "The language-defined structural role of source code"
     :owner core
     :value-type symbol)
    (code-edit-kind
     :kind attribute
     :summary "The editing operation applied to source code"
     :owner core
     :roles (code-construct)
     :value-type symbol)
    (code-navigation-kind
     :kind attribute
     :summary "The language integration's kind of source navigation"
     :owner core
     :roles (code-construct)
     :value-type symbol)
    (code-operation-kind
     :kind attribute
     :summary "The programming operation being presented"
     :owner core
     :roles (code-operation)
     :value-type symbol)
    (code-selection-created
     :kind event
     :summary "A source-code construct was selected"
     :owner core
     :roles (code-construct)
     :occasions (state-change)
     :phases (before content after))
    (boundary-entered
     :kind event
     :summary "Navigation arrived at a source-code boundary"
     :owner core
     :occasions (navigation)
     :phases (before content after))
    (notebook
     :kind role
     :summary "An interactive computational notebook"
     :owner ein
     :occasions (navigation state-change inspection notification)
     :phases (before content after))
    (notebook-cell
     :kind role
     :summary "One executable, rendered, or uninterpreted notebook cell"
     :owner ein
     :occasions (navigation continuous edit state-change inspection)
     :phases (before content after))
    (notebook-cell-kind
     :kind attribute
     :summary "The content type of a notebook cell"
     :owner ein
     :roles (notebook-cell)
     :value-type symbol)
    (notebook-cell-action
     :kind attribute
     :summary "The structural operation applied to a notebook cell"
     :owner ein
     :roles (notebook-cell)
     :value-type symbol)
    (notebook-action
     :kind attribute
     :summary "The lifecycle operation applied to a notebook"
     :owner ein
     :roles (notebook)
     :value-type symbol)
    (candidate
     :kind role
     :summary "One available completion candidate"
     :owner core
     :occasions (navigation state-change)
     :phases (before content after))
    (command-menu
     :kind role
     :summary "An interactive menu of commands and configurable values"
     :owner core
     :occasions (navigation state-change inspection)
     :phases (before content after))
    (command-menu-item
     :kind role
     :summary "A command, value, or section within an interactive command menu"
     :owner core
     :occasions (navigation state-change inspection)
     :phases (before content after))
    (command-menu-item-kind
     :kind attribute
     :summary "The structural kind of an interactive command-menu item"
     :owner core
     :roles (command-menu-item)
     :value-type symbol
     :allowed-values (command value section history other))
    (command-menu-action
     :kind attribute
     :summary "The command-menu operation being presented"
     :owner core
     :roles (command-menu command-menu-item)
     :value-type symbol)
    (command-menu-opened
     :kind event
     :summary "An interactive command menu was displayed"
     :owner core
     :roles (command-menu)
     :occasions (navigation state-change)
     :phases (before content after))
    (command-menu-closed
     :kind event
     :summary "An interactive command menu was dismissed"
     :owner core
     :roles (command-menu)
     :occasions (state-change)
     :phases (before content after))
    (command-menu-suspended
     :kind event
     :summary "An interactive command menu was suspended for later resumption"
     :owner core
     :roles (command-menu)
     :occasions (state-change)
     :phases (before content after))
    (command-menu-resumed
     :kind event
     :summary "A suspended interactive command menu was resumed"
     :owner core
     :roles (command-menu)
     :occasions (state-change)
     :phases (before content after))
    (command-menu-value-changed
     :kind event
     :summary "A command-menu value or presentation setting changed"
     :owner core
     :roles (command-menu command-menu-item)
     :occasions (state-change)
     :phases (before content after))
    (command-interaction
     :kind role
     :summary "An interactive shell or command-interpreter session"
     :owner core
     :occasions
     (navigation continuous state-change edit inspection notification)
     :phases (before content after))
    (command-input
     :kind role
     :summary "Input entered into an interactive command session"
     :owner core
     :occasions (navigation state-change edit inspection)
     :phases (before content after))
    (command-output
     :kind role
     :summary "Process output from an interactive command session"
     :owner core
     :occasions (navigation continuous inspection notification)
     :phases (before content after))
    (command-prompt
     :kind role
     :summary "A command session prompt ready to receive input"
     :owner core
     :occasions (navigation continuous notification)
     :phases (before content after))
    (command-interaction-kind
     :kind attribute
     :summary "The kind of interactive command session"
     :owner core
     :roles (command-interaction command-input command-output command-prompt)
     :value-type symbol
     :allowed-values (shell repl))
    (command-operation
     :kind attribute
     :summary "The command-session operation being presented"
     :owner core
     :roles (command-interaction command-input command-output command-prompt)
     :value-type symbol
     :allowed-values
     (submit delete-output clear-buffer kill-input send-eof signal
             completion history-navigation command-navigation
             output-navigation prompt-navigation input-boundary copy-input
             accumulate insert-argument setting process-exit))
    (command-exit-status
     :kind attribute
     :summary "Numeric exit status of a completed command process"
     :owner core
     :roles (command-interaction)
     :value-type integer)
    (command-input-origin
     :kind attribute
     :summary "Where presented command input came from"
     :owner core
     :roles (command-input)
     :value-type symbol
     :allowed-values
     (current history copied completion accumulated previous-argument))
    (command-submitted
     :kind event
     :summary "Input was submitted to an interactive command process"
     :owner core
     :roles (command-input)
     :occasions (state-change)
     :phases (before content after))
    (command-output-received
     :kind event
     :summary "Logical process output became ready for presentation"
     :owner core
     :roles (command-output)
     :occasions (continuous notification)
     :phases (before content after))
    (command-prompt-ready
     :kind event
     :summary "An interactive command process became ready for input"
     :owner core
     :roles (command-prompt)
     :occasions (continuous notification)
     :phases (before content after))
    (command-process-signalled
     :kind event
     :summary "The user sent EOF or another signal to a command process"
     :owner core
     :roles (command-interaction)
     :occasions (state-change notification)
     :phases (before content after))
    (command-process-exited
     :kind event
     :summary "An interactive command process exited or disconnected"
     :owner core
     :roles (command-interaction)
     :occasions (notification)
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
    (completion-input-updated
     :kind event
     :summary "Completion input was updated without accepting it"
     :owner core
     :roles (candidate)
     :occasions (edit state-change)
     :phases (before content after))
    (completion-session-closed
     :kind event
     :summary "An interactive completion session was dismissed"
     :owner core
     :roles (candidate)
     :occasions (state-change)
     :phases (before content after))
    (completion-separator-inserted
     :kind event
     :summary "A completion separator was inserted without accepting a candidate"
     :owner corfu
     :occasions (edit)
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

(defconst emacsvox-aural-workflow-module-fragments
  '((bs
     :schema-version 1
     :id bs-buffer-state-tones
     :summary "Compatibility tones for buffer state in BS"
     :rules
     ((:id bs-buffer-modified-tone
       :match
       (:role buffer-entry :module bs :state modified
        :occasion navigation)
       :render
       (:before
        (:append
         ((:id bs-buffer-modified-tone-action
           :kind tone :tone buffer-modified)))))
      (:id bs-buffer-read-only-tone
       :match
       (:role buffer-entry :module bs :state read-only
        :occasion navigation)
       :render
       (:before
        (:append
         ((:id bs-buffer-read-only-tone-action
           :kind tone :tone buffer-read-only)))))))
    (corfu
     :schema-version 1
     :id corfu-completion-edit-tones
     :summary "Compatibility tone for Corfu completion edits"
     :rules
     ((:id corfu-separator-inserted-tone
       :match
       (:module corfu :event completion-separator-inserted
        :occasion edit)
       :render
       (:before
        (:append
         ((:id corfu-separator-inserted-tone-action
           :kind tone :tone completion-separator)))))))
    (python
     :schema-version 1
     :id python-interaction-feedback
     :summary "Present Python navigation, editing, and operation outcomes"
     :rules
     ((:id python-navigation-boundary-cue
       :match
       (:role code-construct :module python :event boundary-entered
        :occasion navigation)
       :render
       (:after
        ((:id python-navigation-boundary-cue-action
          :kind cue :cue paragraph))))
      (:id python-dedent-line-cue
       :match
       (:role code-construct :module python :event object-changed
        :code-edit-kind dedent-line :occasion edit)
       :render
       (:after
        ((:id python-dedent-line-cue-action :kind cue :cue left))))
      (:id python-shift-left-cue
       :match
       (:role code-construct :module python :event object-changed
        :code-edit-kind shift-left :occasion edit)
       :render
       (:before
        ((:id python-shift-left-cue-action :kind cue :cue left))))
      (:id python-shift-right-cue
       :match
       (:role code-construct :module python :event object-changed
        :code-edit-kind shift-right :occasion edit)
       :render
       (:before
        ((:id python-shift-right-cue-action :kind cue :cue right))))
      (:id python-indent-region-cue
       :match
       (:role code-construct :module python :event object-changed
        :code-edit-kind indent-region :occasion edit)
       :render
       (:before
        ((:id python-indent-region-cue-action :kind cue :cue right))))
      (:id python-fill-paragraph-cue
       :match
       (:role code-construct :module python :event object-changed
        :code-edit-kind fill-paragraph :occasion edit)
       :render
       (:before
        ((:id python-fill-paragraph-cue-action
          :kind cue :cue fill-object))))
      (:id python-elpy-navigation-cue
       :match
       (:role code-construct :module python :event focus-entered
        :code-navigation-kind elpy :occasion navigation)
       :render
       (:before
        ((:id python-elpy-navigation-cue-action
          :kind cue :cue large-movement))))
      (:id python-elpy-structural-edit-cue
       :match
       (:role code-construct :module python :event object-changed
        :code-edit-kind elpy-structural :occasion edit)
       :render
       (:before
        ((:id python-elpy-structural-edit-cue-action
          :kind cue :cue large-movement))))
      (:id python-code-selection-cue
       :match
       (:role code-construct :module python :event code-selection-created
        :occasion state-change)
       :render
       (:before
        ((:id python-code-selection-cue-action
          :kind cue :cue mark-object))))
      (:id python-operation-started-cue
       :match
       (:role code-operation :module python :event operation-started
        :occasion state-change)
       :render
       (:before
        ((:id python-operation-started-cue-action
          :kind cue :cue progress))))
      (:id python-operation-completed-cue
       :match
       (:role code-operation :module python :event operation-completed
        :occasion state-change)
       :render
       (:before
        ((:id python-operation-completed-cue-action
          :kind cue :cue task-done))))
      (:id python-operation-failed-cue
       :match
       (:role code-operation :module python :event operation-failed
        :occasion state-change)
       :render
       (:before
        ((:id python-operation-failed-cue-action
          :kind cue :cue warn-user))))))
    (ein
     :schema-version 1
     :id ein-notebook-feedback
     :summary "Present notebook cell identity, structure, and lifecycle"
     :rules
     ((:id ein-code-cell-tone
       :match
       (:role notebook-cell :module ein :notebook-cell-kind code)
       :render
       (:before
        ((:id ein-code-cell-tone-action
          :kind tone :tone notebook-cell-code))))
      (:id ein-markdown-cell-tone
       :match
       (:role notebook-cell :module ein :notebook-cell-kind markdown)
       :render
       (:before
        ((:id ein-markdown-cell-tone-action
          :kind tone :tone notebook-cell-markdown))))
      (:id ein-raw-cell-tone
       :match
       (:role notebook-cell :module ein :notebook-cell-kind raw)
       :render
       (:before
        ((:id ein-raw-cell-tone-action
          :kind tone :tone notebook-cell-raw))))
      (:id ein-cell-navigation-cue
       :match
       (:role notebook-cell :module ein :event focus-entered
        :occasion navigation)
       :render
       (:before
        ((:id ein-cell-navigation-cue-action
          :kind cue :cue large-movement))))
      (:id ein-notebook-navigation-cue
       :match
       (:role notebook :module ein :event focus-entered
        :occasion navigation)
       :render
       (:before
        ((:id ein-notebook-navigation-cue-action
          :kind cue :cue large-movement))))
      (:id ein-cell-removed-cue
       :match
       (:role notebook-cell :module ein :event object-changed
        :notebook-cell-action removed :occasion state-change)
       :render
       (:before
        ((:id ein-cell-removed-cue-action
          :kind cue :cue delete-object))))
      (:id ein-cell-inserted-cue
       :match
       (:role notebook-cell :module ein :event object-changed
        :notebook-cell-action inserted :occasion edit)
       :render
       (:before
        ((:id ein-cell-inserted-cue-action
          :kind cue :cue yank-object))))
      (:id ein-cell-yanked-cue
       :match
       (:role notebook-cell :module ein :event object-changed
        :notebook-cell-action yanked :occasion edit)
       :render
       (:before
        ((:id ein-cell-yanked-cue-action
          :kind cue :cue yank-object))))
      (:id ein-cell-split-cue
       :match
       (:role notebook-cell :module ein :event object-changed
        :notebook-cell-action split :occasion edit)
       :render
       (:before
        ((:id ein-cell-split-cue-action
          :kind cue :cue open-object))))
      (:id ein-cell-merged-cue
       :match
       (:role notebook-cell :module ein :event object-changed
        :notebook-cell-action merged :occasion edit)
       :render
       (:before
        ((:id ein-cell-merged-cue-action
          :kind cue :cue close-object))))
      (:id ein-cell-moved-cue
       :match
       (:role notebook-cell :module ein :event object-changed
        :notebook-cell-action moved :occasion state-change)
       :render
       (:before
        ((:id ein-cell-moved-cue-action
          :kind cue :cue large-movement))))
      (:id ein-output-hidden-cue
       :match
       (:role notebook-cell :module ein :event visibility-changed
        :visibility folded :occasion state-change)
       :render
       (:before
        ((:id ein-output-hidden-cue-action
          :kind cue :cue close-object))))
      (:id ein-output-shown-cue
       :match
       (:role notebook-cell :module ein :event visibility-changed
        :visibility expanded :occasion state-change)
       :render
       (:before
        ((:id ein-output-shown-cue-action
          :kind cue :cue open-object))))
      (:id ein-operation-started-cue
       :match
       (:role code-operation :module ein :event operation-started
        :occasion state-change)
       :render
       (:before
        ((:id ein-operation-started-cue-action
          :kind cue :cue progress))))
      (:id ein-notebook-opened-cue
       :match
       (:role notebook :module ein :event object-changed
        :notebook-action opened :occasion state-change)
       :render
       (:before
        ((:id ein-notebook-opened-cue-action
          :kind cue :cue open-object))))
      (:id ein-notebook-closed-cue
       :match
       (:role notebook :module ein :event object-changed
        :notebook-action closed :occasion state-change)
       :render
       (:before
        ((:id ein-notebook-closed-cue-action
          :kind cue :cue close-object))))))
    (agent-shell
     :schema-version 1
     :id agent-shell-tool-status-cues
     :summary "Default cues for Agent Shell tool lifecycle updates"
     :rules
     ((:id agent-shell-tool-pending-cue
       :match
       (:role agent-tool :module agent-shell
        :event agent-tool-status-changed
        :agent-tool-status pending :occasion notification)
       :render
       (:before
        (:append
         ((:id agent-shell-tool-pending-cue-action
           :kind cue :cue item)))))
      (:id agent-shell-tool-in-progress-cue
       :match
       (:role agent-tool :module agent-shell
        :event agent-tool-status-changed
        :agent-tool-status in-progress :occasion notification)
       :render
       (:before
        (:append
         ((:id agent-shell-tool-in-progress-cue-action
           :kind cue :cue progress)))))
      (:id agent-shell-tool-completed-cue
       :match
       (:role agent-tool :module agent-shell
        :event agent-tool-status-changed
        :agent-tool-status completed :occasion notification)
       :render
       (:before
        (:append
         ((:id agent-shell-tool-completed-cue-action
           :kind cue :cue task-done)))))
      (:id agent-shell-tool-failed-cue
       :match
       (:role agent-tool :module agent-shell
        :event agent-tool-status-changed
        :agent-tool-status failed :occasion notification)
       :render
       (:before
        (:append
         ((:id agent-shell-tool-failed-cue-action
           :kind cue :cue warn-user)))))))
    (solitaire
     :schema-version 1
     :id solitaire-cell-tones
     :summary "Compatibility tones for Solitaire board cells"
     :rules
     ((:id solitaire-stone-tone
       :match
       (:role game-cell :module solitaire :game-cell-kind stone
        :occasion inspection)
       :render
       (:before
        (:append
         ((:id solitaire-stone-tone-action
           :kind tone :tone solitaire-stone)))))
      (:id solitaire-hole-tone
       :match
       (:role game-cell :module solitaire :game-cell-kind hole
        :occasion inspection)
       :render
       (:before
        (:append
         ((:id solitaire-hole-tone-action
           :kind tone :tone solitaire-hole)))))))
    (tabulated-list
     :schema-version 1
     :id tabulated-list-field-state-tones
     :summary "Compatibility tone for empty Tabulated List fields"
     :rules
     ((:id tabulated-list-empty-field-tone
       :match
       (:role field :module tabulated-list :state empty
        :occasion navigation)
       :render
       (:before
        (:append
         ((:id tabulated-list-empty-field-tone-action
           :kind tone :tone field-empty))))))))
  "Automatic compatibility policy for shared workflow integrations.")

(defconst emacsvox-aural-workflow-feature-fragments
  '((:schema-version 1
     :id mail-message-status-cues
     :summary
     "Add semantic cues for unread, replied, forwarded, flagged, and attached messages"
     :rules
     ((:id workflow-mail-unread
       :match (:role message :state unread :occasion navigation)
       :render
       (:before
        (:append
         ((:id workflow-mail-unread-cue :kind cue :cue mail-unread)))))
      (:id workflow-mail-replied
       :match (:role message :state replied :occasion navigation)
       :render
       (:before
        (:append
         ((:id workflow-mail-replied-cue :kind cue :cue mail-replied)))))
      (:id workflow-mail-forwarded
       :match (:role message :state forwarded :occasion navigation)
       :render
       (:before
        (:append
         ((:id workflow-mail-forwarded-cue :kind cue :cue mail-forwarded)))))
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
         ((:id workflow-mail-attachments-cue
           :kind cue :cue mail-has-attachment)))))))
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
           :kind cue :cue open-object)))))
      (:id workflow-magit-section-folded-replaces-compatibility
       :match
       (:role vcs-section :module magit :event visibility-changed
        :visibility folded :occasion state-change
        :legacy-cue close-object)
       :render
       (:before (:remove (legacy-cue))))
      (:id workflow-magit-section-expanded-replaces-compatibility
       :match
       (:role vcs-section :module magit :event visibility-changed
        :visibility expanded :occasion state-change
        :legacy-cue open-object)
       :render
       (:before (:remove (legacy-cue)))))))
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

(defun emacsvox-aural-register-workflow-provider ()
  "Register the shared cross-module workflow semantic vocabulary."
  (dolist (definition emacsvox-aural-workflow-semantics)
    (let ((id (car definition))
          (metadata (cdr definition)))
      (unless (emacsvox-aural-semantic id)
        (apply #'emacsvox-aural-register-semantic id metadata))))
  (emacsvox-aural-validate-registry)
  (dolist (definition emacsvox-aural-workflow-module-fragments)
    (let* ((module (car definition))
           (data (cdr definition))
           (id (plist-get data :id)))
      (unless (gethash id emacsvox-aural-module-fragment-registry)
        (emacsvox-aural-register-module-fragment
         module data :source "emacsvox-aural-provider-workflows"))))
  (dolist (data emacsvox-aural-workflow-feature-fragments)
    (unless (emacsvox-aural-feature-fragment-entry (plist-get data :id))
      (emacsvox-aural-register-feature-fragment
       data :built-in t :source "emacsvox-aural-provider-workflows"
       :collection
       (pcase (plist-get data :id)
         ('mail-message-status-cues 'mail)
         ('dired-entry-state-labels 'dired)
         ('magit-section-visibility-cues 'magit)
         (_ 'general)))))
  (dolist (data emacsvox-aural-agent-shell-feature-fragments)
    (unless (emacsvox-aural-feature-fragment-entry (plist-get data :id))
      (emacsvox-aural-register-feature-fragment
       data :built-in t :source "emacsvox-aural-provider-workflows"
       :collection 'agent-shell))))

(emacsvox-aural-register-workflow-provider)

(provide 'emacsvox-aural-provider-workflows)
;;; emacsvox-aural-provider-workflows.el ends here
