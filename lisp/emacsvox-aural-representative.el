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

(defun emacsvox-aural-register-representative-semantics ()
  "Register the representative cross-module semantic vocabulary."
  (dolist (definition emacsvox-aural-representative-semantics)
    (let ((id (car definition))
          (metadata (cdr definition)))
      (unless (emacsvox-aural-semantic id)
        (apply #'emacsvox-aural-register-semantic id metadata))))
  (emacsvox-aural-validate-registry))

(emacsvox-aural-register-representative-semantics)

(provide 'emacsvox-aural-representative)
;;; emacsvox-aural-representative.el ends here
